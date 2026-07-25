shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 color1 : source_color = vec4(0.18, 0.2, 0.24, 1.0);
uniform vec4 color2 : source_color = vec4(0.75, 0.78, 0.82, 1.0);
uniform float grid_size : hint_range(0.1, 20.0) = 2.0;

void fragment() {
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 cell = floor(world_pos.xz / grid_size);
	float checker = mod(cell.x + cell.y, 2.0);
	ALBEDO = mix(color1.rgb, color2.rgb, checker);
	ROUGHNESS = 0.85;
	METALLIC = 0.0;
}
