extends RigidBody2D
## Minimal stand-in that follows the PlayerShip API (contract §4) so the
## gameplay systems can be tested before / without the real ship scene.
## Simplified barbell model: thrust at a point 4 m ahead of the CoM.

const PX := Game.PX_PER_M

var hull: float = 100.0
var max_hull: float = 100.0
var flight_assist: bool = false
var alive: bool = true
var controls_enabled: bool = true
var throttle_input: float = 0.0
var turn_input: float = 0.0
var strafe_input: float = 0.0

var _prev_v := Vector2.ZERO
var _contacts := {}
var _teleport := false
var _tx := Transform2D.IDENTITY
var _shape: CollisionPolygon2D

func _ready() -> void:
	add_to_group(&"player_ship")
	Game.player = self
	mass = 1000.0
	center_of_mass_mode = RigidBody2D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector2.ZERO
	inertia = 1000.0 * 8.37 * PX * PX
	linear_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	contact_monitor = true
	max_contacts_reported = 8
	collision_layer = Game.LAYER_PLAYER
	collision_mask = Game.LAYER_WORLD | Game.LAYER_PROPS | Game.LAYER_TRAFFIC
	z_as_relative = false
	z_index = Game.Z_SHIP
	var mat := PhysicsMaterial.new()
	mat.bounce = 0.45
	mat.friction = 0.2
	physics_material_override = mat
	var pts := PackedVector2Array([Vector2(52, 0), Vector2(10, -20), Vector2(-38, -16), Vector2(-38, 16), Vector2(10, 20)])
	_shape = CollisionPolygon2D.new()
	_shape.polygon = pts
	add_child(_shape)
	var poly := Polygon2D.new()
	poly.polygon = pts
	poly.color = Color("#E9EEF3")
	add_child(poly)
	var line := Line2D.new()
	line.points = pts + PackedVector2Array([pts[0]])
	line.width = 2.0
	line.default_color = Color("#1D3557")
	add_child(line)
	Game.hull_changed.emit(hull, max_hull)

func _physics_process(_delta: float) -> void:
	var thr := 0.0
	var trn := 0.0
	var stf := 0.0
	if controls_enabled and alive:
		thr = Input.get_action_strength(&"thrust_forward") - Input.get_action_strength(&"thrust_reverse")
		trn = Input.get_axis(&"turn_left", &"turn_right")
		stf = Input.get_axis(&"strafe_left", &"strafe_right")
	throttle_input = thr
	turn_input = trn
	strafe_input = stf

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if _teleport:
		_teleport = false
		state.transform = _tx
		state.linear_velocity = Vector2.ZERO
		state.angular_velocity = 0.0
		_prev_v = Vector2.ZERO
		_contacts.clear()
		return
	var fwd := state.transform.x.normalized()
	var right := state.transform.y.normalized()
	var main := throttle_input * 5000.0 * (0.6 if throttle_input < 0.0 else 1.0)
	state.apply_force(fwd * main * PX, fwd * 4.0 * PX)
	state.apply_force(right * turn_input * 2600.0 * PX, fwd * 4.0 * PX)
	state.apply_central_force(right * strafe_input * 1200.0 * PX)
	state.apply_central_force(-state.linear_velocity * 1000.0 * 0.12)
	state.apply_torque(-inertia * 0.35 * state.angular_velocity)
	# Contact events (same semantics as the real ship).
	var now := {}
	for i in state.get_contact_count():
		var col := state.get_contact_collider_object(i)
		if col == null:
			continue
		var id := col.get_instance_id()
		var p := state.get_contact_local_position(i)
		var n := state.get_contact_local_normal(i)
		var closing := -(_prev_v - state.get_contact_collider_velocity_at_position(i)).dot(n) / PX
		if not _contacts.has(id) and closing > 0.8:
			Game.impact.emit.call_deferred(p, n, closing, self, col)
		now[id] = true
		var rel := state.linear_velocity - state.get_contact_collider_velocity_at_position(i)
		var tang := (rel - n * rel.dot(n)).length() / PX
		if tang > 1.0:
			Game.scrape.emit.call_deferred(p, n, tang, self)
	_contacts = now
	_prev_v = state.linear_velocity

func velocity_mps() -> Vector2:
	return linear_velocity / PX

func speed_mps() -> float:
	return linear_velocity.length() / PX

func take_damage(amount: float, _at: Vector2 = Vector2.ZERO) -> void:
	if not alive:
		return
	hull = maxf(0.0, hull - amount)
	Game.hull_changed.emit(hull, max_hull)
	if hull <= 0.0:
		destroy()

func repair(amount: float) -> void:
	hull = minf(max_hull, hull + amount)
	Game.hull_changed.emit(hull, max_hull)

func destroy() -> void:
	if not alive:
		return
	alive = false
	controls_enabled = false
	visible = false
	_shape.set_deferred(&"disabled", true)
	set_deferred(&"freeze", true)
	Game.ship_destroyed.emit(global_position)

func respawn_at(xform: Transform2D) -> void:
	alive = true
	controls_enabled = true
	visible = true
	hull = max_hull
	freeze = false
	_shape.set_deferred(&"disabled", false)
	global_transform = xform
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	_tx = xform
	_teleport = true
	Game.hull_changed.emit(hull, max_hull)
	Game.ship_respawned.emit(xform.origin)
