// Bakes ONE tileable nebula texture at startup (SubViewport, UPDATE_ONCE).
// Doing the expensive domain-warped fbm once instead of per frame keeps the
// live sky pass down to a single texture fetch.
//   RGB = nebula emission colour, stored x4 (decoded in sky.gdshader) so the
//         very dark values keep precision in an 8-bit target.
//   A   = dust density (dark lanes that also swallow stars).
shader_type canvas_item;
render_mode blend_disabled, unshaded;

#include "res://assets/art/environment/shaders/noise.gdshaderinc"

uniform float base_cells = 4.0;

void fragment() {
	vec2 uv = UV;
	vec2 per = vec2(base_cells);
	vec2 p = uv * base_cells;

	// Two-level domain warp (IQ style). All offsets are periodic in p.
	vec2 q = vec2(pfbm(p + vec2(0.0, 0.0), per, 5), pfbm(p + vec2(5.2, 1.3), per, 5));
	vec2 r = vec2(pfbm(p + 1.6 * q + vec2(1.7, 9.2), per, 4), pfbm(p + 1.6 * q + vec2(8.3, 2.8), per, 4));
	float f = pfbm(p + 1.5 * r, per, 6);

	// A diagonal "galactic band" (period 1 along u - v keeps it tileable),
	// wobbled by the warp so it does not read as a straight stripe.
	float band_coord = (uv.x - uv.y) + 0.18 * r.x + 0.08 * q.y;
	float band = pow(0.5 + 0.5 * cos(6.2831853 * band_coord), 2.2);

	float dens = smoothstep(-0.25, 0.55, f + 0.25 * band);
	dens *= 0.35 + 0.85 * band;

	vec3 indigo = vec3(0.10, 0.10, 0.34);
	vec3 violet = vec3(0.40, 0.14, 0.58);
	vec3 teal = vec3(0.04, 0.36, 0.44);
	vec3 rose = vec3(0.55, 0.20, 0.42);
	vec3 col = mix(indigo, violet, clamp(f * f * 5.0, 0.0, 1.0));
	col = mix(col, teal, clamp(length(q) * 1.4 - 0.15, 0.0, 1.0) * 0.85);
	col = mix(col, rose, clamp(r.y * 2.2 - 0.35, 0.0, 1.0) * 0.45);
	// Brighter, whiter filaments where the warped field folds.
	float fil = pow(clamp(1.0 - abs(f - 0.12) * 5.0, 0.0, 1.0), 4.0);
	col += vec3(0.30, 0.36, 0.55) * fil * band;

	vec3 emission = col * dens;

	// Dust lanes: higher frequency, concentrated along the band.
	float d = pfbm(p * 2.0 + 1.4 * r, per * 2.0, 5);
	float dust = smoothstep(0.02, 0.32, d) * (0.25 + 0.75 * band);

	COLOR = vec4(clamp(emission, 0.0, 1.0), clamp(dust, 0.0, 1.0));
}
