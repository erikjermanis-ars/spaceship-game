@tool
class_name InteriorPortal
extends Interactable
## A way from one interior straight into another (no exterior between):
## the end of the Pier 7 gangway into the KESTREL's airlock, and back.
## The director opens `door`, walks you through, fades, swaps the interior
## scene and puts you at the node named `arrival` in the new one.
## With `needs_frigate_gangway` it only works while the frigate is clamped in
## its berth with the gangway sealed; otherwise it says why.

@export_file("*.tscn") var target_scene := ""
## Node in the target interior where you arrive (its rotation = facing).
@export var arrival := "FromGangway"
@export var door: NodePath
## Where you walk to before the fade (local px, through the door).
@export var walk_in := Vector2(30, 0)
@export var needs_frigate_gangway := true
@export var blocked_text := "Gangway not connected  ·  the berth is empty"
## Location card subtitle in the new interior.
@export var arrival_note := ""


func _use(_by: Node2D) -> void:
	if needs_frigate_gangway and not frigate_connected(get_tree()):
		GameplayUtil.play_oneshot(self, GameplayUtil.load_audio("console_beep.wav"), -10.0, 0.7)
		Game.toast(blocked_text, 2.5)
		return
	var d := get_tree().get_first_node_in_group(&"on_foot_director")
	if d:
		d.call(&"transfer", self)


func get_door() -> SlidingDoor:
	return get_node_or_null(door) as SlidingDoor


## Is the KESTREL clamped in its berth with the gangway sealed?
static func frigate_connected(tree: SceneTree) -> bool:
	var f := tree.get_first_node_in_group(&"frigate")
	return f != null and f.has_method(&"gangway_ready") and bool(f.call(&"gangway_ready"))
