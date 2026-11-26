@tool
class_name Airlock
extends Node2D
## Airlock between the vacuum outside and a pressurised interior: an outer
## hatch, an inner door and a cycle in between (doors interlocked, amber
## beacon, hiss of air). The director calls cycle_in() when you arrive and
## the hatch panel (a CallbackInteractable at this node) asks to leave.

signal exit_requested
signal cycle_done(pressurised: bool)

@export var outer_door: NodePath
@export var inner_door: NodePath
## Where you appear when coming in (local px), facing +X.
@export var arrival_m := Vector2(1.6, 0)
@export var exit_prompt := "Cycle airlock · exit"
@export var cycle_time := 2.6

var cycling := false
var _beacon: Node2D
var _t := 0.0
var _snd_cycle: AudioStream


## Batched painter used by the draw callbacks (see OnFootPainter).
var pen: OnFootPainter

func _ready() -> void:
	z_as_relative = false
	z_index = Game.Z_WALL_TOP + 1 if not Engine.is_editor_hint() else 13
	if Engine.is_editor_hint():
		return
	_snd_cycle = GameplayUtil.load_audio("airlock_cycle.wav")
	var use := CallbackInteractable.new()
	use.name = "HatchPanel"
	use.prompt = exit_prompt
	use.reach_m = 2.1
	use.prompt_offset_m = Vector2(0.4, -1.4)
	use.condition = func() -> bool: return not cycling
	use.on_use = func(_by: Node2D) -> void: exit_requested.emit()
	add_child(use)
	_beacon = Node2D.new()
	_beacon.material = OnFootArt.unshaded()
	_beacon.draw.connect(_draw_beacon)
	add_child(_beacon)


func arrival_global() -> Vector2:
	return to_global(arrival_m * OnFootArt.PX)


func _outer() -> SlidingDoor:
	return get_node_or_null(outer_door) as SlidingDoor


func _inner() -> SlidingDoor:
	return get_node_or_null(inner_door) as SlidingDoor


## Arriving from outside: outer hatch shuts, air comes in, inner door unlocks.
func cycle_in() -> void:
	cycling = true
	if _inner():
		_inner().locked = true
	if _outer():
		_outer().close()
	GameplayUtil.play_oneshot(self, _snd_cycle, -4.0)
	await get_tree().create_timer(cycle_time, false).timeout
	cycling = false
	if _inner():
		_inner().locked = false
	cycle_done.emit(true)


## Leaving: inner door locks, air is pumped out (the director fades out
## during this and swaps back to the exterior).
func cycle_out() -> void:
	cycling = true
	if _inner():
		_inner().locked = true
	GameplayUtil.play_oneshot(self, _snd_cycle, -4.0, 0.88)


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _beacon == null:
		return
	_t += delta
	_beacon.queue_redraw()


func _draw() -> void:
	pen = OnFootPainter.new(self)
	_paint_draw()
	pen.flush()


func _paint_draw() -> void:
	# The hatch control panel (on the wall next to the outer hatch).
	pen.rrect(Rect2(Vector2(-0.4, -1.6), Vector2(1.6, 3.2)), 0.3, Color("C9D2DC"), OnFootArt.INK, 0.12)
	pen.rect(Rect2(Vector2(0.0, -1.1), Vector2(0.9, 2.2)), Color("1B2533"))


func _draw_beacon() -> void:
	pen = OnFootPainter.new(_beacon)
	_paint_draw_beacon()
	pen.flush()


func _paint_draw_beacon() -> void:
	# Status: green = pressurised, rotating amber while cycling.
	var c := OnFootArt.AMBER if cycling else OnFootArt.NAV_GREEN
	var a := 0.55 + 0.45 * sin(_t * 9.0) if cycling else 1.0
	pen.rect_flat(Rect2(Vector2(0.1, -0.9), Vector2(0.7, 1.8)), Color(c, 0.35 * a))
	pen.circle(Vector2(0.45, -0.5), 0.25, Color(c, a))
	pen.circle(Vector2(0.45, 0.4), 0.18, Color(0.5, 0.9, 1.0, 0.8))
