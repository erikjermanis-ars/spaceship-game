class_name AmbientAudio
extends Node
## Stereo ambient pad on the Ambient bus, faded in gently at start. Ducks a
## little while the ship is destroyed so the explosion reads clearly.

## Kept low so collisions and the engine lead the mix (file is ~-16 LUFS).
@export var target_db := -15.0
@export var fade_in_time := 5.0

var _player: AudioStreamPlayer
var _duck := 0.0

func _ready() -> void:
	var loop := GameplayUtil.load_loop("ambient_space_drone.wav")
	# The headless dummy driver never releases playbacks; keep test logs clean.
	if loop == null or DisplayServer.get_name() == "headless":
		return
	_player = GameplayUtil.make_player(self, loop, &"Ambient", -60.0)
	_player.play()
	var tw := create_tween()
	tw.tween_property(_player, ^"volume_db", target_db, fade_in_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	Game.ship_destroyed.connect(func(_p: Vector2) -> void: _duck = 1.0)

func _process(delta: float) -> void:
	if _player == null or _duck <= 0.0:
		return
	_duck = maxf(0.0, _duck - delta / 3.0)
	_player.volume_db = target_db - 8.0 * _duck

func _exit_tree() -> void:
	if _player:
		_player.stop()
