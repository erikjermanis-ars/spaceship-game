class_name BoundarySystem
extends Node
## Soft edge of the playable area (Game.world_bounds). Outside it the HUD
## warns, a warning tone loops, and a gentle restoring force — growing with
## distance — nudges the ship back. Also draws a faint dashed amber
## perimeter that fades in as you get close to it.

const BASE_ACCEL := 2.0         ## m/s² just outside the edge
const ACCEL_PER_M := 0.08       ## extra m/s² per metre beyond the edge
const MAX_ACCEL := 14.0
const SHOW_DIST_M := 120.0      ## perimeter line starts appearing at this distance

var outside := false
var distance_out_m := 0.0
var _warn_player: AudioStreamPlayer
var _amp := 0.0
var _edge: _BoundaryEdge

func _ready() -> void:
	add_to_group(&"boundary_system")
	var loop := GameplayUtil.load_loop("boundary_warning.wav")
	_warn_player = GameplayUtil.make_player(self, loop, &"UI", -80.0)
	_edge = _BoundaryEdge.new()
	add_child(_edge)

func _physics_process(_delta: float) -> void:
	if not GameplayUtil.player_alive():
		outside = false
		return
	var ship := Game.player
	var b := Game.world_bounds
	var p := ship.global_position
	var closest := Vector2(clampf(p.x, b.position.x, b.end.x), clampf(p.y, b.position.y, b.end.y))
	var off := p - closest
	outside = off.length_squared() > 1.0
	distance_out_m = off.length() / Game.PX_PER_M
	if outside:
		var accel := minf(MAX_ACCEL, BASE_ACCEL + ACCEL_PER_M * distance_out_m)
		# F = m·a, in Godot units (×PX_PER_M). Applied every step (forces are
		# cleared after each physics step).
		ship.apply_central_force(-off.normalized() * ship.mass * accel * Game.PX_PER_M)
	_edge.update_proximity(p, b)

func _process(delta: float) -> void:
	var target := 1.0 if outside else 0.0
	_amp = move_toward(_amp, target, delta * (6.0 if outside else 2.5))
	if _warn_player.stream == null:
		return
	if _amp > 0.01:
		if not _warn_player.playing:
			_warn_player.play()
		_warn_player.volume_db = linear_to_db(_amp) - 8.0
	elif _warn_player.playing:
		_warn_player.stop()

## Dashed amber rectangle at the bounds; redrawn only when bounds change,
## alpha follows the ship's distance to the edge.
class _BoundaryEdge extends Node2D:
	var _bounds := Rect2()

	func _ready() -> void:
		z_as_relative = false
		z_index = Game.Z_FX
		modulate.a = 0.0

	func update_proximity(p: Vector2, b: Rect2) -> void:
		if b != _bounds:
			_bounds = b
			queue_redraw()
		var inner := minf(minf(p.x - b.position.x, b.end.x - p.x), minf(p.y - b.position.y, b.end.y - p.y))
		var d_m := inner / Game.PX_PER_M
		modulate.a = clampf(1.0 - d_m / SHOW_DIST_M, 0.0, 1.0) * 0.8

	func _draw() -> void:
		if _bounds.size == Vector2.ZERO:
			return
		var col := Color(1.0, 0.69, 0.0, 0.8)
		var c := [_bounds.position, Vector2(_bounds.end.x, _bounds.position.y), _bounds.end, Vector2(_bounds.position.x, _bounds.end.y)]
		for i in 4:
			draw_dashed_line(c[i], c[(i + 1) % 4], col, 6.0, 60.0, true, true)
