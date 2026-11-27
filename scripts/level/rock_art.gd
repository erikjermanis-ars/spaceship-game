@tool
class_name RockArt
extends RefCounted
## Faceted low-poly rock: the mesh builder behind Vesper Rock and the rocks of
## its asteroid field.
##
## A rock is an outline plus a few interior points with heights. The points
## are Delaunay-triangulated and every triangle becomes one flat facet that
## carries its 3D normal. Lighting is then a function of that normal:
##   * static rock (the outpost) bakes it into vertex colours (`Facets.baked`),
##   * tumbling rocks keep the normal in the UVs and asteroid_lit.gdshader
##     lights them in world space, so the lit side keeps facing the sun while
##     the rock turns, without ever redrawing it.
## Everything lands in ONE triangle array = one draw call per rock.

## Direction TOWARD the sun (LevelArt.LIGHT_DIR on the plane, raised 38 deg).
const LIGHT3 := Vector3(-0.468, -0.624, 0.62)
## Contrast of the facet shading. Mirrored in asteroid_lit.gdshader.
const SHADE_GAIN := 0.85
const SHADE_MIN := 0.3
const SHADE_MAX := 1.45
## UV marking a vertex as unlit (outline strokes, veins, cracks, shadows).
const UNLIT := Vector2(4.0, 0.0)
const FEATHER := 1.0


class Facets extends RefCounted:
	var pts := PackedVector2Array()
	var cols := PackedColorArray()     ## albedo
	var uvs := PackedVector2Array()    ## facet normal (xy), or UNLIT
	var idx := PackedInt32Array()

	## Flat polygon with one normal.
	func poly(p: PackedVector2Array, col: Color, n := UNLIT) -> void:
		var tri := Geometry2D.triangulate_polygon(p)
		if tri.is_empty():
			return
		var base := pts.size()
		pts.append_array(p)
		for i in p.size():
			cols.append(col)
			uvs.append(n)
		for t in tri:
			idx.append(base + t)

	## Antialiased line segment (solid core, 1 px alpha feather each side).
	func seg(a: Vector2, b: Vector2, col: Color, width: float, n := UNLIT) -> void:
		var d := b - a
		var l := d.length()
		if l < 0.001:
			return
		d /= l
		var hw := maxf(width, 1.0) * 0.5
		a -= d * hw
		b += d * hw
		var o := d.orthogonal()
		var f := hw + FEATHER
		var clear := Color(col, 0.0)
		var base := pts.size()
		pts.append_array(PackedVector2Array([a - o * f, b - o * f, b - o * hw, a - o * hw, a + o * hw, b + o * hw, b + o * f, a + o * f]))
		cols.append_array(PackedColorArray([clear, clear, col, col, col, col, clear, clear]))
		for i in 8:
			uvs.append(n)
		for t: int in [0, 1, 2, 0, 2, 3, 3, 2, 5, 3, 5, 4, 4, 5, 6, 4, 6, 7]:
			idx.append(base + t)

	func path(p: PackedVector2Array, col: Color, width: float, closed := false) -> void:
		var n := p.size() if closed else p.size() - 1
		for i in n:
			seg(p[i], p[(i + 1) % p.size()], col, width)

	func append(o: Facets) -> void:
		var base := pts.size()
		pts.append_array(o.pts)
		cols.append_array(o.cols)
		uvs.append_array(o.uvs)
		for t in o.idx:
			idx.append(base + t)

	## Vertex colours with the lighting baked in, for a mesh that never turns
	## (`rot` = its global rotation).
	func baked(rot := 0.0) -> PackedColorArray:
		var out := PackedColorArray()
		out.resize(cols.size())
		for i in cols.size():
			var k := RockArt.shade(uvs[i], rot)
			var c := cols[i]
			out[i] = Color(minf(c.r * k, 1.0), minf(c.g * k, 1.0), minf(c.b * k, 1.0), c.a)
		return out


## Brightness factor of a facet with normal `n` (xy; z is implied). 1.0 = a
## flat top, so albedo colours are the colours of level ground.
static func shade(n: Vector2, rot := 0.0) -> float:
	if n.x > 3.0:
		return 1.0
	var nz := sqrt(maxf(0.0, 1.0 - n.length_squared()))
	var w := n.rotated(rot)
	var k := Vector3(w.x, w.y, nz).dot(LIGHT3)
	return clampf(1.0 + (k - LIGHT3.z) * SHADE_GAIN, SHADE_MIN, SHADE_MAX)


## Irregular closed outline around the origin (px): a superellipse (`power` >
## 2 = blockier) roughened by a few harmonics and per-vertex jitter.
static func blob(rng: RandomNumberGenerator, rx: float, ry: float, n: int, rough: float, power := 2.0) -> PackedVector2Array:
	var ph := [rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU]
	var out := PackedVector2Array()
	for i in n:
		var a := TAU * (float(i) + rng.randf_range(-0.3, 0.3)) / float(n)
		var c := cos(a)
		var s := sin(a)
		var r := pow(pow(absf(c), power) + pow(absf(s), power), -1.0 / power)
		var k := 1.0 + rough * (0.5 * sin(a * 2.0 + ph[0]) + 0.3 * sin(a * 3.0 + ph[1]) + 0.2 * sin(a * 5.0 + ph[2]))
		k += rough * rng.randf_range(-0.35, 0.35)
		out.append(Vector2(c * rx, s * ry) * r * k)
	return out


## Convex version of `blob`, recentred on its centroid (a field rock: the
## outline is also its collision shape and its centre of mass is the origin).
static func convex_blob(rng: RandomNumberGenerator, radius: float, n: int, rough := 0.24) -> PackedVector2Array:
	var hull := Geometry2D.convex_hull(blob(rng, radius, radius * rng.randf_range(0.72, 1.0), n, rough))
	hull.remove_at(hull.size() - 1)     # convex_hull closes the loop
	var c := centroid(hull)
	for i in hull.size():
		hull[i] -= c
	return hull


static func centroid(p: PackedVector2Array) -> Vector2:
	var a := 0.0
	var c := Vector2.ZERO
	for i in p.size():
		var q := p[(i + 1) % p.size()]
		var x := p[i].cross(q)
		a += x
		c += (p[i] + q) * x
	return c / (3.0 * a) if absf(a) > 0.001 else Vector2.ZERO


static func area(p: PackedVector2Array) -> float:
	var a := 0.0
	for i in p.size():
		a += p[i].cross(p[(i + 1) % p.size()])
	return absf(a) * 0.5


## Distance from `p` to the nearest edge of `poly`.
static func edge_distance(p: Vector2, poly: PackedVector2Array) -> float:
	var best := INF
	for i in poly.size():
		var q := Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()])
		best = minf(best, p.distance_squared_to(q))
	return sqrt(best)


## Facets `outline` (height 0 along it) with interior points `inner` at
## `heights` (px). `tone` maps a facet centre to its albedo. With `clip`,
## triangles touching the outline are cut to it (needed for concave outlines,
## where Delaunay triangles span the bays).
static func facets(mesh: Facets, outline: PackedVector2Array, inner: PackedVector2Array, heights: PackedFloat32Array, tone: Callable, clip := false) -> void:
	var nb := outline.size()
	var pts := outline.duplicate()
	pts.append_array(inner)
	var tris := Geometry2D.triangulate_delaunay(pts)
	for t in range(0, tris.size(), 3):
		var ia := tris[t]
		var ib := tris[t + 1]
		var ic := tris[t + 2]
		var a := pts[ia]
		var b := pts[ib]
		var c := pts[ic]
		var ha := 0.0 if ia < nb else heights[ia - nb]
		var hb := 0.0 if ib < nb else heights[ib - nb]
		var hc := 0.0 if ic < nb else heights[ic - nb]
		var n3 := Vector3(b.x - a.x, b.y - a.y, hb - ha).cross(Vector3(c.x - a.x, c.y - a.y, hc - ha)).normalized()
		if n3.z < 0.0:
			n3 = -n3
		var n := Vector2(n3.x, n3.y)
		var cen := (a + b + c) / 3.0
		var tri := PackedVector2Array([a, b, c])
		if clip and (ia < nb or ib < nb or ic < nb):
			for piece in Geometry2D.intersect_polygons(tri, outline):
				mesh.poly(piece, tone.call(cen), n)
		elif not clip or Geometry2D.is_point_in_polygon(cen, outline):
			mesh.poly(tri, tone.call(cen), n)


## A bowl: inward-facing wall facets around a darker floor, plus a thin lip.
## The wall away from the sun catches the light, the near wall is in shadow.
static func crater(mesh: Facets, c: Vector2, r: float, rng: RandomNumberGenerator, wall: Color, bed: Color, squash := Vector2.ONE, n := 12, depth := 0.72) -> void:
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	var a0 := rng.randf() * TAU
	for i in n:
		var a := a0 + TAU * float(i) / float(n)
		var d := Vector2(cos(a), sin(a)) * squash
		outer.append(c + d * r * rng.randf_range(0.92, 1.08))
		inner.append(c + d * r * rng.randf_range(0.5, 0.62))
	for i in n:
		var j := (i + 1) % n
		var mid := ((outer[i] + outer[j]) * 0.5 - c).normalized()
		mesh.poly(PackedVector2Array([outer[i], outer[j], inner[j], inner[i]]), wall, -mid * depth)
		mesh.seg(outer[i], outer[j], wall.lightened(0.12), 1.2, mid * 0.6)
	mesh.poly(inner, bed, Vector2.ZERO)


## Dark outline stroke under the facets (half of it shows outside the edge).
static func stroke(mesh: Facets, outline: PackedVector2Array, width := 5.0) -> void:
	for i in outline.size():
		mesh.seg(outline[i], outline[(i + 1) % outline.size()], Color(0.03, 0.05, 0.09, 0.92), width)


## The lit rim: every colliding thing has a bright edge on its sunward side
## (CONTRACT §6). Each edge carries its outward normal, so it is lit like a
## facet standing on end.
static func rim(mesh: Facets, outline: PackedVector2Array, lit: Color, width := 2.2) -> void:
	var n := outline.size()
	var cw := Geometry2D.is_polygon_clockwise(outline)
	for i in n:
		var a := outline[i]
		var b := outline[(i + 1) % n]
		var d := b - a
		if d.length_squared() < 0.01:
			continue
		var nrm := Vector2(d.y, -d.x).normalized()
		if cw:
			nrm = -nrm
		mesh.seg(a, b, lit, width, nrm)


## Jagged line from `a` to `b` (veins, cracks): `amp` px of sideways wander.
static func jagged(rng: RandomNumberGenerator, a: Vector2, b: Vector2, steps: int, amp: float) -> PackedVector2Array:
	var out := PackedVector2Array([a])
	var side := (b - a).orthogonal().normalized()
	for i in range(1, steps):
		out.append(a.lerp(b, float(i) / float(steps)) + side * rng.randf_range(-amp, amp))
	out.append(b)
	return out
