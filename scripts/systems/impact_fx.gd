class_name ImpactFX
extends Node2D
## Turns Game.impact / Game.scrape events into sparks, flashes, debris,
## shockwaves, scorch decals, camera shake, hit-stop and sound.
##
## Everything is pooled and created up front so a collision never allocates
## nodes: emitters are re-armed with restart(), sprites are re-tweened.
## Effects scale with three speed tiers (closing speed along the normal):
##   light < 3 m/s  ·  medium 3–10 m/s  ·  heavy > 10 m/s

enum Tier { LIGHT, MEDIUM, HEAVY }

const LIGHT_MAX := 3.0
const MEDIUM_MAX := 10.0
const MIN_SPEED := 0.6           ## below this an impact is ignored entirely
const DECAL_MAX := 90
const DECAL_LIFETIME := 20.0
const SCRAPE_RELEASE := 0.1      ## s for the scrape loop to fall silent
const SCRAPE_ATTACK := 0.02
const SCRAPE_DECAL_SPACING_M := 1.4

var _pools := {}                 # name -> {"nodes": Array, "i": int}
var _decals: Array[Sprite2D] = []
var _decal_i := 0

# audio
var _snd_light: AudioStream
var _snd_medium: AudioStream
var _snd_heavy: AudioStream
var _snd_clunk: AudioStream
var _snd_rattle: AudioStream
var _ui_players: Array[AudioStreamPlayer] = []
var _pos_players: Array[AudioStreamPlayer2D] = []
var _ui_i := 0
var _pos_i := 0
var _sound_budget := 0.0         # simple limiter: sounds per short window

# scrape state
var _scrape_player: AudioStreamPlayer
var _scrape_emitter: CPUParticles2D
var _scrape_glow: Sprite2D
var _scrape_amp := 0.0
var _scrape_target := 0.0
var _scrape_last_ms := -100000
var _scrape_pos := Vector2.ZERO
var _scrape_dir := Vector2.RIGHT
var _scrape_normal := Vector2.UP
var _scrape_speed := 0.0
var _scrape_dist_accum := 0.0

var _hitstop_active := false

func _ready() -> void:
	add_to_group(&"impact_fx")
	z_as_relative = false
	z_index = Game.Z_FX
	_build_pools()
	_load_audio()
	Game.impact.connect(_on_impact)
	Game.scrape.connect(_on_scrape)

# ================================================================ setup ===
func _build_pools() -> void:
	# Spark sprays: amount differs per tier, so each tier has its own pool.
	_make_pool("spark_light", 8, func() -> Node: return _make_sparks(10, 0.32))
	_make_pool("spark_medium", 8, func() -> Node: return _make_sparks(26, 0.45))
	_make_pool("spark_heavy", 6, func() -> Node: return _make_sparks(60, 0.6))
	_make_pool("debris", 4, _make_debris)
	_make_pool("smoke", 4, _make_smoke)
	_make_pool("flash", 10, func() -> Node: return _make_sprite(FxTextures.glow(), true))
	_make_pool("core", 10, func() -> Node: return _make_sprite(FxTextures.hot_core(), true))
	_make_pool("ring", 4, func() -> Node: return _make_sprite(FxTextures.ring(), true))

	_scrape_emitter = _make_sparks(140, 0.5)
	_scrape_emitter.one_shot = false
	_scrape_emitter.explosiveness = 0.0
	_scrape_emitter.spread = 30.0
	_scrape_emitter.scale_amount_min = 0.6
	_scrape_emitter.scale_amount_max = 1.4
	_scrape_glow = _make_sprite(FxTextures.glow(), true)
	_scrape_glow.modulate = Color(1.0, 0.75, 0.4, 0.0)

func _make_pool(pool_name: String, count: int, factory: Callable) -> void:
	var nodes: Array = []
	for i in count:
		nodes.append(factory.call())
	_pools[pool_name] = {"nodes": nodes, "i": 0}

func _take(pool_name: String) -> Node:
	var pool: Dictionary = _pools[pool_name]
	var nodes: Array = pool["nodes"]
	var n: Node = nodes[pool["i"]]
	pool["i"] = (int(pool["i"]) + 1) % nodes.size()
	return n

func _make_sparks(amount: int, lifetime: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = amount
	p.lifetime = lifetime
	p.explosiveness = 0.92
	p.randomness = 0.4
	p.lifetime_randomness = 0.6
	p.local_coords = false
	p.texture = FxTextures.spark()
	p.material = FxTextures.additive()
	p.particle_flag_align_y = true
	p.gravity = Vector2.ZERO
	p.spread = 40.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 3.0
	p.initial_velocity_min = 100.0
	p.initial_velocity_max = 400.0
	p.damping_min = 250.0
	p.damping_max = 650.0
	p.scale_amount_min = 0.45
	p.scale_amount_max = 1.1
	p.scale_amount_curve = FxTextures.shrink_curve()
	p.color_ramp = FxTextures.spark_ramp()
	add_child(p)
	return p

func _make_debris() -> Node:
	var p := CPUParticles2D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = 16
	p.lifetime = 1.5
	p.explosiveness = 0.95
	p.lifetime_randomness = 0.5
	p.local_coords = false
	p.texture = FxTextures.chunk()
	p.material = FxTextures.additive()
	p.gravity = Vector2.ZERO
	p.spread = 70.0
	p.initial_velocity_min = 60.0
	p.initial_velocity_max = 300.0
	p.damping_min = 40.0
	p.damping_max = 140.0
	p.angular_velocity_min = -720.0
	p.angular_velocity_max = 720.0
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.3
	p.scale_amount_curve = FxTextures.shrink_curve()
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.2, 0.7, 1.0])
	g.colors = PackedColorArray([Color(1, 0.95, 0.8, 1), Color(1, 0.65, 0.25, 1),
		Color(0.85, 0.25, 0.05, 0.7), Color(0.4, 0.08, 0.02, 0)])
	p.color_ramp = g
	add_child(p)
	return p

func _make_smoke() -> Node:
	var p := CPUParticles2D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = 10
	p.lifetime = 1.8
	p.explosiveness = 0.85
	p.lifetime_randomness = 0.4
	p.local_coords = false
	p.texture = FxTextures.smoke()
	p.gravity = Vector2.ZERO
	p.spread = 80.0
	p.initial_velocity_min = 15.0
	p.initial_velocity_max = 80.0
	p.damping_min = 30.0
	p.damping_max = 60.0
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.angular_velocity_min = -40.0
	p.angular_velocity_max = 40.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	p.scale_amount_curve = FxTextures.grow_curve()
	p.color_ramp = FxTextures.smoke_ramp()
	add_child(p)
	return p

func _make_sprite(tex: Texture2D, additive: bool) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex
	if additive:
		s.material = FxTextures.additive()
	s.visible = false
	add_child(s)
	return s

func _load_audio() -> void:
	_snd_light = GameplayUtil.load_variations("impact_light_", 4, 1.1, 2.0)
	_snd_medium = GameplayUtil.load_variations("impact_medium_", 3, 1.08, 2.0)
	_snd_heavy = GameplayUtil.load_variations("impact_heavy_", 3, 1.06, 1.5)
	_snd_clunk = GameplayUtil.load_variations("container_clunk_", 3, 1.1, 2.0)
	_snd_rattle = GameplayUtil.load_audio("debris_rattle.wav")
	var sfx := GameplayUtil.bus(&"SFX")
	for i in 8:
		var a := AudioStreamPlayer.new()
		a.bus = sfx
		add_child(a)
		_ui_players.append(a)
	for i in 10:
		var b := AudioStreamPlayer2D.new()
		b.bus = sfx
		b.max_distance = 2600.0
		b.attenuation = 1.6
		b.panning_strength = 1.2
		add_child(b)
		_pos_players.append(b)
	_scrape_player = AudioStreamPlayer.new()
	_scrape_player.bus = sfx
	_scrape_player.stream = GameplayUtil.load_loop("scrape_loop.wav")
	_scrape_player.volume_db = -80.0
	add_child(_scrape_player)

# =============================================================== impact ===
func _on_impact(pos: Vector2, normal: Vector2, speed_mps: float, source: Node, other: Node) -> void:
	if speed_mps < MIN_SPEED or not is_finite(pos.x):
		return
	var player_hit := _is_player(source) or _is_player(other)
	var n := _orient_normal(normal, pos, source)
	# Relative motion of the reporting body against the thing it hit gives
	# the tangent sparks get dragged along.
	var rel := _body_velocity(source) - _body_velocity(other)
	var tangent := rel - n * rel.dot(n)
	var tan_dir := tangent.normalized() if tangent.length_squared() > 1.0 else n.orthogonal()
	var glance := clampf(tangent.length() / maxf(rel.length(), 1.0), 0.0, 1.0)
	var tier := _tier(speed_mps)
	var t := _tier_t(tier, speed_mps)
	var prop_involved := _is_prop(source) or _is_prop(other)

	_emit_sparks(tier, pos, n, tan_dir, glance, speed_mps)
	_flash(tier, t, pos)
	if tier == Tier.HEAVY:
		_heavy_extras(pos, n, t)
	var surface := other if not _is_player(other) else source
	if tier != Tier.LIGHT or speed_mps > 2.0:
		_place_decal_deferred(surface, pos, n, tan_dir, glance, tier, t)
	_impact_sound(tier, t, speed_mps, pos, player_hit, prop_involved)
	if player_hit:
		_camera_feedback(tier, t, speed_mps, n)

func _tier(speed: float) -> Tier:
	if speed < LIGHT_MAX:
		return Tier.LIGHT
	if speed < MEDIUM_MAX:
		return Tier.MEDIUM
	return Tier.HEAVY

## 0..1 position of `speed` inside its tier (drives intensity within a tier).
func _tier_t(tier: Tier, speed: float) -> float:
	match tier:
		Tier.LIGHT:
			return clampf(inverse_lerp(MIN_SPEED, LIGHT_MAX, speed), 0.0, 1.0)
		Tier.MEDIUM:
			return clampf(inverse_lerp(LIGHT_MAX, MEDIUM_MAX, speed), 0.0, 1.0)
	return clampf(inverse_lerp(MEDIUM_MAX, 35.0, speed), 0.0, 1.0)

func _emit_sparks(tier: Tier, pos: Vector2, n: Vector2, tan_dir: Vector2, glance: float, speed: float) -> void:
	var pool := "spark_light"
	var v_scale := 1.0
	match tier:
		Tier.MEDIUM:
			pool = "spark_medium"
			v_scale = 1.6
		Tier.HEAVY:
			pool = "spark_heavy"
			v_scale = 2.4
	# Spray 1: head-on hits splash out around the normal; glancing hits drag
	# the sparks along the surface in the direction of motion.
	var along := (n * (1.3 - glance) + tan_dir * glance * 1.6).normalized()
	var p1 := _take(pool) as CPUParticles2D
	_fire(p1, pos, along, lerpf(80.0, 26.0, glance), v_scale, speed)
	# Spray 2 (medium/heavy): the "reflected" splash straight off the surface.
	if tier != Tier.LIGHT:
		var p2 := _take(pool) as CPUParticles2D
		_fire(p2, pos, (n + tan_dir * 0.25).normalized(), 70.0, v_scale * 0.7, speed)

func _fire(p: CPUParticles2D, pos: Vector2, dir: Vector2, spread: float, v_scale: float, speed: float) -> void:
	p.global_position = pos
	p.direction = dir
	p.spread = spread
	var sp := clampf(speed / 10.0, 0.4, 2.2)
	p.initial_velocity_min = 70.0 * v_scale * sp
	p.initial_velocity_max = 300.0 * v_scale * sp
	p.restart()
	p.emitting = true

func _flash(tier: Tier, t: float, pos: Vector2) -> void:
	var radius_px := 14.0
	var dur := 0.07
	var col := Color(1.0, 0.85, 0.6)
	match tier:
		Tier.MEDIUM:
			radius_px = lerpf(26.0, 46.0, t)
			dur = 0.1
		Tier.HEAVY:
			radius_px = lerpf(48.0, 85.0, t)
			dur = 0.14
			col = Color(1.0, 0.9, 0.75)
	var glow := _take("flash") as Sprite2D
	_pop_sprite(glow, pos, radius_px * 2.0 / 128.0, radius_px * 2.6 / 128.0, dur * 1.6, col)
	var core := _take("core") as Sprite2D
	_pop_sprite(core, pos, radius_px * 0.9 / 64.0, radius_px * 0.4 / 64.0, dur, Color(1, 1, 1))

func _heavy_extras(pos: Vector2, n: Vector2, t: float) -> void:
	var debris := _take("debris") as CPUParticles2D
	debris.global_position = pos
	debris.direction = n
	debris.initial_velocity_max = lerpf(220.0, 380.0, t)
	debris.restart()
	debris.emitting = true
	var smoke := _take("smoke") as CPUParticles2D
	smoke.global_position = pos + n * 8.0
	smoke.direction = n
	smoke.restart()
	smoke.emitting = true
	# Shockwave ring: thin, quick, cool-white.
	var ring := _take("ring") as Sprite2D
	var r_end := lerpf(140.0, 260.0, t)
	_pop_sprite(ring, pos, 20.0 / 128.0, r_end / 128.0, 0.32, Color(0.85, 0.95, 1.0, 0.85), Tween.EASE_OUT)

func _pop_sprite(s: Sprite2D, pos: Vector2, scale_from: float, scale_to: float, dur: float, col: Color, fade_ease := Tween.EASE_IN) -> void:
	_kill_tween(s)
	s.global_position = pos
	s.scale = Vector2.ONE * scale_from
	s.modulate = col
	s.visible = true
	var tw := s.create_tween().set_parallel(true)
	tw.tween_property(s, ^"scale", Vector2.ONE * scale_to, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(s, ^"modulate:a", 0.0, dur).set_trans(Tween.TRANS_QUAD).set_ease(fade_ease)
	tw.chain().tween_callback(s.hide)
	s.set_meta(&"tw", tw)

# =============================================================== decals ===
func _place_decal_deferred(surface: Node, pos: Vector2, n: Vector2, tan_dir: Vector2, glance: float, tier: Tier, t: float) -> void:
	var size_m := 1.0
	match tier:
		Tier.LIGHT:
			size_m = 1.2
		Tier.MEDIUM:
			size_m = lerpf(2.0, 3.2, t)
		Tier.HEAVY:
			size_m = lerpf(3.8, 6.0, t)
	var stretch := 1.0 + glance * 1.8
	var heat := 0.25 + 0.75 * (float(tier) / 2.0)
	# Deferred: impacts are often reported from inside the physics step and
	# re-parenting under a body there is not allowed.
	_place_decal.call_deferred(surface, pos, n, tan_dir, size_m, stretch, heat)

func _place_decal(surface: Node, pos: Vector2, n: Vector2, tan_dir: Vector2, size_m: float, stretch: float, heat: float) -> void:
	var parent: Node2D = null
	if surface != null and is_instance_valid(surface) and surface is CollisionObject2D and not _is_player(surface):
		parent = surface as Node2D
	else:
		parent = _structure_at(pos - n * 4.0)
	if parent == null:
		return
	var d := _next_decal()
	if d.get_parent() != parent:
		if d.get_parent():
			d.get_parent().remove_child(d)
		parent.add_child(d)
	d.z_index = _decal_z(parent)
	# Push the mark into the plating so it doesn't overhang into space;
	# flattened across the normal, stretched along the slide direction.
	var s := size_m * Game.PX_PER_M / 64.0
	d.global_position = pos - n * size_m * Game.PX_PER_M * 0.28
	d.global_rotation = (-n).orthogonal().angle() if stretch < 1.2 else tan_dir.angle()
	d.global_scale = Vector2(s * stretch, s * 0.6)
	d.modulate = Color(1, 1, 1, 0.9)
	d.visible = true
	var glow := d.get_child(0) as Sprite2D
	glow.modulate = Color(1.0, 0.55, 0.18, clampf(heat, 0.0, 1.0))
	_kill_tween(d)
	var tw := d.create_tween()
	tw.tween_property(glow, ^"modulate:a", 0.0, 1.6).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_interval(DECAL_LIFETIME * 0.4)
	tw.tween_property(d, ^"modulate:a", 0.0, DECAL_LIFETIME * 0.6)
	tw.tween_callback(d.hide)
	d.set_meta(&"tw", tw)

func _next_decal() -> Sprite2D:
	if _decals.size() < DECAL_MAX:
		var d := _new_decal()
		_decals.append(d)
		return d
	_decal_i = (_decal_i + 1) % _decals.size()
	var cur := _decals[_decal_i]
	if not is_instance_valid(cur):
		cur = _new_decal()
		_decals[_decal_i] = cur
	return cur

func _new_decal() -> Sprite2D:
	var d := Sprite2D.new()
	d.texture = FxTextures.scorch()
	d.z_as_relative = false
	d.z_index = Game.Z_STRUCTURE + 1
	var glow := Sprite2D.new()
	glow.texture = FxTextures.hot_core()
	glow.material = FxTextures.additive()
	glow.scale = Vector2(0.9, 0.7)
	d.add_child(glow)
	return d

## Draw a decal just above the hull it sits on: station structure bands use
## the module's struct_z (blast doors sit lower, traffic higher), containers
## draw at their own absolute z. Always below the player ship (Z_SHIP).
func _decal_z(parent: Node) -> int:
	var host := parent.get_parent()
	if host != null and &"struct_z" in host:
		return mini(int(host.get(&"struct_z")) + 1, Game.Z_SHIP - 1)
	if parent is CanvasItem and not (parent as CanvasItem).z_as_relative:
		return mini((parent as CanvasItem).z_index + 1, Game.Z_SHIP - 1)
	return Game.Z_STRUCTURE + 1

## Collision object on the world layer under a point (for scrape decals).
func _structure_at(p: Vector2) -> Node2D:
	var space := get_world_2d().direct_space_state
	if space == null:
		return null
	var q := PhysicsPointQueryParameters2D.new()
	q.position = p
	q.collision_mask = Game.LAYER_WORLD | Game.LAYER_PROPS
	q.collide_with_areas = false
	var hits := space.intersect_point(q, 1)
	if hits.is_empty():
		return null
	return hits[0]["collider"] as Node2D

# ================================================================ sound ===
func _impact_sound(tier: Tier, t: float, speed: float, pos: Vector2, player_hit: bool, prop: bool) -> void:
	if _sound_budget > 6.0:
		return
	_sound_budget += 1.0
	match tier:
		Tier.LIGHT:
			_play(_snd_light, lerpf(-12.0, -4.0, t), randf_range(1.0, 1.12), pos, player_hit)
		Tier.MEDIUM:
			_play(_snd_medium, lerpf(-5.0, 0.0, t), randf_range(0.96, 1.06), pos, player_hit)
			_play(_snd_light, -9.0, randf_range(1.05, 1.2), pos, player_hit)
		Tier.HEAVY:
			_play(_snd_heavy, lerpf(-2.0, 0.0, t), randf_range(0.92, 1.02), pos, player_hit)
			_play(_snd_medium, -8.0, randf_range(0.85, 0.95), pos, player_hit)
			_play(_snd_rattle, lerpf(-14.0, -6.0, t), randf_range(0.95, 1.1), pos, player_hit)
	if prop:
		var cv := lerpf(-10.0, 0.0, clampf(inverse_lerp(0.8, 12.0, speed), 0.0, 1.0))
		_play(_snd_clunk, cv, randf_range(0.92, 1.08), pos, player_hit)

func _play(stream: AudioStream, vol_db: float, pitch: float, pos: Vector2, non_positional: bool) -> void:
	if stream == null:
		return
	if non_positional:
		var a := _ui_players[_ui_i]
		_ui_i = (_ui_i + 1) % _ui_players.size()
		a.stream = stream
		a.volume_db = vol_db
		a.pitch_scale = pitch
		a.play()
	else:
		var b := _pos_players[_pos_i]
		_pos_i = (_pos_i + 1) % _pos_players.size()
		b.global_position = pos
		b.stream = stream
		b.volume_db = vol_db + 2.0
		b.pitch_scale = pitch
		b.play()

# =============================================================== camera ===
func _camera_feedback(tier: Tier, t: float, speed: float, n: Vector2) -> void:
	var cam := Game.camera
	if cam != null and is_instance_valid(cam):
		var trauma := 0.06 + 0.06 * t
		match tier:
			Tier.MEDIUM:
				trauma = 0.18 + 0.22 * t
			Tier.HEAVY:
				trauma = 0.5 + 0.4 * t
		if cam.has_method(&"add_trauma"):
			cam.call(&"add_trauma", trauma)
		if cam.has_method(&"punch"):
			# The view keeps travelling into the obstacle for a beat (inertia).
			cam.call(&"punch", -n, clampf(speed * 2.0, 3.0, 48.0))
	if tier == Tier.HEAVY and speed > 12.0:
		hit_stop(lerpf(0.045, 0.08, t), 0.12)

## Brief time dilation. Real-time timer so it is not stretched by itself.
func hit_stop(duration: float, time_scale: float) -> void:
	if _hitstop_active:
		return
	_hitstop_active = true
	var prev := Engine.time_scale
	Engine.time_scale = time_scale
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = prev if prev > 0.05 else 1.0
	_hitstop_active = false

# =============================================================== scrape ===
func _on_scrape(pos: Vector2, normal: Vector2, tangent_speed_mps: float, source: Node) -> void:
	if not is_finite(pos.x):
		return
	var n := _orient_normal(normal, pos, source)
	var v := _body_velocity(source)
	var tang := v - n * v.dot(n)
	if tang.length_squared() > 1.0:
		_scrape_dir = tang.normalized()
	_scrape_normal = n
	var moved := _scrape_pos.distance_to(pos)
	_scrape_pos = pos
	_scrape_speed = tangent_speed_mps
	_scrape_target = clampf(tangent_speed_mps / 14.0, 0.12, 1.0)
	_scrape_last_ms = Time.get_ticks_msec()
	# Drop elongated scuff marks along the scrape path.
	if moved < 40.0:
		_scrape_dist_accum += moved
	if _scrape_dist_accum > SCRAPE_DECAL_SPACING_M * Game.PX_PER_M:
		_scrape_dist_accum = 0.0
		_place_decal.call_deferred(null, pos, n, _scrape_dir, 0.9, 2.6, 0.5)
	# A speed-scaled trauma FLOOR, not a per-tick add: scrapes arrive 120x a
	# second, and accumulating them maxed the shake on any gentle slide.
	# Impacts still stack on top through add_trauma().
	if _is_player(source) and Game.camera and &"trauma" in Game.camera:
		var floor_t := clampf(0.15 + tangent_speed_mps / 100.0, 0.0, 0.4)
		Game.camera.set(&"trauma", maxf(float(Game.camera.get(&"trauma")), floor_t))

func _process(delta: float) -> void:
	_sound_budget = maxf(0.0, _sound_budget - delta * 40.0)
	var active := Time.get_ticks_msec() - _scrape_last_ms < 70
	var target := _scrape_target if active else 0.0
	# Fast attack, ~0.1 s release.
	var rate := 1.0 / SCRAPE_ATTACK if target > _scrape_amp else 1.0 / SCRAPE_RELEASE
	_scrape_amp = move_toward(_scrape_amp, target, rate * delta)
	if _scrape_player.stream:
		if _scrape_amp > 0.002:
			if not _scrape_player.playing:
				_scrape_player.play(randf() * _scrape_player.stream.get_length() * 0.8)
			_scrape_player.volume_db = linear_to_db(_scrape_amp) - 1.0
			_scrape_player.pitch_scale = 0.78 + clampf(_scrape_speed / 40.0, 0.0, 0.55)
		elif _scrape_player.playing:
			_scrape_player.stop()
	_scrape_emitter.emitting = active
	if active:
		# Sparks leave along the slide and peel off the surface, so most of
		# them end up against dark space where additive sparks read best.
		_scrape_emitter.global_position = _scrape_pos + _scrape_normal * 3.0
		_scrape_emitter.direction = (_scrape_dir + _scrape_normal * 0.8).normalized()
		var sp := clampf(_scrape_speed / 10.0, 0.5, 2.5)
		_scrape_emitter.initial_velocity_min = 120.0 * sp
		_scrape_emitter.initial_velocity_max = 420.0 * sp
		_scrape_glow.visible = true
		_scrape_glow.global_position = _scrape_pos
		_scrape_glow.scale = Vector2.ONE * (0.35 + 0.1 * sp) * randf_range(0.85, 1.15)
	_scrape_glow.modulate.a = move_toward(_scrape_glow.modulate.a, 0.85 * _scrape_amp, delta * 10.0)
	if _scrape_glow.modulate.a <= 0.01:
		_scrape_glow.visible = false

# ============================================================== helpers ===
func _kill_tween(n: Node) -> void:
	if n.has_meta(&"tw"):
		var old: Variant = n.get_meta(&"tw")
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()

func _is_player(n: Variant) -> bool:
	return n != null and is_instance_valid(n) and n == Game.player

func _is_prop(n: Variant) -> bool:
	if n == null or not is_instance_valid(n):
		return false
	if n is Node and ((n as Node).is_in_group(&"radar_prop") or (n as Node).is_in_group(&"container")):
		return true
	return n is RigidBody2D and n != Game.player and ((n as RigidBody2D).collision_layer & Game.LAYER_PROPS) != 0

func _body_velocity(n: Variant) -> Vector2:
	if n == null or not is_instance_valid(n):
		return Vector2.ZERO
	if n is RigidBody2D:
		return (n as RigidBody2D).linear_velocity / Game.PX_PER_M
	if n is CharacterBody2D:
		return (n as CharacterBody2D).velocity / Game.PX_PER_M
	if n is Node and (n as Node).has_method(&"get_velocity_mps"):
		return (n as Node).call(&"get_velocity_mps")
	return Vector2.ZERO

## The normal's sign is not part of the contract; make it point from the
## surface towards the reporting body so sprays leave the surface.
func _orient_normal(normal: Vector2, pos: Vector2, source: Variant) -> Vector2:
	var n := normal.normalized() if normal.length_squared() > 0.0001 else Vector2.UP
	if source is Node2D and is_instance_valid(source):
		if n.dot((source as Node2D).global_position - pos) < 0.0:
			n = -n
	return n
