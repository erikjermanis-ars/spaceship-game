// Fullscreen additive sun: white-hot core, warm bloom, wide cool scatter, a
// faint anamorphic streak, a static starburst, and lens-flare ghosts strung
// along the line from the sun through the screen centre. Everything is scaled
// by `sun_vis` (the script dims it when the planet eclipses the sun).
shader_type canvas_item;
render_mode blend_add, unshaded;

uniform vec2 view_size = vec2(1920.0, 1080.0);
uniform vec2 sun_pos = vec2(150.0, 150.0);   // canvas units
uniform float sun_vis = 1.0;
uniform float intensity = 1.0;
uniform float ghost_gain = 1.0;
// A farther sun (another sky look): `size` < 1 shrinks the whole glare around
// the sun, `sun_tint` shifts its colour. Defaults are the Meridian sun.
uniform float size = 1.0;
uniform vec3 sun_tint = vec3(1.0);

float hexagon(vec2 p, float radius) {
	p = abs(p);
	float d = max(p.x * 0.8660254 + p.y * 0.5, p.y);
	return d / radius;
}

vec3 ghost(vec2 frag, vec2 at, float radius, vec3 tint, float hex) {
	vec2 d = frag - at;
	float rr = mix(length(d) / radius, hexagon(d, radius), hex);
	float body = 1.0 - smoothstep(0.75, 1.0, rr);
	float rim = exp(-pow((rr - 0.93) / 0.06, 2.0));
	return tint * (body * 0.55 + rim * 0.6);
}

void fragment() {
	vec2 frag = UV * view_size;
	float H = view_size.y;
	vec2 d = (frag - sun_pos) / (H * size);
	float r = length(d);

	vec3 col = vec3(0.0);
	float core = exp(-pow(r / 0.0075, 2.0));
	float inner = exp(-r / 0.022);
	float bloom = exp(-r / 0.085);
	float scatter = exp(-r / 0.38);
	col += vec3(1.0, 0.98, 0.94) * core * 1.6;
	col += vec3(1.0, 0.92, 0.78) * inner * 0.65;
	col += vec3(1.0, 0.78, 0.55) * bloom * 0.22;
	col += vec3(0.35, 0.45, 0.75) * scatter * 0.07;

	// Anamorphic horizontal streak (subtle, cool-tinted).
	float streak = exp(-abs(d.y) / 0.0025) * exp(-abs(d.x) / 0.22);
	col += vec3(0.55, 0.75, 1.0) * streak * 0.16;

	// Static starburst rays (aperture blades).
	float ang = atan(d.y, d.x);
	float rays = pow(abs(cos(ang * 3.0 + 0.4)), 60.0) + 0.6 * pow(abs(cos(ang * 7.0 + 1.1)), 120.0);
	col += vec3(1.0, 0.93, 0.82) * rays * exp(-r / 0.09) * 0.12 * smoothstep(0.004, 0.02, r);

	// Lens ghosts along the sun -> centre axis (and beyond).
	vec2 axis = view_size * 0.5 - sun_pos;
	vec3 g = vec3(0.0);
	g += ghost(frag, sun_pos + axis * 0.42, H * 0.022, vec3(0.30, 0.65, 0.70), 1.0) * 0.050;
	g += ghost(frag, sun_pos + axis * 0.70, H * 0.055, vec3(0.45, 0.30, 0.70), 1.0) * 0.032;
	g += ghost(frag, sun_pos + axis * 1.24, H * 0.016, vec3(0.90, 0.65, 0.35), 0.0) * 0.028;
	g += ghost(frag, sun_pos + axis * 1.42, H * 0.085, vec3(0.25, 0.55, 0.45), 1.0) * 0.022;
	g += ghost(frag, sun_pos + axis * 1.62, H * 0.035, vec3(0.70, 0.40, 0.55), 1.0) * 0.035;
	g += ghost(frag, sun_pos + axis * 1.90, H * 0.140, vec3(0.30, 0.40, 0.70), 0.0) * 0.016;
	// A thin halo ring around the sun (ice-crystal style lens ring).
	float ring = exp(-pow((r - 0.24) / 0.012, 2.0));
	g += vec3(0.45, 0.55, 0.75) * ring * 0.022;
	col += g * ghost_gain;

	col *= sun_tint * (intensity * sun_vis);
	COLOR = vec4(col, 1.0);
}
