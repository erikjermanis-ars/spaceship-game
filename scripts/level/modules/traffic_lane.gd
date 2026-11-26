@tool
extends StationModule
## A closed traffic lane: spawns AI ships that fly it, lines it with nav buoys
## (small colliding markers, red to port / green to starboard of the travel
## direction, flashing in a chase pattern that shows the flow) and paints faint
## holographic chevrons. Buoys ping (positional) in sync with their flash.

enum Shape { CIRCLE, ELLIPSE, ROUNDED_RECT }

@export var shape := Shape.CIRCLE:
	set(v): shape = v; queue_rebuild()
## Circle: x = radius. Ellipse / rect: half extents (m).
@export var size_m := Vector2(320, 320):
	set(v): size_m = v; queue_rebuild()
@export var corner_m := 100.0:
	set(v): corner_m = v; queue_rebuild()
## Travel direction: clockwise on screen.
@export var clockwise := true:
	set(v): clockwise = v; queue_rebuild()
## Ships: "kind:speed_mps" entries, spaced evenly around the lane.
@export var ships: PackedStringArray = PackedStringArray(["shuttle:28"]):
	set(v): ships = v; queue_rebuild()
@export var buoy_spacing_m := 0.0:
	set(v): buoy_spacing_m = v; queue_rebuild()
@export var buoy_offset_m := 26.0:
	set(v): buoy_offset_m = v; queue_rebuild()
@export var chevrons := true:
	set(v): chevrons = v; queue_rebuild()
@export var seed := 0:
	set(v): seed = v; queue_rebuild()

const LIVERY_POOL := [Color("2A9D8F"), Color("E76F51"), Color("4EA8DE"), Color("1D3557"), Color("F4A261"), Color("6D597A")]
const NAMES := ["ORBITAL TRANSIT", "KESTREL STAR", "HALCYON LINE", "AURORA BULK", "VEGA HAULER", "TIDEWAY 9"]

var path := PackedVector2Array()     # local px, closed (last == first)
var cum := PackedFloat32Array()      # cumulative length
var total := 1.0
var _buoys: Array[Vector2] = []      # local px
var _buoy_phase: Array[float] = []
var _ping: AudioStreamPlayer2D
var _last_x := 0.0
var _flash_count := 0
var _level: Node


func _build() -> void:
	_make_path()
	# chevrons in the lane (additive, subtle)
	if chevrons:
		var step := 60.0 * PX
		var d := step * 0.5
		var pairs := PackedVector2Array()
		while d < total:
			var xf := _sample_local(d)
			var f := xf.x.normalized()
			var n := xf.y.normalized()
			var c := xf.origin
			pairs.append_array([c - f * 22 - n * 34, c + f * 12, c + f * 12, c - f * 22 + n * 34])
			d += step
		lines(Band.STRUCT_FX, pairs, Color(0.5, 0.9, 1.0, 0.16), 7.0)
	# buoys
	_buoys.clear()
	_buoy_phase.clear()
	if buoy_spacing_m > 0.0:
		var step := buoy_spacing_m * PX
		var d := 0.0
		var i := 0
		while d < total - step * 0.5:
			var xf := _sample_local(d)
			for s: float in [-1.0, 1.0]:
				var p: Vector2 = xf.origin + xf.y.normalized() * s * buoy_offset_m * PX
				hull(A.circle_poly(p, 1.5 * PX, 12), &"pearl", [], {"bevel": 0.35})
				fill(Band.STRUCT_DETAIL, A.circle_poly(p, 0.8 * PX, 10), A.NAVY)
				# port (left of travel) = red; travel dir is +X, left is -Y
				var col := A.NAV_RED if s < 0 else A.NAV_GREEN
				var ph := fposmod(-float(i) * 0.09, 1.0)
				beacon(p, col, 110.0, ph)
				if s > 0:
					_buoys.append(p)
					_buoy_phase.append(ph)
			d += step
			i += 1


func _after_build() -> void:
	var TrafficShip := preload("res://scripts/level/modules/traffic_ship.gd")
	var n := ships.size()
	for i in n:
		var spec := ships[i].split(":")
		var ship: StationModule = TrafficShip.new()
		ship.kind = spec[0]
		ship.speed_mps = float(spec[1]) if spec.size() > 1 else 25.0
		ship.seed = seed * 10 + i
		ship.livery = LIVERY_POOL[(seed + i) % LIVERY_POOL.size()]
		ship.ship_name = NAMES[(seed + i) % NAMES.size()]
		ship.name = "Traffic%d_%s" % [i, spec[0]]
		ship.lane = self
		ship.distance = total * float(i) / n
		add_child(ship)
		_generated.append(ship)
	if Engine.is_editor_hint() or _buoys.is_empty():
		return
	var p := "res://assets/audio/beacon_ping.wav"
	if ResourceLoader.exists(p) and LevelArt.audio_enabled():
		_ping = AudioStreamPlayer2D.new()
		_ping.stream = load(p)
		_ping.bus = &"SFX"
		_ping.max_distance = 1500.0
		_ping.attenuation = 2.2
		_ping.volume_db = -8.0
		add_child(_ping)
		_generated.append(_ping)
	_level = get_tree().get_first_node_in_group(&"meridian_level") if is_inside_tree() else null


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or _ping == null:
		return
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	if _level == null:
		_level = get_tree().get_first_node_in_group(&"meridian_level")
		if _level == null:
			return
	var c := to_local(cam.get_screen_center_position())
	var best := -1
	var best_d := INF
	for i in _buoys.size():
		var dd := _buoys[i].distance_squared_to(c)
		if dd < best_d:
			best_d = dd
			best = i
	if best < 0 or best_d > _ping.max_distance * _ping.max_distance:
		return
	var t: float = _level.beacon_time()
	var x := fposmod(t / 1.8 - _buoy_phase[best], 1.0)
	if x < _last_x:
		_flash_count += 1
		if _flash_count % 2 == 0:
			_ping.position = _buoys[best]
			_ping.pitch_scale = 1.0 + 0.04 * float(best % 3)
			_ping.play()
	_last_x = x


# ------------------------------------------------------------------ path

func _make_path() -> void:
	path.clear()
	var pts := PackedVector2Array()
	match shape:
		Shape.CIRCLE:
			pts = A.circle_poly(Vector2.ZERO, size_m.x * PX, 128)
		Shape.ELLIPSE:
			for i in 128:
				var a := TAU * i / 128.0
				pts.append(Vector2(cos(a) * size_m.x, sin(a) * size_m.y) * PX)
		Shape.ROUNDED_RECT:
			pts = A.rounded_rect(Rect2(-size_m * PX, size_m * 2.0 * PX), corner_m * PX, 12)
	if not clockwise:
		pts.reverse()
	pts.append(pts[0])
	path = pts
	cum.resize(path.size())
	cum[0] = 0.0
	for i in range(1, path.size()):
		cum[i] = cum[i - 1] + path[i].distance_to(path[i - 1])
	total = maxf(cum[cum.size() - 1], 1.0)


func _pos_at(d: float) -> Vector2:
	d = fposmod(d, total)
	var lo := 0
	var hi := cum.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if cum[mid] <= d:
			lo = mid
		else:
			hi = mid
	var seg := cum[hi] - cum[lo]
	var t := 0.0 if seg <= 0.0 else (d - cum[lo]) / seg
	return path[lo].lerp(path[hi], t)


## Local transform at distance d (px); heading looks a little ahead so it
## banks smoothly through the polyline corners.
func _sample_local(d: float) -> Transform2D:
	var p := _pos_at(d)
	var ahead := _pos_at(d + 120.0)
	var behind := _pos_at(d - 120.0)
	var dir := (ahead - behind)
	var ang := dir.angle() if dir.length_squared() > 0.01 else 0.0
	return Transform2D(ang, p)


func sample_transform(d: float) -> Transform2D:
	return global_transform * _sample_local(d)
