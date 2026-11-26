@tool
extends StationModule
## Propellant depot: spherical cryo tanks (colliding) on a service deck,
## joined by overhead pipe runs. Local origin = depot centre, metres.

## x, y, radius (m), label
const TANKS := [
	[-42.0, -18.0, 26.0, "LH2 · 01"],
	[22.0, -38.0, 19.0, "LOX · 02"],
	[16.0, 24.0, 22.0, "LH2 · 03"],
	[-38.0, 44.0, 15.0, "N2 · 04"],
	[60.0, 6.0, 13.0, "LOX · 05"],
]


func _build() -> void:
	deck(A.rounded_rect(Rect2(m(-80, -70), m(160, 135)), 140.0), 6.0)
	hazard(Band.DECK, A.rect_m(-80, 60, 80, 64), 1.2)
	text(Band.DECK, m(0, 55), "PROPELLANT DEPOT  ·  NO HOT WORK", 40, Color(1.0, 0.75, 0.3, 0.5))
	var D := Band.STRUCT_DETAIL
	# pipes overhead between tank centres (drawn first, under tank glows)
	for i in TANKS.size() - 1:
		var a: Array = TANKS[i]
		var b: Array = TANKS[i + 1]
		var pa := m(a[0], a[1])
		var pb := m(b[0], b[1])
		var dir := (pb - pa).normalized()
		overhead(A.obox((pa + pb) * 0.5, dir, pa.distance_to(pb), 2.6 * PX), Color(0.92, 0.82, 0.55, 0.55), Color(1, 0.95, 0.75, 0.7))
	for t in TANKS:
		var c := m(t[0], t[1])
		var r: float = t[2] * PX
		var col := &"teal" if String(t[3]).begins_with("LOX") else &"pearl"
		hull(A.circle_poly(c, r, 40), col, [], {"bevel": 1.2})
		# latitude rings + meridians give a spherical read
		for k: float in [0.78, 0.5]:
			arc(D, c, r * k, 0, TAU, Color(0.4, 0.5, 0.6, 0.5), 1.6, 48)
		for k in 6:
			var ang := TAU * k / 6.0
			seam(D, c + Vector2(cos(ang), sin(ang)) * r * 0.5, c + Vector2(cos(ang), sin(ang)) * (r - 12.0))
		fill(D, A.circle_poly(c - Vector2(r, r) * 0.28, r * 0.32, 24), Color(1, 1, 1, 0.22))
		fill(D, A.arc_band(c, r * 0.18, r * 0.27, 0, TAU, 32), A.AMBER)
		text(D, c + Vector2(0, r * 0.62), t[3], int(clampf(r * 0.16, 18, 40)), A.NAVY)
		beacon(c + Vector2(r * 0.7, -r * 0.7), A.NAV_RED, 90.0, A.hash01(int(t[0]), 1))
		lamp(c, A.WARM, 50.0)
