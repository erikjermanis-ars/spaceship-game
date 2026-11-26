extends Node2D
## Race-course flyability check (run headless):
##   Godot --headless --path . --fixed-fps 120 res://scenes/test/gate_clearance_check.tscn
## Loads the level on its own and, for every RaceCourse gate, samples LAYER_WORLD
## collision over 30 s of simulated time (so moving structure — the ring, crane
## and blast doors — is caught in different poses):
##   * gate centre (intersect_point)
##   * full gate span, as a thin box along the marker's local Y (intersect_shape)
##   * the two pylon discs at ±width/2 (RaceSystem builds solid pylons there)
##   * a ship-sized (10 m) corridor 30 m before → 30 m after the gate along +X
## Reports the fraction of samples where each probe is blocked. A static block
## (100 %) is a failure; partial blocks are reported as moving hazards.

const LEVEL := preload("res://scenes/level/level.tscn")
const SAMPLE_EVERY := 0.25
const DURATION := 30.0
const PYLON_R_M := 1.4

var _level: Node2D
var _gates: Array[Marker2D] = []
var _hits := {}     # gate name -> {probe: count}
var _samples := 0
var _sim := 0.0
var _next := 0.5


func _ready() -> void:
	_level = LEVEL.instantiate()
	add_child(_level)
	for c in _level.get_node(^"RaceCourse").get_children():
		if c is Marker2D:
			_gates.append(c)
			_hits[c.name] = {"centre": 0, "span": 0, "pylon_a": 0, "pylon_b": 0, "corridor": 0}


func _physics_process(delta: float) -> void:
	_sim += delta
	if _sim >= _next:
		_next += SAMPLE_EVERY
		_sample()
	if _sim >= DURATION:
		_report()
		get_tree().quit()


func _query(shape: Shape2D, xf: Transform2D) -> bool:
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	q.transform = xf
	q.collision_mask = Game.LAYER_WORLD
	q.collide_with_areas = false
	return not get_world_2d().direct_space_state.intersect_shape(q, 1).is_empty()


func _sample() -> void:
	_samples += 1
	var space := get_world_2d().direct_space_state
	for g in _gates:
		var h: Dictionary = _hits[g.name]
		var w_px: float = float(g.get_meta("width_m", 40.0)) * Game.PX_PER_M
		var xf := g.global_transform
		var pq := PhysicsPointQueryParameters2D.new()
		pq.position = xf.origin
		pq.collision_mask = Game.LAYER_WORLD
		if not space.intersect_point(pq, 1).is_empty():
			h.centre += 1
		# Span: the inner 90 % between the posts (posts themselves checked separately).
		var span := RectangleShape2D.new()
		span.size = Vector2(4.0, w_px * 0.9)
		if _query(span, xf):
			h.span += 1
		var disc := CircleShape2D.new()
		disc.radius = PYLON_R_M * Game.PX_PER_M
		var y_axis := xf.y.normalized()
		if _query(disc, Transform2D(0.0, xf.origin + y_axis * w_px * 0.5)):
			h.pylon_a += 1
		if _query(disc, Transform2D(0.0, xf.origin - y_axis * w_px * 0.5)):
			h.pylon_b += 1
		var corr := RectangleShape2D.new()
		corr.size = Vector2(600.0, 100.0)
		if _query(corr, xf):
			h.corridor += 1


func _report() -> void:
	var fails := 0
	print("\n===== GATE CLEARANCE (%d samples over %.0f s) =====" % [_samples, DURATION])
	for g in _gates:
		var h: Dictionary = _hits[g.name]
		var parts: Array[String] = []
		var bad := false
		for k in h:
			var frac: float = float(h[k]) / float(_samples)
			if frac > 0.0:
				parts.append("%s %.0f%%" % [k, frac * 100.0])
			# A probe blocked in (almost) every sample means static geometry.
			if frac > 0.95 and k != "corridor":
				bad = true
		var status := "FAIL" if bad else ("WARN" if not parts.is_empty() else "OK  ")
		if bad:
			fails += 1
		print("  %s %s at (%.0f, %.0f) m w=%.0f m  %s" % [status, g.name,
			g.global_position.x / Game.PX_PER_M, g.global_position.y / Game.PX_PER_M,
			float(g.get_meta("width_m", 40.0)), ", ".join(parts) if not parts.is_empty() else "clear"])
	print("RESULT: %s (%d gates blocked by static geometry)" % ["OK" if fails == 0 else "FAIL", fails])
