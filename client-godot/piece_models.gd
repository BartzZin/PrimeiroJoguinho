extends RefCounted
## Textured miniatures supplied in Models/Xadrez_final.rar.
## Keep the imported materials: their textures distinguish both armies.

const SCENES = {
	"white": {
		"p": preload("res://assets/models/blue/pawn.glb"),
		"r": preload("res://assets/models/blue/rook.glb"),
		"n": preload("res://assets/models/blue/knight.glb"),
		"b": preload("res://assets/models/blue/bishop.glb"),
		"q": preload("res://assets/models/blue/queen.glb"),
		"k": preload("res://assets/models/blue/king.glb"),
	},
	"black": {
		"p": preload("res://assets/models/red/pawn.glb"),
		"r": preload("res://assets/models/red/rook.glb"),
		"n": preload("res://assets/models/red/knight.glb"),
		"b": preload("res://assets/models/red/bishop.glb"),
		"q": preload("res://assets/models/red/queen.glb"),
		"k": preload("res://assets/models/red/king.glb"),
	},
}
const HEIGHTS = {"p": 0.94, "r": 1.04, "n": 1.12, "b": 1.18, "q": 1.26, "k": 1.30}
const MAX_FOOTPRINT = 0.84


static func mesh_bounds(node: Node3D, parent_transform := Transform3D.IDENTITY) -> AABB:
	var transform = parent_transform * node.transform
	var bounds = AABB()
	if node is MeshInstance3D:
		bounds = transform * node.get_aabb()
	for child in node.get_children():
		if child is Node3D:
			var child_bounds = mesh_bounds(child, transform)
			if child_bounds.has_volume():
				bounds = bounds.merge(child_bounds) if bounds.has_volume() else child_bounds
	return bounds


static func create(kind: String, side: String) -> Node3D:
	var model = SCENES[side][kind].instantiate()
	var bounds = mesh_bounds(model)
	var factor = minf(HEIGHTS[kind] / bounds.size.y, MAX_FOOTPRINT / maxf(bounds.size.x, bounds.size.z))
	# Sources have their origin at half height. Put the base on the board and
	# center the full silhouette, including the horse's muzzle and accessories.
	var centered = Node3D.new()
	centered.name = "Miniature"
	centered.add_child(model)
	model.position -= Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
	centered.scale = Vector3.ONE * factor
	# glTF fronts face +Z. Solar advances toward -Z; Lunar toward +Z.
	centered.rotation.y = PI if side == "white" else 0.0
	return centered
