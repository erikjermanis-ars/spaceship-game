@tool
extends Node2D
## What you see beyond the walls of an interior inside the spaceport pier:
## the pier's roof continuing north and south, and the landing-pad deck to the
## west (the ship is parked out there). East of the pier is open space: the
## game's SpaceBackground layer shows through.
##
## The interior is a cut-away of the real pier, placed at the pier's real
## world position, so the stars and planet outside line up with what you saw
## from the pad. Unshaded: this is sunlit outside, not part of the dark rooms.

@export var pier_width_m := 25.0
@export var pier_extent_m := 70.0     # how far the roof is drawn N and S
@export var interior_rect_m := Rect2(0, -15, 25, 30)
@export var deck_width_m := 40.0


## Batched painter used by the draw callbacks (see OnFootPainter).
var pen: OnFootPainter

func _ready() -> void:
	z_as_relative = false
	z_index = -8
	if not Engine.is_editor_hint():
		material = OnFootArt.unshaded()


func _draw() -> void:
	pen = OnFootPainter.new(self)
	_paint_draw()
	pen.flush()


func _paint_draw() -> void:
	var px := OnFootArt.PX
	var ir := Rect2(interior_rect_m.position * px, interior_rect_m.size * px)
	# --- pad deck to the west (dark deck plates, grid, hazard edge, lamps)
	var deck := Rect2(Vector2(-deck_width_m * px, ir.position.y - pier_extent_m * px), Vector2(deck_width_m * px, ir.size.y + pier_extent_m * 2.0 * px))
	pen.rect_flat(deck, Color("1B2431"))
	var g := 60.0
	var x := deck.end.x - g
	while x > deck.position.x:
		pen.line(Vector2(x, deck.position.y), Vector2(x, deck.end.y), Color("2C3A4E"), 0.6)
		x -= g
	var y := deck.position.y
	while y < deck.end.y:
		pen.line(Vector2(deck.position.x, y), Vector2(deck.end.x, y), Color("2C3A4E"), 0.6)
		y += g
	# the walkway lane leading to airlock 7B
	for s: float in [-8.0, 8.0]:
		var xx := -330.0
		while xx < -2.0:
			pen.line(Vector2(xx, s), Vector2(xx + 5.0, s), Color(0.92, 0.95, 1.0, 0.45), 0.7)
			xx += 9.0
	# --- pier roof north and south of the cut-away
	for part in [Rect2(Vector2(0, ir.position.y - pier_extent_m * px), Vector2(pier_width_m * px, pier_extent_m * px)),
			Rect2(Vector2(0, ir.end.y), Vector2(pier_width_m * px, pier_extent_m * px))]:
		var r: Rect2 = part
		pen.rect_flat(r, Color("E3E9EF"))
		pen.rect_flat(Rect2(Vector2(r.position.x + 2.4 * px, r.position.y), Vector2(1.8 * px, r.size.y)), Color("2B3440"))
		var wy := r.position.y + 4.0
		var i := 0
		while wy < r.end.y - 4.0:
			var lit := LevelArt.hash01(i, 7) > 0.35
			pen.rect_flat(Rect2(Vector2(r.position.x + 2.55 * px, wy), Vector2(1.5 * px, 10.0)), Color("FFE2A0") if lit else Color("3A4452"))
			wy += 13.0
			i += 1
		pen.rect_flat(Rect2(Vector2(r.position.x + 11.2 * px, r.position.y), Vector2(2.6 * px, r.size.y)), Color("2A9D8F"))
		pen.rect_flat(Rect2(Vector2(r.position.x + 14.6 * px, r.position.y), Vector2(0.8 * px, r.size.y)), Color("1D3557"))
		var sy := r.position.y + 90.0
		while sy < r.end.y:
			pen.line(Vector2(r.position.x + 4.2 * px, sy), Vector2(r.end.x - 4.2 * px, sy), Color(0.45, 0.52, 0.6, 0.8), 1.2)
			sy += 90.0
		pen.line(Vector2(r.position.x, r.position.y), Vector2(r.position.x, r.end.y), Color(1, 1, 1), 2.0)
		pen.line(Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.end.y), Color("8E9AA8"), 2.0)
