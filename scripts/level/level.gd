@tool
extends Node2D
## Root of Meridian Station. Registers itself with Game, publishes the world
## bounds, and runs the two cheap per-frame passes every module relies on:
##   * the depth pass: below-deck and overhead canvas layers are scaled about
##     the camera centre (true perspective parallax => a 2.5D feel while the
##     colliding layer stays exactly at scale 1),
##   * the beacon clock: one shader uniform drives every blinking light.

## Playable area in metres (centred on the station).
@export var bounds_m := Rect2(-1100, -900, 2200, 1800)

var _time := 0.0


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	add_to_group(&"meridian_level")
	var game := get_node_or_null(^"/root/Game")
	if game:
		game.level = self
		game.world_bounds = Rect2(bounds_m.position * LevelArt.PX, bounds_m.size * LevelArt.PX)
	# Run after everything else moved this frame (camera rig, ship).
	process_priority = 1000


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_time += delta
	LevelArt.blink_material().set_shader_parameter(&"t", _time)
	_update_depth()


func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return
	# Stop positional loops before teardown so their playbacks are released.
	for p in find_children("*", "AudioStreamPlayer2D", true, false):
		(p as AudioStreamPlayer2D).stop()
		(p as AudioStreamPlayer2D).stream = null
	LevelArt.cleanup()


## Seconds on the shared beacon clock (for syncing audio pings to flashes).
func beacon_time() -> float:
	return _time


func _update_depth() -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var c := cam.get_screen_center_position()
	var layers: Array = LevelArt.depth_layers
	for e in layers:
		var ci: Node2D = e[0]
		if not is_instance_valid(ci):
			continue
		var parent := ci.get_parent() as Node2D
		if parent == null:
			continue
		var s: float = lerpf(1.0, e[1], LevelArt.depth_amount)
		var off: Vector2 = e[2]
		var base := parent.global_transform
		ci.global_transform = Transform2D(base.x * s, base.y * s, c + (base.origin - c) * s + off)
