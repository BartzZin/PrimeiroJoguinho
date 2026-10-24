shader_type spatial;
render_mode cull_disabled, blend_mix, depth_draw_opaque;
uniform float flow_time = 0.0;
uniform vec3 water_color : source_color = vec3(0.18,0.65,0.95);

void vertex() {
	VERTEX.z += sin(UV.y*18.0+UV.x*7.0+flow_time*1.5)*0.035*UV.y;
}
void fragment() {
	float streak = sin(UV.x*91.0+sin(UV.x*27.0)*3.0+flow_time*0.8)*0.5+0.5;
	float foam = pow(sin(UV.y*60.0+flow_time*5.0+UV.x*7.0)*0.5+0.5,6.0);
	float edge = smoothstep(0.0,0.1,UV.x)*(1.0-smoothstep(0.9,1.0,UV.x));
	ALBEDO = mix(water_color,vec3(0.92,0.97,1.0),streak*0.45+foam*0.3);
	ROUGHNESS = 0.34;
	EMISSION = water_color*0.08;
	ALPHA = edge*mix(0.66,0.92,streak)*(1.0-smoothstep(0.80,1.0,UV.y));
}
