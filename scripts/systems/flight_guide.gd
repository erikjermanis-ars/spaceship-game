class_name FlightGuide
extends Node2D
## In-world piloting aid drawn around the ship at low alpha:
## * prograde marker — where you are actually drifting (vs. where you point)
## * predicted path — the next ~1.5 s integrated with the same barbell flight
##   model (current velocity, angular velocity and held inputs), so you can
##   see the swing of the side thrusters before it happens.
## Toggle with G (action `flight_guide`, registered here).

const PREDICT_TIME := 1.5
const STEPS := 36
## Contract defaults (SI), used when the ship doesn't expose a property.
## Keys are the PlayerShip's exported property names so live tuning-panel
## changes are reflected in the prediction.
const DEFAULTS := {
	"main_thrust_n": 5000.0, "reverse_scale": 0.6, "side_thrust_n": 2600.0,
	"strafe_thrust_n": 1200.0, "thrust_point_m": 4.0, "boost_multiplier": 2.0,
	"linear_drag": 0.12, "angular_drag": 0.35, "inertia_per_mass_m2": 8.37,
	"mass_kg": 1000.0, "assist_rot_gain": 3.0, "assist_slip_gain": 1.2,
}

var enabled := true
var _pts := PackedVector2Array()
var _cols := PackedColorArray()
var _end_heading := 0.0
var _alpha := 0.0

func _ready() -> void:
	add_to_group(&"flight_guide")
	z_as_relative = false
	z_index = Game.Z_FX
	material = FxTextures.additive()
	if not InputMap.has_action(&"flight_guide"):
		InputMap.add_action(&"flight_guide")
		var e := InputEventKey.new()
		e.physical_keycode = KEY_G
		InputMap.action_add_event(&"flight_guide", e)
	if Game.cmd.has("no-guide"):
		enabled = false
	_pts.resize(STEPS + 1)
	_cols.resize(STEPS + 1)

func _poll_input() -> void:
	if Input.is_action_just_pressed(&"flight_guide"):
		enabled = not enabled
		Game.toast("Flight guide: %s" % ("ON" if enabled else "OFF"), 1.5)

func _process(delta: float) -> void:
	_poll_input()
	var want := enabled and GameplayUtil.player_alive()
	_alpha = move_toward(_alpha, 1.0 if want else 0.0, delta * 5.0)
	visible = _alpha > 0.01
	if visible and GameplayUtil.player_valid():
		_predict()
		queue_redraw()

func _param(ship: Object, key: String) -> float:
	return float(GameplayUtil.pget(ship, StringName(key), DEFAULTS[key]))

## Integrates the barbell model in SI units (semi-implicit Euler), mirroring
## the ship's own force model including flight assist.
func _predict() -> void:
	var ship := Game.player
	var m := _param(ship, "mass_kg")
	var inertia := m * _param(ship, "inertia_per_mass_m2")
	var throttle := float(GameplayUtil.pget(ship, &"throttle_input", 0.0))
	var turn := float(GameplayUtil.pget(ship, &"turn_input", 0.0))
	var strafe := float(GameplayUtil.pget(ship, &"strafe_input", 0.0))
	var assist := bool(GameplayUtil.pget(ship, &"flight_assist", false))
	var boost := _param(ship, "boost_multiplier") if bool(GameplayUtil.pget(ship, &"boosting", false)) else 1.0
	var main := throttle * _param(ship, "main_thrust_n") * boost
	if throttle < 0.0:
		main *= _param(ship, "reverse_scale")
	var side_max := _param(ship, "side_thrust_n")
	var side := turn * side_max * boost
	var strafe_max := _param(ship, "strafe_thrust_n")
	var arm := _param(ship, "thrust_point_m")
	var lin_drag := _param(ship, "linear_drag")
	var ang_drag := _param(ship, "angular_drag")
	var rot_gain := _param(ship, "assist_rot_gain")
	var slip_gain := _param(ship, "assist_slip_gain")

	var p := ship.global_position / Game.PX_PER_M
	var v := ship.linear_velocity / Game.PX_PER_M
	var th := ship.global_rotation
	var w := ship.angular_velocity
	var dt := PREDICT_TIME / STEPS
	_pts[0] = p * Game.PX_PER_M
	_cols[0] = Color(0.5, 0.9, 1.0, 0.0)
	for i in range(1, STEPS + 1):
		var fwd := Vector2.from_angle(th)
		var right := fwd.orthogonal() * -1.0   # local +Y (starboard) in y-down space
		var torque := arm * side
		var lat := strafe * strafe_max
		if assist:
			if is_zero_approx(turn):
				var max_t := side_max * arm
				torque += clampf(-inertia * rot_gain * w, -max_t, max_t)
			if is_zero_approx(strafe):
				lat = clampf(-m * slip_gain * v.dot(right), -strafe_max, strafe_max)
		w += (torque / inertia - ang_drag * w) * dt
		th += w * dt
		var f := fwd * main + right * (side + lat)
		v += (f / m - lin_drag * v) * dt
		p += v * dt
		_pts[i] = p * Game.PX_PER_M
		var k := float(i) / STEPS
		_cols[i] = Color(0.5, 0.9, 1.0, (1.0 - k) * 0.5 * _alpha)
	_end_heading = th

func _draw() -> void:
	if not GameplayUtil.player_valid():
		return
	var ship := Game.player
	var vel := ship.linear_velocity
	var speed := vel.length() / Game.PX_PER_M
	if speed > 0.6:
		draw_polyline_colors(_pts, _cols, 2.0, true)
		# Ghost chevron at the predicted end, showing predicted heading.
		var endp := _pts[STEPS]
		var f := Vector2.from_angle(_end_heading)
		var r := f.orthogonal()
		var c := Color(0.5, 0.9, 1.0, 0.22 * _alpha)
		draw_polyline(PackedVector2Array([endp - f * 14.0 + r * 12.0, endp + f * 14.0, endp - f * 14.0 - r * 12.0]), c, 2.0, true)
		# Prograde marker: ring with three ticks, offset along velocity.
		var dir := vel / vel.length()
		var mp := ship.global_position + dir * 110.0
		var a := clampf((speed - 0.6) / 3.0, 0.0, 1.0) * 0.75 * _alpha
		var pc := Color(0.6, 1.0, 0.75, a)
		draw_arc(mp, 9.0, 0.0, TAU, 20, pc, 2.0, true)
		draw_line(mp + dir.orthogonal() * 9.0, mp + dir.orthogonal() * 17.0, pc, 2.0, true)
		draw_line(mp - dir.orthogonal() * 9.0, mp - dir.orthogonal() * 17.0, pc, 2.0, true)
		draw_line(mp - dir * 9.0, mp - dir * 16.0, pc, 2.0, true)
	# Heading tick (where the nose points), for contrast with prograde.
	var hd := Vector2.from_angle(ship.global_rotation)
	var hp := ship.global_position + hd * 110.0
	draw_line(hp - hd * 6.0, hp + hd * 6.0, Color(1, 1, 1, 0.35 * _alpha), 2.0, true)
