"""Independent orthodox move generator. No third party chess implementation.

Attack maps deliberately ignore pins, capture shields and immobilization.
Magic filters apply to physical moves, never to geometric attacks.
"""

from dataclasses import dataclass, replace

FILES = "abcdefgh"
INITIAL_FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"


def square(name: str) -> int:
    if len(name) != 2 or name[0] not in FILES or name[1] not in "12345678":
        raise ValueError("INVALID_SQUARE")
    return FILES.index(name[0]) + 8 * (int(name[1]) - 1)


def algebraic(pos: int) -> str:
    return FILES[pos % 8] + str(pos // 8 + 1)


def other(side: str) -> str:
    return "black" if side == "white" else "white"


@dataclass(frozen=True)
class Piece:
    id: str
    side: str
    kind: str


@dataclass(frozen=True)
class Move:
    origin: int
    target: int
    promotion: str | None = None

    @classmethod
    def parse(cls, value: str):
        if len(value) not in (4, 5):
            raise ValueError("INVALID_MOVE")
        promotion = value[4:] or None
        if promotion and promotion not in "qrbn":
            raise ValueError("INVALID_PROMOTION")
        return cls(square(value[:2]), square(value[2:4]), promotion)

    def uci(self):
        return algebraic(self.origin) + algebraic(self.target) + (self.promotion or "")


@dataclass
class Board:
    pieces: dict[int, Piece]
    turn: str = "white"
    castling: str = "KQkq"
    ep: int | None = None
    halfmove: int = 0
    fullmove: int = 1

    @classmethod
    def from_fen(cls, fen=INITIAL_FEN):
        placement, side, rights, ep, half, full = fen.split()
        pieces = {}
        rows = placement.split("/")
        if len(rows) != 8:
            raise ValueError("INVALID_FEN")
        for rank, row in enumerate(reversed(rows)):
            file = 0
            for char in row:
                if char.isdigit():
                    file += int(char)
                else:
                    if char.lower() not in "prnbqk" or file >= 8:
                        raise ValueError("INVALID_FEN")
                    pos = rank * 8 + file
                    color = "white" if char.isupper() else "black"
                    pieces[pos] = Piece(f"{color}_{algebraic(pos)}", color, char.lower())
                    file += 1
            if file != 8:
                raise ValueError("INVALID_FEN")
        return cls(
            pieces,
            "white" if side == "w" else "black",
            "" if rights == "-" else rights,
            None if ep == "-" else square(ep),
            int(half),
            int(full),
        )

    def fen(self):
        rows = []
        for rank in range(7, -1, -1):
            row, empty = "", 0
            for file in range(8):
                piece = self.pieces.get(rank * 8 + file)
                if piece:
                    row += str(empty) if empty else ""
                    row += piece.kind.upper() if piece.side == "white" else piece.kind
                    empty = 0
                else:
                    empty += 1
            rows.append(row + (str(empty) if empty else ""))
        return (
            "/".join(rows) + f" {'w' if self.turn == 'white' else 'b'} {self.castling or '-'} "
            f"{algebraic(self.ep) if self.ep is not None else '-'} {self.halfmove} {self.fullmove}"
        )

    def copy(self):
        return replace(self, pieces=self.pieces.copy())

    def king(self, side):
        return next(pos for pos, p in self.pieces.items() if p.side == side and p.kind == "k")

    def attacks(self, pos):
        piece = self.pieces[pos]
        x, y = pos % 8, pos // 8
        if piece.kind == "p":
            steps = [(-1, 1 if piece.side == "white" else -1), (1, 1 if piece.side == "white" else -1)]
        elif piece.kind == "n":
            steps = [(1, 2), (2, 1), (-1, 2), (-2, 1), (1, -2), (2, -1), (-1, -2), (-2, -1)]
        else:
            steps = []
            if piece.kind in "rbqk":
                if piece.kind in "rqk":
                    steps += [(1, 0), (-1, 0), (0, 1), (0, -1)]
                if piece.kind in "bqk":
                    steps += [(1, 1), (1, -1), (-1, 1), (-1, -1)]
        sliding = piece.kind in "rbq"
        for dx, dy in steps:
            nx, ny = x + dx, y + dy
            while 0 <= nx < 8 and 0 <= ny < 8:
                target = ny * 8 + nx
                yield target
                if not sliding or target in self.pieces:
                    break
                nx, ny = nx + dx, ny + dy

    def attacked(self, pos, by_side):
        return any(pos in self.attacks(origin) for origin, p in self.pieces.items() if p.side == by_side)

    def in_check(self, side=None):
        side = side or self.turn
        return self.attacked(self.king(side), other(side))

    def captured_square(self, move):
        piece = self.pieces[move.origin]
        if piece.kind == "p" and move.target == self.ep and move.target not in self.pieces:
            return move.target - (8 if piece.side == "white" else -8)
        return move.target

    def candidates(self, frozen=frozenset()):
        for origin, piece in self.pieces.items():
            if piece.side != self.turn or piece.id in frozen:
                continue
            if piece.kind == "p":
                step = 8 if piece.side == "white" else -8
                forward = origin + step
                targets = []
                if 0 <= forward < 64 and forward not in self.pieces:
                    targets.append(forward)
                    if (
                        origin // 8 == (1 if piece.side == "white" else 6)
                        and forward + step not in self.pieces
                    ):
                        targets.append(forward + step)
                for target in self.attacks(origin):
                    enemy = self.pieces.get(target)
                    ep_pawn = self.pieces.get(target - step)
                    if (enemy and enemy.side != piece.side and enemy.kind != "k") or (
                        target == self.ep
                        and enemy is None
                        and ep_pawn
                        and ep_pawn.side != piece.side
                        and ep_pawn.kind == "p"
                    ):
                        targets.append(target)
                for target in targets:
                    for promotion in ("q", "r", "b", "n") if target // 8 in (0, 7) else (None,):
                        yield Move(origin, target, promotion)
            else:
                for target in self.attacks(origin):
                    occupant = self.pieces.get(target)
                    if occupant is None or (occupant.side != piece.side and occupant.kind != "k"):
                        yield Move(origin, target)
                if piece.kind == "k":
                    base = 0 if piece.side == "white" else 56
                    if origin != base + 4 or self.in_check():
                        continue
                    for symbol, rook_file, king_file, empty_files, crossing in (
                        ("K", 7, 6, (5, 6), 5),
                        ("Q", 0, 2, (1, 2, 3), 3),
                    ):
                        symbol = symbol if piece.side == "white" else symbol.lower()
                        rook = self.pieces.get(base + rook_file)
                        if (
                            symbol not in self.castling
                            or rook is None
                            or rook.kind != "r"
                            or rook.side != piece.side
                            or rook.id in frozen
                            or any(base + file in self.pieces for file in empty_files)
                        ):
                            continue
                        crossed = self.copy()
                        crossed.pieces[base + crossing] = crossed.pieces.pop(origin)
                        if not crossed.in_check(piece.side):
                            yield Move(origin, base + king_file)

    def apply(self, move):
        board = self.copy()
        piece = board.pieces.pop(move.origin)
        captured_pos = self.captured_square(move)
        captured = board.pieces.pop(captured_pos, None)
        board.pieces[move.target] = replace(piece, kind=move.promotion) if move.promotion else piece
        if piece.kind == "k" and abs(move.target - move.origin) == 2:
            rook_origin = (move.origin // 8) * 8 + (7 if move.target > move.origin else 0)
            rook_target = move.origin + (1 if move.target > move.origin else -1)
            board.pieces[rook_target] = board.pieces.pop(rook_origin)
        rights = board.castling
        if piece.kind == "k":
            rights = rights.replace("K" if piece.side == "white" else "k", "")
            rights = rights.replace("Q" if piece.side == "white" else "q", "")
        for pos, symbol in ((0, "Q"), (7, "K"), (56, "q"), (63, "k")):
            if pos == move.origin or (captured and pos == captured_pos):
                rights = rights.replace(symbol, "")
        board.castling = rights
        board.ep = (
            (move.origin + move.target) // 2
            if piece.kind == "p" and abs(move.target - move.origin) == 16
            else None
        )
        board.halfmove = 0 if piece.kind == "p" or captured else board.halfmove + 1
        board.fullmove += int(piece.side == "black")
        board.turn = other(piece.side)
        return board

    def legal_moves(self, frozen=frozenset(), protected=frozenset()):
        side = self.turn
        for move in self.candidates(frozen):
            captured = self.pieces.get(self.captured_square(move))
            if captured and captured.id in protected:
                continue
            after = self.apply(move)
            if not after.in_check(side):
                yield move


def perft(board, depth):
    if depth == 0:
        return 1
    return sum(perft(board.apply(move), depth - 1) for move in board.legal_moves())
