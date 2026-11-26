extends Node2D
## Main scene: assembles the playable sandbox (contract §3).
##
##   Main
##     SpaceBackground  Level  PlayerShip  CameraRig
##     Systems (ImpactFX, DamageSystem, RaceSystem, DockingSystem,
##              BoundarySystem, AmbientAudio, FlightGuide)
##     HUD  TuningPanel
##
## main.tscn instances every piece statically (so the editor shows the whole
## game). This script still copes with pieces that are missing: anything not
## present as a child is instanced at runtime if its scene file exists, and
## a stand-in ship / basic follow camera are provided, so the game always
## boots. `level_scene` lets test scenes (gameplay_sandbox.tscn) swap the
## level while reusing everything else.

const BG_SCENE := "res://scenes/environment/space_background.tscn"
const SHIP_SCENE := "res://scenes/ship/player_ship.tscn"
const CAMERA_SCENE := "res://scenes/ship/camera_rig.tscn"
const TUNING_SCENE := "res://scenes/ui/tuning_panel.tscn"
const STANDIN_SHIP := "res://scripts/systems/sandbox/standin_ship.gd"

@export_file("*.tscn") var level_scene := "res://scenes/level/level.tscn"

var _missing: PackedStringArray = []

func _ready() -> void:
	_swap_level_if_overridden()
	var bg := _ensure(&"SpaceBackground", BG_SCENE, 0)
	var level := _ensure(&"Level", level_scene, 1 if bg else 0)
	if level == null:
		Game.world_bounds = Rect2(-4000, -3000, 8000, 6000)

	var spawn := _spawn_transform()
	GameplayUtil.start_transform = spawn
	GameplayUtil.has_start_transform = true

	var ship := get_node_or_null(^"PlayerShip") as RigidBody2D
	if ship == null:
		ship = _instance(SHIP_SCENE) as RigidBody2D
		if ship == null:
			_missing.append("player_ship.tscn (using stand-in ship)")
			ship = RigidBody2D.new()
			ship.set_script(load(STANDIN_SHIP))
		ship.name = &"PlayerShip"
		ship.transform = spawn      # before entering the tree: no physics jump
		add_child(ship)
		move_child(ship, _index_after(level if level else bg))
	else:
		# Re-enter the tree at the spawn point. Setting global_transform on a
		# live CCD body would sweep it from the origin through the station.
		var idx := ship.get_index()
		remove_child(ship)
		ship.transform = spawn
		add_child(ship)
		move_child(ship, idx)

	var cam := get_node_or_null(^"CameraRig")
	if cam == null:
		cam = _instance(CAMERA_SCENE)
		if cam == null:
			_missing.append("camera_rig.tscn (using basic follow camera)")
			cam = _FallbackCamera.new()
		cam.name = &"CameraRig"
		add_child(cam)
		move_child(cam, ship.get_index() + 1)

	if get_node_or_null(^"TuningPanel") == null:
		var tp := _instance(TUNING_SCENE)
		if tp:
			tp.name = &"TuningPanel"
			add_child(tp)
		else:
			_missing.append("tuning_panel.tscn")

	if not _missing.is_empty():
		print("[main] optional pieces missing: ", ", ".join(_missing))

## A test scene may point `level_scene` at a different level than the one
## instanced in main.tscn: replace it before anything reads the level.
func _swap_level_if_overridden() -> void:
	var existing := get_node_or_null(^"Level")
	if existing == null or existing.scene_file_path == level_scene:
		return
	var idx := existing.get_index()
	remove_child(existing)
	existing.free()
	Game.level = null
	var lvl := _instance(level_scene)
	if lvl:
		lvl.name = &"Level"
		add_child(lvl)
		move_child(lvl, idx)

## Returns the existing child `node_name`, or instances `path` into slot `index`.
func _ensure(node_name: StringName, path: String, index: int) -> Node:
	var n := get_node_or_null(NodePath(node_name))
	if n:
		return n
	n = _instance(path)
	if n == null:
		_missing.append(path.get_file())
		return null
	n.name = node_name
	add_child(n)
	move_child(n, mini(index, get_child_count() - 1))
	return n

func _instance(path: String) -> Node:
	if path == "" or not ResourceLoader.exists(path):
		return null
	var ps := load(path) as PackedScene
	return ps.instantiate() if ps else null

func _index_after(n: Node) -> int:
	return n.get_index() + 1 if n else 0

## --spawn=x_px,y_px,heading_deg overrides the level's PlayerSpawn marker.
func _spawn_transform() -> Transform2D:
	if Game.cmd.has("spawn"):
		var parts := String(Game.cmd["spawn"]).split(",")
		if parts.size() >= 2:
			var heading := deg_to_rad(float(parts[2])) if parts.size() >= 3 else 0.0
			return Transform2D(heading, Vector2(float(parts[0]), float(parts[1])))
	return GameplayUtil.spawn_transform(get_tree())

## Used only when the real camera rig scene is missing.
class _FallbackCamera extends Camera2D:
	var trauma := 0.0

	func _ready() -> void:
		Game.camera = self
		zoom = Vector2.ONE * 0.9
		make_current()

	func add_trauma(amount: float) -> void:
		trauma = clampf(trauma + amount, 0.0, 1.0)

	func punch(_direction: Vector2, _strength_px: float) -> void:
		pass

	func _process(delta: float) -> void:
		if GameplayUtil.player_valid():
			global_position = Game.player.global_position + Game.player.linear_velocity * 0.4
		trauma = maxf(0.0, trauma - delta * 1.3)
		var s := trauma * trauma * 22.0
		offset = Vector2(randf_range(-s, s), randf_range(-s, s))
