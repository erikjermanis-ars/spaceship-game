extends Node
## KESTREL flight and damage model (run headless):
##   Godot --headless --path . --fixed-fps 120 res://scenes/test/frigate_test.tscn
## Flies the frigate in open space east of the pier and checks:
##   thrust       -> ~3 m/s² at full throttle (impulse deck + two nacelles)
##   turn couple  -> A/D rotate it in place (no sideways shove)
##   all stop     -> Space kills drift and spin
##   shield       -> absorbs a hit (shield drains, the hull barely notices)
##   collapse     -> a big hit drops the shield, breaches the bow, red alert
##   nacelle      -> a wrecked port nacelle makes full throttle pull to port
##   regen        -> the shield comes back after a quiet spell
##   core breach  -> Engineering at zero starts the countdown, the ship is
##                   lost, and it comes back clamped in its berth, repaired
## Prints PASS / FAIL lines and exits with code 0 / 1.

const MAIN := preload("res://scenes/main.tscn")
const AT := "9000,-3000,0"

var _fails := 0
var _main: Node
var _k: FrigateShip


func _ready() -> void:
	Game.cmd["no-intro"] = true
	Game.cmd["fly"] = "kestrel@" + AT
	_main = MAIN.instantiate()
	add_child(_main)
	_k = _main.get_node(^"Frigate") as FrigateShip
	_run.call_deferred()


func _run() -> void:
	await _wait(func() -> bool: return Game.player == _k and not _k.freeze, 5.0, "flying the KESTREL in open space")
	await _secs(0.3)
	_check(_k.flight_assist, "flight assist on by default")

	# ---- thrust
	_k.throttle_setting = 1.0
	var v0 := _k.speed_mps()
	Input.action_press(&"thrust_forward")
	await _secs(2.0)
	var eo := _k.engine_out
	Input.action_release(&"thrust_forward")
	var dv := _k.speed_mps() - v0
	_check(dv > 4.8 and dv < 6.4, "full throttle: +%.2f m/s in 2 s (about 3 m/s²)" % dv)
	_check(eo.x > 0.95 and eo.y > 0.95 and eo.z > 0.95, "impulse and both nacelles at full (%.2f %.2f %.2f)" % [eo.x, eo.y, eo.z])
	await _all_stop()

	# ---- turn couple: pure rotation
	_k.flight_assist = false
	Input.action_press(&"turn_right")
	await _secs(2.5)
	Input.action_release(&"turn_right")
	var w := _k.angular_velocity
	var lat := absf(_k.velocity_mps().dot(Vector2.from_angle(_k.global_rotation).orthogonal()))
	_check(w > 0.05, "D turns clockwise (%.3f rad/s)" % w)
	_check(lat < 0.4, "turn in place: sideways drift %.2f m/s" % lat)
	await _all_stop()
	_check(absf(_k.angular_velocity) < 0.01 and _k.speed_mps() < 0.3, "all stop: still")

	# ---- shield takes a hit
	var bow_hit := _k.to_global(Vector2(70.0, 0.0) * Game.PX_PER_M)
	_k.take_damage(10.0, bow_hit)
	var d := _k.damage
	_check(absf(d.shield - 85.0) < 0.5, "shield drained by 15 (%.1f)" % d.shield)
	_check(d.integrity[FrigateDamage.Sec.BOW] > 97.0 and d.integrity[FrigateDamage.Sec.BOW] < 100.0, "bow barely scratched (%.1f)" % d.integrity[FrigateDamage.Sec.BOW])
	_check(d.shield_hits.size() == 1, "shield ripple queued")

	# ---- collapse + breach
	_k.take_damage(80.0, bow_hit)
	_check(not d.shield_online and d.shield <= 0.0, "shield collapsed")
	_check(d.integrity[FrigateDamage.Sec.BOW] < 60.0, "bow hurt through the gap (%.1f)" % d.integrity[FrigateDamage.Sec.BOW])
	_check(d.breaches.size() >= 1, "hull breached at the bow")
	await get_tree().physics_frame
	_check(_k.red_alert, "red alert")
	_check(_k.hull < 100.0 and _k.hull > 80.0, "overall hull %.1f %%" % _k.hull)

	# ---- wreck the port nacelle: full throttle now pulls to port
	var port_nac := _k.to_global(Vector2(-46.0, -28.0) * Game.PX_PER_M)
	for i in 4:
		_k.take_damage(30.0, port_nac)
	_check(d.integrity[FrigateDamage.Sec.NACELLE_P] < 8.0 and d.eff(FrigateDamage.Sec.NACELLE_P) == 0.0, "port nacelle dark")
	await _all_stop()
	_k.flight_assist = false
	Input.action_press(&"thrust_forward")
	await _secs(1.5)
	var eo2 := _k.engine_out
	Input.action_release(&"thrust_forward")
	_check(_k.angular_velocity < -0.003, "asymmetric thrust yaws to port (%.4f rad/s)" % _k.angular_velocity)
	_check(eo2.y == 0.0 and eo2.z > 0.9, "port nacelle silent, starboard full (%.2f / %.2f)" % [eo2.y, eo2.z])
	await _all_stop()

	# ---- shield regen after a quiet spell (Engineering is intact)
	var s0 := d.shield
	await _secs(6.0)
	_check(d.shield > s0 + 15.0 and d.shield_online, "shield regenerating (%.0f -> %.0f)" % [s0, d.shield])

	# ---- core breach: Engineering to zero
	var eng := _k.to_global(Vector2(-40.0, 0.0) * Game.PX_PER_M)
	d.shield = 0.0
	d.shield_online = false
	d.since_hit = 0.0
	for i in 6:
		_k.take_damage(30.0, eng)
		if d.core_breach >= 0.0:
			break
	_check(d.core_breach >= 0.0, "core breach countdown (%.1f s)" % d.core_breach)
	await _wait(func() -> bool: return not _k.alive, FrigateDamage.CORE_BREACH_TIME + 1.0, "reactor lost: ship destroyed")
	await _wait(func() -> bool: return _k.alive and _k.dock.gangway_ready(), 8.0, "recovered: clamped in Berth E2")
	await get_tree().physics_frame
	_check(_k.hull >= 99.9 and d.breaches.is_empty() and d.shield_online, "repaired: hull %.0f, no breaches, shields up" % _k.hull)
	_check(_k.global_position.distance_to(_k.dock.target().origin) < 0.5, "on the berth mark")

	print("frigate_test: %s (%d failure%s)" % ["OK" if _fails == 0 else "FAILED", _fails, "" if _fails == 1 else "s"])
	get_tree().quit(0 if _fails == 0 else 1)


func _all_stop() -> void:
	Input.action_press(&"ship_hover")
	var t := 0.0
	while t < 20.0 and (_k.speed_mps() > 0.2 or absf(_k.angular_velocity) > 0.005):
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	Input.action_release(&"ship_hover")
	_k.flight_assist = true


func _check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_fails += 1


func _secs(s: float) -> void:
	var t := 0.0
	while t < s:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()


func _wait(cond: Callable, timeout: float, what: String) -> void:
	var t := 0.0
	while not cond.call() and t < timeout:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	_check(cond.call(), "%s (%.1f s)" % [what, t])
	if not cond.call():
		print("frigate_test: FAILED (stuck: %s)" % what)
		get_tree().quit(1)
