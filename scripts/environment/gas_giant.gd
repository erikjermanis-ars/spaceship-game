class_name GasGiant
extends Node2D
## The ringed gas giant of the Vesper sky look. One shader quad draws the globe
## and its rings together (see gas_giant.gdshader), so this node only builds
## the quad, the 1D ring profile texture, and turns the cloud tops slowly.
##
## The local origin is the planet centre; one local unit = one layer unit.

const SHADER := "res://assets/art/environment/shaders/gas_giant.gdshader"
const RING_INNER := 1.22           # in planet radii
const RING_OUTER := 2.35
const QUAD_EXTENT := 2.45          # shader quad half-size in planet radii
const RING_TEXELS := 1024

var radius := 640.0

var _mat: ShaderMaterial
## Starts with the great storm on the face seen from the outpost.
var _spin := 3.15


func setup(planet_radius: float, light: Vector3, screen_tilt_deg: float, pole_tilt_deg: float,
		surface_tex: Texture2D) -> void:
	radius = planet_radius
	# Same convention as PlanetSystem: planet frame -> view space, pole = -Y.
	var view_from_planet := Basis(Vector3(0, 0, 1), deg_to_rad(screen_tilt_deg)) \
		* Basis(Vector3(1, 0, 0), deg_to_rad(pole_tilt_deg))
	var rect := ColorRect.new()
	rect.name = "Giant"
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ext := radius * QUAD_EXTENT
	rect.position = Vector2(-ext, -ext)
	rect.size = Vector2(ext, ext) * 2.0
	_mat = ShaderMaterial.new()
	_mat.shader = load(SHADER)
	_mat.set_shader_parameter("surface_tex", surface_tex)
	_mat.set_shader_parameter("ring_tex", _make_ring_texture())
	_mat.set_shader_parameter("view_to_planet", view_from_planet.transposed())
	_mat.set_shader_parameter("light_dir", light.normalized())
	_mat.set_shader_parameter("extent", QUAD_EXTENT)
	_mat.set_shader_parameter("ring_inner", RING_INNER)
	_mat.set_shader_parameter("ring_outer", RING_OUTER)
	rect.material = _mat
	add_child(rect)


func _process(delta: float) -> void:
	# A giant turns fast for its size, but it is far away: ~25 minutes a turn
	# keeps the storms visibly drifting without looking like a spinning ball.
	_spin = fposmod(_spin + delta * TAU / 1500.0, TAU)
	_mat.set_shader_parameter("spin", _spin)


## Radial ring profile, inner edge -> outer edge. R = optical density,
## G = tint (0 dusty .. 1 bright ice). Built on the CPU because it is 1D and
## tiny, and so it can carry mipmaps (the bake viewports cannot).
func _make_ring_texture() -> Texture2D:
	var rng := RandomNumberGenerator.new()
	rng.seed = 90411
	# Three octaves of value noise along the radius give ringlets of all widths.
	var knots: Array[PackedFloat32Array] = []
	for cells: int in [14, 55, 210]:
		var k := PackedFloat32Array()
		for i in cells + 1:
			k.append(rng.randf())
		knots.append(k)
	var img := Image.create(RING_TEXELS, 1, false, Image.FORMAT_RGBA8)
	for x in RING_TEXELS:
		var u := (float(x) + 0.5) / float(RING_TEXELS)
		var n := 0.5 * _knot(knots[0], u) + 0.3 * _knot(knots[1], u) + 0.2 * _knot(knots[2], u)
		# Broad structure, Saturn-like: a faint inner ring, a dense bright main
		# ring, a wide dark division, a paler outer ring with one narrow gap,
		# and a thin isolated ringlet near the edge.
		var d := 0.0
		d += 0.22 * _span(u, 0.02, 0.20, 0.02)
		d += 0.92 * _span(u, 0.20, 0.56, 0.012)
		d += 0.05 * _span(u, 0.56, 0.635, 0.008)
		d += 0.62 * _span(u, 0.635, 0.875, 0.012)
		d -= 0.55 * _span(u, 0.785, 0.800, 0.004)
		d += 0.30 * _span(u, 0.925, 0.945, 0.006)
		d = clampf(d * (0.55 + 0.9 * n), 0.0, 1.0)
		var tint := clampf(0.25 + 0.9 * _span(u, 0.20, 0.56, 0.05) * (0.5 + n) + 0.35 * _span(u, 0.635, 0.875, 0.03), 0.0, 1.0)
		img.set_pixel(x, 0, Color(d, tint, 0.0, 1.0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _knot(k: PackedFloat32Array, u: float) -> float:
	var f := u * float(k.size() - 1)
	var i := mini(int(f), k.size() - 2)
	var t := f - float(i)
	return lerpf(k[i], k[i + 1], t * t * (3.0 - 2.0 * t))


## 1 inside [a, b], with soft edges of width `e`.
static func _span(u: float, a: float, b: float, e: float) -> float:
	return smoothstep(a - e, a + e, u) * (1.0 - smoothstep(b - e, b + e, u))
