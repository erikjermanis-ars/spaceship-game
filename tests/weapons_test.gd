extends Node2D
## Weapons check (run headless):
##   Godot --headless --path . --fixed-fps 120 res://scenes/test/weapons_test.tscn
## The WREN, a WeaponSystem and a few things to shoot, alone in empty space:
##   * a bolt flies at 260 m/s, keeps the shooter's velocity, fades out at range
##   * a bolt can't tunnel through a thin wall, and the wall's take_shot() gets
##     (damage, at, dir, shooter); Game.shot_hit follows
##   * a target drone staggers on the first hit, bursts on the second
##     (Game.target_destroyed) and respawns
##   * a free container is shoved along the bolt
##   * a parked ship takes a scratch (never below half hull) and your HUD's
##     hull signal is left alone
##   * the guns fire 6 /s through the `ship_fire` action, overheat, lock out,
##     recover, and stay safe with the controls off or a latched key

const SHIP := preload("res://scenes/ship/player_ship.tscn")
const CARGO := preload("res://scripts/level/cargo_box.gd")
const LANE := 4000.0          # px between test lanes: nothing shares a line of fire

var _fails := 0
var ship: PlayerShip
var guns: WrenGuns
var weapons: WeaponSystem
var _shot_hits: Array = []
var _destroyed: Array = []
var _hull_events: Array = []


## Records take_shot() calls: stands in for whatever another system makes
## shootable (asteroids ...).
class ShotCatcher extends StaticBody2D:
	var calls: Array = []

	func take_shot(damage: float, at: Vector2, dir: Vector2, shooter: Node) -> void:
		calls.append([damage, at, dir, shooter])


func _ready() -> void:
	weapons = WeaponSystem.new()
	weapons.name = "Weapons"
	add_child(weapons)
	ship = SHIP.instantiate() as PlayerShip
	add_child(ship)
	guns = ship.get_node(^"Guns") as WrenGuns
	Game.shot_hit.connect(func(pos: Vector2, normal: Vector2, collider: Node, shooter: Node) -> void:
		_shot_hits.append([pos, normal, collider, shooter]))
	Game.target_destroyed.connect(func(kind: String) -> void: _destroyed.append(kind))
	Game.hull_changed.connect(func(h: float, _m: float) -> void: _hull_events.append(h))
	_run.call_deferred()


func _run() -> void:
	await _ticks(3)
	_check(guns != null and weapons.is_in_group(&"weapon_system"), "WREN has a Guns node; WeaponSystem is in group weapon_system")
	await _test_bolt_flight()
	await _test_take_shot()
	await _test_drone()
	await _test_container()
	await _test_other_ship()
	await _test_guns()
	print("weapons_test: %s (%d failure%s)" % ["OK" if _fails == 0 else "FAILED", _fails, "" if _fails == 1 else "s"])
	get_tree().quit(0 if _fails == 0 else 1)


func _test_bolt_flight() -> void:
	var from := Vector2(0, -LANE)
	weapons.fire(from, Vector2.RIGHT, Vector2(0, 300.0), null)
	_check(weapons.live_bolts() == 1 and weapons.shots_fired == 1, "fire() launches one pooled bolt")
	await _secs(0.5)
	var p := weapons.newest_bolt_position()
	var want_x := WeaponSystem.BOLT_SPEED_MPS * Game.PX_PER_M * 0.5
	_check(absf(p.x - want_x) < 60.0, "bolt flies at 260 m/s (%.0f px in 0.5 s, expect %.0f)" % [p.x, want_x])
	_check(absf(p.y - (from.y + 150.0)) < 8.0, "bolt keeps the shooter's velocity (drifted %.0f px, expect 150)" % (p.y - from.y))
	var last := p
	var t := 0.5
	while weapons.live_bolts() > 0 and t < 4.0:
		last = weapons.newest_bolt_position()
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	var range_px := WeaponSystem.BOLT_RANGE_M * Game.PX_PER_M
	_check(weapons.live_bolts() == 0 and last.x > range_px and last.x < range_px * 1.1,
		"bolt expires just past its 500 m range (%.0f m, after %.2f s)" % [last.x / Game.PX_PER_M, t])
	_check(weapons.shots_hit == 0 and _shot_hits.is_empty(), "a miss hits nothing")


func _test_take_shot() -> void:
	# A wall 4 px thick: a bolt covers 21.7 px per tick, so only the swept
	# ray stops it.
	var wall := ShotCatcher.new()
	wall.collision_layer = Game.LAYER_WORLD
	wall.collision_mask = 0
	var cs := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = Vector2(4, 400)
	cs.shape = rs
	wall.add_child(cs)
	wall.position = Vector2(2003, LANE)
	add_child(wall)
	await _ticks(3)
	weapons.fire(Vector2(0, LANE), Vector2.RIGHT, Vector2.ZERO, ship)
	await _secs(1.2)
	_check(wall.calls.size() == 1 and weapons.live_bolts() == 0, "thin wall stops the bolt (take_shot called %d time(s))" % wall.calls.size())
	if wall.calls.size() == 1:
		var c: Array = wall.calls[0]
		_check(is_equal_approx(c[0], WeaponSystem.BOLT_DAMAGE) and is_equal_approx(c[0], 10.0), "take_shot damage = %.1f" % c[0])
		_check((c[1] as Vector2).distance_to(Vector2(2001, LANE)) < 1.5, "take_shot `at` is the hit point %s" % str(c[1]))
		_check((c[2] as Vector2).is_equal_approx(Vector2.RIGHT), "take_shot `dir` is the bolt direction")
		_check(c[3] == ship, "take_shot `shooter` is the ship")
	_check(_shot_hits.size() == 1 and _shot_hits[0][2] == wall and _shot_hits[0][3] == ship
		and (_shot_hits[0][1] as Vector2).dot(Vector2.LEFT) > 0.99, "Game.shot_hit(pos, normal, collider, shooter) emitted with the surface normal")
	wall.queue_free()
	await _ticks(2)


func _test_drone() -> void:
	var drone := TargetDrone.new()
	drone.home = Vector2(1500, LANE * 2.0)
	drone.sway_m = Vector2.ZERO
	drone.respawn_s = 1.0
	add_child(drone)
	var shot_log: Array = []
	drone.shot.connect(func(_d: TargetDrone, destroyed: bool) -> void: shot_log.append(destroyed))
	await _ticks(4)
	_check(drone.is_in_group(&"target_drone") and drone.is_in_group(&"radar_prop")
		and (drone.collision_layer & WeaponSystem.HIT_MASK) != 0, "drone is in groups target_drone + radar_prop, on a layer bolts hit")
	var from := Vector2(0, LANE * 2.0)
	weapons.fire(from, Vector2.RIGHT, Vector2.ZERO, ship)
	await _secs(0.7)
	_check(drone.alive and is_equal_approx(drone.health, 10.0) and shot_log == [false], "first hit: staggered, still alive (health %.0f)" % drone.health)
	_check(drone.linear_velocity.length() > 5.0 or drone.global_position.distance_to(drone.home) > 2.0, "first hit rocks it on its spring")
	_check(_destroyed.is_empty(), "no target_destroyed yet")
	weapons.fire(from, Vector2.RIGHT, Vector2.ZERO, ship)
	await _secs(0.7)
	_check(not drone.alive and shot_log == [false, true], "second hit bursts it")
	_check(_destroyed == ["drone"], "Game.target_destroyed(\"drone\") emitted once")
	_check(drone.collision_layer == 0 and not drone.is_in_group(&"radar_prop"), "a dead drone is out of the world and off the radar")
	weapons.fire(from, Vector2.RIGHT, Vector2.ZERO, ship)
	await _secs(0.4)
	_check(shot_log.size() == 2, "bolts pass through where it was")
	await _secs(1.2)
	_check(drone.alive and is_equal_approx(drone.health, drone.max_health) and drone.collision_layer == Game.LAYER_PROPS
		and drone.global_position.distance_to(drone.home) < 20.0, "it respawns on station with full health")
	drone.queue_free()
	await _ticks(2)


func _test_container() -> void:
	var box: RigidBody2D = CARGO.new()
	box.position = Vector2(1500, LANE * 3.0)
	add_child(box)
	await _ticks(4)
	weapons.fire(Vector2(0, LANE * 3.0), Vector2.RIGHT, Vector2.ZERO, ship)
	await _secs(0.7)
	var v := box.linear_velocity.x / Game.PX_PER_M
	var want := WeaponSystem.PROP_IMPULSE_NS / box.mass
	_check(absf(v - want) < want * 0.25 and absf(box.linear_velocity.y) < 2.0,
		"container (%.0f kg) nudged along the bolt: %.2f m/s (expect %.2f)" % [box.mass, v, want])
	box.queue_free()
	await _ticks(2)


func _test_other_ship() -> void:
	var other := SHIP.instantiate() as PlayerShip
	other.start_as_player = false
	other.position = Vector2(1500, LANE * 4.0)
	add_child(other)
	other.park()
	await _ticks(4)
	_check(Game.player == ship, "the second ship is parked, not flown")
	weapons.fire(Vector2(0, LANE * 4.0), Vector2.RIGHT, Vector2.ZERO, ship)
	await _secs(0.7)
	_check(is_equal_approx(other.hull, other.max_hull - WeaponSystem.SHIP_SCRATCH), "a parked ship takes a %.1f hp scratch (hull %.1f)" % [WeaponSystem.SHIP_SCRATCH, other.hull])
	_check(_hull_events.is_empty() and is_equal_approx(ship.hull, ship.max_hull), "... without touching Game.hull_changed (that is your ship's hull)")
	# Stray fire must not be able to destroy a parked ship.
	other.hull = other.max_hull * WeaponSystem.SCRATCH_FLOOR + 1.0
	weapons.fire(Vector2(0, LANE * 4.0), Vector2.RIGHT, Vector2.ZERO, ship)
	await _secs(0.7)
	_check(is_equal_approx(other.hull, other.max_hull * WeaponSystem.SCRATCH_FLOOR + 1.0) and other.alive, "scratches stop at %d %% hull" % int(WeaponSystem.SCRATCH_FLOOR * 100.0))
	other.queue_free()
	await _ticks(2)


func _test_guns() -> void:
	var before := weapons.shots_fired
	# Controls off: the trigger is dead.
	ship.controls_enabled = false
	Input.action_press(&"ship_fire")
	await _secs(0.5)
	_check(guns.shots == 0, "guns are safe while the controls are off")
	# A key held when you take control stays latched until it is released.
	ship._latch_held_actions()
	ship.controls_enabled = true
	await _secs(0.5)
	_check(guns.shots == 0, "a trigger held while boarding does not fire")
	Input.action_release(&"ship_fire")
	await _ticks(2)
	Input.action_press(&"ship_fire")
	await _secs(1.0)
	_check(guns.shots >= 6 and guns.shots <= 7 and weapons.shots_fired - before == guns.shots, "holding ship_fire: %d shots in 1 s (6 /s)" % guns.shots)
	_check(guns.heat > 0.2 and not guns.overheated, "heat builds (%.0f %%)" % (guns.heat * 100.0))
	_check(ship.linear_velocity.length() < 0.01, "no recoil on the ship")
	var t := 1.0
	while not guns.overheated and t < 6.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	var at_lock := guns.shots
	_check(guns.overheated and guns.heat > 0.98 and at_lock == 23, "overheats after %d shots, %.1f s of fire" % [at_lock, t])
	await _secs(1.0)
	_check(guns.shots == at_lock and guns.overheated, "locked out: the held trigger does nothing")
	t = 0.0
	while guns.overheated and t < 6.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	_check(not guns.overheated and guns.heat <= guns.ready_below + 0.05, "ready again %.1f s later, at %.0f %% heat" % [t + 1.0, guns.heat * 100.0])
	await _secs(0.4)
	_check(guns.shots > at_lock, "firing resumes while the trigger is still held")
	Input.action_release(&"ship_fire")
	await _secs(2.5)
	_check(guns.heat < 0.01, "heat bleeds off when not firing")
	# Dead ships don't shoot.
	ship.alive = false
	Input.action_press(&"ship_fire")
	var n := guns.shots
	await _secs(0.4)
	_check(guns.shots == n, "a destroyed ship's guns are dead")
	Input.action_release(&"ship_fire")
	await _secs(2.5)        # let the last bolts expire before quitting


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
