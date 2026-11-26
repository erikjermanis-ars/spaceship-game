@tool
extends StationModule
## Overhead maglev transit tube linking two districts, with pylons and pods
## shuttling back and forth. Purely visual (overhead band, non-colliding):
## it ties the station together and keeps things moving above the player.
## `points_m` are LOCAL metres (module usually sits at the origin).

@export var points_m: PackedVector2Array = PackedVector2Array([Vector2(0, 0), Vector2(100, 0)]):
	set(v): points_m = v; queue_rebuild()
@export var width_m := 5.0:
	set(v): width_m = v; queue_rebuild()
@export var pods := 2
@export var pod_speed_mps := 55.0

var _pts := PackedVector2Array()
var _cum := PackedFloat32Array()
var _len := 1.0
var _pod_layer: Node2D
var _t := 0.0


func _build() -> void:
	_pts = PackedVector2Array()
	for p in points_m:
		_pts.append(p * PX)
	_cum = PackedFloat32Array([0.0])
	for i in range(1, _pts.size()):
		_cum.append(_cum[i - 1] + _pts[i].distance_to(_pts[i - 1]))
	_len = maxf(_cum[_cum.size() - 1], 1.0)
	var w := width_m * PX
	# shadow, translucent tube, rails, glazing glints
	for i in _pts.size() - 1:
		var a := _pts[i]
		var b := _pts[i + 1]
		var box := A.obox((a + b) * 0.5, b - a, a.distance_to(b) + w * 0.5, w)
		fill(Band.OVER_SHADOW, box, A.OVER_SHADOW)
		fill(Band.OVER, box, Color(0.82, 0.88, 0.95, 0.30))
	strip(Band.OVER, _pts, w * 0.36, Color(0.95, 0.97, 1.0, 0.18))
	var off := w * 0.5
	var l1 := PackedVector2Array()
	var l2 := PackedVector2Array()
	for i in _pts.size():
		var d := (_pts[mini(i + 1, _pts.size() - 1)] - _pts[maxi(i - 1, 0)]).normalized()
		var n := d.orthogonal()
		l1.append(_pts[i] + n * off)
		l2.append(_pts[i] - n * off)
	polyline(Band.OVER, l1, Color(0.95, 0.98, 1.0, 0.75), 2.5)
	polyline(Band.OVER, l2, Color(0.6, 0.7, 0.82, 0.75), 2.5)
	# pylon collars every ~70 m with a cyan light
	var d0 := 35.0 * PX
	while d0 < _len:
		var p := _along(_pts, _cum, d0)
		var q := _along(_pts, _cum, minf(d0 + 10.0, _len))
		var dir := (q - p).normalized()
		fill(Band.OVER, A.obox(p, dir, 2.2 * PX, w * 1.5), Color(0.9, 0.93, 0.97, 0.8))
		lamp(p, A.CYAN, 36.0, 2)
		d0 += 70.0 * PX
	# station caps at both ends
	for e in [_pts[0], _pts[_pts.size() - 1]]:
		fill(Band.OVER, A.circle_poly(e, w * 0.9, 16), Color(0.92, 0.95, 1.0, 0.8))
		lamp(e, A.WARM, 70.0, 2)


func _after_build() -> void:
	_pod_layer = Node2D.new()
	_pod_layer.name = "Pods"
	_pod_layer.z_as_relative = false
	_pod_layer.z_index = G.Z_OVERHEAD + 1
	_pod_layer.draw.connect(_draw_pods)
	add_child(_pod_layer)
	_generated.append(_pod_layer)
	if not Engine.is_editor_hint():
		# pods ride the overhead tube, so they use the overhead depth scale
		A.depth_layers.append([_pod_layer, A.OVER_SCALE, Vector2.ZERO])
		_band_nodes.append(_pod_layer)


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _pod_layer == null:
		return
	_t += delta
	_pod_layer.queue_redraw()


func _pod_pos(i: int) -> Array:
	# ping-pong with dwell at the stations, eased
	var travel := _len / (pod_speed_mps * PX)
	var cycle := travel * 2.0 + 6.0
	var t := fposmod(_t + cycle * float(i) / maxf(pods, 1), cycle)
	var s := 0.0
	if t < 3.0:
		s = 0.0
	elif t < 3.0 + travel:
		s = smoothstep(0.0, 1.0, (t - 3.0) / travel)
	elif t < 6.0 + travel:
		s = 1.0
	else:
		s = 1.0 - smoothstep(0.0, 1.0, (t - 6.0 - travel) / travel)
	var d := s * _len
	var p := _along(_pts, _cum, d)
	var q := _along(_pts, _cum, clampf(d + 20.0, 0.0, _len))
	var r := _along(_pts, _cum, clampf(d - 20.0, 0.0, _len))
	return [p, (q - r).angle()]


func _draw_pods() -> void:
	var w := width_m * PX
	for i in pods:
		var pr := _pod_pos(i)
		var p: Vector2 = pr[0]
		_pod_layer.draw_set_transform(p, pr[1], Vector2.ONE)
		var r := Rect2(Vector2(-90, -w * 0.32), Vector2(180, w * 0.64))
		_pod_layer.draw_rect(r, Color(0.96, 0.97, 1.0, 0.95))
		_pod_layer.draw_rect(Rect2(Vector2(-80, -w * 0.12), Vector2(160, w * 0.24)), Color(1.0, 0.86, 0.55, 0.95))
		_pod_layer.draw_rect(r, Color(0.2, 0.3, 0.45, 0.9), false, 2.0, true)
		_pod_layer.draw_rect(Rect2(Vector2(84, -6), Vector2(8, 12)), Color(0.5, 0.95, 1.0, 1.0))
	_pod_layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
