@tool
extends RefCounted
## Paints civilian ship designs into a StationModule (docked freighters, the
## half-built cruiser in the drydock, AI traffic). Ships face local +X.
## All sizes in metres; `xf` places the ship inside the module (px).

const A := preload("res://scripts/level/level_art.gd")
const SM := preload("res://scripts/level/station_module.gd")
const PX := 10.0


static func _p(xf: Transform2D, pts: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v in pts:
		out.append(xf * ((v as Vector2) * PX))
	return out


static func _box(xf: Transform2D, x0: float, y0: float, x1: float, y1: float) -> PackedVector2Array:
	return _p(xf, [Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)])


## Long-haul container freighter.
static func freighter(m: SM, xf: Transform2D, L: float, B: float, livery: Color, ship_name: String, engines_on := false, seed := 0) -> void:
	var h := B * 0.5
	var outline := _p(xf, [
		Vector2(-0.5 * L, -0.36 * B), Vector2(-0.43 * L, -h), Vector2(0.34 * L, -h),
		Vector2(0.5 * L, -0.17 * B), Vector2(0.5 * L, 0.17 * B), Vector2(0.34 * L, h),
		Vector2(-0.43 * L, h), Vector2(-0.5 * L, 0.36 * B)])
	# Engine nozzles (drawn first so the hull overlaps them).
	var D := SM.Band.STRUCT_DETAIL
	for i in 3:
		var y := (float(i) - 1.0) * B * 0.26
		var nz := _box(xf, -0.5 * L - 3.2, y - B * 0.09, -0.5 * L + 1.0, y + B * 0.09)
		m.fill(SM.Band.STRUCT, nz, A.NAVY)
		m.outline(SM.Band.STRUCT, nz, Color(0.6, 0.7, 0.85, 0.8), 1.5)
		if engines_on:
			m.glow(xf * (Vector2(-0.5 * L - 4.0, y) * PX), Color(0.5, 0.85, 1.0, 0.9), B * 3.0)
			m.glow(xf * (Vector2(-0.5 * L - 9.0, y) * PX), Color(0.3, 0.6, 1.0, 0.5), B * 5.0)
	m.hull(outline, &"pearl")
	# Livery side stripes.
	m.fill(D, _box(xf, -0.42 * L, -h + 1.0, 0.3 * L, -h + 2.2), livery)
	m.fill(D, _box(xf, -0.42 * L, h - 2.2, 0.3 * L, h - 1.0), livery)
	# Container racks.
	var x := -0.36 * L
	var lanes := maxi(2, int((B - 6.0) / 2.6))
	var idx := seed * 97
	while x < 0.2 * L:
		var bay_len := 6.1
		for j in lanes:
			var y0 := -h + 3.0 + j * 2.6
			idx += 1
			var hsh := A.hash01(idx, seed + 11)
			if hsh < 0.1:
				continue
			var lv: Dictionary = A.LIVERIES[int(hsh * 997.0) % A.LIVERIES.size()]
			var col: Color = lv.color
			var bx := _box(xf, x, y0, x + bay_len - 0.4, y0 + 2.3)
			m.fill(D, bx, col)
			m.outline(D, bx, col.darkened(0.45), 1.2, true, false)
		x += bay_len
	# Spine walkway along the centre line between rack groups.
	m.fill(D, _box(xf, -0.4 * L, -0.5, 0.22 * L, 0.5), Color("BFC9D4"))
	# Bridge superstructure.
	var bridge := _p(xf, [Vector2(0.24 * L, -h * 0.75), Vector2(0.33 * L, -h * 0.75), Vector2(0.37 * L, -h * 0.35),
		Vector2(0.37 * L, h * 0.35), Vector2(0.33 * L, h * 0.75), Vector2(0.24 * L, h * 0.75)])
	m.fill(D, bridge, A.PEARL)
	m.outline(D, bridge, A.OUTLINE, 2.5)
	m.rim(D, bridge, Color.WHITE, A.PANEL)
	m.windows(D, _p(xf, [Vector2(0.355 * L, -h * 0.45), Vector2(0.355 * L, h * 0.45)]), 1.0, 0.8, seed)
	m.fill(D, _box(xf, 0.25 * L, -h * 0.5, 0.31 * L, h * 0.5), A.NAVY)
	# Name on the bow deck.
	# keep the name readable on screen for docked (static) ships
	var tr := xf.get_rotation() + PI * 0.5
	if absf(wrapf(tr + m.rotation, -PI, PI)) > PI * 0.5 + 0.01:
		tr += PI
	m.text(D, xf * (Vector2(0.43 * L, 0) * PX), ship_name, int(clampf(B * 3.4, 18, 60)), A.NAVY, tr)
	# Nav lights: red port (-Y), green starboard (+Y), white strobe at stern.
	m.beacon(xf * (Vector2(0.1 * L, -h + 0.8) * PX), A.NAV_RED, 70.0, A.hash01(seed, 3))
	m.beacon(xf * (Vector2(0.1 * L, h - 0.8) * PX), A.NAV_GREEN, 70.0, A.hash01(seed, 3))
	m.beacon(xf * (Vector2(-0.48 * L, 0) * PX), Color.WHITE, 90.0, A.hash01(seed, 5), true)
	m.lamp(xf * (Vector2(0.5 * L - 1.2, 0) * PX), A.WARM, 60.0)


## Small passenger shuttle (~14 m).
static func shuttle(m: SM, xf: Transform2D, livery: Color, seed := 0, engines_on := true) -> void:
	var o := _p(xf, [Vector2(7.0, 0.0), Vector2(5.2, -2.2), Vector2(-3.8, -3.6), Vector2(-6.6, -2.9),
		Vector2(-6.6, 2.9), Vector2(-3.8, 3.6), Vector2(5.2, 2.2)])
	var D := SM.Band.STRUCT_DETAIL
	if engines_on:
		for s: float in [-1.4, 1.4]:
			m.glow(xf * (Vector2(-7.4, s) * PX), Color(0.45, 0.85, 1.0, 0.95), 46.0)
			m.glow(xf * (Vector2(-10.5, s) * PX), Color(0.3, 0.6, 1.0, 0.45), 80.0)
	m.hull(o, &"pearl", [], {"bevel": 0.5})
	m.fill(D, _p(xf, [Vector2(5.6, -1.2), Vector2(6.4, 0.0), Vector2(5.6, 1.2), Vector2(3.2, 1.5), Vector2(3.2, -1.5)]), A.NAVY)
	m.fill(D, _p(xf, [Vector2(5.4, -0.7), Vector2(5.9, 0.0), Vector2(5.4, 0.3), Vector2(4.0, 0.2)]), Color(0.6, 0.85, 1.0, 0.55))
	m.fill(D, _box(xf, -5.5, -3.1, 2.5, -2.4), livery)
	m.fill(D, _box(xf, -5.5, 2.4, 2.5, 3.1), livery)
	m.fill(D, _box(xf, -6.8, -2.0, -5.8, 2.0), A.NAVY)
	m.seam(D, xf * (Vector2(-1.0, -2.8) * PX), xf * (Vector2(-1.0, 2.8) * PX))
	m.lamp(xf * (Vector2(-3.7, -3.4) * PX), A.NAV_RED, 34.0)
	m.lamp(xf * (Vector2(-3.7, 3.4) * PX), A.NAV_GREEN, 34.0)
	m.beacon(xf * (Vector2(-1.5, 0) * PX), Color.WHITE, 60.0, A.hash01(seed, 9), true)


## Work tug (~11 m) with forward grapple arms, hazard livery.
static func tug(m: SM, xf: Transform2D, seed := 0, engines_on := true) -> void:
	var D := SM.Band.STRUCT_DETAIL
	var body := _p(xf, [Vector2(3.0, -3.4), Vector2(3.0, 3.4), Vector2(-4.2, 3.8), Vector2(-5.6, 2.6), Vector2(-5.6, -2.6), Vector2(-4.2, -3.8)])
	var arm_l := _box(xf, 2.0, -3.9, 6.2, -2.6)
	var arm_r := _box(xf, 2.0, 2.6, 6.2, 3.9)
	if engines_on:
		for s: float in [-1.6, 1.6]:
			m.glow(xf * (Vector2(-6.2, s) * PX), Color(1.0, 0.7, 0.35, 0.9), 40.0)
	m.hull(arm_l, &"steel", [], {"bevel": 0.3})
	m.hull(arm_r, &"steel", [], {"bevel": 0.3})
	m.hull(body, &"amber", [], {"bevel": 0.5})
	m.hazard(D, _box(xf, -4.6, -1.8, -2.6, 1.8), 0.6, PI * 0.25)
	m.fill(D, _box(xf, 0.2, -1.8, 2.6, 1.8), A.NAVY)
	m.fill(D, _box(xf, 1.9, -1.2, 2.5, 1.2), Color(0.6, 0.85, 1.0, 0.6))
	m.lamp(xf * (Vector2(6.0, -3.25) * PX), A.AMBER, 30.0)
	m.lamp(xf * (Vector2(6.0, 3.25) * PX), A.AMBER, 30.0)
	m.lamp(xf * (Vector2(-4.0, -3.6) * PX), A.NAV_RED, 30.0)
	m.lamp(xf * (Vector2(-4.0, 3.6) * PX), A.NAV_GREEN, 30.0)
	m.beacon(xf * (Vector2(-1.0, 0) * PX), A.AMBER, 70.0, A.hash01(seed, 4))
