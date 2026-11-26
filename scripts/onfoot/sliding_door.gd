@tool
class_name SlidingDoor
extends Node2D
## A two-leaf sliding door. The opening spans local Y (from -width/2 to
## +width/2), you walk through it along local X. Rotate the node 90° for a
## door in a horizontal wall.
##
## Each leaf is an AnimatableBody2D (moving collider the walker can't pass)
## with a LightOccluder2D (blocks the flashlight while closed). `auto` doors
## open when the walker comes close, like supermarket doors on a starship;
## manual doors are driven by code (the airlock).

signal opened
signal closed

@export var width_m := 1.6:
	set(v): width_m = v; queue_redraw()
@export var thickness_m := 0.4:
	set(v): thickness_m = v; queue_redraw()
@export var auto := true
@export var sense_m := 2.3
@export var locked := false:
	set(v): locked = v; queue_redraw()
@export var heavy := false            ## airlock-style: slower, servo sound
@export var frame_color := Color("8E9AA8")
@export var leaf_color := Color("C9D2DC")
@export var accent := Color("2A9D8F")

var open_t := 0.0                     ## 0 closed .. 1 open
var _want_open := false
var _leaves: Array[AnimatableBody2D] = []
var _snd: AudioStream
var _player: AudioStreamPlayer2D
var _was_open := false


## Batched painter used by the draw callbacks (see OnFootPainter).
var pen: OnFootPainter

func _ready() -> void:
	z_as_relative = false
	z_index = Game.Z_WALL_TOP if not Engine.is_editor_hint() else 12
	if Engine.is_editor_hint():
		return
	# Doors are part of the walls: drawn unshaded like the wall tops, so
	# they read the same in lit and dark rooms.
	material = OnFootArt.unshaded()
	for side: float in [-1.0, 1.0]:
		var body := AnimatableBody2D.new()
		body.sync_to_physics = false
		body.collision_layer = Game.LAYER_WALK
		body.collision_mask = 0
		var cs := CollisionShape2D.new()
		var rs := RectangleShape2D.new()
		rs.size = Vector2(thickness_m * 0.6, width_m * 0.5) * OnFootArt.PX
		cs.shape = rs
		body.add_child(cs)
		var occ := LightOccluder2D.new()
		var op := OccluderPolygon2D.new()
		var h := rs.size * 0.5
		op.polygon = PackedVector2Array([Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y)])
		occ.occluder = op
		body.add_child(occ)
		add_child(body)
		_leaves.append(body)
	_snd = GameplayUtil.load_audio("door_servo.wav" if heavy else "door_slide.wav")
	_player = AudioStreamPlayer2D.new()
	_player.bus = GameplayUtil.bus(&"SFX")
	_player.max_distance = 500.0
	_player.volume_db = -8.0 if heavy else -12.0
	add_child(_player)
	_place_leaves()


func open() -> void:
	_want_open = true


func close() -> void:
	_want_open = false


func is_open() -> bool:
	return open_t > 0.95


## Jump to a state without animating (behind a fade).
func snap(t: float) -> void:
	open_t = t
	_want_open = t > 0.5
	_was_open = t > 0.5
	_place_leaves()
	queue_redraw()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if auto:
		var w := Game.walker
		var near := w != null and is_instance_valid(w) and w.is_inside_tree() \
			and w.global_position.distance_to(global_position) < sense_m * OnFootArt.PX
		_want_open = near and not locked
	var target := 1.0 if _want_open else 0.0
	if not is_equal_approx(open_t, target):
		var was_still := is_equal_approx(open_t, 0.0) or is_equal_approx(open_t, 1.0)
		if was_still and _snd and _player:
			_player.stream = _snd
			_player.pitch_scale = (1.0 if _want_open else 0.92) * (1.0 if heavy else randf_range(0.97, 1.04))
			_player.play()
		var speed := 0.9 if heavy else 3.6
		open_t = move_toward(open_t, target, delta * speed)
		_place_leaves()
		queue_redraw()
		if open_t >= 1.0 and not _was_open:
			_was_open = true
			opened.emit()
		elif open_t <= 0.0 and _was_open:
			_was_open = false
			closed.emit()


func _place_leaves() -> void:
	var half := width_m * 0.25 * OnFootArt.PX
	var k := smoothstep(0.0, 1.0, open_t)
	for i in _leaves.size():
		var side := -1.0 if i == 0 else 1.0
		_leaves[i].position = Vector2(0, side * (half + k * width_m * 0.48 * OnFootArt.PX))


func _draw() -> void:
	pen = OnFootPainter.new(self)
	_paint_draw()
	pen.flush()


func _paint_draw() -> void:
	var px := OnFootArt.PX
	var t := thickness_m * px
	var w := width_m * px
	var k := smoothstep(0.0, 1.0, open_t)
	# floor track (visible when open)
	pen.rect_flat(Rect2(Vector2(-t * 0.3, -w * 0.5), Vector2(t * 0.6, w)), Color(0.08, 0.1, 0.14))
	pen.line(Vector2(0, -w * 0.5), Vector2(0, w * 0.5), Color(1.0, 0.69, 0.0, 0.5), 0.18)
	# leaves
	for side: float in [-1.0, 1.0]:
		var c := Vector2(0, side * (w * 0.25 + k * w * 0.48))
		var r := Rect2(c - Vector2(t * 0.32, w * 0.25), Vector2(t * 0.64, w * 0.5))
		pen.rect(r, leaf_color, OnFootArt.INK, 0.12)
		pen.line(Vector2(r.position.x + t * 0.32, r.position.y + 0.4), Vector2(r.position.x + t * 0.32, r.end.y - 0.4), accent, 0.25)
	# frame posts with status lights
	for side: float in [-1.0, 1.0]:
		var p := Rect2(Vector2(-t * 0.6, side * w * 0.5 - (t * 0.5 if side > 0 else t * 0.5)), Vector2(t * 1.2, t))
		pen.rect(p, frame_color, OnFootArt.INK, 0.12)
	var lamp_col := OnFootArt.NAV_RED if locked else (OnFootArt.NAV_GREEN if k > 0.5 else OnFootArt.CYAN)
	pen.circle(Vector2(-t * 0.6 - 0.4, -w * 0.5 - t * 0.1), 0.32, lamp_col)
	pen.circle(Vector2(t * 0.6 + 0.4, w * 0.5 + t * 0.1), 0.32, lamp_col)
