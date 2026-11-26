extends Node2D
## Stand-in level for testing the gameplay systems in isolation
## (scenes/test/gameplay_sandbox.tscn). Builds simple walls, a rotating arm,
## containers, a docking pad, five race gates and a spawn marker, following
## the level contract (§3) so every system sees the same structure as in the
## real level.

const WALL_FILL := Color("#C9D2DC")
const WALL_RIM := Color("#7FE6FF")

var _arm: AnimatableBody2D
var _structures: Array[PackedVector2Array] = []

func _ready() -> void:
	Game.level = self
	Game.world_bounds = Rect2(-2400, -1600, 4800, 3200)
	add_to_group(&"radar_structure")
	# Outer walls and blocks.
	_wall([Vector2(-1200, -700), Vector2(1400, -700), Vector2(1400, -600), Vector2(-1200, -600)])
	_wall([Vector2(-1200, 600), Vector2(1400, 600), Vector2(1400, 700), Vector2(-1200, 700)])
	_wall([Vector2(300, -250), Vector2(520, -250), Vector2(520, 250), Vector2(300, 250)])
	_wall([Vector2(-700, 150), Vector2(-450, 100), Vector2(-420, 300), Vector2(-680, 340)])
	_wall([Vector2(1500, -300), Vector2(1700, -200), Vector2(1700, 250), Vector2(1500, 300)])
	_rotating_arm(Vector2(1000, 0))
	for i in 6:
		_container(Vector2(-200 + (i % 3) * 70, -350 + floori(i / 3.0) * 60))
	_pad(Vector2(-950, 0))
	var spawn := Marker2D.new()
	spawn.name = "PlayerSpawn"
	spawn.position = Vector2(-950, 0)
	spawn.add_to_group(&"player_spawn")
	add_child(spawn)
	var course := Node2D.new()
	course.name = "RaceCourse"
	add_child(course)
	var gates := [[Vector2(-700, -300), 0.0], [Vector2(0, -450), 0.0], [Vector2(800, -400), 30.0],
		[Vector2(1250, 420), 160.0], [Vector2(0, 450), 180.0], [Vector2(-1000, 300), 200.0]]
	for i in gates.size():
		var m := Marker2D.new()
		m.name = "Gate%02d" % (i + 1)
		m.position = gates[i][0]
		m.rotation_degrees = gates[i][1]
		m.set_meta(&"width_m", 22.0)
		course.add_child(m)

func get_radar_polygons() -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for p in _structures:
		out.append(global_transform * p)
	if _arm:
		out.append(_arm.global_transform * PackedVector2Array([Vector2(-20, -260), Vector2(20, -260), Vector2(20, 260), Vector2(-20, 260)]))
	return out

func _wall(pts_in: Array) -> void:
	var pts := PackedVector2Array(pts_in)
	var body := StaticBody2D.new()
	body.collision_layer = Game.LAYER_WORLD
	body.collision_mask = 0
	body.z_as_relative = false
	body.z_index = Game.Z_STRUCTURE
	var cp := CollisionPolygon2D.new()
	cp.polygon = pts
	body.add_child(cp)
	_visual(body, pts)
	add_child(body)
	_structures.append(pts)

func _visual(parent: Node, pts: PackedVector2Array) -> void:
	var poly := Polygon2D.new()
	poly.polygon = pts
	poly.color = WALL_FILL
	parent.add_child(poly)
	var rim := Line2D.new()
	rim.points = pts + PackedVector2Array([pts[0]])
	rim.width = 3.0
	rim.default_color = WALL_RIM
	rim.antialiased = true
	parent.add_child(rim)

func _rotating_arm(c: Vector2) -> void:
	_arm = AnimatableBody2D.new()
	_arm.sync_to_physics = true
	_arm.collision_layer = Game.LAYER_WORLD
	_arm.collision_mask = 0
	_arm.position = c
	_arm.z_as_relative = false
	_arm.z_index = Game.Z_STRUCTURE
	var pts := PackedVector2Array([Vector2(-20, -260), Vector2(20, -260), Vector2(20, 260), Vector2(-20, 260)])
	var cp := CollisionPolygon2D.new()
	cp.polygon = pts
	_arm.add_child(cp)
	_visual(_arm, pts)
	add_child(_arm)

func _physics_process(delta: float) -> void:
	if _arm:
		_arm.rotation += 0.25 * delta

func _container(p: Vector2) -> void:
	var b := RigidBody2D.new()
	b.position = p
	b.mass = 400.0
	b.collision_layer = Game.LAYER_PROPS
	b.collision_mask = Game.LAYER_WORLD | Game.LAYER_PLAYER | Game.LAYER_PROPS | Game.LAYER_TRAFFIC
	b.contact_monitor = true
	b.max_contacts_reported = 4
	b.linear_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	b.angular_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	b.z_as_relative = false
	b.z_index = Game.Z_PROPS
	b.add_to_group(&"radar_prop")
	var pts := PackedVector2Array([Vector2(-25, -12), Vector2(25, -12), Vector2(25, 12), Vector2(-25, 12)])
	var cp := CollisionPolygon2D.new()
	cp.polygon = pts
	b.add_child(cp)
	var poly := Polygon2D.new()
	poly.polygon = pts
	poly.color = Color("#2A9D8F")
	b.add_child(poly)
	b.body_entered.connect(func(other: Node) -> void:
		if other == Game.player:
			return
		var rel := b.linear_velocity - ((other as RigidBody2D).linear_velocity if other is RigidBody2D else Vector2.ZERO)
		var sp := rel.length() / Game.PX_PER_M
		if sp > 0.8:
			Game.impact.emit(b.global_position, rel.normalized(), sp, b, other))
	add_child(b)

func _pad(p: Vector2) -> void:
	var a := Area2D.new()
	a.position = p
	a.collision_layer = Game.LAYER_TRIGGERS
	a.collision_mask = Game.LAYER_PLAYER
	a.add_to_group(&"docking_pad")
	a.set_meta(&"pad_name", "Pad 1")
	a.z_as_relative = false
	a.z_index = Game.Z_BELOW_DECK
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(160, 120)
	cs.shape = r
	a.add_child(cs)
	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([Vector2(-80, -60), Vector2(80, -60), Vector2(80, 60), Vector2(-80, 60)])
	poly.color = Color(1.0, 0.69, 0.0, 0.25)
	a.add_child(poly)
	add_child(a)
