shader_type sky;
uniform sampler2D panorama : source_color, filter_linear_mipmap, repeat_enable;
void sky() {
	vec3 original = texture(panorama,SKY_COORDS).rgb;
	if (AT_CUBEMAP_PASS) {
		// The photographic light field stays static and is filtered only once.
		COLOR = original;
	} else {
		float y = normalize(EYEDIR).y;
		float lower = 1.0-smoothstep(-0.05,0.18,y);
		float down = clamp(-y,0.0,1.0);
		// A floating world has a cloud sea below the horizon, not the neutral
		// ground patch of a terrestrial panorama. Never duplicate the sun below.
		vec2 cloud_uv = vec2(SKY_COORDS.x,0.25+0.18*(1.0-pow(down,0.6)));
		vec3 clouds = min(texture(panorama,cloud_uv).rgb,vec3(5.0));
		clouds = mix(clouds,vec3(0.65,0.72,0.82),smoothstep(0.85,1.0,down));
		COLOR = mix(original,clouds,lower);
	}
}
