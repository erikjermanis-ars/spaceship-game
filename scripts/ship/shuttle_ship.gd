class_name ShuttleShip
extends PlayerShip
## PETREL: a heavy cargo hover shuttle.
##
## It flies the WREN's model (PlayerShip): W at the throttle setting, S retro,
## A/D turn thrusters, Q/E strafe, F flight assist. Its numbers make it a
## heavy hauler (2.6 t, ~4.6 m/s² at full throttle, slow to spin up), and its
## turn thrusters fire as a COUPLE: the bow quads push one way, the stern
## quads the other, so it pivots in place instead of swinging out.
## On top of that:
##   * Space = HOVER: station-keeping RCS brakes you to a stop with the
##     heading held; W/S and Q/E slide, A/D yaw slowly. Keep holding over any
##     station deck and it descends onto magnetic skids: LAND ANYWHERE.
##   * LMB / V = mag-line (MagLine): hook cargo, structure, traffic;
##     RMB / B reels in. L = floodlights.
## Altitude is a fake Z (metres) that only drives landing and visuals;
## collisions stay 2D.

signal touched_down(grade: String)
signal lifted_off
signal landing_aborted(reason: String)

enum Land { CRUISE, HOVER, DESCENT, LANDED, LIFTING }

## Hull (local px), the collision shape. Nose = +X.
const HULL := [Vector2(70, 0), Vector2(60, -14), Vector2(52, -21.6), Vector2(38, -26.8), Vector2(25, -29.1), Vector2(4.6, -31), Vector2(-15.4, -31), Vector2(-38, -35.8), Vector2(-66, -29), Vector2(-66, 29), Vector2(-38, 35.8), Vector2(-15.4, 31), Vector2(4.6, 31), Vector2(25, 29.1), Vector2(38, 26.8), Vector2(52, 21.6), Vector2(60, 14)]

## Where you step out (local metres): door, mid-ramp and ramp foot on the
## port side. Landing needs deck and clear space there too.
const RAMP_POINTS := [Vector2(-0.5, -3.6), Vector2(-0.5, -4.6), Vector2(-0.5, -6.0)]

## The PETREL's flight model: the "PETREL default" tuning preset and what
## the ship starts with (applied in _init; the scene doesn't override these).
const PETREL_DEFAULTS := {
	"main_thrust_n": 12000.0, "reverse_scale": 0.3, "side_thrust_n": 3400.0,
	"thrust_point_m": 5.0, "strafe_thrust_n": 3600.0, "turn_couple": 1.0, "stern_point_m": 4.6,
	"mass_kg": 2600.0, "inertia_per_mass_m2": 14.0, "linear_drag": 0.1, "angular_drag": 0.8,
	"bounce": 0.05, "friction": 0.3, "throttle_rate": 0.35,
	"assist_rot_gain": 2.0, "assist_slip_gain": 0.8,
}

@export_group("PETREL engines")
## Stern engine bells (port one mirrored), for visuals and the debug overlay.
@export var engine_pos_m := Vector2(-6.6, 1.4)
@export_group("PETREL hover & landing")
@export var hover_brake := 2.0          ## 1/s
@export var hover_nudge_n := 5200.0
@export var hover_cap_n := 14000.0
## A/D yaw rate of the held heading while hovering (rad/s).
@export var hover_yaw_rate := 0.5
## Heading-hold controller (critically damped, capped by the turn thrusters).
@export var hover_hold_kp := 9.0
@export var hover_hold_kd := 6.0
@export var cruise_alt_m := 3.0
@export var descent_mps := 2.2
@export var max_land_speed := 2.0
@export var max_land_spin := 0.3
@export var tow_eye_m := Vector2(-1.0, 0.0)

# ---- live state (HUD / FX / audio read these) ----
var aim_dir := Vector2.RIGHT
var hover_strength := 0.0
var engine_out := Vector2.ZERO          ## port, starboard main engine (0..1 of full)
## Fore/aft RCS push while hovering, fraction of side thrust (+ = forward).
var long_rcs_output := 0.0
var altitude_m := 3.0
var skids := 0.0                        ## 0 up .. 1 down
var land_state: Land = Land.CRUISE
var land_ok := false
var land_status := ""
var skid_ok: Array = [true, true, true, true]
var probe := {}
var floodlights := false
var last_grade := ""
var line: MagLine

var _hover_heading := 0.0
var _hover_ok_t := 0.0
var _probe_t := 0.0
var _wants_move := false
var _lift_block_t := 0.0
var _mouse_t := 99.0
var _hull_px := PackedVector2Array()
var _snd := {}


func _init() -> void:
	for k in PETREL_DEFAULTS:
		set(k, PETREL_DEFAULTS[k])
	throttle_default = 0.5


func _ready() -> void:
	_hull_px = PackedVector2Array(HULL)
	super._ready()
	line = MagLine.new()
	line.name = "MagLine"
	line.ship = self
	line.eye_local = tow_eye_m * PX
	add_child(line)
	line.snapped.connect(func() -> void:
		if Game.camera and Game.camera.has_method(&"add_trauma"):
			Game.camera.call(&"add_trauma", 0.3))
	contact_impact.connect(func(_p: Vector2, _n: Vector2, speed: float, _o: Node) -> void:
		if speed >= 12.0 and line.is_attached():
			line.release())
	for n in ["skids_deploy", "landing_chime_silk", "landing_abort_warble", "liftoff_whoosh"]:
		_snd[n] = GameplayUtil.load_audio(n + ".wav")
	_snd["clunk"] = GameplayUtil.load_variations("touchdown_clunk_", 4, 1.05, 1.5)
	if not start_as_player:
		_go_home.call_deferred()


## Session start: parked on the hangar berth, landed, nobody aboard (shown
## with its detailed landed model).
func _go_home() -> void:
	start_landed()
	# Levels without a berth (test sandboxes): stay where the scene put us.
	if get_tree().get_first_node_in_group(&"shuttle_berth") != null:
		global_transform = home_transform()
	_tick_xf = global_transform
	_tick_prev_xf = global_transform
	park()
	var vis := get_node_or_null(^"Visuals") as CanvasItem
	if vis:
		vis.visible = false
	landed_model()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_t = 0.0


# ================================================================ vehicle

func ship_id() -> StringName:
	return &"petrel"


func uses_pad_clamps() -> bool:
	return false


func make_landed_model() -> Node2D:
	return ShuttleLanded.new()


func can_disembark() -> bool:
	return Game.player == self and alive and land_state == Land.LANDED


func disembark_hint() -> String:
	if land_state == Land.LANDED:
		return ""
	return "Land first  ·  hold Space over a deck"


## Boarded on the ground: stay landed (frozen) until a lift-off input.
func on_boarded() -> void:
	controls_enabled = true


func park() -> void:
	super.park()
	_zero_outputs()
	if line:
		line.release(true)


## Nothing firing: used whenever the flight model stops running (landed,
## parked, dead), so FX/audio/HUD don't keep showing the last thrust.
func _zero_outputs() -> void:
	engine_out = Vector2.ZERO
	long_rcs_output = 0.0
	throttle_input = 0.0
	turn_input = 0.0
	strafe_input = 0.0
	main_output = 0.0
	bow_lateral_output = 0.0
	stern_lateral_output = 0.0


## Respawn / berth: brought back landed and unpowered on the hangar floor.
func home_transform() -> Transform2D:
	var berth := get_tree().get_first_node_in_group(&"shuttle_berth") as Node2D
	if berth:
		return berth.global_transform
	return super.home_transform()


## Start of session (and after a respawn at home): sitting on its skids.
func start_landed() -> void:
	_zero_outputs()
	land_state = Land.LANDED
	altitude_m = 0.0
	skids = 1.0
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	freeze_mode = RigidBody2D.FREEZE_MODE_STATIC
	freeze = true


func respawn_at(xform: Transform2D) -> void:
	if line:
		line.release(true)
	super.respawn_at(xform)
	land_state = Land.CRUISE
	altitude_m = cruise_alt_m
	skids = 0.0
	_zero_outputs()
	# Home is the hangar berth: arrive landed there, fly from a race gate.
	if xform.origin.distance_to(home_transform().origin) < 1.0:
		start_landed.call_deferred()


## Hooked cargo or a planned shove with the towed load hurts less.
func damage_scale(other: Node, _speed_mps: float) -> float:
	if line and line.is_attached() and other == line.target:
		return 0.4
	return 1.0


func destroy() -> void:
	if line:
		line.release(true)
	land_state = Land.CRUISE
	super.destroy()
	_zero_outputs()


# ================================================================== input

func _controls_active() -> bool:
	return controls_enabled and alive and powered and Game.player == self and Game.mode == Game.Mode.FLIGHT


func _read_input(delta: float) -> void:
	super._read_input(delta)
	var active := _controls_active()
	_wants_move = active and (_raw_fwd > 0.2 or _raw_rev > 0.2 or absf(turn_input) > 0.2 or absf(strafe_input) > 0.2)
	hover_strength = _act(&"ship_hover") if active else 0.0
	if land_state == Land.LANDED:
		# Sitting on the skids: inputs only mean "lift off" (_tick_landing).
		throttle_input = 0.0
		turn_input = 0.0
		strafe_input = 0.0
	elif land_state == Land.HOVER or land_state == Land.DESCENT:
		# A/D swing the held heading slowly (line the ramp up to land).
		_hover_heading = wrapf(_hover_heading + turn_input * hover_yaw_rate * delta, -PI, PI)
	if active and Input.is_action_just_pressed(&"ship_lights"):
		floodlights = not floodlights
		GameplayUtil.play_oneshot(self, GameplayUtil.load_audio("switch_click.wav"), -10.0, 1.2, &"UI")
	_update_aim(active)
	# Mag-line: hold to stay hooked, release to let go.
	if line:
		if active and _act(&"ship_line") > 0.5:
			if line.state == MagLine.State.READY and Input.is_action_just_pressed(&"ship_line"):
				line.fire()
		elif line.is_attached():
			line.release()
	_mouse_t += delta


## Aim: right stick > recent mouse > nose.
func _update_aim(active: bool) -> void:
	var stick := Vector2(Input.get_axis(&"aim_left", &"aim_right"), Input.get_axis(&"aim_up", &"aim_down"))
	if active and stick.length() > 0.35:
		aim_dir = stick.normalized()
		var cam := Game.camera as CameraRig
		if cam and cam.rotate_with_ship:
			aim_dir = aim_dir.rotated(cam.rotation)
	elif active and (_mouse_t < 2.0 or Input.is_action_pressed(&"ship_line")) and get_viewport() != null:
		var to := get_global_mouse_position() - global_position
		if to.length() > 1.0:
			aim_dir = to.normalized()
	else:
		aim_dir = Vector2.from_angle(global_rotation)
	if line:
		line.aim_dir = aim_dir


# ================================================================ physics

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_tick_landing(delta)
	if line:
		line.physics_tick(delta, controls_enabled and Game.player == self and _act(&"ship_reel") > 0.5)
	if freeze or not alive:
		_zero_outputs()


func _apply_flight_forces(state: PhysicsDirectBodyState2D, xf: Transform2D, v: Vector2, w: float) -> void:
	if land_state == Land.HOVER or land_state == Land.DESCENT:
		_apply_hover_forces(state, xf, v, w)
	else:
		# Cruise: exactly the WREN's model with the PETREL's numbers.
		super._apply_flight_forces(state, xf, v, w)
		long_rcs_output = 0.0
	var eng := maxf(main_output, 0.0)
	engine_out = Vector2(eng, eng)
	# ---- mag-line pull at the tow eye ----
	if line and line.ship_force != Vector2.ZERO:
		state.apply_force(line.ship_force * PX, xf.basis_xform(tow_eye_m * PX))


## Hover / descent: station-keeping RCS brakes to a stop and the turn
## thrusters hold the heading; W/S and Q/E nudge (ship frame), A/D yaw the
## held heading (see _read_input). Main engine off.
func _apply_hover_forces(state: PhysicsDirectBodyState2D, xf: Transform2D, v: Vector2, w: float) -> void:
	var fwd := xf.x.normalized()
	var right := xf.y.normalized()
	var v_si := v / PX
	var nudge := fwd * (_raw_fwd - _raw_rev) + right * strafe_input
	var f_rcs := -mass_kg * hover_brake * hover_strength * v_si + nudge.limit_length(1.0) * hover_nudge_n
	f_rcs = f_rcs.limit_length(hover_cap_n)
	var i_si := mass_kg * inertia_per_mass_m2
	var max_t := max_turn_torque_nm()
	var err := wrapf(_hover_heading - xf.get_rotation(), -PI, PI)
	var tau := clampf(i_si * (hover_hold_kp * err - hover_hold_kd * w), -max_t, max_t)
	state.apply_central_force(f_rcs * PX)
	state.apply_torque(tau * PX * PX)
	state.apply_central_force(-v * mass_kg * linear_drag)
	state.apply_torque(-inertia * angular_drag * w)
	# ---- outputs: RCS quads split the push; the hold torque is a couple ----
	main_output = 0.0
	var lat := f_rcs.dot(right) / maxf(side_thrust_n, 1.0)
	var couple := tau / maxf(max_t, 1.0)
	bow_lateral_output = lat * 0.5 + couple * 0.5
	stern_lateral_output = lat * 0.5 - couple * 0.5
	long_rcs_output = f_rcs.dot(fwd) / maxf(side_thrust_n, 1.0)
	dbg_main_force = Vector2.ZERO
	dbg_side_force = Vector2.ZERO
	dbg_strafe_force = f_rcs
	dbg_assist_torque = tau


## Which RCS quad groups fire, 0..~1 each (ShuttleVisuals puffs and
## ShuttleAudio hiss/puffs read this): bow port, bow starboard, stern port,
## stern starboard, aft-pushing (bow quads firing forward: S retro, hover
## braking) and fore-pushing (stern quads firing aft: hover). + lateral output
## = push to starboard = gas out of the PORT quad.
func rcs_levels() -> PackedFloat32Array:
	var bow := bow_lateral_output
	var stern := stern_lateral_output
	var retro := maxf(-main_output, 0.0) / maxf(reverse_scale, 0.05)
	return PackedFloat32Array([
		maxf(bow, 0.0), maxf(-bow, 0.0), maxf(stern, 0.0), maxf(-stern, 0.0),
		maxf(-long_rcs_output, 0.0) + retro, maxf(long_rcs_output, 0.0)])


func thrust_point_local() -> Vector2:
	return Vector2(engine_pos_m.x * PX, 0.0)


func hull_polygon() -> PackedVector2Array:
	return _hull_px


# ================================================================ landing

func _tick_landing(delta: float) -> void:
	if not alive:
		return
	var hovering := hover_strength > 0.1 and Game.player == self
	var speed := linear_velocity.length() / PX
	# Probe: every tick while landing, 10 Hz when slow enough to care.
	_probe_t -= delta
	var need := land_state == Land.HOVER or land_state == Land.DESCENT
	if need or (speed < 6.0 and _probe_t <= 0.0 and land_state != Land.LANDED):
		_probe_t = 0.1
		probe = LandingProbe.check(self, _hull_px, max_land_speed, max_land_spin, RAMP_POINTS)
		land_ok = bool(probe.ok)
		land_status = String(probe.text)
		skid_ok = probe.skid_ok
	elif speed >= 6.0 and not need:
		probe = {}
		land_status = ""
	match land_state:
		Land.CRUISE:
			altitude_m = move_toward(altitude_m, cruise_alt_m, 2.0 * delta)
			skids = move_toward(skids, 0.0 if altitude_m > 2.0 else skids, delta * 4.0)
			if hovering:
				_enter_hover()
		Land.HOVER:
			altitude_m = move_toward(altitude_m, maxf(1.2, minf(altitude_m, cruise_alt_m)), 2.0 * delta)
			if altitude_m < 1.2:
				altitude_m = move_toward(altitude_m, 1.2, 2.0 * delta)
			if not hovering:
				land_state = Land.CRUISE
			elif land_ok:
				_hover_ok_t += delta
				if _hover_ok_t >= 0.25:
					land_state = Land.DESCENT
					if line and line.is_attached():
						line.release(true)
						Game.toast("LINE STOWED", 1.2)
			else:
				_hover_ok_t = 0.0
		Land.DESCENT:
			var lat := speed
			if not hovering:
				_abort("released")
				return
			if lat > max_land_speed:
				_abort("TOO FAST")
				return
			if not land_ok:
				_abort(land_status.get_slice("  ", 0))
				return
			var rate := descent_mps
			if altitude_m < 0.6:
				rate = 0.5 if lat < 0.6 else 1.5
			altitude_m -= rate * delta
			if altitude_m < 2.0:
				if skids < 0.01:
					_play("skids_deploy", -6.0)
				skids = move_toward(skids, 1.0, delta * 4.0)
			if altitude_m <= 0.0:
				_touch_down(lat)
		Land.LANDED:
			altitude_m = 0.0
			skids = 1.0
			if Game.player == self and controls_enabled and powered and Game.mode == Game.Mode.FLIGHT:
				_lift_block_t -= delta
				if _wants_move and _lift_block_t <= 0.0:
					_lift_off()
		Land.LIFTING:
			altitude_m = move_toward(altitude_m, cruise_alt_m, cruise_alt_m / 0.8 * delta)
			if altitude_m > 2.0:
				skids = move_toward(skids, 0.0, delta * 4.0)
			if altitude_m >= cruise_alt_m:
				land_state = Land.CRUISE


func _enter_hover() -> void:
	land_state = Land.HOVER
	_hover_heading = global_rotation
	_hover_ok_t = 0.0


func _abort(reason: String) -> void:
	land_state = Land.HOVER if hover_strength > 0.1 else Land.CRUISE
	_hover_ok_t = 0.0
	_play("landing_abort_warble", -10.0)
	if reason != "released":
		Game.toast("LANDING ABORTED  ·  %s" % reason, 1.6)
	landing_aborted.emit(reason)


func _touch_down(lat: float) -> void:
	altitude_m = 0.0
	skids = 1.0
	var grade := "SILK" if lat < 0.35 else ("FIRM" if lat < 1.0 else "SKID")
	if grade == "SKID":
		take_damage(3.0 + 4.0 * (lat - 1.0), global_position)
		if not alive:
			return   # the touchdown finished it off: no landing
		Game.scrape.emit(global_position, Vector2.UP, lat, self)
	# Pads: free services and a bonus for nailing the centre.
	var on_pad := false
	var bull := false
	for n in get_tree().get_nodes_in_group(&"docking_pad"):
		var pad := n as Area2D
		if WalkSite._pad_contains(pad, global_position):
			on_pad = true
			bull = global_position.distance_to(pad.global_position) < 0.6 * PX
	if bull:
		grade = "BULLSEYE"
	last_grade = grade
	land_state = Land.LANDED
	_lift_block_t = 0.4
	# Stop dead where we are (the teleport path zeroes velocities in the
	# physics callback), then freeze: magnetic skids hold the ship.
	_teleport_xform = global_transform
	_pending_teleport = true
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	_zero_outputs()
	freeze_mode = RigidBody2D.FREEZE_MODE_STATIC
	set_deferred(&"freeze", true)
	for i in 4:
		get_tree().create_timer(0.04 * i, false).timeout.connect(func() -> void: _play_stream(_snd.get("clunk"), -5.0))
	if grade == "SILK" or grade == "BULLSEYE":
		_play("landing_chime_silk", -8.0)
	if Game.camera and Game.camera.has_method(&"punch"):
		Game.camera.call(&"punch", Vector2.DOWN, 3.0)
	var deck := String(probe.get("deck_name", "deck"))
	if on_pad:
		repair(max_hull)
		Game.toast("%s  ·  LANDED · %s  ·  pad services: hull repaired" % [grade, deck], 3.0)
	else:
		Game.toast("%s  ·  LANDED · %s  ·  X get out · move to lift off" % [grade, deck], 3.0)
	touched_down.emit(grade)


func _lift_off() -> void:
	# Never lift off into something: a container on the skids blocks us, a
	# wall overlap nudges us clear first.
	var q := PhysicsShapeQueryParameters2D.new()
	var shape := ConvexPolygonShape2D.new()
	shape.set_point_cloud(_hull_px)
	q.shape = shape
	q.transform = global_transform
	q.collision_mask = Game.LAYER_PROPS
	q.exclude = [get_rid()]
	if not get_world_2d().direct_space_state.intersect_shape(q, 1).is_empty():
		Game.toast("OBSTRUCTED  ·  clear the skids", 1.4)
		_lift_block_t = 1.0
		return
	land_state = Land.LIFTING
	_contacts_prev.clear()
	_prev_lin_vel = Vector2.ZERO
	_prev_ang_vel = 0.0
	_pending_teleport = false
	collision_layer = Game.LAYER_PLAYER
	set_deferred(&"freeze", false)
	_play("liftoff_whoosh", -6.0)
	lifted_off.emit()


func _play(n: String, db: float) -> void:
	_play_stream(_snd.get(n), db)


func _play_stream(s: AudioStream, db: float) -> void:
	if s == null or not is_inside_tree():
		return
	var p := AudioStreamPlayer2D.new()
	p.stream = s
	p.bus = GameplayUtil.bus(&"SFX")
	p.volume_db = db
	p.max_distance = 1600.0
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
