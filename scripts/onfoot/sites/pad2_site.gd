@tool
extends Node2D
## Pad 2 on-foot extras, authored in WORLD coordinates with the origin on the
## spaceport pier's west wall (x = 560 m) at the airlock door (y = 131 m).
## Local -X = out onto the pad, +X = into the pier.
##
##   * Airlock 7B vestibule on the pier wall (a manual heavy SlidingDoor)
##     -> leads to the Pier 7 crew concourse interior.
##   * Painted pedestrian walkway from the ship to the airlock.
##   * Props: cargo crates, a fuel cart with its hose, floodlight pools.

signal enter_requested

const INTERIOR := "res://scenes/onfoot/interiors/pier7_concourse.tscn"
const VEST := Rect2(-16, -26, 16, 52)        # vestibule footprint (px)
const DOOR_W_M := 1.6

## [centre px, size m, rotation, livery]
const CRATES := [
	[Vector2(-44, 62), Vector2(2.4, 1.2), 0.0, Color("E76F51")],
	[Vector2(-44, 75), Vector2(2.4, 1.2), 0.0, Color("2A9D8F")],
	[Vector2(-70, 70), Vector2(1.2, 1.2), 0.25, Color("F4A261")],
	[Vector2(-52, -60), Vector2(1.2, 1.2), -0.12, Color("4EA8DE")],
]
const CART := Rect2(-96, -218, 28, 14)

var door: SlidingDoor
var _beacon_t := 0.0
var _cycling := false
var _beacon: Sprite2D


## Batched painter used by the draw callbacks (see OnFootPainter).
var pen: OnFootPainter

func _ready() -> void:
	z_as_relative = false
	z_index = Game.Z_BELOW_DECK + 9 if not Engine.is_editor_hint() else -41
	if Engine.is_editor_hint():
		return
	# Close-up pier facade over the flight-scale pier art near the pad.
	var facade := Node2D.new()
	facade.name = "PierFacade"
	facade.z_as_relative = false
	facade.z_index = Game.Z_STRUCTURE + 4     # above every station structure band
	facade.draw.connect(_draw_facade.bind(facade))
	add_child(facade)
	# Vestibule roof + sign (above the walker: you walk *under* it to enter).
	var roof := Node2D.new()
	roof.name = "Roof"
	roof.z_as_relative = false
	roof.z_index = Game.Z_WALL_TOP
	roof.draw.connect(_draw_roof.bind(roof))
	add_child(roof)
	door = SlidingDoor.new()
	door.name = "AirlockDoor"
	door.position = Vector2(VEST.position.x, 0)
	door.width_m = DOOR_W_M
	door.thickness_m = 0.5
	door.auto = false
	door.heavy = true
	door.leaf_color = Color("D9E0E7")
	door.accent = OnFootArt.AMBER
	add_child(door)
	_beacon = OnFootArt.glow_sprite(roof, Vector2(-8, -20), OnFootArt.AMBER, 14.0, 1)
	_beacon.modulate.a = 0.0
	# Warm floodlight pools on the deck either side of the door.
	for y: float in [-30.0, 30.0]:
		var g := OnFootArt.glow_sprite(self, Vector2(-26, y), Color(1.0, 0.86, 0.6, 0.22), 40.0)
		g.z_index = 0
	_build_collision()
	var use := CallbackInteractable.new()
	use.name = "EnterAirlock"
	use.prompt = "Enter airlock 7B"
	use.reach_m = 2.0
	use.position = Vector2(VEST.position.x - 8, 0)
	use.prompt_offset_m = Vector2(-0.6, -1.6)
	use.on_use = func(_by: Node2D) -> void: enter_requested.emit()
	add_child(use)


func get_interior_path() -> String:
	return INTERIOR


## Where the walker stands outside / ends up inside the vestibule (global).
func outside_point() -> Vector2:
	return to_global(Vector2(VEST.position.x - 22, 0))


func inside_point() -> Vector2:
	return to_global(Vector2(-6, 0))


func set_cycling(on: bool) -> void:
	_cycling = on


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _beacon == null:
		return
	_beacon_t += delta
	var want := 1.0 if _cycling or (door and door.open_t > 0.02 and door.open_t < 0.98) else 0.0
	_beacon.modulate.a = want * pow(maxf(0.0, sin(_beacon_t * 7.0)), 3.0)


func _build_collision() -> void:
	var body := StaticBody2D.new()
	body.collision_layer = Game.LAYER_WALK
	body.collision_mask = 0
	var hw := DOOR_W_M * 0.5 * OnFootArt.PX
	var rects: Array[Rect2] = [
		Rect2(VEST.position, Vector2(VEST.size.x, -VEST.position.y - hw)),         # north block
		Rect2(Vector2(VEST.position.x, hw), Vector2(VEST.size.x, VEST.end.y - hw)),  # south block
		CART.grow(-0.5),
	]
	for c in CRATES:
		var sz: Vector2 = c[1] * OnFootArt.PX
		rects.append(Rect2(c[0] - sz * 0.5, sz))
	for r in rects:
		var cs := CollisionShape2D.new()
		var rs := RectangleShape2D.new()
		rs.size = r.size
		cs.shape = rs
		cs.position = r.get_center()
		body.add_child(cs)
	add_child(body)


# ------------------------------------------------------------------ art ---

func _draw() -> void:
	pen = OnFootPainter.new(self)
	_paint_draw()
	pen.flush()


func _paint_draw() -> void:
	var px := OnFootArt.PX
	# --- walkway: lane from the pad along y = 0 to the door, plus a branch north
	var lane_c := Color(0.92, 0.95, 1.0, 0.55)
	var hw := 8.0
	_dashes(Vector2(-330, -hw), Vector2(VEST.position.x - 2, -hw), lane_c)
	_dashes(Vector2(-330, hw), Vector2(VEST.position.x - 2, hw), lane_c)
	_dashes(Vector2(-300 - hw, -hw), Vector2(-300 - hw, -95), lane_c)
	_dashes(Vector2(-300 + hw, -hw), Vector2(-300 + hw, -95), lane_c)
	var x := -280.0
	while x < -40.0:
		var chev := PackedVector2Array([Vector2(x, -4.5), Vector2(x + 4.5, 0), Vector2(x, 4.5), Vector2(x - 1.6, 4.5), Vector2(x + 2.9, 0), Vector2(x - 1.6, -4.5)])
		pen.fill(chev, Color(0.5, 0.9, 1.0, 0.35))
		x += 28.0
	pen.text(Vector2(-120, -11), "AIRLOCK 7B  ·  PIER 7 CREW CONCOURSE", 4.2, Color(0.85, 0.92, 1.0, 0.55))
	pen.text(Vector2(-300, -100), "WALKWAY", 3.6, Color(0.85, 0.92, 1.0, 0.45))
	# stop line in front of the door
	pen.hazard(Rect2(Vector2(VEST.position.x - 7, -hw - 2), Vector2(4, hw * 2 + 4)), 1.6)

	# --- fuel cart with a hose running to a wall socket
	var cart := CART
	var so := OnFootArt.SHADOW_OFFSET * 1.6
	pen.rect_flat(Rect2(cart.position + so, cart.size), OnFootArt.SHADOW)
	pen.rrect(cart, 1.5, Color("C9D2DC"), OnFootArt.INK, 0.18)
	pen.rrect(Rect2(cart.position + Vector2(2, 2), Vector2(15, 10)), 4.0, Color("E9EEF3"), OnFootArt.INK, 0.15)   # tank
	pen.line(cart.position + Vector2(9.5, 2.5), cart.position + Vector2(9.5, 11.5), Color("1D3557"), 0.6)
	pen.rect(Rect2(cart.position + Vector2(19, 2), Vector2(7, 10)), Color("4A5563"), OnFootArt.INK, 0.12)   # pump
	pen.circle(cart.position + Vector2(22.5, 5), 1.0, Color(0.4, 1.0, 0.6))
	pen.text(cart.position + Vector2(9.5, 8.2), "H2", 3.0, Color("1D3557"))
	for wx: float in [3.0, 25.0]:
		for wy: float in [-0.6, cart.size.y + 0.6]:
			pen.rrect(Rect2(cart.position + Vector2(wx - 1.6, wy - 0.7), Vector2(3.2, 1.4)), 0.5, Color("2B3440"))
	var hose := PackedVector2Array()
	var a := cart.position + Vector2(26, 7)
	var b := Vector2(-1.5, -196)
	for i in 13:
		var t := i / 12.0
		hose.append(a.lerp(b, t) + Vector2(0, sin(t * PI) * 9.0))
	pen.polyline(hose, Color(0.1, 0.12, 0.16), 1.1)
	pen.polyline(hose, Color("FFB000"), 0.45)
	pen.rect(Rect2(Vector2(-3, -200), Vector2(3, 8)), Color("8E9AA8"), OnFootArt.INK, 0.12)

	# --- cargo crates
	for c in CRATES:
		_crate(c[0], c[1] * px, c[2], c[3])


func _crate(c: Vector2, size: Vector2, rot: float, livery: Color) -> void:
	var so := OnFootArt.SHADOW_OFFSET * 1.4
	pen.set_transform(c + so, rot)
	pen.rect_flat(Rect2(-size * 0.5, size), OnFootArt.SHADOW)
	pen.set_transform(c, rot)
	var r := Rect2(-size * 0.5, size)
	pen.rect(r, livery.darkened(0.1), OnFootArt.INK, 0.15)
	pen.rect(r.grow(-1.0), livery, Color(0, 0, 0, 0))
	pen.line(r.position + Vector2(1.0, 1.0), r.end - Vector2(1.0, 1.0), livery.darkened(0.25), 0.4)
	pen.line(Vector2(r.position.x + 1.0, r.end.y - 1.0), Vector2(r.end.x - 1.0, r.position.y + 1.0), livery.darkened(0.25), 0.4)
	pen.rect_flat(Rect2(Vector2(-2.2, -1.2), Vector2(4.4, 2.4)), Color(0.95, 0.96, 0.98, 0.9))
	pen.set_transform()


func _dashes(a: Vector2, b: Vector2, col: Color) -> void:
	var d := a.distance_to(b)
	var dir := (b - a) / d
	var s := 0.0
	while s < d:
		pen.line(a + dir * s, a + dir * minf(s + 5.0, d), col, 0.7)
		s += 9.0


func _draw_roof(ci: Node2D) -> void:
	pen = OnFootPainter.new(ci)
	_paint_draw_roof(ci)
	pen.flush()


func _paint_draw_roof(ci: Node2D) -> void:
	var r := VEST
	pen.rect_flat(Rect2(r.position + Vector2(1.2, 2.0), r.size), Color(0, 0.01, 0.03, 0.35))
	pen.rrect(r, 1.2, Color("E9EEF3"), OnFootArt.INK, 0.25)
	pen.rrect(r.grow(-1.4), 0.8, Color("DCE3EA"), Color("BFC9D4"), 0.15)
	pen.rect_flat(Rect2(Vector2(r.position.x + 3, r.position.y + 2), Vector2(2.2, r.size.y - 4)), Color("1D3557"))
	pen.rect_flat(Rect2(Vector2(r.position.x + 5.6, r.position.y + 2), Vector2(0.8, r.size.y - 4)), Color("2A9D8F"))
	# vents + panel seams
	for i in 4:
		pen.rect_flat(Rect2(Vector2(-7.5, -17 + i * 1.4), Vector2(4.5, 0.6)), Color("8E9AA8"))
		pen.rect_flat(Rect2(Vector2(-7.5, 12 + i * 1.4), Vector2(4.5, 0.6)), Color("8E9AA8"))
	pen.line(Vector2(r.position.x + 1.4, -9), Vector2(-1.4, -9), Color("BFC9D4"), 0.25)
	pen.line(Vector2(r.position.x + 1.4, 9), Vector2(-1.4, 9), Color("BFC9D4"), 0.25)
	pen.text(Vector2(-8.8, 3.2), "7B", 7.0, Color("1D3557"))
	# beacon housing + pressure status lamp
	pen.circle(Vector2(-8, -20), 1.6, Color("8E9AA8"), OnFootArt.INK, 0.15)
	pen.circle(Vector2(-8, -20), 1.0, Color(1.0, 0.69, 0.0))
	pen.circle(Vector2(-8, 20), 1.2, Color("4A5563"), OnFootArt.INK, 0.12)
	pen.circle(Vector2(-8, 20), 0.7, OnFootArt.NAV_GREEN)


## The pier spine's roof (x 560-585 m) redrawn at walking scale for the
## stretch you can see from Pad 2: same colours and layout as the flight art
## (window strips, teal and navy bands, edge lamps) but with framed windows,
## plate seams, vents and fasteners. A local LOD patch: only where the player
## can actually stand close to it.
func _draw_facade(ci: Node2D) -> void:
	pen = OnFootPainter.new(ci)
	_paint_draw_facade(ci)
	pen.flush()


func _paint_draw_facade(ci: Node2D) -> void:
	var px := OnFootArt.PX
	var y0 := -48.0 * px          # world y 83 .. 179 m
	var y1 := 48.0 * px
	var w := 25.0 * px
	pen.rect_flat(Rect2(Vector2(0, y0), Vector2(w, y1 - y0)), Color("E9EEF3"))
	# plate seams (3 m) + fasteners
	var y := ceilf(y0 / 30.0) * 30.0
	while y < y1:
		pen.line(Vector2(4.4 * px, y), Vector2(w - 4.4 * px, y), Color("C9D2DC"), 0.3)
		for x in [6.0, 9.0, 16.0, 19.0, 21.0]:
			pen.circle(Vector2(x * px, y + 1.2), 0.25, Color("B4BFCB"))
		y += 30.0
	pen.line(Vector2(10.5 * px, y0), Vector2(10.5 * px, y1), Color("D3DBE3"), 0.3)
	# window strips: framed panes, some lit, some dark (cabins)
	for wx: float in [2.4 - 0.9, 22.6 - 0.9]:
		pen.rect_flat(Rect2(Vector2(wx * px, y0), Vector2(1.8 * px, y1 - y0)), Color("2B3440"))
		var i := 0
		var wy := y0 + 0.6
		while wy < y1 - 1.0:
			var lit := LevelArt.hash01(i + int(wx * 10.0), 31) > 0.3
			var pane := Rect2(Vector2(wx * px + 1.6, wy + 0.5), Vector2(1.8 * px - 3.2, 10.0))
			pen.rect_flat(pane, Color("FFE2A0") if lit else Color("3A4A60"))
			if lit:
				pen.rect_flat(Rect2(pane.position, Vector2(pane.size.x, 2.0)), Color(1, 1, 1, 0.35))
			pen.polyline(OnFootArt.rect_poly(pane), Color("1D2733"), 0.4, true)
			wy += 12.0
			i += 1
	pen.rect_flat(Rect2(Vector2(11.2 * px, y0), Vector2(2.6 * px, y1 - y0)), Color("2A9D8F"))
	pen.line(Vector2(11.2 * px + 1.0, y0), Vector2(11.2 * px + 1.0, y1), Color("5CC2B5"), 0.4)
	pen.rect_flat(Rect2(Vector2(14.6 * px, y0), Vector2(0.8 * px, y1 - y0)), Color("1D3557"))
	# roof vents and a service hatch
	for vy: float in [-30.0, 8.0, 34.0]:
		var vr := Rect2(Vector2(6.2 * px, vy * px * 0.1 * 10.0 - 8.0), Vector2(3.2 * px, 16.0))
		pen.rect(vr, Color("C9D2DC"), Color("8E9AA8"), 0.25)
		for k in 6:
			pen.line(Vector2(vr.position.x + 2.0, vr.position.y + 2.0 + k * 2.4), Vector2(vr.end.x - 2.0, vr.position.y + 2.0 + k * 2.4), Color("6D7A8A"), 0.5)
	pen.rrect(Rect2(Vector2(17.0 * px, -60.0), Vector2(4.0 * px, 40.0)), 2.0, Color("DCE3EA"), Color("8E9AA8"), 0.3)
	pen.hazard(Rect2(Vector2(17.0 * px + 2.0, -58.0), Vector2(4.0 * px - 4.0, 3.0)), 1.6)
	# lit edge (west face) + edge lamps every 16 m (matches the flight art)
	pen.line(Vector2(0.4, y0), Vector2(0.4, y1), Color(1, 1, 1), 0.8)
	pen.line(Vector2(w - 0.4, y0), Vector2(w - 0.4, y1), Color("8E9AA8"), 0.8)
	for ly: float in [-6.0, 10.0, 26.0, -22.0, -38.0, 42.0]:
		pen.circle(Vector2(0.9 * px, ly * px), 1.0, Color("7FE6FF"))
		pen.circle(Vector2(w - 0.9 * px, ly * px), 1.0, Color("7FE6FF"))
	# painted pier name, readable from the pad
	pen.text(Vector2(6.0 * px, -30.0 * px), "PIER 7", 22.0, Color(0.11, 0.21, 0.34, 0.85), HORIZONTAL_ALIGNMENT_CENTER, -1.0, true, -PI * 0.5)
