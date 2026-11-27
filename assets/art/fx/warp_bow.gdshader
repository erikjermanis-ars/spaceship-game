// Warp bubble and bow shock around the ship snapshot inside the tunnel, drawn
// under the snapshot. The quad is centred on the ship and turned to its
// heading: +x is ahead. Coordinates are in ship lengths (the snapshot texture's
// width as drawn), so it fits any ship.
//   bubble  a pocket of calm: the tunnel is dimmed around the hull (alpha), so
//           the ship stays readable against it, with a thin rippling rim that
//           is brightest at the bow
//   front   a thin parabola standing off the bow, flickering
//   sheath  glowing flow streaming back along both sides
//   wake    a tapering trail behind the engines
// Premultiplied output: rgb adds light, alpha only darkens what is behind.
shader_type canvas_item;
render_mode blend_premul_alpha, unshaded;

#include "res://assets/art/fx/warp_palette.gdshaderinc"

uniform float extent = 5.0;       // quad size in ship lengths
uniform float time = 0.0;
uniform float intensity = 1.0;
uniform float mix_m = 0.0;

void fragment() {
	vec2 q = (UV - 0.5) * extent;
	vec3 mid = warp_mid(mix_m);
	vec3 hot = warp_hot(mix_m);
	float flick = 0.85 + 0.15 * sin(time * 37.0) * sin(time * 23.0 + 1.3);

	// ---- bubble: an egg a little longer than the ship ----
	vec2 bq = (q + vec2(0.04, 0.0)) / vec2(0.74, 0.50);
	float e = length(bq);
	float ang = atan(bq.y, bq.x);
	float dark = 0.62 * (1.0 - smoothstep(0.45, 1.05, e));
	float ripple = 0.75 + 0.25 * sin(ang * 9.0 - time * 17.0) * sin(ang * 4.0 + time * 6.0);
	float rim = exp(-pow((e - 1.0) / 0.045, 2.0)) * ripple;
	float ahead = 0.18 + 0.82 * smoothstep(-0.6, 0.9, cos(ang));
	vec3 col = mix(mid, hot, 0.6) * rim * ahead * 0.75;
	col += mid * exp(-pow((e - 0.95) / 0.22, 2.0)) * 0.12;

	// ---- shock front: 0 on the front, > 0 behind it (inside the sheath) ----
	float stand_off = 0.84 + 0.02 * sin(time * 19.0);
	float front = stand_off - 0.62 * q.y * q.y - q.x;
	float edge = exp(-abs(front) / 0.026);
	float sheath = smoothstep(0.0, 0.06, front) * exp(-front * 2.2) * smoothstep(0.9, 1.1, e);
	// Streamlines sliding backwards through the sheath.
	float flow = 0.55 + 0.45 * sin(q.y * 34.0 + 1.6 * sin(q.x * 6.0 + time * 26.0));
	float reach = exp(-dot(q, q) * 0.40);
	col += hot * edge * reach * flick;
	col += mid * sheath * flow * reach * 0.55;

	// ---- wake ----
	float behind = max(-q.x - 0.62, 0.0);
	float wake = exp(-abs(q.y) / (0.03 + 0.07 * behind)) * smoothstep(0.0, 0.15, behind) * exp(-behind * 1.5);
	col += mid * wake * 0.55 * flick;

	// Never show the quad's border.
	vec2 b = abs(UV * 2.0 - 1.0);
	float inside = 1.0 - smoothstep(0.75, 1.0, max(b.x, b.y));
	COLOR = vec4(col * intensity * inside, dark * intensity);
}
