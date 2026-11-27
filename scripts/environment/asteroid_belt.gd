class_name AsteroidBelt
extends Node2D
## One depth layer of the far asteroid belt in the Vesper sky look: hundreds
## of small rock silhouettes scattered along an arc of a huge orbit, plus an
## optional faint dust band. Everything is ONE static mesh (one draw call) that
## slowly rotates about the orbit's centre, which is this node's origin, so the
## rocks drift along the belt. Lighting is done in the vertex shader because
## the mesh turns and the sun does not.
##
## The belt is scenery: SpaceBackground keeps it dim and hazy so it never reads
## as rock you could hit. The asteroid field you can hit belongs to the level.
##
## Call setup(), then add_dust() / add_rocks().

const ROCK_SHADER := "res://assets/art/environment/shaders/belt_rocks.gdshader"
const DUST_SHADER := "res://assets/art/environment/shaders/belt_dust.gdshader"

var orbit_radius := 7000.0
## Orbital drift in rad/s (tiny: the rocks should creep, not fly).
var spin := 0.0003
## Towards the sun in layer space.
var sun_dir := Vector2(-0.9, 0.44)

var _ring: Node2D
var _rock_mat: ShaderMaterial


func setup(p_orbit_radius: float, p_spin: float, p_sun_dir: Vector2) -> void:
	orbit_radius = p_orbit_radius
	spin = p_spin
	sun_dir = p_sun_dir.normalized()
	_ring = Node2D.new()
	_ring.name = "Orbit"
	add_child(_ring)


## Scatters `count` rocks in a band of the given half width (2 sigma) around
## the orbit. `size_range` is the rock radius in layer units; most are small.
## May be called more than once (a big layer is built in batches); the colours
## of the first call apply to every batch.
func add_rocks(p_seed: int, count: int, half_width: float, size_range: Vector2, feather: float,
		lit: Color, shadow: Color, opacity: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed
	var verts := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for i in count:
		var ang := rng.randf() * TAU
		var off := clampf(rng.randfn(0.0, 0.5), -1.6, 1.6) * half_width
		var c := Vector2.from_angle(ang) * (orbit_radius + off)
		var size := lerpf(size_range.x, size_range.y, pow(rng.randf(), 3.5))
		_add_rock(rng, c, size, feather, verts, cols, idx)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance2D.new()
	mi.name = "Rocks"
	mi.mesh = mesh
	if _rock_mat == null:
		_rock_mat = ShaderMaterial.new()
		_rock_mat.shader = load(ROCK_SHADER)
		_rock_mat.set_shader_parameter("lit_color", lit)
		_rock_mat.set_shader_parameter("shadow_color", shadow)
		_rock_mat.set_shader_parameter("opacity", opacity)
		_rock_mat.set_shader_parameter("sun_local", sun_dir)
	mi.material = _rock_mat
	_ring.add_child(mi)


## One lumpy rock: a fan around an off-centre peak (so it reads as faceted),
## plus a transparent feather ring that stands in for antialiasing (no MSAA).
## Vertex colour = (normal.x, normal.y, albedo, alpha), decoded in the shader.
func _add_rock(rng: RandomNumberGenerator, c: Vector2, size: float, feather: float,
		verts: PackedVector2Array, cols: PackedColorArray, idx: PackedInt32Array) -> void:
	var n := rng.randi_range(6, 10)
	var rot := rng.randf() * TAU
	var stretch := rng.randf_range(1.0, 1.7)
	var albedo := rng.randf()
	var base := verts.size()
	var peak := Vector2(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.3, 0.3)).rotated(rot)
	verts.append(c + peak * size)
	# The peak leans a little the way it is offset; mostly it faces the viewer.
	cols.append(Color(0.5 + peak.x * 0.5, 0.5 + peak.y * 0.5, albedo, 1.0))
	for k in n:
		var a := TAU * (float(k) + rng.randf_range(-0.3, 0.3)) / float(n)
		var local := Vector2(cos(a) * stretch, sin(a)) * rng.randf_range(0.62, 1.1)
		var dir := local.rotated(rot)
		var nrm := dir.normalized()
		var enc := Color(0.5 + 0.46 * nrm.x, 0.5 + 0.46 * nrm.y, albedo, 1.0)
		verts.append(c + dir * size)
		cols.append(enc)
		verts.append(c + dir * size + nrm * feather)
		cols.append(Color(enc.r, enc.g, albedo, 0.0))
	for k in n:
		var a0 := base + 1 + 2 * k
		var a1 := base + 1 + 2 * ((k + 1) % n)
		idx.append_array(PackedInt32Array([base, a0, a1, a0, a0 + 1, a1 + 1, a0, a1 + 1, a1]))


## A faint additive dust band along the orbit. `noise_tex` must tile.
func add_dust(noise_tex: Texture2D, half_width: float, tint: Color, gain: float) -> void:
	var segs := 256
	var rows := 8
	var verts := PackedVector2Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	# Whole number of noise tiles around the orbit, so the strip has no seam.
	var u_tiles := maxf(roundf(TAU * orbit_radius / (half_width * 4.0)), 1.0)
	for i in segs + 1:
		var dir := Vector2.from_angle(TAU * float(i) / float(segs))
		for j in rows + 1:
			var v := float(j) / float(rows)
			var bell := pow(1.0 - pow(2.0 * v - 1.0, 2.0), 2.0)
			verts.append(dir * (orbit_radius + (2.0 * v - 1.0) * half_width))
			cols.append(Color(1.0, 1.0, 1.0, bell))
			uvs.append(Vector2(float(i) / float(segs) * u_tiles, v * 0.5))
	for i in segs:
		for j in rows:
			var a := i * (rows + 1) + j
			var b := a + rows + 1
			idx.append_array(PackedInt32Array([a, b, a + 1, a + 1, b, b + 1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance2D.new()
	mi.name = "Dust"
	mi.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = load(DUST_SHADER)
	mat.set_shader_parameter("noise_tex", noise_tex)
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("gain", gain)
	mi.material = mat
	_ring.add_child(mi)
	_ring.move_child(mi, 0)


func _process(delta: float) -> void:
	_ring.rotation = fposmod(_ring.rotation + spin * delta, TAU)
	if _rock_mat != null:
		_rock_mat.set_shader_parameter("sun_local", sun_dir.rotated(-_ring.rotation))
