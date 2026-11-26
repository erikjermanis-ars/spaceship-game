// The home planet, drawn on a quad that covers the disk plus its atmosphere.
// Orthographic sphere; surface data comes from the baked equirect map
// (planet_bake.gdshader). Lighting: day/night terminator, ocean sun glint,
// clouds, blue atmospheric rim scattering with a warm terminator band, and
// procedural city lights on the night side.
// Output is premultiplied: the disk is opaque, the halo outside is additive.
shader_type canvas_item;
render_mode blend_premul_alpha, unshaded;

#include "res://assets/art/environment/shaders/noise.gdshaderinc"

uniform sampler2D surface_tex : repeat_enable, filter_linear;
uniform mat3 view_to_planet = mat3(1.0);
uniform vec3 light_dir = vec3(-0.55, -0.80, 0.22);   // towards the sun, view space (y down, z to viewer)
uniform float extent = 1.22;          // quad half-size in planet radii
uniform float atmo_height = 0.075;    // halo falloff in planet radii
uniform float spin = 0.0;             // surface longitude offset (rad)
uniform float cloud_spin = 0.0;       // clouds drift a little faster
uniform float day_gain = 0.82;        // keep the day side from out-shining the station hulls
uniform float city_gain = 1.0;
uniform vec3 atmo_color : source_color = vec3(0.32, 0.58, 1.0);
uniform vec3 sunset_color : source_color = vec3(1.0, 0.48, 0.22);
uniform vec3 city_warm : source_color = vec3(1.0, 0.82, 0.48);
uniform vec3 city_cool : source_color = vec3(0.55, 0.88, 1.0);


vec3 surface_albedo(vec4 s, float lat, out float ocean) {
	float e = s.r * 2.0 - 1.0;
	float moist = s.g;
	ocean = 1.0 - smoothstep(-0.004, 0.012, e);
	vec3 deep = vec3(0.015, 0.055, 0.14);
	vec3 shallow = vec3(0.04, 0.20, 0.30);
	vec3 water = mix(deep, shallow, smoothstep(-0.22, 0.0, e));
	vec3 lush = vec3(0.10, 0.21, 0.09);
	vec3 savanna = vec3(0.30, 0.30, 0.14);
	vec3 desert = vec3(0.50, 0.40, 0.25);
	vec3 rock = vec3(0.30, 0.27, 0.24);
	vec3 snow = vec3(0.86, 0.90, 0.94);
	vec3 land = mix(desert, savanna, smoothstep(0.18, 0.42, moist));
	land = mix(land, lush, smoothstep(0.42, 0.68, moist));
	land = mix(land, rock, smoothstep(0.16, 0.34, e));
	float ice = smoothstep(1.05, 1.25, abs(lat) + 0.25 * (moist - 0.5)) + smoothstep(0.32, 0.44, e);
	land = mix(land, snow, clamp(ice, 0.0, 1.0));
	water = mix(water, snow * 0.9, smoothstep(1.18, 1.32, abs(lat)));
	return mix(land, water, ocean);
}

void fragment() {
	vec2 c = (UV * 2.0 - 1.0) * extent;
	float r = length(c);
	float aa = max(fwidth(r), 1e-4);
	float disk = 1.0 - smoothstep(1.0 - aa * 1.5, 1.0, r);
	vec3 L = normalize(light_dir);

	vec3 surf = vec3(0.0);
	if (r < 1.0) {
		float z = sqrt(max(1.0 - r * r, 0.0));
		vec3 n = vec3(c, z);
		vec3 pn = view_to_planet * n;
		float lat = asin(clamp(-pn.y, -1.0, 1.0));
		float lon = atan(pn.z, pn.x);
		float v = 0.5 - lat / PI;
		vec4 s = texture(surface_tex, vec2((lon + spin) / TAU, v));
		float clouds = texture(surface_tex, vec2((lon + cloud_spin) / TAU, v)).a;
		float ocean;
		vec3 albedo = surface_albedo(s, lat, ocean);

		float ndl = dot(n, L);
		float lit = smoothstep(-0.06, 0.55, ndl);
		float night = 1.0 - smoothstep(-0.16, 0.06, ndl);

		vec3 col = albedo * lit * day_gain;
		// Faint moonlight on the night side so it reads as terrain, not a hole.
		col += (albedo * 0.06 + vec3(0.004, 0.007, 0.014)) * night;
		// Sun glint on open water.
		vec3 hv = normalize(L + vec3(0.0, 0.0, 1.0));
		float spec = pow(max(dot(n, hv), 0.0), 70.0) * ocean * lit;
		col += vec3(1.0, 0.92, 0.78) * spec * 0.55 * (1.0 - clouds);
		// Cloud deck, slightly shadowed on the night edge.
		float cl = smoothstep(0.18, 0.85, clouds);
		vec3 cloud_col = vec3(0.92, 0.94, 0.98) * smoothstep(-0.02, 0.6, ndl) * day_gain;
		col = mix(col, cloud_col, cl * 0.88);
		col += vec3(0.020, 0.026, 0.040) * cl * night;

		// City lights: baked metro density x procedural street-scale clustering.
		float dens = s.b;
		if (dens > 0.01 && night > 0.001) {
			vec3 sp = pn * 1.0;
			// Rotate the lookup with the surface so lights stay glued to land.
			float cs = cos(spin);
			float sn = sin(spin);
			sp = vec3(cs * sp.x - sn * sp.z, sp.y, sn * sp.x + cs * sp.z);
			float n1 = noise3(sp * 55.0);          // districts
			float n2 = noise3(sp * 240.0 + 3.0);   // blocks
			float n3 = noise3(sp * 640.0 + 7.0);   // individual sparkle
			float district = smoothstep(-0.18, 0.22, n1 + (dens - 0.4) * 0.8);
			float blocks = smoothstep(-0.08, 0.3, n2 + 0.12 * district);
			float spark = smoothstep(0.18, 0.45, n3);
			float lights = 1.7 * dens * district * blocks * (0.3 + 1.2 * spark);
			lights += smoothstep(0.65, 1.0, dens) * district * 0.45 * (0.5 + 0.5 * blocks);
			float coolmix = smoothstep(0.25, 0.45, noise3(sp * 18.0 + 9.0));
			vec3 lc = mix(city_warm, city_cool, coolmix * 0.35);
			float vis = night * (1.0 - cl * 0.8);
			col += lc * lights * vis * 0.95 * city_gain;
			// Light bouncing off the undersides of clouds: a soft warm smear.
			col += city_warm * dens * cl * night * 0.06 * city_gain;
		}

		// Atmosphere seen through the limb: blue haze on the day side, a warm
		// band at the terminator, a faint airglow on the night side.
		float fres = pow(1.0 - z, 2.6);
		float scat = smoothstep(-0.30, 0.45, ndl);
		float tband = exp(-pow((ndl + 0.03) / 0.09, 2.0));
		col = mix(col, atmo_color * lit * 0.55, 0.16 * lit);
		col += atmo_color * fres * scat * 0.85;
		col += sunset_color * tband * (0.03 + 0.7 * fres) * 0.45;
		col += vec3(0.05, 0.09, 0.16) * fres * 0.4;
		// Night side should still read as a solid disk against the stars.
		col += vec3(0.006, 0.009, 0.018);
		surf = col;
	}

	// ---- halo outside the disk (additive) ----
	float h = max(r - 1.0, 0.0) / atmo_height;
	vec2 nl = c / max(r, 1e-4);
	float limb_l = dot(nl, L.xy) + L.z * 0.15;
	float halo_lit = smoothstep(-0.45, 0.55, limb_l);
	vec3 halo_col = mix(sunset_color, atmo_color, smoothstep(-0.25, 0.35, limb_l));
	float glow = exp(-h * 2.6) * 0.75 + exp(-h * 0.6) * 0.10;
	vec3 halo = halo_col * glow * (0.06 + halo_lit) * 0.95;
	halo *= 1.0 - smoothstep(extent * 0.9, extent, r);

	vec3 rgb = surf * disk + halo * (1.0 - disk);
	COLOR = vec4(rgb, disk);
}
