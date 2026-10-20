import hashlib
import json
import secrets
import threading
import time
from collections import defaultdict
from uuid import uuid4

from sqlalchemy import delete, func, insert, select, update
from sqlalchemy.exc import SQLAlchemyError

from .domain.chess import Board, other
from .domain.game import Game, RuleError, identifier, project_event, require
from .storage import accounts, events, invites, matches, receipts, rooms, sessions


def hashed(value):
    return hashlib.sha256(value.encode()).hexdigest()


TUTORIALS = {
    "movement": {
        "title": "Primeiro movimento",
        "text": "Selecione o peão de e2 e avance para e4. A resposta prevista é e7-e5.",
        "fen": None,
        "cards": [],
        "replies": ["e7e5", "g8f6", "b8c6", "f8c5"],
    },
    "shield": {
        "title": "Escudo e ruptura",
        "text": "Conjure Escudo Arcano na torre de a1 antes de mover. Selecione a carta e depois a peça.",
        "fen": "4k3/8/8/8/8/8/7P/R3K3 w Q - 0 1",
        "cards": ["arcane_shield", "shield_break", "dispel"],
        "replies": ["e8e7", "e7e6", "e6e5"],
    },
    "trap": {
        "title": "Armadilha oculta",
        "text": "Coloque Selo de Raízes em f6 e faça um lance. O cavalo inimigo seguirá para f6. Use o catálogo para conhecer as outras cartas.",
        "fen": "4k1n1/8/8/8/8/8/PP6/4K3 w - - 0 1",
        "cards": ["hidden_snare", "oracle_eye", "ward"],
        "replies": ["g8f6", "e8e7", "e7e6"],
    },
}


class Service:
    def __init__(self, engine, now=time.monotonic):
        self.engine, self.now = engine, now
        self.locks = defaultdict(threading.RLock)
        self.stamps = {}
        self.accepting_matches = True
        self.metrics = {"accepted": 0, "rejected": 0, "timeouts": 0}

    def issue_invite(self, days=7):
        code = secrets.token_urlsafe(24)
        with self.engine.begin() as db:
            db.execute(insert(invites).values(hash=hashed(code), expires=time.time() + days * 86400))
        return code

    def _tokens(self, db, account_id):
        access, refresh = secrets.token_urlsafe(32), secrets.token_urlsafe(32)
        for token, kind, duration in ((access, "access", 1800), (refresh, "refresh", 604800)):
            db.execute(
                insert(sessions).values(
                    hash=hashed(token), account_id=account_id, kind=kind, expires=time.time() + duration
                )
            )
        return {
            "access_token": access,
            "refresh_token": refresh,
            "expires_in": 1800,
            "account_id": account_id,
        }

    def redeem(self, code, nickname):
        with self.engine.begin() as db:
            invite = (
                db.execute(select(invites).where(invites.c.hash == hashed(code)).with_for_update())
                .mappings()
                .first()
            )
            require(invite and invite["expires"] > time.time() and not invite["used_by"], "INVALID_INVITE")
            account_id = str(uuid4())
            db.execute(insert(accounts).values(id=account_id, nickname=nickname))
            db.execute(update(invites).where(invites.c.hash == invite["hash"]).values(used_by=account_id))
            return self._tokens(db, account_id)

    def refresh(self, token):
        with self.engine.begin() as db:
            row = (
                db.execute(select(sessions).where(sessions.c.hash == hashed(token)).with_for_update())
                .mappings()
                .first()
            )
            require(row and row["kind"] == "refresh" and row["expires"] > time.time(), "NOT_AUTHENTICATED")
            db.execute(delete(sessions).where(sessions.c.hash == row["hash"]))
            return self._tokens(db, row["account_id"])

    def authenticate(self, token):
        with self.engine.connect() as db:
            row = db.execute(select(sessions).where(sessions.c.hash == hashed(token))).mappings().first()
            require(row and row["kind"] == "access" and row["expires"] > time.time(), "NOT_AUTHENTICATED")
            return row["account_id"]

    def create_room(self, account_id):
        require(self.accepting_matches, "SERVER_MAINTENANCE")
        code = secrets.token_urlsafe(12)
        with self.engine.begin() as db:
            db.execute(delete(rooms).where(rooms.c.owner == account_id, rooms.c.match_id.is_(None)))
            db.execute(insert(rooms).values(code=code, owner=account_id, expires=time.time() + 3600))
        return {"code": code, "match_id": None}

    def room(self, account_id, code):
        with self.engine.connect() as db:
            room = db.execute(select(rooms).where(rooms.c.code == code)).mappings().first()
            require(room, "ROOM_NOT_FOUND")
            if room["owner"] != account_id:
                self._match(db, account_id, room["match_id"])
            return {"code": code, "match_id": room["match_id"]}

    def _create_match(self, db, white, black, game):
        match_id = str(uuid4())
        db.execute(
            insert(matches).values(
                id=match_id,
                white=white,
                black=black,
                version=game.version,
                status=game.status,
                snapshot=game.dump(),
                created_at=time.time(),
            )
        )
        self.stamps[match_id] = self.now()
        return match_id

    def join_room(self, account_id, code):
        require(self.accepting_matches, "SERVER_MAINTENANCE")
        with self.locks["room:" + code], self.engine.begin() as db:
            room = db.execute(select(rooms).where(rooms.c.code == code).with_for_update()).mappings().first()
            require(room and room["expires"] > time.time(), "ROOM_NOT_FOUND")
            if room["match_id"]:
                self._match(db, account_id, room["match_id"])
                return {"match_id": room["match_id"]}
            require(room["owner"] != account_id, "CANNOT_JOIN_OWN_ROOM")
            match_id = self._create_match(db, room["owner"], account_id, Game.new())
            db.execute(update(rooms).where(rooms.c.code == code).values(match_id=match_id))
            return {"match_id": match_id}

    def tutorial(self, account_id, scenario):
        require(self.accepting_matches, "SERVER_MAINTENANCE")
        require(scenario in TUTORIALS, "INVALID_SCENARIO")
        setup = TUTORIALS[scenario]
        game = Game.new()
        game.tutorial = scenario
        if setup["fen"]:
            game.board = Board.from_fen(setup["fen"])
        game.players["white"].hand = [
            {"instance_id": identifier(), "definition_id": c} for c in setup["cards"]
        ]
        # Scripted lessons use a curated hand, not a shuffled competitive deck.
        game.players["white"].deck = []
        game.players["white"].mana = 5
        with self.engine.begin() as db:
            if not db.execute(select(accounts).where(accounts.c.id == "tutorial")).first():
                db.execute(insert(accounts).values(id="tutorial", nickname="Tutorial"))
            match_id = self._create_match(db, account_id, "tutorial", game)
        return {"match_id": match_id, **{k: setup[k] for k in ("title", "text")}}

    def _match(self, db, account_id, match_id, lock=False):
        query = select(matches).where(matches.c.id == match_id)
        row = db.execute(query.with_for_update() if lock else query).mappings().first()
        require(row and account_id in (row["white"], row["black"]), "NOT_PARTICIPANT")
        return row, "white" if row["white"] == account_id else "black"

    def _charge(self, match_id, game, now):
        if game.status == "active":
            side = game.board.turn
            game.clocks[side] -= max(0, now - self.stamps.get(match_id, now)) * 1000
            if game.clocks[side] <= 0:
                game.clocks[side] = 0
                game.finish("timeout", other(side))

    def view(self, account_id, match_id):
        with self.locks[match_id], self.engine.connect() as db:
            row, side = self._match(db, account_id, match_id)
            game = Game.load(row["snapshot"])
            # Read projections never invent an uncommitted final result.
            if game.status == "active":
                active = game.board.turn
                game.clocks[active] = max(
                    0, game.clocks[active] - (self.now() - self.stamps.get(match_id, self.now())) * 1000
                )
            return {"type": "match.snapshot", "match_id": match_id, **game.project(side)}

    def _save(self, db, match_id, game, additions):
        db.execute(
            update(matches)
            .where(matches.c.id == match_id)
            .values(version=game.version, status=game.status, snapshot=game.dump())
        )
        seq = db.execute(select(func.max(events.c.seq)).where(events.c.match_id == match_id)).scalar() or 0
        if game.status != "active":
            additions.append({"type": "match.finished", "reason": game.reason, "winner": game.winner})
        for offset, event in enumerate(additions, 1):
            db.execute(
                insert(events).values(
                    match_id=match_id,
                    seq=seq + offset,
                    version=game.version,
                    payload=event,
                    created_at=time.time(),
                )
            )

    def command(self, account_id, match_id, command):
        with self.locks[match_id]:
            previous_stamp = self.stamps.get(match_id)
            previous_metrics = self.metrics.copy()
            try:
                return self._command_transaction(account_id, match_id, command)
            except SQLAlchemyError:
                if previous_stamp is not None:
                    self.stamps[match_id] = previous_stamp
                self.metrics = previous_metrics
                raise

    def _command_transaction(self, account_id, match_id, command):
        digest = hashed(json.dumps(command, sort_keys=True, separators=(",", ":")))
        with self.locks[match_id], self.engine.begin() as db:
            row, side = self._match(db, account_id, match_id, lock=True)
            request_id = command["request_id"]
            keys = (
                receipts.c.match_id == match_id,
                receipts.c.actor == account_id,
                receipts.c.request_id == request_id,
            )
            receipt = db.execute(select(receipts).where(*keys)).mappings().first()
            if receipt:
                require(receipt["digest"] == digest, "REQUEST_ID_REUSED")
                return receipt["response"]
            game = Game.load(row["snapshot"])
            now = self.now()
            self._charge(match_id, game, now)
            timed_out = row["status"] == "active" and game.status != "active"
            if timed_out:
                game.version += 1
                self._save(db, match_id, game, [])
                self.stamps[match_id] = now
            try:
                require(game.status == "active", "GAME_FINISHED")
                require(command["expected_version"] == game.version, "STALE_VERSION")
                additions = game.command(side, command["type"], command["payload"])
                if game.tutorial and game.status == "active" and game.board.turn == "black":
                    index = game.players["black"].own_turn_count - 1
                    replies = TUTORIALS[game.tutorial]["replies"]
                    reply = replies[index] if index < len(replies) else None
                    if reply and reply in {m.uci() for m in game.moves()}:
                        additions += game.move("black", reply)
                    else:
                        game.finish("tutorial_complete")
                game.version += 1
                self._save(db, match_id, game, additions)
                response = {
                    "type": "command.accepted",
                    "request_id": request_id,
                    "state_version": game.version,
                }
                self.stamps[match_id] = now
                self.metrics["accepted"] += 1
            except RuleError as exc:
                response = {
                    "type": "command.rejected",
                    "request_id": request_id,
                    "state_version": row["version"] + int(timed_out),
                    "code": str(exc),
                }
                self.metrics["rejected"] += 1
            db.execute(
                insert(receipts).values(
                    match_id=match_id,
                    actor=account_id,
                    request_id=request_id,
                    digest=digest,
                    response=response,
                )
            )
            return response

    def history(self, account_id, match_id):
        with self.engine.connect() as db:
            _, side = self._match(db, account_id, match_id)
            return [
                {"seq": r.seq, "state_version": r.version, **project_event(r.payload, side)}
                for r in db.execute(
                    select(events).where(events.c.match_id == match_id).order_by(events.c.seq)
                )
            ]

    def mine(self, account_id):
        with self.engine.connect() as db:
            query = (
                select(matches.c.id, matches.c.status, matches.c.created_at)
                .where((matches.c.white == account_id) | (matches.c.black == account_id))
                .order_by(matches.c.created_at.desc())
                .limit(50)
            )
            return [dict(row) for row in db.execute(query).mappings()]

    def expire(self):
        changed = []
        with self.engine.connect() as db:
            active = db.execute(select(matches.c.id).where(matches.c.status == "active")).scalars().all()
        for match_id in active:
            with self.locks[match_id], self.engine.begin() as db:
                row = (
                    db.execute(select(matches).where(matches.c.id == match_id).with_for_update())
                    .mappings()
                    .one()
                )
                game = Game.load(row["snapshot"])
                self._charge(match_id, game, self.now())
                if row["status"] == "active" and game.status != "active":
                    game.version += 1
                    self._save(db, match_id, game, [])
                    self.metrics["timeouts"] += 1
                    changed.append(match_id)
        return changed

    def void_after_restart(self):
        # Must run once before accepting traffic; deployment is single-worker.
        with self.engine.begin() as db:
            for row in (
                db.execute(select(matches).where(matches.c.status == "active").with_for_update())
                .mappings()
                .all()
            ):
                game = Game.load(row["snapshot"])
                game.finish("server_failure")
                game.version += 1
                self._save(db, row["id"], game, [])
