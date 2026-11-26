class_name PlayerShip
extends RigidBody2D
## The player's courier. Flight model = Pat Kerr's "Motion Lab" ship,
## side-thruster variant: a barbell (light thruster head + 2x heavier payload,
## 6 m apart) with ALL thrust applied at the head, 4 m ahead of the centre of
## mass. A sideways push at the bow both rotates the ship and shoves the whole
## craft sideways, which is what gives it that swinging, drifting, counter-steer
## feel. Drag is applied as explicit forces (terminal speed = thrust / (m*k)).
##
## The main engine runs at a THROTTLE SETTING (0-100 %, Shift raises it,
## Ctrl/Z lowers it): W lights the engine at that setting. 50 % matches the
## old cruise thrust, 100 % the old boost.
##
## The PETREL (ShuttleShip) flies this same model with its own numbers; its
## turn thrusters fire as a couple (bow one way, stern the other, see
## turn_couple), so it pivots in place instead of swinging.
##
## Everything is tuned in SI units (metres, kg, newtons) and converted with
## Game.PX_PER_M (1 m = 10 px): forces x PX, torques/inertia x PX^2.
##
## Collision reporting: contact_monitor is on; every physics step we diff the
## contact list, compute the closing speed from the PRE-contact relative
## velocity at the contact point, and emit Game.impact / Game.scrape (queued
## and flushed from _physics_process so listeners never run inside the physics
## server's callback).

const GameScript := preload("res://scripts/autoload/game.gd")
const PX := GameScript.PX_PER_M

# --------------------------------------------------------------- tunables --
@export_group("Mass")
## Ship mass. Reference: 1000 kg.
@export_range(100.0, 20000.0, 10.0, "suffix:kg") var mass_kg := 1000.0:
	set(v):
		mass_kg = maxf(v, 1.0)
		_apply_mass()
## Moment of inertia per unit mass (barbell: 1/3 at +4 m, 2/3 at -2 m + body radius).
@export_range(0.5, 40.0, 0.01, "suffix:m²") var inertia_per_mass_m2 := 8.37:
	set(v):
		inertia_per_mass_m2 = maxf(v, 0.05)
		_apply_mass()

@export_group("Thrusters")
## Main engine thrust at 100 % throttle.
@export_range(0.0, 60000.0, 50.0, "suffix:N") var main_thrust_n := 10900.0
## Retro thrust (S) as a fraction of FULL main thrust. Retro is a fixed-power
## RCS burn: the throttle setting only drives the main engine.
@export_range(0.0, 1.5, 0.005) var reverse_scale := 0.275
## Lateral thrust of the bow RCS quads (applied at the thrust point).
@export_range(0.0, 20000.0, 50.0, "suffix:N") var side_thrust_n := 2600.0
## Distance of the thrust point ahead of the centre of mass.
@export_range(0.0, 8.0, 0.05, "suffix:m") var thrust_point_m := 4.0
## Pure lateral thrust at the CoM (Q/E). Not in the reference model.
@export_range(0.0, 20000.0, 10.0, "suffix:N") var strafe_thrust_n := 2080.0
## Turn as a couple: the stern thrusters fire OPPOSITE the bow ones at this
## fraction of their thrust. 0 = bow only (turn AND slide sideways, the
## WREN), 1 = equal and opposite (pure rotation in place, the PETREL).
@export_range(0.0, 1.0, 0.01) var turn_couple := 0.0
## Distance of the stern turn thrusters behind the centre of mass.
@export_range(0.0, 8.0, 0.05, "suffix:m") var stern_point_m := 3.6
## How fast holding throttle up/down moves the setting (fraction per second).
@export_range(0.05, 3.0, 0.05, "suffix:/s") var throttle_rate := 0.5
## Throttle setting the ship starts (and respawns) with.
@export_range(0.0, 1.0, 0.05) var throttle_default := 0.5

@export_group("Drag")
## Linear drag coefficient: F = -m * k * v  (1/s).
@export_range(0.0, 2.0, 0.005, "suffix:1/s") var linear_drag := 0.12
## Angular drag coefficient: T = -I * k * omega  (1/s).
@export_range(0.0, 5.0, 0.01, "suffix:1/s") var angular_drag := 0.35

@export_group("Flight assist")
## How hard assist fights rotation (1/s). Capped by bow RCS authority.
@export_range(0.0, 20.0, 0.1, "suffix:1/s") var assist_rot_gain := 3.0
## How hard assist bleeds sideways slip (1/s). Capped by strafe thrust.
@export_range(0.0, 10.0, 0.1, "suffix:1/s") var assist_slip_gain := 1.2

@export_group("Collision")
## Godot SUMS the two materials' bounce (structure 0.3, containers 0.32), so
## a low ship value still gives ~0.35 restitution: crashes thud instead of
## pinballing, and the ship can stay in contact to push containers.
@export_range(0.0, 1.0, 0.01) var bounce := 0.05:
	set(v):
		bounce = v
		_apply_material()
@export_range(0.0, 1.0, 0.01) var friction := 0.2:
	set(v):
		friction = v
		_apply_material()
## Minimum closing speed for Game.impact.
@export var impact_min_speed_mps := 0.8
## Per-collider cooldown between impact events.
@export var impact_cooldown_s := 0.15
## Minimum tangential speed for Game.scrape.
@export var scrape_min_speed_mps := 1.0

## The WREN's flight model. Also the "WREN default" preset in the tuning
## panel (ShuttleShip.PETREL_DEFAULTS is the other one).
const WREN_DEFAULTS := {
	"main_thrust_n": 10900.0, "reverse_scale": 0.275, "side_thrust_n": 2600.0,
	"thrust_point_m": 4.0, "strafe_thrust_n": 2080.0, "turn_couple": 0.0, "stern_point_m": 3.6,
	"mass_kg": 1000.0, "inertia_per_mass_m2": 8.37, "linear_drag": 0.12, "angular_drag": 0.35,
	"bounce": 0.05, "friction": 0.2, "throttle_rate": 0.5,
	"assist_rot_gain": 3.0, "assist_slip_gain": 1.2,
}

# ------------------------------------------------------------ public API --
var hull: float = 100.0
var max_hull: float = 100.0
## Main engine throttle setting, 0..1 (Shift / Ctrl·Z). W fires at this.
var throttle_setting: float = 0.5
var flight_assist: bool = false
var alive: bool = true
var controls_enabled: bool = true
## False while parked with nobody aboard: engines and alarms are silent.
var powered: bool = true
## The ship the session starts in sets Game.player; other pilotable ships
## (the hangar shuttle) start parked and take over Game.player when boarded.
@export var start_as_player := true
## Shown on location cards and toasts.
@export var vehicle_name := "WREN"
## Reach of the prop sensor that caches neighbours' pre-contact velocity
## (must cover the hull: the frigate needs far more than the WREN).
var sensor_radius_m := 9.0
## Live input readouts for the HUD. throttle_input is the engine command:
## forward = W x throttle_setting (0..1), retro = -S (-1..0).
var throttle_input: float = 0.0   # -1..1
var turn_input: float = 0.0       # -1..1, negative = left / counter-clockwise
var strafe_input: float = 0.0     # -1..1, negative = left

## Thruster outputs for visuals/audio/debug. main_output is a fraction of
## FULL main thrust (1.0 = 100 % throttle; retro is negative, -reverse_scale
## at most). Lateral ones are fractions of side thrust. Lateral sign:
## + = force toward starboard (+Y), so the gas leaves on the PORT side.
var main_output: float = 0.0
var bow_lateral_output: float = 0.0
var stern_lateral_output: float = 0.0
## World-space forces of the last step in newtons (for the debug overlay):
## main and side act at the bow thrust point, strafe/assist at the CoM.
var dbg_main_force := Vector2.ZERO
var dbg_side_force := Vector2.ZERO
var dbg_strafe_force := Vector2.ZERO
var dbg_assist_torque := 0.0
## Recent contacts for the debug overlay: [{pos, normal, speed, time}]
var recent_contacts: Array[Dictionary] = []

signal contact_impact(pos: Vector2, normal: Vector2, speed_mps: float, other: Node)

# --------------------------------------------------------------- private --
var _raw_fwd := 0.0               # W / S as pressed (before the throttle setting)
var _raw_rev := 0.0
var _prev_lin_vel := Vector2.ZERO
var _prev_ang_vel := 0.0
var _contacts_prev := {}          # collider instance id -> true
var _impact_cooldowns := {}       # collider instance id -> seconds left
var _queued_impacts: Array[Dictionary] = []
var _queued_scrape := {}
var _last_scrape := {}            # bridges micro-bounces while sliding
var _scrape_grace := 0.0
var _pending_teleport := false
var _teleport_xform := Transform2D.IDENTITY
var _sensor_bodies := {}          # instance id -> RigidBody2D near the ship
var _sensor_vel := {}             # instance id -> [lin_vel, ang_vel] cached pre-step
var _sim_time := 0.0
var _material: PhysicsMaterial
## Body transforms seen by the last two _physics_process calls (a RigidBody's
## transform is synced from the server once per tick, before the scripts run).
## Rendering interpolates between them (see render_transform).
var _tick_prev_xf := Transform2D.IDENTITY
var _tick_xf := Transform2D.IDENTITY
@onready var _visuals: Node2D = get_node_or_null(^"Visuals") as Node2D

@onready var _collision: CollisionPolygon2D = $CollisionPolygon2D


func _ready() -> void:
	add_to_group(&"player_ship")
	if start_as_player:
		Game.player = self
	# Godot's own damping off: drag is applied as explicit forces.
	linear_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp = 0.0
	gravity_scale = 0.0
	can_sleep = false
	center_of_mass_mode = RigidBody2D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector2.ZERO
	continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	contact_monitor = true
	max_contacts_reported = 6
	collision_layer = Game.LAYER_PLAYER
	collision_mask = Game.LAYER_WORLD | Game.LAYER_PROPS | Game.LAYER_TRAFFIC
	z_index = Game.Z_SHIP
	z_as_relative = false
	throttle_setting = throttle_default
	_apply_mass()
	_apply_material()
	_build_sensor()
	if start_as_player:
		Game.hull_changed.emit(hull, max_hull)


func _apply_mass() -> void:
	mass = mass_kg
	inertia = mass_kg * inertia_per_mass_m2 * PX * PX


func _apply_material() -> void:
	if _material == null:
		_material = PhysicsMaterial.new()
	# Also re-claim it after a scene's own material (loaded after _init) lands.
	if physics_material_override != _material:
		physics_material_override = _material
	_material.bounce = bounce
	_material.friction = friction


## A slightly larger Area2D that tracks nearby rigid props so we know their
## velocity BEFORE a collision changes it (needed for honest closing speeds).
func _build_sensor() -> void:
	var area := Area2D.new()
	area.name = "ContactSensor"
	area.collision_layer = 0
	area.collision_mask = Game.LAYER_PROPS | Game.LAYER_TRAFFIC
	area.monitorable = false
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = sensor_radius_m * PX
	shape.shape = circle
	area.add_child(shape)
	add_child(area)
	area.body_entered.connect(func(b: Node2D) -> void:
		if b is RigidBody2D:
			_sensor_bodies[b.get_instance_id()] = b)
	area.body_exited.connect(func(b: Node2D) -> void:
		_sensor_bodies.erase(b.get_instance_id())
		_sensor_vel.erase(b.get_instance_id()))


# ------------------------------------------------------------- per frame --
func _physics_process(delta: float) -> void:
	_tick_prev_xf = _tick_xf
	_tick_xf = global_transform
	_sim_time += delta
	_flush_events()
	_read_input(delta)
	# Cache neighbour velocities before the physics step resolves contacts.
	for id in _sensor_bodies:
		var b: RigidBody2D = _sensor_bodies[id]
		if is_instance_valid(b):
			_sensor_vel[id] = [b.linear_velocity, b.angular_velocity, b.global_position]
	for id in _impact_cooldowns.keys():
		_impact_cooldowns[id] -= delta
		if _impact_cooldowns[id] <= 0.0:
			_impact_cooldowns.erase(id)
	# Age out debug contacts.
	while not recent_contacts.is_empty() and _sim_time - float(recent_contacts[0].time) > 2.5:
		recent_contacts.pop_front()


## Physics runs at 120 Hz but frames render at the display rate, with 0-3
## steps per frame. Drawing the ship (and following it with the camera) at the
## raw physics transform made the whole world judder; instead both use this
## transform, interpolated between the last two physics steps.
func render_transform() -> Transform2D:
	var xf := global_transform
	if not alive or not xf.is_equal_approx(_tick_xf) \
			or _tick_prev_xf.origin.distance_squared_to(_tick_xf.origin) > 2500.0 * 2500.0:
		return xf   # dead, moved outside a tick (teleport/respawn), or a jump
	return _tick_prev_xf.interpolate_with(_tick_xf, clampf(Engine.get_physics_interpolation_fraction(), 0.0, 1.0))


func _process(_delta: float) -> void:
	# The hull art sits at the interpolated transform (see render_transform).
	if _visuals:
		_visuals.transform = global_transform.affine_inverse() * render_transform()


## Override: may the pilot's inputs drive this ship right now?
func _controls_active() -> bool:
	return controls_enabled and alive


func _read_input(delta: float) -> void:
	var active := _controls_active()
	if Input.is_action_just_pressed(&"flight_assist") and active:
		flight_assist = not flight_assist
		Game.toast("Flight assist %s" % ("ON" if flight_assist else "OFF"), 1.6)

	var fwd := 0.0
	var rev := 0.0
	var trn := 0.0
	var stf := 0.0
	if active:
		var dthr := _act(&"throttle_up") - _act(&"throttle_down")
		if dthr != 0.0:
			throttle_setting = clampf(throttle_setting + dthr * throttle_rate * delta, 0.0, 1.0)
		fwd = _act(&"thrust_forward")
		rev = _act(&"thrust_reverse")
		trn = _act(&"turn_right") - _act(&"turn_left")
		stf = _act(&"strafe_right") - _act(&"strafe_left")
	_raw_fwd = fwd
	_raw_rev = rev
	# W fires the engine at the throttle setting; S is a fixed retro burn.
	throttle_input = clampf(fwd * throttle_setting - rev, -1.0, 1.0)
	turn_input = clampf(trn, -1.0, 1.0)
	strafe_input = clampf(stf, -1.0, 1.0)


## Input latch: actions held at the moment you take control (the E, Shift or
## W you were pressing on foot) read as 0 until released once.
var _latched := {}


func _act(action: StringName) -> float:
	if _latched.has(action):
		if Input.is_action_pressed(action):
			return 0.0
		_latched.erase(action)
	return Input.get_action_strength(action)


func _latch_held_actions() -> void:
	_latched.clear()
	for a in InputMap.get_actions():
		if not String(a).begins_with("ui_") and Input.is_action_pressed(a):
			_latched[a] = true


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if _pending_teleport:
		_pending_teleport = false
		state.transform = _teleport_xform
		state.linear_velocity = Vector2.ZERO
		state.angular_velocity = 0.0
		_prev_lin_vel = Vector2.ZERO
		_prev_ang_vel = 0.0
		_contacts_prev.clear()
		return

	_apply_flight_forces(state, state.transform, state.linear_velocity, state.angular_velocity)
	_process_contacts(state)
	_prev_lin_vel = state.linear_velocity
	_prev_ang_vel = state.angular_velocity


## Main engine force (N, along the nose) for an engine command (-1..1).
func main_force_n(cmd: float) -> float:
	return cmd * main_thrust_n * (reverse_scale if cmd < 0.0 else 1.0)


## Torque (N·m) the turn thrusters make at full deflection: bow thruster at
## thrust_point_m plus the opposing stern one (turn_couple) at stern_point_m.
func max_turn_torque_nm() -> float:
	return side_thrust_n * (thrust_point_m + turn_couple * stern_point_m)


## Override: this ship's flight model (forces, torques, HUD/FX outputs).
## Barbell: main and bow side thrust at the bow point; with turn_couple > 0
## the stern thrusters push the other way so the turn is (partly) a couple.
func _apply_flight_forces(state: PhysicsDirectBodyState2D, xf: Transform2D, v: Vector2, w: float) -> void:
	var fwd := xf.x.normalized()
	var right := xf.y.normalized()     # starboard
	var bow := fwd * thrust_point_m * PX   # global-oriented offset from the CoM
	var stern := -fwd * stern_point_m * PX

	# ---- main engine (at the bow thrust point, along the axis) ----
	var main_n := main_force_n(throttle_input)
	var f_main := fwd * main_n
	# ---- turn thrusters: bow pushes, stern (couple share) pushes back ----
	var side_n := turn_input * side_thrust_n
	var f_side := right * side_n
	var f_stern := -f_side * turn_couple
	# ---- strafe at the CoM ----
	var strafe_n := strafe_input * strafe_thrust_n
	var assist_torque := 0.0  # N·m
	var max_t := max_turn_torque_nm()
	if flight_assist:
		var inertia_si := mass_kg * inertia_per_mass_m2
		if is_zero_approx(turn_input):
			assist_torque = clampf(-inertia_si * assist_rot_gain * w, -max_t, max_t)
		if is_zero_approx(strafe_input):
			var slip_mps := v.dot(right) / PX
			strafe_n = clampf(-mass_kg * assist_slip_gain * slip_mps, -strafe_thrust_n, strafe_thrust_n)
	var f_strafe := right * strafe_n

	state.apply_force(f_main * PX, bow)
	state.apply_force(f_side * PX, bow)
	if turn_couple > 0.0:
		state.apply_force(f_stern * PX, stern)
	state.apply_central_force(f_strafe * PX)
	if assist_torque != 0.0:
		state.apply_torque(assist_torque * PX * PX)
	# ---- drag as forces (Godot damping is disabled) ----
	state.apply_central_force(-v * mass_kg * linear_drag)
	state.apply_torque(-inertia * angular_drag * w)

	# ---- outputs for FX / audio / debug ----
	main_output = main_n / maxf(main_thrust_n, 1.0)
	var side_frac := side_n / maxf(side_thrust_n, 1.0)
	var strafe_frac := strafe_n / maxf(side_thrust_n, 1.0)
	# Assist torque is a couple: bow pushes one way, stern the other.
	var couple := assist_torque / maxf(max_t, 1.0)
	bow_lateral_output = side_frac + strafe_frac * 0.5 + couple * 0.5
	stern_lateral_output = -side_frac * turn_couple + strafe_frac * 0.5 - couple * 0.5
	dbg_main_force = f_main
	dbg_side_force = f_side + f_stern
	dbg_strafe_force = f_strafe
	dbg_assist_torque = assist_torque


# ------------------------------------------------------------- contacts --
## Godot 4.7 (verified with tests/ship_contact_probe.gd):
##  * get_contact_local_position() returns the contact point in GLOBAL coords.
##  * get_contact_local_normal() points from the collider TOWARD this body.
##  * By the time this callback runs the solver has already changed our
##    velocity (bounce), so the pre-contact velocity is last step's.
func _process_contacts(state: PhysicsDirectBodyState2D) -> void:
	var now := {}
	var origin := state.transform.origin
	var best_scrape := 0.0
	for i in state.get_contact_count():
		var collider := state.get_contact_collider_object(i)
		if collider == null:
			continue
		var id := collider.get_instance_id()
		var p := state.get_contact_local_position(i)
		var n := state.get_contact_local_normal(i)
		if n.length_squared() < 0.5:
			continue
		var r := p - origin
		# Collider surface velocity (e.g. a rotating ring's rim). For rigid
		# props use the cached pre-step velocity; the solver already pushed them.
		var col_v := state.get_contact_collider_velocity_at_position(i)
		if _sensor_vel.has(id):
			var cached: Array = _sensor_vel[id]
			var cr: Vector2 = p - (cached[2] as Vector2)
			col_v = (cached[0] as Vector2) + Vector2(-cached[1] * cr.y, cached[1] * cr.x)
		var pre_v := _prev_lin_vel + Vector2(-_prev_ang_vel * r.y, _prev_ang_vel * r.x)
		var closing := -(pre_v - col_v).dot(n) / PX

		if not now.has(id):
			now[id] = true
			var is_new := not _contacts_prev.has(id)
			# A persistent contact can still be re-struck hard (bouncing along a wall).
			if (is_new and closing > impact_min_speed_mps) or (not is_new and closing > 3.0):
				if not _impact_cooldowns.has(id):
					_impact_cooldowns[id] = impact_cooldown_s
					_queued_impacts.append({"pos": p, "normal": n, "speed": closing, "other": collider})
					recent_contacts.append({"pos": p, "normal": n, "speed": closing, "time": _sim_time})
					if recent_contacts.size() > 12:
						recent_contacts.pop_front()

		# Scrape: tangential slip using post-solve velocities.
		var post_v := state.linear_velocity + Vector2(-state.angular_velocity * r.y, state.angular_velocity * r.x)
		var rel := post_v - state.get_contact_collider_velocity_at_position(i)
		var tang := (rel - n * rel.dot(n)).length() / PX
		if tang > scrape_min_speed_mps and tang > best_scrape:
			best_scrape = tang
			_queued_scrape = {"pos": p, "normal": n, "speed": tang}
	_contacts_prev = now


func _flush_events() -> void:
	for e in _queued_impacts:
		var other: Node = e.other if is_instance_valid(e.other) else null
		Game.impact.emit(e.pos, e.normal, e.speed, self, other)
		contact_impact.emit(e.pos, e.normal, e.speed, other)
	_queued_impacts.clear()
	if not _queued_scrape.is_empty():
		Game.scrape.emit(_queued_scrape.pos, _queued_scrape.normal, _queued_scrape.speed, self)
		_last_scrape = _queued_scrape
		_last_scrape["gap"] = (global_position - _queued_scrape.pos).dot(_queued_scrape.normal)
		_scrape_grace = 0.12
		_queued_scrape = {}
	elif _scrape_grace > 0.0 and not _last_scrape.is_empty():
		# With restitution, sliding along a wall is a train of tiny bounces.
		# Keep the scrape alive across the short gaps while we're still hugging
		# the surface so the grinding sound/sparks don't chatter.
		_scrape_grace -= get_physics_process_delta_time()
		var gap := (global_position - (_last_scrape.pos as Vector2)).dot(_last_scrape.normal as Vector2)
		if gap - float(_last_scrape.gap) < 0.6 * PX:
			var along := linear_velocity - (_last_scrape.normal as Vector2) * linear_velocity.dot(_last_scrape.normal)
			var p: Vector2 = _last_scrape.pos + along * get_physics_process_delta_time()
			_last_scrape.pos = p
			Game.scrape.emit(p, _last_scrape.normal, along.length() / PX, self)
		else:
			_scrape_grace = 0.0


# ------------------------------------------------------------ public API --
func velocity_mps() -> Vector2:
	return linear_velocity / PX


func speed_mps() -> float:
	return linear_velocity.length() / PX


## Thrust point (bow RCS) in local pixels.
func thrust_point_local() -> Vector2:
	return Vector2(thrust_point_m * PX, 0.0)


func take_damage(amount: float, _at: Vector2 = Vector2.ZERO) -> void:
	if not alive or amount <= 0.0:
		return
	hull = maxf(hull - amount, 0.0)
	Game.hull_changed.emit(hull, max_hull)
	if hull <= 0.0:
		destroy()


func repair(amount: float) -> void:
	if not alive:
		return
	hull = minf(hull + amount, max_hull)
	Game.hull_changed.emit(hull, max_hull)


func destroy() -> void:
	if not alive:
		return
	alive = false
	controls_enabled = false
	throttle_input = 0.0
	turn_input = 0.0
	strafe_input = 0.0
	var pos := global_position
	# The frozen wreck must not keep reporting its last speed (HUD readout,
	# camera look-ahead and speed zoom). DamageSystem already captured the
	# pre-destruction velocity for the debris on the previous tick.
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	visible = false
	_collision.set_deferred(&"disabled", true)
	set_deferred(&"freeze", true)
	Game.ship_destroyed.emit(pos)


# ----------------------------------------------------------- vehicle API --
# Used by the on-foot layer (OnFootDirector) to treat every pilotable ship the
# same way: get out of the one you fly, board any parked one.

var _landed: Node2D


## Override: the detailed close-up model shown while parked.
func make_landed_model() -> Node2D:
	return LandedShip.new()


## The parked model (created on first use, kept while parked).
func landed_model() -> Node2D:
	if _landed == null or not is_instance_valid(_landed):
		_landed = make_landed_model()
		_landed.name = "Landed"
		add_child(_landed)
		_landed.call(&"set_board_action", func(_by: Node2D) -> void:
			var d := get_tree().get_first_node_in_group(&"on_foot_director")
			if d:
				d.call(&"board", self))
	return _landed


func has_landed_model() -> bool:
	return _landed != null and is_instance_valid(_landed)


func drop_landed_model() -> void:
	if has_landed_model():
		_landed.queue_free()
	_landed = null


## Override: can the pilot get out right now? (The courier: docked and
## clamped on a pad.)
func can_disembark() -> bool:
	if Game.player != self or not alive:
		return false
	var dock := get_tree().get_first_node_in_group(&"docking_system")
	return dock != null and bool(dock.call(&"is_settled"))


## Shown (as a toast) when you press X but can't get out yet.
func disembark_hint() -> String:
	return ""


## Nobody aboard: a frozen, silent obstacle (static world layer, so the ship
## you fly can bump into it and the walker can't walk through it).
func park() -> void:
	controls_enabled = false
	powered = false
	throttle_input = 0.0
	turn_input = 0.0
	strafe_input = 0.0
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	set_deferred(&"freeze", true)
	collision_layer = Game.LAYER_WORLD


## Becomes the player's ship (still frozen: the director calls on_boarded()
## once the camera is back in flight view).
func take_control() -> void:
	powered = true
	collision_layer = Game.LAYER_PLAYER
	_latch_held_actions()
	Game.set_player(self)
	Game.hull_changed.emit(hull, max_hull)


## Override: the director hands over control (the courier just unfreezes;
## its pad clamps hold it until you touch the controls).
func on_boarded() -> void:
	freeze = false
	controls_enabled = true


## Override: stable id for per-ship records (race best laps).
func ship_id() -> StringName:
	return &"wren"


## Override: does DockingSystem's clamp spring apply to this ship?
func uses_pad_clamps() -> bool:
	return true


## Override: where a destroyed ship is brought back when not racing.
func home_transform() -> Transform2D:
	return GameplayUtil.spawn_transform(get_tree())


## Override: how much further out the flight camera sits for this ship
## (multiplies the camera zoom: the frigate is 17x the WREN's length).
func camera_zoom_scale() -> float:
	return 1.0


## Override: damage multiplier for a hit on `other` at `speed_mps`.
func damage_scale(_other: Node, _speed_mps: float) -> float:
	return 1.0


func respawn_at(xform: Transform2D) -> void:
	hull = max_hull
	alive = true
	controls_enabled = true
	visible = true
	recent_contacts.clear()
	_impact_cooldowns.clear()
	_queued_impacts.clear()
	_queued_scrape = {}
	_last_scrape = {}
	_scrape_grace = 0.0
	freeze = false
	_collision.set_deferred(&"disabled", false)
	# Teleport directly (works while frozen) and again inside the physics
	# callback so the solver's cached state can't drag us back.
	global_transform = xform
	_tick_xf = xform
	_tick_prev_xf = xform
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	_teleport_xform = xform
	_pending_teleport = true
	Game.hull_changed.emit(hull, max_hull)
	Game.ship_respawned.emit(xform.origin)
