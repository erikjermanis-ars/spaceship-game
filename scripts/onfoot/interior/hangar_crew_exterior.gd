@tool
extends Node2D
## What you see beyond the walls of the Hangar 2 crew room. The crew room is a
## cut-away of the hangar's east wall (10 m thick, the rooms sit inside it), so
## west of it is the hangar floor with the shuttle bay and the lane to airlock
## H2, north and south the wall's roof carries on, and east is open space (the
## game's SpaceBackground shows through).
##
## Why this exists: the station itself is suspended and hidden while you are
## inside, so without it the west windows and the airlock hatch would look out
## on stars where the bay floor is. Everything is placed from the same numbers
## as hangar.gd / hangar_site.gd. Unshaded: the bay is floodlit, not part of
## the dark rooms.

## Hangar centre in this interior's coordinates (px). The interior's origin is
## the wall's inner face at the airlock: world (6300, -4350), the hangar's
## centre is world (5800, -4250).
const HANGAR := Vector2(-500, 100)
const HALF := Vector2(600, 450)          # hangar half size, walls included
const WALL := 100.0
const BAY := Rect2(316, -318, 88, 176)   # shuttle bay, hangar-local (hangar_site.gd)
## The rooms' hull spans these Y (px): no roof is drawn over the cut-away, or
## the east windows would show roof instead of stars.
const CUT_TOP := -290.0
const CUT_BOTTOM := 120.0
const TUBE := Rect2(36, 120, 28, 430)    # the pod's track south, inside the wall

var pen: OnFootPainter


func _ready() -> void:
	z_as_relative = false
	z_index = -8
	if not Engine.is_editor_hint():
		material = OnFootArt.unshaded()


func _draw() -> void:
	pen = OnFootPainter.new(self)
	_floor()
	_markings()
	_walls()
	pen.flush()


func _floor() -> void:
	var inner := Rect2(HANGAR - HALF + Vector2(WALL, WALL), HALF * 2.0 - Vector2(WALL, WALL) * 2.0)
	# Runs 1 m under the crew room's west hull, so its windows show deck.
	var deck := Rect2(inner.position, inner.size + Vector2(10, 0))
	pen.rect_flat(deck, Color("1F2836"))
	var x := deck.end.x - 60.0
	while x > deck.position.x:
		pen.line(Vector2(x, deck.position.y), Vector2(x, deck.end.y), Color("2B384B"), 0.6)
		x -= 60.0
	var y := deck.position.y + 50.0
	while y < deck.end.y:
		pen.line(Vector2(deck.position.x, y), Vector2(deck.end.x, y), Color("2B384B"), 0.6)
		y += 60.0
	# the landing pad (raised) and the blast-door threshold, far to the west
	var pad := Rect2(HANGAR + Vector2(-150, -200), Vector2(400, 400))
	pen.rect(pad, Color("273243"), Color("4A5D75"), 0.8)
	pen.hazard(Rect2(pad.position, Vector2(pad.size.x, 10)), 6.0)
	pen.hazard(Rect2(Vector2(pad.position.x, pad.end.y - 10), Vector2(pad.size.x, 10)), 6.0)
	pen.ring(pad.get_center(), 120.0, Color(0.9, 0.93, 0.97, 0.8), 4.0, 48)
	pen.ring(pad.get_center(), 105.0, Color(1.0, 0.69, 0.0, 0.8), 1.6, 48)
	pen.hazard(Rect2(Vector2(inner.position.x + 54, inner.position.y), Vector2(5, inner.size.y)), 2.0)


func _markings() -> void:
	# amber guide lines into the bay (hangar.gd)
	for s: float in [-1.0, 1.0]:
		pen.line(HANGAR + Vector2(-440, s * 140.0), HANGAR + Vector2(440, s * 140.0), Color(1.0, 0.75, 0.2, 0.55), 6.0, false)
	# the shuttle's painted bay
	var b := Rect2(HANGAR + BAY.position, BAY.size)
	var amber := Color(1.0, 0.69, 0.0, 0.8)
	for c: Vector2 in [b.position, Vector2(b.end.x, b.position.y), b.end, Vector2(b.position.x, b.end.y)]:
		var sx := 1.0 if c.x < b.get_center().x else -1.0
		var sy := 1.0 if c.y < b.get_center().y else -1.0
		pen.line(c, c + Vector2(14 * sx, 0), amber, 0.9)
		pen.line(c, c + Vector2(0, 14 * sy), amber, 0.9)
	pen.polyline(OnFootArt.rect_poly(b), Color(1.0, 0.69, 0.0, 0.25), 0.4, true)
	pen.hazard(Rect2(Vector2(b.position.x, b.end.y + 3), Vector2(b.size.x, 4)), 1.6)
	# maintenance crates in the south-east corner
	for i in 3:
		var c := HANGAR + Vector2(440, 140.0 + i * 65.0)
		pen.rect(Rect2(c - Vector2(22, 22), Vector2(44, 44)), Color("F2A900"), Color("7A5200"), 1.2)
		pen.line(c - Vector2(14, 14), c + Vector2(14, 14), Color(0.3, 0.2, 0.0, 0.8), 3.0)
		pen.line(c - Vector2(14, -14), c + Vector2(14, -14), Color(0.3, 0.2, 0.0, 0.8), 3.0)
	# the crew lane to airlock H2 (hangar_site.gd paints the same on the deck)
	var lane := Color(0.92, 0.95, 1.0, 0.5)
	for k: float in [-1.0, 1.0]:
		var corner := Vector2(-198.5 + 8.5 * k, -8.5 * k)
		_dashes(Vector2(corner.x, -30.0), corner, lane)
		_dashes(corner, Vector2(-34.0, corner.y), lane)
		pen.rect_flat(Rect2(Vector2(-32.0, corner.y - 0.3), Vector2(26.0, 0.6)), Color(0.92, 0.95, 1.0, 0.45))
	var x := -175.0
	while x < -40.0:
		if absf(x + 105.0) > 16.0:
			pen.fill(PackedVector2Array([Vector2(x, -4), Vector2(x + 4, 0), Vector2(x, 4), Vector2(x - 1.5, 4), Vector2(x + 2.5, 0), Vector2(x - 1.5, -4)]), Color(0.5, 0.9, 1.0, 0.35))
		x += 14.0
	pen.hazard(Rect2(Vector2(-5.0, -11.0), Vector2(4.0, 22.0)), 2.0)
	pen.text(Vector2(-105.0, 1.3), "CREW ROOM", 3.6, Color(0.85, 0.92, 1.0, 0.5), HORIZONTAL_ALIGNMENT_CENTER, 60.0)


func _dashes(a: Vector2, b: Vector2, col: Color) -> void:
	var d := a.distance_to(b)
	var dir := (b - a) / d
	var s := 0.0
	while s < d:
		pen.line(a + dir * s, a + dir * minf(s + 5.0, d), col, 0.7)
		s += 9.0


func _walls() -> void:
	var o := HANGAR - HALF
	var e := HANGAR + HALF
	var parts: Array[Rect2] = [
		Rect2(o, Vector2(HALF.x * 2.0, WALL)),                                  # north wall
		Rect2(Vector2(o.x, e.y - WALL), Vector2(HALF.x * 2.0, WALL)),           # south wall
		Rect2(Vector2(0, o.y), Vector2(WALL, CUT_TOP - o.y)),                   # east wall, north of the rooms
		Rect2(Vector2(0, CUT_BOTTOM), Vector2(WALL, e.y - CUT_BOTTOM)),         # east wall, south of them
	]
	for r in parts:
		pen.rect_flat(r, Color("E3E9EF"))
	# roof detail of the east wall: navy band, lit windows on the outer face
	for r: Rect2 in [parts[2], parts[3]]:
		pen.rect_flat(Rect2(Vector2(45, r.position.y), Vector2(20, r.size.y)), Color("1D3557"))
		pen.rect_flat(Rect2(Vector2(76, r.position.y), Vector2(16, r.size.y)), Color("3A4048"))
		var wy := r.position.y + 2.0
		var i := 0
		while wy < r.end.y - 14.0:
			var lit := LevelArt.hash01(i, 32) > 0.35
			pen.rect_flat(Rect2(Vector2(79, wy), Vector2(10, 13)), Color("FFF3B0") if lit else Color("C2A970"))
			wy += 15.0
			i += 1
		pen.line(Vector2(0, r.position.y), Vector2(0, r.end.y), Color(1, 1, 1), 2.0)
		pen.line(Vector2(WALL, r.position.y), Vector2(WALL, r.end.y), Color("8E9AA8"), 2.0)
	pen.rect_flat(Rect2(Vector2(o.x + 30, o.y + 12), Vector2(HALF.x * 2.0 - 60, 10)), Color("1D3557"))
	pen.rect_flat(Rect2(Vector2(o.x + 30, e.y - 55), Vector2(HALF.x * 2.0 - 60, 20)), Color("1D3557"))
	# the transit tube: the pod's track runs south inside the wall
	pen.rect(TUBE, Color("161D28"), Color("8E9AA8"), 0.6)
	for xx: float in [TUBE.position.x + 6.0, TUBE.end.x - 6.0]:
		pen.line(Vector2(xx, TUBE.position.y), Vector2(xx, TUBE.end.y), Color("5A6878"), 0.8, false)
	var ty := TUBE.position.y + 44.0
	while ty < TUBE.end.y:
		pen.line(Vector2(TUBE.position.x + 6.0, ty), Vector2(TUBE.end.x - 6.0, ty), Color("2B384B"), 1.2, false)
		pen.circle(Vector2(TUBE.position.x + 2.5, ty), 0.8, OnFootArt.CYAN)
		pen.circle(Vector2(TUBE.end.x - 2.5, ty), 0.8, OnFootArt.CYAN)
		ty += 30.0
