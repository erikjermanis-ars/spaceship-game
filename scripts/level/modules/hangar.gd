@tool
extends StationModule
## Hangar 2: an open-roofed service bay at the north end of the pier. The
## west opening is closed by two sliding blast-door leaves (separate
## blast_door.gd modules) that tuck into the door housings north and south.
## Local origin = bay centre, metres.

@export var size_m := Vector2(120, 90):
	set(v): size_m = v; queue_rebuild()
@export var wall_m := 10.0:
	set(v): wall_m = v; queue_rebuild()
@export var opening_m := 60.0:
	set(v): opening_m = v; queue_rebuild()


func _build() -> void:
	var hx := size_m.x * 0.5
	var hy := size_m.y * 0.5
	var w := wall_m
	var ho := opening_m * 0.5
	var parts: Array[PackedVector2Array] = [
		A.rect_m(-hx, -hy, hx, -hy + w),                # north wall
		A.rect_m(-hx, hy - w, hx, hy),                  # south wall
		A.rect_m(hx - w, -hy + w - 1, hx, hy - w + 1),  # east wall
		A.rect_m(-hx, -hy + w - 1, -hx + w, -ho),       # west stub N
		A.rect_m(-hx, ho, -hx + w, hy - w + 1),         # west stub S
		A.rect_m(-hx - 6, -hy - 33, -hx + w, -hy + 1),  # door housing N
		A.rect_m(-hx - 6, hy - 1, -hx + w, hy + 33),    # door housing S
	]
	# union() keeps only the largest merged polygon, so merge in an order where
	# every part touches what is already merged: the east wall joins the north
	# and south walls first. (Starting from the north wall dropped it, with its
	# stub and door housing, from the art while they still collided.)
	var order := [2, 0, 1, 3, 4, 5, 6]
	var shape := parts[order[0]]
	for i in range(1, order.size()):
		shape = union(shape, parts[order[i]])
	# Floor first (below deck) so it tucks under the walls.
	deck(A.rect_m(-hx + 2, -hy + 2, hx - 2, hy - 2), 5.0, Color("1A2230"), Color("222C3B"), Color("2B384B"), Color("4A5D75"))
	hazard(Band.DECK, A.rect_m(-hx + w + 1, -ho, -hx + w + 4, ho), 1.2)
	# Painted floor guide lines into the bay.
	for s: float in [-1.0, 1.0]:
		line(Band.DECK, m(-hx + w + 6, s * 14.0), m(hx - w - 6, s * 14.0), Color(1.0, 0.75, 0.2, 0.55), 6.0)
	text(Band.DECK, m(hx - w - 16, 0), "HANGAR 2", 70, Color(0.85, 0.9, 1.0, 0.55), PI * 0.5)
	hull(shape, &"pearl", parts, {"bevel": 1.0})
	radar_polys.append(A.rect_m(-hx, -hy, hx, -hy + w))
	radar_polys.append(A.rect_m(-hx, hy - w, hx, hy))
	radar_polys.append(A.rect_m(hx - w, -hy, hx, hy))
	var D := Band.STRUCT_DETAIL
	# Roof detail: navy band, seams, windows on the outer faces.
	fill(D, A.rect_m(-hx + 3, -hy + 1.2, hx - 3, -hy + 2.2), A.NAVY)
	fill(D, A.rect_m(-hx + 3, hy - 5.5, hx - 3, hy - 3.5), A.NAVY)
	fill(D, A.rect_m(hx - 5.5, -hy + 6, hx - 3.5, hy - 6), A.NAVY)
	windows(D, PackedVector2Array([m(-hx + 12, hy - 1.6), m(hx - 4, hy - 1.6)]), 1.4, 1.2, 31)
	windows(D, PackedVector2Array([m(hx - 1.6, -hy + 4), m(hx - 1.6, hy - 4)]), 1.4, 1.2, 32)
	var pairs := PackedVector2Array()
	var x := -hx + 12.0
	while x < hx - 6.0:
		pairs.append_array([m(x, -hy + 1.5), m(x, -hy + 3.2), m(x, hy - 3.2), m(x, hy - 1.5)])
		x += 8.0
	seams(D, pairs)
	# Sits fully on the light roof band of the north wall, where navy reads.
	text(D, m(5, -hy + w * 0.5 - 1.0), "MERIDIAN  ·  HANGAR 2  ·  SERVICE BAY", 46, A.NAVY)
	for s: float in [-1.0, 1.0]:
		# door housings: hazard faces + warning lamps
		var yy := s * (hy + 16)
		hazard(D, A.rect_m(-hx - 5, yy - 12, -hx - 1, yy + 12), 1.0)
		beacon(m(-hx - 3, s * (ho + 2.0)), A.AMBER, 110.0, 0.0 if s < 0 else 0.5)
		beacon(m(-hx + w * 0.5, s * (hy + 30)), Color.WHITE, 120.0, 0.2, true)
	# Overhead gantry crane rails across the open bay.
	for xx: float in [-14.0, 22.0]:
		truss(m(xx, -hy + 2), m(xx, hy - 2), 5.0)
	overhead(A.rect_m(-18.0, -24, 26.0, -19.0), Color(0.85, 0.88, 0.92, 0.5), Color(1, 0.85, 0.4, 0.8))
	lamp(m(4, -21.5), A.WARM, 80.0, 2)
	# Static clutter inside: parked shuttle and maintenance crates.
	var ShipPainter := preload("res://scripts/level/ship_painter.gd")
	ShipPainter.shuttle(self, Transform2D(-PI * 0.5, m(hx - w - 14, -hy + w + 12)), A.TEAL, 3, false)
	for i in 3:
		var c := m(hx - w - 6, 14.0 + i * 6.5)
		hull(A.rect_poly(Rect2(c - Vector2(22, 22), Vector2(44, 44))), &"amber", [], {"bevel": 0.4})
		line(Band.STRUCT_DETAIL, c - Vector2(14, 14), c + Vector2(14, 14), Color(0.3, 0.2, 0.0, 0.8), 3.0)
		line(Band.STRUCT_DETAIL, c - Vector2(14, -14), c + Vector2(14, -14), Color(0.3, 0.2, 0.0, 0.8), 3.0)
