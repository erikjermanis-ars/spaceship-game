class_name WeaponHitFx
extends Node2D
## What a bolt hit looks and sounds like: a spark spray that splashes back off
## the surface, a small flash, and a scorch mark with a glowing ember that
## cools in a few seconds. Everything is pooled and created up front (same
## approach as ImpactFX), so a hit never allocates a node.

const G := preload("res://scripts/autoload/game.gd")
const SPARK_POOL := 10
const FLASH_POOL := 10
const MARK_POOL := 28
const MARK_LIFE_S := 6.0
const EMBER_COLOR := Color(1.0, 0.5, 0.12)

var _sparks: Array[CPUParticles2D] = []
var _flashes: Array[Sprite2D] = []
var _cores: Array[Sprite2D] = []
var _marks: Array[Sprite2D] = []
var _spark_i := 0
var _flash_i := 0
var _mark_i := 0
var _snd_hit: AudioStream
var _voices: Array[AudioStreamPlayer2D] = []
var _voice_i := 0
var _last_sound_ms := -1000


func _ready() -> void:
	for i in SPARK_POOL:
		_sparks.append(_make_sparks())
	for i in FLASH_POOL:
		_flashes.append(_make_sprite(FxTextures.glow()))
		_cores.append(_make_sprite(FxTextures.hot_core()))
	_snd_hit = GameplayUtil.load_variations("pulse_hit_", 3, 1.12, 2.0)
	if _snd_hit != null:
		for i in 6:
			var v := AudioStreamPlayer2D.new()
			v.stream = _snd_hit
			v.bus = GameplayUtil.bus(&"SFX")
			v.max_distance = 2600.0
			v.attenuation = 1.6
			v.panning_strength = 1.2
			add_child(v)
			_voices.append(v)


func _make_sparks() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = 14
	p.lifetime = 0.34
	p.explosiveness = 0.95
	p.lifetime_randomness = 0.6
	p.local_coords = false
	p.texture = FxTextures.spark()
	p.material = FxTextures.additive()
	p.particle_flag_align_y = true
	p.gravity = Vector2.ZERO
	p.spread = 58.0
	p.initial_velocity_min = 90.0
	p.initial_velocity_max = 460.0
	p.damping_min = 300.0
	p.damping_max = 800.0
	p.scale_amount_min = 0.4
	p.scale_amount_max = 0.95
	p.scale_amount_curve = FxTextures.shrink_curve()
	p.color_ramp = FxTextures.spark_ramp()
	add_child(p)
	return p


func _make_sprite(tex: Texture2D) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex
	s.material = FxTextures.additive()
	s.visible = false
	add_child(s)
	return s


## `normal` points off the surface, `dir` is where the bolt was going.
func hit(pos: Vector2, normal: Vector2, dir: Vector2, collider: Node) -> void:
	# Sparks leave between the mirror bounce and the surface normal: a head-on
	# hit splashes straight back, a grazing one skips along the plating.
	var bounce := dir.bounce(normal) if normal.dot(dir) < 0.0 else normal
	var out := (bounce + normal * 0.9).normalized()
	var p := _sparks[_spark_i]
	_spark_i = (_spark_i + 1) % SPARK_POOL
	p.global_position = pos + normal * 2.0
	p.direction = out
	p.restart()
	p.emitting = true
	var glow := _flashes[_flash_i]
	var core := _cores[_flash_i]
	_flash_i = (_flash_i + 1) % FLASH_POOL
	_pop(glow, pos, 0.34, 0.62, 0.16, Color(1.0, 0.62, 0.25, 0.95))
	_pop(core, pos, 0.5, 0.2, 0.09, Color(1.0, 0.97, 0.9))
	# Things that take shots show their own damage; everything else is marked.
	if collider != null and not collider.has_method(&"take_shot"):
		_mark.call_deferred(collider, pos, normal)
	_sound(pos)


func _pop(s: Sprite2D, pos: Vector2, scale_from: float, scale_to: float, dur: float, col: Color) -> void:
	_kill_tween(s)
	s.global_position = pos
	s.scale = Vector2.ONE * scale_from
	s.modulate = col
	s.visible = true
	var tw := s.create_tween().set_parallel(true)
	tw.tween_property(s, ^"scale", Vector2.ONE * scale_to, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(s, ^"modulate:a", 0.0, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(s.hide)
	s.set_meta(&"tw", tw)


## Scorch + ember stuck to whatever was hit, so it rides along on the ring,
## a container or a passing freighter. Deferred: re-parenting is not allowed
## while the physics step that reported the hit is still running.
func _mark(surface: Node, pos: Vector2, normal: Vector2) -> void:
	if not is_instance_valid(surface) or not (surface is Node2D):
		return
	var d := _next_mark()
	if d.get_parent() != surface:
		if d.get_parent():
			d.get_parent().remove_child(d)
		surface.add_child(d)
	d.z_index = _mark_z(surface)
	# Sunk slightly into the plating so the smudge doesn't hang out over space.
	d.global_position = pos - normal * 3.0
	d.global_rotation = normal.angle() + PI * 0.5
	d.global_scale = Vector2(0.3, 0.2) * randf_range(0.85, 1.2)
	d.modulate = Color(1, 1, 1, 0.85)
	d.visible = true
	var ember := d.get_child(0) as Sprite2D
	ember.modulate = Color(EMBER_COLOR, 1.0)
	var halo := d.get_child(1) as Sprite2D
	halo.modulate = Color(EMBER_COLOR, 0.9)
	_kill_tween(d)
	var tw := d.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ember, ^"modulate:a", 0.0, 1.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(halo, ^"modulate:a", 0.0, 0.7)
	tw.tween_property(d, ^"modulate:a", 0.0, MARK_LIFE_S * 0.5).set_delay(MARK_LIFE_S * 0.5)
	tw.chain().tween_callback(d.hide)
	d.set_meta(&"tw", tw)


func _next_mark() -> Sprite2D:
	if _marks.size() < MARK_POOL:
		var fresh := _new_mark()
		_marks.append(fresh)
		return fresh
	_mark_i = (_mark_i + 1) % _marks.size()
	# The body a mark was stuck to may have been freed, and the mark with it.
	if not is_instance_valid(_marks[_mark_i]):
		_marks[_mark_i] = _new_mark()
	return _marks[_mark_i]


func _new_mark() -> Sprite2D:
	var d := Sprite2D.new()
	d.texture = FxTextures.scorch()
	d.z_as_relative = false
	# Ember: normal blend, so it shows on a white hull too.
	var ember := Sprite2D.new()
	ember.texture = FxTextures.hot_core()
	ember.scale = Vector2(0.55, 0.55)
	d.add_child(ember)
	var halo := Sprite2D.new()
	halo.texture = FxTextures.glow()
	halo.material = FxTextures.additive()
	halo.scale = Vector2(1.1, 1.3)
	d.add_child(halo)
	return d


## Just above the hull it sits on, always below the player ship (the same
## rule as ImpactFX's decals).
func _mark_z(parent: Node) -> int:
	var host := parent.get_parent()
	if host != null and &"struct_z" in host:
		return mini(int(host.get(&"struct_z")) + 1, G.Z_SHIP - 1)
	if parent is CanvasItem and not (parent as CanvasItem).z_as_relative:
		return mini((parent as CanvasItem).z_index + 1, G.Z_SHIP - 1)
	return G.Z_STRUCTURE + 1


func _sound(pos: Vector2) -> void:
	if _voices.is_empty():
		return
	# Two bolts landing in the same instant are one sound.
	var now := Time.get_ticks_msec()
	if now - _last_sound_ms < 40:
		return
	_last_sound_ms = now
	var v := _voices[_voice_i]
	_voice_i = (_voice_i + 1) % _voices.size()
	v.global_position = pos
	v.volume_db = -5.0
	v.pitch_scale = randf_range(0.94, 1.08)
	v.play()


func _kill_tween(n: Node) -> void:
	if n.has_meta(&"tw"):
		var old: Variant = n.get_meta(&"tw")
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()
