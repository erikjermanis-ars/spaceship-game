class_name CameraRig
extends Camera2D
## Follow camera for the player ship.
##  * Look-ahead: the view leads the ship along its velocity. Only the lead
##    OFFSET is smoothed (critically-damped spring) — the ship itself is
##    tracked exactly, so it never jitters or lags behind at 80 m/s.
##  * Speed zoom: pulls out smoothly as speed rises (1.0 at rest -> 0.45 at
##    boost speed), times a manual wheel/(=/-) zoom factor.
##  * Trauma shake: shake = trauma², noise-driven, decays over time.
##    punch(dir, px) adds a directional kick that springs back.
##  * Optional rotate-with-ship mode (C): ship nose points up the screen.
##  * Focus mode (on foot): set_focus(node, zoom) blends position, zoom and
##    rotation from the ship view to a close, north-up view of another node
##    (the walker), with a critically damped follow and a small walk lead.
##    The same camera is used everywhere, so there is never a camera cut.
## Sets Game.camera and follows Game.player whenever one exists.

@export_group("Follow")
## Seconds of velocity the view leads by.
@export var lookahead_time := 1.1
## Max lead as a fraction of the half-viewport, per axis (an ellipse), so the
## lead can use the wide screen axis fully when flying east/west.
@export_range(0.0, 1.0, 0.01) var lookahead_max_frac := 0.55
## Spring angular frequency of the lead offset (rad/s). Lower = lazier.
@export var lookahead_omega := 3.2

@export_group("Zoom")
@export var zoom_rest := 1.0
@export var zoom_fast := 0.45
@export var zoom_speed_ref_mps := 83.0
## 0 = no speed zoom, 1 = full (tuning panel slider).
@export_range(0.0, 1.5, 0.01) var speed_zoom_amount := 1.0
@export var zoom_smoothing := 1.4
@export var manual_zoom_min := 0.45
@export var manual_zoom_max := 2.5

@export_group("Shake")
## Global shake multiplier (tuning panel slider).
@export_range(0.0, 3.0, 0.01) var shake_amount := 1.0
@export var max_shake_px := 26.0
@export var max_shake_rot := 0.03
@export var trauma_decay := 1.25
@export var shake_frequency := 22.0
## React to the player's own impacts/scrapes (shake + punch) by itself.
## Off by default: in the main game GAMEPLAY's ImpactFX drives add_trauma()/
## punch() so the camera doesn't double up. Test scenes without ImpactFX
## (e.g. the ship sandbox) switch this on.
@export var auto_impact_shake := false

@export_group("Rotate mode")
@export var rotate_with_ship := false
@export var rotate_smoothing := 5.0

@export_group("Focus (on foot)")
## Follow spring of the focus point (rad/s): high = tight, low = floaty.
@export var focus_omega := 7.0
## Seconds of the focus target's velocity the view leads by.
@export var focus_lead_time := 0.35
@export var focus_zoom_min := 0.7
@export var focus_zoom_max := 1.45

var trauma := 0.0
var manual_zoom := 1.0
## Wheel zoom factor while in focus mode (separate from the flight one).
var focus_manual_zoom := 1.0

var _look := Vector2.ZERO
var _look_vel := Vector2.ZERO
var _punch := Vector2.ZERO
var _punch_vel := Vector2.ZERO
var _zoom := 1.0
var _base_rot := 0.0
var _t := 0.0
var _noise := FastNoiseLite.new()
var _snap := true

var _focus: Node2D
var _focus_zoom := 7.5
var _focus_blend := 0.0          # 0 = ship view .. 1 = focus view
var _focus_dir := 0.0            # +1 blending in, -1 blending out
var _focus_blend_time := 1.4
var _focus_pos := Vector2.ZERO   # smoothed focus point
var _focus_vel := Vector2.ZERO
var _focus_snap := true


func _ready() -> void:
	Game.camera = self
	ignore_rotation = false
	position_smoothing_enabled = false
	rotation_smoothing_enabled = false
	process_callback = Camera2D.CAMERA2D_PROCESS_IDLE
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0
	_noise.seed = 1337
	make_current()
	# Test-harness convenience: --cam-zoom=2.5 (manual zoom factor), --cam-rotate.
	if Game.cmd.has("cam-zoom"):
		manual_zoom = clampf(float(Game.cmd["cam-zoom"]), 0.1, 8.0)
	if Game.cmd.has("cam-rotate"):
		rotate_with_ship = true
	Game.impact.connect(_on_impact)
	Game.scrape.connect(_on_scrape)
	Game.ship_respawned.connect(func(_p: Vector2) -> void: _snap = true)


func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)


## Directional kick of the view by `strength_px` screen pixels that springs back.
func punch(direction: Vector2, strength_px: float) -> void:
	if direction.length_squared() < 0.0001:
		return
	# Clamp so stacked hits can't throw the view off the ship.
	_punch_vel += direction.normalized() * minf(strength_px, 48.0) * 24.0


## Blend the view to follow `target` at `zoom_level` over `blend_s` seconds.
## Calling it again while focused just re-targets (the follow spring glides).
func set_focus(target: Node2D, zoom_level: float, blend_s := 1.4) -> void:
	if _focus == null or _focus_blend <= 0.0:
		_focus_snap = true
	_focus = target
	_focus_zoom = zoom_level
	_focus_dir = 1.0
	_focus_blend_time = maxf(blend_s, 0.001)


## Blend back to the ship view.
func clear_focus(blend_s := 1.4) -> void:
	_focus_dir = -1.0
	_focus_blend_time = maxf(blend_s, 0.001)


func is_focused() -> bool:
	return _focus != null and _focus_dir > 0.0


## Jump straight onto the focus target (after a teleport behind a fade).
func snap_focus() -> void:
	_focus_snap = true
	if _focus_dir > 0.0:
		_focus_blend = 1.0


func _unhandled_input(event: InputEvent) -> void:
	if is_focused():
		if event.is_action_pressed(&"zoom_in"):
			focus_manual_zoom = clampf(focus_manual_zoom * 1.1, focus_zoom_min, focus_zoom_max)
		elif event.is_action_pressed(&"zoom_out"):
			focus_manual_zoom = clampf(focus_manual_zoom / 1.1, focus_zoom_min, focus_zoom_max)
		return
	if event.is_action_pressed(&"zoom_in"):
		manual_zoom = clampf(manual_zoom * 1.12, manual_zoom_min, manual_zoom_max)
	elif event.is_action_pressed(&"zoom_out"):
		manual_zoom = clampf(manual_zoom / 1.12, manual_zoom_min, manual_zoom_max)
	elif event.is_action_pressed(&"camera_mode"):
		rotate_with_ship = not rotate_with_ship
		Game.toast("Camera: %s" % ("rotate with ship" if rotate_with_ship else "north up"), 1.5)


func _process(delta: float) -> void:
	_t += delta
	var dt := minf(delta, 1.0 / 20.0)
	_focus_blend = clampf(_focus_blend + _focus_dir * dt / _focus_blend_time, 0.0, 1.0)
	if _focus_dir < 0.0 and _focus_blend <= 0.0:
		_focus = null
		_focus_dir = 0.0
	if _focus_blend >= 1.0:
		# Fully on foot: the ship view isn't needed (the ship may even be
		# suspended while we're inside an interior).
		_apply_view(_focus_view(dt), dt)
		return
	var ship := Game.player
	if not is_instance_valid(ship):
		return
	var view := _ship_view(ship, dt)
	if _focus != null:
		var f := _focus_view(dt)
		var b := smoothstep(0.0, 1.0, _focus_blend)
		view.pos = view.pos.lerp(f.pos, b)
		view.zoom = exp(lerpf(log(view.zoom), log(f.zoom), b))
		view.rot = lerp_angle(view.rot, f.rot, b)
	_apply_view(view, dt)


## Close north-up view of the focus node with a critically damped follow.
func _focus_view(dt: float) -> Dictionary:
	# If the target is freed mid-blend, hold the last focus point.
	var target := _focus_pos
	if is_instance_valid(_focus):
		target = _focus.call(&"render_position") if _focus.has_method(&"render_position") else _focus.global_position
		var v: Variant = _focus.get(&"velocity")
		if v is Vector2:
			target += (v as Vector2) * focus_lead_time
	if _focus_snap:
		_focus_pos = target
		_focus_vel = Vector2.ZERO
		_focus_snap = false
	else:
		var w := focus_omega
		var steps := 2
		var h := dt / steps
		for i in steps:
			var acc := (target - _focus_pos) * w * w - _focus_vel * 2.0 * w
			_focus_vel += acc * h
			_focus_pos += _focus_vel * h
	return {"pos": _focus_pos, "zoom": _focus_zoom * focus_manual_zoom, "rot": 0.0, "floor_trauma": 0.0}


## Shake/punch, applied on top of whichever view is active.
func _apply_view(view: Dictionary, dt: float) -> void:
	# ---- punch: under-damped spring back to zero ----
	var pw := 16.0
	var pacc := -_punch * pw * pw - _punch_vel * 2.0 * 0.45 * pw
	_punch_vel += pacc * dt
	_punch += _punch_vel * dt

	# ---- shake ----
	trauma = maxf(trauma - trauma_decay * dt, 0.0)
	var tr := maxf(trauma, float(view.floor_trauma))
	var shake := tr * tr * shake_amount
	var n1 := _noise.get_noise_2d(_t * shake_frequency, 0.0)
	var n2 := _noise.get_noise_2d(_t * shake_frequency, 50.0)
	var n3 := _noise.get_noise_2d(_t * shake_frequency, 100.0)
	var shake_off := Vector2(n1, n2) * max_shake_px * shake
	var z: float = view.zoom
	zoom = Vector2(z, z)
	rotation = float(view.rot) + n3 * max_shake_rot * shake
	global_position = view.pos
	# Screen-space offsets (shake/punch) are converted to world units and
	# rotated with the view so they always read the same on screen.
	offset = ((shake_off + _punch) / z).rotated(rotation)


## The flight view: speed zoom, look-ahead and optional rotate-with-ship.
func _ship_view(ship: RigidBody2D, dt: float) -> Dictionary:
	var vel: Vector2 = ship.linear_velocity
	var speed_mps := vel.length() / Game.PX_PER_M

	# ---- zoom (log-space smoothing feels even in and out) ----
	# Ease-out: pulls back early (cruise already shows ~3 s of travel ahead)
	# and flattens towards boost speed.
	var x := clampf(speed_mps / zoom_speed_ref_mps, 0.0, 1.0)
	var k := (1.0 - (1.0 - x) * (1.0 - x)) * speed_zoom_amount
	var target_zoom := lerpf(zoom_rest, zoom_fast, clampf(k, 0.0, 1.5)) * manual_zoom
	target_zoom = maxf(target_zoom, 0.12)
	if _snap:
		_zoom = target_zoom
	else:
		_zoom = exp(lerpf(log(_zoom), log(target_zoom), 1.0 - exp(-zoom_smoothing * dt)))

	# ---- look-ahead spring (critically damped, sub-stepped for stability) ----
	var half := get_viewport_rect().size * 0.5 / _zoom
	var lead_target := vel * lookahead_time
	var lim := half * lookahead_max_frac
	var e := Vector2(lead_target.x / maxf(lim.x, 1.0), lead_target.y / maxf(lim.y, 1.0)).length()
	if e > 1.0:
		lead_target /= e
	if _snap:
		_look = lead_target
		_look_vel = Vector2.ZERO
	else:
		var steps := 2
		var h := dt / steps
		for i in steps:
			var acc := (lead_target - _look) * lookahead_omega * lookahead_omega - _look_vel * 2.0 * lookahead_omega
			_look_vel += acc * h
			_look += _look_vel * h

	var floor_trauma := 0.0
	if ship is PlayerShip and (ship as PlayerShip).boosting:
		floor_trauma = 0.2

	# ---- rotation ----
	# Follow the ship's interpolated (rendered) transform, not the raw 120 Hz
	# physics one, so the world scrolls smoothly at any frame rate.
	var ship_xf: Transform2D = ship.call(&"render_transform") if ship.has_method(&"render_transform") else ship.global_transform
	var target_rot := (ship_xf.get_rotation() + PI * 0.5) if rotate_with_ship else 0.0
	if _snap:
		_base_rot = target_rot
	else:
		_base_rot = lerp_angle(_base_rot, target_rot, 1.0 - exp(-rotate_smoothing * dt))

	_snap = false
	return {"pos": ship_xf.origin + _look, "zoom": _zoom, "rot": _base_rot, "floor_trauma": floor_trauma}


func _on_impact(_pos: Vector2, normal: Vector2, speed_mps: float, source: Node, _other: Node) -> void:
	if not auto_impact_shake or source != Game.player:
		return
	add_trauma(clampf((speed_mps - 1.0) / 22.0, 0.05, 0.75))
	# The view keeps travelling into the obstacle for a moment, then recovers.
	punch(-normal, clampf(speed_mps * 1.4, 2.0, 34.0))


func _on_scrape(_pos: Vector2, _normal: Vector2, tangent_speed_mps: float, source: Node) -> void:
	if not auto_impact_shake or source != Game.player:
		return
	trauma = maxf(trauma, clampf(0.18 + tangent_speed_mps / 70.0, 0.0, 0.5))
