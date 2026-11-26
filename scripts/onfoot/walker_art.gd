class_name WalkerArt
extends Node2D
## Procedural top-down character, facing +X, drawn in world pixels
## (1 m = 10 px; shoulders ~0.56 m wide).
##
## "Procedural animation": instead of a sprite sheet, the pose is computed
## every frame from a few numbers the Walker feeds in:
##   step_phase  advances with distance walked (π per step), so feet plant
##               exactly as far as the body moves (no foot sliding)
##   speed_mps / run_amount  scale stride, arm swing, torso twist and bob
## plus idle breathing and an occasional look-around. It is resolution
## independent (crisp at any zoom), costs ~40 draw calls, and new outfits are
## just colour changes.

const SUIT := Color("E9EEF3")
const SUIT_SHADE := Color("C3CCD6")
const SUIT_DARK := Color("4A5563")
const BOOT := Color("2B3440")
const GLOVE := Color("56616E")
const ACCENT := Color("2A9D8F")
const NAVY := Color("1D3557")
const AMBER := Color("FFB000")
const VISOR := Color("16304F")
const SKIN := Color("C99B7A")
const HAIR := Color("3A2A22")
const INK := Color(0.05, 0.07, 0.11, 0.95)

var step_phase := 0.0
var speed_mps := 0.0
var run_amount := 0.0
var helmet := true
var lamp_on := false

var _t := 0.0
var _move := 0.0        # 0 idle .. 1 walking (smoothed)
var _idle_t := 0.0
var _look := 0.0        # head turn (rad), idle glances
var _helmet_k := 1.0    # 1 = helmet on, animates on change


## Batched painter used by the draw callbacks (see OnFootPainter).
var pen: OnFootPainter

func advance(delta: float) -> void:
	_t += delta
	var moving := speed_mps > 0.3
	_move = move_toward(_move, 1.0 if moving else 0.0, delta * 5.0)
	_idle_t = 0.0 if moving else _idle_t + delta
	# After standing still a while, glance left and right now and then.
	var look_target := 0.0
	if _idle_t > 2.5:
		look_target = 0.55 * sin(_idle_t * 0.7) * smoothstep(2.5, 3.5, _idle_t)
	_look = lerpf(_look, look_target, 1.0 - exp(-4.0 * delta))
	_helmet_k = move_toward(_helmet_k, 1.0 if helmet else 0.0, delta * 2.5)
	queue_redraw()


func _draw() -> void:
	pen = OnFootPainter.new(self)
	_paint_draw()
	pen.flush()


func _paint_draw() -> void:
	var amp := lerpf(1.9, 2.9, run_amount) * _move           # foot travel (px)
	var arm_amp := lerpf(1.5, 2.5, run_amount) * _move
	var s := sin(step_phase)
	var twist := 0.16 * s * _move * lerpf(1.0, 1.4, run_amount)
	var bob := 1.0 + (0.03 + 0.03 * run_amount) * absf(s) * _move
	var breathe := 1.0 + 0.012 * sin(_t * 1.7) * (1.0 - _move)

	# --- drop shadow (offset in GLOBAL space: the sun doesn't turn with us)
	var so := OnFootArt.SHADOW_OFFSET.rotated(-global_rotation)
	pen.fill(OnFootArt.ellipse_poly(so + Vector2(-0.3, 0), 2.6, 3.4, 0.0, 18), Color(0, 0.01, 0.03, 0.3))

	# --- legs & boots (under the body)
	for side: float in [-1.0, 1.0]:
		var fx := amp * s * side            # left foot (+Y side) leads when s > 0
		var swing := maxf(0.0, cos(step_phase) * side) * _move   # foot moving forward = lifted
		var hip := Vector2(-0.4, side * 1.1)
		var foot := Vector2(fx + 0.3, side * 1.2)
		pen.capsule(hip, foot, 1.35, SUIT_DARK)
		var fl := 1.0 + 0.14 * swing
		var boot := OnFootArt.ellipse_poly(foot + Vector2(0.35, 0), 1.25 * fl, 0.66 * fl, 0.0, 14)
		pen.poly(boot, BOOT, INK, 0.1)
		pen.circle(foot + Vector2(1.1 * fl, 0), 0.3, Color(0.75, 0.82, 0.9, 0.5))

	pen.set_transform(Vector2.ZERO, twist, Vector2(bob * breathe, bob * breathe))

	# --- backpack (life support)
	var pack := Rect2(Vector2(-3.05, -1.95), Vector2(1.9, 3.9))
	pen.rrect(pack, 0.55, SUIT_SHADE, INK, 0.12)
	pen.rect_flat(Rect2(pack.position + Vector2(0.45, 0.35), Vector2(0.28, 3.2)), ACCENT)
	pen.circle(Vector2(-2.45, -1.3), 0.2, Color(0.4, 1.0, 0.6))
	pen.circle(Vector2(-2.45, 1.3), 0.2, Color(0.4, 1.0, 0.6) if fmod(_t, 2.0) < 1.6 else Color(0.2, 0.4, 0.3))

	# --- arms (counter-swing to the legs)
	for side: float in [-1.0, 1.0]:
		var sh := Vector2(0.1, side * 2.45)
		var hand := Vector2(-arm_amp * s * side + 0.5, side * 3.05)
		pen.capsule(sh, hand, 1.15, INK)
		pen.capsule(sh, hand, 0.92, SUIT_SHADE)
		pen.circle(hand, 0.6, GLOVE, INK, 0.1)

	# --- torso
	var torso := OnFootArt.ellipse_poly(Vector2(0, 0), 1.6, 2.9, 0.0, 24)
	pen.poly(torso, SUIT, INK, 0.16)
	# chest/shoulder yoke and stripe
	pen.fill(OnFootArt.ellipse_poly(Vector2(0.35, 0), 0.95, 2.2, 0.0, 18), Color(SUIT_SHADE, 0.6))
	pen.line(Vector2(0.75, -2.0), Vector2(0.75, 2.0), NAVY, 0.4)
	pen.line(Vector2(0.4, -2.3), Vector2(0.4, 2.3), ACCENT, 0.22)
	for side: float in [-1.0, 1.0]:
		pen.circle(Vector2(0.05, side * 2.35), 0.85, SUIT, INK, 0.1)
		pen.arc(Vector2(0.05, side * 2.35), 0.62, 0, 16, ACCENT, 0.18, TAU)
	pen.rect_flat(Rect2(Vector2(-0.9, 2.55), Vector2(0.8, 0.25)), AMBER)

	# --- head (turns a little on its own when idle)
	pen.set_transform(Vector2.ZERO, twist * 0.4 + _look, Vector2(bob * breathe, bob * breathe))
	var hc := Vector2(0.3, 0)
	if _helmet_k < 1.0:
		_draw_head(hc)
	if _helmet_k > 0.0:
		_draw_helmet(hc, _helmet_k)
	pen.set_transform()


func _draw_head(c: Vector2) -> void:
	pen.circle(c + Vector2(-0.1, 0), 1.45, SUIT_SHADE, INK, 0.12)   # neck seal ring
	pen.fill(OnFootArt.ellipse_poly(c + Vector2(0.5, 0), 0.75, 0.95, 0.0, 14), SKIN)
	for side: float in [-1.0, 1.0]:
		pen.circle(c + Vector2(0.1, side * 1.08), 0.27, SKIN.darkened(0.08))
	# hair, swept back; the face shows at the front
	var hair := OnFootArt.ellipse_poly(c + Vector2(-0.2, 0), 1.18, 1.05, 0.0, 20)
	pen.poly(hair, HAIR, INK, 0.1)
	pen.arc(c + Vector2(-0.3, 0), 0.7, -1.2, 10, HAIR.lightened(0.15), 0.18, 1.2)
	pen.circle(c + Vector2(1.22, 0), 0.18, SKIN.darkened(0.12))   # nose tip


func _draw_helmet(c: Vector2, k: float) -> void:
	var a := k
	var shell := Color(SUIT, a)
	pen.circle(c, 1.8, shell, Color(INK, a), 0.16)
	# visor wraps the front; it slides back over the shell as the helmet retracts
	var v0 := lerpf(-1.25, -0.35, 1.0 - k)
	var v1 := lerpf(1.25, 0.35, 1.0 - k)
	var visor := LevelArt.arc_band(c, 0.0, 1.62, v0, v1, 16)
	pen.fill(visor, Color(VISOR, a))
	pen.arc(c, 1.62, v0, v1, Color(NAVY.darkened(0.3), a), 0.14, 16)
	pen.arc(c + Vector2(-0.15, 0), 1.25, -0.9, 8, Color(0.75, 0.92, 1.0, 0.7 * a), 0.2, -0.25)   # reflection
	pen.line(c + Vector2(-1.6, 0), c + Vector2(-0.4, 0), Color(ACCENT, a), 0.3)
	# helmet lamp on the right temple
	var lamp := c + Vector2(0.45, 1.6)
	pen.rrect(Rect2(lamp - Vector2(0.45, 0.28), Vector2(0.9, 0.56)), 0.2, Color(GLOVE, a))
	pen.circle(lamp + Vector2(0.38, 0), 0.22, Color(1.0, 0.97, 0.8, a) if lamp_on else Color(0.3, 0.35, 0.4, a))
