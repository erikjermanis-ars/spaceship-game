@tool
extends StationModule
## Vesper's landing apron: the deck in the terrace cut into the rock's south
## face. Two docking pads (separate docking_pad.gd nodes) stand on it, the
## ore hoppers sit against the back wall under the screen-house belt, and a
## 30 m x 20 m patch east of the pads is kept clear for the freight intake.
##
## The deck is tucked under the rock on three sides (clipped to the rock's
## uncut outline), so the below-deck parallax never opens a gap at the walls.
## Local origin = the Base node (shared with VesperRock), metres.

const Rock := preload("res://scripts/level/modules/rock_base.gd")
const R := preload("res://scripts/level/rock_art.gd")

## Outer (south) edge of the deck, and how far it reaches under the rock.
const SOUTH_M := 142.0
const TUCK := Rect2(-186, 28, 264, 114)
## Kept free of props for the freight intake (m).
const FREIGHT_SLOT := Rect2(-3, 90, 30, 20)
## Ore hoppers against the back wall: x of each west edge (m).
const HOPPERS := [12.0, 24.0, 36.0]
const HOPPER := Rect2(0, 55, 9, 14)


## The deck polygon (px): the terrace cut plus the strip tucked under the rock.
static func deck_poly() -> PackedVector2Array:
	var under := PackedVector2Array()
	for inset in Geometry2D.offset_polygon(Rock.raw_outline(), -6.0 * PX):
		for p in Geometry2D.intersect_polygons(inset, A.rect_poly(Rect2(TUCK.position * PX, TUCK.size * PX))):
			if R.area(p) > R.area(under):
				under = p
	var open := A.rect_m(-400, 0, 400, SOUTH_M)
	for p in Geometry2D.intersect_polygons(Rock.terrace(), open):
		open = p
	return union(under, open)


func _build() -> void:
	deck(deck_poly(), 6.0)
	var K := Band.DECK
	# lip: hazard strip and edge lights along the open south side
	hazard(K, A.rect_m(-161, SOUTH_M - 3.4, 51, SOUTH_M - 1.0), 1.2)
	var n := 17
	for i in n:
		lamp(m(lerpf(-160, 50, (i + 0.5) / n), SOUTH_M + 0.8), A.CYAN, 28.0, 0)
	for x: float in [-164.0, 54.0]:
		lamp(m(x, SOUTH_M - 2.0), A.AMBER, 44.0, 0)
	# floodlight pools from the masts on the terrace lip
	for x: float in [-150.0, -100.0, -50.0, 0.0, 42.0]:
		glow(m(x, 60), Color(1.0, 0.9, 0.7, 0.13), 360.0, Band.DECK_FX)
	# lead-out lines from the pads, apron name
	for x: float in [-120.0, -48.0]:
		line(K, m(x, 127), m(x, SOUTH_M - 4.5), Color(0.92, 0.95, 1.0, 0.35), 3.0)
	text(K, m(12, 124), "VESPER ROCK  ·  LANDING APRON", 30, Color(0.8, 0.88, 1.0, 0.45))
	text(K, m(28, 78.5), "ORE HOPPERS  ·  KEEP CLEAR OF CHUTES", 15, Color(1.0, 0.75, 0.3, 0.6))
	line(K, m(8, 76.0), m(48, 76.0), Color(1.0, 0.69, 0.0, 0.45), 2.0)
	_hoppers()


func _hoppers() -> void:
	var D := Band.STRUCT_DETAIL
	var y0 := HOPPER.position.y
	var y1 := HOPPER.end.y
	for i in HOPPERS.size():
		var x: float = HOPPERS[i]
		var box := A.rect_m(x, y0, x + HOPPER.size.x, y1)
		hull(box, &"steel", [box], {"bevel": 0.6})
		# open bin: dark funnel, ore in it
		fill(D, A.rect_m(x + 1.2, y0 + 1.2, x + 7.8, y1 - 3.4), Color("1B2028"))
		fill(D, PackedVector2Array([m(x + 1.2, y0 + 1.2), m(x + 7.8, y0 + 1.2), m(x + 6.0, y0 + 5.0), m(x + 3.0, y0 + 5.0)]), Color("2B313B"))
		for k in 6:
			var p := m(x + 2.4 + 4.2 * A.hash01(k, i + 70), y0 + 5.6 + 4.0 * A.hash01(k, i + 71))
			var s := 5.0 + 5.0 * A.hash01(k, i + 72)
			var col := Color("5D5F6A").lerp(Color("45DCC6"), 0.55 if A.hash01(k, i + 73) > 0.6 else 0.0)
			fill(D, PackedVector2Array([p + Vector2(-s, 0), p + Vector2(0, -s), p + Vector2(s, 0), p + Vector2(0, s)]), col)
		outline(D, A.rect_m(x + 1.2, y0 + 1.2, x + 7.8, y1 - 3.4), Color(0.9, 0.93, 0.97, 0.6), 1.4)
		hazard(D, A.rect_m(x + 0.6, y1 - 2.6, x + 8.4, y1 - 0.6), 0.8)
		text(Band.DECK, m(x + 4.5, y1 + 4.2), "H%d" % (i + 1), 20, Color(0.8, 0.88, 1.0, 0.5))
		lamp(m(x + 4.5, y1 - 0.2), A.AMBER, 30.0)
	# feed header over the bins (the screen-house belt drops onto it)
	var x0: float = HOPPERS[0]
	var x1: float = HOPPERS[HOPPERS.size() - 1] + HOPPER.size.x
	overhead(A.rect_m(x0 + 2.0, y0 + 3.0, x1 - 2.0, y0 + 6.0), Color(0.55, 0.6, 0.68, 0.8))
