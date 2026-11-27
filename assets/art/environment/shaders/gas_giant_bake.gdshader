// Bakes the ringed gas giant's cloud tops once into an equirectangular target
// (the Vesper sky look). RGB = albedo, A = cloud "height" (bright zones ride
// higher), which the live shader uses for a little relief at the terminator.
//
// Structure: a 1D band profile along latitude (cream zones, amber/rust belts),
// sheared by zonally stretched turbulence so band edges curl into festoons,
// plus a few oval storms that swirl the bands around them. Noise is sampled on
// the unit sphere, so the map is seamless in longitude and clean at the poles.
shader_type canvas_item;
render_mode blend_disabled, unshaded;

#include "res://assets/art/environment/shaders/noise.gdshaderinc"

uniform float seed = 11.0;

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

float vnoise1(float x) {
	float i = floor(x);
	float f = x - i;
	f = f * f * (3.0 - 2.0 * f);
	return mix(hash11(i), hash11(i + 1.0), f);
}

// 0 = dark belt, 1 = bright zone. Broad bands with finer stripes inside them.
float band_profile(float lat) {
	float s = lat * 5.2 + seed;
	float b = vnoise1(s) * 0.58 + vnoise1(s * 2.7 + 7.0) * 0.27 + vnoise1(s * 6.3 + 3.0) * 0.15;
	return smoothstep(0.22, 0.78, b);
}

vec3 band_color(float b, float lat, float streak) {
	vec3 dark = vec3(0.30, 0.15, 0.10);     // deep belt brown
	vec3 rust = vec3(0.58, 0.28, 0.14);
	vec3 amber = vec3(0.82, 0.56, 0.27);
	vec3 cream = vec3(0.93, 0.84, 0.66);
	vec3 c = mix(dark, rust, smoothstep(0.0, 0.3, b));
	c = mix(c, amber, smoothstep(0.25, 0.62, b));
	c = mix(c, cream, smoothstep(0.58, 0.95, b));
	// Fine streaks along the flow break up the flat band fills.
	c *= 0.88 + 0.24 * streak;
	// Teal polar haze: photochemical smog darkens and cools the caps.
	float polar = smoothstep(0.85, 1.32, abs(lat));
	c = mix(c, vec3(0.10, 0.25, 0.28), polar * 0.85);
	return c;
}

// Swirls `lat`/`lon` around an oval storm and returns its mask (0..1).
float storm(inout float lat, inout float lon, vec2 at, vec2 size, float twist) {
	float dx = (mod(lon - at.x + PI, TAU) - PI) * cos(at.y);
	float dy = lat - at.y;
	vec2 d = vec2(dx / size.x, dy / size.y);
	float e = length(d);
	float w = exp(-e * e * 1.4);
	vec2 sw = rot2(twist * w) * vec2(dx, dy);
	lat = at.y + mix(dy, sw.y, w);
	lon = at.x + mix(dx, sw.x, w) / cos(at.y);
	return smoothstep(1.15, 0.55, e);
}

void fragment() {
	float lon = (UV.x - 0.5) * TAU;
	float lat = (0.5 - UV.y) * PI;

	// ---- storms first: they bend the coordinates the bands are read at ----
	float m_spot = storm(lat, lon, vec2(0.9, -0.36), vec2(0.34, 0.13), 3.4);
	float m_oval = storm(lat, lon, vec2(-1.7, 0.50), vec2(0.13, 0.065), -2.8);
	float m_pearl = storm(lat, lon, vec2(2.6, 0.16), vec2(0.09, 0.05), 2.4);

	vec3 p = vec3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon));
	// Zonal turbulence: stretching the sample space along latitude makes the
	// features long in longitude, like jet streams.
	vec3 zp = vec3(p.x, p.y * 4.5, p.z) + seed;
	float w1 = fbm3(zp * 1.6, 5);
	float w2 = fbm3(zp * 5.0 + 2.5 * w1, 5);
	float w3 = fbm3(vec3(p.x, p.y * 2.5, p.z) * 19.0 + 4.0 * w2 + seed, 4);
	float lat_w = lat + 0.070 * w1 + 0.040 * w2 + 0.014 * w3;

	float b = band_profile(lat_w);
	float streak = fbm3(vec3(p.x, p.y * 14.0, p.z) * 9.0 + 3.0 * w2, 4) + 0.5;
	// Paler upwellings drawn out along the flow inside the darker belts.
	b = clamp(b + 0.16 * smoothstep(0.02, 0.30, w2) * (1.0 - b), 0.0, 1.0);
	vec3 col = band_color(b, lat_w, streak);

	// ---- storm colouring: a rust-red great spot with a pale collar, and two
	// white ovals. The spiral inside comes from the swirled band lookup.
	vec3 spot = mix(vec3(0.62, 0.22, 0.10), vec3(0.80, 0.42, 0.20), b);
	col = mix(col, spot, m_spot * 0.85);
	col = mix(col, vec3(0.95, 0.88, 0.74), (m_oval + m_pearl) * 0.7);

	float height = clamp(0.25 + 0.6 * b + 0.25 * max(m_spot, max(m_oval, m_pearl)), 0.0, 1.0);
	COLOR = vec4(clamp(col, 0.0, 1.0), height);
}
