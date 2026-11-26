extends Node
## On-foot flow check (run headless):
##   Godot --headless --path . --fixed-fps 120 res://scenes/test/onfoot_flow_test.tscn
## Boots the real game (main.tscn), docks at Pad 2 and drives the whole loop
## through the OnFootDirector, checking the state the player can't see:
##   disembark -> flight systems paused, ship frozen, parallax flat, walker out
##   airlock   -> station suspended (no processing, bodies out of physics),
##                interior loaded, pressurised (helmet off)
##   switch    -> a light switch toggles its room light
##   leave     -> interior freed, station resumed, flight layer STILL paused
##   re-enter  -> the light is still on (state persisted across the unload)
##   board     -> everything back to flight, nothing left behind
## Prints PASS / FAIL lines and exits with code 0 / 1.

const MAIN := preload("res://scenes/main.tscn")

var _fails := 0
var _main: Node
var _dir: OnFootDirector


func _ready() -> void:
	Game.cmd["no-intro"] = true
	Game.cmd["dock-at"] = "2"
	Game.cmd["on-foot"] = true
	_main = MAIN.instantiate()
	add_child(_main)
	_dir = _main.get_node(^"OnFoot") as OnFootDirector
	_run.call_deferred()


func _run() -> void:
	# ---- disembark
	await _wait_state(OnFootDirector.State.EXTERIOR, 15.0, "disembarked at Pad 2")
	var ship := Game.player as RigidBody2D
	_check(Game.mode == Game.Mode.ON_FOOT, "game mode is ON_FOOT")
	_check(_dir.walker != null and is_instance_valid(_dir.walker), "walker spawned")
	_check(ship.freeze, "parked ship is frozen")
	_check(not bool(ship.get(&"controls_enabled")), "ship controls disabled")
	_check(is_zero_approx(LevelArt.depth_amount), "2.5D parallax flattened")
	_check(_sys(&"RaceSystem").process_mode == Node.PROCESS_MODE_DISABLED, "race system paused")
	_check(_sys(&"DockingSystem").process_mode == Node.PROCESS_MODE_DISABLED, "docking system paused")
	_check(not (_main.get_node(^"HUD/FlightPanel") as CanvasItem).visible, "flight HUD hidden")
	_check(_dir.landed != null, "detailed landed-ship model shown")
	var pad2 := _dir.get(&"_extras") as Node2D
	_check(pad2 != null and String(pad2.call(&"get_interior_path")) != "", "Pad 2 site has an interior")

	# ---- into the interior
	_dir.call(&"_enter_interior")
	await _wait_state(OnFootDirector.State.INTERIOR, 15.0, "entered the interior")
	var level := _main.get_node(^"Level")
	_check(level.process_mode == Node.PROCESS_MODE_DISABLED and not (level as CanvasItem).visible, "station suspended and hidden")
	_check(ship.process_mode == Node.PROCESS_MODE_DISABLED, "ship suspended (out of physics)")
	var interior := _dir.get(&"_interior") as InteriorLevel
	_check(interior != null and interior.walls.size() >= 15, "interior walls built (%d)" % (interior.walls.size() if interior else 0))
	await _wait(func() -> bool: return not _dir.walker.helmet, 6.0, "airlock pressurised, helmet off")

	# ---- a light switch
	var sw := interior.get_node(^"Switches/QuartersSwitch") as LightSwitch
	var light := interior.get_node(^"Lights/QuartersLight") as RoomLight
	_check(not light.on, "quarters start dark")
	sw.interact(_dir.walker)
	_check(light.on, "light switch turns the quarters light on")

	# ---- leave
	_dir.call(&"_leave_interior")
	await _wait_state(OnFootDirector.State.EXTERIOR, 15.0, "back outside")
	_check(_dir.get(&"_interior") == null, "interior unloaded")
	_check(level.process_mode != Node.PROCESS_MODE_DISABLED and (level as CanvasItem).visible, "station resumed")
	_check(_sys(&"RaceSystem").process_mode == Node.PROCESS_MODE_DISABLED, "flight systems still paused while on foot")
	_check(_dir.walker.helmet, "helmet back on outside")

	# ---- re-enter: state persisted
	_dir.call(&"_enter_interior")
	await _wait_state(OnFootDirector.State.INTERIOR, 15.0, "re-entered the interior")
	interior = _dir.get(&"_interior") as InteriorLevel
	_check((interior.get_node(^"Lights/QuartersLight") as RoomLight).on, "quarters light still on (state restored)")
	await _wait(func() -> bool: return not (interior.get_node(^"Airlock") as Airlock).cycling, 6.0, "airlock cycle finished")
	_dir.call(&"_leave_interior")
	await _wait_state(OnFootDirector.State.EXTERIOR, 15.0, "outside again")

	# ---- board (stand at the foot of the boarding stairs first, as a player would)
	_dir.walker.place(_dir.landed.foot_global(), 0.0)
	_dir.board()
	await _wait_state(OnFootDirector.State.FLIGHT, 15.0, "boarded")
	await get_tree().physics_frame
	_check(Game.mode == Game.Mode.FLIGHT, "game mode is FLIGHT")
	_check(not ship.freeze and bool(ship.get(&"controls_enabled")), "ship unfrozen with controls")
	_check(is_equal_approx(LevelArt.depth_amount, 1.0), "parallax restored")
	_check(_sys(&"DockingSystem").process_mode != Node.PROCESS_MODE_DISABLED, "docking system running again")
	_check((_main.get_node(^"HUD/FlightPanel") as CanvasItem).visible, "flight HUD visible")
	_check(_dir.walker == null and _dir.landed == null, "walker and landed model gone")
	_check(_dir.get_node(^"Site").get_child_count() == 0, "pad site freed")
	_check((_dir.get(&"_suspended") as Dictionary).is_empty(), "nothing left suspended")

	print("onfoot_flow_test: %s (%d failure%s)" % ["OK" if _fails == 0 else "FAILED", _fails, "" if _fails == 1 else "s"])
	get_tree().quit(0 if _fails == 0 else 1)


func _sys(n: StringName) -> Node:
	return _main.get_node(NodePath("Systems/%s" % n))


func _check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_fails += 1


func _wait_state(s: OnFootDirector.State, timeout: float, what: String) -> void:
	await _wait(func() -> bool: return _dir.state == s, timeout, what)


func _wait(cond: Callable, timeout: float, what: String) -> void:
	var t := 0.0
	while not cond.call() and t < timeout:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	_check(cond.call(), "%s (%.1f s)" % [what, t])
	if not cond.call():
		print("onfoot_flow_test: FAILED (stuck: %s)" % what)
		get_tree().quit(1)
