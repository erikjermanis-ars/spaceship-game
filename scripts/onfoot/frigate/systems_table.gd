@tool
class_name SystemsTable
extends Interactable
## Engineering's master systems display: a long table-top screen showing the
## KESTREL from above (it reads well in a top-down game), each hull section
## coloured by its integrity, the deflector's charge as a ring, breaches as
## pulsing marks and the docking clamps when the ship is berthed. It is the
## damage model you can walk up to. E reads out the worst systems.

@export var size_m := Vector2(7.0, 1.8)

var _screen: Node2D
var _t := 0.0
var _ship: FrigateShip


func _ready() -> void:
	z_as_relative = false
	z_index = 1
	prompt = "Ship status"
	reach_m = 1.8
	prompt_offset_m = Vector2(0, -1.4)
	if Engine.is_editor_hint():
		return
	var body := StaticBody2D.new()
	body.collision_layer = Game.LAYER_WALK
	var cs := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = size_m * OnFootArt.PX - Vector2(0.4, 0.4)
	cs.shape = rs
	body.add_child(cs)
	add_child(body)
	_screen = Node2D.new()
	_screen.material = OnFootArt.unshaded()
	_screen.draw.connect(_draw_screen)
	add_child(_screen)
	_ship = get_tree().get_first_node_in_group(&"frigate") as FrigateShip


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _screen == null:
		return
	var before := int(_t * 10.0)
	_t += delta
	if int(_t * 10.0) != before:
		_screen.queue_redraw()


func _use(_by: Node2D) -> void:
	GameplayUtil.play_oneshot(self, GameplayUtil.load_audio("console_beep.wav"), -8.0, 1.1)
	if _ship == null:
		return
	var d := _ship.damage
	var parts: PackedStringArray = []
	for i in d.integrity.size():
		if d.integrity[i] < 95.0:
			parts.append("%s %d %%" % [FrigateDamage.NAMES[i], int(d.integrity[i])])
	var head := "SHIELDS %d %%" % int(d.shield)
	Game.toast("%s  ·  %s" % [head, "all sections nominal" if parts.is_empty() else "  ·  ".join(parts)], 5.0)


func _draw() -> void:
	var pen := OnFootPainter.new(self)
	var s := size_m * OnFootArt.PX
	var r := Rect2(-s * 0.5, s)
	pen.set_transform(OnFootArt.SHADOW_OFFSET)
	pen.rrect(r, 1.5, Color(0, 0.01, 0.03, 0.25))
	pen.set_transform()
	pen.rrect(r, 1.5, Color("C9D2DC"), OnFootArt.INK, 0.15)
	pen.rrect(r.grow(-0.9), 1.0, Color("0F1722"))
	pen.flush()


func _sec_col(v: float) -> Color:
	if v < 1.0:
		return Color(0.35, 0.1, 0.1)
	if v < 35.0:
		return OnFootArt.NAV_RED if fmod(_t, 0.6) < 0.4 else Color(0.5, 0.12, 0.12)
	if v < 70.0:
		return OnFootArt.AMBER
	return Color(0.4, 0.95, 0.85)


func _draw_screen() -> void:
	var pen := OnFootPainter.new(_screen)
	var s := size_m * OnFootArt.PX
	var r := Rect2(-s * 0.5, s).grow(-1.4)
	pen.rect_flat(r, Color(0.08, 0.18, 0.26, 0.6))
	if _ship == null:
		pen.flush()
		return
	var d := _ship.damage
	# ship top-down, bow to the right, fitted to the screen height
	var k := (r.size.y * 0.8) / (FrigateShape.HALF_BEAM * 2.0 * OnFootArt.PX)
	var c := r.get_center() + Vector2(-4.0, 0)
	for key: String in FrigateShape.PARTS:
		var poly := PackedVector2Array()
		var sum := Vector2.ZERO
		for v: Vector2 in FrigateShape.PARTS[key]:
			poly.append(c + v * k)
			sum += v
		var mid := sum / float(poly.size()) / OnFootArt.PX
		var col := _sec_col(d.integrity[FrigateDamage.section_at(mid)])
		pen.fill(poly, Color(col, 0.28))
		poly.append(poly[0])
		pen.polyline(poly, Color(col, 0.9), 0.12)
	# shield ring
	var half := Vector2(FrigateShape.HALF_LENGTH + 8.0, FrigateShape.HALF_BEAM + 6.0) * OnFootArt.PX * k
	var sh := clampf(d.shield / FrigateDamage.SHIELD_MAX, 0.0, 1.0)
	var n := 32
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 0.7) / n
		var on := float(i) / n < sh
		pen.line(c + Vector2(cos(a0) * half.x, sin(a0) * half.y), c + Vector2(cos(a1) * half.x, sin(a1) * half.y),
			Color(0.5, 0.9, 1.0, 0.8 if on else 0.12), 0.15)
	for b in d.breaches:
		var p: Vector2 = c + (b.pos as Vector2) * OnFootArt.PX * k
		pen.circle(p, 0.6 + 0.3 * sin(_t * 8.0), Color(1.0, 0.5, 0.2, 0.95))
	if _ship.dock.state == FrigateDock.State.LOCKED:
		pen.text(Vector2(r.end.x - 9.0, r.position.y + 2.2), "BERTH E2", 1.6, Color(OnFootArt.NAV_GREEN, 0.9))
	pen.text(Vector2(r.position.x + 7.0, r.position.y + 2.2), "SHIELD %d%%" % int(sh * 100.0), 1.5, Color(0.5, 0.9, 1.0, 0.9))
	pen.flush()
