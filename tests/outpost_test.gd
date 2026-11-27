extends Node2D
## Vesper asteroid field (run headless):
##   Godot --headless --path . --fixed-fps 120 res://scenes/test/outpost_test.tscn
## Builds a small field in empty space and checks:
##   seed         -> the same seed plans the same field, and the same rock
##   chip         -> take_shot() takes hit points, cracks the rock, nudges it
##   split        -> at zero it breaks into 2-3 rocks one size down (the count
##                   the seed says), and Game.target_destroyed("asteroid") fires
##   burst        -> the smallest size leaves no rocks behind
##   ore          -> an ore rock leaves an ORE canister (group cargo_container)
##   impacts      -> a rock hitting a wall reports on Game.impact; a rock hit by
##                   the player reports nothing (the player reports those)
##   refill       -> the field tops itself up below 70 %
##   sleep        -> with nobody near, the field is out of the physics space
## Prints PASS / FAIL lines, then `outpost_test: OK`, and exits 0 / 1.

const Field := preload("res://scripts/level/modules/asteroid_field.gd")

var _fails := 0
var _destroyed: Array[String] = []
var _rock_impacts := 0
var _player_impacts := 0


func _ready() -> void:
	Game.target_destroyed.connect(func(kind: String) -> void: _destroyed.append(kind))
	Game.impact.connect(_on_impact)
	_run.call_deferred()


func _on_impact(_pos: Vector2, _n: Vector2, _speed: float, source: Node, other: Node) -> void:
	if source is Asteroid:
		_rock_impacts += 1
		if other == Game.player or (other and other.is_in_group(&"player_ship")):
			_player_impacts += 1


func _check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_fails += 1


func _secs(s: float) -> void:
	var t := 0.0
	while t < s:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()


func _field(at: Vector2, count: int, awake: bool) -> Node2D:
	var f: Node2D = Field.new()
	f.position = at
	f.count = count
	f.seed = 77
	f.extent_m = Vector2(320, 320)
	f.clusters = 2
	f.always_awake = awake
	f.clear_circles_m = [Vector3(0, 0, 60)] as Array[Vector3]
	add_child(f)
	return f


func _rock(at: Vector2, cls: int, rseed: int, ore: bool) -> Asteroid:
	var r := Asteroid.new()
	r.setup(cls, rseed, ore)
	r.position = at
	add_child(r)
	return r


func _loose_rocks() -> Array[Asteroid]:
	var out: Array[Asteroid] = []
	for c in get_children():
		if c is Asteroid and not c.is_queued_for_deletion():
			out.append(c as Asteroid)
	return out


func _run() -> void:
	# ---- seed
	var a := _field(Vector2(40000, 0), 12, true)
	var b := _field(Vector2(40000, 9000), 12, true)
	var pa: Array[Dictionary] = a.plan()
	var pb: Array[Dictionary] = b.plan()
	var same := pa.size() == pb.size() and pa.size() == 12
	for i in mini(pa.size(), pb.size()):
		same = same and pa[i].home == pb[i].home and pa[i].cls == pb[i].cls and pa[i].ore == pb[i].ore
	_check(same, "same seed plans the same %d rocks" % pa.size())
	var ra: Array[Asteroid] = a.rocks()
	var rb: Array[Asteroid] = b.rocks()
	_check(ra.size() == 12 and ra[0].outline == rb[0].outline and ra[5].outline == rb[5].outline, "same seed builds the same rock outlines")
	var clear := true
	for d in pa:
		clear = clear and (d.home as Vector2).length() > 60.0
	_check(clear, "no rock planted in the keep-clear circle")
	b.queue_free()
	await _secs(0.2)

	# ---- chip
	var rock := _rock(Vector2(0, 0), 1, 4242, false)
	await _secs(0.1)
	var hp0 := rock.hp
	rock.take_shot(30.0, rock.global_position + Vector2(-30, 0), Vector2.RIGHT, null)
	await _secs(0.1)
	_check(is_instance_valid(rock) and is_equal_approx(rock.hp, hp0 - 30.0), "a 30 point shot leaves %.0f of %.0f hit points" % [rock.hp, hp0])
	_check(rock._crack_count == 1, "the hit cracked the rock")
	_check(rock.linear_velocity.x > 0.5 and rock.linear_velocity.x < 30.0, "and nudged it (%.2f m/s)" % (rock.linear_velocity.x / 10.0))

	# ---- split: the fragment count is what the rock's seed says
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242 * 7919 + 13
	var want := 2 + (rng.randi() % 2)
	rock.take_shot(30.0, rock.global_position, Vector2.RIGHT, null)
	rock.take_shot(40.0, rock.global_position, Vector2.RIGHT, null)
	await _secs(0.2)
	var frags := _loose_rocks()
	var small := true
	for f in frags:
		small = small and f.size_class == 0
	_check(not is_instance_valid(rock), "at zero hit points the rock is gone")
	_check(frags.size() == want and small, "it broke into %d small rocks (seed says %d)" % [frags.size(), want])
	_check(_destroyed == ["asteroid"], "Game.target_destroyed(\"asteroid\") fired once")
	await _secs(1.0)
	var apart := frags.size() > 1 and frags[0].global_position.distance_to(frags[1].global_position) > 30.0
	_check(apart, "the fragments fly apart")

	# ---- burst: the smallest size just goes
	for f in frags:
		f.take_shot(1000.0, f.global_position, Vector2.DOWN, null)
	await _secs(0.2)
	_check(_loose_rocks().is_empty(), "small rocks burst into dust, nothing left")
	_check(_destroyed.size() == 1 + want, "one target_destroyed per rock (%d)" % _destroyed.size())
	_check(get_tree().get_nodes_in_group(&"cargo_container").is_empty(), "plain rock leaves no canister")

	# ---- ore
	var ore_rock := _rock(Vector2(3000, 0), 2, 99, true)
	await _secs(0.1)
	ore_rock.take_shot(10000.0, ore_rock.global_position, Vector2.RIGHT, null)
	await _secs(0.3)
	var cans := get_tree().get_nodes_in_group(&"cargo_container")
	_check(cans.size() == 1 and cans[0].is_in_group(&"ore_canister") and cans[0].get("brand") == "ORE", "an ore rock leaves one ORE canister in group cargo_container")
	if cans.size() == 1:
		_check((cans[0] as RigidBody2D).mass > 1000.0 and cans[0].get("size_m") == Vector2(6.1, 2.44), "the canister is a small container (%.0f kg)" % (cans[0] as RigidBody2D).mass)
	for f in _loose_rocks():
		f.queue_free()
	for c in cans:
		c.queue_free()
	await _secs(0.2)

	# ---- impacts: rock -> wall reports, player -> rock does not
	var wall := StaticBody2D.new()
	wall.collision_layer = Game.LAYER_WORLD
	var ws := CollisionShape2D.new()
	var wr := RectangleShape2D.new()
	wr.size = Vector2(60, 600)
	ws.shape = wr
	wall.add_child(ws)
	wall.position = Vector2(6400, 0)
	add_child(wall)
	var thrown := _rock(Vector2(6200, 0), 1, 7, false)
	thrown.linear_velocity = Vector2(120, 0)
	var target := _rock(Vector2(6000, 2000), 1, 8, false)
	var player := RigidBody2D.new()
	player.collision_layer = Game.LAYER_PLAYER
	player.collision_mask = Game.LAYER_WORLD | Game.LAYER_PROPS
	player.mass = 1000.0
	var ps := CollisionShape2D.new()
	var pc := CircleShape2D.new()
	pc.radius = 30.0
	ps.shape = pc
	player.add_child(ps)
	player.position = Vector2(5600, 2000)
	player.linear_velocity = Vector2(150, 0)
	player.add_to_group(&"player_ship")
	add_child(player)
	Game.player = player
	var before := _rock_impacts
	await _secs(5.0)
	_check(_rock_impacts > before, "a rock hitting structure reports on Game.impact (%d)" % (_rock_impacts - before))
	_check(player.linear_velocity.x < 100.0, "the player really hit the other rock (now %.1f m/s)" % (player.linear_velocity.x / 10.0))
	_check(_player_impacts == 0, "rocks never report contacts with the player")
	Game.player = null
	for n: Node in [wall, thrown, target, player]:
		n.queue_free()
	await _secs(0.2)

	# ---- refill
	var rocks: Array[Asteroid] = a.rocks()
	for i in 7:
		rocks[i].queue_free()
	await _secs(0.1)
	var low: int = a.rock_count()
	await _secs(8.0)
	var floor_n := int(ceil(12 * 0.7))
	_check(low == 5 and a.rock_count() == floor_n, "field topped up from %d to %d rocks (70 %% of 12 = %d)" % [low, a.rock_count(), floor_n])

	# ---- sleep
	var far := _field(Vector2(-400000, 0), 6, false)
	await _secs(0.5)
	var fr: Array[Asteroid] = far.rocks()
	var p0 := fr[0].global_position
	await _secs(1.0)
	_check(not far.active and fr.size() == 6 and fr[0].global_position == p0, "with nobody near, the field sleeps (rocks out of the simulation)")
	_check(a.active, "an always_awake field stays up")

	print("outpost_test: %s" % ("OK" if _fails == 0 else "FAILED (%d)" % _fails))
	# Rock glints use LevelArt's shared glow texture and blink material.
	LevelArt.cleanup()
	get_tree().quit(0 if _fails == 0 else 1)
