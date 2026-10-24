shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D artwork : source_color, filter_linear_mipmap_anisotropic;
uniform float brightness = 1.0;

void fragment() {
	// Perspective-correct the common reference framing in the material, preserving originals.
	vec2 face_uv = UV;
	bool interior = UV.x > 0.09 && UV.x < 0.91 && UV.y > 0.08 && UV.y < 0.94;
	if (interior && UV.y < 0.66) {
		vec2 art_uv = clamp((UV - vec2(0.09, 0.08)) / vec2(0.82, 0.58), vec2(0.0), vec2(1.0));
		face_uv = mix(vec2(0.12, 0.14), vec2(0.89, 0.86), art_uv);
	}
	vec2 top = mix(vec2(0.182, 0.056), vec2(0.835, 0.105), face_uv.x);
	vec2 bottom = mix(vec2(0.182, 0.933), vec2(0.835, 0.898), face_uv.x);
	vec2 point = mix(top, bottom, face_uv.y);
	vec3 color = texture(artwork, point).rgb;
	// A writing area belongs to the card face; the game behind the hand stays visible.
	if (interior && UV.y >= 0.66) {
		color = mix(vec3(0.065, 0.022, 0.12), vec3(0.035, 0.012, 0.065), (UV.y - 0.66) / 0.28);
		if (UV.y < 0.669) { color = vec3(0.63, 0.39, 0.13); }
	}
	if (length((UV - vec2(0.18, 0.11)) * vec2(1.0, 1.55)) < 0.087) {
		color = vec3(0.065, 0.022, 0.12);
	}
	ALBEDO = color * brightness;
}
