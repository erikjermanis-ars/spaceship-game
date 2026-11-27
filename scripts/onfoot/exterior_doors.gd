class_name ExteriorDoors
extends RefCounted
## Airlock doors in the station's outer walls that you can walk up to from a
## deck: the registry the on-foot director reads when it builds a walk site.
## Wherever you get out (a pad, or any deck the PETREL landed on), every door
## whose `at` lies on that site's walkable area appears there, and going
## through it loads `scene` and puts you in the Airlock node named `airlock`.
## The other way round, that Airlock's `exit_point` is this door's `at`.
##
##   at       world px: where you stand in front of the door, on the deck
##   facing   radians: the way INTO the wall from there (0 = +X / east)
##   scene    the interior behind it
##   airlock  name of the Airlock node in that interior (its exit_point = at)
##   label    painted over the door and shown in the prompt
##
## A new way in from outside = one entry here + one Airlock in the interior.

const DOORS := [
	{"id": "hangar2", "at": Vector2(6290.0, -4350.0), "facing": 0.0,
		"scene": "res://scenes/onfoot/interiors/hangar2_crew.tscn", "airlock": "Airlock", "label": "HANGAR 2 CREW"},
	{"id": "cargo_c", "at": Vector2(1680.0, 5859.0), "facing": -PI * 0.5,
		"scene": "res://scenes/onfoot/interiors/cargo_control.tscn", "airlock": "Airlock", "label": "YARD CONTROL"},
	{"id": "vesper", "at": Vector2(89825.0, 2830.0), "facing": -PI * 0.5,
		"scene": "res://scenes/onfoot/interiors/vesper_rock.tscn", "airlock": "Airlock", "label": "HAB A"},
]


## The doors that open onto walk site `site`.
static func on_site(site: WalkSite) -> Array:
	var out: Array = []
	for d: Dictionary in DOORS:
		if ResourceLoader.exists(String(d.scene)) and site.covers(d.at):
			out.append(d)
	return out


static func by_point(p: Vector2) -> Dictionary:
	for d: Dictionary in DOORS:
		if (d.at as Vector2).distance_to(p) < 20.0:
			return d
	return {}
