class_name ShipExplosion
extends Node2D
## One-off ship destruction effect: white-hot flash, fireball, expanding
## shockwave, hot sparks, lingering smoke and tumbling hull shards that keep
## the ship's momentum and bounce off the station. Frees itself when done.

const SHARD_COUNT := 16
const LIFETIME := 9.0
const HULL_COLORS := [Color("#E9EEF3"), Color("#C9D2DC"), Color("#8E9AA8"), Color("#1D3557"), Color("#2A9D8F")]

var _shards: Array[RigidBody2D] = []
var _age := 0.0
var _vel := Vector2.ZERO

func explode(pos: Vector2, ship_velocity_px: Vector2) -> void:
	global_position = pos
	_vel = ship_velocity_px
	_flash(Color(1, 1, 1), 16.0, 0.12, 0.0)
	_flash(Color(1.0, 0.7, 0.35, 0.85), 30.0, 0.45, 0.02)
	_flash(Color(0.55, 0.85, 1.0, 0.5), 20.0, 0.7, 0.0)  # cool reactor-blue tint
	_ring(Color(1.0, 0.9, 0.8, 0.9), 650.0, 0.75)
	_ring(Color(0.6, 0.9, 1.0, 0.6), 380.0, 1.1)
	_particles()
	for i in SHARD_COUNT:
		_spawn_shard(i)
	_sounds()
	_camera()

func _process(delta: float) -> void:
	_age += delta
	# Fade the shards' visuals over the last couple of seconds.
	if _age > LIFETIME - 2.5:
		var a := clampf((LIFETIME - _age) / 2.5, 0.0, 1.0)
		for s in _shards:
			if is_instance_valid(s):
				s.modulate.a = a
	if _age >= LIFETIME:
		queue_free()

# ------------------------------------------------------------- visuals ---
func _flash(col: Color, radius_m: float, dur: float, delay: float) -> void:
	var s := Sprite2D.new()
	s.texture = FxTextures.glow()
	s.material = FxTextures.additive()
	s.modulate = col
	var r := radius_m * Game.PX_PER_M
	s.scale = Vector2.ONE * (r * 0.4 / 64.0)
	add_child(s)
	var tw := s.create_tween().set_parallel(true)
	tw.tween_property(s, ^"scale", Vector2.ONE * (r / 64.0), dur).set_delay(delay).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(s, ^"modulate:a", 0.0, dur).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(s.queue_free)

func _ring(col: Color, radius_px: float, dur: float) -> void:
	var s := Sprite2D.new()
	s.texture = FxTextures.ring()
	s.material = FxTextures.additive()
	s.modulate = col
	s.scale = Vector2.ONE * 0.1
	add_child(s)
	var tw := s.create_tween().set_parallel(true)
	tw.tween_property(s, ^"scale", Vector2.ONE * (radius_px / 110.0), dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(s, ^"modulate:a", 0.0, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(s.queue_free)

func _particles() -> void:
	var drift := _vel * 0.6
	# Fireball: big soft additive blobs expanding and cooling.
	var fire := _emitter(36, 1.1, FxTextures.glow(), true)
	fire.initial_velocity_min = 30.0
	fire.initial_velocity_max = 220.0
	fire.damping_min = 120.0
	fire.damping_max = 260.0
	fire.scale_amount_min = 0.5
	fire.scale_amount_max = 1.1
	fire.scale_amount_curve = FxTextures.grow_curve()
	fire.color_ramp = FxTextures.fire_ramp()
	fire.gravity = drift * 0.6
	# Sparks: lots of fast streaks.
	var sparks := _emitter(110, 0.9, FxTextures.spark(), true)
	sparks.particle_flag_align_y = true
	sparks.initial_velocity_min = 200.0
	sparks.initial_velocity_max = 1100.0
	sparks.damping_min = 300.0
	sparks.damping_max = 900.0
	sparks.scale_amount_min = 0.5
	sparks.scale_amount_max = 1.1
	sparks.scale_amount_curve = FxTextures.shrink_curve()
	sparks.color_ramp = FxTextures.spark_ramp()
	# Embers: slower glowing chunks.
	var embers := _emitter(40, 2.2, FxTextures.chunk(), true)
	embers.initial_velocity_min = 40.0
	embers.initial_velocity_max = 380.0
	embers.damping_min = 20.0
	embers.damping_max = 90.0
	embers.angular_velocity_min = -600.0
	embers.angular_velocity_max = 600.0
	embers.scale_amount_min = 0.5
	embers.scale_amount_max = 1.4
	embers.scale_amount_curve = FxTextures.shrink_curve()
	embers.color_ramp = FxTextures.fire_ramp()
	embers.gravity = drift * 0.3
	# Smoke: lingers and drifts with the wreck.
	var smoke := _emitter(28, 4.5, FxTextures.smoke(), false)
	smoke.explosiveness = 0.7
	smoke.initial_velocity_min = 20.0
	smoke.initial_velocity_max = 160.0
	smoke.damping_min = 25.0
	smoke.damping_max = 60.0
	smoke.scale_amount_min = 1.4
	smoke.scale_amount_max = 3.2
	smoke.scale_amount_curve = FxTextures.grow_curve()
	smoke.color_ramp = FxTextures.smoke_ramp()
	smoke.angular_velocity_min = -30.0
	smoke.angular_velocity_max = 30.0
	smoke.gravity = drift * 0.15
	smoke.z_index = -1   # under the fire

func _emitter(amount: int, lifetime: float, tex: Texture2D, additive: bool) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = 0.95
	p.lifetime_randomness = 0.5
	p.randomness = 0.5
	p.local_coords = false
	p.texture = tex
	if additive:
		p.material = FxTextures.additive()
	p.spread = 180.0
	p.gravity = Vector2.ZERO
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 18.0
	add_child(p)
	p.emitting = true
	return p

func _spawn_shard(i: int) -> void:
	var body := RigidBody2D.new()
	body.collision_layer = 0
	body.collision_mask = Game.LAYER_WORLD | Game.LAYER_PROPS
	body.gravity_scale = 0.0
	body.linear_damp = 0.12
	body.angular_damp = 0.4
	body.continuous_cd = RigidBody2D.CCD_MODE_CAST_RAY
	var mat := PhysicsMaterial.new()
	mat.bounce = 0.35
	mat.friction = 0.4
	body.physics_material_override = mat
	# Random jagged plate, 0.5–2.4 m across, biggest first.
	var size_m := lerpf(3.4, 0.7, float(i) / SHARD_COUNT) * randf_range(0.8, 1.2)
	var pts := PackedVector2Array()
	var corners := randi_range(3, 5)
	for c in corners:
		var a := TAU * c / corners + randf_range(-0.35, 0.35)
		pts.append(Vector2.from_angle(a) * size_m * Game.PX_PER_M * 0.5 * randf_range(0.55, 1.0))
	var shape := CollisionPolygon2D.new()
	shape.polygon = pts
	body.add_child(shape)
	var poly := Polygon2D.new()
	poly.polygon = pts
	poly.color = HULL_COLORS[i % HULL_COLORS.size()].darkened(randf_range(0.0, 0.35))
	body.add_child(poly)
	var edge := Line2D.new()
	var closed := pts.duplicate()
	closed.append(pts[0])
	edge.points = closed
	edge.width = 1.2
	edge.default_color = Color(1.0, 0.55, 0.2, 0.95)
	edge.material = FxTextures.additive()
	edge.antialiased = true
	body.add_child(edge)
	# Edges glow hot and cool down.
	var tw := edge.create_tween()
	tw.tween_property(edge, ^"default_color", Color(0.6, 0.15, 0.05, 0.0), randf_range(1.2, 2.6))
	body.mass = size_m * 20.0
	var dir := Vector2.from_angle(randf() * TAU)
	var speed := randf_range(6.0, 28.0) * Game.PX_PER_M * (1.2 - size_m / 3.0)
	body.linear_velocity = _vel * randf_range(0.6, 1.0) + dir * speed
	body.angular_velocity = randf_range(-9.0, 9.0)
	body.position = dir * randf_range(0.0, 2.0) * Game.PX_PER_M
	body.rotation = randf() * TAU
	add_child(body)
	_shards.append(body)
	# Bigger shards trail smoke for a moment.
	if i < 5:
		var trail := CPUParticles2D.new()
		trail.amount = 24
		trail.lifetime = 1.2
		trail.local_coords = false
		trail.texture = FxTextures.smoke()
		trail.gravity = Vector2.ZERO
		trail.spread = 180.0
		trail.initial_velocity_min = 5.0
		trail.initial_velocity_max = 20.0
		trail.scale_amount_min = 0.25
		trail.scale_amount_max = 0.6
		trail.scale_amount_curve = FxTextures.grow_curve()
		trail.color_ramp = FxTextures.smoke_ramp()
		trail.z_index = -1
		body.add_child(trail)
		trail.emitting = true
		var t2 := trail.create_tween()
		t2.tween_interval(randf_range(1.2, 2.5))
		t2.tween_callback(trail.set_emitting.bind(false))

# --------------------------------------------------------------- audio ---
func _sounds() -> void:
	var boom := GameplayUtil.load_audio("explosion_ship.wav")
	GameplayUtil.play_oneshot(self, boom, 0.0, randf_range(0.95, 1.03))
	var rattle := GameplayUtil.load_audio("debris_rattle.wav")
	if rattle:
		var t := get_tree().create_timer(0.35, false)
		t.timeout.connect(func() -> void:
			if is_inside_tree():
				GameplayUtil.play_oneshot(self, rattle, -5.0, 0.9))
		var t2 := get_tree().create_timer(0.9, false)
		t2.timeout.connect(func() -> void:
			if is_inside_tree():
				GameplayUtil.play_oneshot(self, rattle, -10.0, 1.15))

func _camera() -> void:
	var cam := Game.camera
	if cam == null or not is_instance_valid(cam):
		return
	if cam.has_method(&"add_trauma"):
		cam.call(&"add_trauma", 1.0)
	if cam.has_method(&"punch"):
		cam.call(&"punch", Vector2.from_angle(randf() * TAU), 90.0)
