extends Logger
## Local structured diagnostics. Never serialize network bodies or game snapshots.

const FIELDS = ["match_id", "request_id", "kind", "code", "status", "duration_ms", "attempt", "close_code", "file", "function", "line", "error_type", "message", "square", "pid", "version", "side", "stage", "reason"]
var detailed = false
var directory = ""
var path = ""
var available = false
var max_file_bytes = 2 * 1024 * 1024
var max_closed_files = 5
var _mutex = Mutex.new()
var _writing = false
var _file: FileAccess
var _base = ""
var _segment = 0


func setup(profile: String, folder_override = ""):
	directory = folder_override if folder_override != "" else "user://logs/" + profile.validate_filename()
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) != OK:
		return
	_base = "client-%s-%s-%s" % [Time.get_datetime_string_from_system(true).replace(":", "-"), OS.get_process_id(), Time.get_ticks_usec()]
	_open_segment()
	_prune_closed()


func _open_segment():
	path = directory.path_join(_base + "-%03d.jsonl" % _segment)
	_file = FileAccess.open(path, FileAccess.WRITE)
	available = _file != null
	if available:
		var marker = FileAccess.open(path + ".active", FileAccess.WRITE)
		if marker != null:
			marker.store_string(str(OS.get_process_id()))
			marker.close()


func _prune_closed():
	var dir = DirAccess.open(directory)
	if dir == null:
		return
	var closed: Array[String] = []
	for name in dir.get_files():
		if not name.ends_with(".jsonl"):
			continue
		var full_path = directory.path_join(name)
		if FileAccess.file_exists(full_path + ".active"):
			var marker = FileAccess.open(full_path + ".active", FileAccess.READ)
			if marker != null:
				var pid = int(marker.get_as_text())
				marker.close()
				if pid > 0 and OS.is_process_running(pid):
					continue
			DirAccess.remove_absolute(full_path + ".active")
		closed.append(full_path)
	closed.sort()
	while closed.size() > max_closed_files:
		DirAccess.remove_absolute(closed.pop_front())


static func redact(value: String) -> String:
	var result = value.left(2048)
	for pattern in [
		"(?i)Bearer\\s+[A-Za-z0-9._~+/-]+=*",
		"(?i)(?:postgresql[^: ]*|https?)://[^/@ :]+:[^/@ ]+@",
		"(?i)[\"']?(?:access_token|refresh_token|authorization|invite|room_code|password|secret|my_hand|my_traps|payload)[\"']?\\s*[:=]\\s*(?:\"[^\"]*\"|'[^']*'|[^\\s,;}]+)",
	]:
		var expression = RegEx.new()
		if expression.compile(pattern) == OK:
			result = expression.sub(result, "[REDACTED]", true)
	return result


func record(level: String, event: String, fields = {}):
	if level != "ERROR" and not detailed:
		return
	_mutex.lock()
	# File system errors can themselves invoke Logger. Avoid recursive logging.
	if _writing or not available:
		_mutex.unlock()
		return
	_writing = true
	var entry = {"time": Time.get_datetime_string_from_system(true) + "Z", "level": level, "event": event}
	for key in fields:
		if key in FIELDS:
			var value = fields[key]
			if value is String:
				entry[key] = redact(value)
			elif value is int or value is float or value is bool:
				entry[key] = value
	var encoded = (JSON.stringify(entry) + "\n").to_utf8_buffer()
	if encoded.size() <= max_file_bytes:
		if _file.get_position() + encoded.size() > max_file_bytes:
			_file.close()
			DirAccess.remove_absolute(path + ".active")
			_segment += 1
			_open_segment()
			_prune_closed()
		if available:
			_file.store_buffer(encoded)
			_file.flush()
			available = _file.get_error() == OK
	_writing = false
	_mutex.unlock()


func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]):
	record("WARNING" if error_type == Logger.ERROR_TYPE_WARNING else "ERROR", "engine_error", {
		"function": function, "file": file, "line": line, "error_type": error_type,
		"message": rationale if rationale != "" else code,
	})


func close():
	_mutex.lock()
	_writing = true
	if _file != null:
		_file.close()
		_file = null
	if path != "":
		DirAccess.remove_absolute(path + ".active")
	available = false
	if directory != "":
		_prune_closed()
	_writing = false
	_mutex.unlock()
