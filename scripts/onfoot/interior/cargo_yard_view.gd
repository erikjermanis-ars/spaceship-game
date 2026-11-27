@tool
extends Node2D
## What you see out of Yard Control's windows: Cargo Yard C itself. The world
## is suspended (and hidden) while you are indoors, so, like PierExterior and
## BerthView, the interior paints its own surroundings: the apron with its
## lanes and bay numbers, the five container stacks, the slewing crane and
## every free container, each where it really is right now. The yard is frozen
## while you are inside, so what you see is what you step back out into.
##
## Geometry comes from the yard module's own constants (STACKS, CRANE_PIVOT)
## and the same seeded hashes, so the stacks' colours match the flight view.
## Drawn once, in yard-local px, through one OnFootPainter batch. Unshaded:
## it is sunlit outside, not part of the dark rooms.

const Yard := preload("res://scripts/level/modules/cargo_yard.gd")
const PX := 10.0
const APRON := Rect2(-2450, -920, 4900, 2450)   ## cargo_yard.gd: m(-245, -92), m(490, 245)

## Where the yard is when there is no live level to ask (editor preview).
@export var yard_origin := Vector2(0, 6000)
@export var yard_seed := 7

var _crane_angle := PI
var _crane_boom_m := 100.0
## [Transform2D (yard-local), size px, colour] per free container.
var _boxes: Array = []


func _ready() -> void:
	z_as_relative = false
	z_index = -9
	var origin := yard_origin
	if not Engine.is_editor_hint():
		material = OnFootArt.unshaded()
		var yard := _find_yard()
		if yard:
			origin = yard.global_position
			yard_seed = int(yard.get(&"seed"))
			_read_live(yard)
	# The interior sits at its real world position, so world px = global px.
	# In the editor the level is at the origin: shift by its world_origin.
	var level := get_parent() as InteriorLevel
	if Engine.is_editor_hint() and level and level.use_world_origin:
		position = origin - level.world_origin
	else:
		global_position = origin
	queue_redraw()


func _find_yard() -> Node2D:
	for n in get_tree().get_nodes_in_group(&"radar_structure"):
		if n.get_script() == Yard:
			return n as Node2D
	return null


## The crane's slew angle and the free containers, as the yard left them.
func _read_live(yard: Node2D) -> void:
	var crane := yard.get_node_or_null(^"Crane")
	if crane:
		_crane_boom_m = float(crane.get(&"boom_m"))
		var body := crane.get(&"body") as Node2D
		if body:
			_crane_angle = body.rotation
	var inv := yard.global_transform.affine_inverse()
	for n in get_tree().get_nodes_in_group(&"cargo_container"):
		var box := n as Node2D
		if box == null or not box.is_inside_tree():
			continue
		var xf := inv * box.global_transform
		if APRON.grow(900.0).has_point(xf.origin):
			_boxes.append([xf, (box.get(&"size_m") as Vector2) * PX, box.get(&"color") as Color])


func _draw() -> void:
	var pen := OnFootPainter.new(self, 0.3)
	_apron(pen)
	_stacks(pen)
	_free_boxes(pen)
	_crane(pen)
	pen.flush()


func _apron(pen: OnFootPainter) -> void:
	var poly := LevelArt.rounded_rect(APRON, 160.0)
	pen.fill(poly, Color("1A222E"))
	var inner := LevelArt.rounded_rect(APRON.grow(-7.0), 153.0)
	pen.fill(inner, Color("212B39"))
	var step := 80.0
	var x := ceilf(APRON.position.x / step) * step
	while x < APRON.end.x:
		for seg in Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([Vector2(x, APRON.position.y - 1), Vector2(x, APRON.end.y + 1)]), inner):
			pen.line(seg[0], seg[seg.size() - 1], Color("2A3648"), 1.5, false)
		x += step
	var y := ceilf(APRON.position.y / step) * step
	while y < APRON.end.y:
		for seg in Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([Vector2(APRON.position.x - 1, y), Vector2(APRON.end.x + 1, y)]), inner):
			pen.line(seg[0], seg[seg.size() - 1], Color("2A3648"), 1.5, false)
		y += step
	pen.polyline(poly, Color("50637C"), 2.0, true)
	for ly: float in [-80.0, 660.0]:
		pen.line(Vector2(-2250, ly), Vector2(-900, ly), Color(1.0, 0.8, 0.3, 0.4), 5.0)
	# crane slew arc and its end stops
	var pivot: Vector2 = Yard.CRANE_PIVOT * PX
	pen.arc(pivot, 1000.0, PI * 0.7, PI * 1.3, Color(1.0, 0.69, 0.0, 0.45), 10.0, 64)
	pen.arc(pivot, 1030.0, PI * 0.7, PI * 1.3, Color(1.0, 0.69, 0.0, 0.2), 4.0, 64)
	for e: float in [-1.0, 1.0]:
		var a := PI + e * PI * 0.25
		pen.set_transform(pivot + Vector2.from_angle(a) * 1000.0, a)
		pen.hazard(Rect2(-80, -15, 160, 30), 9.0)
		pen.set_transform()
	# apron edge lights
	for i in 24:
		var lx := lerpf(-2350, 2350, (i + 0.5) / 24.0)
		for ly: float in [-900.0, 1510.0]:
			pen.circle(Vector2(lx, ly), 9.0, Color(0.5, 0.9, 1.0, 0.12))
			pen.circle(Vector2(lx, ly), 3.0, OnFootArt.CYAN)
	# painted bay numbers and the yard's name (text flushes the batch first)
	for i in Yard.STACKS.size():
		var r: Rect2 = Yard.STACKS[i]
		var west := i < 3
		var at := Vector2(r.position.x - 14.0 if west else r.end.x + 12.0, r.get_center().y) * PX
		pen.text(at, "C%d" % (i + 1), 80.0, Color(0.85, 0.9, 1.0, 0.35), HORIZONTAL_ALIGNMENT_CENTER, 400.0, true, -PI * 0.5 if west else PI * 0.5)
	pen.text(Vector2(100, 1280), "CARGO YARD C", 150.0, Color(0.85, 0.9, 1.0, 0.12), HORIZONTAL_ALIGNMENT_CENTER, 2400.0)


## The stacks: steel plinths gridded with containers, coloured by the same
## hash the yard module uses, so they are the stacks you flew past.
func _stacks(pen: OnFootPainter) -> void:
	var idx := yard_seed * 1000
	for sr: Rect2 in Yard.STACKS:
		var r := Rect2(sr.position * PX, sr.size * PX)
		pen.rect_flat(Rect2(r.position + Vector2(26, 22), r.size), Color(0.0, 0.01, 0.03, 0.4))
		pen.rect_flat(r, Color("6B7787"))
		pen.rect_flat(r.grow(-4.0), Color("8E9AA8"))
		var y := sr.position.y + 1.0
		while y + 2.44 <= sr.end.y - 0.8:
			var x := sr.position.x + 1.0
			while x + 6.0 <= sr.end.x - 0.8:
				idx += 1
				var h := LevelArt.hash01(idx, yard_seed)
				var len_m := 12.2 if h > 0.35 else 6.1
				if x + len_m > sr.end.x - 0.8:
					len_m = 6.1
				var col: Color = LevelArt.LIVERIES[int(h * 991.0) % LevelArt.LIVERIES.size()]["color"]
				if LevelArt.hash01(idx, yard_seed + 1) < 0.06:
					col = Color("2A3446")   # empty slot
				var cell := Rect2(Vector2(x, y) * PX, Vector2(len_m - 0.3, 2.14) * PX)
				pen.rect_flat(cell, col.darkened(0.5))
				pen.rect_flat(cell.grow(-1.2), col)
				x += len_m
			y += 2.44
		pen.polyline(OnFootArt.rect_poly(r), Color("DCE3EA"), 2.4, true)
		for c: Vector2 in [r.position + Vector2(15, 15), r.end - Vector2(15, 15)]:
			pen.circle(c, 10.0, Color(1.0, 0.69, 0.0, 0.18))
			pen.circle(c, 3.5, OnFootArt.AMBER)


func _free_boxes(pen: OnFootPainter) -> void:
	for b in _boxes:
		var s: Vector2 = b[1]
		var col: Color = b[2]
		var r := Rect2(-s * 0.5, s)
		pen.xf = b[0]
		pen.rect_flat(r.grow(5.0), Color(0, 0, 0.02, 0.3))
		pen.rect_flat(r, col.darkened(0.25))
		pen.rect_flat(r.grow(-2.0), col)
		var x := r.position.x + 5.0
		while x < r.end.x - 4.0:
			pen.line(Vector2(x, r.position.y + 3), Vector2(x, r.end.y - 3), col.darkened(0.3), 1.0, false)
			x += 4.0
	pen.set_transform()


## The slewing crane, boom along local +X (crane.gd, simplified).
func _crane(pen: OnFootPainter) -> void:
	var l := _crane_boom_m * PX
	var amber := Color("FFB000")
	var edge := Color("8A5E00")
	pen.set_transform(Yard.CRANE_PIVOT * PX + Vector2(20, 18), _crane_angle)
	pen.rect_flat(Rect2(-240, -60, l + 240, 120), Color(0.0, 0.01, 0.03, 0.3))
	pen.set_transform(Yard.CRANE_PIVOT * PX, _crane_angle)
	pen.rect(Rect2(40, -30, l - 40, 60), amber, edge, 3.0)
	pen.hazard(Rect2(80, -22, l - 250, 44), 16.0)
	pen.rect(Rect2(-240, -60, 180, 120), amber, edge, 3.0)
	pen.rect_flat(Rect2(-230, -50, 160, 100), Color("8E9AA8"))
	for i in 4:
		pen.polyline(OnFootArt.rect_poly(Rect2(-230 + i * 40, -50, 40, 100)), Color("5C6878"), 1.5, true)
	pen.circle(Vector2.ZERO, 80.0, amber, edge, 3.0, 32)
	pen.circle(Vector2.ZERO, 60.0, OnFootArt.NAVY, Color(0.7, 0.8, 0.9, 0.8), 2.0, 32)
	pen.rect_flat(Rect2(10, -45, 55, 35), Color("2C6A86"))
	# the spreader and the two boxes it carries
	pen.rect(Rect2(l - 160, -65, 130, 130), amber, edge, 3.0)
	pen.rect_flat(Rect2(l - 155, -61, 120, 59), Color("4EA8DE"))
	pen.rect_flat(Rect2(l - 155, 2, 120, 59), Color("E9EEF3"))
	pen.circle(Vector2(l - 15, 0), 5.0, OnFootArt.NAV_RED)
	pen.set_transform()
