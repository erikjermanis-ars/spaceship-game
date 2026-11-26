class_name SpaceBackground
extends CanvasLayer
## The establishing-shot backdrop: deep space, nebula, stars, the home planet
## with its orbital ring and elevators, a moon, far-off stations, distant
## traffic and the sun's glare. Renders on CanvasLayer -10 and does its OWN
## parallax from the active camera, so it has zero gameplay coupling: drop the
## scene anywhere and it follows whatever Camera2D the viewport uses.
##
## Parallax model: a layer with factor p is treated as lying at a depth behind
## the play plane such that it moves p times as fast as the world. Its zoom is
## derived physically from the camera zoom: s = 1 / (p / zoom + 1 - p), so far
## layers barely scale when the camera speed-zooms out, near ones scale more.
##
## Cost: two fullscreen shader passes (sky, sun glare), one partial (planet),
## a few cached _draw() silhouettes, and two one-off bakes at startup.

const SHADERS := "res://assets/art/environment/shaders/"

## Layer-space layout, chosen for the view from the world origin (where the
## station sits): planet lower-left, sun top-right, moon top-centre.
const PLANET_PARALLAX := 0.15
const PLANET_ANCHOR := Vector2(-1500.0, 1250.0)
const PLANET_RADIUS := 1450.0
const MOON_PARALLAX := 0.08
const MOON_ANCHOR := Vector2(-260.0, -380.0)
const MOON_RADIUS := 34.0
const SUN_PARALLAX := 0.01
## Sun position as a fraction of the visible screen (top-right corner area).
const SUN_SCREEN := Vector2(0.885, 0.15)
## How far "behind" the planet the sun is (negative z = backlit crescent).
const SUN_DEPTH := -1.3

@export var nebula_bake_size := 1024
@export var planet_bake_size := Vector2i(2048, 1024)
## Overall brightness multiplier of the sun glare (1 = default look).
@export var sun_intensity := 1.0

var _layers: Array[Dictionary] = []   # {node: Node2D, p: float, anchor: Vector2}
var _sky: ColorRect
var _sky_mat: ShaderMaterial
var _sun: ColorRect
var _sun_mat: ShaderMaterial
var _moon_mat: ShaderMaterial
var _planet: PlanetSystem
var _light_dir := Vector3(0.62, -0.45, -0.64)
var _time := 0.0


func _ready() -> void:
	layer = -10
	follow_viewport_enabled = false
	# Run after cameras/rigs so we read this frame's final canvas transform.
	process_priority = 1000
	_light_dir = _compute_light_dir()
	var nebula_tex := _make_bake("nebula_bake.gdshader", Vector2i(nebula_bake_size, nebula_bake_size))
	var planet_tex := _make_bake("planet_bake.gdshader", planet_bake_size)
	_build_sky(nebula_tex)
	_build_moon()
	_build_planet(planet_tex)
	_build_far_traffic()
	_build_stations()
	_build_near_traffic()
	_build_sun()
	_update_view()


## Direction towards the sun in planet view space: on screen it points from
## the planet (lower-left) to the glare (top-right), and it sits somewhat
## behind the planet, which gives the dramatic backlit crescent + night side.
func _compute_light_dir() -> Vector3:
	var ref := Vector2(1920.0, 1080.0)
	var sun_c := (SUN_SCREEN - Vector2(0.5, 0.5)) * ref
	var d := (sun_c - PLANET_ANCHOR).normalized()
	return Vector3(d.x, d.y, SUN_DEPTH).normalized()


func _make_bake(shader_file: String, size: Vector2i) -> Texture2D:
	var vp := SubViewport.new()
	vp.name = shader_file.get_basename().to_pascal_case()
	vp.size = size
	vp.disable_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var rect := ColorRect.new()
	rect.size = Vector2(size)
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADERS + shader_file)
	rect.material = mat
	vp.add_child(rect)
	add_child(vp)
	return vp.get_texture()


func _full_rect(rect_name: String, shader_file: String) -> ColorRect:
	var r := ColorRect.new()
	r.name = rect_name
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	var m := ShaderMaterial.new()
	m.shader = load(SHADERS + shader_file)
	r.material = m
	add_child(r)
	return r


func _build_sky(nebula_tex: Texture2D) -> void:
	_sky = _full_rect("Sky", "sky.gdshader")
	_sky_mat = _sky.material
	_sky_mat.set_shader_parameter("nebula_tex", nebula_tex)
	_sky_mat.set_shader_parameter("sun_uv", SUN_SCREEN)


func _add_layer(node: Node2D, p: float, anchor: Vector2) -> void:
	add_child(node)
	_layers.append({"node": node, "p": p, "anchor": anchor})


func _build_moon() -> void:
	var holder := Node2D.new()
	holder.name = "Moon"
	var r := ColorRect.new()
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ext := 1.15
	r.position = Vector2(-MOON_RADIUS, -MOON_RADIUS) * ext
	r.size = Vector2(MOON_RADIUS, MOON_RADIUS) * 2.0 * ext
	_moon_mat = ShaderMaterial.new()
	_moon_mat.shader = load(SHADERS + "moon.gdshader")
	# The moon gets a less backlit sun so it reads as a crescent, not a hole.
	_moon_mat.set_shader_parameter("light_dir", Vector3(_light_dir.x, _light_dir.y, -0.25))
	_moon_mat.set_shader_parameter("extent", ext)
	r.material = _moon_mat
	holder.add_child(r)
	_add_layer(holder, MOON_PARALLAX, MOON_ANCHOR)


func _build_planet(surface_tex: Texture2D) -> void:
	_planet = PlanetSystem.new()
	_planet.name = "PlanetSystem"
	_planet.setup(PLANET_RADIUS, _light_dir, -32.0, 36.0, surface_tex)
	_add_layer(_planet, PLANET_PARALLAX, PLANET_ANCHOR)


func _build_far_traffic() -> void:
	var t := DistantTraffic.new()
	t.name = "FarTraffic"
	t.setup(31, 14, Rect2(-3200, -2400, 6400, 4800), Vector2(14.0, 34.0), 6.0, 0.7)
	_add_layer(t, 0.22, Vector2.ZERO)


func _build_stations() -> void:
	var sun2 := Vector2(_light_dir.x, _light_dir.y).normalized()
	# [kind, layer anchor, size, rotation, parallax, spin]
	var defs := [
		[DistantStation.Kind.WHEEL, Vector2(-640, -270), 165.0, 0.0, 0.40, 0.045],
		[DistantStation.Kind.SHIPYARD, Vector2(1450, 420), 210.0, -0.28, 0.36, 0.0],
		[DistantStation.Kind.CYLINDER, Vector2(560, 860), 170.0, 0.42, 0.33, 0.0],
		[DistantStation.Kind.RELAY, Vector2(1900, -1050), 55.0, 0.3, 0.45, 0.0],
		[DistantStation.Kind.DEPOT, Vector2(-2150, -500), 85.0, -0.6, 0.38, 0.0],
		[DistantStation.Kind.WHEEL, Vector2(2700, 1500), 95.0, 0.0, 0.30, -0.06],
		[DistantStation.Kind.CYLINDER, Vector2(-2600, 1700), 140.0, -0.9, 0.34, 0.0],
		[DistantStation.Kind.RELAY, Vector2(-900, -1700), 50.0, 1.1, 0.42, 0.0],
		[DistantStation.Kind.SHIPYARD, Vector2(-3400, 300), 170.0, 1.3, 0.37, 0.0],
		[DistantStation.Kind.DEPOT, Vector2(3300, -600), 75.0, 0.4, 0.40, 0.0],
		[DistantStation.Kind.WHEEL, Vector2(-300, -2300), 120.0, 0.0, 0.33, 0.05],
		[DistantStation.Kind.WHEEL, Vector2(3150, -2350), 140.0, 0.0, 0.38, -0.04],
		[DistantStation.Kind.SHIPYARD, Vector2(2300, -2900), 150.0, 0.5, 0.36, 0.0],
		[DistantStation.Kind.DEPOT, Vector2(-3300, -2200), 80.0, 0.9, 0.38, 0.0],
		[DistantStation.Kind.RELAY, Vector2(3500, 2500), 55.0, -0.4, 0.40, 0.0],
	]
	var i := 0
	for d in defs:
		var s := DistantStation.new()
		s.name = "Distant%02d" % i
		s.setup(d[0], d[2], d[3], sun2, d[5])
		# Depth haze: the farther the layer, the dimmer and bluer it reads.
		# Even the nearest stays well under foreground hull brightness so the
		# silhouettes never read as something you could hit.
		var h := clampf((float(d[4]) - 0.28) / 0.17, 0.0, 1.0)
		s.modulate = Color(lerpf(0.42, 0.6, h), lerpf(0.48, 0.66, h), lerpf(0.62, 0.8, h), lerpf(0.7, 0.85, h))
		_add_layer(s, d[4], d[1])
		i += 1


func _build_near_traffic() -> void:
	var t := DistantTraffic.new()
	t.name = "NearTraffic"
	t.setup(77, 9, Rect2(-3600, -2600, 7200, 5200), Vector2(40.0, 95.0), 10.0, 1.0)
	_add_layer(t, 0.40, Vector2.ZERO)


func _build_sun() -> void:
	_sun = _full_rect("SunGlare", "sun_glare.gdshader")
	_sun_mat = _sun.material
	_sun_mat.set_shader_parameter("intensity", sun_intensity)


func _process(delta: float) -> void:
	_time += delta
	_update_view()


## Reads the viewport's final canvas transform (camera position, zoom,
## rotation, shake/offset included) and positions every layer from it.
func _update_view() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var view := vp.get_visible_rect().size
	var ct := vp.get_canvas_transform()
	var zoom := maxf(ct.get_scale().x, 0.001)
	var rot := ct.get_rotation()
	var center := view * 0.5
	var cam := ct.affine_inverse() * center

	for l in _layers:
		var p: float = l["p"]
		var s := 1.0 / (p / zoom + 1.0 - p)
		var off: Vector2 = (Vector2(l["anchor"]) - cam * p).rotated(rot) * s
		var n: Node2D = l["node"]
		n.transform = Transform2D(rot, Vector2(s, s), 0.0, center + off)

	_sky_mat.set_shader_parameter("cam_pos", cam)
	_sky_mat.set_shader_parameter("cam_zoom", zoom)
	_sky_mat.set_shader_parameter("cam_rot", rot)
	_sky_mat.set_shader_parameter("view_size", view)
	_sky_mat.set_shader_parameter("twinkle_time", fposmod(_time, 6283.0))

	# Sun: pinned near a screen corner with a whisper of parallax.
	var s_sun := 1.0 / (SUN_PARALLAX / zoom + 1.0 - SUN_PARALLAX)
	var sun_off := ((SUN_SCREEN - Vector2(0.5, 0.5)) * view - cam * SUN_PARALLAX * s_sun).rotated(rot)
	var sun_pos := center + sun_off
	_sun_mat.set_shader_parameter("view_size", view)
	_sun_mat.set_shader_parameter("sun_pos", sun_pos)
	_sky_mat.set_shader_parameter("sun_uv", sun_pos / view)
	# Eclipse: fade the glare when the planet disk slides over the sun.
	var pl: Node2D = _planet
	var pc := pl.transform.origin
	var pr := PLANET_RADIUS * pl.transform.get_scale().x
	var dist := sun_pos.distance_to(pc)
	var vis := smoothstep(pr * 0.985, pr * 1.06, dist)
	_sun_mat.set_shader_parameter("sun_vis", vis)
