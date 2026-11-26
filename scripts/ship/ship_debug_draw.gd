extends Node2D
## Physics debug overlay (F3 / Game.debug_draw). Shows how the flight model and
## collisions actually work: collision polygon, centre of mass, the bow thrust
## point with live force vectors at their real application points, velocity
## split into forward/slip components, angular velocity arc and recent contact
## points with their normals and closing speeds.
##
## Draws in GLOBAL coordinates (top_level) so the text stays upright.

const FORCE_SCALE := 0.012        # px per newton (5000 N -> 60 px)
const VEL_TIME := 0.5             # velocity arrow = where we'll be in 0.5 s
const C_POLY := Color(1.0, 0.85, 0.2, 0.9)
const C_MAIN := Color(0.3, 0.8, 1.0)
const C_SIDE := Color(1.0, 0.35, 0.8)
const C_STRAFE := Color(0.7, 0.5, 1.0)
const C_VEL := Color(0.4, 1.0, 0.5)
const C_SLIP := Color(1.0, 0.6, 0.2)
const C_OMEGA := Color(1.0, 1.0, 1.0, 0.8)
const C_CONTACT := Color(1.0, 0.3, 0.25)

var ship: PlayerShip
var _font: Font
var _polys: Array[PackedVector2Array] = []


func _ready() -> void:
	ship = get_parent() as PlayerShip
	top_level = true
	z_as_relative = false
	z_index = Game.Z_OVERHEAD_FX + 5
	_font = ThemeDB.fallback_font
	var cp := ship.get_node_or_null(^"CollisionPolygon2D") as CollisionPolygon2D if ship else null
	if cp:
		var pts := cp.polygon
		pts.append(pts[0])
		_polys.append(pts)
	visible = Game.debug_draw
	Game.debug_draw_changed.connect(func(on: bool) -> void:
		visible = on
		queue_redraw())


func _process(_delta: float) -> void:
	if visible and ship:
		global_transform = Transform2D.IDENTITY
		queue_redraw()


func _zoom() -> float:
	var cam := get_viewport().get_camera_2d()
	return cam.zoom.x if cam else 1.0


func _arrow(from: Vector2, vec: Vector2, color: Color, width: float) -> void:
	if vec.length() < 0.5:
		return
	var to := from + vec
	draw_line(from, to, color, width, true)
	var head := minf(vec.length() * 0.35, 10.0 * width / 2.0)
	var d := vec.normalized()
	draw_colored_polygon(PackedVector2Array([to + d * head * 0.4, to - d * head + d.orthogonal() * head * 0.5,
		to - d * head - d.orthogonal() * head * 0.5]), color)


## Text stays upright on screen even in the rotate-with-ship camera mode.
func _text(pos: Vector2, s: String, color: Color, size_px: float) -> void:
	var cam := get_viewport().get_camera_2d()
	draw_set_transform(pos, cam.global_rotation if cam else 0.0)
	draw_string_outline(_font, Vector2.ZERO, s, HORIZONTAL_ALIGNMENT_LEFT, -1, int(size_px), maxi(2, int(size_px / 5.0)), Color(0, 0, 0, 0.85))
	draw_string(_font, Vector2.ZERO, s, HORIZONTAL_ALIGNMENT_LEFT, -1, int(size_px), color)
	draw_set_transform(Vector2.ZERO)


func _draw() -> void:
	if ship == null or not ship.alive:
		return
	var z := maxf(_zoom(), 0.05)
	var lw := 1.6 / z            # constant on-screen line width
	var fs := 19.0 / z           # constant on-screen font size
	var gt := ship.global_transform
	var com := gt.origin
	# Collision polygon.
	for p in _polys:
		var g := PackedVector2Array()
		g.resize(p.size())
		for i in p.size():
			g[i] = gt * p[i]
		draw_polyline(g, C_POLY, lw, true)
	# Centre of mass (classic quartered disc).
	var r := 5.0 / z + 3.0
	draw_circle(com, r, Color.WHITE)
	draw_arc(com, r, 0, TAU, 24, Color.BLACK, lw * 0.7, true)
	draw_colored_polygon(PackedVector2Array([com, com + gt.x.normalized() * r, com + gt.y.normalized() * r]), Color.BLACK)
	draw_colored_polygon(PackedVector2Array([com, com - gt.x.normalized() * r, com - gt.y.normalized() * r]), Color.BLACK)
	# Barbell spine: head (thrust point) and payload.
	var bow := gt * ship.thrust_point_local()
	var payload := gt * Vector2(-2.0 * Game.PX_PER_M, 0)
	draw_line(payload, bow, Color(1, 1, 1, 0.35), lw, true)
	draw_circle(bow, 3.0 / z + 2.0, C_SIDE)
	draw_arc(payload, 9.0, 0, TAU, 20, Color(1, 1, 1, 0.5), lw, true)
	# Forces at their real application points.
	_arrow(bow, ship.dbg_main_force * FORCE_SCALE, C_MAIN, lw * 1.6)
	_arrow(bow, ship.dbg_side_force * FORCE_SCALE, C_SIDE, lw * 1.6)
	_arrow(com, ship.dbg_strafe_force * FORCE_SCALE, C_STRAFE, lw * 1.6)
	# Velocity and its decomposition (forward vs slip).
	var v := ship.linear_velocity
	_arrow(com, v * VEL_TIME, C_VEL, lw * 1.4)
	var fwd := gt.x.normalized()
	var right := gt.y.normalized()
	var slip := right * v.dot(right)
	if slip.length() > 3.0:
		_arrow(com + fwd * v.dot(fwd) * VEL_TIME, slip * VEL_TIME, C_SLIP, lw)
	# Angular velocity arc (sweep = rotation over the next 0.5 s).
	var w := ship.angular_velocity
	if absf(w) > 0.02:
		var ar := 70.0
		var a0 := gt.get_rotation()
		var a1 := a0 + clampf(w * VEL_TIME, -PI * 1.5, PI * 1.5)
		draw_arc(com, ar, minf(a0, a1), maxf(a0, a1), 32, C_OMEGA, lw, true)
		var tip := com + Vector2.from_angle(a1) * ar
		var tangent := Vector2.from_angle(a1).orthogonal() * signf(w)
		_arrow(tip - tangent * 8.0, tangent * 8.0, C_OMEGA, lw)
	# Contacts.
	for c in ship.recent_contacts:
		var age := clampf((ship._sim_time - float(c.time)) / 2.5, 0.0, 1.0)
		var col := Color(C_CONTACT, 1.0 - age)
		var p: Vector2 = c.pos
		var n: Vector2 = c.normal
		draw_circle(p, 4.0 / z + 1.5, col)
		_arrow(p, n * 40.0, col, lw * 1.3)
		_text(p + n * 46.0 + Vector2(4, 0), "%.1f m/s" % float(c.speed), col, fs)
	# Readout.
	var speed := v.length() / Game.PX_PER_M
	var slip_mps := v.dot(right) / Game.PX_PER_M
	var info := "v %.1f m/s   slip %+.1f m/s   ω %+.2f rad/s   thr %+.2f  turn %+.2f%s%s" % [
		speed, slip_mps, w, ship.throttle_input, ship.turn_input,
		"  BOOST" if ship.boosting else "", "  ASSIST" if ship.flight_assist else ""]
	_text(com + Vector2(-80.0, 110.0) / z, info, Color(0.9, 0.95, 1.0), fs)
