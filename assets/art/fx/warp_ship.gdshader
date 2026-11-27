// The ship snapshot drawn over the tunnel: the texture as given, lit by the
// tunnel. The bow end (texture +x) catches the light of the vanishing point,
// the whole hull picks up a little of the journey colour, and the brightness
// trembles with the shudder.
shader_type canvas_item;
render_mode unshaded;

#include "res://assets/art/fx/warp_palette.gdshaderinc"

uniform float time = 0.0;
uniform float glow = 1.0;       // 0 = plain sprite, 1 = full tunnel lighting
uniform float mix_m = 0.0;

void fragment() {
	vec4 base = COLOR;              // texture x modulate
	vec3 hot = warp_hot(mix_m);
	vec3 mid = warp_mid(mix_m);
	float bow = smoothstep(0.35, 1.0, UV.x);
	float flick = 0.9 + 0.1 * sin(time * 31.0 + UV.x * 9.0);
	vec3 lit = base.rgb * mix(vec3(1.0), 0.80 + 0.45 * mid, 0.55 * glow);
	lit += hot * bow * bow * 0.30 * glow * flick;
	COLOR = vec4(lit, base.a);
}
