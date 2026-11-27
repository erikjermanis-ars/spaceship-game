class_name RangeScoreboard
extends Node2D
## The gunnery range's scoreboard: hits, kills, the current streak and the
## best one, as a holographic projection on the range "floor" (under the ship
## and the drones, like the lane chevrons). It sits inside the range so you
## can read it while you shoot, and it is faint enough not to hide a target.
##
## Drawn only when a number changes (the canvas item caches it); a hit just
## brightens it for a moment through `modulate`.

const A := preload("res://scripts/level/level_art.gd")
const SIZE := Vector2(620.0, 130.0)      # px (62 x 13 m)
const COLUMNS := ["HITS", "KILLS", "STREAK", "BEST"]

var tint := Color(1.0, 0.75, 0.3)
var _values := PackedInt32Array([0, 0, 0, 0])
var _tween: Tween


func _ready() -> void:
	z_as_relative = false
	z_index = Game.Z_STRUCTURE + 2       # the station's additive "floor light" band
	material = A.add_material()


func set_score(hits: int, kills: int, streak: int, best: int) -> void:
	var now := PackedInt32Array([hits, kills, streak, best])
	if now == _values:
		return
	var bump := hits > _values[0]
	_values = now
	queue_redraw()
	if bump:
		if _tween and _tween.is_valid():
			_tween.kill()
		modulate = Color(2.2, 2.2, 2.2)
		_tween = create_tween()
		_tween.tween_property(self, ^"modulate", Color.WHITE, 0.4)


func _draw() -> void:
	var r := Rect2(-SIZE * 0.5, SIZE)
	draw_rect(r, Color(tint, 0.035))
	draw_rect(r, Color(tint, 0.2), false, 2.0, true)
	for c: Vector2 in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var sx := 1.0 if c.x < 0.0 else -1.0
		var sy := 1.0 if c.y < 0.0 else -1.0
		draw_polyline(PackedVector2Array([c + Vector2(0, sy * 26), c, c + Vector2(sx * 26, 0)]), Color(tint, 0.55), 4.0, true)
	var f := A.font()
	var col_w := SIZE.x / COLUMNS.size()
	for i in COLUMNS.size():
		var x := r.position.x + col_w * i
		if i > 0:
			draw_line(Vector2(x, r.position.y + 18), Vector2(x, r.end.y - 18), Color(tint, 0.16), 2.0)
		# The live streak is the number to watch: it runs cyan while it is alive.
		var hot := i == 2 and _values[2] > 0
		var vcol := Color(0.55, 0.95, 1.0, 0.8) if hot else Color(tint, 0.5)
		draw_string(f, Vector2(x, r.position.y + 34), COLUMNS[i], HORIZONTAL_ALIGNMENT_CENTER, col_w, 20, Color(tint, 0.38))
		draw_string(f, Vector2(x, r.position.y + 110), str(_values[i]), HORIZONTAL_ALIGNMENT_CENTER, col_w, 80, vcol)
