class_name VesperSky
extends RefCounted
## Builds the VESPER ROCK sky look: a remote mining outpost in an asteroid
## belt around a ringed gas giant. Compared with Meridian the sun is farther
## (smaller, whiter, lower-left), the nebula is warm dust instead of violet
## haze, and there are no stations or traffic: only moons and drifting rock.
##
## Layer-space layout, chosen for the view from the look's origin: the giant
## fills the upper-right, its rings sweep down across the frame, and the belt
## crosses from upper-left to lower-right through the play area.

const GIANT_PARALLAX := 0.12
const GIANT_ANCHOR := Vector2(790.0, -400.0)
const GIANT_RADIUS := 610.0
const SUN_SCREEN := Vector2(0.105, 0.845)
## The sun is a little in FRONT of the giant (positive z), so the face we see
## is mostly lit and the terminator sits towards the far upper-right limb.
const SUN_DEPTH := 0.38
## Direction (layer space) from the origin to the centre of the belt's orbit.
const BELT_CENTRE_DIR := Vector2(0.50, -0.866)
const BELT_ORBIT := 7600.0


## Bakes, giant and moons are built here. The belt meshes are the slow part
## (thousands of rocks in GDScript), so they are queued in `look.pending` for
## SpaceBackground to spread over a few frames when it builds ahead of time.
static func build(bg: SpaceBackground) -> SkyLook:
	var look := SkyLook.new(SpaceBackground.LOOK_VESPER)
	var light := _light_dir()
	var sun2 := Vector2(light.x, light.y).normalized()
	look.sun_screen = SUN_SCREEN
	var nebula := bg.make_bake("nebula_bake.gdshader", Vector2i(bg.nebula_bake_size, bg.nebula_bake_size), {
		"col_deep": Vector3(0.20, 0.07, 0.12),
		"col_main": Vector3(0.58, 0.16, 0.34),
		"col_alt": Vector3(0.62, 0.34, 0.10),
		"col_accent": Vector3(0.30, 0.12, 0.40),
		"col_filament": Vector3(0.62, 0.42, 0.30),
		"seed_offset": Vector2(31.7, 12.4),
		"band_dir": Vector2(1.0, 1.0),
		"band_power": 1.5,
		"dust_floor": 0.4,
		"dust_gain": 1.25,
	}, "VesperNebulaBake")
	var giant_tex := bg.make_bake("gas_giant_bake.gdshader", bg.planet_bake_size, {}, "GasGiantBake")
	look.sky_params = {
		"nebula_tex": nebula,
		"nebula_offset": Vector2(0.12, 0.78),
		"nebula_gain": 0.21,
		"base_color": Color(0.022, 0.014, 0.022),
		"sun_sky_tint": Color(0.060, 0.050, 0.045),
		"star_base": 0.62,
		"star_band": 3.1,
	}
	look.sky_offset = Vector2(41000.0, 27000.0)
	look.sun_gain = 0.72
	look.sun_params = {
		"size": 0.62,
		"sun_tint": Vector3(0.90, 0.95, 1.06),
		"ghost_gain": 0.55,
	}

	# Moons first (farthest), then the giant, then the belt in front of it.
	look.add_layer(bg.make_moon("IceMoon", 23.0, Vector3(light.x, light.y, 0.25), {
		"tint": Vector3(0.84, 0.93, 1.0), "albedo_hi": 0.92, "albedo_lo": 0.66, "gain": 0.8,
		"seed": Vector3(11.0, 4.0, 9.0), "crater_scale": 1.3,
		"night_color": Vector3(0.05, 0.04, 0.035), "rim_color": Vector3(0.35, 0.5, 0.6),
	}), 0.07, Vector2(-520.0, -330.0))
	var giant := GasGiant.new()
	giant.name = "GasGiant"
	giant.setup(GIANT_RADIUS, light, -14.0, 21.0, giant_tex)
	look.add_layer(giant, GIANT_PARALLAX, GIANT_ANCHOR)
	look.disk = giant
	look.disk_radius = GIANT_RADIUS
	look.add_layer(bg.make_moon("DarkMoon", 46.0, Vector3(light.x, light.y, 0.1), {
		"tint": Vector3(0.62, 0.52, 0.46), "albedo_hi": 0.50, "albedo_lo": 0.20, "gain": 0.8,
		"seed": Vector3(2.0, 7.0, 13.0), "crater_scale": 3.4,
		"night_color": Vector3(0.045, 0.032, 0.022), "rim_color": Vector3(0.3, 0.2, 0.12),
	}), 0.16, Vector2(250.0, 395.0))

	# Three belt depths. Haze by depth: the farther the layer, the smaller,
	# denser and more see-through its rocks, and the slower it drifts. Even the
	# nearest layer stays soft-edged, translucent and far below hull
	# brightness, so it never reads as rock you could hit (the same rule as
	# Meridian's distant stations). The farthest also carries the dust band.
	var far := _new_belt(look, "BeltFar", sun2, 0.20, 0.00016)
	var far_lit := Color(0.40, 0.31, 0.26)
	var far_shadow := Color(0.075, 0.058, 0.062)
	look.pending.append(func() -> void:
		far.add_dust(nebula, 1300.0, Color(0.80, 0.52, 0.34), 0.2)
		far.add_rocks(4107, 2600, 400.0, Vector2(2.0, 9.0), 1.2, far_lit, far_shadow, 0.62))
	look.pending.append(func() -> void:
		far.add_rocks(4108, 2600, 400.0, Vector2(2.0, 9.0), 1.2, far_lit, far_shadow, 0.62))
	var mid := _new_belt(look, "BeltMid", sun2, 0.31, 0.00024)
	var near := _new_belt(look, "BeltNear", sun2, 0.44, 0.00034)
	look.pending.append(func() -> void:
		mid.add_rocks(4211, 900, 600.0, Vector2(4.0, 20.0), 1.8,
			Color(0.43, 0.33, 0.27), Color(0.062, 0.048, 0.052), 0.68)
		near.add_rocks(4391, 260, 780.0, Vector2(8.0, 38.0), 2.6,
			Color(0.46, 0.35, 0.28), Color(0.050, 0.040, 0.045), 0.76))
	return look


## Direction towards the sun in the giant's view space (y down, z to viewer).
static func _light_dir() -> Vector3:
	var ref := Vector2(1920.0, 1080.0)
	var d := ((SUN_SCREEN - Vector2(0.5, 0.5)) * ref - GIANT_ANCHOR).normalized()
	return Vector3(d.x, d.y, SUN_DEPTH).normalized()


## An empty belt layer, in place in the look; its rocks are added later.
static func _new_belt(look: SkyLook, node_name: String, sun2: Vector2, parallax: float, spin: float) -> AsteroidBelt:
	var belt := AsteroidBelt.new()
	belt.name = node_name
	belt.setup(BELT_ORBIT, spin, sun2)
	# The orbit centre is far off towards the giant; the band passes through
	# the origin, nudged down-left so its dense core clears the giant.
	look.add_layer(belt, parallax, BELT_CENTRE_DIR * (BELT_ORBIT - 140.0))
	return belt
