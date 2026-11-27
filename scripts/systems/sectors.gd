class_name Sectors
extends RefCounted
## The places a frigate's quantum drive can reach. Every sector lives in the
## same world scene, far apart: a jump moves the ship (and whatever is parked
## on its flight deck) from one to the other, and swaps the world bounds and
## the sky. Small ships can't cross: the boundary system keeps them inside
## the sector they are in.
##
## `origin`/`half` are world px. `arrive` is where a frigate drops out (px,
## relative to the origin) and `arrive_heading` the way it is going (rad).
## `map` is the star-map position (arbitrary map units), `beacon` whether the
## drive can lock on (charted places without a jump beacon show on the map
## but can't be selected: there is more out there than you can reach yet).

const MERIDIAN := &"meridian"
const VESPER := &"vesper"

const DEFS := {
	&"meridian": {
		"name": "MERIDIAN STATION", "kind": "Civic hub  ·  home port", "beacon": true,
		"origin": Vector2(0, 0), "half": Vector2(11000, 9000),
		"arrive": Vector2(8900, 0), "arrive_heading": PI,
		"map": Vector2(-150, 40), "look": &"meridian",
		"notes": ["Habitat ring, commerce pier, drydock, cargo yard", "Berths E1 · E2 on Pier 7 East"],
	},
	&"vesper": {
		"name": "VESPER ROCK", "kind": "Mining & survey outpost", "beacon": true,
		"origin": Vector2(90000, 0), "half": Vector2(8000, 6500),
		"arrive": Vector2(-5600, 0), "arrive_heading": 0.0,
		"map": Vector2(170, -60), "look": &"vesper",
		"notes": ["Asteroid belt of the ringed giant Vesper", "Berth V1  ·  ore, rock and not much else"],
	},
	&"tideway": {
		"name": "TIDEWAY RELAY", "kind": "Deep-space relay", "beacon": false,
		"map": Vector2(60, 118), "notes": ["Jump beacon offline  ·  survey pending"],
	},
	&"halcyon_drift": {
		"name": "CASSINI DRIFT", "kind": "Uncharted", "beacon": false,
		"map": Vector2(-30, -150), "notes": ["No beacon  ·  long-range scan only"],
	},
}
## Light-years between two map units (flavour for the star map).
const LY_PER_UNIT := 0.021


static func has(id: StringName) -> bool:
	return DEFS.has(id) and bool(DEFS[id].beacon)


static func display_name(id: StringName) -> String:
	return String(DEFS[id].name) if DEFS.has(id) else String(id).to_upper()


static func origin(id: StringName) -> Vector2:
	return DEFS[id].get("origin", Vector2.ZERO)


static func bounds(id: StringName) -> Rect2:
	var d: Dictionary = DEFS[id]
	var h: Vector2 = d.half
	return Rect2((d.origin as Vector2) - h, h * 2.0)


## Where a frigate drops out of the jump, and the way it is heading.
static func arrival(id: StringName) -> Transform2D:
	var d: Dictionary = DEFS[id]
	return Transform2D(float(d.arrive_heading), (d.origin as Vector2) + (d.arrive as Vector2))


## The sector a world position belongs to (the nearest reachable one).
static func at(p: Vector2) -> StringName:
	var best := MERIDIAN
	var best_d := INF
	for id: StringName in DEFS:
		if not bool(DEFS[id].beacon):
			continue
		var d := p.distance_squared_to(DEFS[id].origin)
		if d < best_d:
			best_d = d
			best = id
	return best


static func distance_ly(a: StringName, b: StringName) -> float:
	return (DEFS[a].map as Vector2).distance_to(DEFS[b].map) * LY_PER_UNIT
