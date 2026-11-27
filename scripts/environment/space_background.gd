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
##
## Looks: the backdrop can show more than one place. A SkyLook holds a place's
## parallax layers and its overrides for the two shared fullscreen passes;
## set_look() swaps them instantly (the jump hides the cut under a flash).
## Meridian is built at startup. Other looks are built a moment later, hidden,
## so startup is no slower and the swap itself does not hitch.

const SHADERS := "res://assets/art/environment/shaders/"

const GROUP := &"space_background"
const LOOK_MERIDIAN := &"meridian"
const LOOK_VESPER := &"vesper"
## World position (px) of VESPER ROCK: the origin `--sky-look=vesper` uses.
const VESPER_ORIGIN := Vector2(90000.0, 0.0)
## Seconds after startup before the other looks are baked in the background.
const PREBAKE_DELAY := 1.5
## Frames a freshly built look is drawn hidden behind the sky, so its shaders
## compile then and not on the frame of the swap.
const WARM_FRAMES := 3

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

var _looks := {}                      # StringName -> SkyLook
var _active: SkyLook
var _origin := Vector2.ZERO           # world position the active look is composed around
var _prebake_in := PREBAKE_DELAY
var _prebuilding: SkyLook             # look being built ahead of time, a step per frame
var _warming: SkyLook                 # look being drawn under the sky to compile its shaders
var _warm_left := 0
var _sky: ColorRect
var _sky_mat: ShaderMaterial
var _sun: ColorRect
var _sun_mat: ShaderMaterial
var _planet: PlanetSystem
var _light_dir := Vector3(0.62, -0.45, -0.64)
var _time := 0.0


func _ready() -> void:
	layer = -10
	# The jump sequence finds the backdrop through this group to call set_look().
	add_to_group(GROUP)
	follow_viewport_enabled = false
	# Run after cameras/rigs so we read this frame's final canvas transform.
	process_priority = 1000
	_light_dir = _compute_light_dir()
	var nebula_tex := make_bake("nebula_bake.gdshader", Vector2i(nebula_bake_size, nebula_bake_size))
	var planet_tex := make_bake("planet_bake.gdshader", planet_bake_size)
	_build_sky(nebula_tex)
	_active = SkyLook.new(LOOK_MERIDIAN)
	_active.sun_screen = SUN_SCREEN
	# Only the texture is listed: every other Meridian value is the shader's
	# default, which set_look() restores by clearing the other look's overrides.
	_active.sky_params = {"nebula_tex": nebula_tex}
	_looks[LOOK_MERIDIAN] = _active
	add_child(_active.root)
	_build_moon()
	_build_planet(planet_tex)
	_build_far_traffic()
	_build_stations()
	_build_near_traffic()
	_build_sun()
	if Game.cmd.has("sky-look"):
		set_look(StringName(String(Game.cmd["sky-look"])), VESPER_ORIGIN)
	_update_view()


## Switch the whole backdrop to another place. Instant (called under a white flash).
## `world_origin` = the world position (px) the composition is designed around:
## parallax is computed from (camera - world_origin), so each look frames its
## own station the way the Meridian look frames (0, 0).
func set_look(id: StringName, world_origin: Vector2) -> void:
	var next := _ensure_look(id)
	if next == null:
		return
	# Needed now: finish whatever the ahead-of-time build had left.
	next.finish()
	if next == _prebuilding:
		_prebuilding = null
	_origin = world_origin
	if next != _active:
		_end_warm()
		_show_look(_active, false)
		# Clear the old look's overrides (back to the shader defaults, which
		# are Meridian's values), then apply the new look's.
		for k: String in _active.sky_params:
			_sky_mat.set_shader_parameter(k, null)
		for k: String in _active.sun_params:
			_sun_mat.set_shader_parameter(k, null)
		_active = next
		for k: String in next.sky_params:
			_sky_mat.set_shader_parameter(k, next.sky_params[k])
		for k: String in next.sun_params:
			_sun_mat.set_shader_parameter(k, next.sun_params[k])
		_sun_mat.set_shader_parameter("intensity", sun_intensity * next.sun_gain)
		_show_look(next, true)
	_update_view()


## The id of the look on screen (`&"meridian"` at startup).
func look() -> StringName:
	return _active.id


## World position (px) the active look is composed around.
func look_origin() -> Vector2:
	return _origin


## Returns the look, building it now if this is the first time it is needed.
func _ensure_look(id: StringName) -> SkyLook:
	if _looks.has(id):
		return _looks[id]
	if id != LOOK_VESPER:
		push_warning("SpaceBackground: unknown sky look '%s'" % id)
		return null
	var built := VesperSky.build(self)
	_looks[id] = built
	_show_look(built, false)
	add_child(built.root)
	# Between the sky and the sun glare, like the Meridian layers.
	var meridian: SkyLook = _looks[LOOK_MERIDIAN]
	move_child(built.root, meridian.root.get_index() + 1)
	return built


## A hidden look is also stopped, so its per-frame work costs nothing.
func _show_look(l: SkyLook, on: bool) -> void:
	l.root.visible = on
	l.root.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED


## Ahead-of-time build of the other look, part 2 (part 1 is its build steps,
## one per frame, in _process): draw it for a few frames UNDER the opaque sky
## pass. The bakes render and every shader compiles while nothing can be
## seen, so the swap during a jump is just a visibility flip.
func _start_warm(l: SkyLook) -> void:
	if l == _active:
		return
	_warming = l
	_warm_left = WARM_FRAMES
	l.root.z_index = -1
	l.root.visible = true


func _end_warm() -> void:
	if _warming == null:
		return
	_warming.root.z_index = 0
	if _warming != _active:
		_warming.root.visible = false
	_warming = null


## Direction towards the sun in planet view space: on screen it points from
## the planet (lower-left) to the glare (top-right), and it sits somewhat
## behind the planet, which gives the dramatic backlit crescent + night side.
func _compute_light_dir() -> Vector3:
	var ref := Vector2(1920.0, 1080.0)
	var sun_c := (SUN_SCREEN - Vector2(0.5, 0.5)) * ref
	var d := (sun_c - PLANET_ANCHOR).normalized()
	return Vector3(d.x, d.y, SUN_DEPTH).normalized()


## Renders `shader_file` once into a texture (SubViewport, UPDATE_ONCE).
## `params` are uniforms for that one bake: looks share the bake shaders.
func make_bake(shader_file: String, size: Vector2i, params := {}, node_name := "") -> Texture2D:
	var vp := SubViewport.new()
	vp.name = node_name if node_name != "" else shader_file.get_basename().to_pascal_case()
	vp.size = size
	vp.disable_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var rect := ColorRect.new()
	rect.size = Vector2(size)
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADERS + shader_file)
	for k: String in params:
		mat.set_shader_parameter(k, params[k])
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


## Meridian's builders below add to the look being built (the active one).
func _add_layer(node: Node2D, p: float, anchor: Vector2) -> void:
	_active.add_layer(node, p, anchor)


## A small lit sphere on its own quad (moon.gdshader). `params` override the
## shader's surface uniforms; with none it is Meridian's grey moon.
func make_moon(moon_name: String, radius: float, light: Vector3, params := {}) -> Node2D:
	var holder := Node2D.new()
	holder.name = moon_name
	var r := ColorRect.new()
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ext := 1.15
	r.position = Vector2(-radius, -radius) * ext
	r.size = Vector2(radius, radius) * 2.0 * ext
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADERS + "moon.gdshader")
	mat.set_shader_parameter("light_dir", light)
	mat.set_shader_parameter("extent", ext)
	for k: String in params:
		mat.set_shader_parameter(k, params[k])
	r.material = mat
	holder.add_child(r)
	return holder


func _build_moon() -> void:
	# The moon gets a less backlit sun so it reads as a crescent, not a hole.
	var moon := make_moon("Moon", MOON_RADIUS, Vector3(_light_dir.x, _light_dir.y, -0.25))
	_add_layer(moon, MOON_PARALLAX, MOON_ANCHOR)


func _build_planet(surface_tex: Texture2D) -> void:
	_planet = PlanetSystem.new()
	_planet.name = "PlanetSystem"
	_planet.setup(PLANET_RADIUS, _light_dir, -32.0, 36.0, surface_tex)
	_add_layer(_planet, PLANET_PARALLAX, PLANET_ANCHOR)
	_active.disk = _planet
	_active.disk_radius = PLANET_RADIUS


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
	if _warming != null:
		_warm_left -= 1
		if _warm_left <= 0:
			_end_warm()
	elif _prebuilding != null:
		if not _prebuilding.step():
			_start_warm(_prebuilding)
			_prebuilding = null
	elif _prebake_in > 0.0:
		_prebake_in -= delta
		if _prebake_in <= 0.0 and not _looks.has(LOOK_VESPER):
			_prebuilding = _ensure_look(LOOK_VESPER)
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
	# Camera position relative to the place this look is composed around.
	var cam := ct.affine_inverse() * center - _origin

	_place_layers(_active, cam, zoom, rot, center)
	if _warming != null:
		# The warm-up draws the look as it will appear from its own origin.
		_place_layers(_warming, Vector2.ZERO, zoom, rot, center)

	_sky_mat.set_shader_parameter("cam_pos", cam + _active.sky_offset)
	_sky_mat.set_shader_parameter("cam_zoom", zoom)
	_sky_mat.set_shader_parameter("cam_rot", rot)
	_sky_mat.set_shader_parameter("view_size", view)
	_sky_mat.set_shader_parameter("twinkle_time", fposmod(_time, 6283.0))

	# Sun: pinned near a screen corner with a whisper of parallax.
	var s_sun := 1.0 / (SUN_PARALLAX / zoom + 1.0 - SUN_PARALLAX)
	var sun_off := ((_active.sun_screen - Vector2(0.5, 0.5)) * view - cam * SUN_PARALLAX * s_sun).rotated(rot)
	var sun_pos := center + sun_off
	_sun_mat.set_shader_parameter("view_size", view)
	_sun_mat.set_shader_parameter("sun_pos", sun_pos)
	_sky_mat.set_shader_parameter("sun_uv", sun_pos / view)
	# Eclipse: fade the glare when the planet disk slides over the sun.
	var pl := _active.disk
	var pc := pl.transform.origin
	var pr := _active.disk_radius * pl.transform.get_scale().x
	var dist := sun_pos.distance_to(pc)
	var vis := smoothstep(pr * 0.985, pr * 1.06, dist)
	_sun_mat.set_shader_parameter("sun_vis", vis)


func _place_layers(l: SkyLook, cam: Vector2, zoom: float, rot: float, center: Vector2) -> void:
	for d in l.layers:
		var p: float = d["p"]
		var s := 1.0 / (p / zoom + 1.0 - p)
		var off: Vector2 = (Vector2(d["anchor"]) - cam * p).rotated(rot) * s
		var n: Node2D = d["node"]
		n.transform = Transform2D(rot, Vector2(s, s), 0.0, center + off)
