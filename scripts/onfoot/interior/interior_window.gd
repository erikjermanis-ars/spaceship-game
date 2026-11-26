@tool
class_name InteriorWindow
extends Node2D
## A window in a wall: the InteriorLevel cuts this span out of the wall's
## drawing and light occluders (collision stays: it's glass). Place the node
## at the window's centre ON the wall line; the span runs along local Y.
## Whatever is behind the wall shows through: for an outer hull window that
## is space itself (the SpaceBackground layer behind the whole game).

@export var length_m := 4.0:
	set(v): length_m = v; queue_redraw()
@export var thickness_m := 1.0:
	set(v): thickness_m = v; queue_redraw()


## Batched painter used by the draw callbacks (see OnFootPainter).
var pen: OnFootPainter

func _ready() -> void:
	z_as_relative = false
	z_index = Game.Z_WALL_TOP if not Engine.is_editor_hint() else 12


## Span in the PARENT's coordinates (the interior root), for the wall cutter.
func span() -> Array:
	var d := Vector2(0, length_m * 0.5 * OnFootArt.PX).rotated(rotation)
	return [position - d, position + d]


func _draw() -> void:
	pen = OnFootPainter.new(self)
	_paint_draw()
	pen.flush()


func _paint_draw() -> void:
	var px := OnFootArt.PX
	var r := Rect2(Vector2(-thickness_m * 0.5, -length_m * 0.5) * px, Vector2(thickness_m, length_m) * px)
	# glass: faint cool tint with streak reflections, mullions every 2 m
	pen.rect_flat(r, Color(0.55, 0.8, 0.95, 0.12))
	pen.line(Vector2(r.position.x, r.position.y), Vector2(r.position.x, r.end.y), Color(0.8, 0.95, 1.0, 0.55), 0.25)
	pen.line(Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.end.y), Color(0.8, 0.95, 1.0, 0.35), 0.18)
	var n := maxi(1, int(round(length_m / 2.0)))
	for i in n + 1:
		var y := r.position.y + r.size.y * i / n
		pen.rect(Rect2(Vector2(r.position.x - 0.3, y - 0.6), Vector2(r.size.x + 0.6, 1.2)), Color("C9D2DC"), OnFootArt.INK, 0.1)
	for i in n:
		var y := r.position.y + r.size.y * (i + 0.3) / n
		pen.line(Vector2(r.position.x + 1.0, y), Vector2(r.end.x - 1.0, y + 5.0), Color(1, 1, 1, 0.16), 0.4)
