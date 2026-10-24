shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;
uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;
uniform float cloud_time = 0.0;
uniform vec4 cloud_tint : source_color = vec4(0.75,0.81,0.88,1.0);
varying vec3 world_position;
void vertex() { world_position = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
	vec2 p = world_position.xz*0.004+vec2(cloud_time*0.0003,cloud_time*0.00012);
	float broad = texture(cloud_noise,p).r;
	float detail = texture(cloud_noise,p*3.1+vec2(0.31,0.16)).r;
	float density = broad*0.75+detail*0.25;
	float shade = clamp(0.68+(broad-texture(cloud_noise,p+vec2(0.008,0.005)).r)*4.0,0.35,1.0);
	ALBEDO = cloud_tint.rgb*shade;
	ALPHA = smoothstep(0.29,0.61,density)*0.91*(1.0-smoothstep(170.0,240.0,length(world_position.xz)));
}
