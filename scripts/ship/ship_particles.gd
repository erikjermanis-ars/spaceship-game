class_name ShipParticles
extends Node2D
## Tiny pooled particle renderer for the ship's gas puffs, smoke and sparks.
## Why not CPUParticles2D: RCS gas must inherit the ship's velocity (vacuum —
## the puff travels with the ship and only its exhaust velocity decays), and
## we need per-emission direction/velocity from several nozzles. One node,
## one draw pass, fixed-size ring buffer, zero per-frame allocations.
##
## Runs in GLOBAL coordinates (top_level, identity transform).

const MAX := 320

enum Kind { PUFF, SPARK }

var texture: Texture2D

var _pos := PackedVector2Array()
var _base_vel := PackedVector2Array()   # inherited, constant
var _rel_vel := PackedVector2Array()    # decays with _drag
var _life := PackedFloat32Array()
var _max_life := PackedFloat32Array()
var _size0 := PackedFloat32Array()
var _size1 := PackedFloat32Array()
var _drag := PackedFloat32Array()
var _col0 := PackedColorArray()
var _col1 := PackedColorArray()
var _kind := PackedByteArray()
var _next := 0
var _alive := 0


func _init() -> void:
	top_level = true
	_pos.resize(MAX)
	_base_vel.resize(MAX)
	_rel_vel.resize(MAX)
	_life.resize(MAX)
	_max_life.resize(MAX)
	_size0.resize(MAX)
	_size1.resize(MAX)
	_drag.resize(MAX)
	_col0.resize(MAX)
	_col1.resize(MAX)
	_kind.resize(MAX)


func _ready() -> void:
	global_transform = Transform2D.IDENTITY
	if texture == null:
		texture = ShipFxTextures.puff()


func emit(pos: Vector2, base_vel: Vector2, rel_vel: Vector2, life: float, size0: float,
		size1: float, col0: Color, col1: Color, drag := 3.0, kind := Kind.PUFF) -> void:
	var i := _next
	_next = (_next + 1) % MAX
	if _life[i] <= 0.0:
		_alive += 1
	_pos[i] = pos
	_base_vel[i] = base_vel
	_rel_vel[i] = rel_vel
	_life[i] = life
	_max_life[i] = life
	_size0[i] = size0
	_size1[i] = size1
	_drag[i] = drag
	_col0[i] = col0
	_col1[i] = col1
	_kind[i] = kind


func clear() -> void:
	for i in MAX:
		_life[i] = 0.0
	_alive = 0
	queue_redraw()


func _process(delta: float) -> void:
	if _alive <= 0:
		return
	var alive := 0
	for i in MAX:
		if _life[i] <= 0.0:
			continue
		_life[i] -= delta
		if _life[i] <= 0.0:
			continue
		alive += 1
		_rel_vel[i] *= exp(-_drag[i] * delta)
		_pos[i] += (_base_vel[i] + _rel_vel[i]) * delta
	_alive = alive
	queue_redraw()


func _draw() -> void:
	for i in MAX:
		var life := _life[i]
		if life <= 0.0:
			continue
		var t := 1.0 - life / _max_life[i]   # 0 at birth -> 1 at death
		var c := _col0[i].lerp(_col1[i], t)
		if _kind[i] == Kind.SPARK:
			var v := _base_vel[i] + _rel_vel[i]
			var tail := v * 0.025
			c.a *= 1.0 - t
			draw_line(_pos[i] - tail, _pos[i], c, lerpf(_size0[i], _size1[i], t), true)
		else:
			var s := lerpf(_size0[i], _size1[i], t)
			# Ease alpha in quickly and out smoothly.
			c.a *= smoothstep(0.0, 0.08, t) * (1.0 - t * t)
			draw_texture_rect(texture, Rect2(_pos[i] - Vector2(s, s) * 0.5, Vector2(s, s)), false, c)
