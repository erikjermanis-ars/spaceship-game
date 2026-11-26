@tool
class_name InteriorProp
extends Node2D
## A piece of furniture / equipment, drawn procedurally. Footprint is a rect
## of `size_m` centred on the node; local +X is the "front" (the side you use
## or sit on), so rotate the node to face it into the room.
##
## solid   -> StaticBody2D on LAYER_WALK (the walker bumps into it)
## occlude -> LightOccluder2D (casts flashlight shadows; use for tall things)
## Screens, LEDs and lamps go into an unshaded child so they glow in dark rooms.

enum Kind {
	BED, DESK, CHAIR, LOCKERS, SOFA, ARMCHAIR, COFFEE_TABLE, RUG, PLANT, CONSOLE,
	CRATES, SHELF, BENCH, SUIT_RACK, BAR, STOOL, BIN, EXTINGUISHER, WALL_SCREEN,
	NIGHTSTAND, PALLET_JACK, WATER_COOLER,
}

@export var kind: Kind = Kind.CRATES:
	set(v): kind = v; queue_redraw()
@export var size_m := Vector2(1, 1):
	set(v): size_m = v; queue_redraw()
@export var color := Color("2A9D8F"):
	set(v): color = v; queue_redraw()
@export var solid := true
@export var occlude := false
@export var seed := 0:
	set(v): seed = v; queue_redraw()

const INK := OnFootArt.INK
var _t := 0.0
var _emissive: Node2D


## Batched painter used by the draw callbacks (see OnFootPainter).
var pen: OnFootPainter

func _ready() -> void:
	z_as_relative = false
	if kind == Kind.RUG:
		z_index = -2
	elif kind == Kind.WALL_SCREEN or kind == Kind.EXTINGUISHER:
		z_index = 11        # mounted on the wall: just under the wall tops
	else:
		z_index = 1
	if Engine.is_editor_hint():
		return
	var hs := size_m * OnFootArt.PX * 0.5
	var poly := PackedVector2Array([Vector2(-hs.x, -hs.y), Vector2(hs.x, -hs.y), Vector2(hs.x, hs.y), Vector2(-hs.x, hs.y)])
	if solid and kind != Kind.RUG:
		var body := StaticBody2D.new()
		body.collision_layer = Game.LAYER_WALK
		body.collision_mask = 0
		var cs := CollisionShape2D.new()
		var rs := RectangleShape2D.new()
		rs.size = hs * 2.0 - Vector2(0.4, 0.4)
		cs.shape = rs
		body.add_child(cs)
		add_child(body)
	if occlude:
		var occ := LightOccluder2D.new()
		var op := OccluderPolygon2D.new()
		op.polygon = poly
		occ.occluder = op
		add_child(occ)
	if _has_emissive():
		_emissive = Node2D.new()
		_emissive.material = OnFootArt.unshaded()
		_emissive.draw.connect(_draw_emissive)
		add_child(_emissive)


func _has_emissive() -> bool:
	return kind in [Kind.DESK, Kind.CONSOLE, Kind.WALL_SCREEN, Kind.LOCKERS, Kind.SUIT_RACK, Kind.WATER_COOLER, Kind.BAR]


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _emissive == null:
		return
	# Screens refresh at ~10 Hz: lively, and far cheaper than every frame.
	var before := int(_t * 10.0)
	_t += delta
	if int(_t * 10.0) != before:
		_emissive.queue_redraw()


func _draw() -> void:
	pen = OnFootPainter.new(self)
	_paint_draw()
	pen.flush()


func _paint_draw() -> void:
	var px := OnFootArt.PX
	var s := size_m * px
	var r := Rect2(-s * 0.5, s)
	# soft drop shadow (global light direction)
	if kind != Kind.RUG and kind != Kind.WALL_SCREEN:
		pen.set_transform(OnFootArt.SHADOW_OFFSET.rotated(-global_rotation), 0.0)
		pen.rect_flat(r, Color(0, 0.01, 0.03, 0.22))
		pen.set_transform()
	match kind:
		Kind.BED: _bed(r)
		Kind.DESK: _desk(r)
		Kind.CHAIR: _chair(r)
		Kind.LOCKERS: _lockers(r)
		Kind.SOFA: _sofa(r)
		Kind.ARMCHAIR: _armchair(r)
		Kind.COFFEE_TABLE: _coffee_table(r)
		Kind.RUG: _rug(r)
		Kind.PLANT: _plant(r)
		Kind.CONSOLE: _console(r)
		Kind.CRATES: _crates(r)
		Kind.SHELF: _shelf(r)
		Kind.BENCH: _bench(r)
		Kind.SUIT_RACK: _suit_rack(r)
		Kind.BAR: _bar(r)
		Kind.STOOL: _stool(r)
		Kind.BIN: _bin(r)
		Kind.EXTINGUISHER: _extinguisher(r)
		Kind.WALL_SCREEN: pen.rect(r, Color("1B2533"), INK, 0.15)
		Kind.NIGHTSTAND: _nightstand(r)
		Kind.PALLET_JACK: _pallet_jack(r)
		Kind.WATER_COOLER: _water_cooler(r)


# ----------------------------------------------------------------- kinds --

func _bed(r: Rect2) -> void:
	# head at -X... pillow end; frame, mattress, blanket over the foot half
	pen.rrect(r, 0.6, Color("6D7A8A"), INK, 0.15)
	var m := r.grow(-0.6)
	pen.rrect(m, 0.8, Color("E3E8EE"), Color("B4BFCB"), 0.1)
	var pil := Rect2(Vector2(m.position.x + 0.6, m.position.y + 0.8), Vector2(3.6, m.size.y - 1.6))
	pen.rrect(pil, 1.2, Color("FFFFFF"), Color("C9D2DC"), 0.1)
	var bl := Rect2(Vector2(m.position.x + m.size.x * 0.38, m.position.y - 0.2), Vector2(m.size.x * 0.62 + 0.2, m.size.y + 0.4))
	pen.rrect(bl, 0.9, color, color.darkened(0.3), 0.12)
	pen.line(Vector2(bl.position.x + 1.0, bl.position.y + 0.2), Vector2(bl.position.x + 1.0, bl.end.y - 0.2), color.lightened(0.25), 0.5)
	for i in 3:
		var x := bl.position.x + 3.5 + i * 3.6
		pen.line(Vector2(x, bl.position.y + 0.6), Vector2(x + 1.2, bl.end.y - 0.6), Color(color.darkened(0.15), 0.6), 0.2)


func _desk(r: Rect2) -> void:
	pen.rect(r, Color("8A6F55"), INK, 0.15)
	pen.rect(r.grow(-0.35), Color("A3876B"), Color(0, 0, 0, 0))
	# monitor at the back (-X edge), keyboard, mug, papers
	var mon := Rect2(Vector2(r.position.x + 0.8, -2.4), Vector2(1.2, 4.8))
	pen.rect(mon, Color("1B2533"), INK, 0.1)
	pen.rect(Rect2(Vector2(r.position.x + 2.6, -1.8), Vector2(1.3, 3.6)), Color("2B3440"), INK, 0.08)
	pen.circle(Vector2(r.position.x + 3.0, r.end.y - 2.0), 0.75, Color("E9EEF3"), INK, 0.1)
	pen.circle(Vector2(r.position.x + 3.0, r.end.y - 2.0), 0.48, Color("5A3A28"))
	var paper := Rect2(Vector2(r.position.x + 1.6, r.position.y + 1.2), Vector2(2.4, 1.8))
	pen.set_transform(paper.get_center(), 0.2)
	pen.rect(Rect2(-paper.size * 0.5, paper.size), Color("F4F7FA"), Color("C9D2DC"), 0.06)
	pen.set_transform()


func _chair(r: Rect2) -> void:
	var c := r.get_center()
	var rad := minf(r.size.x, r.size.y) * 0.5
	pen.circle(c, rad * 0.95, Color("2B3440"), INK, 0.12)
	pen.circle(c + Vector2(0.3, 0), rad * 0.7, color, color.darkened(0.3), 0.1)
	var back := Rect2(Vector2(r.position.x - 0.2, -rad * 0.85), Vector2(1.4, rad * 1.7))
	pen.rrect(back, 0.6, color.darkened(0.2), INK, 0.12)


func _lockers(r: Rect2) -> void:
	pen.rect(r, Color("6D7A8A"), INK, 0.15)
	var n := maxi(1, int(r.size.y / 8.0))
	var w := r.size.y / n
	for i in n:
		var d := Rect2(Vector2(r.position.x + 0.4, r.position.y + i * w + 0.3), Vector2(r.size.x - 0.8, w - 0.6))
		pen.rect(d, color if i % 3 != 1 else color.darkened(0.12), Color("4A5563"), 0.1)
		for k in 3:
			pen.line(Vector2(d.position.x + 0.8 + k * 0.7, d.position.y + 1.0), Vector2(d.position.x + 0.8 + k * 0.7, d.end.y - 1.0), Color(0, 0, 0, 0.25), 0.25)
		pen.rect_flat(Rect2(Vector2(d.end.x - 1.0, d.get_center().y - 0.6), Vector2(0.5, 1.2)), Color("C9D2DC"))


func _sofa(r: Rect2) -> void:
	var dark := color.darkened(0.25)
	pen.rrect(r, 1.2, dark, INK, 0.15)
	var back := Rect2(r.position, Vector2(2.4, r.size.y))
	pen.rrect(back, 1.0, color.darkened(0.12), INK, 0.12)
	for side: float in [-1.0, 1.0]:
		var arm := Rect2(Vector2(r.position.x, (r.end.y - 2.2) if side > 0 else r.position.y), Vector2(r.size.x, 2.2))
		pen.rrect(arm, 1.0, color.darkened(0.12), INK, 0.12)
	var seat := Rect2(Vector2(r.position.x + 2.4, r.position.y + 2.2), Vector2(r.size.x - 2.6, r.size.y - 4.4))
	var n := maxi(1, int(seat.size.y / 7.0))
	for i in n:
		var cu := Rect2(Vector2(seat.position.x, seat.position.y + i * seat.size.y / n + 0.2), Vector2(seat.size.x, seat.size.y / n - 0.4))
		pen.rrect(cu, 1.0, color, color.darkened(0.3), 0.1)
		pen.line(cu.position + Vector2(0.8, 1.0), Vector2(cu.position.x + 0.8, cu.end.y - 1.0), color.lightened(0.18), 0.35)
	# a throw cushion
	pen.rrect(Rect2(Vector2(seat.position.x + 0.3, seat.position.y + 1.0), Vector2(1.8, 2.6)), 0.6, Color("FFB000"), INK, 0.08)


func _armchair(r: Rect2) -> void:
	pen.rrect(r, 1.4, color.darkened(0.15), INK, 0.15)
	pen.rrect(Rect2(r.position, Vector2(2.4, r.size.y)), 1.0, color.darkened(0.25), INK, 0.1)
	pen.rrect(Rect2(r.position + Vector2(2.4, 1.8), Vector2(r.size.x - 2.6, r.size.y - 3.6)), 1.0, color, color.darkened(0.3), 0.1)


func _coffee_table(r: Rect2) -> void:
	pen.rrect(r, 0.8, Color("2B3440"), INK, 0.15)
	pen.rrect(r.grow(-0.5), 0.6, Color(0.6, 0.85, 0.95, 0.35), Color(0.8, 0.95, 1.0, 0.5), 0.1)
	pen.rect(Rect2(Vector2(-1.8, -2.4), Vector2(3.0, 2.2)), Color("E76F51"), INK, 0.06)   # magazine
	pen.circle(Vector2(1.6, 2.2), 0.7, Color("E9EEF3"), INK, 0.08)


func _rug(r: Rect2) -> void:
	pen.rrect(r, 1.0, Color(color, 0.85))
	pen.polyline(OnFootArt.rect_poly(r.grow(-1.2)), Color(color.lightened(0.25), 0.8), 0.5, true)
	pen.polyline(OnFootArt.rect_poly(r.grow(-2.2)), Color(color.darkened(0.2), 0.6), 0.25, true)
	var c := r.get_center()
	pen.fill(PackedVector2Array([c + Vector2(0, -r.size.y * 0.25), c + Vector2(r.size.x * 0.22, 0), c + Vector2(0, r.size.y * 0.25), c + Vector2(-r.size.x * 0.22, 0)]), Color(color.lightened(0.15), 0.6))


func _plant(r: Rect2) -> void:
	var c := r.get_center()
	var rad := minf(r.size.x, r.size.y) * 0.5
	pen.circle(c, rad * 0.62, Color("C9D2DC"), INK, 0.12)
	pen.circle(c, rad * 0.5, Color("4A3A2E"))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 17
	var leaves := 9
	for i in leaves:
		var a := TAU * i / leaves + rng.randf_range(-0.25, 0.25)
		var l := rad * rng.randf_range(0.75, 1.05)
		var tip := c + Vector2(cos(a), sin(a)) * l
		var side := Vector2(cos(a), sin(a)).orthogonal() * rad * 0.2
		var mid := c + Vector2(cos(a), sin(a)) * l * 0.5
		var leaf := PackedVector2Array([c, mid + side, tip, mid - side])
		var g := Color("3E8E5A").lerp(Color("6CBF6A"), rng.randf())
		pen.poly(leaf, g, g.darkened(0.35), 0.08)
		pen.line(c, tip, g.darkened(0.25), 0.1)


func _console(r: Rect2) -> void:
	pen.rrect(r, 0.6, Color("4A5563"), INK, 0.15)
	pen.rect(Rect2(r.position + Vector2(0.4, 0.4), Vector2(r.size.x * 0.55, r.size.y - 0.8)), Color("2B3440"), Color(0, 0, 0, 0))
	# keyboard strip at the front edge
	var n := maxi(1, int(r.size.y / 9.0))
	for i in n:
		var y := r.position.y + (i + 0.5) * r.size.y / n
		pen.rect(Rect2(Vector2(r.end.x - 2.6, y - 2.0), Vector2(1.6, 4.0)), Color("1B2533"), INK, 0.06)
	pen.line(Vector2(r.end.x - 0.3, r.position.y + 0.5), Vector2(r.end.x - 0.3, r.end.y - 0.5), Color("2A9D8F"), 0.3)


func _crates(r: Rect2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 3
	var cols := [color, Color("E76F51"), Color("F4A261"), Color("4EA8DE"), Color("8AB17D")]
	var nx := maxi(1, int(round(r.size.x / 12.0)))
	var ny := maxi(1, int(round(r.size.y / 12.0)))
	var cw := r.size.x / nx
	var ch := r.size.y / ny
	for i in nx:
		for j in ny:
			var cr := Rect2(r.position + Vector2(i * cw, j * ch), Vector2(cw, ch)).grow(-0.3)
			var col: Color = cols[rng.randi() % cols.size()]
			pen.rect(cr, col.darkened(0.12), INK, 0.12)
			pen.rect(cr.grow(-0.9), col)
			pen.line(cr.position + Vector2(0.9, 0.9), cr.end - Vector2(0.9, 0.9), col.darkened(0.25), 0.35)
			pen.line(Vector2(cr.position.x + 0.9, cr.end.y - 0.9), Vector2(cr.end.x - 0.9, cr.position.y + 0.9), col.darkened(0.25), 0.35)
			pen.rect_flat(Rect2(cr.get_center() - Vector2(1.6, 0.9), Vector2(3.2, 1.8)), Color(0.95, 0.96, 0.98, 0.9))


func _shelf(r: Rect2) -> void:
	pen.rect(r, Color("3A4452"), INK, 0.15)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 9
	var y := r.position.y + 0.5
	while y < r.end.y - 2.0:
		var h := rng.randf_range(2.0, 4.0)
		h = minf(h, r.end.y - 0.5 - y)
		var w := r.size.x - rng.randf_range(0.6, 2.4)
		var col := Color("C9A27A").lerp(Color("8E9AA8"), rng.randf())
		pen.rect(Rect2(Vector2(r.position.x + 0.3, y), Vector2(w, h - 0.3)), col, INK, 0.08)
		y += h
	for x in [r.position.x + 0.15, r.end.x - 0.15]:
		pen.line(Vector2(x, r.position.y), Vector2(x, r.end.y), Color("FFB000"), 0.3)


func _bench(r: Rect2) -> void:
	pen.rrect(r, 0.5, Color("6D7A8A"), INK, 0.12)
	var n := maxi(1, int(r.size.y / 2.0))
	for i in n:
		var y := r.position.y + (i + 0.5) * r.size.y / n
		pen.line(Vector2(r.position.x + 0.5, y), Vector2(r.end.x - 0.5, y), Color("8E9AA8"), 0.5)


func _suit_rack(r: Rect2) -> void:
	# Back board against the wall (-X) with a cubby per suit; each EVA suit
	# hangs facing the room, drawn like the walker (pack, shoulders, helmet).
	pen.rect(Rect2(r.position, Vector2(1.2, r.size.y)), Color("4A5563"), INK, 0.12)
	var n := maxi(1, int(r.size.y / 9.0))
	var w := r.size.y / n
	for i in n:
		var y0 := r.position.y + i * w
		pen.line(Vector2(r.position.x + 1.2, y0), Vector2(r.end.x - 0.4, y0), Color("6D7A8A"), 0.35)
		var c := Vector2(r.position.x + 4.0, y0 + w * 0.5)
		pen.rrect(Rect2(c + Vector2(-3.0, -1.7), Vector2(1.6, 3.4)), 0.45, Color("C3CCD6"), INK, 0.1)   # pack
		var torso := OnFootArt.ellipse_poly(c, 1.25, 2.6, 0.0, 18)
		pen.poly(torso, Color("E9EEF3"), INK, 0.12)
		for sd: float in [-1.0, 1.0]:
			pen.circle(c + Vector2(0.0, sd * 2.2), 0.7, Color("E9EEF3"), INK, 0.08)
			pen.arc(c + Vector2(0.0, sd * 2.2), 0.5, 0, 12, Color("2A9D8F"), 0.15, TAU)
		pen.line(c + Vector2(0.6, -1.9), c + Vector2(0.6, 1.9), Color("1D3557"), 0.3)
		# helmet on the shelf in front of the suit
		var h := c + Vector2(2.6, 0)
		pen.circle(h, 1.15, Color("E9EEF3"), INK, 0.1)
		pen.fill(LevelArt.arc_band(h, 0.0, 1.0, -1.1, 1.1, 10), Color("16304F"))
	pen.line(Vector2(r.end.x - 0.4, r.position.y), Vector2(r.end.x - 0.4, r.end.y), Color("FFB000"), 0.25)


func _bar(r: Rect2) -> void:
	pen.rrect(r, 0.6, Color("2B3440"), INK, 0.15)
	pen.rect(Rect2(Vector2(r.end.x - 2.0, r.position.y + 0.3), Vector2(1.6, r.size.y - 0.6)), Color("C9A27A"), INK, 0.08)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 5
	var y := r.position.y + 2.0
	while y < r.end.y - 2.0:
		var col: Color = [Color("4EA8DE"), Color("E76F51"), Color("8AB17D"), Color("F4A261")][rng.randi() % 4]
		pen.circle(Vector2(r.position.x + 1.6, y), 0.55, Color(col, 0.85), INK, 0.06)
		y += rng.randf_range(1.3, 2.2)


func _stool(r: Rect2) -> void:
	var c := r.get_center()
	var rad := minf(r.size.x, r.size.y) * 0.5
	pen.circle(c, rad, Color("4A5563"), INK, 0.12)
	pen.circle(c, rad * 0.75, color, color.darkened(0.3), 0.08)


func _bin(r: Rect2) -> void:
	var c := r.get_center()
	var rad := minf(r.size.x, r.size.y) * 0.5
	pen.circle(c, rad, Color("6D7A8A"), INK, 0.12)
	pen.circle(c, rad * 0.7, Color("2B3440"))
	pen.arc(c, rad * 0.85, 0, TAU, Color("2A9D8F"), 0.25, 20)


func _extinguisher(r: Rect2) -> void:
	pen.rect(r, Color("C9D2DC"), INK, 0.1)
	pen.circle(r.get_center() + Vector2(0.4, 0), minf(r.size.x, r.size.y) * 0.38, Color("D63A2F"), INK, 0.1)
	pen.circle(r.get_center() + Vector2(0.4, 0), 0.35, Color("2B3440"))


func _nightstand(r: Rect2) -> void:
	pen.rect(r, Color("8A6F55"), INK, 0.12)
	pen.rect(r.grow(-0.4), Color("A3876B"))
	pen.rect(Rect2(r.get_center() - Vector2(1.2, 0.8), Vector2(2.4, 1.6)), Color("2B3440"), INK, 0.06)


func _pallet_jack(r: Rect2) -> void:
	for side: float in [-1.0, 1.0]:
		pen.rect(Rect2(Vector2(r.position.x, side * r.size.y * 0.28 - 0.9), Vector2(r.size.x * 0.75, 1.8)), Color("FFB000"), INK, 0.1)
	pen.rrect(Rect2(Vector2(r.end.x - r.size.x * 0.28, r.position.y + 0.5), Vector2(r.size.x * 0.28, r.size.y - 1.0)), 0.6, Color("E5A000"), INK, 0.12)
	pen.capsule(Vector2(r.end.x - 1.0, 0), Vector2(r.end.x + 3.0, 0), 0.6, Color("2B3440"))
	pen.capsule(Vector2(r.end.x + 3.0, -1.4), Vector2(r.end.x + 3.0, 1.4), 0.6, Color("2B3440"))


func _water_cooler(r: Rect2) -> void:
	pen.rect(r, Color("E9EEF3"), INK, 0.12)
	pen.circle(r.get_center() - Vector2(0.4, 0), minf(r.size.x, r.size.y) * 0.36, Color(0.55, 0.8, 0.95, 0.85), INK, 0.08)


# --------------------------------------------------------------- emissive --

func _draw_emissive() -> void:
	pen = OnFootPainter.new(_emissive)
	_paint_draw_emissive()
	pen.flush()


func _paint_draw_emissive() -> void:
	var px := OnFootArt.PX
	var s := size_m * px
	var r := Rect2(-s * 0.5, s)
	var t := _t
	match kind:
		Kind.DESK:
			var mon := Rect2(Vector2(r.position.x + 1.0, -2.2), Vector2(0.8, 4.4))
			pen.rect_flat(mon, Color(0.35, 0.75, 1.0, 0.9))
			for i in 4:
				var w := 2.0 + 1.6 * (0.5 + 0.5 * sin(t * 0.7 + i * 1.7))
				pen.rect_flat(Rect2(Vector2(mon.position.x + 0.15, mon.position.y + 0.4 + i * 1.0), Vector2(0.5, minf(w, 3.8) * 0.25)), Color(1, 1, 1, 0.75))
		Kind.CONSOLE:
			var n := maxi(1, int(r.size.y / 9.0))
			for i in n:
				var y := r.position.y + (i + 0.5) * r.size.y / n
				var scr := Rect2(Vector2(r.position.x + 0.8, y - 3.2), Vector2(r.size.x * 0.45, 6.4))
				var hue: Color = [Color(0.3, 0.85, 1.0), Color(0.35, 1.0, 0.65), Color(1.0, 0.75, 0.3)][(i + seed) % 3]
				pen.rect_flat(scr, Color(hue, 0.18))
				pen.polyline(OnFootArt.rect_poly(scr), Color(hue, 0.9), 0.15, true)
				# a scrolling readout / radar sweep
				if (i + seed) % 3 == 0:
					var c := scr.get_center()
					var a := t * 2.0 + i
					pen.arc(c, 1.6, 0, TAU, Color(hue, 0.6), 0.12, 20)
					pen.line(c, c + Vector2(cos(a), sin(a)) * 1.6, Color(hue, 0.9), 0.15)
				else:
					for k in 5:
						var w := 0.6 + 1.6 * fposmod(sin(t * (0.5 + k * 0.13) + k * 2.1 + i) * 43.7, 1.0)
						pen.rect_flat(Rect2(Vector2(scr.position.x + 0.4, scr.position.y + 0.6 + k * 1.1), Vector2(minf(w, scr.size.x - 0.8), 0.45)), Color(hue, 0.8))
				for k in 4:
					var on := fposmod(t * 1.3 + k * 0.37 + i, 1.0) < 0.7
					pen.circle(Vector2(r.end.x - 0.9, y - 1.5 + k), 0.18, Color(0.4, 1.0, 0.6) if on else Color(1.0, 0.4, 0.3))
		Kind.WALL_SCREEN:
			# Seen from above a wall screen is a thin lit strip; its face
			# (+X) shows a scrolling traffic ticker.
			var face := Rect2(Vector2(r.end.x - 1.0, r.position.y + 0.4), Vector2(0.8, r.size.y - 0.8))
			pen.rect_flat(face, Color(0.12, 0.35, 0.55))
			var n := 7
			for i in n:
				var f := fposmod(i / float(n) + t * 0.08, 1.0)
				var y := face.position.y + f * face.size.y
				var h := face.size.y * 0.06
				var hue := Color(1.0, 0.8, 0.3) if i % 3 == 0 else Color(0.5, 0.9, 1.0)
				pen.rect_flat(Rect2(Vector2(face.position.x + 0.1, y), Vector2(0.6, minf(h, face.end.y - y))), Color(hue, 0.85))
			pen.rect_flat(Rect2(Vector2(face.end.x, face.position.y), Vector2(0.6, face.size.y)), Color(0.4, 0.8, 1.0, 0.18))
		Kind.LOCKERS:
			var n := maxi(1, int(r.size.y / 8.0))
			var w := r.size.y / n
			for i in n:
				pen.circle(Vector2(r.end.x - 0.75, r.position.y + i * w + 1.0), 0.18, Color(0.4, 1.0, 0.6))
		Kind.SUIT_RACK:
			var n := maxi(1, int(r.size.y / 9.0))
			var w := r.size.y / n
			for i in n:
				var blink := fposmod(t + i * 0.4, 2.0) < 1.7
				pen.circle(Vector2(r.position.x + 0.9, r.position.y + (i + 0.5) * w - 1.6), 0.2, Color(0.4, 1.0, 0.6) if blink else Color(0.1, 0.3, 0.2))
		Kind.WATER_COOLER:
			pen.circle(Vector2(r.end.x - 0.5, -0.6), 0.16, Color(0.3, 0.7, 1.0))
			pen.circle(Vector2(r.end.x - 0.5, 0.6), 0.16, Color(1.0, 0.3, 0.3))
		Kind.BAR:
			pen.line(Vector2(r.end.x - 0.15, r.position.y + 0.4), Vector2(r.end.x - 0.15, r.end.y - 0.4), Color(1.0, 0.7, 0.35, 0.9), 0.25)
