class_name ShuttleAudio
extends Node
## PETREL sound: twin engines (smoother and higher than the WREN) that swell
## over the lower half of the throttle, a hot top-end layer (the old
## afterburner loop) over the upper half, the RCS thrusters (the WREN's hiss
## bed plus a valve "puff" each time a quad opens: the A/D turn couple, Q/E
## strafe, S retro and hover station-keeping), the hover hum and the low-hull
## alarm. S also gives the engines a low retro rumble, as in the WREN. All
## loops run continuously and are gated by volume (cheap, click-free).
## Silent while parked (unpowered); the Engine bus fades out on foot.

const RCS_DB := -15.0
## Retro rumble on the engine bed, as a fraction of the forward "body" level.
const RETRO_RUMBLE := 0.6

var ship: ShuttleShip
var _engine: AudioStreamPlayer2D
var _burner: AudioStreamPlayer2D
var _hiss: AudioStreamPlayer2D
var _puff: AudioStreamPlayer2D
var _hover: AudioStreamPlayer2D
var _alarm: AudioStreamPlayer
var _eng := 0.0
var _retro_amp := 0.0
var _hiss_amp := 0.0
var _since_puff := 10.0
## Per-quad-group firing level last frame (onset detection for the puffs):
## bow port, bow stbd, stern port, stern stbd, aft-pushing, fore-pushing.
var _rcs_prev := PackedFloat32Array([0, 0, 0, 0, 0, 0])
## Last computed RCS activity (0..~1.5), for tests and the debug overlay.
var rcs_activity := 0.0


func _ready() -> void:
	ship = get_parent() as ShuttleShip
	_engine = _loop("petrel_engine_loop.wav", &"Engine")
	_burner = _loop("petrel_afterburner_loop.wav", &"Engine")
	_hiss = _loop("rcs_hiss_loop.wav", &"Engine")
	_hover = _loop("hover_hum_loop.wav", &"Engine")
	var puffs := GameplayUtil.load_variations("rcs_puff_", 3, 1.12, 1.5)
	if puffs:
		_puff = AudioStreamPlayer2D.new()
		_puff.stream = puffs
		_puff.bus = GameplayUtil.bus(&"Engine")
		_puff.max_polyphony = 4
		_puff.max_distance = 2200.0
		_puff.attenuation = 1.2
		ship.add_child.call_deferred(_puff)
	var a := GameplayUtil.load_loop("low_hull_alarm.wav")
	if a:
		_alarm = GameplayUtil.make_player(self, a, &"UI", -14.0)


func _loop(file: String, bus: StringName) -> AudioStreamPlayer2D:
	var s := GameplayUtil.load_loop(file)
	if s == null:
		return null
	var p := AudioStreamPlayer2D.new()
	p.stream = s
	p.bus = GameplayUtil.bus(bus)
	p.volume_db = -80.0
	p.max_distance = 2200.0
	p.attenuation = 1.2
	ship.add_child.call_deferred(p)
	p.ready.connect(p.play, CONNECT_ONE_SHOT)
	return p


func _process(delta: float) -> void:
	if ship == null:
		return
	var live := ship.alive and ship.powered
	_since_puff += delta
	var out := ship.main_output if live else 0.0
	var fwd := maxf(out, 0.0)
	var retro := maxf(-out, 0.0) / maxf(ship.reverse_scale, 0.05)
	_eng = move_toward(_eng, fwd, delta * (6.0 if fwd > _eng else 3.0))
	# S is a 0/1 key: spool the retro rumble like W, or it steps ~13 dB a frame.
	_retro_amp = move_toward(_retro_amp, retro, delta * (6.0 if retro > _retro_amp else 3.0))
	var body := maxf(clampf(_eng * 2.0, 0.0, 1.0), _retro_amp * RETRO_RUMBLE)  # 0-50 % throttle (or retro)
	var hot := clampf(_eng * 2.0 - 1.0, 0.0, 1.0)  # 50-100 %: the old afterburner
	if _engine:
		_engine.volume_db = -80.0 if not live else lerpf(-22.0, -5.0, sqrt(body))
		_engine.pitch_scale = 0.8 + 0.45 * body + 0.08 * hot + 0.05 * clampf(ship.speed_mps() / 36.0, 0.0, 1.2)
	if _burner:
		_burner.volume_db = -80.0 if hot <= 0.001 else lerpf(-34.0, -6.0, sqrt(hot))
	# ---- RCS: hiss bed follows how many quads fire, a puff on each opening ----
	var lv := ship.rcs_levels() if live else PackedFloat32Array([0, 0, 0, 0, 0, 0])
	var act := 0.0
	for i in lv.size():
		var raw := minf(lv[i], 1.5)
		act += minf(raw, 1.0)
		if raw > 0.05 and _rcs_prev[i] < 0.03:
			_on_rcs_onset(raw)
		_rcs_prev[i] = raw
	rcs_activity = clampf(act, 0.0, 1.5)
	var target := clampf(act, 0.0, 1.2)
	var rate := 30.0 if target > _hiss_amp else 10.0
	_hiss_amp = lerpf(_hiss_amp, target, 1.0 - exp(-rate * delta))
	if _hiss:
		_hiss.volume_db = -80.0 if _hiss_amp <= 0.001 else lerpf(-40.0, RCS_DB, sqrt(clampf(_hiss_amp / 1.2, 0.0, 1.0)))
		_hiss.pitch_scale = 0.88 + 0.1 * _hiss_amp   # a touch lower than the WREN's quads
	if _hover:
		var hov := live and (ship.land_state == ShuttleShip.Land.HOVER or ship.land_state == ShuttleShip.Land.DESCENT)
		_hover.volume_db = lerpf(_hover.volume_db, -12.0 if hov else -70.0, minf(1.0, delta * 5.0))
		_hover.pitch_scale = 0.8 + 0.08 * ship.altitude_m
	if _alarm:
		var want := live and Game.player == ship and ship.hull < ship.max_hull * 0.25
		if want and not _alarm.playing:
			_alarm.play()
		elif not want and _alarm.playing:
			_alarm.stop()


func _on_rcs_onset(strength: float) -> void:
	if _puff == null or not _puff.is_inside_tree() or _since_puff < 0.06:
		return
	_since_puff = 0.0
	_puff.volume_db = lerpf(-18.0, -10.0, clampf(strength, 0.0, 1.0))
	_puff.play()
