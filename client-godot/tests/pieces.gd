extends SceneTree
## Motion, paths, sounds and real board integration, without a backend.

const PieceAnimator = preload("res://piece_animator.gd")
const PieceMovePath = preload("res://piece_move_path.gd")
const PieceSfxPlayer = preload("res://piece_sfx_player.gd")
const BoardPiecesPresenter = preload("res://board_pieces_presenter.gd")
const Preferences = preload("res://preferences.gd")
const Models = preload("res://piece_models.gd")
const Preview = preload("res://tests/models.gd")
var failures := 0
var checks := 0

class FixtureGame:
	extends Preview.PreviewGame

	func _begin_connection():
		rendered_version = -1
		set_connection_state("connecting")


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func square_position(square: String) -> Vector3:
	return Vector3(square.unicode_at(0) - 97, 0, 8 - int(square[1]))


func destination(square: String) -> Vector3:
	return square_position(square) + Vector3(0, 0.095, 0)


func initial_pieces() -> Array:
	var result: Array = []
	for side: String in ["white", "black"]:
		for file in range(8):
			var pawn_square: String = "abcdefgh"[file] + ("2" if side == "white" else "7")
			var back_square: String = "abcdefgh"[file] + ("1" if side == "white" else "8")
			result.append({"id": side + "_" + pawn_square, "kind": "p", "side": side, "square": pawn_square})
			result.append({"id": side + "_" + back_square, "kind": "rnbqkbnr"[file], "side": side, "square": back_square})
	return result


func test_paths() -> void:
	check(PieceMovePath.squares("e2", "e4", "p") == ["e3", "e4"], "Pawn double steps must land on both squares")
	check(PieceMovePath.squares("a1", "a8", "r").size() == 7, "Long files must have seven individual steps")
	check(PieceMovePath.squares("h8", "a1", "b") == ["g7", "f6", "e5", "d4", "c3", "b2", "a1"], "Diagonals must follow square centers in either direction")
	check(PieceMovePath.squares("e4", "e4", "q").is_empty(), "Unchanged squares must produce no movement")
	var knight_paths := {
		"f5": ["e4", "f4", "f5"], "f3": ["e4", "f4", "f3"],
		"b5": ["c4", "b4", "b5"], "b3": ["c4", "b4", "b3"],
		"e6": ["d5", "d6", "e6"], "c6": ["d5", "d6", "c6"],
		"e2": ["d3", "d2", "e2"], "c2": ["d3", "d2", "c2"],
	}
	for target: String in knight_paths:
		check(PieceMovePath.squares("d4", target, "n") == knight_paths[target], "Knights must traverse the two-square axis first: " + target)
	var hops := PieceMovePath.build("d4", "f5", "n", square_position, {"e4": 1.3, "f4": 0.94})
	check(hops.size() == 1 and hops[0].points.size() == 4, "Occupied intermediate squares must merge into one L-shaped flight")
	var motion := PieceAnimator.new()
	motion.setup(destination("d4"), "knight")
	var contacts: Array[Vector3] = []
	motion.landed.connect(func(): contacts.append(motion.position))
	motion.enqueue(hops)
	var safe := true
	var follows_l := true
	for frame in range(40):
		motion.advance(0.02)
		var flat := Vector3(motion.position.x, destination("d4").y, motion.position.z)
		for square: String in ["e4", "f4"]:
			if flat.distance_to(destination(square)) < 0.85:
				safe = safe and motion.position.y >= destination(square).y + 1.3
		follows_l = follows_l and (is_equal_approx(flat.z, destination("d4").z) or is_equal_approx(flat.x, destination("f5").x))
	check(safe, "Occupied squares must be crossed above the tallest model, without landing on it")
	check(follows_l, "Merged flights must preserve the corner of the L")
	check(contacts.size() == 1 and contacts[0].is_equal_approx(destination("f5")), "Only a real ground landing may emit a contact")
	clear_motion_observers(motion)


func test_idle() -> void:
	var positive_x := 0
	var negative_x := 0
	var positive_z := 0
	var negative_z := 0
	var varied_periods := 0
	var within_square := true
	for piece: Dictionary in initial_pieces():
		var motion := PieceAnimator.new()
		motion.setup(Vector3.ZERO, piece.id)
		motion.set_idle_enabled(true)
		motion.advance(0.2)
		positive_x += int(motion.rotation.x > 0.0)
		negative_x += int(motion.rotation.x < 0.0)
		positive_z += int(motion.rotation.z > 0.0)
		negative_z += int(motion.rotation.z < 0.0)
		var initial_pose := motion.rotation
		var deterministic := PieceAnimator.new()
		deterministic.setup(Vector3.ZERO, piece.id)
		deterministic.set_idle_enabled(true)
		deterministic.advance(0.2)
		check(motion.rotation.is_equal_approx(deterministic.rotation), "The same ID must retain its individual idle profile")
		var model := Models.create(piece.kind, piece.side)
		var pivot := Node3D.new()
		pivot.add_child(model)
		for sample in range(50):
			motion.advance(0.06)
			check(motion.rotation.length() <= deg_to_rad(1.0) and motion.rotation.y == 0.0, "Idle must stay below one degree without turning around the vertical axis")
			pivot.rotation = motion.rotation
			var bounds := Models.mesh_bounds(pivot)
			within_square = within_square and bounds.position.x >= -0.5 and bounds.end.x <= 0.5 and bounds.position.z >= -0.5 and bounds.end.z <= 0.5
		pivot.free()
		varied_periods += int(not motion.rotation.is_equal_approx(initial_pose))
		var before_stop := motion.rotation
		motion.set_idle_enabled(false)
		check(motion.rotation.is_equal_approx(before_stop), "Suspending idle must preserve the current pose before easing out")
		motion.advance(0.25)
		check(motion.rotation.is_zero_approx() and not motion.needs_processing(), "Suspended idle must settle to neutral and stop processing")
	check(mini(positive_x, negative_x) >= 5 and mini(positive_z, negative_z) >= 5, "Real server IDs must sway in different directions at the same time")
	check(varied_periods == 32, "The entire army must not share a three-second loop")
	check(within_square, "All 32 swaying miniatures must stay within their squares")


func test_animator() -> void:
	var motion := PieceAnimator.new()
	motion.setup(destination("e2"), "white_e2")
	motion.set_idle_enabled(true)
	motion.advance(0.4)
	var idle_pose := motion.rotation
	var contacts: Array[Vector3] = []
	var starts: Array[bool] = []
	var finished: Array[bool] = []
	motion.landed.connect(func(): contacts.append(motion.position))
	motion.jump_started.connect(func(): starts.append(true))
	motion.move_finished.connect(func(): finished.append(true))
	motion.enqueue(PieceMovePath.build("e2", "e4", "p", square_position))
	check(motion.rotation.is_equal_approx(idle_pose), "Starting a move must not abruptly erase the idle pose")
	motion.advance(0.001)
	check(motion.rotation.distance_to(idle_pose) < 0.001, "Takeoff must blend smoothly out of idle")
	motion.advance(0.219)
	check(contacts.size() == 1 and contacts[0].is_equal_approx(destination("e3")), "The first jump must land on e3 after 0.22 second")
	check(motion.moving and finished.is_empty(), "Intermediate contacts must not finish the whole move")
	motion.enqueue(PieceMovePath.build("e4", "e5", "p", square_position))
	motion.advance(0.56)
	check(contacts.size() == 3 and contacts[1].is_equal_approx(destination("e4")) and contacts[2].is_equal_approx(destination("e5")), "New confirmed moves must queue after the entire current route")
	check(starts.size() == 3 and finished.size() == 2 and not motion.moving, "Each hop must emit one takeoff and one landing, including a large frame delta")
	check(motion.rotation.length() < 0.001, "Landing must blend back into idle instead of jumping to its full pose")
	motion.advance(0.2)
	check(not motion.rotation.is_zero_approx(), "Idle must return gradually after the last landing")
	motion.enqueue(PieceMovePath.build("e5", "e7", "p", square_position))
	motion.advance(0.1)
	var contacts_before_disable := contacts.size()
	motion.set_enabled(false)
	check(motion.position.is_equal_approx(destination("e7")) and motion.rotation.is_zero_approx() and not motion.moving, "Disabling animation must finish the full queued route immediately")
	check(contacts.size() == contacts_before_disable, "Settings changes must not fabricate landing sounds")
	motion.set_enabled(true)
	motion.enqueue(PieceMovePath.build("e7", "e8", "p", square_position))
	motion.advance(0.05)
	motion.snap_to(destination("e8"))
	motion.advance(1.0)
	check(contacts.size() == contacts_before_disable and not motion.moving, "Resynchronization must cancel pending contacts silently")
	var fine := PieceAnimator.new()
	fine.setup(destination("a1"), "rook")
	fine.enqueue(PieceMovePath.build("a1", "a8", "r", square_position))
	for frame in range(182):
		fine.advance(0.01)
	check(fine.position.is_equal_approx(destination("a8")) and not fine.moving, "Seven squares must complete in approximately 1.82 seconds")
	clear_motion_observers(motion)


func clear_motion_observers(motion: PieceAnimator) -> void:
	# These test closures observe the motion object itself; break that reference cycle.
	for event: Signal in [motion.landed, motion.jump_started, motion.move_finished]:
		for connection: Dictionary in event.get_connections():
			event.disconnect(connection.callable)


func new_presenter() -> BoardPiecesPresenter:
	var presenter := BoardPiecesPresenter.new()
	presenter.setup(square_position)
	presenter.set_active(true)
	root.add_child(presenter)
	return presenter


func test_presenter() -> void:
	var presenter := new_presenter()
	var pieces: Array = [
		{"id": "white_e5", "kind": "p", "side": "white", "square": "e5"},
		{"id": "black_d5", "kind": "p", "side": "black", "square": "d5"},
	]
	presenter.synchronize(pieces, [])
	var pawn = presenter.get_node("white_e5")
	var pawn_id: int = pawn.get_instance_id()
	var model_id: int = pawn.miniature.get_instance_id()
	var sounds: Array[StringName] = []
	pawn.sfx.played.connect(func(event): sounds.append(event))
	pawn._process(0.3)
	var idle_pose: Vector3 = pawn.visual_pivot.rotation
	presenter.synchronize(pieces, [])
	check(pawn.visual_pivot.rotation.is_equal_approx(idle_pose) and sounds.is_empty(), "Unchanged snapshots must preserve idle and remain silent")
	pieces[0].square = "e6"
	presenter.synchronize(pieces, [])
	pawn._process(0.1)
	var moving_pose: Vector3 = pawn.position
	var shield: Array = [{"id": "shield", "piece_id": "white_e5", "kind": "shield"}]
	presenter.synchronize(pieces, shield)
	var ring_id: int = pawn.effects_root.get_child(0).get_instance_id()
	presenter.synchronize(pieces, shield)
	check(pawn.position.is_equal_approx(moving_pose) and pawn.effects_root.get_child(0).get_instance_id() == ring_id, "Repeated effects must preserve the animation and existing rings")
	pawn._process(0.16)
	check(pawn.get_instance_id() == pawn_id and pawn.miniature.get_instance_id() == model_id and not pawn.animator.moving, "Updates must not restart the route or replace the model")
	check(sounds == [&"impulse", &"landing"], "A one-square move must play exactly one impulse and one landing")
	presenter.synchronize(pieces, [{"id": "ice", "piece_id": "white_e5", "kind": "frozen"}])
	pawn._process(0.25)
	check(pawn.visual_pivot.rotation.is_zero_approx() and not pawn.is_processing(), "Frozen pieces must ease to rest")
	presenter.synchronize(pieces, [])
	pawn._process(0.25)
	check(not pawn.visual_pivot.rotation.is_zero_approx(), "Unfreezing must resume individual idle motion")
	pieces[0].square = "e7"
	presenter.synchronize(pieces, [], false)
	var before_resync := sounds.size()
	pieces[0].square = "e8"
	pieces[0].kind = "n"
	presenter.synchronize(pieces, shield)
	presenter.synchronize(pieces, shield)
	check(pawn.kind == "p", "Promotion must keep the pawn model until its final landing")
	pawn._process(0.26)
	check(pawn.kind == "n" and pawn.miniature.get_child(0).scene_file_path.ends_with("/blue/knight.glb"), "Promotion must replace the model on arrival, using the pawn's route")
	check(sounds.size() == before_resync + 2 and pawn.effects_root.get_child_count() == 1, "Promotion must preserve effects and emit only its real hop sounds")
	pieces[0].kind = "p"
	pieces[0].square = "e5"
	presenter.synchronize(pieces, [], false)
	var victim = presenter.get_node("black_d5")
	pieces.pop_back()
	pieces[0].square = "d6"
	presenter.synchronize(pieces, [])
	pawn._process(0.26)
	check(not is_instance_valid(victim) and pawn.position.is_equal_approx(destination("d6")), "En passant must remove the captured ID and animate the diagonal step")
	presenter.set_animations_enabled(false)
	var before_instant := sounds.size()
	pieces[0].square = "d7"
	presenter.synchronize(pieces, [])
	check(pawn.position.is_equal_approx(destination("d7")) and sounds.size() == before_instant + 1 and sounds[-1] == &"landing", "Disabled animations must play a single contact for a confirmed move")
	presenter.set_sounds_enabled(false)
	check(not pawn.sfx.impulse.playing and not pawn.sfx.landing.playing, "Muting must stop current playback immediately")
	pieces[0].square = "d8"
	presenter.synchronize(pieces, [])
	check(sounds.size() == before_instant + 1, "Muted confirmed moves must remain silent")
	presenter.set_animations_enabled(true)
	pieces[0].square = "d7"
	presenter.synchronize(pieces, [])
	pawn._process(0.1)
	presenter.synchronize([], [])
	check(not is_instance_valid(pawn) and presenter.get_child_count() == 0, "Capturing a moving piece must dispose of its queued motion and sounds")
	presenter.synchronize(pieces, [])
	check(presenter.get_child_count() == 1 and not presenter.get_node("white_e5").animator.moving, "Newly received pieces must appear directly at the authoritative square")
	presenter.clear()
	check(presenter.get_child_count() == 0, "Changing boards must clear all views and remembered squares")
	presenter.free()


func test_castling() -> void:
	for move: Array in [["e1", "g1", "h1", "f1"], ["e1", "c1", "a1", "d1"], ["e8", "g8", "h8", "f8"], ["e8", "c8", "a8", "d8"]]:
		var presenter := new_presenter()
		var side := "white" if move[0][1] == "1" else "black"
		var pieces: Array = [
			{"id": "rook", "kind": "r", "side": side, "square": move[2]},
			{"id": "king", "kind": "k", "side": side, "square": move[0]},
		]
		presenter.synchronize(pieces, [])
		var king = presenter.get_node("king")
		var rook = presenter.get_node("rook")
		var rook_sounds: Array[StringName] = []
		var king_sounds: Array[StringName] = []
		rook.sfx.played.connect(func(event): rook_sounds.append(event))
		king.sfx.played.connect(func(event): king_sounds.append(event))
		pieces[0].square = move[3]
		pieces[1].square = move[1]
		presenter.synchronize(pieces, [])
		rook._process(0.3)
		check(rook.position.is_equal_approx(destination(move[2])) and rook_sounds.is_empty(), "Castling rook must wait silently for the king, regardless of snapshot order")
		king._process(0.52)
		check(king.position.is_equal_approx(destination(move[1])) and not king.animator.moving, "Castling king must hop across its two squares first")
		rook._process(1.0)
		check(rook.position.is_equal_approx(destination(move[3])) and not rook.animator.moving, "The rook must finish after overflying the king's occupied square")
		check(rook_sounds.count(&"landing") == (1 if move[3][0] == "f" else 2), "Castling must not produce a landing on the king")
		presenter.set_animations_enabled(false)
		pieces[0].square = move[2]
		pieces[1].square = move[0]
		presenter.synchronize(pieces, [], false)
		var contacts_before := king_sounds.size() + rook_sounds.size()
		pieces[0].square = move[3]
		pieces[1].square = move[1]
		presenter.synchronize(pieces, [])
		check(king_sounds.size() + rook_sounds.size() == contacts_before + 1, "Instant castling must produce one contact for the whole confirmed move")
		presenter.free()


func match_snapshot(version: int = 0, square: String = "e2") -> Dictionary:
	return {
		"type": "match.snapshot", "match_id": "animation-test", "state_version": version,
		"viewer_side": "white", "active_side": "white", "status": "active", "clock_ms": {"white": 600000, "black": 600000},
		"pieces": [{"id": "white_e2", "kind": "p", "side": "white", "square": square}],
		"public_effects": [], "my_hand": [], "legal_moves": [], "can_cast": false,
		"my_mana": 2, "opponent_mana": 2, "opponent_hand_count": 3, "my_deck_count": 21,
		"tutorial": null, "draw_offer": null,
	}


func test_client() -> void:
	var game := FixtureGame.new()
	root.add_child(game)
	game.match_id = "animation-test"
	game.connected_match_id = game.match_id
	game.set_connection_state("connecting")
	game.handle_message(match_snapshot())
	var pawn = game.pieces_root.get_node("white_e2")
	var sounds: Array[StringName] = []
	pawn.sfx.played.connect(func(event): sounds.append(event))
	game.handle_message(match_snapshot(1, "e4"))
	pawn._process(0.1)
	var pose: Vector3 = pawn.position
	game.handle_message({"type": "clock.sync", "snapshot": match_snapshot(1, "e4")})
	check(pawn.position.is_equal_approx(pose) and sounds.size() == 1, "Clock messages must not restart motion or repeat sounds")
	game.set_connection_state("reconnecting")
	game.handle_message(match_snapshot(1, "e4"))
	check(game.pieces_root.get_node("white_e2") == pawn and not pawn.animator.moving, "Reconnecting at the same version must resync the existing piece immediately")
	check(pawn.position.is_equal_approx(game.world_square("e4") + Vector3(0, 0.095, 0)) and sounds.size() == 1, "Reconnection must cancel pending landings without audio")
	game.handle_message(match_snapshot(2, "e5"))
	pawn._process(0.1)
	var before_settings := sounds.size()
	game.change_setting("animations", false)
	check(not pawn.animator.moving and pawn.visual_pivot.rotation.is_zero_approx() and not game.cards_row.animate_moves, "The shared animation setting must finish motion and reset the pose immediately")
	check(sounds.size() == before_settings, "Disabling animations mid-jump must not add a false contact")
	game.change_setting("animations", true)
	game.change_setting("sound_effects", false)
	game.handle_message(match_snapshot(3, "e6"))
	pawn._process(0.26)
	check(sounds.size() == before_settings, "The sound setting must silence subsequent moves independently of animation")
	game.change_setting("sound_effects", true)
	var finished := match_snapshot(4, "e6")
	finished.status = "finished"
	finished.result_reason = "checkmate"
	finished.winner = "white"
	game.handle_message(finished)
	pawn._process(0.25)
	check(pawn.visual_pivot.rotation.is_zero_approx() and not pawn.is_processing(), "Ending a match must ease all idle pieces to rest")
	game.server_field.text = "http://127.0.0.1:9"
	game.session = {"access_token": "fixture"}
	game.match_id = "next-match"
	game.connect_match()
	check(game.pieces_root.get_child_count() == 0 and not is_instance_valid(pawn), "Changing matches must clear old visual state")
	var next := match_snapshot()
	next.match_id = game.match_id
	game.handle_message(next)
	check(game.pieces_root.get_child_count() == 1 and not game.pieces_root.get_node("white_e2").animator.moving, "A new match must start without movement or contact sounds")
	game.free()


func test_preferences_and_audio() -> void:
	var profile := "motion-test-" + str(Time.get_ticks_usec())
	var preferences := Preferences.new()
	preferences.load_profile(profile)
	var old_config := ConfigFile.new()
	old_config.set_value("general", "animations", false)
	old_config.save(preferences.path)
	preferences.load_profile(profile)
	check(preferences.values.sound_effects and not preferences.values.animations, "Existing profiles must default sound on and preserve their animation preference")
	preferences.values.sound_effects = false
	preferences.save()
	var reopened := Preferences.new()
	reopened.load_profile(profile)
	check(not reopened.values.sound_effects, "The sound preference must survive reopening")
	DirAccess.remove_absolute(preferences.path)
	check(PieceSfxPlayer.IMPULSE.get_length() > 0.02 and PieceSfxPlayer.IMPULSE.get_length() < 0.15, "Impulse audio must be a short valid sample")
	for stream: AudioStreamWAV in PieceSfxPlayer.LANDINGS:
		check(stream.get_length() > 0.05 and stream.get_length() < 0.2 and stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, "Landing samples must be short, valid and non-looping")
	var sound := PieceSfxPlayer.new()
	root.add_child(sound)
	sound.setup("sample")
	var events: Array[StringName] = []
	sound.played.connect(func(event): events.append(event))
	sound.play_impulse()
	sound.play_landing()
	check(events == [&"impulse", &"landing"], "Enabled players must dispatch contact sounds")
	sound.set_enabled(false)
	check(not sound.impulse.playing and not sound.landing.playing, "Mute must interrupt both sound players")
	sound.play_landing()
	check(events.size() == 2, "Muted players must ignore new sound requests")
	sound.free()


func capture_preview(suffix: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--screenshot-prefix="):
			await RenderingServer.frame_post_draw
			var path := argument.trim_prefix("--screenshot-prefix=") + suffix + ".png"
			check(root.get_texture().get_image().save_png(path) == OK, "Could not save animation preview")


func test_full_board() -> void:
	var game := Preview.PreviewGame.new()
	root.add_child(game)
	game.snapshot = match_snapshot()
	game.snapshot.pieces = initial_pieces()
	game.set_connection_state("connected")
	game.render_snapshot(false)
	await process_frame
	await physics_frame
	check(game.pieces_root.get_child_count() == 32, "A full animated board must contain 32 persistent views")
	for piece in game.pieces_root.get_children():
		piece._process(0.375)
	await capture_preview("-idle")
	for side: String in ["white", "black"]:
		game.snapshot.viewer_side = side
		game.position_camera()
		var move := "e2e4" if side == "white" else "e7e5"
		game.snapshot.legal_moves = [move]
		await process_frame
		await game._smoke_click_square(move.substr(0, 2))
		await game._smoke_click_square(move.substr(2, 2))
		check(game.received_commands.back().payload == {"from": move.substr(0, 2), "to": move.substr(2, 2)}, "Real mouse selection must work during individual idle motion for both armies")
	game.snapshot.viewer_side = "white"
	game.position_camera()
	var recording: AudioEffectRecord
	var recording_path := ""
	var recording_index := -1
	if DisplayServer.get_name() != "headless":
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--audio-preview="):
				recording_path = argument.trim_prefix("--audio-preview=")
				recording = AudioEffectRecord.new()
				recording.format = AudioStreamWAV.FORMAT_16_BITS
				recording_index = AudioServer.get_bus_effect_count(0)
				AudioServer.add_bus_effect(0, recording)
				recording.set_recording_active(true)
	game.snapshot.pieces[8].square = "e4"
	game.snapshot.pieces[3].square = "c3"
	game.render_snapshot()
	for piece in game.pieces_root.get_children():
		piece._process(0.11)
		piece.set_process(false)
	await capture_preview("-move")
	game.snapshot.legal_moves = ["e4e5"]
	await game._smoke_click_square("e4")
	await game._smoke_click_square("e5")
	check(game.received_commands.back().payload == {"from": "e4", "to": "e5"}, "Picking must follow authoritative squares during multi-hop travel")
	if DisplayServer.get_name() != "headless":
		for piece in game.pieces_root.get_children():
			piece.set_process(piece.animator.needs_processing())
		await create_timer(2.0).timeout
	if recording != null:
		recording.set_recording_active(false)
		check(recording.get_recording().save_to_wav(recording_path) == OK, "Could not save the actual mixed contact audio")
		AudioServer.remove_bus_effect(0, recording_index)
	game.free()


func run() -> void:
	root.size = Vector2i(1920, 1080)
	test_paths()
	test_idle()
	test_animator()
	test_presenter()
	test_castling()
	test_client()
	test_preferences_and_audio()
	await test_full_board()
	# Let the audio mixer release stopped playback instances before quitting.
	await create_timer(0.2).timeout
	print("PIECES: individual idle, square-by-square paths, L-shaped overflights, queued hops, contact audio, promotion, capture, castling, preferences, reconnection and picking; checks=", checks, "; failures=", failures)
	quit(0 if failures == 0 else 1)
