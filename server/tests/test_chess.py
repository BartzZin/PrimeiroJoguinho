import pytest

from app.domain.chess import Board, Move, perft, square


@pytest.mark.parametrize("depth,expected", [(1, 20), (2, 400), (3, 8902), (4, 197281)])
def test_initial_perft(depth, expected):
    assert perft(Board.from_fen(), depth) == expected


def test_kiwipete():
    board = Board.from_fen("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1")
    assert perft(board, 1) == 48
    assert perft(board, 2) == 2039


def test_en_passant_discovered_check():
    board = Board.from_fen("k7/8/8/r4pPK/8/8/8/8 w - f6 0 1")
    assert "g5f6" not in {m.uci() for m in board.legal_moves()}


def test_shield_on_en_passant_victim():
    board = Board.from_fen("k7/8/8/5pP1/8/8/8/7K w - f6 0 1")
    assert "g5f6" in {m.uci() for m in board.legal_moves()}
    assert "g5f6" not in {m.uci() for m in board.legal_moves(protected={board.pieces[square("f5")].id})}


def test_promotions_preserve_id():
    board = Board.from_fen("7k/P7/8/8/8/8/8/7K w - - 0 1")
    assert {m.promotion for m in board.legal_moves() if m.origin == square("a7")} == set("qrbn")
    result = board.apply(Move.parse("a7a8n"))
    assert result.pieces[square("a8")].id == board.pieces[square("a7")].id


def test_frozen_rook_prevents_castling_but_still_attacks():
    board = Board.from_fen("4k3/8/8/8/8/8/8/4K2R w K - 0 1")
    frozen = {board.pieces[square("h1")].id}
    assert "e1g1" not in {m.uci() for m in board.legal_moves(frozen)}
    assert board.attacked(square("h8"), "white")


def test_fen_roundtrip():
    board = Board.from_fen()
    assert Board.from_fen(board.fen()).fen() == board.fen()
