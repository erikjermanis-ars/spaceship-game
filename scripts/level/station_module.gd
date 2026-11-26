@tool
class_name StationModule
extends Node2D
## Base class of the procedural "station kit".
##
## A module describes itself ONCE in `_build()` by calling painter helpers
## (`hull()`, `deck()`, `truss()`, `windows()`, `beacon()` ...). Those calls
## record draw operations into depth bands AND collect the collision geometry,
## so visuals and physics come from the same source of truth.
##
## `_realize()` then creates:
##   * one StaticBody2D / AnimatableBody2D (`body`) with convex CollisionPolygon2D
##     pieces (layer LAYER_WORLD by default),
##   * one cached canvas item per used depth band (absolute z-index), replayed
##     only when the module is rebuilt -> no per-frame drawing cost,
##   * a debug outline item toggled by Game.debug_draw.
## Moving modules (ring, crane, doors) set `moving = true` and transform
## `body` in `_physics_process` -- all visuals are children of the body.

enum Band {
	DECK, DECK_SHADOW, DECK_FX, DECK_BLINK,
	STRUCT, STRUCT_DETAIL, STRUCT_FX, STRUCT_BLINK,
	OVER_SHADOW, OVER, OVER_FX, OVER_BLINK,
	DEBUG,
}

const G := preload("res://scripts/autoload/game.gd")
const A := preload("res://scripts/level/level_art.gd")
const PX := 10.0

# Per band: [z, depth kind (0 deck, 1 struct, 2 overhead), material (0 none, 1 add, 2 blink), shadow kind (0 none, 1 hull, 2 overhead)]
const BAND_SPEC := [
	[G.Z_BELOW_DECK, 0, 0, 0],
	[G.Z_BELOW_DECK + 1, 0, 0, 1],
	[G.Z_BELOW_DECK + 2, 0, 1, 0],
	[G.Z_BELOW_DECK + 3, 0, 2, 0],
	[G.Z_STRUCTURE, 1, 0, 0],
	[G.Z_STRUCTURE + 1, 1, 0, 0],
	[G.Z_STRUCTURE + 2, 1, 1, 0],
	[G.Z_STRUCTURE + 3, 1, 2, 0],
	[G.Z_OVERHEAD - 1, 1, 0, 2],
	[G.Z_OVERHEAD, 2, 0, 0],
	[G.Z_OVERHEAD_FX, 2, 1, 0],
	[G.Z_OVERHEAD_FX + 1, 2, 2, 0],
	[G.Z_OVERHEAD_FX + 5, 1, 0, 0],
]

## Groups of draw ops that can be merged into one triangle array.
class TriBatch:
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()

	func add(p: PackedVector2Array, tri: PackedInt32Array, c: Color) -> void:
		var base := pts.size()
		pts.append_array(p)
		var n := p.size()
		var start := cols.size()
		cols.resize(start + n)
		for i in n:
			cols[start + i] = c
		for t in tri:
			idx.append(base + t)

	func add_cols(p: PackedVector2Array, tri: PackedInt32Array, c: PackedColorArray) -> void:
		var base := pts.size()
		pts.append_array(p)
		cols.append_array(c)
		for t in tri:
			idx.append(base + t)

## Make the module an AnimatableBody2D the subclass moves itself.
var moving := false
## Physics layer bits for the body (structures are LAYER_WORLD).
var body_layer := G.LAYER_WORLD
## Absolute z of the STRUCT band (+1 detail, +2 fx, +3 blink). Traffic uses Z_PROPS.
var struct_z := G.Z_STRUCTURE
## Join the radar_structure group (when it has solids).
var on_radar := true
## Collision physics material (bouncy-ish metal by default).
var bounce := 0.3

var body: CollisionObject2D
## Visible solid outlines (local px) - radar + debug.
var solids: Array[PackedVector2Array] = []
## Convex collision pieces (local px).
var pieces: Array[PackedVector2Array] = []
## Optional simplified radar outlines; falls back to `solids`.
var radar_polys: Array[PackedVector2Array] = []

var _ops: Array = []
var _open: Array = []
var _generated: Array[Node] = []
var _band_nodes: Array = []
var _rebuild_queued := false


func _ready() -> void:
	rebuild()


func _exit_tree() -> void:
	_unregister_depth()


## Re-runs _build() and recreates generated children. Cheap enough to call
## from export setters in the editor.
func rebuild() -> void:
	_rebuild_queued = false
	_clear()
	_build()
	_realize()
	_after_build()


func queue_rebuild() -> void:
	if not is_inside_tree() or _rebuild_queued:
		return
	_rebuild_queued = true
	rebuild.call_deferred()


## Override: record geometry with the painter helpers.
func _build() -> void:
	pass


## Override (moving modules): local transform of `body` at spawn.
func _initial_body_transform() -> Transform2D:
	return Transform2D.IDENTITY


## Override: runs after nodes exist (attach audio, timers ...).
func _after_build() -> void:
	pass


func get_radar_polygons() -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var src := radar_polys if not radar_polys.is_empty() else solids
	var xf := (body as Node2D).global_transform if body else global_transform
	for p in src:
		out.append(xf * p)
	return out

# ===================================================================== core

func _clear() -> void:
	_unregister_depth()
	for n in _generated:
		if is_instance_valid(n):
			n.get_parent().remove_child(n)
			n.queue_free()
	_generated.clear()
	_band_nodes.clear()
	solids.clear()
	pieces.clear()
	radar_polys.clear()
	_ops.clear()
	_open.clear()
	for i in Band.size():
		_ops.append([])
		_open.append(null)
	body = null


func _realize() -> void:
	var visual_parent: Node2D = self
	if not pieces.is_empty() or moving:
		if moving:
			var ab := AnimatableBody2D.new()
			ab.sync_to_physics = true
			body = ab
		else:
			body = StaticBody2D.new()
		body.name = "Body"
		body.collision_layer = body_layer
		body.collision_mask = 0
		var mat := PhysicsMaterial.new()
		mat.bounce = bounce
		mat.friction = 0.25
		if body is StaticBody2D:
			(body as StaticBody2D).physics_material_override = mat
		elif body is AnimatableBody2D:
			(body as AnimatableBody2D).physics_material_override = mat
		for p in pieces:
			var cp := CollisionPolygon2D.new()
			cp.build_mode = CollisionPolygon2D.BUILD_SOLIDS
			cp.polygon = p
			body.add_child(cp)
		# Moving bodies start where they will be on their first physics step,
		# otherwise the first sync reads as a huge kinematic velocity.
		if moving:
			body.transform = _initial_body_transform()
		add_child(body)
		_generated.append(body)
		visual_parent = body
		if on_radar and not solids.is_empty():
			add_to_group(&"radar_structure")
	# Debug outlines of the collision pieces.
	if not pieces.is_empty():
		for p in pieces:
			var closed := p.duplicate()
			closed.append(p[0])
			_op(Band.DEBUG, &"draw_polyline", [closed, Color(1.0, 0.2, 0.8, 0.95), 2.0, true])
	for b in Band.size():
		_band_nodes.append(null)
		if (_ops[b] as Array).is_empty():
			continue
		var spec: Array = BAND_SPEC[b]
		if spec[2] != 0:
			# Additive light is order independent: pull all glow sprites to the
			# front so the renderer batches them; everything else keeps its
			# order (text relies on draw_set_transform sequences).
			var sprites: Array = []
			var rest: Array = []
			for op in _ops[b]:
				if not (op is TriBatch) and op[0] == &"draw_texture_rect":
					sprites.append(op)
				else:
					rest.append(op)
			_ops[b] = sprites + rest
		var ci := Node2D.new()
		ci.name = "Band_%s" % Band.keys()[b]
		ci.z_as_relative = false
		var z: int = spec[0]
		if b >= Band.STRUCT and b <= Band.STRUCT_BLINK:
			z = struct_z + (b - Band.STRUCT)
		ci.z_index = z
		match spec[2]:
			1: ci.material = A.add_material()
			2: ci.material = A.blink_material()
		ci.draw.connect(_replay.bind(b, ci))
		visual_parent.add_child(ci)
		_generated.append(ci)
		_band_nodes[b] = ci
		if b == Band.DEBUG:
			ci.visible = false
	_register_depth()
	if not Engine.is_editor_hint():
		var game := _game()
		if game and _band_nodes[Band.DEBUG] != null:
			(_band_nodes[Band.DEBUG] as Node2D).visible = game.debug_draw
			if not game.debug_draw_changed.is_connected(_on_debug_draw):
				game.debug_draw_changed.connect(_on_debug_draw)


func _on_debug_draw(enabled: bool) -> void:
	if _band_nodes.size() > Band.DEBUG and _band_nodes[Band.DEBUG] != null:
		(_band_nodes[Band.DEBUG] as Node2D).visible = enabled


func _game() -> Node:
	return get_node_or_null(^"/root/Game")


func _replay(b: int, ci: Node2D) -> void:
	var rid := ci.get_canvas_item()
	for op in _ops[b]:
		if op is TriBatch:
			var tb: TriBatch = op
			if not tb.idx.is_empty():
				RenderingServer.canvas_item_add_triangle_array(rid, tb.idx, tb.pts, tb.cols)
		else:
			ci.callv(op[0], op[1])


func _register_depth() -> void:
	if Engine.is_editor_hint():
		return
	for b in _band_nodes.size():
		var ci: Node2D = _band_nodes[b]
		if ci == null:
			continue
		var spec: Array = BAND_SPEC[b]
		var s := 1.0
		match spec[1]:
			0: s = A.DECK_SCALE
			2: s = A.OVER_SCALE
		var off := Vector2.ZERO
		match spec[3]:
			1: off = A.HULL_SHADOW_OFFSET
			2: off = A.OVER_SHADOW_OFFSET
		if s == 1.0 and off == Vector2.ZERO:
			continue
		A.depth_layers.append([ci, s, off])


func _unregister_depth() -> void:
	if _band_nodes.is_empty():
		return
	var mine := {}
	for ci in _band_nodes:
		if ci != null:
			mine[ci] = true
	var keep: Array = []
	for e in A.depth_layers:
		if not mine.has(e[0]) and is_instance_valid(e[0]):
			keep.append(e)
	A.depth_layers.clear()
	A.depth_layers.append_array(keep)

# ============================================================ painter API
# All coordinates are LOCAL pixels (use `m()` / LevelArt.rect_m for metres).

static func m(x: float, y: float) -> Vector2:
	return Vector2(x, y) * PX


func _op(b: int, method: StringName, args: Array) -> void:
	_open[b] = null
	(_ops[b] as Array).append([method, args])


func _batch(b: int) -> TriBatch:
	var tb: TriBatch = _open[b]
	if tb == null:
		tb = TriBatch.new()
		(_ops[b] as Array).append(tb)
		_open[b] = tb
	return tb


## Flat filled polygon (batched into one triangle array per band run).
func fill(b: int, poly: PackedVector2Array, color: Color) -> void:
	if poly.size() < 3:
		return
	var tri := Geometry2D.triangulate_polygon(poly)
	if tri.is_empty():
		var d := Geometry2D.decompose_polygon_in_convex(poly)
		for piece in d:
			var t2 := Geometry2D.triangulate_polygon(piece)
			if not t2.is_empty():
				_batch(b).add(piece, t2, color)
		return
	_batch(b).add(poly, tri, color)


func fill_rect(b: int, r: Rect2, color: Color) -> void:
	_batch(b).add(A.rect_poly(r), PackedInt32Array([0, 1, 2, 0, 2, 3]), color)


func fill_circle(b: int, c: Vector2, r: float, color: Color, n := 0) -> void:
	if n <= 0:
		n = clampi(int(r / 3.0), 10, 48)
	fill(b, A.circle_poly(c, r, n), color)


func outline(b: int, poly: PackedVector2Array, color: Color, width := 2.0, closed := true, aa := true) -> void:
	if poly.size() < 2:
		return
	if not aa:
		# Cheap variant: edges as quads merged into the band's triangle batch
		# (use for hundreds of tiny outlines, e.g. container cells).
		var n := poly.size() if closed else poly.size() - 1
		var hw := width * 0.5
		for i in n:
			var a := poly[i]
			var c := poly[(i + 1) % poly.size()]
			var d := (c - a).normalized()
			var nn := d.orthogonal() * hw
			a -= d * hw
			c += d * hw
			_batch(b).add(PackedVector2Array([a - nn, c - nn, c + nn, a + nn]), PackedInt32Array([0, 1, 2, 0, 2, 3]), color)
		return
	var p := poly
	if closed:
		p = poly.duplicate()
		p.append(poly[0])
	_aa_polyline(b, p, color, width)


func line(b: int, a: Vector2, c: Vector2, color: Color, width := 2.0) -> void:
	_aa_segment(b, a, c, color, width)


## Many independent segments (pairs of points).
func lines(b: int, pairs: PackedVector2Array, color: Color, width := 2.0) -> void:
	if pairs.size() < 2:
		return
	for i in range(0, pairs.size() - 1, 2):
		_aa_segment(b, pairs[i], pairs[i + 1], color, width)


func polyline(b: int, pts: PackedVector2Array, color: Color, width := 2.0) -> void:
	if pts.size() < 2:
		return
	_aa_polyline(b, pts, color, width)


# Antialiased lines are pre-tessellated into the band's merged triangle array
# (a solid core plus a 1-unit alpha feather on each side). Godot turns every
# segment of a wide/antialiased draw_multiline/draw_polyline into its own
# canvas command, re-submitted every frame; the station has ~10k static
# segments, which cost ~30 fps. Baked quads cost one command per band.
const _FEATHER := 1.0
const _SEG_TRI := [0, 1, 2, 0, 2, 3, 3, 2, 5, 3, 5, 4, 4, 5, 6, 4, 6, 7]

func _aa_polyline(b: int, pts: PackedVector2Array, color: Color, width: float) -> void:
	for i in pts.size() - 1:
		_aa_segment(b, pts[i], pts[i + 1], color, width)


func _aa_segment(b: int, a: Vector2, c: Vector2, color: Color, width: float) -> void:
	var d := c - a
	var l := d.length()
	if l < 0.001:
		return
	d /= l
	var hw := maxf(width, 1.0) * 0.5
	# Square caps close the joints between consecutive segments. In additive
	# bands the overlap would show as bright dots, so those keep butt ends.
	if BAND_SPEC[b][2] != 1:
		a -= d * hw
		c += d * hw
	var n := d.orthogonal()
	var o := hw + _FEATHER
	var clear := Color(color, 0.0)
	_batch(b).add_cols(
		PackedVector2Array([a - n * o, c - n * o, c - n * hw, a - n * hw, a + n * hw, c + n * hw, c + n * o, a + n * o]),
		PackedInt32Array(_SEG_TRI),
		PackedColorArray([clear, clear, color, color, color, color, clear, clear]))


func arc(b: int, c: Vector2, r: float, a0: float, a1: float, color: Color, width := 2.0, n := 32) -> void:
	_op(b, &"draw_arc", [c, r, a0, a1, n, color, width, true])


func text(b: int, pos: Vector2, s: String, size_px: int, color: Color, rot := 0.0, bold := true) -> void:
	var f := A.font() if bold else A.font_regular()
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	var asc := f.get_ascent(size_px)
	var desc := f.get_descent(size_px)
	_op(b, &"draw_set_transform", [pos, rot, Vector2.ONE])
	_op(b, &"draw_string", [f, Vector2(-w * 0.5, (asc - desc) * 0.5), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color])
	_op(b, &"draw_set_transform", [Vector2.ZERO, 0.0, Vector2.ONE])


## Text laid out along a circular arc (characters upright to the tangent).
func arc_text(b: int, c: Vector2, r: float, mid_angle: float, s: String, size_px: int, color: Color, tracking := 1.15) -> void:
	var f := A.font()
	var total := 0.0
	var widths: Array[float] = []
	for ch in s:
		var w := f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x * tracking
		widths.append(w)
		total += w
	var ang := mid_angle - (total * 0.5) / r
	var asc := f.get_ascent(size_px)
	var desc := f.get_descent(size_px)
	for i in s.length():
		var w := widths[i]
		var a := ang + (w * 0.5) / r
		var p := c + Vector2(cos(a), sin(a)) * r
		_op(b, &"draw_set_transform", [p, a + PI * 0.5, Vector2.ONE])
		_op(b, &"draw_string", [f, Vector2(-w * 0.5 / tracking, (asc - desc) * 0.5), s[i], HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color])
		ang += w / r
	_op(b, &"draw_set_transform", [Vector2.ZERO, 0.0, Vector2.ONE])


## Additive soft glow sprite.
func glow(pos: Vector2, color: Color, radius: float, b := Band.STRUCT_FX) -> void:
	_op(b, &"draw_texture_rect", [A.glow_texture(), Rect2(pos - Vector2(radius, radius), Vector2(radius, radius) * 2.0), false, color])


## Small physical lamp: bright core dot + additive halo.
func lamp(pos: Vector2, color: Color, radius := 28.0, level := 1) -> void:
	var core_b: int = [Band.DECK, Band.STRUCT_DETAIL, Band.OVER][level]
	var fx_b: int = [Band.DECK_FX, Band.STRUCT_FX, Band.OVER_FX][level]
	fill_circle(core_b, pos, maxf(radius * 0.09, 2.2), color.lerp(Color.WHITE, 0.55), 10)
	glow(pos, Color(color.r, color.g, color.b, 0.85), radius, fx_b)


## Blinking navigation light (animated by beacon_blink.gdshader).
func beacon(pos: Vector2, color: Color, radius := 60.0, phase := 0.0, strobe := false, level := 1) -> void:
	var core_b: int = [Band.DECK, Band.STRUCT_DETAIL, Band.OVER][level]
	var blink_b: int = [Band.DECK_BLINK, Band.STRUCT_BLINK, Band.OVER_BLINK][level]
	fill_circle(core_b, pos, 3.2, color.lerp(Color.WHITE, 0.3).darkened(0.25), 10)
	_op(blink_b, &"draw_texture_rect", [A.glow_texture(), Rect2(pos - Vector2(radius, radius), Vector2(radius, radius) * 2.0), false, A.blink_color(color, phase, strobe)])


## Colliding, visible structure. `poly` is the visual outline; `convex` are the
## collision pieces (auto convex-decomposed from `poly` when empty).
## opts: lit (bool, directional rim), shadow (bool), bevel (m), collide (bool)
func hull(poly: PackedVector2Array, style: StringName = &"pearl", convex: Array = [], opts := {}) -> void:
	if poly.size() < 3:
		return
	var st: Dictionary = A.STYLES.get(style, A.STYLES[&"pearl"])
	var collide: bool = opts.get("collide", true)
	if collide:
		solids.append(poly)
		if convex.is_empty():
			for piece in Geometry2D.decompose_polygon_in_convex(poly):
				pieces.append(piece)
		else:
			for piece in convex:
				pieces.append(piece)
	if opts.get("shadow", true):
		fill(Band.DECK_SHADOW, poly, A.HULL_SHADOW)
	var closed := poly.duplicate()
	closed.append(poly[0])
	_aa_polyline(Band.STRUCT, closed, A.OUTLINE, 5.0)
	fill(Band.STRUCT, poly, st.edge)
	var bevel: float = opts.get("bevel", st.bevel) * PX
	if bevel > 0.5:
		var cw := Geometry2D.is_polygon_clockwise(poly)
		for inner in Geometry2D.offset_polygon(poly, -bevel, Geometry2D.JOIN_MITER):
			if Geometry2D.is_polygon_clockwise(inner) == cw:
				fill(Band.STRUCT, inner, st.fill)
	rim(Band.STRUCT, poly, st.rim, st.shade, opts.get("lit", true), opts.get("rim_width", 2.2))


## Edge highlight: each edge gets a colour by how much it faces the light.
func rim(b: int, poly: PackedVector2Array, lit_col: Color, shade_col: Color, directional := true, width := 2.2) -> void:
	var n := poly.size()
	var pairs := PackedVector2Array()
	var cols := PackedColorArray()
	var cw := Geometry2D.is_polygon_clockwise(poly)
	var light := A.LIGHT_DIR.normalized()
	for i in n:
		var a := poly[i]
		var c := poly[(i + 1) % n]
		var d := c - a
		if d.length_squared() < 0.01:
			continue
		var nrm := Vector2(d.y, -d.x).normalized()
		if cw:
			nrm = -nrm
		var k := 1.0
		if directional:
			k = clampf(nrm.dot(light) * 0.5 + 0.5, 0.0, 1.0)
			k = smoothstep(0.15, 0.85, k)
		else:
			k = 0.8
		pairs.append(a)
		pairs.append(c)
		cols.append(shade_col.lerp(lit_col, k))
	for i in cols.size():
		_aa_segment(b, pairs[i * 2], pairs[i * 2 + 1], cols[i], width)


## Invisible collision (e.g. custom-drawn props that already paint themselves).
func collider(poly: PackedVector2Array, visible_on_radar := true) -> void:
	for piece in Geometry2D.decompose_polygon_in_convex(poly):
		pieces.append(piece)
	if visible_on_radar:
		solids.append(poly)


## Non-colliding below-deck floor (the ship flies over it).
func deck(poly: PackedVector2Array, grid_m := 6.0, base := Color("1E2836"), plate := Color("273345"), grid := Color("324257"), edge := Color("53667F")) -> void:
	fill(Band.DECK, poly, base)
	var inner_polys := Geometry2D.offset_polygon(poly, -0.7 * PX)
	for inner in inner_polys:
		fill(Band.DECK, inner, plate)
	if grid_m > 0.0 and not inner_polys.is_empty():
		var inner: PackedVector2Array = inner_polys[0]
		var bb := A.poly_bounds(inner)
		var step := grid_m * PX
		var pairs := PackedVector2Array()
		var x := ceilf(bb.position.x / step) * step
		while x < bb.end.x:
			for seg in Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([Vector2(x, bb.position.y - 1), Vector2(x, bb.end.y + 1)]), inner):
				if seg.size() >= 2:
					pairs.append(seg[0])
					pairs.append(seg[seg.size() - 1])
			x += step
		var y := ceilf(bb.position.y / step) * step
		while y < bb.end.y:
			for seg in Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([Vector2(bb.position.x - 1, y), Vector2(bb.end.x + 1, y)]), inner):
				if seg.size() >= 2:
					pairs.append(seg[0])
					pairs.append(seg[seg.size() - 1])
			y += step
		lines(Band.DECK, pairs, grid, 1.5)
	outline(Band.DECK, poly, edge, 2.0)


## Amber/black diagonal hazard stripes filling `poly` on band `b`.
func hazard(b: int, poly: PackedVector2Array, stripe_m := 1.6, angle := PI * 0.25, col := A.AMBER) -> void:
	fill(b, poly, col)
	var bb := A.poly_bounds(poly)
	var dir := Vector2(cos(angle), sin(angle))
	var nrm := dir.orthogonal()
	var w := stripe_m * PX
	var diag := bb.size.length()
	var c := bb.get_center()
	var k := -diag
	while k < diag:
		var o := c + nrm * k
		var stripe := PackedVector2Array([o - dir * diag, o + dir * diag, o + dir * diag + nrm * w, o - dir * diag + nrm * w])
		for piece in Geometry2D.intersect_polygons(stripe, poly):
			fill(b, piece, A.STRIPE_DARK)
		k += w * 2.0
	outline(b, poly, Color(0, 0, 0, 0.5), 1.5)


## Warm window strip along a polyline. `width_m` strip width, `cell_m`
## window length. Cells are laid out continuously along the whole polyline
## (so curved strips stay regular) and lit in "rooms" of a few cells.
func windows(b: int, pts: PackedVector2Array, width_m := 2.0, cell_m := 1.6, seed := 0, warm := A.WARM, glow_alpha := 0.13) -> void:
	if pts.size() < 2:
		return
	var w := width_m * PX
	_strip(b, pts, w, Color("18202D"))
	var cum := PackedFloat32Array([0.0])
	for i in range(1, pts.size()):
		cum.append(cum[i - 1] + pts[i].distance_to(pts[i - 1]))
	var total := cum[cum.size() - 1]
	var cell := maxf(cell_m * 1.35, 1.2) * PX
	var gap := 0.2 * PX
	var hw := w * 0.5 - 0.28 * PX
	var palette := [warm, warm.lerp(Color("FFC870"), 0.6), warm.lerp(Color.WHITE, 0.45), warm.darkened(0.3)]
	var t := gap
	var idx := 0
	var seg := 0
	while t + cell <= total:
		var room := A.hash01(idx / 3, seed)
		var col: Color = palette[int(room * 3.99)]
		if room < 0.1:
			col = Color("2B3547")          # unlit room
		elif room > 0.97:
			col = A.CYAN.lerp(Color.WHITE, 0.35)
		col = col.darkened(0.12 * A.hash01(idx, seed + 7))
		var p0 := _along(pts, cum, t)
		var p1 := _along(pts, cum, t + cell)
		var d := (p1 - p0).normalized()
		var nrm := d.orthogonal() * hw
		_batch(b).add(PackedVector2Array([p0 - nrm, p1 - nrm, p1 + nrm, p0 + nrm]), PackedInt32Array([0, 1, 2, 0, 2, 3]), col)
		t += cell + gap
		idx += 1
	if glow_alpha > 0.0:
		var fx: int = Band.OVER_FX
		if b < Band.STRUCT:
			fx = Band.DECK_FX
		elif b <= Band.STRUCT_BLINK:
			fx = Band.STRUCT_FX
		_aa_polyline(fx, pts, Color(warm.r, warm.g, warm.b * 0.8, glow_alpha), w * 3.2)


static func _along(pts: PackedVector2Array, cum: PackedFloat32Array, d: float) -> Vector2:
	var lo := 0
	var hi := cum.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if cum[mid] <= d:
			lo = mid
		else:
			hi = mid
	var L := cum[hi] - cum[lo]
	return pts[lo] if L <= 0.0 else pts[lo].lerp(pts[hi], (d - cum[lo]) / L)


## Constant-width quad strip along a polyline (batched).
func _strip(b: int, pts: PackedVector2Array, w: float, color: Color) -> void:
	for i in pts.size() - 1:
		var a := pts[i]
		var c := pts[i + 1]
		var d := (c - a).normalized()
		var nrm := d.orthogonal() * w * 0.5
		# extend a bit so consecutive quads overlap on curves
		var e := d * minf(w * 0.15, 3.0)
		_batch(b).add(PackedVector2Array([a - e - nrm, c + e - nrm, c + e + nrm, a - e + nrm]), PackedInt32Array([0, 1, 2, 0, 2, 3]), color)


func strip(b: int, pts: PackedVector2Array, width_px: float, color: Color) -> void:
	_strip(b, pts, width_px, color)


## Overhead lattice truss from a to b (non-colliding, casts a shadow).
func truss(a: Vector2, b: Vector2, width_m := 6.0, color := Color(0.86, 0.9, 0.95, 0.55), lights := true) -> void:
	var w := width_m * PX
	var d := (b - a)
	var L := d.length()
	if L < 1.0:
		return
	var dir := d / L
	var nrm := dir.orthogonal() * w * 0.5
	var box := PackedVector2Array([a - nrm, b - nrm, b + nrm, a + nrm])
	# An open lattice casts a faint box, darker under the two chords.
	fill(Band.OVER_SHADOW, box, Color(A.OVER_SHADOW, 0.1))
	line(Band.OVER_SHADOW, a - nrm, b - nrm, A.OVER_SHADOW, 6.0)
	line(Band.OVER_SHADOW, a + nrm, b + nrm, A.OVER_SHADOW, 6.0)
	fill(Band.OVER, box, Color(0.55, 0.62, 0.72, 0.16))
	var pairs := PackedVector2Array()
	pairs.append_array([a - nrm, b - nrm, a + nrm, b + nrm])
	var bay := w
	var n := maxi(1, int(L / bay))
	for i in n:
		var t0 := float(i) / n
		var t1 := float(i + 1) / n
		var p0 := a + d * t0
		var p1 := a + d * t1
		pairs.append_array([p0 - nrm, p1 + nrm, p0 - nrm, p0 + nrm])
	pairs.append_array([b - nrm, b + nrm])
	# Thin, translucent members: overhead must never read like a colliding rim
	# (CONTRACT §6), so a gap spanned by a truss still looks flyable.
	lines(Band.OVER, pairs, color, 1.6)
	# heavier chords
	line(Band.OVER, a - nrm, b - nrm, color, 2.5)
	line(Band.OVER, a + nrm, b + nrm, color, 2.5)
	if lights and L > 30 * PX:
		var k := int(L / (40.0 * PX))
		for i in range(1, k + 1):
			var p := a + d * (float(i) / (k + 1))
			lamp(p, A.CYAN, 34.0, 2)


## Solid overhead slab (e.g. bridge deck / umbilical) with shadow.
## Only colliding hull gets a bright rim (CONTRACT §6): the slab is drawn
## see-through and its edge is capped to a faint 1 px line whatever the caller
## passes, so bridges and umbilicals never read as solid obstacles.
func overhead(poly: PackedVector2Array, color := Color(0.85, 0.9, 0.95, 0.62), edge := Color(0.85, 0.9, 0.95, 0.2)) -> void:
	fill(Band.OVER_SHADOW, poly, A.OVER_SHADOW)
	fill(Band.OVER, poly, Color(color, color.a * 0.72))
	outline(Band.OVER, poly, Color(edge, minf(edge.a * 0.35, 0.22)), 1.0)


## Engraved panel seam (dark line + light highlight offset by light dir).
func seam(b: int, a: Vector2, c: Vector2, dark := Color(0.45, 0.52, 0.6, 0.85), width := 1.6) -> void:
	_aa_segment(b, a, c, dark, width)
	var off := -A.LIGHT_DIR.normalized() * 1.2
	_aa_segment(b, a + off, c + off, Color(1, 1, 1, 0.45), 1.0)


func seams(b: int, pairs: PackedVector2Array, dark := Color(0.45, 0.52, 0.6, 0.85), width := 1.6) -> void:
	if pairs.size() < 2:
		return
	lines(b, pairs, dark, width)
	var off := -A.LIGHT_DIR.normalized() * 1.2
	var hi := PackedVector2Array()
	hi.resize(pairs.size())
	for i in pairs.size():
		hi[i] = pairs[i] + off
	lines(b, hi, Color(1, 1, 1, 0.4), 1.0)


static func poly_area(p: PackedVector2Array) -> float:
	var a := 0.0
	var n := p.size()
	for i in n:
		a += p[i].cross(p[(i + 1) % n])
	return a * 0.5


## Boolean union of two polygons, returning the outer outline (holes dropped).
static func union(a: PackedVector2Array, b: PackedVector2Array) -> PackedVector2Array:
	var best := a
	var best_area := 0.0
	for p in Geometry2D.merge_polygons(a, b):
		var ar := absf(poly_area(p))
		if ar > best_area:
			best = p
			best_area = ar
	return best
