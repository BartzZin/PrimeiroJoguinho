extends RefCounted
## Preferences live apart from session credentials and are scoped to each profile.

const DEFAULTS = {"detailed_logs": false, "quality": 2, "animations": true, "top_view": false, "fullscreen": false, "sidebar_visible": false}
var values = DEFAULTS.duplicate()
var path = ""


func load_profile(profile: String) -> Error:
	path = "user://preferences_" + profile.validate_filename() + ".cfg"
	values = DEFAULTS.duplicate()
	var config = ConfigFile.new()
	var result = config.load(path)
	if result != OK:
		return OK if result == ERR_FILE_NOT_FOUND else result
	for key in DEFAULTS:
		var value = config.get_value("general", key, DEFAULTS[key])
		if key == "quality":
			if value is int and value >= 0 and value <= 2:
				values[key] = value
		elif value is bool:
			values[key] = value
	return OK


func save() -> Error:
	if path == "":
		return ERR_UNCONFIGURED
	var config = ConfigFile.new()
	for key in DEFAULTS:
		config.set_value("general", key, values[key])
	return config.save(path)
