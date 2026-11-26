class_name DistantStation
extends Node2D
## A far-off orbital structure for scale: dark silhouette, thin sun-side rim
## light, tiny warm windows, and blinking navigation lights. Geometry is drawn
## once (cached by the CanvasItem); only the small additive light layer is
## redrawn each frame, and rotating parts just rotate their node.

enum Kind { WHEEL, SHIPYARD, CYLINDER, RELAY, DEPOT }

var kind: Kind = Kind.WHEEL
var size := 200.0                 ## characteristic radius / half-length in layer units
var spin_speed := 0.0             ## rad/s for the rotating body (wheels)
var sun_dir := Vector2(0.8, -0.6) ## towards the sun in layer space (for rim light)

var _body: Node2D        # rotating geometry
var _overlay: Node2D     # non-rotating shading (rim light / shadow)
var _lights: Node2D      # additive, redrawn each frame
var _time := 0.0
## {pos: Vector2, color: Color, size: float, period: float, phase: float,
##  decay: float, on_body: bool, base: float}
var _light_defs: Array[Dictionary] = []
var _sparks_rng := RandomNumberGenerator.new()


func setup(p_kind: Kind, p_size: float, p_rotation: float, p_sun_dir: Vector2, p_spin := 0.0) -> void:
	kind = p_kind
	size = p_size
	rotation = p_rotation
	sun_dir = p_sun_dir.rotated(-p_rotation).normalized()  # into local space
	spin_speed = p_spin
	_sparks_rng.seed = hash(name) + int(p_size)

	_body = Node2D.new()
	_body.name = "Body"
	_body.draw.connect(_draw_body)
	add_child(_body)
	_overlay = Node2D.new()
	_overlay.name = "Shading"
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	_lights = Node2D.new()
	_lights.name = "Lights"
	_lights.material = EnvArt.additive_material()
	_lights.draw.connect(_draw_lights)
	add_child(_lights)
	_define_lights()


func _process(delta: float) -> void:
	_time += delta
	if spin_speed != 0.0:
		_body.rotation = fposmod(_body.rotation + spin_speed * delta, TAU)
	# Skip the per-frame redraw entirely while the station is far off screen.
	if _is_near_view():
		_lights.queue_redraw()


func _is_near_view() -> bool:
	var vr := get_viewport_rect().grow(size * 2.0 * absf(get_global_transform().get_scale().x) + 200.0)
	return vr.has_point(get_global_transform() * Vector2.ZERO)


# ------------------------------------------------------------- shading ----
func _rim_alpha(normal: Vector2) -> float:
	return clampf(normal.dot(sun_dir) * 1.2, 0.0, 1.0)


func _draw_lit_polygon(ci: CanvasItem, pts: PackedVector2Array, fill: Color, rim_w := 1.6) -> void:
	ci.draw_colored_polygon(pts, fill)
	# Per-edge rim light on the edges whose outward normal faces the sun.
	# Shoelace sign gives the winding, so outward normals work either way.
	var n := pts.size()
	var area := 0.0
	for i in n:
		var p0 := pts[i]
		var p1 := pts[(i + 1) % n]
		area += p0.x * p1.y - p1.x * p0.y
	var flip := -1.0 if area < 0.0 else 1.0
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		var e := b - a
		if e.length_squared() < 0.01:
			continue
		var nrm := Vector2(e.y, -e.x).normalized() * flip
		var k := _rim_alpha(nrm)
		if k > 0.02:
			ci.draw_line(a, b, Color(EnvArt.RIM_LIGHT, 0.85 * k), rim_w, true)
		else:
			ci.draw_line(a, b, Color(0.02, 0.03, 0.05, 0.6), 1.0, true)


static func _rect_pts(c: Vector2, half: Vector2) -> PackedVector2Array:
	return PackedVector2Array([
		c + Vector2(-half.x, -half.y), c + Vector2(half.x, -half.y),
		c + Vector2(half.x, half.y), c + Vector2(-half.x, half.y)])


# ---------------------------------------------------------------- body ----
func _draw_body() -> void:
	match kind:
		Kind.WHEEL: _draw_wheel()
		Kind.SHIPYARD: _draw_shipyard()
		Kind.CYLINDER: _draw_cylinder()
		Kind.RELAY: _draw_relay()
		Kind.DEPOT: _draw_depot()


func _draw_overlay() -> void:
	if kind == Kind.WHEEL:
		# Rotation-independent lighting: a lit arc on the sun side of the rim
		# and a soft shadow on the far side give the torus volume.
		var ang := sun_dir.angle()
		_overlay.draw_arc(Vector2.ZERO, size + 13.0, ang - 1.1, ang + 1.1, 48, Color(EnvArt.RIM_LIGHT, 0.75), 2.0, true)
		_overlay.draw_arc(Vector2.ZERO, size + 12.0, ang - 0.5, ang + 0.5, 24, Color(0.9, 0.94, 1.0, 0.5), 1.2, true)
		_overlay.draw_arc(Vector2.ZERO, size, ang + PI - 1.3, ang + PI + 1.3, 48, Color(0.0, 0.0, 0.02, 0.45), 26.0, true)
		_overlay.draw_arc(Vector2.ZERO, size * 0.2 + 4.0, ang - 1.0, ang + 1.0, 24, Color(EnvArt.RIM_LIGHT, 0.7), 1.6, true)


func _draw_wheel() -> void:
	var b := _body
	var r := size
	# Spokes (behind the rim), with a thin spine line.
	for i in 6:
		var a := TAU * float(i) / 6.0
		var d := Vector2.from_angle(a)
		b.draw_line(d * r * 0.2, d * (r - 12.0), EnvArt.HULL_MID, 7.0, true)
		b.draw_line(d * r * 0.2, d * (r - 12.0), EnvArt.HULL_PANEL, 1.2, true)
	# Rim torus.
	b.draw_arc(Vector2.ZERO, r, 0.0, TAU, 128, EnvArt.HULL_DARK, 26.0, true)
	b.draw_arc(Vector2.ZERO, r + 12.5, 0.0, TAU, 128, Color(0.03, 0.04, 0.07), 1.2, true)
	b.draw_arc(Vector2.ZERO, r - 12.5, 0.0, TAU, 128, EnvArt.HULL_PANEL, 1.0, true)
	# Window bands: segmented warm strips (habitat decks).
	var segs := 36
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := a0 + TAU / float(segs) * 0.72
		var on := (i * 7) % 5 != 0
		b.draw_arc(Vector2.ZERO, r + 4.0, a0, a1, 6, Color(EnvArt.WINDOW_WARM, 0.5 if on else 0.12), 1.6, true)
		b.draw_arc(Vector2.ZERO, r - 4.0, a0 + 0.03, a1 - 0.02, 6, Color(EnvArt.WINDOW_WARM, 0.32 if (i % 3) else 0.08), 1.3, true)
	# Radiators/docking modules every 60 degrees.
	for i in 6:
		var a := TAU * (float(i) + 0.5) / 6.0
		var d := Vector2.from_angle(a)
		var t := Vector2(-d.y, d.x)
		var c := d * (r + 16.0)
		var pts := PackedVector2Array([c - t * 9.0 - d * 4.0, c + t * 9.0 - d * 4.0, c + t * 6.0 + d * 8.0, c - t * 6.0 + d * 8.0])
		b.draw_colored_polygon(pts, EnvArt.HULL_MID)
	# Hub.
	b.draw_circle(Vector2.ZERO, r * 0.2, EnvArt.HULL_MID)
	b.draw_arc(Vector2.ZERO, r * 0.2, 0.0, TAU, 48, EnvArt.HULL_PANEL, 1.5, true)
	b.draw_circle(Vector2.ZERO, r * 0.09, EnvArt.HULL_DARK)
	b.draw_arc(Vector2.ZERO, r * 0.12, 0.0, TAU, 32, Color(EnvArt.TECH_CYAN, 0.35), 1.2, true)


func _draw_shipyard() -> void:
	var b := _body
	var L := size
	var frame_col := Color(0.085, 0.105, 0.150)
	var strut := Color(0.13, 0.16, 0.22, 0.9)
	# Main spine truss (solid keel with faint lattice).
	_draw_lit_polygon(b, _rect_pts(Vector2.ZERO, Vector2(L, 6.0)), EnvArt.HULL_DARK, 1.2)
	for i in 30:
		var x := -L + 2.0 * L * float(i) / 30.0
		b.draw_line(Vector2(x, -6), Vector2(x + 2.0 * L / 30.0, 6), Color(EnvArt.HULL_PANEL, 0.35), 1.0, true)
	# Top/bottom rails of the build bay.
	var bay := L * 0.24
	b.draw_line(Vector2(-L * 0.66, -bay), Vector2(L * 0.66, -bay), strut, 4.0, true)
	b.draw_line(Vector2(-L * 0.66, bay), Vector2(L * 0.66, bay), strut, 4.0, true)
	# Gantry frames: thin solid struts, so they read as structure not wireframe.
	var frames := 6
	for i in frames:
		var x := lerpf(-L * 0.62, L * 0.62, float(i) / float(frames - 1))
		b.draw_line(Vector2(x, -bay - 6.0), Vector2(x, bay + 6.0), frame_col, 6.0, true)
		b.draw_line(Vector2(x + 2.0, -bay - 6.0), Vector2(x + 2.0, bay + 6.0), Color(EnvArt.RIM_LIGHT, 0.25), 1.0, true)
	# The ship being built: an elegant long hull, finished at the bow, skeletal aft.
	var hl := L * 0.55
	var hw := L * 0.10
	var hull := PackedVector2Array([
		Vector2(hl, 0), Vector2(hl * 0.62, -hw * 0.85), Vector2(hl * 0.2, -hw),
		Vector2(-hl * 0.1, -hw), Vector2(-hl * 0.1, hw), Vector2(hl * 0.2, hw), Vector2(hl * 0.62, hw * 0.85)])
	_draw_lit_polygon(b, hull, Color(0.19, 0.22, 0.28), 1.8)
	# Sun-side half of the hull catches more light (cheap volume).
	var lit_half := PackedVector2Array([Vector2(hl, 0), Vector2(hl * 0.62, -hw * 0.85), Vector2(hl * 0.2, -hw), Vector2(-hl * 0.1, -hw), Vector2(-hl * 0.1, 0)])
	if sun_dir.y > 0.0:
		for i in lit_half.size():
			lit_half[i].y = -lit_half[i].y
	b.draw_colored_polygon(lit_half, Color(0.55, 0.62, 0.75, 0.10))
	for i in 4:
		var x := hl * (0.45 - 0.14 * float(i))
		b.draw_line(Vector2(x, -hw * 0.9), Vector2(x, hw * 0.9), Color(0.08, 0.10, 0.14, 0.8), 1.0, true)
	b.draw_line(Vector2(hl * 0.85, 0), Vector2(-hl * 0.08, 0), Color(EnvArt.TECH_CYAN, 0.18), 1.0, true)
	# Skeletal aft section: ribs and longerons only.
	var rib := Color(0.21, 0.25, 0.32, 0.85)
	for i in 8:
		var x := -hl * 0.1 - float(i + 1) * hl * 0.1
		var w := hw * (1.0 - 0.03 * float(i))
		b.draw_line(Vector2(x, -w), Vector2(x, w), rib, 1.4, true)
	b.draw_line(Vector2(-hl * 0.1, -hw), Vector2(-hl * 0.9, -hw * 0.76), rib, 1.2, true)
	b.draw_line(Vector2(-hl * 0.1, hw), Vector2(-hl * 0.9, hw * 0.76), rib, 1.2, true)
	b.draw_line(Vector2(-hl * 0.1, 0), Vector2(-hl * 0.9, 0), rib, 1.8, true)
	# Habitat block / control tower at one end of the spine.
	var tower := _rect_pts(Vector2(L * 0.86, -L * 0.13), Vector2(L * 0.08, L * 0.065))
	_draw_lit_polygon(b, tower, EnvArt.HULL_MID)
	for i in 3:
		var y := -L * 0.17 + float(i) * L * 0.04
		b.draw_line(Vector2(L * 0.80, y), Vector2(L * 0.92, y), Color(EnvArt.WINDOW_WARM, 0.4), 1.2, true)


func _draw_cylinder() -> void:
	var b := _body
	var L := size
	var R := size * 0.2
	# Mirrors splayed from the sun-facing end (thin reflective vanes).
	for s in [-1.0, 1.0]:
		var root := Vector2(L * 0.92, s * R * 0.9)
		var tip := root + Vector2(L * 0.62, s * R * 1.7)
		var mirror := PackedVector2Array([root, tip, tip + Vector2(-L * 0.06, s * R * 0.45), root + Vector2(-L * 0.04, s * R * 0.2)])
		b.draw_colored_polygon(mirror, Color(0.22, 0.30, 0.44, 0.45))
		b.draw_line(root, tip, Color(0.60, 0.72, 0.88, 0.45), 1.2, true)
	# Capsule body.
	var body := PackedVector2Array()
	for i in 13:
		var a := -PI * 0.5 + PI * float(i) / 12.0
		body.append(Vector2(L - R, 0) + Vector2.from_angle(a) * R)
	for i in 13:
		var a := PI * 0.5 + PI * float(i) / 12.0
		body.append(Vector2(-L + R, 0) + Vector2.from_angle(a) * R)
	_draw_lit_polygon(b, body, EnvArt.HULL_DARK, 2.0)
	# Cylindrical shading: a soft lit band along the sun-facing flank.
	var side := -1.0 if sun_dir.y < 0.0 else 1.0
	b.draw_line(Vector2(-L + R, side * R * 0.62), Vector2(L - R, side * R * 0.62), Color(0.45, 0.52, 0.66, 0.16), R * 0.55, true)
	b.draw_line(Vector2(-L + R, -side * R * 0.6), Vector2(L - R, -side * R * 0.6), Color(0.0, 0.0, 0.02, 0.35), R * 0.6, true)
	# Long window strips (the habitat's "sky" windows) glowing faintly warm.
	for k in 3:
		var y := lerpf(-R * 0.45, R * 0.45, float(k) / 2.0)
		b.draw_line(Vector2(-L + R * 1.2, y), Vector2(L - R * 1.2, y), Color(EnvArt.WINDOW_WARM, 0.18 if k != 1 else 0.3), 1.4, true)
	# Structural ring bands.
	for i in 9:
		var x := lerpf(-L * 0.82, L * 0.82, float(i) / 8.0)
		b.draw_line(Vector2(x, -R), Vector2(x, R), Color(0.02, 0.03, 0.05, 0.7), 1.5, true)
	# Docking spindle on the far end.
	_draw_lit_polygon(b, _rect_pts(Vector2(-L - R * 0.45, 0), Vector2(R * 0.5, R * 0.2)), EnvArt.HULL_MID, 1.2)


func _draw_relay() -> void:
	var b := _body
	var s := size
	# Triangular truss with three dish antennas.
	var tri := PackedVector2Array([Vector2(0, -s), Vector2(s * 0.87, s * 0.5), Vector2(-s * 0.87, s * 0.5)])
	for i in 3:
		b.draw_line(tri[i], tri[(i + 1) % 3], EnvArt.HULL_MID, 4.0, true)
		b.draw_line(tri[i], Vector2.ZERO, EnvArt.HULL_DARK, 3.0, true)
	for i in 3:
		var p := tri[i]
		var d := p.normalized()
		b.draw_circle(p + d * s * 0.16, s * 0.2, EnvArt.HULL_MID)
		b.draw_arc(p + d * s * 0.16, s * 0.2, d.angle() - 1.2, d.angle() + 1.2, 16, Color(EnvArt.RIM_LIGHT, 0.5), 1.4, true)
		b.draw_circle(p + d * s * 0.16, s * 0.05, EnvArt.HULL_PANEL)
	b.draw_circle(Vector2.ZERO, s * 0.18, EnvArt.HULL_DARK)
	b.draw_arc(Vector2.ZERO, s * 0.18, 0.0, TAU, 24, Color(EnvArt.RIM_LIGHT, 0.4), 1.2, true)


func _draw_depot() -> void:
	var b := _body
	var s := size
	var tanks := [Vector2(-s * 0.55, -s * 0.3), Vector2(s * 0.05, -s * 0.45), Vector2(s * 0.6, -s * 0.15),
		Vector2(-s * 0.3, s * 0.4), Vector2(s * 0.35, s * 0.45)]
	# Truss connecting the tanks to a central keel.
	b.draw_line(Vector2(-s, 0), Vector2(s, 0), EnvArt.HULL_MID, 8.0, true)
	for t in tanks:
		b.draw_line(Vector2(t.x, 0), t, EnvArt.HULL_DARK, 4.0, true)
	for t in tanks:
		var r := s * 0.24
		b.draw_circle(t, r, EnvArt.HULL_DARK)
		var ang := sun_dir.angle()
		b.draw_arc(t, r - 1.0, ang - 1.2, ang + 1.2, 24, Color(EnvArt.RIM_LIGHT, 0.75), 1.8, true)
		b.draw_arc(t, r * 0.62, ang - 0.6, ang + 0.6, 16, Color(EnvArt.RIM_LIGHT, 0.18), 3.0, true)
		# Amber hazard band.
		b.draw_arc(t, r * 0.82, ang + 2.0, ang + 4.0, 16, Color(EnvArt.HAZARD_AMBER, 0.3), 2.0, true)


# -------------------------------------------------------------- lights ----
func _add_light(pos: Vector2, color: Color, sz: float, period := 0.0, phase := 0.0, decay := 6.0,
		on_body := false, base := 0.0) -> void:
	_light_defs.append({"pos": pos, "color": color, "size": sz, "period": period,
		"phase": phase, "decay": decay, "on_body": on_body, "base": base})


func _define_lights() -> void:
	match kind:
		Kind.WHEEL:
			for i in 6:
				var a := TAU * (float(i) + 0.5) / 6.0
				_add_light(Vector2.from_angle(a) * (size + 24.0), EnvArt.NAV_RED if i % 2 == 0 else EnvArt.NAV_GREEN, 16.0, 2.4, float(i) * 0.4, 3.5, true, 0.15)
			_add_light(Vector2.ZERO, EnvArt.STROBE, 34.0, 1.6, 0.0, 11.0)
			_add_light(Vector2.ZERO, EnvArt.TECH_CYAN, 22.0, 0.0, 0.0, 0.0, false, 0.35)
		Kind.SHIPYARD:
			_add_light(Vector2(-size, 0), EnvArt.NAV_RED, 22.0, 2.0, 0.0, 3.0, false, 0.1)
			_add_light(Vector2(size, 0), EnvArt.NAV_RED, 22.0, 2.0, 1.0, 3.0, false, 0.1)
			for i in 6:
				var x := lerpf(-size * 0.62, size * 0.62, float(i) / 5.0)
				_add_light(Vector2(x, -size * 0.25), EnvArt.STROBE, 12.0, 1.3, float(i) * 0.09, 14.0)
				_add_light(Vector2(x, size * 0.25), EnvArt.HAZARD_AMBER, 8.0, 0.0, 0.0, 0.0, false, 0.4)
			# Floodlights washing the hull under construction.
			for i in 3:
				_add_light(Vector2(size * (0.3 - 0.28 * float(i)), 0), Color(0.75, 0.9, 1.0), 70.0, 0.0, 0.0, 0.0, false, 0.07)
		Kind.CYLINDER:
			_add_light(Vector2(size + size * 0.06, 0), EnvArt.STROBE, 22.0, 2.8, 0.3, 9.0)
			_add_light(Vector2(-size - size * 0.15, 0), EnvArt.NAV_RED, 18.0, 2.8, 1.7, 3.0, false, 0.15)
			_add_light(Vector2(0, -size * 0.2), EnvArt.NAV_GREEN, 10.0, 0.0, 0.0, 0.0, false, 0.4)
		Kind.RELAY:
			_add_light(Vector2.ZERO, EnvArt.TECH_CYAN, 26.0, 1.1, 0.0, 2.5, false, 0.2)
			for i in 3:
				var a := -PI * 0.5 + TAU * float(i) / 3.0
				_add_light(Vector2.from_angle(a) * size, EnvArt.NAV_RED, 12.0, 1.8, float(i) * 0.6, 4.0, false, 0.1)
		Kind.DEPOT:
			_add_light(Vector2(-size, 0), EnvArt.HAZARD_AMBER, 16.0, 1.4, 0.0, 3.0, false, 0.15)
			_add_light(Vector2(size, 0), EnvArt.HAZARD_AMBER, 16.0, 1.4, 0.7, 3.0, false, 0.15)
			_add_light(Vector2(0, 0), EnvArt.STROBE, 20.0, 2.5, 0.2, 12.0)


func _draw_lights() -> void:
	var rot := _body.rotation
	for l in _light_defs:
		var k := EnvArt.blink(_time, l["period"], l["phase"], l["decay"])
		var a: float = maxf(k, l["base"])
		if a < 0.01:
			continue
		var p: Vector2 = l["pos"]
		if l["on_body"]:
			p = p.rotated(rot)
		var c: Color = l["color"]
		EnvArt.draw_glow(_lights, p, l["size"], Color(c, a * 0.9))
	if kind == Kind.SHIPYARD:
		# Welding sparks flickering on the unfinished hull.
		for i in 3:
			if _sparks_rng.randf() < 0.35:
				var p := Vector2(-size * (0.15 + 0.5 * _sparks_rng.randf()), size * 0.08 * (_sparks_rng.randf() * 2.0 - 1.0))
				EnvArt.draw_glow(_lights, p, 10.0 + 8.0 * _sparks_rng.randf(), Color(0.75, 0.9, 1.0, 0.9))
