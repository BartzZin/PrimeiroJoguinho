shader_type spatial;
uniform vec4 stone_tint : source_color = vec4(0.48,0.51,0.54,1.0);
uniform sampler2D stone_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float detail_strength = 0.4;
varying vec3 world_position;
float hash(vec3 p) { return fract(sin(dot(p,vec3(127.1,311.7,74.7)))*43758.5453); }
float noise(vec3 p) {
	vec3 i=floor(p),f=fract(p); f=f*f*(3.0-2.0*f);
	return mix(mix(mix(hash(i),hash(i+vec3(1,0,0)),f.x),mix(hash(i+vec3(0,1,0)),hash(i+vec3(1,1,0)),f.x),f.y),mix(mix(hash(i+vec3(0,0,1)),hash(i+vec3(1,0,1)),f.x),mix(hash(i+vec3(0,1,1)),hash(i+vec3(1,1,1)),f.x),f.y),f.z);
}
void vertex() { world_position = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
	vec3 world_n = normalize(mat3(INV_VIEW_MATRIX)*NORMAL);
	vec3 weights = abs(world_n);
	vec2 uv = weights.y > max(weights.x,weights.z) ? world_position.xz : (weights.x > weights.z ? world_position.zy : world_position.xy);
	vec3 surface = texture(stone_map,uv*0.4).rgb;
	float relief = dot(surface,vec3(0.2126,0.7152,0.0722));
	ALBEDO = surface*stone_tint.rgb*1.2;
	ROUGHNESS = clamp(0.48+relief*0.35,0.4,0.85);
	METALLIC = 0.0;
	if (detail_strength > 0.0) {
		vec3 dx = dFdx(VERTEX), dy = dFdy(VERTEX);
		vec3 r1 = cross(dy,NORMAL), r2 = cross(NORMAL,dx);
		float determinant = dot(dx,r1);
		vec3 gradient = sign(determinant)*(dFdx(relief)*r1+dFdy(relief)*r2);
		if (abs(determinant) > 0.00000001) { NORMAL = normalize(abs(determinant)*NORMAL-gradient*detail_strength*0.08); }
	}
}
