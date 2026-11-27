@tool
extends StationModule
## Vesper's docking spar: a pier standing off the rock's north rim, parallel
## to the frigate lane. Its north face is the wall Frigate Berth V1 clamps
## onto (the FrigateBerth module adds the pylons and the gangway housing; the
## gangway interior attaches to this hull). A pressurised trunk runs from the
## pier back to HAB A, two buttresses foot it on the rock and two overhead
## trusses brace its ends.
##
## Also lays the lane lights: frigates drop out of their jump 560 m west of
## the berth heading east, so the berth axis (y = 0) is kept open from one
## side of the sector to the other and lined with below-deck buoys whose
## flashes run inbound.
## Local origin = Vesper's origin = the berth's capture position, metres.

## The berth wall: the pier's north face (= the berth's pier_dist_m).
const WALL_Y := 71.0
const PIER_DEPTH := 24.0
const PIER_HALF := 110.0
## Trunk to HAB A: half width and where it ends (inside the habitat's wall).
const TRUNK_HALF := 6.0
const TRUNK_TO := 165.0
## Buttresses down onto the rock: x of the centre line, y of the foot (m).
const BUTTRESSES := [[-72.0, 118.0], [72.0, 148.0]]
## Overhead braces: pier end to an anchor on the rock (m).
const BRACES := [[Vector2(-104, 91), Vector2(-150, 152)], [Vector2(104, 91), Vector2(90, 174)]]
## Lane lights: rows this far either side of the axis, from/to |x| (m).
const LANE_HALF := 56.0
const LANE_FROM := 140.0
const LANE_TO := 500.0
const LANE_STEP := 40.0


func _build() -> void:
	var D := Band.STRUCT_DETAIL
	var y0 := WALL_Y
	var y1 := WALL_Y + PIER_DEPTH
	var pier := A.rounded_rect(Rect2(m(-PIER_HALF, y0), m(PIER_HALF * 2.0, PIER_DEPTH)), 10.0 * PX, 6)
	var trunk := A.rect_m(-TRUNK_HALF, y1 - 2.0, TRUNK_HALF, TRUNK_TO)
	var convex: Array = [trunk, A.rect_m(-PIER_HALF + 10, y0, PIER_HALF - 10, y1),
		A.rect_m(-PIER_HALF, y0 + 2, -PIER_HALF + 10, y1 - 2), A.rect_m(PIER_HALF - 10, y0 + 2, PIER_HALF, y1 - 2)]
	var shape := union(pier, trunk)
	for b: Array in BUTTRESSES:
		var foot := A.rect_m(b[0] - 5.0, y1 - 2.0, b[0] + 5.0, b[1])
		convex.append(foot)
		shape = union(shape, foot)
	hull(shape, &"pearl", convex, {"bevel": 1.0})
	radar_polys.append(A.rect_m(-PIER_HALF, y0, PIER_HALF, y1))
	radar_polys.append(trunk)
	# --- trunk: window strips, navy spine, ring frames
	for sx: float in [-1.0, 1.0]:
		windows(D, PackedVector2Array([m(sx * (TRUNK_HALF - 1.9), y1 + 3), m(sx * (TRUNK_HALF - 1.9), TRUNK_TO - 4)]), 1.5, 1.2, 41 + int(sx))
	fill(D, A.rect_m(-0.7, y1 + 3, 0.7, TRUNK_TO - 4), A.NAVY)
	var pairs := PackedVector2Array()
	var y := y1 + 10.0
	while y < TRUNK_TO - 4.0:
		pairs.append_array([m(-TRUNK_HALF + 3.2, y), m(TRUNK_HALF - 3.2, y)])
		lamp(m(-TRUNK_HALF + 0.7, y), A.CYAN, 22.0)
		lamp(m(TRUNK_HALF - 0.7, y), A.CYAN, 22.0)
		y += 12.0
	# --- buttresses: plain structural legs with a hazard collar at the foot
	for b: Array in BUTTRESSES:
		fill(D, A.rect_m(b[0] - 1.0, y1 + 1.5, b[0] + 1.0, b[1] - 5.0), A.NAVY)
		hazard(D, A.rect_m(b[0] - 4.2, b[1] - 4.0, b[0] + 4.2, b[1] - 1.2), 0.8)
		lamp(m(b[0], b[1] - 2.6), A.AMBER, 30.0)
	# --- pier: window strips, accent bands, seams, name
	for seg in [[-PIER_HALF + 13.0, -14.0], [14.0, PIER_HALF - 13.0]]:
		windows(D, PackedVector2Array([m(seg[0], y0 + 2.3), m(seg[1], y0 + 2.3)]), 1.7, 1.3, int(seg[0]) + 3)
		windows(D, PackedVector2Array([m(seg[0], y1 - 2.3), m(seg[1], y1 - 2.3)]), 1.7, 1.3, int(seg[1]) + 9)
		fill(D, A.rect_m(seg[0], y0 + 15.6, seg[1], y0 + 18.0), A.TEAL)
		fill(D, A.rect_m(seg[0], y0 + 18.8, seg[1], y0 + 19.6), A.NAVY)
	var x := -PIER_HALF + 18.0
	while x < PIER_HALF - 14.0:
		if absf(x) > 16.0:
			pairs.append_array([m(x, y0 + 4.2), m(x, y1 - 4.2)])
		x += 9.0
	seams(D, pairs)
	text(D, m(-60, y0 + 9.6), "VESPER ROCK  ·  BERTH V1", 50, A.NAVY)
	text(D, m(62, y0 + 9.6), "FRIGATE SPAR", 50, A.NAVY)
	# --- junction cabin: the berth master's cupola where the trunk meets the pier
	var c := m(0, (y0 + y1) * 0.5)
	fill(D, A.circle_poly(c, 10.5 * PX, 8, PI / 8.0), A.NAVY)
	fill(D, A.circle_poly(c, 9.2 * PX, 8, PI / 8.0), Color("E3E9EF"))
	fill(D, A.circle_poly(c, 6.2 * PX, 28), Color("1F4B60"))
	fill(D, A.circle_poly(c + Vector2(-9, -11), 4.6 * PX, 24), Color("2A6680"))
	outline(D, A.circle_poly(c, 6.2 * PX, 28), Color(0.9, 0.97, 1.0, 0.9), 2.2)
	glow(c, Color(0.5, 0.9, 1.0, 0.3), 170.0)
	# --- edge lights, tip beacons, braces
	var xl := -PIER_HALF + 14.0
	while xl < PIER_HALF - 10.0:
		lamp(m(xl, y0 + 0.9), A.CYAN, 26.0)
		lamp(m(xl, y1 - 0.9), A.CYAN, 26.0)
		xl += 16.0
	for s: float in [-1.0, 1.0]:
		# a ship inbound from the west has the pier to starboard: green
		beacon(m(s * (PIER_HALF - 5), y0 + 4), A.NAV_GREEN, 110.0, 0.0)
		beacon(m(s * (PIER_HALF - 5), y1 - 4), A.NAV_RED, 110.0, 0.5)
		beacon(m(s * (PIER_HALF - 8), (y0 + y1) * 0.5), Color.WHITE, 150.0, 0.3 + 0.2 * s, true)
	for b: Array in BRACES:
		truss((b[0] as Vector2) * PX, (b[1] as Vector2) * PX, 5.0)
	_lane_lights()


## Lane lights. West is the way in (a ship heading east keeps green to
## starboard, red to port); the way out to the east is marked amber.
## Flashes run toward the berth.
func _lane_lights() -> void:
	var count := int((LANE_TO - LANE_FROM) / LANE_STEP) + 1
	for end: float in [-1.0, 1.0]:
		for i in count:
			var d := LANE_FROM + LANE_STEP * i
			for side: float in [-1.0, 1.0]:
				var p := m(end * d, side * LANE_HALF)
				var col := A.AMBER
				if end < 0.0:
					col = A.NAV_GREEN if side > 0.0 else A.NAV_RED
				fill_circle(Band.DECK, p, 11.0, Color("2C3A4E"), 10)
				outline(Band.DECK, A.circle_poly(p, 11.0, 10), Color(0.42, 0.5, 0.6, 0.9), 1.4)
				fill_circle(Band.DECK, p, 4.0, col.darkened(0.2), 8)
				beacon(p, col, 85.0, 1.0 - float(i) / float(count), false, 0)
