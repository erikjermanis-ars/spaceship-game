class_name Contracts
extends Node
## A handful of standing contracts that give the sandbox something to do and
## tie its systems together: hauling with the PETREL, shooting with the WREN
## and jumping with a frigate. Each one counts things the other systems
## already announce on the Game bus (cargo_delivered, target_destroyed), so
## nothing else knows contracts exist.
##
## A contract is repeatable: filling its target pays credits and raises the
## next target. Credits are a score for the session (nothing to spend them on
## in this demo); the HUD's contracts panel shows both.

signal changed
signal completed(id: StringName, reward: int)

## id, title, what to do, first target, reward for the first tier.
const DEFS := [
	{"id": &"yards", "title": "YARDS SUPPLY", "brief": "Containers from Cargo Yard C to the Yards intake", "target": 4, "reward": 300},
	{"id": &"gunnery", "title": "GUNNERY QUAL", "brief": "Burst target drones at the range", "target": 8, "reward": 250},
	{"id": &"resupply", "title": "VESPER RESUPPLY", "brief": "Containers to Vesper Rock's supply drop", "target": 5, "reward": 900},
	{"id": &"clearance", "title": "BELT CLEARANCE", "brief": "Break up rocks in Vesper's belt", "target": 10, "reward": 400},
	{"id": &"ore", "title": "ORE RUN", "brief": "Vesper ore canisters to Meridian's Yards intake", "target": 3, "reward": 1200},
]

var credits := 0
## id -> {count, target, reward, tier, flash}
var state := {}
var _snd: AudioStream


func _ready() -> void:
	add_to_group(&"contracts")
	for d: Dictionary in DEFS:
		state[d.id] = {"count": 0, "target": int(d.target), "reward": int(d.reward), "tier": 1, "flash": 0.0}
	_snd = GameplayUtil.load_audio("contract_complete.wav")
	Game.cargo_delivered.connect(_on_delivered)
	Game.target_destroyed.connect(_on_target)


func _on_delivered(brand: String, receiver_id: String, _slots: int) -> void:
	var ore := brand.nocasecmp_to("ORE") == 0
	if receiver_id == "yards":
		advance(&"ore" if ore else &"yards")
	elif receiver_id == "vesper" and not ore:
		advance(&"resupply")


func _on_target(kind: String) -> void:
	match kind:
		"drone": advance(&"gunnery")
		"asteroid": advance(&"clearance")


## Count one more toward contract `id`; pays out and re-arms it when full.
func advance(id: StringName, n := 1) -> void:
	if not state.has(id):
		return
	var s: Dictionary = state[id]
	s.count = int(s.count) + n
	s.flash = 1.0
	if int(s.count) >= int(s.target):
		var reward := int(s.reward)
		credits += reward
		s.count = 0
		s.tier = int(s.tier) + 1
		s.target = int(ceil(float(s.target) * 1.5))
		s.reward = int(round(float(reward) * 1.6 / 50.0)) * 50
		s.flash = 2.0
		GameplayUtil.play_oneshot(self, _snd, -5.0, 1.0, &"UI")
		Game.toast("CONTRACT COMPLETE  ·  %s  ·  +%d cr" % [_title(id), reward], 4.5)
		completed.emit(id, reward)
	changed.emit()


func _title(id: StringName) -> String:
	for d: Dictionary in DEFS:
		if d.id == id:
			return String(d.title)
	return String(id)


func _process(delta: float) -> void:
	for id: StringName in state:
		state[id].flash = maxf(0.0, float(state[id].flash) - delta)
