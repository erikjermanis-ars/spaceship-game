@tool
class_name Interactable
extends Node2D
## Anything the walker can use with E: light switches, doors, terminals, the
## ship's hatch. The director picks the closest enabled interactable within
## reach (and roughly in front of the walker) every frame and shows its
## prompt; pressing E calls `interact()`.
##
## A plain node + group scan instead of an Area2D per object: there are only
## a handful in range at any time, so a distance check is cheaper and simpler
## than physics overlap queries, and it works the same in every scene.
## Subclasses override `_use()` and may update `prompt` to reflect state.

signal used(by: Node2D)

## Shown next to the key cap, e.g. "Lights on".
@export var prompt := "Use"
## How close (metres, from this node's origin) the walker must be.
@export var reach_m := 1.6
@export var enabled := true
## Where the floating prompt appears, relative to this node (metres, global axes).
@export var prompt_offset_m := Vector2(0, -1.2)


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		add_to_group(&"interactable")


## Distance-based availability; subclasses can add conditions.
func can_use(_by: Node2D) -> bool:
	return enabled and is_visible_in_tree()


func interact(by: Node2D) -> void:
	if not can_use(by):
		return
	_use(by)
	used.emit(by)


func _use(_by: Node2D) -> void:
	pass


## Global point the walker's reach is measured to.
func reach_point() -> Vector2:
	return global_position


func prompt_position() -> Vector2:
	return global_position + prompt_offset_m * OnFootArt.PX
