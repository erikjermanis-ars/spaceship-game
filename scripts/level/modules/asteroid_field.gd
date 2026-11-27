extends Node2D
## The asteroid field around Vesper Rock: scatters `count` rocks (Asteroid)
## through the sector from a seed, keeps them out of the places ships need
## (clear_rects_m / clear_circles_m: the base, the apron, the berth lane), and
## tops the field up when rocks have been shot away.
##
## Layout is a pure function of the exports (`plan()`), so the same seed gives
## the same field every run. Rocks sit in loose clusters with loners between.
##
## The whole field sleeps (no physics, not drawn) while no camera or ship is
## anywhere near: Vesper shares the world with Meridian, 9 km away.

const PX := 10.0
## Share of small / medium / large rocks.
const WEIGHTS := [0.4, 0.38, 0.22]
## Each rock circles its home at this radius (m): the "slow drift".
const ORBIT_MIN_M := 6.0
const ORBIT_MAX_M := 24.0
const CHECK_S := 0.25
const REFILL_S := 2.0

@export var count := 40
@export var seed := 4211
## Half extents (m) of the sector, centred on this node.
@export var extent_m := Vector2(800, 650)
@export var edge_margin_m := 50.0
## Areas (m, local) no rock may be planted in or wander into.
@export var clear_rects_m: Array[Rect2] = []
## More of the same as circles: x, y, radius (m).
@export var clear_circles_m: Array[Vector3] = []
@export var clusters := 8
@export var cluster_spread_m := 60.0
@export var ore_ratio := 0.25
## A new rock is added when fewer than this share of `count` are left ...
@export var refill_below := 0.7
## ... at least this far (m) from the camera centre and from every ship.
@export var refill_clear_m := 420.0
## The field is awake while a camera or ship is within this range (m).
@export var wake_range_m := 2400.0
## Tests: never sleep.
@export var always_awake := false

var active := true
var _rocks: Node2D
var _rng := RandomNumberGenerator.new()
var _serial := 0
var _check := 0.0
var _refill := 0.0


func _ready() -> void:
	_rocks = Node2D.new()
	_rocks.name = "Rocks"
	add_child(_rocks)
	_rng.seed = seed * 977 + 5
	for d in plan():
		_spawn(d)
	_set_active(always_awake or _someone_near())


## The seeded layout: [{home (m, local), cls, ore, seed, orbit_m, orbit_a,
## turn (+1/-1), rot, spin}].
func plan() -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	# One cluster per cell of a 2-row grid over the sector, so the field is
	# spread out instead of piling up wherever the dice fell.
	var hubs: Array[Vector2] = []
	var h := extent_m - Vector2(edge_margin_m, edge_margin_m)
	var cols := maxi(1, int(ceil(clusters / 2.0)))
	var cell := Vector2(h.x * 2.0 / cols, h.y)
	for k in clusters:
		var corner := Vector2(-h.x + cell.x * (k % cols), -h.y + cell.y * floori(float(k) / cols))
		for _attempt in 40:
			var p := corner + Vector2(rng.randf(), rng.randf()) * cell
			if _is_clear(p, cluster_spread_m * 0.7):
				hubs.append(p)
				break
	var out: Array[Dictionary] = []
	var tries := 0
	while out.size() < count and tries < count * 80:
		tries += 1
		var p := _random_point(rng)
		if rng.randf() < 0.65 and not hubs.is_empty():
			p = hubs[rng.randi() % hubs.size()] + Vector2.from_angle(rng.randf() * TAU) * absf(rng.randfn(0.0, cluster_spread_m))
		var d := _make(rng, p)
		if _fits(d, out):
			d.seed = seed * 1000 + out.size()
			d.ore = false
			out.append(d)
	# Exactly ore_ratio of the planned rocks carry ore (a top-up rock rolls).
	var want := int(round(out.size() * ore_ratio))
	while want > 0:
		var pick: Dictionary = out[rng.randi() % out.size()]
		if not pick.ore:
			pick.ore = true
			want -= 1
	return out


func rocks() -> Array[Asteroid]:
	var out: Array[Asteroid] = []
	for c in _rocks.get_children():
		if c is Asteroid and not c.is_queued_for_deletion():
			out.append(c)
	return out


func rock_count() -> int:
	return rocks().size()

# ================================================================== layout

func _random_point(rng: RandomNumberGenerator) -> Vector2:
	var h := extent_m - Vector2(edge_margin_m, edge_margin_m)
	return Vector2(rng.randf_range(-h.x, h.x), rng.randf_range(-h.y, h.y))


func _make(rng: RandomNumberGenerator, home: Vector2) -> Dictionary:
	var roll := rng.randf()
	var cls := 0 if roll < WEIGHTS[0] else (1 if roll < WEIGHTS[0] + WEIGHTS[1] else 2)
	return {
		"home": home, "cls": cls, "ore": rng.randf() < ore_ratio, "seed": 0,
		"orbit_m": rng.randf_range(ORBIT_MIN_M, ORBIT_MAX_M), "orbit_a": rng.randf() * TAU,
		"turn": 1.0 if rng.randf() < 0.5 else -1.0,
		"rot": rng.randf() * TAU, "spin": rng.randf_range(-0.22, 0.22) / (1.0 + cls),
	}


## Room a rock needs around its home: its own size plus the circle it drifts in.
static func _reach(d: Dictionary) -> float:
	return float(Asteroid.CLASSES[d.cls].radius_m) * 1.25 + float(d.orbit_m)


func _fits(d: Dictionary, others: Array[Dictionary]) -> bool:
	var home: Vector2 = d.home
	if not _is_clear(home, _reach(d) + 8.0):
		return false
	for o in others:
		if home.distance_to(o.home) < _reach(d) + _reach(o):
			return false
	return true


## True if `p` (m, local) is inside the sector and at least `pad` metres from
## every keep-clear area.
func _is_clear(p: Vector2, pad: float) -> bool:
	var h := extent_m - Vector2(edge_margin_m, edge_margin_m)
	if absf(p.x) > h.x or absf(p.y) > h.y:
		return false
	for r in clear_rects_m:
		if r.grow(pad).has_point(p):
			return false
	for c in clear_circles_m:
		if p.distance_to(Vector2(c.x, c.y)) < c.z + pad:
			return false
	return true


func _spawn(d: Dictionary) -> Asteroid:
	var rock := Asteroid.new()
	rock.setup(d.cls, d.seed, d.ore)
	_serial += 1
	rock.name = "Rock%02d" % _serial
	var home: Vector2 = d.home
	var arm := Vector2.from_angle(d.orbit_a) * float(d.orbit_m)
	rock.position = (home + arm) * PX
	rock.rotation = d.rot
	rock.home = to_global(home * PX)
	# Circular orbit around home under the tether spring.
	var w := TAU / Asteroid.TETHER_PERIOD_S
	rock.linear_velocity = (arm.orthogonal() * w * float(d.turn) * PX).rotated(global_rotation)
	rock.angular_velocity = d.spin
	_rocks.add_child(rock)
	return rock

# ============================================================== housekeeping

func _physics_process(delta: float) -> void:
	_check += delta
	if _check < CHECK_S:
		return
	_check = 0.0
	_set_active(always_awake or _someone_near())
	if not active:
		return
	_refill += CHECK_S
	if _refill >= REFILL_S:
		_refill = 0.0
		if rock_count() < int(ceil(count * refill_below)):
			_add_one()


func _watchers() -> Array[Vector2]:
	var out: Array[Vector2] = []
	var cam := get_viewport().get_camera_2d()
	if cam:
		out.append(cam.get_screen_center_position())
	for s in get_tree().get_nodes_in_group(&"player_ship"):
		if s is Node2D:
			out.append((s as Node2D).global_position)
	return out


func _someone_near() -> bool:
	for p in _watchers():
		if p.distance_to(global_position) < wake_range_m * PX:
			return true
	return false


func _set_active(on: bool) -> void:
	if on == active:
		return
	active = on
	_rocks.visible = on
	# DISABLED takes the bodies out of the physics space; they come back with
	# their velocities when the field wakes.
	_rocks.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED


## Quietly plants one new rock where nobody is looking: outside the camera's
## view, far from the camera and every ship, and not inside anything.
func _add_one() -> void:
	var watchers := _watchers()
	var vp := get_viewport()
	var view := (vp.get_canvas_transform().affine_inverse() * vp.get_visible_rect()).grow(80.0 * PX)
	var space := get_world_2d().direct_space_state
	for _attempt in 16:
		var d := _make(_rng, _random_point(_rng))
		if not _is_clear(d.home, _reach(d) + 8.0):
			continue
		var g := to_global((d.home as Vector2) * PX)
		if vp.get_camera_2d() != null and view.has_point(g):
			continue
		var far := true
		for w in watchers:
			far = far and w.distance_to(g) > refill_clear_m * PX
		if not far:
			continue
		var probe := CircleShape2D.new()
		probe.radius = _reach(d) * PX
		var q := PhysicsShapeQueryParameters2D.new()
		q.shape = probe
		q.transform = Transform2D(0.0, g)
		q.collision_mask = Game.LAYER_WORLD | Game.LAYER_PLAYER | Game.LAYER_PROPS | Game.LAYER_TRAFFIC
		if not space.intersect_shape(q, 1).is_empty():
			continue
		d.seed = seed * 1000 + 500 + _serial
		_spawn(d)
		return
