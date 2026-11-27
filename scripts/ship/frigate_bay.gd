class_name FrigateBay
extends Node2D
## A frigate's FLIGHT DECK: the open landing bay in its stern.
##
##   * two landing pads (FrigateBayPad + docking trigger): the WREN flies in
##     from astern and settles on one like on any station pad;
##   * the deck itself is published in LevelArt.walk_decks, so the PETREL's
##     landing probe treats it as a deck (hold Space over it to land). The
##     entry follows the ship: its polygon is rewritten whenever the frigate
##     has moved;
##   * STOWED SHIPS: a ship parked on the deck rides along. While the frigate
##     flies (or jumps to another station) each stowed ship is held at its
##     place on the deck, and the hull doesn't collide with it.
##
## A parked ship is a frozen static body, so moving it every tick is safe
## (it is live continuous-collision bodies that must never be teleported).

const PX := 10.0
## Extra room (m) around the bay rectangle when deciding "is it on the deck".
const MARGIN_M := 1.0

var ship: FrigateShip
var pads: Array[FrigateBayPad] = []
## [{ship: PlayerShip, local: Transform2D}]
var stowed: Array[Dictionary] = []

var _deck := {}
var _deck_xf := Transform2D(0.0, Vector2(INF, INF))


func setup(p_ship: FrigateShip) -> void:
	ship = p_ship
	name = "Bay"
	var letters := ["A", "B"]
	for i in FrigateShape.BAY_PADS.size():
		var pad := FrigateBayPad.new()
		pad.name = "Pad%s" % letters[i]
		pad.position = (FrigateShape.BAY_PADS[i] as Vector2) * PX
		pad.setup("%s Bay %s" % [ship.vehicle_name, letters[i]], FrigateShape.BAY_PAD_SIZE)
		add_child(pad)
		pads.append(pad)
	_deck = {"module": ship, "poly": deck_polygon()}
	LevelArt.walk_decks.append(_deck)


func _exit_tree() -> void:
	LevelArt.walk_decks.erase(_deck)
	release_all()


## The deck's outline in global px.
func deck_polygon() -> PackedVector2Array:
	var r := FrigateShape.BAY
	return ship.global_transform * OnFootArt.rect_poly(Rect2(r.position * PX, r.size * PX))


## Is global point `p` over the flight deck?
func contains(p: Vector2) -> bool:
	var local := ship.global_transform.affine_inverse() * p / PX
	return FrigateShape.BAY.grow(MARGIN_M).has_point(local)


## Which parked ships sit on the deck right now? Called when someone takes
## the frigate's helm: from then on they ride with the ship.
func refresh() -> void:
	release_all()
	for n in get_tree().get_nodes_in_group(&"player_ship"):
		var s := n as PlayerShip
		if s == null or s == ship or s == Game.player or s.powered or not s.alive:
			continue
		if contains(s.global_position):
			_stow(s)


func is_stowed(s: Node) -> bool:
	for e in stowed:
		if e.ship == s:
			return true
	return false


func _stow(s: PlayerShip) -> void:
	var local := ship.global_transform.affine_inverse() * s.global_transform
	stowed.append({"ship": s, "local": local})
	s.carrier = ship
	s.carrier_local = local
	ship.add_collision_exception_with(s)
	s.add_collision_exception_with(ship)


func _unstow(e: Dictionary) -> void:
	var s: PlayerShip = e.ship
	if is_instance_valid(s):
		s.carrier = null
		if is_instance_valid(ship):
			ship.remove_collision_exception_with(s)
			s.remove_collision_exception_with(ship)


func release_all() -> void:
	for e in stowed:
		_unstow(e)
	stowed.clear()


func _physics_process(_delta: float) -> void:
	if ship == null:
		return
	var xf := ship.global_transform
	if not xf.is_equal_approx(_deck_xf):
		_deck_xf = xf
		_deck.poly = deck_polygon()
	for i in range(stowed.size() - 1, -1, -1):
		var e := stowed[i]
		var s: PlayerShip = e.ship
		# Boarded (someone flies it off the deck) or gone: no longer cargo.
		if not is_instance_valid(s) or s.powered or s == Game.player or not s.alive:
			_unstow(e)
			stowed.remove_at(i)
			continue
		var want: Transform2D = xf * (e.local as Transform2D)
		if not s.global_transform.is_equal_approx(want):
			s.global_transform = want
