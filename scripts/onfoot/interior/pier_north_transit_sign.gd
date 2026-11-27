@tool
extends Node2D
## A lit destination sign hung beside a transit pod's door: which way that
## pod goes, readable from across the platform, before you are close enough
## for the door's prompt. Drawn above the wall tops and unshaded, like the
## gangway gate's status sign, so it reads the same in a dark room.
## Node origin = the sign's centre.

@export var heading := "PIER LINE":
	set(v): heading = v; queue_redraw()
@export var destination := "PIER 7 SOUTH":
	set(v): destination = v; queue_redraw()
@export var size := Vector2(26, 8):
	set(v): size = v; queue_redraw()
@export var accent := Color("FFB000"):
	set(v): accent = v; queue_redraw()


func _ready() -> void:
	z_as_relative = false
	z_index = Game.Z_WALL_TOP + 1 if not Engine.is_editor_hint() else 13
	if not Engine.is_editor_hint():
		material = OnFootArt.unshaded()


func _draw() -> void:
	var pen := OnFootPainter.new(self)
	var r := Rect2(-size * 0.5, size)
	pen.rrect(r, 0.6, Color("17202B"), OnFootArt.INK, 0.15)
	pen.rect_flat(Rect2(r.position + Vector2(1, 1), Vector2(1.6, size.y - 2)), accent)
	# Both lines are centred in the space right of the accent bar.
	var w := size.x - 4.6
	var c := Vector2(r.position.x + 3.6 + w * 0.5, 0)
	pen.text(c + Vector2(0, -0.9), heading, 1.9, Color(0.85, 0.92, 1.0, 0.8), HORIZONTAL_ALIGNMENT_CENTER, w, false)
	pen.text(c + Vector2(0, 2.5), destination, 2.7, accent.lightened(0.25), HORIZONTAL_ALIGNMENT_CENTER, w)
	pen.flush()
