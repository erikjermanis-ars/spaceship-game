class_name LandedShip
extends Node2D
## The detailed "on foot" model of the player's ship. Added as a child of the
## PlayerShip while you're out (so it sits exactly where the ship landed) and
## cross-faded with the flight sprite during the zoom.
##
## Why a second model: the flight sprite is drawn for a camera ~7x further
## out. Up close you want more detail (landing gear, cockpit interior, panel
## lines) and moving parts (hatch, boarding stairs). Swapping models by
## distance is the classic "level of detail" (LOD) technique.
##
## Static detail lives in an SVG imported at 12x (crisp at walking zoom);
## animated parts are drawn here. Other ships subclass this and override
## _configure() (art + hatch geometry), _build_glows(), _animate() and
## _paint_details() (see ShuttleLanded).

signal hatch_finished(open: bool)

## Configured in _configure() (defaults: the courier WREN).
var tex: Texture2D = preload("res://assets/art/onfoot/ship_landed.svg")
var svg_scale := 12.0
## Port boarding hatch (local px, nose = +X). Port side = local -Y.
var hatch_x0 := 12.6
var hatch_x1 := 21.4
var hatch_y := -11.6          ## hull edge at the hatch
var ramp_len := 11.0
var ramp_w := 7.6
## Where the walker stands at the top of the stairs / at the foot.
var door_point := Vector2(17.0, -9.0)
var foot_point := Vector2(17.0, -26.5)
var shadow_offset := Vector2(4.0, 6.0)

var hatch_t := 0.0:          # 0 closed .. 1 door open + stairs down
	set(v):
		hatch_t = v
		queue_redraw()
		_update_hatch_fx()

var _t := 0.0
var _heat := 0.85            # engine bells cool down after landing
var _shadow: Sprite2D
var _hull: Sprite2D
var _glows := {}             # name -> Sprite2D
var _hatch_light: Sprite2D
var _board: CallbackInteractable
var _snd_open: AudioStream
var _snd_close: AudioStream


## Batched painter used by the draw callbacks (see OnFootPainter).
var pen: OnFootPainter

func _ready() -> void:
	_configure()
	z_as_relative = false
	z_index = Game.Z_SHIP
	_shadow = Sprite2D.new()
	_shadow.texture = tex
	_shadow.scale = Vector2.ONE / svg_scale
	_shadow.modulate = Color(0, 0.01, 0.03, 0.3)
	_shadow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_shadow.show_behind_parent = true
	add_child(_shadow)
	_hull = Sprite2D.new()
	_hull.texture = tex
	_hull.scale = Vector2.ONE / svg_scale
	_hull.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_hull.show_behind_parent = true
	add_child(_hull)

	# Lights (additive, unshaded so they glow the same day or night).
	_build_glows()
	_hatch_light = OnFootArt.glow_sprite(self, Vector2((hatch_x0 + hatch_x1) * 0.5, hatch_y - 3.4), Color(1.0, 0.85, 0.6, 0.0), 10.0)
	for g: Sprite2D in _glows.values():
		g.z_index = 1
	_hatch_light.z_index = 1

	_board = CallbackInteractable.new()
	_board.name = "BoardHatch"
	_board.prompt = "Board ship"
	_board.reach_m = 2.2
	_board.position = foot_point + Vector2(0, 2.0)
	_board.prompt_offset_m = Vector2(0, -1.6)
	add_child(_board)

	_snd_open = GameplayUtil.load_audio("hatch_open.wav")
	_snd_close = GameplayUtil.load_audio("hatch_close.wav")
	_update_hatch_fx()


## Hook for the director: what happens when the player picks "Board ship".
func set_board_action(cb: Callable) -> void:
	_board.on_use = cb


## Override: art and hatch geometry for this ship.
func _configure() -> void:
	pass


## Override: nav lights etc. (additive glow sprites in `_glows`).
func _build_glows() -> void:
	_glows.nav_port = OnFootArt.glow_sprite(self, Vector2(-9, -25.4), OnFootArt.NAV_RED, 9.0)
	_glows.nav_stbd = OnFootArt.glow_sprite(self, Vector2(-9, 25.4), OnFootArt.NAV_GREEN, 9.0)
	_glows.strobe = OnFootArt.glow_sprite(self, Vector2(-43.2, 0), Color.WHITE, 10.0)
	_glows.beacon = OnFootArt.glow_sprite(self, Vector2(4, 0), OnFootArt.NAV_RED, 7.0)
	_glows.bell_p = OnFootArt.glow_sprite(self, Vector2(-49, -21), Color(1.0, 0.45, 0.15), 8.0)
	_glows.bell_s = OnFootArt.glow_sprite(self, Vector2(-49, 21), Color(1.0, 0.45, 0.15), 8.0)
	_glows.console = OnFootArt.glow_sprite(self, Vector2(36.6, 0), Color(0.3, 0.8, 1.0, 0.35), 4.0)


func door_global() -> Vector2:
	return to_global(door_point)


func foot_global() -> Vector2:
	return to_global(foot_point)


## Facing (global radians) for someone stepping out of the hatch.
func outward_angle() -> float:
	return global_rotation - PI * 0.5


func open_hatch(time := 1.1) -> void:
	_play(_snd_open, -4.0)
	var tw := create_tween()
	tw.tween_property(self, ^"hatch_t", 1.0, time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func() -> void: hatch_finished.emit(true))


func close_hatch(time := 1.0) -> void:
	_play(_snd_close, -4.0)
	var tw := create_tween()
	tw.tween_property(self, ^"hatch_t", 0.0, time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func() -> void: hatch_finished.emit(false))


func _play(s: AudioStream, db: float) -> void:
	if s == null:
		return
	var p := AudioStreamPlayer2D.new()
	p.stream = s
	p.bus = GameplayUtil.bus(&"SFX")
	p.volume_db = db
	p.max_distance = 600.0
	p.position = Vector2((hatch_x0 + hatch_x1) * 0.5, hatch_y)
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


func _process(delta: float) -> void:
	_t += delta
	_heat = maxf(0.0, _heat - delta / 40.0)
	# Shadow falls towards the bottom-right whatever way the ship faces.
	_shadow.position = shadow_offset.rotated(-global_rotation)
	_animate(delta)
	queue_redraw()


## Override: animate `_glows`. Parked: steady nav lights, a slow
## anti-collision beacon and strobe, engines cooling.
func _animate(_delta: float) -> void:
	var nav := 0.85 + 0.1 * sin(_t * 2.0)
	(_glows.nav_port as Sprite2D).modulate.a = nav
	(_glows.nav_stbd as Sprite2D).modulate.a = nav
	var strobe_ph := fmod(_t, 2.4)
	(_glows.strobe as Sprite2D).modulate.a = 1.0 if strobe_ph < 0.08 or (strobe_ph > 0.2 and strobe_ph < 0.26) else 0.0
	(_glows.beacon as Sprite2D).modulate.a = pow(maxf(0.0, sin(_t * 2.6)), 6.0)
	var h := _heat * (0.9 + 0.1 * sin(_t * 7.0))
	(_glows.bell_p as Sprite2D).modulate.a = h
	(_glows.bell_s as Sprite2D).modulate.a = h


func _update_hatch_fx() -> void:
	if _hatch_light:
		_hatch_light.modulate.a = 0.55 * clampf(hatch_t * 1.6 - 0.3, 0.0, 1.0)


func _draw() -> void:
	pen = OnFootPainter.new(self)
	_paint_draw()
	pen.flush()


func _paint_draw() -> void:
	_paint_details()
	_draw_hatch()


## Override: ship-specific animated detail drawn over the SVG.
func _paint_details() -> void:
	# Heat tint on the bells (drawn over the SVG).
	if _heat > 0.01:
		for s: float in [-1.0, 1.0]:
			var bell := PackedVector2Array([Vector2(-45, s * 23.6), Vector2(-51, s * 24.6), Vector2(-51, s * 17.4), Vector2(-45, s * 18.4)])
			pen.fill(bell, Color(1.0, 0.45, 0.15, 0.45 * _heat))
	# Cockpit screens: little animated readouts.
	for i in 3:
		var y := -1.6 + i * 1.1
		var w := 0.4 + 0.3 * (0.5 + 0.5 * sin(_t * (1.3 + i) + i))
		pen.rect_flat(Rect2(Vector2(36.35, y), Vector2(0.6, w)), Color(0.5, 0.95, 1.0, 0.8))
	# Registration, painted on the wings so it reads upright on screen
	# whichever way the ship is parked (same trick as the pad numbers).
	var flip := cos(global_rotation) < 0.0
	var k := -1.0 if flip else 1.0
	_label(Vector2(-18, 16.0 * k), "WREN" if not flip else "MC-07", flip)
	_label(Vector2(-18, -15.4 * k), "MC-07" if not flip else "WREN", flip)


func _label(p: Vector2, s: String, flip: bool) -> void:
	var off := Vector2(0, 0.9).rotated(PI if flip else 0.0)
	pen.text(p + off, s, 2.5, Color(0.11, 0.21, 0.34, 0.85), HORIZONTAL_ALIGNMENT_CENTER, -1.0, true, PI if flip else 0.0)


func _draw_hatch() -> void:
	var k := hatch_t
	# Door slides aft along the hull first (0..0.45), then the stairs unfold.
	var door_k := clampf(k / 0.45, 0.0, 1.0)
	var ramp_k := clampf((k - 0.35) / 0.65, 0.0, 1.0)
	var hx := (hatch_x0 + hatch_x1) * 0.5
	# Stairs: unfold outward from under the hull edge.
	if ramp_k > 0.0:
		var ln := ramp_len * ramp_k
		var r := Rect2(Vector2(hx - ramp_w * 0.5, hatch_y - ln), Vector2(ramp_w, ln))
		pen.rect_flat(Rect2(r.position + Vector2(1.2, 1.6), r.size), Color(0, 0.01, 0.03, 0.35))  # shadow
		pen.rect(r, Color("3A4452"), OnFootArt.INK, 0.15)
		var steps := 6
		for i in steps:
			var y := hatch_y - ln * (i + 0.5) / steps
			pen.rect_flat(Rect2(Vector2(r.position.x + 0.5, y - 0.65), Vector2(ramp_w - 1.0, 1.0)), Color("8E9AA8"))
			pen.line(Vector2(r.position.x + 0.5, y - 0.65), Vector2(r.end.x - 0.5, y - 0.65), Color("C9D2DC"), 0.18)
		# hand rails + amber edge markers + little step lights
		for sx: float in [r.position.x + 0.25, r.end.x - 0.25]:
			pen.line(Vector2(sx, hatch_y), Vector2(sx, hatch_y - ln), Color("C9D2DC"), 0.45)
		pen.rect_flat(Rect2(Vector2(r.position.x, r.position.y), Vector2(ramp_w, 0.7)), OnFootArt.AMBER)
		for i in 3:
			var y := hatch_y - ln * (i + 0.5) / 3.0
			pen.circle(Vector2(r.position.x + 0.25, y), 0.28, Color(1.0, 0.85, 0.55))
			pen.circle(Vector2(r.end.x - 0.25, y), 0.28, Color(1.0, 0.85, 0.55))
	# Doorway: warm cabin light shows once the door moves.
	var frame := Rect2(Vector2(hatch_x0 + 0.6, hatch_y + 0.1), Vector2(hatch_x1 - hatch_x0 - 1.2, 2.6))
	if door_k > 0.0:
		pen.rect_flat(frame, Color(1.0, 0.86, 0.62).lerp(Color("2B3440"), 1.0 - door_k))
	# Door leaf: slides aft over the hull.
	var leaf := Rect2(frame.position + Vector2(-door_k * (frame.size.x + 0.6), 0), frame.size)
	pen.rect(leaf, Color("D9E0E7"), Color("4A5563"), 0.2)
	pen.line(leaf.position + Vector2(0.6, 1.3), leaf.position + Vector2(leaf.size.x - 0.6, 1.3), Color("8E9AA8"), 0.2)
	pen.rect_flat(Rect2(leaf.position + Vector2(leaf.size.x - 1.6, 0.6), Vector2(0.9, 0.5)), Color(0.4, 1.0, 0.6) if k > 0.0 else OnFootArt.NAV_RED)
