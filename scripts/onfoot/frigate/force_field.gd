@tool
class_name ForceField
extends InteriorWindow
## The flight deck's atmosphere-containment field across the bay mouth. To
## the wall builder it is a window (no wall drawn, no light occluder, but it
## still stops you walking out into space); it draws as a shimmering curtain
## of light between two emitter posts and hums quietly.

var _field: Node2D
var _t := 0.0
var _hum: AudioStreamPlayer2D


func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	_field = Node2D.new()
	_field.material = OnFootArt.add_unshaded()
	_field.draw.connect(_draw_field)
	add_child(_field)
	var s := GameplayUtil.load_loop("force_field_loop.wav")
	if s:
		_hum = AudioStreamPlayer2D.new()
		_hum.stream = s
		_hum.bus = GameplayUtil.bus(&"SFX")
		_hum.volume_db = -14.0
		_hum.max_distance = 420.0
		add_child(_hum)
		_hum.play()


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _field == null:
		return
	var before := int(_t * 20.0)
	_t += delta
	if int(_t * 20.0) != before:
		_field.queue_redraw()


## Emitter posts at both ends (the static part).
func _paint_draw() -> void:
	var px := OnFootArt.PX
	var half := length_m * 0.5 * px
	for s: float in [-1.0, 1.0]:
		var c := Vector2(0, s * half)
		pen.rrect(Rect2(c - Vector2(7, 6), Vector2(14, 12)), 2.0, Color("5C6878"), OnFootArt.INK, 0.15)
		pen.rect_flat(Rect2(c - Vector2(2, 4), Vector2(4, 8)), Color("7FE6FF"))


func _draw_field() -> void:
	var p := OnFootPainter.new(_field)
	var px := OnFootArt.PX
	var half := length_m * 0.5 * px
	var n := int(length_m * 1.5)
	var h := half * 2.0 / n
	for i in n:
		var y := -half + i * h
		var sh := 0.5 + 0.5 * sin(float(i) * 1.3 + _t * 3.1) * sin(float(i) * 0.37 - _t * 1.7)
		p.rect_flat(Rect2(Vector2(-3.0, y + 0.3), Vector2(6.0, h - 0.6)), Color(0.35, 0.8, 1.0, 0.05 + 0.1 * sh))
		p.rect_flat(Rect2(Vector2(-0.6, y + 0.3), Vector2(1.2, h - 0.6)), Color(0.7, 0.95, 1.0, 0.25 + 0.4 * sh))
	p.flush()
