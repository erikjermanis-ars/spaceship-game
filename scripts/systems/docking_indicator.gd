class_name DockingIndicator
extends Node2D
## In-world docking guide drawn around the ship while it is over a pad:
## a dashed target ring, the pad's alignment axis, and a progress arc that
## fills while holding steady. Turns green and pulses once docked.

const COL_GUIDE := Color(0.5, 0.9, 1.0)
const COL_WARN := Color(1.0, 0.69, 0.0)
const COL_DONE := Color(0.23, 1.0, 0.48)

var system: DockingSystem
var _alpha := 0.0
var _t := 0.0

func _ready() -> void:
	z_as_relative = false
	z_index = Game.Z_FX

func _process(delta: float) -> void:
	_t += delta
	var want := system != null and system.phase != DockingSystem.Phase.NONE and system.current_pad != null and GameplayUtil.player_alive()
	if want and system.phase == DockingSystem.Phase.APPROACH and system.hint == "":
		want = false   # not armed yet (e.g. sitting on spawn pad): stay quiet
	_alpha = move_toward(_alpha, 1.0 if want else 0.0, delta * 4.0)
	visible = _alpha > 0.01
	if visible:
		queue_redraw()

func _draw() -> void:
	if system == null or system.current_pad == null or not is_instance_valid(system.current_pad) or not GameplayUtil.player_valid():
		return
	var pad := system.current_pad
	var ship_pos := Game.player.global_position
	var r := 75.0
	var col := COL_GUIDE
	match system.phase:
		DockingSystem.Phase.APPROACH:
			col = COL_WARN
		DockingSystem.Phase.DOCKED:
			col = COL_DONE
	col.a = _alpha
	# Pad axis through the pad centre (shows which way to align).
	var axis := Vector2.from_angle(pad.global_rotation)
	var pc := pad.global_position
	var faint := Color(col.r, col.g, col.b, 0.35 * _alpha)
	draw_dashed_line(pc - axis * 160.0, pc + axis * 160.0, faint, 2.0, 12.0, true, true)
	draw_arc(pc, 10.0, 0.0, TAU, 16, faint, 2.0, true)
	# Dashed ring around the ship, slowly rotating.
	var segs := 24
	for i in segs:
		if i % 2 == 0:
			var a0 := TAU * i / segs + _t * 0.6
			draw_arc(ship_pos, r, a0, a0 + TAU / segs, 4, Color(col.r, col.g, col.b, 0.5 * _alpha), 2.0, true)
	# Progress arc.
	if system.progress > 0.0:
		draw_arc(ship_pos, r + 8.0, -PI * 0.5, -PI * 0.5 + TAU * system.progress, 48, col, 5.0, true)
	if system.phase == DockingSystem.Phase.DOCKED:
		var p := fmod(_t, 1.6) / 1.6
		draw_arc(ship_pos, r + 8.0 + p * 40.0, 0.0, TAU, 48, Color(col.r, col.g, col.b, (1.0 - p) * 0.6 * _alpha), 2.0, true)
