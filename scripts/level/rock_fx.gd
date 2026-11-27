extends RefCounted
## What a shot rock throws off: dust and pebbles, the crack / shatter sounds,
## and the ore canister. Static helpers used by Asteroid; everything is
## parented to `host` (the rock's parent), because the rock itself may be gone
## a frame later.

const G := preload("res://scripts/autoload/game.gd")
const A := preload("res://scripts/level/level_art.gd")
const CargoBox := preload("res://scripts/level/cargo_box.gd")
const PX := 10.0
## Ore canister: a small container in dark graphite with teal bands.
const CANISTER_SIZE_M := Vector2(6.1, 2.44)
const CANISTER_COLOR := Color("2B3138")
const BAND := Color("2A9D8F")
const GOLD := Color("F0BE4A")
## Seconds the canister passes through the fragments it was born inside.
const UNPAIR_S := 1.5


## Dust (soft) and pebbles (hard little squares) thrown from `at` (global px)
## along `dir` (ZERO = all round).
static func puff(host: Node, at: Vector2, dir: Vector2, amount: int, speed_mps: float, size: float) -> void:
	if host == null or not host.is_inside_tree():
		return
	for dust: bool in [true, false]:
		var p := CPUParticles2D.new()
		p.z_as_relative = false
		p.z_index = G.Z_FX
		p.one_shot = true
		p.explosiveness = 0.95
		p.amount = amount if dust else amount * 2
		p.lifetime = 1.6 if dust else 1.1
		p.direction = dir if dir != Vector2.ZERO else Vector2.RIGHT
		p.spread = 55.0 if dir != Vector2.ZERO else 180.0
		p.gravity = Vector2.ZERO
		p.initial_velocity_min = speed_mps * PX * (0.15 if dust else 0.4)
		p.initial_velocity_max = speed_mps * PX * (0.6 if dust else 1.6)
		p.damping_min = 20.0
		p.damping_max = 60.0
		p.angle_max = 360.0
		var ramp := Gradient.new()
		if dust:
			p.texture = A.glow_texture()
			p.scale_amount_min = 0.25 * size
			p.scale_amount_max = 0.6 * size
			ramp.colors = PackedColorArray([Color(0.74, 0.7, 0.64, 0.3), Color(0.6, 0.57, 0.53, 0.0)])
		else:
			p.scale_amount_min = 1.5 * size
			p.scale_amount_max = 4.5 * size
			ramp.colors = PackedColorArray([Color(0.62, 0.59, 0.55, 1.0), Color(0.35, 0.34, 0.33, 0.0)])
		p.color_ramp = ramp
		host.add_child(p)
		p.global_position = at
		p.emitting = true
		p.finished.connect(p.queue_free)


## Positional one-shot by file name. The rock sounds are synthesized by the
## audio workstream: a missing file (or a headless run) is silently skipped.
static func sound(host: Node, at: Vector2, file: String, volume_db: float, pitch: float) -> void:
	var stream := GameplayUtil.load_audio(file)
	if stream == null or host == null or not host.is_inside_tree():
		return
	var p := AudioStreamPlayer2D.new()
	p.stream = stream
	p.bus = GameplayUtil.bus(&"SFX")
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.max_distance = 6000.0
	host.add_child(p)
	p.global_position = at
	p.finished.connect(p.queue_free)
	p.play()


## The ore body comes loose as a canister-sized slug: a CargoBox (brand ORE),
## so the shuttle's mag-line and the cargo features treat it as cargo. The
## caller places it and adds it to the tree; `frags` are the rock fragments
## it is born inside, which it passes through until they have parted.
static func canister(serial: int, frags: Array[RigidBody2D]) -> RigidBody2D:
	var box: RigidBody2D = CargoBox.new()
	box.setup(CANISTER_SIZE_M, CANISTER_COLOR, "ORE", "VSPR %06d" % (absi(serial) % 1000000))
	box.add_to_group(&"ore_canister")
	var band := Node2D.new()
	band.name = "Livery"
	band.draw.connect(func() -> void:
		var h := CANISTER_SIZE_M * PX * 0.5
		for sx: float in [-1.0, 1.0]:
			band.draw_rect(Rect2(Vector2(sx * (h.x - 9.0) - 4.0, -h.y + 2.0), Vector2(8.0, h.y * 2.0 - 4.0)), BAND)
			band.draw_rect(Rect2(Vector2(sx * (h.x - 16.0) - 0.8, -h.y + 2.0), Vector2(1.6, h.y * 2.0 - 4.0)), GOLD))
	box.add_child(band)
	if not frags.is_empty():
		for f in frags:
			box.add_collision_exception_with(f)
		# Lets go when the box enters the tree (it is added deferred).
		box.ready.connect(func() -> void:
			box.get_tree().create_timer(UNPAIR_S, false).timeout.connect(_unpair.bind(box, frags)), CONNECT_ONE_SHOT)
	return box


static func _unpair(box: Variant, frags: Array[RigidBody2D]) -> void:
	if not is_instance_valid(box):
		return
	for f in frags:
		if is_instance_valid(f):
			(box as RigidBody2D).remove_collision_exception_with(f)
