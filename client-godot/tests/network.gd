extends SceneTree
## Controlled HTTP/WebSocket failures against tools/test_client_network.py.

const PREVIEW = preload("res://tests/models.gd")
var failures = 0


func _initialize():
	call_deferred("run")


func check(value, message):
	if not value:
		failures += 1
		push_error(message)


func wait_for_open(game):
	var deadline = Time.get_ticks_msec() + 5000
	while game.socket.get_ready_state() != WebSocketPeer.STATE_OPEN and Time.get_ticks_msec() < deadline:
		await create_timer(0.02).timeout
	check(game.socket.get_ready_state() == WebSocketPeer.STATE_OPEN, "Fixture socket must open")


func run():
	var address = ""
	var refused = ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--fixture="):
			address = argument.trim_prefix("--fixture=")
		elif argument.begins_with("--refused="):
			refused = argument.trim_prefix("--refused=")
	check(address != "" and refused != "", "Local fixtures are required")
	if failures:
		quit(1)
		return
	var game = PREVIEW.PreviewGame.new()
	root.add_child(game)
	game.set_process(true)
	game.token_deadline = Time.get_ticks_msec() + 1800000
	game.server_field.text = refused
	game.session = {"access_token": "NETWORK_TEST_SECRET"}
	game.match_id = "unreachable"
	game.connect_match()
	var deadline = Time.get_ticks_msec() + 45000
	while game.connection_state != "failed" and Time.get_ticks_msec() < deadline:
		if game.retry_at > 0:
			check(game.retry_at - Time.get_ticks_msec() <= game.RETRY_DELAYS_MS[game.connection_attempt - 1], "Retry delay must be bounded")
			game.retry_at = Time.get_ticks_msec() - 1
		await create_timer(0.03).timeout
	check(game.connection_state == "failed" and game.connection_attempt == 3, "Unavailable server must stop after three retries")
	game.server_field.text = address
	game.session = {"access_token": "NETWORK_TEST_SECRET", "refresh_token": "NETWORK_TEST_REFRESH"}
	game.match_id = "reject"
	game.connect_match()
	deadline = Time.get_ticks_msec() + 10000
	while game.connection_state != "failed" and Time.get_ticks_msec() < deadline:
		if game.retry_at > 0:
			game.retry_at = Time.get_ticks_msec() - 1
		await create_timer(0.03).timeout
	check(game.connection_state == "failed" and game.session.is_empty(), "Rejected refresh must end authentication retries")
	check(game.status_label.text.contains("expirou"), "Authentication failure must tell the player how to recover")
	game.session = {"access_token": "NETWORK_TEST_SECRET"}
	game.match_id = "no-snapshot"
	game.connect_match()
	for attempt in range(4):
		await wait_for_open(game)
		check(game.connection_state != "connected", "An open socket alone must not confirm a match")
		game.check_connection_timeout(game.connection_deadline + 1)
		if attempt < 3:
			game.retry_at = Time.get_ticks_msec() - 1
			await create_timer(0.1).timeout
	check(game.connection_state == "failed" and game.retry_at == 0, "Missing snapshots must exhaust retries")
	game.queue_free()
	await process_frame
	print("NETWORK: refused server, rejected authentication and missing snapshots; failures=", failures)
	quit(0 if failures == 0 else 1)
