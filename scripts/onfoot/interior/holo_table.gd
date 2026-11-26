@tool
class_name HoloTable
extends Interactable
## Round ops table that projects a hologram of Meridian Station (ring, hub,
## pier, traffic blips) when switched on. The hologram is additive and
## unshaded, with a cyan PointLight2D so it lights the room around it.

@export var radius_m := 1.6
@export var on := true:
	set(v):
		on = v
		if _light:
			_light.enabled = on
		_update_prompt()

var _holo: Node2D
var _light: PointLight2D
var _t := 0.0
var _k := 0.0      # projector warm-up 0..1


## Batched painter used by the draw callbacks (see OnFootPainter).
var pen: OnFootPainter

func _ready() -> void:
	z_as_relative = false
	z_index = 2
	reach_m = radius_m + 1.2
	prompt_offset_m = Vector2(0, -radius_m - 0.6)
	if Engine.is_editor_hint():
		return
	add_to_group(&"persist")
	var body := StaticBody2D.new()
	body.collision_layer = Game.LAYER_WALK
	var cs := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = radius_m * OnFootArt.PX - 0.3
	cs.shape = c
	body.add_child(cs)
	add_child(body)
	_light = PointLight2D.new()
	_light.texture = OnFootArt.radial_texture()
	_light.texture_scale = (radius_m + 3.0) * OnFootArt.PX * 2.0 / 128.0
	_light.color = Color(0.45, 0.85, 1.0)
	_light.energy = 0.7
	add_child(_light)
	_holo = Node2D.new()
	_holo.material = OnFootArt.add_unshaded()
	_holo.z_index = 1
	_holo.draw.connect(_draw_holo)
	add_child(_holo)
	_k = 1.0 if on else 0.0
	on = on


func _update_prompt() -> void:
	prompt = "Hologram off" if on else "Hologram on"


func _use(_by: Node2D) -> void:
	on = not on
	GameplayUtil.play_oneshot(self, GameplayUtil.load_audio("holo_on.wav" if on else "console_beep.wav"), -8.0, 1.0 if on else 0.8)


func save_state() -> Dictionary:
	return {"on": on}


func load_state(d: Dictionary) -> void:
	on = bool(d.get("on", on))
	_k = 1.0 if on else 0.0


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _holo == null:
		return
	_t += delta
	_k = move_toward(_k, 1.0 if on else 0.0, delta * 1.5)
	_light.energy = 0.7 * _k * (0.92 + 0.08 * sin(_t * 9.0))
	if _k > 0.0 or on:
		_holo.queue_redraw()


func _draw() -> void:
	pen = OnFootPainter.new(self)
	_paint_draw()
	pen.flush()


func _paint_draw() -> void:
	var r := radius_m * OnFootArt.PX
	pen.circle(OnFootArt.SHADOW_OFFSET * 1.5, r, Color(0, 0.01, 0.03, 0.3))
	pen.circle(Vector2.ZERO, r, Color("3A4452"), OnFootArt.INK, 0.2)
	pen.circle(Vector2.ZERO, r - 1.2, Color("1B2533"), Color("8E9AA8"), 0.15)
	pen.circle(Vector2.ZERO, r * 0.35, Color("2B3440"), Color("2A9D8F"), 0.2)
	for i in 12:
		var a := TAU * i / 12.0
		pen.line(Vector2(cos(a), sin(a)) * (r - 1.0), Vector2(cos(a), sin(a)) * (r - 0.4), Color("8E9AA8"), 0.2)


func _draw_holo() -> void:
	pen = OnFootPainter.new(_holo)
	_paint_draw_holo()
	pen.flush()


func _paint_draw_holo() -> void:
	if _k <= 0.001:
		return
	var a := _k * (0.85 + 0.15 * sin(_t * 23.0) * sin(_t * 3.1))
	var col := Color(0.4, 0.85, 1.0, 0.75 * a)
	var dim := Color(0.4, 0.85, 1.0, 0.3 * a)
	var R := radius_m * OnFootArt.PX * 0.72
	# projection cone base
	pen.circle(Vector2.ZERO, R * 1.05, Color(0.3, 0.7, 1.0, 0.08 * a))
	# rotating ring with spokes
	var rot := _t * 0.25
	pen.arc(Vector2(-R * 0.15, 0), R * 0.62, 0, 40, col, 0.35, TAU)
	pen.arc(Vector2(-R * 0.15, 0), R * 0.5, 0, 40, dim, 0.2, TAU)
	for i in 6:
		var an := rot + TAU * i / 6.0
		pen.line(Vector2(-R * 0.15, 0) + Vector2(cos(an), sin(an)) * R * 0.14, Vector2(-R * 0.15, 0) + Vector2(cos(an), sin(an)) * R * 0.5, dim, 0.15)
	pen.circle(Vector2(-R * 0.15, 0), R * 0.14, Color(0.5, 0.9, 1.0, 0.35 * a))
	# the pier, with a highlighted dot for Pad 2 (you are here)
	pen.rect_flat(Rect2(Vector2(R * 0.62, -R * 0.75), Vector2(R * 0.08, R * 1.5)), col)
	var blink := 0.5 + 0.5 * sin(_t * 6.0)
	pen.circle(Vector2(R * 0.56, R * 0.22), 0.45, Color(1.0, 0.75, 0.3, a * blink))
	# traffic blips orbiting
	for i in 5:
		var an := _t * (0.3 + i * 0.05) + i * 1.25
		var p := Vector2(-R * 0.15, 0) + Vector2(cos(an), sin(an)) * R * (0.78 + 0.07 * (i % 2))
		pen.circle(p, 0.3, Color(1.0, 0.85, 0.4, 0.8 * a))
	# scan line sweeping across
	var sy := fposmod(_t * 0.6, 2.0) - 1.0
	pen.line(Vector2(-R, sy * R), Vector2(R, sy * R), Color(0.5, 0.95, 1.0, 0.18 * a), 0.3)
