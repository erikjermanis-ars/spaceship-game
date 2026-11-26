extends Node
## The player ship's own sounds (non-positional: you're sitting in it).
## Engine rumble and boost roar follow the throttle through attack/release
## smoothing; RCS hiss follows thruster activity, with a valve "puff" on every
## nozzle onset; ignition thump when the engine lights; low-hull alarm.
## Every stream is optional (AUDIO produces them in parallel) — missing files
## are skipped silently.

const DIR := "res://assets/audio/"

# Beds sit a few dB under assets/audio/README.md's starting values so impacts
# (the collision showcase) clearly lead the mix over a held throttle.
@export var engine_db_idle := -24.0
@export var engine_db_full := -8.0
@export var boost_db := -9.0
@export var rcs_db := -15.0

var ship: PlayerShip
var visuals: Node

var _engine: AudioStreamPlayer
var _boost: AudioStreamPlayer
var _hiss: AudioStreamPlayer
var _alarm: AudioStreamPlayer
var _puff: AudioStreamPlayer
var _ignite: AudioStreamPlayer
var _kick: AudioStreamPlayer

var _eng_amp := 0.0
var _boost_amp := 0.0
var _hiss_amp := 0.0
var _was_thrusting := false
var _was_boosting := false
var _since_ignite := 10.0
var _since_kick := 10.0
var _since_puff := 10.0
var _hull_frac := 1.0
## Seconds since the low-hull alarm was (re)armed by a fresh hit while low.
var _alarm_t := 100.0
const ALARM_LOUD_S := 3.0       # full-level klaxon after each hit while low
const ALARM_FADE_S := 1.0       # then it fades to a quiet reminder
const ALARM_DB := -14.0
const ALARM_QUIET_DB := -30.0


func _ready() -> void:
	ship = get_parent() as PlayerShip
	visuals = get_node_or_null(^"../Visuals")
	# Headless runs (tests) use the dummy audio driver, which never releases
	# playbacks and reports them as leaks at exit. Skip audio there.
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	_engine = _make_loop("engine_main_loop.wav", &"Engine")
	_boost = _make_loop("engine_boost_loop.wav", &"Engine")
	_hiss = _make_loop("rcs_hiss_loop.wav", &"Engine")
	_alarm = _make_loop("low_hull_alarm.wav", &"UI")
	_puff = _make_oneshot(["rcs_puff_1.wav", "rcs_puff_2.wav", "rcs_puff_3.wav"], &"Engine", 1.12)
	_ignite = _make_oneshot(["engine_ignite.wav"], &"Engine", 1.04)
	_kick = _make_oneshot(["boost_kick.wav"], &"Engine", 1.03)
	for p in [_engine, _boost, _hiss]:
		if p:
			p.volume_db = -80.0
			p.play()
	if visuals and visuals.has_signal(&"rcs_onset"):
		visuals.rcs_onset.connect(_on_rcs_onset)
	Game.hull_changed.connect(func(h: float, m: float) -> void:
		var f := h / maxf(m, 1.0)
		# There is no passive repair, so the klaxon re-arms only when a NEW
		# hit lands while low; otherwise it settles to a quiet reminder.
		if f < 0.25 and f < _hull_frac:
			_alarm_t = 0.0
		_hull_frac = f)


func _bus(name: StringName) -> StringName:
	return name if AudioServer.get_bus_index(name) != -1 else &"Master"


func _make_loop(file: String, bus: StringName) -> AudioStreamPlayer:
	var path := DIR + file
	if not ResourceLoader.exists(path):
		return null
	var stream := Game.get_loop(path)
	if stream == null:
		return null
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = _bus(bus)
	add_child(p)
	return p


func _make_oneshot(files: Array, bus: StringName, pitch_rand: float) -> AudioStreamPlayer:
	var paths: Array = []
	for f in files:
		if ResourceLoader.exists(DIR + f):
			paths.append(DIR + f)
	if paths.is_empty():
		return null
	var p := AudioStreamPlayer.new()
	p.stream = Game.get_variations(paths, pitch_rand, 1.5)
	p.bus = _bus(bus)
	p.max_polyphony = 4
	add_child(p)
	return p


static func _amp_to_db(a: float, floor_db: float, top_db: float) -> float:
	if a <= 0.001:
		return -80.0
	# Perceptual curve: amplitude 0..1 mapped onto a dB range.
	return lerpf(floor_db, top_db, sqrt(clampf(a, 0.0, 1.0)))


func _smooth(cur: float, target: float, attack: float, release: float, delta: float) -> float:
	var rate := attack if target > cur else release
	return lerpf(cur, target, 1.0 - exp(-rate * delta))


func _process(delta: float) -> void:
	if ship == null:
		return
	# The beds always run (volume does the gating). Restart any that stopped,
	# e.g. after the ship was taken out of the tree and put back.
	for p in [_engine, _boost, _hiss]:
		if p and not p.playing:
			p.play()
	var alive := ship.alive
	_since_ignite += delta
	_since_kick += delta
	_since_puff += delta
	var thr := absf(ship.throttle_input) if alive else 0.0
	var speed_k := clampf(ship.speed_mps() / 83.0, 0.0, 1.4)
	var boosting := ship.boosting and alive

	# ---- main engine: idle murmur -> full roar ----
	# Attack matches the plume (ship_visuals ~0.17 s to 95 %), slightly longer tail.
	_eng_amp = _smooth(_eng_amp, thr, 18.0, 6.0, delta)
	if _engine:
		_engine.volume_db = -80.0 if not alive else lerpf(engine_db_idle, engine_db_full, sqrt(_eng_amp))
		_engine.pitch_scale = 0.75 + 0.42 * _eng_amp + 0.08 * speed_k + 0.1 * _boost_amp
	# ---- boost roar ----
	_boost_amp = _smooth(_boost_amp, 1.0 if boosting else 0.0, 18.0, 6.0, delta)
	if _boost:
		_boost.volume_db = _amp_to_db(_boost_amp, -40.0, boost_db)
		_boost.pitch_scale = 0.95 + 0.15 * minf(speed_k, 1.0)
	# ---- RCS hiss ----
	var act := 0.0
	if visuals and alive:
		act = float(visuals.get(&"rcs_activity"))
	_hiss_amp = _smooth(_hiss_amp, clampf(act, 0.0, 1.2), 30.0, 10.0, delta)
	if _hiss:
		_hiss.volume_db = _amp_to_db(_hiss_amp / 1.2, -40.0, rcs_db)
		_hiss.pitch_scale = 0.95 + 0.1 * _hiss_amp

	# ---- ignition: throttle went from 0 to >0 (rate-limited) ----
	var thrusting := thr > 0.05
	if thrusting and not _was_thrusting and _since_ignite > 0.7 and _ignite:
		_ignite.volume_db = -6.0
		_ignite.play()
		_since_ignite = 0.0
	_was_thrusting = thrusting
	# ---- boost kick ----
	if boosting and not _was_boosting and _since_kick > 0.45 and _kick:
		_kick.volume_db = -3.0
		_kick.play()
		_since_kick = 0.0
	_was_boosting = boosting
	# ---- low hull alarm ----
	if _alarm:
		var want := alive and _hull_frac < 0.25
		_alarm_t += delta
		if want and not _alarm.playing:
			_alarm.play()
		elif not want and _alarm.playing:
			_alarm.stop()
		var k := clampf((_alarm_t - ALARM_LOUD_S) / ALARM_FADE_S, 0.0, 1.0)
		_alarm.volume_db = lerpf(ALARM_DB, ALARM_QUIET_DB, k)


func _on_rcs_onset(strength: float) -> void:
	if _puff == null or _since_puff < 0.06:
		return
	_since_puff = 0.0
	_puff.volume_db = lerpf(-18.0, -10.0, clampf(strength, 0.0, 1.0))
	_puff.play()


## The ship can leave and re-enter the tree without being freed: main.gd
## removes and re-adds the PlayerShip to place it at the spawn point. So
## leaving only stops playback, _process restarts the beds, and streams are
## released only when the node is actually freed. (Releasing them on exit used
## to silence every ship sound for the whole session.)
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_EXIT_TREE:
			for p in _players():
				p.stop()
		NOTIFICATION_PREDELETE:
			# Stop before teardown; quitting mid-sound otherwise leaks the
			# playback objects (noisy "still in use" errors at exit).
			for p in _players():
				p.stop()
				p.stream = null


func _players() -> Array[AudioStreamPlayer]:
	var out: Array[AudioStreamPlayer] = []
	for c in get_children():
		if c is AudioStreamPlayer:
			out.append(c)
	return out
