class_name FreightLedger
extends RefCounted
## Session tally of freight delivered to FreightReceivers. Static, so anything
## (a contracts panel, a test) can read it without finding a node:
##     FreightLedger.delivered["yards"]   containers that receiver has taken
##     FreightLedger.total()              containers delivered anywhere
## Receivers write it just before they emit Game.cargo_delivered.

## receiver_id -> containers delivered.
static var delivered: Dictionary = {}
## receiver_id -> hold slots those containers were worth (a 12 m box is 2).
static var slots: Dictionary = {}
## brand -> containers delivered (to any receiver).
static var brands: Dictionary = {}


static func record(receiver_id: String, brand: String, n_slots: int) -> void:
	delivered[receiver_id] = count(receiver_id) + 1
	slots[receiver_id] = int(slots.get(receiver_id, 0)) + n_slots
	brands[brand] = int(brands.get(brand, 0)) + 1


static func count(receiver_id: String) -> int:
	return int(delivered.get(receiver_id, 0))


static func total() -> int:
	var n := 0
	for id in delivered:
		n += int(delivered[id])
	return n


static func total_slots() -> int:
	var n := 0
	for id in slots:
		n += int(slots[id])
	return n


## New session (tests).
static func reset() -> void:
	delivered.clear()
	slots.clear()
	brands.clear()
