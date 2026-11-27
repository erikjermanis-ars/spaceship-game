// Asteroid belt rocks (Vesper sky look): one big static mesh per depth layer.
// All shading happens per VERTEX, so the fragment stage is free. The mesh
// stores a fake surface normal in COLOR.rg and the rock's albedo in COLOR.b;
// lighting is resolved here instead of being baked into vertex colours because
// the belt slowly orbits (the mesh rotates) while the sun does not.
shader_type canvas_item;
render_mode unshaded;

uniform vec2 sun_local = vec2(-0.9, 0.44);   // towards the sun, in mesh space
uniform vec3 lit_color : source_color = vec3(0.30, 0.23, 0.18);
uniform vec3 shadow_color : source_color = vec3(0.030, 0.026, 0.034);
uniform float opacity = 0.85;

void vertex() {
	vec2 n = COLOR.rg * 2.0 - 1.0;
	float nz = sqrt(max(1.0 - dot(n, n), 0.0));
	// The sun sits low over the belt plane, so rims facing it catch the light
	// and the far rims fall into shadow: reads as lumps, not flat cut-outs.
	float ndl = dot(vec3(n, nz), normalize(vec3(sun_local * 0.9, 0.45)));
	float lit = smoothstep(-0.35, 0.9, ndl);
	COLOR = vec4(mix(shadow_color, lit_color, lit) * (0.55 + 0.6 * COLOR.b), COLOR.a * opacity);
}
