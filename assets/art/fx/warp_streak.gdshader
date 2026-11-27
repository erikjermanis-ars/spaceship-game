// Jump spool-up and leap, pass 2: additive light over the (still visible)
// world. Everything is analytic in polar coordinates around the focus; r is
// measured in screen heights so the look is the same at any window size.
//   charge: motes of light spiral in towards the ship and speed up, rings
//           collapse onto it, and a pulsing core with slow rays builds.
//   streak: extra star streaks shoot outwards (red/blue tips), the core
//           swells towards the flash.
//   shock:  one hard chromatic ring bursts outwards when the ship leaps.
shader_type canvas_item;
render_mode blend_add, unshaded;

#include "res://assets/art/fx/warp_palette.gdshaderinc"

uniform vec2 view_size = vec2(1920.0, 1080.0);
uniform vec2 focus = vec2(960.0, 540.0);
uniform float time = 0.0;
uniform float charge = 0.0;
uniform float streak = 0.0;
uniform float shock = 1.0;      // 0..1 ring progress, >= 1 = none
uniform float mix_m = 0.0;      // palette position (see warp_palette)

// Motes falling in along one ring of `n` angular cells.
float motes(float a, float r, float n, float seed) {
	float ang = a / TAU * n;
	float cell = mod(floor(ang), n);
	float f = fract(ang) - 0.5;
	float h = whash(cell + seed);
	float h2 = whash(cell * 1.7 + seed + 3.0);
	float h3 = whash(cell * 2.9 + seed + 11.0);
	// More cells wake up as the charge builds.
	float awake = smoothstep(h3 * 0.8, h3 * 0.8 + 0.2, charge);
	float speed = (0.22 + 0.45 * h) * (0.5 + 1.7 * charge);
	float ph = fract(time * speed + h2 * 7.0);
	// Slow at the rim, fast into the core: reads as being pulled in.
	float rho = 1.2 * (1.0 - ph * ph);
	float dr = r - rho;
	float tail = 0.012 + 0.075 * speed * ph;
	float along = dr < 0.0 ? exp(-dr * dr / 0.00002) : exp(-dr / tail);
	float lat = (f - (h2 - 0.5) * 0.5) / n * TAU * r;
	float w = 0.0014 + 0.0030 * rho;
	float env = smoothstep(0.0, 0.12, ph) * smoothstep(0.02, 0.12, rho);
	return exp(-lat * lat / (w * w)) * along * env * awake * (0.35 + 0.65 * h);
}

// Star streaks growing outwards from random radii; rgb lengths differ a
// little, which leaves coloured tips.
vec3 star_streaks(float a, float r, float n, float seed) {
	float ang = a / TAU * n;
	float cell = mod(floor(ang), n);
	float f = fract(ang) - 0.5;
	float h = whash(cell + seed);
	float h2 = whash(cell * 1.3 + seed + 5.0);
	float h3 = whash(cell * 2.1 + seed + 9.0);
	float r0 = 0.05 + 1.15 * sqrt(h);
	float grow = streak * streak * (1.2 + 3.2 * h2);
	vec3 r1 = r0 * (1.0 + grow * vec3(1.05, 1.0, 0.95));
	vec3 seg = smoothstep(r0 * 0.985, r0, r) * (1.0 - smoothstep(r1 * 0.96, r1, vec3(r)));
	float head = mix(0.3, 1.0, clamp((r - r0) / max(r1.g - r0, 1e-4), 0.0, 1.0));
	float lat = (f - (h3 - 0.5) * 0.6) / n * TAU * r;
	float w = 0.0011 + 0.0022 * r;
	return seg * head * exp(-lat * lat / (w * w)) * (0.25 + 0.75 * h3);
}

void fragment() {
	vec2 p = (UV * view_size - focus) / view_size.y;
	float r = max(length(p), 1e-4);
	float a = atan(p.y, p.x);
	vec3 mid = warp_mid(mix_m);
	vec3 hot = warp_hot(mix_m);
	vec3 col = vec3(0.0);

	if (charge > 0.001) {
		// The inflow winds up into a spiral as the charge grows, and gives
		// way to the outward streaks once the ship leaps.
		float inflow = 1.0 - smoothstep(0.0, 0.5, streak);
		float as = a + (0.25 + 0.9 * charge) * inflow * log(r + 0.03);
		float m = motes(as, r, 46.0, 1.0) + 0.8 * motes(as + 1.3, r, 83.0, 31.0) + 0.6 * motes(as + 2.9, r, 131.0, 67.0);
		col += mix(mid, hot, 0.6) * m * (0.5 + 0.9 * charge) * inflow;
		// Rings collapsing onto the ship, faster and brighter with charge.
		float rate = 0.30 + 0.95 * charge;
		for (int i = 0; i < 2; i++) {
			float ph = fract(time * rate + float(i) * 0.5);
			float rr = 0.8 * pow(1.0 - ph, 1.6);
			float ring = exp(-pow((r - rr) / (0.003 + 0.022 * rr), 2.0));
			col += mid * ring * ph * charge * charge * 0.55 * inflow;
		}
		// Core: a tight pulsing heart, a soft bloom and six slow rays.
		float pulse = 0.82 + 0.18 * sin(time * (5.0 + 13.0 * charge));
		float c2 = charge * charge;
		col += hot * exp(-r / 0.035) * c2 * pulse * 1.1;
		col += mid * exp(-r / 0.16) * c2 * 0.45;
		float rays = pow(abs(cos(a * 3.0 + time * 0.35)), 48.0) + 0.5 * pow(abs(cos(a * 5.0 - time * 0.22 + 1.0)), 90.0);
		col += hot * rays * exp(-r / 0.22) * c2 * 0.35;
	}

	if (streak > 0.001) {
		float fade = smoothstep(0.0, 0.2, streak) * smoothstep(0.03, 0.16, r);
		vec3 st = star_streaks(a, r, 150.0, 5.0) + star_streaks(a + 0.7, r, 233.0, 41.0) * 0.8;
		col += st * hot * fade * 1.25;
		// The core swells into the flash.
		float s3 = streak * streak * streak;
		col += hot * exp(-r / (0.05 + 0.30 * s3)) * s3 * 1.3;
	}

	if (shock < 1.0) {
		float k = (1.0 - shock) * (1.0 - shock);
		vec3 rs = shock * 1.5 * vec3(1.014, 1.0, 0.986);
		float wd = 0.010 + 0.045 * shock;
		vec3 ring = exp(-pow((vec3(r) - rs) / wd, vec3(2.0)));
		col += ring * hot * k * 1.7;
		// A fainter echo trailing the main ring.
		col += mid * exp(-pow((r - rs.g * 0.72) / (wd * 1.6), 2.0)) * k * 0.45;
	}

	COLOR = vec4(col, 1.0);
}
