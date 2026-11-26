class_name DockingSystem
extends Node
## Docking pads (Area2D in group `docking_pad`). Settle on a pad slowly,
## without spinning, roughly aligned with its +X (either way round), and hold
## for HOLD_TIME to dock: clamps engage, hull is repaired, boost refilled.
##
## A pad only arms when the ship flies onto it from outside, so sitting on
## the spawn pad (at start or after a respawn) doesn't "dock", and guidance
## only appears below HINT_SPEED so fly-overs stay quiet.

enum Phase { NONE, APPROACH, HOLDING, DOCKED }

const MAX_SPEED := 1.5          ## m/s
const MAX_SPIN := 0.15          ## rad/s
const MAX_ANGLE_DEG := 25.0     ## alignment tolerance (either direction)
const HOLD_TIME := 1.5
const HINT_SPEED := 6.0         ## m/s: above this you are just flying over

var phase := Phase.NONE
var progress := 0.0              ## 0..1 hold progress (HUD/indicator)
var pad_name := ""
var hint := ""                   ## what the pilot still needs to fix
var current_pad: Area2D

var _pads: Array[Area2D] = []
var _armed := false              # current pad was entered from outside
var _outside_time := 0.0         # s spent off every pad since (re)spawn
## Area2D overlaps only update after a physics step, so the first frames
## after spawning always look "outside"; require a real excursion.
const MIN_OUTSIDE_TIME := 0.4
var _scan_timer := 0.0
var _redock_check := false       # just switched ships: dock in place if settled on a pad
var _clamped := false            # clamp spring currently holding the ship
var _snd_clamp: AudioStream
var _snd_chime: AudioStream
var _indicator: DockingIndicator

func _ready() -> void:
	add_to_group(&"docking_system")
	_snd_clamp = GameplayUtil.load_audio("dock_clamp.wav")
	_snd_chime = GameplayUtil.load_audio("dock_chime.wav")
	_indicator = DockingIndicator.new()
	_indicator.system = self
	add_child(_indicator)
	Game.ship_destroyed.connect(func(_p: Vector2) -> void: _leave())
	Game.ship_respawned.connect(func(_p: Vector2) -> void:
		_leave()
		_outside_time = 0.0)
	Game.player_changed.connect(func(_s: RigidBody2D, _o: RigidBody2D) -> void:
		_leave()
		_outside_time = 0.0
		# Boarding a ship that is parked on a pad: its clamps re-engage.
		_redock_check = true)

func pads() -> Array[Area2D]:
	return _pads


func is_docked() -> bool:
	return phase == Phase.DOCKED and current_pad != null


## True while docked with the clamps holding a settled ship (safe to get out).
func is_settled() -> bool:
	return is_docked() and _clamped and GameplayUtil.player_valid() \
		and Game.player.linear_velocity.length() < 0.6 * Game.PX_PER_M \
		and absf(Game.player.angular_velocity) < MAX_SPIN


## Quietly docked again (you climbed back into a ship parked on this pad).
func _resume_dock(pad: Area2D) -> void:
	current_pad = pad
	pad_name = String(pad.get_meta(&"pad_name", pad.name))
	_armed = true
	phase = Phase.DOCKED
	_clamped = true
	progress = 1.0
	hint = ""
	Game.docked.emit(pad_name)


## Test/debug hook: dock at `pad` immediately (the ship must already sit on it).
func force_dock(pad: Area2D) -> void:
	_leave()
	current_pad = pad
	pad_name = String(pad.get_meta(&"pad_name", pad.name))
	_armed = true
	_dock()

func _physics_process(delta: float) -> void:
	_scan_timer -= delta
	if _scan_timer <= 0.0:
		# Pads can be streamed in later; rescan occasionally (cheap).
		_scan_timer = 2.0
		_pads.clear()
		for n in get_tree().get_nodes_in_group(&"docking_pad"):
			if n is Area2D:
				_pads.append(n)
	if not GameplayUtil.player_alive():
		return
	var ship := Game.player
	# Ships with their own landing gear (the PETREL's mag-skids) don't use
	# pad clamps: its spring would fight their fly-by-wire.
	if ship.has_method(&"uses_pad_clamps") and not bool(ship.call(&"uses_pad_clamps")):
		if phase != Phase.NONE:
			_leave()
		return
	var pad := _pad_under(ship)
	if _redock_check and pad != null:
		_redock_check = false
		if ship.linear_velocity.length() / Game.PX_PER_M < MAX_SPEED:
			_resume_dock(pad)
			return
	elif _redock_check and _outside_time > 0.5:
		_redock_check = false
	if pad != current_pad:
		_leave()
		current_pad = pad
		if pad:
			pad_name = String(pad.get_meta(&"pad_name", pad.name))
			phase = Phase.APPROACH
			_armed = _outside_time >= MIN_OUTSIDE_TIME
	if pad == null:
		_outside_time += delta
		return
	var v := ship.linear_velocity.length() / Game.PX_PER_M
	if phase == Phase.DOCKED:
		_hold_clamp(ship, pad)
		return
	if not _armed or v > HINT_SPEED:
		phase = Phase.APPROACH
		hint = ""
		progress = 0.0
		return
	var spin := absf(ship.angular_velocity)
	var align := absf(Vector2.from_angle(ship.global_rotation).dot(Vector2.from_angle(pad.global_rotation)))
	var aligned := align >= cos(deg_to_rad(MAX_ANGLE_DEG))
	if v > MAX_SPEED:
		hint = "REDUCE SPEED  %.1f m/s" % v
	elif spin > MAX_SPIN:
		hint = "STOP ROTATION"
	elif not aligned:
		hint = "ALIGN WITH PAD"
	else:
		hint = ""
	if hint == "":
		phase = Phase.HOLDING
		progress = minf(1.0, progress + delta / HOLD_TIME)
		if progress >= 1.0:
			_dock()
	else:
		phase = Phase.APPROACH
		progress = maxf(0.0, progress - delta * 2.0)

## Docking clamps: while docked and the pilot is hands-off, the ship is drawn
## onto the pad centre and its heading (either way round) and held there.
## Any stick input releases it, with a clunk.
func _hold_clamp(ship: RigidBody2D, pad: Area2D) -> void:
	var hands_off := is_zero_approx(float(GameplayUtil.pget(ship, &"throttle_input", 0.0))) \
		and is_zero_approx(float(GameplayUtil.pget(ship, &"turn_input", 0.0))) \
		and is_zero_approx(float(GameplayUtil.pget(ship, &"strafe_input", 0.0)))
	if not hands_off:
		if _clamped:
			_clamped = false
			GameplayUtil.play_oneshot(self, _snd_clamp, -10.0, 1.25)
		return
	if not _clamped:
		# Re-clamp only once the pilot has settled again (no yanking a ship
		# that is drifting off the pad).
		if ship.linear_velocity.length() / Game.PX_PER_M > MAX_SPEED or absf(ship.angular_velocity) > MAX_SPIN * 2.0:
			return
		_clamped = true
		GameplayUtil.play_oneshot(self, _snd_clamp, -10.0, 0.9)
	# Velocity servo towards the pad centre, capped at 1 m/s so a ship that
	# docked near the edge is drawn in gently rather than yanked.
	var to_pad := pad.global_position - ship.global_position
	var v_want := (to_pad * 0.6).limit_length(1.0 * Game.PX_PER_M)
	ship.apply_central_force((v_want - ship.linear_velocity) * 2.5 * ship.mass)
	var heading := pad.global_rotation
	if absf(angle_difference(ship.global_rotation, heading)) > PI * 0.5:
		heading += PI
	var err := angle_difference(ship.global_rotation, heading)
	ship.apply_torque((err * 1.5 - ship.angular_velocity * 2.5) * ship.inertia)

func _pad_under(ship: RigidBody2D) -> Area2D:
	for p in _pads:
		if is_instance_valid(p) and p.monitoring and p.overlaps_body(ship):
			return p
	return null

func _dock() -> void:
	phase = Phase.DOCKED
	_clamped = true
	progress = 1.0
	hint = ""
	var ship := Game.player
	if ship.has_method(&"repair"):
		ship.call(&"repair", float(GameplayUtil.pget(ship, &"max_hull", 100.0)))
	if ship.has_method(&"refill_boost"):
		ship.call(&"refill_boost")
	GameplayUtil.play_oneshot(self, _snd_clamp, -2.0)
	var t := get_tree().create_timer(0.35, false)
	t.timeout.connect(func() -> void: GameplayUtil.play_oneshot(self, _snd_chime, -4.0, 1.0, &"UI"))
	if Game.camera and Game.camera.has_method(&"add_trauma"):
		Game.camera.call(&"add_trauma", 0.12)
	Game.docked.emit(pad_name)
	Game.toast("DOCKED AT %s — hull repaired, boost refilled" % pad_name.to_upper(), 3.5)

func _leave() -> void:
	if phase == Phase.DOCKED:
		Game.undocked.emit(pad_name)
	_armed = false
	_clamped = false
	phase = Phase.NONE
	progress = 0.0
	hint = ""
	current_pad = null
