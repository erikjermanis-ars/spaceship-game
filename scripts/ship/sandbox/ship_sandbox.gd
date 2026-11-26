extends Node2D
## Flight/collision test room for the player ship: a walled arena with straight
## and angled walls, a gap to thread, pillars, a slowly rotating bar
## (AnimatableBody2D) and loose cargo crates (RigidBody2D).
## Prints every impact so collision reporting can be checked from the console.
## Supports the Game harness args (--spawn, --input, --shots, --debug-draw ...).

const PX := 10.0
const C_WALL := Color("#C9D2DC")
const C_WALL_DARK := Color("#8E9AA8")
const C_RIM := Color("#7FE6FF")
const C_NAVY := Color("#1D3557")
const C_AMBER := Color("#FFB000")

@export var print_impacts := true

var _bar: AnimatableBody2D
var _ship: PlayerShip


func _ready() -> void:
	_build_backdrop()
	# Arena walls (100 m x 80 m inner box... generous).
	_wall(Vector2(0, -1540), Vector2(4160, 80), 0.0)
	_wall(Vector2(0, 1540), Vector2(4160, 80), 0.0)
	_wall(Vector2(-2040, 0), Vector2(80, 3000), 0.0)
	_wall(Vector2(2040, 0), Vector2(80, 3000), 0.0)
	# Obstacles.
	_wall(Vector2(1100, 0), Vector2(60, 800), 0.0)                  # head-on wall
	_wall(Vector2(500, -750), Vector2(700, 50), deg_to_rad(-25))     # angled
	_wall(Vector2(-700, 650), Vector2(800, 50), deg_to_rad(38))      # angled
	_wall(Vector2(-1100, -880), Vector2(60, 1240), 0.0)             # gap: upper post
	_wall(Vector2(-1100, 745), Vector2(60, 1510), 0.0)              # gap: lower post (25 m gap)
	_pillar(Vector2(-450, -420), 70.0)
	_pillar(Vector2(-250, 280), 50.0)
	_pillar(Vector2(1500, -700), 90.0)
	_bar = _rotating_bar(Vector2(400, 820), Vector2(700, 40))
	for i in 7:
		_crate(Vector2(520 + (i % 4) * 70, 260 + (i / 4) * 60), randf() * 0.4)
	# Ship + camera + tuning panel.
	_ship = (load("res://scenes/ship/player_ship.tscn") as PackedScene).instantiate()
	add_child(_ship)
	_ship.global_transform = _spawn_xform()
	if Game.cmd.has("hull"):
		_ship.take_damage.call_deferred(_ship.max_hull - float(Game.cmd["hull"]))
	# Use GAMEPLAY's impact sparks/sounds if they exist; otherwise let the
	# camera shake on impacts by itself.
	var fx_path := "res://scripts/systems/impact_fx.gd"
	var has_fx := ResourceLoader.exists(fx_path) and not Game.cmd.has("no-fx")
	if has_fx:
		var fx := Node2D.new()
		fx.name = "ImpactFX"
		fx.set_script(load(fx_path))
		add_child(fx)
	var cam := (load("res://scenes/ship/camera_rig.tscn") as PackedScene).instantiate()
	cam.set(&"auto_impact_shake", not has_fx)
	add_child(cam)
	if ResourceLoader.exists("res://scenes/ui/tuning_panel.tscn"):
		add_child((load("res://scenes/ui/tuning_panel.tscn") as PackedScene).instantiate())
	Game.world_bounds = Rect2(-2000, -1500, 4000, 3000)
	Game.impact.connect(_on_impact)
	Game.scrape.connect(_on_scrape)
	Game.toast("Ship sandbox — WASD/arrows fly, Q/E strafe, Shift/Ctrl throttle, F assist, F3 debug, Tab tuning, T respawn", 6.0)


func _spawn_xform() -> Transform2D:
	if Game.cmd.has("spawn"):
		var p := String(Game.cmd["spawn"]).split(",")
		if p.size() >= 2:
			var heading := deg_to_rad(float(p[2])) if p.size() >= 3 else 0.0
			return Transform2D(heading, Vector2(float(p[0]), float(p[1])))
	return Transform2D(0.0, Vector2(-300, 0))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"respawn") and _ship:
		_ship.respawn_at(_spawn_xform())


func _physics_process(delta: float) -> void:
	if _bar:
		_bar.rotation += 0.35 * delta


var _last_scrape_print := -1.0


func _on_scrape(pos: Vector2, _normal: Vector2, tangent: float, _source: Node) -> void:
	if print_impacts and Game.sim_time() - _last_scrape_print > 0.25:
		_last_scrape_print = Game.sim_time()
		print("[scrape t=%.2f] tangent=%.2f m/s pos=(%.0f, %.0f)" % [Game.sim_time(), tangent, pos.x, pos.y])


func _on_impact(pos: Vector2, normal: Vector2, speed: float, source: Node, other: Node) -> void:
	if print_impacts:
		print("[impact t=%.2f] speed=%.2f m/s pos=(%.0f, %.0f) n=(%.2f, %.2f) src=%s other=%s" % [
			Game.sim_time(), speed, pos.x, pos.y, normal.x, normal.y,
			source.name if source else "-", other.name if other else "-"])


# ------------------------------------------------------------ builders --
func _poly_rect(size: Vector2) -> PackedVector2Array:
	var h := size * 0.5
	return PackedVector2Array([Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y)])


func _decorate(body: Node2D, pts: PackedVector2Array, fill: Color, rim: Color) -> void:
	var poly := Polygon2D.new()
	poly.polygon = pts
	poly.color = fill
	body.add_child(poly)
	var line := Line2D.new()
	var closed := pts.duplicate()
	closed.append(pts[0])
	line.points = closed
	line.width = 3.0
	line.default_color = rim
	line.antialiased = true
	body.add_child(line)


func _wall(center: Vector2, size: Vector2, rot: float) -> StaticBody2D:
	var b := StaticBody2D.new()
	b.name = "Wall"
	b.position = center
	b.rotation = rot
	b.collision_layer = Game.LAYER_WORLD
	b.collision_mask = 0
	var pts := _poly_rect(size)
	var cs := CollisionPolygon2D.new()
	cs.polygon = pts
	b.add_child(cs)
	_decorate(b, pts, C_WALL, C_RIM)
	# Navy panel stripe down the long axis so rotation/scale read clearly.
	var stripe := Polygon2D.new()
	var s := Vector2(size.x * 0.9, minf(size.y * 0.25, 10.0)) if size.x > size.y else Vector2(minf(size.x * 0.25, 10.0), size.y * 0.9)
	stripe.polygon = _poly_rect(s)
	stripe.color = C_NAVY
	b.add_child(stripe)
	b.z_index = Game.Z_STRUCTURE
	add_child(b)
	return b


func _pillar(center: Vector2, radius: float) -> void:
	var b := StaticBody2D.new()
	b.name = "Pillar"
	b.position = center
	b.collision_layer = Game.LAYER_WORLD
	var pts := PackedVector2Array()
	for i in 12:
		pts.append(Vector2.from_angle(TAU * i / 12.0) * radius)
	var cs := CollisionPolygon2D.new()
	cs.polygon = pts
	b.add_child(cs)
	_decorate(b, pts, C_WALL_DARK, C_RIM)
	b.z_index = Game.Z_STRUCTURE
	add_child(b)


func _rotating_bar(center: Vector2, size: Vector2) -> AnimatableBody2D:
	var b := AnimatableBody2D.new()
	b.name = "RotatingBar"
	b.position = center
	b.sync_to_physics = true
	b.collision_layer = Game.LAYER_WORLD
	var pts := _poly_rect(size)
	var cs := CollisionPolygon2D.new()
	cs.polygon = pts
	b.add_child(cs)
	_decorate(b, pts, C_WALL, C_AMBER)
	var hub := Polygon2D.new()
	var hp := PackedVector2Array()
	for i in 16:
		hp.append(Vector2.from_angle(TAU * i / 16.0) * 34.0)
	hub.polygon = hp
	hub.color = C_NAVY
	b.add_child(hub)
	b.z_index = Game.Z_STRUCTURE
	add_child(b)
	return b


func _crate(pos: Vector2, rot: float) -> void:
	var b := RigidBody2D.new()
	b.name = "Crate"
	b.position = pos
	b.rotation = rot
	b.mass = 400.0
	b.gravity_scale = 0.0
	b.linear_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	b.angular_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	b.linear_damp = 0.05
	b.angular_damp = 0.1
	b.collision_layer = Game.LAYER_PROPS
	b.collision_mask = Game.LAYER_WORLD | Game.LAYER_PLAYER | Game.LAYER_PROPS | Game.LAYER_TRAFFIC
	b.continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	var mat := PhysicsMaterial.new()
	mat.bounce = 0.3
	mat.friction = 0.4
	b.physics_material_override = mat
	var pts := _poly_rect(Vector2(40, 26))
	var cs := CollisionPolygon2D.new()
	cs.polygon = pts
	b.add_child(cs)
	_decorate(b, pts, Color("#2A9D8F"), Color("#E9EEF3"))
	var band := Polygon2D.new()
	band.polygon = _poly_rect(Vector2(8, 26))
	band.color = C_AMBER
	b.add_child(band)
	b.z_index = Game.Z_PROPS
	add_child(b)


## Motion reference: a faint dot grid plus a few big soft "nebula" blobs.
func _build_backdrop() -> void:
	var env_path := "res://scenes/environment/space_background.tscn"
	if ResourceLoader.exists(env_path) and not Game.cmd.has("no-env"):
		var ps := load(env_path) as PackedScene
		if ps:
			add_child(ps.instantiate())
	var grid := _DotGrid.new()
	grid.z_index = Game.Z_BELOW_DECK - 1
	add_child(grid)


class _DotGrid extends Node2D:
	func _draw() -> void:
		var c := Color(0.5, 0.65, 0.85, 0.35)
		for x in range(-2000, 2001, 100):
			for y in range(-1500, 1501, 100):
				var big := (x % 500 == 0) and (y % 500 == 0)
				draw_circle(Vector2(x, y), 3.0 if big else 1.5, c if not big else Color(0.6, 0.85, 1.0, 0.6))
