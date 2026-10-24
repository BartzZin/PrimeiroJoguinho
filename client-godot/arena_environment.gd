extends Node3D
## Persistent decorative world. It never receives private match data or colliders.

const WATER_SHADER = preload("res://assets/arena/waterfall.gdshader")
const BANNER_SHADER = preload("res://assets/arena/banner.gdshader")
const REALM_SHADER = preload("res://assets/arena/realm.gdshader")
const MARBLE_SHADER = preload("res://assets/arena/marble.gdshader")
const SUN_DIRECTION = Vector3(0.306298, 0.853760, 0.421040)
const CLOUD_SHADER = preload("res://assets/arena/cloud_sea.gdshader")
const PHOTO_SKY = preload("res://assets/arena/photographic_sky.gdshader")
var animation_enabled = true:
	set(value):
		animation_enabled = value
		set_process(value)
var elapsed = 0.0
var sky_material: Material
var water_materials: Array[ShaderMaterial] = []
var banner_materials: Array[ShaderMaterial] = []
var environment: Environment
var scene_cache = {}
var material_cache = {}
var world_islands: Array[Node3D] = []
var ornaments: Array[Node3D] = []
var probe: ReflectionProbe
var fragment_nodes: Array[Node3D] = []
var world_meshes: Array[MeshInstance3D] = []
var quality_level = 2
var sky_path = ""
var cloud_material: ShaderMaterial
var cloud_planes: Array[Node3D] = []
var cloud_volumes: Array[FogVolume] = []


func _ready():
	name = "CelestialArena"
	place("platform", Vector3.ZERO)
	# Tall ornaments sit outside the useful playing area and below the camera rays.
	for i in range(8):
		var a = TAU * (i + 0.5) / 8.0
		var p = Vector3(cos(a) * 11.1, -0.55, sin(a) * 11.1)
		var crimson = p.x > 0
		var ornament = place("pillar", p, 1.0, crimson)
		ornaments.append(ornament)
		add_banner(p + Vector3(0, 0.8, 0), a, crimson)
		place("crystal", Vector3(cos(a)*10.1, -0.55, sin(a)*10.1), 0.5, crimson)
	# Main islands and satellites form an entire world, not a one-sided stage set.
	var positions = [Vector3(-35,-8,-42), Vector3(35,-8,-42), Vector3(-39,-10,35), Vector3(39,-10,35), Vector3(0,-14,-64), Vector3(0,-15,57), Vector3(-67,-17,0), Vector3(67,-17,0)]
	for i in range(positions.size()):
		var p = positions[i]
		var crimson = p.x > 0 or i == 5
		var main = i < 2
		var island = place("island", p, 2.0 if main else 1.2, crimson)
		world_islands.append(island)
		var palace = place("castle", p + Vector3(0, 0.12, 0), 0.9 if main else 0.45, crimson)
		palace.rotation.y = -0.25 if crimson else 0.25
		add_waterfall(p + Vector3(0, -9 if main else -6, 9 if main else 5), 3.0 if main else 1.7, 18 if main else 12, crimson)
		# Rock fragments carry real volume even when seen from below.
		for k in range(2):
			var offset = Vector3(9 + k * 6, -6-k*4, 4-k*9)
			fragment_nodes.append(place("island", p + offset, 0.18 + k * 0.09, crimson))
	for pair in [[0,6],[1,7],[2,5],[3,5]]:
		var start = positions[pair[0]]
		var end = positions[pair[1]]
		var direction = (end-start).normalized()
		start += direction*10.0
		end -= direction*6.0
		var bridge = place("bridge", (start+end)*0.5+Vector3(0,0.2,0), 1.0, start.x > 0)
		var x = (end-start).normalized()
		var y = (Vector3.UP-x*x.dot(Vector3.UP)).normalized()
		bridge.basis = Basis(x,y,x.cross(y))*Basis.from_scale(Vector3(start.distance_to(end)/18.0,1,1))
	build_cloud_sea()
	set_quality(quality_level)
	set_process(animation_enabled)


func place(asset: String, position_value: Vector3, scale_value = 1.0, crimson = false) -> Node3D:
	var path = "res://assets/arena/" + asset + ".glb"
	var result: Node3D
	if not scene_cache.has(path) and ResourceLoader.exists(path):
		var resource = load(path)
		if resource is PackedScene:
			scene_cache[path] = resource
	if scene_cache.has(path):
		result = scene_cache[path].instantiate()
	else:
		push_warning("Recurso decorativo da arena indisponível: " + asset)
		result = Node3D.new()
	result.name = asset.capitalize().replace(" ", "") + str(get_child_count())
	result.position = position_value
	result.scale = Vector3.ONE * scale_value
	decorate(result, crimson, asset == "island", asset == "crystal")
	add_child(result)
	return result


func decorate(node: Node, crimson: bool, rocky = false, crystal_asset = false):
	if node is MeshInstance3D:
		world_meshes.append(node)
		node.visibility_range_end = 210
		node.lod_bias = 0.8
		for surface in range(node.mesh.get_surface_count()):
			var original = node.get_active_material(surface)
			if original is StandardMaterial3D:
				var key = str(original.get_instance_id()) + str(crimson)
				if not material_cache.has(key):
					if original.albedo_texture != null:
						var paint = ShaderMaterial.new()
						paint.shader = REALM_SHADER
						paint.set_shader_parameter("albedo_map", original.albedo_texture)
						paint.set_shader_parameter("crimson", crimson)
						paint.set_shader_parameter("rocky", rocky)
						paint.set_shader_parameter("crystal_asset", crystal_asset)
						paint.set_shader_parameter("detail_map", preload("res://assets/arena/limestone.png"))
						paint.set_shader_parameter("has_normal", original.normal_texture != null)
						if original.normal_texture != null:
							paint.set_shader_parameter("normal_map", original.normal_texture)
						material_cache[key] = paint
					else:
						var paint = original.duplicate()
						var color = paint.albedo_color
						if crimson and color.b > color.r * 1.5:
							paint.albedo_color = Color(color.b * 0.8, color.g * 0.3, color.r * 0.5)
						if original.resource_name.contains("marble") or original.resource_name.contains("limestone"):
							var stone = ShaderMaterial.new()
							stone.shader = MARBLE_SHADER
							stone.set_shader_parameter("stone_map", preload("res://assets/arena/limestone.png"))
							stone.set_shader_parameter("stone_tint", Color("d6cec0") if original.resource_name.contains("marble") else Color("b4ad9b"))
							material_cache[key] = stone
						else:
							material_cache[key] = paint
				node.set_surface_override_material(surface, material_cache[key])
	for child in node.get_children():
		decorate(child, crimson, rocky, crystal_asset)


func configure_environment(value: Environment):
	environment = value
	sky_material = ShaderMaterial.new()
	sky_material.shader = PHOTO_SKY
	environment.background_mode = Environment.BG_SKY
	environment.sky = Sky.new()
	environment.sky.sky_material = sky_material
	# A photographic HDR sky is cached once, not recaptured every frame.
	environment.sky.process_mode = Sky.PROCESS_MODE_QUALITY
	environment.sky.radiance_size = Sky.RADIANCE_SIZE_256
	environment.background_energy_multiplier = 0.65
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b1bfce")
	environment.ambient_light_energy = 0.25
	environment.ambient_light_sky_contribution = 0.25
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC if RenderingServer.get_current_rendering_method() == "gl_compatibility" else Environment.TONE_MAPPER_AGX
	environment.fog_enabled = true
	environment.fog_light_color = Color("bad3ec")
	environment.fog_density = 0.0007
	environment.fog_sky_affect = 0.12
	environment.glow_enabled = true
	environment.glow_intensity = 0.35
	environment.volumetric_fog_density = 0.0004
	environment.volumetric_fog_length = 110
	set_quality(quality_level)


func set_quality(level: int):
	quality_level = level
	if environment != null:
		environment.volumetric_fog_enabled = level == 2 and RenderingServer.get_current_rendering_method() == "forward_plus"
		environment.glow_enabled = level > 0
	if sky_material is ShaderMaterial:
		var path = "res://assets/arena/sky/celestial_"+("4k" if level == 2 else "1k")+".hdr"
		if sky_path != path and ResourceLoader.exists(path):
			sky_material.set_shader_parameter("panorama",load(path))
			sky_path = path
	if level > 0 and not is_instance_valid(probe):
		probe = ReflectionProbe.new()
		probe.name = "ArenaReflection"
		probe.position = Vector3(0,3,0)
		probe.size = Vector3(30,16,30)
		probe.max_distance = 90
		probe.update_mode = ReflectionProbe.UPDATE_ONCE
		probe.intensity = 0.5
		probe.cull_mask = 1
		probe.mesh_lod_threshold = 3.0
		add_child(probe)
	if is_instance_valid(probe):
		probe.visible = level > 0
	for node in world_islands:
		node.visible = true
	for node in fragment_nodes:
		node.visible = level > 0
	for i in range(cloud_planes.size()):
		cloud_planes[i].visible = level > 0 or i == 0
	if level == 2:
		ensure_cloud_volumes()
	for node in cloud_volumes:
		node.visible = level == 2 and RenderingServer.get_current_rendering_method() == "forward_plus"
	for node in world_meshes:
		node.lod_bias = 0.7 if level == 0 else 1.0
		if node.is_inside_tree() and node.global_position.length() > 25:
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if level == 2 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for paint in material_cache.values():
		if paint is ShaderMaterial:
			paint.set_shader_parameter("detail_strength", [0.0,0.25,0.4][level])


func build_cloud_sea():
	var noise = FastNoiseLite.new()
	noise.seed = 42
	noise.frequency = 0.012
	noise.fractal_octaves = 5
	var texture = NoiseTexture2D.new()
	texture.width = 512
	texture.height = 512
	texture.seamless = true
	texture.generate_mipmaps = true
	texture.noise = noise
	cloud_material = ShaderMaterial.new()
	cloud_material.shader = CLOUD_SHADER
	cloud_material.set_shader_parameter("cloud_noise",texture)
	for i in range(2):
		var mesh = MeshInstance3D.new()
		mesh.name = "CloudSea"+str(i)
		var plane = PlaneMesh.new()
		plane.size = Vector2(500,500)
		mesh.mesh = plane
		mesh.position = Vector3(i*12,-25-i*7,0)
		mesh.material_override = cloud_material
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cloud_planes.append(mesh)
		add_child(mesh)


func ensure_cloud_volumes():
	if not cloud_volumes.is_empty() or RenderingServer.get_current_rendering_method() != "forward_plus":
		return
	var noise = FastNoiseLite.new()
	noise.seed = 42
	noise.frequency = 0.06
	noise.fractal_octaves = 4
	var fog_noise = NoiseTexture3D.new()
	fog_noise.width = 32
	fog_noise.height = 32
	fog_noise.depth = 32
	fog_noise.seamless = true
	fog_noise.noise = noise
	var material = FogMaterial.new()
	material.density = 0.35
	material.albedo = Color("d8e2ee")
	material.density_texture = fog_noise
	material.edge_fade = 0.3
	for i in range(8):
		var fog = FogVolume.new()
		fog.shape = RenderingServer.FOG_VOLUME_SHAPE_ELLIPSOID
		fog.size = Vector3(44,20,34)
		var a = i*TAU/8
		fog.position = Vector3(cos(a)*43,-18,sin(a)*43)
		fog.material = material
		cloud_volumes.append(fog)
		add_child(fog)


func add_waterfall(position_value: Vector3, width: float, height: float, crimson: bool):
	var paint = ShaderMaterial.new()
	paint.shader = WATER_SHADER
	# Both kingdoms have water. A subtle warm tint distinguishes the red realm.
	paint.set_shader_parameter("water_color", Color("61b9ed") if not crimson else Color("c1a9cc"))
	water_materials.append(paint)
	for yaw in [0.0, PI / 2]:
		var mesh = MeshInstance3D.new()
		var plane = PlaneMesh.new()
		plane.orientation = PlaneMesh.FACE_Z
		plane.size = Vector2(width, height)
		plane.subdivide_width = 8
		plane.subdivide_depth = 24
		mesh.mesh = plane
		mesh.material_override = paint
		mesh.position = position_value
		mesh.rotation.y = yaw
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mesh)


func add_banner(position_value: Vector3, angle: float, crimson: bool):
	var paint = ShaderMaterial.new()
	paint.shader = BANNER_SHADER
	paint.set_shader_parameter("cloth_color", Color("761b29") if crimson else Color("143c85"))
	banner_materials.append(paint)
	var mesh = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	plane.orientation = PlaneMesh.FACE_Z
	plane.size = Vector2(1.05, 2.5)
	plane.subdivide_width = 8
	plane.subdivide_depth = 20
	mesh.mesh = plane
	mesh.material_override = paint
	mesh.position = position_value + Vector3(0, -0.5, 0)
	mesh.rotation.y = -angle - PI / 2
	add_child(mesh)


func _process(delta: float):
	elapsed += minf(delta, 0.1)
	if cloud_material != null:
		cloud_material.set_shader_parameter("cloud_time",elapsed)
	# Manual time uniforms freeze all atmospheric animation with the preference.
	for paint in water_materials:
		paint.set_shader_parameter("flow_time", elapsed)
	for paint in banner_materials:
		paint.set_shader_parameter("wind_time", elapsed)
