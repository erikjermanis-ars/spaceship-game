@tool
extends Node2D
## Hangar 2 on-foot extras. Origin = hangar centre (world 580, -425 m), axes
## like the world. The Hangar Bay landing pad is a raised platform in the bay;
## a stairway on its east edge leads down to the hangar floor, where the
## shuttle is parked in its painted bay.
##
##   * a gap in the pad railing at the top of the stairs (rail_gaps)
##   * the hangar floor as a walk area (walk_polys); the hangar walls and crates
##     already block the walker, so the floor itself needs no railing
##   * a safety barrier at the blast-door threshold: the doors cycle, and
##     past them is vacuum and a long fall into nothing
##   * floor markings: shuttle bay, walkway from the stairs, door warning

const STAIRS := Rect2(245, -172, 44, 36)        # local px: pad edge -> floor (eastwards)
const FLOOR := Rect2(-440, -345, 935, 690)      # walkable hangar floor (inside the walls)
const DOOR_X := -440.0
## The blast-door line itself (doors at world x 520-524 m): nobody walks out
## of an open door, even after landing the shuttle in the doorway.
const DOOR_LINE_X := -550.0
const BAY := Rect2(316, -318, 88, 176)          # shuttle parking bay
## Where you stand in front of the crew room's airlock (ExteriorDoors "hangar2",
## world 6290, -4350), for the painted lane that leads there.
const CREW_DOOR := Vector2(490, -100)
const CREW_LABEL_X := 395.0

var pen: OnFootPainter


func _ready() -> void:
	z_as_relative = false
	z_index = -41
	if Engine.is_editor_hint():
		return
	# Door-threshold barrier: an invisible wall with a drawn safety rail.
	var body := StaticBody2D.new()
	body.collision_layer = Game.LAYER_WALK
	var cs := CollisionShape2D.new()
	var ss := SegmentShape2D.new()
	ss.a = Vector2(DOOR_X, FLOOR.position.y)
	ss.b = Vector2(DOOR_X, FLOOR.end.y)
	cs.shape = ss
	body.add_child(cs)
	var cs2 := CollisionShape2D.new()
	var ss2 := SegmentShape2D.new()
	ss2.a = Vector2(DOOR_LINE_X, -310.0)
	ss2.b = Vector2(DOOR_LINE_X, 310.0)
	cs2.shape = ss2
	body.add_child(cs2)
	add_child(body)


func get_title() -> String:
	return "Hangar 2"


func rail_gaps() -> Array:
	return [[to_global(Vector2(STAIRS.position.x, STAIRS.position.y + 1.0)), to_global(Vector2(STAIRS.position.x, STAIRS.end.y - 1.0))]]


func walk_polys() -> Array:
	return [{"poly": global_transform * OnFootArt.rect_poly(FLOOR), "rail": false}]


func _draw() -> void:
	pen = OnFootPainter.new(self)
	_paint()
	pen.flush()


func _paint() -> void:
	# --- walkway from the stairs to the shuttle bay
	var lane := Color(0.92, 0.95, 1.0, 0.5)
	for y: float in [STAIRS.position.y - 2.0, STAIRS.end.y + 2.0]:
		_dashes(Vector2(STAIRS.end.x + 2, y), Vector2(BAY.position.x - 4, y), lane)
	var x := STAIRS.end.x + 8.0
	while x < BAY.position.x - 8.0:
		pen.fill(PackedVector2Array([Vector2(x, -158), Vector2(x + 4, -154), Vector2(x, -150), Vector2(x - 1.5, -150), Vector2(x + 2.5, -154), Vector2(x - 1.5, -158)]), Color(0.5, 0.9, 1.0, 0.35))
		x += 14.0

	# --- crew lane: from the foot of the stairs south, then east to airlock H2
	#     in the east wall (the ExteriorDoor paints its own last 2 m)
	var x0 := STAIRS.end.x + 4.0
	var top := STAIRS.end.y + 6.0
	for k: float in [-1.0, 1.0]:
		var corner := Vector2(x0 + 8.5 + 8.5 * k, CREW_DOOR.y - 8.5 * k)
		_dashes(Vector2(corner.x, top), corner, lane)
		_dashes(corner, Vector2(CREW_DOOR.x - 24.0, corner.y), lane)
	x = x0 + 32.0
	while x < CREW_DOOR.x - 30.0:
		if absf(x - CREW_LABEL_X) > 16.0:
			pen.fill(PackedVector2Array([Vector2(x, CREW_DOOR.y - 4), Vector2(x + 4, CREW_DOOR.y), Vector2(x, CREW_DOOR.y + 4), Vector2(x - 1.5, CREW_DOOR.y + 4), Vector2(x + 2.5, CREW_DOOR.y), Vector2(x - 1.5, CREW_DOOR.y - 4)]), Color(0.5, 0.9, 1.0, 0.35))
		x += 14.0
	pen.text(Vector2(CREW_LABEL_X, CREW_DOOR.y + 1.3), "CREW ROOM", 3.6, Color(0.85, 0.92, 1.0, 0.5), HORIZONTAL_ALIGNMENT_CENTER, 60.0)

	# --- shuttle parking bay: corner brackets, hatched apron, painted label
	var b := BAY
	var amber := Color(1.0, 0.69, 0.0, 0.8)
	for c: Vector2 in [b.position, Vector2(b.end.x, b.position.y), b.end, Vector2(b.position.x, b.end.y)]:
		var sx := 1.0 if c.x < b.get_center().x else -1.0
		var sy := 1.0 if c.y < b.get_center().y else -1.0
		pen.line(c, c + Vector2(14 * sx, 0), amber, 0.9)
		pen.line(c, c + Vector2(0, 14 * sy), amber, 0.9)
	pen.polyline(OnFootArt.rect_poly(b), Color(1.0, 0.69, 0.0, 0.25), 0.4, true)
	pen.hazard(Rect2(Vector2(b.position.x, b.end.y + 3), Vector2(b.size.x, 4)), 1.6)
	pen.text(Vector2(b.get_center().x, b.end.y + 18), "BAY 2-S  ·  SHUTTLE", 5.0, Color(0.85, 0.92, 1.0, 0.5))
	pen.text(Vector2(b.get_center().x, b.position.y - 8), "MAG-ANCHOR ZONE", 3.6, Color(1.0, 0.8, 0.4, 0.45))

	# --- blast-door threshold: hazard band + safety rail + warning text
	pen.hazard(Rect2(Vector2(DOOR_X - 6, FLOOR.position.y), Vector2(5, FLOOR.size.y)), 2.0)
	pen.line(Vector2(DOOR_X, FLOOR.position.y), Vector2(DOOR_X, FLOOR.end.y), Color(1.0, 0.69, 0.0, 0.95), 0.4)
	var y := FLOOR.position.y
	while y <= FLOOR.end.y:
		pen.circle(Vector2(DOOR_X, y), 0.55, Color("D9E0E7"), OnFootArt.INK, 0.12, 10)
		pen.circle(Vector2(DOOR_X, y), 0.22, Color(1.0, 0.69, 0.0), Color(0, 0, 0, 0), 0.1, 8)
		y += 25.0
	pen.text(Vector2(DOOR_X + 24, -6), "BLAST DOORS", 5.0, Color(1.0, 0.75, 0.3, 0.6), HORIZONTAL_ALIGNMENT_CENTER, -1.0, true, PI * 0.5)
	pen.text(Vector2(DOOR_X + 32, -6), "KEEP CLEAR · VACUUM BEYOND", 3.0, Color(1.0, 0.75, 0.3, 0.5), HORIZONTAL_ALIGNMENT_CENTER, -1.0, true, PI * 0.5)

	# --- the stairs (drawn last: they sit over the pad edge and the floor)
	_draw_stairs()


func _draw_stairs() -> void:
	var r := STAIRS
	pen.rect_flat(Rect2(r.position + Vector2(1.2, 1.8), r.size), Color(0, 0.01, 0.03, 0.35))   # shadow
	pen.rect(r, Color("3A4452"), OnFootArt.INK, 0.15)
	var steps := 7
	for i in steps:
		# Treads step down eastwards: lighter at the top (pad), darker below.
		var x0 := r.position.x + r.size.x * i / steps
		var w := r.size.x / steps
		var shade := lerpf(1.0, 0.72, float(i) / (steps - 1))
		pen.rect_flat(Rect2(Vector2(x0 + 0.3, r.position.y + 1.2), Vector2(w - 0.9, r.size.y - 2.4)), Color("9AA6B4") * Color(shade, shade, shade))
		pen.line(Vector2(x0 + 0.4, r.position.y + 1.2), Vector2(x0 + 0.4, r.end.y - 1.2), Color(1.0, 0.75, 0.2, 0.85), 0.35)   # nosing
	for yy: float in [r.position.y + 0.5, r.end.y - 0.5]:
		pen.line(Vector2(r.position.x, yy), Vector2(r.end.x, yy), Color("D9E0E7"), 0.5)   # handrails
		pen.circle(Vector2(r.position.x, yy), 0.5, Color("D9E0E7"), OnFootArt.INK, 0.1, 10)
		pen.circle(Vector2(r.end.x, yy), 0.5, Color("D9E0E7"), OnFootArt.INK, 0.1, 10)
	pen.text(Vector2(r.get_center().x, r.position.y - 4), "STAIRS · BAY FLOOR", 2.6, Color(0.85, 0.92, 1.0, 0.55))


func _dashes(a: Vector2, b: Vector2, col: Color) -> void:
	var d := a.distance_to(b)
	if d < 1.0:
		return
	var dir := (b - a) / d
	var s := 0.0
	while s < d:
		pen.line(a + dir * s, a + dir * minf(s + 5.0, d), col, 0.7)
		s += 9.0
