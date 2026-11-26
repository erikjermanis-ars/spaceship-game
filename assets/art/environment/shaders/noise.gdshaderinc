// Shared hash / noise helpers for the space backdrop.
// Hashes are Dave Hoskins' sin-free "hash without sine" variants: stable across
// GPUs (no sin() precision issues) and cheap enough for per-pixel use.

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

vec3 hash32(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yxz + 33.33);
	return fract((p3.xxy + p3.yzz) * p3.zyx);
}

vec3 hash33s(vec3 p3) {
	p3 = fract(p3 * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yxz + 33.33);
	return -1.0 + 2.0 * fract((p3.xxy + p3.yxx) * p3.zyx);
}

// ---- periodic 2D gradient noise (tileable: `per` must be integer cells) ----
vec2 pgrad(vec2 i, vec2 per) {
	float a = hash12(mod(i, per)) * 6.2831853;
	return vec2(cos(a), sin(a));
}

float pnoise(vec2 p, vec2 per) {
	vec2 i = floor(p);
	vec2 f = p - i;
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = dot(pgrad(i, per), f);
	float b = dot(pgrad(i + vec2(1.0, 0.0), per), f - vec2(1.0, 0.0));
	float c = dot(pgrad(i + vec2(0.0, 1.0), per), f - vec2(0.0, 1.0));
	float d = dot(pgrad(i + vec2(1.0, 1.0), per), f - vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Octave frequency doubles each step, so the period doubles too: stays tileable.
float pfbm(vec2 p, vec2 per, int octaves) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < octaves; i++) {
		sum += amp * pnoise(p, per);
		p = p * 2.0 + vec2(17.31, 9.17) * float(i + 1);
		per *= 2.0;
		amp *= 0.5;
	}
	return sum;
}

// ---- 3D gradient noise (used on sphere points: seamless, no pole pinch) ----
float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = p - i;
	vec3 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(dot(hash33s(i + vec3(0.0, 0.0, 0.0)), f - vec3(0.0, 0.0, 0.0)),
				dot(hash33s(i + vec3(1.0, 0.0, 0.0)), f - vec3(1.0, 0.0, 0.0)), u.x),
			mix(dot(hash33s(i + vec3(0.0, 1.0, 0.0)), f - vec3(0.0, 1.0, 0.0)),
				dot(hash33s(i + vec3(1.0, 1.0, 0.0)), f - vec3(1.0, 1.0, 0.0)), u.x), u.y),
		mix(mix(dot(hash33s(i + vec3(0.0, 0.0, 1.0)), f - vec3(0.0, 0.0, 1.0)),
				dot(hash33s(i + vec3(1.0, 0.0, 1.0)), f - vec3(1.0, 0.0, 1.0)), u.x),
			mix(dot(hash33s(i + vec3(0.0, 1.0, 1.0)), f - vec3(0.0, 1.0, 1.0)),
				dot(hash33s(i + vec3(1.0, 1.0, 1.0)), f - vec3(1.0, 1.0, 1.0)), u.x), u.y),
		u.z);
}

float fbm3(vec3 p, int octaves) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < octaves; i++) {
		sum += amp * noise3(p);
		p = p * 2.03 + vec3(1.7, 9.2, 4.1);
		amp *= 0.5;
	}
	return sum;
}

float ridged3(vec3 p, int octaves) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < octaves; i++) {
		float n = 1.0 - abs(noise3(p) * 1.6);
		sum += amp * n * n;
		p = p * 2.07 + vec3(3.1, 5.7, 2.3);
		amp *= 0.5;
	}
	return sum;
}

mat2 rot2(float a) {
	float c = cos(a);
	float s = sin(a);
	return mat2(vec2(c, s), vec2(-s, c));
}
