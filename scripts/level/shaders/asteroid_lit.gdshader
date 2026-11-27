// Sun-lit facets for the tumbling rocks of the Vesper field.
// A rock is one cached triangle array (see RockArt). Each facet's normal is
// stored in its vertices' UVs, so the lighting can be done here, in WORLD
// space: the rock turns, the sun stays where it is, and nothing is redrawn.
//   UV.x > 3  : unlit (outline stroke, shadow, ore veins, cracks)
//   otherwise : UV = facet normal xy (z implied), COLOR = albedo
// Constants mirror RockArt.LIGHT3 / SHADE_*.
shader_type canvas_item;

const vec3 SUN = vec3(-0.468, -0.624, 0.62);

varying float v_shade;

void vertex() {
	vec2 n = UV;
	float lit = 1.0 - step(3.0, n.x);
	vec2 nw = normalize(MODEL_MATRIX[0].xy) * n.x + normalize(MODEL_MATRIX[1].xy) * n.y;
	float nz = sqrt(max(0.0, 1.0 - dot(n, n)));
	float k = dot(vec3(nw, nz), SUN);
	v_shade = mix(1.0, clamp(1.0 + (k - SUN.z) * 0.85, 0.3, 1.45), lit);
}

void fragment() {
	COLOR = vec4(COLOR.rgb * v_shade, COLOR.a);
}
