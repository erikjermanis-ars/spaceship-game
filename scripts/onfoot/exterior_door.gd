class_name ExteriorDoor
extends Node2D
## An airlock door in the station's outer wall, seen from the deck outside
## (one per ExteriorDoors entry on the current walk site). The node sits where
## you stand in front of it; local +X points into the wall. It offers the
## same handful of calls a pad's extras scene does (Pad 2's vestibule), so the
## director walks you in the same way: get_interior_path(), `door`,
## outside_point(), inside_point(), set_cycling().

signal enter_requested

const DEPTH := 12.0          ## px from the standing point to the door leaf

var def := {}
var door: SlidingDoor
## The Airlock node (in the interior) this door leads to.
var airlock_name := "Airlock"

var pen: OnFootPainter
var _beacon: Sprite2D
var _cycling := false
var _t := 0.0


func setup(d: Dictionary) -> void:
	def = d
	airlock_name = String(d.get("airlock", "Airlock"))
	global_position = d.at
	global_rotation = float(d.facing)


func _ready() -> void:
	z_as_relative = false
	z_index = Game.Z_STRUCTURE + 4      # over the station's own wall art
	door = SlidingDoor.new()
	door.name = "Leaf"
	door.position = Vector2(DEPTH, 0)
	door.width_m = 1.6
	door.thickness_m = 0.5
	door.auto = false
	door.heavy = true
	door.leaf_color = Color("D9E0E7")
	door.accent = OnFootArt.AMBER
	add_child(door)
	_beacon = OnFootArt.glow_sprite(self, Vector2(DEPTH - 2.0, -14.0), OnFootArt.AMBER, 12.0, 1)
	_beacon.modulate.a = 0.0
	var pool := OnFootArt.glow_sprite(self, Vector2(-6.0, 0.0), Color(1.0, 0.86, 0.6, 0.2), 34.0)
	pool.z_index = 0
	var use := CallbackInteractable.new()
	use.name = "Enter"
	use.prompt = "Enter airlock  ·  %s" % String(def.get("label", "")).capitalize()
	use.reach_m = 2.0
	use.position = Vector2(2.0, 0)
	use.prompt_offset_m = Vector2(0, -1.8)
	use.on_use = func(_by: Node2D) -> void: enter_requested.emit()
	add_child(use)


func get_interior_path() -> String:
	return String(def.get("scene", ""))


func outside_point() -> Vector2:
	return global_position


func inside_point() -> Vector2:
	return to_global(Vector2(DEPTH - 3.0, 0))


func set_cycling(on: bool) -> void:
	_cycling = on


func _process(delta: float) -> void:
	_t += delta
	var want := 1.0 if _cycling or (door and door.open_t > 0.02 and door.open_t < 0.98) else 0.0
	_beacon.modulate.a = want * pow(maxf(0.0, sin(_t * 7.0)), 3.0)


func _draw() -> void:
	pen = OnFootPainter.new(self)
	# threshold: a hazard strip on the deck and a painted walkway stub
	pen.hazard(Rect2(Vector2(DEPTH - 7.0, -11.0), Vector2(4.0, 22.0)), 2.0)
	pen.rect_flat(Rect2(Vector2(-22.0, -8.5), Vector2(DEPTH + 14.0, 0.6)), Color(0.92, 0.95, 1.0, 0.45))
	pen.rect_flat(Rect2(Vector2(-22.0, 7.9), Vector2(DEPTH + 14.0, 0.6)), Color(0.92, 0.95, 1.0, 0.45))
	# the door frame set into the wall
	var frame := Rect2(Vector2(DEPTH - 3.0, -13.0), Vector2(9.0, 26.0))
	pen.rrect(frame, 1.2, Color("C9D2DC"), OnFootArt.INK, 0.2)
	pen.rect_flat(Rect2(Vector2(DEPTH - 1.6, -9.0), Vector2(6.0, 18.0)), Color("1B2533"))
	# status lamps either side
	for s: float in [-1.0, 1.0]:
		pen.circle(Vector2(DEPTH + 1.0, 11.0 * s), 0.9, OnFootArt.NAV_GREEN)
	# name plate, readable from the deck
	pen.rrect(Rect2(Vector2(DEPTH + 7.0, -16.0), Vector2(5.0, 32.0)), 0.8, Color("1D3557"))
	pen.text(Vector2(DEPTH + 9.6, 0.0), String(def.get("label", "AIRLOCK")), 2.6, Color(0.92, 0.95, 1.0, 0.95), HORIZONTAL_ALIGNMENT_CENTER, -1.0, true, PI * 0.5)
	pen.flush()
