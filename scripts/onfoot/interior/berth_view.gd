@tool
extends Node2D
## What you see out of the Berth E2 gangway's windows: the KESTREL's hull
## right alongside (when it is clamped in), its two clamp pylons and the
## gangway's own shell. The world is suspended while you're indoors, so this
## is drawn by the interior itself, from the frigate's real transform and
## art, the same way PierExterior paints the pier around the concourse.
## Unshaded: it is sunlit outside.

const PX := 10.0

var _ship_root: Node2D
var _berth: Node2D


func _ready() -> void:
	z_as_relative = false
	z_index = -9
	if Engine.is_editor_hint():
		return
	material = OnFootArt.unshaded()
	var f := get_tree().get_first_node_in_group(&"frigate") as Node2D
	var berth: Node2D = null
	for n in get_tree().get_nodes_in_group(&"frigate_berth"):
		if f and String(n.get(&"berth_id")) == String(f.get(&"berth_id")):
			berth = n
	_berth = berth
	if berth:
		var pylons := Node2D.new()
		pylons.use_parent_material = true
		pylons.draw.connect(_draw_pylons.bind(pylons))
		add_child(pylons)
		pylons.global_transform = berth.global_transform
	# Only a ship that is actually clamped in shows outside.
	if f == null or not f.has_method(&"gangway_ready") or not bool(f.call(&"gangway_ready")):
		return
	_ship_root = Node2D.new()
	_ship_root.name = "Frigate"
	_ship_root.use_parent_material = true
	add_child(_ship_root)
	_ship_root.global_transform = (f as Node2D).global_transform
	var livery: Color = f.get(&"livery")
	for l in [["frigate_hull", 0.5, Color.WHITE], ["frigate_livery", 1.0, livery]]:
		var s := Sprite2D.new()
		s.texture = load("res://assets/art/ship/%s.svg" % l[0])
		s.scale = Vector2.ONE * float(l[1])
		s.modulate = l[2]
		s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		s.use_parent_material = true
		_ship_root.add_child(s)
	var lights := Sprite2D.new()
	lights.texture = load("res://assets/art/ship/frigate_lights.svg")
	lights.material = OnFootArt.add_unshaded()
	lights.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_ship_root.add_child(lights)


## The clamp pylons and the extended gangway shell, in the berth's frame
## (same geometry as FrigateBerth, simplified for the close-up).
func _draw_pylons(ci: Node2D) -> void:
	var pen := OnFootPainter.new(ci, 0.3)
	var side := float(_berth.get(&"pier_side"))
	var dist := float(_berth.get(&"pier_dist_m"))
	for h: Vector2 in [FrigateShape.CLAMP_FWD, FrigateShape.CLAMP_AFT]:
		var tip := absf(h.y) + 3.5
		var arm := Rect2(Vector2(h.x - 3.6, minf(tip * side, dist * side)) * PX, Vector2(7.2, absf(dist - tip)) * PX)
		pen.rect(arm, Color("E3E9EF"), Color("4A5563"), 1.0)
		pen.rect_flat(Rect2(Vector2((h.x - 1.0) * PX, arm.position.y), Vector2(20.0, arm.size.y)), Color("1D3557"))
		var head := Rect2(Vector2(h.x - 6.5, minf(tip * side, (tip + 5.0) * side)) * PX, Vector2(13.0, 5.0) * PX)
		pen.rect(head, Color("C9D2DC"), Color("4A5563"), 1.0)
		pen.hazard(Rect2(head.position + Vector2(4, 4), Vector2(30, head.size.y - 8)), 6.0)
		pen.hazard(Rect2(Vector2(head.end.x - 34, head.position.y + 4), Vector2(30, head.size.y - 8)), 6.0)
	# gangway shell around the walkway tube
	var a: Vector2 = FrigateShape.AIRLOCK
	var shell := Rect2(Vector2(a.x - 2.2, minf((a.y + 0.2) * side, (dist - 1.0) * side)) * PX, Vector2(4.4, absf(dist - 1.0 - a.y - 0.2)) * PX)
	pen.rect(shell, Color("D9E0E7"), Color("4A5563"), 0.8)
	pen.flush()
