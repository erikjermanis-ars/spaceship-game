class_name Walker
extends CharacterBody2D
## The on-foot player character (top-down).
##
## Movement: CharacterBody2D in floating mode (no gravity, top-down), moved
## with move_and_slide at the 120 Hz physics rate. Velocity eases towards
## the stick/WASD direction (acceleration + braking) so it has a little
## weight without feeling sluggish.
##
## Rendering: the art child (WalkerArt) is drawn at a position interpolated
## between the last two physics ticks (same trick as the ship), so walking is
## smooth at any display refresh rate. The camera follows render_position().
##
## Collision: layer LAYER_WALKER; it bumps into station structure (WORLD),
## the parked ship (PLAYER, frozen while you're out) and on-foot obstacles
## (WALK: railings, furniture, interior walls, doors).

signal footstep(pos: Vector2, running: bool)

@export var walk_speed_mps := 2.6
@export var run_speed_mps := 4.8
@export var accel_mps2 := 22.0
@export var brake_mps2 := 28.0
## Radius of the collision circle (shoulders are a bit wider; this lets you
## squeeze past things the way people do).
@export var radius_m := 0.3

const ART_SCALE := 1.25

## Input is ignored while false (cutscenes: hatch, airlock, boarding).
var controls_enabled := true
## Facing angle (radians, 0 = +X). Smoothly follows the movement direction.
var facing := 0.0
## Inside a pressurised interior the helmet comes off (art + footstep sound).
var helmet := true:
	set(v):
		helmet = v
		if _art:
			_art.helmet = v
var running := false
var flashlight_on := false
## Extra velocity (px/s) from what you stand on (the gangway's moving
## walkway). Set every physics frame by a Travelator, consumed and cleared
## here, so the feet don't walk while the belt carries you.
var conveyor := Vector2.ZERO

var _art: WalkerArt
var _light: PointLight2D
var _prev_pos := Vector2.ZERO
var _cur_pos := Vector2.ZERO
var _auto_target := Vector2.ZERO
var _auto_active := false
var _auto_speed := 1.6
var _auto_done: Callable
var _step_phase := 0.0
var _snd_steps_suit: AudioStream
var _snd_steps_deck: AudioStream
var _snd_toggle: AudioStream
var _step_player: AudioStreamPlayer2D


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = Game.LAYER_WALKER
	collision_mask = Game.LAYER_WORLD | Game.LAYER_PLAYER | Game.LAYER_WALK | Game.LAYER_PROPS
	# Small body in px units: keep the safety margin tiny so it can get close
	# to walls without visible gaps.
	safe_margin = 0.05
	var cs := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = radius_m * Game.PX_PER_M
	cs.shape = c
	add_child(cs)
	z_as_relative = false
	z_index = Game.Z_WALKER

	_art = WalkerArt.new()
	_art.name = "Art"
	_art.helmet = helmet
	# Stylised: drawn ~25 % larger than life so the character reads well
	# from the top-down camera (the collision circle stays realistic).
	_art.scale = Vector2.ONE * ART_SCALE
	add_child(_art)

	_light = PointLight2D.new()
	_light.name = "Flashlight"
	_light.texture = OnFootArt.cone_texture()
	_light.texture_scale = 9.0 * Game.PX_PER_M * 2.0 / 256.0   # ~9 m reach
	_light.color = Color(1.0, 0.95, 0.85)
	_light.energy = 1.25
	_light.shadow_enabled = true
	_light.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	_light.shadow_filter_smooth = 1.5
	_light.enabled = false
	_light.position = Vector2(1.2, 0)     # helmet lamp, just ahead of the face
	_light.scale = Vector2.ONE / ART_SCALE
	_art.add_child(_light)

	_snd_steps_suit = GameplayUtil.load_variations("step_suit_", 4, 1.06, 2.0)
	_snd_steps_deck = GameplayUtil.load_variations("step_deck_", 4, 1.06, 2.5)
	_snd_toggle = GameplayUtil.load_audio("switch_click.wav")
	_step_player = AudioStreamPlayer2D.new()
	_step_player.bus = GameplayUtil.bus(&"SFX")
	_step_player.max_distance = 400.0
	_step_player.max_polyphony = 3
	add_child(_step_player)

	_prev_pos = global_position
	_cur_pos = global_position
	_art.rotation = facing
	Game.walker = self


func _exit_tree() -> void:
	if Game.walker == self:
		Game.walker = null


## Teleport (behind a fade): no interpolation smear, no physics sweep.
func place(pos: Vector2, face: float) -> void:
	global_position = pos
	velocity = Vector2.ZERO
	facing = face
	_prev_pos = pos
	_cur_pos = pos
	_auto_active = false
	if _art:
		_art.position = Vector2.ZERO
		_art.rotation = face


## Scripted walk to a point (hatch ramps, doorways). Collisions still apply
## except for the shapes we deliberately walk through (callers open them).
func auto_walk(to: Vector2, speed_mps := 1.6, done: Callable = Callable()) -> void:
	_auto_target = to
	_auto_active = true
	_auto_speed = speed_mps
	_auto_done = done


func is_auto_walking() -> bool:
	return _auto_active


func render_position() -> Vector2:
	return _prev_pos.lerp(_cur_pos, clampf(Engine.get_physics_interpolation_fraction(), 0.0, 1.0))


func set_flashlight(on: bool, silent := false) -> void:
	flashlight_on = on
	_light.enabled = on
	_art.lamp_on = on
	if not silent and _snd_toggle and _step_player:
		GameplayUtil.play_oneshot(self, _snd_toggle, -14.0, 1.5)


## The flashlight is brighter indoors (dark rooms) than outside in sunlight,
## where it would only wash out the pad.
func set_flashlight_energy(e: float) -> void:
	_light.energy = e


func _physics_process(delta: float) -> void:
	var want := Vector2.ZERO
	var speed := walk_speed_mps
	if _auto_active:
		var to := _auto_target - global_position
		var d := to.length()
		if d < 0.6:
			_auto_active = false
			if _auto_done.is_valid():
				var cb := _auto_done
				_auto_done = Callable()
				cb.call()
		else:
			want = to / d
			speed = _auto_speed
			# Ease in to the target instead of stopping dead.
			speed = minf(speed, d / Game.PX_PER_M * 4.0)
	elif controls_enabled:
		want = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
		running = Input.is_action_pressed(&"run")
		speed = run_speed_mps if running else walk_speed_mps
		if Input.is_action_just_pressed(&"flashlight"):
			set_flashlight(not flashlight_on)
	var target_v := want * speed * Game.PX_PER_M
	var rate := accel_mps2 if want.length_squared() > 0.01 else brake_mps2
	velocity = velocity.move_toward(target_v, rate * Game.PX_PER_M * delta)
	if _auto_active:
		# Scripted moves ignore the ship collision (we walk up its ramp).
		global_position += velocity * delta
	elif conveyor != Vector2.ZERO:
		var own := velocity
		velocity = own + conveyor
		move_and_slide()
		velocity = own
	else:
		move_and_slide()
	conveyor = Vector2.ZERO

	# Face where we're going (or where the stick points when blocked).
	var look := want if want.length_squared() > 0.04 else velocity / maxf(velocity.length(), 0.001)
	if look.length_squared() > 0.04 and (want.length_squared() > 0.04 or velocity.length() > 2.0):
		facing = lerp_angle(facing, look.angle(), 1.0 - exp(-14.0 * delta))

	_prev_pos = _cur_pos
	_cur_pos = global_position
	_advance_steps(delta)


## Distance-driven walk cycle: the feet plant every `stride` metres of real
## movement, so they never slide over the floor whatever the speed. Each
## plant fires a footstep sound in sync with the animation.
func _advance_steps(delta: float) -> void:
	var spd := velocity.length() / Game.PX_PER_M
	var stride := lerpf(0.7, 1.05, clampf((spd - walk_speed_mps) / (run_speed_mps - walk_speed_mps), 0.0, 1.0))
	var prev := _step_phase
	_step_phase += spd * delta / stride * PI
	if spd < 0.25:
		# Settle the feet back together when stopping.
		var target := roundf(_step_phase / PI) * PI
		_step_phase = move_toward(_step_phase, target, delta * 6.0)
	elif floori(prev / PI) != floori(_step_phase / PI):
		_play_step(spd)
	_art.step_phase = _step_phase
	_art.speed_mps = spd
	_art.run_amount = clampf((spd - walk_speed_mps) / (run_speed_mps - walk_speed_mps), 0.0, 1.0)


func _play_step(spd: float) -> void:
	footstep.emit(global_position, running)
	var s := _snd_steps_suit if helmet else _snd_steps_deck
	if s == null:
		return
	_step_player.stream = s
	var run_k := clampf((spd - walk_speed_mps) / (run_speed_mps - walk_speed_mps), 0.0, 1.0)
	_step_player.volume_db = lerpf(-15.0, -9.0, run_k) if not helmet else lerpf(-11.0, -6.0, run_k)
	_step_player.pitch_scale = 1.0 + 0.06 * run_k
	_step_player.play()


func _process(delta: float) -> void:
	if _art == null:
		return
	# The body sits at the physics position; the art is offset to the
	# interpolated one (the body itself is never rotated).
	_art.position = render_position() - global_position
	_art.rotation = facing
	_art.advance(delta)
