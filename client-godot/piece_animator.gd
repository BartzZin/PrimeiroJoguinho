extends RefCounted
## Pure, deterministic visual state. Signals describe actual animation contacts.

signal jump_started
signal landed
signal move_finished

const PieceMovePath = preload("res://piece_move_path.gd")
const FLIGHT_TIME = 0.22
const SETTLE_TIME = 0.04
const IDLE_BLEND_TIME = 0.2
const IDLE_ANGLE = PI / 180.0
const JUMP_HEIGHT = 0.22
const HIGH_JUMP_HEIGHT = 0.38
const OBSTACLE_MARGIN = 0.15

var position := Vector3.ZERO
var rotation := Vector3.ZERO
var destination := Vector3.ZERO
var moving := false
var _queue: Array = []
var _current: PieceMovePath.Hop
var _hop_index := 0
var _elapsed := 0.0
var _settling := false
var _paused := false
var _enabled := true
var _idle_enabled := false
var _idle_blend := 0.0
var _time := 0.0
var _period := Vector2(3.0, 4.0)
var _phase := Vector2.ZERO
var _amplitude := Vector2.ZERO
var _takeoff_rotation := Vector3.ZERO
var _landing_rotation := Vector3.ZERO
var _lean := Vector3.ZERO


func setup(at: Vector3, identity: String) -> void:
	position = at
	destination = at
	var random := RandomNumberGenerator.new()
	# Mix the entire ID: neighboring IDs such as white_a2/white_b2 must diverge.
	random.seed = identity.sha256_text().substr(0, 12).hex_to_int()
	_period = Vector2(random.randf_range(3.0, 5.0), random.randf_range(3.0, 5.0))
	_phase = Vector2(random.randf_range(0.0, TAU), random.randf_range(0.0, TAU))
	_amplitude = Vector2(random.randf_range(0.25, 0.6), random.randf_range(0.35, 0.75))
	_amplitude.x *= -1.0 if random.randf() < 0.5 else 1.0
	_amplitude.y *= -1.0 if random.randf() < 0.5 else 1.0


func set_enabled(value: bool) -> void:
	_enabled = value
	if not value:
		snap_to(destination)


func set_idle_enabled(value: bool) -> void:
	_idle_enabled = value


func set_paused(value: bool) -> void:
	_paused = value


func enqueue(hops: Array[PieceMovePath.Hop]) -> void:
	if hops.is_empty():
		return
	destination = hops[-1].points[-1]
	if not _enabled:
		snap_to(destination)
		move_finished.emit()
		return
	_queue.append(hops.duplicate())
	moving = true


func snap_to(at: Vector3) -> void:
	destination = at
	position = at
	rotation = Vector3.ZERO
	_queue.clear()
	_current = null
	_hop_index = 0
	_elapsed = 0.0
	_settling = false
	_paused = false
	moving = false
	_idle_blend = 0.0


func needs_processing() -> bool:
	return _enabled and (moving or _idle_enabled or _idle_blend > 0.0)


func advance(delta: float) -> void:
	if not _enabled:
		return
	var remaining := maxf(delta, 0.0)
	_time += remaining
	if not moving or _paused:
		_update_idle(remaining)
		return
	while remaining > 0.000001 and moving and not _paused:
		if _current == null:
			_start_hop()
		var duration := SETTLE_TIME if _settling else FLIGHT_TIME * (_current.points.size() - 1)
		var step := minf(remaining, maxf(0.0, duration - _elapsed))
		_elapsed += step
		remaining -= step
		var progress := clampf(_elapsed / duration, 0.0, 1.0)
		if _settling:
			rotation = _landing_rotation * (1.0 - smoothstep(0.0, 1.0, progress))
			rotation += _lean * sin(progress * PI) * 0.4
		else:
			_sample_flight(progress)
		if _elapsed + 0.000001 >= duration:
			_finish_stage()
	if not moving and remaining > 0.0:
		_update_idle(remaining)


func _update_idle(delta: float) -> void:
	_idle_blend = move_toward(_idle_blend, 1.0 if _idle_enabled else 0.0, delta / IDLE_BLEND_TIME)
	var weight := smoothstep(0.0, 1.0, _idle_blend)
	rotation = Vector3(
		sin(_time * TAU / _period.x + _phase.x) * _amplitude.x,
		0.0,
		sin(_time * TAU / _period.y + _phase.y) * _amplitude.y
	) * IDLE_ANGLE * weight


func _start_hop() -> void:
	_current = _queue[0][_hop_index]
	_elapsed = 0.0
	_settling = false
	_takeoff_rotation = rotation
	_idle_blend = 0.0
	var direction := (_current.points[-1] - _current.points[0]).normalized()
	_lean = Vector3(direction.z, 0.0, -direction.x) * IDLE_ANGLE * 0.65
	jump_started.emit()


func _sample_flight(progress: float) -> void:
	var travel := smoothstep(0.0, 1.0, progress)
	var height := HIGH_JUMP_HEIGHT if _current.high_jump else JUMP_HEIGHT
	var lift := sin(travel * PI) * height
	if _current.clearance > 0.0:
		# Rise before crossing occupied squares, then descend on the free endpoint.
		travel = smoothstep(0.18, 0.82, progress)
		height = maxf(height, _current.clearance + OBSTACLE_MARGIN)
		lift = height * smoothstep(0.0, 0.18, progress) * (1.0 - smoothstep(0.82, 1.0, progress))
	var scaled := travel * (_current.points.size() - 1)
	var index := mini(int(scaled), _current.points.size() - 2)
	position = _current.points[index].lerp(_current.points[index + 1], scaled - index)
	position.y += lift
	rotation = _takeoff_rotation * (1.0 - smoothstep(0.0, 0.35, progress))
	rotation += _lean * sin(progress * TAU)


func _finish_stage() -> void:
	_elapsed = 0.0
	if not _settling:
		position = _current.points[-1]
		_landing_rotation = rotation
		_settling = true
		landed.emit()
		return
	rotation = Vector3.ZERO
	_current = null
	_hop_index += 1
	if _hop_index == _queue[0].size():
		_queue.pop_front()
		_hop_index = 0
		moving = not _queue.is_empty()
		move_finished.emit()
