extends Node2D
## Positional ambient loop (station machinery hum by default). Place near big
## structures; Godot attenuates it against the active Camera2D.

@export_file("*.wav", "*.ogg") var stream_path := "res://assets/audio/station_hum_loop.wav"
@export var max_distance_m := 260.0
@export var volume_db := -6.0
@export var pitch := 1.0
@export var attenuation := 1.4

var player: AudioStreamPlayer2D


func _ready() -> void:
	var game := get_node_or_null(^"/root/Game")
	if game == null or not ResourceLoader.exists(stream_path) or not LevelArt.audio_enabled():
		return
	player = AudioStreamPlayer2D.new()
	player.stream = game.get_loop(stream_path)
	player.bus = &"Ambient"
	player.max_distance = max_distance_m * 10.0
	player.attenuation = attenuation
	player.volume_db = volume_db
	player.pitch_scale = pitch
	add_child(player)
	# random start offset so several hums don't phase together
	player.play(randf() * 3.0)
