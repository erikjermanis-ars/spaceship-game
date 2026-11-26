@tool
extends StationModule
## Cargo Yard C: a big below-deck apron, colliding container stacks and a
## field of free-floating containers (RigidBody2D) that drift, tumble and get
## shoved by the player, by traffic and by the slewing crane.
## Local origin = yard centre, metres.

@export var container_count := 42:
	set(v): container_count = v; queue_rebuild()
@export var seed := 7:
	set(v): seed = v; queue_rebuild()

## Static stacks (m): Rect2(position, size).
const STACKS := [
	Rect2(-220, -70, 125, 45),
	Rect2(-220, 5, 125, 45),
	Rect2(-220, 80, 125, 50),
	Rect2(150, -75, 80, 60),
	Rect2(150, 55, 80, 75),
]
## Zones (m) where free containers spawn, with counts (scaled to container_count).
const ZONES := [
	[Rect2(-215, -150, 430, 55), 12],
	[Rect2(-80, 150, 300, 45), 9],
	[Rect2(95, -70, 40, 200), 5],
	[Rect2(-215, -18, 115, 18), 3],
	[Rect2(-215, 55, 115, 20), 3],
	[Rect2(-285, -60, 45, 180), 4],
	[Rect2(-60, -80, 40, 30), 2],
	[Rect2(240, -40, 50, 150), 4],
	[Rect2(-22, 60, 34, 30), 2],   # inside the crane's slew arc: it bats them around
]
const CRANE_PIVOT := Vector2(70, 30)

var _boxes_spawned := false


func _build() -> void:
	# --- apron deck with lane markings
	var apron := A.rounded_rect(Rect2(m(-245, -92), m(490, 245)), 160.0)
	deck(apron, 8.0, Color("1A222E"), Color("212B39"), Color("2A3648"), Color("50637C"))
	# painted lanes + bay numbers
	for y: float in [-8.0, 66.0]:
		line(Band.DECK, m(-225, y), m(-90, y), Color(1.0, 0.8, 0.3, 0.4), 5.0)
	for i in 3:
		var r: Rect2 = STACKS[i]
		text(Band.DECK, m(r.position.x - 14, r.get_center().y), "C%d" % (i + 1), 80, Color(0.85, 0.9, 1.0, 0.35), -PI * 0.5)
	for i in range(3, 5):
		var r: Rect2 = STACKS[i]
		text(Band.DECK, m(r.end.x + 12, r.get_center().y), "C%d" % (i + 1), 80, Color(0.85, 0.9, 1.0, 0.35), PI * 0.5)
	text(Band.DECK, m(10, 128), "CARGO YARD C", 150, Color(0.85, 0.9, 1.0, 0.12))
	# crane slew circle warning ring on the deck
	arc(Band.DECK, m(CRANE_PIVOT.x, CRANE_PIVOT.y), 100.0 * PX, PI * 0.7, PI * 1.3, Color(1.0, 0.69, 0.0, 0.45), 10.0, 64)
	arc(Band.DECK, m(CRANE_PIVOT.x, CRANE_PIVOT.y), 103.0 * PX, PI * 0.7, PI * 1.3, Color(1.0, 0.69, 0.0, 0.2), 4.0, 64)
	for e: float in [-1.0, 1.0]:
		var a := PI + e * PI * 0.25
		var p := m(CRANE_PIVOT.x, CRANE_PIVOT.y) + Vector2(cos(a), sin(a)) * 100.0 * PX
		hazard(Band.DECK, A.obox(p, Vector2(cos(a), sin(a)), 16.0 * PX, 3.0 * PX), 0.9)
	# apron edge lights
	for i in 24:
		var t := (i + 0.5) / 24.0
		lamp(m(lerpf(-235, 235, t), -90), A.CYAN, 30.0, 0)
		lamp(m(lerpf(-235, 235, t), 151), A.CYAN, 30.0, 0)
	# --- stacks: one collider each, painted as a grid of containers
	var idx := seed * 1000
	for r: Rect2 in STACKS:
		var poly := A.rect_m(r.position.x, r.position.y, r.end.x, r.end.y)
		hull(poly, &"steel", [], {"bevel": 0.4})
		var D := Band.STRUCT_DETAIL
		var cw := 12.2
		var ch := 2.44
		var y := r.position.y + 1.0
		while y + ch <= r.end.y - 0.8:
			var x := r.position.x + 1.0
			while x + 6.0 <= r.end.x - 0.8:
				idx += 1
				var hsh := A.hash01(idx, seed)
				var len_m := cw if hsh > 0.35 else 6.1
				if x + len_m > r.end.x - 0.8:
					len_m = 6.1
				var lv: Dictionary = A.LIVERIES[int(hsh * 991.0) % A.LIVERIES.size()]
				var col: Color = lv["color"]
				if A.hash01(idx, seed + 1) < 0.06:
					col = Color("2A3446")  # empty slot
				var cell := A.rect_m(x, y, x + len_m - 0.3, y + ch - 0.3)
				fill(D, cell, col)
				outline(D, cell, col.darkened(0.5), 1.2, true, false)
				x += len_m
			y += ch
		rim(D, poly, Color.WHITE, A.PANEL, true, 2.4)
		beacon(m(r.position.x + 1.5, r.position.y + 1.5), A.AMBER, 70.0, A.hash01(idx, 4))
		beacon(m(r.end.x - 1.5, r.end.y - 1.5), A.AMBER, 70.0, A.hash01(idx, 5))


func _after_build() -> void:
	var CargoBox := preload("res://scripts/level/cargo_box.gd")
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var placed: Array[Vector2] = []
	var total_w := 0
	for z in ZONES:
		total_w += int(z[1])
	var serial := 400100 + seed
	for z in ZONES:
		var rect: Rect2 = z[0]
		var n := int(round(float(z[1]) * container_count / total_w))
		var tries := 0
		while n > 0 and tries < 200:
			tries += 1
			var p := Vector2(rng.randf_range(rect.position.x, rect.end.x), rng.randf_range(rect.position.y, rect.end.y))
			if _blocked(p, placed):
				continue
			placed.append(p)
			n -= 1
			var big := rng.randf() < 0.35
			var size := Vector2(12.2 if big else 6.1, 2.44)
			var lv: Dictionary = A.LIVERIES[rng.randi() % A.LIVERIES.size()]
			var box: RigidBody2D = CargoBox.new()
			serial += rng.randi_range(17, 311)
			box.setup(size, lv["color"], lv["name"], "MRDU %06d" % serial)
			box.name = "Cargo%02d" % placed.size()
			box.position = p * PX
			box.rotation = rng.randf_range(-PI, PI) if rng.randf() < 0.5 else rng.randf_range(-0.2, 0.2) + (PI * 0.5 if rng.randf() < 0.3 else 0.0)
			if not Engine.is_editor_hint():
				# gentle initial drift so the yard feels alive
				box.linear_velocity = Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * 4.0
				box.angular_velocity = rng.randf_range(-0.06, 0.06)
			add_child(box)
			_generated.append(box)


func _blocked(p: Vector2, placed: Array[Vector2]) -> bool:
	for q in placed:
		if p.distance_to(q) < 14.0:
			return true
	for r: Rect2 in STACKS:
		if r.grow(8.0).has_point(p):
			return true
	if p.distance_to(CRANE_PIVOT) < 16.0:
		return true
	return false
