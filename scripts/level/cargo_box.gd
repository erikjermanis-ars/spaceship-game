@tool
extends RigidBody2D
## A free-floating cargo container the player can bump and shove around.
## Paints itself once (cached _draw). Reports prop<->world / prop<->prop /
## prop<->traffic impacts on Game.impact (never contacts with the player:
## the player reports those itself).

const G := preload("res://scripts/autoload/game.gd")
const A := preload("res://scripts/level/level_art.gd")
const PX := 10.0
const MIN_IMPACT_MPS := 0.8
const COOLDOWN_MS := 180

var size_m := Vector2(6.1, 2.44)
var color := Color("E76F51")
var brand := "HELIOS"
var serial := "MRDU 400000"

var _touching := {}     # collider id -> true (contacts last physics frame)
## Velocity before this step's contact resolution (px/s) - impacts are
## measured with it, otherwise the solver has already absorbed the hit.
var prev_velocity := Vector2.ZERO
var prev_velocity2 := Vector2.ZERO
var _cooldown := {}     # collider id -> msec of last report
var _game: Node


func setup(p_size_m: Vector2, p_color: Color, p_brand: String, p_serial: String) -> void:
	size_m = p_size_m
	color = p_color
	brand = p_brand
	serial = p_serial


func _ready() -> void:
	collision_layer = G.LAYER_PROPS
	collision_mask = G.LAYER_WORLD | G.LAYER_PLAYER | G.LAYER_PROPS | G.LAYER_TRAFFIC
	# ~1.9 t empty 6 m box .. heavier long boxes. Ship is 1 t: pushable, but you feel it.
	mass = 1800.0 * (size_m.x * size_m.y) / (6.1 * 2.44)
	linear_damp = 0.05
	angular_damp = 0.12
	can_sleep = true
	continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	var mat := PhysicsMaterial.new()
	mat.bounce = 0.32
	mat.friction = 0.35
	physics_material_override = mat
	contact_monitor = true
	max_contacts_reported = 4
	var cs := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = size_m * PX
	cs.shape = rs
	add_child(cs)
	z_as_relative = false
	z_index = G.Z_PROPS
	add_to_group(&"radar_prop")
	add_to_group(&"cargo_container")
	if not Engine.is_editor_hint():
		_game = get_node_or_null(^"/root/Game")
		if _game:
			_game.debug_draw_changed.connect(func(_on: bool) -> void: queue_redraw())


func _draw() -> void:
	var s := size_m * PX
	var r := Rect2(-s * 0.5, s)
	# soft contact shadow (cheap, symmetric so rotation doesn't matter)
	draw_rect(r.grow(5.0), Color(0, 0, 0.02, 0.3))
	draw_rect(r, color.darkened(0.25))
	draw_rect(r.grow(-2.0), color)
	# corrugations across the short side
	var x := r.position.x + 5.0
	var dark := color.darkened(0.3)
	var lite := color.lightened(0.18)
	var dk := PackedVector2Array()
	var lt := PackedVector2Array()
	while x < r.end.x - 4.0:
		dk.append_array([Vector2(x, r.position.y + 3), Vector2(x, r.end.y - 3)])
		lt.append_array([Vector2(x + 1.5, r.position.y + 3), Vector2(x + 1.5, r.end.y - 3)])
		x += 4.5
	draw_multiline(dk, dark, 1.4)
	draw_multiline(lt, lite, 1.0)
	# corner castings
	var c := 4.0
	for p in [r.position, Vector2(r.end.x - c, r.position.y), Vector2(r.position.x, r.end.y - c), r.end - Vector2(c, c)]:
		draw_rect(Rect2(p, Vector2(c, c)), Color("1B2330"))
	# lit rim: these are solid (bright edge like every colliding thing)
	draw_rect(r, Color(1, 1, 1, 0.85), false, 1.6, true)
	draw_rect(r.grow(1.5), Color(0.02, 0.04, 0.08, 0.9), false, 1.5, true)
	# branding
	var f := A.font()
	var ink := Color(1, 1, 1, 0.92) if color.get_luminance() < 0.6 else Color("1D3557")
	var fs := int(clampf(s.y * 0.42, 8.0, 18.0))
	var w := f.get_string_size(brand, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(f, Vector2(-w * 0.5, fs * 0.36), brand, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
	if s.x > 90.0:
		draw_string(A.font_regular(), Vector2(r.position.x + 6, r.end.y - 4), serial, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(ink, 0.7))
	if _game and _game.debug_draw:
		draw_rect(r, Color(1.0, 0.2, 0.8, 0.95), false, 2.0, true)


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if _game == null:
		return
	var n := state.get_contact_count()
	var pre := prev_velocity
	var pre2 := prev_velocity2
	prev_velocity2 = prev_velocity
	prev_velocity = state.linear_velocity
	if n == 0:
		if not _touching.is_empty():
			_touching.clear()
		return
	var now := Time.get_ticks_msec()
	var seen := {}
	for i in n:
		var other := state.get_contact_collider_object(i)
		if other == null:
			continue
		var oid := other.get_instance_id()
		seen[oid] = true
		if _touching.has(oid):
			continue
		if other == _game.player or (other is Node and (other as Node).is_in_group(&"player_ship")):
			continue
		# prop<->prop: only the lower instance id reports (no double events)
		if other is RigidBody2D and (other as Node).is_in_group(&"cargo_container") and oid < get_instance_id():
			continue
		if now - int(_cooldown.get(oid, -100000)) < COOLDOWN_MS:
			continue
		var normal := state.get_contact_local_normal(i)
		# Contacts can surface a step after the solver already absorbed part
		# of the hit, so measure with the larger of the two previous steps.
		var other_v := state.get_contact_collider_velocity_at_position(i)
		var other_v2 := other_v
		if other is RigidBody2D and "prev_velocity" in other:
			other_v = other.prev_velocity
			other_v2 = other.prev_velocity2
		var speed := maxf(absf((pre - other_v).dot(normal)), absf((pre2 - other_v2).dot(normal))) / PX
		if speed < MIN_IMPACT_MPS:
			continue
		_cooldown[oid] = now
		_game.impact.emit(state.get_contact_local_position(i), normal, speed, self, other)
	_touching = seen
