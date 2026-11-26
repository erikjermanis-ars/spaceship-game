@tool
extends StationModule
## An AI ship (AnimatableBody2D on LAYER_TRAFFIC) driven along a traffic lane.
## The owning lane calls nothing per frame: each ship advances its own
## distance along the lane's sampled path in _physics_process.

@export_enum("shuttle", "tug", "freighter") var kind := "shuttle":
	set(v): kind = v; queue_rebuild()
@export var livery := Color("2A9D8F"):
	set(v): livery = v; queue_rebuild()
@export var seed := 0:
	set(v): seed = v; queue_rebuild()
@export var speed_mps := 28.0
@export var ship_name := "MERIDIAN TRANSIT"

var lane: Node = null      # traffic_lane.gd
var distance := 0.0        # px along the lane
var _engine: AudioStreamPlayer2D


func _build() -> void:
	moving = true
	body_layer = G.LAYER_TRAFFIC
	struct_z = G.Z_PROPS
	on_radar = false
	bounce = 0.2
	var SP := preload("res://scripts/level/ship_painter.gd")
	match kind:
		"tug": SP.tug(self, Transform2D.IDENTITY, seed, true)
		"freighter": SP.freighter(self, Transform2D.IDENTITY, 72.0, 18.0, livery, ship_name, true, seed)
		_: SP.shuttle(self, Transform2D.IDENTITY, livery, seed, true)


func _after_build() -> void:
	if body == null:
		return
	if not Engine.is_editor_hint():
		body.add_to_group(&"radar_traffic")
		body.set_meta("traffic_kind", kind)
		_attach_engine_audio()
	_snap()


func _attach_engine_audio() -> void:
	var path := "res://assets/audio/traffic_engine_loop.wav"
	var game := _game()
	if game == null or not ResourceLoader.exists(path) or not LevelArt.audio_enabled():
		return
	_engine = AudioStreamPlayer2D.new()
	_engine.stream = game.get_loop(path)
	_engine.bus = &"SFX"
	match kind:
		"freighter":
			_engine.pitch_scale = 0.55
			_engine.max_distance = 3200.0
			_engine.volume_db = -12.0
		"tug":
			_engine.pitch_scale = 0.85
			_engine.max_distance = 1800.0
			_engine.volume_db = -14.0
		_:
			_engine.pitch_scale = 1.05 + 0.1 * A.hash01(seed, 1)
			_engine.max_distance = 2000.0
			_engine.volume_db = -13.0
	# The loop is the hottest file in the set (~-12 LUFS): keep passing traffic
	# under the player's own engine, and pan it clearly.
	_engine.attenuation = 2.0
	_engine.panning_strength = 1.3
	_engine.autoplay = true
	body.add_child(_engine)
	_generated.append(_engine)


func _initial_body_transform() -> Transform2D:
	if lane and lane.has_method("sample_transform") and is_inside_tree():
		return global_transform.affine_inverse() * lane.sample_transform(distance)
	return Transform2D.IDENTITY


func _snap() -> void:
	if lane and body and lane.has_method("sample_transform"):
		(body as Node2D).global_transform = lane.sample_transform(distance)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or body == null or lane == null:
		return
	distance += speed_mps * PX * delta
	_snap()
