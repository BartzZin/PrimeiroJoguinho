extends SceneTree
const HAND = preload("res://card_hand.gd")
var failures = 0
var sequence = 0

class DragGame:
	extends "res://main.gd"
	var received_commands = []
	func _ready():
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		build_ui()
		build_stage()
		set_process(false)
	func send_command(kind, payload):
		if not pending.is_empty(): return null
		var id = "ui-test-" + str(received_commands.size())
		received_commands.append({"type": kind, "payload": payload, "request_id": id})
		pending[id] = {"command": {"type": kind}, "created_at": Time.get_ticks_msec()}
		return id

func _initialize():
	call_deferred("run")

func check(condition: bool, message: String):
	if not condition:
		failures += 1
		push_error(message)

func data(hand: Array, version: int) -> Dictionary:
	return {"type": "match.snapshot", "match_id": "cards", "state_version": version,
		"viewer_side": "white", "active_side": "white", "status": "active", "can_cast": true,
		"pieces": [{"id": "white-king", "kind": "k", "side": "white", "square": "e1"},
			{"id": "own", "kind": "p", "side": "white", "square": "a2"},
			{"id": "enemy", "kind": "p", "side": "black", "square": "h7"}],
		"public_effects": [{"id": "shield", "kind": "shield", "piece_id": "enemy", "side": "black"}],
		"my_hand": hand, "my_mana": 4, "opponent_mana": 3, "my_deck_count": 10,
		"opponent_hand_count": 3, "legal_moves": ["a2a3"], "clock_ms": {"white": 600000, "black": 600000},
		"my_traps": [], "revealed_traps": [], "my_discard": [], "draw_offer": null, "tutorial": null}

func fixture(game, id: String):
	sequence += 2
	game.pending.clear()
	game.cards_row.reset()
	game.snapshot = data([{"instance_id": "active-" + str(sequence), "definition_id": id},
		{"instance_id": "other", "definition_id": "arcane_draw"}], sequence)
	game.rendered_version = sequence
	game.set_connection_state("connected")
	game.render_snapshot()
	await process_frame
	await physics_frame

func motion(point: Vector2, held: bool = false):
	var event = InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	root.push_input(event, true)
	await process_frame
	await physics_frame

func button(point: Vector2, pressed: bool, index = MOUSE_BUTTON_LEFT):
	var event = InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = index
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed and index == MOUSE_BUTTON_LEFT else 0
	event.pressed = pressed
	root.push_input(event, true)
	await physics_frame
	await process_frame

func square_point(game, square: String) -> Vector2:
	var point = game.camera.unproject_position(game.world_square(square) + Vector3(0, 0.09, 0))
	return game.stage.get_global_transform_with_canvas() * (point * game.stage.size / Vector2(game.viewport.size))

func drag(game, square: String):
	var hand = game.cards_row
	await motion(hand.get_global_transform_with_canvas() * hand.activation_strip().get_center())
	if hand.animate_moves: await create_timer(0.7).timeout
	var id = str(game.snapshot.my_hand[0].instance_id)
	var point = hand.buttons[id].get_global_transform_with_canvas() * (hand.buttons[id].size / 2)
	await motion(point)
	await button(point, true)
	check(hand.state == "pressed", "Holding a card must capture the gesture")
	await motion(point + Vector2(12, -15), true)
	check(hand.state == "dragging", "8px threshold must start drag")
	var destination = square_point(game, square) if square != "" else Vector2(2, 2)
	for step in range(1, 6):
		await motion(point.lerp(destination, step / 5.0), true)
	await button(destination, false)
	await physics_frame
	await process_frame

func run():
	root.size = Vector2i(1920, 1080)
	var game = DragGame.new()
	root.add_child(game)
	game.match_id = "cards"
	game.connected_match_id = "cards"
	game.cards_row.animate_moves = false
	game.animate_moves = false
	for id in HAND.IDS:
		game.cards[id] = {"name": id.replace("_", " ").capitalize(), "text": "Spell", "mana_cost": 2}
	game.cards.arcane_focus.mana_cost = 0
	# Incremental reconciliation must retain nodes through moves, mana and availability changes.
	await fixture(game, "frost_bind")
	var hand = game.cards_row
	var active = str(game.snapshot.my_hand[0].instance_id)
	var node_id = hand.holders[active].get_instance_id()
	var other_id = hand.holders.other.get_instance_id()
	game.snapshot.my_mana = 3
	game.snapshot.state_version += 1
	game.render_snapshot()
	check(hand.holders[active].get_instance_id() == node_id and hand.holders.other.get_instance_id() == other_id, "Mana or piece updates must not recreate cards")
	check(hand.holders[active].find_child("outline", true, false) == null, "Purple rectangular outline must not exist")
	# A slow path out of the activation strip remains within a fixed open envelope.
	await motion(hand.get_global_transform_with_canvas() * hand.activation_strip().get_center())
	for y in range(int(hand.size.y) - 35, int(hand.expanded_zone.position.y) + 35, -8):
		await motion(hand.get_global_transform_with_canvas() * Vector2(hand.size.x / 2, y))
	check(not hand.retracted, "Moving toward cards must never collapse the hand")
	var center = hand.buttons[active].get_global_transform_with_canvas() * (hand.buttons[active].size / 2)
	await motion(center)
	await button(center, true)
	await button(center, false)
	check(hand.state == "selected", "Simple click selects without casting")
	check(game.received_commands.is_empty(), "Click must not cast")
	check(is_equal_approx(hand.holders.other.scale.x / (hand.card_height / 1.55), 0.8), "Other cards must shrink to 80 percent")
	check(is_equal_approx(hand.holders[active].scale.x / (hand.card_height / 1.55), 1.06), "Selected card must grow to 106 percent")
	await motion(game.stage.get_global_rect().position + Vector2(20, 20))
	await create_timer(0.3).timeout
	check(not hand.retracted, "Selection must lock hand open")
	game.clear_selection()
	# Every spell goes through actual down/move/up events and the unchanged payload.
	for id in HAND.IDS:
		await fixture(game, id)
		var target_square = "d4"
		var expected = {}
		if id in ["arcane_shield", "ward"]:
			target_square = "a2"
			expected = {"piece_id": "own"}
		elif id in ["frost_bind", "shield_break"]:
			target_square = "h7"
			expected = {"piece_id": "enemy"}
		elif id == "dispel":
			target_square = "h7"
			expected = {"effect_id": "shield"}
		elif id in ["hidden_snare", "oracle_eye", "trap_disarm"]:
			expected = {"square": "d4"}
		var before = game.received_commands.size()
		var played = str(game.snapshot.my_hand[0].instance_id)
		var stable = hand.holders.other.get_instance_id()
		await drag(game, target_square)
		check(game.received_commands.size() == before + 1, "Drop must submit once: " + id)
		if game.received_commands.size() <= before: continue
		var sent = game.received_commands[-1]
		check(sent.payload == {"card_instance_id": played, "target": expected}, "Spell target mapping: " + id)
		check(hand.state == "pending" and hand.holders.has(played) and game.snapshot.my_mana == 4, "No optimistic card or mana consumption")
		var after = game.snapshot.duplicate(true)
		after.my_hand = [game.snapshot.my_hand[1]]
		after.state_version = sequence + 1
		after.can_cast = false
		var receipt = {"type": "command.accepted", "request_id": sent.request_id, "state_version": after.state_version}
		var count = hand.resolution_count
		if before % 2 == 0:
			game.handle_message(receipt)
			check(hand.state == "pending", "Receipt alone must not remove the card")
			game.handle_message(after)
		else:
			game.handle_message(after)
			check(hand.state == "pending" and hand.holders.has(played), "Snapshot alone must retain reserved visual")
			game.handle_message(receipt)
		game.handle_message(receipt)
		await process_frame
		await process_frame
		check(hand.resolution_count == count + 1 and not hand.holders.has(played), "Confirmation must animate/remove once: " + id)
		check(hand.holders.other.get_instance_id() == stable, "Only the consumed card may disappear")
	# Rejection and invalid/outside releases restore the same instance.
	await fixture(game, "frost_bind")
	active = str(game.snapshot.my_hand[0].instance_id)
	node_id = hand.holders[active].get_instance_id()
	var before = game.received_commands.size()
	await drag(game, "a2")
	await drag(game, "")
	check(game.received_commands.size() == before and hand.holders[active].get_instance_id() == node_id, "Invalid drops must return without charge or recreation")
	await drag(game, "h7")
	var sent = game.received_commands[-1]
	game.handle_message({"type": "command.rejected", "request_id": sent.request_id, "state_version": sequence, "code": "STALE_VERSION"})
	check(hand.pending_request == "" and hand.holders[active].get_instance_id() == node_id, "Rejected commands must restore the reserved instance")
	# Dissipation ambiguity requires explicit choice, with no command until then.
	await fixture(game, "dispel")
	game.snapshot.public_effects.append({"id": "frozen", "kind": "frozen", "piece_id": "enemy", "side": "black"})
	game.render_snapshot()
	before = game.received_commands.size()
	await drag(game, "h7")
	check(is_instance_valid(game.card_effect_popup) and game.received_commands.size() == before, "Two public effects must require choice")
	if is_instance_valid(game.card_effect_popup):
		var choice = game.card_effect_popup.panel.get_child(0).get_child(1)
		# Native popup receives its own viewport mouse events.
		var at = choice.get_global_transform_with_canvas() * (choice.size / 2)
		for pressed in [true, false]:
			var event = InputEventMouseButton.new()
			event.position = at
			event.button_index = MOUSE_BUTTON_LEFT
			event.pressed = pressed
			root.push_input(event, true)
			await process_frame
		check(game.received_commands.size() == before + 1 and game.received_commands[-1].payload.target == {"effect_id": "frozen"}, "Popup mouse choice must dispatch the chosen effect")
	# Cancel captured gestures without dispatching, even when the pointer leaves the hand.
	game.pending.clear()
	await fixture(game, "frost_bind")
	before = game.received_commands.size()
	for cancel_kind in ["escape", "right", "focus", "resize"]:
		var active_id = str(game.snapshot.my_hand[0].instance_id)
		await motion(hand.get_global_transform_with_canvas() * hand.activation_strip().get_center())
		center = hand.buttons[active_id].get_global_transform_with_canvas() * (hand.buttons[active_id].size / 2)
		await motion(center)
		await button(center, true)
		await motion(center + Vector2(20, -30), true)
		if cancel_kind == "escape":
			var key = InputEventKey.new()
			key.keycode = KEY_ESCAPE
			key.pressed = true
			root.push_input(key, true)
		elif cancel_kind == "right":
			await button(center, true, MOUSE_BUTTON_RIGHT)
		elif cancel_kind == "focus":
			root.focus_exited.emit()
		else:
			root.mode = Window.MODE_WINDOWED
			root.size = Vector2i(1280, 800)
			await create_timer(0.2).timeout
			await process_frame
			await process_frame
		await button(square_point(game, "h7"), false)
		check(not hand.captured() and game.received_commands.size() == before, "Cancel captured drag: " + cancel_kind)
	# Black-side picking uses the same authoritative IDs after orbit, zoom and sidebar resize.
	root.size = Vector2i(1920, 1080)
	await create_timer(0.2).timeout
	await fixture(game, "frost_bind")
	game.snapshot.viewer_side = "black"
	game.snapshot.pieces[1].side = "black"
	game.snapshot.pieces[2].side = "white"
	game.camera_yaw = 0.35
	game.camera_pitch = 1.0
	game.camera_distance = 12
	game.apply_sidebar_visibility(true)
	game.render_snapshot()
	await process_frame
	await process_frame
	await drag(game, "h7")
	check(game.received_commands.size() == before + 1 and game.received_commands[-1].payload.target == {"piece_id": "enemy"}, "Black rotated camera must preserve drop targets")
	game.pending.clear()
	hand.reset()
	game.snapshot.viewer_side = "white"
	game.camera_yaw = 0
	game.camera_pitch = 0.85
	game.camera_distance = 11.5
	game.apply_sidebar_visibility(false)
	# Continuous spring motion: intermediate frames, reversal and stable node identities.
	game.pending.clear()
	hand.reset()
	await fixture(game, "arcane_shield")
	game.animate_moves = true
	hand.animate_moves = true
	hand.retracted = true
	hand._retarget()
	await create_timer(0.7).timeout
	var start = hand.holders.other.position
	await motion(hand.get_global_transform_with_canvas() * hand.activation_strip().get_center())
	await create_timer(0.10).timeout
	var middle = hand.holders.other.position
	check(middle.distance_to(start) > 1 and middle.distance_to(hand.poses.other.position) > 1, "Opening must have intermediate visible frames")
	await motion(game.stage.get_global_rect().position + Vector2(10, 10))
	await create_timer(0.1).timeout
	check(not hand.retracted, "Closing must wait 250ms")
	await create_timer(0.22).timeout
	check(hand.retracted, "Hand must close after dwell outside fixed zone")
	await motion(hand.get_global_transform_with_canvas() * hand.activation_strip().get_center())
	await create_timer(0.7).timeout
	check(not hand.retracted and hand.holders.other.position.distance_to(hand.poses.other.position) < 0.3, "Reversal must settle smoothly")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--screenshot=") and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(argument.trim_prefix("--screenshot="))
	print("CARDS: stable nodes/zones, spring motion, selection scales, 12 real mouse drags, targets, popup, receipts both orders, rejection and single resolution; failures=", failures)
	game.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
