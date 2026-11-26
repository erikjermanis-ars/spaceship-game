// Bakes the planet's data maps once at startup into an equirectangular target.
//   R = elevation (0.5 = sea level)
//   G = moisture / biome selector
//   B = city density (where people live: low, wet coasts and river plains)
//   A = cloud density
// Noise is evaluated on the 3D unit sphere so the map is seamless in longitude
// and does not pinch at the poles.
shader_type canvas_item;
render_mode blend_disabled, unshaded;

#include "res://assets/art/environment/shaders/noise.gdshaderinc"

uniform float seed = 3.0;

void fragment() {
	float lon = (UV.x - 0.5) * 6.2831853;
	float lat = (0.5 - UV.y) * 3.1415927;
	vec3 p = vec3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon));
	vec3 sp = p + vec3(seed * 1.31, seed * 0.77, seed * 2.13);

	// ---- continents: warped fbm + ridged mountain ranges ----
	vec3 w = vec3(fbm3(sp * 1.3 + 4.0, 4), fbm3(sp * 1.3 + 9.0, 4), fbm3(sp * 1.3 + 13.0, 4));
	float cont = fbm3(sp * 1.7 + 1.4 * w, 7);
	float ridges = ridged3(sp * 3.1 + w, 5);
	float elev = cont + 0.08;                       // bias -> ~40 % land
	elev += smoothstep(0.0, 0.25, elev) * (ridges - 0.35) * 0.35;

	// ---- moisture ----
	float moist = 0.5 + 0.9 * fbm3(sp * 2.6 + 21.0 + w, 5);
	moist -= 0.25 * smoothstep(0.15, 0.45, elev);   // drier inland highs
	// Subtropical desert belts around +-25 deg latitude.
	float abslat = abs(lat);
	moist -= 0.22 * exp(-pow((abslat - 0.42) / 0.16, 2.0));

	// ---- cities: low coastal land, clustered into metro regions ----
	float land = smoothstep(0.0, 0.02, elev);
	float coastal = 1.0 - smoothstep(0.02, 0.22, elev);
	float metro = smoothstep(-0.04, 0.28, fbm3(sp * 5.0 + 40.0, 4));
	float spread = smoothstep(-0.16, 0.22, fbm3(sp * 11.0 + 7.0, 3));
	float polar = 1.0 - smoothstep(0.9, 1.15, abslat);
	float city = land * polar * (0.30 * coastal + 0.70 * metro * (0.4 + 0.6 * coastal)) * spread;
	// A developed world: some ocean platforms / arcologies too.
	float sea_city = (1.0 - land) * smoothstep(0.42, 0.55, fbm3(sp * 9.0 + 77.0, 3)) * smoothstep(-0.18, -0.02, elev) * 0.6;
	city = clamp(city + sea_city, 0.0, 1.0);

	// ---- clouds: latitude banded, zonal stretched, with storm swirls ----
	vec3 cp = vec3(p.x, p.y * 2.2, p.z) * 2.2 + vec3(seed * 0.5, 0.0, 1.0);
	vec3 cw = vec3(fbm3(cp * 1.5 + 3.0, 4), fbm3(cp * 1.5 + 8.0, 4), fbm3(cp * 1.5 + 12.0, 4));
	float c = fbm3(cp * 1.6 + 2.2 * cw, 6);
	float belts = 0.55 + 0.45 * cos(lat * 6.0);    // ITCZ + mid-latitude storm tracks
	float clouds = smoothstep(0.0, 0.42, c + 0.12 * belts - 0.05);
	clouds *= 0.55 + 0.45 * smoothstep(-0.1, 0.4, fbm3(cp * 4.5 + 5.0, 3) + 0.2);

	COLOR = vec4(clamp(elev * 0.5 + 0.5, 0.0, 1.0), clamp(moist, 0.0, 1.0), city, clamp(clouds, 0.0, 1.0));
}
