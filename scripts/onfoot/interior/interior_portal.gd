@tool
class_name InteriorPortal
extends Interactable
## A way from one interior straight into another (no exterior between). The
## director opens `door`, walks you through, fades, swaps the interior scene
## and puts you at the node named by the link's arrival marker.
##
## Three kinds of link:
##   * FIXED (default): `target_scene` + `arrival`, as authored. With `ride`
##     it is a transit pod: the swap plays the pod's ride instead of a plain
##     fade (the Meridian transit line).
##   * a station's gangway (`berth_id` set): leads aboard whichever frigate
##     is clamped into that berth with its gangway sealed, arriving at that
##     ship's port or starboard airlock. Blocked while the berth is empty.
##   * a frigate's airlock (`frigate_side` = +1 starboard / -1 port): leads
##     into the station behind the berth the ship is docked at, if that side
##     faces the pier. Blocked adrift, and on the side facing space.

@export_file("*.tscn") var target_scene := ""
## Node in the target interior where you arrive (its rotation = facing).
@export var arrival := ""
@export var door: NodePath
## Where you walk to before the fade (local px, through the door).
@export var walk_in := Vector2(30, 0)
## Station side of a gangway: the berth it serves ("E2"). Empty = not one.
@export var berth_id := ""
## Frigate side of a gangway: which airlock this is (+1 starboard, -1 port).
@export var frigate_side := 0
## Transit pod: ride sound and a travel card instead of a plain fade.
@export var ride := false
@export var blocked_text := "Gangway not connected  ·  the berth is empty"
## Location card subtitle in the new interior.
@export var arrival_note := ""

var _check := 0.0


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or berth_id == "":
		return
	# The world is suspended indoors, so who is docked can't change under
	# you: refreshing the prompt twice a second is plenty.
	_check -= delta
	if _check <= 0.0:
		_check = 0.5
		var f := FrigateShip.docked_at(get_tree(), berth_id)
		prompt = "Board the %s" % f.vehicle_name if f else "Gangway hatch"


func _use(_by: Node2D) -> void:
	var link := resolve()
	if link.is_empty():
		GameplayUtil.play_oneshot(self, GameplayUtil.load_audio("console_beep.wav"), -10.0, 0.7)
		Game.toast(blocked_text, 2.5)
		return
	var d := get_tree().get_first_node_in_group(&"on_foot_director")
	if d:
		d.call(&"transfer", self)


func get_door() -> SlidingDoor:
	return get_node_or_null(door) as SlidingDoor


## Where this portal leads right now: {scene, arrival, note, frigate, ride},
## or {} while it is blocked.
func resolve() -> Dictionary:
	if berth_id != "":
		var f := FrigateShip.docked_at(get_tree(), berth_id)
		if f == null:
			return {}
		return {"scene": f.interior_scene(), "arrival": "FromGangwayS" if f.dock.side() > 0.0 else "FromGangwayP",
			"note": arrival_note if arrival_note != "" else "Airlock  ·  the bridge is forward, the flight deck aft",
			"frigate": f, "ride": false}
	if frigate_side != 0:
		var f := FrigateShip.aboard
		if f == null or not is_instance_valid(f) or not f.gangway_ready() or signf(f.dock.side()) != signf(frigate_side):
			return {}
		var b := f.dock.berth
		if not ResourceLoader.exists(String(b.get(&"gangway_scene"))):
			return {}
		return {"scene": String(b.get(&"gangway_scene")), "arrival": String(b.get(&"gangway_arrival")),
			"note": "Berth %s gangway  ·  %s" % [f.berth_name(), String(b.get(&"station_name"))], "frigate": null, "ride": false}
	if target_scene == "" or not ResourceLoader.exists(target_scene):
		return {}
	return {"scene": target_scene, "arrival": arrival, "note": arrival_note, "frigate": null, "ride": ride}
