@tool
extends StationModule
## Meridian's gunnery range: a marked patch of open space with target drones.
## A holographic boundary, patrol rings and a scoreboard projected on the
## "floor", amber buoys on the corners (small and solid, like the lane buoys)
## and the drones themselves. The "GUNNERY RANGE" sign is a HoloSign next to
## this node in level.tscn. Local origin = range centre, metres.
##
## Score: every drone hit counts; a streak is drones destroyed one after
## another with no more than STREAK_WINDOW_S between kills.

const DRONE := preload("res://scripts/level/target_drone.gd")
const BOARD := preload("res://scripts/level/range_scoreboard.gd")
const STREAK_WINDOW_S := 5.0
const TINT := Color(1.0, 0.75, 0.3)

## Outer size of the marked area.
@export var size_m := Vector2(150, 104):
	set(v): size_m = v; queue_rebuild()
## How much of each corner is cut off (the boundary is an octagon).
@export var corner_m := 22.0:
	set(v): corner_m = v; queue_rebuild()
## Where each drone holds station.
@export var drone_spots_m := PackedVector2Array([
	Vector2(-50, -24), Vector2(-20, -32), Vector2(14, -22), Vector2(46, -28),
	Vector2(-38, 14), Vector2(-6, 4), Vector2(24, 22), Vector2(52, 6)]):
	set(v): drone_spots_m = v; queue_rebuild()
## Centre of the scoreboard: in the clear strip below the drones, where you
## can read it from anywhere in the range.
@export var board_pos_m := Vector2(10, 41):
	set(v): board_pos_m = v; queue_rebuild()
@export var seed := 11:
	set(v): seed = v; queue_rebuild()

var hits := 0
var kills := 0
var streak := 0
var best_streak := 0

var drones: Array[TargetDrone] = []
var _board: RangeScoreboard
var _streak_left := 0.0


func _build() -> void:
	var F := Band.STRUCT_FX
	var hx := size_m.x * 0.5
	var hy := size_m.y * 0.5
	var c := minf(corner_m, minf(hx, hy) * 0.8)
	var corners := PackedVector2Array([
		m(-hx + c, -hy), m(hx - c, -hy), m(hx, -hy + c), m(hx, hy - c),
		m(hx - c, hy), m(-hx + c, hy), m(-hx, hy - c), m(-hx, -hy + c)])
	# Dashed holographic boundary.
	var dashes := PackedVector2Array()
	for i in corners.size():
		var a := corners[i]
		var b := corners[(i + 1) % corners.size()]
		var edge := a.distance_to(b)
		var d := (b - a) / edge
		var s := 2.0 * PX
		while s < edge - 2.0 * PX:
			dashes.append_array([a + d * s, a + d * minf(s + 5.0 * PX, edge - 2.0 * PX)])
			s += 8.0 * PX
	lines(F, dashes, Color(TINT, 0.3), 3.0)
	# A buoy on every corner: solid, shootable, and what the radar shows.
	for i in corners.size():
		var p := corners[i]
		hull(A.circle_poly(p, 1.5 * PX, 12), &"amber", [], {"bevel": 0.35})
		fill(Band.STRUCT_DETAIL, A.circle_poly(p, 0.8 * PX, 10), A.NAVY)
		beacon(p, A.AMBER, 110.0, fposmod(float(i) * 0.125, 1.0))
	# Each drone's patrol: a faint ring with a centre tick, so you can see
	# where one will come back.
	for i in drone_spots_m.size():
		var o := m(drone_spots_m[i].x, drone_spots_m[i].y)
		var sway := _sway(i)
		var ring := PackedVector2Array()
		for k in 33:
			var a := TAU * k / 32.0
			ring.append(o + Vector2(cos(a) * (sway.x + 3.5), sin(a) * (maxf(sway.y, 1.0) + 3.5)) * PX)
		polyline(F, ring, Color(0.5, 0.9, 1.0, 0.1), 1.5)
		lines(F, PackedVector2Array([o - m(1.2, 0), o + m(1.2, 0), o - m(0, 1.2), o + m(0, 1.2)]), Color(0.5, 0.9, 1.0, 0.22), 1.5)
	text(F, m(0, -hy + 5.5), "LIVE FIRE AREA", 44, Color(TINT, 0.22))
	text(F, m(-hx + 5.5, 0), "RANGE", 44, Color(TINT, 0.22), -PI * 0.5)
	text(F, m(hx - 5.5, 0), "RANGE", 44, Color(TINT, 0.22), PI * 0.5)


## Patrol half-extents (m) of drone `i`: varied, but the same every run.
func _sway(i: int) -> Vector2:
	return Vector2(lerpf(4.0, 9.0, A.hash01(i, seed)), lerpf(1.5, 5.0, A.hash01(i, seed + 3)))


func _after_build() -> void:
	drones.clear()
	if Engine.is_editor_hint():
		return
	set_physics_process(true)
	for i in drone_spots_m.size():
		var d: TargetDrone = DRONE.new()
		d.name = "Drone%d" % (i + 1)
		d.home = global_transform * m(drone_spots_m[i].x, drone_spots_m[i].y)
		d.sway_m = _sway(i)
		d.pattern = i % 3
		d.period_s = lerpf(7.0, 12.0, A.hash01(i, seed + 5))
		d.phase = A.hash01(i, seed + 9)
		d.shot.connect(_on_drone_shot)
		add_child(d)
		_generated.append(d)
		drones.append(d)
	_board = BOARD.new()
	_board.name = "Scoreboard"
	_board.position = m(board_pos_m.x, board_pos_m.y)
	_board.tint = TINT
	add_child(_board)
	_generated.append(_board)
	_board.set_score(hits, kills, streak, best_streak)


func _on_drone_shot(_drone: TargetDrone, destroyed: bool) -> void:
	hits += 1
	if destroyed:
		kills += 1
		streak += 1
		_streak_left = STREAK_WINDOW_S
		best_streak = maxi(best_streak, streak)
		var game := _game()
		if game and not drones.any(func(d: TargetDrone) -> bool: return d.alive):
			game.toast("RANGE CLEAR  ·  all targets down", 3.0)
	_board.set_score(hits, kills, streak, best_streak)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or _streak_left <= 0.0:
		return
	_streak_left -= delta
	if _streak_left <= 0.0:
		streak = 0
		if _board:
			_board.set_score(hits, kills, streak, best_streak)
