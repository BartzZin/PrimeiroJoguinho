extends Button
## GUI picking follows the projected card, not its rectangular bounding box.

var polygon = PackedVector2Array()


func _has_point(point: Vector2) -> bool:
	return polygon.size() >= 3 and Geometry2D.is_point_in_polygon(point, polygon)
