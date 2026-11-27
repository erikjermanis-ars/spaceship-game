extends Node2D
## Automated sanity checks for Meridian Station (run headless):
##   Godot --headless --path . res://scenes/test/level_validate.tscn
## Checks the scene contract (spawn, gates, pads, radar), that gates and the
## spawn are not blocked by colliding geometry, that traffic lanes are clear of
## static structure, and that cargo containers report prop impacts.
## Vesper Rock (the Outpost subtree, 9 km east) has its own section: berth V1
## and its approach, the pads, the apron deck, the asteroid field.

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
		_outpost_checks()
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


## Vesper Rock. Lengths in metres; `PX` converts.
func _outpost_checks() -> void:
	const PX := 10.0
	print("[outpost]")
	var outpost := $Level.get_node_or_null(^"Outpost") as Node2D
	_check(outpost != null, "Outpost node in the level")
	if outpost == null:
		return
	var space := get_world_2d().direct_space_state
	var solid := G.LAYER_WORLD | G.LAYER_PROPS | G.LAYER_TRAFFIC
	# --- everything solid stays inside Vesper's sector (+-800 x +-650 m)
	var sector := Rect2(outpost.global_position - Vector2(800, 650) * PX, Vector2(1600, 1300) * PX)
	var inside := true
	for s in get_tree().get_nodes_in_group(&"radar_structure"):
		if outpost.is_ancestor_of(s):
			for poly: PackedVector2Array in s.get_radar_polygons():
				for p in poly:
					inside = inside and sector.has_point(p)
	_check(inside, "outpost structure is inside its sector")
	# --- berth V1: the ship's place and the approach lane are free
	var berth: Node2D = null
	for b in get_tree().get_nodes_in_group(&"frigate_berth"):
		if b.get("berth_id") == "V1" and outpost.is_ancestor_of(b):
			berth = b
	_check(berth != null, "Berth V1 exists under Outpost")
	var field := outpost.get_node_or_null(^"Field")
	if berth != null:
		var side: float = berth.get("pier_side")
		# Frigates drop out of their jump 560 m astern of the berth (Vesper
		# (-560, 0) m, heading +X) and fly straight in. Open side: a 90 m
		# strip along the axis from beyond the arrival point to 350 m ahead
		# of the berth (the pylons are all on the pier side).
		var strip := RectangleShape2D.new()
		strip.size = Vector2(1162, 90) * PX
		_check(_hits(space, strip, berth.global_transform * Transform2D(0.0, Vector2(-119, -45.0 * side) * PX), solid) == 0, "berth V1: nothing within 90 m of the axis on the ship's side")
		# the hull's place, pier side (152 m long, 44.4 m half-beam): only
		# the berth's own pylons reach in
		var slot := RectangleShape2D.new()
		slot.size = Vector2(156, 45) * PX
		_check(_hits(space, slot, berth.global_transform * Transform2D(0.0, Vector2(8, 22.5 * side) * PX), solid, [berth.body.get_rid()]) == 0, "berth V1: the hull's place is free")
		# the lane at full width, outward from the ends of the pier
		var lane_in := RectangleShape2D.new()
		lane_in.size = Vector2(588, 180) * PX
		var lane_out := RectangleShape2D.new()
		lane_out.size = Vector2(350, 180) * PX
		var astern := _hits(space, lane_in, berth.global_transform * Transform2D(0.0, Vector2(-406, 0) * PX), solid)
		var ahead := _hits(space, lane_out, berth.global_transform * Transform2D(0.0, Vector2(287, 0) * PX), solid)
		_check(astern == 0, "berth V1: straight lane from the jump arrival point (560 m astern, west) is clear")
		_check(ahead == 0, "berth V1: 350 m straight lane ahead (east) is clear")
		_check(berth.global_position.is_equal_approx(outpost.global_position) and absf(berth.global_rotation) < 0.001, "berth V1: capture position is Vesper's origin, bow east")
		# the field sleeps in this scene, so check its rocks by position
		var in_lane := 0
		if field != null:
			for r: Asteroid in field.rocks():
				var q: Vector2 = berth.to_local(r.global_position) / PX
				if absf(q.y) < 90.0 + r.radius_m() and q.x > -700.0 and q.x < 462.0:
					in_lane += 1
		_check(in_lane == 0, "berth V1: no asteroid starts in the lane")
	# --- pads and apron
	var apron_slot := outpost.to_global(Vector2(12, 330) * PX)
	for pad_name: String in ["Vesper 1", "Vesper 2"]:
		var pad: Area2D = null
		for p in get_tree().get_nodes_in_group(&"docking_pad"):
			if p.get_meta("pad_name", "") == pad_name and outpost.is_ancestor_of(p):
				pad = p
		var on_deck := false
		if pad != null:
			for e in LevelArt.walk_decks:
				if e.module.name == &"VesperApron" and Geometry2D.is_point_in_polygon(pad.global_position, e.poly):
					on_deck = true
		_check(pad != null and on_deck, "pad %s exists and stands on the apron deck" % pad_name)
	var slot_on_deck := false
	for e in LevelArt.walk_decks:
		if outpost.is_ancestor_of(e.module) and Geometry2D.is_point_in_polygon(apron_slot, e.poly):
			slot_on_deck = true
	var patch := RectangleShape2D.new()
	patch.size = Vector2(30, 20) * PX
	_check(slot_on_deck and _hits(space, patch, Transform2D(0.0, apron_slot), solid) == 0, "apron is a registered deck with the 30 x 20 m freight slot free")
	# --- asteroid field
	_check(field != null, "asteroid field exists")
	if field == null:
		return
	var plan: Array[Dictionary] = field.plan()
	var again: Array[Dictionary] = field.plan()
	var rocks: Array[Asteroid] = field.rocks()
	var same: bool = plan.size() == again.size() and plan.size() == rocks.size() and plan.size() == int(field.count)
	for i in mini(plan.size(), rocks.size()):
		same = same and plan[i].home == again[i].home and plan[i].cls == again[i].cls
		same = same and rocks[i].size_class == int(plan[i].cls) and rocks[i].home.distance_to(field.to_global((plan[i].home as Vector2) * PX)) < 0.5
	_check(same, "field: %d rocks, seeded (plan is repeatable and the rocks match it)" % rocks.size())
	var buried := 0
	var ore := 0
	for r in rocks:
		ore += 1 if r.ore else 0
		var probe := CircleShape2D.new()
		probe.radius = (r.radius_m() + 2.0) * PX
		buried += _hits(space, probe, Transform2D(0.0, r.global_position), G.LAYER_WORLD)
		if not sector.has_point(r.global_position):
			buried += 1
	_check(buried == 0, "field: no rock starts inside structure or outside the sector")
	_check(ore >= 5 and ore <= rocks.size() / 2, "field: %d of %d rocks are ore-bearing" % [ore, rocks.size()])
	_check(rocks[0].has_method(&"take_shot") and rocks[0].is_in_group(&"asteroid") and rocks[0].is_in_group(&"radar_prop"), "rocks are shootable radar props")


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
