class_name ShuttleAudio
extends Node
## PETREL sound: twin engines (smoother and higher than the WREN), an
## afterburner layer, the gyro's reaction-wheel whine (you can hear "nose
## first, then go"), the hover hum and the low-hull alarm. All loops run
## continuously and are gated by volume (cheap, click-free). Silent while
## parked (unpowered); the Engine bus fades out while you're on foot.

var ship: ShuttleShip
var _engine: AudioStreamPlayer2D
var _burner: AudioStreamPlayer2D
var _gyro: AudioStreamPlayer2D
var _hover: AudioStreamPlayer2D
var _alarm: AudioStreamPlayer
var _eng := 0.0
var _jit := 0.0


func _ready() -> void:
	ship = get_parent() as ShuttleShip
	_engine = _loop("petrel_engine_loop.wav", &"Engine")
	_burner = _loop("petrel_afterburner_loop.wav", &"Engine")
	_gyro = _loop("gyro_whine_loop.wav", &"Engine")
	_hover = _loop("hover_hum_loop.wav", &"Engine")
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
	_eng = move_toward(_eng, ship.main_frac if live else 0.0, delta * (6.0 if ship.main_frac > _eng else 3.0))
	if _engine:
		_engine.volume_db = -80.0 if not live else lerpf(-22.0, -5.0, sqrt(_eng))
		_engine.pitch_scale = 0.8 + 0.45 * _eng + 0.05 * clampf(ship.speed_mps() / 36.0, 0.0, 1.2)
	if _burner:
		_burner.volume_db = lerpf(_burner.volume_db, -6.0 if live and ship.boosting else -60.0, minf(1.0, delta * 8.0))
	if _gyro:
		var w := absf(ship.angular_velocity) / 3.5
		var g := clampf(w * 0.6 + ship.gyro_frac * 0.7, 0.0, 1.0) if live else 0.0
		_jit = randf_range(-0.06, 0.06) if ship.gyro_heat > 0.7 else 0.0
		_gyro.volume_db = lerpf(-40.0, -10.0, g) if live else -80.0
		_gyro.pitch_scale = clampf(0.5 + 1.8 * g + _jit, 0.4, 2.4)
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
