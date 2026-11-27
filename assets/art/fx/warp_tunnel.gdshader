// The light-speed tunnel: opaque where `tunnel` has reached, so it replaces
// the world for the length of the jump. Log-polar coordinates around the
// vanishing point (u = angle, v = -log r): scrolling v makes every feature
// rush outwards and stretch exactly as perspective would, and a tileable
// noise texture wraps around the angle without a seam.
//
// Depth is built from layers that move at different speeds:
//   walls      slow, soft clouds of the journey colour, twisting
//   filaments  thin bright threads (ridged noise) that wind slowly
//   streaks    four rings of crisp streaks, far = dense/thin/slow,
//              near = sparse/thick/fast, with faint colour fringes at the heads
//   pulse      a soft wave of light that runs out from the core now and then
//   ribs       faint rings passing by, the tunnel's "segments"
//   core       a breathing white-hot vanishing point with shimmering rays
// `mix_m` drifts the palette along the journey; `progress` makes the core
// surge at both ends, where the flashes are.
shader_type canvas_item;
render_mode unshaded;

#include "res://assets/art/fx/warp_palette.gdshaderinc"

uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform vec2 view_size = vec2(1920.0, 1080.0);
uniform vec2 focus = vec2(960.0, 540.0);    // vanishing point, canvas units
uniform float r_max = 1.2;                  // focus -> farthest corner, screen heights
uniform float time = 0.0;
uniform float tunnel = 1.0;
uniform float mix_m = 0.0;
uniform float progress = 0.0;

// One ring of `n` streak cells. `w` is the scrolled depth coordinate, `freq`
// streaks per unit depth, `ca` the chromatic split of the heads.
vec3 streak_layer(float u, float w, float n, float freq, float density, float width, float seed, float ca) {
	float ang = u * n;
	float cell = mod(floor(ang), n);
	float f = fract(ang) - 0.5;
	float h = whash(cell + seed);
	float h2 = whash(cell * 1.31 + seed + 5.0);
	if (h2 > density) {
		return vec3(0.0);
	}
	float sv = w * freq * (0.6 + 0.8 * h) + h * 13.0;
	vec3 s = fract(vec3(sv + ca, sv, sv - ca));
	// Sharp head on the outer end, long tail back towards the vanishing point.
	vec3 body = smoothstep(vec3(0.0), vec3(0.02), s) * pow(1.0 - s, vec3(3.5));
	float lat = (f - (whash(cell * 2.3 + seed) - 0.5) * 0.5) / width;
	return body * exp(-lat * lat) * (0.4 + 0.6 * h2 / density);
}

void fragment() {
	float H = view_size.y;
	// The vanishing point never sits quite still.
	vec2 wob = vec2(sin(time * 0.83), cos(time * 0.61)) * 0.007;
	vec2 p = (UV * view_size - focus) / H - wob;
	float r = max(length(p), 1e-4);
	float u = atan(p.y, p.x) / TAU + time * 0.011 + 0.03 * sin(time * 0.23);   // slow roll
	float v = -log(r);
	// The palette swirls a little around the angle so it is never one flat hue.
	float ml = clamp(mix_m + 0.20 * sin(TAU * 2.0 * u + v * 0.9 - time * 0.45), 0.0, 1.0);
	vec3 deep = warp_deep(ml);
	vec3 mid = warp_mid(ml);
	vec3 hot = warp_hot(mix_m);
	float twist = 0.12 + 0.26 * sin(time * 0.17);

	// ---- walls ----
	float n1 = texture(noise_tex, vec2(u * 2.0 + twist * v, (v + time * 0.55) * 0.21)).r;
	float n2 = texture(noise_tex, vec2(u * 3.0 - 1.6 * twist * v + 0.31, (v + time * 0.95) * 0.33)).g;
	float walls = smoothstep(0.42, 0.72, n1 * 0.55 + n2 * 0.55);
	vec3 col = deep * (0.5 + 1.1 * n1) + mid * walls * 0.20;

	// ---- filaments ----
	float fa = texture(noise_tex, vec2(u * 2.0 + 0.5 * twist * v + time * 0.010, (v + time * 1.30) * 0.11)).b;
	float fb = texture(noise_tex, vec2(u * 3.0 - 0.8 * twist * v - time * 0.013, (v + time * 0.80) * 0.17 + 0.5)).a;
	float fil = pow(1.0 - abs(2.0 * fa - 1.0), 12.0) + 0.7 * pow(1.0 - abs(2.0 * fb - 1.0), 16.0);
	col += mix(mid, hot, 0.35) * fil * 0.40 * (0.4 + 1.2 * n2);

	// ---- streaks: far -> near ----
	vec3 st = streak_layer(u, v + time * 0.80, 150.0, 0.70, 0.60, 0.14, 1.0, 0.004) * 0.55;
	st += streak_layer(u + 0.37, v + time * 1.45, 68.0, 0.52, 0.55, 0.11, 7.0, 0.006) * 0.85;
	st += streak_layer(u + 0.11, v + time * 2.40, 29.0, 0.40, 0.50, 0.075, 19.0, 0.008) * 1.20;
	st += streak_layer(u + 0.63, v + time * 3.80, 11.0, 0.30, 0.55, 0.040, 43.0, 0.010) * 1.00;
	col += st * mix(mid, hot, 0.8);

	// ---- ribs ----
	float ribs = pow(0.5 + 0.5 * sin((v + time * 1.9) * 5.0 + n1 * 5.0), 28.0);
	col += mid * ribs * 0.09;

	// ---- pulse: the tunnel's heartbeat ----
	float pw = fract(time * 0.42);
	float pr = pw * pw * 1.8;
	col += mid * exp(-pow((r - pr) / (0.03 + 0.25 * pw), 2.0)) * (1.0 - pw) * 0.22;

	// Detail dissolves into the glow near the vanishing point (it would only
	// alias there), and the frame edge falls off a little.
	col *= smoothstep(0.012, 0.11, r);
	col *= 1.0 - 0.30 * smoothstep(0.55, 1.25, r);

	// ---- core ----
	float breath = 1.0 + 0.18 * sin(time * 1.7) + 0.07 * sin(time * 4.3 + 1.0);
	float surge = 1.0 + 2.6 * smoothstep(0.80, 1.0, progress) + 1.6 * (1.0 - smoothstep(0.0, 0.10, progress));
	float size = breath * surge;
	float rays = pow(texture(noise_tex, vec2(u * 5.0, time * 0.06)).r, 3.0) * 4.0;
	col += hot * (exp(-r / (0.016 * size)) * 1.7 + exp(-r / (0.065 * size)) * 0.65);
	col += mix(mid, hot, 0.4) * exp(-r / 0.26) * (0.22 + 0.5 * rays);

	col += (whash2(FRAGCOORD.xy) - 0.5) / 255.0;
	// The tunnel opens outwards from the vanishing point as `tunnel` rises;
	// at 1 it covers everything.
	float cover = smoothstep(0.0, 1.0, tunnel * 2.2 - (r / r_max) * 1.2);
	COLOR = vec4(col, cover);
}
