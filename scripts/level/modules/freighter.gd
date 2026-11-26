@tool
extends StationModule
## A docked (static, colliding) container freighter. Bow = local +X.

@export var length_m := 190.0:
	set(v): length_m = v; queue_rebuild()
@export var beam_m := 48.0:
	set(v): beam_m = v; queue_rebuild()
@export var livery := Color("E76F51"):
	set(v): livery = v; queue_rebuild()
@export var ship_name := "KESTREL STAR":
	set(v): ship_name = v; queue_rebuild()
@export var engines_on := false:
	set(v): engines_on = v; queue_rebuild()
@export var seed := 1:
	set(v): seed = v; queue_rebuild()


func _build() -> void:
	preload("res://scripts/level/ship_painter.gd").freighter(self, Transform2D.IDENTITY, length_m, beam_m, livery, ship_name, engines_on, seed)
