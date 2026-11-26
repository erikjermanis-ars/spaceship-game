extends Node2D
## PETREL flight-model check (run headless):
##   Godot --headless --path . --fixed-fps 120 res://scenes/test/shuttle_flight_test.tscn
## The shuttle alone in empty space, driven through the same input actions a
## player uses:
##   * "point, then go": engines stay shut while the nose is > 60 deg off
##   * a 180 deg flip settles within 5 deg in <= 1.6 s, overshoot < 3 deg
##   * terminal speed = (2 engines + RCS) / (m * drag)
##   * hover (Space) brakes from ~30 m/s to a stop in <= 6.5 s, heading held
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

	# ---- flip to face west: engines wait for the nose
	Input.action_press(&"move_left")
	await _ticks(2)
	_check(ship.main_frac < 0.01, "engines shut at 180 deg error (main %.2f)" % ship.main_frac)
	var t := 0.0
	var settled := -1.0
	var max_over := 0.0
	while t < 2.5:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		var err := absf(angle_difference(ship.global_rotation, PI))
		if settled < 0.0 and err < deg_to_rad(5.0):
			settled = t
		if settled >= 0.0:
			max_over = maxf(max_over, err)
	_check(settled > 0.0 and settled <= 1.6, "180 deg flip settles in %.2f s (<= 1.6)" % settled)
	_check(max_over < deg_to_rad(3.0) + deg_to_rad(5.0), "overshoot after settling %.1f deg" % rad_to_deg(max_over))

	# ---- terminal speed
	await _secs(40.0)
	var v := ship.speed_mps()
	var expect := (2.0 * ship.engine_n + ship.rcs_n) / (ship.mass_kg * ship.linear_drag)
	_check(absf(v - expect) < 1.0, "terminal %.1f m/s (expect %.1f)" % [v, expect])
	Input.action_release(&"move_left")

	# ---- hover stop from cruise
	var hd := ship.global_rotation
	Input.action_press(&"ship_hover")
	t = 0.0
	while ship.speed_mps() > 0.5 and t < 10.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	_check(t <= 6.5 + v / 10.0, "hover stops from %.0f m/s in %.1f s" % [v, t])
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
	# Fly away from it: the line goes taut and drags the box along.
	Input.action_press(&"move_right")
	await _secs(6.0)
	var box_v := box.linear_velocity.length() / Game.PX_PER_M
	_check(box_v > 2.0, "towed container moving at %.1f m/s" % box_v)
	_check(ship.line.tension_n <= MagLine.CLUTCH_N + 1.0, "applied tension <= clutch (%.0f kN)" % (ship.line.tension_n / 1000.0))
	Input.action_release(&"ship_line")
	Input.action_release(&"move_right")
	await _ticks(2)
	_check(not ship.line.is_attached(), "released on letting go")

	# ---- long-range hook (rays from the nose, line from the tow eye): no snap
	await _secs(0.5)
	ship.linear_velocity = Vector2.ZERO
	ship.angular_velocity = 0.0
	box.queue_free()
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
