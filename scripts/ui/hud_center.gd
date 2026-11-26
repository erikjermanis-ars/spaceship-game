extends Control
## Centre-screen status: race countdown (3-2-1-GO), docking guidance,
## boundary warning and the destroyed/respawning card.

var _race: RaceSystem
var _dock: DockingSystem
var _bound: BoundarySystem
var _dmg: DamageSystem
var _count_pop := 0.0
var _count_val := -1
var _t := 0.0
var _dead_t := 0.0               # seconds since the ship was destroyed

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

func _process(delta: float) -> void:
	_t += delta
	if _race == null:
		_race = get_tree().get_first_node_in_group(&"race_system") as RaceSystem
		if _race:
			_race.countdown_tick.connect(_on_tick)
	if _dock == null:
		_dock = get_tree().get_first_node_in_group(&"docking_system") as DockingSystem
	if _bound == null:
		_bound = get_tree().get_first_node_in_group(&"boundary_system") as BoundarySystem
	if _dmg == null:
		_dmg = get_tree().get_first_node_in_group(&"damage_system") as DamageSystem
	_count_pop = maxf(0.0, _count_pop - delta)
	if GameplayUtil.player_valid() and not GameplayUtil.player_alive():
		_dead_t += delta
	else:
		_dead_t = 0.0
	queue_redraw()

func _on_tick(v: int) -> void:
	_count_val = v
	_count_pop = 1.0 if v > 0 else 1.2

func _draw() -> void:
	var c := size * 0.5
	# --- countdown ---
	if _count_pop > 0.0 and _count_val >= 0:
		var k := _count_pop
		var txt := str(_count_val) if _count_val > 0 else "GO"
		var fs := int(lerpf(110.0, 150.0, k * k))
		var col := HudStyle.WHITE if _count_val > 0 else HudStyle.GREEN
		col.a = clampf(k * 1.6, 0.0, 1.0)
		HudStyle.text(self, c + Vector2(-300, -120), txt, fs, col, HORIZONTAL_ALIGNMENT_CENTER, 600)
		draw_arc(c + Vector2(0, -160), 110.0 + (1.0 - k) * 40.0, 0.0, TAU, 64, Color(col, col.a * 0.4), 2.0, true)

	# --- destroyed ---
	if GameplayUtil.player_valid() and not GameplayUtil.player_alive():
		# Lower third, fading in after the first burst so the explosion's
		# fireball and shock ring are unobstructed at their peak.
		var a := clampf((_dead_t - 0.6) * 3.0, 0.0, 1.0)
		if a <= 0.0:
			return
		var r := Rect2(c + Vector2(-260, 210), Vector2(520, 96))
		HudStyle.draw_panel(self, r, 14.0, Color(HudStyle.RED, 0.8 * a), Color(0.12, 0.0, 0.0, 0.55 * a))
		HudStyle.text(self, r.position + Vector2(0, 46), "HULL BREACH", 36, Color(HudStyle.RED, a), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		var left := _dmg.respawn_countdown if _dmg else -1.0
		var sub := "Recovering ship…" if left < 0.0 else "Recovery drone launching in %.1f s" % left
		HudStyle.text(self, r.position + Vector2(0, 78), sub, 18, Color(HudStyle.WHITE, a), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		return

	# --- boundary ---
	if _bound and _bound.outside:
		var blink := 0.65 + 0.35 * sin(_t * 8.0)
		var r2 := Rect2(c + Vector2(-330, -300), Vector2(660, 84))
		HudStyle.draw_panel(self, r2, 12.0, Color(HudStyle.AMBER, blink), Color(0.1, 0.06, 0.0, 0.55))
		_stripes(Rect2(r2.position + Vector2(14, 8), Vector2(26, r2.size.y - 16)))
		_stripes(Rect2(Vector2(r2.end.x - 40, r2.position.y + 8), Vector2(26, r2.size.y - 16)))
		HudStyle.text(self, r2.position + Vector2(0, 40), "LEAVING STATION CONTROL SPACE", 28, Color(HudStyle.AMBER, blink), HORIZONTAL_ALIGNMENT_CENTER, r2.size.x)
		HudStyle.text(self, r2.position + Vector2(0, 68), "Turn back  ·  %d m outside the traffic perimeter" % int(_bound.distance_out_m), 17, HudStyle.WHITE, HORIZONTAL_ALIGNMENT_CENTER, r2.size.x)

	# --- docking ---
	if _dock and _dock.phase != DockingSystem.Phase.NONE:
		var visible_prompt := _dock.phase != DockingSystem.Phase.APPROACH or _dock.hint != ""
		if visible_prompt:
			var r3 := Rect2(c + Vector2(-220, 150), Vector2(440, 70))
			var title := ""
			var col2 := HudStyle.CYAN
			match _dock.phase:
				DockingSystem.Phase.APPROACH:
					title = "%s  ·  %s" % [_dock.pad_name.to_upper(), _dock.hint]
					col2 = HudStyle.AMBER
				DockingSystem.Phase.HOLDING:
					title = "DOCKING…  HOLD STEADY"
				DockingSystem.Phase.DOCKED:
					title = "DOCKED  ·  %s" % _dock.pad_name.to_upper()
					col2 = HudStyle.GREEN
			HudStyle.draw_panel(self, r3, 10.0, Color(col2, 0.7))
			HudStyle.text(self, r3.position + Vector2(0, 32), title, 20, col2, HORIZONTAL_ALIGNMENT_CENTER, r3.size.x)
			var bar := Rect2(r3.position + Vector2(40, 46), Vector2(r3.size.x - 80, 6))
			draw_rect(bar, Color(col2, 0.15))
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * _dock.progress, bar.size.y)), col2)
			# Docked and settled: you can get out and walk (OnFootDirector).
			if _dock.is_settled() and Game.mode == Game.Mode.FLIGHT:
				var pulse := 0.75 + 0.25 * sin(_t * 3.0)
				HudStyle.key_hint(self, r3.position + Vector2(r3.size.x * 0.5 - 70.0, r3.size.y + 40.0), "X", "Exit ship", pulse)

func _stripes(r: Rect2) -> void:
	# Amber hazard stripes: thin parallelograms rising to the right.
	draw_rect(r, Color(0.05, 0.04, 0.0, 0.6))
	var rise := 10.0
	var thick := 6.0
	var y := r.position.y + rise
	while y + thick <= r.end.y:
		var pts := PackedVector2Array([Vector2(r.position.x, y), Vector2(r.end.x, y - rise),
			Vector2(r.end.x, y - rise + thick), Vector2(r.position.x, y + thick)])
		draw_colored_polygon(pts, Color(HudStyle.AMBER, 0.85))
		y += thick * 2.0
