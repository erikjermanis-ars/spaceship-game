extends Control
## P / Esc pauses the whole tree. This node keeps processing while paused
## so it can resume; the help overlay (H) also works while paused.

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed(&"pause"):
		var tree := get_tree()
		tree.paused = not tree.paused
		visible = tree.paused
		# Make sure a hit-stop in progress can't leave the game in slow motion.
		if not tree.paused:
			Engine.time_scale = 1.0
		GameplayUtil.play_oneshot(self, GameplayUtil.load_audio("ui_click.wav"), -8.0, 0.9 if tree.paused else 1.1, &"UI")
		queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.01, 0.03, 0.55))
	var w := 520.0
	var r := Rect2(Vector2((size.x - w) * 0.5, size.y * 0.5 - 70.0), Vector2(w, 120))
	HudStyle.draw_panel(self, r, 16.0, Color(HudStyle.CYAN, 0.8), Color(0.02, 0.05, 0.1, 0.85))
	HudStyle.text(self, r.position + Vector2(0, 58), "PAUSED", 44, HudStyle.WHITE, HORIZONTAL_ALIGNMENT_CENTER, w)
	HudStyle.text(self, r.position + Vector2(0, 94), "P / Esc to resume  ·  H for controls", 18, HudStyle.MUTED, HORIZONTAL_ALIGNMENT_CENTER, w)
