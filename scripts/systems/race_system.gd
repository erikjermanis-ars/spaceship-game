class_name RaceSystem
extends Node
## Time-trial through the level's RaceCourse gates.
##
## * Free flight: crossing Gate01 starts the clock (flying start).
## * R (restart_race): teleport to the spawn pad, 3-2-1-GO with controls
##   locked, clock starts at GO (standing start).
## * Passing is detected by intersecting the ship's per-step motion segment
##   with the gate line, so it can't be skipped at high speed, and only
##   counts when travelling along the gate's +X.
## * Splits are compared with the best lap's splits; best lap persists in
##   user://race_records.cfg.
## * T (respawn) puts you back on the last passed gate, facing through it.

enum State { IDLE, COUNTDOWN, RUNNING }

signal countdown_tick(value: int)   ## 3, 2, 1, then 0 = GO
signal gate_passed(index: int)      ## 0-based gate index (visual/HUD use)

const SAVE_PATH := "user://race_records.cfg"
const COUNTDOWN_STEP := 1.0
const PASS_MARGIN_M := 1.5          ## leniency beyond the posts
const RESPAWN_AHEAD_M := 8.0

var state := State.IDLE
var gates: Array[Node2D] = []
var visuals: Array[RaceGateVisual] = []
var next_index := 0
var race_time := 0.0
var best_time := INF
var best_splits: Array[float] = []
var current_splits: Array[float] = []
var last_split_delta := 0.0
var has_last_delta := false
var last_gate_index := -1
var countdown_value := 0
var last_finish_time := -1.0
var last_finish_was_best := false
var finish_display_time := 0.0     ## > 0 while the HUD should show a result

var _countdown_left := 0.0
var _prev_pos := Vector2.ZERO
var _have_prev := false
var _setup_done := false
var _snd_gate: AudioStream
var _snd_count: AudioStream
var _snd_go: AudioStream
var _snd_finish: AudioStream

func _ready() -> void:
	add_to_group(&"race_system")
	_snd_gate = GameplayUtil.load_audio("gate_pass.wav")
	_snd_count = GameplayUtil.load_audio("race_countdown.wav")
	_snd_go = GameplayUtil.load_audio("race_go.wav")
	_snd_finish = GameplayUtil.load_audio("race_finish.wav")
	_load_records()
	Game.ship_respawned.connect(func(_p: Vector2) -> void: _have_prev = false)
	Game.player_changed.connect(_on_player_changed)

func _setup() -> void:
	_setup_done = true
	gates = GameplayUtil.race_gates()
	for i in gates.size():
		var g := gates[i]
		var v := RaceGateVisual.new()
		v.name = "GateVisual"
		g.add_child(v)
		v.setup(i + 1, i == gates.size() - 1, float(g.get_meta(&"width_m", 40.0)))
		visuals.append(v)
	if best_splits.size() != gates.size():
		best_splits.clear()   # course changed since the record was set
	_refresh_visuals()

func gate_count() -> int:
	return gates.size()

func is_running() -> bool:
	return state == State.RUNNING

func next_gate() -> Node2D:
	if next_index >= 0 and next_index < gates.size():
		return gates[next_index]
	return null

func best_split(index: int) -> float:
	return best_splits[index] if index >= 0 and index < best_splits.size() else -1.0

# ================================================================ input ===
# Polled (not _unhandled_input) so the scripted --input test harness, which
# uses Input.action_press, can drive it too.
func _process(_delta: float) -> void:
	if Input.is_action_just_pressed(&"restart_race"):
		start_countdown()
	elif Input.is_action_just_pressed(&"respawn"):
		manual_reset()

func start_countdown() -> void:
	if gates.size() < 2 or not GameplayUtil.player_valid():
		Game.toast("No race course in this level", 2.0)
		return
	state = State.COUNTDOWN
	next_index = 0
	last_gate_index = -1
	race_time = 0.0
	current_splits.clear()
	has_last_delta = false
	finish_display_time = 0.0
	_teleport(GameplayUtil.spawn_transform(get_tree()))
	GameplayUtil.set_controls(false)
	_countdown_left = COUNTDOWN_STEP * 3.0
	countdown_value = 3
	countdown_tick.emit(3)
	_play(_snd_count, -13.0, 1.0)
	_refresh_visuals()

func manual_reset() -> void:
	if not GameplayUtil.player_valid() or state == State.COUNTDOWN:
		return
	_teleport(get_respawn_transform())

func get_respawn_transform() -> Transform2D:
	if last_gate_index >= 0 and last_gate_index < gates.size():
		var g := gates[last_gate_index]
		var fwd := Vector2.from_angle(g.global_rotation)
		var base := g.global_position + fwd * RESPAWN_AHEAD_M * Game.PX_PER_M
		return Transform2D(g.global_rotation, _clear_point(base, fwd, g.global_position))
	return GameplayUtil.spawn_transform(get_tree())

## Moving structure (the crane boom) or traffic can be sitting on the respawn
## point: step further along the course, then try just behind the gate.
func _clear_point(base: Vector2, fwd: Vector2, gate_pos: Vector2) -> Vector2:
	var space := get_viewport().world_2d.direct_space_state if is_inside_tree() else null
	if space == null:
		return base
	var circle := CircleShape2D.new()
	circle.radius = 8.0 * Game.PX_PER_M
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = circle
	q.collision_mask = Game.LAYER_WORLD | Game.LAYER_TRAFFIC
	var candidates: Array[Vector2] = []
	for i in 6:
		candidates.append(base + fwd * i * 6.0 * Game.PX_PER_M)
	candidates.append(gate_pos - fwd * 10.0 * Game.PX_PER_M)
	for c in candidates:
		q.transform = Transform2D(0.0, c)
		if space.intersect_shape(q, 1).is_empty():
			return c
	return base

func _teleport(xf: Transform2D) -> void:
	var dmg := get_tree().get_first_node_in_group(&"damage_system") as DamageSystem
	if dmg:
		dmg.teleport_player(xf)
	elif Game.player.has_method(&"respawn_at"):
		Game.player.call(&"respawn_at", xf)
	_have_prev = false

# ============================================================== physics ===
func _physics_process(delta: float) -> void:
	if not _setup_done:
		if Game.level != null and is_instance_valid(Game.level):
			_setup()
		return
	finish_display_time = maxf(0.0, finish_display_time - delta)
	match state:
		State.COUNTDOWN:
			_tick_countdown(delta)
		State.RUNNING:
			race_time += delta
	if not GameplayUtil.player_alive():
		_have_prev = false
		return
	var pos := Game.player.global_position
	if _have_prev and state != State.COUNTDOWN:
		_check_crossing(_prev_pos, pos)
	_prev_pos = pos
	_have_prev = true

func _tick_countdown(delta: float) -> void:
	GameplayUtil.set_controls(false)
	_countdown_left -= delta
	var v := int(ceil(_countdown_left / COUNTDOWN_STEP))
	if v != countdown_value:
		countdown_value = v
		countdown_tick.emit(maxi(v, 0))
		if v > 0:
			_play(_snd_count, -13.0, 1.0)
	if _countdown_left <= 0.0:
		countdown_value = 0
		_play(_snd_go, -12.0, 1.0)
		GameplayUtil.set_controls(true)
		state = State.RUNNING
		race_time = 0.0
		Game.race_started.emit()
		_refresh_visuals()

func _check_crossing(a: Vector2, b: Vector2) -> void:
	var g := next_gate()
	if g == null:
		return
	var c := g.global_position
	var fwd := Vector2.from_angle(g.global_rotation)
	var span := fwd.orthogonal()
	var d0 := (a - c).dot(fwd)
	var d1 := (b - c).dot(fwd)
	# Must go from behind (-X side) to in front, i.e. the right direction.
	if not (d0 < 0.0 and d1 >= 0.0):
		return
	var t := d0 / (d0 - d1)
	var hit := a.lerp(b, t)
	var half := float(g.get_meta(&"width_m", 40.0)) * 0.5 + PASS_MARGIN_M
	if absf((hit - c).dot(span)) <= half * Game.PX_PER_M:
		# Exact crossing time inside this step for a fairer clock.
		var sub := (1.0 - t) * get_physics_process_delta_time()
		_on_gate_passed(next_index, sub)

func _on_gate_passed(i: int, overshoot: float) -> void:
	var total := gates.size()
	last_gate_index = i
	gate_passed.emit(i)
	if i < visuals.size():
		visuals[i].pulse()
	if state == State.IDLE:
		if i != 0:
			return
		# Flying start.
		state = State.RUNNING
		race_time = overshoot
		current_splits.clear()
		finish_display_time = 0.0
		Game.race_started.emit()
		_play(_snd_go, -14.0, 1.0)
	var split := race_time - overshoot
	current_splits.append(split)
	has_last_delta = i > 0 and i < best_splits.size()
	if has_last_delta:
		last_split_delta = split - best_splits[i]
	Game.checkpoint_passed.emit(i + 1, total, split)
	if i == total - 1:
		_finish(split)
		return
	_play(_snd_gate, -11.0, 1.0 + 0.25 * float(i) / maxf(1.0, total - 1.0))
	next_index = i + 1
	_refresh_visuals()

func _finish(time: float) -> void:
	last_finish_was_best = time < best_time
	if last_finish_was_best:
		best_time = time
		best_splits = current_splits.duplicate()
		_save_records()
	last_finish_time = time
	finish_display_time = 6.0
	Game.race_finished.emit(time, best_time)
	_play(_snd_finish, -8.0, 1.0)
	var msg := "FINISH  %s" % GameplayUtil.format_time(time)
	if last_finish_was_best:
		msg += "  —  NEW BEST"
	else:
		msg += "  (best %s, %s)" % [GameplayUtil.format_time(best_time), GameplayUtil.format_delta(time - best_time)]
	Game.toast(msg, 5.0)
	state = State.IDLE
	next_index = 0
	_refresh_visuals()

func _refresh_visuals() -> void:
	var racing := state != State.IDLE
	for i in visuals.size():
		var s := RaceGateVisual.GateState.FUTURE
		if racing and i < next_index:
			s = RaceGateVisual.GateState.PASSED
		elif i == next_index:
			s = RaceGateVisual.GateState.NEXT
		elif i == next_index + 1:
			s = RaceGateVisual.GateState.AFTER
		visuals[i].set_state(s)

## Cue levels sit above the music bed but below heavy crashes and the
## explosion: these files are the hottest in the set (race_go peaks ~-5 LUFS).
func _play(stream: AudioStream, vol: float, pitch: float) -> void:
	GameplayUtil.play_oneshot(self, stream, vol, pitch, &"UI")

## Changing ships mid-race abandons the lap; records are kept per ship.
func _on_player_changed(_ship: RigidBody2D, _old: RigidBody2D) -> void:
	if state != State.IDLE:
		state = State.IDLE
		GameplayUtil.set_controls(true)
		Game.toast("Race abandoned  ·  changed ship", 2.0)
	next_index = 0
	last_gate_index = -1
	race_time = 0.0
	current_splits.clear()
	has_last_delta = false
	_have_prev = false
	_load_records()
	if _setup_done and best_splits.size() != gates.size():
		best_splits.clear()
	_refresh_visuals()

# ============================================================= records ===
## ConfigFile section: "race" for the WREN (unchanged, old saves still load),
## "race_<id>" for other ships.
func _section() -> String:
	if GameplayUtil.player_valid() and Game.player.has_method(&"ship_id"):
		var id := String(Game.player.call(&"ship_id"))
		if id != "wren":
			return "race_" + id
	return "race"

func _load_records() -> void:
	best_time = INF
	best_splits.clear()
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		return
	best_time = float(cf.get_value(_section(), "best", INF))
	for v in cf.get_value(_section(), "splits", []):
		best_splits.append(float(v))

func _save_records() -> void:
	var cf := ConfigFile.new()
	cf.load(SAVE_PATH)   # keep the other ships' records
	cf.set_value(_section(), "best", best_time)
	cf.set_value(_section(), "splits", best_splits)
	cf.save(SAVE_PATH)

## Forget the stored best lap (not bound to a key; handy from the debugger).
func clear_records() -> void:
	best_time = INF
	best_splits.clear()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
