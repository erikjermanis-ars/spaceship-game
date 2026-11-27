@tool
class_name ShipLift
extends Interactable
## A lift car stop. A frigate's deck is 140 m from the flight deck to the
## bridge, so a car runs along the keel: E here rides to the stop named by
## `to_marker` (a Marker2D in the same interior). The director does the ride
## (door, a short fade, the far stop's location card).

@export var to_marker := "LiftBridge"
@export var destination := "Bridge"

## Batched painter used by the draw callback (see OnFootPainter).
var pen: OnFootPainter
var _lamp: Node2D
var _t := 0.0


func _ready() -> void:
	z_as_relative = false
	z_index = 1
	prompt = "Lift  ·  %s" % destination
	reach_m = 1.7
	prompt_offset_m = Vector2(0, -1.5)
	if Engine.is_editor_hint():
		return
	_lamp = Node2D.new()
	_lamp.material = OnFootArt.unshaded()
	_lamp.draw.connect(_draw_lamp)
	add_child(_lamp)


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _lamp == null:
		return
	var before := int(_t * 4.0)
	_t += delta
	if int(_t * 4.0) != before:
		_lamp.queue_redraw()


func _use(_by: Node2D) -> void:
	var d := get_tree().get_first_node_in_group(&"on_foot_director")
	if d:
		d.call(&"ride_lift", self)


## The lift pad: a floor plate with chevrons pointing at the wall panel.
func _draw() -> void:
	pen = OnFootPainter.new(self)
	pen.rrect(Rect2(Vector2(-9, -9), Vector2(18, 18)), 2.0, Color("2B3440"), OnFootArt.INK, 0.15)
	pen.rrect(Rect2(Vector2(-7.5, -7.5), Vector2(15, 15)), 1.5, Color("3A4656"))
	pen.ring(Vector2.ZERO, 5.2, Color(0.5, 0.9, 1.0, 0.5), 0.3, 28)
	pen.text(Vector2(0, 0.6), "LIFT", 2.6, Color(0.85, 0.92, 1.0, 0.8))
	pen.flush()


func _draw_lamp() -> void:
	var p := OnFootPainter.new(_lamp)
	var k := 0.6 + 0.4 * sin(_t * 2.5)
	p.ring(Vector2.ZERO, 6.6, Color(0.5, 0.9, 1.0, 0.35 * k), 0.5, 28)
	p.flush()
