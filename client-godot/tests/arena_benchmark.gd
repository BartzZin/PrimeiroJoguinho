extends "res://tests/arena.gd"
## Actual frame intervals, no generation running; -- --capture=output saves JSON.

func run():
	if DisplayServer.get_name() == "headless":
		push_error("Benchmark requires real GPU rendering")
		quit(1)
		return
	root.size = Vector2i(1920,1080)
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var levels = [2,1,0]
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--quality="):
			levels = [clampi(int(argument.trim_prefix("--quality=")),0,2)]
	var game = make_game(levels[0])
	var report = {"adapter": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(), "resolution": "1920x1080", "pieces": 32, "cards": 5, "profiles": []}
	for level in levels:
		game.set_graphics_quality(level)
		await create_timer(3.0).timeout
		var samples: Array[float] = []
		var draw_calls = 0
		var primitives = 0
		var texture_bytes = 0
		var video_bytes = 0
		var visible_primitives = 0
		var shadow_primitives = 0
		for angle in range(4):
			game.camera_yaw = angle*PI/2
			game.position_camera()
			await create_timer(0.5).timeout
			for frame in range(90):
				var before = Time.get_ticks_usec()
				await process_frame
				samples.append((Time.get_ticks_usec()-before)/1000.0)
				draw_calls = maxi(draw_calls, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
				primitives = maxi(primitives, int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
				texture_bytes = maxi(texture_bytes, int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)))
				video_bytes = maxi(video_bytes, int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)))
				visible_primitives = maxi(visible_primitives,game.viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME))
				shadow_primitives = maxi(shadow_primitives,game.viewport.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME))
		samples.sort()
		var total = samples.reduce(func(sum_value,value): return sum_value+value,0.0)
		var result = {"quality":level,"frames":samples.size(),"average_fps":1000.0/(total/samples.size()),"p95_frame_ms":samples[int(samples.size()*0.95)],"max_frame_ms":samples[-1],"max_draw_calls":draw_calls,"max_primitives":primitives,"renderer_texture_mib":texture_bytes/1048576.0}
		result.render_scale = game.viewport.scaling_3d_scale
		result.lod_threshold = game.viewport.mesh_lod_threshold
		result.renderer_video_mib = video_bytes/1048576.0
		result.visible_primitives = visible_primitives
		result.shadow_primitives = shadow_primitives
		var orbit: Array[float] = []
		for frame in range(360):
			var before = Time.get_ticks_usec()
			game.camera_yaw = TAU*frame/360.0
			game.position_camera()
			if frame in [120,240]:
				for piece in game.snapshot.pieces:
					if frame == 120 and piece.square == "e2": piece.square = "e4"
					if frame == 240 and piece.square == "e7": piece.square = "e5"
				game.snapshot.state_version += 1
				game.render_snapshot()
			await process_frame
			orbit.append((Time.get_ticks_usec()-before)/1000.0)
		orbit.sort()
		result.orbit_p95_ms = orbit[int(orbit.size()*0.95)]
		result.orbit_max_ms = orbit[-1]
		report.profiles.append(result)
		print("BENCHMARK ",JSON.stringify(result))
	if capture != "":
		DirAccess.make_dir_recursive_absolute(capture)
		var file = FileAccess.open(capture.path_join("performance.json"),FileAccess.WRITE)
		file.store_string(JSON.stringify(report,"\t"))
		file.close()
	game.queue_free()
	for frame in range(5):
		await process_frame
	quit()
