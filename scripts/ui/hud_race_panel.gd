extends Control
## Top-left time-trial panel: clock, gate n/N, last split vs best, best lap.

const PANEL_RECT := Rect2(32, 32, 400, 156)

var _race: RaceSystem
var _split_show := 0.0
var _split_delta := 0.0
var _split_has := false
var _split_gate := 0
var _accum := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Game.checkpoint_passed.connect(_on_checkpoint)

func _on_checkpoint(index: int, _total: int, _split: float) -> void:
	if _race == null:
		return
	_split_gate = index
	_split_has = _race.has_last_delta
	_split_delta = _race.last_split_delta
	_split_show = 4.0

func _process(delta: float) -> void:
	if _race == null or not is_instance_valid(_race):
		_race = get_tree().get_first_node_in_group(&"race_system") as RaceSystem
	_split_show = maxf(0.0, _split_show - delta)
	_accum += delta
	if _accum >= 1.0 / 30.0:
		_accum = 0.0
		queue_redraw()

func _draw() -> void:
	# The Meridian Circuit is Meridian's: nothing to show at another station.
	if Game.sector != Sectors.MERIDIAN:
		return
	if _race == null or _race.gate_count() < 2:
		return
	var r := PANEL_RECT
	HudStyle.draw_panel(self, r)
	var o := r.position + Vector2(22, 0)
	var total := _race.gate_count()
	var running := _race.state == RaceSystem.State.RUNNING
	var counting := _race.state == RaceSystem.State.COUNTDOWN
	HudStyle.label(self, o + Vector2(0, 28), "Time trial  ·  Meridian circuit", HudStyle.CYAN)

	var t := _race.race_time
	var tcol := HudStyle.WHITE
	if not running and not counting:
		if _race.finish_display_time > 0.0:
			t = _race.last_finish_time
			tcol = HudStyle.GREEN if _race.last_finish_was_best else HudStyle.WHITE
		else:
			t = 0.0
			tcol = HudStyle.MUTED
	HudStyle.text(self, o + Vector2(0, 80), GameplayUtil.format_time(t), 48, tcol, HORIZONTAL_ALIGNMENT_LEFT, -1, HudStyle.mono())

	# Gate counter.
	var gate_txt := "GATE %d/%d" % [mini(_race.next_index + 1, total), total] if running or counting else "READY"
	HudStyle.text(self, o + Vector2(236, 62), gate_txt, 20, HudStyle.CYAN if running else HudStyle.MUTED)

	# Last split delta (green = ahead of best).
	if _split_show > 0.0 and running:
		var a := clampf(_split_show, 0.0, 1.0)
		if _split_has:
			var col := HudStyle.GREEN if _split_delta <= 0.0 else HudStyle.RED
			col.a = a
			HudStyle.text(self, o + Vector2(236, 86), GameplayUtil.format_delta(_split_delta), 22, col, HORIZONTAL_ALIGNMENT_LEFT, -1, HudStyle.mono())
		else:
			HudStyle.text(self, o + Vector2(236, 86), "SPLIT %d" % _split_gate, 18, Color(HudStyle.WHITE, a))

	# Best + hint line.
	var best := "BEST  " + (GameplayUtil.format_time(_race.best_time) if _race.best_time < INF else "--:--.--")
	HudStyle.text(self, o + Vector2(0, 112), best, 18, HudStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, -1, HudStyle.mono())
	var hint := ""
	if not running and not counting:
		hint = "Fly through START or press R"
	elif running:
		hint = "R restart  ·  T back to last gate"
	HudStyle.text(self, o + Vector2(0, 140), hint, 15, HudStyle.MUTED)
