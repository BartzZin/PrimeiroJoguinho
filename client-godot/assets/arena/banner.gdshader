shader_type spatial;
render_mode cull_disabled;
uniform float wind_time = 0.0;
uniform vec4 cloth_color : source_color = vec4(0.02,0.12,0.42,1.0);
void vertex() {
	VERTEX.z += (sin(wind_time*1.2+UV.y*6.0)+sin(wind_time*1.9+UV.x*5.0)*0.35)*0.08*UV.y;
}
void fragment() {
	float trim = step(UV.x,0.045)+step(0.955,UV.x)+step(0.965,UV.y);
	vec2 p = (UV-vec2(0.5,0.40))*vec2(1.0,1.7);
	float angle = atan(p.y,p.x);
	float radius = length(p);
	float emblem = (1.0-smoothstep(0.015,0.025,abs(radius-0.15))) + (1.0-step(0.012,abs(sin(angle*6.0))*radius))*step(radius,0.23)*step(0.09,radius);
	ALBEDO = mix(cloth_color.rgb,vec3(0.78,0.51,0.16),clamp(trim+emblem,0.0,1.0));
	ROUGHNESS = 0.86;
}
