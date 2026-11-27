class_name SkyLook
extends RefCounted
## Everything SpaceBackground needs to show one place's sky: the parallax
## layers (all parented under `root`, so a look is shown or hidden with one
## node), where its sun sits, which disk can eclipse that sun, and the uniform
## overrides for the two shared fullscreen passes (sky and sun glare).
##
## A look only overrides what differs; SpaceBackground applies Meridian's
## values first, so switching back always restores them.

var id: StringName
var root: Node2D
var layers: Array[Dictionary] = []    # {node: Node2D, p: float, anchor: Vector2}
## Sun position as a fraction of the visible screen.
var sun_screen := Vector2(0.5, 0.5)
## The body whose disk fades the glare when it slides over the sun.
var disk: Node2D
var disk_radius := 0.0
## Added to the camera position the sky pass sees: a big offset gives this
## place its own star field and patch of nebula from the same procedural sky.
var sky_offset := Vector2.ZERO
var sky_params := {}                  # sky.gdshader uniform -> value
var sun_params := {}                  # sun_glare.gdshader uniform -> value
## Multiplies SpaceBackground.sun_intensity (a farther sun glares less).
var sun_gain := 1.0
## Slow build steps still to run (e.g. big meshes). A look built ahead of time
## runs one per frame; a look that is needed now runs them all at once.
var pending: Array[Callable] = []


func _init(p_id: StringName) -> void:
	id = p_id
	root = Node2D.new()
	root.name = String(p_id).to_pascal_case()


## Adds a parallax layer: `p` is how fast it moves relative to the world,
## `anchor` where it sits in layer space when the camera is at the look origin.
func add_layer(node: Node2D, p: float, anchor: Vector2) -> void:
	root.add_child(node)
	layers.append({"node": node, "p": p, "anchor": anchor})


## Runs one pending build step. False once there is nothing left to do.
func step() -> bool:
	if pending.is_empty():
		return false
	var c: Callable = pending.pop_front()
	c.call()
	return not pending.is_empty()


func finish() -> void:
	while step():
		pass
