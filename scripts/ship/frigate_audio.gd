class_name FrigateAudio
extends Node
## KESTREL sound. A 120 t frigate is felt more than heard:
##   * the reactor / drive hum (a low D, inside the music bed) runs whenever
##     the ship is powered; the impulse throb swells over it with the main
##     engines, deeper and slower than the small ships;
##   * the RCS is the WREN's hiss bed pitched far down, plus a heavy valve
##     thud each time a quad group opens;
##   * docking: the clamp rams, jaws and locking bolts, the gangway running
##     out and sealing, and the reverse on undocking;
##   * damage: shield hits (energy crackle), the shield collapsing and coming
##     back, hull breaches, venting atmosphere, the hull groaning under heavy
##     hits, the red-alert tone when you go to red alert and the core-breach
##     warning while the reactor is failing.
## Silent while parked; the Engine bus fades out on foot like the others.

const RED_ALERT_TIME := 7.2      ## three cycles, then quiet (it repeats on new damage)

var ship: FrigateShip
var _hum: AudioStreamPlayer2D
var _impulse: AudioStreamPlayer2D
var _hiss: AudioStreamPlayer2D
var _vent: AudioStreamPlayer2D
var _alert: AudioStreamPlayer
var _core: AudioStreamPlayer
var _burst: AudioStreamPlayer2D
var _snd := {}
var _eng := 0.0
var _hiss_amp := 0.0
var _rcs_prev := PackedFloat32Array([0, 0, 0, 0, 0, 0])
var _since_burst := 10.0
var _alert_left := 0.0
var _since_alert := 99.0
var _loops: Array[AudioStreamPlayer2D] = []


func _ready() -> void:
	ship = get_parent() as FrigateShip
	_hum = _loop("frigate_drive_hum_loop.wav", &"Engine")
	_impulse = _loop("frigate_impulse_loop.wav", &"Engine")
	_hiss = _loop("rcs_hiss_loop.wav", &"Engine")
	_vent = _loop("venting_loop.wav", &"SFX")
	var a := GameplayUtil.load_loop("red_alert_loop.wav")
	if a:
		_alert = GameplayUtil.make_player(self, a, &"UI", -13.0)
	var c := GameplayUtil.load_loop("core_breach_loop.wav")
	if c:
		_core = GameplayUtil.make_player(self, c, &"UI", -11.0)
	var b := GameplayUtil.load_audio("frigate_rcs_burst.wav")
	if b:
		_burst = AudioStreamPlayer2D.new()
		_burst.stream = b
		_burst.bus = GameplayUtil.bus(&"Engine")
		_burst.max_polyphony = 3
		_burst.max_distance = 5000.0
		ship.add_child.call_deferred(_burst)
	for n in ["frigate_clamp_engage", "frigate_clamp_release", "gangway_extend", "gangway_retract",
			"shield_down", "shield_up", "hull_breach", "frigate_hull_groan"]:
		_snd[n] = GameplayUtil.load_audio(n + ".wav")
	_snd["shield_hit"] = GameplayUtil.load_variations("shield_hit_", 3, 1.08, 2.0)
	if ship:
		ship.dock_event.connect(_on_dock)
		ship.damage_event.connect(_on_damage)


func _loop(file: String, bus: StringName) -> AudioStreamPlayer2D:
	var s := GameplayUtil.load_loop(file)
	if s == null:
		return null
	var p := AudioStreamPlayer2D.new()
	p.stream = s
	p.bus = GameplayUtil.bus(bus)
	p.volume_db = -80.0
	p.max_distance = 5000.0
	p.attenuation = 1.0
	ship.add_child.call_deferred(p)
	p.ready.connect(p.play, CONNECT_ONE_SHOT)
	# Quitting mid-loop otherwise leaks the playback (and its stream): stop
	# it as it leaves the tree, release the stream when it is freed.
	p.tree_exiting.connect(p.stop)
	p.tree_exited.connect(func() -> void:
		if p.is_queued_for_deletion():
			p.stream = null)
	_loops.append(p)
	return p


func _process(delta: float) -> void:
	if ship == null:
		return
	for p in _loops:
		if p.is_inside_tree() and not p.playing:
			p.play()
	var live := ship.alive and ship.powered
	var mine := live and Game.player == ship
	_since_burst += delta
	var e := ship.engine_out
	var fwd := maxf(e.x, (e.y + e.z) * 0.5) if live else 0.0
	_eng = move_toward(_eng, fwd, delta * (2.5 if fwd > _eng else 1.2))
	if _hum:
		_hum.volume_db = lerpf(_hum.volume_db, -12.0 + 3.0 * _eng if live else -80.0, minf(1.0, delta * 2.0))
		_hum.pitch_scale = 1.0 + 0.04 * _eng
	if _impulse:
		_impulse.volume_db = -80.0 if _eng < 0.01 else lerpf(-26.0, -4.0, sqrt(_eng))
		_impulse.pitch_scale = 0.85 + 0.25 * _eng + 0.04 * clampf(ship.speed_mps() / 50.0, 0.0, 1.0)
	# ---- RCS: deep hiss bed + a valve thud on every opening ----
	var lv := ship.rcs_levels() if live else PackedFloat32Array([0, 0, 0, 0, 0, 0])
	var act := 0.0
	for i in lv.size():
		var raw := minf(lv[i], 1.5)
		act += minf(raw, 1.0)
		if raw > 0.08 and _rcs_prev[i] < 0.03:
			_rcs_onset(raw)
		_rcs_prev[i] = raw
	var tgt := clampf(act, 0.0, 1.2)
	_hiss_amp = lerpf(_hiss_amp, tgt, 1.0 - exp(-(20.0 if tgt > _hiss_amp else 6.0) * delta))
	if _hiss:
		_hiss.volume_db = -80.0 if _hiss_amp <= 0.001 else lerpf(-38.0, -12.0, sqrt(clampf(_hiss_amp / 1.2, 0.0, 1.0)))
		_hiss.pitch_scale = 0.5 + 0.06 * _hiss_amp
	# ---- venting: louder with every open breach ----
	var vents := 0
	if live or ship.alive:
		for b in ship.damage.breaches:
			if ship.damage.venting(b):
				vents += 1
	if _vent:
		_vent.volume_db = lerpf(_vent.volume_db, -80.0 if vents == 0 else -16.0 + 2.0 * minf(vents, 4), minf(1.0, delta * 3.0))
	# ---- alarms (only for the pilot) ----
	_since_alert += delta
	_alert_left = maxf(0.0, _alert_left - delta)
	if _alert:
		var want := mine and _alert_left > 0.0 and ship.red_alert
		if want and not _alert.playing:
			_alert.play()
		elif not want and _alert.playing:
			_alert.stop()
	if _core:
		var want := mine and ship.damage.core_breach >= 0.0
		if want and not _core.playing:
			_core.play()
		elif not want and _core.playing:
			_core.stop()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for p in _loops:
			if is_instance_valid(p):
				p.stop()
				p.stream = null


func _rcs_onset(strength: float) -> void:
	if _burst == null or not _burst.is_inside_tree() or _since_burst < 0.12:
		return
	_since_burst = 0.0
	_burst.volume_db = lerpf(-16.0, -8.0, clampf(strength, 0.0, 1.0))
	_burst.pitch_scale = randf_range(0.92, 1.06)
	_burst.play()


func _on_dock(ev: String) -> void:
	match ev:
		"capture": _play("frigate_clamp_engage", -2.0)
		"lock": _play("gangway_extend", -6.0)
		"undock": _play("gangway_retract", -6.0)
		"unclamp": _play("frigate_clamp_release", -3.0)


func _on_damage(kind: String, data: Dictionary) -> void:
	match kind:
		"hit":
			var amt := float(data.get("amount", 0.0))
			if float(data.shield) > 0.0:
				_play("shield_hit", lerpf(-12.0, -2.0, clampf(amt / 20.0, 0.0, 1.0)), randf_range(0.92, 1.08))
			if bool(data.breach):
				_play("hull_breach", -4.0)
			elif float(data.hull) > 5.0:
				_play("frigate_hull_groan", -6.0)
			# New damage while at red alert sounds it again (not too often).
			if ship.red_alert and float(data.hull) > 1.0 and _since_alert > 12.0:
				_since_alert = 0.0
				_alert_left = RED_ALERT_TIME
		"shields_down": _play("shield_down", -2.0)
		"shields_up": _play("shield_up", -8.0)
		"alert":
			if bool(data.on):
				_since_alert = 0.0
				_alert_left = RED_ALERT_TIME


func _play(n: String, db: float, pitch := 1.0) -> void:
	var s: AudioStream = _snd.get(n)
	if s == null or not ship.is_inside_tree():
		return
	var p := AudioStreamPlayer2D.new()
	p.stream = s
	p.bus = GameplayUtil.bus(&"SFX")
	p.volume_db = db
	p.pitch_scale = pitch
	p.max_distance = 6000.0
	ship.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
