extends RefCounted
## Presentation paths only. Legality and final positions belong to the server.

const BOARD_CLEARANCE = Vector3(0, 0.095, 0)

class Hop:
	extends RefCounted
	var points := PackedVector3Array()
	var clearance := 0.0
	var high_jump := false


static func squares(origin: String, target: String, kind: String) -> Array[String]:
	var result: Array[String] = []
	var at := Vector2i("abcdefgh".find(origin[0]), int(origin[1]) - 1)
	var end := Vector2i("abcdefgh".find(target[0]), int(target[1]) - 1)
	var difference := end - at
	if difference == Vector2i.ZERO:
		return result
	var direction := Vector2i(signi(difference.x), signi(difference.y))
	if kind == "n" and absi(difference.x) * absi(difference.y) == 2:
		var major := Vector2i(direction.x, 0) if absi(difference.x) == 2 else Vector2i(0, direction.y)
		for step in range(2):
			at += major
			result.append(_square(at))
		result.append(target)
	elif difference.x == 0 or difference.y == 0 or absi(difference.x) == absi(difference.y):
		while at != end:
			at += direction
			result.append(_square(at))
	else:
		# A skipped server state can span more than one legal move.
		result.append(target)
	return result


static func build(origin: String, target: String, kind: String, square_to_position: Callable, occupied: Dictionary = {}) -> Array[Hop]:
	var result: Array[Hop] = []
	var points := PackedVector3Array([square_to_position.call(origin) + BOARD_CLEARANCE])
	var clearance := 0.0
	for square: String in squares(origin, target, kind):
		points.append(square_to_position.call(square) + BOARD_CLEARANCE)
		if square != target and occupied.has(square):
			clearance = maxf(clearance, float(occupied[square]))
			continue
		var hop := Hop.new()
		hop.points = points
		hop.clearance = clearance
		hop.high_jump = kind == "n"
		result.append(hop)
		points = PackedVector3Array([points[-1]])
		clearance = 0.0
	return result


static func _square(at: Vector2i) -> String:
	return "abcdefgh"[at.x] + str(at.y + 1)
