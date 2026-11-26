@tool
extends StationModule
## Solar Field 3: rows of long photovoltaic wings strung between two side
## trusses. Rows leave alternating gaps, forming a serpentine slalom; an
## overhead power bus runs down the middle. A comms mast guards the entry.
## Local origin = field centre, metres.

@export var half_width_m := 115.0:
	set(v): half_width_m = v; queue_rebuild()
@export var rows_m: PackedFloat32Array = PackedFloat32Array([-200.0, -110.0, -20.0, 70.0, 160.0]):
	set(v): rows_m = v; queue_rebuild()
@export var gap_m := 59.0:
	set(v): gap_m = v; queue_rebuild()
@export var row_thick_m := 11.0:
	set(v): row_thick_m = v; queue_rebuild()
## Which side the FIRST row's gap is on (+1 east, -1 west).
@export var first_gap_side := 1.0:
	set(v): first_gap_side = v; queue_rebuild()


func _build() -> void:
	var hw := half_width_m
	var fw := 6.0           # side truss width
	var y0 := rows_m[0] - 45.0
	var y1 := rows_m[rows_m.size() - 1] + 45.0
	var D := Band.STRUCT_DETAIL
	# --- side trusses
	for s: float in [-1.0, 1.0]:
		var x0 := s * hw - fw * 0.5
		var truss_poly := A.rect_m(x0, y0, x0 + fw, y1)
		hull(truss_poly, &"grey", [], {"bevel": 0.5})
		var pairs := PackedVector2Array()
		var y := y0 + 1.0
		var k := 0
		while y < y1 - 4.0:
			pairs.append_array([m(x0 + 1.0, y), m(x0 + fw - 1.0, y + 4.0)] if k % 2 == 0 else [m(x0 + fw - 1.0, y), m(x0 + 1.0, y + 4.0)])
			y += 4.0
			k += 1
		lines(D, pairs, Color(0.42, 0.5, 0.6, 0.8), 2.0)
		beacon(m(s * hw, y0 + 2), A.NAV_RED if s < 0 else A.NAV_GREEN, 110.0, 0.0)
		beacon(m(s * hw, y1 - 2), A.NAV_RED if s < 0 else A.NAV_GREEN, 110.0, 0.5)
		text(D, m(s * hw, (y0 + y1) * 0.5), "SOLAR FIELD 3  ·  48 MW", 40, A.NAVY, -PI * 0.5 * s)
	# --- panel rows
	for i in rows_m.size():
		var side := first_gap_side * (1.0 if i % 2 == 0 else -1.0)
		var yc := rows_m[i]
		var t := row_thick_m * 0.5
		var xa := -hw + fw * 0.5 - 0.5
		var xb := hw - fw * 0.5 + 0.5
		if side > 0:
			xb = hw - gap_m
		else:
			xa = -hw + gap_m
		var row := A.rect_m(xa, yc - t, xb, yc + t)
		hull(row, &"solar", [], {"bevel": 0.5})
		# photovoltaic cells: two wings either side of a central spar
		var cx := xa + 1.2
		var ci := 0
		while cx < xb - 4.0:
			for wing: float in [-1.0, 1.0]:
				var c0 := yc + (0.6 if wing > 0 else -t + 0.9)
				var c1 := yc + (t - 0.9 if wing > 0 else -0.6)
				var shade := Color("23407A") if (ci + int(wing)) % 2 == 0 else Color("1E3870")
				fill(D, A.rect_m(cx, c0, cx + 3.3, c1), shade)
				fill(D, A.rect_m(cx + 0.2, c0 + 0.2, cx + 1.4, c0 + 0.9), Color(0.75, 0.9, 1.0, 0.18))
			cx += 3.6
			ci += 1
		var cells := PackedVector2Array()
		var gx2 := xa + 1.2
		while gx2 < xb - 4.0:
			cells.append_array([m(gx2 + 1.65, yc - t + 0.9), m(gx2 + 1.65, yc + t - 0.9)])
			gx2 += 3.6
		lines(D, cells, Color(0.45, 0.7, 1.0, 0.35), 1.0)
		fill(D, A.rect_m(xa + 0.6, yc - 0.35, xb - 0.6, yc + 0.35), Color("C9D2DC"))
		# hazard tip + amber light at the free end, cyan gate lights across the gap
		var tip_x := xb if side > 0 else xa
		var dirx := 1.0 if side > 0 else -1.0
		hazard(D, A.rect_m(tip_x - dirx * 3.5, yc - t + 0.6, tip_x - dirx * 0.6, yc + t - 0.6), 0.8)
		beacon(m(tip_x - dirx * 2.0, yc), A.AMBER, 110.0, 0.15 * i)
		var gx0 := tip_x
		var gx1 := side * hw
		for j in 4:
			var gx := lerpf(gx0, gx1, (j + 0.5) / 4.0)
			lamp(m(gx, yc), A.CYAN, 34.0, 0)
	# --- overhead power bus down the middle + junction boxes
	truss(m(0, y0 - 2), m(0, y1 + 2), 6.0)
	for yc in rows_m:
		overhead(A.rect_m(-5, yc - 4, 5, yc + 4), Color(0.85, 0.9, 0.95, 0.65))
		lamp(m(0, yc), A.CYAN, 50.0, 2)
	# --- comms mast at the entry (colliding) with a dish
	var mast_c := m(-55, y0 - 22)
	hull(A.circle_poly(mast_c, 9.0 * PX, 28), &"pearl", [], {"bevel": 0.8})
	fill(D, A.circle_poly(mast_c, 7.0 * PX, 28), Color("D8DFE7"))
	for a in 8:
		var d := Vector2(cos(a * TAU / 8.0), sin(a * TAU / 8.0))
		seam(D, mast_c + d * 15.0, mast_c + d * 66.0)
	fill(D, A.circle_poly(mast_c, 1.8 * PX, 12), A.NAVY)
	hull(A.rect_poly(Rect2(mast_c + Vector2(80, -20), Vector2(70, 40))), &"grey", [], {"bevel": 0.4})
	beacon(mast_c, A.NAV_RED, 150.0, 0.0)
	beacon(mast_c + Vector2(115, 0), Color.WHITE, 90.0, 0.4, true)
	truss(mast_c, m(-hw + 3, y0 - 22), 3.0, Color(0.86, 0.9, 0.95, 0.7), false)
