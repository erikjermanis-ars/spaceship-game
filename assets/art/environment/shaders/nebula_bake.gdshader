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
// Palette and structure are uniforms so each sky look bakes its own mood from
// the same field. The defaults are the Meridian haze (indigo/violet/teal/rose).
uniform vec3 col_deep = vec3(0.10, 0.10, 0.34);
uniform vec3 col_main = vec3(0.40, 0.14, 0.58);
uniform vec3 col_alt = vec3(0.04, 0.36, 0.44);
uniform vec3 col_accent = vec3(0.55, 0.20, 0.42);
uniform vec3 col_filament = vec3(0.30, 0.36, 0.55);
uniform vec2 seed_offset = vec2(0.0);     // shifts the noise field (stays tileable)
uniform vec2 band_dir = vec2(1.0, -1.0);  // integer components keep the band tileable
uniform float band_power = 2.2;           // lower = a wider galactic band
uniform float dust_floor = 0.25;          // dust density away from the band
uniform float dust_gain = 1.0;

void fragment() {
	vec2 uv = UV;
	vec2 per = vec2(base_cells);
	vec2 p = uv * base_cells + seed_offset;

	// Two-level domain warp (IQ style). All offsets are periodic in p.
	vec2 q = vec2(pfbm(p + vec2(0.0, 0.0), per, 5), pfbm(p + vec2(5.2, 1.3), per, 5));
	vec2 r = vec2(pfbm(p + 1.6 * q + vec2(1.7, 9.2), per, 4), pfbm(p + 1.6 * q + vec2(8.3, 2.8), per, 4));
	float f = pfbm(p + 1.5 * r, per, 6);

	// A diagonal "galactic band" (period 1 along u - v keeps it tileable),
	// wobbled by the warp so it does not read as a straight stripe.
	float band_coord = (uv.x * band_dir.x + uv.y * band_dir.y) + 0.18 * r.x + 0.08 * q.y;
	float band = pow(0.5 + 0.5 * cos(6.2831853 * band_coord), band_power);

	float dens = smoothstep(-0.25, 0.55, f + 0.25 * band);
	dens *= 0.35 + 0.85 * band;

	vec3 col = mix(col_deep, col_main, clamp(f * f * 5.0, 0.0, 1.0));
	col = mix(col, col_alt, clamp(length(q) * 1.4 - 0.15, 0.0, 1.0) * 0.85);
	col = mix(col, col_accent, clamp(r.y * 2.2 - 0.35, 0.0, 1.0) * 0.45);
	// Brighter, whiter filaments where the warped field folds.
	float fil = pow(clamp(1.0 - abs(f - 0.12) * 5.0, 0.0, 1.0), 4.0);
	col += col_filament * fil * band;

	vec3 emission = col * dens;

	// Dust lanes: higher frequency, concentrated along the band.
	float d = pfbm(p * 2.0 + 1.4 * r, per * 2.0, 5);
	float dust = smoothstep(0.02, 0.32, d) * (dust_floor + (1.0 - dust_floor) * band) * dust_gain;

	COLOR = vec4(clamp(emission, 0.0, 1.0), clamp(dust, 0.0, 1.0));
}
