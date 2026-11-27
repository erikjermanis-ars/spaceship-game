@tool
class_name NavConsole
extends Interactable
## The bridge's navigation table: a round holo-table showing the local stars.
## E opens the STAR MAP (JumpSystem.open_map), where you lay in a course for
## the quantum drive. The jump itself is flown from the captain's chair.

@export var radius_m := 1.2

var pen: OnFootPainter
var _holo: Node2D
var _t := 0.0


func _ready() -> void:
	z_as_relative = false
	z_index = 1
	prompt = "Star map  ·  lay in a course"
	reach_m = radius_m + 1.3
	prompt_offset_m = Vector2(0, -radius_m - 0.8)
	if Engine.is_editor_hint():
		return
	var body := StaticBody2D.new()
	body.collision_layer = Game.LAYER_WALK
	var cs := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = radius_m * OnFootArt.PX
	cs.shape = c
	body.add_child(cs)
	add_child(body)
	_holo = Node2D.new()
	_holo.material = OnFootArt.add_unshaded()
	_holo.draw.connect(_draw_holo)
	add_child(_holo)


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _holo == null:
		return
	var before := int(_t * 12.0)
	_t += delta
	if int(_t * 12.0) != before:
		_holo.queue_redraw()


func _use(_by: Node2D) -> void:
	var j := get_tree().get_first_node_in_group(&"jump_system")
	if j:
		j.call(&"open_map")


func _draw() -> void:
	pen = OnFootPainter.new(self)
	var r := radius_m * OnFootArt.PX
	pen.set_transform(OnFootArt.SHADOW_OFFSET)
	pen.circle(Vector2.ZERO, r + 0.6, OnFootArt.SHADOW)
	pen.set_transform()
	pen.circle(Vector2.ZERO, r, Color("2B3440"), OnFootArt.INK, 0.15)
	pen.ring(Vector2.ZERO, r - 1.0, Color("8E9AA8"), 0.35)
	pen.circle(Vector2.ZERO, r - 2.0, Color("0E1C30"))
	pen.flush()


## The stars you can reach, slowly turning: the same layout as the star map.
func _draw_holo() -> void:
	var p := OnFootPainter.new(_holo)
	var r := (radius_m - 0.25) * OnFootArt.PX
	p.ring(Vector2.ZERO, r, Color(0.4, 0.8, 1.0, 0.35), 0.2, 36)
	p.ring(Vector2.ZERO, r * 0.55, Color(0.4, 0.8, 1.0, 0.16), 0.15, 28)
	var here := Game.sector
	var course: StringName = &""
	var j := get_tree().get_first_node_in_group(&"jump_system")
	if j:
		course = j.get(&"course")
	var rot := _t * 0.12
	var pts := {}
	for id: StringName in Sectors.DEFS:
		var m: Vector2 = Sectors.DEFS[id].map
		pts[id] = (m / 190.0 * r).rotated(rot)
	if course != &"" and pts.has(course) and pts.has(here):
		var a: Vector2 = pts[here]
		var b: Vector2 = pts[course]
		var k := fmod(_t * 0.6, 1.0)
		p.line(a, b, Color(1.0, 0.8, 0.4, 0.5), 0.2)
		p.circle(a.lerp(b, k), 0.5, Color(1.0, 0.9, 0.6, 0.9))
	for id: StringName in pts:
		var beacon := bool(Sectors.DEFS[id].beacon)
		var c := Color(0.5, 0.9, 1.0, 0.9) if beacon else Color(0.5, 0.6, 0.75, 0.4)
		if id == here:
			c = Color(0.4, 1.0, 0.6, 0.95)
			p.ring(pts[id], 1.3 + 0.4 * sin(_t * 3.0), Color(c, 0.6), 0.15, 16)
		p.circle(pts[id], 0.6 if beacon else 0.4, c)
	p.flush()
