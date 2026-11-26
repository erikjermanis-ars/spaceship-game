extends Node2D
## Which sound each flight control makes, on both ships, measured at runtime
## from the actual players (not from the code). Needs a real audio driver, so
## run it WINDOWED (ShipAudio / ShuttleAudio are silent under --headless):
##   Godot --path . --fixed-fps 120 res://scenes/test/ship_audio_test.tscn
## For every input it holds the key, then checks:
##   * W: engine bed up from its idle murmur, thruster hiss quiet
##   * S: retro is heard (engine rumble AND thruster hiss), a valve puff fires
##   * A/D/Q/E: thruster hiss + a valve puff, engine bed stays at idle
##   * PETREL: no gyro sound at all (it has no gyro any more)
##   * Shift to 100 %: the high-power roar layer comes in; at 50 % it is silent

const WREN := preload("res://scenes/ship/player_ship.tscn")
const SHUTTLE := preload("res://scenes/ship/shuttle.tscn")
const LOUD := -35.0     # "audible" bed level (dB)
const QUIET := -60.0    # "silent" bed level (dB)

var _fails := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	if not GameplayUtil.audio_enabled():
		print("ship_audio_test: needs a real audio driver (run without --headless)")
		get_tree().quit(1)
		return
	await _ticks(3)
	# ---------------------------------------------------------------- WREN
	var wren := WREN.instantiate() as PlayerShip
	add_child(wren)
	await _ticks(4)
	var wa := wren.get_node(^"Audio")
	print("WREN")
	await _probe(wren, func() -> Dictionary:
		return {"engine": _db(wa.get(&"_engine")), "roar": _db(wa.get(&"_boost")), "hiss": _db(wa.get(&"_hiss")),
			"puff_t": float(wa.get(&"_since_puff"))})
	wren.queue_free()
	await _ticks(4)
	# -------------------------------------------------------------- PETREL
	var ship := SHUTTLE.instantiate() as ShuttleShip
	add_child(ship)
	await _ticks(3)
	ship.take_control()
	ship.on_boarded()
	ship.land_state = ShuttleShip.Land.CRUISE
	ship.altitude_m = ship.cruise_alt_m
	ship.collision_layer = Game.LAYER_PLAYER
	ship.freeze = false
	ship.drop_landed_model()
	await _ticks(6)
	var pa := ship.get_node(^"Audio")
	print("PETREL")
	_check(pa.get(&"_gyro") == null, "no gyro player")
	var gyro_playing := false
	for c in ship.get_children():
		if c is AudioStreamPlayer2D and (c as AudioStreamPlayer2D).stream and String((c as AudioStreamPlayer2D).stream.resource_path).contains("gyro"):
			gyro_playing = true
	_check(not gyro_playing, "gyro whine loop not loaded")
	await _probe(ship, func() -> Dictionary:
		return {"engine": _db(pa.get(&"_engine")), "roar": _db(pa.get(&"_burner")), "hiss": _db(pa.get(&"_hiss")),
			"puff_t": float(pa.get(&"_since_puff"))})
	print("ship_audio_test: %s (%d failure%s)" % ["OK" if _fails == 0 else "FAILED", _fails, "" if _fails == 1 else "s"])
	get_tree().quit(0 if _fails == 0 else 1)


## Holds each control in turn and checks the levels `read` reports.
func _probe(ship: PlayerShip, read: Callable) -> void:
	ship.flight_assist = false
	ship.throttle_setting = 0.5
	await _secs(1.0)
	var idle: Dictionary = read.call()
	# Powered and idle: only the engine's idle murmur.
	_check(idle.engine < -18.0 and idle.hiss <= QUIET and idle.roar <= QUIET, "idle: murmur only  %s" % _fmt(idle))
	for row in [
			[&"thrust_forward", "W", true, false, false],
			[&"thrust_reverse", "S", true, true, true],
			[&"turn_left", "A", false, true, true],
			[&"turn_right", "D", false, true, true],
			[&"strafe_left", "Q", false, true, true],
			[&"strafe_right", "E", false, true, true]]:
		_halt(ship)
		await _secs(1.0)
		Input.action_press(row[0])
		await _secs(0.5)
		var r: Dictionary = read.call()
		Input.action_release(row[0])
		var ok_engine: bool = (r.engine > idle.engine + 6.0) if row[2] else (r.engine <= idle.engine + 0.5)
		var ok_hiss: bool = (r.hiss > LOUD) if row[3] else (r.hiss <= QUIET + 15.0)
		var ok_puff: bool = (r.puff_t < 0.5) if row[4] else true
		_check(ok_engine and ok_hiss and ok_puff and r.roar <= QUIET,
			"%s: engine %s, thrusters %s%s  %s" % [row[1], "up" if row[2] else "at idle", "on" if row[3] else "quiet",
				", valve puff" if row[4] else "", _fmt(r)])
	# Full throttle brings in the high-power layer.
	_halt(ship)
	await _secs(1.0)
	Input.action_press(&"throttle_up")
	await _secs(1.5 / ship.throttle_rate)
	Input.action_release(&"throttle_up")
	Input.action_press(&"thrust_forward")
	await _secs(0.6)
	var full: Dictionary = read.call()
	Input.action_release(&"thrust_forward")
	_check(ship.throttle_setting >= 0.99 and full.roar > LOUD and full.engine > LOUD,
		"100%%: engine + roar  %s" % _fmt(full))
	_halt(ship)
	await _secs(1.0)


func _halt(ship: PlayerShip) -> void:
	ship.linear_velocity = Vector2.ZERO
	ship.angular_velocity = 0.0


func _db(p: Variant) -> float:
	if p == null or not (p is Node) or not (p as Node).is_inside_tree():
		return -100.0
	var playing := bool((p as Node).get(&"playing"))
	return float((p as Node).get(&"volume_db")) if playing else -100.0


func _fmt(d: Dictionary) -> String:
	return "[engine %.0f  roar %.0f  hiss %.0f dB  puff %.2f s ago]" % [d.engine, d.roar, d.hiss, d.puff_t]


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
