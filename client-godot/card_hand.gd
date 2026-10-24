extends Control
## One independent 3D world for the whole hand; only authorized cards enter here.

signal card_selected(card: Dictionary)

const HIT_BUTTON = preload("res://card_hit_button.gd")

const IDS = ["arcane_shield", "hidden_snare", "frost_bind", "dispel", "shield_break", "oracle_eye", "silence_seal", "arcane_focus", "ward", "trap_disarm", "temporal_boost", "arcane_draw"]
static var models = {}
static var faces = {}
var viewport: SubViewport
var camera: Camera3D
var holders = {}
var buttons = {}
var selected_id = ""
var retracted = false
var card_height = 320.0
var rest_positions = {}
var projected_polygons = {}
var retract_distance = 0.0
var signature = ""
var animate_moves = true:
	set(value):
		if animate_moves == value:
			return
		animate_moves = value
		if not value and tween != null:
			tween.kill()
			arrange()
var generation = 0
var tween: Tween


func _ready():
	custom_minimum_size = Vector2.ZERO
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	camera.size = 900
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
	resized.connect(arrange)
	arrange.call_deferred()


func set_quality(index: int):
	if viewport != null:
		viewport.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][index]
		redraw()


func redraw():
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func update_hand(hand: Array, definitions: Dictionary, can_cast: bool, mana: int):
	var fingerprint = JSON.stringify([hand, definitions, can_cast, mana])
	if fingerprint == signature:
		return
	signature = fingerprint
	generation += 1
	if tween != null:
		tween.kill()
	for holder in holders.values():
		holder.free()
	for control in buttons.values():
		control.free()
	holders.clear()
	buttons.clear()
	for card in hand:
		var id = str(card.instance_id)
		var definition = definitions.get(card.definition_id, {"name": card.definition_id, "mana_cost": 0, "text": ""})
		var holder = Node3D.new()
		holder.rotation = Vector3(-0.06, -0.09, 0)
		viewport.add_child(holder)
		var path = "res://assets/cards/models/card.glb"
		if not models.has(path):
			models[path] = load(path)
		if models[path] is PackedScene:
			var model = models[path].instantiate()
			holder.add_child(model)
			var face = model.find_child("Artwork", true, false)
			if face is MeshInstance3D:
				var image_path = "res://assets/cards/faces/" + card.definition_id + ".png"
				if not faces.has(image_path):
					faces[image_path] = load(image_path)
				var paint = ShaderMaterial.new()
				paint.shader = preload("res://assets/cards/face.gdshader")
				paint.set_shader_parameter("artwork", faces[image_path])
				face.material_override = paint
		holder.set_meta("outline", add_outline(holder))
		holders[id] = holder
		var control = HIT_BUTTON.new()
		control.name = "Card_" + id
		var title = add_text(holder, "CardTitle", str(definition.name), Vector3(0, -0.405, 0.08), 40)
		title.width = 300
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_text(holder, "ManaCost", str(int(definition.mana_cost)), Vector3(-0.29, 0.55, 0.08), 48)
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			control.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		control.tooltip_text = str(definition.text)
		control.accessibility_name = str(definition.name) + ", " + str(int(definition.mana_cost)) + " mana. " + control.tooltip_text
		control.disabled = not can_cast or mana < int(definition.mana_cost)
		control.pressed.connect(func(): card_selected.emit(card))
		add_child(control)
		buttons[id] = control
		# Dim unavailable cards without touching imported texture/material resources.
		if control.disabled:
			for text_node in ["CardTitle", "ManaCost"]:
				holder.get_node(text_node).modulate = Color("aaa4bf")
			tint_meshes(holder, Color(0.48, 0.48, 0.58))
			var face = holder.find_child("Artwork", true, false)
			if face is MeshInstance3D and face.material_override is ShaderMaterial:
				face.material_override.set_shader_parameter("brightness", 0.5)
	if not holders.has(selected_id):
		selected_id = ""
		retracted = false
	arrange()


func tint_meshes(node: Node, tint: Color):
	if node is MeshInstance3D:
		for surface in range(node.mesh.get_surface_count()):
			var source = node.get_active_material(surface)
			if source is StandardMaterial3D:
				var paint = source.duplicate()
				paint.albedo_color *= tint
				node.set_surface_override_material(surface, paint)
	for child in node.get_children():
		tint_meshes(child, tint)


func add_outline(holder: Node3D) -> Node3D:
	var outline = Node3D.new()
	var paint = StandardMaterial3D.new()
	paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	paint.albedo_color = Color("d4b0ff")
	for edge in [Vector4(-0.49, 0, 0.025, 1.55), Vector4(0.49, 0, 0.025, 1.55), Vector4(0, -0.775, 0.98, 0.025), Vector4(0, 0.775, 0.98, 0.025)]:
		var mesh = MeshInstance3D.new()
		mesh.mesh = BoxMesh.new()
		mesh.mesh.size = Vector3(edge.z, edge.w, 0.015)
		mesh.position = Vector3(edge.x, edge.y, -0.09)
		mesh.material_override = paint
		outline.add_child(mesh)
	holder.add_child(outline)
	outline.visible = false
	return outline


func add_text(holder: Node3D, node_name: String, value: String, at: Vector3, font: int) -> Label3D:
	var label = Label3D.new()
	label.name = node_name
	label.text = value
	label.font_size = font
	label.pixel_size = 0.0028
	label.outline_size = 5
	label.outline_modulate = Color("130a22")
	label.modulate = Color("fff4df")
	label.position = at
	holder.add_child(label)
	return label


func arrange():
	if camera == null or size.x <= 0 or size.y <= 0:
		return
	if tween != null:
		tween.kill()
	camera.size = size.y
	var count = max(1, holders.size())
	card_height = maxf(1, minf(320, minf(size.y * 0.65, (size.x - 48) / count / 0.8)))
	var slot = card_height * 0.8
	var index = 0
	rest_positions.clear()
	var top = size.y
	for id in holders:
		var normalized = (2.0 * index / (count - 1) - 1.0) if count > 1 else 0.0
		var angle = deg_to_rad(-8.0 * normalized)
		var half_height = card_height * (cos(angle) + 0.633 * absf(sin(angle))) / 2.0
		var center_y = size.y - 24 - half_height - 56 * (1 - normalized * normalized)
		holders[id].rotation = Vector3(-0.06, -0.09, angle)
		holders[id].scale = Vector3.ONE * card_height / 1.55
		rest_positions[id] = Vector3((index - (count - 1) / 2.0) * slot, size.y / 2.0 - center_y, index)
		top = minf(top, center_y - half_height - (26 if id == selected_id else 0))
		index += 1
	retract_distance = maxf(0, size.y - 72 - top)
	apply_positions(target_positions())


func target_positions() -> Dictionary:
	var result = {}
	for id in holders:
		var at = rest_positions.get(id, holders[id].position)
		at.y += (26 if id == selected_id else 0) - (retract_distance if retracted else 0)
		at.z = 100 if id == selected_id else at.z
		result[id] = at
	return result


func apply_positions(positions: Dictionary):
	for id in positions:
		holders[id].position = positions[id]
		holders[id].get_meta("outline").visible = id == selected_id
	update_hit_shapes()
	redraw()


func update_hit_shapes():
	projected_polygons.clear()
	for id in holders:
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
		move_child(buttons[id], get_child_count() - 1)
	if buttons.has(selected_id):
		move_child(buttons[selected_id], get_child_count() - 1)


func transition():
	if tween != null:
		tween.kill()
	var targets = target_positions()
	if not animate_moves or not is_visible_in_tree() or holders.is_empty():
		apply_positions(targets)
		return
	var starts = {}
	for id in holders:
		starts[id] = holders[id].position
	tween = create_tween()
	tween.tween_method(func(weight):
		var positions = {}
		for id in targets:
			positions[id] = starts[id].lerp(targets[id], weight)
		apply_positions(positions)
	, 0.0, 1.0, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.finished.connect(redraw)


func select(id: String):
	if id == selected_id and not (id == "" and retracted):
		return
	selected_id = id
	retracted = false
	# Recompute the 72px reveal for the newly elevated card.
	var top = size.y
	for key in holders:
		var height = card_height * (cos(holders[key].rotation.z) + 0.633 * absf(sin(holders[key].rotation.z)))
		top = minf(top, size.y / 2 - rest_positions.get(key, holders[key].position).y - height / 2 - (26 if key == id else 0))
	retract_distance = maxf(0, size.y - 72 - top)
	transition()


func activation_strip() -> Rect2:
	var width = minf(size.x, maxf(1, holders.size()) * card_height * 0.8)
	return Rect2((size.x - width) / 2, size.y - 72, width, 72)


func _input(event):
	if not event is InputEventMouseMotion or holders.is_empty() or not is_visible_in_tree():
		return
	var point = get_global_transform_with_canvas().affine_inverse() * event.position
	if not Rect2(Vector2.ZERO, size).has_point(point):
		return
	var over_card = false
	for polygon in projected_polygons.values():
		if Rect2(Vector2.ZERO, size).has_point(point) and Geometry2D.is_point_in_polygon(point, polygon):
			over_card = true
	var should_retract = retracted
	if retracted:
		if activation_strip().has_point(point):
			should_retract = false
	elif not over_card and not activation_strip().has_point(point):
		should_retract = true
	if should_retract != retracted:
		retracted = should_retract
		transition()
