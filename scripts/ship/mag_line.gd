class_name MagLine
extends Node2D
## The PETREL's magnetic towline. Hold the line button to fire at the
## highlighted target and stay hooked; let go to release (everything keeps
## its momentum: that's the fling). Hold reel to winch in.
##
## A rope that can only pull (no push): tension T = k*stretch + c*stretch
## rate when taut, 0 when slack. Forces are equal and opposite: the ship is
## pulled toward the anchor, a free cargo container is pulled toward the ship.
## Static or moving structure (pier corners, the ring, the crane) only pulls
## the ship: hook one at speed and you swing around it.
##
##   slip clutch  above 45 kN the spool pays out instead (up to 40 m)
##   snap         at full length and > 60 kN for 0.15 s, or any > 150 kN spike
##   winch        reel at 4 m/s; stalls above 30 kN (then you get dragged in)
##
## Drawn in global coordinates (top_level) on the FX layer.

signal latched(kind: String)
signal released
signal snapped

enum State { READY, ATTACHED, COOLDOWN }

const RANGE_M := 32.0
const MIN_LEN_M := 3.0
const MAX_LEN_M := 40.0
const K := 60000.0              # N per m of stretch
const C := 7500.0               # N per m/s of stretch rate
const CLUTCH_N := 45000.0
const STALL_N := 30000.0
const SNAP_N := 60000.0
const SPIKE_N := 150000.0
const REEL_MPS := 4.0
const PAYOUT_MPS := 15.0

var ship: RigidBody2D
## Local tow-eye position on the ship (px).
var eye_local := Vector2(-10, 0)

var state := State.READY
var target: CollisionObject2D
var target_kind := ""           ## CARGO / STRUCTURE / MOVING / TRAFFIC
var target_mass := 0.0
var anchor_local := Vector2.ZERO
var length_m := 0.0
var tension_n := 0.0
var slipping := false
var winch_state := ""           ## "", IN, STALL
var aim_dir := Vector2.RIGHT    ## set by the ship each tick
## Force on the ship this tick (N, global), applied in its _integrate_forces.
var ship_force := Vector2.ZERO

var _prev_d := -1.0
var _prev_anchor := Vector2.ZERO
var _cool := 0.0
var _over_t := 0.0
var _scan_tick := 0
var _scan_hit := {}             ## {pos, collider, kind}
var _fire_t := 1.0              ## head flight animation 0..1
var _dry_t := 1.0
var _whip_t := 1.0
var _whip_from := Vector2.ZERO
var _whip_to := Vector2.ZERO
var _t := 0.0

var _snd := {}
var _loop_tension: AudioStreamPlayer2D
var _loop_clutch: AudioStreamPlayer2D
var _loop_winch: AudioStreamPlayer2D


func _ready() -> void:
	top_level = true
	z_as_relative = false
	z_index = Game.Z_FX
	for n in ["magline_fire", "magline_latch", "magline_snap", "magline_release"]:
		_snd[n] = GameplayUtil.load_audio(n + ".wav")
	_loop_tension = _make_loop("magline_tension_loop.wav")
	_loop_clutch = _make_loop("clutch_scream_loop.wav")
	_loop_winch = _make_loop("winch_loop.wav")


func _make_loop(file: String) -> AudioStreamPlayer2D:
	var s := GameplayUtil.load_loop(file)
	if s == null:
		return null
	var p := AudioStreamPlayer2D.new()
	p.stream = s
	p.bus = GameplayUtil.bus(&"SFX")
	p.volume_db = -60.0
	p.max_distance = 1500.0
	add_child(p)
	return p


func is_attached() -> bool:
	return state == State.ATTACHED


func eye_global() -> Vector2:
	return ship.to_global(eye_local)


func anchor_global() -> Vector2:
	if target == null or not is_instance_valid(target):
		return eye_global()
	return target.global_transform * anchor_local


## Highlighted target for the reticle: {} or {pos, kind}.
func scan_result() -> Dictionary:
	return _scan_hit


# ------------------------------------------------------------- controls --

func fire() -> void:
	if state != State.READY:
		return
	_play("magline_fire", -8.0)
	if _scan_hit.is_empty():
		_dry_t = 0.0      # line flies out empty and comes back
		return
	target = _scan_hit.collider
	target_kind = _scan_hit.kind
	target_mass = (target as RigidBody2D).mass if target is RigidBody2D else 0.0
	anchor_local = target.global_transform.affine_inverse() * (_scan_hit.pos as Vector2)
	# Rays are cast from the nose but the line runs from the tow eye: start
	# with exactly that length (slack-free, no snap on the first tick).
	length_m = clampf(eye_global().distance_to(_scan_hit.pos) / Game.PX_PER_M, MIN_LEN_M, MAX_LEN_M)
	_prev_d = -1.0
	_prev_anchor = anchor_global()
	_over_t = 0.0
	_fire_t = 0.0
	state = State.ATTACHED
	_play("magline_latch", -6.0)
	latched.emit(target_kind)


func release(silent := false) -> void:
	if state != State.ATTACHED:
		return
	state = State.COOLDOWN
	_cool = 0.35
	_clear_target()
	if not silent:
		_play("magline_release", -10.0)
	released.emit()


func _snap() -> void:
	_whip_from = eye_global()
	_whip_to = anchor_global()
	_whip_t = 0.0
	state = State.COOLDOWN
	_cool = 1.5
	_clear_target()
	_play("magline_snap", -3.0)
	Game.toast("LINE SNAPPED", 1.6)
	snapped.emit()


func _clear_target() -> void:
	target = null
	target_kind = ""
	target_mass = 0.0
	tension_n = 0.0
	slipping = false
	winch_state = ""
	ship_force = Vector2.ZERO


# -------------------------------------------------------------- physics --

## Called by the ship every physics tick (before the step).
func physics_tick(dt: float, reel: bool) -> void:
	_t += dt
	ship_force = Vector2.ZERO
	if state == State.COOLDOWN:
		_cool -= dt
		if _cool <= 0.0:
			state = State.READY
	if state == State.READY:
		_scan_tick += 1
		if _scan_tick % 4 == 0:
			_scan()
	if state != State.ATTACHED:
		_update_audio(dt)
		return
	if target == null or not is_instance_valid(target) or not target.is_inside_tree():
		release()
		return
	var anchor := anchor_global()
	# Anchor teleported (respawned container, a node moved by code): let go.
	if anchor.distance_to(_prev_anchor) > 5.0 * Game.PX_PER_M:
		release()
		return
	_prev_anchor = anchor
	var eye := eye_global()
	var dvec := anchor - eye
	var d := dvec.length() / Game.PX_PER_M
	var dir := dvec / maxf(dvec.length(), 0.001)
	var vd := 0.0 if _prev_d < 0.0 else (d - _prev_d) / dt
	_prev_d = d
	# Winch.
	winch_state = ""
	if reel:
		if tension_n > STALL_N:
			winch_state = "STALL"
		else:
			length_m = maxf(MIN_LEN_M, length_m - REEL_MPS * dt)
			winch_state = "IN"
	var e := d - length_m
	var raw := maxf(0.0, K * e + C * vd) if e > 0.0 else 0.0
	slipping = false
	var applied := raw
	if raw > CLUTCH_N and length_m < MAX_LEN_M:
		# Slip clutch: pay out line rather than pull harder.
		length_m = minf(MAX_LEN_M, length_m + minf(PAYOUT_MPS * dt, maxf(0.0, e - CLUTCH_N / K)))
		applied = CLUTCH_N
		slipping = true
	applied = minf(applied, CLUTCH_N)
	# Snap: held over the limit at full length, or one brutal spike.
	if length_m >= MAX_LEN_M and raw > SNAP_N:
		_over_t += dt
	else:
		_over_t = 0.0
	if _over_t >= 0.15 or raw > SPIKE_N:
		_snap()
		return
	tension_n = applied
	if applied > 0.0:
		ship_force = dir * applied
		# Third law: the other end gets the opposite pull (free rigid bodies
		# only; structure and kinematic traffic just hold).
		if target is RigidBody2D and not (target as RigidBody2D).freeze:
			var rb := target as RigidBody2D
			rb.sleeping = false
			rb.apply_force(-dir * applied * Game.PX_PER_M, anchor - rb.global_position)
	_update_audio(dt)


## Fan of 9 rays (+-20 deg) from the nose along the aim direction.
func _scan() -> void:
	_scan_hit = {}
	if ship == null:
		return
	var space := ship.get_world_2d().direct_space_state
	var from := ship.to_global(Vector2(70, 0))
	var best := INF
	for i in 9:
		var a := aim_dir.angle() + deg_to_rad(-20.0 + i * 5.0)
		var to := from + Vector2.from_angle(a) * RANGE_M * Game.PX_PER_M
		var q := PhysicsRayQueryParameters2D.create(from, to, Game.LAYER_WORLD | Game.LAYER_PROPS | Game.LAYER_TRAFFIC, [ship.get_rid()])
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var dist: float = from.distance_to(hit.position)
		if dist < best:
			best = dist
			_scan_hit = {"pos": hit.position, "collider": hit.collider, "kind": _kind(hit.collider)}


static func _kind(c: Object) -> String:
	if c is RigidBody2D and not (c as RigidBody2D).freeze:
		return "CARGO"
	if c is CollisionObject2D and ((c as CollisionObject2D).collision_layer & Game.LAYER_TRAFFIC) != 0:
		return "TRAFFIC"
	if c is AnimatableBody2D:
		return "MOVING"
	return "STRUCTURE"


func _play(n: String, db: float) -> void:
	var s: AudioStream = _snd.get(n)
	if s == null or not is_inside_tree():
		return
	var p := AudioStreamPlayer2D.new()
	p.stream = s
	p.bus = GameplayUtil.bus(&"SFX")
	p.volume_db = db
	p.max_distance = 1500.0
	add_child(p)
	p.global_position = eye_global() if ship else global_position
	p.finished.connect(p.queue_free)
	p.play()


func _update_audio(_dt: float) -> void:
	var k := clampf(tension_n / CLUTCH_N, 0.0, 1.0)
	_set_loop(_loop_tension, k > 0.05, lerpf(-30.0, -8.0, k), 0.8 + 0.5 * k)
	_set_loop(_loop_clutch, slipping, -6.0, 1.0)
	_set_loop(_loop_winch, winch_state == "IN", -12.0, 1.0)


func _set_loop(p: AudioStreamPlayer2D, on: bool, db: float, pitch: float) -> void:
	if p == null:
		return
	if ship:
		p.global_position = eye_global()
	if on:
		if not p.playing:
			p.play()
		p.volume_db = move_toward(p.volume_db, db, 3.0)
		p.pitch_scale = pitch
	elif p.playing:
		p.volume_db -= 4.0
		if p.volume_db < -50.0:
			p.stop()


# ----------------------------------------------------------------- draw --

func _process(delta: float) -> void:
	_fire_t = minf(1.0, _fire_t + delta / 0.08)
	_dry_t = minf(1.0, _dry_t + delta / 0.3)
	_whip_t = minf(1.0, _whip_t + delta / 0.25)
	queue_redraw()


func _draw() -> void:
	if ship == null or not is_instance_valid(ship) or not ship.is_inside_tree():
		return
	var pen := OnFootPainter.new(self, 0.6)
	var eye := eye_global()
	if ship.has_method(&"render_transform"):
		var rx: Transform2D = ship.call(&"render_transform")
		eye = rx * eye_local
	var show_aim := Game.player == ship and Game.mode == Game.Mode.FLIGHT and bool(ship.get(&"controls_enabled"))
	match state:
		State.ATTACHED:
			var a := anchor_global()
			var tip := eye.lerp(a, _fire_t)
			var col := Color("2A9D8F").lerp(Color("7FE6FF"), 0.4)
			if tension_n > STALL_N:
				col = OnFootArt.AMBER
			if slipping or tension_n >= CLUTCH_N:
				col = OnFootArt.NAV_RED if fmod(_t, 0.16) < 0.08 else OnFootArt.AMBER
			pen.polyline(_rope(eye, tip), Color(0, 0.01, 0.03, 0.5), 2.6)
			pen.polyline(_rope(eye, tip), col, 1.4)
			pen.circle(a, 3.2, Color(0.75, 0.95, 1.0), OnFootArt.INK, 0.6, 12)
			pen.circle(a, 1.4, col, Color(0, 0, 0, 0), 0.3, 10)
		State.READY:
			if show_aim and not _scan_hit.is_empty():
				var p: Vector2 = _scan_hit.pos
				_dashes(pen, eye, p, Color(0.5, 0.9, 1.0, 0.35))
				var r := 6.0 + sin(_t * 8.0) * 0.8
				pen.polyline(PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)]), Color(0.5, 0.95, 1.0, 0.9), 1.2, true)
			elif show_aim:
				var p := eye + aim_dir * RANGE_M * Game.PX_PER_M
				pen.polyline(PackedVector2Array([p + Vector2(0, -4), p + Vector2(4, 0), p + Vector2(0, 4), p + Vector2(-4, 0)]), Color(0.7, 0.75, 0.8, 0.35), 1.0, true)
	if _dry_t < 1.0:
		var k := sin(_dry_t * PI)
		pen.line(eye, eye + aim_dir * RANGE_M * Game.PX_PER_M * k, Color(0.6, 0.9, 1.0, 0.5), 1.0)
	if _whip_t < 1.0:
		var k := 1.0 - _whip_t
		var m := _whip_from.lerp(_whip_to, 0.5)
		pen.line(_whip_from, _whip_from.lerp(m, k), Color(1.0, 0.5, 0.3, k), 1.4)
		pen.line(_whip_to, _whip_to.lerp(m, k), Color(1.0, 0.5, 0.3, k), 1.4)
	pen.flush()


## 16-segment rope: sags sideways when slack (amplitude from spare length).
func _rope(a: Vector2, b: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var d := a.distance_to(b)
	var L := length_m * Game.PX_PER_M
	var sag := 0.5 * sqrt(maxf(0.0, L * L - d * d))
	var n := (b - a).orthogonal().normalized()
	for i in 17:
		var t := i / 16.0
		pts.append(a.lerp(b, t) + n * sin(t * PI) * sag)
	return pts


func _dashes(pen: OnFootPainter, a: Vector2, b: Vector2, col: Color) -> void:
	var d := a.distance_to(b)
	if d < 1.0:
		return
	var dir := (b - a) / d
	var s := 0.0
	while s < d:
		pen.line(a + dir * s, a + dir * minf(s + 6.0, d), col, 0.9)
		s += 12.0
