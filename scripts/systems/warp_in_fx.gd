class_name WarpInFX
extends Node2D
## Short "materialise" effect when the ship (re)appears: a bright streak along
## the heading collapsing onto the ship, an imploding cyan ring, a flash and a
## white-hot ship silhouette that cools to its normal colours.

const DURATION := 0.7

var _t := 0.0
var _streak_len := 0.0

func play(pos: Vector2, heading: float) -> void:
	global_position = pos
	rotation = heading
	material = FxTextures.additive()
	_streak_len = 60.0 * Game.PX_PER_M
	var ring := Sprite2D.new()
	ring.texture = FxTextures.ring()
	ring.material = FxTextures.additive()
	ring.modulate = Color(0.5, 0.9, 1.0, 0.0)
	ring.scale = Vector2.ONE * 3.2
	add_child(ring)
	var tw := ring.create_tween().set_parallel(true)
	tw.tween_property(ring, ^"scale", Vector2.ONE * 0.25, DURATION * 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(ring, ^"modulate:a", 0.9, DURATION * 0.3)
	tw.chain().tween_property(ring, ^"modulate:a", 0.0, 0.12)

	var flash := Sprite2D.new()
	flash.texture = FxTextures.glow()
	flash.material = FxTextures.additive()
	flash.modulate = Color(0.7, 0.95, 1.0, 0.0)
	flash.scale = Vector2.ONE * 0.4
	add_child(flash)
	var tf := flash.create_tween()
	tf.tween_interval(DURATION * 0.5)
	tf.tween_property(flash, ^"modulate:a", 1.0, 0.04)
	tf.parallel().tween_property(flash, ^"scale", Vector2.ONE * 2.2, 0.25).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tf.tween_property(flash, ^"modulate:a", 0.0, 0.3)

	var sparks := CPUParticles2D.new()
	sparks.amount = 40
	sparks.lifetime = 0.5
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.local_coords = false
	sparks.texture = FxTextures.spark()
	sparks.material = FxTextures.additive()
	sparks.particle_flag_align_y = true
	sparks.spread = 180.0
	sparks.gravity = Vector2.ZERO
	sparks.initial_velocity_min = 150.0
	sparks.initial_velocity_max = 520.0
	sparks.damping_min = 400.0
	sparks.damping_max = 800.0
	sparks.scale_amount_min = 0.3
	sparks.scale_amount_max = 0.7
	sparks.color_ramp = FxTextures.energy_ramp()
	add_child(sparks)
	var ts := sparks.create_tween()
	ts.tween_interval(DURATION * 0.5)
	ts.tween_callback(sparks.set_emitting.bind(true))

	# The ship itself flashes white-hot then settles.
	if GameplayUtil.player_valid():
		var ship := Game.player
		ship.modulate = Color(0.6, 1.0, 1.2, 0.0)
		var tp := ship.create_tween()
		tp.tween_interval(DURATION * 0.45)
		tp.tween_property(ship, ^"modulate", Color(2.0, 2.4, 2.6, 1.0), 0.08)
		tp.tween_property(ship, ^"modulate", Color.WHITE, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	_sound()

func _sound() -> void:
	# A dedicated warp sound is optional (requested from AUDIO); otherwise
	# layer a pitched-up boost kick with the gate chime.
	if GameplayUtil.audio_exists("warp_in.wav"):
		GameplayUtil.play_oneshot(self, GameplayUtil.load_audio("warp_in.wav"), -4.0)
		return
	GameplayUtil.play_oneshot(self, GameplayUtil.load_audio("boost_kick.wav"), -9.0, 1.35)
	var chime := GameplayUtil.load_audio("dock_chime.wav")
	if chime:
		var t := get_tree().create_timer(DURATION * 0.45, false)
		t.timeout.connect(func() -> void:
			if is_inside_tree():
				GameplayUtil.play_oneshot(self, chime, -14.0, 1.5))

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()
	if _t > DURATION + 0.6:
		queue_free()

func _draw() -> void:
	# Streak collapsing from far behind the ship into its position.
	var k := clampf(_t / (DURATION * 0.5), 0.0, 1.0)
	if k >= 1.0:
		return
	var e := 1.0 - pow(1.0 - k, 3.0)
	var tail := -_streak_len * (1.0 - e)
	var head := -_streak_len * (1.0 - e) * 0.15
	var a := sin(k * PI)
	draw_line(Vector2(tail, 0), Vector2(head, 0), Color(0.5, 0.9, 1.0, 0.35 * a), 22.0, true)
	draw_line(Vector2(tail, 0), Vector2(head, 0), Color(0.85, 0.97, 1.0, 0.9 * a), 4.0, true)
