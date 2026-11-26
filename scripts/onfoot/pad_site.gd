class_name PadSite
extends Node2D
## The walkable surroundings of a landing pad, created when you step out of
## the ship and freed when you take off (nothing on-foot exists in flight).
##
## Generic part (works for every pad): reads the pad module's deck size and
## puts a safety railing around the deck edge, with matching invisible walls
## so you can't walk off the pad into space.
##
## Pad-specific part: if `EXTRAS` lists a scene for this pad, the director
## adds it next to this node (Pad 2 has an airlock into the spaceport pier).
## That scene can provide an interior via `get_interior_path()`. A new
## walkable location = one new scene + one line in EXTRAS: data-driven, no
## director code changes.

const EXTRAS := {
	"Pad 2": "res://scenes/onfoot/sites/pad2_site.tscn",
}
const RAIL_GAP_M := 0.5          # railing sits this far inside the deck edge

var pad_name := ""
var _deck := Rect2()             ## walkable rect, pad-local px


## `pad` is the docking trigger (Area2D); its parent is the pad module.
## Batched painter used by the draw callbacks (see OnFootPainter).
var pen: OnFootPainter

func setup(pad: Area2D) -> void:
	pad_name = String(pad.get_meta(&"pad_name", pad.name))
	var module := pad.get_parent() as Node2D
	global_transform = module.global_transform if module else pad.global_transform
	var size_m: Vector2 = module.get(&"size_m") if module and module.get(&"size_m") != null else Vector2(40, 40)
	var tail_m: float = float(module.get(&"tail_m")) if module and module.get(&"tail_m") != null else 0.0
	var hx := size_m.x * 0.5 * OnFootArt.PX
	var hy := size_m.y * 0.5 * OnFootArt.PX
	var g := RAIL_GAP_M * OnFootArt.PX
	_deck = Rect2(Vector2(-hx - tail_m * OnFootArt.PX + g, -hy + g), Vector2(size_m.x + tail_m, size_m.y) * OnFootArt.PX - Vector2(g, g) * 2.0)
	z_as_relative = false
	z_index = Game.Z_BELOW_DECK + 8
	_build_walls()


## Scene path of the pad-specific extras (authored in world coordinates), or "".
static func extras_for(pad: String) -> String:
	var p: String = EXTRAS.get(pad, "")
	return p if p != "" and ResourceLoader.exists(p) else ""


func _build_walls() -> void:
	var body := StaticBody2D.new()
	body.name = "DeckEdge"
	body.collision_layer = Game.LAYER_WALK
	body.collision_mask = 0
	var t := 6.0
	var r := _deck
	for rr: Rect2 in [
		Rect2(Vector2(r.position.x - t, r.position.y - t), Vector2(r.size.x + t * 2, t)),
		Rect2(Vector2(r.position.x - t, r.end.y), Vector2(r.size.x + t * 2, t)),
		Rect2(Vector2(r.position.x - t, r.position.y), Vector2(t, r.size.y)),
		Rect2(Vector2(r.end.x, r.position.y), Vector2(t, r.size.y)),
	]:
		var cs := CollisionShape2D.new()
		var rs := RectangleShape2D.new()
		rs.size = rr.size
		cs.shape = rs
		cs.position = rr.get_center()
		body.add_child(cs)
	add_child(body)


func _draw() -> void:
	pen = OnFootPainter.new(self)
	_paint_draw()
	pen.flush()


func _paint_draw() -> void:
	_draw_deck_detail()
	# Safety railing: stanchions every 2.5 m joined by a chain-and-cable line.
	var r := _deck
	var corners := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position])
	var shadow := Vector2(0.5, 0.8).rotated(-global_rotation)
	pen.polyline(_offset(corners, shadow), Color(0, 0.01, 0.03, 0.3), 0.6)
	pen.polyline(corners, Color(1.0, 0.69, 0.0, 0.9), 0.35)
	pen.polyline(_offset(corners, Vector2(-0.25, -0.25)), Color(1.0, 0.9, 0.6, 0.45), 0.12)
	for i in 4:
		var a := corners[i]
		var b := corners[i + 1]
		var n := maxi(1, int(a.distance_to(b) / 25.0))
		for j in n + 1:
			var p := a.lerp(b, float(j) / n)
			pen.circle(p + shadow, 0.6, Color(0, 0.01, 0.03, 0.3))
			pen.circle(p, 0.55, Color("D9E0E7"))
			pen.ring(p, 0.55, OnFootArt.INK, 0.12)
			pen.circle(p, 0.22, Color(1.0, 0.69, 0.0))


func _offset(p: PackedVector2Array, o: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array(p)
	for i in out.size():
		out[i] += o
	return out


## Close-up detail the flight-scale deck art doesn't need: 1.5 m plate seams,
## bolts, scuffs, and a scorch ring where ships settle. Subtle, so the pad's
## painted markings still read through.
func _draw_deck_detail() -> void:
	var r := _deck
	var cell := 15.0
	var seam := Color(0.0, 0.02, 0.05, 0.16)
	var hi := Color(0.6, 0.7, 0.85, 0.05)
	var x := ceilf(r.position.x / cell) * cell
	while x < r.end.x:
		pen.line(Vector2(x, r.position.y), Vector2(x, r.end.y), seam, 0.15)
		pen.line(Vector2(x + 0.25, r.position.y), Vector2(x + 0.25, r.end.y), hi, 0.12)
		x += cell
	var y := ceilf(r.position.y / cell) * cell
	while y < r.end.y:
		pen.line(Vector2(r.position.x, y), Vector2(r.end.x, y), seam, 0.15)
		pen.line(Vector2(r.position.x, y + 0.25), Vector2(r.end.x, y + 0.25), hi, 0.12)
		y += cell
	x = ceilf(r.position.x / cell) * cell
	while x < r.end.x:
		y = ceilf(r.position.y / cell) * cell
		while y < r.end.y:
			for o: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
				pen.circle(Vector2(x, y) + o * 1.1, 0.18, Color(0.55, 0.65, 0.78, 0.18))
			y += cell
		x += cell
	# landing scorch: soft concentric rings around the pad centre
	for i in 6:
		pen.ring(Vector2.ZERO, 40.0 + i * 9.0, Color(0.0, 0.0, 0.02, 0.035), 7.0)
	# scuffs and stains (seeded so they're always the same)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(pad_name)
	for i in 34:
		var p := Vector2(rng.randf_range(r.position.x + 10, r.end.x - 10), rng.randf_range(r.position.y + 10, r.end.y - 10))
		var a := rng.randf_range(0, TAU)
		var l := rng.randf_range(4.0, 14.0)
		pen.line(p, p + Vector2.from_angle(a) * l, Color(0.0, 0.0, 0.02, rng.randf_range(0.05, 0.12)), rng.randf_range(0.3, 1.2))
	for i in 8:
		var p := Vector2(rng.randf_range(r.position.x + 20, r.end.x - 20), rng.randf_range(r.position.y + 20, r.end.y - 20))
		pen.fill(OnFootArt.ellipse_poly(p, rng.randf_range(3, 8), rng.randf_range(2, 5), rng.randf_range(0, PI), 14), Color(0.02, 0.03, 0.05, 0.1))
