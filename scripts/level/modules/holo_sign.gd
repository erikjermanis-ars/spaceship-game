@tool
extends StationModule
## Overhead holographic signage (additive cyan light floating above the lanes).

@export var title := "WELCOME TO MERIDIAN":
	set(v): title = v; queue_rebuild()
@export var subtitle := "PORT CONTROL  ·  CH 16  ·  SPEED LIMIT 40 M/S":
	set(v): subtitle = v; queue_rebuild()
@export var size_m := Vector2(78, 20):
	set(v): size_m = v; queue_rebuild()
@export var tint := Color(0.5, 0.92, 1.0):
	set(v): tint = v; queue_rebuild()


func _build() -> void:
	var h := size_m.y * PX
	var title_px := int(h * 0.36)
	var sub_px := int(h * 0.13)
	var f := A.font()
	# frame grows to fit the text
	var tw := maxf(f.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_px).x,
		f.get_string_size(subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, sub_px).x)
	var w := maxf(size_m.x * PX, tw + h * 0.6)
	var r := Rect2(Vector2(-w * 0.5, -h * 0.5), Vector2(w, h))
	var F := Band.OVER_FX
	_op(F, &"draw_rect", [r, Color(tint, 0.06), true, -1.0, false])
	_op(F, &"draw_rect", [r, Color(tint, 0.45), false, 3.0, true])
	var y := r.position.y + 6.0
	var pairs := PackedVector2Array()
	while y < r.end.y:
		pairs.append_array([Vector2(r.position.x + 4, y), Vector2(r.end.x - 4, y)])
		y += 9.0
	lines(F, pairs, Color(tint, 0.05), 1.0)
	# corner brackets
	for c: Vector2 in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var sx := 1.0 if c.x < 0 else -1.0
		var sy := 1.0 if c.y < 0 else -1.0
		polyline(F, PackedVector2Array([c + Vector2(0, sy * 40), c, c + Vector2(sx * 40, 0)]), Color(tint, 0.9), 5.0)
	text(F, Vector2(0, -h * 0.12), title, title_px, Color(tint, 0.85))
	line(F, Vector2(-tw * 0.5, h * 0.12), Vector2(tw * 0.5, h * 0.12), Color(tint, 0.35), 2.0)
	text(F, Vector2(0, h * 0.27), subtitle, sub_px, Color(tint, 0.65))
	beacon(Vector2(r.position.x, 0), tint, 70.0, 0.0, false, 2)
	beacon(Vector2(r.end.x, 0), tint, 70.0, 0.5, false, 2)
