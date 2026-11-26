@tool
extends StationModule
## Meridian Yards, Drydock 2: an open gantry frame cradling a half-built
## explorer-class starship. The frame and the ship collide; two 34 m channels
## (narrowed by rib teeth) run lengthwise past the hull. Gantry cranes and
## catwalks are overhead. Local origin = dock centre, metres.

@export var half_size_m := Vector2(125, 60):
	set(v): half_size_m = v; queue_rebuild()
@export var beam_m := 8.0:
	set(v): beam_m = v; queue_rebuild()
@export var sparks := true

const WELD_POINTS := [Vector2(-38, -4), Vector2(-52, 9), Vector2(-28, 13.5)]


func _build() -> void:
	var hx := half_size_m.x
	var hy := half_size_m.y
	var b := beam_m
	# ---------------------------------------------------------------- floor
	deck(A.rect_m(-hx - 14, -hy - 12, hx + 14, hy + 12), 8.0, Color("19212D"), Color("1F2937"), Color("283447"), Color("4A5D75"))
	text(Band.DECK, m(0, 0), "DRYDOCK  2", 260, Color(0.8, 0.88, 1.0, 0.10))
	for s: float in [-1.0, 1.0]:
		for e: float in [-1.0, 1.0]:
			# chevrons on the deck leading into each channel
			for i in 3:
				var x := e * (hx + 6 - i * 4.5)
				var y := s * (hy - b - 17)
				var tip := m(x - e * 2.5, y)
				polyline(Band.DECK, PackedVector2Array([m(x, y - 6), tip, m(x, y + 6)]), Color(0.5, 0.9, 1.0, 0.35), 6.0)
	# ---------------------------------------------------------------- frame
	var frame: Array[PackedVector2Array] = [
		A.rect_m(-hx, -hy, hx, -hy + b),
		A.rect_m(-hx, hy - b, hx, hy),
		A.rect_m(-hx, -17, -hx + 10, 17),
		A.rect_m(hx - 10, -17, hx, 17),
	]
	var teeth_x := [-90.0, -45.0, 0.0, 45.0, 90.0]
	for tx in teeth_x:
		# Shallow (~23°) ramps, not square blocks: a ship hugging the wall is
		# deflected off the flank instead of stopped dead by a flat face.
		# The first vertex keeps the side's y sign (used by the filter below).
		frame.append(PackedVector2Array([m(tx - 16, -hy + b - 1), m(tx + 16, -hy + b - 1), m(tx + 2, -hy + b + 5), m(tx - 2, -hy + b + 5)]))
		frame.append(PackedVector2Array([m(tx - 16, hy - b + 1), m(tx + 16, hy - b + 1), m(tx + 2, hy - b - 5), m(tx - 2, hy - b - 5)]))
	var top := frame[0]
	var bot := frame[1]
	for i in range(4, frame.size()):
		if i % 2 == 0:
			top = union(top, frame[i])
		else:
			bot = union(bot, frame[i])
	hull(top, &"grey", [frame[0]] + frame.slice(4).filter(func(p): return p[0].y < 0), {"bevel": 0.7})
	hull(bot, &"grey", [frame[1]] + frame.slice(4).filter(func(p): return p[0].y > 0), {"bevel": 0.7})
	hull(frame[2], &"navy", [], {"bevel": 0.6})
	hull(frame[3], &"navy", [], {"bevel": 0.6})
	var D := Band.STRUCT_DETAIL
	# lattice pattern on the beams (reads as an open gantry)
	for s: float in [-1.0, 1.0]:
		var yc := s * (hy - b * 0.5)
		var pairs := PackedVector2Array()
		var x := -hx + 2.0
		var k := 0
		while x < hx - 6.0:
			var ya := yc - b * 0.32
			var yb := yc + b * 0.32
			if k % 2 == 0:
				pairs.append_array([m(x, ya), m(x + 6.0, yb)])
			else:
				pairs.append_array([m(x, yb), m(x + 6.0, ya)])
			x += 6.0
			k += 1
		lines(D, pairs, Color(0.42, 0.5, 0.6, 0.85), 2.5)
		line(D, m(-hx + 1, yc - b * 0.32), m(hx - 1, yc - b * 0.32), Color(0.42, 0.5, 0.6, 0.85), 2.0)
		line(D, m(-hx + 1, yc + b * 0.32), m(hx - 1, yc + b * 0.32), Color(0.42, 0.5, 0.6, 0.85), 2.0)
		# lamps along the inner edge, guiding the channels
		var xl := -hx + 8.0
		while xl < hx - 6.0:
			lamp(m(xl, s * (hy - b - 0.2)), A.CYAN, 28.0)
			xl += 12.0
		# frame corners
		beacon(m(-hx + 2, s * (hy - 2)), A.NAV_RED, 120.0, 0.0)
		beacon(m(hx - 2, s * (hy - 2)), A.NAV_GREEN, 120.0, 0.5)
	text(D, m(-50, -hy + b * 0.5), "MERIDIAN YARDS", 52, A.NAVY)
	text(D, m(50, hy - b * 0.5), "DRYDOCK 2  ·  HULL 117", 46, A.NAVY)
	for e: float in [-1.0, 1.0]:
		hazard(D, A.rect_m(e * (hx - 5) - 4, -15, e * (hx - 5) + 4, -11), 0.9)
		hazard(D, A.rect_m(e * (hx - 5) - 4, 11, e * (hx - 5) + 4, 15), 0.9)
		beacon(m(e * (hx - 5), 0), Color.WHITE, 140.0, 0.25, true)
	# ------------------------------------------------------------ the ship
	_paint_cruiser()
	# ------------------------------------------------------------ overhead
	for gx: float in [-62.0, 12.0, 68.0]:
		truss(m(gx, -hy - 6), m(gx, hy + 6), 7.0)
		var ty := 26.0 if gx < 0 else -20.0
		# crane trolley: grey block, amber hazard ends, hoist lamp
		overhead(A.rect_m(gx - 5.5, ty - 3.5, gx + 5.5, ty + 3.5), Color(0.78, 0.82, 0.88, 0.62), Color(1, 1, 1, 0.25))
		fill(Band.OVER, A.rect_m(gx - 5.5, ty - 3.5, gx - 3.5, ty + 3.5), Color(1.0, 0.69, 0.0, 0.8))
		fill(Band.OVER, A.rect_m(gx + 3.5, ty - 3.5, gx + 5.5, ty + 3.5), Color(1.0, 0.69, 0.0, 0.8))
		lamp(m(gx, ty), A.WARM, 70.0, 2)
	# catwalks from the beams to the hull
	for cx: float in [-20.0, 35.0]:
		overhead(A.rect_m(cx - 1.6, -hy + b, cx + 1.6, -13), Color(0.85, 0.9, 0.95, 0.5))
		overhead(A.rect_m(cx - 1.6, 13, cx + 1.6, hy - b), Color(0.85, 0.9, 0.95, 0.5))


func _paint_cruiser() -> void:
	var D := Band.STRUCT_DETAIL
	# Nacelles (starboard one unfinished), pylons, engineering hull, saucer.
	for s: float in [-1.0, 1.0]:
		var nac := A.capsule(m(-45, s * 13.8), 60.0 * PX, 7.0 * PX, 6)
		hull(A.rect_m(-52, s * 5, -36, s * 11), &"grey", [], {"bevel": 0.4})
		hull(nac, &"pearl", [], {"bevel": 0.5})
		fill(D, A.capsule(m(-45, s * 13.8), 52.0 * PX, 2.6 * PX, 6), Color(0.35, 0.75, 1.0, 0.85) if s < 0 else Color("1A2230"))
		if s < 0:
			glow(m(-45, s * 13.8), Color(0.3, 0.7, 1.0, 0.35), 260.0)
		else:
			_skeleton(A.capsule(m(-45, s * 13.8), 54.0 * PX, 5.2 * PX, 6), 3.0, false)
	var body := A.capsule(m(-25, 0), 92.0 * PX, 15.0 * PX, 8)
	hull(body, &"pearl", [], {"bevel": 0.8})
	var saucer := A.circle_poly(Vector2.ZERO, 1.0, 40)
	var xf := Transform2D(Vector2(40.0 * PX, 0), Vector2(0, 17.0 * PX), m(40, 0))
	saucer = xf * saucer
	hull(saucer, &"pearl", [], {"bevel": 1.0})
	# saucer detail
	var inner := Transform2D(Vector2(30.0 * PX, 0), Vector2(0, 12.0 * PX), m(42, 0)) * A.circle_poly(Vector2.ZERO, 1.0, 40)
	outline(D, inner, Color(0.55, 0.62, 0.7, 0.8), 1.6)
	fill(D, Transform2D(Vector2(36.0 * PX, 0), Vector2(0, 2.0 * PX), m(40, 0)) * A.circle_poly(Vector2.ZERO, 1.0, 30), A.NAVY)
	var bridge := A.circle_poly(m(52, 0), 5.0 * PX, 24)
	fill(D, bridge, Color("1F4B60"))
	fill(D, A.circle_poly(m(51.2, -1), 3.4 * PX, 20), Color("2C6A86"))
	outline(D, bridge, Color(0.9, 0.97, 1.0, 0.9), 2.5)
	var wpts := PackedVector2Array()
	for i in 41:
		var a := lerpf(-2.4, 2.4, i / 40.0)
		wpts.append(m(40, 0) + Vector2(cos(a) * 36.0, sin(a) * 14.6) * PX)
	windows(D, wpts, 1.2, 1.0, 9)
	text(D, m(28, -8.5), "PATHFINDER", 40, A.NAVY)
	text(D, m(28, 8.5), "MSV-117", 34, Color("4A5A70"))
	# Engineering hull: half plated -> exposed ribs + scaffolding.
	_skeleton(A.rect_m(-60, -6.2, -18, 6.2), 3.2, true)
	fill(D, A.rect_m(-14, -1.4, 18, 1.4), A.TEAL)
	# deflector glow at the saucer/hull neck
	glow(m(2, 0), Color(0.4, 0.8, 1.0, 0.5), 120.0)
	# warning lamps on the scaffolding
	for p: Vector2 in [Vector2(-60, -7), Vector2(-18, -7), Vector2(-60, 7), Vector2(-18, 7)]:
		beacon(m(p.x, p.y), A.AMBER, 80.0, A.hash01(int(p.x), 2))


## Exposed frame: dark interior, ribs, stringers, amber scaffolding outline.
func _skeleton(poly: PackedVector2Array, rib_m: float, scaffold: bool) -> void:
	var D := Band.STRUCT_DETAIL
	fill(D, poly, Color("161D28"))
	var bb := A.poly_bounds(poly)
	var pairs := PackedVector2Array()
	var x := bb.position.x + rib_m * PX * 0.5
	while x < bb.end.x:
		for seg in Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([Vector2(x, bb.position.y - 1), Vector2(x, bb.end.y + 1)]), poly):
			pairs.append_array([seg[0], seg[seg.size() - 1]])
		x += rib_m * PX
	lines(D, pairs, Color("9AA6B4"), 3.0)
	for t: float in [0.3, 0.7]:
		var y := lerpf(bb.position.y, bb.end.y, t)
		line(D, Vector2(bb.position.x + 6, y), Vector2(bb.end.x - 6, y), Color("6D7A8A"), 2.0)
	# a few finished plates
	var plates := int(bb.size.x / (rib_m * PX))
	for i in plates:
		if A.hash01(i, int(bb.position.x)) < 0.35:
			var px0 := bb.position.x + i * rib_m * PX + 3
			var r := Rect2(Vector2(px0, bb.position.y + 4), Vector2(rib_m * PX - 6, bb.size.y - 8))
			for piece in Geometry2D.intersect_polygons(A.rect_poly(r), poly):
				fill(D, piece, Color("C9D2DC"))
	if scaffold:
		outline(D, Geometry2D.offset_polygon(poly, 6.0)[0], Color(1.0, 0.72, 0.1, 0.9), 2.5)


func _after_build() -> void:
	if not sparks or Engine.is_editor_hint():
		return
	for wp in WELD_POINTS:
		var p := CPUParticles2D.new()
		p.position = m(wp.x, wp.y)
		p.z_as_relative = false
		p.z_index = G.Z_FX
		p.amount = 18
		p.lifetime = 0.45
		p.explosiveness = 0.2
		p.randomness = 0.6
		p.direction = Vector2(0, -1)
		p.spread = 180.0
		p.gravity = Vector2(0, 0)
		p.initial_velocity_min = 30.0
		p.initial_velocity_max = 160.0
		p.damping_min = 80.0
		p.damping_max = 160.0
		p.scale_amount_min = 1.5
		p.scale_amount_max = 3.5
		var g := Gradient.new()
		g.colors = PackedColorArray([Color(1, 1, 0.85, 1), Color(1, 0.6, 0.15, 0.9), Color(1, 0.3, 0.05, 0)])
		g.offsets = PackedFloat32Array([0, 0.4, 1])
		p.color_ramp = g
		p.material = A.add_material()
		add_child(p)
		_generated.append(p)
		# steady welding glow
		var gl := Sprite2D.new()
		gl.texture = A.glow_texture()
		gl.position = p.position
		gl.scale = Vector2(1.2, 1.2)
		gl.modulate = Color(1.0, 0.75, 0.4, 0.6)
		gl.material = A.add_material()
		gl.z_as_relative = false
		gl.z_index = G.Z_FX
		add_child(gl)
		_generated.append(gl)
