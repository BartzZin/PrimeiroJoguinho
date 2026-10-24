extends Node3D
## Reconciles authoritative data, remembers confirmed squares and builds paths.

const PieceView = preload("res://piece_view.gd")
const PieceMovePath = preload("res://piece_move_path.gd")
const BOARD_CLEARANCE = PieceMovePath.BOARD_CLEARANCE

var _pieces: Dictionary[String, PieceView] = {}
var _states: Dictionary[String, Dictionary] = {}
var _square_to_position: Callable
var _animations_enabled := true
var _sounds_enabled := true
var _active := false


func setup(square_to_position: Callable) -> void:
	_square_to_position = square_to_position


func synchronize(pieces: Array, public_effects: Array, animated: bool = true) -> void:
	var incoming: Dictionary[String, Dictionary] = {}
	var effects_by_piece: Dictionary = {}
	for effect: Dictionary in public_effects:
		var id: String = effect.get("piece_id", "")
		if not effects_by_piece.has(id):
			effects_by_piece[id] = []
		effects_by_piece[id].append(effect)
	for piece: Dictionary in pieces:
		incoming[piece.id] = piece
	for id: String in _pieces.keys():
		if not incoming.has(id):
			_pieces[id].free()
			_pieces.erase(id)
	for piece: Dictionary in pieces:
		var id: String = piece.id
		if not _pieces.has(id):
			var view := PieceView.new()
			view.setup(id, piece.kind, piece.side, _position(piece.square))
			view.set_animations_enabled(_animations_enabled)
			view.set_sounds_enabled(_sounds_enabled)
			view.set_active(_active)
			_pieces[id] = view
			add_child(view)
		_pieces[id].update_effects(effects_by_piece.get(id, []))
	var castling_rooks := _castling_rooks(incoming) if animated else {}
	for piece: Dictionary in pieces:
		if not castling_rooks.has(piece.id):
			_synchronize_piece(piece, incoming, animated, castling_rooks)
	for rook_id: String in castling_rooks:
		var king: PieceView = _pieces[castling_rooks[rook_id]]
		if _animations_enabled and king.animator.moving:
			_pieces[rook_id].wait_for(king)
		_synchronize_piece(incoming[rook_id], incoming, animated, castling_rooks)
	_states.clear()
	for piece: Dictionary in pieces:
		_states[piece.id] = piece.duplicate()


func _synchronize_piece(piece: Dictionary, incoming: Dictionary, animated: bool, castling_rooks: Dictionary) -> void:
	var view: PieceView = _pieces[piece.id]
	if not animated or not _states.has(piece.id):
		view.resync(_position(piece.square), piece.kind, piece.side)
		return
	var previous: Dictionary = _states[piece.id]
	if previous.square == piece.square:
		view.synchronize_model(piece.kind, piece.side)
		return
	var occupied: Dictionary = {}
	for other_id: String in incoming:
		if other_id == piece.id:
			continue
		var square: String = incoming[other_id].square
		if castling_rooks.get(other_id) == piece.id:
			# The rook has not moved yet while the king crosses its future square.
			square = _states[other_id].square
		occupied[square] = _pieces[other_id].clearance_height(incoming[other_id].kind)
	var hops := PieceMovePath.build(previous.square, piece.square, previous.kind, _square_to_position, occupied)
	view.enqueue_move(hops, piece.kind, piece.side, not castling_rooks.has(piece.id))


func _castling_rooks(incoming: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for id: String in incoming:
		if not _states.has(id) or _states[id].kind != "k":
			continue
		var before: String = _states[id].square
		var after: String = incoming[id].square
		if before[1] != after[1] or absi(after.unicode_at(0) - before.unicode_at(0)) != 2:
			continue
		var rook_origin := ("h" if after[0] == "g" else "a") + after[1]
		var rook_target := ("f" if after[0] == "g" else "d") + after[1]
		for rook_id: String in incoming:
			if _states.has(rook_id) and _states[rook_id].kind == "r" and _states[rook_id].side == incoming[id].side and _states[rook_id].square == rook_origin and incoming[rook_id].square == rook_target:
				result[rook_id] = id
	return result


func _position(square: String) -> Vector3:
	return _square_to_position.call(square) + BOARD_CLEARANCE


func set_animations_enabled(value: bool) -> void:
	if _animations_enabled == value:
		return
	_animations_enabled = value
	for view: PieceView in _pieces.values():
		view.set_animations_enabled(value)


func set_sounds_enabled(value: bool) -> void:
	_sounds_enabled = value
	for view: PieceView in _pieces.values():
		view.set_sounds_enabled(value)


func set_active(value: bool) -> void:
	if _active == value:
		return
	_active = value
	for view: PieceView in _pieces.values():
		view.set_active(value)


func clear() -> void:
	for view: PieceView in _pieces.values():
		view.free()
	_pieces.clear()
	_states.clear()
