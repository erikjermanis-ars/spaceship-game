@tool
class_name OnFootPainter
extends RefCounted
## Batched vector painter for on-foot art.
##
## Why: in the Compatibility renderer every antialiased line, circle or
## polyline drawn with CanvasItem.draw_* becomes its own draw call. A detailed
## floor or a pad full of bolts is thousands of them (we measured ~10 000 draw
## calls and 26 fps). This painter instead collects everything into ONE
## triangle array (vertex colours, no texture) and submits it with a single
## RenderingServer call: thousands of shapes, one draw call.
##
## Antialiasing without MSAA: each shape gets a thin "feather" ring whose
## outer vertices are transparent, ~1 screen pixel wide at walking zoom.
##
## Usage inside _draw():
##     var p := OnFootPainter.new(self)
##     p.rect(...); p.line(...); p.circle(...)
##     p.text(...)        # flushes first, so draw order is kept
##     p.flush()          # submit the remaining batch

var ci: CanvasItem
var feather := 0.12        ## px in world units (~1 screen px at zoom 8.5)
var xf := Transform2D.IDENTITY

var _pts := PackedVector2Array()
var _cols := PackedColorArray()
var _idx := PackedInt32Array()


func _init(target: CanvasItem, feather_px := 0.12) -> void:
	ci = target
	feather = feather_px


## Like CanvasItem.draw_set_transform: applies to shapes added afterwards.
func set_transform(pos := Vector2.ZERO, rot := 0.0, scl := Vector2.ONE) -> void:
	xf = Transform2D(rot, scl, 0.0, pos)


func flush() -> void:
	if _idx.is_empty():
		return
	RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), _idx, _pts, _cols)
	_pts = PackedVector2Array()
	_cols = PackedColorArray()
	_idx = PackedInt32Array()


# ----------------------------------------------------------- primitives --

## Filled polygon with a soft antialiased edge.
func fill(poly: PackedVector2Array, col: Color, aa := true) -> void:
	if poly.size() < 3 or col.a <= 0.0:
		return
	var p := xf * poly
	var tri := Geometry2D.triangulate_polygon(p)
	if tri.is_empty():
		return
	var base := _pts.size()
	_pts.append_array(p)
	_push_color(col, p.size())
	for t in tri:
		_idx.append(base + t)
	if aa:
		_feather_ring(p, col)


## Polygon fill plus an outline in another colour (the classic look).
func poly(p: PackedVector2Array, col: Color, outline := Color(0, 0, 0, 0), width := 0.12) -> void:
	fill(p, col, outline.a <= 0.0)
	if outline.a > 0.0:
		polyline(p, outline, width, true)


func rect(r: Rect2, col: Color, outline := Color(0, 0, 0, 0), width := 0.12) -> void:
	poly(OnFootArt.rect_poly(r), col, outline, width)


## Plain axis-aligned rect without feathering (floors, big flat areas).
func rect_flat(r: Rect2, col: Color) -> void:
	fill(OnFootArt.rect_poly(r), col, false)


func rrect(r: Rect2, rad: float, col: Color, outline := Color(0, 0, 0, 0), width := 0.12) -> void:
	poly(LevelArt.rounded_rect(r, rad, 3), col, outline, width)


func circle(c: Vector2, r: float, col: Color, outline := Color(0, 0, 0, 0), width := 0.12, segs := 0) -> void:
	if segs <= 0:
		segs = clampi(int(r * 3.0), 8, 40)
	var p := LevelArt.circle_poly(c, r, segs)
	fill(p, col, outline.a <= 0.0)
	if outline.a > 0.0:
		polyline(p, outline, width, true)


func ring(c: Vector2, r: float, col: Color, width := 0.15, segs := 0) -> void:
	if segs <= 0:
		segs = clampi(int(r * 3.0), 10, 48)
	polyline(LevelArt.circle_poly(c, r, segs), col, width, true)


func ellipse(c: Vector2, rx: float, ry: float, col: Color, outline := Color(0, 0, 0, 0), width := 0.12, rot := 0.0) -> void:
	poly(OnFootArt.ellipse_poly(c, rx, ry, rot, 20), col, outline, width)


## Antialiased line segment (solid core + transparent feather each side).
func line(a: Vector2, b: Vector2, col: Color, width := 0.15, caps := true) -> void:
	a = xf * a
	b = xf * b
	var d := b - a
	var l := d.length()
	if l < 0.0001 or col.a <= 0.0:
		return
	d /= l
	var hw := width * 0.5
	if caps:
		a -= d * hw
		b += d * hw
	var n := d.orthogonal()
	var o := hw + feather
	var clear := Color(col, 0.0)
	var base := _pts.size()
	_pts.append_array(PackedVector2Array([a - n * o, b - n * o, b - n * hw, a - n * hw, a + n * hw, b + n * hw, b + n * o, a + n * o]))
	_cols.append_array(PackedColorArray([clear, clear, col, col, col, col, clear, clear]))
	for t in [0, 1, 2, 0, 2, 3, 3, 2, 5, 3, 5, 4, 4, 5, 6, 4, 6, 7]:
		_idx.append(base + t)


func polyline(pts: PackedVector2Array, col: Color, width := 0.15, closed := false) -> void:
	var n := pts.size()
	if n < 2:
		return
	for i in (n if closed else n - 1):
		line(pts[i], pts[(i + 1) % n], col, width)


func arc(c: Vector2, r: float, a0: float, a1: float, col: Color, width := 0.15, segs := 24) -> void:
	polyline(LevelArt.arc_points(c, r, a0, a1, segs), col, width)


func capsule(a: Vector2, b: Vector2, width: float, col: Color) -> void:
	line(a, b, col, width, false)
	circle(a, width * 0.5, col)
	circle(b, width * 0.5, col)


## Diagonal hazard stripes clipped to a rect.
func hazard(r: Rect2, stripe := 2.0, col := OnFootArt.AMBER, dark := Color("17202B")) -> void:
	rect_flat(r, dark)
	var x := r.position.x - r.size.y
	var rp := OnFootArt.rect_poly(r)
	while x < r.end.x:
		var p := PackedVector2Array([
			Vector2(x, r.end.y), Vector2(x + stripe, r.end.y),
			Vector2(x + stripe + r.size.y, r.position.y), Vector2(x + r.size.y, r.position.y)])
		for c in Geometry2D.intersect_polygons(p, rp):
			fill(c, col, false)
		x += stripe * 2.0


## Text keeps its order: the pending batch is submitted first.
func text(pos: Vector2, s: String, size: float, col: Color, align := HORIZONTAL_ALIGNMENT_CENTER, width := -1.0, bold := true, rot := 0.0) -> void:
	flush()
	OnFootArt.text(ci, xf * pos, s, size, col, align, width, bold, rot + xf.get_rotation())


# ------------------------------------------------------------- internals --

func _push_color(col: Color, n: int) -> void:
	var start := _cols.size()
	_cols.resize(start + n)
	for i in n:
		_cols[start + i] = col


## Transparent ring just outside the polygon edge (vertex normals, so it is
## continuous around curves). Winding-independent.
func _feather_ring(p: PackedVector2Array, col: Color) -> void:
	var n := p.size()
	var area := 0.0
	for i in n:
		area += p[i].cross(p[(i + 1) % n])
	var s := 1.0 if area > 0.0 else -1.0
	var clear := Color(col, 0.0)
	var base := _pts.size()
	for i in n:
		var prev := p[(i - 1 + n) % n]
		var cur := p[i]
		var nxt := p[(i + 1) % n]
		var n1 := (cur - prev).normalized().orthogonal()
		var n2 := (nxt - cur).normalized().orthogonal()
		var nn := (n1 + n2)
		nn = nn.normalized() if nn.length_squared() > 0.0001 else n1
		_pts.append(cur)
		_pts.append(cur + nn * feather * s)
		_cols.append(col)
		_cols.append(clear)
	for i in n:
		var a := base + i * 2
		var b := base + ((i + 1) % n) * 2
		_idx.append_array(PackedInt32Array([a, b, b + 1, a, b + 1, a + 1]))
