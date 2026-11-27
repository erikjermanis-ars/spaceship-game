// The ringed gas giant of the Vesper sky look: planet and rings in ONE quad so
// they can shadow each other exactly and cost a single partial pass.
//
// Orthographic sphere (view space: x right, y down, z to the viewer). The
// rings are the planet's equatorial plane: each pixel's view ray is intersected
// with that plane and the hit radius indexes a 1D density profile (`ring_tex`,
// built on the CPU with mipmaps so thin ringlets do not shimmer at the ansae).
//   * planet shadow on the rings: a cylinder along -light_dir;
//   * ring shadow on the planet: march the surface point towards the sun onto
//     the ring plane and read the same profile, blurred.
// Output is premultiplied: opaque disk, translucent rings, additive thin halo.
shader_type canvas_item;
render_mode blend_premul_alpha, unshaded;

uniform sampler2D surface_tex : repeat_enable, filter_linear;
uniform sampler2D ring_tex : repeat_disable, filter_linear_mipmap;
uniform mat3 view_to_planet = mat3(1.0);
uniform vec3 light_dir = vec3(-0.8, 0.4, 0.3);   // towards the sun, view space
uniform float extent = 2.45;          // quad half-size in planet radii
uniform float spin = 0.0;
uniform float ring_inner = 1.22;      // planet radii
uniform float ring_outer = 2.35;
uniform float day_gain = 0.60;        // keeps the cloud tops under hull brightness
uniform float ring_gain = 0.46;
uniform float ring_opacity = 0.9;
uniform vec3 ring_bright : source_color = vec3(0.84, 0.76, 0.64);
uniform vec3 ring_dusty : source_color = vec3(0.50, 0.37, 0.29);
uniform vec3 haze_color : source_color = vec3(0.95, 0.72, 0.45);
uniform float haze_height = 0.035;

float ring_u(float rho) {
	return (rho - ring_inner) / (ring_outer - ring_inner);
}

void fragment() {
	vec2 c = (UV * 2.0 - 1.0) * extent;
	float r = length(c);
	float aa = max(fwidth(r), 1e-4);
	float disk = 1.0 - smoothstep(1.0 - aa * 1.5, 1.0, r);
	vec3 L = normalize(light_dir);
	// Ring plane normal (the planet's pole) in view space.
	vec3 N = normalize(vec3(0.0, 1.0, 0.0) * view_to_planet);
	float z = sqrt(max(1.0 - r * r, 0.0));

	// ---- planet ----
	vec3 surf = vec3(0.0);
	if (r < 1.0) {
		vec3 n = vec3(c, z);
		vec3 pn = view_to_planet * n;
		float lat = asin(clamp(-pn.y, -1.0, 1.0));
		float lon = atan(pn.z, pn.x);
		vec4 s = texture(surface_tex, vec2((lon + spin) / TAU, 0.5 - lat / PI));
		float ndl = dot(n, L);
		// High clouds catch the light a little past the terminator.
		float lit = smoothstep(-0.10, 0.62, ndl + 0.05 * (s.a - 0.5));
		// Gas giants darken strongly towards the limb (deep scattering haze).
		float limb = mix(0.42, 1.0, pow(z, 0.55));
		// Ring shadow: follow the sun ray from this point to the ring plane.
		float ln = dot(L, N);
		float t = -dot(n, N) / (abs(ln) < 1e-3 ? 1e-3 : ln);
		float sh = 0.0;
		if (t > 0.0) {
			float us = ring_u(length(n + t * L));
			if (us > 0.0 && us < 1.0) {
				sh = textureLod(ring_tex, vec2(us, 0.5), 2.0).r;
			}
		}
		vec3 col = s.rgb * lit * limb * day_gain * (1.0 - 0.72 * sh);
		// Night side: faint ring-shine, so it reads as a globe and not a hole.
		float night = 1.0 - smoothstep(-0.2, 0.1, ndl);
		col += (s.rgb * 0.035 + vec3(0.010, 0.008, 0.007)) * night;
		// Warm haze on the lit limb, a thin cool one on the dark limb.
		float fres = pow(1.0 - z, 3.0);
		col += haze_color * fres * smoothstep(-0.2, 0.5, ndl) * 0.16;
		col += vec3(0.03, 0.05, 0.07) * fres * 0.5;
		surf = col;
	}

	// ---- thin halo outside the disk (additive) ----
	float h = max(r - 1.0, 0.0) / haze_height;
	vec2 nl = c / max(r, 1e-4);
	float halo_lit = smoothstep(-0.5, 0.5, dot(nl, L.xy) + L.z * 0.2);
	vec3 halo = haze_color * exp(-h * 2.4) * 0.22 * (0.03 + halo_lit) * (1.0 - disk);

	// ---- rings ----
	float zr = -(c.x * N.x + c.y * N.y) / N.z;
	vec3 P = vec3(c, zr);
	float u = ring_u(length(P));
	vec3 ring_pm = vec3(0.0);
	float ring_a = 0.0;
	if (u > 0.0 && u < 1.0) {
		vec4 rp = texture(ring_tex, vec2(u, 0.5));
		float dens = rp.r;
		// We look at the sunlit face when the sun and the viewer are on the
		// same side of the plane; otherwise only light leaking through shows.
		float same_side = step(0.0, dot(L, N) * N.z);
		float face = mix(0.22 * (1.0 - dens), 1.0, same_side);
		// Planet shadow across the rings (penumbra widens with distance).
		float along = dot(P, L);
		float perp = length(P - L * along);
		float soft = 0.03 + 0.02 * max(-along, 0.0);
		float shadow = along < 0.0 ? smoothstep(0.985 - soft, 0.985 + soft, perp) : 1.0;
		vec3 rc = mix(ring_dusty, ring_bright, rp.g) * ring_gain * face;
		rc *= mix(0.05, 1.0, shadow);
		ring_a = dens * ring_opacity;
		ring_pm = rc * ring_a;
	}

	// ---- composite: rings in front of or behind the globe ----
	vec3 body = surf * disk + halo;
	vec3 rgb;
	float alpha;
	if (r >= 1.0 || zr > z) {
		rgb = ring_pm + body * (1.0 - ring_a);
		alpha = ring_a + disk * (1.0 - ring_a);
	} else {
		rgb = body + ring_pm * (1.0 - disk);
		alpha = disk + ring_a * (1.0 - disk);
	}
	COLOR = vec4(rgb, alpha);
}
