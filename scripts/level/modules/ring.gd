@tool
extends StationModule
## The Meridian Ring: a slowly rotating habitat ring made of arcs separated by
## flyable gaps. The whole ring is ONE AnimatableBody2D; overhead spokes, gap
## bridges and the bearing collar ride on it. Passing through a gap while it
## turns is the timing challenge at the centre of the level.

@export var outer_radius_m := 240.0:
	set(v): outer_radius_m = v; queue_rebuild()
@export var thickness_m := 35.0:
	set(v): thickness_m = v; queue_rebuild()
@export var gap_m := 45.0:
	set(v): gap_m = v; queue_rebuild()
@export_range(2, 8) var gap_count := 4:
	set(v): gap_count = v; queue_rebuild()
## Radians per second (positive = clockwise on screen).
@export var spin := 0.026
## Radius where the overhead spokes meet the bearing collar.
@export var collar_radius_m := 54.0:
	set(v): collar_radius_m = v; queue_rebuild()

const SECTORS := ["SECTOR A  ·  CONCORDIA", "SECTOR B  ·  HALCYON", "SECTOR C  ·  LUMEN", "SECTOR D  ·  VERANDA"]


func _build() -> void:
	moving = true
	var R := outer_radius_m * PX
	var Ri := (outer_radius_m - thickness_m) * PX
	var h := gap_m * 0.5 * PX
	var c := Vector2.ZERO
	var n := gap_count
	for k in n:
		var g0 := TAU * float(k) / n
		var g1 := TAU * float(k + 1) / n
		var ao0 := g0 + asin(h / R)
		var ao1 := g1 - asin(h / R)
		var ai0 := g0 + asin(h / Ri)
		var ai1 := g1 - asin(h / Ri)
		# --- visual outline (fine) and collision quads (coarser, exact convex)
		var poly := PackedVector2Array()
		var fine := 110
		for i in fine + 1:
			var a := lerpf(ao0, ao1, float(i) / fine)
			poly.append(c + Vector2(cos(a), sin(a)) * R)
		for i in range(fine, -1, -1):
			var a := lerpf(ai0, ai1, float(i) / fine)
			poly.append(c + Vector2(cos(a), sin(a)) * Ri)
		var quads: Array = []
		var N := 30
		for i in N:
			var t0 := float(i) / N
			var t1 := float(i + 1) / N
			var o0 := lerpf(ao0, ao1, t0)
			var o1 := lerpf(ao0, ao1, t1)
			var i0 := lerpf(ai0, ai1, t0)
			var i1 := lerpf(ai0, ai1, t1)
			quads.append(PackedVector2Array([
				Vector2(cos(o0), sin(o0)) * R, Vector2(cos(o1), sin(o1)) * R,
				Vector2(cos(i1), sin(i1)) * Ri, Vector2(cos(i0), sin(i0)) * Ri]))
		hull(poly, &"pearl", quads, {"lit": false, "bevel": 1.1})
		# simplified radar outline
		radar_polys.append(A.arc_band(c, Ri, R, ao0, ao1, 16))
		_detail_arc(k, R, Ri, g0, g1)
		# --- overhead bridge across the gap that FOLLOWS this arc (at g1)
		var axis := Vector2(cos(g1), sin(g1))
		var perp := axis.orthogonal()
		var rb := (outer_radius_m - thickness_m * 0.45) * PX
		truss(axis * rb - perp * (h + 60), axis * rb + perp * (h + 60), 7.0)
		# thin utility conduit near the outer rim, also overhead
		var rc := (outer_radius_m - 4.0) * PX
		overhead(A.obox(axis * rc, perp, h * 2.0 + 120, 1.6 * PX), Color(0.8, 0.86, 0.92, 0.38))
		# --- spoke at the middle of this arc (overhead)
		var sa := (g0 + g1) * 0.5
		var sd := Vector2(cos(sa), sin(sa))
		var r0 := collar_radius_m * PX
		var r1 := Ri + 40.0
		truss(sd * r0, sd * r1, 9.0, Color(0.88, 0.92, 0.97, 0.6), false)
		overhead(A.obox(sd * (r0 + r1) * 0.5, sd, r1 - r0, 3.2 * PX), Color(0.9, 0.94, 0.98, 0.5), Color(0.6, 0.95, 1.0, 0.6))
		var steps := 6
		for i in steps:
			lamp(sd * lerpf(r0 + 60, r1 - 60, float(i) / (steps - 1)), A.CYAN, 40.0, 2)
		# elevator car riding the spoke (static decoration)
		var car := sd * lerpf(r0, r1, 0.3 + 0.4 * A.hash01(k, 7))
		overhead(A.obox(car, sd, 6.0 * PX, 4.2 * PX), Color(0.98, 0.9, 0.7, 0.85), Color(1, 1, 1, 0.9))
		lamp(car, A.WARM, 70.0, 2)
	# --- bearing collar (overhead ring that the spokes hang from)
	var cr0 := (collar_radius_m - 4.0) * PX
	var cr1 := (collar_radius_m + 4.0) * PX
	var collar := A.arc_band(c, cr0, cr1, 0.0, TAU, 96)
	fill(Band.OVER_SHADOW, collar, A.OVER_SHADOW)
	fill(Band.OVER, collar, Color(0.82, 0.87, 0.93, 0.62))
	arc(Band.OVER, c, cr1, 0, TAU, Color(1, 1, 1, 0.75), 2.5, 96)
	arc(Band.OVER, c, cr0, 0, TAU, Color(0.55, 0.65, 0.75, 0.75), 2.0, 96)
	for i in 24:
		var a := TAU * i / 24.0
		lamp(Vector2(cos(a), sin(a)) * (cr0 + cr1) * 0.5, A.CYAN if i % 2 == 0 else A.WARM, 30.0, 2)


## Roof art of one habitat arc: window strips, structural bands, a glazed
## park strip with trees, accent stripe, bulkhead end caps, beacons, names.
func _detail_arc(k: int, R: float, Ri: float, g0: float, g1: float) -> void:
	var D := Band.STRUCT_DETAIL
	var h := gap_m * 0.5 * PX
	var cap := 7.0 * PX   # bulkhead end-cap depth
	var c := Vector2.ZERO
	var ang := func(r: float, start: bool) -> float:
		var off := asin(clampf((h + cap) / r, -1.0, 1.0))
		return g0 + off if start else g1 - off
	var rm := func(m_: float) -> float: return (outer_radius_m - thickness_m + m_) * PX
	# Inner and outer window strips.
	for spec in [[2.6, 2.2], [thickness_m - 2.6, 2.2]]:
		var r: float = rm.call(spec[0])
		windows(D, A.arc_points(c, r, ang.call(r, true), ang.call(r, false), 120), spec[1], 1.5, k * 13 + int(spec[0]))
	# Structural band seams (radial) between inner windows and the park.
	var pairs := PackedVector2Array()
	var r_a: float = rm.call(5.0)
	var r_b: float = rm.call(12.0)
	var r_c: float = rm.call(25.5)
	var r_d: float = rm.call(31.0)
	var a0: float = ang.call(r_b, true)
	var a1: float = ang.call(r_b, false)
	var nseg := int((a1 - a0) / deg_to_rad(2.5))
	for i in nseg + 1:
		var a := lerpf(a0, a1, float(i) / nseg)
		var d := Vector2(cos(a), sin(a))
		pairs.append_array([d * r_a, d * r_b, d * r_c, d * r_d])
	seams(D, pairs)
	arc(D, c, r_a, a0, a1, Color(0.55, 0.62, 0.7, 0.7), 1.5, 90)
	arc(D, c, r_d, a0, a1, Color(0.55, 0.62, 0.7, 0.7), 1.5, 90)
	# Teal accent band near the outer rim + navy pinstripe.
	var t0: float = rm.call(27.0)
	var t1: float = rm.call(29.4)
	fill(D, A.arc_band(c, t0, t1, ang.call(t1, true), ang.call(t1, false), 90), A.TEAL)
	arc(D, c, rm.call(30.2), ang.call(t1, true), ang.call(t1, false), A.NAVY, 3.0, 90)
	# Glazed park strip.
	var p0: float = rm.call(13.5)
	var p1: float = rm.call(24.0)
	var pa0: float = ang.call(p1, true) + 0.01
	var pa1: float = ang.call(p1, false) - 0.01
	var park := A.arc_band(c, p0, p1, pa0, pa1, 90)
	fill(D, park, Color("1C4536"))
	fill(D, A.arc_band(c, p0 + 8, p1 - 8, pa0 + 0.004, pa1 - 0.004, 90), Color("24573F"))
	# meandering path
	var path := PackedVector2Array()
	var pn := 140
	for i in pn + 1:
		var a := lerpf(pa0 + 0.01, pa1 - 0.01, float(i) / pn)
		var r := lerpf(p0, p1, 0.5 + 0.28 * sin(a * 47.0 + k))
		path.append(Vector2(cos(a), sin(a)) * r)
	polyline(D, path, Color("D9CBA3"), 7.0)
	# ponds
	for j in 3:
		var a := lerpf(pa0, pa1, 0.2 + 0.3 * j + 0.05 * A.hash01(j, k))
		var r := lerpf(p0, p1, 0.5 - 0.28 * sin(a * 47.0 + k))
		fill(D, A.circle_poly(Vector2(cos(a), sin(a)) * r, 16.0 + 10.0 * A.hash01(j, k + 3), 18), Color("2E6E8E"))
	# trees (deterministic scatter)
	var tree_cols := [Color("2F7A55"), Color("3E9A63"), Color("276B4A"), Color("5BB07A"), Color("8CC084")]
	var ntrees := int((pa1 - pa0) * p1 / 26.0)
	for i in ntrees:
		var a := lerpf(pa0, pa1, A.hash01(i, 101 + k))
		var r := lerpf(p0 + 10, p1 - 10, A.hash01(i, 202 + k))
		var pos := Vector2(cos(a), sin(a)) * r
		var pr := lerpf(p0, p1, 0.5 + 0.28 * sin(a * 47.0 + k))
		if absf(r - pr) < 12.0:
			continue
		var rad := 6.0 + 12.0 * A.hash01(i, 303 + k)
		var col: Color = tree_cols[i % tree_cols.size()]
		fill(D, A.circle_poly(pos + Vector2(2.5, 3.5), rad, 10), Color(0.05, 0.15, 0.1, 0.6))
		fill(D, A.circle_poly(pos, rad, 10), col)
		fill(D, A.circle_poly(pos - Vector2(rad, rad) * 0.25, rad * 0.45, 8), col.lightened(0.25))
	# glazing mullions + sheen
	var mull := PackedVector2Array()
	var nm := int((pa1 - pa0) / deg_to_rad(1.1))
	for i in nm + 1:
		var a := lerpf(pa0, pa1, float(i) / nm)
		var d := Vector2(cos(a), sin(a))
		mull.append_array([d * p0, d * p1])
	lines(D, mull, Color(0.85, 0.95, 1.0, 0.28), 1.5)
	fill(D, A.arc_band(c, p1 - 24, p1 - 14, pa0, pa1, 90), Color(1, 1, 1, 0.07))
	arc(D, c, p0, pa0, pa1, Color(0.9, 0.97, 1.0, 0.85), 2.5, 90)
	arc(D, c, p1, pa0, pa1, Color(0.9, 0.97, 1.0, 0.85), 2.5, 90)
	# warm path lamps + faint green glow of the park
	var nl := int((pa1 - pa0) * (p0 + p1) * 0.5 / 140.0)
	for i in nl:
		var a := lerpf(pa0, pa1, (i + 0.5) / nl)
		var r := lerpf(p0, p1, 0.5 + 0.28 * sin(a * 47.0 + k))
		glow(Vector2(cos(a), sin(a)) * r, Color(1.0, 0.85, 0.55, 0.55), 26.0)
	polyline(Band.STRUCT_FX, A.arc_points(c, (p0 + p1) * 0.5, pa0, pa1, 90), Color(0.3, 0.9, 0.5, 0.05), p1 - p0 + 40.0)
	# Bulkhead end caps (navy) with hazard edge facing the gap.
	for start: bool in [true, false]:
		var g: float = g0 if start else g1
		var axis := Vector2(cos(g), sin(g))
		var perp := axis.orthogonal() * (1.0 if start else -1.0)
		var ri := Ri + 3.0
		var ro := R - 3.0
		var e_in := axis * sqrt(ri * ri - h * h) + perp * h
		var e_out := axis * sqrt(ro * ro - h * h) + perp * h
		var cap_poly := PackedVector2Array([e_in + perp * 14, e_out + perp * 14, e_out + perp * cap, e_in + perp * cap])
		fill(D, cap_poly, A.NAVY)
		outline(D, cap_poly, Color(0.6, 0.75, 0.95, 0.6), 1.5)
		hazard(D, PackedVector2Array([e_in + perp * 3, e_out + perp * 3, e_out + perp * 12, e_in + perp * 12]), 1.2, (g + PI * 0.25))
		# docking-light chevrons along the cap
		for j in 4:
			var p := e_in.lerp(e_out, (j + 0.5) / 4.0) + perp * (cap * 0.6)
			lamp(p, A.CYAN, 30.0)
		# nav beacons flanking the gap: red on the leading edge, green trailing
		var col := A.NAV_RED if start else A.NAV_GREEN
		beacon(e_out + perp * 8 - axis * 6, col, 120.0, 0.25 * k + (0.0 if start else 0.5))
		beacon(e_in + perp * 8 + axis * 6, col, 90.0, 0.25 * k + (0.1 if start else 0.6))
	# white strobe mid-arc on the rim
	var mid := (g0 + g1) * 0.5
	beacon(Vector2(cos(mid), sin(mid)) * (R - 18), Color(1, 1, 1), 150.0, 0.13 * k, true)
	# cyan rim lights (outer edge), sparse
	var nr := 20
	for i in nr:
		var a := lerpf(ang.call(R, true), ang.call(R, false), (i + 0.5) / nr)
		lamp(Vector2(cos(a), sin(a)) * (R - 9), A.CYAN, 26.0)
	# Names painted on the structural band.
	var r_txt: float = rm.call(8.6)
	arc_text(D, c, r_txt, (g0 + g1) * 0.5 - 0.22, "MERIDIAN", 54, A.NAVY)
	arc_text(D, c, r_txt, (g0 + g1) * 0.5 + 0.26, SECTORS[k % SECTORS.size()], 34, Color("4A5A70"))


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or body == null:
		return
	(body as Node2D).rotation = wrapf((body as Node2D).rotation + spin * delta, -PI, PI)
