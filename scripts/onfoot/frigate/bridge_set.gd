@tool
class_name BridgeSet
extends Node2D
## The KESTREL's bridge furniture, drawn in code (bridge-local metres, the
## node sits at the room's centre, forward = -Y):
##   * the main viewscreen along the forward bulkhead, and in front of it a
##     floor-projected TACTICAL HOLOGRAM (top-down, so it reads from above):
##     the ship's own outline, range rings, the berth pylons when docked,
##     drifting contacts and scan sweeps;
##   * helm and ops stations forward, a raised command ring with the
##     captain's chair (a separate CaptainChair node) and two flanking seats,
##     a split tactical rail behind, and wall stations port and starboard.
## Static art is drawn once; screens and the hologram are unshaded and
## refresh at ~15 Hz. Consoles collide with the walker.

const PX := 10.0
## [centre (m), size (m), facing angle]: forward stations, tactical rail,
## wall stations. Facing = the side the operator sits on.
const CONSOLES := [
	[Vector2(-2.5, -2.7), Vector2(2.4, 0.7), 0.0], [Vector2(2.5, -2.7), Vector2(2.4, 0.7), 0.0],
	[Vector2(-2.3, 4.3), Vector2(2.6, 0.6), 0.0], [Vector2(2.3, 4.3), Vector2(2.6, 0.6), 0.0],
	[Vector2(-8.5, -3.0), Vector2(0.7, 2.6), 0.0], [Vector2(-8.5, 1.0), Vector2(0.7, 2.6), 0.0],
	[Vector2(8.5, -3.0), Vector2(0.7, 2.6), 0.0], [Vector2(8.5, 1.0), Vector2(0.7, 2.6), 0.0],
]
const SEATS := [Vector2(-2.5, -1.9), Vector2(2.5, -1.9), Vector2(-1.7, 1.9), Vector2(1.7, 1.9),
	Vector2(-7.6, -3.0), Vector2(7.6, -3.0)]

var _screens: Node2D
var _light: PointLight2D
var _t := 0.0
var _docked := false
var _berth := ""
var _alert := false


func _ready() -> void:
	z_as_relative = false
	z_index = 1
	if Engine.is_editor_hint():
		return
	var body := StaticBody2D.new()
	body.collision_layer = Game.LAYER_WALK
	for c in CONSOLES:
		var cs := CollisionShape2D.new()
		var rs := RectangleShape2D.new()
		rs.size = (c[1] as Vector2) * PX - Vector2(0.4, 0.4)
		cs.shape = rs
		cs.position = (c[0] as Vector2) * PX
		body.add_child(cs)
	# command ring railing: short segments either side of the steps
	for a in range(200, 341, 20):
		if a > 250 and a < 290:
			continue
		var cs := CollisionShape2D.new()
		var ss := SegmentShape2D.new()
		ss.a = Vector2.from_angle(deg_to_rad(a)) * 3.2 * PX + Vector2(0, 1.0) * PX
		ss.b = Vector2.from_angle(deg_to_rad(a + 20)) * 3.2 * PX + Vector2(0, 1.0) * PX
		cs.shape = ss
		body.add_child(cs)
	add_child(body)
	_screens = Node2D.new()
	_screens.material = OnFootArt.unshaded()
	_screens.draw.connect(_draw_screens)
	add_child(_screens)
	_light = PointLight2D.new()
	_light.texture = OnFootArt.radial_texture()
	_light.texture_scale = 9.0 * PX * 2.0 / 128.0
	_light.position = Vector2(0, -4.8) * PX
	_light.color = Color(0.45, 0.8, 1.0)
	_light.energy = 0.55
	add_child(_light)
	var f := FrigateShip.aboard
	_berth = f.berth_name() if f else ""
	_docked = f != null and bool(f.call(&"gangway_ready"))
	_alert = f != null and bool(f.get(&"red_alert"))


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _screens == null:
		return
	var before := int(_t * 15.0)
	_t += delta
	if int(_t * 15.0) != before:
		_screens.queue_redraw()
	_light.energy = 0.5 + 0.06 * sin(_t * 2.3)
	_light.color = Color(1.0, 0.35, 0.3) if _alert and fmod(_t, 1.2) < 0.7 else Color(0.45, 0.8, 1.0)


func _draw() -> void:
	var pen := OnFootPainter.new(self)
	# command ring on the floor (raised: lighter disc, rim, step gap)
	var cr := Vector2(0, 1.0) * PX
	pen.circle(cr, 3.4 * PX, Color(0.2, 0.26, 0.36, 0.55))
	pen.circle(cr, 3.1 * PX, Color(0.27, 0.33, 0.44, 0.7))
	pen.arc(cr, 3.25 * PX, deg_to_rad(200), deg_to_rad(250), Color("C9D2DC"), 0.35, 16)
	pen.arc(cr, 3.25 * PX, deg_to_rad(290), deg_to_rad(340), Color("C9D2DC"), 0.35, 16)
	pen.arc(cr, 3.0 * PX, 0.0, TAU, Color(0.5, 0.9, 1.0, 0.35), 0.15, 64)
	# floor light strips toward the screen
	for s: float in [-1.0, 1.0]:
		pen.line(Vector2(4.2 * s, -6.0) * PX, Vector2(4.2 * s, 4.8) * PX, Color(0.5, 0.9, 1.0, 0.18), 0.25)
	# consoles: body, angled top, screen bezel
	for c in CONSOLES:
		var ctr: Vector2 = (c[0] as Vector2) * PX
		var sz: Vector2 = (c[1] as Vector2) * PX
		var r := Rect2(ctr - sz * 0.5, sz)
		pen.set_transform(OnFootArt.SHADOW_OFFSET)
		pen.rrect(r, 1.0, Color(0, 0.01, 0.03, 0.25))
		pen.set_transform()
		pen.rrect(r, 1.0, Color("C9D2DC"), OnFootArt.INK, 0.15)
		pen.rrect(r.grow(-0.8), 0.6, Color("1B2533"))
	# seats
	for p: Vector2 in SEATS:
		var c2 := p * PX
		pen.circle(c2, 0.42 * PX, Color("2B3440"), OnFootArt.INK, 0.12)
		pen.rrect(Rect2(c2 - Vector2(3.2, 3.0), Vector2(6.4, 6.0)), 1.5, Color("24406A"))
	# viewscreen frame on the forward bulkhead
	pen.rect(Rect2(Vector2(-7.0, -6.45) * PX, Vector2(14.0, 0.45) * PX), Color("2B3440"), OnFootArt.INK, 0.15)
	pen.flush()


## Screens, the viewscreen glow and the tactical hologram (unshaded).
func _draw_screens() -> void:
	var pen := OnFootPainter.new(_screens)
	var cyan := Color(0.5, 0.9, 1.0)
	var tint := Color(1.0, 0.35, 0.3) if _alert else cyan
	# viewscreen: a bright strip with a slow shimmer
	var vs := Rect2(Vector2(-6.8, -6.38) * PX, Vector2(13.6, 0.3) * PX)
	pen.rect_flat(vs, Color(tint, 0.65 + 0.1 * sin(_t * 1.3)))
	pen.rect_flat(Rect2(vs.position + Vector2(0, 0.8), Vector2(vs.size.x, 0.6)), Color(1, 1, 1, 0.5))
	# console screens: little bar graphs and readouts that tick over
	for i in CONSOLES.size():
		var c: Array = CONSOLES[i]
		var ctr: Vector2 = (c[0] as Vector2) * PX
		var sz: Vector2 = (c[1] as Vector2) * PX - Vector2(2.2, 2.2)
		var horiz := sz.x > sz.y
		var n := 6
		for k in n:
			var v := LevelArt.hash01(int(_t * 4.0) + k * 13 + i * 31, i + 3)
			var col := cyan if k % 3 else OnFootArt.AMBER
			if horiz:
				var x := ctr.x - sz.x * 0.5 + (k + 0.5) * sz.x / n
				pen.rect_flat(Rect2(Vector2(x - 1.0, ctr.y + sz.y * 0.5 - sz.y * v), Vector2(2.0, sz.y * v)), Color(col, 0.75))
			else:
				var y := ctr.y - sz.y * 0.5 + (k + 0.5) * sz.y / n
				pen.rect_flat(Rect2(Vector2(ctr.x - sz.x * 0.5, y - 1.0), Vector2(sz.x * v, 2.0)), Color(col, 0.75))
	# tactical hologram projected on the floor in front of the helm
	var hc := Vector2(0, -4.75) * PX
	var hr := Rect2(hc - Vector2(4.4, 1.15) * PX, Vector2(8.8, 2.3) * PX)
	pen.rect_flat(hr, Color(tint, 0.07))
	pen.polyline(OnFootArt.rect_poly(hr), Color(tint, 0.5), 0.15, true)
	for k in 3:
		pen.ring(hc, (0.5 + 0.35 * k) * PX, Color(tint, 0.18), 0.1, 40)
	# sweep
	var sw := _t * 1.4
	pen.line(hc, hc + Vector2.from_angle(sw) * 1.6 * PX, Color(tint, 0.45), 0.12)
	# own ship: the hull parts, scaled down, bow up
	var k_s := 0.009
	for outline in FrigateShape.outlines():
		var poly := PackedVector2Array()
		for v in outline:
			poly.append(hc + Vector2(v.y, -v.x) * k_s)
		poly.append(poly[0])
		pen.polyline(poly, Color(tint, 0.85), 0.1)
	if _docked:
		for h: Vector2 in [FrigateShape.CLAMP_FWD, FrigateShape.CLAMP_AFT]:
			var p0 := hc + Vector2(h.y + 2.0, -h.x) * PX * k_s
			pen.line(p0, p0 + Vector2(40.0, 0) * PX * k_s, Color(OnFootArt.NAV_GREEN, 0.8), 0.15)
		pen.text(hc + Vector2(2.6, -0.8) * PX, "BERTH %s · CLAMPED" % _berth, 1.5, Color(OnFootArt.NAV_GREEN, 0.9))
	else:
		pen.text(hc + Vector2(2.6, -0.8) * PX, "ALL STOP", 1.5, Color(tint, 0.9))
	# drifting contacts
	for i in 5:
		var a := LevelArt.hash01(i, 11) * TAU + _t * 0.05 * (1.0 + i * 0.3)
		var rr := (0.6 + LevelArt.hash01(i, 12) * 0.5) * PX
		var p := hc + Vector2(cos(a) * rr * 3.4, sin(a) * rr * 0.9)
		if hr.has_point(p):
			pen.circle(p, 0.12 * PX, Color(OnFootArt.AMBER, 0.8))
	if _alert:
		pen.text(hc + Vector2(-2.6, -0.8) * PX, "RED ALERT", 1.6, Color(1.0, 0.3, 0.3, 0.6 + 0.4 * sin(_t * 6.0)))
	pen.flush()
