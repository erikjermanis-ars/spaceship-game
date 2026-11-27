@tool
extends RefCounted
## Paints the outpost's buildings onto Vesper Rock: crew habitats, two domes,
## the ops block, the ore plant (pit head, conveyors, crusher, screen house),
## tanks, comms and solar. The rock under them is one solid collider, so all
## of this is paint in the rock module's bands, each block with a short
## cast shadow on the ground. Numbers in metres, the rock module's frame.

const A := preload("res://scripts/level/level_art.gd")
const SM := preload("res://scripts/level/station_module.gd")
const R := preload("res://scripts/level/rock_art.gd")
const PX := 10.0
const S := SM.Band.STRUCT
const D := SM.Band.STRUCT_DETAIL
const GROUND_SHADOW := Color(0.0, 0.0, 0.02, 0.4)

## Where things stand (m): boulders and craters keep off these.
const FOOTPRINTS := [
	Rect2(-52, -66, 74, 22), Rect2(-40, -34, 58, 16), Rect2(-16, -46, 10, 14), Rect2(16, -30, 34, 10),
	Rect2(48, -28, 50, 40), Rect2(-113, -77, 34, 34), Rect2(-135, -45, 22, 22), Rect2(-82, -62, 32, 12),
	Rect2(-126, 8, 152, 36), Rect2(18, 12, 20, 20), Rect2(8, -102, 56, 30), Rect2(-73, -103, 22, 22),
	Rect2(-54, -114, 32, 32), Rect2(-184, -50, 28, 36), Rect2(-160, 40, 212, 12), Rect2(44, -80, 30, 54), Rect2(-9, -140, 18, 76),
]
const TANKS := [[18.0, -90.0, 8.0, "LOX"], [38.0, -88.0, 8.0, "LH2"], [55.0, -79.0, 6.0, "N2"]]


static func build(m: SM) -> void:
	_ore_plant(m)
	_habitats(m)
	_domes(m)
	_ops(m)
	_tanks(m)
	_comms(m)
	_solar(m)
	_lights(m)


static func _v(x: float, y: float) -> Vector2:
	return Vector2(x, y) * PX


## A building: ground shadow (longer for taller things), then a hull that
## doesn't collide (the rock under it already does).
static func _block(m: SM, poly: PackedVector2Array, style: StringName, bevel := 0.8, height := 1.0) -> void:
	var cast := PackedVector2Array()
	for p in poly:
		cast.append(p + Vector2(7.0, 10.0) * height)
	m.fill(S, cast, GROUND_SHADOW)
	m.hull(poly, style, [], {"collide": false, "shadow": false, "bevel": bevel})


static func _habitats(m: SM) -> void:
	# connecting tubes first, so the blocks overlap their ends
	_block(m, A.rect_m(-15, -46, -9, -32), &"grey", 0.5, 0.5)
	_block(m, A.rect_m(16, -29, 50, -23), &"grey", 0.5, 0.5)
	_block(m, A.rect_m(-82, -58, -50, -52), &"grey", 0.5, 0.5)
	m.windows(D, PackedVector2Array([_v(20, -26), _v(47, -26)]), 1.2, 1.0, 31, A.WARM, 0.08)
	m.windows(D, PackedVector2Array([_v(-80, -55), _v(-54, -55)]), 1.2, 1.0, 32, A.WARM, 0.08)
	# HAB A: the long block with the outpost's name on its roof
	_block(m, A.rounded_rect(Rect2(_v(-52, -66), _v(74, 22)), 3.0 * PX), &"pearl", 0.9, 1.3)
	m.windows(D, PackedVector2Array([_v(-48, -63.6), _v(18, -63.6)]), 1.6, 1.2, 11)
	m.windows(D, PackedVector2Array([_v(-48, -46.4), _v(18, -46.4)]), 1.6, 1.2, 12)
	m.fill(D, A.rect_m(-48, -61.6, 18, -60.2), A.TEAL)
	m.text(D, _v(-15, -54.0), "VESPER ROCK", 84, A.NAVY)
	var pairs := PackedVector2Array()
	for x: float in [-38.0, -29.0, 0.0, 9.0]:
		pairs.append_array([_v(x, -59.6), _v(x, -48.2)])
	m.seams(D, pairs)
	for x: float in [-46.0, 15.0]:
		m.fill(D, A.rect_m(x - 2.2, -57.5, x + 2.2, -50.5), Color("AEB9C6"))
		m.outline(D, A.rect_m(x - 2.2, -57.5, x + 2.2, -50.5), Color(0.3, 0.36, 0.45, 0.8), 1.2)
		m.fill(D, A.rect_m(x - 1.4, -56.5, x + 1.4, -54.2), Color("2B3440"))
	# HAB B: crew quarters
	_block(m, A.rounded_rect(Rect2(_v(-40, -34), _v(58, 16)), 2.5 * PX), &"pearl", 0.8, 1.0)
	m.windows(D, PackedVector2Array([_v(-37, -20.2), _v(15, -20.2)]), 1.5, 1.1, 13)
	m.windows(D, PackedVector2Array([_v(-37, -31.8), _v(-18, -31.8)]), 1.5, 1.1, 14)
	m.fill(D, A.rect_m(-37, -29.4, 15, -28.4), A.NAVY)
	m.text(D, _v(-11, -25.0), "HAB B  ·  CREW", 28, A.NAVY)


static func _domes(m: SM) -> void:
	var a := _v(-96, -60)
	var b := _v(-124, -34)
	_block(m, A.obox((a + b) * 0.5, b - a, a.distance_to(b), 5.0 * PX), &"grey", 0.5, 0.5)
	# hydroponics dome: glass over planting beds
	var r := 17.0 * PX
	m.fill(S, A.circle_poly(a + Vector2(9, 13), r, 32), GROUND_SHADOW)
	m.hull(A.circle_poly(a, r, 40), &"glass", [], {"collide": false, "shadow": false, "bevel": 1.0})
	m.fill(D, A.circle_poly(a, r - 16.0, 36), Color("1F5240"))
	for i in 5:
		var y := -11.0 + 5.5 * i
		var half := sqrt(maxf(0.0, 14.0 * 14.0 - y * y))
		m.fill(D, A.rect_poly(Rect2(a + Vector2(-half, y - 1.6) * PX, Vector2(half * 2.0, 3.2) * PX)), [Color("3E9A63"), Color("5BB07A"), Color("2F7A55"), Color("8CC084"), Color("3E9A63")][i])
	var mull := PackedVector2Array()
	for i in 12:
		var d := Vector2.from_angle(TAU * i / 12.0)
		mull.append_array([a + d * 12.0, a + d * (r - 6.0)])
	m.lines(D, mull, Color(0.85, 0.97, 1.0, 0.3), 1.4)
	m.outline(D, A.circle_poly(a, r * 0.6, 28), Color(0.85, 0.97, 1.0, 0.25), 1.4)
	m.fill(D, A.circle_poly(a - Vector2(r, r) * 0.33, r * 0.3, 20), Color(1, 1, 1, 0.14))
	m.glow(a, Color(0.5, 1.0, 0.6, 0.12), r * 1.5)
	m.text(D, a + Vector2(0, r + 26.0), "HYDROPONICS", 20, Color(0.85, 0.92, 1.0, 0.8))
	# survey dome: a pearl shell with an open observing slit
	var r2 := 11.0 * PX
	m.fill(S, A.circle_poly(b + Vector2(7, 10), r2, 28), GROUND_SHADOW)
	m.hull(A.circle_poly(b, r2, 32), &"pearl", [], {"collide": false, "shadow": false, "bevel": 1.0})
	for k: float in [0.72, 0.42]:
		m.outline(D, A.circle_poly(b, r2 * k, 28), Color(0.45, 0.52, 0.6, 0.55), 1.4)
	m.fill(D, A.obox(b + Vector2(18, -18), Vector2(1, -1), 60.0, 16.0), Color("18202D"))
	m.fill(D, A.circle_poly(b + Vector2(10, -10), 7.0, 12), A.CYAN)
	m.glow(b + Vector2(10, -10), Color(0.5, 0.9, 1.0, 0.5), 40.0)
	m.fill(D, A.circle_poly(b - Vector2(r2, r2) * 0.3, r2 * 0.3, 16), Color(1, 1, 1, 0.2))
	m.text(D, b + Vector2(0, r2 + 22.0), "SURVEY", 20, Color(0.85, 0.92, 1.0, 0.8))


## Ops block with the control cupola, on the east shoulder.
static func _ops(m: SM) -> void:
	var poly := PackedVector2Array([_v(52, -28), _v(94, -28), _v(98, -24), _v(98, 8), _v(94, 12), _v(52, 12), _v(48, 8), _v(48, -24)])
	_block(m, poly, &"pearl", 1.0, 1.4)
	m.windows(D, PackedVector2Array([_v(50.6, -22), _v(50.6, 6)]), 1.5, 1.1, 21)
	m.windows(D, PackedVector2Array([_v(54, 9.6), _v(92, 9.6)]), 1.5, 1.1, 22)
	m.fill(D, A.rect_m(54, -25.6, 92, -24.4), A.TEAL)
	m.fill(D, A.rect_m(83, -22, 95, 5), A.NAVY)
	m.text(D, _v(89, -8.5), "VESPER CONTROL", 24, A.PEARL, -PI * 0.5)
	var c := _v(68, -8)
	m.fill(D, A.circle_poly(c, 10.5 * PX, 8, PI / 8.0), A.NAVY)
	m.fill(D, A.circle_poly(c, 9.2 * PX, 8, PI / 8.0), Color("E3E9EF"))
	m.windows(D, A.circle_poly(c, 7.6 * PX, 32), 1.5, 1.1, 23)
	m.fill(D, A.circle_poly(c, 5.6 * PX, 28), Color("1F4B60"))
	m.fill(D, A.circle_poly(c + Vector2(-8, -10), 4.2 * PX, 24), Color("2A6680"))
	m.fill(D, A.circle_poly(c + Vector2(-18, -22), 1.6 * PX, 14), Color(1, 1, 1, 0.18))
	m.outline(D, A.circle_poly(c, 5.6 * PX, 28), Color(0.9, 0.97, 1.0, 0.9), 2.2)
	m.glow(c, Color(0.5, 0.9, 1.0, 0.3), 150.0)
	m.beacon(_v(52, -26), A.NAV_RED, 80.0, 0.3)
	m.beacon(_v(52, 10), A.NAV_GREEN, 80.0, 0.3)


static func _ore_plant(m: SM) -> void:
	# pit head: haul road and the loader at the top bench
	_belt(m, _v(-124, 20), _v(-80, 24), 51)
	_belt(m, _v(-50, 26), _v(-14, 30), 52)
	# crusher
	_block(m, A.rect_m(-80, 10, -50, 38), &"steel", 0.7, 1.6)
	m.hazard(D, A.rect_m(-80, 10, -77, 38), 1.0)
	m.fill(D, A.rect_m(-74, 15, -60, 33), Color("1B2028"))
	m.outline(D, A.rect_m(-74, 15, -60, 33), Color(0.85, 0.89, 0.93, 0.7), 1.6)
	for i in 5:
		m.fill(D, A.rect_m(-73.2, 16.4 + 3.3 * i, -60.8, 18.4 + 3.3 * i), Color("3C434E"))
	_rubble(m, _v(-67, 24), 46.0, 9, 61)
	m.fill(D, A.rect_m(-58, 13, -52, 35), A.NAVY)
	m.text(D, _v(-55, 24), "CRUSHER 01", 24, A.PEARL, -PI * 0.5)
	m.beacon(_v(-78.5, 11.5), A.AMBER, 80.0, 0.0)
	m.beacon(_v(-51.5, 36.5), A.AMBER, 80.0, 0.5)
	# screen house: sorts the crushed ore onto the hopper belt
	_block(m, A.rect_m(-14, 16, 10, 42), &"grey", 0.7, 1.3)
	for i in 3:
		m.fill(D, A.rect_m(-10.5 + 7.0 * i, 20, -5.5 + 7.0 * i, 31), Color("2B3440"))
		m.fill(D, A.rect_m(-10.0 + 7.0 * i, 20.5, -6.0 + 7.0 * i, 24.0), Color("45DCC6").darkened(0.35))
	m.fill(D, A.rect_m(-12, 35, 8, 39.5), A.TEAL)
	m.text(D, _v(-2, 37.3), "SCREEN HOUSE", 20, A.PEARL)
	m.lamp(_v(-12, 18), A.AMBER, 30.0)
	# stockpile beside it, and the elevated belt down to the apron hoppers
	_rubble(m, _v(28, 22), 62.0, 16, 62)
	var a := _v(8, 34)
	var b := _v(30, 61)
	m.overhead(A.obox((a + b) * 0.5, b - a, a.distance_to(b), 4.0 * PX), Color(0.55, 0.6, 0.68, 0.8))
	m.strip(SM.Band.OVER, PackedVector2Array([a, b]), 16.0, Color(0.12, 0.14, 0.18, 0.75))
	m.lamp(b, A.AMBER, 36.0, 2)


## A conveyor on the ground: dark belt, grey side frames, ore on it.
static func _belt(m: SM, a: Vector2, b: Vector2, seed: int) -> void:
	var dir := (b - a).normalized()
	var n := dir.orthogonal()
	var w := 3.6 * PX
	var cast := A.obox((a + b) * 0.5 + Vector2(5, 7), dir, a.distance_to(b), w)
	m.fill(S, cast, GROUND_SHADOW)
	m.fill(S, A.obox((a + b) * 0.5, dir, a.distance_to(b), w), Color("8E9AA8"))
	m.fill(S, A.obox((a + b) * 0.5, dir, a.distance_to(b), w - 9.0), Color("22262E"))
	m.line(S, a - n * w * 0.5, b - n * w * 0.5, Color("DCE3EA"), 1.4)
	var t := 6.0
	var i := 0
	while t < a.distance_to(b) - 6.0:
		var p := a + dir * t + n * (A.hash01(i, seed) - 0.5) * 12.0
		var s := 3.0 + 3.0 * A.hash01(i, seed + 1)
		var col := Color("5D5F6A").lerp(Color("45DCC6"), 0.5 if A.hash01(i, seed + 2) > 0.7 else 0.0)
		m.fill(S, PackedVector2Array([p + Vector2(-s, 0), p + Vector2(0, -s), p + Vector2(s, 0), p + Vector2(0, s)]), col)
		t += 9.0 + 9.0 * A.hash01(i, seed + 3)
		i += 1
	m.fill(S, A.obox(a, dir, 8.0, w + 6.0), A.AMBER)
	m.fill(S, A.obox(b, dir, 8.0, w + 6.0), A.AMBER)


## A heap of broken ore: a low faceted mound, some lumps showing teal.
static func _rubble(m: SM, c: Vector2, r: float, lumps: int, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var mesh := R.Facets.new()
	for i in lumps:
		var p := c + Vector2.from_angle(rng.randf() * TAU) * r * sqrt(rng.randf()) * 0.8
		var lump := R.convex_blob(rng, r * rng.randf_range(0.22, 0.42), 6)
		for k in lump.size():
			lump[k] += p
		var base := Color("4F525C").lerp(Color("3BB9A8"), 0.55 if rng.randf() > 0.72 else 0.0)
		var tone := func(_c: Vector2) -> Color: return base.darkened(rng.randf_range(0.0, 0.12))
		R.facets(mesh, lump, PackedVector2Array([p]), PackedFloat32Array([r * 0.25]), tone)
	m._batch(D).add_cols(mesh.pts, mesh.idx, mesh.baked(m.global_rotation))


static func _tanks(m: SM) -> void:
	for i in TANKS.size() - 1:
		var a := _v(TANKS[i][0], TANKS[i][1])
		var b := _v(TANKS[i + 1][0], TANKS[i + 1][1])
		m.overhead(A.obox((a + b) * 0.5, b - a, a.distance_to(b), 1.8 * PX), Color(0.92, 0.82, 0.55, 0.55))
	m.overhead(A.obox(_v(60, -54), Vector2(0.2, 1.0), 50.0 * PX, 1.8 * PX), Color(0.92, 0.82, 0.55, 0.55))
	for t: Array in TANKS:
		var c := _v(t[0], t[1])
		var r: float = t[2] * PX
		m.fill(S, A.circle_poly(c + Vector2(8, 11), r, 24), GROUND_SHADOW)
		m.hull(A.circle_poly(c, r, 28), &"teal" if t[3] == "LOX" else &"pearl", [], {"collide": false, "shadow": false, "bevel": 1.0})
		m.outline(D, A.circle_poly(c, r * 0.62, 22), Color(0.4, 0.5, 0.6, 0.5), 1.4)
		m.fill(D, A.circle_poly(c - Vector2(r, r) * 0.28, r * 0.3, 16), Color(1, 1, 1, 0.24))
		m.fill(D, A.arc_band(c, r * 0.2, r * 0.32, 0, TAU, 20), A.AMBER)
		m.text(D, c + Vector2(0, r * 0.62), t[3], 16, A.NAVY if t[3] != "LOX" else A.PEARL)
	m.beacon(_v(18, -99), A.NAV_RED, 80.0, 0.6)


## Comms: a relay dish and the antenna mast with its guy wires.
static func _comms(m: SM) -> void:
	var c := _v(-62, -92)
	var r := 9.5 * PX
	m.fill(S, A.circle_poly(c + Vector2(9, 12), r, 24), GROUND_SHADOW)
	m.hull(A.circle_poly(c, r, 32), &"pearl", [], {"collide": false, "shadow": false, "bevel": 1.0})
	for i in 3:
		m.fill(D, A.circle_poly(c, r * (0.78 - 0.22 * i), 28), Color("DDE3EA").lerp(Color("AEB9C6"), float(i) / 3.0))
	var ribs := PackedVector2Array()
	for i in 12:
		var d := Vector2.from_angle(TAU * i / 12.0)
		ribs.append_array([c + d * r * 0.14, c + d * (r - 9.0)])
	m.lines(D, ribs, Color(0.5, 0.58, 0.67, 0.55), 1.3)
	for i in 3:
		var d := Vector2.from_angle(TAU * i / 3.0 + 0.5)
		m.overhead(A.obox(c + d * r * 0.42, d, r * 0.84, 10.0), Color(0.9, 0.93, 0.97, 0.7))
	m.overhead(A.circle_poly(c, 16.0, 12), Color(0.95, 0.97, 1.0, 0.85))
	m.lamp(c, Color(1.0, 0.4, 0.3), 46.0, 2)
	# mast
	var mast := _v(-38, -98)
	var guys := PackedVector2Array()
	for i in 3:
		var anchor := mast + Vector2.from_angle(TAU * i / 3.0 - 0.4) * 15.0 * PX
		guys.append_array([mast, anchor])
		m.fill(D, A.circle_poly(anchor, 9.0, 8), Color("5C6878"))
		m.beacon(anchor, A.NAV_RED, 70.0, 0.33 * i)
	m.lines(D, guys, Color(0.85, 0.9, 0.95, 0.45), 1.2)
	m.fill(S, A.circle_poly(mast + Vector2(14, 20), 30.0, 12), GROUND_SHADOW)
	m.hull(A.circle_poly(mast, 3.0 * PX, 8, PI / 8.0), &"steel", [], {"collide": false, "shadow": false, "bevel": 0.5})
	for ang: float in [0.3, 0.3 + PI * 0.5]:
		m.overhead(A.obox(mast, Vector2.from_angle(ang), 22.0 * PX, 1.2 * PX), Color(0.9, 0.93, 0.97, 0.75))
	m.overhead(A.circle_poly(mast, 2.0 * PX, 12), Color(0.95, 0.97, 1.0, 0.9))
	m.beacon(mast, Color.WHITE, 140.0, 0.1, true, 2)


static func _solar(m: SM) -> void:
	for y: float in [-48.0, -30.0]:
		var rack := A.rect_m(-182, y, -158, y + 14)
		_block(m, rack, &"solar", 0.5, 0.6)
		var grid := PackedVector2Array()
		for k in range(1, 6):
			grid.append_array([_v(-182 + 4.0 * k, y + 0.8), _v(-182 + 4.0 * k, y + 13.2)])
		grid.append_array([_v(-181.2, y + 7), _v(-158.8, y + 7)])
		m.lines(D, grid, Color(0.55, 0.68, 0.9, 0.5), 1.2)
		m.fill(D, PackedVector2Array([_v(-180, y + 1.5), _v(-172, y + 1.5), _v(-176, y + 6)]), Color(1, 1, 1, 0.07))


## Floodlight masts along the lip of the terrace, lamps around the pit.
static func _lights(m: SM) -> void:
	for x: float in [-150.0, -100.0, -50.0, 0.0, 42.0]:
		var p := _v(x, 46.5)
		m.fill(S, A.circle_poly(p + Vector2(5, 7), 13.0, 10), GROUND_SHADOW)
		m.fill(D, A.circle_poly(p, 13.0, 10), Color("5C6878"))
		m.outline(D, A.circle_poly(p, 13.0, 10), Color(0.9, 0.93, 0.97, 0.8), 1.4)
		m.lamp(p, A.WARM, 60.0)
	for p: Vector2 in [_v(-170, -6), _v(-112, -2), _v(-150, 38)]:
		m.fill(D, A.circle_poly(p, 9.0, 8), Color("5C6878"))
		m.lamp(p, A.AMBER, 44.0)
