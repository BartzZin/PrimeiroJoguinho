shader_type spatial;

uniform vec4 stone_color : source_color = vec4(0.66, 0.71, 0.73, 1.0);
uniform float highlight = 0.0;
uniform sampler2D stone_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float veins = sin(world_position.x * 8.0 + world_position.z * 5.0
		+ 1.5 * sin(world_position.z * 9.0 - world_position.x * 3.0));
	vec3 stone = texture(stone_map, world_position.xz * 0.75).rgb;
	float grain = dot(stone,vec3(0.2126,0.7152,0.0722));
	ALBEDO = stone_color.rgb * (0.82 + grain*0.65) * (0.97 + 0.03 * smoothstep(0.35, 0.9, veins));
	METALLIC = 0.04;
	ROUGHNESS = 0.38+grain*0.4;
	SPECULAR = 0.3;
	EMISSION = stone_color.rgb * highlight * 0.12;
}
