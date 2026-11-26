@tool
extends StationModule
## Arboretum: glass domes full of trees joined by pearl transit tubes.
## Local origin = cluster centre, metres.

## x, y, r (m), name
const DOMES := [
	[-30.0, -10.0, 34.0, "ARBORETUM"],
	[42.0, -34.0, 24.0, "ORCHARD"],
	[36.0, 40.0, 21.0, "HYDROPONICS"],
]


func _build() -> void:
	var D := Band.STRUCT_DETAIL
	# connecting tubes (colliding)
	for i in range(1, DOMES.size()):
		var a := m(DOMES[0][0], DOMES[0][1])
		var b := m(DOMES[i][0], DOMES[i][1])
		var tube := A.obox((a + b) * 0.5, b - a, a.distance_to(b), 7.0 * PX)
		hull(tube, &"pearl", [], {"bevel": 0.6})
		windows(D, PackedVector2Array([a, b]), 1.6, 1.2, i)
	for d in DOMES:
		var c := m(d[0], d[1])
		var r: float = d[2] * PX
		var dome := A.circle_poly(c, r, 48)
		hull(dome, &"glass", [], {"bevel": 1.0})
		# inside: lawn, trees, path
		fill(D, A.circle_poly(c, r - 18.0, 44), Color("1F5240"))
		var n := int(r * r / 900.0)
		for i in n:
			var a := TAU * A.hash01(i, int(d[0]))
			var rr := sqrt(A.hash01(i, int(d[1]) + 9)) * (r - 34.0)
			var p := c + Vector2(cos(a), sin(a)) * rr
			var tr := 7.0 + 12.0 * A.hash01(i, 3)
			var col: Color = [Color("2F7A55"), Color("3E9A63"), Color("5BB07A"), Color("8CC084"), Color("D98E73")][i % 5]
			fill(D, A.circle_poly(p, tr, 10), col)
			fill(D, A.circle_poly(p - Vector2(tr, tr) * 0.25, tr * 0.45, 8), col.lightened(0.22))
		arc(D, c, r * 0.45, 0, TAU, Color("D9CBA3"), 5.0, 40)
		# glazing
		var mull := PackedVector2Array()
		for i in 16:
			var a := TAU * i / 16.0
			mull.append_array([c + Vector2(cos(a), sin(a)) * 10.0, c + Vector2(cos(a), sin(a)) * (r - 6.0)])
		lines(D, mull, Color(0.85, 0.97, 1.0, 0.3), 1.4)
		arc(D, c, r * 0.7, 0, TAU, Color(0.85, 0.97, 1.0, 0.25), 1.4, 40)
		fill(D, A.circle_poly(c - Vector2(r, r) * 0.33, r * 0.3, 24), Color(1, 1, 1, 0.13))
		glow(c, Color(0.5, 1.0, 0.6, 0.12), r * 1.6)
		text(D, c + Vector2(0, r + 30.0), d[3], int(clampf(r * 0.1, 20, 36)), Color(0.8, 0.9, 1.0, 0.8))
		beacon(c + Vector2(0, -r + 10.0), Color.WHITE, 90.0, A.hash01(int(d[0]), 2), true)
