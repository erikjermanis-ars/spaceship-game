class_name PlanetSystem
extends Node2D
## The home world plus its orbital infrastructure, drawn in one parallax layer
## so everything stays glued together: a tilted orbital ring (back half drawn
## behind the planet, front half in front), space-elevator threads from the
## surface up to the ring with climbing cars, and faint satellites.
##
## The local origin is the planet centre; one local unit = one layer unit.
## 3D maths is orthographic: view space x right, y down, z towards the viewer.

const SHADER := "res://assets/art/environment/shaders/planet.gdshader"

const RING_RADIUS := 1.42          # in planet radii
const QUAD_EXTENT := 1.22          # shader quad half-size in planet radii
const ELEVATOR_COUNT := 3
const SATELLITES := 22

var radius := 1450.0
var light_dir := Vector3(0.62, -0.45, -0.64)
## planet frame -> view space (pole is planet -Y, equator in planet XZ).
var view_from_planet := Basis()

var _planet_rect: ColorRect
var _mat: ShaderMaterial
var _ring_back: Node2D
var _ring_front: Node2D
var _dynamic: Node2D
var _spin := 0.0
var _cloud_spin := 0.0
var _time := 0.0
var _elevator_angles: Array[float] = []
var _sats: Array[Dictionary] = []


func setup(planet_radius: float, light: Vector3, screen_tilt_deg: float, pole_tilt_deg: float,
		surface_tex: Texture2D) -> void:
	radius = planet_radius
	light_dir = light.normalized()
	view_from_planet = Basis(Vector3(0, 0, 1), deg_to_rad(screen_tilt_deg)) \
		* Basis(Vector3(1, 0, 0), deg_to_rad(pole_tilt_deg))
	_build(surface_tex)


func _build(surface_tex: Texture2D) -> void:
	_ring_back = Node2D.new()
	_ring_back.name = "RingBack"
	_ring_back.draw.connect(_draw_ring.bind(_ring_back, false))
	add_child(_ring_back)

	_planet_rect = ColorRect.new()
	_planet_rect.name = "Planet"
	_planet_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ext := radius * QUAD_EXTENT
	_planet_rect.position = Vector2(-ext, -ext)
	_planet_rect.size = Vector2(ext, ext) * 2.0
	_mat = ShaderMaterial.new()
	_mat.shader = load(SHADER)
	_mat.set_shader_parameter("surface_tex", surface_tex)
	_mat.set_shader_parameter("view_to_planet", view_from_planet.transposed())
	_mat.set_shader_parameter("light_dir", light_dir)
	_mat.set_shader_parameter("extent", QUAD_EXTENT)
	_planet_rect.material = _mat
	add_child(_planet_rect)

	_ring_front = Node2D.new()
	_ring_front.name = "RingFront"
	_ring_front.draw.connect(_draw_ring.bind(_ring_front, true))
	_ring_front.draw.connect(_draw_elevators.bind(_ring_front))
	add_child(_ring_front)

	_dynamic = Node2D.new()
	_dynamic.name = "OrbitalLights"
	_dynamic.material = EnvArt.additive_material()
	_dynamic.draw.connect(_draw_dynamic)
	add_child(_dynamic)

	_pick_elevators()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7741
	for i in SATELLITES:
		var orbit := Basis(Vector3(0, 0, 1), rng.randf_range(-0.5, 0.5)) \
			* Basis(Vector3(1, 0, 0), rng.randf_range(-0.35, 0.35))
		_sats.append({
			"basis": view_from_planet * orbit,
			"r": rng.randf_range(1.03, 1.30),
			"phase": rng.randf() * TAU,
			# Lower orbits are faster (roughly Kepler-ish, just for feel).
			"speed": 0.0,
			"size": rng.randf_range(5.0, 9.0),
			"warm": rng.randf() < 0.3,
		})
		_sats[i]["speed"] = 0.010 / pow(_sats[i]["r"], 1.5) * (1.0 if rng.randf() < 0.8 else -1.0)


## Planet-frame direction -> view space position in local units.
func _project(p_planet: Vector3) -> Vector3:
	return view_from_planet * p_planet * radius


## 0 when the 3D point (in planet radii) sits in the planet's shadow, else 1.
func _sunlit(p_view: Vector3) -> float:
	var along := p_view.dot(light_dir)
	if along >= 0.0:
		return 1.0
	var perp := (p_view - light_dir * along).length()
	return clampf((perp - 0.97) / 0.06, 0.0, 1.0)


## Occluded by the planet disk if behind it (z < 0) and inside the silhouette.
func _occluded(v: Vector3) -> bool:
	return v.z < 0.0 and Vector2(v.x, v.y).length() < radius * 1.005


func _pick_elevators() -> void:
	# Choose the equator longitude whose elevator would be most visible: on the
	# near side (z > 0) and pointing up-right, towards where the camera usually
	# looks from the lower-left planet. Others are spaced evenly around.
	var want := Vector2(1.0, -0.85).normalized()
	var best := 0.0
	var best_score := -INF
	for i in 360:
		var a := TAU * float(i) / 360.0
		var v := view_from_planet * Vector3(cos(a), 0.0, sin(a))
		if v.z < 0.15:
			continue
		var score := Vector2(v.x, v.y).normalized().dot(want) + Vector2(v.x, v.y).length() * 0.6
		if score > best_score:
			best_score = score
			best = a
	_elevator_angles.clear()
	for k in ELEVATOR_COUNT:
		_elevator_angles.append(best + TAU * float(k) / float(ELEVATOR_COUNT) + (0.35 if k == 1 else 0.0))


func _ring_point(theta: float, r_scale := 1.0) -> Vector3:
	return view_from_planet * Vector3(cos(theta), 0.0, sin(theta)) * RING_RADIUS * r_scale


func _draw_ring(ci: Node2D, front: bool) -> void:
	var n := 720
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var hi_cols := PackedColorArray()
	var lights: Array[Vector2] = []
	for i in n + 1:
		var theta := TAU * float(i) / float(n)
		var p := _ring_point(theta)
		var is_front := p.z >= 0.0
		if is_front != front:
			_flush_ring(ci, pts, cols, hi_cols)
			continue
		var lit := _sunlit(p)
		var pos := Vector2(p.x, p.y) * radius
		pts.append(pos)
		# Far side of the ring is dimmer and bluer (seen through more haze).
		var depth_fade := 0.62 if not front else 1.0
		var base := EnvArt.HULL_MID.lerp(EnvArt.HULL_PANEL, 0.5)
		cols.append(Color(base.r * depth_fade, base.g * depth_fade, base.b * depth_fade, 0.5))
		var hc := EnvArt.RIM_LIGHT.lerp(Color(0.85, 0.9, 1.0), 0.4)
		hi_cols.append(Color(hc.r, hc.g, hc.b, (0.06 + 0.34 * lit) * depth_fade))
		if i % 9 == 0:
			lights.append(pos)
	_flush_ring(ci, pts, cols, hi_cols)
	# Habitat module windows along the ring: warm specks, brighter in shadow.
	var warm := EnvArt.WINDOW_WARM
	for l in lights:
		ci.draw_rect(Rect2(l - Vector2(1.6, 1.6), Vector2(3.2, 3.2)), Color(warm.r, warm.g, warm.b, 0.55 if front else 0.3))


func _flush_ring(ci: Node2D, pts: PackedVector2Array, cols: PackedColorArray, hi: PackedColorArray) -> void:
	if pts.size() >= 2:
		ci.draw_polyline_colors(pts, cols, 12.0, true)
		ci.draw_polyline_colors(pts, hi, 1.6, true)
	pts.clear()
	cols.clear()
	hi.clear()


func _draw_elevators(ci: Node2D) -> void:
	for a in _elevator_angles:
		var dir := Vector3(cos(a), 0.0, sin(a))
		var base := view_from_planet * dir
		if base.z < 0.02:
			continue
		var top := _ring_point(a)
		var b2 := Vector2(base.x, base.y) * radius
		var t2 := Vector2(top.x, top.y) * radius
		var lit := _sunlit(top)
		# Faint: they are thousands of km away and must not read as tethers
		# across the play space.
		ci.draw_line(b2, t2, Color(0.55, 0.70, 0.90, 0.08), 5.0, true)
		ci.draw_line(b2, t2, Color(0.80, 0.90, 1.00, 0.18 + 0.14 * lit), 1.0, true)
		# Anchor station on the ring: a small dark hub with a lit rim.
		var axis := (t2 - b2).normalized()
		var side := Vector2(-axis.y, axis.x)
		var hub := PackedVector2Array([
			t2 + side * 26.0 + axis * 6.0, t2 + side * 14.0 + axis * 18.0,
			t2 - side * 14.0 + axis * 18.0, t2 - side * 26.0 + axis * 6.0,
			t2 - side * 18.0 - axis * 10.0, t2 + side * 18.0 - axis * 10.0])
		ci.draw_colored_polygon(hub, EnvArt.HULL_MID)
		hub.append(hub[0])
		ci.draw_polyline(hub, Color(EnvArt.RIM_LIGHT, 0.35 + 0.5 * lit), 1.5, true)
		# Ground terminus: a bright city-hub patch.
		ci.draw_circle(b2, 3.5, Color(EnvArt.WINDOW_WARM, 0.8))


func _process(delta: float) -> void:
	_time += delta
	# Very slow surface rotation (a full day takes ~40 minutes of play).
	_spin = fposmod(_spin + delta * TAU / 2400.0, TAU)
	_cloud_spin = fposmod(_cloud_spin + delta * TAU / 1900.0, TAU)
	_mat.set_shader_parameter("spin", _spin)
	_mat.set_shader_parameter("cloud_spin", _cloud_spin)
	_dynamic.queue_redraw()


func _draw_dynamic() -> void:
	# Satellites / orbital traffic glints.
	for s in _sats:
		var a: float = s["phase"] + _time * float(s["speed"]) * 6.0
		var b: Basis = s["basis"]
		var v: Vector3 = b * Vector3(cos(a), 0.0, sin(a)) * float(s["r"])
		var vp := v * radius
		if _occluded(vp):
			continue
		var lit := _sunlit(v)
		var col: Color = EnvArt.WINDOW_WARM if s["warm"] else Color(0.8, 0.92, 1.0)
		var glint := 0.25 + 0.75 * lit * (0.6 + 0.4 * sin(_time * 1.7 + float(s["phase"]) * 9.0))
		EnvArt.draw_glow(_dynamic, Vector2(vp.x, vp.y), float(s["size"]), Color(col, 0.55 * glint))
	# Elevator climbers: cars sliding up and down the threads.
	for i in _elevator_angles.size():
		var a: float = _elevator_angles[i]
		var base := view_from_planet * Vector3(cos(a), 0.0, sin(a))
		if base.z < 0.02:
			continue
		var top := _ring_point(a)
		var b2 := Vector2(base.x, base.y) * radius
		var t2 := Vector2(top.x, top.y) * radius
		for k in 3:
			var u := fposmod(_time * 0.012 + float(k) / 3.0 + float(i) * 0.17, 1.0)
			var up := k != 1
			var f := u if up else 1.0 - u
			var p := b2.lerp(t2, f)
			EnvArt.draw_glow(_dynamic, p, 9.0, Color(EnvArt.TECH_CYAN if up else EnvArt.WINDOW_WARM, 0.75))
		# Beacon at the hub.
		var bl := EnvArt.blink(_time, 2.2, float(i) * 0.7, 4.0)
		EnvArt.draw_glow(_dynamic, t2 + (t2 - b2).normalized() * 20.0, 18.0, Color(EnvArt.NAV_RED, 0.9 * bl))
	# Ring beacons, strobing in sequence around the front arc.
	for k in 12:
		var th := TAU * float(k) / 12.0 + 0.13
		var p := _ring_point(th)
		if _occluded(p * radius):
			continue
		var bl := EnvArt.blink(_time, 3.0, float(k) * 0.25, 9.0)
		EnvArt.draw_glow(_dynamic, Vector2(p.x, p.y) * radius, 14.0, Color(EnvArt.STROBE, 0.8 * bl))


## Screen-space data the sun needs for eclipse tests (centre in local units).
func get_disk_radius() -> float:
	return radius
