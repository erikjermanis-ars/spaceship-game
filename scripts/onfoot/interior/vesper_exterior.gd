@tool
extends Node2D
## What you see around Vesper Rock's interior: the rock itself (HAB A and
## HAB B stand on it, the adit down to the apron is cut through it), the
## docking spar's roof either side of the arrivals rooms, the habitats' roofs
## where the cut-away doesn't reach, and the landing apron south of the
## airlock. The world is suspended while you're indoors, so the interior
## paints its own surroundings, the way PierExterior does for Pier 7.
##
## The interior sits at Vesper's real origin (world_origin = (90000, 0)), so
## every number here is the level's own: the rock outline comes from the
## rock module, the rest from the constants in outpost_spar.gd, rock_works.gd
## and outpost_apron.gd (metres there, px here). Unshaded: sunlit outside.
## The ore plant, tanks and apron fittings are painted too, so the adit runs
## past the same crusher and screen house you see when you step outside.

const Rock := preload("res://scripts/level/modules/rock_base.gd")
## Outpost/Base (the rock's frame) in Vesper's frame, px.
const BASE := Vector2(0, 2300)
const SPAR := Rect2(-1100, 710, 2200, 240)
const HAB_A := Rect2(-520, 1640, 740, 220)
const HAB_B := Rect2(-400, 1960, 580, 160)
const APRON := Rect2(-1600, 2820, 2100, 900)
const FACET := 150.0
const PEARL := Color("E3E9EF")
const NAVY := Color("1D3557")
const TEAL := Color("2A9D8F")
const STEEL := Color("98A4B2")
const GREY := Color("C3CBD5")
const EDGE := Color("5C6878")
const CAST := Color(0.0, 0.0, 0.02, 0.4)

## Rooms dug into the rock (local px): each gets a dark surround, so the
## tunnel reads as a cut through solid rock and not a corridor on the ground.
@export var cut_rects: Array[Rect2] = []:
	set(v): cut_rects = v; queue_redraw()
## Where the apron airlock's outer hatch is (local px): the walkway stub.
@export var hatch := Vector2(-175, 2815):
	set(v): hatch = v; queue_redraw()

var pen: OnFootPainter


func _ready() -> void:
	z_as_relative = false
	z_index = -8
	if not Engine.is_editor_hint():
		material = OnFootArt.unshaded()


func _draw() -> void:
	pen = OnFootPainter.new(self, 0.3)
	_apron()
	_rock()
	# the cut stops at the rock face: the apron is open deck. It goes under
	# the works, which stand on the surface over the adit.
	var in_rock := Rect2(-4000, -4000, 8000, 4000 + APRON.position.y)
	for r in cut_rects:
		pen.rect_flat(r.grow(26.0).intersection(in_rock), Color(0.02, 0.02, 0.04, 0.5))
	_works()
	_spar()
	_roof(HAB_A, "VESPER ROCK", Vector2(-368, 1772), 22.0, 11)
	_roof(HAB_B, "HAB B", Vector2(104, 2052), 18.0, 13)
	pen.flush()


## The apron deck in the terrace: dark plates, a grid, and the painted lane
## from the hatch (the same stub the ExteriorDoor paints outside).
func _apron() -> void:
	pen.rect_flat(APRON, Color("1B2431"))
	var x := APRON.position.x
	while x < APRON.end.x:
		pen.line(Vector2(x, APRON.position.y), Vector2(x, APRON.end.y), Color("2C3A4E"), 0.6)
		x += 60.0
	var y := APRON.position.y
	while y < APRON.end.y:
		pen.line(Vector2(APRON.position.x, y), Vector2(APRON.end.x, y), Color("2C3A4E"), 0.6)
		y += 60.0
	pen.hazard(Rect2(hatch + Vector2(-11, 8), Vector2(22, 4)), 2.0)
	for s: float in [-8.5, 8.5]:
		var yy := hatch.y + 14.0
		while yy < hatch.y + 150.0:
			pen.line(hatch * Vector2(1, 0) + Vector2(s, yy), hatch * Vector2(1, 0) + Vector2(s, yy + 5.0), Color(0.92, 0.95, 1.0, 0.45), 0.7)
			yy += 9.0
	# floodlight pools from the masts on the terrace lip
	for fx: float in [-1500.0, -1000.0, -500.0, 0.0, 420.0]:
		for k in 5:
			pen.circle(Vector2(fx, APRON.position.y + 40.0), 60.0 + 34.0 * k, Color(1.0, 0.9, 0.7, 0.022), Color(0, 0, 0, 0), 0.1, 28)
	_apron_fittings()


## What stands on the apron (outpost.tscn, outpost_apron.gd): the two pads,
## the supply drop east of them and the ore hoppers against the back wall.
func _apron_fittings() -> void:
	for px: float in [-1200.0, -480.0]:
		var c := Vector2(px, 3300.0)
		var box := Rect2(c - Vector2(190, 190), Vector2(380, 380))
		pen.hazard(box, 14.0)
		pen.rect_flat(box.grow(-18.0), Color("1B2431"))
		pen.circle(c, 120.0, Color(0, 0, 0, 0), Color(0.9, 0.93, 0.97, 0.8), 5.0, 40)
		pen.fill(PackedVector2Array([c + Vector2(60, -40), c + Vector2(100, 0), c + Vector2(60, 40)]), Color(0.9, 0.93, 0.97, 0.8))
	var drop := Rect2(_b(-3, 90), Vector2(300, 200))
	pen.hazard(drop, 14.0)
	pen.rect_flat(drop.grow(-18.0), Color("1B2431"))
	for hx: float in [12.0, 24.0, 36.0]:
		var bin := Rect2(_b(hx, 55), Vector2(90, 140))
		_block(bin, STEEL, 0.6)
		pen.rect(Rect2(_b(hx + 1.2, 56.2), Vector2(66, 94)), Color("1B2028"), Color(0.9, 0.93, 0.97, 0.6), 1.4)
		for k in 5:
			var p := _b(hx + 2.4 + 4.2 * LevelArt.hash01(k, int(hx) + 70), 60.6 + 4.0 * LevelArt.hash01(k, int(hx) + 71))
			_lump(p, 5.0 + 5.0 * LevelArt.hash01(k, int(hx) + 72), LevelArt.hash01(k, int(hx) + 73) > 0.6)
		pen.hazard(Rect2(_b(hx + 0.6, 66.4), Vector2(78, 20)), 8.0)
	pen.rect_flat(Rect2(_b(14, 58), Vector2(290, 30)), Color(0.55, 0.6, 0.68, 0.8))


## The rock, faceted like the real one: outline points plus a jittered grid,
## Delaunay-triangulated, one flat tone per facet in its stratum's colour.
func _rock() -> void:
	var rock := PackedVector2Array()
	for p in Rock.rock_outline():
		rock.append(p + BASE)
	pen.fill(rock, Rock.STRATA[1].darkened(0.3))
	var pts := PackedVector2Array()
	for i in rock.size():
		var a := rock[i]
		var b := rock[(i + 1) % rock.size()]
		var n := maxi(1, int(ceil(a.distance_to(b) / (FACET * 0.8))))
		for k in n:
			pts.append(a.lerp(b, float(k) / float(n)))
	var bb := LevelArt.poly_bounds(rock)
	var row := 0
	var y := bb.position.y + FACET * 0.4
	while y < bb.end.y:
		var col := 0
		var x := bb.position.x + (FACET * 0.5 if row % 2 == 1 else 0.0)
		while x < bb.end.x:
			var j := Vector2(LevelArt.hash01(col, row * 2 + 1) - 0.5, LevelArt.hash01(col, row * 2 + 2) - 0.5) * FACET * 0.66
			var p := Vector2(x, y) + j
			if Geometry2D.is_point_in_polygon(p, rock):
				pts.append(p)
			x += FACET
			col += 1
		y += FACET * 0.87
		row += 1
	var tris := Geometry2D.triangulate_delaunay(pts)
	for i in range(0, tris.size(), 3):
		var tri := PackedVector2Array([pts[tris[i]], pts[tris[i + 1]], pts[tris[i + 2]]])
		var c := (tri[0] + tri[1] + tri[2]) / 3.0
		if not Geometry2D.is_point_in_polygon(c, rock):
			continue
		var band := (c - BASE).dot(Rock.STRATA_DIR) / (Rock.STRATA_M * 10.0) \
			+ 0.55 * sin((c - BASE).dot(Rock.STRATA_DIR.orthogonal()) / 900.0)
		var tone: Color = Rock.STRATA[posmod(int(floor(band)), Rock.STRATA.size())]
		# facing: facets whose normal leans sunward (up-left) are lighter
		var lean := (tri[1] - tri[0]).rotated(0.9).normalized().dot(Vector2(-0.6, -0.8))
		pen.fill(tri, tone.darkened(0.16 - 0.12 * lean + 0.1 * LevelArt.hash01(i, 3)), false)
	_bedding(rock)
	_rubble(rock)
	pen.polyline(rock, Color(0.96, 0.94, 0.9, 0.55), 3.0, true)


## Thin bedding lines along the strata boundaries (the rock module's own).
func _bedding(rock: PackedVector2Array) -> void:
	var across := Rock.STRATA_DIR.orthogonal()
	for k in range(-9, 9):
		var path := PackedVector2Array()
		var u := -2600.0
		while u <= 2600.0:
			path.append(BASE + Rock.STRATA_DIR * Rock.STRATA_M * 10.0 * (float(k) - 0.55 * sin(u / 900.0)) + across * u)
			u += 70.0
		for part in Geometry2D.intersect_polyline_with_polygon(path, rock):
			pen.polyline(part, Color(0.08, 0.08, 0.12, 0.3), 1.6)


## Close-up interest the flight-scale rock doesn't need: loose stones with a
## short cast shadow, a few per 10 m, placed from a hash so they never move.
func _rubble(rock: PackedVector2Array) -> void:
	var bb := LevelArt.poly_bounds(rock)
	var cell := 64.0
	var cols := int(bb.size.x / cell) + 1
	var rows := int(bb.size.y / cell) + 1
	for j in rows:
		for i in cols:
			var n := j * cols + i
			if LevelArt.hash01(n, 21) < 0.45:
				continue
			var c := bb.position + Vector2(i + LevelArt.hash01(n, 22), j + LevelArt.hash01(n, 23)) * cell
			if not Geometry2D.is_point_in_polygon(c, rock):
				continue
			var big := LevelArt.hash01(n, 24)
			var r := 2.0 + 5.0 * big * big + (9.0 if big > 0.93 else 0.0)
			var stone := PackedVector2Array()
			var cast := PackedVector2Array()
			for k in 6:
				var p := c + Vector2.from_angle(TAU * k / 6.0 + big * 3.0) * r * (0.7 + 0.5 * LevelArt.hash01(n * 6 + k, 25))
				stone.append(p)
				cast.append(p + Vector2(0.35, 0.5) * r)
			var tone: Color = Rock.STRATA[n % Rock.STRATA.size()]
			pen.fill(cast, Color(0.0, 0.0, 0.02, 0.35), false)
			pen.fill(stone, tone.darkened(0.1), false)
			pen.fill(PackedVector2Array([stone[3], stone[4], stone[5], c]), tone.lightened(0.14), false)


## The spar's roof either side of the cut-away (the rooms cover the middle).
func _spar() -> void:
	pen.rect_flat(SPAR, PEARL)
	for yy: float in [SPAR.position.y + 16.0, SPAR.end.y - 30.0]:
		pen.rect_flat(Rect2(Vector2(SPAR.position.x + 130.0, yy), Vector2(SPAR.size.x - 260.0, 14.0)), Color("2B3440"))
		var x := SPAR.position.x + 134.0
		var i := 0
		while x < SPAR.end.x - 140.0:
			pen.rect_flat(Rect2(Vector2(x, yy + 1.5), Vector2(10.0, 11.0)), Color("FFE2A0") if LevelArt.hash01(i, 5) > 0.35 else Color("3A4452"))
			x += 13.0
			i += 1
	pen.rect_flat(Rect2(Vector2(SPAR.position.x + 130.0, SPAR.position.y + 156.0), Vector2(SPAR.size.x - 260.0, 24.0)), Color("2A9D8F"))
	pen.rect_flat(Rect2(Vector2(SPAR.position.x + 130.0, SPAR.position.y + 188.0), Vector2(SPAR.size.x - 260.0, 8.0)), Color("1D3557"))
	var sx := SPAR.position.x + 180.0
	while sx < SPAR.end.x - 140.0:
		pen.line(Vector2(sx, SPAR.position.y + 42.0), Vector2(sx, SPAR.end.y - 42.0), Color(0.45, 0.52, 0.6, 0.8), 1.2)
		sx += 90.0
	pen.line(SPAR.position, Vector2(SPAR.end.x, SPAR.position.y), Color(1, 1, 1), 2.0)
	pen.line(Vector2(SPAR.position.x, SPAR.end.y), SPAR.end, Color("8E9AA8"), 2.0)


## A habitat block's roof: pearl shell, a window strip along both long
## sides, a teal band and its name (as painted on the real roofs), put
## where the cut-away leaves roof to paint it on.
func _roof(r: Rect2, title: String, title_at: Vector2, title_size: float, salt: int) -> void:
	pen.rect_flat(Rect2(r.position + Vector2(7, 10), r.size), Color(0.0, 0.0, 0.02, 0.4))
	pen.rrect(r, 25.0, PEARL, Color("8E9AA8"), 1.6)
	for yy: float in [r.position.y + 17.0, r.end.y - 31.0]:
		pen.rect_flat(Rect2(Vector2(r.position.x + 36.0, yy), Vector2(r.size.x - 72.0, 14.0)), Color("2B3440"))
		var x := r.position.x + 40.0
		var i := 0
		while x < r.end.x - 48.0:
			pen.rect_flat(Rect2(Vector2(x, yy + 1.5), Vector2(10.0, 11.0)), Color("FFE2A0") if LevelArt.hash01(i, salt) > 0.4 else Color("3A4452"))
			x += 13.0
			i += 1
	pen.rect_flat(Rect2(Vector2(r.position.x + 40.0, r.position.y + 44.0), Vector2(r.size.x - 80.0, 12.0)), Color("2A9D8F"))
	pen.text(title_at, title, title_size, Color("1D3557"))


## Base-frame metres (the numbers rock_works.gd and outpost_apron.gd use) to
## local px.
func _b(x: float, y: float) -> Vector2:
	return BASE + Vector2(x, y) * 10.0


## A building seen from above: cast shadow, flat roof, a darker edge.
func _block(r: Rect2, col: Color, height := 1.0) -> void:
	pen.rect_flat(Rect2(r.position + Vector2(7, 10) * height, r.size), CAST)
	pen.rect(r, col, EDGE, 1.6)


func _lump(p: Vector2, s: float, ore: bool) -> void:
	pen.fill(PackedVector2Array([p + Vector2(-s, 0), p + Vector2(0, -s), p + Vector2(s, 0), p + Vector2(0, s)]),
		Color("5D5F6A").lerp(Color("45DCC6"), 0.5 if ore else 0.0), false)


## A conveyor on the ground: grey side frames, dark belt, ore riding on it.
func _belt(a: Vector2, b: Vector2, salt: int) -> void:
	var dir := (b - a).normalized()
	pen.line(a + Vector2(5, 7), b + Vector2(5, 7), CAST, 36.0, false)
	pen.line(a, b, Color("8E9AA8"), 36.0, false)
	pen.line(a, b, Color("22262E"), 27.0, false)
	var t := 6.0
	var i := 0
	while t < a.distance_to(b) - 6.0:
		_lump(a + dir * t + dir.orthogonal() * (LevelArt.hash01(i, salt) - 0.5) * 12.0,
			3.0 + 3.0 * LevelArt.hash01(i, salt + 1), LevelArt.hash01(i, salt + 2) > 0.7)
		t += 9.0 + 9.0 * LevelArt.hash01(i, salt + 3)
		i += 1
	for e: Vector2 in [a, b]:
		pen.line(e - dir * 4.0, e + dir * 4.0, Color("FFB000"), 42.0, false)


## The ore plant between HAB B and the apron, the tank farm by the trunk and
## the control block on the east shoulder: same footprints as rock_works.gd.
func _works() -> void:
	_belt(_b(-124, 20), _b(-80, 24), 51)
	_belt(_b(-50, 26), _b(-14, 30), 52)
	# crusher
	_block(Rect2(_b(-80, 10), Vector2(300, 280)), STEEL, 1.6)
	pen.hazard(Rect2(_b(-80, 10), Vector2(30, 280)), 10.0)
	pen.rect(Rect2(_b(-74, 15), Vector2(140, 180)), Color("1B2028"), Color(0.85, 0.89, 0.93, 0.7), 1.6)
	for i in 5:
		pen.rect_flat(Rect2(_b(-73.2, 16.4 + 3.3 * i), Vector2(124, 20)), Color("3C434E"))
	for k in 7:
		_lump(_b(-67, 24) + Vector2(LevelArt.hash01(k, 61) - 0.5, LevelArt.hash01(k, 62) - 0.5) * 70.0, 8.0 + 8.0 * LevelArt.hash01(k, 63), k % 3 == 0)
	pen.rect_flat(Rect2(_b(-58, 13), Vector2(60, 220)), NAVY)
	# screen house: sorts the crushed ore onto the hopper belt
	_block(Rect2(_b(-14, 16), Vector2(240, 260)), GREY, 1.3)
	for i in 3:
		pen.rect_flat(Rect2(_b(-10.5 + 7.0 * i, 20), Vector2(50, 110)), Color("2B3440"))
		pen.rect_flat(Rect2(_b(-10.0 + 7.0 * i, 20.5), Vector2(40, 35)), Color("45DCC6").darkened(0.35))
	pen.rect_flat(Rect2(_b(-12, 35), Vector2(200, 45)), TEAL)
	# stockpile, then the elevated belt down to the hoppers
	for k in 14:
		_lump(_b(28, 22) + Vector2.from_angle(TAU * LevelArt.hash01(k, 64)) * 50.0 * LevelArt.hash01(k, 65), 9.0 + 9.0 * LevelArt.hash01(k, 66), k % 4 == 0)
	pen.line(_b(8, 34), _b(30, 61), Color(0.55, 0.6, 0.68, 0.8), 40.0, false)
	pen.line(_b(8, 34), _b(30, 61), Color(0.12, 0.14, 0.18, 0.75), 16.0, false)
	# tank farm east of the trunk
	for t: Array in [[18.0, -90.0, 80.0, TEAL], [38.0, -88.0, 80.0, PEARL], [55.0, -79.0, 60.0, PEARL]]:
		var c := _b(t[0], t[1])
		var r: float = t[2]
		pen.circle(c + Vector2(8, 11), r, CAST)
		pen.circle(c, r, t[3], EDGE, 1.6, 32)
		pen.ring(c, r * 0.62, Color(0.4, 0.5, 0.6, 0.5), 1.4, 28)
		pen.ring(c, r * 0.26, Color("FFB000"), r * 0.12, 20)
	# control block and its tube to HAB B
	_block(Rect2(_b(16, -29), Vector2(340, 60)), GREY, 0.5)
	var ops := PackedVector2Array([_b(52, -28), _b(94, -28), _b(98, -24), _b(98, 8), _b(94, 12), _b(52, 12), _b(48, 8), _b(48, -24)])
	pen.rect_flat(Rect2(_b(48, -28) + Vector2(10, 14), Vector2(500, 400)), CAST)
	pen.poly(ops, PEARL, Color("8E9AA8"), 1.6)
	pen.rect_flat(Rect2(_b(83, -22), Vector2(120, 270)), NAVY)
	pen.circle(_b(68, -8), 105.0, NAVY, Color(0, 0, 0, 0), 0.1, 8)
	pen.circle(_b(68, -8), 92.0, PEARL, Color(0, 0, 0, 0), 0.1, 8)
	pen.circle(_b(68, -8), 56.0, Color("1F4B60"), Color(0.9, 0.97, 1.0, 0.9), 2.2, 28)
	# floodlight masts on the terrace lip
	for mx: float in [-150.0, -100.0, -50.0, 0.0, 42.0]:
		pen.circle(_b(mx, 46.5) + Vector2(5, 7), 13.0, CAST)
		pen.circle(_b(mx, 46.5), 13.0, EDGE, Color(0.9, 0.93, 0.97, 0.8), 1.4, 10)
		pen.circle(_b(mx, 46.5), 6.0, Color("FFE2A0"))
	# (text is centred over a width; the offsets put the baseline under it)
	pen.text(_b(-55, 24) + Vector2(7, 0), "CRUSHER 01", 20.0, PEARL, HORIZONTAL_ALIGNMENT_CENTER, 220.0, true, -PI * 0.5)
	pen.text(_b(-2, 37.25) + Vector2(0, 5.5), "SCREEN HOUSE", 15.0, PEARL, HORIZONTAL_ALIGNMENT_CENTER, 200.0)
