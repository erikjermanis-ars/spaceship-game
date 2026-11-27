class_name GunAimLine
extends Node2D
## A faint line and reticle showing where the WREN's bolts will actually go.
## Bolts keep the ship's velocity, so when you drift sideways they don't fly
## where the nose points: the line follows the bolt's true track through the
## world (what matters for a target that sits still). The reticle rides on
## whatever the line touches, and turns amber on something that takes shots.
##
## Only visible while firing and for a moment after (WrenGuns.aim_alpha), so
## it never clutters ordinary flight. Three draw calls while it shows.

const PX := 10.0
const REACH_M := 300.0          # how far the line looks for something to touch
const LINE_M := 150.0           # how far it is drawn when it touches nothing
const C_LINE := Color(1.0, 0.82, 0.6)
const C_LOCK := Color(1.0, 0.69, 0.0)
## "Small" for the reticle: the hit point is this close to the target's origin.
const SNAP_M := 4.0

var guns: WrenGuns
var _hit_m := -1.0              # distance to what the line touches, -1 = nothing
var _lock := false              # ... and it takes shots
var _lock_vis := 0.0
## A small target (a drone) is bracketed whole: the reticle goes on its centre.
var _snap_to: Node2D
var _ray := PhysicsRayQueryParameters2D.new()


func _ready() -> void:
	top_level = true
	z_as_relative = false
	z_index = Game.Z_FX
	material = FxTextures.additive()
	global_transform = Transform2D.IDENTITY
	_ray.collision_mask = WeaponSystem.HIT_MASK
	_ray.collide_with_areas = false


## Bolt track from the nose: unit direction in the world.
func _track_dir(xf: Transform2D) -> Vector2:
	var v := xf.x.normalized() * WeaponSystem.BOLT_SPEED_MPS * PX + guns.ship.linear_velocity
	return v.normalized()


## Called every physics tick by the guns: find what the line touches (space
## queries belong in the physics step).
func track() -> void:
	if guns.aim_alpha <= 0.01:
		_hit_m = -1.0
		_lock = false
		return
	var ship := guns.ship
	var xf := ship.global_transform
	var from := xf * Vector2(WrenGuns.MUZZLES[0].x, 0.0)
	_ray.from = from
	_ray.to = from + _track_dir(xf) * REACH_M * PX
	_ray.exclude = [ship.get_rid()]
	var hit := get_world_2d().direct_space_state.intersect_ray(_ray)
	_snap_to = null
	if hit.is_empty():
		_hit_m = -1.0
		_lock = false
	else:
		_hit_m = from.distance_to(hit.position) / PX
		var body := hit.collider as Node2D
		_lock = body != null and body.has_method(&"take_shot")
		if _lock and body.global_position.distance_to(hit.position) < SNAP_M * PX:
			_snap_to = body


func _process(delta: float) -> void:
	visible = guns != null and guns.aim_alpha > 0.01
	if visible:
		_lock_vis = move_toward(_lock_vis, 1.0 if _lock else 0.0, delta * 10.0)
		queue_redraw()


func _draw() -> void:
	var a := guns.aim_alpha
	var xf := guns.ship.render_transform()
	var dir := _track_dir(xf)
	var from := xf * Vector2(WrenGuns.MUZZLES[0].x, 0.0)
	var touching := _hit_m >= 0.0
	var end_m := _hit_m if touching else LINE_M
	var col := C_LINE.lerp(C_LOCK, _lock_vis)
	# Line: fades in off the nose; fades out again unless it ends on something.
	var p0 := from + dir * minf(6.0, end_m) * PX
	var p1 := from + dir * minf(34.0, end_m) * PX
	var p2 := from + dir * end_m * PX
	draw_polyline_colors(PackedVector2Array([p0, p1, p2]),
		PackedColorArray([Color(col, 0.0), Color(col, 0.2 * a), Color(col, (0.22 if touching else 0.0) * a)]), 1.5, true)
	# Reticle: on the target, or at the guns' convergence range.
	var c := from + dir * (end_m if touching else minf(guns.converge_m, LINE_M)) * PX
	var r := lerpf(13.0, 20.0, _lock_vis)
	if is_instance_valid(_snap_to):
		c = _snap_to.global_position
		r = lerpf(13.0, 34.0, _lock_vis)
	var ra := (0.3 + 0.45 * _lock_vis) * a
	draw_arc(c, r, 0.0, TAU, 24, Color(col, ra), 1.5, true)
	var n := dir.orthogonal()
	var gap := r + 3.0
	var tick := r + 9.0
	draw_multiline(PackedVector2Array([
		c + n * gap, c + n * tick, c - n * gap, c - n * tick,
		c + dir * gap, c + dir * tick, c - dir * gap, c - dir * tick]), Color(col, ra), 1.5)
