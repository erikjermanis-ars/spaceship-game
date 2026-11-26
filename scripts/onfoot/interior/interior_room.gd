@tool
class_name InteriorRoom
extends Node2D
## One room of an interior: a rectangle (node position = top-left corner,
## px) with a floor style. The InteriorLevel builds the walls from all rooms'
## edges, so rooms just need to share edges where they touch.
##
## Each room draws its own floor as one cached canvas item. Keeping floors
## per room (instead of one huge floor) means each one only overlaps its own
## lights, which keeps 2D lighting cheap.

enum Floor { PLATE, GRATE, CARPET, TILE }

@export var room_name := "Room":
	set(v): room_name = v; queue_redraw()
@export var size_m := Vector2(6, 5):
	set(v): size_m = v; queue_redraw()
@export var floor_style: Floor = Floor.PLATE:
	set(v): floor_style = v; queue_redraw()
@export var floor_color := Color("5B6B80"):
	set(v): floor_color = v; queue_redraw()
## Painted label on the floor (empty = none).
@export var floor_label := "":
	set(v): floor_label = v; queue_redraw()
@export var label_offset_m := Vector2(0, 0):
	set(v): label_offset_m = v; queue_redraw()


## Batched painter used by the draw callbacks (see OnFootPainter).
var pen: OnFootPainter

func rect_px() -> Rect2:
	return Rect2(position, size_m * OnFootArt.PX)


func rect_global() -> Rect2:
	return Rect2(global_position, size_m * OnFootArt.PX)


func _ready() -> void:
	z_as_relative = false
	z_index = -4


func _draw() -> void:
	pen = OnFootPainter.new(self)
	_paint_draw()
	pen.flush()


func _paint_draw() -> void:
	var px := OnFootArt.PX
	var r := Rect2(Vector2.ZERO, size_m * px)
	var base := floor_color
	pen.rect_flat(r, base)
	match floor_style:
		Floor.PLATE:
			var cell := 1.5 * px
			var seam := base.darkened(0.28)
			var hi := base.lightened(0.1)
			var x := cell
			while x < r.size.x - 0.1:
				pen.line(Vector2(x, 0), Vector2(x, r.size.y), seam, 0.18)
				x += cell
			var y := cell
			while y < r.size.y - 0.1:
				pen.line(Vector2(0, y), Vector2(r.size.x, y), seam, 0.18)
				y += cell
			# alternate plates slightly lighter + corner fasteners
			var i := 0
			var yy := 0.0
			while yy < r.size.y - 0.1:
				var xx := 0.0
				var j := 0
				while xx < r.size.x - 0.1:
					var pr := Rect2(Vector2(xx, yy), Vector2(minf(cell, r.size.x - xx), minf(cell, r.size.y - yy)))
					if (i + j) % 2 == 0:
						pen.rect_flat(pr.grow(-0.15), Color(hi, 0.35))
					for c in [pr.position + Vector2(0.9, 0.9), pr.end - Vector2(0.9, 0.9)]:
						pen.circle(c, 0.22, seam)
					xx += cell
					j += 1
				yy += cell
				i += 1
		Floor.GRATE:
			var step := 0.55
			var dark := base.darkened(0.45)
			var y := step * 0.5
			while y < r.size.y:
				pen.line(Vector2(0.3, y), Vector2(r.size.x - 0.3, y), dark, 0.25)
				y += step
			var cell := 2.0 * px
			var x := cell
			while x < r.size.x - 0.1:
				pen.rect_flat(Rect2(Vector2(x - 0.3, 0), Vector2(0.6, r.size.y)), base.darkened(0.2))
				x += cell
		Floor.CARPET:
			var border := base.darkened(0.18)
			pen.polyline(OnFootArt.rect_poly(r.grow(-1.2)), border, 0.9, true)
			pen.polyline(OnFootArt.rect_poly(r.grow(-2.6)), Color(base.lightened(0.12), 0.6), 0.25, true)
			var y := 2.0
			while y < r.size.y:
				pen.line(Vector2(0, y), Vector2(r.size.x, y), Color(base.darkened(0.06), 0.7), 0.12)
				y += 1.2
		Floor.TILE:
			var cell := 0.8 * px
			var g := base.darkened(0.12)
			var x := cell
			while x < r.size.x:
				pen.line(Vector2(x, 0), Vector2(x, r.size.y), g, 0.12)
				x += cell
			var y := cell
			while y < r.size.y:
				pen.line(Vector2(0, y), Vector2(r.size.x, y), g, 0.12)
				y += cell
	# ambient occlusion along the walls (soft dark band)
	for k in 4:
		var w := 0.6 + k * 0.6
		pen.polyline(OnFootArt.rect_poly(r.grow(-w * 0.5)), Color(0, 0.01, 0.03, 0.06), w, true)
	if floor_label != "":
		var c := r.get_center() + label_offset_m * px
		pen.text(c, floor_label, 5.0, Color(1, 1, 1, 0.22))
