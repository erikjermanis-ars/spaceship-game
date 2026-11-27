@tool
class_name FrigateDeck
extends InteriorLevel
## A frigate's main deck (an InteriorLevel placed wherever the ship is,
## north-up: bow = up). The rooms sit at their TRUE positions inside the hull
## (1 m = 1 m), so the deck plan follows the ship's shape: a ready room in the
## prow, the bridge behind it, cabins either side of the spine corridor where
## the hull is widest, Engineering at the waist and the flight deck in the
## stern between the two engine arms.
##
## Ship metres (bow +X, starboard +Y) map onto the deck as
##     deck px = Vector2(y, -x) * 10        (see to_deck / to_ship)
##
## Besides the usual room/wall build it ties the interior to the ship's real
## state, read once when you come aboard (the world is suspended while you're
## inside, so it can't change under you):
##   * the HULL around the rooms: the ship's own outline and both drive
##     rings, drawn under the deck plan as a cut-away;
##   * the FLIGHT DECK: pad markings, and every small ship that is parked on
##     the real deck, shown as its detailed landed model in the same place.
##     E at its hatch boards it (OnFootDirector.board_stowed);
##   * RED ALERT: the room lights and the ambient darkness pulse red;
##   * each room belongs to a hull section (by where it is on the deck); a
##     badly hurt section has failing lights that stutter and sparks spitting
##     from damaged conduits.

const PX := 10.0
## Ship frame -> deck frame (bow up).
const DECK_XF := Transform2D(Vector2(0, -1), Vector2(1, 0), Vector2.ZERO)
const HULL_FILL := Color("39444F")
const HULL_RIB := Color("4A5766")
const HULL_SKIN := Color("E9EEF3")
const RING_FILL := Color("8794A5")

var _ship: FrigateShip
var _cm: CanvasModulate
var _alert := false
var _t := 0.0
var _sparks: Array = []          ## [CPUParticles2D, Rect2 (local), next_t, integrity]
var _lights: Array[RoomLight] = []
## PlayerShip -> its landed model on the flight deck.
var _stowed := {}


static func to_deck(ship_m: Vector2) -> Vector2:
	return Vector2(ship_m.y, -ship_m.x) * PX


static func to_ship(deck_px: Vector2) -> Vector2:
	return Vector2(-deck_px.y, deck_px.x) / PX


func _ready() -> void:
	super._ready()
	_build_hull()
	if Engine.is_editor_hint():
		return
	_ship = FrigateShip.aboard
	for c in get_children():
		if c is CanvasModulate:
			_cm = c
	if _ship == null:
		return
	interior_name = "%s  ·  Main deck" % _ship.vehicle_name
	_alert = _ship.red_alert
	for l in find_children("*", "RoomLight", true, false):
		_lights.append(l as RoomLight)
	for n in find_children("*", "InteriorRoom", true, false):
		var room := n as InteriorRoom
		var r := Rect2(room.position, room.size_m * OnFootArt.PX)
		var integ := _ship.damage.integrity[section_of(r.get_center())]
		if integ < 60.0:
			_damage_room(r, integ)
	_build_stowed()


## Which hull section a deck position (local px) belongs to.
static func section_of(p: Vector2) -> int:
	return FrigateDamage.section_at(to_ship(p))


# ================================================================ the hull

## The ship around the rooms: hull structure, skin line and the drive rings.
func _build_hull() -> void:
	var hull := Node2D.new()
	hull.name = "HullPlan"
	hull.z_as_relative = false
	hull.z_index = -9
	if not Engine.is_editor_hint():
		hull.material = OnFootArt.unshaded()
	hull.draw.connect(_draw_hull.bind(hull))
	add_child(hull)
	var deck := Node2D.new()
	deck.name = "DeckMarkings"
	deck.z_as_relative = false
	deck.z_index = -3
	deck.draw.connect(_draw_deck_markings.bind(deck))
	add_child(deck)


func _map(src: Array, mirror := false) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v: Vector2 in src:
		out.append(Vector2(-v.y if mirror else v.y, -v.x))
	return out


func _draw_hull(ci: Node2D) -> void:
	var pen := OnFootPainter.new(ci, 0.3)
	_paint_berth(pen)
	# drive rings and their pylons (outside the pressure hull: seen from above)
	for mirror: bool in [false, true]:
		for k in 2:
			pen.poly(_map(FrigateShape.PARTS["pylon_s%d" % k], mirror), Color("A5B1BF"), Color("3E4A5A"), 0.25)
		var o := _map(FrigateShape.RING_OUTER, mirror)
		var i := _map(FrigateShape.RING_INNER, mirror)
		var n := o.size()
		for k in n:
			pen.fill(PackedVector2Array([o[k], o[(k + 1) % n], i[(k + 1) % n], i[k]]), RING_FILL, false)
		var mid := PackedVector2Array()
		for v: Vector2 in FrigateShape.RING_MID:
			mid.append(Vector2(-v.y if mirror else v.y, -v.x) * PX)
		pen.polyline(mid, Color("13223A"), 1.3, true)
		pen.polyline(mid, Color(0.4, 0.65, 1.0, 0.55), 0.35, true)
		pen.polyline(o, Color("3E4A5A"), 0.3, true)
		pen.polyline(i, Color("3E4A5A"), 0.3, true)
	# the hull: structure between the rooms and the skin, notched where a
	# window looks out (so you see space, and the drive rings, through it)
	var body := _map(FrigateShape.BODY)
	# The clipper wants outlines wound one way (the other way means "a hole").
	if Geometry2D.is_polygon_clockwise(body):
		body.reverse()
	var pieces: Array[PackedVector2Array] = [body]
	for notch in _window_notches():
		if Geometry2D.is_polygon_clockwise(notch):
			notch.reverse()
		var next: Array[PackedVector2Array] = []
		for piece in pieces:
			# Notches only bite in from the skin, so clipping never leaves holes.
			next.append_array(Geometry2D.clip_polygons(piece, notch))
		pieces = next
	for piece in pieces:
		pen.fill(piece, HULL_FILL)
	# frames every 4 m across the beam, and the keel line
	var x := FrigateShape.BOW_X - 4.0
	while x > FrigateShape.BAY.position.x:
		var hw := FrigateShape.half_beam(x) - 0.3
		if hw > 0.5:
			pen.line(to_deck(Vector2(x, -hw)), to_deck(Vector2(x, hw)), HULL_RIB, 0.25, false)
		x -= 4.0
	pen.line(to_deck(Vector2(FrigateShape.BOW_X - 2.0, 0)), to_deck(Vector2(FrigateShape.BAY.end.x, 0)), HULL_RIB, 0.4, false)
	for piece in pieces:
		pen.polyline(piece, HULL_SKIN, 1.8, true)
	pen.flush()


## Clamped into a berth: the pier wall, the two clamp pylons and the gangway
## tube outside the hull (the world is suspended indoors, so the deck draws
## what you would see through its windows, as BerthView does from the pier).
func _paint_berth(pen: OnFootPainter) -> void:
	var ship := FrigateShip.aboard
	if ship == null or ship.dock.state != FrigateDock.State.LOCKED or ship.dock.berth == null:
		return
	var s := ship.dock.side()
	var dist := float(ship.dock.berth.get(&"pier_dist_m"))
	var rect := func(x0: float, y0: float, x1: float, y1: float) -> PackedVector2Array:
		return PackedVector2Array([to_deck(Vector2(x0, y0 * s)), to_deck(Vector2(x1, y0 * s)), to_deck(Vector2(x1, y1 * s)), to_deck(Vector2(x0, y1 * s))])
	# the pier itself, running the length of the ship
	pen.poly(rect.call(-110.0, dist, 120.0, dist + 26.0), Color("C9D2DC"), Color("3E4A5A"), 0.3)
	pen.fill(rect.call(-110.0, dist + 3.0, 120.0, dist + 4.2), Color("1D3557"), false)
	pen.fill(rect.call(-110.0, dist + 8.0, 120.0, dist + 9.0), Color("2A9D8F"), false)
	for h: Vector2 in [FrigateShape.CLAMP_FWD, FrigateShape.CLAMP_AFT]:
		var tip := absf(h.y) + 0.4
		pen.poly(rect.call(h.x - 3.6, tip + 4.0, h.x + 3.6, dist), Color("E3E9EF"), Color("4A5563"), 0.25)
		pen.fill(rect.call(h.x - 1.0, tip + 4.5, h.x + 1.0, dist), Color("1D3557"), false)
		pen.poly(rect.call(h.x - 6.5, tip, h.x + 6.5, tip + 4.6), Color("C9D2DC"), Color("4A5563"), 0.25)
		pen.fill(rect.call(h.x - 6.0, tip + 0.6, h.x - 2.6, tip + 4.0), Color("FFB000"), false)
		pen.fill(rect.call(h.x + 2.6, tip + 0.6, h.x + 6.0, tip + 4.0), Color("FFB000"), false)
	# the gangway tube from the pier to this airlock, with its window strip
	var a: Vector2 = FrigateShape.AIRLOCK
	pen.poly(rect.call(a.x - 2.2, a.y - 0.6, a.x + 2.2, dist), Color("D9E0E7"), Color("4A5563"), 0.25)
	pen.fill(rect.call(a.x + 1.2, a.y + 1.0, a.x + 1.7, dist - 1.0), Color(1.0, 0.88, 0.62, 0.9), false)
	pen.fill(rect.call(a.x - 1.9, a.y + 0.2, a.x - 1.5, dist - 0.5), Color("1D3557"), false)


## One rectangle per hull window, from the wall line out past the skin.
func _window_notches() -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for n in find_children("*", "Node2D", true, false):
		var w := n as InteriorWindow
		if w == null:
			continue
		var pos := _local(w)
		var along := Vector2(0, 1).rotated(w.global_rotation - global_rotation)
		var across := along.orthogonal()
		var probe := (w.thickness_m * 0.5 + 0.4) * PX
		var room_a := _room_near_point(pos + across * probe)
		var room_b := _room_near_point(pos - across * probe)
		if room_a == room_b:
			continue      # a window between two rooms (or a stray one): no notch
		var outward := -across if room_a else across
		var half := along * (w.length_m * 0.5 - 0.15) * PX
		var a := pos - outward * w.thickness_m * 0.5 * PX
		var b := pos + outward * 400.0
		out.append(PackedVector2Array([a - half, a + half, b + half, b - half]))
	return out


func _room_near_point(p: Vector2) -> bool:
	for r in _rects:
		if r.has_point(p):
			return true
	return false


## Paint on the flight deck floor: the two pads, the centre line and the
## hazard band at the mouth (the same marks the exterior art has).
func _draw_deck_markings(ci: Node2D) -> void:
	var pen := OnFootPainter.new(ci)
	var bay := FrigateShape.BAY
	var amber := Color(1.0, 0.69, 0.0, 0.85)
	var white := Color(0.92, 0.95, 1.0, 0.7)
	# mouth: chevrons
	var y := bay.position.y + 0.4
	while y < bay.end.y - 1.2:
		pen.fill(PackedVector2Array([to_deck(Vector2(bay.position.x + 0.4, y)), to_deck(Vector2(bay.position.x + 0.4, y + 0.8)),
			to_deck(Vector2(bay.position.x + 2.4, y + 1.6)), to_deck(Vector2(bay.position.x + 2.4, y + 0.8))]), amber)
		y += 1.6
	pen.line(to_deck(Vector2(bay.position.x + 2.9, bay.position.y + 0.5)), to_deck(Vector2(bay.position.x + 2.9, bay.end.y - 0.5)), white, 0.2)
	# centre line
	var x := bay.position.x + 4.5
	while x < bay.end.x - 3.5:
		pen.line(to_deck(Vector2(x, 0)), to_deck(Vector2(x + 1.6, 0)), white, 0.22)
		x += 3.2
	# pads
	var letters := ["A", "B"]
	var half := FrigateShape.BAY_PAD_SIZE * 0.5
	for k in FrigateShape.BAY_PADS.size():
		var c: Vector2 = FrigateShape.BAY_PADS[k]
		for sx: float in [-1.0, 1.0]:
			for sy: float in [-1.0, 1.0]:
				var corner := c + Vector2(sx * half.x, sy * half.y)
				pen.polyline(PackedVector2Array([to_deck(corner - Vector2(sx * 2.4, 0)), to_deck(corner), to_deck(corner - Vector2(0, sy * 2.4))]), amber, 0.3)
		pen.ring(to_deck(c), 3.4 * PX, white, 0.22, 40)
		pen.circle(to_deck(c), 2.5 * PX, Color(0.11, 0.21, 0.34, 0.75))
		pen.text(to_deck(c) + Vector2(0, 1.0), letters[k], 3.0 * PX * 0.9, Color(0.92, 0.95, 1.0, 0.9))
		pen.line(to_deck(c - Vector2(half.x - 1.0, 0)), to_deck(c - Vector2(4.4, 0)), Color(0.5, 0.9, 1.0, 0.55), 0.15)
		pen.line(to_deck(c + Vector2(4.4, 0)), to_deck(c + Vector2(half.x - 1.0, 0)), Color(0.5, 0.9, 1.0, 0.55), 0.15)
	pen.flush()


# ============================================================ stowed ships

## Small ships parked on the real flight deck appear here, in the same spot.
func _build_stowed() -> void:
	for n in get_tree().get_nodes_in_group(&"player_ship"):
		var s := n as PlayerShip
		if s == null or s == _ship or not s.alive or not s.has_method(&"make_landed_model"):
			continue
		if s is FrigateShip or not _ship.bay.contains(s.global_position):
			continue
		var local := _ship.global_transform.affine_inverse() * s.global_transform
		var model := s.make_landed_model() as LandedShip
		if model == null:
			continue
		model.name = "Stowed_%s" % s.vehicle_name
		model.transform = DECK_XF * local
		add_child(model)
		var who := s
		model.set_board_action(func(_by: Node2D) -> void:
			var d := get_tree().get_first_node_in_group(&"on_foot_director")
			if d:
				d.call(&"board_stowed", who))
		var board := model.get_node_or_null(^"BoardHatch") as Interactable
		if board:
			board.prompt = "Board the %s" % s.vehicle_name
		# The walker bumps into the hull, as it does outside.
		var cp := s.get_node_or_null(^"CollisionPolygon2D") as CollisionPolygon2D
		if cp:
			var body := StaticBody2D.new()
			body.collision_layer = Game.LAYER_WALK
			body.collision_mask = 0
			var shape := CollisionPolygon2D.new()
			shape.polygon = cp.polygon
			body.add_child(shape)
			model.add_child(body)
		_stowed[s] = model


## The landed model of a ship parked on the flight deck (null if it isn't).
func stowed_model(s: Node) -> LandedShip:
	return _stowed.get(s) as LandedShip


func stowed_ships() -> Array:
	return _stowed.keys()


# ================================================================== damage

func _damage_room(r: Rect2, integ: float) -> void:
	for l in _lights:
		if r.has_point(l.position):
			l.faulty = true
	var p := CPUParticles2D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = 18
	p.lifetime = 0.6
	p.explosiveness = 0.9
	p.spread = 180.0
	p.initial_velocity_min = 30.0
	p.initial_velocity_max = 90.0
	p.damping_min = 60.0
	p.damping_max = 120.0
	p.scale_amount_min = 0.25
	p.scale_amount_max = 0.6
	p.color_ramp = FxTextures.spark_ramp()
	p.material = OnFootArt.add_unshaded()
	p.z_as_relative = false
	p.z_index = Game.Z_FX
	add_child(p)
	_sparks.append([p, r, randf_range(0.3, 1.5), integ])


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_t += delta
	if _alert:
		var k := 0.5 + 0.5 * sin(_t * 4.2)
		if _cm:
			_cm.color = ambient.lerp(Color(0.32, 0.06, 0.06), 0.35 + 0.35 * k)
		for l in _lights:
			l.set_tint(Color(1.0, 0.35 + 0.25 * (1.0 - k), 0.3))
	for s in _sparks:
		s[2] -= delta
		if s[2] <= 0.0:
			var r: Rect2 = s[1]
			var p: CPUParticles2D = s[0]
			# along a wall: conduits run behind the wall panels
			var edge := randi() % 4
			var pos := r.position + Vector2(randf() * r.size.x, randf() * r.size.y)
			match edge:
				0: pos.y = r.position.y + 2.0
				1: pos.y = r.end.y - 2.0
				2: pos.x = r.position.x + 2.0
				3: pos.x = r.end.x - 2.0
			p.position = pos
			p.restart()
			var bad := 1.0 - float(s[3]) / 60.0
			s[2] = randf_range(0.4, 2.6 - 1.8 * bad)
