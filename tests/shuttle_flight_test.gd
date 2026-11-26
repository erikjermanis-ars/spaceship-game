extends Node2D
## PETREL flight-model check (run headless):
##   Godot --headless --path . --fixed-fps 120 res://scenes/test/shuttle_flight_test.tscn
## The shuttle alone in empty space, driven through the same input actions a
## player uses. It flies the WREN's model with heavier numbers:
##   * A/D turn IN PLACE: bow and stern thrusters push opposite ways, so it
##     spins with no sideways drift, at the analytic couple rate
##   * heavier than the WREN (mass, slower forward accel and spin-up)
##   * terminal speed = setting x main thrust / (m * drag)
##   * hover (Space) brakes from full speed to a stop in <= 7.5 s, heading held
##   * the mag-line tows a free container (equal and opposite pull)

const SHUTTLE := preload("res://scenes/ship/shuttle.tscn")

var _fails := 0
var ship: ShuttleShip


func _ready() -> void:
	ship = SHUTTLE.instantiate() as ShuttleShip
	add_child(ship)
	_run.call_deferred()


func _run() -> void:
	await _ticks(3)
	ship.take_control()
	ship.on_boarded()
	ship.land_state = ShuttleShip.Land.CRUISE
	ship.altitude_m = ship.cruise_alt_m
	ship.collision_layer = Game.LAYER_PLAYER
	ship.freeze = false
	ship.get_node(^"Visuals").visible = true
	ship.drop_landed_model()
	await _ticks(2)
	_check(ship.rotation == 0.0 or absf(ship.rotation) < 0.01, "starts facing +X")
	var d := ShuttleShip.PETREL_DEFAULTS
	_check(is_equal_approx(ship.mass_kg, d.mass_kg) and is_equal_approx(ship.turn_couple, 1.0) and is_equal_approx(ship.mass, d.mass_kg),
		"PETREL stock numbers applied (%.0f kg, couple %.1f)" % [ship.mass_kg, ship.turn_couple])
	var wren := PlayerShip.WREN_DEFAULTS
	_check(ship.mass_kg > wren.mass_kg * 2.0 and ship.main_thrust_n / ship.mass_kg < float(wren.main_thrust_n) / float(wren.mass_kg),
		"heavier than the WREN, less forward accel (%.1f vs %.1f m/s²)" % [ship.main_thrust_n / ship.mass_kg, float(wren.main_thrust_n) / float(wren.mass_kg)])

	# ---- turn in place: pure couple, no sideways shove
	var p0 := ship.global_position
	Input.action_press(&"turn_left")
	await _secs(1.5)
	Input.action_release(&"turn_left")
	var i_si := ship.mass_kg * ship.inertia_per_mass_m2
	var a_ang := ship.max_turn_torque_nm() / i_si
	var k := ship.angular_drag
	var w_expect := -a_ang / k * (1.0 - exp(-k * 1.5))
	var w := ship.angular_velocity
	_check(w < -0.3 and absf(w - w_expect) < 0.04 * absf(w_expect), "turn left spins CCW at the couple rate (%.3f, expect %.3f rad/s)" % [w, w_expect])
	var drift := ship.global_position.distance_to(p0) / Game.PX_PER_M
	_check(drift < 0.05 and ship.speed_mps() < 0.05, "pivots in place (moved %.3f m, v %.3f m/s)" % [drift, ship.speed_mps()])
	# Flight assist stops the spin.
	ship.flight_assist = true
	await _secs(4.0)
	_check(absf(ship.angular_velocity) < 0.03, "assist stops the spin (%.3f rad/s)" % ship.angular_velocity)

	# ---- terminal speed at full throttle
	ship.throttle_setting = 1.0
	Input.action_press(&"thrust_forward")
	await _secs(50.0)
	var v := ship.speed_mps()
	var expect := ship.main_thrust_n / (ship.mass_kg * ship.linear_drag)
	_check(absf(v - expect) / expect < 0.03, "terminal %.1f m/s at 100%% (expect %.1f)" % [v, expect])
	Input.action_release(&"thrust_forward")
	ship.flight_assist = false

	# ---- hover stop from cruise
	var hd := ship.global_rotation
	Input.action_press(&"ship_hover")
	var t := 0.0
	while ship.speed_mps() > 0.5 and t < 10.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	# Brake cap 14 kN / 2.6 t (5.4 m/s²) + drag: ~6.5 s from 46 m/s.
	_check(ship.speed_mps() <= 0.5 and t <= 7.5, "hover stops from %.0f m/s in %.1f s (<= 7.5, v now %.2f)" % [v, t, ship.speed_mps()])
	_check(absf(angle_difference(ship.global_rotation, hd)) < deg_to_rad(3.0), "heading held while hovering")
	_check(ship.land_state == ShuttleShip.Land.HOVER, "no deck below: stays hovering (%s)" % ship.land_status)
	Input.action_release(&"ship_hover")
	await _ticks(2)

	# ---- mag-line tow: hook a free container ahead and pull it
	var box := RigidBody2D.new()
	box.mass = 1800.0
	box.gravity_scale = 0.0
	box.collision_layer = Game.LAYER_PROPS
	var cs := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = Vector2(60, 25)
	cs.shape = rs
	box.add_child(cs)
	box.linear_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	box.linear_damp = 0.0
	add_child(box)
	box.global_position = ship.global_position + Vector2.from_angle(ship.global_rotation) * 200.0
	await _ticks(6)
	ship.line.aim_dir = Vector2.from_angle(ship.global_rotation)
	ship.line._scan()
	_check(not ship.line.scan_result().is_empty() and ship.line.scan_result().kind == "CARGO", "line targets the container (CARGO)")
	Input.action_press(&"ship_line")
	await _ticks(2)
	_check(ship.line.is_attached(), "line latched")
	# Back away from it on retro: the line goes taut and drags the box along.
	Input.action_press(&"thrust_reverse")
	await _secs(6.0)
	var box_v := box.linear_velocity.length() / Game.PX_PER_M
	_check(box_v > 2.0, "towed container moving at %.1f m/s" % box_v)
	_check(ship.line.tension_n <= MagLine.CLUTCH_N + 1.0, "applied tension <= clutch (%.0f kN)" % (ship.line.tension_n / 1000.0))
	Input.action_release(&"ship_line")
	Input.action_release(&"thrust_reverse")
	await _ticks(2)
	_check(not ship.line.is_attached(), "released on letting go")

	# ---- long-range hook (rays from the nose, line from the tow eye): no snap
	await _secs(0.5)
	ship.linear_velocity = Vector2.ZERO
	ship.angular_velocity = 0.0
	box.queue_free()
	# Holding the line button aims at the mouse (headless: a fixed point), so
	# face it first; otherwise whether the box is in the aim is path luck.
	var to_mouse := ship.get_global_mouse_position() - ship.global_position
	ship._teleport_xform = Transform2D(to_mouse.angle(), ship.global_position)
	ship._pending_teleport = true
	await _ticks(2)
	var far := _make_box(ship.global_position + Vector2.from_angle(ship.global_rotation) * (70.0 + 300.0))
	await _ticks(6)
	ship.line.aim_dir = Vector2.from_angle(ship.global_rotation)
	ship.line._scan()
	_check(not ship.line.scan_result().is_empty(), "container 30 m ahead of the nose is targetable")
	Input.action_press(&"ship_line")
	await _ticks(2)
	await _secs(0.5)
	_check(ship.line.is_attached(), "a 30 m hook holds (no instant snap, L %.1f m)" % ship.line.length_m)
	Input.action_release(&"ship_line")
	far.queue_free()

	print("shuttle_flight_test: %s (%d failure%s)" % ["OK" if _fails == 0 else "FAILED", _fails, "" if _fails == 1 else "s"])
	get_tree().quit(0 if _fails == 0 else 1)


func _make_box(at: Vector2) -> RigidBody2D:
	var b := RigidBody2D.new()
	b.mass = 1800.0
	b.gravity_scale = 0.0
	b.collision_layer = Game.LAYER_PROPS
	var cs := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = Vector2(60, 25)
	cs.shape = rs
	b.add_child(cs)
	b.position = at
	add_child(b)
	return b


func _check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_fails += 1


func _ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _secs(s: float) -> void:
	var t := 0.0
	while t < s:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
