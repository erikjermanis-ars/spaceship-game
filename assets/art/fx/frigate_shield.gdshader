// The KESTREL's deflector shield: an elliptical bubble around the hull,
// invisible until something hits it. Each hit (up to 6 at once) flashes a
// hot spot where it landed and sends a ripple across a hex lattice; the rim
// glows like the edge of a soap bubble. Additive, so it only ever adds light.
// Hit positions are in the ship's local pixels (the bubble rotates with it).
shader_type canvas_item;
render_mode blend_add, unshaded;

uniform float strength = 1.0;        // shield charge 0..1
uniform float glow = 0.0;            // overall visibility (after hits) 0..1
uniform float flicker = 0.0;         // instability: collapsing / recharging
uniform vec4 tint : source_color = vec4(0.45, 0.8, 1.0, 1.0);
uniform vec2 half_size = vec2(920.0, 460.0);
uniform vec4 hits[6];                // xy = local px on the bubble, z = age (s), w = power
uniform int hit_count = 0;
uniform float time_s = 0.0;

float hex_dist(vec2 p) {
	p = abs(p);
	return max(dot(p, normalize(vec2(1.0, 1.7320508))), p.x);
}

vec2 hex_local(vec2 uv) {
	vec2 r = vec2(1.0, 1.7320508);
	vec2 h = r * 0.5;
	vec2 a = mod(uv, r) - h;
	vec2 b = mod(uv - h, r) - h;
	return dot(a, a) < dot(b, b) ? a : b;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	vec2 px = p * half_size;
	float inside = 1.0 - smoothstep(0.985, 1.0, d);
	float rim = smoothstep(0.72, 1.0, d) * inside;
	float cell = smoothstep(0.40, 0.49, hex_dist(hex_local(px / 30.0)));
	float a = glow * (0.32 * rim + 0.14 * cell * rim);
	for (int i = 0; i < 6; i++) {
		if (i >= hit_count) {
			break;
		}
		vec4 h = hits[i];
		float dist = length(px - h.xy);
		float rad = h.z * 620.0;
		float width = 50.0 + h.z * 90.0;
		float ring = exp(-pow((dist - rad) / width, 2.0)) * exp(-h.z * 2.0);
		float spot = exp(-dist / 140.0) * exp(-h.z * 5.0);
		a += h.w * (ring * (0.35 + 0.9 * cell) + spot * 1.4) * inside * smoothstep(0.2, 0.8, d);
	}
	a += flicker * rim * (0.45 + 0.55 * sin(time_s * 37.0 + px.x * 0.013 + px.y * 0.021));
	a *= mix(0.3, 1.0, strength) * inside;
	COLOR = vec4(tint.rgb, clamp(a, 0.0, 1.0));
}
