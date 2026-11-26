@tool
class_name Travelator
extends Node2D
## A moving walkway (the Berth E2 gangway is 52 m long): two belts side by
## side running opposite ways. Standing on one adds its speed to the walker
## (Walker.conveyor), so you glide while your feet stay still, or run along
## it to go faster. The belt surface scrolls (painted chevrons) and hums.
## Node origin = the west end of the walkway, +X along it.

@export var length_m := 50.0:
	set(v): length_m = v; queue_redraw()
@export var lane_width_m := 1.0:
	set(v): lane_width_m = v; queue_redraw()
@export var gap_m := 0.5:
	set(v): gap_m = v; queue_redraw()
@export var speed_mps := 2.2

var _t := 0.0
var _belts: Node2D
var _hum: AudioStreamPlayer2D


func _ready() -> void:
	z_as_relative = false
	z_index = -3
	if Engine.is_editor_hint():
		return
	_belts = Node2D.new()
	_belts.material = OnFootArt.unshaded()
	_belts.draw.connect(_draw_belts)
	add_child(_belts)
	var s := GameplayUtil.load_loop("travelator_loop.wav")
	if s:
		_hum = AudioStreamPlayer2D.new()
		_hum.stream = s
		_hum.bus = GameplayUtil.bus(&"SFX")
		_hum.volume_db = -14.0
		_hum.max_distance = 300.0
		_hum.position = Vector2(length_m * 5.0, 0)
		add_child(_hum)
		_hum.play()


## North lane (-Y) runs along +X, south lane along -X.
func _lane_rect(i: int) -> Rect2:
	var px := OnFootArt.PX
	var y0 := -gap_m * 0.5 - lane_width_m if i == 0 else gap_m * 0.5
	return Rect2(Vector2(0, y0) * px, Vector2(length_m, lane_width_m) * px)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_t += delta
	var w := Game.walker
	if w == null or not is_instance_valid(w) or not w.is_inside_tree():
		return
	var p := to_local(w.global_position)
	for i in 2:
		if _lane_rect(i).grow(-1.0).has_point(p):
			var dir := global_transform.x.normalized() * (1.0 if i == 0 else -1.0)
			w.set(&"conveyor", dir * speed_mps * OnFootArt.PX)


func _process(_delta: float) -> void:
	if _belts:
		_belts.queue_redraw()


func _draw() -> void:
	# Static frame: the trough each belt runs in, with yellow edge lines.
	var pen := OnFootPainter.new(self)
	for i in 2:
		var r := _lane_rect(i)
		pen.rect(r.grow(0.6), Color("2B3440"), OnFootArt.INK, 0.15)
		pen.line(r.position + Vector2(0, -0.4), Vector2(r.end.x, r.position.y - 0.4), Color(1.0, 0.69, 0.0, 0.8), 0.3)
		pen.line(Vector2(r.position.x, r.end.y + 0.4), r.end + Vector2(0, 0.4), Color(1.0, 0.69, 0.0, 0.8), 0.3)
	pen.flush()


func _draw_belts() -> void:
	# The belts: dark rubber with chevrons scrolling in the running direction
	# and a faint cyan strip light in the middle of the walkway.
	var pen := OnFootPainter.new(_belts)
	var px := OnFootArt.PX
	for i in 2:
		var r := _lane_rect(i)
		var dir := 1.0 if i == 0 else -1.0
		pen.rect_flat(r, Color("1A222D"))
		var step := 2.0 * px
		var off := fposmod(_t * speed_mps * px * dir, step)
		var x := r.position.x - step + off
		var cy := r.get_center().y
		var h := r.size.y * 0.32
		while x < r.end.x:
			if x > r.position.x + 1.0 and x < r.end.x - 3.0:
				var tip := x + 2.2 * dir
				pen.fill(PackedVector2Array([Vector2(x, cy - h), Vector2(tip, cy), Vector2(x, cy + h),
					Vector2(x + 0.7 * dir, cy)]), Color(0.5, 0.9, 1.0, 0.35))
			x += step
	pen.rect_flat(Rect2(Vector2(0, -gap_m * 0.5 * px + 0.6), Vector2(length_m * px, gap_m * px - 1.2)), Color(0.5, 0.9, 1.0, 0.12))
	pen.flush()
