extends Node
## Two-ship on-foot loop (run headless):
##   Godot --headless --path . --fixed-fps 120 res://scenes/test/vehicles_flow_test.tscn
## Boots the real game, docks the WREN in Hangar 2 and checks:
##   hangar site   -> stairs gap in the pad railing, hangar floor walkable
##   PETREL parked -> frozen static obstacle with its landed model, not the player
##   board PETREL  -> it becomes Game.player (landed, frozen); WREN parked
##   lift off      -> a move input releases the mag-skids
##   land anywhere -> hold hover until LANDED on the hangar deck, then get out
##   board WREN    -> back in the courier; the PETREL stays parked where it landed
## Prints PASS / FAIL lines and exits with code 0 / 1.

const MAIN := preload("res://scenes/main.tscn")

var _fails := 0
var _main: Node
var _dir: OnFootDirector


func _ready() -> void:
	Game.cmd["no-intro"] = true
	Game.cmd["dock-at"] = "Hangar Bay"
	Game.cmd["on-foot"] = true
	_main = MAIN.instantiate()
	add_child(_main)
	_dir = _main.get_node(^"OnFoot") as OnFootDirector
	_run.call_deferred()


func _run() -> void:
	await _wait(func() -> bool: return _dir.state == OnFootDirector.State.EXTERIOR, 15.0, "out of the WREN in Hangar 2")
	var wren := Game.player as PlayerShip
	var petrel := _main.get_node(^"Shuttle") as ShuttleShip
	var site := _dir.get_node(^"Site/WalkSite") as WalkSite
	_check(_dir.get(&"_extras") != null and String(_dir.pad_name) == "Hangar 2", "hangar site loaded (%s)" % _dir.pad_name)
	_check(site != null and _has_gap(site), "pad railing has the stairs gap")
	_check(petrel.freeze and petrel.collision_layer == Game.LAYER_WORLD, "PETREL parked: frozen, static layer")
	_check(petrel.has_landed_model() and Game.player == wren, "PETREL shows its landed model; WREN is the player")
	_check(petrel.land_state == ShuttleShip.Land.LANDED, "PETREL starts landed on its berth")

	# ---- walk over (teleport to its ramp foot, as if we took the stairs) and board
	var model := petrel.landed_model() as LandedShip
	_dir.walker.place(model.foot_global(), 0.0)
	_dir.board(petrel)
	await _wait(func() -> bool: return _dir.state == OnFootDirector.State.FLIGHT, 15.0, "boarded the PETREL")
	await get_tree().physics_frame
	_check(Game.player == petrel, "PETREL is the player")
	_check(wren.freeze and wren.collision_layer == Game.LAYER_WORLD and wren.has_landed_model(), "WREN parked behind us")
	_check(petrel.collision_layer == Game.LAYER_PLAYER and petrel.freeze, "PETREL aboard: player layer, still clamped")
	_check(not petrel.has_landed_model(), "PETREL flight art back")

	# ---- lift off
	Input.action_press(&"move_left")
	await _wait(func() -> bool: return petrel.land_state != ShuttleShip.Land.LANDED and not petrel.freeze, 3.0, "move input lifts off")
	await _secs(1.2)
	Input.action_release(&"move_left")
	_check(petrel.altitude_m > 1.0, "climbing (alt %.1f m)" % petrel.altitude_m)

	# ---- land anywhere: hover over the hangar deck until the skids lock
	Input.action_press(&"ship_hover")
	await _wait(func() -> bool: return petrel.land_state == ShuttleShip.Land.LANDED, 14.0, "hover-land on the hangar deck (%s)" % petrel.land_status)
	Input.action_release(&"ship_hover")
	await get_tree().physics_frame
	_check(petrel.freeze, "skids locked (frozen)")
	_check(_dir.can_exit(), "X can get out")

	# ---- get out, board the WREN
	_dir.disembark()
	await _wait(func() -> bool: return _dir.state == OnFootDirector.State.EXTERIOR, 15.0, "out of the PETREL")
	_check(String(_dir.pad_name) == "Hangar 2", "same hangar site from a deck landing")
	_check(petrel.freeze and petrel.collision_layer == Game.LAYER_WORLD, "PETREL parked where it landed")
	var wm := wren.landed_model() as LandedShip
	_dir.walker.place(wm.foot_global(), 0.0)
	_dir.board(wren)
	await _wait(func() -> bool: return _dir.state == OnFootDirector.State.FLIGHT, 15.0, "boarded the WREN")
	await get_tree().physics_frame
	_check(Game.player == wren and not wren.freeze, "WREN is the player again")
	_check(petrel.freeze and petrel.has_landed_model(), "PETREL stays parked")
	# Back in the WREN on its pad: the clamps re-engage, so you can get out again.
	await _wait(func() -> bool: return _dir.can_exit(), 2.0, "WREN re-docked in place (X works again)")
	_check((_dir.get(&"_suspended") as Dictionary).is_empty(), "nothing left suspended")

	print("vehicles_flow_test: %s (%d failure%s)" % ["OK" if _fails == 0 else "FAILED", _fails, "" if _fails == 1 else "s"])
	get_tree().quit(0 if _fails == 0 else 1)


func _has_gap(site: WalkSite) -> bool:
	# The pad's east rail (x = 604.5 m) must be split around the stairs.
	var pieces := 0
	for seg in site.get(&"_rails"):
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		if absf(a.x - 6045.0) < 2.0 and absf(b.x - 6045.0) < 2.0:
			pieces += 1
	return pieces >= 2


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
		print("vehicles_flow_test: FAILED (stuck: %s)" % what)
		get_tree().quit(1)
