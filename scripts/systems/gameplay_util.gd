class_name GameplayUtil
extends RefCounted
## Small shared helpers for the gameplay systems and HUD: safe audio loading,
## bus fallback, spawn lookup and duck-typed access to the player ship (the
## PlayerShip class is written by another workstream, so we never hard-depend
## on its type).

const AUDIO_DIR := "res://assets/audio/"

## Transform the player started the session at (set by main.gd). Used as the
## respawn point when no race gate has been passed yet.
static var start_transform := Transform2D.IDENTITY
static var has_start_transform := false

static func audio_path(file: String) -> String:
	return AUDIO_DIR + file

static func audio_exists(file: String) -> bool:
	return ResourceLoader.exists(audio_path(file))

## False in headless runs: the dummy audio driver never releases playbacks,
## so every sound played there shows up as a leak warning at exit. All
## gameplay audio goes through the loaders below, which then return null
## (every caller already tolerates a missing stream).
static func audio_enabled() -> bool:
	return DisplayServer.get_name() != "headless"

## One-shot stream or null when the file is not there (yet).
static func load_audio(file: String) -> AudioStream:
	var p := audio_path(file)
	if not audio_enabled() or not ResourceLoader.exists(p):
		return null
	return load(p) as AudioStream

## Looping stream (via Game.get_loop) or null when missing.
static func load_loop(file: String) -> AudioStream:
	var p := audio_path(file)
	if not audio_enabled() or not ResourceLoader.exists(p):
		return null
	return Game.get_loop(p)

## Randomizer over numbered variations, e.g. ("impact_light_", 4) loads
## impact_light_1..4.wav, skipping missing files. Returns null if none exist.
static func load_variations(prefix: String, count: int, pitch_rand := 1.08, vol_rand_db := 2.0) -> AudioStream:
	if not audio_enabled():
		return null
	var paths: Array = []
	for i in range(1, count + 1):
		var p := audio_path("%s%d.wav" % [prefix, i])
		if ResourceLoader.exists(p):
			paths.append(p)
	if paths.is_empty():
		return null
	return Game.get_variations(paths, pitch_rand, vol_rand_db)

## Returns `wanted` if the bus exists, else "Master" (bus layout is written
## by the audio workstream and may not be present during development).
static func bus(wanted: StringName) -> StringName:
	return wanted if AudioServer.get_bus_index(wanted) != -1 else &"Master"

static func make_player(parent: Node, stream: AudioStream, bus_name: StringName, volume_db := 0.0) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = bus(bus_name)
	p.volume_db = volume_db
	parent.add_child(p)
	return p

## Fire-and-forget one-shot (non positional). The player frees itself.
static func play_oneshot(parent: Node, stream: AudioStream, volume_db := 0.0, pitch := 1.0, bus_name: StringName = &"SFX") -> void:
	if stream == null or parent == null or not parent.is_inside_tree():
		return
	var p := make_player(parent, stream, bus_name, volume_db)
	p.pitch_scale = pitch
	p.finished.connect(p.queue_free)
	p.play()

# ------------------------------------------------------------ player ------
static func player_valid() -> bool:
	return Game.player != null and is_instance_valid(Game.player) and Game.player.is_inside_tree()

## Duck-typed property read with a default (the ship may be a stand-in).
static func pget(obj: Object, prop: StringName, default_value: Variant) -> Variant:
	if obj == null or not is_instance_valid(obj):
		return default_value
	var v: Variant = obj.get(prop)
	return default_value if v == null else v

static func player_alive() -> bool:
	return player_valid() and bool(pget(Game.player, &"alive", true))

static func player_velocity_mps() -> Vector2:
	if not player_valid():
		return Vector2.ZERO
	return Game.player.linear_velocity / Game.PX_PER_M

static func set_controls(enabled: bool) -> void:
	if player_valid() and &"controls_enabled" in Game.player:
		Game.player.set(&"controls_enabled", enabled)

# ------------------------------------------------------------- level ------
## PlayerSpawn marker transform from the level (group player_spawn), the
## recorded start transform, or identity.
static func spawn_transform(tree: SceneTree) -> Transform2D:
	var m := tree.get_first_node_in_group(&"player_spawn") as Node2D
	if m:
		return Transform2D(m.global_rotation, m.global_position)
	if has_start_transform:
		return start_transform
	return Transform2D.IDENTITY

## Sorted list of gate markers (Gate01, Gate02, ...) under Level/RaceCourse.
static func race_gates() -> Array[Node2D]:
	var out: Array[Node2D] = []
	if Game.level == null or not is_instance_valid(Game.level):
		return out
	var course := Game.level.get_node_or_null(^"RaceCourse")
	if course == null:
		course = Game.level.find_child("RaceCourse", true, false)
	if course == null:
		return out
	var named: Array = []
	for c in course.get_children():
		if c is Node2D and String(c.name).begins_with("Gate"):
			named.append(c)
	named.sort_custom(func(a: Node, b: Node) -> bool:
		return String(a.name).naturalnocasecmp_to(String(b.name)) < 0)
	for n in named:
		out.append(n)
	return out

static func format_time(t: float) -> String:
	if t < 0.0 or is_inf(t) or is_nan(t):
		return "--:--.--"
	var m := int(t / 60.0)
	var s := t - m * 60.0
	return "%d:%05.2f" % [m, s]

static func format_delta(d: float) -> String:
	return ("+%.2f" % d) if d >= 0.0 else ("-%.2f" % -d)
