@tool
class_name DeskLamp
extends Interactable
## A small lamp with its own warm pool of light (a radial PointLight2D).
## Works independently of the room light: read in the dark.

@export var on := false:
	set(v):
		on = v
		_apply()
		queue_redraw()
@export var light_radius_m := 3.0
@export var light_color := Color(1.0, 0.8, 0.5)

var _light: PointLight2D
var _glow: Node2D


## Batched painter used by the draw callbacks (see OnFootPainter).
var pen: OnFootPainter

func _ready() -> void:
	z_as_relative = false
	z_index = 3 if not Engine.is_editor_hint() else 3
	reach_m = 1.5
	prompt_offset_m = Vector2(0, -0.9)
	if Engine.is_editor_hint():
		return
	add_to_group(&"persist")
	_light = PointLight2D.new()
	_light.texture = OnFootArt.radial_texture()
	_light.texture_scale = light_radius_m * OnFootArt.PX * 2.0 / 128.0
	_light.color = light_color
	_light.energy = 1.1
	_light.shadow_enabled = true
	_light.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	add_child(_light)
	_glow = Node2D.new()
	_glow.material = OnFootArt.unshaded()
	_glow.draw.connect(func() -> void:
		if on:
			_glow.draw_circle(Vector2(0.6, 0), 0.75, Color(1.0, 0.92, 0.7), true, -1.0, true))
	add_child(_glow)
	_apply()


func _apply() -> void:
	prompt = "Lamp off" if on else "Lamp on"
	if _light:
		_light.enabled = on
	if _glow:
		_glow.queue_redraw()


func _use(_by: Node2D) -> void:
	on = not on
	GameplayUtil.play_oneshot(self, GameplayUtil.load_audio("switch_click.wav"), -8.0, 1.25)


func save_state() -> Dictionary:
	return {"on": on}


func load_state(d: Dictionary) -> void:
	on = bool(d.get("on", on))


func _draw() -> void:
	pen = OnFootPainter.new(self)
	_paint_draw()
	pen.flush()


func _paint_draw() -> void:
	pen.circle(Vector2(-0.6, 0), 1.1, Color("2B3440"), OnFootArt.INK, 0.1)   # base
	pen.line(Vector2(-0.6, 0), Vector2(0.4, 0), Color("8E9AA8"), 0.35)            # arm
	var shade := PackedVector2Array([Vector2(0.0, -1.0), Vector2(1.5, -1.3), Vector2(1.5, 1.3), Vector2(0.0, 1.0)])
	pen.poly(shade, Color("FFB000") if not on else Color("FFD27A"), OnFootArt.INK, 0.1)
