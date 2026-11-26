extends Node2D
## Automated sanity checks for Meridian Station (run headless):
##   Godot --headless --path . res://scenes/test/level_validate.tscn
## Checks the scene contract (spawn, gates, pads, radar), that gates and the
## spawn are not blocked by colliding geometry, that traffic lanes are clear of
## static structure, and that cargo containers report prop impacts.

const G := preload("res://scripts/autoload/game.gd")

var _frames := 0
var _impacts := 0
var _player_impacts := 0
var _fails := 0
var _sim := 0.0


func _ready() -> void:
	var game := get_node(^"/root/Game")
	game.impact.connect(_on_impact)


func _on_impact(_pos: Vector2, _n: Vector2, speed: float, source: Node, other: Node) -> void:
	if source and source.is_in_group(&"cargo_container"):
		_impacts += 1
		if other and other.is_in_group(&"player_ship"):
			_player_impacts += 1
		if _impacts <= 5:
			print("  impact: %s -> %s at %.1f m/s" % [source.name, other.name if other else "null", speed])


func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		_fails += 1


func _physics_process(delta: float) -> void:
	_frames += 1
	_sim += delta
	if _frames == 3:
		_static_checks()
		_spawn_collision_pair()
	if _sim >= 30.0:
		print("[props] container impacts in 30 s: %d (with player: %d)" % [_impacts, _player_impacts])
		_check(_impacts > 0, "containers emit Game.impact for prop contacts")
		_check(_player_impacts == 0, "containers never report player contacts")
		print("RESULT: %s (%d failures)" % ["OK" if _fails == 0 else "FAILED", _fails])
		get_tree().quit(1 if _fails > 0 else 0)


## Two containers on a head-on course in empty space (deterministic impact).
func _spawn_collision_pair() -> void:
	var CargoBox := preload("res://scripts/level/cargo_box.gd")
	for i in 2:
		var b: RigidBody2D = CargoBox.new()
		b.setup(Vector2(6.1, 2.44), Color("4EA8DE"), "TEST", "TEST %d" % i)
		b.name = "TestBox%d" % i
		b.position = Vector2(-9000.0 + 400.0 * i, 8200.0)
		b.linear_velocity = Vector2(30.0 if i == 0 else -30.0, 0.0)
		add_child(b)


func _static_checks() -> void:
	var game := get_node(^"/root/Game")
	var level: Node2D = $Level
	print("[contract]")
	_check(game.level == level, "Game.level is the Level root")
	_check(game.world_bounds.size.x > 20000.0, "world bounds set: %s" % str(game.world_bounds))
	var spawn := level.get_node_or_null(^"PlayerSpawn") as Marker2D
	_check(spawn != null and spawn.is_in_group(&"player_spawn"), "PlayerSpawn marker in group player_spawn")
	var course := level.get_node_or_null(^"RaceCourse")
	_check(course != null and course.get_child_count() >= 12, "RaceCourse has %d gates" % (course.get_child_count() if course else 0))
	var pads := get_tree().get_nodes_in_group(&"docking_pad")
	var names: Array[String] = []
	for p in pads:
		names.append(String(p.get_meta("pad_name", "?")))
		_check(p is Area2D and p.collision_layer == G.LAYER_TRIGGERS and p.collision_mask == G.LAYER_PLAYER, "pad %s is a trigger Area2D" % p.get_meta("pad_name", "?"))
	print("  pads: ", names)
	var nstruct := 0
	var npoly := 0
	for s in get_tree().get_nodes_in_group(&"radar_structure"):
		nstruct += 1
		npoly += s.get_radar_polygons().size()
	_check(nstruct > 10 and npoly > 20, "radar_structure: %d nodes, %d polygons" % [nstruct, npoly])
	_check(get_tree().get_nodes_in_group(&"radar_traffic").size() >= 8, "radar_traffic: %d" % get_tree().get_nodes_in_group(&"radar_traffic").size())
	_check(get_tree().get_nodes_in_group(&"radar_prop").size() >= 30, "radar_prop: %d" % get_tree().get_nodes_in_group(&"radar_prop").size())

	var space := get_world_2d().direct_space_state
	print("[clearance]")
	# spawn: ship-sized box must be free
	var box := RectangleShape2D.new()
	box.size = Vector2(12, 6) * 10.0
	_check(_hits(space, box, spawn.global_transform, G.LAYER_WORLD | G.LAYER_PROPS | G.LAYER_TRAFFIC) == 0, "spawn is clear")
	# gates: the central 80 % of each span must be free of WORLD geometry
	for g in course.get_children():
		var mk := g as Marker2D
		var w: float = mk.get_meta("width_m", 40.0)
		var probe := RectangleShape2D.new()
		probe.size = Vector2(6.0, w * 0.8) * 10.0
		var n := _hits(space, probe, mk.global_transform, G.LAYER_WORLD)
		_check(n == 0, "%s (%.0f m) clear" % [mk.name, w])
	# traffic lanes vs static structure
	for lane in level.get_node(^"Lanes").get_children():
		var worst := 0
		var circle := CircleShape2D.new()
		circle.radius = 60.0
		var d := 0.0
		while d < lane.total:
			var xf: Transform2D = lane.sample_transform(d)
			worst += _hits(space, circle, xf, G.LAYER_WORLD, [lane.body.get_rid()] if lane.body else [])
			d += 50.0
		_check(worst == 0, "lane %s clear of structure (%d blocked samples)" % [lane.name, worst])


func _hits(space: PhysicsDirectSpaceState2D, shape: Shape2D, xf: Transform2D, mask: int, exclude: Array = []) -> int:
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	q.transform = xf
	q.collision_mask = mask
	q.exclude = exclude
	q.collide_with_areas = false
	var res := space.intersect_shape(q, 8)
	for r in res:
		var c: Object = r.collider
		print("      blocked by ", (c as Node).get_path() if c is Node else c)
	return res.size()
