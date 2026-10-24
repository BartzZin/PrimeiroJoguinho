extends Control

const NAMES = {"p": "Peão", "r": "Torre", "n": "Cavalo", "b": "Bispo", "q": "Dama", "k": "Rei"}
const BoardPiecesPresenter = preload("res://board_pieces_presenter.gd")
const BOARD_FRAME = preload("res://assets/board/frame.glb")
const STONE_SHADER = preload("res://assets/board/stone.gdshader")
const DIAGNOSTICS = preload("res://diagnostics.gd")
const PREFERENCES = preload("res://preferences.gd")
const SETTINGS_MENU = preload("res://settings_menu.gd")
const CARD_HAND = preload("res://card_hand.gd")
const CARD_TARGETS = preload("res://card_targets.gd")
const ARENA = preload("res://arena_environment.gd")
const ARENA_CAMERA = preload("res://arena_camera.gd")
const GRAPHICS = preload("res://graphics_profile.gd")
const CONNECTION_TIMEOUT_MS = 10000
const RETRY_DELAYS_MS = [2000, 4000, 8000]
const EFFECT_NAMES = {"shield": "escudo", "frozen": "imobilização", "ward": "proteção rúnica", "silence": "silêncio"}
var server_field: LineEdit
var invite_field: LineEdit
var nickname_field: LineEdit
var room_field: LineEdit
var status_label: Label
var info_label: Label
var clocks_label: Label
var target_label: Label
var cards_row: Control
var card_drag_point = Vector2.ZERO
var card_drop_queued = false
var card_drag_active = false
var card_preview_square = ""
var card_preview_valid = false
var card_effect_popup: Control
var card_effect_square = ""
var history_box: VBoxContainer
var effects_box: VBoxContainer
var catalogue: RichTextLabel
var stage: SubViewportContainer
var viewport: SubViewport
var camera: Camera3D
var board_root: Node3D
var pieces_root: BoardPiecesPresenter
var socket = WebSocketPeer.new()
var session = {}
var snapshot = {}
var cards = {}
var match_id = ""
var waiting_room = ""
var selected_square = ""
var selected_card = {}
var selected_target = {}
var pending = {}
var connection_state = "idle"
var connection_generation = 0
var connection_attempt = 0
var connection_deadline = 0
var retry_at = 0
var awaiting_refresh = false
var connection_label: Label
var gear_button: Button
var sidebar_button: Button
var sidebar_scroll: ScrollContainer
var settings_menu: Control
var diagnostics: Logger
var preferences = PREFERENCES.new()
var queued_picks: Array[Vector2] = []
var rendered_version = -1
var room_polling = false
var refresh_in_progress = false
var token_deadline = 0
var profile = "default"
var top_view = false
var animate_moves: bool = true:
	set(value):
		animate_moves = value
		if is_instance_valid(pieces_root):
			pieces_root.set_animations_enabled(value)
		if is_instance_valid(cards_row):
			cards_row.animate_moves = value
		if is_instance_valid(arena):
			arena.animation_enabled = value
var camera_yaw = 0.0
var camera_pitch = 0.36
var camera_distance = 12.8
var connected_match_id = ""
var directional_light: DirectionalLight3D
var stage_environment: Environment
var arena: Node3D
var inspection = ARENA_CAMERA.new()
var inspection_bar: HBoxContainer
var graphics_level = 2
var fps_label: Label
var next_fps_update = 0
var tile_material_cache = {}
var game_hud: PanelContainer
var hud_title: Label


func _ready():
	Engine.max_fps = 60
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--profile="):
			profile = argument.trim_prefix("--profile=").validate_filename()
	diagnostics = DIAGNOSTICS.new()
	diagnostics.setup(profile)
	OS.add_logger(diagnostics)
	var preference_error = preferences.load_profile(profile)
	diagnostics.detailed = preferences.values.detailed_logs
	if preference_error != OK:
		log_event("ERROR", "preferences_load_failed", {"code": error_string(preference_error)})
	build_ui()
	build_stage()
	apply_preferences()
	log_event("INFO", "client_started", {"pid": OS.get_process_id(), "version": ProjectSettings.get_setting("application/config/version", "0.1.0")})
	var timer = Timer.new()
	timer.wait_time = 2
	timer.timeout.connect(poll_room)
	add_child(timer)
	timer.start()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--smoke="):
			await smoke_test(argument.trim_prefix("--smoke="))
			return
		elif argument.begins_with("--bootstrap="):
			var data = consume_bootstrap(argument.trim_prefix("--bootstrap="))
			if not data.is_empty():
				server_field.text = data.server
				save_session(data.session)
				match_id = data.match_id
				connect_match()
				await load_catalogue()
			return
	var config = ConfigFile.new()
	if config.load("user://session_" + profile + ".cfg") == OK:
		server_field.text = config.get_value("session", "server", server_field.text)
		session["refresh_token"] = config.get_value("session", "refresh_token", "")
		await refresh_session()
	await load_catalogue()


func consume_bootstrap(path):
	var file = FileAccess.open(path, FileAccess.READ)
	if file != null:
		var parser = JSON.new()
		var result = parser.parse(file.get_as_text())
		file.close()
		DirAccess.remove_absolute(path)
		if result == OK and parser.data is Dictionary:
			var data = parser.data
			if data.get("session") is Dictionary and data.session.get("access_token") is String and data.session.get("refresh_token") is String and data.get("server") is String and data.get("match_id") is String:
				return data
	log_event("ERROR", "bootstrap_invalid")
	set_connection_state("failed")
	set_status("Não foi possível ler os dados de abertura. Abra Jogar.cmd novamente.")
	return {}


func _exit_tree():
	socket.close()
	if diagnostics != null:
		OS.remove_logger(diagnostics)
		diagnostics.close()


func log_event(level, event, fields = {}):
	if diagnostics != null:
		diagnostics.record(level, event, fields)


func set_status(text_value):
	status_label.text = text_value
	status_label.tooltip_text = text_value


func apply_preferences():
	apply_sidebar_visibility(preferences.values.sidebar_visible)
	animate_moves = preferences.values.animations
	pieces_root.set_sounds_enabled(preferences.values.sound_effects)
	top_view = preferences.values.top_view
	set_graphics_quality(preferences.values.quality)
	fps_label.visible = preferences.values.show_fps
	arena.animation_enabled = animate_moves
	position_camera()
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if preferences.values.fullscreen else DisplayServer.WINDOW_MODE_MAXIMIZED)


func change_setting(key, value):
	preferences.values[key] = value
	if key == "sidebar_visible":
		apply_sidebar_visibility(value)
	elif key == "detailed_logs":
		if diagnostics != null:
			if not value:
				log_event("INFO", "detailed_logging_disabled")
			diagnostics.detailed = value
			if value:
				log_event("INFO", "detailed_logging_enabled")
	elif key in ["quality", "render_scale", "shadows"]:
		set_graphics_quality(preferences.values.quality)
	elif key == "show_fps":
		fps_label.visible = value
	elif key == "animations":
		animate_moves = value
		arena.animation_enabled = value
	elif key == "sound_effects":
		pieces_root.set_sounds_enabled(value)
	elif key == "top_view":
		if inspection.inspecting:
			toggle_inspection()
		top_view = value
		position_camera()
	elif key == "fullscreen" and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if value else DisplayServer.WINDOW_MODE_MAXIMIZED)
	if preferences.path != "" and preferences.save() != OK:
		log_event("ERROR", "preferences_save_failed")
	settings_menu.present(preferences.values)


func apply_sidebar_visibility(value: bool):
	queued_picks.clear()
	sidebar_scroll.visible = value
	sidebar_button.set_pressed_no_signal(value)
	sidebar_button.tooltip_text = "Ocultar barra lateral" if value else "Mostrar barra lateral"
	sidebar_button.accessibility_name = sidebar_button.tooltip_text
	if value:
		sidebar_scroll.set_deferred("scroll_vertical", sidebar_scroll.get_meta("saved_scroll", 0))


func toggle_sidebar(value: bool):
	if not value:
		sidebar_scroll.set_meta("saved_scroll", sidebar_scroll.scroll_vertical)
	change_setting("sidebar_visible", value)


func open_logs_folder():
	if diagnostics == null or not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(diagnostics.directory)):
		set_status("Não foi possível gravar logs. Verifique a permissão da pasta de dados do jogo.")
		return
	var result = OS.shell_open(ProjectSettings.globalize_path(diagnostics.directory))
	if result != OK:
		log_event("ERROR", "open_logs_failed", {"code": error_string(result)})
		set_status("Não foi possível abrir a pasta de logs.")


func label(text_value, parent, size_value = 20):
	var control = Label.new()
	control.text = text_value
	control.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	control.add_theme_font_size_override("font_size", size_value)
	parent.add_child(control)
	return control


func button(text_value, parent, action):
	var control = Button.new()
	control.text = text_value
	control.custom_minimum_size.y = 44
	control.add_theme_font_size_override("font_size", 19)
	control.pressed.connect(action)
	parent.add_child(control)
	return control


func field(placeholder, parent, initial = ""):
	var control = LineEdit.new()
	control.placeholder_text = placeholder
	control.text = initial
	control.custom_minimum_size.y = 44
	control.add_theme_font_size_override("font_size", 19)
	parent.add_child(control)
	return control


func build_ui():
	apply_ui_theme()
	var background = ColorRect.new()
	background.color = Color("0a1121")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 20)
	add_child(margin)
	var outer = VBoxContainer.new()
	margin.add_child(outer)
	var layout = HBoxContainer.new()
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_theme_constant_override("separation", 16)
	outer.add_child(layout)
	var main_column = VBoxContainer.new()
	main_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(main_column)
	stage = SubViewportContainer.new()
	stage.stretch = true
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.custom_minimum_size = Vector2(500, 340)
	main_column.add_child(stage)
	stage.gui_input.connect(board_input)
	stage.resized.connect(func(): queued_picks.clear(); layout_hand_overlay.call_deferred())
	stage.item_rect_changed.connect(func(): layout_hand_overlay.call_deferred())
	viewport = SubViewport.new()
	viewport.size = Vector2i(900, 650)
	viewport.world_3d = World3D.new()
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	stage.add_child(viewport)
	game_hud = PanelContainer.new()
	game_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hud_style = StyleBoxFlat.new()
	hud_style.bg_color = Color(0.025,0.045,0.075,0.88)
	hud_style.border_color = Color(0.66,0.49,0.24,0.6)
	hud_style.set_border_width_all(1)
	hud_style.set_corner_radius_all(8)
	hud_style.set_content_margin_all(12)
	game_hud.add_theme_stylebox_override("panel",hud_style)
	var hud_rows = VBoxContainer.new()
	hud_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game_hud.add_child(hud_rows)
	var hud_heading = HBoxContainer.new()
	hud_heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_heading.add_theme_constant_override("separation",24)
	hud_rows.add_child(hud_heading)
	hud_title = label("XADREZ ARCANO",hud_heading,18)
	hud_title.modulate = Color("d9c391")
	hud_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	hud_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clocks_label = label("SOLAR · AZUL  10:00     •     LUNAR · VERMELHO  10:00",hud_heading,20)
	clocks_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	clocks_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	clocks_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clocks_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_label = label("Entre com um convite ou abra o tutorial pelo menu ☰.",hud_rows,16)
	info_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	info_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(game_hud)
	cards_row = CARD_HAND.new()
	cards_row.card_selected.connect(select_card)
	cards_row.drag_updated.connect(_card_drag_updated)
	cards_row.card_dropped.connect(_card_dropped)
	cards_row.interaction_cancelled.connect(_card_cancelled)
	cards_row.spell_resolved.connect(_card_resolved)
	cards_row.input_blocked = func(): return inspection.inspecting or is_instance_valid(settings_menu) and settings_menu.visible or is_instance_valid(card_effect_popup) and card_effect_popup.visible
	add_child(cards_row)
	var scroll = ScrollContainer.new()
	sidebar_scroll = scroll
	scroll.visible = preferences.values.sidebar_visible
	scroll.custom_minimum_size.x = 350
	layout.add_child(scroll)
	var sidebar = VBoxContainer.new()
	sidebar.custom_minimum_size.x = 330
	sidebar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(sidebar)
	label("CONEXÃO", sidebar, 20)
	server_field = field("Servidor HTTPS", sidebar, "http://127.0.0.1:8000")
	nickname_field = field("Seu nome", sidebar, "Jogador")
	invite_field = field("Convite de acesso (uso único)", sidebar)
	invite_field.secret = true
	button("Entrar com convite", sidebar, login)
	button("Renovar sessão", sidebar, refresh_session)
	label("SALA PRIVADA", sidebar, 20)
	room_field = field("Código da sala", sidebar)
	button("Criar sala", sidebar, create_room)
	button("Copiar código", sidebar, func(): DisplayServer.clipboard_set(room_field.text))
	button("Entrar na sala", sidebar, join_room)
	button("Reconectar partida", sidebar, connect_match)
	label("TUTORIAL GUIADO", sidebar, 20)
	for lesson in ["movement", "shield", "trap"]:
		var titles = {"movement": "1. Movimento", "shield": "2. Defesa mágica", "trap": "3. Armadilha"}
		button(titles[lesson], sidebar, start_tutorial.bind(lesson))
	label("AÇÃO SELECIONADA", sidebar, 20)
	target_label = label("Selecione uma peça ou carta.", sidebar)
	label("Segure uma carta, arraste ao tabuleiro e solte para usar.", sidebar, 16)
	button("Cancelar seleção", sidebar, clear_selection)
	effects_box = VBoxContainer.new()
	sidebar.add_child(effects_box)
	button("Oferecer empate", sidebar, send_command.bind("draw.offer", {}))
	button("Aceitar empate", sidebar, send_command.bind("draw.respond", {"accept": true}))
	button("Recusar empate", sidebar, send_command.bind("draw.respond", {"accept": false}))
	button("Desistir…", sidebar, confirm_resign)
	label("HISTÓRICO", sidebar, 20)
	button("Minhas partidas", sidebar, load_matches)
	button("Eventos desta partida", sidebar, load_history)
	history_box = VBoxContainer.new()
	sidebar.add_child(history_box)
	label("CATÁLOGO • 12 CARTAS", sidebar, 20)
	catalogue = RichTextLabel.new()
	catalogue.bbcode_enabled = true
	catalogue.custom_minimum_size.y = 270
	sidebar.add_child(catalogue)
	label("Alpha: sem repetição e regras de 50/75 lances. Empate material apenas rei contra rei.", sidebar, 14)
	var footer = HBoxContainer.new()
	footer.custom_minimum_size.y = 44
	footer.add_theme_constant_override("separation", 16)
	outer.add_child(footer)
	connection_label = label("Sem partida", footer, 16)
	connection_label.custom_minimum_size.x = 150
	status_label = label("Pronto. O servidor confirma todas as ações.", footer, 16)
	status_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fps_label = label("FPS —", footer, 14)
	fps_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	fps_label.custom_minimum_size.x = 132
	fps_label.tooltip_text = "Taxa e intervalo médio dos quadros; não é latência de rede."
	fps_label.visible = preferences.values.show_fps
	sidebar_button = Button.new()
	sidebar_button.name = "SidebarToggle"
	sidebar_button.custom_minimum_size = Vector2(44, 44)
	sidebar_button.toggle_mode = true
	sidebar_button.icon = preload("res://assets/ui/menu.svg")
	sidebar_button.expand_icon = true
	sidebar_button.add_theme_constant_override("icon_max_width", 24)
	sidebar_button.toggled.connect(toggle_sidebar)
	footer.add_child(sidebar_button)
	apply_sidebar_visibility(preferences.values.sidebar_visible)
	gear_button = button("", footer, func(): settings_menu.toggle(preferences.values))
	gear_button.name = "SettingsGear"
	gear_button.custom_minimum_size = Vector2(44, 44)
	gear_button.icon = preload("res://assets/ui/gear.svg")
	gear_button.expand_icon = true
	gear_button.add_theme_constant_override("icon_max_width", 24)
	gear_button.tooltip_text = "Configurações gerais"
	gear_button.accessibility_name = "Configurações gerais"
	settings_menu = SETTINGS_MENU.new()
	settings_menu.anchor_button = gear_button
	settings_menu.setting_changed.connect(change_setting)
	settings_menu.open_logs_requested.connect(open_logs_folder)
	settings_menu.inspection_requested.connect(toggle_inspection)
	settings_menu.graphics_report_requested.connect(copy_graphics_report)
	inspection_bar = HBoxContainer.new()
	inspection_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	inspection_bar.size = Vector2(650,44)
	inspection_bar.add_theme_constant_override("separation", 12)
	var inspection_hint = label("INSPEÇÃO • botão direito para olhar", inspection_bar, 17)
	inspection_hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	inspection_hint.add_theme_color_override("font_shadow_color", Color("071327"))
	inspection_hint.add_theme_constant_override("shadow_offset_x", 1)
	inspection_hint.add_theme_constant_override("shadow_offset_y", 1)
	button("Voltar ao tabuleiro (I)", inspection_bar, toggle_inspection)
	inspection_bar.hide()
	add_child(inspection_bar)
	add_child(settings_menu)
	layout_hand_overlay.call_deferred()


func layout_hand_overlay():
	if is_instance_valid(cards_row) and is_instance_valid(stage):
		cards_row.position = get_global_transform().affine_inverse() * stage.global_position
		cards_row.size = stage.size
		if is_instance_valid(game_hud):
			var hud_width = minf(stage.size.x-32,1120)
			game_hud.position = cards_row.position + Vector2((stage.size.x-hud_width)/2,12)
			game_hud.size = Vector2(hud_width,76)
			hud_title.visible = stage.size.x >= 900
			clocks_label.add_theme_font_size_override("font_size",20 if stage.size.x > 1000 else 14)
		if is_instance_valid(inspection_bar):
			inspection_bar.position = cards_row.position + Vector2(12, 100)
			inspection_bar.get_child(0).visible = stage.size.x > 760
			inspection_bar.size = Vector2(minf(stage.size.x-24,650),44)


func apply_ui_theme():
	theme = Theme.new()
	theme.default_font_size = 20
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style = StyleBoxFlat.new()
		style.bg_color = Color({"normal": "142137", "hover": "233854", "pressed": "304564", "disabled": "101a2b"}[state])
		style.border_color = Color("344861")
		style.set_border_width_all(1)
		style.set_corner_radius_all(7)
		style.content_margin_left = 12
		style.content_margin_right = 12
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		theme.set_stylebox(state, "Button", style)
		if state == "normal":
			theme.set_stylebox(state, "LineEdit", style.duplicate())
	theme.set_color("font_color", "Button", Color("e1eaf5"))
	theme.set_color("font_disabled_color", "Button", Color("7789a3"))
	theme.set_color("font_color", "LineEdit", Color("e1eaf5"))
	var focus = StyleBoxFlat.new()
	focus.bg_color = Color(0, 0, 0, 0)
	focus.border_color = Color("c4a76d")
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(7)
	theme.set_stylebox("focus", "Button", focus)
	theme.set_stylebox("focus", "LineEdit", focus)


func material(color_value, metal = 0.0, roughness = 0.65):
	var result = StandardMaterial3D.new()
	result.albedo_color = color_value
	result.roughness = roughness
	result.metallic = metal
	return result


func build_stage():
	arena = ARENA.new()
	arena.quality_level = GRAPHICS.resolve(preferences.values.quality,RenderingServer.get_video_adapter_name())
	var world = WorldEnvironment.new()
	world.environment = Environment.new()
	stage_environment = world.environment
	world.environment.ssao_enabled = true
	world.environment.ssao_radius = 0.2
	world.environment.ssao_intensity = 1.5
	arena.configure_environment(world.environment)
	viewport.add_child(world)
	var light = DirectionalLight3D.new()
	directional_light = light
	light.basis = Basis.looking_at(-ARENA.SUN_DIRECTION, Vector3.UP)
	light.light_energy = 1.1
	light.light_color = Color("fff1d8")
	light.shadow_enabled = true
	light.directional_shadow_max_distance = 30
	light.shadow_bias = 0.025
	light.shadow_normal_bias = 0.18
	light.light_angular_distance = 0.7
	viewport.add_child(light)
	var fill = DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-40, 155, 0)
	fill.light_color = Color("c5dbff")
	fill.light_energy = 0.07
	viewport.add_child(fill)
	camera = Camera3D.new()
	camera.fov = 55
	camera.far = 260
	viewport.add_child(camera)
	position_camera()
	board_root = Node3D.new()
	viewport.add_child(board_root)
	viewport.add_child(BOARD_FRAME.instantiate())
	viewport.add_child(arena)
	for rank in range(8):
		for file in range(8):
			var name_value = "abcdefgh"[file] + str(rank + 1)
			var body = StaticBody3D.new()
			body.collision_layer = 1
			body.collision_mask = 0
			body.set_meta("square", name_value)
			body.position = world_square(name_value)
			var mesh = MeshInstance3D.new()
			mesh.layers = 2
			mesh.mesh = BoxMesh.new()
			mesh.mesh.size = Vector3(0.995, 0.18, 0.995)
			mesh.material_override = tile_material(Color("a8b5bc") if (file + rank) % 2 else Color("23354a"))
			body.add_child(mesh)
			var collision = CollisionShape3D.new()
			collision.shape = BoxShape3D.new()
			collision.shape.size = Vector3(1, 0.3, 1)
			body.add_child(collision)
			board_root.add_child(body)
	pieces_root = BoardPiecesPresenter.new()
	pieces_root.setup(world_square)
	pieces_root.set_animations_enabled(animate_moves)
	viewport.add_child(pieces_root)
	for index in range(8):
		for edge in [-1, 1]:
			add_coordinate("abcdefgh"[index], Vector3(index - 3.5, 0.025, edge * 4.15), 0 if edge == 1 else PI)
			add_coordinate(str(index + 1), Vector3(edge * 4.15, 0.025, 3.5 - index), PI / 2 if edge == -1 else -PI / 2)


func add_box(size_value, position_value, paint):
	var mesh = MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.mesh.size = size_value
	mesh.position = position_value
	mesh.material_override = paint
	viewport.add_child(mesh)


func tile_material(color_value, highlighted = false):
	var key = str(color_value) + str(highlighted)
	if tile_material_cache.has(key):
		return tile_material_cache[key]
	var result = ShaderMaterial.new()
	result.shader = STONE_SHADER
	result.set_shader_parameter("stone_color", color_value)
	result.set_shader_parameter("highlight", 1.0 if highlighted else 0.0)
	result.set_shader_parameter("stone_map",preload("res://assets/arena/limestone.png"))
	tile_material_cache[key] = result
	return result


func set_graphics_quality(index):
	graphics_level = GRAPHICS.resolve(index, RenderingServer.get_video_adapter_name())
	var config = GRAPHICS.configuration(graphics_level, preferences.values.render_scale)
	cards_row.set_quality(graphics_level)
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if RenderingServer.get_current_rendering_method() == "forward_plus" else Viewport.SCALING_3D_MODE_BILINEAR
	viewport.scaling_3d_scale = config.scale
	viewport.fsr_sharpness = 0.3
	viewport.msaa_3d = Viewport.MSAA_4X if graphics_level == 2 else Viewport.MSAA_2X
	viewport.mesh_lod_threshold = config.lod
	viewport.texture_mipmap_bias = [0.35,0.15,0.0][graphics_level]
	viewport.anisotropic_filtering_level = [Viewport.ANISOTROPY_2X,Viewport.ANISOTROPY_4X,Viewport.ANISOTROPY_8X][graphics_level]
	RenderingServer.directional_shadow_atlas_set_size(config.shadow_size, false)
	directional_light.shadow_enabled = preferences.values.shadows
	directional_light.directional_shadow_max_distance = config.shadow_distance
	directional_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if graphics_level == 2 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	directional_light.directional_shadow_split_1 = 0.4 if graphics_level == 0 else 0.15
	directional_light.shadow_bias = [0.08,0.05,0.025][graphics_level]
	directional_light.shadow_normal_bias = [1.0,0.65,0.25][graphics_level]
	var advanced = RenderingServer.get_current_rendering_method() == "forward_plus"
	stage_environment.ssao_enabled = config.ssao and advanced
	stage_environment.ssil_enabled = config.ssil and advanced
	stage_environment.ssao_radius = 0.6
	stage_environment.ssao_intensity = 1.6
	stage_environment.ssil_intensity = 0.7
	if is_instance_valid(arena):
		arena.set_quality(graphics_level)


func add_coordinate(text_value, position_value, yaw):
	var coordinate = Label3D.new()
	coordinate.text = text_value
	coordinate.position = position_value
	coordinate.rotation = Vector3(-PI / 2, yaw, 0)
	coordinate.font_size = 52
	coordinate.pixel_size = 0.004
	coordinate.modulate = Color("ead6a8")
	coordinate.outline_size = 4
	viewport.add_child(coordinate)


func toggle_fullscreen():
	var mode = DisplayServer.window_get_mode()
	change_setting("fullscreen", mode not in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN])


func _unhandled_key_input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and settings_menu.visible:
			settings_menu.hide()
			get_viewport().set_input_as_handled()
			return
		if get_viewport().gui_get_focus_owner() is LineEdit and event.keycode in [KEY_I, KEY_HOME]:
			return
		if event.keycode == KEY_I or event.keycode == KEY_ESCAPE and inspection.inspecting:
			toggle_inspection()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_HOME:
			reset_camera()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_F11:
			cards_row.cancel()
			_close_card_effects()
			toggle_fullscreen()
		elif event.keycode == KEY_ESCAPE and DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]:
			change_setting("fullscreen", false)


func position_camera():
	if inspection.inspecting:
		return
	var reverse = -1.0 if snapshot.get("viewer_side", "white") == "black" else 1.0
	if top_view:
		camera.position = Vector3(0, 13, 0.01 * reverse)
	else:
		camera.position = Vector3(sin(camera_yaw) * cos(camera_pitch), sin(camera_pitch), cos(camera_yaw) * cos(camera_pitch) * reverse) * camera_distance
	camera.look_at(Vector3.ZERO if top_view else Vector3(0, 0, 0.65 * reverse))


func toggle_inspection():
	settings_menu.hide()
	queued_picks.clear()
	card_drop_queued = false
	card_drag_active = false
	cards_row.cancel()
	_close_card_effects()
	if inspection.inspecting:
		inspection.leave(camera)
	else:
		inspection.enter(camera)
	inspection_bar.visible = inspection.inspecting
	cards_row.visible = not inspection.inspecting
	settings_menu.set_inspection(inspection.inspecting)
	log_event("INFO", "camera_inspection", {"status": "on" if inspection.inspecting else "off"})


func reset_camera():
	if inspection.inspecting:
		toggle_inspection()
	queued_picks.clear()
	cards_row.cancel()
	camera_yaw = 0.0
	camera_pitch = 0.36
	camera_distance = 12.8
	position_camera()


func graphics_report() -> Dictionary:
	return {"version":ProjectSettings.get_setting("application/config/version"),"gpu":RenderingServer.get_video_adapter_name(),
		"renderer":RenderingServer.get_current_rendering_method(),"quality":graphics_level,
		"system_ram_gib":snappedf(float(OS.get_memory_info().get("physical",0))/1073741824.0,0.1),
		"render_scale":viewport.scaling_3d_scale,"viewport":str(viewport.size),"fps":Engine.get_frames_per_second(),
		"renderer_video_mib":snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)/1048576.0,0.1)}


func copy_graphics_report():
	DisplayServer.clipboard_set(JSON.stringify(graphics_report(),"\t"))
	set_status("Diagnóstico gráfico copiado. Inclui GPU, perfil, resolução e FPS; nenhum dado da partida.")


func world_square(value):
	return Vector3("abcdefgh".find(value[0]) - 3.5, 0, 3.5 - (int(value[1]) - 1))


func api(method, path, body = {}):
	var result = await api_result(method, path, body)
	return result.data if result.ok else {}


func safe_route(path):
	var parts = path.split("/")
	if parts.size() > 3 and parts[2] in ["rooms", "matches", "ws"]:
		parts[3] = "{id}"
	return "/".join(parts)


func api_result(method, path, body = {}):
	var base = server_field.text.trim_suffix("/")
	if not (base.begins_with("https://") or base.begins_with("http://127.0.0.1:") or base.begins_with("http://localhost:")):
		set_status("Use HTTPS para servidores externos.")
		log_event("ERROR", "http_invalid_server")
		return {"ok": false, "data": {}, "status": 0}
	var request = HTTPRequest.new()
	request.timeout = 10
	add_child(request)
	var headers = PackedStringArray(["Content-Type: application/json"])
	if session.has("access_token"):
		headers.append("Authorization: Bearer " + session.access_token)
	var started = Time.get_ticks_msec()
	log_event("INFO", "http_started", {"stage": safe_route(path)})
	var error = request.request(base + path, headers, method, JSON.stringify(body) if method != HTTPClient.METHOD_GET else "")
	if error != OK:
		request.queue_free()
		set_status("Não foi possível iniciar a conexão com o servidor.")
		log_event("ERROR", "http_start_failed", {"stage": safe_route(path), "code": error_string(error)})
		return {"ok": false, "data": {}, "status": 0}
	var response = await request.request_completed
	request.queue_free()
	var parser = JSON.new()
	var parse_error = parser.parse(response[3].get_string_from_utf8())
	var parsed = parser.data if parse_error == OK else null
	var ok = response[0] == HTTPRequest.RESULT_SUCCESS and response[1] >= 200 and response[1] < 300 and parsed != null
	var code = "HTTP_%d" % response[1] if response[1] else "SERVER_UNREACHABLE"
	if parsed is Dictionary and parsed.get("code") is String:
		code = parsed.code
	log_event("INFO" if ok else "ERROR", "http_completed" if ok else "http_failed", {"stage": safe_route(path), "status": response[1], "code": "OK" if ok else code, "duration_ms": Time.get_ticks_msec() - started})
	if not ok:
		set_status("Falha ao acessar o servidor: " + code + ".")
	return {"ok": ok, "data": parsed if ok else {}, "status": response[1]}


func save_session(data):
	session = data
	token_deadline = Time.get_ticks_msec() + int(data.get("expires_in", 1800)) * 1000
	var config = ConfigFile.new()
	config.set_value("session", "server", server_field.text)
	config.set_value("session", "refresh_token", session.refresh_token)
	if config.save("user://session_" + profile + ".cfg") != OK:
		log_event("ERROR", "session_save_failed")
	if match_id == "":
		set_status("Sessão autenticada. Crie uma sala ou inicie um tutorial.")


func login():
	var data = await api(HTTPClient.METHOD_POST, "/v1/auth/invite", {"invite": invite_field.text, "nickname": nickname_field.text})
	if data.has("access_token"):
		save_session(data)
		invite_field.text = ""
		await load_catalogue()


func refresh_session(reopen_socket = true):
	if refresh_in_progress or not session.has("refresh_token"):
		return false
	refresh_in_progress = true
	var token = session.refresh_token
	var generation = connection_generation
	var result = await api_result(HTTPClient.METHOD_POST, "/v1/auth/refresh", {"refresh_token": token})
	refresh_in_progress = false
	# Refresh tokens rotate on the server. Keep the new token for the same
	# session even if the user changed matches while the request was in flight.
	if session.get("refresh_token") != token:
		return false
	if result.ok and result.data.has("access_token"):
		save_session(result.data)
		if reopen_socket and generation == connection_generation and connection_state == "connected":
			connect_match()
		return true
	if result.status == 401:
		session.clear()
		_connection_failed("AUTHENTICATION_EXPIRED", 0, true)
		set_status("Sua sessão expirou. Entre novamente com um convite.")
	else:
		token_deadline = Time.get_ticks_msec() + 90000
	return false


func load_catalogue():
	var data = await api(HTTPClient.METHOD_GET, "/v1/cards")
	if data is Array:
		catalogue.text = ""
		for card in data:
			cards[card.id] = card
			catalogue.append_text("[b]" + card.name + " • " + str(card.mana_cost) + " mana[/b]\n" + card.text + "\n\n")
		if not snapshot.is_empty():
			render_snapshot()


func create_room():
	var data = await api(HTTPClient.METHOD_POST, "/v1/rooms")
	if data.has("code"):
		waiting_room = data.code
		room_field.text = data.code
		status_label.text = "Sala criada. Compartilhe o código com outro convidado."


func poll_room():
	if waiting_room == "" or room_polling:
		return
	room_polling = true
	var data = await api(HTTPClient.METHOD_GET, "/v1/rooms/" + waiting_room)
	room_polling = false
	if data.get("match_id") != null:
		waiting_room = ""
		match_id = data.match_id
		connect_match()


func join_room():
	var data = await api(HTTPClient.METHOD_POST, "/v1/rooms/" + room_field.text.strip_edges() + "/join")
	if data.has("match_id"):
		match_id = data.match_id
		waiting_room = ""
		connect_match()


func start_tutorial(scenario):
	var data = await api(HTTPClient.METHOD_POST, "/v1/tutorials/" + scenario + "/start")
	if data.has("match_id"):
		match_id = data.match_id
		waiting_room = ""
		info_label.text = data.text
		connect_match()


func connect_match():
	connection_generation += 1
	connection_attempt = 0
	retry_at = 0
	awaiting_refresh = false
	queued_picks.clear()
	if match_id == "" or not session.has("access_token"):
		set_connection_state("failed")
		set_status("Entre com um convite e selecione uma partida primeiro.")
		return
	var address = server_field.text
	if not (address.begins_with("https://") or address.begins_with("http://127.0.0.1:") or address.begins_with("http://localhost:")):
		set_connection_state("failed")
		set_status("Use HTTPS para servidores externos.")
		return
	if connected_match_id != match_id:
		if inspection.inspecting:
			toggle_inspection()
		cards_row.reset()
		_card_cancelled()
		pending.clear()
		snapshot.clear()
		pieces_root.clear()
		connected_match_id = match_id
	_begin_connection()


func set_connection_state(value):
	connection_state = value
	if is_instance_valid(pieces_root):
		pieces_root.set_active(value == "connected" and snapshot.get("status") == "active")
	if value != "connected" and is_instance_valid(cards_row):
		cards_row.cancel()
	connection_label.text = {"idle": "Sem partida", "connecting": "Conectando", "connected": "Conectado", "reconnecting": "Reconectando", "failed": "Falha na conexão"}[value]
	connection_label.modulate = Color("70d7b2") if value == "connected" else (Color("ef9b9b") if value == "failed" else Color("d9c18d"))


func _begin_connection():
	socket.close()
	socket = WebSocketPeer.new()
	socket.handshake_headers = PackedStringArray(["Authorization: Bearer " + session.access_token])
	var base = server_field.text.trim_suffix("/").replace("https://", "wss://").replace("http://", "ws://")
	set_connection_state("connecting" if connection_attempt == 0 else "reconnecting")
	set_status("Conectando à partida…" if connection_attempt == 0 else "Reconectando à partida (%d/3)…" % connection_attempt)
	log_event("INFO", "connection_started", {"match_id": match_id, "attempt": connection_attempt})
	connection_deadline = Time.get_ticks_msec() + CONNECTION_TIMEOUT_MS
	var error = socket.connect_to_url(base + "/v1/ws/match/" + match_id)
	rendered_version = -1
	if error != OK:
		_connection_failed(error_string(error))


func _connection_failed(reason, close_code = 0, terminal = false):
	log_event("ERROR", "connection_failed", {"match_id": match_id, "reason": reason, "close_code": close_code, "attempt": connection_attempt})
	socket.close()
	connection_deadline = 0
	queued_picks.clear()
	if not terminal and connection_attempt < RETRY_DELAYS_MS.size():
		retry_at = Time.get_ticks_msec() + RETRY_DELAYS_MS[connection_attempt]
		connection_attempt += 1
		set_connection_state("reconnecting")
		set_status("Conexão interrompida; relógio continua. Nova tentativa em %d s (%d/3)." % [RETRY_DELAYS_MS[connection_attempt - 1] / 1000, connection_attempt])
	else:
		retry_at = 0
		set_connection_state("failed")
		set_status("Falha na conexão. Verifique o servidor e use Reconectar partida.")


func _retry_connection():
	awaiting_refresh = true
	var generation = connection_generation
	if session.has("refresh_token"):
		await refresh_session(false)
	if generation != connection_generation:
		return
	awaiting_refresh = false
	if connection_state == "failed":
		return
	if not session.has("access_token"):
		_connection_failed("NOT_AUTHENTICATED", 0, true)
		return
	_begin_connection()


func _process(_delta):
	if is_instance_valid(fps_label) and fps_label.visible and Time.get_ticks_msec() >= next_fps_update:
		var fps = Engine.get_frames_per_second()
		fps_label.text = "%d FPS • %.1f ms" % [fps, 1000.0/fps] if fps > 0 else "FPS —"
		next_fps_update = Time.get_ticks_msec()+250
	socket.poll()
	var now = Time.get_ticks_msec()
	if session.has("access_token") and now > token_deadline - 60000 and not refresh_in_progress and not awaiting_refresh and connection_state not in ["connecting", "reconnecting", "failed"]:
		refresh_session()
	if retry_at > 0:
		if now >= retry_at and not refresh_in_progress:
			retry_at = 0
			_retry_connection()
		return
	if awaiting_refresh or connection_state in ["idle", "failed"]:
		return
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		while socket.get_available_packet_count() > 0:
			var parser = JSON.new()
			if parser.parse(socket.get_packet().get_string_from_utf8()) == OK and parser.data is Dictionary:
				handle_message(parser.data)
			else:
				_connection_failed("INVALID_SERVER_MESSAGE")
				return
		if connection_state == "connected":
			for key in pending:
				if now - pending[key].sent_at > 5000:
					log_event("INFO", "command_replayed", {"request_id": key, "kind": pending[key].command.type})
					socket.send_text(JSON.stringify(pending[key].command))
					pending[key].sent_at = now
	elif socket.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		_connection_failed("SOCKET_CLOSED", socket.get_close_code())
		return
	check_connection_timeout(now)


func check_connection_timeout(now):
	if connection_deadline > 0 and now >= connection_deadline:
		_connection_failed("INITIAL_SNAPSHOT_TIMEOUT")


func handle_message(data):
	var message_type = data.get("type", "")
	if message_type == "match.snapshot":
		if data.get("match_id") != match_id:
			log_event("INFO", "stale_snapshot_ignored")
			return
		if not valid_snapshot(data):
			_connection_failed("INVALID_SNAPSHOT")
			return
		if data.state_version < rendered_version:
			return
		var first_snapshot = connection_state != "connected"
		snapshot = data
		set_connection_state("connected")
		connection_deadline = 0
		retry_at = 0
		connection_attempt = 0
		if first_snapshot:
			set_status("Partida conectada. Você joga com as peças " + ("azuis." if data.viewer_side == "white" else "vermelhas."))
			log_event("INFO", "connection_ready", {"match_id": match_id, "version": data.state_version, "side": data.viewer_side})
			for key in pending:
				pending[key].sent_at = Time.get_ticks_msec() - 5001
		var clocks = data.clock_ms
		clocks_label.text = "SOLAR · AZUL  %s     •     LUNAR · VERMELHO  %s" % [clock_text(clocks.white), clock_text(clocks.black)]
		if first_snapshot or data.state_version != rendered_version:
			rendered_version = data.state_version
			render_snapshot(not first_snapshot)
	elif message_type == "clock.sync" and data.get("snapshot") is Dictionary:
		handle_message(data.snapshot)
	elif message_type in ["command.accepted", "command.rejected"]:
		var request_id = data.get("request_id", "")
		var elapsed = Time.get_ticks_msec() - pending.get(request_id, {}).get("created_at", Time.get_ticks_msec())
		cards_row.receipt(request_id, message_type == "command.accepted", int(data.get("state_version", -1)))
		pending.erase(request_id)
		if message_type == "command.rejected" and request_id == "":
			cards_row.receipt(cards_row.pending_request, false, int(data.get("state_version", -1)))
			pending.clear()
		log_event("ERROR" if message_type == "command.rejected" else "INFO", message_type, {"request_id": request_id, "code": data.get("code", "OK"), "duration_ms": elapsed})
		if message_type == "command.rejected":
			set_status("Ação recusada: " + data.get("code", "INVALID_PAYLOAD"))
		else:
			set_status("Ação confirmada pelo servidor.")


func valid_snapshot(data):
	if data.get("viewer_side") not in ["white", "black"] or data.get("active_side") not in ["white", "black"]:
		return false
	if not (data.get("state_version") is float or data.get("state_version") is int) or not data.get("clock_ms") is Dictionary:
		return false
	for side in ["white", "black"]:
		if not (data.clock_ms.get(side) is float or data.clock_ms.get(side) is int):
			return false
	for key in ["pieces", "public_effects", "my_hand", "legal_moves"]:
		if not data.get(key) is Array:
			return false
	for key in ["my_mana", "opponent_mana", "opponent_hand_count", "my_deck_count"]:
		if not (data.get(key) is float or data.get(key) is int):
			return false
	for key in ["status", "tutorial", "draw_offer", "can_cast"]:
		if not data.has(key):
			return false
	if data.status not in ["active", "finished", "voided"] or not data.can_cast is bool:
		return false
	if data.state_version < 0 or (data.status != "active" and (not data.has("result_reason") or not data.has("winner"))):
		return false
	for piece in data.pieces:
		if not piece is Dictionary or not piece.get("id") is String or piece.get("kind") not in NAMES or piece.get("side") not in ["white", "black"] or not valid_square(piece.get("square")):
			return false
	for card in data.my_hand:
		if not card is Dictionary or not card.get("instance_id") is String or not card.get("definition_id") is String or not card.definition_id.is_valid_identifier():
			return false
	for effect in data.public_effects:
		if not effect is Dictionary or not effect.get("id") is String or not effect.get("kind") is String:
			return false
	for move in data.legal_moves:
		if not move is String or move.length() not in [4, 5] or not valid_square(move.substr(0, 2)) or not valid_square(move.substr(2, 2)):
			return false
	for key in ["my_traps", "revealed_traps"]:
		if not data.get(key, []) is Array:
			return false
		for trap in data.get(key, []):
			if not trap is Dictionary or not valid_square(trap.get("square")):
				return false
	return true


func valid_square(value):
	return value is String and value.length() == 2 and value[0] in "abcdefgh" and value[1] in "12345678"


func clock_text(milliseconds):
	var seconds = int(ceil(milliseconds / 1000.0))
	return "%02d:%02d" % [seconds / 60, seconds % 60]


func send_command(kind, payload):
	if snapshot.is_empty() or connection_state != "connected" or socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		status_label.text = "Conecte a uma partida primeiro."
		return
	if not pending.is_empty():
		status_label.text = "Aguardando confirmação da ação anterior."
		return
	var request_id = Crypto.new().generate_random_bytes(16).hex_encode()
	var command = {"type": kind, "request_id": request_id, "match_id": match_id,
		"protocol_version": 1, "expected_version": int(snapshot.state_version), "payload": payload}
	pending[request_id] = {"command": command, "sent_at": Time.get_ticks_msec(), "created_at": Time.get_ticks_msec()}
	log_event("INFO", "command_sent", {"match_id": match_id, "request_id": request_id, "kind": kind, "version": snapshot.state_version})
	var error = socket.send_text(JSON.stringify(command))
	if error != OK:
		_connection_failed(error_string(error))
	return request_id


func render_snapshot(animate_transition: bool = true):
	position_camera()
	pieces_root.set_active(connection_state == "connected" and snapshot.get("status") == "active")
	pieces_root.synchronize(snapshot.pieces, snapshot.public_effects, animate_transition and connection_state == "connected")
	cards_row.animate_moves = animate_moves
	cards_row.update_hand(snapshot.my_hand, cards, snapshot.get("can_cast", false), int(snapshot.my_mana), int(snapshot.get("state_version", -1)))
	if snapshot.tutorial == null:
		info_label.text = "%s • Sua mana %s/5 • Rival %s/5 • Mão rival %s • Baralho %s" % ["Sua vez" if snapshot.active_side == snapshot.viewer_side else "Vez do adversário", int(snapshot.my_mana), int(snapshot.opponent_mana), int(snapshot.opponent_hand_count), int(snapshot.my_deck_count)]
	if snapshot.status != "active":
		info_label.text = "Partida encerrada: " + str(snapshot.result_reason) + " • Vencedor: " + str(snapshot.winner)
	elif snapshot.draw_offer != null:
		status_label.text = "Oferta de empate pendente de " + str(snapshot.draw_offer)
	if card_effect_popup != null and card_effect_popup.visible:
		var current = CARD_TARGETS.resolve(snapshot, selected_card.get("definition_id", ""), card_effect_square)
		if not current.valid or current.effects.map(func(effect): return effect.id) != card_effect_popup.option_ids:
			_close_card_effects()
			cards_row.cancel()
	clear_board_selection()


func clear_selection():
	cards_row.cancel()
	_card_cancelled()
	clear_board_selection()


func clear_board_selection():
	selected_square = ""
	if selected_card.is_empty():
		target_label.text = "Segure e arraste uma carta ao tabuleiro."
	for child in effects_box.get_children():
		child.queue_free()
	update_tiles()


func update_tiles():
	for tile in board_root.get_children():
		var pos = tile.get_meta("square")
		var file = "abcdefgh".find(pos[0])
		var rank = int(pos[1]) - 1
		var color_value = Color("a8b5bc") if (file + rank) % 2 else Color("23354a")
		for trap in snapshot.get("my_traps", []):
			if trap.square == pos:
				color_value = Color("257e78")
		for trap in snapshot.get("revealed_traps", []):
			if trap.square == pos:
				color_value = Color("bb5471")
		for move in snapshot.get("legal_moves", []):
			if selected_square != "" and move.substr(0, 2) == selected_square and move.substr(2, 2) == pos:
				color_value = Color("4a936b")
		if pos == selected_square:
			color_value = Color("d3aa45")
		if pos == card_preview_square:
			color_value = Color("67e5c0") if card_preview_valid else Color("ef6666")
		tile.get_child(0).material_override = tile_material(color_value, pos == selected_square)


func board_input(event):
	if settings_menu.visible or is_instance_valid(card_effect_popup) and card_effect_popup.visible:
		return
	if inspection.inspecting:
		if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			inspection.look(camera, event.relative)
		return
	if card_drag_active or cards_row.busy():
		return
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
		camera_yaw -= event.relative.x * 0.005
		camera_pitch = clamp(camera_pitch + event.relative.y * 0.005, 0.32, 1.45)
		position_camera()
	if not event is InputEventMouseButton or not event.pressed:
		return
	if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		camera_distance = clamp(camera_distance + (-0.5 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 0.5), 8, 20)
		position_camera()
		return
	if event.button_index != MOUSE_BUTTON_LEFT or snapshot.is_empty() or connection_state != "connected" or settings_menu.visible:
		return
	if stage.size.x > 0 and stage.size.y > 0:
		queued_picks.append(event.position * Vector2(viewport.size) / stage.size)


func _physics_process(_delta):
	if inspection.inspecting:
		queued_picks.clear()
		return
	if card_drag_active or card_drop_queued:
		_process_card_pick()
		queued_picks.clear()
		return
	if queued_picks.is_empty():
		return
	if not is_instance_valid(camera) or not camera.is_inside_tree() or connection_state != "connected" or settings_menu.visible:
		queued_picks.clear()
		return
	var world = camera.get_world_3d()
	if world == null or world.direct_space_state == null:
		queued_picks.clear()
		log_event("ERROR", "board_world_unavailable")
		set_status("O tabuleiro ainda está carregando. Aguarde e tente novamente.")
		return
	while not queued_picks.is_empty():
		var point = queued_picks.pop_front()
		var origin = camera.project_ray_origin(point)
		var query = PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(point) * 100, 1)
		var hit = world.direct_space_state.intersect_ray(query)
		if not hit.is_empty() and hit.collider.has_meta("square"):
			var square = hit.collider.get_meta("square")
			log_event("INFO", "board_selected", {"square": square})
			click_square(square)


func click_square(pos):
	var piece = {}
	for candidate in snapshot.pieces:
		if candidate.square == pos:
			piece = candidate
	if not selected_card.is_empty():
		clear_selection()
	var possible = []
	for move in snapshot.get("legal_moves", []):
		if move.begins_with(selected_square + pos) and selected_square != "":
			possible.append(move)
	if not possible.is_empty():
		if possible[0].length() == 5:
			choose_promotion(selected_square, pos)
		else:
			send_command("move.request", {"from": selected_square, "to": pos})
		return
	selected_square = pos
	target_label.text = pos + (" • " + NAMES[piece.kind] if not piece.is_empty() else " • casa vazia")
	update_tiles()


func choose_promotion(origin, target):
	var dialog = AcceptDialog.new()
	dialog.title = "Escolha a promoção"
	dialog.dialog_text = "A escolha é obrigatória; o relógio continua."
	var row = HBoxContainer.new()
	dialog.add_child(row)
	for kind in ["q", "r", "b", "n"]:
		button(NAMES[kind], row, func(): send_command("move.request", {"from": origin, "to": target, "promotion": kind}); dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered(Vector2i(430, 150))


func select_card(card):
	clear_board_selection()
	selected_card = card
	selected_target = {}
	target_label.text = cards.get(card.definition_id, {"name": card.definition_id}).name + ": arraste ao tabuleiro para usar."


func _card_drag_updated(point: Vector2):
	card_drag_point = point
	card_drag_active = true


func _card_dropped(_card, point: Vector2):
	card_drag_point = point
	card_drop_queued = true
	card_drag_active = false


func _card_cancelled():
	card_drag_active = false
	card_drop_queued = false
	card_preview_square = ""
	selected_card = {}
	selected_target = {}
	_close_card_effects()
	if is_instance_valid(target_label):
		target_label.text = "Segure e arraste uma carta ao tabuleiro."
	if is_instance_valid(board_root):
		update_tiles()


func _close_card_effects():
	if is_instance_valid(card_effect_popup):
		var popup = card_effect_popup
		card_effect_popup = null
		popup.hide()
		popup.queue_free()


func _process_card_pick():
	var drop = card_drop_queued
	card_drop_queued = false
	var square = ""
	var local = stage.get_global_transform_with_canvas().affine_inverse() * card_drag_point
	if connection_state == "connected" and not settings_menu.visible and Rect2(Vector2.ZERO, stage.size).has_point(local):
		var world = camera.get_world_3d()
		if world != null and world.direct_space_state != null:
			var point = local * Vector2(viewport.size) / stage.size
			var origin = camera.project_ray_origin(point)
			var hit = world.direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(point) * 100, 1))
			if not hit.is_empty(): square = hit.collider.get_meta("square", "")
	var result = CARD_TARGETS.resolve(snapshot, selected_card.get("definition_id", ""), square)
	if card_preview_square != square or card_preview_valid != result.valid:
		card_preview_square = square
		card_preview_valid = result.valid
		update_tiles()
	if not drop:
		return
	if not result.valid or selected_card.is_empty() or not pending.is_empty():
		cards_row.cancel()
		set_status("Solte a carta em um alvo válido do tabuleiro.")
		return
	if result.effects.size() > 1:
		card_effect_square = square
		card_effect_popup = preload("res://card_effect_menu.gd").new()
		card_effect_popup.chosen.connect(_choose_card_effect)
		card_effect_popup.cancelled.connect(func(): _close_card_effects(); cards_row.cancel())
		add_child(card_effect_popup)
		card_effect_popup.present(result.effects, get_global_transform_with_canvas().affine_inverse() * card_drag_point)
		return
	_submit_card(result.target)


func _choose_card_effect(id: String):
	var result = CARD_TARGETS.resolve(snapshot, selected_card.get("definition_id", ""), card_effect_square)
	var found = result.effects.any(func(effect): return effect.id == id)
	_close_card_effects()
	if not found:
		cards_row.cancel()
		return
	_submit_card({"effect_id": id})


func _submit_card(target: Dictionary):
	var request_id = send_command("spell.request", {"card_instance_id": selected_card.instance_id, "target": target})
	if request_id == null or str(request_id) == "":
		cards_row.cancel()
		return
	cards_row.reserve(str(request_id))
	card_preview_square = ""
	update_tiles()
	set_status("Ativando carta; aguardando confirmação…")


func _card_resolved(definition: String, point: Vector2):
	# This signal only belongs to this player's pending command. Hidden targets stay local.
	if inspection.inspecting:
		return
	var local = stage.get_global_transform_with_canvas().affine_inverse() * point
	var origin = camera.project_ray_origin(local * Vector2(viewport.size) / stage.size)
	var direction = camera.project_ray_normal(local * Vector2(viewport.size) / stage.size)
	if absf(direction.y) < 0.001: return
	var position_value = origin + direction * (-origin.y / direction.y)
	var ring = MeshInstance3D.new()
	ring.layers = 2
	ring.mesh = TorusMesh.new()
	ring.mesh.inner_radius = 0.29
	ring.mesh.outer_radius = 0.34
	ring.position = position_value + Vector3(0, 0.15, 0)
	var paint = StandardMaterial3D.new()
	paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	paint.albedo_color = Color("83e8ff") if definition == "frost_bind" else Color("e5bc69")
	ring.material_override = paint
	viewport.add_child(ring)
	var effect_tween = create_tween()
	if animate_moves:
		effect_tween.tween_property(ring, "scale", Vector3.ONE * 1.8, 0.25)
	else:
		effect_tween.tween_interval(0.12)
	effect_tween.tween_callback(ring.queue_free)


func confirm_resign():
	var dialog = ConfirmationDialog.new()
	dialog.dialog_text = "Desistir desta partida?"
	dialog.confirmed.connect(func(): send_command("match.resign", {}); dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered()


func load_matches():
	var data = await api(HTTPClient.METHOD_GET, "/v1/matches")
	for child in history_box.get_children():
		child.queue_free()
	if data is Array:
		for item in data:
			button(item.id.substr(0, 8) + " • " + item.status, history_box, func(): match_id = item.id; pending.clear(); connect_match())


func load_history():
	if match_id == "":
		return
	var data = await api(HTTPClient.METHOD_GET, "/v1/matches/" + match_id + "/history")
	for child in history_box.get_children():
		child.queue_free()
	if data is Array:
		for event in data:
			label(str(event.seq) + " • " + event.type + " " + str(event.get("move", event.get("card", event.get("reason", "")))), history_box, 14)


func _smoke_pointer(position, held: bool = false):
	var motion = InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	get_viewport().push_input(motion, true)
	await get_tree().process_frame


func _smoke_mouse_click(position):
	await _smoke_pointer(position)
	for pressed in [true, false]:
		var event = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = position
		event.global_position = position
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		get_viewport().push_input(event, true)
		await get_tree().physics_frame
		await get_tree().process_frame


func _smoke_click_square(square):
	var point = camera.unproject_position(world_square(square) + Vector3(0, 0.09, 0))
	var local = point * stage.size / Vector2(viewport.size)
	# Follow a real mouse path through free board space when the hand covers the target.
	for polygon in cards_row.projected_polygons.values():
		if not cards_row.retracted and Geometry2D.is_point_in_polygon(local, polygon):
			await _smoke_pointer(stage.get_global_transform_with_canvas() * Vector2(12, 12))
			var deadline = Time.get_ticks_msec() + 4000
			while Time.get_ticks_msec() < deadline:
				await get_tree().process_frame
				var covered = cards_row.projected_polygons.values().any(func(shape): return Geometry2D.is_point_in_polygon(local, shape))
				if cards_row.retracted and not covered:
					break
			await get_tree().physics_frame
			await get_tree().process_frame
			break
	# Native window resize events can arrive while the hand is retracting.
	point = camera.unproject_position(world_square(square) + Vector3(0, 0.09, 0))
	local = point * stage.size / Vector2(viewport.size)
	await _smoke_mouse_click(stage.get_global_transform_with_canvas() * local)


func _smoke_drag_card(definition: String, square: String, pause_before_release: bool):
	var card = {}
	for candidate in snapshot.my_hand:
		if candidate.definition_id == definition: card = candidate
	if card.is_empty(): return false
	await _smoke_pointer(cards_row.get_global_transform_with_canvas() * cards_row.activation_strip().get_center())
	await get_tree().create_timer(0.7).timeout
	var control = cards_row.buttons[str(card.instance_id)]
	var start = control.get_global_transform_with_canvas() * (control.size / 2)
	await _smoke_pointer(start)
	var down = InputEventMouseButton.new()
	down.position = start
	down.global_position = start
	down.button_index = MOUSE_BUTTON_LEFT
	down.button_mask = MOUSE_BUTTON_MASK_LEFT
	down.pressed = true
	get_viewport().push_input(down, true)
	await get_tree().process_frame
	await _smoke_pointer(start + Vector2(12, -16), true)
	var point = camera.unproject_position(world_square(square) + Vector3(0, 0.09, 0))
	var destination = stage.get_global_transform_with_canvas() * (point * stage.size / Vector2(viewport.size))
	for step in range(1, 7):
		await _smoke_pointer(start.lerp(destination, step / 6.0), true)
		await get_tree().physics_frame
	if pause_before_release: set_process(false)
	var up = InputEventMouseButton.new()
	up.position = destination
	up.global_position = destination
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	get_viewport().push_input(up, true)
	await get_tree().physics_frame
	await get_tree().process_frame
	return true


func smoke_test(path):
	var data = consume_bootstrap(path)
	if data.is_empty():
		get_tree().quit(2)
		return
	session = data.session
	token_deadline = Time.get_ticks_msec() + 1800000
	server_field.text = data.server
	match_id = data.match_id
	connect_match()
	await load_catalogue()
	var deadline = Time.get_ticks_msec() + 15000
	while (connection_state != "connected" or snapshot.get("state_version", -1) < int(data.get("wait_for_version", 0))) and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.1).timeout
	if snapshot.is_empty() or connection_state != "connected" or snapshot.get("state_version", -1) < int(data.get("wait_for_version", 0)):
		push_error("SMOKE_NO_SNAPSHOT")
		get_tree().quit(3)
		return
	var frozen_verified = false
	if data.get("verify_frozen_a7", false):
		var pawn_id = ""
		for piece in snapshot.pieces:
			if piece.square == "a7": pawn_id = piece.id
		frozen_verified = snapshot.public_effects.any(func(effect): return effect.kind == "frozen" and effect.piece_id == pawn_id) and not snapshot.legal_moves.has("a7a6") and not snapshot.legal_moves.has("a7a5")
		if not frozen_verified:
			push_error("SMOKE_FROZEN_TARGET_NOT_CONFIRMED")
			get_tree().quit(9)
			return
	print("SMOKE_CONNECTED ", snapshot.viewer_side, " version=", snapshot.state_version)
	if data.has("spell"):
		if not await _smoke_drag_card(data.spell, data.get("spell_square", "a7"), data.get("reconnect_spell", false)):
			get_tree().quit(7)
			return
		if data.get("reconnect_spell", false):
			socket.close()
			set_process(true)
		var spell_deadline = Time.get_ticks_msec() + 20000
		while (snapshot.state_version < 1 or not pending.is_empty() or cards_row.resolution_count < 1 or cards_row.busy()) and Time.get_ticks_msec() < spell_deadline:
			await get_tree().create_timer(0.1).timeout
		if cards_row.resolution_count != 1:
			push_error("SMOKE_SPELL_NOT_RESOLVED")
			get_tree().quit(8)
			return

	if data.has("sidebar_visible") and sidebar_scroll.visible != data.sidebar_visible:
		await _smoke_mouse_click(sidebar_button.get_global_transform_with_canvas() * (sidebar_button.size / 2))
	if data.has("move"):
		await _smoke_click_square(data.move.substr(0, 2))
		if selected_square != data.move.substr(0, 2):
			push_error("SMOKE_MOUSE_SELECTION_FAILED")
			get_tree().quit(5)
			return
		if data.get("reconnect", false):
			# Pause packet consumption so the test interrupts a real pending command.
			set_process(false)
		await _smoke_click_square(data.move.substr(2, 2))
	var replayed_id = ""
	if data.get("reconnect", false):
		if pending.is_empty():
			push_error("SMOKE_NO_PENDING_COMMAND")
			get_tree().quit(6)
			return
		replayed_id = pending.keys()[0]
		socket.close()
		set_process(true)
	deadline = Time.get_ticks_msec() + 15000
	while (snapshot.state_version < int(data.get("expected_version", 0)) or connection_state != "connected" or not pending.is_empty()) and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.2).timeout
	if not cards_row.holders.is_empty():
		await _smoke_pointer(cards_row.get_global_transform_with_canvas() * cards_row.activation_strip().get_center())
		await get_tree().create_timer(0.7).timeout
	if data.get("show_settings", false):
		await _smoke_mouse_click(gear_button.get_global_transform_with_canvas() * (gear_button.size / 2))
		await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(path + ".png")
	print("SMOKE_FINAL version=", snapshot.state_version)
	var report = FileAccess.open(path + ".result.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"state_version": snapshot.state_version, "viewer_side": snapshot.viewer_side, "pieces": snapshot.pieces, "connection_state": connection_state, "replayed_request_id": replayed_id, "pending_count": pending.size(), "sidebar_visible": sidebar_scroll.visible, "card_resolutions": cards_row.resolution_count, "frozen_verified": frozen_verified}))
	report.close()
	get_tree().quit(0 if snapshot.state_version >= int(data.get("expected_version", 0)) and connection_state == "connected" and pending.is_empty() else 4)
