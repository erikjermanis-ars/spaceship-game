// Small distant moon: grey cratered sphere lit by the same sun as the planet.
// It is tiny on screen, so per-pixel 3D noise is affordable here.
shader_type canvas_item;
render_mode blend_premul_alpha, unshaded;

#include "res://assets/art/environment/shaders/noise.gdshaderinc"

uniform vec3 light_dir = vec3(-0.55, -0.80, 0.22);
uniform float extent = 1.15;
uniform float gain = 0.85;
// Surface character, so the same sphere can be Meridian's grey moon (the
// defaults), an icy moon or a dark cratered one.
uniform vec3 tint = vec3(0.86, 0.88, 0.92);
uniform float albedo_hi = 0.62;
uniform float albedo_lo = 0.36;
uniform vec3 night_color = vec3(0.025, 0.035, 0.06);   // light bounced off the parent world
uniform vec3 rim_color = vec3(0.25, 0.35, 0.55);
uniform vec3 seed = vec3(5.0, 1.0, 3.0);
uniform float crater_scale = 2.4;

void fragment() {
	vec2 c = (UV * 2.0 - 1.0) * extent;
	float r = length(c);
	float aa = max(fwidth(r), 1e-4);
	float disk = 1.0 - smoothstep(1.0 - aa * 1.5, 1.0, r);
	vec3 L = normalize(light_dir);
	vec3 rgb = vec3(0.0);
	if (r < 1.0) {
		float z = sqrt(max(1.0 - r * r, 0.0));
		vec3 n = vec3(c, z);
		vec3 p = n * 2.3 + seed;
		float maria = smoothstep(0.0, 0.25, fbm3(p * 0.9, 4));
		float crater = ridged3(p * crater_scale, 3);
		float albedo = mix(albedo_hi, albedo_lo, maria) * (0.82 + 0.3 * crater);
		float ndl = dot(n, L);
		float lit = smoothstep(-0.03, 0.35, ndl);
		rgb = tint * albedo * lit * gain;
		// Earthshine: the night side is faintly lit by the planet below-left.
		rgb += night_color * (1.0 - lit);
		rgb += rim_color * pow(1.0 - z, 3.0) * lit * 0.25;
	}
	// Barely-there halo so it sits in the sky rather than on it.
	float h = max(r - 1.0, 0.0);
	vec3 halo = vec3(0.6, 0.65, 0.75) * exp(-h * 18.0) * 0.06 * (1.0 - disk);
	halo *= 1.0 - smoothstep(extent * 0.85, extent, r);
	COLOR = vec4(rgb * disk + halo, disk);
}
