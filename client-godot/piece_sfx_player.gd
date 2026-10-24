extends Node
## Shared original samples; one independent player component per miniature.

signal played(kind: StringName)

const IMPULSE = preload("res://assets/audio/pieces/impulse.wav")
const LANDINGS = [
	preload("res://assets/audio/pieces/landing-1.wav"),
	preload("res://assets/audio/pieces/landing-2.wav"),
	preload("res://assets/audio/pieces/landing-3.wav"),
]
var impulse := AudioStreamPlayer.new()
var landing := AudioStreamPlayer.new()
var _random := RandomNumberGenerator.new()
var _enabled := true


func _init() -> void:
	name = "PieceSfx"
	impulse.name = "Impulse"
	landing.name = "Landing"
	impulse.stream = IMPULSE
	landing.max_polyphony = 2
	add_child(impulse)
	add_child(landing)


func setup(identity: String) -> void:
	_random.seed = (identity + ":sound").sha256_text().substr(0, 12).hex_to_int()


func _exit_tree() -> void:
	stop()


func set_enabled(value: bool) -> void:
	_enabled = value
	if not value:
		stop()


func stop() -> void:
	impulse.stop()
	landing.stop()


func play_impulse() -> void:
	if not _enabled or not is_inside_tree():
		return
	impulse.pitch_scale = _random.randf_range(0.96, 1.04)
	impulse.volume_db = -15.0
	impulse.play()
	played.emit(&"impulse")


func play_landing() -> void:
	if not _enabled or not is_inside_tree():
		return
	landing.stream = LANDINGS[_random.randi_range(0, LANDINGS.size() - 1)]
	landing.pitch_scale = _random.randf_range(0.96, 1.04)
	landing.volume_db = _random.randf_range(-15.0, -13.0)
	landing.play()
	played.emit(&"landing")
