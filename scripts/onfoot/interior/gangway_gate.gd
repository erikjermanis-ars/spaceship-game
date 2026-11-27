@tool
extends Node2D
## The inner door of a berth's gangway, in a station interior. It opens for
## you only while a frigate is clamped into `berth_id` with the gangway
## sealed; a status sign over it says which ship is in and what it is doing.
## (The world is suspended while you're indoors, so the frigate's state can't
## change under you: checking a couple of times a second is plenty.)

@export var door: NodePath
@export var sign_offset := Vector2(-14, -30)
@export var berth_id := "E2"

var _connected := false
var _ship_name := ""
var _t := 0.0
var _check := 0.0
var _sign: Node2D


func _ready() -> void:
	z_as_relative = false
	z_index = Game.Z_WALL_TOP + 1 if not Engine.is_editor_hint() else 13
	if Engine.is_editor_hint():
		return
	_sign = Node2D.new()
	_sign.material = OnFootArt.unshaded()
	_sign.draw.connect(_draw_sign)
	add_child(_sign)
	_refresh()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_t += delta
	_check -= delta
	if _check <= 0.0:
		_check = 0.5
		_refresh()
	_sign.queue_redraw()


func _refresh() -> void:
	var f := FrigateShip.docked_at(get_tree(), berth_id)
	_connected = f != null
	_ship_name = f.vehicle_name if f else "NO SHIP"
	var d := get_node_or_null(door) as SlidingDoor
	if d:
		d.locked = not _connected
		d.auto = _connected


func _draw_sign() -> void:
	var pen := OnFootPainter.new(_sign)
	var r := Rect2(sign_offset + Vector2(-2, -4), Vector2(30, 8))
	pen.rrect(r, 0.6, Color("17202B"), OnFootArt.INK, 0.15)
	var col := OnFootArt.NAV_GREEN if _connected else (OnFootArt.NAV_RED if fmod(_t, 1.0) < 0.6 else Color(0.5, 0.15, 0.15))
	pen.rect_flat(Rect2(r.position + Vector2(1, 1), Vector2(2.2, r.size.y - 2)), col)
	pen.text(r.position + Vector2(17, 3.4), "BERTH %s  ·  %s" % [berth_id, _ship_name], 2.2, Color(0.85, 0.92, 1.0, 0.9))
	pen.text(r.position + Vector2(17, 6.4), "GANGWAY SEALED" if _connected else "GANGWAY RETRACTED", 2.0, col)
	pen.flush()
