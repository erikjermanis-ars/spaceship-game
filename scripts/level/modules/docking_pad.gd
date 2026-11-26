@tool
extends StationModule
## A landing pad: below-deck platform with hazard border, target markings,
## painted number and edge lights, plus the contract's docking trigger:
## an Area2D in group `docking_pad` (layer TRIGGERS, mask PLAYER) whose +X
## is the heading the ship should face when docked (= this node's +X).

@export var pad_name := "Pad 1":
	set(v): pad_name = v; queue_rebuild()
@export var label := "01":
	set(v): label = v; queue_rebuild()
@export var size_m := Vector2(48, 46):
	set(v): size_m = v; queue_rebuild()
## Extra platform length behind the pad (-X), e.g. to tuck under a pier.
@export var tail_m := 12.0:
	set(v): tail_m = v; queue_rebuild()
@export var trigger_size_m := Vector2(26, 26)
## Colliding light posts at the two front corners.
@export var posts := true:
	set(v): posts = v; queue_rebuild()
@export var accent := Color("2A9D8F"):
	set(v): accent = v; queue_rebuild()

var area: Area2D


func _build() -> void:
	var hx := size_m.x * 0.5 * PX
	var hy := size_m.y * 0.5 * PX
	var plat := A.rounded_rect(Rect2(Vector2(-hx - tail_m * PX, -hy), Vector2(size_m.x + tail_m, size_m.y) * PX), 30.0)
	deck(plat, 4.0, Color("1B2431"), Color("243042"), Color("2C3A4E"), Color("6A7F99"))
	# Hazard border (four strips) around the pad square.
	var b := 2.2 * PX
	var inset := 1.4 * PX
	var r := Rect2(Vector2(-hx + inset, -hy + inset), Vector2(hx - inset, hy - inset) * 2.0)
	hazard(Band.DECK, A.rect_poly(Rect2(r.position, Vector2(r.size.x, b))), 1.1)
	hazard(Band.DECK, A.rect_poly(Rect2(Vector2(r.position.x, r.end.y - b), Vector2(r.size.x, b))), 1.1)
	hazard(Band.DECK, A.rect_poly(Rect2(Vector2(r.position.x, r.position.y + b), Vector2(b, r.size.y - 2 * b))), 1.1, -PI * 0.25)
	hazard(Band.DECK, A.rect_poly(Rect2(Vector2(r.end.x - b, r.position.y + b), Vector2(b, r.size.y - 2 * b))), 1.1, -PI * 0.25)
	# Target circle + heading arrow.
	var rad := minf(hx, hy) * 0.62
	arc(Band.DECK, Vector2.ZERO, rad, 0, TAU, Color(0.92, 0.95, 1.0, 0.85), 5.0, 64)
	arc(Band.DECK, Vector2.ZERO, rad - 14, 0, TAU, Color(accent, 0.9), 3.0, 64)
	fill(Band.DECK, PackedVector2Array([Vector2(rad * 0.75, 0), Vector2(rad * 0.45, -36), Vector2(rad * 0.45, 36)]), Color(1, 1, 1, 0.85))
	# Big painted pad number (reads as "bottom" relative to heading).
	# Painted number reads upright on screen whatever the pad's heading.
	# Kept out of the ship's footprint: the number sits in a corner between the
	# target circle and the hazard border, the name just inside the stripes.
	text(Band.DECK, Vector2(-hx + inset + b + 56, -hy + inset + b + 50), label, int(rad * 0.45), Color(0.55, 0.66, 0.78, 0.38), -rotation)
	text(Band.DECK, Vector2(0, hy - inset - b - 22), pad_name.to_upper(), 24, Color(0.75, 0.85, 0.95, 0.75), -rotation)
	# Edge lights along the front and sides (cyan) + green "cleared" lamps.
	var n := 6
	for i in n:
		var t := (i + 0.5) / n
		lamp(Vector2(hx + 4, lerpf(-hy, hy, t)), A.CYAN, 32.0, 0)
		lamp(Vector2(lerpf(-hx, hx, t), -hy - 4), A.CYAN, 26.0, 0)
		lamp(Vector2(lerpf(-hx, hx, t), hy + 4), A.CYAN, 26.0, 0)
	glow(Vector2.ZERO, Color(accent, 0.18), rad * 1.6, Band.DECK_FX)
	if posts:
		for s: float in [-1.0, 1.0]:
			var pc := Vector2(hx + 10, s * (hy + 10))
			hull(A.circle_poly(pc, 1.6 * PX, 12), &"grey", [], {"bevel": 0.4})
			beacon(pc, A.NAV_GREEN if s > 0 else A.NAV_RED, 70.0, 0.1)


func _after_build() -> void:
	area = Area2D.new()
	area.name = "DockTrigger"
	area.collision_layer = G.LAYER_TRIGGERS
	area.collision_mask = G.LAYER_PLAYER
	area.monitorable = false
	area.set_meta("pad_name", pad_name)
	var cs := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = trigger_size_m * PX
	cs.shape = rs
	area.add_child(cs)
	add_child(area)
	_generated.append(area)
	if not Engine.is_editor_hint():
		area.add_to_group(&"docking_pad")
