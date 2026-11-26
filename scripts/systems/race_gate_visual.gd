class_name RaceGateVisual
extends Node2D
## Holographic race gate attached to a Level/RaceCourse/GateNN marker.
## Two emitter pylons at ±width/2 along local Y and an animated beam curtain
## between them (shader). The state drives colour and brightness so the
## player can always read: next gate (bright cyan), the one after (dim),
## future (faint), passed (fades out).

enum GateState { NEXT, AFTER, FUTURE, PASSED }

const SHADER_PATH := "res://assets/art/fx/gate_beam.gdshader"
const COL_NEXT := Color(0.5, 0.92, 1.0)
const COL_FINISH := Color(1.0, 0.82, 0.38)
const COL_PASSED := Color(0.45, 1.0, 0.65)
const POST_RADIUS_M := 1.4

var gate_number := 1
var is_finish := false
var is_start := false
var width_px := 400.0
var solid_posts := true

var _state := GateState.FUTURE
var _beam: Node2D
var _beam_mat: ShaderMaterial
var _glows: Array[Sprite2D] = []
var _intensity := 0.0
var _tween: Tween
var _font: Font
var _label := ""
var _label_node: Node2D

func setup(number: int, finish: bool, width_m: float) -> void:
	gate_number = number
	is_finish = finish
	is_start = number == 1
	width_px = width_m * Game.PX_PER_M
	z_as_relative = false
	z_index = Game.Z_PROPS
	_font = HudStyle.font()
	_label = "FINISH" if is_finish else ("START" if is_start else "%02d" % number)
	_build()
	_build_label()
	set_state(GateState.FUTURE, true)

func _build() -> void:
	var half := width_px * 0.5
	_beam = Node2D.new()
	if ResourceLoader.exists(SHADER_PATH):
		_beam_mat = ShaderMaterial.new()
		_beam_mat.shader = load(SHADER_PATH)
		_beam_mat.set_shader_parameter(&"half_span", half)
		_beam_mat.set_shader_parameter(&"band", 48.0)
		_beam.material = _beam_mat
	_beam.draw.connect(func() -> void:
		_beam.draw_texture_rect(FxTextures.white(), Rect2(-48.0, -half, 96.0, width_px), false))
	add_child(_beam)
	for side in [-1.0, 1.0]:
		var g := Sprite2D.new()
		g.texture = FxTextures.glow()
		g.material = FxTextures.additive()
		g.position = Vector2(0, side * half)
		g.scale = Vector2.ONE * 0.75
		add_child(g)
		_glows.append(g)
		if solid_posts:
			var body := StaticBody2D.new()
			body.collision_layer = Game.LAYER_WORLD
			body.collision_mask = 0
			body.position = g.position
			var cs := CollisionShape2D.new()
			var circle := CircleShape2D.new()
			circle.radius = POST_RADIUS_M * Game.PX_PER_M
			cs.shape = circle
			body.add_child(cs)
			add_child(body)

## Gate number/name drawn upright (screen-aligned) next to the -Y post.
func _build_label() -> void:
	_label_node = Node2D.new()
	var r := POST_RADIUS_M * Game.PX_PER_M
	# Further out when the span is horizontal on screen (text is wide).
	var out_dir := Vector2(0, -1).rotated(global_rotation)
	_label_node.position = Vector2(0, -width_px * 0.5 - r * 2.0 - 52.0 * absf(out_dir.x))
	add_child(_label_node)
	_label_node.global_rotation = 0.0
	_label_node.draw.connect(func() -> void:
		if _font == null:
			return
		var col := _color()
		var lit := _state == GateState.NEXT
		var c := Color(col.r, col.g, col.b, 0.95 if lit else 0.5)
		_label_node.draw_string(_font, Vector2(-80, 8), _label, HORIZONTAL_ALIGNMENT_CENTER, 160, 22, c))

func state() -> GateState:
	return _state

func set_state(s: GateState, instant := false) -> void:
	if s == _state and not instant:
		return
	_state = s
	var target := 0.12
	match s:
		GateState.NEXT:
			target = 1.0
		GateState.AFTER:
			target = 0.38
		GateState.FUTURE:
			target = 0.12
		GateState.PASSED:
			target = 0.0
	if _tween and _tween.is_valid():
		_tween.kill()
	if instant:
		_set_intensity(target)
	else:
		_tween = create_tween()
		_tween.tween_method(_set_intensity, _intensity, target, 0.6).set_trans(Tween.TRANS_SINE)
	queue_redraw()
	if _label_node:
		_label_node.queue_redraw()

## Bright white pulse when the ship goes through, then fade to passed.
func pulse() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_set_intensity(2.2)
	_tween = create_tween()
	_tween.tween_method(_set_intensity, 2.2, 0.0, 1.1).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)

func _color() -> Color:
	if _state == GateState.PASSED:
		return COL_PASSED
	return COL_FINISH if is_finish else COL_NEXT

func _set_intensity(v: float) -> void:
	_intensity = v
	var col := _color()
	if _beam_mat:
		_beam_mat.set_shader_parameter(&"intensity", v)
		_beam_mat.set_shader_parameter(&"tint", col)
		_beam_mat.set_shader_parameter(&"flow", 1.0 if _state == GateState.NEXT else 0.3)
	_beam.visible = v > 0.01
	for g in _glows:
		g.modulate = Color(col.r, col.g, col.b, clampf(0.25 + v * 0.75, 0.0, 1.0) if v > 0.01 else 0.18)

func _draw() -> void:
	var half := width_px * 0.5
	var r := POST_RADIUS_M * Game.PX_PER_M
	var col := _color()
	var lit := _state == GateState.NEXT
	for side in [-1.0, 1.0]:
		var c := Vector2(0, side * half)
		# Pylon: navy body, pearl rim, emitter lens facing the gap.
		draw_circle(c, r * 1.25, Color(0.02, 0.03, 0.06, 0.55))
		draw_circle(c, r, Color("#1D3557"))
		draw_arc(c, r, 0.0, TAU, 24, Color("#E9EEF3"), 2.0, true)
		draw_arc(c, r * 0.62, 0.0, TAU, 20, Color("#8E9AA8"), 1.0, true)
		draw_circle(c - Vector2(0, side * r * 0.35), r * 0.28, col if lit else col.darkened(0.55))
		# Fins along the pass direction show which way to fly through.
		draw_line(c + Vector2(-r * 2.2, 0), c + Vector2(-r * 1.05, 0), Color("#C9D2DC"), 3.0, true)
		draw_line(c + Vector2(r * 1.05, 0), c + Vector2(r * 2.2, 0), Color("#C9D2DC"), 3.0, true)
