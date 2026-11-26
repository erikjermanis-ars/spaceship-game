@tool
class_name WindowShutter
extends Interactable
## Motorised slat shutter over an InteriorWindow. Node sits at the window
## centre (span along local Y, like the window); the control panel the walker
## uses is at `panel_offset_m` (local). Closed = slats + a light occluder.

@export var length_m := 10.0:
	set(v): length_m = v; queue_redraw()
@export var thickness_m := 1.0
@export var panel_offset_m := Vector2(-1.2, 6.0)
@export var closed := false:
	set(v):
		closed = v
		_update_prompt()

var _k := 0.0      # 0 open .. 1 closed (animated)
var _occ: LightOccluder2D
var _panel: Node2D


## Batched painter used by the draw callbacks (see OnFootPainter).
var pen: OnFootPainter

func _ready() -> void:
	z_as_relative = false
	z_index = Game.Z_WALL_TOP + 1 if not Engine.is_editor_hint() else 13
	reach_m = 1.4
	if Engine.is_editor_hint():
		_k = 1.0 if closed else 0.0
		return
	add_to_group(&"persist")
	_k = 1.0 if closed else 0.0
	_occ = LightOccluder2D.new()
	var op := OccluderPolygon2D.new()
	var h := Vector2(thickness_m, length_m) * OnFootArt.PX * 0.5
	op.polygon = PackedVector2Array([Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y)])
	_occ.occluder = op
	_occ.visible = closed
	add_child(_occ)
	_panel = Node2D.new()
	_panel.material = OnFootArt.unshaded()
	_panel.position = panel_offset_m * OnFootArt.PX
	_panel.draw.connect(func() -> void:
		_panel.draw_rect(Rect2(Vector2(0.1, -0.9), Vector2(0.5, 1.8)), Color(0.3, 0.85, 1.0, 0.9))
		_panel.draw_circle(Vector2(0.35, 0.0), 0.22, OnFootArt.AMBER if closed else OnFootArt.NAV_GREEN, true, -1.0, true))
	add_child(_panel)
	_update_prompt()


func reach_point() -> Vector2:
	return to_global(panel_offset_m * OnFootArt.PX)


func prompt_position() -> Vector2:
	return reach_point() + prompt_offset_m * OnFootArt.PX


func _update_prompt() -> void:
	prompt = "Open shutters" if closed else "Close shutters"
	if _occ:
		_occ.visible = closed
	if _panel:
		_panel.queue_redraw()


func _use(_by: Node2D) -> void:
	closed = not closed
	GameplayUtil.play_oneshot(self, GameplayUtil.load_audio("switch_click.wav"), -8.0, 0.9)
	GameplayUtil.play_oneshot(self, GameplayUtil.load_audio("door_servo.wav"), -14.0, 1.45)


func save_state() -> Dictionary:
	return {"closed": closed}


func load_state(d: Dictionary) -> void:
	closed = bool(d.get("closed", closed))
	_k = 1.0 if closed else 0.0
	queue_redraw()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var target := 1.0 if closed else 0.0
	if not is_equal_approx(_k, target):
		_k = move_toward(_k, target, delta * 0.7)
		queue_redraw()


func _draw() -> void:
	pen = OnFootPainter.new(self)
	_paint_draw()
	pen.flush()


func _paint_draw() -> void:
	var px := OnFootArt.PX
	var L := length_m * px
	var T := thickness_m * px
	# panel on the wall
	var pp := panel_offset_m * px
	pen.rrect(Rect2(pp + Vector2(-0.4, -1.3), Vector2(1.2, 2.6)), 0.3, Color("C9D2DC"), OnFootArt.INK, 0.1)
	if _k <= 0.001:
		return
	# slats roll down from the top (-Y) end of the window
	var cover := L * _k
	var r := Rect2(Vector2(-T * 0.5, -L * 0.5), Vector2(T, cover))
	pen.rect_flat(r, Color("8E9AA8"))
	var y := r.position.y + 0.6
	while y < r.end.y:
		pen.line(Vector2(r.position.x, y), Vector2(r.end.x, y), Color("6D7A8A"), 0.35)
		y += 1.2
	pen.rect_flat(Rect2(Vector2(r.position.x, r.end.y - 0.8), Vector2(T, 0.8)), Color("4A5563"))
