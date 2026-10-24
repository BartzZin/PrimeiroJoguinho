extends RefCounted
## Local rendering policy. No hardware estimate is presented as measured FPS.
const AUTO = 3
const SCALES = [0, 67, 75, 85, 100]

static func resolve(selection: int, adapter: String) -> int:
	if selection != AUTO:
		return clampi(selection,0,2)
	var name = adapter.to_lower()
	for low in ["1050", "1030", "950", "960", "750", "intel", "vega", "radeon graphics"]:
		if name.contains(low): return 0
	if name.contains("rtx") or name.contains("rx 7") or name.contains("rx 8"):
		return 2
	return 1

static func configuration(level: int, scale_percent = 0) -> Dictionary:
	level = clampi(level,0,2)
	return {"level":level,"scale":float(scale_percent)/100.0 if scale_percent > 0 else [0.67,0.85,1.0][level],
		"lod": [5.0,2.5,1.0][level],"shadow_size": [2048,2048,4096][level],
		"shadow_distance": [20.0,30.0,80.0][level],"ssao":level>0,"ssil":level==2,
		"volumetric":level==2,"reflections":level>0,"sky_resolution": "4k" if level==2 else "1k"}
