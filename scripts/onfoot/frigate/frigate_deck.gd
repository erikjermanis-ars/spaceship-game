@tool
class_name FrigateDeck
extends InteriorLevel
## The KESTREL's main deck (an InteriorLevel placed wherever the ship is,
## north-up: bow = up). Besides the usual room/wall build it ties the
## interior to the ship's real state, read once when you come aboard (the
## world is suspended while you're inside, so it can't change under you):
##   * RED ALERT: the room lights and the ambient darkness pulse red;
##   * each room belongs to a hull section (by where it is on the deck); a
##     badly hurt section has failing lights that stutter and sparks spitting
##     from damaged conduits.

## Deck-plan bands (local px): above BOW_Y is the bow, below ENG_Y engineering.
const BOW_Y := -100.0
const ENG_Y := 160.0

var _ship: FrigateShip
var _cm: CanvasModulate
var _alert := false
var _t := 0.0
var _sparks: Array = []          ## [CPUParticles2D, Rect2 (local), next_t, integrity]
var _lights: Array[RoomLight] = []


func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	_ship = get_tree().get_first_node_in_group(&"frigate") as FrigateShip
	for c in get_children():
		if c is CanvasModulate:
			_cm = c
	if _ship == null:
		return
	_alert = _ship.red_alert
	for l in find_children("*", "RoomLight", true, false):
		_lights.append(l as RoomLight)
	for n in find_children("*", "InteriorRoom", true, false):
		var room := n as InteriorRoom
		var r := Rect2(room.position, room.size_m * OnFootArt.PX)
		var integ := _ship.damage.integrity[section_of(r.get_center())]
		if integ < 60.0:
			_damage_room(r, integ)


## Which hull section a deck position (local px) belongs to.
static func section_of(p: Vector2) -> int:
	if p.y < BOW_Y:
		return FrigateDamage.Sec.BOW
	if p.y > ENG_Y:
		return FrigateDamage.Sec.ENGINEERING
	return FrigateDamage.Sec.PORT if p.x < 0.0 else FrigateDamage.Sec.STARBOARD


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
