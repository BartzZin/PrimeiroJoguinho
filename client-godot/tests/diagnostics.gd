extends SceneTree

const LOG = preload("res://diagnostics.gd")
const PREFS = preload("res://preferences.gd")
const PREVIEW = preload("res://tests/models.gd")
var failures = 0
var directory = "user://diagnostics-tests/" + str(Time.get_ticks_usec())

class RefreshGame:
	extends "res://main.gd"

	func _ready():
		status_label = Label.new()
		server_field = LineEdit.new()
		add_child(status_label)
		add_child(server_field)
		set_process(false)

	func api_result(_method, _path, _body = {}):
		await get_tree().create_timer(0.1).timeout
		return {"ok": true, "status": 200, "data": {"access_token": "fresh-test-token", "refresh_token": "rotated-test-token", "expires_in": 1800}}


func _initialize():
	call_deferred("run")


func check(condition, message):
	if not condition:
		failures += 1
		push_error(message)


func read_logs(folder):
	var output = ""
	for name in DirAccess.get_files_at(folder):
		if name.ends_with(".jsonl"):
			output += FileAccess.get_file_as_string(folder.path_join(name))
	return output


func expected_script_error():
	var sample: Variant = {}
	return sample.DIAGNOSTICS_EXPECTED_MISSING_KEY


func thread_records(logger, number):
	for index in range(20):
		logger.record("ERROR", "thread_event", {"version": number * 20 + index})


func snapshot():
	return {
		"type": "match.snapshot", "match_id": "test-match", "state_version": 0,
		"viewer_side": "white", "active_side": "white", "status": "active", "clock_ms": {"white": 600000, "black": 600000},
		"pieces": [{"id": "pawn", "kind": "p", "side": "white", "square": "e2"}],
		"public_effects": [], "my_hand": [], "legal_moves": ["e2e4"], "can_cast": true,
		"my_mana": 2, "opponent_mana": 2, "opponent_hand_count": 3, "my_deck_count": 21,
		"tutorial": null, "draw_offer": null,
	}


func run():
	root.size = Vector2i(1920, 1080)
	var logger = LOG.new()
	logger.setup("test", directory.path_join("basic"))
	check(logger.available, "Logger must open its local folder")
	logger.record("INFO", "disabled_detail")
	logger.record("ERROR", "basic_error", {"message": "Bearer sensitive-access refresh_token=sensitive-refresh", "payload": "PRIVATE_HAND", "invite": "PRIVATE_INVITE"})
	var text = read_logs(logger.directory)
	check(text.contains("basic_error") and not text.contains("disabled_detail"), "Disabled diagnostics must retain only basic errors")
	check(not text.contains("sensitive-access") and not text.contains("sensitive-refresh") and not text.contains("PRIVATE_HAND") and not text.contains("PRIVATE_INVITE"), "Secrets must be redacted or discarded")
	OS.add_logger(logger)
	print("An expected script error follows to verify automatic Logger capture:")
	expected_script_error()
	OS.remove_logger(logger)
	text = read_logs(logger.directory)
	check(text.contains("engine_error") and text.contains("diagnostics.gd") and text.contains("expected_script_error"), "Script errors must include source locations")
	var threads = []
	for number in range(3):
		var thread = Thread.new()
		thread.start(thread_records.bind(logger, number))
		threads.append(thread)
	for thread in threads:
		thread.wait_to_finish()
	for line in read_logs(logger.directory).strip_edges().split("\n"):
		var parser = JSON.new()
		check(parser.parse(line) == OK, "Concurrent logs must remain valid JSONL")
	logger.close()
	var rotating = LOG.new()
	rotating.max_file_bytes = 512
	rotating.max_closed_files = 2
	rotating.setup("rotation", directory.path_join("rotation"))
	for index in range(40):
		rotating.record("ERROR", "rotate", {"version": index, "message": "A small log entry for bounded rotation"})
	rotating.close()
	var files = DirAccess.get_files_at(rotating.directory)
	check(files.size() <= 2 and files.size() > 0, "Rotation must retain the configured number of closed files")
	for name in files:
		var file = FileAccess.open(rotating.directory.path_join(name), FileAccess.READ)
		check(file.get_length() <= 512, "Rotated files must respect the size limit")
		file.close()
	var blocker_path = directory.path_join("not-a-directory")
	var blocker = FileAccess.open(blocker_path, FileAccess.WRITE)
	blocker.store_string("block directory creation")
	blocker.close()
	var blocked = LOG.new()
	blocked.setup("blocked", blocker_path.path_join("logs"))
	blocked.record("ERROR", "cannot_write")
	check(not blocked.available, "An inaccessible folder must disable logging without interrupting the client")
	blocked.close()
	var refreshing = RefreshGame.new()
	root.add_child(refreshing)
	refreshing.profile = "test-refresh-" + str(Time.get_ticks_usec())
	refreshing.session = {"refresh_token": "old-test-token"}
	refreshing.match_id = "first"
	refreshing.refresh_session.call_deferred(false)
	await create_timer(0.02).timeout
	refreshing.connection_generation += 1
	refreshing.match_id = "second"
	await create_timer(0.15).timeout
	check(refreshing.session.get("refresh_token") == "rotated-test-token", "Changing matches must not discard a rotated refresh token")
	refreshing.session = {"refresh_token": "old-test-token"}
	refreshing.refresh_session.call_deferred(false)
	await create_timer(0.02).timeout
	refreshing.session = {"refresh_token": "other-session-token"}
	await create_timer(0.15).timeout
	check(refreshing.session.get("refresh_token") == "other-session-token", "An old refresh must not overwrite a different login")
	DirAccess.remove_absolute("user://session_" + refreshing.profile + ".cfg")
	refreshing.queue_free()
	var game = PREVIEW.PreviewGame.new()
	root.add_child(game)
	var test_profile = "test-diagnostics-" + str(Time.get_ticks_usec())
	game.preferences.load_profile(test_profile)
	game.diagnostics = LOG.new()
	game.diagnostics.setup(test_profile, directory.path_join("ui"))
	OS.add_logger(game.diagnostics)
	game.match_id = "test-match"
	game.connected_match_id = game.match_id
	game.set_connection_state("connecting")
	game.set_status("Conectando à partida…")
	game.handle_message(snapshot())
	check(game.connection_state == "connected" and not game.status_label.text.contains("Conectando"), "First snapshot must confirm connection")
	game.set_status("Ação confirmada pelo servidor.")
	game.handle_message({"type": "clock.sync", "snapshot": snapshot()})
	check(game.status_label.text == "Ação confirmada pelo servidor.", "Clock snapshots must preserve action feedback")
	var stale = snapshot()
	stale.match_id = "another-match"
	game.handle_message(stale)
	check(game.snapshot.match_id == "test-match", "Snapshots from an old match must be ignored")
	var invalid = snapshot()
	invalid.my_hand = [null]
	check(not game.valid_snapshot(invalid), "Malformed hands must not reach the renderer")
	invalid = snapshot()
	invalid.pieces[0].square = "z9"
	check(not game.valid_snapshot(invalid), "Invalid board coordinates must not reach picking")
	for attempt in range(4):
		game.connection_deadline = 1
		game.check_connection_timeout(2)
		if attempt < 3:
			check(game.connection_state == "reconnecting" and game.connection_attempt == attempt + 1 and game.retry_at > 0, "Timeout must schedule a bounded retry")
	check(game.connection_state == "failed" and game.retry_at == 0, "Retry exhaustion must show a terminal failure")
	game.handle_message(snapshot())
	game._connection_failed("NOT_AUTHENTICATED", 1008, true)
	check(game.connection_state == "failed" and game.retry_at == 0, "Authentication failure must be actionable")
	game.handle_message(snapshot())
	game.pending["request-test"] = {"command": {}, "sent_at": 0}
	game.session = {"access_token": "test-placeholder"}
	game.server_field.text = "http://127.0.0.1:9"
	game.connect_match()
	check(game.pending.has("request-test"), "Manual reconnect must retain command IDs for the same match")
	var generation = game.connection_generation
	game.match_id = "new-match"
	game.connect_match()
	check(game.pending.is_empty() and game.connection_generation > generation, "Changing matches must cancel old work")
	game.socket.close()
	game.match_id = "test-match"
	game.handle_message(snapshot())
	await process_frame
	await physics_frame
	check(not game.gear_button.get_global_rect().intersects(game.stage.get_global_rect()) and not game.gear_button.get_global_rect().intersects(game.cards_row.get_global_rect()), "Gear must reserve space outside the board and cards")
	await game._smoke_mouse_click(game.gear_button.get_global_rect().get_center())
	check(game.settings_menu.visible, "Gear mouse click must open settings")
	await process_frame
	check(Rect2(Vector2.ZERO, game.size).encloses(game.settings_menu.panel.get_global_rect()), "Settings must stay inside the window")
	check(game.settings_menu.content.get_child(1) == game.settings_menu.logs_checkbox, "Detailed logs must be the first setting")
	game.settings_menu.logs_checkbox.button_pressed = true
	check(game.diagnostics.detailed, "Checkbox must enable diagnostics immediately")
	var saved = PREFS.new()
	saved.load_profile(test_profile)
	check(saved.values.detailed_logs, "Diagnostic preference must survive reopening")
	game.settings_menu.logs_checkbox.button_pressed = false
	check(not game.diagnostics.detailed, "Unchecking must disable detailed events immediately")
	var escape = InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	root.push_input(escape, true)
	check(not game.settings_menu.visible, "Escape must close settings")
	await game._smoke_mouse_click(game.gear_button.get_global_rect().get_center())
	await game._smoke_mouse_click(game.gear_button.get_global_rect().get_center())
	check(not game.settings_menu.visible, "Clicking the gear again must close settings")
	await game._smoke_mouse_click(game.gear_button.get_global_rect().get_center())
	game.clear_selection()
	await game._smoke_click_square("e2")
	check(not game.settings_menu.visible and game.selected_square == "", "A click outside settings must close them without moving a piece underneath")
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 800)
	await process_frame
	await process_frame
	await game._smoke_click_square("e2")
	check(game.selected_square == "e2", "Mouse picking must work after resizing")
	if DisplayServer.get_name() != "headless":
		var f11 = InputEventKey.new()
		f11.keycode = KEY_F11
		f11.pressed = true
		root.push_input(f11, true)
		check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN, "F11 action must enter fullscreen")
		game.settings_menu.toggle(game.preferences.values)
		root.push_input(escape, true)
		check(not game.settings_menu.visible and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN, "Escape must close settings before leaving fullscreen")
		root.push_input(escape, true)
		check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MAXIMIZED, "Escape must leave fullscreen when settings are closed")
	DirAccess.remove_absolute(game.preferences.path)
	game.queue_free()
	await process_frame
	print("DIAGNOSTICS: logs, script errors, threads, rotation, write failures, connection states, retries, settings, preferences and input; failures=", failures)
	quit(0 if failures == 0 else 1)
