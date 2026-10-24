extends SceneTree
## Offline scene/input regressions; -- --capture=directory adds actual GPU review.

var failures = 0
var capture = ""
var capture_quality = 2
var capture_shadows = true

class Preview:
	extends "res://main.gd"
	func _ready():
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		build_ui()
		build_stage()
		set_process(false)


func _initialize():
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			capture = argument.trim_prefix("--capture=")
		if argument.begins_with("--quality="):
			capture_quality = clampi(int(argument.trim_prefix("--quality=")),0,2)
		if argument == "--no-shadows":
			capture_shadows = false
	call_deferred("run")


func check(value: bool, message: String):
	if not value:
		failures += 1
		push_error(message)


func key(code: Key):
	var event = InputEventKey.new()
	event.keycode = code
	event.pressed = true
	root.push_input(event, true)
	await process_frame


func make_game(quality = -1):
	var game = Preview.new()
	if quality >= 0:
		game.preferences.values.quality = quality
	root.add_child(game)
	game.match_id = "arena-test"
	game.connected_match_id = game.match_id
	game.snapshot = {"viewer_side": "white", "active_side": "white", "status": "active", "state_version": 0,
		"pieces": [], "public_effects": [], "my_hand": [], "legal_moves": ["e2e4"],
		"my_mana": 5, "opponent_mana": 3, "opponent_hand_count": 3, "my_deck_count": 20,
		"can_cast": true, "my_traps": [], "revealed_traps": [], "my_discard": [],
		"clock_ms": {"white": 600000, "black": 600000}, "tutorial": null, "draw_offer": null}
	for side in ["white", "black"]:
		for file in range(8):
			for rank in [1, 2]:
				var row = rank if side == "white" else 9-rank
				game.snapshot.pieces.append({"id": side+str(file)+str(rank), "kind": "p" if rank == 2 else "rnbqkbnr"[file], "side": side, "square": "abcdefgh"[file]+str(row)})
	var ids = ["frost_bind", "arcane_shield", "hidden_snare", "arcane_focus", "arcane_draw"]
	var titles = ["Prisão de Gelo", "Escudo Arcano", "Selo de Raízes", "Concentração", "Intuição"]
	var costs = [3,2,2,0,2]
	for i in range(ids.size()):
		game.cards[ids[i]] = {"name": titles[i], "text": "Arraste ao tabuleiro para conjurar.", "mana_cost": costs[i]}
		game.snapshot.my_hand.append({"instance_id": "card"+str(i), "definition_id": ids[i]})
	game.set_connection_state("connected")
	game.render_snapshot()
	game.apply_sidebar_visibility(false)
	return game


func run():
	root.size = Vector2i(1920, 1080)
	var game = make_game()
	await process_frame
	await physics_frame
	if DisplayServer.get_name() != "headless":
		await create_timer(0.5).timeout
	for asset in ["pillar", "castle", "island", "crystal", "platform", "bridge"]:
		check(ResourceLoader.exists("res://assets/arena/"+asset+".glb"), "Missing final arena resource: "+asset)
	check(game.arena.world_islands.size() == 8, "Two main and six secondary islands")
	check(game.arena.ornaments.size() == 8, "Eight peripheral ornament groups")
	check(game.stage_environment.background_mode == Environment.BG_SKY, "Visible continuous sky")
	for descendant in game.arena.find_children("*", "CollisionObject3D", true, false):
		check(descendant.collision_layer & 1 == 0, "Scenery cannot intercept board picks")
	var arena_id = game.arena.get_instance_id()
	var original_transform = game.camera.transform
	await key(KEY_I)
	check(game.inspection.inspecting and game.inspection_bar.visible, "I enters inspection")
	check(game.inspection_bar.size.y <= 56, "Inspection controls remain a compact horizontal bar")
	check(not game.cards_row.visible, "Inspection leaves the environment unobstructed")
	game.inspection.look(game.camera, Vector2(230, -600))
	check(game.camera.rotation.x > 0, "Inspection can look above the horizon")
	var click = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(500, 300)
	game.board_input(click)
	check(game.queued_picks.is_empty(), "Inspection blocks piece moves")
	check(game.cards_row.input_blocked.call(), "Inspection blocks card gestures")
	await key(KEY_ESCAPE)
	check(not game.inspection.inspecting and game.camera.transform.is_equal_approx(original_transform), "Esc restores exact playing transform")
	check(game.cards_row.visible, "Returning restores the hand")
	game.toggle_inspection()
	game.pending["keep-during-inspection"] = {"command": {"type":"spell.request"}}
	game.settings_menu.toggle(game.preferences.values)
	await key(KEY_ESCAPE)
	check(game.inspection.inspecting and not game.settings_menu.visible, "Esc closes menu before inspection")
	await key(KEY_HOME)
	check(not game.inspection.inspecting and game.camera_yaw == 0, "Home restores playing view")
	check(game.pending.has("keep-during-inspection"), "Inspection preserves commands already sent")
	game.pending.clear()
	for quality in range(3):
		game.set_graphics_quality(quality)
		check(game.stage_environment.volumetric_fog_enabled == (quality == 2 and RenderingServer.get_current_rendering_method() == "forward_plus"), "Quality applies volumetric budget")
	game.arena.animation_enabled = false
	var frozen_time = game.arena.elapsed
	await process_frame
	await process_frame
	check(game.arena.elapsed == frozen_time, "Animation preference freezes atmosphere")
	game.arena.animation_enabled = true
	game.snapshot.state_version = 1
	game.render_snapshot()
	check(game.arena.get_instance_id() == arena_id, "Snapshots preserve environment")
	for side in ["white", "black"]:
		game.snapshot.viewer_side = side
		game.position_camera()
		await game._smoke_click_square("e2")
		check(game.selected_square == "e2", "Board mouse path works through scenery for "+side+"; actual="+game.selected_square+" hand="+game.cards_row.state+" folded="+str(game.cards_row.retracted))
		game.clear_selection()
	for expanded in [true,false]:
		game.apply_sidebar_visibility(expanded)
		root.size = Vector2i(1280,800) if expanded else Vector2i(1920,1080)
		await process_frame
		await process_frame
		game.toggle_inspection()
		if DisplayServer.get_name() != "headless" and expanded:
			await key(KEY_F11)
			check(DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN,DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN], "F11 enters fullscreen during inspection")
			await key(KEY_F11)
			check(game.inspection.inspecting, "Fullscreen changes preserve inspection")
		await process_frame
		check(game.inspection_bar.get_rect().end.x <= game.stage.get_rect().end.x+game.stage.position.x+20, "Inspection controls stay in the available area")
		game.toggle_inspection()
	if capture != "" and DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute(capture)
		game.snapshot.viewer_side = "white"
		game.preferences.values.shadows = capture_shadows
		game.set_graphics_quality(capture_quality)
		for i in range(4):
			game.camera_yaw = i * PI/2
			game.position_camera()
			await create_timer(1.0).timeout
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(capture.path_join("arena-"+str(i)+".png"))
		game.toggle_inspection()
		game.inspection.look(game.camera, Vector2(0,-600))
		await create_timer(1.0).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(capture.path_join("arena-sky.png"))
		game.toggle_inspection()
	print("ARENA: persistent world, eight islands/ornaments, quality, frozen atmosphere, inspection keyboard/input and both board orientations; failures=", failures)
	game.queue_free()
	for i in range(5):
		await process_frame
	quit(1 if failures else 0)
