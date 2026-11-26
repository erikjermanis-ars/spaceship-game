extends Camera2D
## Camera for scenes/test/level_tour.tscn. Either tours key areas of the
## level over time, or (with `-- --cam=x_m,y_m,zoom`) holds a fixed view.
## `--show-gates` draws the race course for layout review.

const STOPS := [
	# [centre (m), zoom, seconds]
	[Vector2(535, 230), 1.0, 3.0],     # spawn pad
	[Vector2(480, -100), 0.45, 3.0],   # spaceport
	[Vector2(0, -600), 0.5, 3.0],      # drydock
	[Vector2(-680, 0), 0.4, 3.0],      # solar array
	[Vector2(0, 0), 0.3, 3.0],         # ring
	[Vector2(0, 600), 0.5, 3.0],       # cargo yard
]

var _t := 0.0
var _fixed := false
var _fps_accum := 0.0
var _fps_min := 1000.0


func _ready() -> void:
	# Space background is another workstream's scene: add it only if present.
	var bg_path := "res://scenes/environment/space_background.tscn"
	var g0 := get_node_or_null(^"/root/Game")
	if ResourceLoader.exists(bg_path) and not (g0 and g0.cmd.has("no-bg")):
		var bg: Node = (load(bg_path) as PackedScene).instantiate()
		get_parent().add_child.call_deferred(bg)
		get_parent().move_child.call_deferred(bg, 0)
	var game := get_node_or_null(^"/root/Game")
	if game and game.cmd.has("no-level"):
		(get_parent().get_node(^"Level") as Node2D).visible = false
	if game and game.cmd.has("show-gates"):
		var ov := Node2D.new()
		ov.z_index = 100
		ov.z_as_relative = false
		ov.draw.connect(_draw_gates.bind(ov))
		get_parent().add_child.call_deferred(ov)
	if game and game.cmd.has("cam"):
		var p := String(game.cmd["cam"]).split(",")
		position = Vector2(float(p[0]), float(p[1])) * 10.0
		var z := float(p[2]) if p.size() > 2 else 1.0
		zoom = Vector2(z, z)
		_fixed = true
	else:
		position = STOPS[0][0] * 10.0
	make_current()


func _process(delta: float) -> void:
	var game := get_node_or_null(^"/root/Game")
	if game and game.cmd.has("hide-band"):
		for n in get_tree().root.find_children("Band_" + String(game.cmd["hide-band"]), "", true, false):
			(n as CanvasItem).visible = false
	if game and game.cmd.has("fps"):
		_fps_accum += delta
		if _fps_accum >= 1.0:
			_fps_accum = 0.0
			var f := Engine.get_frames_per_second()
			if _t > 1.5:
				_fps_min = minf(_fps_min, f)
			print("[fps] t=%.1f fps=%d min=%d draw_calls=%d objects=%d" % [_t, f, int(_fps_min),
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])
	if _fixed:
		_t += delta
		return
	_t += delta
	var acc := 0.0
	for i in STOPS.size():
		var d: float = STOPS[i][2]
		if _t < acc + d or i == STOPS.size() - 1:
			var k := clampf((_t - acc) / d, 0.0, 1.0)
			var nxt: Array = STOPS[mini(i + 1, STOPS.size() - 1)]
			var e := smoothstep(0.6, 1.0, k)
			position = (STOPS[i][0] as Vector2).lerp(nxt[0], e) * 10.0
			var z := lerpf(STOPS[i][1], nxt[1], e)
			zoom = Vector2(z, z)
			return
		acc += d


## Layout review overlay: gate spans (white), direction arrows, numbers and
## the ideal racing polyline between gate centres.
func _draw_gates(ov: Node2D) -> void:
	var course := get_parent().get_node_or_null(^"Level/RaceCourse")
	if course == null:
		return
	var prev := Vector2.INF
	var font := ThemeDB.fallback_font
	for g in course.get_children():
		var mk := g as Marker2D
		var w: float = mk.get_meta("width_m", 40.0) * 10.0
		var x := mk.global_transform.x.normalized()
		var y := mk.global_transform.y.normalized()
		var c := mk.global_position
		ov.draw_line(c - y * w * 0.5, c + y * w * 0.5, Color(1, 1, 1, 0.9), 8.0)
		ov.draw_circle(c - y * w * 0.5, 14.0, Color(1, 0.3, 0.3))
		ov.draw_circle(c + y * w * 0.5, 14.0, Color(0.3, 1, 0.4))
		ov.draw_line(c, c + x * 120.0, Color(1, 0.9, 0.2), 6.0)
		ov.draw_string(font, c + Vector2(30, -30), String(mk.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 90, Color(1, 1, 0.4))
		if prev != Vector2.INF:
			ov.draw_line(prev, c, Color(1, 0.9, 0.2, 0.35), 4.0)
		prev = c
