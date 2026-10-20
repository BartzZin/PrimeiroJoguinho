import json
import random
from copy import deepcopy

import pytest

from app.domain.chess import Board, square
from app.domain.game import CARDS, Game, RuleError, identifier, project_event


def grant(game, side, card):
    instance = {"instance_id": identifier(), "definition_id": card}
    game.players[side].hand = [instance]
    game.players[side].mana = 5
    game.players[side].used_spell = False
    return instance["instance_id"]


def cast(game, side, card, target):
    return game.cast(side, grant(game, side, card), target)


def test_resources_and_roundtrip():
    game = Game.new()
    assert game.players["white"].mana == 2
    assert len(game.players["black"].hand) == 3
    assert len(game.players["white"].deck) == 21
    assert Game.load(json.loads(json.dumps(game.dump()))).dump() == game.dump()
    game.move("white", "e2e4")
    assert game.players["black"].mana == 2
    game.move("black", "e7e5")
    assert len(game.players["white"].hand) == 4


def test_shield_expiration_and_break():
    game = Game.new()
    game.board = Board.from_fen("4k3/8/8/8/8/8/r7/R3K3 w Q - 0 1")
    rook = game.board.pieces[square("a1")]
    cast(game, "white", "arcane_shield", {"piece_id": rook.id})
    game.move("white", "e1f1")
    assert "a2a1" not in {m.uci() for m in game.moves()}
    cast(game, "black", "shield_break", {"piece_id": rook.id})
    assert "a2a1" in {m.uci() for m in game.moves()}
    game.move("black", "a2a1")
    assert not game.effects


def test_trap_does_not_expire_on_activation_turn():
    game = Game.new()
    cast(game, "white", "hidden_snare", {"square": "f6"})
    game.move("white", "e2e4")
    game.move("black", "g8f6")
    assert game.affected("frozen")
    game.move("white", "d2d4")
    assert not any(m.origin == square("f6") for m in game.moves())
    game.move("black", "e7e5")
    assert not game.affected("frozen")


def test_traps_of_opposite_owners_can_overlap():
    game = Game.new()
    cast(game, "white", "hidden_snare", {"square": "d4"})
    game.move("white", "e2e4")
    cast(game, "black", "hidden_snare", {"square": "d4"})
    assert len(game.traps) == 2
    enemy = json.dumps(game.project("black"))
    assert game.traps[0]["id"] not in enemy
    public = project_event(
        {"type": "spell.cast", "private": {"white": {"target": {"square": "d4"}}}}, "black"
    )
    assert "d4" not in json.dumps(public)


def test_ward_consumed_by_freeze():
    game = Game.new()
    pawn = game.board.pieces[square("e2")]
    cast(game, "white", "ward", {"piece_id": pawn.id})
    game.move("white", "e2e4")
    cast(game, "black", "frost_bind", {"piece_id": pawn.id})
    assert not game.affected("frozen") and not game.affected("ward")


def test_immobilized_piece_keeps_check():
    game = Game.new()
    game.board = Board.from_fen("4k3/8/8/8/8/8/4r3/4K3 w - - 0 1")
    rook = game.board.pieces[square("e2")]
    cast(game, "white", "frost_bind", {"piece_id": rook.id})
    assert game.board.in_check("white")


def test_magic_escape_prevents_mate():
    game = Game.new()
    game.board = Board.from_fen("7k/6Q1/5K2/8/8/8/8/8 b - - 0 1")
    queen = game.board.pieces[square("g7")]
    game.add_effect("shield", "white", queen.id, "black")
    grant(game, "black", "shield_break")
    # King can capture g7 only if the defender is not protecting it.
    # Change white king to f5 to make capture safe while preserving blocked escape squares using a rook.
    game.board = Board.from_fen("7k/6Q1/7R/5K2/8/8/8/8 b - - 0 1")
    queen = game.board.pieces[square("g7")]
    game.effects[0]["piece_id"] = queen.id
    assert not list(game.moves())
    assert game.has_turn()
    game.resolve_result()
    assert game.status == "active"
    game.players["black"].hand = []
    game.resolve_result()
    assert game.reason == "checkmate"


def test_silence_and_focus():
    game = Game.new()
    cast(game, "white", "silence_seal", {})
    game.move("white", "e2e4")
    card = grant(game, "black", "arcane_focus")
    with pytest.raises(RuleError, match="INVALID_PHASE"):
        game.cast("black", card, {})
    game.move("black", "e7e5")
    game.move("white", "d2d4")
    game.players["black"].mana = 1
    game.cast("black", card, {})
    assert game.players["black"].mana == 3


def test_oracle_and_blind_disarm():
    game = Game.new()
    cast(game, "white", "hidden_snare", {"square": "a3"})
    game.move("white", "e2e4")
    cast(game, "black", "oracle_eye", {"square": "a2"})
    assert game.project("black")["revealed_traps"] == [{"square": "a3"}]
    game.move("black", "e7e5")
    assert not game.project("black")["revealed_traps"]
    game.move("white", "d2d4")
    events = cast(game, "black", "trap_disarm", {"square": "a3"})
    assert project_event(events[0], "black")["removed"] is True
    assert "removed" not in project_event(events[0], "white")
    assert not game.traps


def test_temporal_boost_once_and_draw():
    game = Game.new()
    cast(game, "white", "temporal_boost", {})
    assert game.clocks["white"] == 615000
    game.players["white"].used_spell = False
    with pytest.raises(RuleError, match="INVALID_TARGET"):
        cast(game, "white", "temporal_boost", {})
    game.players["white"].used_spell = False
    cast(game, "white", "arcane_draw", {})
    assert len(game.players["white"].hand) == 2


def test_king_triggers_snare_without_freeze():
    game = Game.new()
    game.board = Board.from_fen("4k3/8/8/8/8/8/8/4K3 w - - 0 1")
    game.traps = [{"id": "trap", "owner": "black", "square": square("e2")}]
    game.move("white", "e1e2")
    assert not game.traps and not game.effects
    assert game.reason == "bare_kings"


def test_failed_spell_does_not_consume_resources():
    game = Game.new()
    card = grant(game, "white", "arcane_shield")
    before = deepcopy(game.dump())
    with pytest.raises(RuleError):
        game.cast("white", card, {"piece_id": "forged"})
    assert game.dump() == before


def test_random_invariants():
    rng = random.Random(19)
    for _ in range(8):
        game = Game.new()
        for _ in range(80):
            if game.status != "active":
                break
            moves = list(game.moves())
            if not moves:
                break
            game.move(game.board.turn, rng.choice(moves).uci())
            pieces = list(game.board.pieces.values())
            assert len({p.id for p in pieces}) == len(pieces)
            assert sum(p.kind == "k" for p in pieces) == 2
            for player in game.players.values():
                all_cards = player.hand + player.deck + player.discard
                assert len(all_cards) == 24
                assert len({c["instance_id"] for c in all_cards}) == 24
                assert 0 <= player.mana <= 5 and len(player.hand) <= 5


def test_all_twelve_cards_present():
    assert len(CARDS) == 12
