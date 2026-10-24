shader_type spatial;
render_mode cull_disabled;
uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic;
uniform bool has_normal = false;
uniform bool crimson = false;
uniform bool rocky = false;
uniform bool crystal_asset = false;
uniform sampler2D detail_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float detail_strength = 0.4;
varying vec3 world_position;
varying vec3 local_position;
void vertex() { world_position = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; local_position = VERTEX; }
void fragment() {
	vec3 c = texture(albedo_map,UV).rgb;
	// The generator interpreted this translucent gem as neutral/dark. Restore
	// its sapphire material on the actual faceted surface, preserving the gold.
	float gem = crystal_asset ? smoothstep(0.55,0.75,local_position.y)*(1.0-smoothstep(0.025,0.09,max(c.r,max(c.g,c.b))-min(c.r,min(c.g,c.b))))*(1.0-smoothstep(0.16,0.30,max(c.r,max(c.g,c.b)))) : 0.0;
	c = mix(c,vec3(0.02,0.16,0.65),gem);
	float blue = smoothstep(0.12,0.35,(c.b-c.r)/max(c.b,0.04))*smoothstep(0.0,0.15,(c.b-c.g)/max(c.b,0.04));
	float pale_stone = (1.0-blue)*(1.0-smoothstep(1.3,1.7,c.r/max(c.b,0.001)))*smoothstep(0.015,0.08,max(c.r,max(c.g,c.b)));
	if (crimson) { c = mix(c,vec3(c.b*0.85,c.g*0.18,c.r*0.32+0.005),blue); }
	else { c = mix(c,c*vec3(0.55,0.82,1.05),blue); }
	if (crimson && !rocky && !crystal_asset) { c *= mix(vec3(1.0),vec3(0.34,0.29,0.33),pale_stone); }
	if (rocky) {
		float grain = sin(world_position.x*21.0+sin(world_position.z*14.0))*sin(world_position.y*35.0+world_position.z*17.0);
		c *= 0.94+grain*0.08;
	}
	float weathering = 0.5;
	if (detail_strength > 0.0) {
		weathering = dot(texture(detail_map,world_position.xz*0.5+world_position.y*0.11).rgb,vec3(0.2126,0.7152,0.0722));
		c *= mix(1.0,0.82+weathering*0.7,detail_strength);
	}
	ALBEDO = c;
	ROUGHNESS = mix(0.53+weathering*0.25,0.20,gem);
	METALLIC = clamp((c.r-c.b)*2.0,0.0,0.65);
	EMISSION = c*blue*(0.03+gem*0.22);
	if (has_normal) { NORMAL_MAP = texture(normal_map,UV).rgb; }
}
