extends SceneTree
## Builds res://default_bus_layout.tres (Godot loads it automatically at startup).
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tools/audio/make_bus_layout.gd
## Buses: Master (hard limiter) <- SFX (subtle small-room reverb), Engine, Ambient, UI.

func _init() -> void:
	# Start from a clean single-bus state.
	while AudioServer.bus_count > 1:
		AudioServer.remove_bus(AudioServer.bus_count - 1)
	while AudioServer.get_bus_effect_count(0) > 0:
		AudioServer.remove_bus_effect(0, 0)
	AudioServer.set_bus_name(0, "Master")

	# Many simultaneous impacts + engine + music can stack past 0 dBFS:
	# a transparent brick-wall limiter keeps the sum clean.
	var limiter := AudioEffectHardLimiter.new()
	limiter.resource_name = "HardLimiter"
	limiter.ceiling_db = -0.5
	limiter.pre_gain_db = 0.0
	limiter.release = 0.1
	AudioServer.add_bus_effect(0, limiter)

	for bus_name in ["SFX", "Engine", "Ambient", "UI"]:
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, &"Master")

	# A hint of hull/cabin space on collisions and cues; the sounds already
	# carry their own character, so keep it small and mostly dry.
	var verb := AudioEffectReverb.new()
	verb.resource_name = "Reverb"
	verb.room_size = 0.22
	verb.damping = 0.6
	verb.spread = 0.7
	verb.hipass = 0.12
	verb.predelay_msec = 12.0
	verb.predelay_feedback = 0.2
	verb.dry = 1.0
	verb.wet = 0.12
	AudioServer.add_bus_effect(AudioServer.get_bus_index(&"SFX"), verb)

	var layout := AudioServer.generate_bus_layout()
	var err := ResourceSaver.save(layout, "res://default_bus_layout.tres")
	print("saved default_bus_layout.tres: ", error_string(err))
	quit(0 if err == OK else 1)
