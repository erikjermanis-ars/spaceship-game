extends Node
## Headless check of the race flow (start -> splits -> finish -> best saved).
## Run: Godot --headless --path . res://scenes/test/gameplay_race_test.tscn

func _ready() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var race := get_tree().get_first_node_in_group(&"race_system") as RaceSystem
	if race == null or race.gate_count() < 2:
		print("[race-test] FAIL: no race system / gates")
		get_tree().quit(1)
		return
	race.clear_records()
	var finishes: Array = []
	Game.race_finished.connect(func(t: float, b: float) -> void: finishes.append([t, b]))
	for lap in 2:
		for i in race.gate_count():
			race.race_time += 1.0 + lap * 0.5
			race._on_gate_passed(i, 0.0)
	var cf := ConfigFile.new()
	var saved := cf.load(RaceSystem.SAVE_PATH) == OK
	print("[race-test] finishes=", finishes, " best=", race.best_time, " splits=", race.best_splits.size(), " saved=", saved, " state=", race.state)
	var ok := finishes.size() == 2 and is_equal_approx(race.best_time, finishes[0][0]) and saved and race.state == RaceSystem.State.IDLE
	print("[race-test] ", "PASS" if ok else "FAIL")
	race.clear_records()
	get_tree().quit(0 if ok else 1)
