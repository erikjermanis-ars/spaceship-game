class_name OnFootHUD
extends CanvasLayer
## HUD for walking around, drawn above the flight HUD (same HudStyle look):
##   * a floating key prompt ("E  LIGHTS ON") next to the thing you can use
##   * a location card when you arrive somewhere ("PAD 2 · MERIDIAN SPACEPORT")
##   * a short controls reminder
##   * the full-screen fade used to hide level swaps
## Pure presentation: the director tells it what to show.

var target: Interactable          ## current interactable under the prompt
var fade := 0.0:                  ## 0 clear .. 1 black
	set(v):
		fade = v
		if _fade_rect:
			_fade_rect.color.a = v
			_fade_rect.visible = v > 0.001

var _canvas: Control
var _fade_rect: ColorRect
var _loc_title := ""
var _loc_sub := ""
var _loc_t := 99.0
var _hint_t := 99.0
var _hint_text := ""
var _hint_len := 1.0
var _prompt_a := 0.0
var _last_target: Interactable
var _t := 0.0

const LOC_TIME := 4.5


func _ready() -> void:
	layer = 11
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_canvas)
	add_child(_canvas)
	_fade_rect = ColorRect.new()
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.color = Color(0.0, 0.005, 0.015, 0.0)
	_fade_rect.visible = false
	add_child(_fade_rect)


## Tween the black overlay; await the returned tween's `finished`.
func fade_to(a: float, time: float) -> Tween:
	var tw := create_tween()
	tw.tween_property(self, ^"fade", a, time).set_trans(Tween.TRANS_SINE)
	return tw


func show_location(title: String, sub: String) -> void:
	_loc_title = title
	_loc_sub = sub
	_loc_t = 0.0


func show_hint(text: String, time := 9.0) -> void:
	_hint_text = text
	_hint_t = -time
	_hint_len = time


func _process(delta: float) -> void:
	_t += delta
	_loc_t += delta
	_hint_t += delta
	if target != _last_target:
		_prompt_a = 0.0
		_last_target = target
	_prompt_a = move_toward(_prompt_a, 1.0 if target != null else 0.0, delta * 8.0)
	_canvas.queue_redraw()


func _draw_canvas() -> void:
	var size := _canvas.size
	# --- location card
	if _loc_t < LOC_TIME:
		var a := clampf(minf(_loc_t * 2.5, (LOC_TIME - _loc_t) * 1.5), 0.0, 1.0)
		var w := 620.0
		var r := Rect2(Vector2((size.x - w) * 0.5, 70.0), Vector2(w, 86.0))
		HudStyle.draw_panel(_canvas, r, 14.0, Color(HudStyle.CYAN, 0.7 * a), Color(0.02, 0.05, 0.1, 0.6 * a))
		HudStyle.text(_canvas, r.position + Vector2(0, 42), _loc_title, 30, Color(HudStyle.WHITE, a), HORIZONTAL_ALIGNMENT_CENTER, w)
		HudStyle.text(_canvas, r.position + Vector2(0, 70), _loc_sub, 16, Color(HudStyle.CYAN, a), HORIZONTAL_ALIGNMENT_CENTER, w)
	# --- controls reminder (bottom left)
	if _hint_t < 0.0 and _hint_text != "":
		var a := clampf(-_hint_t * 0.8, 0.0, 1.0) * clampf((_hint_t + _hint_len) * 3.0, 0.0, 1.0)
		var parts := _hint_text.split("|")
		var x := 40.0
		var y := size.y - 44.0
		for p in parts:
			var kv := p.split(":")
			if kv.size() == 2:
				x += HudStyle.key_hint(_canvas, Vector2(x, y), kv[0].strip_edges(), kv[1].strip_edges(), a, 16) + 26.0
	# --- interaction prompt, anchored near the object on screen
	var tgt := target if target != null else _last_target
	if _prompt_a > 0.01 and tgt != null and is_instance_valid(tgt):
		var ct := _canvas.get_viewport().get_canvas_transform()
		var sp := ct * tgt.prompt_position()
		var label := tgt.prompt
		var f := HudStyle.font()
		var w := 44.0 + f.get_string_size(label.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x + 20.0
		var pos := Vector2(sp.x - w * 0.5, sp.y)
		pos.x = clampf(pos.x, 20.0, size.x - w - 20.0)
		pos.y = clampf(pos.y, 60.0, size.y - 40.0)
		var a := _prompt_a
		var bg := Rect2(pos + Vector2(-10, -30), Vector2(w + 10, 42))
		_canvas.draw_rect(bg, Color(0.02, 0.05, 0.1, 0.55 * a))
		_canvas.draw_line(bg.position, Vector2(bg.end.x, bg.position.y), Color(HudStyle.CYAN, 0.6 * a), 1.5)
		var bob := sin(_t * 4.0) * 1.5
		HudStyle.key_hint(_canvas, pos + Vector2(0, bob), "E", label, a, 19)
