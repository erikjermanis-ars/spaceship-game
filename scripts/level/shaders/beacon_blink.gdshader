// Blinking navigation lights for the station kit.
// Every beacon is just a glow quad inside a cached draw list; this shader
// animates all of them at once, so hundreds of beacons cost zero script time.
//
// Per-beacon data is packed into the vertex colour ALPHA (rgb = light colour):
//   a <  0.5 : slow "beacon" pulse,      phase = a * 2
//   a >= 0.5 : double-flash white strobe, phase = (a - 0.5) * 2
// `t` is driven by the Level root (one uniform write per frame) so that audio
// pings can be synchronised with the flashes.
shader_type canvas_item;
render_mode blend_add;

uniform float t = 0.0;
uniform float beacon_period = 1.8;
uniform float strobe_period = 1.35;

varying vec3 v_rgb;
varying float v_int;

void vertex() {
	float a = COLOR.a;
	float is_strobe = step(0.5, a);
	float phase = fract(a * 2.0);
	// Slow beacon: sharp attack, exponential decay, never fully dark.
	float x1 = fract(t / beacon_period - phase);
	float beacon = 0.06 + 0.94 * exp(-x1 * 6.0) * smoothstep(0.0, 0.02, x1);
	// Strobe: two short flashes per period.
	float x2 = fract(t / strobe_period - phase);
	float strobe = step(x2, 0.035) + step(0.10, x2) * step(x2, 0.135);
	v_int = mix(beacon, strobe, is_strobe);
	v_rgb = COLOR.rgb;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	COLOR = vec4(v_rgb, tex.a * v_int);
}
