@tool
extends StationModule
## Slewing cargo crane (AnimatableBody2D) whose boom sweeps back and forth
## across the yard aisle - a moving hazard you have to time.
## Local origin = slewing pivot; the boom points along local +X of the body.

@export var boom_m := 100.0:
	set(v): boom_m = v; queue_rebuild()
@export var centre_deg := 180.0
@export var sweep_deg := 45.0
@export var period := 24.0
@export var phase := 0.0

var _t := 0.0
var _last_sign := 0.0
var _sfx: AudioStreamPlayer2D


func _build() -> void:
	moving = true
	var L := boom_m
	var base := A.circle_poly(Vector2.ZERO, 8.0 * PX, 24)
	var boom := A.rect_m(4, -3, L, 3)
	var cw := A.rect_m(-24, -6, -6, 6)
	var spreader := A.rect_m(L - 16, -6.5, L - 3, 6.5)
	var shape := union(union(union(base, boom), cw), spreader)
	hull(shape, &"amber", [base, boom, cw, spreader], {"bevel": 0.5})
	radar_polys.append(A.rect_m(-24, -6, L, 6))
	var D := Band.STRUCT_DETAIL
	# boom lattice + hazard stripes
	hazard(D, A.rect_m(8, -2.2, L - 17, 2.2), 1.6, PI * 0.25)
	var pairs := PackedVector2Array()
	var x := 8.0
	while x < L - 18:
		pairs.append_array([m(x, -2.6), m(x + 3, 2.6)])
		x += 6.0
	lines(D, pairs, Color(0.1, 0.1, 0.12, 0.35), 2.0)
	# counterweight (concrete blocks)
	fill(D, A.rect_m(-23, -5, -7, 5), Color("8E9AA8"))
	for i in 4:
		outline(D, A.rect_m(-23 + i * 4, -5, -19 + i * 4, 5), Color("5C6878"), 1.5)
	# cab + slewing ring
	fill(D, A.circle_poly(Vector2.ZERO, 6.0 * PX, 24), A.NAVY)
	fill(D, A.rect_m(1, -4.5, 6.5, -1), Color("2C6A86"))
	outline(D, A.circle_poly(Vector2.ZERO, 6.0 * PX, 24), Color(0.7, 0.8, 0.9, 0.8), 2.0)
	# spreader carrying a container
	fill(D, A.rect_m(L - 15.5, -6.1, L - 3.5, -0.2), Color("4EA8DE"))
	fill(D, A.rect_m(L - 15.5, 0.2, L - 3.5, 6.1), Color("E9EEF3"))
	outline(D, A.rect_m(L - 15.5, -6.1, L - 3.5, 6.1), Color("1D3557"), 2.0)
	text(D, m(L - 9.5, 3.1), "TIDEWAY", 16, A.NAVY)
	# lights
	beacon(m(L - 1.5, 0), A.NAV_RED, 120.0, 0.0)
	beacon(m(L * 0.5, 0), A.AMBER, 100.0, 0.35)
	beacon(m(-22, 0), A.NAV_RED, 90.0, 0.5)
	lamp(m(L - 9.5, 0), A.WARM, 90.0)


func _initial_body_transform() -> Transform2D:
	return Transform2D(deg_to_rad(centre_deg) + deg_to_rad(sweep_deg) * sin(phase), Vector2.ZERO)


func _after_build() -> void:
	if Engine.is_editor_hint():
		return
	var path := "res://assets/audio/door_servo.wav"
	if ResourceLoader.exists(path) and LevelArt.audio_enabled():
		_sfx = AudioStreamPlayer2D.new()
		_sfx.stream = load(path)
		_sfx.bus = &"SFX"
		_sfx.max_distance = 2400.0
		_sfx.attenuation = 1.6
		_sfx.pitch_scale = 0.8
		add_child(_sfx)
		_generated.append(_sfx)
	_physics_process(0.0)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or body == null:
		return
	_t += delta
	var w := TAU / period
	var ang := deg_to_rad(centre_deg) + deg_to_rad(sweep_deg) * sin(w * _t + phase)
	(body as Node2D).rotation = ang
	# servo groan as the boom reverses (angular velocity changes sign)
	var s := signf(cos(w * _t + phase))
	if _last_sign != 0.0 and s != _last_sign and _sfx:
		_sfx.play()
	_last_sign = s
