// The white-out that hides the cut into and out of the tunnel. It blooms from
// the focus: at partial `flash` the middle is already opaque while the corners
// are still clearing, and at 1 the whole screen is covered.
shader_type canvas_item;
render_mode unshaded;

uniform vec2 view_size = vec2(1920.0, 1080.0);
uniform vec2 focus = vec2(960.0, 540.0);
uniform float flash = 0.0;
uniform vec3 tint = vec3(1.0);

void fragment() {
	float r = length((UV * view_size - focus) / view_size.y);
	float a = clamp(flash * (1.0 + 1.6 * exp(-r * 2.4)), 0.0, 1.0);
	a = a * a * (3.0 - 2.0 * a);
	COLOR = vec4(mix(tint, vec3(1.0), a * a), a);
}
