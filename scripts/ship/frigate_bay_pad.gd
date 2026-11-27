class_name FrigateBayPad
extends Node2D
## One landing pad on a frigate's flight deck. It carries the same fields a
## station DockingPad module has (`size_m`, `tail_m`, `pad_name`), because
## DockingSystem and WalkSite read those from a docking trigger's parent.
## The trigger itself is the child Area2D `DockTrigger` (group `docking_pad`).

var pad_name := "Bay A"
var size_m := Vector2(17, 11)
var tail_m := 0.0
var area: Area2D


func setup(p_name: String, p_size_m: Vector2) -> void:
	pad_name = p_name
	size_m = p_size_m
	area = Area2D.new()
	area.name = "DockTrigger"
	area.collision_layer = Game.LAYER_TRIGGERS
	area.collision_mask = Game.LAYER_PLAYER
	area.monitorable = false
	area.set_meta(&"pad_name", pad_name)
	area.add_to_group(&"docking_pad")
	var cs := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	# A little smaller than the painted pad: a ship counts as "on it" once
	# most of its hull is inside the brackets.
	rs.size = (size_m - Vector2(5.0, 4.0)) * Game.PX_PER_M
	cs.shape = rs
	area.add_child(cs)
	add_child(area)
