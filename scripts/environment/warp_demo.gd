class_name WarpDemo
extends Node
## Scripted preview of a light-speed jump for env_test (`--warp-demo`): drives
## a WarpFX the way the real jump sequence will, with a stand-in ship at the
## screen centre, and swaps the sky look under the arrival flash. It loops,
## flying out and back in turn, so every stage can be captured with --shots.
##
## The timeline is the one the game's jump sequence uses, after a 1 s lead-in:
##   1.0 - 4.2   spool: charge 0 -> 1
##   4.2 - 5.1   leap: charge 1, streak 0 -> 1, flash rising over the last quarter
##   5.1 - 9.7   tunnel = 1, progress 0 -> 1; the flash clears over the first
##               0.5 s and returns over the last 7 %
##   9.7         sky look swap under the flash, tunnel off
##   9.7 - 10.6  streak 1 -> 0, flash clearing over 0.45 s
## `--warp-heading=deg` sets the ship's heading (default -20).
## `--warp-ship=res://texture@scale` uses a real ship texture as the snapshot
## (e.g. res://assets/art/ship/frigate_hull.svg@0.5, with --cam=0,0,0.3).

const LOOP := 12.5
const T_CHARGE := 1.0
const T_STREAK := 4.2
const T_TUNNEL := 5.1
const T_ARRIVE := 9.7
const T_SETTLE := 10.6
const SHIP_POLY := [Vector2(45, 0), Vector2(-40, -26), Vector2(-28, 0), Vector2(-40, 26)]

var fx: WarpFX

var _root: Node2D
var _bg: SpaceBackground
var _cam: Camera2D
var _ship: Polygon2D
var _snapshot: Texture2D
var _snapshot_scale := 1.0
var _in_tunnel := false
var _t := 0.0
var _swapped := false
var _heading := deg_to_rad(-20.0)


func setup(root: Node2D, bg: SpaceBackground, cam: Camera2D) -> void:
	_root = root
	_bg = bg
	_cam = cam
	if Game.cmd.has("warp-heading"):
		_heading = deg_to_rad(float(Game.cmd["warp-heading"]))
	fx = WarpFX.new()
	fx.name = "WarpFX"
	root.add_child(fx)
	fx.heading = _heading
	_set_direction()
	# The stand-in ship: one polygon in the world, and the same polygon
	# rendered once into a texture to hand over as the snapshot.
	_ship = _make_ship()
	_ship.rotation = _heading
	cam.add_child(_ship)
	if Game.cmd.has("warp-ship"):
		var parts := String(Game.cmd["warp-ship"]).split("@")
		_snapshot = load(parts[0])
		_snapshot_scale = float(parts[1]) if parts.size() > 1 else 1.0
		_ship.queue_free()
		var real := Sprite2D.new()
		real.texture = _snapshot
		real.scale = Vector2.ONE * _snapshot_scale
		real.rotation = _heading
		cam.add_child(real)
		return
	var vp := SubViewport.new()
	vp.size = Vector2i(128, 64)
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var twin := _make_ship()
	twin.position = Vector2(vp.size) * 0.5
	vp.add_child(twin)
	add_child(vp)
	_snapshot = vp.get_texture()


func _make_ship() -> Polygon2D:
	var p := Polygon2D.new()
	p.polygon = PackedVector2Array(SHIP_POLY)
	p.color = Color("#E9EEF3")
	return p


## Fly towards whichever place we are not at.
func _set_direction() -> void:
	fx.direction = 1.0 if _bg.look() == SpaceBackground.LOOK_MERIDIAN else -1.0


func _process(delta: float) -> void:
	_t += delta
	if _t >= LOOP:
		_t -= LOOP
		_swapped = false
		_set_direction()
	var t := _t
	fx.charge = _ramp(t, T_CHARGE, T_STREAK) if t < T_TUNNEL else 0.0
	fx.streak = _ramp(t, T_STREAK, T_TUNNEL) if t < T_ARRIVE else 1.0 - _ramp(t, T_ARRIVE, T_SETTLE)
	var tunnel := t >= T_TUNNEL and t < T_ARRIVE
	fx.tunnel = 1.0 if tunnel else 0.0
	fx.progress = _ramp(t, T_TUNNEL, T_ARRIVE)
	var leap_len := T_TUNNEL - T_STREAK
	var tunnel_len := T_ARRIVE - T_TUNNEL
	if t < T_TUNNEL:
		fx.flash = _ramp(t, T_TUNNEL - 0.25 * leap_len, T_TUNNEL)
	elif t < T_ARRIVE:
		fx.flash = maxf(1.0 - _ramp(t, T_TUNNEL, T_TUNNEL + 0.5), _ramp(t, T_ARRIVE - 0.07 * tunnel_len, T_ARRIVE))
	else:
		fx.flash = 1.0 - _ramp(t, T_ARRIVE, T_ARRIVE + 0.45)
	if t >= T_ARRIVE and not _swapped:
		_swapped = true
		_swap_look()
	# Like the game: the snapshot is handed over once when the tunnel starts
	# (it covers the world ship) and taken back when it ends.
	if tunnel != _in_tunnel:
		_in_tunnel = tunnel
		if tunnel:
			var zoom := _cam.zoom.x * _snapshot_scale
			var centre := get_viewport().get_visible_rect().size * 0.5
			fx.set_ship_snapshot(_snapshot, centre, _heading, Vector2(zoom, zoom))
		else:
			fx.clear_ship_snapshot()


## Arrive at the other place: the sky changes and the test scene (camera and
## reference shapes) moves to that place's origin, as the real jump moves the
## ship to the other sector.
func _swap_look() -> void:
	if _bg.look() == SpaceBackground.LOOK_MERIDIAN:
		_bg.set_look(SpaceBackground.LOOK_VESPER, SpaceBackground.VESPER_ORIGIN)
	else:
		_bg.set_look(SpaceBackground.LOOK_MERIDIAN, Vector2.ZERO)
	_root.position = _bg.look_origin()


static func _ramp(t: float, a: float, b: float) -> float:
	return clampf((t - a) / (b - a), 0.0, 1.0)
