extends Node
## Flight deck, second frigate, quantum jump and contracts (run headless):
##   Godot --headless --path . --fixed-fps 120 res://scenes/test/carrier_jump_test.tscn
## Boots the real game and checks:
##   two frigates -> KESTREL in E2 and HALCYON in E1, both real ships; a
##                   station gangway portal resolves to whichever is docked
##   flight deck  -> the WREN docks on the KESTREL's bay pad; X steps out into
##                   the frigate's hangar next to the parked ship
##   helm         -> from the bridge the WREN is stowed and rides the ship
##   jump         -> the drive refuses without a course / too close; a jump
##                   moves the frigate AND the stowed WREN to Vesper, switches
##                   sector, bounds and sky, and hands the helm back
##   far side     -> leave the helm, board the WREN in the hangar, fly it at
##                   Vesper; its recovery point is a Vesper pad
##   contracts    -> drone kills and deliveries pay out
## Prints PASS / FAIL lines and exits with code 0 / 1.

const MAIN := preload("res://scenes/main.tscn")

var _fails := 0
var _main: Node
var _dir: OnFootDirector


func _ready() -> void:
	Game.cmd["no-intro"] = true
	_main = MAIN.instantiate()
	add_child(_main)
	_dir = _main.get_node(^"OnFoot") as OnFootDirector
	_run.call_deferred()


func _run() -> void:
	await _secs(0.6)
	var wren := Game.player as PlayerShip
	var kestrel := _main.get_node(^"Frigate") as FrigateShip
	var halcyon := _main.get_node(^"Halcyon") as FrigateShip
	var jump := _main.get_node(^"Systems/JumpSystem") as JumpSystem
	var dock := _main.get_node(^"Systems/DockingSystem") as DockingSystem

	# ---- two frigates, any-berth gangways
	_check(kestrel.berth_name() == "E2" and kestrel.gangway_ready(), "KESTREL clamped in Berth E2")
	_check(halcyon.berth_name() == "E1" and halcyon.gangway_ready() and halcyon.freeze, "HALCYON is a real ship, clamped in Berth E1")
	_check(String(halcyon.ship_id()) == "halcyon" and String(kestrel.ship_id()) == "kestrel", "ship ids follow the names")
	var portal := InteriorPortal.new()
	add_child(portal)
	portal.berth_id = "E1"
	var link := portal.resolve()
	_check(link.get("frigate") == halcyon and String(link.get("arrival", "")) == "FromGangwayP", "Berth E1's gangway leads aboard the HALCYON, port airlock")
	portal.berth_id = "E2"
	link = portal.resolve()
	_check(link.get("frigate") == kestrel and String(link.get("arrival", "")) == "FromGangwayS", "Berth E2's gangway leads aboard the KESTREL, starboard airlock")
	portal.berth_id = "V1"
	_check(portal.resolve().is_empty(), "an empty berth's gangway is blocked")
	portal.queue_free()

	# ---- the WREN lands on the KESTREL's flight deck
	var pad := kestrel.bay.pads[0]
	wren.respawn_at(Transform2D(kestrel.global_rotation, pad.global_position))
	await _secs(0.5)
	_check(kestrel.bay.contains(wren.global_position), "WREN is over the flight deck")
	dock.force_dock(pad.area)
	await _wait(func() -> bool: return dock.is_settled(), 6.0, "WREN clamped on %s" % pad.pad_name)
	_check(_dir.can_exit(), "X is offered on the bay pad")
	_dir.disembark()
	await _wait(func() -> bool: return _dir.state == OnFootDirector.State.INTERIOR and _dir.get(&"_interior") is FrigateDeck, 8.0, "stepped out into the frigate's hangar")
	var deck := _dir.get(&"_interior") as FrigateDeck
	_check(FrigateShip.aboard == kestrel, "aboard the KESTREL")
	var model := deck.stowed_model(wren)
	_check(model != null, "the parked WREN is shown on the flight deck")
	_check(model != null and _dir.walker.global_position.distance_to(model.foot_global()) < 30.0, "standing at its boarding stairs")
	_check(not _dir.walker.helmet, "the deck holds air: no helmet")
	_check(wren.freeze and wren.collision_layer == Game.LAYER_WORLD, "WREN parked")

	# ---- the lift, then the captain's chair
	var lift := deck.get_node(^"Interactive/LiftAft") as ShipLift
	_dir.walker.place(lift.global_position, 0.0)
	lift.interact(_dir.walker)
	await _wait(func() -> bool: return _dir.state == OnFootDirector.State.INTERIOR and _dir.walker.global_position.distance_to(deck.get_node(^"LiftBridge").global_position) < 6.0, 6.0, "the lift runs to the bridge")
	var chair := deck.get_node(^"Interactive/CaptainChair") as CaptainChair
	_dir.walker.place(chair.global_position + Vector2(0, 16), -PI * 0.5)
	chair.interact(_dir.walker)
	await _wait(func() -> bool: return _dir.state == OnFootDirector.State.FLIGHT and Game.player == kestrel, 10.0, "took the helm")
	await get_tree().physics_frame
	_check(kestrel.bay.is_stowed(wren), "the WREN is stowed: it rides with the ship")
	var local0 := kestrel.global_transform.affine_inverse() * wren.global_transform

	# ---- the drive's interlocks
	_check(jump.blocker(kestrel).begins_with("NO COURSE"), "no course: the drive won't spool")
	jump.set_course(Sectors.VESPER)
	_check(jump.blocker(kestrel) == "UNDOCK FIRST", "clamped in: the drive won't spool")
	Input.action_press(&"thrust_reverse")
	await _wait(func() -> bool: return kestrel.dock.state == FrigateDock.State.UNDOCKING, 3.0, "undocking")
	Input.action_release(&"thrust_reverse")
	await _wait(func() -> bool: return kestrel.dock.state == FrigateDock.State.FREE, 8.0, "free of the berth")
	await _secs(0.3)
	jump.call(&"_can_jump", kestrel, false)
	_check(jump.blocker(kestrel) == "TOO CLOSE TO STRUCTURE", "beside the pier: too close to spool")
	_check(wren.global_position.distance_to((kestrel.global_transform * local0).origin) < 2.0, "the WREN moved off the berth with the ship")

	# ---- the jump
	jump.force_jump(kestrel)
	_check(jump.busy() and kestrel.jump_ctl == jump, "the drive has the helm")
	_check(not _dir.can_exit() or not bool(_dir.call(&"_jump_idle")), "nobody leaves the bridge mid-jump")
	await _wait(func() -> bool: return Game.sector == Sectors.VESPER, 4.0, "sector switched behind the flash")
	_check(Game.world_bounds.is_equal_approx(Sectors.bounds(Sectors.VESPER)), "world bounds are Vesper's")
	var bg := get_tree().get_first_node_in_group(&"space_background")
	_check(bg != null and bg.call(&"look") == &"vesper", "the sky is Vesper's")
	await _wait(func() -> bool: return not jump.busy(), 12.0, "dropped out, helm handed back")
	await get_tree().physics_frame
	await get_tree().physics_frame
	var arrive := Sectors.arrival(Sectors.VESPER).origin
	_check(kestrel.global_position.distance_to(arrive) < 900.0, "KESTREL is at Vesper's arrival point (%.0f m off)" % (kestrel.global_position.distance_to(arrive) / 10.0))
	_check(wren.global_position.distance_to((kestrel.global_transform * local0).origin) < 2.0, "the WREN came along, still on its pad")
	_check(kestrel.jump_ctl == null and kestrel.collision_mask == (Game.LAYER_WORLD | Game.LAYER_PROPS | Game.LAYER_TRAFFIC), "the hull collides again")
	_check(jump.course == &"", "course cleared on arrival")
	_check(kestrel.alive and kestrel.hull > 99.0, "arrived undamaged")

	# ---- on the far side: leave the helm, fly the WREN
	Input.action_press(&"ship_hover")
	await _wait(func() -> bool: return kestrel.speed_mps() < 0.3 and absf(kestrel.angular_velocity) < 0.01, 15.0, "all stop")
	Input.action_release(&"ship_hover")
	_dir.disembark()
	await _wait(func() -> bool: return _dir.state == OnFootDirector.State.INTERIOR and _dir.get(&"_interior") is FrigateDeck, 8.0, "on the bridge at Vesper")
	deck = _dir.get(&"_interior") as FrigateDeck
	model = deck.stowed_model(wren)
	_check(model != null, "the WREN is still in the hangar")
	_dir.walker.place(model.foot_global(), 0.0)
	_dir.board_stowed(wren)
	await _wait(func() -> bool: return _dir.state == OnFootDirector.State.FLIGHT and Game.player == wren, 10.0, "boarded the WREN in the hangar")
	await _secs(0.3)
	_check(Sectors.at(wren.global_position) == Sectors.VESPER, "flying the WREN at Vesper Rock")
	_check(not kestrel.bay.is_stowed(wren), "no longer stowed")
	_check((_dir.get(&"_suspended") as Dictionary).is_empty(), "nothing left suspended")
	_check(Sectors.at(wren.home_transform().origin) == Sectors.VESPER, "a lost WREN is recovered to a Vesper pad")
	_check(kestrel.freeze and kestrel.collision_layer == Game.LAYER_WORLD, "KESTREL parked, adrift at Vesper")

	# ---- contracts
	var contracts := _main.get_node(^"Systems/Contracts") as Contracts
	for i in 8:
		Game.target_destroyed.emit("drone")
	_check(contracts.credits == 250 and int(contracts.state[&"gunnery"].tier) == 2, "8 drones pay the gunnery contract")
	for i in 3:
		Game.cargo_delivered.emit("ORE", "yards", 1)
	_check(contracts.credits == 1450, "3 ore canisters at the Yards intake pay the ore run")
	Game.cargo_delivered.emit("HELIOS", "vesper", 1)
	_check(int(contracts.state[&"resupply"].count) == 1 and int(contracts.state[&"yards"].count) == 0, "a container at Vesper counts for the resupply only")

	print("carrier_jump_test: %s (%d failure%s)" % ["OK" if _fails == 0 else "FAILED", _fails, "" if _fails == 1 else "s"])
	get_tree().quit(0 if _fails == 0 else 1)


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
		print("carrier_jump_test: FAILED (stuck: %s)" % what)
		get_tree().quit(1)
