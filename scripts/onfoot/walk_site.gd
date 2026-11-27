class_name WalkSite
extends Node2D
## The walkable area where you got out of a ship. Created when you step out,
## freed when you fly off (nothing on-foot exists while flying).
##
## A site is a set of walk polygons (global px) with safety railings along
## their edges (and matching invisible walls, so you can't walk off a deck
## into space), plus close-up deck detail. Where you are decides the site:
##   1. on (or in the area covered by) a docking pad -> the pad deck, plus the
##      pad's EXTRAS scene if it has one (Pad 2: airlock; Hangar Bay: stairs
##      down to the hangar floor). Extras can add walk polygons and cut gaps
##      in the pad railing (stairs, gangways).
##   2. on any other station deck (the shuttle can land anywhere on a deck)
##      -> that deck and every deck touching it, merged.
## Adding a location = one scene + one line in PAD_EXTRAS.

## pad name -> {scene, covers (Rect2, global px, optional)}. `covers` makes the
## site apply when you land anywhere inside that area, not only on the pad.
const PAD_EXTRAS := {
	"Pad 2": {"scene": "res://scenes/onfoot/sites/pad2_site.tscn"},
	"Hangar Bay": {"scene": "res://scenes/onfoot/sites/hangar_site.tscn", "covers": Rect2(5300, -4620, 1000, 740)},
}
const RAIL_INSET_M := 0.5
const GAP_TOLERANCE_PX := 10.0

## Location name for the HUD card.
var title := ""
var _walk: Array[PackedVector2Array] = []   ## all walk polygons (global px)
var _rails: Array = []                       ## [Vector2 a, Vector2 b] railing segments
var _centres: Array[Vector2] = []            ## pad centres (landing scorch rings)

## Batched painter used by the draw callback (see OnFootPainter).
var pen: OnFootPainter


# ================================================================= setup

## A docking pad (Area2D trigger; its parent is the pad module) plus extras.
func setup_pad(pad: Area2D, extras: Node) -> void:
	title = String(pad.get_meta(&"pad_name", pad.name))
	var module := pad.get_parent() as Node2D
	var xf := module.global_transform if module else pad.global_transform
	var size_m: Vector2 = module.get(&"size_m") if module and module.get(&"size_m") != null else Vector2(40, 40)
	var tail_m: float = float(module.get(&"tail_m")) if module and module.get(&"tail_m") != null else 0.0
	var px := OnFootArt.PX
	var g := RAIL_INSET_M * px
	var r := Rect2(Vector2(-size_m.x * 0.5 - tail_m, -size_m.y * 0.5) * px + Vector2(g, g),
		Vector2(size_m.x + tail_m, size_m.y) * px - Vector2(g, g) * 2.0)
	var deck := xf * OnFootArt.rect_poly(r)
	_centres.append(xf.origin)
	var gaps: Array = extras.call(&"rail_gaps") if extras and extras.has_method(&"rail_gaps") else []
	_add(deck, true, gaps)
	if extras and extras.has_method(&"walk_polys"):
		for e in extras.call(&"walk_polys"):
			_add(e.poly, bool(e.get("rail", true)), gaps)
	_finish()


## Any station deck (and the decks touching it): landing off-pad.
func setup_deck(polys: Array[PackedVector2Array], name_hint := "Station deck") -> void:
	title = name_hint
	for p in polys:
		for inset in Geometry2D.offset_polygon(p, -RAIL_INSET_M * OnFootArt.PX):
			_add(inset, true, [])
	_finish()


## Which site applies at global point `p`: {kind: "pad", pad, extras_path} /
## {kind: "deck", polys} / {} (nowhere to stand).
static func locate(tree: SceneTree, p: Vector2) -> Dictionary:
	for n in tree.get_nodes_in_group(&"docking_pad"):
		var pad := n as Area2D
		var pname := String(pad.get_meta(&"pad_name", ""))
		var cfg: Dictionary = PAD_EXTRAS.get(pname, {})
		var covered := cfg.has("covers") and (cfg.covers as Rect2).has_point(p)
		if covered or _pad_contains(pad, p):
			var scene: String = cfg.get("scene", "")
			return {"kind": "pad", "pad": pad, "extras": scene if scene != "" and ResourceLoader.exists(scene) else ""}
	var region := deck_region(p)
	if not region.is_empty():
		return {"kind": "deck", "polys": region, "title": LandingProbe._deck_name(LandingProbe._deck_at(p))}
	return {}


static func _pad_contains(pad: Area2D, p: Vector2) -> bool:
	var module := pad.get_parent() as Node2D
	if module == null or module.get(&"size_m") == null:
		return false
	var size_m: Vector2 = module.get(&"size_m")
	var tail_m: float = float(module.get(&"tail_m")) if module.get(&"tail_m") != null else 0.0
	var local := module.global_transform.affine_inverse() * p
	return Rect2(Vector2(-size_m.x * 0.5 - tail_m, -size_m.y * 0.5) * OnFootArt.PX,
		Vector2(size_m.x + tail_m, size_m.y) * OnFootArt.PX).has_point(local)


## The deck under `p` merged with every deck that overlaps it (transitively).
static func deck_region(p: Vector2) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var all: Array = LevelArt.walk_decks
	var seed := -1
	for i in all.size():
		if Geometry2D.is_point_in_polygon(p, all[i].poly):
			seed = i
			break
	if seed < 0:
		return out
	var merged: PackedVector2Array = all[seed].poly
	var used := {seed: true}
	var grew := true
	while grew:
		grew = false
		for i in all.size():
			if used.has(i):
				continue
			var other: PackedVector2Array = all[i].poly
			if Geometry2D.intersect_polygons(merged, other).is_empty():
				continue
			# The union may come back as outline + holes: keep the biggest
			# polygon that still contains p (holes are smaller and inside it).
			var best_area := -1.0
			for poly in Geometry2D.merge_polygons(merged, other):
				var area := absf(_area(poly))
				if area > best_area and Geometry2D.is_point_in_polygon(p, poly):
					best_area = area
					merged = poly
			used[i] = true
			grew = true
	out.append(merged)
	return out


static func _area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		a += poly[i].cross(poly[(i + 1) % poly.size()])
	return a * 0.5


## True if there is a deck under global point `p` (landing checks).
static func deck_under(p: Vector2) -> bool:
	for e in LevelArt.walk_decks:
		if Geometry2D.is_point_in_polygon(p, e.poly):
			return true
	return false


## Is global point `p` on this site's walkable area?
func covers(p: Vector2) -> bool:
	for poly in _walk:
		if Geometry2D.is_point_in_polygon(p, poly):
			return true
	return false


func _add(poly: PackedVector2Array, rail: bool, gaps: Array) -> void:
	_walk.append(poly)
	if not rail:
		return
	var n := poly.size()
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		for seg in _cut(a, b, gaps):
			_rails.append(seg)


## Edge a->b minus any gap segment lying along it.
func _cut(a: Vector2, b: Vector2, gaps: Array) -> Array:
	var d := b - a
	var L := d.length()
	if L < 0.01:
		return []
	d /= L
	var spans: Array = [[0.0, L]]
	for g in gaps:
		var ga: Vector2 = g[0]
		var gb: Vector2 = g[1]
		var nrm := d.orthogonal()
		if absf((ga - a).dot(nrm)) > GAP_TOLERANCE_PX or absf((gb - a).dot(nrm)) > GAP_TOLERANCE_PX:
			continue
		var t0 := minf((ga - a).dot(d), (gb - a).dot(d))
		var t1 := maxf((ga - a).dot(d), (gb - a).dot(d))
		var next: Array = []
		for sp in spans:
			if t1 <= sp[0] or t0 >= sp[1]:
				next.append(sp)
				continue
			if t0 > sp[0]:
				next.append([sp[0], t0])
			if t1 < sp[1]:
				next.append([t1, sp[1]])
		spans = next
	var out: Array = []
	for sp in spans:
		if sp[1] - sp[0] > 0.5:
			out.append([a + d * sp[0], a + d * sp[1]])
	return out


func _finish() -> void:
	z_as_relative = false
	z_index = Game.Z_BELOW_DECK + 8
	var body := StaticBody2D.new()
	body.name = "Railings"
	body.collision_layer = Game.LAYER_WALK
	body.collision_mask = 0
	for seg in _rails:
		var cs := CollisionShape2D.new()
		var ss := SegmentShape2D.new()
		ss.a = seg[0]
		ss.b = seg[1]
		cs.shape = ss
		body.add_child(cs)
	add_child(body)
	queue_redraw()


# ================================================================== art

func _draw() -> void:
	pen = OnFootPainter.new(self)
	_paint_draw()
	pen.flush()


func _paint_draw() -> void:
	for poly in _walk:
		_draw_deck_detail(poly)
	for c in _centres:
		# landing scorch: soft concentric rings around the pad centre
		for i in 6:
			pen.ring(c, 40.0 + i * 9.0, Color(0.0, 0.0, 0.02, 0.035), 7.0, 48)
	_draw_rails()


## Safety railing: an amber cable with stanchions every ~2.5 m.
func _draw_rails() -> void:
	var shadow := Vector2(0.5, 0.8)
	for seg in _rails:
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		pen.line(a + shadow, b + shadow, Color(0, 0.01, 0.03, 0.3), 0.6)
		pen.line(a, b, Color(1.0, 0.69, 0.0, 0.9), 0.35)
		pen.line(a + Vector2(-0.25, -0.25), b + Vector2(-0.25, -0.25), Color(1.0, 0.9, 0.6, 0.45), 0.12)
		var n := maxi(1, int(a.distance_to(b) / 25.0))
		for j in n + 1:
			var p := a.lerp(b, float(j) / n)
			pen.circle(p + shadow, 0.6, Color(0, 0.01, 0.03, 0.3), Color(0, 0, 0, 0), 0.1, 10)
			pen.circle(p, 0.55, Color("D9E0E7"), OnFootArt.INK, 0.12, 10)
			pen.circle(p, 0.22, Color(1.0, 0.69, 0.0), Color(0, 0, 0, 0), 0.1, 8)


## Close-up detail the flight-scale deck art doesn't need: 1.5 m plate seams,
## bolts, scuffs and stains. Subtle, so painted markings still read through.
func _draw_deck_detail(poly: PackedVector2Array) -> void:
	var bb := LevelArt.poly_bounds(poly)
	var cell := 15.0
	var seam := Color(0.0, 0.02, 0.05, 0.16)
	var hi := Color(0.6, 0.7, 0.85, 0.05)
	var x := ceilf(bb.position.x / cell) * cell
	while x < bb.end.x:
		for s in Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([Vector2(x, bb.position.y - 1), Vector2(x, bb.end.y + 1)]), poly):
			pen.line(s[0], s[s.size() - 1], seam, 0.15, false)
			pen.line(s[0] + Vector2(0.25, 0), s[s.size() - 1] + Vector2(0.25, 0), hi, 0.12, false)
		x += cell
	var y := ceilf(bb.position.y / cell) * cell
	while y < bb.end.y:
		for s in Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([Vector2(bb.position.x - 1, y), Vector2(bb.end.x + 1, y)]), poly):
			pen.line(s[0], s[s.size() - 1], seam, 0.15, false)
			pen.line(s[0] + Vector2(0, 0.25), s[s.size() - 1] + Vector2(0, 0.25), hi, 0.12, false)
		y += cell
	# bolts at every other plate corner
	x = ceilf(bb.position.x / (cell * 2.0)) * cell * 2.0
	while x < bb.end.x:
		y = ceilf(bb.position.y / (cell * 2.0)) * cell * 2.0
		while y < bb.end.y:
			if Geometry2D.is_point_in_polygon(Vector2(x, y), poly):
				for o: Vector2 in [Vector2(1, 1), Vector2(-1, -1)]:
					pen.circle(Vector2(x, y) + o * 1.1, 0.2, Color(0.55, 0.65, 0.78, 0.18), Color(0, 0, 0, 0), 0.1, 6)
			y += cell * 2.0
		x += cell * 2.0
	# scuffs and stains (seeded per polygon so they're always the same)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(bb.position.x * 13.0 + bb.position.y * 7.0)
	var count := clampi(int(bb.get_area() / 4000.0), 6, 60)
	for i in count:
		var p := Vector2(rng.randf_range(bb.position.x, bb.end.x), rng.randf_range(bb.position.y, bb.end.y))
		var a := rng.randf_range(0, TAU)
		var l := rng.randf_range(4.0, 14.0)
		var alpha := rng.randf_range(0.05, 0.12)
		var w := rng.randf_range(0.3, 1.2)
		if Geometry2D.is_point_in_polygon(p, poly):
			pen.line(p, p + Vector2.from_angle(a) * l, Color(0.0, 0.0, 0.02, alpha), w)
	for i in count / 4:
		var p := Vector2(rng.randf_range(bb.position.x, bb.end.x), rng.randf_range(bb.position.y, bb.end.y))
		var e := OnFootArt.ellipse_poly(p, rng.randf_range(3, 8), rng.randf_range(2, 5), rng.randf_range(0, PI), 14)
		if Geometry2D.is_point_in_polygon(p, poly):
			pen.fill(e, Color(0.02, 0.03, 0.05, 0.1))
