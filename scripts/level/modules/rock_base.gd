@tool
extends StationModule
## Vesper Rock: the asteroid the mining outpost is bolted onto. About
## 315 m x 250 m of faceted rock with a terrace cut into its south face for
## the landing apron (OutpostApron fills the cut).
##
## The whole rock collides (convex pieces of the outline), so everything
## standing on it (habitats, domes, the ore plant: RockWorks) is paint.
## The surface is a seeded low-poly mesh (RockArt): Delaunay facets shaded
## from a height field that rises from the edge to a plateau, so the sunward
## rim is bright, the far rim dark, and the top reads as flat ground.
## Local origin = the Base node (230 m south of Vesper's origin, which is the
## frigate berth), metres.

const R := preload("res://scripts/level/rock_art.gd")
const Works := preload("res://scripts/level/modules/rock_works.gd")

const SEED := 2212
const CENTRE := Vector2(-45, 0)
const RADII := Vector2(158, 125)
## The cut for the landing apron (m): a trapezoid opening to the south.
const TERRACE := [Vector2(-160, 52), Vector2(50, 52), Vector2(56, 260), Vector2(-166, 260)]
## Albedo of level ground, one per stratum.
const STRATA := [Color("6E6A69"), Color("5D5F6A"), Color("787068"), Color("64656E")]
const STRATA_DIR := Vector2(0.34, 0.94)
const STRATA_M := 36.0
const FACET_M := 15.0
## The edge slopes up to the plateau over RIM_M, PLATEAU_M high.
const RIM_M := 16.0
const PLATEAU_M := 14.0
## Open-cut pit: centre and radii (m).
const PIT := Rect2(-172, -8, 60, 44)
## Impact craters: x, y, radius (m), away from the buildings.
const CRATERS := [
	[-192.0, -8.0, 6.0], [-150.0, -84.0, 9.0], [-118.0, 60.0, 5.0], [92.0, -62.0, 8.0],
	[84.0, 46.0, 10.0], [102.0, 24.0, 4.0], [-176.0, 58.0, 4.0],
	[-98.0, -18.0, 5.5], [28.0, -52.0, 4.0],
]


## The rock before the terrace is cut (px). The apron tucks its deck under it.
static func raw_outline() -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var out := R.blob(rng, RADII.x * PX, RADII.y * PX, 46, 0.1, 2.5)
	for i in out.size():
		out[i] += CENTRE * PX
	return out


static func terrace() -> PackedVector2Array:
	var out := PackedVector2Array()
	for v: Vector2 in TERRACE:
		out.append(v * PX)
	return out


## The colliding outline (px): the rock minus the terrace.
static func rock_outline() -> PackedVector2Array:
	var best := PackedVector2Array()
	for p in Geometry2D.clip_polygons(raw_outline(), terrace()):
		if R.area(p) > R.area(best):
			best = p
	return best


func _build() -> void:
	var rock := rock_outline()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 1
	solids.append(rock)
	for piece in Geometry2D.decompose_polygon_in_convex(rock):
		pieces.append(piece)
	fill(Band.DECK_SHADOW, rock, A.HULL_SHADOW)
	var mesh := R.Facets.new()
	R.stroke(mesh, rock, 5.0)
	mesh.poly(rock, STRATA[1].darkened(0.25), Vector2.ZERO)   # under any hairline gaps
	_facet(mesh, rock, rng)
	_strata_lines(mesh, rock)
	_pit(mesh, rng)
	for c: Array in CRATERS:
		var p := m(c[0], c[1])
		var r: float = c[2] * PX
		if Geometry2D.is_point_in_polygon(p, rock) and R.edge_distance(p, rock) > r + 30.0:
			R.crater(mesh, p, r, rng, STRATA[0].lightened(0.04), STRATA[1].darkened(0.42), Vector2.ONE, 14)
	_boulders(mesh, rock, rng)
	R.rim(mesh, rock, Color("F6F1E6"), 3.4)
	_batch(Band.STRUCT).add_cols(mesh.pts, mesh.idx, mesh.baked(global_rotation))
	Works.build(self)
	_obstacle_lights(rock)


## Facet the rock: outline points every facet length, a jittered hex grid
## inside, heights rising from the edge to a slightly uneven plateau.
func _facet(mesh: R.Facets, rock: PackedVector2Array, rng: RandomNumberGenerator) -> void:
	var s := FACET_M * PX
	var edge := PackedVector2Array()
	for i in rock.size():
		var a := rock[i]
		var b := rock[(i + 1) % rock.size()]
		var n := maxi(1, int(ceil(a.distance_to(b) / (s * 0.8))))
		for k in n:
			edge.append(a.lerp(b, float(k) / float(n)))
	var inner := PackedVector2Array()
	var heights := PackedFloat32Array()
	var bb := A.poly_bounds(rock)
	var row := 0
	var y := bb.position.y + s * 0.4
	while y < bb.end.y:
		var x := bb.position.x + (s * 0.5 if row % 2 == 1 else 0.0)
		while x < bb.end.x:
			var p := Vector2(x, y) + Vector2(rng.randf_range(-0.33, 0.33), rng.randf_range(-0.33, 0.33)) * s
			x += s
			if not Geometry2D.is_point_in_polygon(p, rock):
				continue
			var d := R.edge_distance(p, rock)
			if d < s * 0.42:
				continue
			var k := smoothstep(0.0, RIM_M * PX, d)
			var swell := 2.2 * PX * sin(p.x / 610.0 + 1.3) * cos(p.y / 470.0)
			inner.append(p)
			heights.append(PLATEAU_M * PX * k + (rng.randf_range(-1.4, 1.4) * PX + swell) * k)
		y += s * 0.87
		row += 1
	var tone := func(c: Vector2) -> Color:
		var base: Color = STRATA[posmod(int(floor(_stratum(c))), STRATA.size())]
		var j := rng.randf_range(-0.05, 0.05)
		return base.lightened(j) if j > 0.0 else base.darkened(-j)
	R.facets(mesh, edge, inner, heights, tone, true)


## Which sedimentary band a point is in (integer part = band index).
func _stratum(p: Vector2) -> float:
	return p.dot(STRATA_DIR) / (STRATA_M * PX) + 0.55 * sin(p.dot(STRATA_DIR.orthogonal()) / 900.0)


## Thin bedding lines along the band boundaries.
func _strata_lines(mesh: R.Facets, rock: PackedVector2Array) -> void:
	var across := STRATA_DIR.orthogonal()
	for k in range(-9, 9):
		var path := PackedVector2Array()
		var u := -2600.0
		while u <= 2600.0:
			path.append(STRATA_DIR * STRATA_M * PX * (float(k) - 0.55 * sin(u / 900.0)) + across * u)
			u += 70.0
		for part in Geometry2D.intersect_polyline_with_polygon(path, rock):
			mesh.path(part, Color(0.08, 0.08, 0.12, 0.3), 1.6)
			var hi := PackedVector2Array()
			for q in part:
				hi.append(q + Vector2(1.4, 1.8))
			mesh.path(hi, Color(1.0, 0.97, 0.9, 0.1), 1.0)


## The open-cut pit: three benches stepping down, ore showing in the floor.
func _pit(mesh: R.Facets, rng: RandomNumberGenerator) -> void:
	var c := PIT.get_center() * PX
	var r := PIT.size.y * 0.5 * PX
	var squash := Vector2(PIT.size.x / PIT.size.y, 1.0)
	var wall := STRATA[2].lightened(0.06)
	for i in 3:
		var k := 1.0 - 0.27 * i
		R.crater(mesh, c + Vector2(6.0, 4.0) * PX * float(i), r * k, rng, wall.darkened(0.08 * i), STRATA[1].darkened(0.3 + 0.12 * i), squash, 13, 0.8)
	var floor_c := c + Vector2(12.0, 8.0) * PX
	for i in 4:
		var a := floor_c + Vector2(rng.randf_range(-9.0, 7.0), rng.randf_range(-4.5, 4.0)) * PX
		var b := a + Vector2.from_angle(rng.randf_range(-0.7, 0.7)) * rng.randf_range(4.0, 8.0) * PX
		var vein := R.jagged(rng, a, b, 4, 9.0)
		mesh.path(vein, Color(0.27, 0.86, 0.78, 0.3), 5.0)
		mesh.path(vein, Color("45DCC6"), 1.8)


## Loose boulders on the plateau: tiny faceted rocks with a cast shadow.
func _boulders(mesh: R.Facets, rock: PackedVector2Array, rng: RandomNumberGenerator) -> void:
	var bb := A.poly_bounds(rock)
	var placed := 0
	var tries := 0
	while placed < 26 and tries < 400:
		tries += 1
		var p := Vector2(rng.randf_range(bb.position.x, bb.end.x), rng.randf_range(bb.position.y, bb.end.y))
		if not Geometry2D.is_point_in_polygon(p, rock) or R.edge_distance(p, rock) < 70.0 or _on_works(p / PX, 4.0):
			continue
		placed += 1
		var r := rng.randf_range(1.1, 3.4) * PX
		var hull_pts := R.convex_blob(rng, r, 7)
		for i in hull_pts.size():
			hull_pts[i] += p
		var shadow := PackedVector2Array()
		for q in hull_pts:
			shadow.append(q + Vector2(0.3, 0.42) * r)
		mesh.poly(shadow, Color(0.0, 0.0, 0.02, 0.38))
		var base: Color = STRATA[rng.randi() % STRATA.size()].lightened(0.05)
		var tone := func(_c: Vector2) -> Color: return base.darkened(rng.randf_range(0.0, 0.1))
		var top := p + Vector2(rng.randf_range(-0.2, 0.2), rng.randf_range(-0.2, 0.2)) * r
		R.facets(mesh, hull_pts, PackedVector2Array([top]), PackedFloat32Array([r * 0.8]), tone)


func _on_works(p_m: Vector2, pad: float) -> bool:
	if PIT.grow(pad).has_point(p_m):
		return true
	for f: Rect2 in Works.FOOTPRINTS:
		if f.grow(pad).has_point(p_m):
			return true
	for c: Array in CRATERS:
		if p_m.distance_to(Vector2(c[0], c[1])) < float(c[2]) + pad:
			return true
	return false


## Red obstruction lights on the rock's extremities.
func _obstacle_lights(rock: PackedVector2Array) -> void:
	for k in 8:
		var dir := Vector2.from_angle(TAU * float(k) / 8.0 + 0.2)
		var best := rock[0]
		for p in rock:
			if (p - CENTRE * PX).dot(dir) > (best - CENTRE * PX).dot(dir):
				best = p
		var at := best.move_toward(CENTRE * PX, 6.0 * PX)
		fill_circle(Band.STRUCT_DETAIL, at, 0.9 * PX, Color("3A404A"), 10)
		beacon(at, A.NAV_RED, 95.0, 0.125 * k)
