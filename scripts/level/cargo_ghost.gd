class_name CargoGhost
extends Node2D
## A picture of a cargo container that slides between two places while it
## shrinks or grows and fades: into the PETREL's hold, out of it, or down a
## FreightReceiver's hatch.
##
## Why a stand-in: the real container is a RigidBody2D. Scaling a live body
## scales its collision shape (Godot warns, the solver misbehaves), and by the
## time this plays the body has already left the world (stowed, delivered) or
## must already collide at full size (ejected). So the body is hidden or gone
## and this draws its livery instead. One batched draw, then only the
## transform and alpha change.
##
## Both ends are transforms in the `anchor`'s space (the ship or the receiver
## it is a child of), so the slide follows a moving ship. `follow_to` replaces
## the end with a live node (the ejected body, which drifts away meanwhile).

var size_m := Vector2(6.1, 2.44)
var color := Color("E76F51")
var brand := ""

var from_local := Transform2D.IDENTITY
var to_local := Transform2D.IDENTITY
var scale_from := 1.0
var scale_to := 0.4
var alpha_from := 1.0
var alpha_to := 0.0
var duration := 0.45
## Shown again when the slide ends (the real container an eject put behind the
## ship, hidden while its picture comes out of the hatch).
var follow_to: Node2D

var _t := 0.0


## Builds a ghost of the container described by CargoHold.describe().
static func of(info: Dictionary) -> CargoGhost:
	var g := CargoGhost.new()
	g.size_m = info.size_m
	g.color = info.color
	g.brand = info.brand
	return g


func _ready() -> void:
	top_level = true
	z_as_relative = false
	_apply(0.0)


func _exit_tree() -> void:
	if follow_to != null and is_instance_valid(follow_to):
		follow_to.visible = true


func _process(delta: float) -> void:
	_t += delta / maxf(duration, 0.01)
	if _t >= 1.0:
		queue_free()
		return
	_apply(_t)


func _anchor_xf() -> Transform2D:
	var a := get_parent() as Node2D
	if a == null:
		return Transform2D.IDENTITY
	# Ships draw at a transform interpolated between physics ticks.
	if a.has_method(&"render_transform"):
		return a.call(&"render_transform")
	return a.global_transform


func _apply(t: float) -> void:
	var base := _anchor_xf()
	var a := base * from_local
	var b := base * to_local
	if follow_to != null and is_instance_valid(follow_to) and follow_to.is_inside_tree():
		b = follow_to.global_transform
	# Ease out: quick off the mark, settling into the hatch.
	var k := 1.0 - pow(1.0 - clampf(t, 0.0, 1.0), 2.2)
	# A box looks the same turned half round: take the shorter way.
	var ra := a.get_rotation()
	var rb := b.get_rotation()
	if absf(angle_difference(ra, rb)) > PI * 0.5:
		rb += PI
	var s := lerpf(scale_from, scale_to, k)
	global_transform = Transform2D(lerp_angle(ra, rb, k), Vector2(s, s), 0.0, a.origin.lerp(b.origin, k))
	# Stay solid for most of the way, fade at the end that is transparent.
	var fade := smoothstep(0.45, 1.0, t) if alpha_to < alpha_from else smoothstep(0.0, 0.5, t)
	modulate.a = lerpf(alpha_from, alpha_to, fade)


## Same look as cargo_box.gd, through the batched painter.
func _draw() -> void:
	var s := size_m * Game.PX_PER_M
	var r := Rect2(-s * 0.5, s)
	var pen := OnFootPainter.new(self, 0.5)
	pen.rect_flat(r.grow(5.0), Color(0, 0, 0.02, 0.3))
	pen.rect_flat(r, color.darkened(0.25))
	pen.rect_flat(r.grow(-2.0), color)
	var dark := color.darkened(0.3)
	var lite := color.lightened(0.18)
	var x := r.position.x + 5.0
	while x < r.end.x - 4.0:
		pen.line(Vector2(x, r.position.y + 3), Vector2(x, r.end.y - 3), dark, 1.4, false)
		pen.line(Vector2(x + 1.5, r.position.y + 3), Vector2(x + 1.5, r.end.y - 3), lite, 1.0, false)
		x += 4.5
	var c := 4.0
	for p: Vector2 in [r.position, Vector2(r.end.x - c, r.position.y), Vector2(r.position.x, r.end.y - c), r.end - Vector2(c, c)]:
		pen.rect_flat(Rect2(p, Vector2(c, c)), Color("1B2330"))
	pen.polyline(OnFootArt.rect_poly(r), Color(1, 1, 1, 0.85), 1.6, true)
	var ink := Color(1, 1, 1, 0.92) if color.get_luminance() < 0.6 else Color("1D3557")
	if brand != "":
		var fs := clampf(s.y * 0.42, 8.0, 18.0)
		pen.text(Vector2(0, fs * 0.36), brand, fs, ink, HORIZONTAL_ALIGNMENT_CENTER, s.x)
	pen.flush()
