class_name CargoHold
extends Node
## The PETREL's cargo hold: ten slots that swallow whole containers.
##
## Anything in group `cargo_container` fits. A 6 m box takes one slot, a 12 m
## one takes two. A stowed container is taken OUT of the scene tree and kept
## here (no physics, no drawing, off the radar), so the very same node, with
## its livery and serial, comes back out on eject(). Last in, first out: they
## all go through one hatch.
##
## This class only stores. CargoHandler decides when the ship swallows or
## drops a container and where an ejected one goes.

signal changed
signal stowed(body: RigidBody2D)
signal ejected(body: RigidBody2D)

## What each used slot adds to the ship's mass. A real 6 m box is 1.8 t, which
## would more than double the PETREL: the hold counts a share of it, so a full
## load is heavy to fly without being a different ship.
const SLOT_KG := 160.0
## Containers at least this long take two slots.
const LONG_BOX_M := 9.0

var capacity := 10

var _items: Array[Dictionary] = []   # {body, parent, brand, color, slots, size_m}


func used() -> int:
	var n := 0
	for it in _items:
		n += int(it.slots)
	return n


func free_slots() -> int:
	return capacity - used()


func count() -> int:
	return _items.size()


func is_empty() -> bool:
	return _items.is_empty()


func mass_kg() -> float:
	return used() * SLOT_KG


## Stowed containers, first in first: [{brand, color, slots, size_m, body}].
func items() -> Array:
	return _items.duplicate()


## The container eject() would return next (or {}).
func top() -> Dictionary:
	return {} if _items.is_empty() else _items[_items.size() - 1]


func can_take(body: Node) -> bool:
	if body == null or not is_instance_valid(body) or not (body is RigidBody2D):
		return false
	if not body.is_in_group(&"cargo_container") or holds(body):
		return false
	return slots_for(body) <= free_slots()


func holds(body: Node) -> bool:
	for it in _items:
		if it.body == body:
			return true
	return false


## Takes the container out of the world and keeps it. False if it doesn't fit.
func stow(body: RigidBody2D) -> bool:
	if not can_take(body):
		return false
	var it := describe(body)
	it["body"] = body
	it["parent"] = body.get_parent()
	if body.get_parent() != null:
		body.get_parent().remove_child(body)
	_items.append(it)
	stowed.emit(body)
	changed.emit()
	return true


## Hands back the last container stowed (null when empty). It is still out of
## the tree: the caller puts it somewhere with put_in_world().
func eject() -> RigidBody2D:
	if _items.is_empty():
		return null
	var it: Dictionary = _items.pop_back()
	ejected.emit(it.body)
	changed.emit()
	return it.body


## Where a container lived before it was stowed (to put it back under the
## same parent), or null if that is gone.
func home_of(it: Dictionary) -> Node:
	var p: Variant = it.get("parent")
	if p != null and is_instance_valid(p) and (p as Node).is_inside_tree():
		return p
	return null


## 1 slot, or 2 for a long box. `cargo_slots` meta overrides (odd-sized cargo).
static func slots_for(body: Node) -> int:
	if body.has_meta(&"cargo_slots"):
		return maxi(1, int(body.get_meta(&"cargo_slots")))
	return 2 if size_of(body).x >= LONG_BOX_M else 1


static func size_of(body: Node) -> Vector2:
	var s: Variant = body.get(&"size_m")
	return s if s is Vector2 else Vector2(6.1, 2.44)


## {brand, color, slots, size_m} of a container (stowed or not).
static func describe(body: Node) -> Dictionary:
	var brand: Variant = body.get(&"brand")
	var color: Variant = body.get(&"color")
	return {
		"brand": String(brand) if brand != null else "CARGO",
		"color": color if color is Color else Color("8E9AA8"),
		"slots": slots_for(body),
		"size_m": size_of(body),
	}


## "HELIOS 6 m": how toasts and the HUD name a container.
static func label(it: Dictionary) -> String:
	return "%s %d m" % [it.brand, int((it.size_m as Vector2).x)]


## Puts a container (back) into the world at a global transform. Position and
## velocity are set BEFORE it enters the tree: a continuous-collision body moved
## afterwards would sweep there from wherever it was.
static func put_in_world(body: RigidBody2D, parent: Node, xf: Transform2D, vel_px := Vector2.ZERO, spin := 0.0) -> void:
	var local := xf
	if parent is Node2D:
		local = (parent as Node2D).global_transform.affine_inverse() * xf
	body.position = local.origin
	body.rotation = local.get_rotation()
	body.sleeping = false
	parent.add_child(body)
	body.linear_velocity = vel_px
	body.angular_velocity = spin
	# cargo_box measures impacts against its pre-step velocity: don't let the
	# speed it was stowed at read as a crash.
	if &"prev_velocity" in body:
		body.set(&"prev_velocity", vel_px)
		body.set(&"prev_velocity2", vel_px)


func _notification(what: int) -> void:
	# Stowed containers are orphans (out of the tree): free them with the hold.
	if what == NOTIFICATION_PREDELETE:
		for it in _items:
			var b: Variant = it.get("body")
			if b != null and is_instance_valid(b) and not (b as Node).is_inside_tree():
				(b as Node).free()
