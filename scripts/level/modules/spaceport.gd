@tool
extends StationModule
## Meridian Spaceport: the commerce pier. A long colliding spine with a
## control tower, mooring arms for docked freighters on the east side and
## jet-bridges reaching over the landing pads on the west side.
## Local origin = spine centre line; all numbers in metres.

@export var spine_top_m := -375.0:
	set(v): spine_top_m = v; queue_rebuild()
@export var spine_bottom_m := 330.0:
	set(v): spine_bottom_m = v; queue_rebuild()
## y positions (m) of the west landing pads (jet bridges reach them).
@export var pad_rows_m: PackedFloat32Array = PackedFloat32Array([-230.0, -120.0, 120.0, 230.0]):
	set(v): pad_rows_m = v; queue_rebuild()
## y positions (m) of east mooring arms and their length (m).
@export var mooring_rows_m: PackedFloat32Array = PackedFloat32Array([-205.0, -95.0, 120.0, 220.0]):
	set(v): mooring_rows_m = v; queue_rebuild()
@export var mooring_len_m := 48.0:
	set(v): mooring_len_m = v; queue_rebuild()

const X0 := -10.0
const X1 := 15.0

var _radar_dish: Node2D


func _build() -> void:
	var top := spine_top_m
	var bot := spine_bottom_m
	# --- spine + tower + mooring arms -> one union outline, convex pieces.
	var spine := A.rounded_rect(Rect2(m(X0, top), m(X1 - X0, bot - top)), 12.0 * PX, 6)
	var tower := A.circle_poly(m(2.5, 0), 27.0 * PX, 8, PI / 8.0)
	var convex: Array = [A.rect_m(X0, top + 12, X1, bot - 12)]
	convex.append(A.rect_poly(Rect2(m(X0 + 2.0, top), m(X1 - X0 - 4.0, 12))))
	convex.append(A.rect_poly(Rect2(m(X0 + 2.0, bot - 12), m(X1 - X0 - 4.0, 12))))
	convex.append(tower)
	var shape := spine
	shape = union(shape, tower)
	for y in mooring_rows_m:
		var arm := A.rect_m(X1 - 2.0, y - 3.5, X1 + mooring_len_m, y + 3.5)
		convex.append(arm)
		shape = union(shape, arm)
		# mooring clamp block at the tip
		var clamp := A.rect_m(X1 + mooring_len_m - 6.0, y - 6.0, X1 + mooring_len_m, y + 6.0)
		convex.append(clamp)
		shape = union(shape, clamp)
	hull(shape, &"pearl", convex, {"bevel": 1.0})
	radar_polys.append(A.rect_m(X0, top, X1, bot))
	radar_polys.append(tower)
	for y in mooring_rows_m:
		radar_polys.append(A.rect_m(X1, y - 4, X1 + mooring_len_m, y + 4))
	var D := Band.STRUCT_DETAIL
	# --- spine detail: window strips, accent band, seams, name.
	for seg in [[top + 14.0, -30.0], [30.0, bot - 14.0]]:
		windows(D, PackedVector2Array([m(X0 + 2.4, seg[0]), m(X0 + 2.4, seg[1])]), 1.8, 1.3, int(seg[0]))
		windows(D, PackedVector2Array([m(X1 - 2.4, seg[0]), m(X1 - 2.4, seg[1])]), 1.8, 1.3, int(seg[1]) + 7)
		fill(D, A.rect_m(1.2, seg[0], 3.8, seg[1]), A.TEAL)
		fill(D, A.rect_m(4.6, seg[0], 5.4, seg[1]), A.NAVY)
	var pairs := PackedVector2Array()
	var y0 := top + 20.0
	while y0 < bot - 15.0:
		if absf(y0) > 30.0:
			pairs.append_array([m(X0 + 4.2, y0), m(X1 - 4.2, y0)])
		y0 += 9.0
	seams(D, pairs)
	text(D, m(-2.0, -170), "MERIDIAN  SPACEPORT", 64, A.NAVY, -PI * 0.5)
	text(D, m(-2.0, 175), "COMMERCE PIER 7", 54, A.NAVY, -PI * 0.5)
	# mooring arms: hazard tips + amber lamps + umbilicals overhead
	for y in mooring_rows_m:
		hazard(D, A.rect_m(X1 + mooring_len_m - 5.0, y - 5.0, X1 + mooring_len_m - 1.0, y + 5.0), 0.9)
		fill(D, A.rect_m(X1 + 1.0, y - 1.0, X1 + mooring_len_m - 6.0, y + 1.0), Color("AAB6C4"))
		lamp(m(X1 + mooring_len_m - 3.0, y - 6.5), A.AMBER, 34.0)
		lamp(m(X1 + mooring_len_m - 3.0, y + 6.5), A.AMBER, 34.0)
		overhead(A.rect_m(X1 + 2.0, y + 6.0, X1 + mooring_len_m + 6.0, y + 8.2), Color(0.95, 0.75, 0.3, 0.55), Color(1, 0.9, 0.6, 0.7))
	# --- control tower
	var D2 := Band.STRUCT_DETAIL
	fill(D2, A.circle_poly(m(2.5, 0), 21.0 * PX, 8, PI / 8.0), A.NAVY)
	fill(D2, A.circle_poly(m(2.5, 0), 19.0 * PX, 8, PI / 8.0), Color("E3E9EF"))
	windows(D2, A.circle_poly(m(2.5, 0), 16.5 * PX, 48), 1.8, 1.2, 77)
	var cab := A.circle_poly(m(2.5, 0), 12.0 * PX, 40)
	fill(D2, cab, Color("1F4B60"))
	fill(D2, A.circle_poly(m(1.0, -1.5), 9.5 * PX, 32), Color("2A6680"))
	fill(D2, A.circle_poly(m(-1.5, -4.5), 3.5 * PX, 20), Color(1, 1, 1, 0.18))
	outline(D2, cab, Color(0.9, 0.97, 1.0, 0.9), 3.0)
	glow(m(2.5, 0), Color(0.5, 0.9, 1.0, 0.3), 220.0)
	for i in 8:
		var a := TAU * i / 8.0 + PI / 8.0
		beacon(m(2.5, 0) + Vector2(cos(a), sin(a)) * 24.0 * PX, Color.WHITE if i % 2 == 0 else A.NAV_RED, 90.0, 0.125 * i, i % 2 == 0)
	# --- jet bridges over the west pads (overhead)
	for y in pad_rows_m:
		# short enough that a ship parked on the pad centre stays in view
		overhead(A.rect_m(X0 - 12.0, y - 2.4, X0 + 2.0, y + 2.4), Color(0.9, 0.93, 0.97, 0.66))
		overhead(A.rect_m(X0 - 15.0, y - 3.6, X0 - 11.0, y + 3.6), Color(0.75, 0.82, 0.9, 0.7))
		lamp(m(X0 - 13.0, y), A.WARM, 40.0, 2)
		lamp(m(X0 - 5.0, y), A.CYAN, 30.0, 2)
	# --- edge lights along the spine + tip beacons
	var yl := top + 20.0
	while yl < bot - 10.0:
		if absf(yl) > 32.0:
			lamp(m(X0 + 0.9, yl), A.CYAN, 26.0)
			lamp(m(X1 - 0.9, yl), A.CYAN, 26.0)
		yl += 16.0
	beacon(m(X0 + 3.0, bot - 4.0), A.NAV_RED, 110.0, 0.0)
	beacon(m(X1 - 3.0, bot - 4.0), A.NAV_GREEN, 110.0, 0.0)
	beacon(m(2.5, bot - 8.0), Color.WHITE, 150.0, 0.3, true)


func _after_build() -> void:
	# Spinning radar antenna on top of the tower (one tiny per-frame node).
	_radar_dish = Node2D.new()
	_radar_dish.name = "RadarDish"
	_radar_dish.position = m(2.5, 0)
	_radar_dish.z_as_relative = false
	_radar_dish.z_index = G.Z_OVERHEAD
	_radar_dish.draw.connect(_draw_dish)
	add_child(_radar_dish)
	_generated.append(_radar_dish)


func _draw_dish() -> void:
	var w := 4.0 * PX
	_radar_dish.draw_rect(Rect2(Vector2(-w * 0.5, -80), Vector2(w, 160)), Color(0.92, 0.95, 1.0, 0.85))
	_radar_dish.draw_rect(Rect2(Vector2(-w * 0.5, -80), Vector2(w, 160)), Color(0.3, 0.4, 0.55, 0.9), false, 2.0, true)
	_radar_dish.draw_line(Vector2.ZERO, Vector2(70, 0), Color(0.85, 0.9, 0.95, 0.8), 4.0, true)
	_radar_dish.draw_circle(Vector2.ZERO, 14.0, Color("1D3557"))
	_radar_dish.draw_circle(Vector2(70, 0), 6.0, Color(1, 0.3, 0.3, 0.9))


func _process(delta: float) -> void:
	if _radar_dish and not Engine.is_editor_hint():
		_radar_dish.rotation += delta * 1.3
