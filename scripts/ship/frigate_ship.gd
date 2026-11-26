class_name FrigateShip
extends PlayerShip
## KESTREL: a 158 m civil exploration frigate, berthed on Pier 7 East.
##
## You don't climb into it from the deck like the WREN or the PETREL. You
## cross the personnel gangway, walk its corridors to the bridge and take the
## captain's chair (see OnFootDirector.take_helm). Leaving the chair (X)
## takes you back to the bridge on foot, when the ship is clamped in its
## berth or at all stop.
##
## Flight: the same PlayerShip model with capital-ship numbers (120 t,
## 3 m/s² at full throttle, a slow turn couple), flight assist ON by
## default, plus:
##   * main thrust from three engines: the impulse deck (40 %) and the two
##     drive nacelles (30 % each), each at its real position, so a damaged
##     nacelle makes the ship pull to one side (FrigateDamage);
##   * Space = ALL STOP: every thruster brakes the drift and the spin;
##   * berth docking with clamp pylons and a gangway (FrigateDock).

signal dock_event(event: String)
## "hit" {shield, hull, sec, pos, breach, shield_fell}, "shields_down",
## "shields_up", "alert" {on}, "core_breach", "destroyed".
signal damage_event(kind: String, data: Dictionary)

const INTERIOR := "res://scenes/onfoot/interiors/frigate_deck.tscn"

## The KESTREL's flight model (also the "KESTREL default" tuning preset).
const FRIGATE_DEFAULTS := {
	"main_thrust_n": 360000.0, "reverse_scale": 0.35, "side_thrust_n": 120000.0,
	"thrust_point_m": 60.0, "strafe_thrust_n": 72000.0, "turn_couple": 1.0, "stern_point_m": 55.0,
	"mass_kg": 120000.0, "inertia_per_mass_m2": 1900.0, "linear_drag": 0.06, "angular_drag": 0.25,
	"bounce": 0.02, "friction": 0.3, "throttle_rate": 0.25,
	"assist_rot_gain": 1.2, "assist_slip_gain": 0.5,
}
## Share of the main thrust per engine: impulse deck, port, starboard nacelle.
const ENGINE_SHARE := Vector3(0.4, 0.3, 0.3)
## Where each engine pushes from (local metres).
const IMPULSE_AT := Vector2(-4.6, 0.0)
const NACELLE_AT := Vector2(-40.0, 28.0)
const VENT_FORCE_N := 2500.0

@export var berth_id := "E2"
@export var livery := Color("2A9D8F")
@export var registry := "MFF-07"
## All-stop brake strength (1/s), capped by the thrusters.
@export var all_stop_gain := 0.5

var damage := FrigateDamage.new()
var dock := FrigateDock.new()
## Space held: 0..1.
var all_stop := 0.0
var red_alert := false
## Engine outputs for FX / audio, 0..1 of each engine's full power:
## x = impulse deck, y = port nacelle, z = starboard nacelle.
var engine_out := Vector3.ZERO
## Fore/aft RCS push (fraction of side thrust, + = forward) from all-stop.
var long_rcs_output := 0.0

var _parts: Array[CollisionPolygon2D] = []
var _wants_move := false
var _undock_hold := 0.0
var _push_off := Vector2.ZERO
## Seconds after the clamps let go during which assist doesn't damp the
## sideways push-off (the ship has to drift clear of the jaws).
var _release_grace := 0.0
var _was_online := true
var _hull_emit_t := 0.0
var _core_announced := false


func _init() -> void:
	for k in FRIGATE_DEFAULTS:
		set(k, FRIGATE_DEFAULTS[k])
	throttle_default = 0.35
	sensor_radius_m = 95.0
	# One convex CollisionPolygon2D per hull part (generated from the art).
	# The first keeps PlayerShip's expected name.
	var first := true
	for key: String in FrigateShape.PARTS:
		var cp := CollisionPolygon2D.new()
		cp.name = "CollisionPolygon2D" if first else "Hull_" + key
		cp.polygon = PackedVector2Array(FrigateShape.PARTS[key])
		add_child(cp)
		_parts.append(cp)
		first = false


func _ready() -> void:
	super._ready()
	flight_assist = true
	max_contacts_reported = 12
	add_to_group(&"frigate")
	# A 158 m hull is a landmark on the radar and the station map, not a blip.
	add_to_group(&"radar_structure")
	_find_berth()
	if not start_as_player:
		_go_home.call_deferred()
	if Game.cmd.has("frigate-hits"):
		_harness_hits.call_deferred(int(Game.cmd["frigate-hits"]))


func _find_berth() -> void:
	for n in get_tree().get_nodes_in_group(&"frigate_berth"):
		if String(n.get(&"berth_id")) == berth_id:
			dock.berth = n as Node2D
			n.set(&"ship", self)
			return


## Session start: clamped in the berth, gangway out, nobody aboard.
func _go_home() -> void:
	_lock_at_berth()
	dock.set_locked()
	park()


# ================================================================ vehicle

func ship_id() -> StringName:
	return &"kestrel"


func uses_pad_clamps() -> bool:
	return false


func camera_zoom_scale() -> float:
	return 0.36


## The frigate has no deck model: you walk its interior instead.
func landed_model() -> Node2D:
	return null


## Radar outline (global px): primary and engineering hulls, both nacelles.
func get_radar_polygons() -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	if not alive:
		return out
	var xf := global_transform
	for key: String in ["primary", "secondary", "nacelle_s", "nacelle_p"]:
		out.append(xf * PackedVector2Array(FrigateShape.PARTS[key]))
	return out


func interior_scene() -> String:
	return INTERIOR


func gangway_ready() -> bool:
	return dock.gangway_ready()


func home_transform() -> Transform2D:
	if dock.berth:
		return dock.target()
	return super.home_transform()


## X leaves the bridge: clamped in the berth (gangway sealed), or at all stop.
func can_disembark() -> bool:
	if Game.player != self or not alive:
		return false
	if dock.state == FrigateDock.State.LOCKED:
		return dock.gangway_ready()
	return dock.state == FrigateDock.State.FREE and speed_mps() < 0.4 and absf(angular_velocity) < 0.01


func exit_label() -> String:
	return "Leave the bridge"


func disembark_hint() -> String:
	match dock.state:
		FrigateDock.State.CAPTURE, FrigateDock.State.UNDOCKING:
			return "Docking sequence in progress"
		FrigateDock.State.LOCKED:
			return "Gangway extending…"
	return "All stop first  ·  hold Space until the ship is still"


func park() -> void:
	super.park()
	_zero_outputs()
	all_stop = 0.0


## Boarded (from the captain's chair): in the clamps it stays frozen until
## you undock; adrift it comes back to life where it was left.
func on_boarded() -> void:
	controls_enabled = true
	_undock_hold = 0.0
	if dock.state != FrigateDock.State.LOCKED:
		freeze = false


## Small props barely scratch a 120 t hull.
func damage_scale(other: Node, _speed_mps: float) -> float:
	if other is RigidBody2D and ((other as RigidBody2D).collision_layer & Game.LAYER_PROPS) != 0:
		return 0.3
	return 1.0


# ================================================================== input

func _controls_active() -> bool:
	return controls_enabled and alive and powered and Game.player == self and Game.mode == Game.Mode.FLIGHT


func _read_input(delta: float) -> void:
	super._read_input(delta)
	var active := _controls_active()
	_wants_move = active and (_raw_fwd > 0.2 or _raw_rev > 0.2 or absf(turn_input) > 0.2 or absf(strafe_input) > 0.2)
	all_stop = _act(&"ship_hover") if active else 0.0
	if dock.state == FrigateDock.State.FREE:
		_undock_hold = 0.0
		return
	# In the clamps the helm only asks to leave: hold any flight input.
	if dock.state == FrigateDock.State.LOCKED and _wants_move:
		_undock_hold += delta
		if _undock_hold >= 0.5 and dock.request_undock():
			_undock_hold = 0.0
			_on_dock_event("undock")
	else:
		_undock_hold = 0.0
	throttle_input = 0.0
	turn_input = 0.0
	strafe_input = 0.0
	all_stop = 0.0


# ================================================================ physics

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	var locked := dock.state == FrigateDock.State.LOCKED
	_release_grace = maxf(0.0, _release_grace - delta)
	damage.tick(delta, locked and alive)
	var ev := dock.tick(self, delta, Game.player == self and alive and powered)
	if ev != "":
		_on_dock_event(ev)
	_tick_damage_state(delta)
	if freeze or not alive or locked:
		_zero_outputs()


func _apply_flight_forces(state: PhysicsDirectBodyState2D, xf: Transform2D, v: Vector2, w: float) -> void:
	if dock.state == FrigateDock.State.CAPTURE:
		dock.apply_capture(state, self)
		_zero_outputs()
		dbg_main_force = Vector2.ZERO
		dbg_side_force = Vector2.ZERO
		dbg_strafe_force = Vector2.ZERO
		return
	if _push_off != Vector2.ZERO:
		state.linear_velocity = _push_off
		_push_off = Vector2.ZERO
	var fwd := xf.x.normalized()
	var right := xf.y.normalized()
	var D := FrigateDamage.Sec
	var e_bow := damage.eff(D.BOW)
	var e_eng := damage.eff(D.ENGINEERING)
	var e_p := damage.eff(D.NACELLE_P) * damage.sputter.x
	var e_s := damage.eff(D.NACELLE_S) * damage.sputter.y
	var e_side := (damage.eff(D.PORT) + damage.eff(D.STARBOARD)) * 0.5
	var v_si := v / PX
	var i_si := mass_kg * inertia_per_mass_m2

	# ---- main engines: each one at its own position ----
	var cmd := throttle_input
	var full := main_thrust_n
	var f_imp := 0.0
	var f_p := 0.0
	var f_s := 0.0
	var retro_n := 0.0
	if cmd > 0.0:
		f_imp = cmd * full * ENGINE_SHARE.x * e_eng
		f_p = cmd * full * ENGINE_SHARE.y * e_p
		f_s = cmd * full * ENGINE_SHARE.z * e_s
	elif cmd < 0.0:
		retro_n = cmd * full * reverse_scale * e_bow       # bow quads fire forward
	# ---- turn couple: bow quads one way, engineering's the other ----
	var side_n := turn_input * side_thrust_n
	var bow_n := side_n * e_bow
	var stern_n := -side_n * turn_couple * e_eng
	var strafe_n := strafe_input * strafe_thrust_n * e_side
	var max_t := side_thrust_n * (thrust_point_m * e_bow + turn_couple * stern_point_m * e_eng)
	var assist_t := 0.0
	var brake_long := 0.0
	# ---- flight assist / all stop ----
	if flight_assist or all_stop > 0.0:
		var gain := maxf(assist_rot_gain if flight_assist else 0.0, 2.0 * all_stop)
		if is_zero_approx(turn_input) or all_stop > 0.0:
			assist_t = clampf(-i_si * gain * w, -max_t, max_t)
		var slip := v_si.dot(right)
		if (is_zero_approx(strafe_input) and _release_grace <= 0.0) or all_stop > 0.0:
			var sg := maxf(assist_slip_gain if flight_assist else 0.0, all_stop_gain * 2.0 * all_stop)
			strafe_n = clampf(-mass_kg * sg * slip, -strafe_thrust_n * e_side, strafe_thrust_n * e_side)
	if all_stop > 0.0 and cmd == 0.0:
		var along := v_si.dot(fwd)
		var cap := main_thrust_n * reverse_scale
		brake_long = clampf(-mass_kg * all_stop_gain * 2.0 * along * all_stop, -cap * e_bow, cap * e_eng)
	var px := PX
	state.apply_force(fwd * f_imp * px, xf.basis_xform(IMPULSE_AT * px))
	state.apply_force(fwd * f_p * px, xf.basis_xform(Vector2(NACELLE_AT.x, -NACELLE_AT.y) * px))
	state.apply_force(fwd * f_s * px, xf.basis_xform(NACELLE_AT * px))
	state.apply_central_force(fwd * (retro_n + brake_long) * px)
	state.apply_force(right * bow_n * px, fwd * thrust_point_m * px)
	state.apply_force(right * stern_n * px, -fwd * stern_point_m * px)
	state.apply_central_force(right * strafe_n * px)
	if assist_t != 0.0:
		state.apply_torque(assist_t * px * px)
	# ---- venting breaches push the hull a little ----
	for b in damage.breaches:
		if damage.venting(b):
			var p: Vector2 = b.pos
			var out := Vector2(0.0, signf(p.y) if absf(p.y) > 2.0 else 0.0)
			if out == Vector2.ZERO:
				out = Vector2(signf(p.x), 0.0)
			state.apply_force(xf.basis_xform(out) * VENT_FORCE_N * px, xf.basis_xform(p * px))
	# ---- drag ----
	state.apply_central_force(-v * mass_kg * linear_drag)
	state.apply_torque(-inertia * angular_drag * w)

	# ---- outputs ----
	var total_fwd := f_imp + f_p + f_s
	main_output = (total_fwd + retro_n) / maxf(main_thrust_n, 1.0)
	engine_out = Vector3(
		f_imp / maxf(full * ENGINE_SHARE.x, 1.0),
		f_p / maxf(full * ENGINE_SHARE.y, 1.0),
		f_s / maxf(full * ENGINE_SHARE.z, 1.0))
	var couple := assist_t / maxf(max_t, 1.0)
	var strafe_frac := strafe_n / maxf(side_thrust_n, 1.0)
	bow_lateral_output = bow_n / maxf(side_thrust_n, 1.0) + strafe_frac * 0.5 + couple * 0.5
	stern_lateral_output = stern_n / maxf(side_thrust_n, 1.0) + strafe_frac * 0.5 - couple * 0.5
	long_rcs_output = (brake_long + retro_n) / maxf(side_thrust_n, 1.0)
	dbg_main_force = fwd * total_fwd
	dbg_side_force = right * (bow_n + stern_n)
	dbg_strafe_force = right * strafe_n
	dbg_assist_torque = assist_t


## RCS quad groups firing (0..~1): bow port, bow stbd, stern port, stern
## stbd, fore quads pushing aft (retro / all-stop), aft quads pushing forward.
## + lateral = push to starboard = gas out of the PORT quads.
func rcs_levels() -> PackedFloat32Array:
	var bow := bow_lateral_output
	var stern := stern_lateral_output
	return PackedFloat32Array([
		maxf(bow, 0.0), maxf(-bow, 0.0), maxf(stern, 0.0), maxf(-stern, 0.0),
		maxf(-long_rcs_output, 0.0), maxf(long_rcs_output, 0.0)])


func _zero_outputs() -> void:
	engine_out = Vector3.ZERO
	long_rcs_output = 0.0
	main_output = 0.0
	bow_lateral_output = 0.0
	stern_lateral_output = 0.0
	if freeze or not alive or dock.state != FrigateDock.State.FREE:
		throttle_input = 0.0
		turn_input = 0.0
		strafe_input = 0.0


# ================================================================ docking

func _on_dock_event(ev: String) -> void:
	match ev:
		"capture":
			Game.toast("SOFT CAPTURE  ·  clamps engaging  ·  hands off the helm", 3.0)
		"lock":
			_lock_at_berth.call_deferred()
			Game.toast("HARD DOCK  ·  BERTH %s  ·  gangway extending" % berth_id, 3.0)
			if Game.camera and Game.camera.has_method(&"add_trauma"):
				Game.camera.call(&"add_trauma", 0.25)
		"gangway":
			if Game.player == self:
				Game.toast("GANGWAY SEALED  ·  X leave the bridge  ·  repairs under way", 4.0)
		"undock":
			Game.toast("UNDOCKING  ·  gangway retracting  ·  clamps release in a moment", 3.0)
		"release":
			freeze = false
			# Gently away from the pier (the berth's +Y side is the pier).
			var away := -dock.target().y.normalized() * dock.side()
			_push_off = away * FrigateDock.PUSH_OFF * PX
			_release_grace = 4.0
			Game.toast("CLEAR OF THE BERTH  ·  you have the helm", 2.5)
			if Game.camera and Game.camera.has_method(&"add_trauma"):
				Game.camera.call(&"add_trauma", 0.15)
	dock_event.emit(ev)


## Frozen exactly on the berth mark (outside the physics callback).
func _lock_at_berth() -> void:
	freeze_mode = RigidBody2D.FREEZE_MODE_STATIC
	freeze = true
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	if dock.berth:
		global_transform = dock.target()
	_tick_xf = global_transform
	_tick_prev_xf = global_transform
	_contacts_prev.clear()
	_zero_outputs()


# ================================================================= damage

func take_damage(amount: float, at: Vector2 = Vector2.ZERO) -> void:
	if not alive or amount <= 0.0 or dock.state == FrigateDock.State.LOCKED:
		return
	var local := Vector2.ZERO if at == Vector2.ZERO else (global_transform.affine_inverse() * at) / PX
	var res := damage.hit(amount, local)
	res["pos"] = local
	res["amount"] = amount
	hull = damage.hull()
	Game.hull_changed.emit(hull, max_hull)
	damage_event.emit("hit", res)
	if res.shield_fell:
		damage_event.emit("shields_down", {})
		Game.toast("SHIELDS DOWN", 2.0)
	if hull <= 0.5:
		destroy()


func _tick_damage_state(delta: float) -> void:
	if not alive:
		return
	var alert := damage.red_alert()
	if alert != red_alert:
		red_alert = alert
		damage_event.emit("alert", {"on": alert})
	if damage.shield_online and not _was_online:
		damage_event.emit("shields_up", {})
	_was_online = damage.shield_online
	if damage.core_breach >= 0.0:
		if not _core_announced:
			_core_announced = true
			damage_event.emit("core_breach", {})
			Game.toast("WARNING  ·  REACTOR CONTAINMENT FAILING  ·  CORE BREACH IN %d s" % int(FrigateDamage.CORE_BREACH_TIME), 4.0)
		if damage.core_breach <= 0.0:
			destroy()
			return
	else:
		_core_announced = false
	# Repairs (berth) change the hull smoothly: tell the HUD a few times a second.
	_hull_emit_t -= delta
	var h := damage.hull()
	if _hull_emit_t <= 0.0 and absf(h - hull) > 0.05:
		_hull_emit_t = 0.25
		hull = h
		if Game.player == self:
			Game.hull_changed.emit(hull, max_hull)


func destroy() -> void:
	if not alive:
		return
	for cp in _parts:
		cp.set_deferred(&"disabled", true)
	dock.reset_free()
	super.destroy()
	_zero_outputs()
	damage_event.emit("destroyed", {})


func respawn_at(xform: Transform2D) -> void:
	damage.reset()
	red_alert = false
	_core_announced = false
	_was_online = true
	super.respawn_at(xform)
	for cp in _parts:
		cp.set_deferred(&"disabled", false)
	dock.reset_free()
	_zero_outputs()
	# Home is the berth: come back clamped in, gangway out.
	if dock.berth and xform.origin.distance_to(dock.target().origin) < 1.0:
		_respawn_docked.call_deferred()


## --frigate-hits=N: N seeded hits of 25 hp across the hull a moment after
## start (shields, breaches, red alert: for screenshots and trying it out).
## The ship must be free, not clamped (use with --fly=kestrel@x,y,deg).
func _harness_hits(n: int) -> void:
	await get_tree().create_timer(0.6, false).timeout
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in n:
		var keys := FrigateShape.PARTS.keys()
		var poly: Array = FrigateShape.PARTS[keys[rng.randi() % keys.size()]]
		var p: Vector2 = poly[rng.randi() % poly.size()] * 0.9
		var was := dock.state
		dock.state = FrigateDock.State.FREE
		take_damage(25.0, to_global(p))
		dock.state = was


func _respawn_docked() -> void:
	_lock_at_berth()
	dock.set_locked()
