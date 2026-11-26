extends Control
## Radar / station map. Bottom-right circular scope centred on the ship;
## M expands it into a large map of the whole control space. Orientation
## always matches the screen (follows the camera's rotation mode).
##
## Structures come from group `radar_structure` (get_radar_polygons(), global
## coords) and are drawn as clipped schematic outlines. Blips: radar_prop
## (grey), radar_traffic (amber), docking pads (green), race gates (cyan,
## next one pulsing), the player (white chevron).

const SMALL_RADIUS := 150.0
const SMALL_RANGE_M := 420.0
const MARGIN := 32.0
const POLY_REFRESH := 0.1
const REDRAW := 1.0 / 30.0
## Width the tuning panel covers on the right (tuning_panel.gd offset_left).
const TUNING_PANEL_W := 430.0

var expanded := false
var _k := 0.0                    # 0 small .. 1 expanded (animated)
var _polys: Array[PackedVector2Array] = []
var _poly_boxes: Array[Rect2] = []
var _poly_timer := 0.0
var _redraw_timer := 0.0
var _t := 0.0
var _circle_cache := {}          # radius -> PackedVector2Array
var _shift := 0.0                # px the small scope moves left (tuning panel open)

func _ready() -> void:
	add_to_group(&"hud_radar")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

func _toggle_input() -> void:
	if Input.is_action_just_pressed(&"radar_toggle"):
		expanded = not expanded
		GameplayUtil.play_oneshot(self, GameplayUtil.load_audio("ui_click.wav"), -10.0, 1.0, &"UI")

func _process(delta: float) -> void:
	_toggle_input()
	_t += delta
	_k = move_toward(_k, 1.0 if expanded else 0.0, delta * 4.0)
	var tp := get_tree().get_first_node_in_group(&"tuning_panel") as CanvasLayer
	var want_shift := TUNING_PANEL_W if tp != null and tp.visible else 0.0
	_shift = move_toward(_shift, want_shift, delta * 2400.0)
	_poly_timer -= delta
	if _poly_timer <= 0.0:
		_poly_timer = POLY_REFRESH
		_refresh_polys()
	_redraw_timer -= delta
	if _redraw_timer <= 0.0:
		_redraw_timer = REDRAW
		queue_redraw()

func _refresh_polys() -> void:
	_polys.clear()
	_poly_boxes.clear()
	for n in get_tree().get_nodes_in_group(&"radar_structure"):
		if not n.has_method(&"get_radar_polygons"):
			continue
		for p in n.call(&"get_radar_polygons"):
			var poly := p as PackedVector2Array
			if poly.size() < 2:
				continue
			_polys.append(poly)
			var box := Rect2(poly[0], Vector2.ZERO)
			for v in poly:
				box = box.expand(v)
			_poly_boxes.append(box)

# ---------------------------------------------------------------- draw ---
func _draw() -> void:
	if not GameplayUtil.player_valid():
		return
	var e := _k * _k * (3.0 - 2.0 * _k)   # smoothstep
	var small_c := small_scope_rect().get_center()
	var big_r := minf(size.y * 0.42, size.x * 0.3)
	var big_c := size * 0.5
	var radius := lerpf(SMALL_RADIUS, big_r, e)
	var center := small_c.lerp(big_c, e)
	var b := Game.world_bounds
	var big_range_m := maxf(b.size.x, b.size.y) * 0.5 / Game.PX_PER_M * 1.04
	var range_m := lerpf(SMALL_RANGE_M, big_range_m, e)
	var focus := Game.player.global_position.lerp(b.get_center(), e)
	var scale_px := radius / (range_m * Game.PX_PER_M)     # screen px per world px
	var rot := get_viewport().get_canvas_transform().get_rotation()
	var xf := Transform2D(rot, Vector2.ONE * scale_px, 0.0, center) * Transform2D(0.0, -focus)

	# Scope background.
	# Near-opaque: bright pearl hulls under the scope must not bleed through.
	draw_circle(center, radius + 6.0, Color(0.0, 0.0, 0.0, 0.4))
	draw_circle(center, radius, Color(0.02, 0.05, 0.1, lerpf(0.9, 0.96, e)))
	for ring in [0.33, 0.66]:
		draw_arc(center, radius * ring, 0.0, TAU, 64, Color(0.5, 0.9, 1.0, 0.1), 1.0, true)
	draw_line(center - Vector2(radius, 0), center + Vector2(radius, 0), Color(0.5, 0.9, 1.0, 0.06), 1.0)
	draw_line(center - Vector2(0, radius), center + Vector2(0, radius), Color(0.5, 0.9, 1.0, 0.06), 1.0)

	# Structures: transform, clip to the scope, draw as outlines.
	var view := Rect2(focus - Vector2.ONE * range_m * Game.PX_PER_M * 1.5, Vector2.ONE * range_m * Game.PX_PER_M * 3.0)
	var clip := _circle(radius - 1.0, center)
	var scol := Color(0.86, 0.92, 0.97, 0.75)
	for i in _polys.size():
		if not view.intersects(_poly_boxes[i]):
			continue
		var local := xf * _polys[i]
		local.append(local[0])
		for seg in Geometry2D.intersect_polyline_with_polygon(local, clip):
			draw_polyline(seg, scol, 1.4, true)

	# Blips.
	for n in get_tree().get_nodes_in_group(&"radar_prop"):
		_blip(xf, center, radius, (n as Node2D).global_position, Color(0.7, 0.75, 0.8, 0.8), 2.0)
	for n in get_tree().get_nodes_in_group(&"radar_traffic"):
		var p := xf * (n as Node2D).global_position
		if p.distance_to(center) < radius - 4.0:
			var hd := Vector2.from_angle((n as Node2D).global_rotation + rot)
			_chevron(p, hd, 6.0, HudStyle.AMBER)
	for n in get_tree().get_nodes_in_group(&"docking_pad"):
		var p2 := xf * (n as Node2D).global_position
		if p2.distance_to(center) < radius - 4.0:
			draw_rect(Rect2(p2 - Vector2(4, 4), Vector2(8, 8)), Color(0.23, 1.0, 0.48, 0.85), false, 1.5)
	_draw_gates(xf, center, radius)

	# Player.
	var pp := xf * Game.player.global_position
	_chevron(pp, Vector2.from_angle(Game.player.global_rotation + rot), 9.0, HudStyle.WHITE)

	# Rim, north marker and caption.
	draw_arc(center, radius, 0.0, TAU, 96, Color(0.5, 0.9, 1.0, 0.65), 1.5, true)
	var north := Vector2.from_angle(rot - PI * 0.5)
	var np := center + north * (radius + 14.0)
	draw_circle(np, 11.0, Color(0.02, 0.05, 0.1, 0.8))
	HudStyle.text(self, np + Vector2(-5, 6), "N", 14, HudStyle.CYAN)
	for i in 12:
		var a := rot + TAU * i / 12.0
		var d := Vector2.from_angle(a)
		draw_line(center + d * (radius - 6.0), center + d * radius, Color(0.5, 0.9, 1.0, 0.5), 1.0, true)
	var cap := "MAP · M to close" if expanded else "RADAR %d m · M map" % int(range_m)
	var cap_w := HudStyle.font().get_string_size(cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 18.0
	draw_rect(Rect2(center + Vector2(-cap_w * 0.5, radius + 10.0), Vector2(cap_w, 22.0)), Color(0.02, 0.05, 0.1, 0.8))
	HudStyle.text(self, center + Vector2(-radius, radius + 26.0), cap, 14, HudStyle.MUTED, HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0)

## Screen rect of the small (collapsed) scope; the gate pointer avoids it.
func small_scope_rect() -> Rect2:
	var d := SMALL_RADIUS * 2.0
	return Rect2(size - Vector2(MARGIN + d + _shift, MARGIN + d), Vector2(d, d))

func _draw_gates(xf: Transform2D, center: Vector2, radius: float) -> void:
	var race := get_tree().get_first_node_in_group(&"race_system") as RaceSystem
	if race == null:
		return
	for i in race.gates.size():
		var g := race.gates[i]
		if not is_instance_valid(g):
			continue
		var p := xf * g.global_position
		var is_next := i == race.next_index
		var inside := p.distance_to(center) < radius - 6.0
		if is_next:
			var pulse := 0.6 + 0.4 * sin(_t * 6.0)
			if not inside:
				# Pin to the rim, pointing outwards.
				var dir := (p - center).normalized()
				p = center + dir * (radius - 8.0)
				_chevron(p, dir, 8.0, Color(HudStyle.CYAN, pulse))
			else:
				_diamond(p, 7.0, Color(HudStyle.CYAN, pulse), true)
		elif inside:
			var passed := race.state != RaceSystem.State.IDLE and i < race.next_index
			_diamond(p, 4.0, Color(0.5, 0.9, 1.0, 0.18 if passed else 0.45), false)

func _blip(xf: Transform2D, center: Vector2, radius: float, world: Vector2, col: Color, r: float) -> void:
	var p := xf * world
	if p.distance_to(center) < radius - 3.0:
		draw_circle(p, r, col)

func _chevron(p: Vector2, dir: Vector2, s: float, col: Color) -> void:
	var side := dir.orthogonal()
	var pts := PackedVector2Array([p + dir * s, p - dir * s * 0.7 + side * s * 0.75, p - dir * s * 0.3, p - dir * s * 0.7 - side * s * 0.75])
	draw_colored_polygon(pts, col)

func _diamond(p: Vector2, s: float, col: Color, filled: bool) -> void:
	var pts := PackedVector2Array([p + Vector2(0, -s), p + Vector2(s, 0), p + Vector2(0, s), p + Vector2(-s, 0)])
	if filled:
		draw_colored_polygon(pts, col)
	else:
		pts.append(pts[0])
		draw_polyline(pts, col, 1.5, true)

func _circle(r: float, c: Vector2) -> PackedVector2Array:
	var key := int(r)
	if not _circle_cache.has(key):
		var pts := PackedVector2Array()
		for i in 48:
			pts.append(Vector2.from_angle(TAU * i / 48.0) * float(key))
		_circle_cache[key] = pts
		if _circle_cache.size() > 64:
			_circle_cache.clear()
			_circle_cache[key] = pts
	var out: PackedVector2Array = _circle_cache[key]
	var moved := PackedVector2Array()
	moved.resize(out.size())
	for i in out.size():
		moved[i] = out[i] + c
	return moved
