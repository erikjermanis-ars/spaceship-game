@tool
class_name FrigateBerth
extends StationModule
## A frigate berth on the pier's east face.
##
## Local frame = the docked frigate's frame: the origin is where the ship's
## centre sits when it is clamped in, +X is its docked heading (bow), and
## the pier wall runs along local y = pier_dist_m * pier_side. That way the
## hardpoints in FrigateShape (generated with the art) line up by
## construction.
##
## What it builds:
##   * two heavy clamp pylons (colliding hull) reaching from the pier to 3.5 m
##     off the hull's hardpoints: one on the primary hull's rim, one on the
##     outer face of the nacelle, so their lengths differ;
##   * animated clamp arms: a hydraulic ram telescopes out to the hardpoint
##     and two jaws close over it (driven by the ship's FrigateDock.clamp_t);
##   * the personnel gangway, the third, lighter pylon: a telescoping tube on
##     a slim truss that runs out overhead to the airlock once the ship is
##     hard-docked, and folds back into its housing on the pier to undock;
##   * approach guidance for the pilot: the berth's ghost outline, the
##     centre line, the capture box and where the ship's centre is now;
##   * `occupied_static`: a parked frigate that never leaves (the HALCYON):
##     same art, static collision, clamps and gangway shown connected.

@export var berth_id := "E2":
	set(v): berth_id = v; queue_rebuild()
## +1: the ship's starboard faces the pier, -1: its port side.
@export var pier_side := 1.0:
	set(v): pier_side = signf(v) if v != 0.0 else 1.0; queue_rebuild()
## Distance (m) from the ship's centre line to the pier wall.
@export var pier_dist_m := 71.0:
	set(v): pier_dist_m = v; queue_rebuild()
@export var occupied_static := false:
	set(v): occupied_static = v; queue_rebuild()
@export var static_name := "HALCYON":
	set(v): static_name = v; queue_rebuild()
@export var static_registry := "MFF-04":
	set(v): static_registry = v; queue_rebuild()
@export var static_livery := Color("E76F51"):
	set(v): static_livery = v; queue_rebuild()

const GAP_M := 3.5            ## pylon tip to the hull hardpoint
const STOWED_GANGWAY_M := 7.0

## The FrigateShip that uses this berth (it registers itself).
var ship: Node2D

var _clamps: Node2D
var _gangway: Node2D
var _gangway_shadow: Node2D
var _guide: Node2D
var _clamp_t := -1.0
var _gang_t := -1.0
var _t := 0.0
var _blink_acc := 0.0


func _ready() -> void:
	super._ready()
	if not Engine.is_editor_hint():
		add_to_group(&"frigate_berth")


## Where the ship's centre sits when clamped in, and its heading.
func docked_transform() -> Transform2D:
	return Transform2D(global_rotation, global_position)


func _hp(v: Vector2) -> Vector2:
	return Vector2(v.x, v.y * pier_side)


# ==================================================================== build

func _build() -> void:
	var s := pier_side
	var D := Band.STRUCT_DETAIL
	for h: Vector2 in [FrigateShape.CLAMP_FWD, FrigateShape.CLAMP_AFT]:
		_pylon(h, s, D)
	# Gangway housing on the pier wall (the gangway folds into it).
	var a: Vector2 = FrigateShape.AIRLOCK
	var house := _rect(a.x - 4.5, pier_dist_m - 6.0, a.x + 4.5, pier_dist_m + 1.0)
	hull(house, &"grey", [house], {"bevel": 0.5})
	fill(D, _rect(a.x - 2.6, pier_dist_m - 5.4, a.x + 2.6, pier_dist_m - 1.0), Color("2B3440"))
	hazard(D, _rect(a.x - 3.8, pier_dist_m - 6.0, a.x + 3.8, pier_dist_m - 5.2), 0.7)
	lamp(_pt(a.x - 3.6, pier_dist_m - 3.0), A.CYAN, 26.0)
	lamp(_pt(a.x + 3.6, pier_dist_m - 3.0), A.CYAN, 26.0)
	if occupied_static:
		for key: String in FrigateShape.PARTS:
			var poly := PackedVector2Array(FrigateShape.PARTS[key])
			pieces.append(poly)
		radar_polys.append(PackedVector2Array(FrigateShape.PARTS["primary"]))
		radar_polys.append(PackedVector2Array(FrigateShape.PARTS["secondary"]))
		radar_polys.append(PackedVector2Array(FrigateShape.PARTS["nacelle_s"]))
		radar_polys.append(PackedVector2Array(FrigateShape.PARTS["nacelle_p"]))
		solids.append(PackedVector2Array(FrigateShape.PARTS["primary"]))


## A heavy clamp pylon from the pier to GAP_M off hardpoint `h` (m).
func _pylon(h: Vector2, s: float, D: int) -> void:
	var tip := absf(h.y) + GAP_M
	var arm := _rect(h.x - 3.6, tip + 4.5, h.x + 3.6, pier_dist_m + 1.0)
	var head := _rect(h.x - 6.5, tip, h.x + 6.5, tip + 5.0)
	var base := _rect(h.x - 8.5, pier_dist_m - 9.0, h.x + 8.5, pier_dist_m + 1.0)
	var outline := union(union(arm, head), base)
	hull(outline, &"pearl", [arm, head, base], {"bevel": 0.9})
	radar_polys.append(_rect(h.x - 4.0, tip, h.x + 4.0, pier_dist_m))
	# structure: navy spine, hydraulic lines, ribs
	fill(D, _rect(h.x - 1.0, tip + 5.5, h.x + 1.0, pier_dist_m - 9.5), A.NAVY)
	fill(D, _rect(h.x - 0.35, tip + 5.5, h.x + 0.35, pier_dist_m - 9.5), A.TEAL)
	for side_x: float in [-2.6, 2.6]:
		line(D, _pt(h.x + side_x, tip + 5.0), _pt(h.x + side_x, pier_dist_m - 9.0), Color("8E9AA8"), 3.0)
		line(D, _pt(h.x + side_x, tip + 5.0), _pt(h.x + side_x, pier_dist_m - 9.0), Color("FFB000", 0.6), 1.0)
	var y := tip + 8.0
	while y < pier_dist_m - 10.0:
		seam(D, _pt(h.x - 3.4, y), _pt(h.x + 3.4, y))
		y += 4.0
	# label plate, readable from the approach (the arms run across the screen)
	var mid := (tip + 5.0 + pier_dist_m - 9.0) * 0.5
	fill(D, _rect(h.x - 1.9, mid - 9.0, h.x + 1.9, mid + 9.0), A.NAVY)
	text(D, _pt(h.x, mid), "BERTH %s  %s" % [berth_id, "FWD" if h.x > 0.0 else "AFT"], 24, A.PEARL, -rotation)
	# hydraulic ram housing on the head + hazard face toward the ship
	fill(D, _rect(h.x - 2.0, tip + 0.8, h.x + 2.0, tip + 4.6), Color("5C6878"))
	hazard(D, _rect(h.x - 6.0, tip + 0.2, h.x - 2.4, tip + 4.6), 0.8)
	hazard(D, _rect(h.x + 2.4, tip + 0.2, h.x + 6.0, tip + 4.6), 0.8)
	# hydraulic base (machinery block at the pier)
	fill(D, _rect(h.x - 6.5, pier_dist_m - 8.0, h.x + 6.5, pier_dist_m - 2.0), Color("C9D2DC"))
	for k in 5:
		var x := h.x - 5.0 + k * 2.5
		fill(D, _rect(x - 0.6, pier_dist_m - 7.2, x + 0.6, pier_dist_m - 2.8), Color("8E9AA8"))
	# floodlights aimed at the hull + corner lamps
	glow(_pt(h.x, tip - 3.0), Color(1.0, 0.95, 0.85, 0.12), 160.0)
	lamp(_pt(h.x - 6.0, tip + 0.6), A.AMBER, 30.0)
	lamp(_pt(h.x + 6.0, tip + 0.6), A.AMBER, 30.0)
	beacon(_pt(h.x, pier_dist_m - 5.0), A.AMBER, 70.0, 0.3 if h.x > 0.0 else 0.8)


func _pt(x: float, y_abs: float) -> Vector2:
	return Vector2(x, y_abs * pier_side) * PX


func _rect(x0: float, y0: float, x1: float, y1: float) -> PackedVector2Array:
	return A.rect_m(x0, minf(y0 * pier_side, y1 * pier_side), x1, maxf(y0 * pier_side, y1 * pier_side))


func _after_build() -> void:
	_clamps = _layer("Clamps", G.Z_STRUCTURE + 2, _draw_clamps)
	_gangway_shadow = _layer("GangwayShadow", G.Z_OVERHEAD - 1, _draw_gangway_shadow)
	_gangway = _layer("Gangway", G.Z_OVERHEAD, _draw_gangway)
	_guide = _layer("Guide", G.Z_FX, _draw_guide)
	_guide.material = A.add_material()
	_guide.visible = false
	if not Engine.is_editor_hint():
		A.depth_layers.append([_gangway, A.OVER_SCALE, Vector2.ZERO])
		A.depth_layers.append([_gangway_shadow, 1.0, A.OVER_SHADOW_OFFSET])
	if occupied_static:
		_build_occupant()


func _layer(n: String, z: int, cb: Callable) -> Node2D:
	var ci := Node2D.new()
	ci.name = n
	ci.z_as_relative = false
	ci.z_index = z
	ci.draw.connect(cb)
	add_child(ci)
	_generated.append(ci)
	return ci


## A parked frigate that never leaves: the ship's art layers plus a static
## glow pass (drive asleep, windows lit).
func _build_occupant() -> void:
	var root := Node2D.new()
	root.name = "Occupant"
	root.z_as_relative = false
	root.z_index = G.Z_SHIP
	add_child(root)
	_generated.append(root)
	var shadow := _sprite(root, "res://assets/art/ship/frigate_hull.svg", 0.5, Color(0, 0.01, 0.03, 0.34))
	shadow.z_as_relative = false
	shadow.z_index = G.Z_BELOW_DECK + 4
	shadow.position = Vector2(26.0, 40.0).rotated(-rotation)
	_sprite(root, "res://assets/art/ship/frigate_hull.svg", 0.5, Color.WHITE)
	_sprite(root, "res://assets/art/ship/frigate_livery.svg", 1.0, static_livery)
	var lights := _sprite(root, "res://assets/art/ship/frigate_lights.svg", 1.0, Color.WHITE)
	lights.material = A.add_material()
	var deco := Node2D.new()
	deco.draw.connect(_draw_occupant.bind(deco))
	root.add_child(deco)
	var glow_node := Node2D.new()
	glow_node.material = A.add_material()
	glow_node.draw.connect(_draw_occupant_glow.bind(glow_node))
	root.add_child(glow_node)


func _sprite(parent: Node, path: String, scl: float, mod: Color) -> Sprite2D:
	var sp := Sprite2D.new()
	if ResourceLoader.exists(path):
		sp.texture = load(path)
	sp.scale = Vector2.ONE * scl
	sp.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sp.modulate = mod
	parent.add_child(sp)
	return sp


func _draw_occupant(ci: Node2D) -> void:
	var f := A.font()
	var col := Color(0.11, 0.21, 0.34, 0.82)
	ci.draw_set_transform(Vector2(240, 132), 0.0)
	ci.draw_string(f, Vector2.ZERO, " ".join(static_name.split("")), HORIZONTAL_ALIGNMENT_CENTER, 300, 30, col)
	ci.draw_set_transform(Vector2(240, -112), 0.0)
	ci.draw_string(f, Vector2.ZERO, static_registry, HORIZONTAL_ALIGNMENT_CENTER, 300, 30, col)
	ci.draw_set_transform(Vector2.ZERO)


func _draw_occupant_glow(ci: Node2D) -> void:
	var g := A.glow_texture()
	var dim := Color(0.35, 0.65, 1.0, 0.18)
	for s: float in [-1.0, 1.0]:
		var cy := FrigateShape.NACELLE_Y * s * PX
		ci.draw_rect(Rect2(Vector2(FrigateShape.GRILLE_X.x * PX, cy - 10.0), Vector2((FrigateShape.GRILLE_X.y - FrigateShape.GRILLE_X.x) * PX, 20.0)), dim)
		var b := Vector2(FrigateShape.BUSSARD_X, FrigateShape.NACELLE_Y * s) * PX
		ci.draw_texture_rect(g, Rect2(b - Vector2(70, 70), Vector2(140, 140)), false, Color(0.35, 0.7, 1.0, 0.35))
		for y: float in FrigateShape.IMPULSE_Y:
			var p := Vector2(FrigateShape.IMPULSE_X, y * s) * PX
			ci.draw_texture_rect(g, Rect2(p - Vector2(30, 30), Vector2(60, 60)), false, Color(1.0, 0.35, 0.15, 0.25))


# ================================================================ per frame

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_t += delta
	var ct := 1.0
	var gt := 1.0
	var live_ship := ship != null and is_instance_valid(ship)
	if live_ship:
		var dk: FrigateDock = ship.get(&"dock")
		ct = dk.clamp_t
		gt = dk.gangway_t
		if not bool(ship.get(&"alive")):
			ct = 0.0
			gt = 0.0
	elif not occupied_static:
		ct = 0.0
		gt = 0.0
	var moving_parts := absf(ct - _clamp_t) > 0.0005 or absf(gt - _gang_t) > 0.0005
	_blink_acc += delta
	var in_motion := (ct > 0.0 and ct < 1.0) or (gt > 0.0 and gt < 1.0)
	if moving_parts or (in_motion and _blink_acc > 0.1):
		_blink_acc = 0.0
		_clamp_t = ct
		_gang_t = gt
		_clamps.queue_redraw()
		_gangway.queue_redraw()
		_gangway_shadow.queue_redraw()
	# Guidance: only for the pilot of this berth's frigate, while approaching.
	var guide := false
	if live_ship and ship == Game.player and bool(ship.get(&"alive")):
		var dk: FrigateDock = ship.get(&"dock")
		guide = dk.in_range and dk.state == FrigateDock.State.FREE
	_guide.visible = guide
	if guide:
		_guide.queue_redraw()


# ================================================================== drawing

func _draw_clamps() -> void:
	var pen := OnFootPainter.new(_clamps, 0.9)
	var t := maxf(_clamp_t, 0.0)
	var ext := smoothstep(0.0, 0.6, t)
	var close := smoothstep(0.55, 1.0, t)
	for h: Vector2 in [FrigateShape.CLAMP_FWD, FrigateShape.CLAMP_AFT]:
		var s := pier_side
		var hy := absf(h.y)
		var tip := hy + GAP_M
		var reach := lerpf(tip, hy + 0.35, ext)
		# hydraulic ram (two telescoping stages)
		var r1 := Rect2(Vector2(h.x - 1.3, minf(tip * s, reach * s)) * PX, Vector2(2.6, absf(tip - reach)) * PX)
		pen.rect(r1, Color("8E9AA8"), Color(0.04, 0.06, 0.1, 0.9), 1.2)
		pen.rect(Rect2(r1.position + Vector2(5, 0), Vector2(16, r1.size.y)), Color("C9D2DC"))
		# cradle across the hardpoint, with two jaws that swing shut over it
		var cy := reach * s * PX
		var cr := Rect2(Vector2((h.x - 2.4) * PX, cy - (8.0 if s > 0 else 6.0)), Vector2(48.0, 14.0))
		pen.rect(cr, Color("5C6878"), Color(0.04, 0.06, 0.1, 0.9), 1.2)
		for j: float in [-1.0, 1.0]:
			var pivot := Vector2((h.x + 2.2 * j) * PX, cy)
			var ang := lerpf(0.95, 0.0, close) * j * s
			var dir := Vector2(0.0, -s).rotated(ang)
			var jaw := PackedVector2Array([pivot + dir.orthogonal() * 6.0, pivot + dir * 22.0 + dir.orthogonal() * 3.0,
				pivot + dir * 22.0 - dir.orthogonal() * 3.0 - Vector2(j * 10.0, 0), pivot - dir.orthogonal() * 6.0])
			pen.fill(jaw, Color("FFB000"))
			pen.polyline(jaw, Color(0.04, 0.06, 0.1, 0.9), 1.2, true)
		# status lamp: cyan ready, amber blinking while moving, green locked
		var col := Color(0.5, 0.9, 1.0, 0.9)
		if t >= 0.999:
			col = Color(0.3, 1.0, 0.5)
		elif t > 0.001:
			col = Color(1.0, 0.7, 0.0) if fmod(_t, 0.5) < 0.3 else Color(0.4, 0.28, 0.0)
		pen.circle(Vector2(h.x * PX, (tip + 2.6) * s * PX), 5.0, col)
	pen.flush()


## Gangway: a 4-stage telescoping tube on a slim truss (the lighter pylon).
func _gangway_geom() -> Array:
	var a: Vector2 = FrigateShape.AIRLOCK
	var p0 := pier_dist_m - 1.0
	var p1 := a.y + 0.2
	var full := p0 - p1
	var cur := lerpf(STOWED_GANGWAY_M, full, smoothstep(0.0, 1.0, maxf(_gang_t, 0.0)))
	var segs: Array = []
	for i in 4:
		var w := 3.8 - i * 0.25
		var y0 := p0 - cur * float(i) / 4.0 + (0.6 if i > 0 else 0.0)
		var y1 := p0 - cur * float(i + 1) / 4.0
		segs.append([a.x, y0, y1, w])
	return segs


func _draw_gangway() -> void:
	var pen := OnFootPainter.new(_gangway, 0.9)
	var s := pier_side
	var segs := _gangway_geom()
	var a: Vector2 = FrigateShape.AIRLOCK
	var end_y: float = segs[3][2]
	# the support truss (narrow, under the tube)
	var tr := Rect2(Vector2((a.x - 2.6) * PX, minf(end_y * s, (pier_dist_m - 1.0) * s) * PX), Vector2(5.2, absf(pier_dist_m - 1.0 - end_y)) * PX)
	pen.rect(tr, Color(0.6, 0.68, 0.78, 0.35))
	for seg in segs:
		var x: float = seg[0]
		var y0: float = seg[1]
		var y1: float = seg[2]
		var w: float = seg[3]
		var r := Rect2(Vector2((x - w * 0.5) * PX, minf(y0 * s, y1 * s) * PX), Vector2(w, absf(y0 - y1)) * PX)
		pen.rect(r, Color(0.9, 0.93, 0.97, 0.88), Color(0.3, 0.38, 0.5, 0.6), 1.0)
		pen.rect_flat(Rect2(Vector2(r.position.x + 3.0, r.position.y), Vector2(4.0, r.size.y)), Color(0.11, 0.21, 0.34, 0.75))
		# windows along the tube
		var yy := minf(y0, y1) + 1.0
		while yy < maxf(y0, y1) - 0.8:
			pen.rect_flat(Rect2(Vector2(r.end.x - 9.0, yy * s * PX - 3.0), Vector2(5.0, 6.0)), Color(1.0, 0.88, 0.62, 0.9))
			yy += 1.6
		# ring frame at the segment's outer end
		pen.rect_flat(Rect2(Vector2(r.position.x - 3.0, y1 * s * PX - 4.0), Vector2(r.size.x + 6.0, 8.0)), Color(0.55, 0.62, 0.72, 0.9))
	# docking collar on the hull: amber while sealing, green when sealed
	if _gang_t > 0.98:
		var c := Vector2(a.x * PX, (a.y + 0.2) * s * PX)
		pen.rect(Rect2(c - Vector2(30, 8), Vector2(60, 16)), Color(0.3, 1.0, 0.5, 0.85), Color(0.04, 0.06, 0.1, 0.8), 1.0)
	elif _gang_t > 0.0:
		var c := Vector2(a.x * PX, end_y * s * PX)
		var on := fmod(_t, 0.5) < 0.3
		pen.circle(c, 6.0, Color(1.0, 0.7, 0.0, 0.95 if on else 0.3))
	pen.flush()


func _draw_gangway_shadow() -> void:
	var pen := OnFootPainter.new(_gangway_shadow, 0.9)
	var s := pier_side
	for seg in _gangway_geom():
		var x: float = seg[0]
		var w: float = seg[3]
		var y0: float = seg[1]
		var y1: float = seg[2]
		pen.rect_flat(Rect2(Vector2((x - w * 0.5) * PX, minf(y0 * s, y1 * s) * PX), Vector2(w, absf(y0 - y1)) * PX), A.OVER_SHADOW)
	pen.flush()


## Approach guidance (additive): ghost berth outline, centre line, the
## capture box and the ship's centre relative to it.
func _draw_guide() -> void:
	if ship == null or not is_instance_valid(ship):
		return
	var dk: FrigateDock = ship.get(&"dock")
	var pen := OnFootPainter.new(_guide, 1.2)
	var ok := dk.hint == "" and dk.in_box
	var col := Color(0.3, 1.0, 0.5, 0.8) if ok else Color(0.5, 0.9, 1.0, 0.55)
	# ghost of the docked hull
	for key: String in FrigateShape.PARTS:
		var poly := PackedVector2Array(FrigateShape.PARTS[key])
		pen.polyline(poly, Color(col, 0.22), 2.0, true)
	# centre line, dashed, along the berth axis
	var x := -2400.0
	while x < 2400.0:
		pen.line(Vector2(x, 0), Vector2(x + 50.0, 0), Color(col, 0.3), 2.0)
		x += 100.0
	# capture box (ship centre must be inside)
	var s := pier_side
	var y_in := FrigateDock.BOX_IN * s
	var y_out := -FrigateDock.BOX_OUT * s
	var box := Rect2(Vector2(-FrigateDock.BOX_AXIAL, minf(y_in, y_out)) * PX, Vector2(FrigateDock.BOX_AXIAL * 2.0, FrigateDock.BOX_IN + FrigateDock.BOX_OUT) * PX)
	pen.polyline(OnFootArt.rect_poly(box), col, 3.0, true)
	if dk.hold > 0.0:
		pen.arc(Vector2.ZERO, 90.0, -PI * 0.5, -PI * 0.5 + TAU * dk.hold, Color(0.3, 1.0, 0.5, 0.9), 6.0, 40)
	# where the ship's centre is, and its heading
	var p := to_local(ship.global_position)
	var hd := Vector2.from_angle(ship.global_rotation - global_rotation)
	pen.circle(p, 9.0, Color(1.0, 0.85, 0.4, 0.9))
	pen.line(p, p + hd * 60.0, Color(1.0, 0.85, 0.4, 0.8), 3.0)
	pen.line(p, Vector2.ZERO, Color(1.0, 0.85, 0.4, 0.35), 2.0)
	pen.flush()
