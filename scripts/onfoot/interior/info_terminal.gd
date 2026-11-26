@tool
class_name InfoTerminal
extends Interactable
## Reads out a short text (station log, notices) through the HUD toasts.
## Each use shows the next entry. Pure data: edit `entries` in the scene.

@export var entries: PackedStringArray = PackedStringArray(["Nothing new."])
@export var title := "TERMINAL"

var _i := 0


func _ready() -> void:
	reach_m = 1.6
	if not Engine.is_editor_hint():
		add_to_group(&"persist")


func _use(_by: Node2D) -> void:
	if entries.is_empty():
		return
	var e := entries[_i % entries.size()]
	_i += 1
	GameplayUtil.play_oneshot(self, GameplayUtil.load_audio("console_beep.wav"), -8.0, 1.0 + 0.06 * (_i % 3))
	Game.toast("%s  ·  %s" % [title, e], 4.5)
	prompt = "Next entry (%d/%d)" % [(_i % entries.size()) + 1, entries.size()]


func save_state() -> Dictionary:
	return {"i": _i}


func load_state(d: Dictionary) -> void:
	_i = int(d.get("i", 0))
