@tool
extends StationModule
## Deep Space Relay: a huge parabolic dish (colliding) with an overhead feed
## tripod, plus its equipment building. Local origin = dish centre, metres.

@export var dish_radius_m := 48.0:
	set(v): dish_radius_m = v; queue_rebuild()


func _build() -> void:
	var R := dish_radius_m * PX
	var D := Band.STRUCT_DETAIL
	# equipment building + causeway
	var bld := A.rect_m(dish_radius_m + 4, -14, dish_radius_m + 44, 14)
	hull(bld, &"pearl", [], {"bevel": 0.8})
	windows(D, PackedVector2Array([m(dish_radius_m + 7, -11.5), m(dish_radius_m + 41, -11.5)]), 1.4, 1.1, 3)
	windows(D, PackedVector2Array([m(dish_radius_m + 7, 11.5), m(dish_radius_m + 41, 11.5)]), 1.4, 1.1, 4)
	fill(D, A.rect_m(dish_radius_m + 8, -4, dish_radius_m + 40, 4), A.NAVY)
	text(D, m(dish_radius_m + 24, 0), "DEEP SPACE RELAY", 34, Color(0.9, 0.95, 1.0, 0.95))
	beacon(m(dish_radius_m + 42, -12), A.NAV_RED, 90.0, 0.2)
	beacon(m(dish_radius_m + 42, 12), A.NAV_RED, 90.0, 0.7)
	# dish
	var dish := A.circle_poly(Vector2.ZERO, R, 64)
	hull(dish, &"pearl", [], {"bevel": 1.5})
	for i in 5:
		var k := 1.0 - (i + 1) * 0.17
		fill(D, A.circle_poly(Vector2.ZERO, R * k, 56), Color("DDE3EA").lerp(Color("AEB9C6"), float(i) / 5.0))
	var ribs := PackedVector2Array()
	for i in 24:
		var a := TAU * i / 24.0
		ribs.append_array([Vector2(cos(a), sin(a)) * R * 0.12, Vector2(cos(a), sin(a)) * (R - 16.0)])
	lines(D, ribs, Color(0.5, 0.58, 0.67, 0.55), 1.5)
	fill(D, A.circle_poly(Vector2(-R * 0.3, -R * 0.35), R * 0.28, 32), Color(1, 1, 1, 0.12))
	# feed tripod overhead
	for i in 3:
		var a := TAU * i / 3.0 + PI / 6.0
		var p := Vector2(cos(a), sin(a)) * (R - 30.0)
		overhead(A.obox(p * 0.5, p, p.length(), 1.6 * PX), Color(0.9, 0.93, 0.97, 0.7))
	overhead(A.circle_poly(Vector2.ZERO, 5.0 * PX, 20), Color(0.95, 0.97, 1.0, 0.85))
	lamp(Vector2.ZERO, Color(1.0, 0.4, 0.3), 70.0, 2)
	for i in 4:
		var a := TAU * i / 4.0 + PI * 0.25
		beacon(Vector2(cos(a), sin(a)) * (R - 10.0), Color.WHITE if i % 2 == 0 else A.NAV_RED, 110.0, 0.25 * i, i % 2 == 0)
