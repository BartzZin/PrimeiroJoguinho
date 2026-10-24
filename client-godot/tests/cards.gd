extends SceneTree

const PREVIEW = preload("res://tests/models.gd")
const HAND = preload("res://card_hand.gd")
var failures = 0


func _initialize():
	call_deferred("run")


func check(condition: bool, message: String):
	if not condition:
		failures += 1
		push_error(message)


func run():
	root.size = Vector2i(1920, 1080)
	var game = PREVIEW.PreviewGame.new()
	root.add_child(game)
	game.animate_moves = false
	game.cards_row.animate_moves = false
	for quality in range(3):
		game.set_graphics_quality(quality)
		check(game.cards_row.viewport.msaa_3d == [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][quality], "Card quality must follow general graphics settings")
	var hand = []
	for id in HAND.IDS:
		hand.append({"instance_id": id, "definition_id": id})
		game.cards[id] = {"name": id.replace("_", " ").capitalize(), "mana_cost": 2, "text": "Test spell"}
	game.cards.arcane_focus.mana_cost = 0
	game.snapshot = {"viewer_side": "white", "active_side": "white", "status": "active",
		"pieces": [{"id": "king", "side": "white", "kind": "k", "square": "e1"}],
		"public_effects": [], "my_hand": hand, "legal_moves": ["e1e2"], "can_cast": true,
		"my_mana": 5, "opponent_mana": 3, "opponent_hand_count": 3, "my_deck_count": 9,
		"tutorial": null, "draw_offer": null}
	game.set_connection_state("connected")
	game.render_snapshot()
	await process_frame
	await physics_frame
	check(game.cards_row.viewport.world_3d != game.viewport.world_3d, "Hand must have its own world")
	check(HAND.models.size() == 1 and game.cards_row.holders.size() == 12, "All twelve spells must use ONE shared model")
	var shared_mesh = null
	for id in HAND.IDS:
		var artwork = game.cards_row.holders[id].find_child("Artwork", true, false)
		check(artwork is MeshInstance3D and artwork.material_override is ShaderMaterial, "Card must expose a replaceable artwork material")
		if shared_mesh == null:
			shared_mesh = artwork.mesh
		check(artwork.mesh == shared_mesh, "Artwork geometry must be shared")
		check(artwork.material_override.get_shader_parameter("artwork").resource_path.ends_with(id + ".png"), "Each spell must use its own image")
		check(not game.cards_row.buttons[id].disabled, "Affordable card must be available")
		check(Rect2(Vector2.ZERO, game.size).encloses(game.cards_row.buttons[id].get_global_rect()), "Full hand must stay visible")
	var generation = game.cards_row.generation
	var instance = game.cards_row.holders.arcane_shield.get_instance_id()
	game.render_snapshot()
	check(game.cards_row.generation == generation and game.cards_row.holders.arcane_shield.get_instance_id() == instance, "Clock-equivalent updates must not recreate models")
	game.snapshot.my_hand = hand.slice(0, 3)
	game.render_snapshot()
	await process_frame
	await game._smoke_mouse_click(game.cards_row.buttons.arcane_shield.get_global_rect().get_center())
	check(game.selected_card.get("instance_id") == "arcane_shield", "Actual mouse click must select the rendered card")
	check(game.cards_row.holders.arcane_shield.get_meta("outline").visible, "Selection must display the 3D outline")
	await game._smoke_click_square("e1")
	check(game.selected_target == {"piece_id": "king"}, "Card target must still use board mouse picking")
	# The existing Conjurar button in the sidebar confirms the selected card.
	await game._smoke_mouse_click(game.sidebar_button.get_global_rect().get_center())
	game.sidebar_scroll.scroll_vertical = 590
	await process_frame
	var confirm = find_button(game.sidebar_scroll, "Conjurar no alvo selecionado")
	game.sidebar_scroll.ensure_control_visible(confirm)
	await process_frame
	await process_frame
	await game._smoke_mouse_click(confirm.get_global_rect().get_center())
	check(game.received_commands.size() == 1 and game.received_commands[0].kind == "spell.request" and game.received_commands[0].payload == {"card_instance_id": "arcane_shield", "target": {"piece_id": "king"}}, "Confirmation mouse path must preserve spell command")
	game.snapshot.my_mana = 0
	game.render_snapshot()
	check(game.cards_row.buttons.arcane_shield.disabled, "Insufficient mana must disable paid cards")
	await game._smoke_mouse_click(game.cards_row.buttons.arcane_shield.get_global_rect().get_center())
	check(game.selected_card.is_empty(), "Mouse must not select an unavailable card")
	game.snapshot.my_hand = [hand[7]]
	game.render_snapshot()
	check(not game.cards_row.buttons.arcane_focus.disabled, "Zero-mana cards must remain usable")
	await game._smoke_mouse_click(game.cards_row.buttons.arcane_focus.get_global_rect().get_center())
	check(game.selected_card.get("definition_id") == "arcane_focus", "Mouse must select a free card with zero mana")
	game.snapshot.can_cast = false
	game.render_snapshot()
	check(game.cards_row.buttons.arcane_focus.disabled, "Opponent turn must prevent selection")
	await game._smoke_mouse_click(game.cards_row.buttons.arcane_focus.get_global_rect().get_center())
	check(game.selected_card.is_empty(), "Mouse must not select a card on opponent turn")
	game.snapshot.can_cast = true
	game.snapshot.my_mana = 5
	game.snapshot.my_hand = [hand[0], hand[9], hand[10]]
	game.render_snapshot()
	check(game.cards_row.holders.size() == 3 and not game.cards_row.holders.has("arcane_focus"), "Draw/removal must replace the authorized hand")
	for expanded in [true, false]:
		game.apply_sidebar_visibility(expanded)
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(1280, 800) if expanded else Vector2i(1920, 1080)
		await process_frame
		await process_frame
		check(not game.cards_row.get_global_rect().intersects(game.gear_button.get_global_rect()), "Hand must not cover footer")
		await game._smoke_mouse_click(game.cards_row.buttons.temporal_boost.get_global_rect().get_center())
		check(game.selected_card.get("definition_id") == "temporal_boost", "Resized hand must preserve input mapping")
	game.clear_selection()
	game.cards_row.animate_moves = true
	game.cards_row.select("arcane_shield")
	await create_timer(0.3).timeout
	check(is_equal_approx(game.cards_row.holders.arcane_shield.position.y, 0.28), "Animated selection must reach its elevation")
	check(game.cards_row.viewport.render_target_update_mode != SubViewport.UPDATE_ALWAYS, "Idle hand must stop continuous rendering")
	game.cards_row.select("trap_disarm")
	game.cards_row.animate_moves = false
	check(is_equal_approx(game.cards_row.holders.trap_disarm.position.y, 0.28) and game.cards_row.viewport.render_target_update_mode != SubViewport.UPDATE_ALWAYS, "Disabling animations must finish selection without continuous rendering")
	game.snapshot.my_hand = hand.slice(0, 5)
	game.render_snapshot()
	var stable_generation = game.cards_row.generation
	var started = Time.get_ticks_usec()
	for repeat in range(1000):
		game.cards_row.update_hand(game.snapshot.my_hand, game.cards, true, 5)
	check(game.cards_row.generation == stable_generation, "Full-hand idle updates must not allocate new models")
	print("CARD_IDLE_UPDATE_US ", (Time.get_ticks_usec() - started) / 1000.0)
	if DisplayServer.get_name() != "headless":
		await create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--screenshot="):
				root.get_texture().get_image().save_png(argument.trim_prefix("--screenshot="))
	print("CARDS: one shared model, 12 images, authorized hand, caching, mouse selection/target/confirmation, availability, resize, animation and idle rendering; failures=", failures)
	var definitions = game.cards.duplicate(true)
	game.queue_free()
	await process_frame
	if DisplayServer.get_name() != "headless":
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--gallery="):
				await gallery(hand, definitions, argument.trim_prefix("--gallery="))
	quit(0 if failures == 0 else 1)


func gallery(hand: Array, definitions: Dictionary, path: String):
	var rows = VBoxContainer.new()
	rows.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(rows)
	for index in range(3):
		var row = HAND.new()
		row.size_flags_vertical = Control.SIZE_EXPAND_FILL
		rows.add_child(row)
		row.update_hand(hand.slice(index * 4, index * 4 + 4), definitions, true, 5)
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	rows.queue_free()
	await process_frame


func find_button(node: Node, text_value: String):
	if node is Button and node.text == text_value:
		return node
	for child in node.get_children():
		var found = find_button(child, text_value)
		if found != null:
			return found
	return null
