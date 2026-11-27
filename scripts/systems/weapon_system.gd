class_name WeaponSystem
extends Node2D
## Flies every weapon bolt in the game and decides what a hit does.
##
## Bolts are plain data in fixed-size arrays (no node per shot). Each physics
## tick a bolt casts a ray from where it was to where it will be, so it can't
## tunnel through a thin wall at 260 m/s. All bolts are drawn by two
## MultiMeshes (body + additive halo): two draw calls however many are flying.
##
## Hit protocol, in this order (see docs/CONTRACT.md "Weapons"):
##   1. hit FX and a positional sound, always;
##   2. `collider.take_shot(damage, at, dir, shooter)` if it has that method;
##   3. else a free prop (RigidBody2D on LAYER_PROPS) gets a small shove;
##   4. else another ship (group player_ship, not the shooter) takes a scratch;
##   5. structure and traffic: FX only;
## then `Game.shot_hit(pos, normal, collider, shooter)`.

const G := preload("res://scripts/autoload/game.gd")
const PX := G.PX_PER_M
const BOLT_SPEED_MPS := 260.0
const BOLT_RANGE_M := 500.0
## Damage handed to take_shot() per bolt.
const BOLT_DAMAGE := 10.0
## Hull points a bolt scratches off another (parked) ship.
const SHIP_SCRATCH := 1.5
## ... down to this fraction of its hull and no further: stray fire scuffs a
## parked ship, it must not be able to destroy the one you came in.
const SCRATCH_FLOOR := 0.5
## Shove given to a free prop, N·s. A 1.8 t container gains 0.22 m/s per bolt:
## a burst visibly sets it drifting, a single shot barely moves it.
const PROP_IMPULSE_NS := 400.0
## ... but never more than this speed change, so light debris isn't launched.
const PROP_MAX_DV_MPS := 2.0
const MAX_BOLTS := 64
## A bolt at the end of its range fades out over this long.
const FADE_S := 0.14
const HIT_MASK := G.LAYER_WORLD | G.LAYER_PROPS | G.LAYER_TRAFFIC

const BODY_SIZE := Vector2(54.0, 10.0)      # px: a 5.4 m dart
const HALO_SIZE := Vector2(150.0, 40.0)
const HALO_COLOR := Color(1.0, 0.5, 0.16)

## Bolts fired / bolts that hit something since the session started (tests).
var shots_fired := 0
var shots_hit := 0

var _pos := PackedVector2Array()
var _prev := PackedVector2Array()        # last tick's position (render interpolation)
var _vel := PackedVector2Array()         # px/s, includes the shooter's velocity
var _dir := PackedVector2Array()         # unit, where the bolt points
var _life := PackedFloat32Array()        # s of flight left; <= 0 = free slot
var _fade := PackedFloat32Array()        # s of fade left, or -1 while flying
var _age := PackedFloat32Array()         # s since it was fired
var _shooter: Array[Node] = []
var _exclude: Array = []                 # per bolt: Array[RID] the ray skips
var _next := 0
var _live := 0

var _body: MultiMesh
var _halo: MultiMesh
var _fx: WeaponHitFx
var _ray := PhysicsRayQueryParameters2D.new()


func _ready() -> void:
	add_to_group(&"weapon_system")
	z_as_relative = false
	z_index = Game.Z_FX
	_pos.resize(MAX_BOLTS)
	_prev.resize(MAX_BOLTS)
	_vel.resize(MAX_BOLTS)
	_dir.resize(MAX_BOLTS)
	_life.resize(MAX_BOLTS)
	_fade.resize(MAX_BOLTS)
	_age.resize(MAX_BOLTS)
	_shooter.resize(MAX_BOLTS)
	_exclude.resize(MAX_BOLTS)
	var none: Array[RID] = []
	for i in MAX_BOLTS:
		_life[i] = 0.0
		_exclude[i] = none
	_ray.collision_mask = HIT_MASK
	_ray.collide_with_areas = false
	# A muzzle pressed into a wall must not shoot through it.
	_ray.hit_from_inside = true
	_halo = _make_layer(WeaponTextures.streak(), true)
	_body = _make_layer(WeaponTextures.bolt(), false)
	_fx = WeaponHitFx.new()
	_fx.name = "HitFx"
	add_child(_fx)


func _make_layer(tex: Texture2D, additive: bool) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.mesh = WeaponTextures.quad()
	mm.instance_count = MAX_BOLTS
	mm.visible_instance_count = 0
	# Bolts are anywhere in the world: never cull the batch by a stale box.
	mm.custom_aabb = AABB(Vector3(-1e6, -1e6, -1.0), Vector3(2e6, 2e6, 2.0))
	var node := MultiMeshInstance2D.new()
	node.multimesh = mm
	node.texture = tex
	node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if additive:
		node.material = FxTextures.additive()
	add_child(node)
	return mm


## Launch one bolt. `inherit_velocity` (px/s) is the shooter's own velocity at
## the muzzle: in vacuum the bolt keeps it.
func fire(origin: Vector2, dir: Vector2, inherit_velocity: Vector2, shooter: Node) -> void:
	if dir.length_squared() < 0.0001:
		return
	var d := dir.normalized()
	var i := _free_slot()
	if _life[i] <= 0.0:
		_live += 1
	_pos[i] = origin
	# Rendering interpolates prev -> pos; on its first frame the bolt should
	# sit at the muzzle and ride with the ship, not appear to fly backwards.
	_prev[i] = origin - inherit_velocity * get_physics_process_delta_time()
	_vel[i] = d * BOLT_SPEED_MPS * PX + inherit_velocity
	_dir[i] = d
	_life[i] = BOLT_RANGE_M / BOLT_SPEED_MPS
	_fade[i] = -1.0
	_age[i] = 0.0
	_shooter[i] = shooter
	var ex: Array[RID] = []
	if shooter is CollisionObject2D:
		ex.append((shooter as CollisionObject2D).get_rid())
	_exclude[i] = ex
	shots_fired += 1


func live_bolts() -> int:
	return _live


## Position of the most recently fired bolt that is still flying (tests).
func newest_bolt_position() -> Vector2:
	var i := posmod(_next - 1, MAX_BOLTS)
	return _pos[i] if _life[i] > 0.0 else Vector2.INF


func _free_slot() -> int:
	for k in MAX_BOLTS:
		var i := (_next + k) % MAX_BOLTS
		if _life[i] <= 0.0:
			_next = (i + 1) % MAX_BOLTS
			return i
	# Full: recycle the oldest.
	var j := _next
	_next = (_next + 1) % MAX_BOLTS
	return j


func _physics_process(delta: float) -> void:
	if _live <= 0:
		return
	var space := get_world_2d().direct_space_state
	for i in MAX_BOLTS:
		if _life[i] <= 0.0:
			continue
		var from := _pos[i]
		var to := from + _vel[i] * delta
		if _fade[i] >= 0.0:
			# Spent: no longer dangerous, just gliding out.
			_fade[i] -= delta
			if _fade[i] <= 0.0:
				_kill(i)
				continue
		else:
			_ray.from = from
			_ray.to = to
			_ray.exclude = _exclude[i]
			var hit := space.intersect_ray(_ray)
			if not hit.is_empty():
				_on_hit(i, hit)
				_kill(i)
				continue
			_life[i] -= delta
			if _life[i] <= 0.0:
				_life[i] = FADE_S     # keeps the slot until the fade ends
				_fade[i] = FADE_S
		_prev[i] = from
		_pos[i] = to
		_age[i] += delta


func _kill(i: int) -> void:
	_life[i] = 0.0
	_fade[i] = -1.0
	_shooter[i] = null
	_live -= 1


func _on_hit(i: int, hit: Dictionary) -> void:
	var pos: Vector2 = hit.position
	var dir := _dir[i]
	var normal: Vector2 = hit.normal
	# Started inside the shape (hit_from_inside): no surface normal.
	if normal.length_squared() < 0.25:
		normal = -dir
	var collider := hit.collider as Node
	var shooter := _shooter[i] if is_instance_valid(_shooter[i]) else null
	shots_hit += 1
	_fx.hit(pos, normal, dir, collider)
	if collider == null:
		return
	if collider.has_method(&"take_shot"):
		collider.call(&"take_shot", BOLT_DAMAGE, pos, dir, shooter)
	elif collider is RigidBody2D and ((collider as RigidBody2D).collision_layer & Game.LAYER_PROPS) != 0:
		_shove(collider as RigidBody2D, pos, dir)
	elif collider.has_method(&"take_damage") and collider.is_in_group(&"player_ship") and collider != shooter:
		_scratch(collider, pos)
	if is_instance_valid(collider):
		Game.shot_hit.emit(pos, normal, collider, shooter)


func _scratch(ship: Node, pos: Vector2) -> void:
	if ship == Game.player:
		ship.call(&"take_damage", SHIP_SCRATCH, pos)     # somebody shot YOU: the full treatment
		return
	var hull := float(GameplayUtil.pget(ship, &"hull", 0.0))
	if hull - SHIP_SCRATCH < float(GameplayUtil.pget(ship, &"max_hull", 100.0)) * SCRATCH_FLOOR:
		return
	# take_damage() announces the hull on Game.hull_changed, which the HUD, the
	# damage vignette and the hull alarm all read as the hull of the ship you
	# fly. This is another ship's hull, so keep it off the bus (the ship's own
	# signals, like the frigate's shield ripple, still fire).
	var was_blocked := Game.is_blocking_signals()
	Game.set_block_signals(true)
	ship.call(&"take_damage", SHIP_SCRATCH, pos)
	Game.set_block_signals(was_blocked)


func _shove(body: RigidBody2D, pos: Vector2, dir: Vector2) -> void:
	var j := minf(PROP_IMPULSE_NS, body.mass * PROP_MAX_DV_MPS)
	body.sleeping = false
	body.apply_impulse(dir * j * PX, pos - body.global_position)


func _process(_delta: float) -> void:
	if _live <= 0:
		if _body.visible_instance_count != 0:
			_body.visible_instance_count = 0
			_halo.visible_instance_count = 0
		return
	var f := clampf(Engine.get_physics_interpolation_fraction(), 0.0, 1.0)
	var dt := get_physics_process_delta_time()
	var n := 0
	for i in MAX_BOLTS:
		if _life[i] <= 0.0:
			continue
		var a := 1.0 if _fade[i] < 0.0 else clampf(_fade[i] / FADE_S, 0.0, 1.0)
		var p := _prev[i].lerp(_pos[i], f)
		var x := _dir[i]
		var y := Vector2(-x.y, x.x)
		# A bolt grows out of the muzzle: its tail never reaches back past
		# where it was fired (it would be drawn across the shooter's hull).
		var grown := clampf((_age[i] - dt + f * dt) * BOLT_SPEED_MPS * PX / BODY_SIZE.x, 0.0, 1.0)
		var body_len := BODY_SIZE.x * grown
		# The texture's nose is its +X edge: put the nose at p, the tail behind.
		_body.set_instance_transform_2d(n, Transform2D(x * body_len, y * BODY_SIZE.y, p - x * body_len * 0.5))
		_body.set_instance_color(n, Color(1, 1, 1, a))
		_halo.set_instance_transform_2d(n, Transform2D(x * HALO_SIZE.x * grown, y * HALO_SIZE.y, p - x * body_len * 0.5))
		_halo.set_instance_color(n, Color(HALO_COLOR, 0.9 * a))
		n += 1
	_body.visible_instance_count = n
	_halo.visible_instance_count = n
