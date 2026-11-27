class_name TargetDrone
extends RigidBody2D
## A gunnery-range target: a small hovering drone that holds station on a
## spring, drifts along a gentle pattern and takes two bolts to kill. The first
## hit staggers it (it rocks back on its spring and its ring goes red), the
## second bursts it. It comes back with a shimmer a few seconds later.
##
## A light free body on LAYER_PROPS, so bolts hit it and the ship can bump it
## aside (it springs back). It never reports contacts: the player reports its
## own, and nothing else needs a drone's.
##
## Implements the weapon hit protocol: take_shot(damage, at, dir, shooter).

## A drone was hit. `destroyed` = that hit killed it.
signal shot(drone: TargetDrone, destroyed: bool)

const G := preload("res://scripts/autoload/game.gd")
const PX := 10.0
const ART := preload("res://assets/art/level/target_drone.svg")
const ART_HIT := preload("res://assets/art/level/target_drone_hit.svg")
const RADIUS_M := 2.4
const MASS_KG := 140.0
## Station-keeping spring (rad/s) and damping ratio: under-damped on purpose,
## so a hit drone visibly rocks back and swings home.
const HOLD_OMEGA := 3.2
const HOLD_ZETA := 0.45
## Push from a bolt, N·s: about 3.5 m/s on 140 kg, a 1 m lurch.
const STAGGER_NS := 480.0
## The shell is held level by a second, softer spring: an off-centre hit
## makes it rock.
const LEVEL_OMEGA := 5.0
const LEVEL_ZETA := 0.3
const C_IDLE := Color(1.0, 0.72, 0.2)
const C_HURT := Color(1.0, 0.25, 0.18)
const C_SHIMMER := Color(0.5, 0.92, 1.0)

@export var max_health := 20.0          # two bolts (WeaponSystem.BOLT_DAMAGE = 10)
@export var respawn_s := 6.0
## Centre of its patrol, global px (set by the range before it enters the tree).
var home := Vector2.ZERO
## Patrol: half-extents in metres, seconds per lap, and where on the lap it starts.
var sway_m := Vector2(6.0, 3.0)
var period_s := 9.0
var phase := 0.0
## 0 = side to side, 1 = circle, 2 = figure of eight.
var pattern := 0

var alive := true
var health := 20.0

var _t := 0.0
var _respawn := 0.0
var _flash := 0.0
var _art: Node2D
var _hit_art: Sprite2D
var _glow: Sprite2D
var _flash_sprite: Sprite2D
var _ring: Sprite2D
var _burst: Sprite2D
var _sparks: CPUParticles2D
var _shards: CPUParticles2D
var _pop_sound: AudioStreamPlayer2D
var _tween: Tween


func _ready() -> void:
	collision_layer = G.LAYER_PROPS
	collision_mask = G.LAYER_WORLD | G.LAYER_PLAYER | G.LAYER_PROPS | G.LAYER_TRAFFIC
	mass = MASS_KG
	inertia = 0.5 * MASS_KG * RADIUS_M * RADIUS_M * PX * PX     # a solid disc
	gravity_scale = 0.0
	can_sleep = false                   # the spring has to keep working
	linear_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp = 0.0
	var mat := PhysicsMaterial.new()
	mat.bounce = 0.2
	mat.friction = 0.3
	physics_material_override = mat
	var cs := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = RADIUS_M * PX
	cs.shape = circle
	add_child(cs)
	z_as_relative = false
	z_index = G.Z_PROPS
	add_to_group(&"target_drone")
	add_to_group(&"radar_prop")
	health = max_health
	_build_art()
	global_position = _anchor()


func _build_art() -> void:
	# Soft halo behind the shell: what you spot first against black space.
	_glow = _sprite(FxTextures.glow(), true, self)
	_glow.z_index = -1
	_glow.scale = Vector2.ONE * (110.0 / 128.0)
	_art = Node2D.new()
	add_child(_art)
	var body := _sprite(ART, false, _art)
	body.scale = Vector2.ONE / 6.0      # imported at 6x, like the ship art
	_hit_art = _sprite(ART_HIT, false, _art)
	_hit_art.scale = Vector2.ONE / 6.0
	_hit_art.visible = false
	# FX draw above ships and are not children of _art: they outlive the shell.
	_flash_sprite = _fx_sprite(FxTextures.hot_core())
	_ring = _fx_sprite(FxTextures.ring())
	_burst = _fx_sprite(FxTextures.glow())
	_sparks = _emitter(FxTextures.spark(), 34, 0.5, true)
	_sparks.particle_flag_align_y = true
	_sparks.initial_velocity_min = 120.0
	_sparks.initial_velocity_max = 520.0
	_sparks.damping_min = 250.0
	_sparks.damping_max = 600.0
	_sparks.scale_amount_min = 0.5
	_sparks.scale_amount_max = 1.2
	_sparks.color_ramp = FxTextures.spark_ramp()
	# Shell fragments: pearl chips that tumble away and fade.
	_shards = _emitter(FxTextures.chunk(), 16, 1.1, false)
	_shards.initial_velocity_min = 60.0
	_shards.initial_velocity_max = 300.0
	_shards.damping_min = 30.0
	_shards.damping_max = 120.0
	_shards.angle_max = 360.0
	_shards.angular_velocity_min = -600.0
	_shards.angular_velocity_max = 600.0
	_shards.scale_amount_min = 0.5
	_shards.scale_amount_max = 1.5
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.15, 0.7, 1.0])
	ramp.colors = PackedColorArray([Color(1, 0.95, 0.8), Color(0.93, 0.95, 0.97), Color(0.75, 0.8, 0.86, 0.9), Color(0.6, 0.65, 0.72, 0.0)])
	_shards.color_ramp = ramp
	var pop := GameplayUtil.load_audio("drone_pop.wav")
	if pop != null:
		_pop_sound = AudioStreamPlayer2D.new()
		_pop_sound.stream = pop
		_pop_sound.bus = GameplayUtil.bus(&"SFX")
		_pop_sound.max_distance = 3000.0
		_pop_sound.attenuation = 1.4
		add_child(_pop_sound)


func _sprite(tex: Texture2D, additive: bool, parent: Node) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex
	s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if additive:
		s.material = FxTextures.additive()
	parent.add_child(s)
	return s


func _fx_sprite(tex: Texture2D) -> Sprite2D:
	var s := _sprite(tex, true, self)
	s.z_as_relative = false
	s.z_index = G.Z_FX
	s.visible = false
	return s


func _emitter(tex: Texture2D, amount: int, lifetime: float, additive: bool) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = amount
	p.lifetime = lifetime
	p.explosiveness = 0.96
	p.lifetime_randomness = 0.5
	p.local_coords = false
	p.texture = tex
	if additive:
		p.material = FxTextures.additive()
	p.gravity = Vector2.ZERO
	p.spread = 180.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = RADIUS_M * PX * 0.5
	p.scale_amount_curve = FxTextures.shrink_curve()
	p.z_as_relative = false
	p.z_index = G.Z_FX
	add_child(p)
	return p


# ------------------------------------------------------------- station --
## Where the drone wants to be right now (global px).
func _anchor() -> Vector2:
	var a := TAU * (_t / period_s + phase)
	var off := Vector2(sin(a), 0.0)
	match pattern:
		1: off = Vector2(cos(a), sin(a))
		2: off = Vector2(sin(a), sin(a * 2.0))
	return home + off * sway_m * PX


func _physics_process(delta: float) -> void:
	_t += delta
	if not alive:
		_respawn -= delta
		if _respawn <= 0.0:
			_come_back()
		return
	# Spring to the moving anchor (see HOLD_*: under-damped on purpose).
	var k := HOLD_OMEGA * HOLD_OMEGA
	var c := 2.0 * HOLD_ZETA * HOLD_OMEGA
	apply_central_force(mass * ((_anchor() - global_position) * k - linear_velocity * c))
	apply_torque(inertia * (-LEVEL_OMEGA * LEVEL_OMEGA * angle_difference(0.0, rotation)
		- 2.0 * LEVEL_ZETA * LEVEL_OMEGA * angular_velocity))


func _process(delta: float) -> void:
	if not alive:
		return
	_flash = maxf(_flash - delta * 5.0, 0.0)
	var hurt := health < max_health
	# Idle: a slow amber breath. Hurt: a quick red flicker ("one more").
	var pulse := 0.5 + 0.5 * sin(_t * (16.0 if hurt else 2.2) + phase * TAU)
	_glow.modulate = Color(C_HURT if hurt else C_IDLE, (0.32 + 0.3 * pulse) if hurt else (0.2 + 0.1 * pulse))
	_flash_sprite.visible = _flash > 0.01
	if _flash_sprite.visible:
		_flash_sprite.modulate = Color(1.0, 0.95, 0.85, _flash)
		_flash_sprite.scale = Vector2.ONE * (0.7 + 0.5 * _flash)


# ---------------------------------------------------------------- shots --
## Weapon hit protocol (WeaponSystem calls this instead of its default effect).
func take_shot(damage: float, at: Vector2, dir: Vector2, _shooter: Node) -> void:
	if not alive:
		return
	health -= damage
	_flash = 1.0
	if health <= 0.0:
		_burst_apart(dir)
	else:
		_hit_art.visible = true
		# Lurch back on the spring; an off-centre hit also rocks the shell.
		apply_impulse(dir * STAGGER_NS * PX, at - global_position)
	shot.emit(self, not alive)


func _burst_apart(dir: Vector2) -> void:
	alive = false
	_respawn = respawn_s
	_art.visible = false
	_glow.visible = false
	_flash_sprite.visible = false
	remove_from_group(&"radar_prop")
	# Out of the simulation until it respawns (deferred: we are usually inside
	# the physics tick that delivered the bolt).
	collision_layer = 0
	collision_mask = 0
	set_deferred(&"freeze", true)
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	for p: CPUParticles2D in [_sparks, _shards]:
		# Mostly thrown onward by the bolt, some of it back toward the gun.
		p.direction = dir
		p.restart()
		p.emitting = true
	_pop(_burst, 0.5, 1.5, 0.22, Color(1.0, 0.75, 0.4))
	_pop(_ring, 0.12, 0.62, 0.34, Color(1.0, 0.9, 0.7, 0.9))
	if _pop_sound:
		_pop_sound.pitch_scale = randf_range(0.94, 1.08)
		_pop_sound.play()
	Game.target_destroyed.emit("drone")


func _come_back() -> void:
	alive = true
	health = max_health
	_hit_art.visible = false
	global_position = _anchor()
	rotation = 0.0
	collision_layer = G.LAYER_PROPS
	collision_mask = G.LAYER_WORLD | G.LAYER_PLAYER | G.LAYER_PROPS | G.LAYER_TRAFFIC
	set_deferred(&"freeze", false)
	add_to_group(&"radar_prop")
	# Shimmer: a cyan ring closes on the spot and the shell swells into place.
	_art.visible = true
	_art.scale = Vector2.ONE * 0.2
	_art.modulate = Color(1.6, 2.2, 2.4, 0.0)
	_glow.visible = true
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_art, ^"scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_art, ^"modulate", Color.WHITE, 0.6)
	_pop(_ring, 0.7, 0.16, 0.5, Color(C_SHIMMER, 0.9))
	_pop(_burst, 1.1, 0.5, 0.5, Color(C_SHIMMER, 0.55))


## One-shot sprite: scale from/to (texture scale), fading out over `dur`.
func _pop(s: Sprite2D, from: float, to: float, dur: float, col: Color) -> void:
	if s.has_meta(&"tw"):
		var old: Variant = s.get_meta(&"tw")
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()
	s.scale = Vector2.ONE * from
	s.modulate = col
	s.visible = true
	var tw := s.create_tween().set_parallel(true)
	tw.tween_property(s, ^"scale", Vector2.ONE * to, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(s, ^"modulate:a", 0.0, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(s.hide)
	s.set_meta(&"tw", tw)
