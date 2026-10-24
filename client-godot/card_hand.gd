extends Control
## One independent 3D world for the whole hand; only authorized cards enter here.

signal card_selected(card: Dictionary)

const IDS = ["arcane_shield", "hidden_snare", "frost_bind", "dispel", "shield_break", "oracle_eye", "silence_seal", "arcane_focus", "ward", "trap_disarm", "temporal_boost", "arcane_draw"]
static var models = {}
static var faces = {}
var viewport: SubViewport
var camera: Camera3D
var holders = {}
var buttons = {}
var selected_id = ""
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
	custom_minimum_size = Vector2(0, 220)
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
	camera.size = 2.35
	camera.position.z = 6
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
		var control = Button.new()
		control.name = "Card_" + id
		var caption = Label.new()
		caption.text = str(definition.name) + "\n" + str(int(definition.mana_cost)) + " MANA"
		caption.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		caption.add_theme_font_size_override("font_size", 15)
		caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		control.add_child(caption)
		control.add_theme_font_size_override("font_size", 15)
		control.add_theme_color_override("font_color", Color("e8e5f8"))
		control.add_theme_color_override("font_disabled_color", Color("9397ab"))
		for state in ["normal", "hover", "pressed", "disabled"]:
			control.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		var focus = StyleBoxFlat.new()
		focus.bg_color = Color.TRANSPARENT
		focus.border_color = Color("c7a7ff")
		focus.set_border_width_all(2)
		focus.set_corner_radius_all(8)
		control.add_theme_stylebox_override("focus", focus)
		control.tooltip_text = str(definition.text)
		control.accessibility_name = caption.text + ". " + control.tooltip_text
		control.disabled = not can_cast or mana < int(definition.mana_cost)
		control.pressed.connect(func(): card_selected.emit(card))
		add_child(control)
		buttons[id] = control
		# Dim unavailable cards without touching imported texture/material resources.
		if control.disabled:
			caption.modulate = Color("9397ab")
			tint_meshes(holder, Color(0.48, 0.48, 0.58))
			var face = holder.find_child("Artwork", true, false)
			if face is MeshInstance3D and face.material_override is ShaderMaterial:
				face.material_override.set_shader_parameter("brightness", 0.5)
	if not holders.has(selected_id):
		selected_id = ""
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


func arrange():
	if camera == null or size.x <= 0 or size.y <= 0:
		return
	var slot = minf(200, size.x / maxf(1, holders.size()))
	var start = (size.x - slot * holders.size()) / 2
	var unit = camera.size / size.y
	var index = 0
	for id in holders:
		var control = buttons[id]
		control.position = Vector2(start + index * slot + 4, 10)
		control.size = Vector2(maxf(1, slot - 8), size.y - 12)
		holders[id].position = Vector3((start + (index + 0.5) * slot - size.x / 2) * unit, 0.14 + (0.14 if id == selected_id else 0), 0)
		var scale_value = minf(1, (slot - 14) * unit / 1.05)
		holders[id].scale = Vector3.ONE * scale_value
		holders[id].get_meta("outline").visible = id == selected_id
		index += 1
	redraw()


func select(id: String):
	if id == selected_id:
		return
	selected_id = id
	if tween != null:
		tween.kill()
	if not animate_moves:
		arrange()
		return
	tween = create_tween().set_parallel(true)
	for key in holders:
		holders[key].get_meta("outline").visible = key == id
		tween.tween_property(holders[key], "position:y", 0.14 + (0.14 if key == id else 0), 0.16)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	tween.finished.connect(redraw)
