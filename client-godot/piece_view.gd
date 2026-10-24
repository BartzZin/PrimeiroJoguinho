extends Node3D
## Composes one miniature, its effects, motion state and contact sounds.

signal motion_finished

const PieceModels = preload("res://piece_models.gd")
const PieceAnimator = preload("res://piece_animator.gd")
const PieceMovePath = preload("res://piece_move_path.gd")
const PieceSfxPlayer = preload("res://piece_sfx_player.gd")

var piece_id := ""
var kind := ""
var side := ""
var model_height := 0.0
var miniature: Node3D
var visual_pivot := Node3D.new()
var effects_root := Node3D.new()
var animator: PieceAnimator = PieceAnimator.new()
var sfx: PieceSfxPlayer = PieceSfxPlayer.new()
var _effects: Array = []
var _pending_models: Array[Dictionary] = []
var _waiting_for: Node
var _animations_enabled := true
var _active := false
var _frozen := false


func _init() -> void:
	visual_pivot.name = "VisualPivot"
	effects_root.name = "Effects"
	add_child(visual_pivot)
	add_child(effects_root)
	add_child(sfx)
	animator.jump_started.connect(sfx.play_impulse)
	animator.landed.connect(sfx.play_landing)
	animator.move_finished.connect(_on_move_finished)
	set_process(false)


func setup(id: String, piece_kind: String, piece_side: String, at: Vector3) -> void:
	piece_id = id
	name = id
	animator.setup(at, id)
	sfx.setup(id)
	update_model(piece_kind, piece_side)
	_update_idle()
	_apply_pose()


func update_model(piece_kind: String, piece_side: String) -> void:
	if kind == piece_kind and side == piece_side:
		return
	kind = piece_kind
	side = piece_side
	if is_instance_valid(miniature):
		miniature.free()
	miniature = PieceModels.create(kind, side)
	visual_pivot.add_child(miniature)
	model_height = PieceModels.mesh_bounds(miniature).size.y


func synchronize_model(piece_kind: String, piece_side: String) -> void:
	if not animator.moving:
		update_model(piece_kind, piece_side)


func clearance_height(final_kind: String) -> float:
	# Include a promotion that may finish while another miniature flies overhead.
	return maxf(model_height, float(PieceModels.HEIGHTS[final_kind]))


func update_effects(effects: Array) -> void:
	if _effects == effects:
		return
	_effects = effects.duplicate(true)
	_frozen = false
	for child in effects_root.get_children():
		child.free()
	for effect: Dictionary in effects:
		_frozen = _frozen or effect.get("kind") == "frozen"
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.32
		torus.outer_radius = 0.4
		ring.mesh = torus
		ring.position.y = 0.29 + effects_root.get_child_count() * 0.09
		var paint := StandardMaterial3D.new()
		paint.albedo_color = Color("55d7ff") if effect.get("kind") == "shield" else Color("997cff")
		paint.roughness = 0.65
		ring.material_override = paint
		effects_root.add_child(ring)
	_update_idle()


func enqueue_move(hops: Array[PieceMovePath.Hop], final_kind: String, final_side: String, instant_sound: bool = true) -> void:
	_pending_models.append({"kind": final_kind, "side": final_side})
	animator.enqueue(hops)
	if not _animations_enabled and instant_sound:
		sfx.play_landing()
	_apply_pose()
	set_process(animator.needs_processing())


func wait_for(view: Node) -> void:
	_clear_wait()
	_waiting_for = view
	animator.set_paused(true)
	view.motion_finished.connect(_release_wait, CONNECT_ONE_SHOT)


func resync(at: Vector3, final_kind: String, final_side: String) -> void:
	_clear_wait()
	_pending_models.clear()
	animator.snap_to(at)
	sfx.stop()
	update_model(final_kind, final_side)
	_apply_pose()
	set_process(animator.needs_processing())


func set_animations_enabled(value: bool) -> void:
	_animations_enabled = value
	var was_moving := animator.moving
	if not value:
		_clear_wait()
	animator.set_enabled(value)
	if not value and not _pending_models.is_empty():
		var final_model: Dictionary = _pending_models[-1]
		_pending_models.clear()
		update_model(final_model.kind, final_model.side)
	_apply_pose()
	set_process(animator.needs_processing())
	if not value and was_moving:
		motion_finished.emit()


func set_sounds_enabled(value: bool) -> void:
	sfx.set_enabled(value)


func set_active(value: bool) -> void:
	_active = value
	_update_idle()


func _update_idle() -> void:
	animator.set_idle_enabled(_active and not _frozen)
	set_process(animator.needs_processing())


func _process(delta: float) -> void:
	animator.advance(delta)
	_apply_pose()
	if not animator.needs_processing():
		set_process(false)


func _apply_pose() -> void:
	position = animator.position
	visual_pivot.rotation = animator.rotation


func _on_move_finished() -> void:
	if not _pending_models.is_empty():
		var final_model: Dictionary = _pending_models.pop_front()
		update_model(final_model.kind, final_model.side)
	motion_finished.emit()


func _release_wait() -> void:
	_waiting_for = null
	animator.set_paused(false)
	set_process(animator.needs_processing())


func _clear_wait() -> void:
	if is_instance_valid(_waiting_for) and _waiting_for.motion_finished.is_connected(_release_wait):
		_waiting_for.motion_finished.disconnect(_release_wait)
	_release_wait()
