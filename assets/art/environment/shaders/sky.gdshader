// Fullscreen deep-space pass: base gradient + baked nebula + 3 procedural star
// layers + a sparse layer of bright glinting stars. Each layer has its own
// parallax (`p`) and derives a physically consistent zoom from the camera zoom
// (s = 1 / (p / zoom + 1 - p)), so far layers barely move or scale.
//
// Stars are evaluated analytically per pixel (one cell lookup per layer) with a
// Gaussian profile whose width is set in PHYSICAL pixels (via derivatives).
// That keeps them crisp at any window scale and makes their total energy
// constant under sub-pixel motion, so they glide instead of crawling/shimmering.
shader_type canvas_item;
render_mode unshaded, blend_disabled;

#include "res://assets/art/environment/shaders/noise.gdshaderinc"

uniform sampler2D nebula_tex : repeat_enable, filter_linear;
uniform vec2 cam_pos = vec2(0.0);
uniform float cam_zoom = 1.0;
uniform float cam_rot = 0.0;
uniform vec2 view_size = vec2(1920.0, 1080.0);
uniform float twinkle_time = 0.0;
// Screen-space direction (0..1 UV) the sun sits at, for the scattered sky tint.
uniform vec2 sun_uv = vec2(0.08, 0.12);

uniform float nebula_parallax = 0.015;
uniform float nebula_tile = 3000.0;       // layer units per nebula texture tile
uniform float nebula_gain = 0.24;
uniform vec3 base_color : source_color = vec3(0.012, 0.018, 0.038);
uniform vec3 sun_sky_tint : source_color = vec3(0.07, 0.065, 0.085);
uniform float star_gain = 1.0;

float layer_scale(float p) {
	return 1.0 / (p / max(cam_zoom, 0.001) + 1.0 - p);
}

vec2 layer_coord(vec2 frag_c, float p, out float s) {
	s = layer_scale(p);
	return rot2(-cam_rot) * frag_c / s + cam_pos * p;
}

vec3 star_tint(float h) {
	// Colour temperature spread: few red/orange, many white, some blue.
	if (h < 0.10) return vec3(1.0, 0.70, 0.52);
	if (h < 0.30) return vec3(1.0, 0.89, 0.74);
	if (h < 0.72) return vec3(0.93, 0.95, 1.0);
	return vec3(0.70, 0.81, 1.0);
}

// Small stars: q = layer coord, cell = layer units, px = layer units per
// physical pixel, size = sigma in canvas units, gain = brightness scale.
vec3 star_layer(vec2 q, float cell, float prob, float px, float px_canvas, float size, float gain, float seed) {
	vec2 g = q / cell;
	vec2 id = floor(g);
	vec3 h = hash32(id + seed);
	if (h.x > prob) {
		return vec3(0.0);
	}
	float m = h.x / prob;                 // uniform 0..1 among existing stars
	float b = pow(1.0 - m, 5.0);          // mostly faint, a few bright
	vec2 sp = 0.18 + 0.64 * hash22(id * 1.37 + seed + 11.0);
	vec2 d = (g - id - sp) * cell / px;   // offset in physical pixels
	float sigma = max(size * (0.7 + 0.7 * b) / px_canvas, 0.6);
	float r2 = dot(d, d);
	float tw = 1.0 + 0.22 * sin(twinkle_time * (1.3 + 3.1 * h.z) + h.y * 61.0);
	float lum = gain * (0.10 + 1.25 * b) * tw;
	// Keep energy roughly constant when sigma is clamped up (tiny stars).
	return star_tint(h.z) * lum * exp(-r2 / (2.0 * sigma * sigma));
}

// Rare bright stars with soft halos and 4-point diffraction glints.
vec3 bright_layer(vec2 q, float cell, float prob, float px, float px_canvas, float seed) {
	vec2 g = q / cell;
	vec2 id = floor(g);
	vec3 h = hash32(id + seed);
	if (h.x > prob) {
		return vec3(0.0);
	}
	float m = h.x / prob;
	vec2 sp = 0.25 + 0.5 * hash22(id * 2.11 + seed + 5.0);
	vec2 dl = (g - id - sp) * cell;       // layer units
	vec2 d = dl / px;                     // physical pixels
	float margin_px = 0.25 * cell / px;
	float r = length(d);
	float scale = 1.0 / px_canvas;        // physical px per canvas unit
	float sigma = max(0.9 * scale, 0.75);
	float bright = 0.55 + 0.9 * pow(1.0 - m, 2.0);
	float tw = 1.0 + 0.12 * sin(twinkle_time * (0.8 + 1.7 * h.z) + h.y * 40.0);
	float core = exp(-r * r / (2.0 * sigma * sigma));
	float halo = exp(-r / (5.0 * scale)) * 0.14;
	float len = (6.0 + 18.0 * pow(1.0 - m, 2.0)) * scale;
	float thin = 0.55 * max(scale, 1.0);
	float spikes = exp(-abs(d.y) / thin) * exp(-abs(d.x) / len)
		+ exp(-abs(d.x) / thin) * exp(-abs(d.y) / len);
	float fade = smoothstep(margin_px, margin_px * 0.6, max(abs(d.x), abs(d.y)));
	vec3 tint = star_tint(fract(h.z * 7.3));
	return tint * bright * tw * (core * 1.3 + halo + spikes * 0.42 * fade);
}

void fragment() {
	vec2 frag = UV * view_size;
	vec2 frag_c = frag - view_size * 0.5;
	// Canvas units per physical pixel (handles hiDPI / window stretch).
	float px_canvas = max(length(dFdx(frag)), 1e-4);

	// ---- base: near-black blue with a faint scatter glow toward the sun ----
	vec2 su = (UV - sun_uv) * vec2(view_size.x / view_size.y, 1.0);
	float sun_d = length(su);
	vec3 col = base_color;
	col += sun_sky_tint * exp(-sun_d * 1.6);
	// Gentle vignette keeps the eye on the play area.
	vec2 vu = UV - 0.5;
	col *= 1.0 - 0.35 * dot(vu, vu);

	// ---- nebula ----
	float sn;
	vec2 qn = layer_coord(frag_c, nebula_parallax, sn);
	vec4 neb = texture(nebula_tex, qn / nebula_tile + vec2(0.37, 0.61));
	vec3 neb_col = neb.rgb * nebula_gain;
	float dust = neb.a;
	col += neb_col * (1.0 - 0.55 * dust);
	col *= 1.0 - 0.25 * dust;
	float neb_l = dot(neb.rgb, vec3(0.33));

	// ---- stars (density follows the bright band of the nebula) ----
	float dens = 0.75 + 1.6 * neb_l;
	float star_occl = 1.0 - 0.8 * dust;
	vec3 stars = vec3(0.0);
	float s0;
	vec2 q0 = layer_coord(frag_c, 0.03, s0);
	float px0 = px_canvas / s0;
	stars += star_layer(q0, 13.0, 0.30 * dens, px0, px_canvas, 0.42, 0.38, 3.0);
	stars += star_layer(q0 + 913.0, 23.0, 0.32 * dens, px0, px_canvas, 0.45, 0.55, 17.0);
	float s1;
	vec2 q1 = layer_coord(frag_c, 0.06, s1);
	float px1 = px_canvas / s1;
	stars += star_layer(q1, 41.0, 0.42 * dens, px1, px_canvas, 0.5, 0.75, 29.0);
	float s2;
	vec2 q2 = layer_coord(frag_c, 0.12, s2);
	float px2 = px_canvas / s2;
	stars += star_layer(q2, 83.0, 0.40, px2, px_canvas, 0.6, 0.95, 41.0);
	stars += bright_layer(q1 + 4000.0, 330.0, 0.20 * (0.6 + 0.8 * neb_l), px1, px_canvas, 53.0);
	stars += bright_layer(q2 + 9000.0, 520.0, 0.22, px2, px_canvas, 67.0);
	col += stars * star_occl * star_gain;

	// ---- dither: kills 8-bit banding in the dark gradients ----
	float dith = (hash12(FRAGCOORD.xy) + hash12(FRAGCOORD.xy + 71.3) - 1.0) / 255.0;
	col += dith;

	COLOR = vec4(col, 1.0);
}
