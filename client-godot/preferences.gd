extends RefCounted
## Preferences live apart from session credentials and are scoped to each profile.

const DEFAULTS = {"detailed_logs": false, "quality": 3, "render_scale": 0, "show_fps": false, "shadows": true, "animations": true, "sound_effects": true, "top_view": false, "fullscreen": false, "sidebar_visible": false}
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
			if value is int and value >= 0 and value <= 3:
				values[key] = value
		elif key == "render_scale":
			if value is int and value in [0,67,75,85,100]:
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
