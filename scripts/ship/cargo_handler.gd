class_name CargoHandler
extends Node
## The PETREL's loadmaster: decides when the hold (CargoHold) swallows the
## container on the mag-line, drops containers out of the stern on U, and
## spills them if the ship is lost. ShuttleShip owns it and ticks it.
##
## Stowing reuses the towline: hook a container and REEL. Once the container
## is alongside the hull and no longer flying at us, the stern hatch takes it. Towing without reeling never stows, so flinging
## and dragging cargo work as before.

const PX := 10.0
## Stow when the container is this close to the hull (just before it would
## bump it)...
const STOW_GAP_M := 1.5
## ...and the container closes slower than this (the winch brings it in at
## 4 m/s; this only stops one that is being whipped past).
const STOW_MAX_REL_MPS := 5.0
const STOW_DWELL_S := 0.1
const STOW_TIME_S := 0.45
## Unloading: push speed relative to the ship, gap behind the hull, and how
## fast holding U repeats (once the last one has drifted clear).
const EJECT_MPS := 1.5
const EJECT_GAP_M := 0.9
const EJECT_TIME_S := 0.3
const REPEAT_S := 0.4
## Stern hatch (local m): where containers shrink into and come out of.
const HATCH_M := Vector2(-4.6, 0.0)
const SPILL_STEP_M := 3.2

var ship: ShuttleShip
var hold: CargoHold

var _stow_t := 0.0
var _denied_id := 0          # container already refused during this reel
var _held := false
var _muted := false          # a refused press stays quiet until U is released
var _repeat_t := 0.0
var _stern_x := 0.0
## Velocity over the last few ticks: by the time a crash destroys the ship
## the solver has already bounced it, so "its momentum" is the fastest of these.
var _vel_hist: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
var _vel_i := 0
var _snd := {}


func _ready() -> void:
	for n in ["cargo_stow", "cargo_eject", "cargo_deny"]:
		_snd[n] = GameplayUtil.load_audio(n + ".wav")
	for p in ship.hull_polygon():
		_stern_x = minf(_stern_x, p.x)


## Every physics tick, from the ship. `reel` and `unload` are the held inputs.
func physics_tick(delta: float, reel: bool, unload_down: bool) -> void:
	_vel_hist[_vel_i] = ship.linear_velocity
	_vel_i = (_vel_i + 1) % _vel_hist.size()
	if not ship.alive:
		return
	_tick_stow(delta, reel)
	_tick_unload(delta, unload_down)


# ================================================================== stow

func _tick_stow(delta: float, reel: bool) -> void:
	var line := ship.line
	var box: RigidBody2D = null
	if line and line.is_attached():
		box = line.target as RigidBody2D
	if box == null or not reel or box.freeze or not box.is_in_group(&"cargo_container"):
		_stow_t = 0.0
		_denied_id = 0
		return
	var rel := (box.linear_velocity - ship.linear_velocity).length() / PX
	if rel > STOW_MAX_REL_MPS or gap_m(box) > STOW_GAP_M:
		_stow_t = 0.0
		return
	_stow_t += delta
	if _stow_t < STOW_DWELL_S:
		return
	if hold.can_take(box):
		_swallow(box)
	elif _denied_id != box.get_instance_id():
		# Once per attempt: it stays alongside on the line, reeling or not.
		_denied_id = box.get_instance_id()
		var it := CargoHold.describe(box)
		if hold.free_slots() <= 0:
			_deny("HOLD FULL  ·  %d/%d" % [hold.used(), hold.capacity])
		else:
			_deny("NO ROOM  ·  %s needs %d slots  ·  HOLD %d/%d" % [CargoHold.label(it), it.slots, hold.used(), hold.capacity])


func _swallow(box: RigidBody2D) -> void:
	var it := CargoHold.describe(box)
	var from := ship.global_transform.affine_inverse() * box.global_transform
	ship.line.release(true)
	if not hold.stow(box):
		return
	var g := CargoGhost.of(it)
	g.from_local = Transform2D(from.get_rotation(), from.origin)
	g.to_local = Transform2D(0.0, HATCH_M * PX)
	g.scale_to = 0.35
	g.duration = STOW_TIME_S
	# Under the hull: it is drawn into the belly, not over the roof.
	g.z_index = Game.Z_SHIP - 1
	ship.add_child(g)
	_stow_t = 0.0
	_play("cargo_stow", -5.0)
	Game.toast("STOWED  ·  %s  ·  HOLD %d/%d" % [CargoHold.label(it), hold.used(), hold.capacity], 2.2)


## Gap (m) between the hull and a container's box; 0 when they touch. The
## hooked point alone won't do: a 12 m box hooked by one end lies against the
## hull with its hook metres away.
func gap_m(box: RigidBody2D) -> float:
	var half := CargoHold.size_of(box) * 0.5 * PX
	var to_ship := ship.global_transform.affine_inverse() * box.global_transform
	var to_box := to_ship.affine_inverse()
	var poly := ship.hull_polygon()
	var best := INF
	# Hull corners against the box: point-to-rectangle in the box's own frame.
	for v in poly:
		var q := (to_box * v).abs() - half
		best = minf(best, Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length())
	# Box corners against the hull outline.
	for c: Vector2 in [half, Vector2(-half.x, half.y), -half, Vector2(half.x, -half.y)]:
		var p := to_ship * c
		if Geometry2D.is_point_in_polygon(p, poly):
			return 0.0
		for i in poly.size():
			best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()])))
	return best / PX


# ================================================================ unload

func _tick_unload(delta: float, down: bool) -> void:
	if not down:
		_held = false
		_muted = false
		return
	var fresh := not _held
	_held = true
	_repeat_t -= delta
	if _muted or (not fresh and _repeat_t > 0.0):
		return
	var why := unload_block()
	if why == "":
		unload()
		_repeat_t = REPEAT_S
	elif fresh:
		_deny(why)
		_muted = true
	elif hold.is_empty():
		# Held until the hold ran dry: say so, without the buzzer.
		Game.toast("HOLD EMPTY", 1.4)
		_muted = true
	else:
		# Held, and the last one is still in the way: wait for it to drift off.
		_repeat_t = 0.1


## Why a container can't be unloaded right now ("" = it can).
func unload_block() -> String:
	if hold.is_empty():
		return "HOLD EMPTY"
	if ship.land_state != ShuttleShip.Land.CRUISE and ship.land_state != ShuttleShip.Land.HOVER:
		return "CAN'T UNLOAD ON THE DECK  ·  lift off first"
	var it := hold.top()
	if not _clear(drop_transform(it.size_m), it.size_m):
		return "STERN BLOCKED  ·  clear the space behind"
	return ""


## Where the next container comes out: lengthwise, just behind the stern.
func drop_transform(size_m: Vector2) -> Transform2D:
	var x := _stern_x - (EJECT_GAP_M + size_m.x * 0.5) * PX
	return ship.global_transform * Transform2D(0.0, Vector2(x, 0.0))


## Drops the last container stowed behind the stern (null if it can't).
func unload() -> RigidBody2D:
	if unload_block() != "":
		return null
	var it := hold.top()
	var xf := drop_transform(it.size_m)
	var parent := _world_parent(it)
	var box := hold.eject()
	var fwd := ship.global_transform.x.normalized()
	var r := xf.origin - ship.global_position
	var w := ship.angular_velocity
	var vel := ship.linear_velocity + Vector2(-w * r.y, w * r.x) - fwd * EJECT_MPS * PX
	box.visible = false      # its picture slides out of the hatch first
	CargoHold.put_in_world(box, parent, xf, vel, w)
	# Third law, with the mass the hold counted for it.
	ship.apply_central_impulse(fwd * float(it.slots) * CargoHold.SLOT_KG * EJECT_MPS * PX)
	var g := CargoGhost.of(it)
	g.from_local = Transform2D(0.0, HATCH_M * PX)
	g.to_local = ship.global_transform.affine_inverse() * xf
	g.follow_to = box
	g.scale_from = 0.45
	g.scale_to = 1.0
	g.alpha_from = 0.0
	g.alpha_to = 1.0
	g.duration = EJECT_TIME_S
	g.z_index = Game.Z_SHIP - 1
	ship.add_child(g)
	# No toast: over an intake every container is announced as DELIVERED a
	# second later, and the HUD slots and the hull lamps already count down.
	_play("cargo_eject", -6.0)
	return box


func _world_parent(it: Dictionary) -> Node:
	var p := hold.home_of(it)
	if p == null and Game.level != null and is_instance_valid(Game.level) and Game.level.is_inside_tree():
		p = Game.level
	return p if p != null else ship.get_parent()


func _clear(xf: Transform2D, size_m: Vector2) -> bool:
	var shape := RectangleShape2D.new()
	shape.size = (size_m + Vector2(0.5, 0.5)) * PX
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	q.transform = xf
	q.collision_mask = Game.LAYER_WORLD | Game.LAYER_PROPS | Game.LAYER_TRAFFIC
	q.exclude = [ship.get_rid()]
	return ship.get_world_2d().direct_space_state.intersect_shape(q, 1).is_empty()


# ================================================================= spill

## The ship is lost: everything in the hold tumbles out around the wreck,
## carrying the ship's momentum. Called deferred (new bodies can't be added
## from inside a physics callback).
func spill() -> void:
	if hold.is_empty() or not ship.is_inside_tree():
		return
	var vel := Vector2.ZERO
	for v in _vel_hist:
		if v.length_squared() > vel.length_squared():
			vel = v
	var centre := ship.global_position
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(centre)
	var placed: Array = []      # [position, radius] of the ones already out
	var n := hold.count()
	var k := 0
	while not hold.is_empty():
		var it := hold.top()
		var parent := _world_parent(it)
		var box := hold.eject()
		var rad := (it.size_m as Vector2).length() * 0.5 * PX
		var xf := Transform2D(rng.randf_range(-PI, PI), centre)
		# Walk a golden-angle spiral out from the wreck to the first free spot.
		for attempt in 40:
			xf = Transform2D(rng.randf_range(-PI, PI), centre + Vector2.from_angle(k * 2.39996) * SPILL_STEP_M * sqrt(float(k)) * PX)
			k += 1
			if _spot_free(xf, it.size_m, rad, placed):
				break
		placed.append([xf.origin, rad])
		var out := xf.origin - centre
		var dir := out.normalized() if out.length() > 1.0 else Vector2.from_angle(rng.randf_range(-PI, PI))
		box.visible = true
		CargoHold.put_in_world(box, parent, xf, vel * 0.9 + dir * rng.randf_range(1.5, 4.0) * PX, rng.randf_range(-1.2, 1.2))
	Game.toast("CARGO LOST  ·  %d container%s adrift" % [n, "" if n == 1 else "s"], 3.0)


func _spot_free(xf: Transform2D, size_m: Vector2, rad: float, placed: Array) -> bool:
	# Bodies added this frame aren't in the physics space yet: check those by hand.
	for p in placed:
		if xf.origin.distance_to(p[0]) < rad + float(p[1]):
			return false
	return _clear(xf, size_m)


# ================================================================= sound

func _deny(text: String) -> void:
	_play("cargo_deny", -6.0)
	Game.toast(text, 1.8)


func _play(n: String, db: float) -> void:
	var s: AudioStream = _snd.get(n)
	if s == null or not ship.is_inside_tree():
		return
	var p := AudioStreamPlayer2D.new()
	p.stream = s
	p.bus = GameplayUtil.bus(&"SFX")
	p.volume_db = db
	p.max_distance = 1600.0
	ship.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
