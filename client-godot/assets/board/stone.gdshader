shader_type spatial;

uniform vec4 stone_color : source_color = vec4(0.66, 0.71, 0.73, 1.0);
uniform float highlight = 0.0;
varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float veins = sin(world_position.x * 8.0 + world_position.z * 5.0
		+ 1.5 * sin(world_position.z * 9.0 - world_position.x * 3.0));
	ALBEDO = stone_color.rgb * (0.95 + 0.05 * smoothstep(0.35, 0.9, veins));
	METALLIC = 0.04;
	ROUGHNESS = 0.6;
	SPECULAR = 0.3;
	EMISSION = stone_color.rgb * highlight * 0.12;
}
