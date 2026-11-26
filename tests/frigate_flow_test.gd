extends Node
## KESTREL on-foot loop (run headless):
##   Godot --headless --path . --fixed-fps 120 res://scenes/test/frigate_flow_test.tscn
## Boots the real game, gets out of the WREN on Pad 2 and checks:
##   berth        -> the KESTREL starts clamped in Berth E2, gangway sealed, parked
##   concourse    -> the south wing's gangway door is open for a docked frigate,
##                   the gangway tube is walled in (no way out into space)
##   portal       -> "Board KESTREL" swaps to the frigate's deck at its airlock
##   chair        -> taking the helm makes the KESTREL the player, still clamped
##   undock       -> holding a flight key runs gangway-in, clamps-open, release
##   all stop     -> Space brakes the ship to a stop; X then works (adrift)
##   re-dock      -> in the capture box: soft capture, hard dock, gangway out
##   leave helm   -> X puts you on the bridge on foot; the frigate parks
##   way back     -> gangway portal to the concourse, airlock 7B to Pad 2, and
##                   board the WREN; nothing is left suspended
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
	await _wait(func() -> bool: return _dir.state == OnFootDirector.State.EXTERIOR, 15.0, "out of the WREN on Pad 2")
	var wren := Game.player as PlayerShip
	var kestrel := _main.get_node(^"Frigate") as FrigateShip
	_check(kestrel.dock.state == FrigateDock.State.LOCKED and kestrel.gangway_ready(), "KESTREL clamped in Berth E2, gangway sealed")
	_check(kestrel.freeze and kestrel.collision_layer == Game.LAYER_WORLD, "KESTREL parked (frozen, static layer)")
	_check(kestrel.global_position.distance_to(kestrel.dock.target().origin) < 0.5, "parked exactly on the berth mark")

	# ---- into the concourse, through the south wing to the gangway
	_dir.call(&"_enter_interior")
	await _wait(func() -> bool: return _dir.state == OnFootDirector.State.INTERIOR, 15.0, "inside the Pier 7 concourse")
	var conc := _dir.get(&"_interior") as InteriorLevel
	await _secs(0.6)
	var gdoor := conc.get_node(^"Doors/GangwayDoor") as SlidingDoor
	_check(not gdoor.locked and gdoor.auto, "gangway door opens for a docked frigate")
	_check(_walled(conc, Vector2(500, 172)) and _walled(conc, Vector2(500, 208)), "gangway tube has hull on both sides")
	_check(_walled(conc, Vector2(775, 178)), "gangway end is sealed apart from the hatch")
	var portal := conc.get_node(^"Interactive/BoardKestrel") as InteriorPortal
	_dir.walker.place(portal.global_position - Vector2(12, 0), 0.0)
	portal.interact(_dir.walker)
	await _wait(func() -> bool: return _dir.state == OnFootDirector.State.INTERIOR and _dir.get(&"_interior") is FrigateDeck, 10.0, "through the hatch onto the KESTREL")
	var deck := _dir.get(&"_interior") as FrigateDeck
	_check(deck.global_position.distance_to(kestrel.global_position) < 1.0, "deck placed on the ship")
	_check(_dir.walker.global_position.distance_to(deck.get_node(^"FromGangway").global_position) < 4.0, "arrived in the airlock")
	_check(not _dir.walker.helmet, "helmet off aboard")

	# ---- the captain's chair
	var chair := deck.get_node(^"Interactive/CaptainChair") as CaptainChair
	_dir.walker.place(chair.global_position + Vector2(0, 16), -PI * 0.5)
	chair.interact(_dir.walker)
	await _wait(func() -> bool: return _dir.state == OnFootDirector.State.FLIGHT and Game.player == kestrel, 10.0, "took the helm")
	await get_tree().physics_frame
	_check(Game.mode == Game.Mode.FLIGHT and _dir.walker == null, "flight mode, walker gone")
	_check(kestrel.collision_layer == Game.LAYER_PLAYER and kestrel.freeze, "KESTREL is the player, still in the clamps")
	_check(wren.freeze and wren.has_landed_model(), "WREN stays parked on Pad 2")
	_check((_dir.get(&"_suspended") as Dictionary).is_empty(), "world and flight layer fully resumed")

	# ---- undock: hold a flight key
	Input.action_press(&"thrust_reverse")
	await _wait(func() -> bool: return kestrel.dock.state == FrigateDock.State.UNDOCKING, 3.0, "holding S starts undocking")
	Input.action_release(&"thrust_reverse")
	await _wait(func() -> bool: return kestrel.dock.state == FrigateDock.State.FREE, 8.0, "gangway in, clamps open, released")
	await get_tree().physics_frame
	_check(not kestrel.freeze and kestrel.dock.gangway_t <= 0.0, "free of the berth")
	await _secs(3.0)
	_check(kestrel.dock.dist > 1.0, "pushed off the pier (%.1f m)" % kestrel.dock.dist)

	# ---- all stop, then X works adrift
	Input.action_press(&"ship_hover")
	await _wait(func() -> bool: return kestrel.speed_mps() < 0.3 and absf(kestrel.angular_velocity) < 0.01, 15.0, "all stop brakes to a halt")
	_check(_dir.can_exit(), "X: leave the bridge at all stop")
	Input.action_release(&"ship_hover")

	# ---- back into the capture box (as if flown there): capture -> lock -> gangway
	var t := kestrel.dock.target()
	kestrel.respawn_at(Transform2D(t.get_rotation() + deg_to_rad(1.5), t.origin + t.x * 18.0 - t.y * 20.0))
	await _wait(func() -> bool: return kestrel.dock.state == FrigateDock.State.CAPTURE, 4.0, "soft capture from the box")
	await _wait(func() -> bool: return kestrel.dock.state == FrigateDock.State.LOCKED, 16.0, "hard dock")
	await _wait(func() -> bool: return kestrel.gangway_ready(), 8.0, "gangway sealed again")
	_check(kestrel.global_position.distance_to(t.origin) < 0.5 and absf(angle_difference(kestrel.global_rotation, t.get_rotation())) < 0.01, "drawn exactly onto the mark")

	# ---- leave the helm: on foot on the bridge
	_dir.disembark()
	await _wait(func() -> bool: return _dir.state == OnFootDirector.State.INTERIOR and _dir.get(&"_interior") is FrigateDeck, 8.0, "X: back on the bridge")
	deck = _dir.get(&"_interior") as FrigateDeck
	_check(Game.mode == Game.Mode.ON_FOOT and _dir.walker != null, "on foot")
	_check(kestrel.freeze and kestrel.collision_layer == Game.LAYER_WORLD, "KESTREL parked in the berth")
	_check(_dir.walker.global_position.distance_to(deck.get_node(^"BridgeStand").global_position) < 2.0, "standing by the chair")

	# ---- the way back: gangway -> concourse -> airlock 7B -> Pad 2 -> WREN
	var hatch := deck.get_node(^"Interactive/GangwayHatch") as InteriorPortal
	_dir.walker.place(hatch.global_position - Vector2(10, 0), 0.0)
	hatch.interact(_dir.walker)
	await _wait(func() -> bool: return _dir.state == OnFootDirector.State.INTERIOR and _dir.get(&"_interior") != null and String((_dir.get(&"_interior") as Node).name) == "Pier7Concourse", 10.0, "back across the gangway")
	_check(_dir.walker.global_position.distance_to((_dir.get(&"_interior") as Node).get_node(^"FromFrigate").global_position) < 4.0, "arrived at the gangway's station end")
	_dir.call(&"_leave_interior")
	await _wait(func() -> bool: return _dir.state == OnFootDirector.State.EXTERIOR, 12.0, "out through airlock 7B")
	_check(String(_dir.pad_name) == "Pad 2" and _dir.get(&"_extras") != null, "Pad 2 site rebuilt")
	var wm := wren.landed_model() as LandedShip
	_dir.walker.place(wm.foot_global(), 0.0)
	_dir.board(wren)
	await _wait(func() -> bool: return _dir.state == OnFootDirector.State.FLIGHT and Game.player == wren, 15.0, "boarded the WREN")
	await get_tree().physics_frame
	_check((_dir.get(&"_suspended") as Dictionary).is_empty(), "nothing left suspended")
	_check(kestrel.freeze and kestrel.gangway_ready(), "KESTREL stays berthed")

	print("frigate_flow_test: %s (%d failure%s)" % ["OK" if _fails == 0 else "FAILED", _fails, "" if _fails == 1 else "s"])
	get_tree().quit(0 if _fails == 0 else 1)


## Is there a wall rectangle at local point `p` of the interior?
func _walled(il: InteriorLevel, p: Vector2) -> bool:
	for w in il.walls:
		if (w[0] as Rect2).grow(0.5).has_point(p):
			return true
	return false


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
		print("frigate_flow_test: FAILED (stuck: %s)" % what)
		get_tree().quit(1)
