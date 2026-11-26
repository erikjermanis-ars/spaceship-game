@tool
extends StationModule
## Tug & service dock: an apron with a control hut and parked work tugs.
## Docking pads are separate docking_pad.gd nodes placed on top of it.
## Local origin = apron centre, metres.

func _build() -> void:
	var SP := preload("res://scripts/level/ship_painter.gd")
	deck(A.rounded_rect(Rect2(m(-110, -55), m(220, 110)), 120.0), 6.0)
	text(Band.DECK, m(-70, 0), "TUG & SERVICE", 54, Color(0.85, 0.9, 1.0, 0.3), -PI * 0.5)
	var D := Band.STRUCT_DETAIL
	# control hut
	var hut := A.rect_m(-100, -45, -80, 45)
	hull(hut, &"pearl", [], {"bevel": 0.8})
	windows(D, PackedVector2Array([m(-82, -42), m(-82, 42)]), 1.5, 1.1, 8)
	fill(D, A.rect_m(-97, -40, -91, 40), A.TEAL)
	beacon(m(-90, -44), A.NAV_RED, 100.0, 0.0)
	beacon(m(-90, 44), A.NAV_GREEN, 100.0, 0.0)
	# parked tugs (static, colliding)
	for i in 3:
		SP.tug(self, Transform2D(PI, m(85, -36 + i * 36)), 20 + i, false)
		hazard(Band.DECK, A.rect_m(92, -44 + i * 36, 96, -28 + i * 36), 0.8)
