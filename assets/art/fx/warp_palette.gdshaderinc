// Shared by the warp_* shaders: the journey palette and small hashes.
// `m` runs 0 -> 1 along the jump: cool blue/teal (Meridian) through violet to
// warm amber (Vesper). The script flips it for the trip back.

vec3 warp_ramp(vec3 a, vec3 b, vec3 c, float m) {
	float t = clamp(m, 0.0, 1.0) * 2.0;
	return t < 1.0 ? mix(a, b, smoothstep(0.0, 1.0, t)) : mix(b, c, smoothstep(0.0, 1.0, t - 1.0));
}

// The dark between the streaks.
vec3 warp_deep(float m) {
	return warp_ramp(vec3(0.012, 0.040, 0.120), vec3(0.075, 0.018, 0.130), vec3(0.140, 0.045, 0.014), m);
}

// Walls, filaments, glows.
vec3 warp_mid(float m) {
	return warp_ramp(vec3(0.10, 0.52, 0.98), vec3(0.62, 0.27, 0.92), vec3(1.00, 0.50, 0.15), m);
}

// Streak heads and the vanishing point: nearly white, faintly tinted.
vec3 warp_hot(float m) {
	return warp_ramp(vec3(0.72, 0.95, 1.00), vec3(0.97, 0.84, 1.00), vec3(1.00, 0.92, 0.72), m);
}

float whash(float n) {
	n = fract(n * 0.1031);
	n *= n + 33.33;
	n *= n + n;
	return fract(n);
}

float whash2(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
