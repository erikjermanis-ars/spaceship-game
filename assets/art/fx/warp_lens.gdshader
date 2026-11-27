// Jump spool-up and leap, pass 1: bends the picture that is already on screen
// (world + sky; the HUD is on a higher layer and is not touched).
//   charge: space is drawn towards the ship: a growing pinch with a ripple
//           running inwards, colour fringes and a closing vignette.
//   streak: every pixel is smeared outwards from the focus, so the real stars
//           and station lights stretch into radial streaks with red/blue tips.
//   shock:  the expanding shock ring refracts what it passes over.
// Reads the screen with hint_screen_texture, which the Compatibility renderer
// supports for canvas items (one backbuffer copy while this rect is visible).
shader_type canvas_item;
render_mode unshaded, blend_disabled;

#include "res://assets/art/fx/warp_palette.gdshaderinc"

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform vec2 view_size = vec2(1920.0, 1080.0);
uniform vec2 focus = vec2(960.0, 540.0);     // canvas units
uniform float time = 0.0;
uniform float charge = 0.0;
uniform float streak = 0.0;
uniform float shock = 1.0;                   // 0..1 ring progress, >= 1 = none

const int TAPS = 10;

void fragment() {
	vec2 fuv = focus / view_size;
	vec2 d = SCREEN_UV - fuv;
	float r = length(d * vec2(view_size.x / view_size.y, 1.0));   // in screen heights

	// ---- charge: pinch + inward ripple ----
	float ripple = sin(r * 34.0 + time * (7.0 + 9.0 * charge)) * smoothstep(0.04, 0.25, r) * smoothstep(1.2, 0.3, r);
	float pull = charge * (0.045 * smoothstep(0.0, 0.9, r) + 0.0035 * charge * ripple);
	// ---- shock ring: a thin radial kick where the ring is ----
	float rs = shock * 1.5;
	float ring = shock < 1.0 ? exp(-pow((r - rs) / (0.03 + 0.05 * shock), 2.0)) * (1.0 - shock) : 0.0;
	pull -= ring * 0.06;

	// The smear (and its gain) fades to nothing at the focus, so the cheap and
	// the smeared branch below meet without a visible edge.
	float away = smoothstep(0.0, 0.25, r);
	float len = streak * streak * 0.42 * away;
	float ca = 0.004 * charge * r + 0.10 * len;
	vec3 col;
	if (len < 0.002) {
		// No smear: three taps are enough for the colour fringes.
		col.r = texture(screen_tex, fuv + d * (1.0 + pull + ca)).r;
		col.g = texture(screen_tex, fuv + d * (1.0 + pull)).g;
		col.b = texture(screen_tex, fuv + d * (1.0 + pull - ca)).b;
	} else {
		// Radial smear. Tap positions are jittered per pixel, which trades
		// banding for fine grain; the max term keeps stretched stars bright
		// (a plain average would dim them into nothing).
		float j = whash2(FRAGCOORD.xy);
		vec3 sum = vec3(0.0);
		vec3 peak = vec3(0.0);
		float wsum = 0.0;
		for (int i = 0; i < TAPS; i++) {
			float t = (float(i) + j) / float(TAPS);
			float w = 1.0 - 0.6 * t;
			float k = 1.0 + pull - len * t;
			vec3 s = vec3(
				texture(screen_tex, fuv + d * (k - ca * t)).r,
				texture(screen_tex, fuv + d * k).g,
				texture(screen_tex, fuv + d * (k + ca * t)).b);
			sum += s * w;
			peak = max(peak, s * w);
			wsum += w;
		}
		col = mix(sum / wsum, peak, 0.55 * smoothstep(0.002, 0.02, len));
	}
	col *= 1.0 + 0.9 * streak * away;

	// Closing vignette while charging: the eye is pulled to the ship.
	col *= 1.0 - 0.42 * charge * smoothstep(0.25, 1.05, r);
	COLOR = vec4(col, 1.0);
}
