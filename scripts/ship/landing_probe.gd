class_name LandingProbe
extends RefCounted
## Can the PETREL set down right here? Checks, first failure wins:
##   NO DECK BELOW   the centre isn't over a station deck (LevelArt.walk_decks)
##   EDGE            a skid / nose / stern corner would hang off the deck
##   OBSTRUCTED      something solid is under/next to the hull (grown 0.4 m)
##   TOO FAST        speed >= max_speed
##   SPINNING        |omega| >= max_spin
## Heading doesn't matter: land at any angle. Any deck counts for any point,
## so straddling a pad and the hangar floor around it is fine.

## Local test points (metres): the 4 visible mag-skid pads (they reach just
## past the hull edge), then nose and stern corners.
const SKIDS := [Vector2(3.6, -2.86), Vector2(3.6, 2.86), Vector2(-4.2, -3.735), Vector2(-4.2, 3.735)]
const EXTRA := [Vector2(6.2, 0.0), Vector2(-6.2, -2.4), Vector2(-6.2, 2.4)]

static var _shape: ConvexPolygonShape2D


## The hull grown by 0.4 m (built once, shared).
static func grown_shape(hull_px: PackedVector2Array) -> ConvexPolygonShape2D:
	if _shape == null:
		var grown := Geometry2D.offset_polygon(hull_px, 4.0)
		_shape = ConvexPolygonShape2D.new()
		# The hull has a slight waist: use its convex hull (point cloud).
		_shape.set_point_cloud(grown[0] if not grown.is_empty() else hull_px)
	return _shape


static func cleanup() -> void:
	_shape = null


## -> {ok, reason, text, skid_ok: Array[bool], deck_name}
static func check(ship: RigidBody2D, hull_px: PackedVector2Array, max_speed := 2.0, max_spin := 0.3, ramp_m: Array = []) -> Dictionary:
	var out := {"ok": false, "reason": "", "text": "", "skid_ok": [false, false, false, false], "deck_name": ""}
	var xf := ship.global_transform
	var centre := xf.origin
	var deck := _deck_at(centre)
	if deck.is_empty():
		out.reason = "NO_DECK"
		out.text = "NO DECK BELOW"
		return out
	out.deck_name = _deck_name(deck)
	var all_on := true
	for i in SKIDS.size():
		var on := not _deck_at(xf * ((SKIDS[i] as Vector2) * Game.PX_PER_M)).is_empty()
		out.skid_ok[i] = on
		all_on = all_on and on
	for p in EXTRA:
		all_on = all_on and not _deck_at(xf * ((p as Vector2) * Game.PX_PER_M)).is_empty()
	if not all_on:
		out.reason = "EDGE"
		out.text = "EDGE  ·  not all skids over deck"
		return out
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = grown_shape(hull_px)
	q.transform = xf
	q.collision_mask = Game.LAYER_WORLD | Game.LAYER_PROPS | Game.LAYER_TRAFFIC
	q.exclude = [ship.get_rid()]
	if not ship.get_world_2d().direct_space_state.intersect_shape(q, 1).is_empty():
		out.reason = "OBSTRUCTED"
		out.text = "OBSTRUCTED  ·  something under the hull"
		return out
	# The boarding ramp needs deck (well inside its edge) and open space, or
	# the pilot would step out over the void or into a wall.
	var foot := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 4.0
	foot.shape = circle
	foot.collision_mask = Game.LAYER_WORLD | Game.LAYER_PROPS | Game.LAYER_WALK
	foot.exclude = [ship.get_rid()]
	for rp in ramp_m:
		var gp := xf * ((rp as Vector2) * Game.PX_PER_M)
		var inside := true
		for o: Vector2 in [Vector2(6, 0), Vector2(-6, 0), Vector2(0, 6), Vector2(0, -6)]:
			inside = inside and not _deck_at(gp + o).is_empty()
		foot.transform = Transform2D(0.0, gp)
		if not inside or not ship.get_world_2d().direct_space_state.intersect_shape(foot, 1).is_empty():
			out.reason = "RAMP"
			out.text = "NO ROOM FOR THE RAMP  ·  port side blocked"
			return out
	var v := ship.linear_velocity.length() / Game.PX_PER_M
	if v >= max_speed:
		out.reason = "TOO_FAST"
		out.text = "TOO FAST  %.1f m/s  (max %.1f)" % [v, max_speed]
		return out
	var w := absf(ship.angular_velocity)
	if w >= max_spin:
		out.reason = "SPINNING"
		out.text = "SPINNING  %d°/s  (max %d)" % [int(rad_to_deg(w)), int(rad_to_deg(max_spin))]
		return out
	out.ok = true
	out.text = "CLEAR TO LAND  ·  %s" % out.deck_name
	return out


static func _deck_at(p: Vector2) -> Dictionary:
	for e in LevelArt.walk_decks:
		if Geometry2D.is_point_in_polygon(p, e.poly):
			return e
	return {}


## Readable deck name from its module ("CargoYard" -> "Cargo yard").
static func _deck_name(e: Dictionary) -> String:
	var m: Node = e.module
	if m == null or not is_instance_valid(m):
		return "Deck"
	var pn: Variant = m.get(&"pad_name")
	if pn != null and String(pn) != "":
		return String(pn)
	return String(m.name).capitalize()
