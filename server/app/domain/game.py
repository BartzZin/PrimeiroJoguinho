"""Serializable magic_rules_v1 state; effects resolve without I/O or clocks."""

import secrets
from copy import deepcopy
from dataclasses import asdict, dataclass, field

from .chess import Board, Move, Piece, algebraic, other, square

RULESET = "magic_rules_v1"
CARDS = {
    "arcane_shield": ("Escudo Arcano", 2, "Impede capturas até o fim do próximo turno adversário."),
    "hidden_snare": ("Selo de Raízes", 2, "Armadilha oculta: imobiliza no próximo turno da peça."),
    "frost_bind": ("Prisão de Gelo", 3, "Imobiliza uma peça inimiga no próximo turno dela."),
    "dispel": ("Dissipação", 1, "Remove um escudo ou imobilização públicos."),
    "shield_break": ("Ruptura", 1, "Remove um escudo inimigo."),
    "oracle_eye": ("Olho do Oráculo", 2, "Revela armadilhas inimigas em 3 × 3 durante este turno."),
    "silence_seal": ("Selo de Silêncio", 3, "Impede magia no próximo turno adversário."),
    "arcane_focus": ("Concentração", 0, "Restaura até 2 de mana; consome a carta do turno."),
    "ward": ("Proteção Rúnica", 1, "Anula a próxima imobilização até o fim do próximo turno adversário."),
    "trap_disarm": ("Desarmar", 1, "Remove uma armadilha inimiga na casa, se houver."),
    "temporal_boost": ("Fôlego Temporal", 2, "+15 segundos; um uso por partida."),
    "arcane_draw": ("Intuição", 2, "Compra até 2 cartas, respeitando mão máxima de 5."),
}


class RuleError(ValueError):
    pass


def require(condition, code):
    if not condition:
        raise RuleError(code)


def identifier():
    return secrets.token_hex(12)


@dataclass
class PlayerState:
    mana: int = 1
    deck: list = field(default_factory=list)
    hand: list = field(default_factory=list)
    discard: list = field(default_factory=list)
    own_turn_count: int = 0
    used_spell: bool = False
    used_boost: bool = False
    revealed: list = field(default_factory=list)


@dataclass
class Game:
    board: Board
    players: dict[str, PlayerState]
    effects: list = field(default_factory=list)
    traps: list = field(default_factory=list)
    clocks: dict = field(default_factory=lambda: {"white": 600000.0, "black": 600000.0})
    status: str = "active"
    reason: str | None = None
    winner: str | None = None
    version: int = 0
    draw_offer: str | None = None
    tutorial: str | None = None
    ruleset_version: str = RULESET

    @classmethod
    def new(cls):
        players = {}
        for side in ("white", "black"):
            deck = [{"instance_id": identifier(), "definition_id": name} for name in CARDS for _ in range(2)]
            secrets.SystemRandom().shuffle(deck)
            players[side] = PlayerState(deck=deck[3:], hand=deck[:3])
        game = cls(Board.from_fen(), players)
        game.start_turn()
        return game

    def dump(self):
        return {
            "board": {
                "fen": self.board.fen(),
                "ids": {algebraic(k): asdict(v) for k, v in self.board.pieces.items()},
            },
            "players": {k: asdict(v) for k, v in self.players.items()},
            **{
                k: deepcopy(getattr(self, k))
                for k in (
                    "effects",
                    "traps",
                    "clocks",
                    "status",
                    "reason",
                    "winner",
                    "version",
                    "draw_offer",
                    "tutorial",
                    "ruleset_version",
                )
            },
        }

    @classmethod
    def load(cls, data):
        board = Board.from_fen(data["board"]["fen"])
        board.pieces = {square(k): Piece(**v) for k, v in data["board"]["ids"].items()}
        return cls(
            board,
            {k: PlayerState(**v) for k, v in data["players"].items()},
            **{k: deepcopy(v) for k, v in data.items() if k not in ("board", "players")},
        )

    def start_turn(self):
        player = self.players[self.board.turn]
        player.own_turn_count += 1
        player.used_spell = False
        player.mana = min(5, player.mana + 1)
        if player.own_turn_count >= 2:
            self.draw(self.board.turn, 1)

    def draw(self, side, count):
        player = self.players[side]
        for _ in range(min(count, 5 - len(player.hand), len(player.deck))):
            player.hand.append(player.deck.pop(0))

    def affected(self, kind):
        return {e["piece_id"] for e in self.effects if e["kind"] == kind}

    def moves(self):
        return self.board.legal_moves(self.affected("frozen"), self.affected("shield"))

    def silenced(self, side):
        return any(e["kind"] == "silence" and e["side"] == side for e in self.effects)

    def add_effect(self, kind, side, piece_id=None, expiry_side=None, expiry_turn=None):
        expiry_side = expiry_side or side
        expiry_turn = expiry_turn or self.players[expiry_side].own_turn_count + 1
        existing = next(
            (
                e
                for e in self.effects
                if e["kind"] == kind and e.get("piece_id") == piece_id and e["side"] == side
            ),
            None,
        )
        if existing:
            existing["expiry_turn"] = max(existing["expiry_turn"], expiry_turn)
        else:
            self.effects.append(
                {
                    "id": identifier(),
                    "kind": kind,
                    "side": side,
                    "piece_id": piece_id,
                    "expiry_side": expiry_side,
                    "expiry_turn": expiry_turn,
                }
            )

    def freeze(self, piece):
        ward = next((e for e in self.effects if e["kind"] == "ward" and e["piece_id"] == piece.id), None)
        if ward:
            self.effects.remove(ward)
        else:
            self.add_effect("frozen", piece.side, piece.id)

    def targets(self, card, side):
        if card in ("arcane_focus", "arcane_draw", "silence_seal", "temporal_boost"):
            return [{}]
        if card in ("hidden_snare", "oracle_eye", "trap_disarm"):
            return [{"square": algebraic(pos)} for pos in range(64)]
        if card == "dispel":
            return [{"effect_id": e["id"]} for e in self.effects if e["kind"] in ("shield", "frozen")]
        return [
            {"piece_id": piece.id}
            for piece in self.board.pieces.values()
            if piece.kind != "k" and ((piece.side == side) == (card in ("arcane_shield", "ward")))
        ]

    def cast(self, side, instance_id, target):
        require(self.status == "active", "GAME_FINISHED")
        require(side == self.board.turn, "NOT_YOUR_TURN")
        player = self.players[side]
        require(not player.used_spell and not self.silenced(side), "INVALID_PHASE")
        instance = next((c for c in player.hand if c["instance_id"] == instance_id), None)
        require(instance is not None, "CARD_NOT_IN_HAND")
        card = instance["definition_id"]
        require(card in CARDS, "CARD_NOT_IN_HAND")
        cost = CARDS[card][1]
        require(player.mana >= cost, "INSUFFICIENT_MANA")
        require(target in self.targets(card, side), "INVALID_TARGET")
        enemy = other(side)
        piece = next((p for p in self.board.pieces.values() if p.id == target.get("piece_id")), None)
        info = {}
        if card in ("arcane_shield", "ward"):
            self.add_effect("shield" if card == "arcane_shield" else "ward", side, piece.id, enemy)
        elif card == "frost_bind":
            self.freeze(piece)
        elif card in ("dispel", "shield_break"):
            effect = next(
                (
                    e
                    for e in self.effects
                    if (card == "dispel" and e["id"] == target.get("effect_id"))
                    or (card == "shield_break" and e["kind"] == "shield" and e["piece_id"] == piece.id)
                ),
                None,
            )
            require(effect is not None, "INVALID_TARGET")
            self.effects.remove(effect)
        elif card == "hidden_snare":
            pos = square(target["square"])
            own_traps = [t for t in self.traps if t["owner"] == side]
            require(
                pos not in self.board.pieces
                and len(own_traps) < 2
                and not any(t["square"] == pos for t in own_traps),
                "INVALID_TARGET",
            )
            self.traps.append({"id": identifier(), "owner": side, "square": pos})
        elif card == "oracle_eye":
            pos = square(target["square"])
            player.revealed = [
                t["id"]
                for t in self.traps
                if t["owner"] == enemy
                and abs(t["square"] % 8 - pos % 8) <= 1
                and abs(t["square"] // 8 - pos // 8) <= 1
            ]
            info["revealed_squares"] = [
                algebraic(t["square"]) for t in self.traps if t["id"] in player.revealed
            ]
        elif card == "trap_disarm":
            trap = next(
                (t for t in self.traps if t["owner"] == enemy and t["square"] == square(target["square"])),
                None,
            )
            info["removed"] = trap is not None
            if trap:
                self.traps.remove(trap)
        elif card == "silence_seal":
            self.add_effect("silence", enemy)
        elif card == "arcane_focus":
            require(player.mana < 5, "INVALID_TARGET")
            player.mana = min(5, player.mana + 2)
        elif card == "arcane_draw":
            require(bool(player.deck), "INVALID_TARGET")
            # Card leaves hand before drawing, so its slot is available.
        elif card == "temporal_boost":
            require(not player.used_boost, "INVALID_TARGET")
            self.clocks[side] += 15000
            player.used_boost = True
        player.mana -= cost
        player.used_spell = True
        player.hand.remove(instance)
        player.discard.append(instance)
        if card == "arcane_draw":
            self.draw(side, 2)
        hidden_target = card in ("hidden_snare", "oracle_eye", "trap_disarm")
        return [
            {
                "type": "spell.cast",
                "side": side,
                "card": card,
                "target": None if hidden_target else target,
                "private": {side: {"target": target, **info}},
            }
        ]

    def move(self, side, value):
        require(self.status == "active", "GAME_FINISHED")
        require(side == self.board.turn, "NOT_YOUR_TURN")
        try:
            move = Move.parse(value)
        except ValueError as exc:
            raise RuleError("INVALID_MOVE") from exc
        require(move in self.moves(), "INVALID_MOVE")
        piece = self.board.pieces[move.origin]
        self.board = self.board.apply(move)
        self.clocks[side] += 5000
        events = [{"type": "piece.moved", "side": side, "move": value, "piece_id": piece.id}]
        arrivals = [move.target]
        if piece.kind == "k" and abs(move.target - move.origin) == 2:
            arrivals.append(move.origin + (1 if move.target > move.origin else -1))
        for pos in arrivals:
            arrived = self.board.pieces[pos]
            for trap in list(self.traps):
                if trap["square"] == pos and trap["owner"] != side:
                    self.traps.remove(trap)
                    if arrived.kind != "k":
                        self.freeze(arrived)
                    events.append(
                        {"type": "trap.triggered", "square": algebraic(pos), "piece_id": arrived.id}
                    )
        living = {p.id for p in self.board.pieces.values()}
        self.effects = [
            e
            for e in self.effects
            if (e["piece_id"] is None or e["piece_id"] in living)
            and not (e["expiry_side"] == side and e["expiry_turn"] <= self.players[side].own_turn_count)
        ]
        self.players[side].revealed = []
        self.draw_offer = None
        self.start_turn()
        self.resolve_result()
        return events

    def has_turn(self):
        if next(self.moves(), None) is not None:
            return True
        side = self.board.turn
        if self.players[side].used_spell or self.silenced(side):
            return False
        # Only removal of shields/freeze can enable a currently unavailable physical move.
        for card in self.players[side].hand:
            if card["definition_id"] not in ("dispel", "shield_break"):
                continue
            for target in self.targets(card["definition_id"], side):
                simulated = deepcopy(self)
                try:
                    simulated.cast(side, card["instance_id"], target)
                except RuleError:
                    continue
                if next(simulated.moves(), None) is not None:
                    return True
        return False

    def finish(self, reason, winner=None):
        self.status = "voided" if reason == "server_failure" else "finished"
        self.reason, self.winner = reason, winner

    def resolve_result(self):
        if all(p.kind == "k" for p in self.board.pieces.values()):
            self.finish("bare_kings")
        elif not self.has_turn():
            checked = self.board.in_check()
            self.finish("checkmate" if checked else "stalemate", other(self.board.turn) if checked else None)

    def command(self, side, kind, payload):
        require(self.status == "active", "GAME_FINISHED")
        if kind == "move.request":
            require(set(payload) <= {"from", "to", "promotion"}, "INVALID_PAYLOAD")
            return self.move(
                side,
                str(payload.get("from", ""))
                + str(payload.get("to", ""))
                + str(payload.get("promotion") or ""),
            )
        if kind == "spell.request":
            require(set(payload) == {"card_instance_id", "target"}, "INVALID_PAYLOAD")
            require(isinstance(payload["target"], dict), "INVALID_TARGET")
            events = self.cast(side, payload["card_instance_id"], payload["target"])
            self.resolve_result()
            return events
        if kind == "match.resign":
            self.finish("resignation", other(side))
        elif kind == "draw.offer":
            require(self.draw_offer is None, "INVALID_PHASE")
            self.draw_offer = side
        elif kind == "draw.respond":
            require(self.draw_offer == other(side), "INVALID_PHASE")
            if payload.get("accept") is True:
                self.finish("agreement")
            self.draw_offer = None
        else:
            raise RuleError("UNKNOWN_COMMAND")
        return [{"type": kind, "side": side}]

    def project(self, side):
        player, enemy = self.players[side], self.players[other(side)]
        return {
            "protocol_version": 1,
            "ruleset_version": RULESET,
            "state_version": self.version,
            "viewer_side": side,
            "board_fen": self.board.fen(),
            "pieces": [{**asdict(p), "square": algebraic(pos)} for pos, p in self.board.pieces.items()],
            "active_side": self.board.turn,
            "phase": "move" if player.used_spell else "spell",
            "public_effects": deepcopy(self.effects),
            "my_hand": deepcopy(player.hand),
            "my_mana": player.mana,
            "opponent_mana": enemy.mana,
            "opponent_hand_count": len(enemy.hand),
            "my_deck_count": len(player.deck),
            "opponent_deck_count": len(enemy.deck),
            "my_discard": deepcopy(player.discard),
            "opponent_discard": [{"definition_id": c["definition_id"]} for c in enemy.discard],
            "my_traps": [{**t, "square": algebraic(t["square"])} for t in self.traps if t["owner"] == side],
            "revealed_traps": [
                {"square": algebraic(t["square"])} for t in self.traps if t["id"] in player.revealed
            ],
            "clock_ms": {s: max(0, round(v)) for s, v in self.clocks.items()},
            "legal_moves": [m.uci() for m in self.moves()]
            if self.board.turn == side and self.status == "active"
            else [],
            "can_cast": self.status == "active"
            and self.board.turn == side
            and not player.used_spell
            and not self.silenced(side),
            "status": self.status,
            "result_reason": self.reason,
            "winner": self.winner,
            "draw_offer": self.draw_offer,
            "tutorial": self.tutorial,
            "limitations": "Alpha: sem repetição e regras de 50/75 lances; empate material apenas rei contra rei.",
        }


def project_event(event, side):
    return {
        **{k: deepcopy(v) for k, v in event.items() if k != "private"},
        **deepcopy(event.get("private", {}).get(side, {})),
    }
