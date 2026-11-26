@tool
class_name RoomLight
extends Node2D
## Ceiling light for a room: a PointLight2D using a soft *box* falloff
## texture scaled to `size_m`, so the light fills its room evenly and fades
## out at the walls. Because it never reaches the next room, it needs no
## shadow map (only the flashlight casts shadows).
##
## Switching on plays a short fluorescent-style start-up flicker; `faulty`
## lights keep flickering now and then (with an electrical buzz).

@export var size_m := Vector2(8, 8)
@export var color := Color(1.0, 0.96, 0.9)
@export var energy := 0.95
@export var on := true:
	set(v):
		on = v
		if is_inside_tree() and not Engine.is_editor_hint():
			_start_t = 0.0
@export var faulty := false

var _light: PointLight2D
var _level := 0.0          # 0..1 current brightness
var _start_t := 99.0       # seconds since switched on (start-up flicker)
var _flick := 1.0
var _flick_timer := 0.0
var _buzz: AudioStreamPlayer2D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	add_to_group(&"persist")
	_rng.seed = hash(name)
	_light = PointLight2D.new()
	_light.texture = OnFootArt.soft_box_texture()
	_light.color = color
	_light.energy = 0.0
	# Non-uniform scale stretches the 128 px box texture over the room
	# (plus a 1 m margin so the falloff ends at the walls, not inside).
	_light.scale = (size_m + Vector2(1.6, 1.6)) * OnFootArt.PX / 128.0
	_light.shadow_enabled = false
	add_child(_light)
	_level = 1.0 if on else 0.0
	_start_t = 99.0
	if faulty:
		var s := GameplayUtil.load_loop("light_buzz_loop.wav")
		if s:
			_buzz = AudioStreamPlayer2D.new()
			_buzz.stream = s
			_buzz.bus = GameplayUtil.bus(&"SFX")
			_buzz.max_distance = 260.0
			_buzz.volume_db = -60.0
			add_child(_buzz)
			_buzz.play()
	_apply()


## Multiplies the light's colour (red alert, emergency lighting). White = normal.
func set_tint(c: Color) -> void:
	if _light:
		_light.color = color * c


func toggle() -> void:
	on = not on


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _light == null:
		return
	_start_t += delta
	var target := 1.0 if on else 0.0
	if on and _start_t < 0.6:
		# Start-up: a couple of quick blinks before it settles.
		var t := _start_t
		target = 1.0 if (t > 0.05 and t < 0.1) or (t > 0.22 and t < 0.26) or t > 0.42 else 0.12
		_level = target
	else:
		_level = move_toward(_level, target, delta * (6.0 if on else 9.0))
	if faulty and on:
		_flick_timer -= delta
		if _flick_timer <= 0.0:
			# Mostly fine, then a burst of stutters.
			if _rng.randf() < 0.35:
				_flick = _rng.randf_range(0.05, 0.5)
				_flick_timer = _rng.randf_range(0.03, 0.09)
			else:
				_flick = _rng.randf_range(0.85, 1.0)
				_flick_timer = _rng.randf_range(0.08, 1.4)
	else:
		_flick = 1.0
	_apply()


func _apply() -> void:
	var lv := _level * _flick
	_light.energy = energy * lv
	_light.enabled = lv > 0.001
	if _buzz:
		_buzz.volume_db = lerpf(-60.0, -22.0, _level) + (6.0 if _flick < 0.6 else 0.0)


func save_state() -> Dictionary:
	return {"on": on}


func load_state(d: Dictionary) -> void:
	on = bool(d.get("on", on))
	_level = 1.0 if on else 0.0
	_start_t = 99.0
