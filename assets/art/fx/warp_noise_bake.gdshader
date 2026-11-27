// Bakes one small tileable noise texture for the light-speed tunnel, once,
// when WarpFX is created. Four unrelated fbm fields in RGBA (0.5 = mean), so
// the tunnel's walls, filaments and rays are a handful of texture fetches per
// pixel instead of per-pixel fbm for the whole journey.
shader_type canvas_item;
render_mode blend_disabled, unshaded;

#include "res://assets/art/environment/shaders/noise.gdshaderinc"

uniform float cells = 6.0;

void fragment() {
	vec2 per = vec2(cells);
	vec2 p = UV * cells;
	// A light domain warp folds the fields into wisps rather than blobs.
	vec2 w = vec2(pfbm(p + vec2(3.1, 7.7), per, 3), pfbm(p + vec2(9.4, 1.2), per, 3));
	float a = pfbm(p + 1.3 * w, per, 5);
	float b = pfbm(p + vec2(21.0, 4.0) - 1.1 * w, per, 5);
	float c = pfbm(p + vec2(5.0, 33.0) + 0.9 * w.yx, per, 5);
	float d = pfbm(p + vec2(47.0, 19.0), per, 4);
	COLOR = clamp(vec4(a, b, c, d) * 1.25 + 0.5, 0.0, 1.0);
}
