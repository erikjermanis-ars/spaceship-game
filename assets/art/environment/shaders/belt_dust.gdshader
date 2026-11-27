// Faint sunlit dust along the asteroid belt (Vesper sky look): an additive
// strip mesh that follows the belt's arc. The strip's vertex alpha carries the
// across-the-band falloff; the wisps come from the already-baked nebula
// texture, reused as tileable noise, so this costs one fetch per pixel.
shader_type canvas_item;
render_mode blend_add, unshaded;

#include "res://assets/art/environment/shaders/noise.gdshaderinc"

uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform vec3 tint : source_color = vec3(0.80, 0.52, 0.34);
uniform float gain = 0.10;

void fragment() {
	vec4 n = texture(noise_tex, UV);
	vec4 n2 = texture(noise_tex, UV * vec2(0.37, 0.41) + vec2(0.21, 0.63));
	float wisps = dot(n.rgb, vec3(0.33)) * 2.2 + 0.35;
	float lanes = (1.0 - 0.75 * n.a) * (0.45 + 1.1 * dot(n2.rgb, vec3(0.33)) * 2.0);
	vec3 col = tint * gain * COLOR.a * wisps * lanes;
	// Dither: the band is a very shallow gradient and would band in 8 bits.
	col += (hash12(FRAGCOORD.xy) - 0.5) / 255.0;
	COLOR = vec4(max(col, vec3(0.0)), 1.0);
}
