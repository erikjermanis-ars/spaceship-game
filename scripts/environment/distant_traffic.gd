class_name DistantTraffic
extends Node2D
## Far-away ships crossing the sky: a bright engine dot, a fading exhaust
## trail and a blinking nav light. Lanes are generated from a seed so the
## backdrop is identical every run. Redrawn every frame, but it is only a few
## dozen tiny draw calls.

var lane_count := 10
var area := Rect2(-3500, -2500, 7000, 5000)
var speed_range := Vector2(30.0, 90.0)
var dot_size := 9.0
var brightness := 1.0
var seed_value := 1

var _lanes: Array[Dictionary] = []
var _time := 0.0


func setup(p_seed: int, count: int, p_area: Rect2, p_speed: Vector2, p_dot: float, p_brightness: float) -> void:
	seed_value = p_seed
	lane_count = count
	area = p_area
	speed_range = p_speed
	dot_size = p_dot
	brightness = p_brightness
	material = EnvArt.additive_material()
	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed
	# Traffic follows a few shared "lanes" (directions), like real routes.
	var headings := [rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU]
	for i in count:
		var h: float = headings[i % headings.size()] + rng.randf_range(-0.08, 0.08)
		var dir := Vector2.from_angle(h)
		var start := Vector2(rng.randf_range(area.position.x, area.end.x), rng.randf_range(area.position.y, area.end.y))
		var length := rng.randf_range(2500.0, 5500.0)
		var palette := [Color(1.0, 0.93, 0.80), EnvArt.TECH_CYAN, EnvArt.WINDOW_WARM, Color(0.85, 0.9, 1.0)]
		_lanes.append({
			"start": start - dir * length * 0.5,
			"dir": dir,
			"length": length,
			"speed": rng.randf_range(speed_range.x, speed_range.y),
			"offset": rng.randf() * length,
			"color": palette[rng.randi() % palette.size()],
			"trail": rng.randf_range(25.0, 60.0),
			"blink": rng.randf() * 2.0,
		})


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	for l in _lanes:
		var length: float = l["length"]
		var d: float = fposmod(float(l["offset"]) + _time * float(l["speed"]), length)
		var u := d / length
		# Fade in/out at lane ends so ships never pop.
		var fade := smoothstep(0.0, 0.08, u) * (1.0 - smoothstep(0.92, 1.0, u))
		if fade <= 0.0:
			continue
		var dir: Vector2 = l["dir"]
		var p: Vector2 = l["start"] + dir * d
		var c: Color = l["color"]
		var tl: float = l["trail"]
		# Exhaust trail: a few segments with decreasing alpha.
		var segs := 5
		for s in segs:
			var a0 := float(s) / float(segs)
			var a1 := float(s + 1) / float(segs)
			var alpha := (1.0 - a0) * 0.22 * fade * brightness
			draw_line(p - dir * tl * a0, p - dir * tl * a1, Color(c.r, c.g * 0.95, c.b, alpha), 1.4, true)
		EnvArt.draw_glow(self, p, dot_size, Color(c, 0.85 * fade * brightness))
		var bl := EnvArt.blink(_time, 1.5, l["blink"], 8.0)
		if bl > 0.02:
			EnvArt.draw_glow(self, p + dir.orthogonal() * 3.0, dot_size * 0.9, Color(EnvArt.NAV_RED, bl * fade * brightness))
