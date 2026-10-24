shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D artwork : source_color, filter_linear_mipmap_anisotropic;
uniform float brightness = 1.0;

void fragment() {
	// Perspective-correct the common reference framing in the material, preserving originals.
	vec2 top = mix(vec2(0.182, 0.056), vec2(0.835, 0.105), UV.x);
	vec2 bottom = mix(vec2(0.182, 0.933), vec2(0.835, 0.898), UV.x);
	vec2 point = mix(top, bottom, UV.y);
	vec3 color = texture(artwork, point).rgb;
	ALBEDO = color * brightness;
}
