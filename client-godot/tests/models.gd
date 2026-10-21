extends SceneTree
## Offline validation of the actual board renderer; no accounts or server needed.

const MODELS = preload("res://piece_models.gd")
var failures = 0

class PreviewGame:
	extends "res://main.gd"

	func _ready():
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		build_ui()
		build_stage()
		set_process(false)


func _initialize():
	call_deferred("run")


func check(condition: bool, message: String):
	if not condition:
		failures += 1
		push_error(message)


func check_materials(node: Node):
	if node is MeshInstance3D:
		check(node.material_override == null, "Imported materials must not be painted over")
		for surface in range(node.mesh.get_surface_count()):
			var paint = node.get_active_material(surface)
			check(paint is StandardMaterial3D, "Missing glTF material")
			if paint is StandardMaterial3D:
				check(paint.albedo_texture != null, "Missing army color texture")
				check(paint.normal_texture != null, "Missing normal map")
	for child in node.get_children():
		check_materials(child)


func run():
	root.size = Vector2i(1920, 1080)
	var game = PreviewGame.new()
	root.add_child(game)
	game.animate_moves = false
	check(ProjectSettings.get_setting("display/window/size/viewport_width") == 1920 and ProjectSettings.get_setting("display/window/size/viewport_height") == 1080, "Default presentation must be Full HD")
	game.set_graphics_quality(0)
	check(not game.directional_light.shadow_enabled and not game.stage_environment.ssao_enabled, "Low quality must disable expensive effects")
	game.set_graphics_quality(2)
	check(game.viewport.msaa_3d == Viewport.MSAA_4X and game.stage_environment.ssao_enabled and game.directional_light.shadow_enabled, "High quality must restore antialiasing, contact shadows and lighting shadows")
	game.snapshot = {
		"viewer_side": "white", "active_side": "white", "status": "active",
		"pieces": [], "public_effects": [], "my_hand": [], "legal_moves": ["e2e4"],
		"my_mana": 3, "opponent_mana": 3, "opponent_hand_count": 3, "my_deck_count": 9,
		"tutorial": null, "draw_offer": null,
	}
	for side in ["white", "black"]:
		var back_rank = "1" if side == "white" else "8"
		var pawn_rank = "2" if side == "white" else "7"
		for file in range(8):
			game.snapshot.pieces.append({"id": side + "-p-" + str(file), "kind": "p", "side": side, "square": "abcdefgh"[file] + pawn_rank})
			game.snapshot.pieces.append({"id": side + "-back-" + str(file), "kind": "rnbqkbnr"[file], "side": side, "square": "abcdefgh"[file] + back_rank})
	game.render_snapshot()
	check(game.pieces_root.get_child_count() == 32, "Initial board must display 32 miniatures")
	for piece in game.pieces_root.get_children():
		var miniature = piece.get_child(0)
		var bounds = MODELS.mesh_bounds(miniature)
		check(absf(bounds.position.y) < 0.001, "Miniature base must rest on the square")
		check(bounds.size.x <= MODELS.MAX_FOOTPRINT + 0.001 and bounds.size.z <= MODELS.MAX_FOOTPRINT + 0.001, "Miniature must fit inside its square")
		check(absf(bounds.get_center().x) < 0.001 and absf(bounds.get_center().z) < 0.001, "Miniature must be centered")
		check_materials(miniature)
	var blue = game.pieces_root.get_node("white-p-0").get_child(0)
	var red = game.pieces_root.get_node("black-p-0").get_child(0)
	check(blue.get_child(0).scene_file_path.contains("/blue/"), "Solar must use the blue army")
	check(red.get_child(0).scene_file_path.contains("/red/"), "Lunar must use the red army")
	check(blue.basis.z.dot(red.basis.z) < 0, "Armies must face each other")
	# Exercise the same selection/highlighting path used by the mouse.
	game.click_square("e2")
	check(game.selected_square == "e2", "Model replacement must preserve square selection")
	game.clear_selection()
	if DisplayServer.get_name() != "headless":
		await create_timer(1).timeout
		await RenderingServer.frame_post_draw
		for square in ["a1", "h1", "a8", "h8"]:
			var screen_position = game.camera.unproject_position(game.world_square(square))
			check(Rect2(Vector2.ZERO, game.viewport.size).has_point(screen_position), "Board corners must remain inside the viewport")
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--screenshot="):
				check(root.get_texture().get_image().save_png(argument.trim_prefix("--screenshot=")) == OK, "Could not save preview")
	# An ordinary move keeps the piece ID and reaches the destination.
	game.snapshot.pieces[8].square = "e4"
	game.render_snapshot()
	check(game.pieces_root.get_node("white-p-4").position.is_equal_approx(game.world_square("e4") + Vector3(0, 0.095, 0)), "Moved model must follow its square")
	# A promotion uses the matching textured queen and still supports effects.
	game.snapshot.pieces[0].kind = "q"
	game.snapshot.public_effects = [{"piece_id": "white-p-0", "kind": "shield"}]
	game.render_snapshot()
	var promoted = game.pieces_root.get_node("white-p-0")
	check(promoted.get_child(0).get_child(0).scene_file_path.ends_with("/blue/queen.glb"), "Promotion must replace the pawn with the blue queen")
	check(promoted.get_child_count() == 2, "Magic effects must coexist with textured models")
	game.snapshot.pieces.pop_back()
	game.render_snapshot()
	check(game.pieces_root.get_child_count() == 31, "Captured model must disappear")
	print("MODELS: 12 textured variants, 32 pieces, Full HD, quality settings, framing, selection, move, promotion, capture and effects; failures=", failures)
	game.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
