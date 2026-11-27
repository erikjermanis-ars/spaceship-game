extends Control
## Points at the next race gate: corner brackets + distance when it is on
## screen, an edge arrow + distance when it is off screen.

const EDGE_MARGIN := 70.0
const RacePanel := preload("res://scripts/ui/hud_race_panel.gd")
const FlightPanel := preload("res://scripts/ui/hud_flight_panel.gd")

var _t := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	# The Meridian Circuit is Meridian's: nothing to show at another station.
	if Game.sector != Sectors.MERIDIAN:
		return
	var race := get_tree().get_first_node_in_group(&"race_system") as RaceSystem
	if race == null or not GameplayUtil.player_alive():
		return
	var g := race.next_gate()
	if g == null:
		return
	var ct := get_viewport().get_canvas_transform()
	var sp := ct * g.global_position
	var dist_m := Game.player.global_position.distance_to(g.global_position) / Game.PX_PER_M
	var col := RaceGateVisual.COL_FINISH if race.next_index == race.gate_count() - 1 else HudStyle.CYAN
	var pulse := 0.75 + 0.25 * sin(_t * 5.0)
	var label := "START" if race.state == RaceSystem.State.IDLE else ("FINISH" if race.next_index == race.gate_count() - 1 else "GATE %d" % (race.next_index + 1))
	var dist_txt := "%d m" % int(dist_m)
	var view := Rect2(Vector2.ZERO, size).grow(-EDGE_MARGIN)
	var centre := size * 0.5
	var blocker := _panel_covering(sp)
	if view.has_point(sp) and blocker.size == Vector2.ZERO:
		# Brackets sized by the gate's on-screen width.
		var half := float(g.get_meta(&"width_m", 40.0)) * 0.5 * Game.PX_PER_M * ct.get_scale().x
		var s := clampf(half * 0.35, 18.0, 60.0)
		var c := Color(col, 0.7 * pulse)
		for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var p: Vector2 = sp + corner * s
			draw_line(p, p - Vector2(corner.x * s * 0.4, 0), c, 2.0, true)
			draw_line(p, p - Vector2(0, corner.y * s * 0.4), c, 2.0, true)
		HudStyle.text(self, sp + Vector2(-80, -s - 10), "%s · %s" % [label, dist_txt], 16, c, HORIZONTAL_ALIGNMENT_CENTER, 160)
		return
	# Off screen (or hidden behind a HUD panel): arrow on the screen edge, or
	# on the panel's edge, in the gate's direction.
	var dir := (sp - centre).normalized()
	var p2 := _edge_point(centre, dir, view)
	if blocker.size == Vector2.ZERO:
		blocker = _panel_covering(p2)
	if blocker.size != Vector2.ZERO:
		var entry := _entry_point(centre, dir, blocker)
		if centre.distance_to(entry) < centre.distance_to(p2):
			p2 = entry - dir * 34.0
	var c2 := Color(col, pulse)
	var side := dir.orthogonal()
	var tri := PackedVector2Array([p2 + dir * 26.0, p2 - dir * 10.0 + side * 11.0, p2 - dir * 4.0, p2 - dir * 10.0 - side * 11.0])
	draw_colored_polygon(tri, c2)
	draw_arc(p2, 30.0, 0.0, TAU, 32, Color(col, 0.25), 1.5, true)
	var tp := p2 - dir * 52.0
	# Dark backing so the label stays readable over white hulls.
	draw_rect(Rect2(tp + Vector2(-52, -17), Vector2(104, 44)), Color(0.02, 0.05, 0.1, 0.7))
	HudStyle.text(self, tp + Vector2(-80, 0), label, 15, Color(col, 0.9), HORIZONTAL_ALIGNMENT_CENTER, 160)
	HudStyle.text(self, tp + Vector2(-80, 20), dist_txt, 20, HudStyle.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 160, HudStyle.mono())

## Where a ray from the centre leaves `r`.
func _edge_point(c: Vector2, d: Vector2, r: Rect2) -> Vector2:
	var tx := INF
	var ty := INF
	if absf(d.x) > 0.0001:
		tx = ((r.end.x if d.x > 0.0 else r.position.x) - c.x) / d.x
	if absf(d.y) > 0.0001:
		ty = ((r.end.y if d.y > 0.0 else r.position.y) - c.y) / d.y
	return c + d * minf(tx, ty)

## The HUD panel rectangle (grown by a margin) that covers screen point `p`,
## or an empty Rect2. Keeps the gate marker from drawing over panel text.
func _panel_covering(p: Vector2) -> Rect2:
	var panels: Array[Rect2] = [
		RacePanel.PANEL_RECT,
		Rect2(Vector2(FlightPanel.MARGIN.x, size.y - FlightPanel.MARGIN.y - FlightPanel.PANEL_SIZE.y), FlightPanel.PANEL_SIZE),
	]
	var radar := get_tree().get_first_node_in_group(&"hud_radar")
	if radar != null and radar.has_method(&"small_scope_rect") and not bool(radar.get(&"expanded")):
		panels.append(radar.call(&"small_scope_rect"))
	for r in panels:
		var g := r.grow(40.0)
		if g.has_point(p):
			return g
	return Rect2()

## Where a ray from `c` (outside `r`) first enters `r` (slab method).
func _entry_point(c: Vector2, d: Vector2, r: Rect2) -> Vector2:
	var t0 := -INF
	var t1 := INF
	for axis in 2:
		var o := c[axis]
		var v := d[axis]
		var lo := r.position[axis]
		var hi := r.end[axis]
		if absf(v) < 0.0001:
			continue
		var a := (lo - o) / v
		var b := (hi - o) / v
		t0 = maxf(t0, minf(a, b))
		t1 = minf(t1, maxf(a, b))
	return c + d * maxf(t0, 0.0)
