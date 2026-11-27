extends Node2D
## PETREL cargo hold and freight delivery check (run headless):
##   Godot --headless --path . --fixed-fps 120 res://scenes/test/cargo_hold_test.tscn
## The shuttle alone in empty space with real cargo containers and one
## FreightReceiver, driven through the input actions a player uses:
##   * hook a container and reel: the hold swallows it (count and mass change,
##     the node leaves the tree); a 12 m container takes two slots
##   * a tuning preset or a respawn doesn't lose the cargo's weight
##   * a full hold refuses, once per attempt
##   * U ejects the SAME node behind the stern at ~1.5 m/s and the mass drops;
##     holding U repeats once the stern is clear
##   * a container resting in a FreightReceiver is taken (Game.cargo_delivered,
##     FreightLedger); a moving one is braked first; a wrong brand is refused once
##   * destroying the ship spills the hold around the wreck with its momentum

const SHUTTLE := preload("res://scenes/ship/shuttle.tscn")
const BOX := preload("res://scripts/level/cargo_box.gd")
const DRY_KG := 2600.0

var _fails := 0
var ship: ShuttleShip
var _toasts: Array[String] = []
var _delivered: Array = []
var _serial := 100


func _ready() -> void:
	ship = SHUTTLE.instantiate() as ShuttleShip
	add_child(ship)
	Game.message.connect(func(text: String, _d: float) -> void: _toasts.append(text))
	Game.cargo_delivered.connect(func(brand: String, id: String, slots: int) -> void: _delivered.append([brand, id, slots]))
	FreightLedger.reset()
	_run.call_deferred()


func _run() -> void:
	await _ticks(3)
	ship.take_control()
	ship.on_boarded()
	ship.land_state = ShuttleShip.Land.CRUISE
	ship.altitude_m = ship.cruise_alt_m
	ship.collision_layer = Game.LAYER_PLAYER
	ship.freeze = false
	ship.drop_landed_model()
	await _ticks(2)
	var hold := ship.hold
	_check(hold != null and hold.capacity == 10 and hold.used() == 0 and hold.free_slots() == 10, "starts with an empty 10-slot hold")
	_check(is_equal_approx(ship.mass_kg, DRY_KG) and is_equal_approx(ship.mass, DRY_KG), "dry mass %.0f kg" % ship.mass)

	# ---- towing without reeling never stows
	var first := _box_ahead(12.0, false, "HELIOS")
	await _hook()
	_check(ship.line.is_attached() and ship.line.target == first, "line hooks the container")
	Input.action_press(&"thrust_reverse")
	await _secs(2.0)
	Input.action_release(&"thrust_reverse")
	_check(hold.used() == 0 and first.is_inside_tree(), "towing without reeling leaves the hold alone")

	# ---- hook + reel: swallowed
	Input.action_press(&"ship_reel")
	await _until(func() -> bool: return hold.used() > 0, 12.0)
	_unhook()
	_check(hold.used() == 1 and hold.count() == 1, "reeled alongside: stowed (hold %d/10)" % hold.used())
	_check(not first.is_inside_tree() and is_instance_valid(first), "the container left the world but is kept")
	_check(not ship.line.is_attached(), "line released on stowing")
	_check(is_equal_approx(ship.mass_kg, DRY_KG + 160.0) and is_equal_approx(ship.mass, DRY_KG + 160.0), "one slot adds 160 kg (%.0f)" % ship.mass)
	var it: Dictionary = hold.items()[0]
	_check(it.brand == "HELIOS" and it.slots == 1 and it.color is Color, "items() describes it (%s, %d slot)" % [it.brand, it.slots])
	_check(_said("STOWED") == 1, "one STOWED toast")

	# ---- a 12 m container takes two slots
	await _settle()
	var long_box := _box_ahead(14.0, true, "VEGA LOG")
	await _hook()
	Input.action_press(&"ship_reel")
	await _until(func() -> bool: return hold.used() >= 3, 12.0)
	_unhook()
	_check(hold.used() == 3 and hold.count() == 2 and not long_box.is_inside_tree(), "12 m container takes two slots (hold %d/10)" % hold.used())
	_check(is_equal_approx(ship.mass, DRY_KG + 480.0), "three slots: +480 kg (%.0f)" % ship.mass)

	# ---- presets and respawns keep the cargo's weight
	ship.set(&"mass_kg", float(ShuttleShip.PETREL_DEFAULTS.mass_kg))     # what "PETREL default" does
	_check(is_equal_approx(ship.mass, DRY_KG + 480.0) and is_equal_approx(ship.dry_mass_kg(), DRY_KG), "a tuning preset keeps the cargo mass (%.0f)" % ship.mass)
	ship.respawn_at(Transform2D(0.0, Vector2(4000, 0)))
	await _ticks(4)
	_check(hold.used() == 3 and is_equal_approx(ship.mass, DRY_KG + 480.0), "a respawn keeps the hold and its weight")

	# ---- nearly full: a long box no longer fits, a short one does
	await _settle()
	while hold.used() < 9:
		_check(hold.stow(_box_far()), "stow() takes a container directly")
	var long2 := _box_far(true)
	var short2 := _box_far()
	_check(hold.free_slots() == 1 and not hold.can_take(long2) and hold.can_take(short2), "9/10: no room for a 12 m container, room for a 6 m one")
	_check(not hold.stow(long2) and long2.is_inside_tree(), "stow() refuses what doesn't fit")
	long2.queue_free()
	_check(hold.stow(short2) and hold.used() == 10, "full: 10/10")
	_check(is_equal_approx(ship.mass, DRY_KG + 1600.0), "full hold: +1600 kg (%.0f)" % ship.mass)

	# ---- a full hold refuses, and says so once
	var extra := _box_ahead(12.0, false, "TIDEWAY")
	_toasts.clear()
	await _hook()
	Input.action_press(&"ship_reel")
	_check(ship.line.is_attached() and ship.line.target == extra, "hooked the extra container")
	await _secs(6.0)
	_unhook()
	_check(hold.used() == 10 and extra.is_inside_tree(), "full hold refuses the container")
	_check(_said("HOLD FULL") == 1, "refusal announced once, not every frame (%d)" % _said("HOLD FULL"))
	extra.queue_free()
	await _settle()

	# ---- unload: the same node comes out behind the stern
	_toasts.clear()
	var v0 := ship.linear_velocity
	Input.action_press(&"cargo_unload")
	await _ticks(3)
	Input.action_release(&"cargo_unload")
	await _ticks(2)
	_check(hold.used() == 9 and short2.is_inside_tree(), "U ejects the last container stowed (LIFO), the same node")
	var local := ship.to_local(short2.global_position) / Game.PX_PER_M
	_check(local.x < -6.6 - 3.0 and absf(local.y) < 0.5, "it comes out behind the stern (%.1f, %.1f m)" % [local.x, local.y])
	var fwd := Vector2.from_angle(ship.global_rotation)
	var rel := (short2.linear_velocity - v0).dot(fwd) / Game.PX_PER_M
	_check(absf(rel + 1.5) < 0.25, "pushed out at about 1.5 m/s (%.2f)" % rel)
	var kick := (ship.linear_velocity - v0).dot(fwd) / Game.PX_PER_M
	_check(kick > 0.02 and kick < 0.3, "the ship gets the opposite nudge (%.3f m/s)" % kick)
	_check(is_equal_approx(ship.mass, DRY_KG + 9.0 * 160.0), "mass drops with it (%.0f)" % ship.mass)
	_check(short2.get(&"brand") == "HELIOS" and String(short2.get(&"serial")).begins_with("TEST"), "livery and serial intact")
	# The stern is still blocked by that one: a new press is refused, once.
	_toasts.clear()
	Input.action_press(&"cargo_unload")
	await _secs(0.6)
	_check(hold.used() == 9 and _said("STERN BLOCKED") == 1, "blocked stern: refused once (%d)" % _said("STERN BLOCKED"))
	Input.action_release(&"cargo_unload")
	await _ticks(2)
	# Holding U repeats as the stern clears.
	short2.queue_free()
	await _ticks(3)
	Input.action_press(&"cargo_unload")
	await _secs(11.0)
	Input.action_release(&"cargo_unload")
	_check(hold.used() <= 7, "holding U keeps unloading as the stern clears (hold %d/10)" % hold.used())
	# Not on the deck.
	ship.land_state = ShuttleShip.Land.LANDED
	_check(ship.cargo.unload() == null and ship.cargo.unload_block() != "", "no unloading while landed")
	ship.land_state = ShuttleShip.Land.CRUISE
	# Empty it: back to the dry mass.
	for b in get_children():
		if b is RigidBody2D and b != ship:
			b.queue_free()
	while not hold.is_empty():
		hold.eject().free()
	_check(is_equal_approx(ship.mass_kg, DRY_KG) and is_equal_approx(ship.mass, DRY_KG), "empty again: dry mass (%.0f)" % ship.mass)

	await _receiver_checks()

	# ---- losing the ship spills the hold, with its momentum
	await _settle()
	var cargo: Array[RigidBody2D] = [_box_far(), _box_far(true), _box_far(), _box_far()]
	for b in cargo:
		hold.stow(b)
	ship.linear_velocity = Vector2(120.0, 0.0)      # 12 m/s
	await _ticks(6)
	var wreck := ship.global_position
	ship.destroy()
	await _ticks(3)
	var all_out := true
	var mean_v := Vector2.ZERO
	var worst := 0.0
	for b in cargo:
		all_out = all_out and b.is_inside_tree()
		if b.is_inside_tree():
			mean_v += b.linear_velocity / cargo.size()
			worst = maxf(worst, b.global_position.distance_to(wreck) / Game.PX_PER_M)
	_check(hold.is_empty() and all_out, "destroyed: all %d containers spill out" % cargo.size())
	_check(worst < 30.0, "around the wreck (furthest %.1f m)" % worst)
	_check(mean_v.x / Game.PX_PER_M > 6.0, "with the ship's momentum (%.1f m/s)" % (mean_v.x / Game.PX_PER_M))
	_check(is_equal_approx(ship.mass_kg, DRY_KG), "the wreck is back to its dry mass")
	var overlap := false
	for i in cargo.size():
		for j in range(i + 1, cargo.size()):
			if cargo[i].global_position.distance_to(cargo[j].global_position) < 60.0:
				overlap = true
	_check(not overlap, "spilled containers don't start inside each other")

	print("cargo_hold_test: %s (%d failure%s)" % ["OK" if _fails == 0 else "FAILED", _fails, "" if _fails == 1 else "s"])
	LevelArt.cleanup()
	get_tree().quit(0 if _fails == 0 else 1)


func _receiver_checks() -> void:
	var rc := FreightReceiver.new()
	rc.receiver_id = "test"
	rc.title = "TEST INTAKE"
	rc.position = Vector2(0, 30000)
	add_child(rc)
	var picky := FreightReceiver.new()
	picky.receiver_id = "picky"
	picky.title = "HELIOS DEPOT"
	picky.accepts = PackedStringArray(["HELIOS"])
	picky.position = Vector2(20000, 30000)
	add_child(picky)
	await _ticks(3)
	_check(rc.is_in_group(&"freight_receiver") and rc.takes("ANYTHING") and picky.takes("helios") and not picky.takes("AURORA"), "receivers: group and accepted brands")
	# Resting inside the stripes: taken.
	_toasts.clear()
	var rest := _box(rc.position + Vector2(120, 40), true, "AURORA")
	await _until(func() -> bool: return not _delivered.is_empty(), 3.0)
	_check(_delivered.size() == 1 and _delivered[0] == ["AURORA", "test", 2], "resting container delivered: cargo_delivered%s" % str(_delivered))
	await _ticks(3)
	_check(not is_instance_valid(rest), "the delivered container is gone")
	_check(FreightLedger.count("test") == 1 and FreightLedger.total() == 1 and FreightLedger.total_slots() == 2, "FreightLedger tallies it")
	_check(_said("DELIVERED  ·  AURORA  ·  TEST INTAKE") == 1, "delivery toast")
	# Shoved in at speed: braked, then taken.
	var moving := _box(rc.position + Vector2(-200, 100), false, "CASSINI")
	moving.linear_velocity = Vector2(30.0, -20.0)      # 3.6 m/s
	await _ticks(30)
	_check(_delivered.size() == 1, "a container still moving is not taken yet")
	await _until(func() -> bool: return _delivered.size() >= 2, 5.0)
	_check(_delivered.size() == 2 and _delivered[1] == ["CASSINI", "test", 1], "braked inside the zone, then delivered")
	# Outside the stripes: left alone.
	var outside := _box(rc.position + Vector2(400, 0), false, "NORDHAV")
	await _secs(1.5)
	_check(_delivered.size() == 2 and is_instance_valid(outside), "a container outside the border is left alone")
	outside.queue_free()
	# Wrong brand: refused, said once.
	_toasts.clear()
	var wrong := _box(picky.position + Vector2(-100, 0), false, "TIDEWAY")
	await _secs(2.5)
	_check(is_instance_valid(wrong) and wrong.is_inside_tree() and FreightLedger.count("picky") == 0, "wrong brand is not taken")
	_check(_said("HELIOS DEPOT doesn't take TIDEWAY") == 1, "refused once (%d)" % _said("doesn't take"))
	var right := _box(picky.position + Vector2(100, 0), false, "HELIOS")
	await _until(func() -> bool: return FreightLedger.count("picky") == 1, 3.0)
	_check(FreightLedger.count("picky") == 1 and FreightLedger.total() == 3 and not is_instance_valid(right), "right brand is taken (total %d)" % FreightLedger.total())
	wrong.queue_free()
	await _ticks(2)


# ------------------------------------------------------------------ helpers

func _box(at: Vector2, long := false, brand := "HELIOS", rot := 0.0) -> RigidBody2D:
	var b: RigidBody2D = BOX.new()
	_serial += 1
	b.call(&"setup", Vector2(12.2 if long else 6.1, 2.44), Color("E76F51"), brand, "TEST %06d" % _serial)
	b.position = at
	b.rotation = rot
	add_child(b)
	return b


## A container broadside-on, `gap_m` ahead of the nose.
func _box_ahead(gap_m: float, long := false, brand := "HELIOS") -> RigidBody2D:
	var fwd := Vector2.from_angle(ship.global_rotation)
	return _box(ship.global_position + fwd * (70.0 + gap_m * Game.PX_PER_M), long, brand, ship.global_rotation + PI * 0.5)


## A container parked far from everything (stowed directly through the API).
func _box_far(long := false) -> RigidBody2D:
	return _box(Vector2(-60000.0 - _serial * 300.0, -60000.0), long, "HELIOS")


## Aim along +X (the ship faces that way) and hold the line button. The aim
## is held on the stick action: holding the line button otherwise aims at the
## mouse, which in a headless run is wherever the OS left it.
func _hook() -> void:
	Input.action_press(&"aim_right")
	await _ticks(8)
	Input.action_press(&"ship_line")
	await _ticks(2)


func _unhook() -> void:
	Input.action_release(&"ship_reel")
	Input.action_release(&"ship_line")
	Input.action_release(&"aim_right")


## Stop the ship dead and let the line cool down.
func _settle() -> void:
	ship.linear_velocity = Vector2.ZERO
	ship.angular_velocity = 0.0
	await _secs(0.6)
	ship.linear_velocity = Vector2.ZERO
	ship.angular_velocity = 0.0
	await _ticks(2)


func _said(part: String) -> int:
	var n := 0
	for t in _toasts:
		if t.contains(part):
			n += 1
	return n


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


func _until(cond: Callable, timeout: float) -> void:
	var t := 0.0
	while not cond.call() and t < timeout:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
