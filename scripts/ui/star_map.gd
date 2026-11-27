class_name StarMap
extends CanvasLayer
## The quantum drive's two screens.
##
## 1. THE STAR MAP (open at the bridge's nav table, or N at a frigate's
##    helm): the charted neighbourhood, where you are, and where the drive
##    can lock on. A/D or the mouse picks a destination, E / Enter / click
##    lays in the course, C clears it, Esc / N / X closes. Places without a
##    jump beacon are shown but can't be selected.
## 2. THE DRIVE STRIP (at a frigate's helm, bottom centre): the course, whether
##    the drive will spool and why not, the spool bar while J is held, and the
##    route with the ship's dot moving along it during the jump.
##
## Drawn in code like the rest of the HUD (HudStyle).

const MAP_SIZE := Vector2(1240, 700)
const MAP_SCALE := 1.55          ## screen px per map unit

var jump: JumpSystem
var selected: StringName = &""

var _view: Control
var _open := false
var _fade := 0.0
var _t := 0.0
var _locked_controls: Node
var _confirm_t := -1.0
var _stars: PackedVector2Array
var _snd := {}


func _ready() -> void:
	layer = 12
	process_mode = Node.PROCESS_MODE_INHERIT
	_view = Control.new()
	_view.name = "View"
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.draw.connect(_draw_view)
	add_child(_view)
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	for i in 260:
		_stars.append(Vector2(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.5, 0.5)))
	for n in ["starmap_open", "starmap_blip", "starmap_confirm"]:
		_snd[n] = GameplayUtil.load_audio(n + ".wav")


func is_open() -> bool:
	return _open


func open() -> void:
	if _open:
		return
	_open = true
	_confirm_t = -1.0
	selected = jump.course if jump.course != &"" else _first_reachable()
	GameplayUtil.play_oneshot(self, _snd["starmap_open"], -6.0, 1.0, &"UI")
	# Whoever was at the controls waits while the map is up.
	_locked_controls = null
	if Game.mode == Game.Mode.ON_FOOT and Game.walker and bool(Game.walker.get(&"controls_enabled")):
		_locked_controls = Game.walker
	elif Game.mode == Game.Mode.FLIGHT and GameplayUtil.player_valid() and bool(Game.player.get(&"controls_enabled")):
		_locked_controls = Game.player
	if _locked_controls:
		_locked_controls.set(&"controls_enabled", false)
	_view.mouse_filter = Control.MOUSE_FILTER_STOP


func close() -> void:
	if not _open:
		return
	_open = false
	if _locked_controls and is_instance_valid(_locked_controls):
		_locked_controls.set(&"controls_enabled", true)
		if _locked_controls.has_method(&"_latch_held_actions"):
			_locked_controls.call(&"_latch_held_actions")
	_locked_controls = null
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _first_reachable() -> StringName:
	for id: StringName in _reachable():
		return id
	return &""


func _reachable() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in Sectors.DEFS:
		if Sectors.has(id) and id != Game.sector:
			out.append(id)
	return out


func _process(delta: float) -> void:
	_t += delta
	_fade = move_toward(_fade, 1.0 if _open else 0.0, delta * 5.0)
	if _open:
		_tick_input(delta)
	_view.queue_redraw()


func _tick_input(delta: float) -> void:
	if _confirm_t >= 0.0:
		_confirm_t += delta
		if _confirm_t > 0.7:
			close()
		return
	var list := _reachable()
	var step := 0
	if Input.is_action_just_pressed(&"move_right") or Input.is_action_just_pressed(&"turn_right"):
		step = 1
	if Input.is_action_just_pressed(&"move_left") or Input.is_action_just_pressed(&"turn_left"):
		step = -1
	if step != 0 and not list.is_empty():
		var i := list.find(selected)
		selected = list[posmod(i + step, list.size())]
		GameplayUtil.play_oneshot(self, _snd["starmap_blip"], -8.0, 1.0, &"UI")
	if Input.is_action_just_pressed(&"interact") or Input.is_action_just_pressed(&"ui_accept"):
		_confirm()
	elif Input.is_action_just_pressed(&"camera_mode"):
		jump.set_course(&"")
		GameplayUtil.play_oneshot(self, _snd["starmap_blip"], -8.0, 0.8, &"UI")
	elif Input.is_action_just_pressed(&"pause") or Input.is_action_just_pressed(&"star_map") \
			or Input.is_action_just_pressed(&"disembark") or Input.is_action_just_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _confirm() -> void:
	if selected == &"" or not Sectors.has(selected) or selected == Game.sector:
		return
	jump.set_course(selected)
	_confirm_t = 0.0
	GameplayUtil.play_oneshot(self, _snd["starmap_confirm"], -5.0, 1.0, &"UI")
	var at_helm := Game.mode == Game.Mode.FLIGHT
	Game.toast("COURSE LAID IN  ·  %s  ·  %s" % [Sectors.display_name(selected),
		"clear the station, then hold J" if at_helm else "take the helm, clear the station, hold J"], 5.0)


func _input(event: InputEvent) -> void:
	if not _open or _confirm_t >= 0.0:
		return
	var mb := event as InputEventMouseButton
	var mm := event as InputEventMouseMotion
	if mb == null and mm == null:
		return
	var pos: Vector2 = (mb.position if mb else mm.position)
	var hit := _node_at(pos)
	if hit != &"" and Sectors.has(hit) and hit != Game.sector:
		if hit != selected:
			selected = hit
			GameplayUtil.play_oneshot(self, _snd["starmap_blip"], -8.0, 1.0, &"UI")
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_confirm()
	if mb:
		get_viewport().set_input_as_handled()


func _map_rect() -> Rect2:
	return Rect2((_view.size - MAP_SIZE) * 0.5, MAP_SIZE)


func _node_pos(id: StringName) -> Vector2:
	var r := _map_rect()
	return r.position + Vector2(r.size.x * 0.36, r.size.y * 0.52) + (Sectors.DEFS[id].map as Vector2) * MAP_SCALE


func _node_at(p: Vector2) -> StringName:
	for id: StringName in Sectors.DEFS:
		if _node_pos(id).distance_to(p) < 46.0:
			return id
	return &""


# ================================================================ drawing

func _draw_view() -> void:
	_draw_strip()
	if _fade > 0.01:
		_draw_map()


## Top-centre drive strip while flying a frigate.
func _draw_strip() -> void:
	var ship := Game.player as FrigateShip if GameplayUtil.player_alive() else null
	if ship == null or Game.mode != Game.Mode.FLIGHT or _fade > 0.5:
		return
	if jump.course == &"" and not jump.busy():
		return
	# Bottom centre, clear of the berth guidance (top) and the exit prompt.
	var c := Vector2(_view.size.x * 0.5, _view.size.y - 236.0)
	var w := 620.0
	var r := Rect2(c + Vector2(-w * 0.5, -30), Vector2(w, 86 if jump.busy() else 60))
	HudStyle.draw_panel(_view, r, 12.0)
	var from := jump.from_sector if jump.busy() else Game.sector
	var to := jump.to_sector if jump.busy() else jump.course
	var title := "QUANTUM DRIVE  ·  %s  ▸  %s" % [Sectors.display_name(from), Sectors.display_name(to)]
	HudStyle.text(_view, r.position + Vector2(0, 26), title, 18, HudStyle.WHITE, HORIZONTAL_ALIGNMENT_CENTER, w)
	if not jump.busy():
		var why := jump.blocker(ship)
		if why == "":
			var pulse := 0.65 + 0.35 * sin(_t * 5.0)
			HudStyle.text(_view, r.position + Vector2(0, 48), "DRIVE READY  ·  hold J to spool", 15, Color(HudStyle.GREEN, pulse), HORIZONTAL_ALIGNMENT_CENTER, w)
		else:
			HudStyle.text(_view, r.position + Vector2(0, 48), why, 15, HudStyle.AMBER, HORIZONTAL_ALIGNMENT_CENTER, w)
		return
	var bar := Rect2(r.position + Vector2(40, 58), Vector2(w - 80, 10))
	match jump.phase:
		JumpSystem.Phase.SPOOL:
			HudStyle.text(_view, r.position + Vector2(0, 48), "SPOOLING  ·  keep holding J", 15, HudStyle.CYAN, HORIZONTAL_ALIGNMENT_CENTER, w)
			HudStyle.seg_bar(_view, bar, jump.progress, HudStyle.CYAN, 32)
		_:
			var k := 0.0
			match jump.phase:
				JumpSystem.Phase.LEAP: k = 0.0
				JumpSystem.Phase.TUNNEL: k = jump.progress
				JumpSystem.Phase.ARRIVE: k = 1.0
			var ly := Sectors.distance_ly(from, to)
			var label := "FOLDING SPACE  ·  %.1f ly to run" % (ly * (1.0 - k)) if jump.phase != JumpSystem.Phase.ARRIVE else "DROPPING OUT"
			HudStyle.text(_view, r.position + Vector2(0, 48), label, 15, HudStyle.CYAN, HORIZONTAL_ALIGNMENT_CENTER, w)
			var a := bar.position + Vector2(0, 5)
			var b := a + Vector2(bar.size.x, 0)
			_view.draw_line(a, b, Color(HudStyle.CYAN, 0.35), 2.0)
			_view.draw_circle(a, 5.0, HudStyle.MUTED)
			_view.draw_circle(b, 5.0, HudStyle.GREEN)
			_view.draw_line(a, a.lerp(b, k), HudStyle.CYAN, 3.0)
			_view.draw_circle(a.lerp(b, k), 6.0, HudStyle.WHITE)


func _draw_map() -> void:
	var v := _view
	var a := _fade
	v.draw_rect(Rect2(Vector2.ZERO, v.size), Color(0.0, 0.01, 0.03, 0.72 * a))
	var r := _map_rect()
	var grow := (1.0 - a) * 30.0
	r = r.grow(-grow)
	HudStyle.draw_panel(v, r, 22.0, Color(HudStyle.PANEL_EDGE, 0.8 * a), Color(0.01, 0.03, 0.07, 0.94 * a))
	HudStyle.text(v, r.position + Vector2(34, 46), "STELLAR CARTOGRAPHY", 26, Color(HudStyle.WHITE, a))
	HudStyle.text(v, r.position + Vector2(34, 72), "QUANTUM DRIVE  ·  jump beacons in range", 15, Color(HudStyle.MUTED, a))
	# chart area: faint grid, background stars, range rings round "here"
	var chart := Rect2(r.position + Vector2(24, 96), Vector2(r.size.x * 0.66, r.size.y - 170))
	v.draw_rect(chart, Color(0.03, 0.07, 0.13, 0.75 * a))
	var gx := chart.position.x + 40.0
	while gx < chart.end.x:
		v.draw_line(Vector2(gx, chart.position.y), Vector2(gx, chart.end.y), Color(0.5, 0.9, 1.0, 0.05 * a), 1.0)
		gx += 60.0
	var gy := chart.position.y + 40.0
	while gy < chart.end.y:
		v.draw_line(Vector2(chart.position.x, gy), Vector2(chart.end.x, gy), Color(0.5, 0.9, 1.0, 0.05 * a), 1.0)
		gy += 60.0
	for i in _stars.size():
		var p := chart.get_center() + _stars[i] * chart.size
		var tw := 0.35 + 0.3 * sin(_t * (0.6 + (i % 7) * 0.2) + i)
		v.draw_rect(Rect2(p, Vector2(2, 2) if i % 9 == 0 else Vector2(1, 1)), Color(0.8, 0.9, 1.0, tw * a))
	v.draw_rect(chart, Color(HudStyle.PANEL_EDGE, 0.5 * a), false, 1.0)
	var here := Game.sector
	var hp := _node_pos(here)
	for k in 3:
		v.draw_arc(hp, 110.0 + k * 110.0, 0.0, TAU, 72, Color(0.5, 0.9, 1.0, 0.07 * a), 1.0, true)
	# routes from here
	for id: StringName in Sectors.DEFS:
		if id == here:
			continue
		var p := _node_pos(id)
		var beacon := Sectors.has(id)
		var is_course := id == jump.course
		var is_sel := id == selected
		var col := Color(0.5, 0.9, 1.0, (0.22 if beacon else 0.07) * a)
		if is_course:
			col = Color(1.0, 0.78, 0.35, 0.9 * a)
		elif is_sel:
			col = Color(0.5, 0.9, 1.0, 0.75 * a)
		_dashed(hp, p, col, 2.0 if (is_sel or is_course) else 1.0, 12.0 if beacon else 4.0)
		if is_course or is_sel:
			# a pip running along the route
			var k := fmod(_t * 0.35, 1.0)
			v.draw_circle(hp.lerp(p, k), 4.0, Color(col, a))
	# nodes
	for id: StringName in Sectors.DEFS:
		var d: Dictionary = Sectors.DEFS[id]
		var p := _node_pos(id)
		var beacon := bool(d.beacon)
		var col := HudStyle.CYAN if beacon else HudStyle.MUTED.darkened(0.25)
		if id == here:
			col = HudStyle.GREEN
		elif id == jump.course:
			col = Color(1.0, 0.78, 0.35)
		var rad := 11.0 if beacon else 7.0
		v.draw_circle(p, rad + 9.0, Color(col, 0.12 * a))
		v.draw_circle(p, rad, Color(col, a))
		v.draw_circle(p, rad - 4.0, Color(0.02, 0.05, 0.1, a))
		v.draw_circle(p, 3.0, Color(col, a))
		if not beacon:
			_dashed_ring(p, rad + 12.0, Color(col, 0.6 * a))
		if id == here:
			v.draw_arc(p, rad + 12.0 + 3.0 * sin(_t * 3.0), 0.0, TAU, 40, Color(col, 0.8 * a), 2.0, true)
			HudStyle.text(v, p + Vector2(-100, -34), "YOU ARE HERE", 13, Color(col, a), HORIZONTAL_ALIGNMENT_CENTER, 200)
		if id == selected and id != here:
			var s := rad + 20.0 + 3.0 * sin(_t * 6.0)
			for sx: float in [-1.0, 1.0]:
				for sy: float in [-1.0, 1.0]:
					var c := p + Vector2(sx, sy) * s
					v.draw_polyline(PackedVector2Array([c - Vector2(sx * 9, 0), c, c - Vector2(0, sy * 9)]), Color(HudStyle.WHITE, a), 2.0, true)
		HudStyle.text(v, p + Vector2(-140, rad + 34), String(d.name), 17, Color(HudStyle.WHITE if beacon else HudStyle.MUTED, a), HORIZONTAL_ALIGNMENT_CENTER, 280)
		HudStyle.text(v, p + Vector2(-140, rad + 54), String(d.kind), 13, Color(HudStyle.MUTED, a * (1.0 if beacon else 0.7)), HORIZONTAL_ALIGNMENT_CENTER, 280)
	# info panel
	var info := Rect2(Vector2(chart.end.x + 20, chart.position.y), Vector2(r.end.x - chart.end.x - 44, chart.size.y))
	v.draw_rect(info, Color(0.03, 0.07, 0.13, 0.75 * a))
	v.draw_rect(info, Color(HudStyle.PANEL_EDGE, 0.5 * a), false, 1.0)
	var o := info.position + Vector2(20, 0)
	if selected != &"" and Sectors.DEFS.has(selected):
		var d: Dictionary = Sectors.DEFS[selected]
		HudStyle.label(v, o + Vector2(0, 34), "DESTINATION", Color(HudStyle.MUTED, a))
		HudStyle.text(v, o + Vector2(0, 68), String(d.name), 24, Color(HudStyle.WHITE, a))
		HudStyle.text(v, o + Vector2(0, 92), String(d.kind), 15, Color(HudStyle.CYAN, a))
		var y := 132.0
		for line: String in d.notes:
			HudStyle.text(v, o + Vector2(0, y), line, 14, Color(HudStyle.MUTED, a), HORIZONTAL_ALIGNMENT_LEFT, info.size.x - 40)
			y += 22.0
		y += 18.0
		var ly := Sectors.distance_ly(here, selected)
		HudStyle.label(v, o + Vector2(0, y), "DISTANCE", Color(HudStyle.MUTED, a))
		HudStyle.text(v, o + Vector2(0, y + 30), "%.1f ly" % ly, 22, Color(HudStyle.WHITE, a), HORIZONTAL_ALIGNMENT_LEFT, -1, HudStyle.mono())
		HudStyle.label(v, o + Vector2(150, y), "TRANSIT", Color(HudStyle.MUTED, a))
		HudStyle.text(v, o + Vector2(150, y + 30), "%.0f s" % JumpSystem.TUNNEL_TIME, 22, Color(HudStyle.WHITE, a), HORIZONTAL_ALIGNMENT_LEFT, -1, HudStyle.mono())
		y += 74.0
		var status := "COURSE LAID IN" if selected == jump.course else "BEACON LOCKED  ·  ready to plot"
		var scol := Color(1.0, 0.78, 0.35) if selected == jump.course else HudStyle.GREEN
		v.draw_rect(Rect2(o + Vector2(0, y - 18), Vector2(info.size.x - 40, 28)), Color(scol, 0.12 * a))
		v.draw_rect(Rect2(o + Vector2(0, y - 18), Vector2(info.size.x - 40, 28)), Color(scol, 0.7 * a), false, 1.0)
		HudStyle.text(v, o + Vector2(10, y + 2), status, 15, Color(scol, a))
		y += 46.0
		HudStyle.text(v, o + Vector2(0, y), "The jump is flown from the helm:", 14, Color(HudStyle.MUTED, a))
		HudStyle.text(v, o + Vector2(0, y + 22), "undock, clear the station by a", 14, Color(HudStyle.MUTED, a))
		HudStyle.text(v, o + Vector2(0, y + 44), "ship's length, then hold J.", 14, Color(HudStyle.MUTED, a))
		HudStyle.text(v, o + Vector2(0, y + 78), "Ships parked on the flight deck", 14, Color(HudStyle.MUTED, a))
		HudStyle.text(v, o + Vector2(0, y + 100), "ride along.", 14, Color(HudStyle.MUTED, a))
	else:
		HudStyle.text(v, o + Vector2(0, 68), "No beacon in range", 20, Color(HudStyle.MUTED, a))
	# key hints
	var hx := r.position.x + 34.0
	var hy := r.end.y - 34.0
	for h: Array in [["A D", "Select"], ["E", "Lay in course"], ["C", "Clear course"], ["Esc", "Close"]]:
		hx += HudStyle.key_hint(v, Vector2(hx, hy), h[0], h[1], a, 16) + 30.0
	if _confirm_t >= 0.0:
		var k := clampf(_confirm_t / 0.5, 0.0, 1.0)
		v.draw_rect(r, Color(1.0, 0.85, 0.5, 0.12 * (1.0 - k) * a))


func _dashed(a: Vector2, b: Vector2, col: Color, width: float, dash: float) -> void:
	var d := b - a
	var L := d.length()
	if L < 1.0:
		return
	d /= L
	var x := 0.0
	while x < L:
		_view.draw_line(a + d * x, a + d * minf(x + dash, L), col, width, true)
		x += dash * 2.0


func _dashed_ring(c: Vector2, rad: float, col: Color) -> void:
	for i in 12:
		var a0 := TAU * i / 12.0
		_view.draw_arc(c, rad, a0, a0 + TAU / 24.0, 5, col, 1.5, true)
