shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// The deck top and bottom share a single mesh surface in skateboard.blend, so the
// two-tone split has to happen per-fragment off the facing direction instead of
// per-surface. Mesh-local +Y is up (board_high carries a 180 deg Y node rotation,
// which leaves the up axis untouched), and the normal is read in model space so the
// split rides along with every flip, shuv and manual.

uniform vec4 grip_color : source_color = vec4(0.12, 0.12, 0.14, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.95, 0.30, 0.02, 1.0);
uniform float grip_roughness : hint_range(0.0, 1.0) = 0.95;
uniform float bottom_roughness : hint_range(0.0, 1.0) = 0.70;
// Airborne, the underside faces away from the sun and falls to ambient alone, which
// drags the orange down to muddy brick right when the spin most needs reading. A small
// emission floor holds the hue without making the deck look lit from within.
uniform float bottom_emission : hint_range(0.0, 1.0) = 0.30;
// Width of the top/bottom crossover band around the rails. Higher is crisper.
uniform float facing_sharpness : hint_range(1.0, 64.0) = 14.0;
uniform float grain_scale : hint_range(1.0, 4096.0) = 720.0;
uniform float grain_strength : hint_range(0.0, 1.0) = 0.55;
uniform float grain_bump : hint_range(0.0, 1.0) = 0.45;

// Model-space normal, captured before the rasterizer flips it for back faces
// (this material renders cull_disabled).
varying vec3 deck_normal;

void vertex() {
	deck_normal = NORMAL;
}

float hash21(vec2 p) {
	p = fract(p * vec2(233.34, 851.73));
	p += dot(p, p + 23.45);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	float facing = normalize(deck_normal).y;
	float top = clamp(facing * facing_sharpness * 0.5 + 0.5, 0.0, 1.0);

	// Two octaves of grit. Fades out once a noise cell drops below a pixel so the deck
	// stops shimmering at chase-camera distance instead of aliasing into fizz.
	vec2 grit_uv = UV * grain_scale;
	float cell_density = length(fwidth(grit_uv));
	float grit_fade = 1.0 - smoothstep(0.5, 1.5, cell_density);
	float base = value_noise(grit_uv);
	float grit = mix(0.5, base * 0.65 + value_noise(grit_uv * 2.17) * 0.35, grit_fade);

	// Grip is nearly black, so the speckle needs a wide *relative* albedo swing to
	// amount to any absolute one at all.
	vec3 grip_albedo = grip_color.rgb * mix(1.0 - grain_strength * 0.85, 1.0 + grain_strength * 0.85, grit);
	float grip_rough = clamp(grip_roughness - grain_strength * 0.25 * (1.0 - grit), 0.0, 1.0);

	ALBEDO = mix(bottom_color.rgb, grip_albedo, top);
	ROUGHNESS = mix(bottom_roughness, grip_rough, top);
	EMISSION = bottom_color.rgb * bottom_emission * (1.0 - top);
	METALLIC = 0.0;

	// The grain that actually sells griptape is micro-shadowing, not color. Perturb the
	// normal along the noise gradient so the grit lights up as the board rotates; the
	// mesh ships TANGENT, so tangent space is available without a normal map.
	float eps = 0.35;
	vec2 grad = vec2(value_noise(grit_uv + vec2(eps, 0.0)) - base,
					 value_noise(grit_uv + vec2(0.0, eps)) - base) / eps;
	NORMAL = normalize(NORMAL - (TANGENT * grad.x + BINORMAL * grad.y) * grain_bump * grit_fade * top);
}
