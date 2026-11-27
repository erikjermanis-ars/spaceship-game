class_name Asteroid
extends RigidBody2D
## A rock of the Vesper asteroid field: drifts, tumbles, gets shoved, can be
## shot to pieces.
##
## * Paints itself ONCE as a single triangle array (RockArt). The facets are
##   lit in the shader, so tumbling costs nothing and the sunward side stays
##   sunward. It is redrawn only when a hit adds a crack.
## * Reports prop<->world / prop<->prop / prop<->traffic impacts on Game.impact
##   like a cargo container, and never contacts with the player (the player
##   reports those itself).
## * `take_shot()` is the weapon hit protocol: chips, cracks, and at zero hit
##   points the rock breaks into rocks of the next size down (the smallest
##   bursts into dust). An ore-bearing rock leaves an ORE canister behind.
## * Station keeping: a very soft pull toward `home` and a soft speed limit, so
##   the field keeps drifting but is still where it was hours later.

const G := preload("res://scripts/autoload/game.gd")
const A := preload("res://scripts/level/level_art.gd")
const R := preload("res://scripts/level/rock_art.gd")
const Fx := preload("res://scripts/level/rock_fx.gd")
const MATERIAL := "res://scripts/level/shaders/asteroid_lit.tres"
const PX := 10.0
const MIN_IMPACT_MPS := 0.8
const COOLDOWN_MS := 180

## Size classes, small to large. Mass is far below real rock (a 9 m boulder
## would be thousands of tonnes) but keeps the order: the 1 t courier bounces
## off all of them, the 120 t frigate shoves the middle size and is stopped by
## the big one.
const CLASSES := [
	{"radius_m": 2.0, "mass": 8000.0, "hp": 30.0, "verts": 9, "inner": 1},
	{"radius_m": 4.5, "mass": 70000.0, "hp": 90.0, "verts": 11, "inner": 3},
	{"radius_m": 9.0, "mass": 500000.0, "hp": 240.0, "verts": 13, "inner": 7},
]
const TINTS := [Color("6C6A70"), Color("766D64"), Color("5E616A"), Color("7B756D")]
const ORE_TINT := Color("555A64")
const VEIN := Color("45DCC6")
const GOLD := Color("F0BE4A")

## Station keeping. The pull toward home is a spring with this period, capped
## so a rock knocked far away wanders back instead of rushing.
const TETHER_PERIOD_S := 150.0
const TETHER_MAX_ACC := 0.05      ## m/s^2
const CRUISE_MPS := 1.6           ## faster than this bleeds off
const TUMBLE_MAX := 0.35          ## rad/s
const SETTLE := 0.3               ## 1/s, how fast the excess bleeds off
const SHOT_IMPULSE := 500.0       ## N*s per point of damage
const MAX_CRACKS := 7
## Fragments are born touching: no impact reports until they have parted
## (simulated seconds, so it also holds in fast headless runs).
const GRACE_S := 0.7

var size_class := 1
var ore := false
var rock_seed := 1
## Global px the rock keeps drifting around. INF = free (no tether).
var home := Vector2.INF
var hp := 0.0
var max_hp := 0.0
## Convex outline (local px): the visual edge and the collision shape.
var outline := PackedVector2Array()
## Velocity before this step's contact resolution (px/s), like CargoBox: the
## player ship and other props measure impacts with it.
var prev_velocity := Vector2.ZERO
var prev_velocity2 := Vector2.ZERO

## Base colour. Fragments keep their parent's; alpha 0 = pick one by seed.
var tint := Color(0, 0, 0, 0)

var _mesh: R.Facets
var _cracks := R.Facets.new()
var _crack_count := 0
var _glints := PackedVector2Array()
var _touching := {}
var _cooldown := {}
var _age := 0.0
var _dead := false
var _game: Node


func setup(p_class: int, p_seed: int, p_ore := false) -> void:
	size_class = clampi(p_class, 0, CLASSES.size() - 1)
	rock_seed = p_seed
	ore = p_ore


func radius_m() -> float:
	return CLASSES[size_class].radius_m


func _ready() -> void:
	var cls: Dictionary = CLASSES[size_class]
	var rng := RandomNumberGenerator.new()
	rng.seed = rock_seed
	_build_mesh(rng, cls)
	max_hp = cls.hp
	hp = max_hp
	collision_layer = G.LAYER_PROPS
	collision_mask = G.LAYER_WORLD | G.LAYER_PLAYER | G.LAYER_PROPS | G.LAYER_TRAFFIC
	var r_px: float = cls.radius_m * PX
	mass = float(cls.mass) * clampf(R.area(outline) / (PI * r_px * r_px), 0.6, 1.2)
	# All damping is done in _integrate_forces (only the excess is damped).
	linear_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp = 0.0
	can_sleep = false
	var mat := PhysicsMaterial.new()
	mat.bounce = 0.25
	mat.friction = 0.6
	physics_material_override = mat
	contact_monitor = true
	max_contacts_reported = 4
	var cs := CollisionShape2D.new()
	var shape := ConvexPolygonShape2D.new()
	shape.points = outline
	cs.shape = shape
	add_child(cs)
	z_as_relative = false
	z_index = G.Z_PROPS
	material = load(MATERIAL)
	add_to_group(&"radar_prop")
	add_to_group(&"asteroid")
	_game = get_node_or_null(^"/root/Game")
	if _game:
		_game.debug_draw_changed.connect(func(_on: bool) -> void: queue_redraw())
	if ore and not _glints.is_empty():
		_add_glints(rng)

# ================================================================== drawing

func _build_mesh(rng: RandomNumberGenerator, cls: Dictionary) -> void:
	var r: float = cls.radius_m * PX
	outline = R.convex_blob(rng, r, cls.verts)
	var m := R.Facets.new()
	# Soft contact shadow, symmetric so the tumble doesn't matter.
	for grown in Geometry2D.offset_polygon(outline, 5.0, Geometry2D.JOIN_ROUND):
		m.poly(grown, Color(0.0, 0.0, 0.02, 0.28))
	R.stroke(m, outline, 4.0)
	# A few raised interior points: more for bigger rocks (finer facets).
	var inner := PackedVector2Array()
	var heights := PackedFloat32Array()
	var tries := 0
	while inner.size() < int(cls.inner) and tries < 60:
		tries += 1
		var p := Vector2.from_angle(rng.randf() * TAU) * r * sqrt(rng.randf()) * 0.62
		var ok := R.edge_distance(p, outline) > r * 0.3
		for q in inner:
			ok = ok and p.distance_to(q) > r * 0.32
		if ok:
			inner.append(p)
			heights.append(r * rng.randf_range(0.4, 0.75))
	var pick: Color = ORE_TINT if ore else TINTS[rng.randi() % TINTS.size()]
	if tint.a == 0.0:
		tint = pick
	var base := tint
	var tone := func(_c: Vector2) -> Color:
		var j := rng.randf_range(-0.08, 0.08)
		return base.lightened(j) if j > 0.0 else base.darkened(-j)
	R.facets(m, outline, inner, heights, tone)
	for i in size_class + (rng.randi() % 2):
		var c := Vector2.from_angle(rng.randf() * TAU) * r * rng.randf_range(0.1, 0.5)
		R.crater(m, c, r * rng.randf_range(0.11, 0.2), rng, base.darkened(0.12), base.darkened(0.5), Vector2.ONE, 9)
	if ore:
		_veins(m, rng, r)
	R.rim(m, outline, Color("F2ECE0"), 2.0)
	_mesh = m


## Teal ore veins crossing the rock, gold nuggets where they branch.
func _veins(m: R.Facets, rng: RandomNumberGenerator, r: float) -> void:
	var n := outline.size()
	for _v in 1 + size_class:
		var i := rng.randi() % n
		var j := (i + (n >> 1) + (rng.randi() % 3) - 1) % n
		var path := R.jagged(rng, outline[i] * 0.86, outline[j] * 0.86, 5, r * 0.13)
		m.path(path, Color(VEIN, 0.3), 3.6)
		m.path(path, VEIN, 1.5)
		var node := path[2 + (rng.randi() % 2)]
		var spur := node + Vector2.from_angle(rng.randf() * TAU) * r * 0.3
		if Geometry2D.is_point_in_polygon(spur, outline):
			m.seg(node, spur, GOLD, 1.5)
		var s := clampf(r * 0.07, 2.2, 5.0)
		m.poly(PackedVector2Array([node + Vector2(0, -s), node + Vector2(s, 0), node + Vector2(0, s), node + Vector2(-s, 0)]), GOLD)
		_glints.append(node)


## The glint: a few glow sprites on the veins, pulsed by the station's shared
## beacon shader (no script time, one extra draw call per ore rock).
func _add_glints(rng: RandomNumberGenerator) -> void:
	var gl := Node2D.new()
	gl.name = "Glint"
	gl.material = A.blink_material()
	var phase := rng.randf()
	var pts := _glints
	var size := clampf(radius_m() * 5.0, 14.0, 34.0)
	gl.draw.connect(func() -> void:
		for i in pts.size():
			gl.draw_texture_rect(A.glow_texture(), Rect2(pts[i] - Vector2(size, size), Vector2(size, size) * 2.0), false,
				A.blink_color(Color(0.55, 1.0, 0.9), phase + 0.37 * i, false)))
	add_child(gl)


func _draw() -> void:
	var ci := get_canvas_item()
	RenderingServer.canvas_item_add_triangle_array(ci, _mesh.idx, _mesh.pts, _mesh.cols, _mesh.uvs)
	if not _cracks.idx.is_empty():
		RenderingServer.canvas_item_add_triangle_array(ci, _cracks.idx, _cracks.pts, _cracks.cols, _cracks.uvs)
	if _game and _game.debug_draw:
		var dbg := R.Facets.new()
		dbg.path(outline, Color(1.0, 0.2, 0.8, 0.95), 2.0, true)
		RenderingServer.canvas_item_add_triangle_array(ci, dbg.idx, dbg.pts, dbg.cols, dbg.uvs)

# ================================================================= shooting

## Weapon hit protocol. `at` is the hit point (global px), `dir` the shot's
## direction of travel.
func take_shot(damage: float, at: Vector2, dir: Vector2, _shooter: Node) -> void:
	if _dead or damage <= 0.0:
		return
	hp -= damage
	var d := dir.normalized() if dir.length_squared() > 0.0001 else Vector2.ZERO
	apply_impulse(d * damage * SHOT_IMPULSE * PX, at - global_position)
	if hp <= 0.0:
		_shatter(d)
	else:
		_chip(at, d)


func _chip(at: Vector2, d: Vector2) -> void:
	var r := radius_m() * PX
	if _crack_count < MAX_CRACKS:
		var rng := RandomNumberGenerator.new()
		rng.seed = rock_seed * 131 + _crack_count
		var from := to_local(at).limit_length(r * 0.8)
		var to := from.rotated(PI + rng.randf_range(-0.9, 0.9)).normalized() * r * rng.randf_range(0.15, 0.6)
		var path := R.jagged(rng, from, to, 4, r * 0.09)
		# Fracture lines read brighter the closer the rock is to breaking.
		var heat := 1.0 - clampf(hp / max_hp, 0.0, 1.0)
		_cracks.path(path, Color(0.04, 0.04, 0.07, 0.9), 2.2)
		for i in path.size() - 1:
			_cracks.seg(path[i] + Vector2(1.2, 1.2), path[i + 1] + Vector2(1.2, 1.2), Color(1.0, 0.9, 0.72, 0.25 + 0.5 * heat), 1.0)
		var fork := path[2] + (path[3] - path[1]).orthogonal().normalized() * r * rng.randf_range(-0.3, 0.3)
		_cracks.seg(path[2], fork, Color(0.04, 0.04, 0.07, 0.8), 1.5)
		_crack_count += 1
		queue_redraw()
	Fx.puff(get_parent(), at, -d, 10, 9.0, 0.5 + 0.2 * size_class)
	Fx.sound(get_parent(), at, "rock_crack_%d.wav" % (1 + _crack_count % 2), -6.0, 1.25 - 0.15 * size_class)


func _shatter(d: Vector2) -> void:
	_dead = true
	var host := get_parent()
	var rng := RandomNumberGenerator.new()
	rng.seed = rock_seed * 7919 + 13
	var r := radius_m() * PX
	var frags: Array[RigidBody2D] = []
	if size_class > 0 and host:
		var n := 2 + (rng.randi() % 2)
		var a0 := rng.randf() * TAU
		for i in n:
			var out := Vector2.from_angle(a0 + TAU * float(i) / float(n) + rng.randf_range(-0.25, 0.25))
			var f := Asteroid.new()
			f.setup(size_class - 1, rock_seed * 31 + i + 1, false)
			f.name = "%s_%d" % [name, i]
			f.home = home
			f.tint = tint
			f.position = position + out * r * 0.55
			f.rotation = rng.randf() * TAU
			f.linear_velocity = linear_velocity + (out * rng.randf_range(2.0, 4.5) + d * 0.8) * PX
			f.angular_velocity = rng.randf_range(-0.8, 0.8)
			frags.append(f)
	if host:
		# Deferred: a shot may land from inside a physics callback.
		for f in frags:
			host.add_child.call_deferred(f)
		if ore:
			var box := Fx.canister(rock_seed, frags)
			box.name = "Ore_%s" % name
			box.position = position
			box.rotation = rng.randf() * TAU
			box.linear_velocity = linear_velocity + d * 1.5 * PX
			box.angular_velocity = rng.randf_range(-0.5, 0.5)
			host.add_child.call_deferred(box)
	Fx.puff(host, global_position, Vector2.ZERO, 14 + 10 * size_class, 7.0 + 3.0 * size_class, 0.7 + 0.5 * size_class)
	Fx.sound(host, global_position, "rock_shatter.wav", -3.0 + 2.0 * size_class, 1.3 - 0.2 * size_class)
	if _game:
		_game.target_destroyed.emit("asteroid")
	queue_free()


# ================================================================== physics

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	var pre := prev_velocity
	var pre2 := prev_velocity2
	prev_velocity2 = prev_velocity
	prev_velocity = state.linear_velocity
	_age += state.step
	_report_impacts(state, pre, pre2)
	_keep_station(state)


func _report_impacts(state: PhysicsDirectBodyState2D, pre: Vector2, pre2: Vector2) -> void:
	var n := state.get_contact_count()
	if n == 0 or _game == null:
		if not _touching.is_empty():
			_touching.clear()
		return
	var now := Time.get_ticks_msec()
	var quiet := _age < GRACE_S
	var seen := {}
	for i in n:
		var other := state.get_contact_collider_object(i)
		if other == null:
			continue
		var oid := other.get_instance_id()
		seen[oid] = true
		if _touching.has(oid) or quiet:
			continue
		var on := other as Node
		if other == _game.player or (on and on.is_in_group(&"player_ship")):
			continue
		if other is RigidBody2D:
			# A container reports every contact it has with a non-container,
			# so that one is its to report. Rock on rock: the lower id reports.
			if on.is_in_group(&"cargo_container") or (on.is_in_group(&"asteroid") and oid < get_instance_id()):
				continue
		if now - int(_cooldown.get(oid, -100000)) < COOLDOWN_MS:
			continue
		var normal := state.get_contact_local_normal(i)
		# Contacts can surface a step after the solver absorbed part of the
		# hit, so measure with the larger of the two previous steps.
		var other_v := state.get_contact_collider_velocity_at_position(i)
		var other_v2 := other_v
		if other is RigidBody2D and "prev_velocity" in other:
			other_v = other.prev_velocity
			other_v2 = other.prev_velocity2
		var speed := maxf(absf((pre - other_v).dot(normal)), absf((pre2 - other_v2).dot(normal))) / PX
		if speed < MIN_IMPACT_MPS:
			continue
		_cooldown[oid] = now
		_game.impact.emit(state.get_contact_local_position(i), normal, speed, self, other)
	_touching = seen


func _keep_station(state: PhysicsDirectBodyState2D) -> void:
	var dt := state.step
	var v := state.linear_velocity
	if home.is_finite():
		var w := TAU / TETHER_PERIOD_S
		v += ((home - state.transform.origin) * w * w).limit_length(TETHER_MAX_ACC * PX) * dt
	var sp := v.length()
	var cruise := CRUISE_MPS * PX
	if sp > cruise:
		v *= 1.0 - (sp - cruise) / sp * minf(SETTLE * dt, 1.0)
	state.linear_velocity = v
	var spin := state.angular_velocity
	if absf(spin) > TUMBLE_MAX:
		state.angular_velocity = spin - signf(spin) * (absf(spin) - TUMBLE_MAX) * minf(SETTLE * dt, 1.0)
