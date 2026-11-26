@tool
class_name CallbackInteractable
extends Interactable
## Interactable that runs a Callable when used: handy for one-off actions
## wired up in code (board the ship, cycle an airlock) without a new script.

var on_use: Callable
## Optional extra condition, e.g. "only while the hatch is open".
var condition: Callable


func can_use(by: Node2D) -> bool:
	if condition.is_valid() and not bool(condition.call()):
		return false
	return super.can_use(by)


func _use(by: Node2D) -> void:
	if on_use.is_valid():
		on_use.call(by)
