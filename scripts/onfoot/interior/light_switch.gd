@tool
class_name LightSwitch
extends Interactable
## Wall switch for one or more RoomLights. Rotate the node so +X points into
## the room (away from the wall). The rocker and its LED show the state.

@export var lights: Array[NodePath] = []
@export var label := "LIGHTS"

var _snd_click: AudioStream
var _snd_on: AudioStream
var _on := false


## Batched painter used by the draw callbacks (see OnFootPainter).
var pen: OnFootPainter

func _ready() -> void:
	z_as_relative = false
	z_index = Game.Z_WALL_TOP + 1 if not Engine.is_editor_hint() else 13
	reach_m = 1.8
	if Engine.is_editor_hint():
		return
	add_to_group(&"persist")
	_snd_click = GameplayUtil.load_audio("switch_click.wav")
	_snd_on = GameplayUtil.load_audio("light_on.wav")
	# LED is emissive: draw it in an unshaded child so it glows in the dark.
	var led := Node2D.new()
	led.material = OnFootArt.unshaded()
	led.draw.connect(func() -> void:
		var c := OnFootArt.NAV_GREEN if _on else Color(1.0, 0.55, 0.15)
		led.draw_circle(Vector2(0.75, -1.25), 0.32, c, true, -1.0, true))
	add_child(led)
	_sync.call_deferred()


func _sync() -> void:
	var ls := _targets()
	_on = not ls.is_empty() and ls[0].on
	prompt = "Lights off" if _on else "Lights on"
	queue_redraw()
	for c in get_children():
		if c is Node2D:
			(c as Node2D).queue_redraw()


func _targets() -> Array[RoomLight]:
	var out: Array[RoomLight] = []
	for p in lights:
		var n := get_node_or_null(p) as RoomLight
		if n:
			out.append(n)
	return out


func _use(_by: Node2D) -> void:
	var ls := _targets()
	if ls.is_empty():
		return
	var turn_on := not ls[0].on
	for l in ls:
		l.on = turn_on
	GameplayUtil.play_oneshot(self, _snd_click, -6.0, randf_range(0.95, 1.05))
	if turn_on:
		GameplayUtil.play_oneshot(self, _snd_on, -12.0, randf_range(0.97, 1.03))
	_sync()


func save_state() -> Dictionary:
	return {}


func load_state(_d: Dictionary) -> void:
	_sync.call_deferred()


func _draw() -> void:
	pen = OnFootPainter.new(self)
	_paint_draw()
	pen.flush()


func _paint_draw() -> void:
	# Wall plate, local +X = into the room.
	var plate := Rect2(Vector2(-0.3, -1.9), Vector2(1.5, 3.8))
	pen.rect_flat(Rect2(plate.position + Vector2(0.25, 0.35), plate.size), Color(0, 0.01, 0.03, 0.3))
	pen.rrect(plate, 0.35, Color("E9EEF3"), OnFootArt.INK, 0.12)
	var rocker := Rect2(Vector2(0.05, -0.65 if _on else -0.15), Vector2(0.9, 0.8))
	pen.rect(Rect2(Vector2(0.05, -0.65), Vector2(0.9, 1.3)), Color("C9D2DC"), Color("8E9AA8"), 0.08)
	pen.rect(rocker, Color("FFFFFF"), Color("8E9AA8"), 0.08)
