@tool
extends StationModule
## The despun central hub: static, round, with four docking notches. The ring
## spins around it; the overhead bearing collar sits just outside its rim.

@export var radius_m := 45.0:
	set(v): radius_m = v; queue_rebuild()
@export var notch_width_m := 16.0:
	set(v): notch_width_m = v; queue_rebuild()
@export var notch_depth_m := 13.0:
	set(v): notch_depth_m = v; queue_rebuild()


func _build() -> void:
	var R := radius_m * PX
	var nw := notch_width_m * PX
	var nd := notch_depth_m * PX
	var circle := A.circle_poly(Vector2.ZERO, R, 72)
	var shape := circle
	for k in 4:
		var a := PI * 0.5 * k
		var d := Vector2(cos(a), sin(a))
		var notch := A.obox(d * (R - nd * 0.5 + 40), d, nd + 80, nw)
		var clipped := Geometry2D.clip_polygons(shape, notch)
		if not clipped.is_empty():
			shape = clipped[0]
			for p in clipped:
				if p.size() > shape.size():
					shape = p
	# Collision: 4 quarter pieces built explicitly as convex fans (robust).
	var convex: Array = []
	var half_w_ang := asin((nw * 0.5) / R)
	for k in 4:
		# Convex quarter: inner corner + rim arc between two notches.
		var q := PackedVector2Array([Vector2(nw * 0.5, nw * 0.5)])
		var a0 := half_w_ang
		var a1 := PI * 0.5 - half_w_ang
		for i in 13:
			var b := lerpf(a0, a1, float(i) / 12.0)
			q.append(Vector2(cos(b), sin(b)) * R)
		convex.append(Transform2D(PI * 0.5 * k, Vector2.ZERO) * q)
	# Inner core between the notch floors (square-ish, convex).
	var core := R - nd
	convex.append(PackedVector2Array([Vector2(core, -nw * 0.5), Vector2(core, nw * 0.5), Vector2(-core, nw * 0.5), Vector2(-core, -nw * 0.5)]))
	convex.append(PackedVector2Array([Vector2(-nw * 0.5, -core), Vector2(nw * 0.5, -core), Vector2(nw * 0.5, core), Vector2(-nw * 0.5, core)]))
	hull(shape, &"pearl", convex, {"lit": true, "bevel": 1.2})
	radar_polys.append(A.circle_poly(Vector2.ZERO, R, 20))
	var D := Band.STRUCT_DETAIL
	# Concentric rings.
	fill(D, A.arc_band(Vector2.ZERO, R * 0.66, R * 0.71, 0, TAU, 72), A.NAVY)
	fill(D, A.arc_band(Vector2.ZERO, R * 0.5, R * 0.52, 0, TAU, 72), A.TEAL)
	# Radial seams between notches.
	var pairs := PackedVector2Array()
	for i in 32:
		var a := TAU * i / 32.0 + 0.05
		var d := Vector2(cos(a), sin(a))
		pairs.append_array([d * R * 0.73, d * (R - 14.0)])
	seams(D, pairs)
	# Central glass dome with reflections.
	var dome := A.circle_poly(Vector2.ZERO, R * 0.42, 48)
	fill(D, dome, Color("214E63"))
	fill(D, A.circle_poly(Vector2(-12, -14), R * 0.36, 40), Color("2B6680"))
	fill(D, A.circle_poly(Vector2(-40, -48), R * 0.16, 24), Color(1, 1, 1, 0.16))
	outline(D, dome, Color(0.9, 0.97, 1.0, 0.9), 3.0)
	var mull := PackedVector2Array()
	for i in 12:
		var a := TAU * i / 12.0
		mull.append_array([Vector2.ZERO, Vector2(cos(a), sin(a)) * R * 0.42])
	lines(D, mull, Color(0.85, 0.95, 1.0, 0.25), 1.5)
	glow(Vector2.ZERO, Color(0.4, 0.85, 1.0, 0.25), R * 0.6)
	arc_text(D, Vector2.ZERO, R * 0.6, -PI * 0.5 - 0.62, "MERIDIAN", 40, A.NAVY)
	arc_text(D, Vector2.ZERO, R * 0.6, -PI * 0.5 + 0.62, "HUB CONTROL", 30, Color("4A5A70"))
	arc_text(D, Vector2.ZERO, R * 0.6, PI * 0.5 - 0.62, "PORT AUTHORITY", 30, Color("4A5A70"))
	arc_text(D, Vector2.ZERO, R * 0.6, PI * 0.5 + 0.62, "EST. 2291", 30, Color("4A5A70"))
	# Notch floors (below deck) with hazard thresholds and lights.
	for k in 4:
		var a := PI * 0.5 * k
		var d := Vector2(cos(a), sin(a))
		var pp := d.orthogonal()
		var floor_poly := A.obox(d * (R - nd * 0.5 + 10), d, nd + 40, nw + 60)
		deck(floor_poly, 3.0)
		hazard(Band.DECK, A.obox(d * (R - 12.0), d, 18.0, nw - 20.0), 1.0, a + PI * 0.25)
		for s: float in [-1.0, 1.0]:
			lamp(d * (R - nd * 0.5) + pp * s * (nw * 0.5 - 14.0), A.AMBER, 34.0, 1)
		lamp(d * (R - nd + 12.0), A.CYAN, 50.0, 1)
		text(D, d * (R - nd - 40.0), "BAY %d" % (k + 1), 26, A.NAVY, a + PI * 0.5)
	# Rim lights + 4 white strobes.
	for i in 36:
		var a := TAU * i / 36.0
		var d := Vector2(cos(a), sin(a))
		var bad := false
		for k in 4:
			if absf(angle_difference(a, PI * 0.5 * k)) < half_w_ang + 0.07:
				bad = true
		if not bad:
			lamp(d * (R - 9.0), A.CYAN if i % 3 else A.WARM, 24.0)
	for k in 4:
		var a := PI * 0.25 + PI * 0.5 * k
		beacon(Vector2(cos(a), sin(a)) * (R - 20.0), Color.WHITE, 120.0, 0.25 * k, true)
