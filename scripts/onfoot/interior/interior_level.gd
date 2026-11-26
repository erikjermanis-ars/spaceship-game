@tool
class_name InteriorLevel
extends Node2D
## Root of an interior scene ("level"). Loaded by the OnFootDirector when you
## go through a door, and freed again when you leave.
##
## Authoring: drop InteriorRoom nodes (rectangles that share edges where they
## touch), SlidingDoor nodes on the shared edges, InteriorWindow nodes on wall
## lines, then furniture / lights / switches. On load this script builds the
## WALLS automatically from the room edges:
##   * merges shared edges, cuts gaps for doors and windows,
##   * outer edges become the thick hull, inner edges thin partitions,
##   * one StaticBody2D with a rectangle per wall (walker collision),
##   * a LightOccluder2D per wall (the flashlight casts shadows),
##   * wall tops drawn once into a cached canvas item above the walker.
## So a new room is one node, not hand-placed wall pieces.
##
## Lighting: a CanvasModulate darkens everything (`ambient`); RoomLights,
## lamps, screens and the flashlight add light back. Anything emissive uses
## an unshaded material.
##
## State (lights, shutters, stock...) is saved by the director when you leave
## and restored when you come back: nodes in group `persist` implement
## save_state() / load_state().

@export var interior_name := "Interior"
@export var ambient := Color(0.12, 0.14, 0.19)
@export var hull_thickness_m := 1.0
@export var wall_thickness_m := 0.3
@export var room_tone := "room_tone_loop.wav"
@export var room_tone_db := -17.0
## Music bed offset while inside (dB), so the room tone carries the space.
@export var music_offset_db := -6.0
@export var airlock: NodePath = ^"Airlock"

const WALL_TOP := Color("2E3846")
const WALL_EDGE := Color("6E829B")
const HULL_TOP := Color("C9D2DC")
const HULL_EDGE := Color("F4F7FA")

## [Rect2 (local px), is_hull, is_window]
var walls: Array = []
var _tone: AudioStreamPlayer
var _tops: Node2D
var _shadows: Node2D


## Batched painter used by the draw callbacks (see OnFootPainter).
var pen: OnFootPainter

func _ready() -> void:
	if Engine.is_editor_hint():
		_build_walls()
		_make_wall_nodes(false)
		return
	var cm := CanvasModulate.new()
	cm.color = ambient
	add_child(cm)
	_build_walls()
	_make_wall_nodes(true)
	var s := GameplayUtil.load_loop(room_tone)
	if s:
		_tone = GameplayUtil.make_player(self, s, &"Ambient", -50.0)
		_tone.play()
		create_tween().tween_property(_tone, ^"volume_db", room_tone_db, 1.5)


func get_airlock() -> Node:
	return get_node_or_null(airlock)


# ----------------------------------------------------------------- state --

func save_state() -> Dictionary:
	var d := {}
	for n in get_tree().get_nodes_in_group(&"persist"):
		if is_ancestor_of(n) and n.has_method(&"save_state"):
			d[str(get_path_to(n))] = n.call(&"save_state")
	return d


func load_state(d: Dictionary) -> void:
	for key in d:
		var n := get_node_or_null(NodePath(key))
		if n and n.has_method(&"load_state"):
			n.call(&"load_state", d[key])


# ----------------------------------------------------------------- walls --

func _collect(cls: String) -> Array:
	var out: Array = []
	for n in find_children("*", cls, true, false):
		out.append(n)
	return out


func _build_walls() -> void:
	walls.clear()
	var rooms: Array = []
	for n in find_children("*", "Node2D", true, false):
		if n is InteriorRoom:
			rooms.append(n)
	if rooms.is_empty():
		return
	var px := OnFootArt.PX
	var hull := hull_thickness_m * px
	var thin := wall_thickness_m * px
	# 1. room edges grouped by line
	var hlines := {}   # y -> [[x0, x1], ...]
	var vlines := {}   # x -> [[y0, y1], ...]
	var bbox := Rect2()
	var first := true
	for room: InteriorRoom in rooms:
		var r := Rect2(_local(room), room.size_m * px)
		bbox = r if first else bbox.merge(r)
		first = false
		_add(hlines, r.position.y, r.position.x, r.end.x)
		_add(hlines, r.end.y, r.position.x, r.end.x)
		_add(vlines, r.position.x, r.position.y, r.end.y)
		_add(vlines, r.end.x, r.position.y, r.end.y)
	# 2. gaps: doors cut everything, windows only cut the drawing/occluders
	var door_cuts := {"h": {}, "v": {}}
	var win_cuts := {"h": {}, "v": {}}
	for n in find_children("*", "Node2D", true, false):
		if n is SlidingDoor:
			var d: SlidingDoor = n
			_cut_for(door_cuts, _local(d), d.global_rotation - global_rotation, d.width_m * px)
		elif n is InteriorWindow:
			var w: InteriorWindow = n
			_cut_for(win_cuts, _local(w), w.global_rotation - global_rotation, w.length_m * px)
	# 3. merge, extend into corners, subtract gaps -> wall rects
	for y in hlines:
		var is_hull := absf(y - bbox.position.y) < 0.5 or absf(y - bbox.end.y) < 0.5
		var t := hull if is_hull else thin
		var ext := hull if is_hull else thin * 0.5
		for iv in _merge(hlines[y]):
			var spans := _subtract([[iv[0] - ext, iv[1] + ext]], _cuts_at(door_cuts.h, y, t))
			for sp in spans:
				for piece in _split(sp, _cuts_at(win_cuts.h, y, t)):
					var y0: float = y - (t if is_hull and absf(y - bbox.position.y) < 0.5 else (0.0 if is_hull else t * 0.5))
					walls.append([Rect2(Vector2(piece[0], y0), Vector2(piece[1] - piece[0], t)), is_hull, piece[2]])
	for x in vlines:
		var is_hull := absf(x - bbox.position.x) < 0.5 or absf(x - bbox.end.x) < 0.5
		var t := hull if is_hull else thin
		for iv in _merge(vlines[x]):
			var spans := _subtract([[iv[0], iv[1]]], _cuts_at(door_cuts.v, x, t))
			for sp in spans:
				for piece in _split(sp, _cuts_at(win_cuts.v, x, t)):
					var x0: float = x - (t if is_hull and absf(x - bbox.position.x) < 0.5 else (0.0 if is_hull else t * 0.5))
					walls.append([Rect2(Vector2(x0, piece[0]), Vector2(t, piece[1] - piece[0])), is_hull, piece[2]])


func _local(n: Node2D) -> Vector2:
	return (global_transform.affine_inverse() * n.global_transform).origin


func _add(lines: Dictionary, key: float, a: float, b: float) -> void:
	var k := snappedf(key, 0.01)
	if not lines.has(k):
		lines[k] = []
	lines[k].append([minf(a, b), maxf(a, b)])


## A gap of `w` centred on `p`; a node rotated ~0 spans local Y -> sits on a
## vertical wall line; rotated ~90° -> horizontal line.
func _cut_for(cuts: Dictionary, p: Vector2, rot: float, w: float) -> void:
	var vertical := absf(sin(rot)) < 0.5
	if vertical:
		_add(cuts.v, p.x, p.y - w * 0.5, p.y + w * 0.5)
	else:
		_add(cuts.h, p.y, p.x - w * 0.5, p.x + w * 0.5)


## Gaps on the wall line at `key`; a door/window may sit anywhere within the
## wall's thickness (e.g. a hatch centred in the 1 m hull).
func _cuts_at(cuts: Dictionary, key: float, thickness: float) -> Array:
	var out: Array = []
	for k in cuts:
		if absf(float(k) - key) <= thickness + 0.5:
			out.append_array(cuts[k])
	return out


func _merge(ivs: Array) -> Array:
	var s := ivs.duplicate()
	s.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var out: Array = []
	for iv in s:
		if not out.is_empty() and iv[0] <= out[-1][1] + 0.01:
			out[-1][1] = maxf(out[-1][1], iv[1])
		else:
			out.append([iv[0], iv[1]])
	return out


func _subtract(spans: Array, cuts: Array) -> Array:
	var out := spans
	for c in cuts:
		var next: Array = []
		for sp in out:
			if c[1] <= sp[0] or c[0] >= sp[1]:
				next.append(sp)
				continue
			if c[0] > sp[0] + 0.01:
				next.append([sp[0], c[0]])
			if c[1] < sp[1] - 0.01:
				next.append([c[1], sp[1]])
		out = next
	return out


## Splits a span into [a, b, is_window] pieces at window cuts.
func _split(sp: Array, wins: Array) -> Array:
	var solid := _subtract([sp], wins)
	var out: Array = []
	for s in solid:
		out.append([s[0], s[1], false])
	for w in wins:
		var a := maxf(w[0], sp[0])
		var b := minf(w[1], sp[1])
		if b > a + 0.01:
			out.append([a, b, true])
	return out


func _make_wall_nodes(runtime: bool) -> void:
	for n in [_tops, _shadows]:
		if n and is_instance_valid(n):
			n.queue_free()
	_shadows = Node2D.new()
	_shadows.name = "WallShadows"
	_shadows.z_as_relative = false
	_shadows.z_index = -3
	_shadows.draw.connect(_draw_shadows)
	add_child(_shadows)
	_tops = Node2D.new()
	_tops.name = "WallTops"
	_tops.z_as_relative = false
	_tops.z_index = Game.Z_WALL_TOP if runtime else 12
	if runtime:
		_tops.material = OnFootArt.unshaded()
	_tops.draw.connect(_draw_tops)
	add_child(_tops)
	if not runtime:
		return
	var body := StaticBody2D.new()
	body.name = "Walls"
	body.collision_layer = Game.LAYER_WALK
	body.collision_mask = 0
	add_child(body)
	for w in walls:
		var r: Rect2 = w[0]
		var cs := CollisionShape2D.new()
		var rs := RectangleShape2D.new()
		rs.size = r.size
		cs.shape = rs
		cs.position = r.get_center()
		body.add_child(cs)
		if not w[2]:
			var occ := LightOccluder2D.new()
			var op := OccluderPolygon2D.new()
			op.polygon = OnFootArt.rect_poly(r)
			occ.occluder = op
			add_child(occ)


func _draw_shadows() -> void:
	pen = OnFootPainter.new(_shadows)
	_paint_draw_shadows()
	pen.flush()


func _paint_draw_shadows() -> void:
	var o := Vector2(0.6, 1.0)
	for w in walls:
		if w[2]:
			continue
		var r: Rect2 = w[0]
		pen.rect_flat(Rect2(r.position + o, r.size), Color(0, 0.01, 0.03, 0.35))
		pen.rect_flat(Rect2(r.position + o * 2.2, r.size), Color(0, 0.01, 0.03, 0.12))


func _draw_tops() -> void:
	pen = OnFootPainter.new(_tops)
	_paint_draw_tops()
	pen.flush()


func _paint_draw_tops() -> void:
	for w in walls:
		if w[2]:
			continue
		var r: Rect2 = w[0]
		if w[1]:
			pen.rect_flat(r, HULL_TOP)
			# panel seams across the hull every 3 m
			var horiz := r.size.x > r.size.y
			var ln := r.size.x if horiz else r.size.y
			var k := 30.0
			var s := fposmod(-(r.position.x if horiz else r.position.y), k)
			while s < ln:
				if horiz:
					pen.line(Vector2(r.position.x + s, r.position.y + 0.8), Vector2(r.position.x + s, r.end.y - 0.8), Color("98A4B3"), 0.2)
				else:
					pen.line(Vector2(r.position.x + 0.8, r.position.y + s), Vector2(r.end.x - 0.8, r.position.y + s), Color("98A4B3"), 0.2)
				s += k
			pen.polyline(OnFootArt.rect_poly(r), Color("8E9AA8"), 0.2, true)
		else:
			pen.rect_flat(r, WALL_TOP)
			pen.line(r.position, Vector2(r.end.x, r.position.y), WALL_EDGE, 0.16)
			pen.line(r.position, Vector2(r.position.x, r.end.y), WALL_EDGE, 0.16)
