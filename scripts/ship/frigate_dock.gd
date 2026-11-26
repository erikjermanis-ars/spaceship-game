class_name FrigateDock
extends RefCounted
## Berth docking for the frigate. A 158 m ship can't "settle on a pad": it is
## caught and held by the berth's two heavy clamp pylons, so docking is a
## sequence the pilot starts by flying into a small capture box.
##
##   FREE ──(in the capture box, slow, aligned, held 1 s)──▶ CAPTURE
##     clamp arms reach out to the hull hardpoints and close; a soft-capture
##     spring then draws the ship onto the exact berth position and heading
##   CAPTURE ──(on the mark)──▶ LOCKED
##     hard dock: the ship is frozen in the clamps, the personnel gangway
##     telescopes out to the airlock, and the berth starts repairs
##   LOCKED ──(pilot holds any flight input)──▶ UNDOCKING
##     gangway retracts, then the clamps open and push the ship off gently
##   UNDOCKING ──▶ FREE (capture stays disarmed until you leave the box)
##
## The box is asymmetric across the ship: toward the pier it is tight,
## because the pylon tips sit 3.5 m off the hull.

enum State { FREE, CAPTURE, LOCKED, UNDOCKING }

const BOX_AXIAL := 5.0          ## m, along the berth axis (fore/aft)
const BOX_IN := 2.5             ## m, toward the pier
const BOX_OUT := 5.0            ## m, away from the pier
const MAX_HEADING_DEG := 4.0
const MAX_SPEED := 1.2          ## m/s
const MAX_SPIN := 0.02          ## rad/s
const HOLD_TIME := 1.0
const GUIDE_RANGE := 420.0      ## m: guidance shows within this
const CLAMP_TIME := 2.4
const GANGWAY_TIME := 4.5
const GANGWAY_RETRACT := 3.0
const CLAMP_RELEASE := 1.6
## Soft capture spring (rad/s): critically damped, so it never overshoots.
const CAPTURE_OMEGA := 0.9
const CAPTURE_MAX_ACCEL := 1.5  ## m/s^2
const PUSH_OFF := 0.5           ## m/s away from the pier on release

var state := State.FREE
var berth: Node2D
var clamp_t := 0.0              ## 0 retracted/open .. 1 on the hardpoints, closed
var gangway_t := 0.0            ## 0 stowed .. 1 sealed to the airlock
var hold := 0.0                 ## 0..1 capture hold progress
## Berth-frame error, metres: x = fore/aft (+ = ship too far forward),
## y = lateral (+ = too close to the pier).
var err := Vector2.ZERO
var heading_err := 0.0          ## degrees, signed
var speed := 0.0                ## m/s relative to the berth
var spin := 0.0                 ## rad/s
var dist := INF                 ## m from the berth point
var hint := ""
var in_range := false
var in_box := false

var _blocked := false
var _t := 0.0


func is_docked() -> bool:
	return state == State.LOCKED


func gangway_ready() -> bool:
	return state == State.LOCKED and gangway_t >= 1.0


func busy() -> bool:
	return state == State.CAPTURE or state == State.UNDOCKING


## The berth's docked transform (where the ship's centre sits, its heading).
func target() -> Transform2D:
	return berth.call(&"docked_transform") if berth else Transform2D.IDENTITY


func side() -> float:
	return float(berth.get(&"pier_side")) if berth else 1.0


## Start of session / respawn at home: already clamped and connected.
func set_locked() -> void:
	state = State.LOCKED
	clamp_t = 1.0
	gangway_t = 1.0
	hold = 0.0
	_blocked = true
	_t = 99.0


## Adrift and unclamped (respawn away from home, destroyed).
func reset_free() -> void:
	state = State.FREE
	clamp_t = 0.0
	gangway_t = 0.0
	hold = 0.0
	_blocked = false


func request_undock() -> bool:
	if state != State.LOCKED:
		return false
	state = State.UNDOCKING
	_t = 0.0
	return true


## Advance the sequence. Returns an event name for the ship to react to
## (sounds, toasts, freezing): "", "capture", "lock", "gangway",
## "undock", "release".
func tick(ship: RigidBody2D, delta: float, pilot: bool) -> String:
	_t += delta
	_measure(ship)
	match state:
		State.FREE:
			clamp_t = move_toward(clamp_t, 0.0, delta / CLAMP_RELEASE)
			gangway_t = 0.0
			# After undocking, capture re-arms only once you have pulled away.
			if _blocked and dist > 12.0:
				_blocked = false
			var ok := pilot and in_box and not _blocked and hint == ""
			hold = clampf(hold + (delta / HOLD_TIME if ok else -delta * 2.0), 0.0, 1.0)
			if hold >= 1.0:
				state = State.CAPTURE
				_t = 0.0
				hold = 0.0
				return "capture"
		State.CAPTURE:
			clamp_t = minf(1.0, clamp_t + delta / CLAMP_TIME)
			var settled := absf(err.x) < 0.15 and absf(err.y) < 0.15 and absf(heading_err) < 0.3 \
				and speed < 0.1 and spin < 0.006
			if clamp_t >= 1.0 and (settled or _t > 14.0):
				state = State.LOCKED
				_t = 0.0
				return "lock"
		State.LOCKED:
			clamp_t = 1.0
			var was := gangway_t
			gangway_t = minf(1.0, gangway_t + delta / GANGWAY_TIME)
			if was < 1.0 and gangway_t >= 1.0:
				return "gangway"
		State.UNDOCKING:
			if gangway_t > 0.0:
				gangway_t = maxf(0.0, gangway_t - delta / GANGWAY_RETRACT)
				if gangway_t <= 0.0:
					_t = 0.0
					return "unclamp"
			else:
				clamp_t = maxf(0.0, clamp_t - delta / CLAMP_RELEASE)
				if clamp_t <= 0.35:
					state = State.FREE
					_blocked = true
					return "release"
	return ""


## Soft-capture spring: pulls the ship onto the berth mark (replaces the
## pilot's forces while the clamps are closing).
func apply_capture(state_body: PhysicsDirectBodyState2D, ship: RigidBody2D) -> void:
	var t := target()
	var px := Game.PX_PER_M
	var w := CAPTURE_OMEGA
	var e := t.origin - state_body.transform.origin
	var a := e * w * w - state_body.linear_velocity * 2.0 * w
	# Ramp in with the clamp arms, and never yank a big ship.
	a = a.limit_length(CAPTURE_MAX_ACCEL * px) * smoothstep(0.0, 0.5, clamp_t)
	state_body.apply_central_force(a * ship.mass)
	var th := angle_difference(state_body.transform.get_rotation(), t.get_rotation())
	var wr := w * 1.2
	var alpha := clampf(th * wr * wr - state_body.angular_velocity * 2.0 * wr, -0.08, 0.08)
	state_body.apply_torque(alpha * smoothstep(0.0, 0.5, clamp_t) * ship.inertia)


func _measure(ship: RigidBody2D) -> void:
	if berth == null or not is_instance_valid(berth):
		in_range = false
		in_box = false
		hint = ""
		return
	var t := target()
	var px := Game.PX_PER_M
	var local := t.affine_inverse() * ship.global_position / px
	err = Vector2(local.x, local.y * side())
	dist = local.length()
	heading_err = rad_to_deg(angle_difference(t.get_rotation(), ship.global_rotation))
	speed = ship.linear_velocity.length() / px
	spin = absf(ship.angular_velocity)
	in_range = dist < GUIDE_RANGE
	in_box = absf(err.x) <= BOX_AXIAL and err.y <= BOX_IN and err.y >= -BOX_OUT
	if not in_range:
		hint = ""
	elif absf(heading_err) > MAX_HEADING_DEG:
		hint = "ALIGN HEADING  %+.1f°" % -heading_err
	elif not in_box:
		hint = "ENTER CAPTURE BOX"
	elif speed > MAX_SPEED:
		hint = "REDUCE SPEED  %.1f m/s" % speed
	elif spin > MAX_SPIN:
		hint = "STOP ROTATION"
	else:
		hint = ""
