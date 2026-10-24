extends RefCounted
## Inspection changes only presentation; leaving it restores the exact playing view.

var inspecting = false
var saved_transform = Transform3D.IDENTITY
var pitch = 0.0
var yaw = 0.0


func enter(camera: Camera3D):
	if inspecting:
		return
	saved_transform = camera.transform
	pitch = camera.rotation.x
	yaw = camera.rotation.y
	inspecting = true


func leave(camera: Camera3D):
	if not inspecting:
		return
	inspecting = false
	camera.transform = saved_transform


func look(camera: Camera3D, relative: Vector2):
	yaw -= relative.x * 0.004
	pitch = clampf(pitch - relative.y * 0.004, deg_to_rad(-85), deg_to_rad(85))
	camera.rotation = Vector3(pitch, yaw, 0)
