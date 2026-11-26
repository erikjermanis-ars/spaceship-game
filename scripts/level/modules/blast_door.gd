@tool
extends StationModule
## One leaf of a sliding blast door (AnimatableBody2D). Two leaves with
## opposite `direction` form the hangar door. The cycle is time based so the
## leaves stay in sync: open -> closing -> closed -> opening.

@export var length_m := 30.0:
	set(v): length_m = v; queue_rebuild()
@export var thick_m := 4.0:
	set(v): thick_m = v; queue_rebuild()
## -1 = leaf occupies local -Y when closed and slides further to -Y to open.
@export var direction := -1.0:
	set(v): direction = v; queue_rebuild()
@export var travel_m := 33.0
@export var open_hold := 6.0
## Slow enough (peak ~10 m/s) that a leaf touching the ship is a shove, not a hit.
@export var close_time := 5.0
@export var closed_hold := 4.5
@export var open_time := 5.0
@export var play_sound := true

var _t := 0.0
var _phase := -1
var _sfx: AudioStreamPlayer2D
var _guard_query: PhysicsShapeQueryParameters2D


func _build() -> void:
	moving = true
	struct_z = G.Z_STRUCTURE - 5   # slides UNDER the hangar walls/housings
	var L := length_m
	var T := thick_m
	var y0 := 0.0 if direction > 0 else -L
	var leaf := A.rect_m(-T * 0.5, y0, T * 0.5, y0 + L)
	hull(leaf, &"steel", [], {"bevel": 0.5})
	var D := Band.STRUCT_DETAIL
	# chevron hazard face on the meeting edge + ribs
	var edge_y := 0.0
	hazard(D, A.rect_m(-T * 0.5 + 0.6, edge_y - 3.0 * signf(-direction) - 0.0, T * 0.5 - 0.6, edge_y), 0.8)
	var pairs := PackedVector2Array()
	var y := y0 + 4.0
	while y < y0 + L - 1.0:
		pairs.append_array([m(-T * 0.5 + 0.5, y), m(T * 0.5 - 0.5, y)])
		y += 3.0
	seams(D, pairs, Color(0.25, 0.3, 0.38, 0.9))
	lamp(m(0, edge_y + direction * 1.2), A.NAV_RED, 40.0)
	radar_polys.append(leaf)


func _after_build() -> void:
	if Engine.is_editor_hint() or not play_sound or not LevelArt.audio_enabled():
		return
	var path := "res://assets/audio/door_servo.wav"
	if ResourceLoader.exists(path):
		_sfx = AudioStreamPlayer2D.new()
		_sfx.stream = load(path)
		_sfx.bus = &"SFX"
		_sfx.max_distance = 2600.0
		_sfx.attenuation = 1.6
		_sfx.volume_db = -2.0
		add_child(_sfx)
		_generated.append(_sfx)


## 0 = fully closed, 1 = fully open.
func open_amount() -> float:
	var period := open_hold + close_time + closed_hold + open_time
	var t := fmod(_t, period)
	if t < open_hold:
		_set_phase(0)
		return 1.0
	t -= open_hold
	if t < close_time:
		_set_phase(1)
		return 1.0 - smoothstep(0.0, 1.0, t / close_time)
	t -= close_time
	if t < closed_hold:
		_set_phase(2)
		return 0.0
	t -= closed_hold
	_set_phase(3)
	return smoothstep(0.0, 1.0, t / open_time)


func _set_phase(p: int) -> void:
	if p == _phase:
		return
	_phase = p
	if (p == 1 or p == 3) and _sfx:
		_sfx.play()


## The leaf starts where its first physics step puts it (fully open), so the
## first sync is not read as a 33 m kinematic sweep.
func _initial_body_transform() -> Transform2D:
	return Transform2D(0.0, Vector2(0, direction * travel_m * PX * open_amount()))


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or body == null:
		return
	var amount := open_amount()
	# Safety interlock: while closing, hold if the player is in the doorway so
	# the two leaves never crush a ship. Both leaves share the same origin and
	# run the same query, so they stay in sync.
	if not (_phase == 1 and _doorway_blocked()):
		_t += delta
		amount = open_amount()
	(body as Node2D).position = Vector2(0, direction * travel_m * PX * amount)


func _doorway_blocked() -> bool:
	var space := get_world_2d().direct_space_state
	if space == null:
		return false
	if _guard_query == null:
		var rs := RectangleShape2D.new()
		rs.size = Vector2(thick_m + 12.0, length_m * 2.0) * PX
		_guard_query = PhysicsShapeQueryParameters2D.new()
		_guard_query.shape = rs
		_guard_query.collision_mask = G.LAYER_PLAYER
		_guard_query.collide_with_areas = false
	_guard_query.transform = global_transform
	return not space.intersect_shape(_guard_query, 1).is_empty()
