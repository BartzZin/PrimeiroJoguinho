extends Control
## Persistent card views, fixed hover zones and captured mouse gestures.
signal card_selected(card: Dictionary)
signal drag_updated(point: Vector2)
signal card_dropped(card: Dictionary, point: Vector2)
signal interaction_cancelled
signal spell_resolved(definition_id: String, point: Vector2)

const HIT_BUTTON = preload("res://card_hit_button.gd")
const IDS = ["arcane_shield", "hidden_snare", "frost_bind", "dispel", "shield_break", "oracle_eye", "silence_seal", "arcane_focus", "ward", "trap_disarm", "temporal_boost", "arcane_draw"]
static var models = {}
static var faces = {}
var viewport: SubViewport
var camera: Camera3D
var holders = {}
var buttons = {}
var entries = {}
var order: Array = []
var poses = {}
var velocities = {}
var scale_velocities = {}
var rotation_velocities = {}
var rest_positions = {}
var projected_polygons = {}
var _draw_order: Array = []
var selected_id = ""
var state = "idle"
var retracted = false
var card_height = 320.0
var retract_distance = 0.0
var expanded_zone = Rect2()
var pointer = Vector2(-10000, -10000)
var press_point = Vector2.ZERO
var drag_point = Vector2.ZERO
var outside_ms = 0
var generation = 0
var snapshot_ids: Array = []
var snapshot_version = -1
var pending_request = ""
var accepted_version = -1
var resolution_count = 0
var resolve_elapsed = 0.0
var input_blocked: Callable
var animate_moves = true:
	set(value):
		animate_moves = value
		if not value and camera != null:
			_settle()

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	var surface = SubViewportContainer.new()
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	surface.stretch = true
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(surface)
	viewport = SubViewport.new()
	viewport.world_3d = World3D.new()
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	surface.add_child(viewport)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.position.z = 3000
	camera.far = 6000
	viewport.add_child(camera)
	var environment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("ced8ed")
	environment.environment.ambient_light_energy = 0.85
	environment.environment.sky = Sky.new()
	environment.environment.sky.sky_material = ProceduralSkyMaterial.new()
	viewport.add_child(environment)
	var light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-25, -25, 0)
	light.light_energy = 1.5
	viewport.add_child(light)
	resized.connect(_resized)
	get_window().focus_exited.connect(func(): cancel())
	get_window().size_changed.connect(func():
		if captured(): cancel()
	)
	arrange.call_deferred()

func redraw():
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func set_quality(index: int):
	viewport.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][index]
	redraw()

func busy() -> bool:
	return state in ["pressed", "dragging", "choosing", "pending", "resolving"]

func captured() -> bool:
	return state in ["pressed", "dragging", "choosing"]

func update_hand(hand: Array, definitions: Dictionary, can_cast: bool, mana: int, version: int = -1):
	snapshot_version = version
	snapshot_ids = hand.map(func(card): return str(card.instance_id))
	var new_order = snapshot_ids.duplicate()
	if state in ["pending", "resolving"] and holders.has(selected_id) and not new_order.has(selected_id):
		new_order.insert(clampi(order.find(selected_id), 0, new_order.size()), selected_id)
	var structural = new_order != order
	for id in holders.keys():
		if not new_order.has(id):
			holders[id].free()
			buttons[id].free()
			holders.erase(id)
			buttons.erase(id)
			entries.erase(id)
			velocities.erase(id)
			scale_velocities.erase(id)
			rotation_velocities.erase(id)
	for card in hand:
		var id = str(card.instance_id)
		var definition = definitions.get(card.definition_id, {"name": card.definition_id, "mana_cost": 0, "text": ""})
		var enabled = can_cast and mana >= int(definition.mana_cost)
		if not holders.has(id):
			_create(card, definition)
		var changed = entries[id].get("enabled") != enabled or entries[id].definition != definition
		entries[id] = {"card": card.duplicate(), "definition": definition.duplicate(), "enabled": enabled}
		if changed:
			_paint(id)
	order = new_order
	if structural:
		generation += 1
		arrange()
	if selected_id != "" and state not in ["pending", "resolving"] and (not snapshot_ids.has(selected_id) or not entries[selected_id].enabled):
		cancel()
	_try_resolve()

func _create(card: Dictionary, definition: Dictionary):
	var id = str(card.instance_id)
	var holder = Node3D.new()
	viewport.add_child(holder)
	var path = "res://assets/cards/models/card.glb"
	if not models.has(path):
		models[path] = load(path)
	var model = models[path].instantiate()
	holder.add_child(model)
	var face = model.find_child("Artwork", true, false)
	var image_path = "res://assets/cards/faces/" + card.definition_id + ".png"
	if not faces.has(image_path):
		faces[image_path] = load(image_path)
	var paint = ShaderMaterial.new()
	paint.shader = preload("res://assets/cards/face.gdshader")
	paint.set_shader_parameter("artwork", faces[image_path])
	face.material_override = paint
	var frame = model.find_child("GoldFrame", true, false)
	frame.material_override = frame.get_active_material(0).duplicate()
	holder.set_meta("frame", frame)
	_add_text(holder, "CardTitle", str(definition.name), Vector3(0, -0.405, 0.08), 40)
	_add_text(holder, "ManaCost", str(int(definition.mana_cost)), Vector3(-0.29, 0.55, 0.08), 48)
	holders[id] = holder
	holder.position = Vector3(0, -size.y, 0)
	holder.scale = Vector3.ONE * 0.01
	velocities[id] = Vector3.ZERO
	scale_velocities[id] = 0.0
	rotation_velocities[id] = Vector3.ZERO
	var button = HIT_BUTTON.new()
	button.name = "Card_" + id
	for mode in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(mode, StyleBoxEmpty.new())
	button.gui_input.connect(_button_input.bind(id))
	add_child(button)
	buttons[id] = button
	entries[id] = {"card": card.duplicate(), "definition": definition.duplicate()}

func _add_text(holder: Node3D, node_name: String, value: String, at: Vector3, font: int):
	var label = Label3D.new()
	label.name = node_name
	label.text = value
	label.font_size = font
	label.pixel_size = 0.0028
	label.outline_size = 5
	label.outline_modulate = Color("130a22")
	label.modulate = Color("fff4df")
	label.position = at
	if node_name == "CardTitle":
		label.width = 300
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	holder.add_child(label)

func _paint(id: String):
	var data = entries[id]
	var reserved = id == selected_id and state in ["pending", "resolving"]
	buttons[id].disabled = not data.get("enabled", false) or state in ["pending", "resolving", "choosing"]
	buttons[id].tooltip_text = str(data.definition.text)
	buttons[id].accessibility_name = str(data.definition.name) + ", " + str(int(data.definition.mana_cost)) + " mana. " + str(data.definition.text)
	holders[id].get_node("CardTitle").text = str(data.definition.name)
	holders[id].get_node("ManaCost").text = str(int(data.definition.mana_cost))
	for key in ["CardTitle", "ManaCost"]:
		holders[id].get_node(key).modulate = Color("fff4df") if data.get("enabled", false) or reserved else Color("aaa4bf")
	var face = holders[id].find_child("Artwork", true, false)
	face.material_override.set_shader_parameter("brightness", 1.0 if data.get("enabled", false) or reserved else 0.5)
	var frame = holders[id].get_meta("frame")
	frame.material_override.emission_enabled = id == selected_id
	frame.material_override.emission = Color("ae792c")
	frame.material_override.emission_energy_multiplier = 0.35
	redraw()

func _resized():
	if state in ["pressed", "dragging", "choosing"]:
		cancel()
	arrange()

func arrange():
	if camera == null or size.x <= 0 or size.y <= 0:
		return
	camera.size = size.y
	card_height = maxf(1, minf(320, minf(size.y * 0.65, (size.x - 48) / max(1, order.size()) / 0.8)))
	var slot = card_height * 0.8
	var top = size.y
	rest_positions.clear()
	for index in range(order.size()):
		var id = order[index]
		var normalized = (2.0 * index / (order.size() - 1) - 1) if order.size() > 1 else 0.0
		var angle = deg_to_rad(-8.0 * normalized)
		var half_height = card_height * (cos(angle) + 0.633 * absf(sin(angle))) / 2
		var center_y = size.y - 24 - half_height - 56 * (1 - normalized * normalized)
		rest_positions[id] = Vector3((index - (order.size() - 1) / 2.0) * slot, size.y / 2 - center_y, index)
		holders[id].set_meta("rest_rotation", Vector3(-0.06, -0.09, angle))
		top = minf(top, center_y - half_height - 40)
	retract_distance = maxf(0, size.y - 72 - top)
	var width = minf(size.x, order.size() * slot + 48)
	expanded_zone = Rect2((size.x - width) / 2, top - 24, width, size.y - top + 24)
	_retarget()

func _retarget():
	poses.clear()
	for id in order:
		var at = rest_positions[id]
		var factor = 1.06 if id == selected_id else (0.8 if selected_id != "" else 1.0)
		at.y += (26 if id == selected_id else 0) - (retract_distance if retracted else 0)
		at.z = 100 if id == selected_id else at.z
		var rotation = holders[id].get_meta("rest_rotation")
		var scale_value = card_height / 1.55 * factor
		if id == selected_id and state in ["dragging", "choosing", "pending", "resolving"]:
			var local = get_global_transform_with_canvas().affine_inverse() * drag_point
			var height = 220.0
			at = Vector3(local.x - size.x / 2 + height * 0.633 / 2 + 24, size.y / 2 - local.y + height / 2 + 24, 200)
			rotation = Vector3.ZERO
			scale_value = height / 1.55
			if state == "resolving":
				at = Vector3(local.x - size.x / 2, size.y / 2 - local.y, 200)
				scale_value = 0.01
		poses[id] = {"position": at, "rotation": rotation, "scale": scale_value}
		_paint(id)
	if not animate_moves:
		_settle()
	set_process(true)

func _settle():
	for id in poses:
		holders[id].position = poses[id].position
		holders[id].rotation = poses[id].rotation
		holders[id].scale = Vector3.ONE * poses[id].scale
		velocities[id] = Vector3.ZERO
		scale_velocities[id] = 0.0
		rotation_velocities[id] = Vector3.ZERO
	_update_hits()
	redraw()

func _spring(value, target, velocity, delta):
	var omega = 22.0
	var offset = value - target
	var temporary = (velocity + omega * offset) * delta
	var decay = exp(-omega * delta)
	return [target + (offset + temporary) * decay, (velocity - omega * temporary) * decay]

func _process(delta):
	var dirty = false
	var moving = false
	if outside_ms > 0 and not busy() and selected_id == "" and Time.get_ticks_msec() - outside_ms >= 250:
		outside_ms = 0
		retracted = true
		_retarget()
	if state == "resolving":
		resolve_elapsed += delta
		for mesh in holders[selected_id].find_children("*", "GeometryInstance3D", true, false):
			mesh.transparency = minf(1, resolve_elapsed / 0.24)
		dirty = true
		if resolve_elapsed >= (0.24 if animate_moves else 0.0):
			_finish_resolution()
	for id in poses:
		if not animate_moves:
			continue
		var holder = holders[id]
		var pose = poses[id]
		if holder.position.distance_to(pose.position) < 0.03 and absf(holder.scale.x - pose.scale) < 0.003 and holder.rotation.distance_to(pose.rotation) < 0.0001:
			continue
		var position_result = _spring(holder.position, pose.position, velocities[id], minf(delta, 0.05))
		var scale_result = _spring(holder.scale.x, pose.scale, scale_velocities[id], minf(delta, 0.05))
		var rotation_result = _spring(holder.rotation, pose.rotation, rotation_velocities[id], minf(delta, 0.05))
		holder.position = position_result[0]
		velocities[id] = position_result[1]
		holder.scale = Vector3.ONE * scale_result[0]
		scale_velocities[id] = scale_result[1]
		holder.rotation = rotation_result[0]
		rotation_velocities[id] = rotation_result[1]
		dirty = true
		moving = true
	if dirty:
		_update_hits()
		redraw()
	if not moving and state != "resolving" and outside_ms == 0:
		set_process(false)
	if state == "returning" and not moving:
		state = "idle"

func _update_hits():
	projected_polygons.clear()
	for id in order:
		var polygon = PackedVector2Array()
		for corner in [Vector3(-0.49, 0.775, 0.08), Vector3(0.49, 0.775, 0.08), Vector3(0.49, -0.775, 0.08), Vector3(-0.49, -0.775, 0.08)]:
			polygon.append(camera.unproject_position(holders[id].to_global(corner)))
		projected_polygons[id] = polygon
		var bounds = Rect2(polygon[0], Vector2.ZERO)
		for point in polygon:
			bounds = bounds.expand(point)
		buttons[id].position = bounds.position
		buttons[id].size = bounds.size
		var local_polygon = PackedVector2Array()
		for point in polygon:
			local_polygon.append(point - bounds.position)
		buttons[id].polygon = local_polygon
	var desired = order.duplicate()
	if desired.has(selected_id):
		desired.erase(selected_id)
		desired.append(selected_id)
	if desired != _draw_order:
		for id in desired: move_child(buttons[id], get_child_count() - 1)
		_draw_order = desired

func activation_strip() -> Rect2:
	return Rect2(expanded_zone.position.x, size.y - 72, expanded_zone.size.x, 72)

func select(id: String):
	if state in ["pending", "resolving"]:
		return
	if id == "":
		cancel()
		return
	if not entries.has(id) or not entries[id].get("enabled", false):
		return
	selected_id = id
	state = "selected"
	retracted = false
	outside_ms = 0
	_retarget()

func cancel():
	if state in ["pending", "resolving"]:
		return
	var had_interaction = selected_id != ""
	selected_id = ""
	state = "returning"
	retracted = false
	outside_ms = 0
	_retarget()
	if had_interaction:
		interaction_cancelled.emit()

func reset():
	pending_request = ""
	state = "idle"
	selected_id = ""
	update_hand([], {}, false, 0)

func _button_input(event, id: String):
	if busy() or (input_blocked.is_valid() and input_blocked.call()) or not entries[id].get("enabled", false):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		select(id)
		state = "pressed"
		press_point = buttons[id].get_global_transform_with_canvas() * event.position
		drag_point = press_point
		card_selected.emit(entries[id].card)
		buttons[id].accept_event()
	elif event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER, KEY_SPACE]:
		select(id)
		card_selected.emit(entries[id].card)
		buttons[id].accept_event()

func _input(event):
	if input_blocked.is_valid() and input_blocked.call():
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and selected_id != "" and state not in ["pending", "resolving"]:
		cancel()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and selected_id != "" and state not in ["pending", "resolving"]:
		cancel()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		pointer = get_global_transform_with_canvas().affine_inverse() * event.position
		if state in ["pressed", "dragging"]:
			if state == "pressed" and event.position.distance_to(press_point) >= 8:
				state = "dragging"
				retracted = true
			if state == "dragging":
				drag_point = event.position
				_retarget()
				drag_updated.emit(drag_point)
			get_viewport().set_input_as_handled()
			return
		if busy() or selected_id != "":
			return
		if activation_strip().has_point(pointer):
			outside_ms = 0
			if retracted:
				retracted = false
				_retarget()
		elif expanded_zone.has_point(pointer) or not Rect2(Vector2.ZERO, size).has_point(pointer):
			outside_ms = 0
		elif not retracted and outside_ms == 0:
			outside_ms = Time.get_ticks_msec()
			set_process(true)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and state in ["pressed", "dragging"]:
		if state == "dragging":
			state = "choosing"
			drag_point = event.position
			card_dropped.emit(entries[selected_id].card, drag_point)
		else:
			state = "selected"
		get_viewport().set_input_as_handled()

func reserve(request_id: String):
	pending_request = request_id
	accepted_version = -1
	state = "pending"
	_retarget()

func receipt(request_id: String, accepted: bool, version: int):
	if request_id != pending_request or state != "pending":
		return
	if not accepted:
		pending_request = ""
		state = "selected"
		if not snapshot_ids.has(selected_id):
			var definitions = {}
			for data in entries.values(): definitions[data.card.definition_id] = data.definition
			update_hand(snapshot_ids.map(func(id): return entries[id].card), definitions, false, 0, snapshot_version)
		cancel()
		return
	accepted_version = version
	_try_resolve()

func _try_resolve():
	if state == "pending" and accepted_version >= 0 and snapshot_version >= accepted_version and not snapshot_ids.has(selected_id):
		state = "resolving"
		resolve_elapsed = 0
		resolution_count += 1
		spell_resolved.emit(entries[selected_id].card.definition_id, drag_point)
		_retarget()

func _finish_resolution():
	var id = selected_id
	holders[id].free()
	buttons[id].free()
	holders.erase(id)
	buttons.erase(id)
	entries.erase(id)
	velocities.erase(id)
	scale_velocities.erase(id)
	rotation_velocities.erase(id)
	order.erase(id)
	poses.erase(id)
	selected_id = ""
	pending_request = ""
	accepted_version = -1
	state = "idle"
	retracted = false
	arrange()
	interaction_cancelled.emit()
