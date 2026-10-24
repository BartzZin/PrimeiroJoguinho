extends "res://tests/arena.gd"
const POLICY = preload("res://graphics_profile.gd")

func run():
	check(POLICY.resolve(3,"NVIDIA GeForce GTX 1050 Ti") == 0, "Automatic GTX 1050 profile")
	check(POLICY.resolve(3,"NVIDIA GeForce GTX 1650") == 1, "Automatic GTX 1650 profile")
	check(POLICY.resolve(3,"NVIDIA GeForce RTX 5060") == 2, "Automatic RTX 5060 profile")
	check(POLICY.resolve(0,"RTX 5060") == 0, "Manual override wins")
	root.size = Vector2i(1920,1080)
	var game = make_game(0)
	game.animate_moves = false
	await create_timer(0.5).timeout
	check(not is_instance_valid(game.arena.probe) and game.arena.cloud_volumes.is_empty(), "Fresh performance profile must not allocate a reflection atlas or fog volumes")
	check(ProjectSettings.get_setting("rendering/reflections/reflection_atlas/reflection_count") <= 4, "Reflection budget must stay bounded for small VRAM devices")
	var old_profile = ConfigFile.new()
	var old_name = "graphics-old-"+str(OS.get_process_id())
	old_profile.set_value("general","quality",2)
	old_profile.save("user://preferences_"+old_name+".cfg")
	var migrated = preload("res://preferences.gd").new()
	migrated.load_profile(old_name)
	check(migrated.values.quality == 2 and migrated.values.render_scale == 0, "Old explicit quality choices survive new defaults")
	DirAccess.remove_absolute(migrated.path)
	for tile in game.board_root.get_children():
		check(tile.get_child(0).layers & 1 == 0, "Private board markers must be excluded from static reflections")
	for quality in range(3):
		game.set_graphics_quality(quality)
		var config = POLICY.configuration(quality)
		check(is_equal_approx(game.viewport.scaling_3d_scale,config.scale), "Each preset uses its rendering scale")
		check(game.viewport.mesh_lod_threshold == config.lod, "Each preset applies a geometry budget")
		check(game.cards_row.viewport.scaling_3d_scale == 1.0, "Card models/text stay at native resolution")
		for side in ["white","black"]:
			game.snapshot.viewer_side = side
			game.position_camera()
			game.clear_selection()
			await game._smoke_click_square("e2")
			check(game.selected_square == "e2", "Render scaling preserves native mouse coordinates")
	game.change_setting("render_scale",75)
	check(is_equal_approx(game.viewport.scaling_3d_scale,0.75), "Manual scale overrides preset")
	game.change_setting("shadows",false)
	check(not game.directional_light.shadow_enabled, "Shadow override disables their cost")
	game.change_setting("show_fps",true)
	game.connection_state = "idle"
	game._process(0.01)
	check(game.fps_label.visible and game.fps_label.text.contains("FPS"), "FPS monitor is available without a match")
	var report = game.graphics_report()
	check(report.has("gpu") and report.has("render_scale") and not report.has("session") and not report.has("snapshot"), "Graphics report includes technical metrics without match data")
	var store = preload("res://preferences.gd").new()
	var profile_name = "graphics-test-"+str(OS.get_process_id())
	store.load_profile(profile_name)
	store.values.quality = 0
	store.values.render_scale = 67
	store.values.show_fps = true
	check(store.save() == OK, "Save graphics preferences")
	var reopened = preload("res://preferences.gd").new()
	reopened.load_profile(profile_name)
	check(reopened.values.quality == 0 and reopened.values.render_scale == 67 and reopened.values.show_fps, "Graphics preferences persist by profile")
	DirAccess.remove_absolute(store.path)
	check(game.stage_environment.sky.process_mode == Sky.PROCESS_MODE_QUALITY and game.arena.sky_material.get_shader_parameter("panorama") is Texture2D, "HDR sky must remain cached rather than updated every frame")
	print("GRAPHICS: automatic/manual profiles, internal resolution, native UI, mouse picks, LOD, shadows, FPS and persistence; failures=",failures)
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
