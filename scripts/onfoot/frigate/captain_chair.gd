@tool
class_name CaptainChair
extends Interactable
## The captain's chair on the KESTREL's bridge. Use it to take the helm: you
## sit down, the bridge powers up, and the view cuts to the ship outside
## (OnFootDirector.take_helm). Local +X is the way the chair faces.

var _panels: Node2D
var _t := 0.0


func _ready() -> void:
	z_as_relative = false
	z_index = 2
	prompt = "Take the helm"
	reach_m = 1.7
	prompt_offset_m = Vector2(0.0, -1.6)
	if Engine.is_editor_hint():
		return
	var body := StaticBody2D.new()
	body.collision_layer = Game.LAYER_WALK
	var cs := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = 0.55 * OnFootArt.PX
	cs.shape = c
	body.add_child(cs)
	add_child(body)
	_panels = Node2D.new()
	_panels.material = OnFootArt.unshaded()
	_panels.draw.connect(_draw_panels)
	add_child(_panels)


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _panels == null:
		return
	var before := int(_t * 8.0)
	_t += delta
	if int(_t * 8.0) != before:
		_panels.queue_redraw()


func _use(_by: Node2D) -> void:
	var d := get_tree().get_first_node_in_group(&"on_foot_director")
	if d:
		d.call(&"take_helm", self)


## Where you sit, and the way you face when seated.
func seat_global() -> Vector2:
	return global_position


func facing() -> float:
	return global_rotation


func _draw() -> void:
	var pen := OnFootPainter.new(self)
	var px := OnFootArt.PX
	pen.set_transform(OnFootArt.SHADOW_OFFSET.rotated(-global_rotation))
	pen.circle(Vector2.ZERO, 0.95 * px, Color(0, 0.01, 0.03, 0.25))
	pen.set_transform()
	# swivel base and footrest ring
	pen.circle(Vector2.ZERO, 0.85 * px, Color("2B3440"), OnFootArt.INK, 0.15)
	pen.ring(Vector2.ZERO, 0.75 * px, Color("8E9AA8"), 0.25)
	# high backrest (behind, -X) with a headrest
	pen.rrect(Rect2(Vector2(-0.75, -0.62) * px, Vector2(0.3, 1.24) * px), 1.6, Color("1D3557"), OnFootArt.INK, 0.15)
	pen.rrect(Rect2(Vector2(-0.82, -0.3) * px, Vector2(0.16, 0.6) * px), 1.0, Color("2A4A73"))
	# seat cushion
	pen.rrect(Rect2(Vector2(-0.48, -0.42) * px, Vector2(0.9, 0.84) * px), 2.0, Color("24406A"), OnFootArt.INK, 0.12)
	pen.line(Vector2(-0.3, 0) * px, Vector2(0.3, 0) * px, Color("3A5E8C"), 0.18)
	# armrests with their little consoles
	for s: float in [-1.0, 1.0]:
		pen.rrect(Rect2(Vector2(-0.5, 0.5 * s - 0.11) * px - Vector2(0, 0), Vector2(1.0, 0.22) * px), 0.8, Color("C9D2DC"), OnFootArt.INK, 0.12)
		pen.rect_flat(Rect2(Vector2(0.05, 0.5 * s - 0.08) * px, Vector2(0.4, 0.16) * px), Color("1B2533"))
	pen.flush()


func _draw_panels() -> void:
	var pen := OnFootPainter.new(_panels)
	var px := OnFootArt.PX
	for s: float in [-1.0, 1.0]:
		for k in 4:
			var on := LevelArt.hash01(int(_t * 3.0) + k * 7, int(s) + 5) > 0.35
			var col: Color = [OnFootArt.CYAN, OnFootArt.AMBER, OnFootArt.NAV_GREEN, OnFootArt.CYAN][k]
			pen.rect_flat(Rect2(Vector2(0.08 + k * 0.09, 0.5 * s - 0.05) * px, Vector2(0.06, 0.1) * px), Color(col, 0.95 if on else 0.3))
	pen.flush()
