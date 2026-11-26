// Holographic race-gate curtain: a thin shimmering beam between the posts,
// a soft halo, drifting interference bands and chevrons flowing in the pass
// direction (+X). Drawn on a quad whose local coords are in pixels.
shader_type canvas_item;
render_mode blend_add, unshaded;

uniform vec4 tint : source_color = vec4(0.5, 0.9, 1.0, 1.0);
uniform float intensity = 1.0;
uniform float half_span = 200.0;   // px from centre to each post
uniform float band = 48.0;          // px half-width of the curtain along X
uniform float flow = 1.0;           // chevron flow speed multiplier

varying vec2 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	float ax = abs(lp.x) / band;
	float ay = abs(lp.y) / half_span;
	float span_fade = smoothstep(1.0, 0.88, ay);
	float shimmer = 0.72 + 0.28 * sin(lp.y * 0.045 - TIME * 7.0) * sin(lp.y * 0.011 + TIME * 2.7);
	float core = exp(-ax * ax * 260.0) * 1.1;
	float halo = exp(-ax * ax * 18.0) * 0.3;
	float bands = 0.5 + 0.5 * sin(lp.y * 0.07 + TIME * 3.0 + sin(lp.x * 0.05 + TIME));
	float curtain = exp(-ax * ax * 4.0) * 0.14 * bands;
	float cell = 56.0;
	float cy = mod(lp.y, cell) - cell * 0.5;
	float c = lp.x + abs(cy) * 0.9;
	float stripe = fract(c / 40.0 - TIME * 1.3 * flow);
	float chev = smoothstep(0.0, 0.1, stripe) * smoothstep(0.3, 0.16, stripe);
	chev *= exp(-ax * ax * 3.0) * 0.3 * (1.0 - smoothstep(0.85, 1.0, ax));
	float a = (core * shimmer + halo * shimmer + curtain + chev) * span_fade * intensity;
	COLOR = vec4(tint.rgb, clamp(a, 0.0, 1.0));
}
