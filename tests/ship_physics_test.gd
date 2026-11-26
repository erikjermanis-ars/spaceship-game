extends Node
## Headless flight-model test. Spawns the PlayerShip (WREN) with no world,
## drives it with scripted input and checks the numbers: W fires at the
## throttle setting (terminal = setting x thrust / (m*k)), Shift/Ctrl move the
## setting, retro is a fixed burn, turning gives BOTH rotation and lateral
## drift toward the turn, spin rate -> F*arm/(I*k), assist stops rotation.
## Prints PASS/FAIL per check and exits with code 0/1.
## Run:
##   Godot --headless --path <root> --fixed-fps 120 res://scenes/test/ship_physics_test.tscn

var ship: PlayerShip
var _results: Array[String] = []
var _failed := 0
var _step := 0.0


func _ready() -> void:
	ship = (load("res://scenes/ship/player_ship.tscn") as PackedScene).instantiate()
	add_child(ship)
	await get_tree().physics_frame
	await _run()
	print("\n===== SHIP PHYSICS TEST =====")
	for r in _results:
		print(r)
	print("RESULT: %s (%d failed)" % ["PASS" if _failed == 0 else "FAIL", _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _check(name: String, ok: bool, detail: String) -> void:
	_results.append("%s  %s  — %s" % ["PASS" if ok else "FAIL", name, detail])
	if not ok:
		_failed += 1


func _release_all() -> void:
	for a in [&"thrust_forward", &"thrust_reverse", &"turn_left", &"turn_right", &"throttle_up", &"throttle_down", &"strafe_left", &"strafe_right"]:
		Input.action_release(a)


func _reset() -> void:
	_release_all()
	ship.flight_assist = false
	ship.throttle_setting = ship.throttle_default
	ship.respawn_at(Transform2D(0.0, Vector2.ZERO))
	await get_tree().physics_frame
	await get_tree().physics_frame


func _hold(actions: Array, seconds: float) -> void:
	for a in actions:
		Input.action_press(a)
	var frames := int(round(seconds * Engine.physics_ticks_per_second))
	for i in frames:
		await get_tree().physics_frame


func _run() -> void:
	var PX := Game.PX_PER_M
	var m := ship.mass_kg
	var inertia_si := m * ship.inertia_per_mass_m2
	# Sanity: body properties match the SI model.
	_check("inertia conversion", is_equal_approx(ship.inertia, inertia_si * PX * PX),
		"inertia=%.0f expected %.0f" % [ship.inertia, inertia_si * PX * PX])

	_check("WREN stock numbers", is_equal_approx(ship.main_thrust_n, 10900.0) and is_equal_approx(ship.strafe_thrust_n, 2080.0),
		"main %.0f N, strafe %.0f N" % [ship.main_thrust_n, ship.strafe_thrust_n])

	# 1) Forward terminal speed at the default (50 %) throttle setting.
	await _reset()
	await _hold([&"thrust_forward"], 55.0)
	var full := ship.main_thrust_n / (m * ship.linear_drag)
	var expected := full * ship.throttle_setting
	var v := ship.speed_mps()
	_check("forward terminal speed @ %d%%" % int(ship.throttle_setting * 100.0), absf(v - expected) / expected < 0.05,
		"%.2f m/s (expected %.2f ±5%%)" % [v, expected])
	_check("forward = +X heading kept", absf(ship.angular_velocity) < 0.001 and absf(ship.velocity_mps().y) < 0.05,
		"omega=%.4f vy=%.3f" % [ship.angular_velocity, ship.velocity_mps().y])

	# 2) Full throttle (what boost used to be).
	await _reset()
	ship.throttle_setting = 1.0
	await _hold([&"thrust_forward"], 55.0)
	v = ship.speed_mps()
	_check("terminal speed @ 100%", absf(v - full) / full < 0.05,
		"%.2f m/s (expected %.2f ±5%%)" % [v, full])
	_check("100% output reads 1.0", absf(ship.main_output - 1.0) < 0.001, "main_output=%.3f" % ship.main_output)

	# 2a) Throttle keys ramp the setting and clamp; W at 0 % does nothing.
	await _reset()
	var s0 := ship.throttle_setting
	await _hold([&"throttle_up"], 0.5)
	_release_all()
	var s1 := ship.throttle_setting
	_check("Shift raises throttle", absf((s1 - s0) - ship.throttle_rate * 0.5) < 0.02,
		"%.2f -> %.2f (rate %.2f/s)" % [s0, s1, ship.throttle_rate])
	await _hold([&"throttle_down"], 4.0)
	_release_all()
	_check("Ctrl lowers throttle to 0 and clamps", ship.throttle_setting == 0.0, "setting=%.3f" % ship.throttle_setting)
	await _hold([&"thrust_forward"], 1.0)
	_check("W at 0% throttle: no thrust", ship.speed_mps() < 0.01 and ship.main_output == 0.0,
		"v=%.3f out=%.3f" % [ship.speed_mps(), ship.main_output])
	_release_all()

	# 2b) Reverse terminal: a fixed burn, independent of the throttle setting.
	await _reset()
	ship.throttle_setting = 0.2
	await _hold([&"thrust_reverse"], 55.0)
	var expected_r := full * ship.reverse_scale
	v = ship.velocity_mps().x
	_check("reverse terminal speed", absf(-v - expected_r) / expected_r < 0.05,
		"vx=%.2f m/s (expected -%.2f)" % [v, expected_r])

	# 3) Turn left from rest: nose swings CCW (negative omega) AND the whole
	#    ship drifts toward its left (-Y while heading +X).
	await _reset()
	await _hold([&"turn_left"], 1.0)
	var w := ship.angular_velocity
	var vel := ship.velocity_mps()
	_check("turn left rotates CCW", w < -0.5, "omega=%.3f rad/s after 1 s" % w)
	_check("turn left drifts left", vel.y < -1.0, "lateral v=(%.2f, %.2f) m/s after 1 s" % [vel.x, vel.y])
	# Analytic check at 1 s: omega = a/k (1 - e^-kt) with a = F*arm/I
	var a_ang := ship.side_thrust_n * ship.thrust_point_m / inertia_si
	var k := ship.angular_drag
	var w_expected := -a_ang / k * (1.0 - exp(-k * 1.0))
	_check("spin-up matches analytic", absf(w - w_expected) < 0.03 * absf(w_expected),
		"omega=%.3f expected %.3f" % [w, w_expected])

	# 3b) Turn right mirrors it.
	await _reset()
	await _hold([&"turn_right"], 1.0)
	_check("turn right rotates CW + drifts right", ship.angular_velocity > 0.5 and ship.velocity_mps().y > 1.0,
		"omega=%.3f vy=%.2f" % [ship.angular_velocity, ship.velocity_mps().y])

	# 4) Max spin rate.
	await _reset()
	await _hold([&"turn_right"], 20.0)
	var w_max := ship.side_thrust_n * ship.thrust_point_m / (inertia_si * ship.angular_drag)
	w = ship.angular_velocity
	_check("terminal spin rate", absf(w - w_max) / w_max < 0.05, "%.3f rad/s (expected %.3f)" % [w, w_max])

	# 5) Flight assist kills rotation; without it the spin persists.
	await _reset()
	await _hold([&"turn_left"], 2.0)
	_release_all()
	var w0 := ship.angular_velocity
	ship.flight_assist = true
	await _hold([], 2.5)
	var w_assist := ship.angular_velocity
	_check("flight assist stops rotation", absf(w_assist) < 0.05,
		"omega %.3f -> %.4f rad/s in 2.5 s" % [w0, w_assist])
	await _reset()
	await _hold([&"turn_left"], 2.0)
	_release_all()
	await _hold([], 2.5)
	_check("no assist: spin decays only by drag", absf(ship.angular_velocity) > 0.2,
		"omega=%.3f after 2.5 s coasting" % ship.angular_velocity)

	# 6) Strafe: lateral velocity, no rotation.
	await _reset()
	await _hold([&"strafe_right"], 2.0)
	_check("strafe right: pure lateral", ship.velocity_mps().y > 1.0 and absf(ship.angular_velocity) < 0.001,
		"vy=%.2f omega=%.4f" % [ship.velocity_mps().y, ship.angular_velocity])


