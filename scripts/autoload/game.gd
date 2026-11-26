extends Node
## Global event bus, shared constants, input map and debug/test harness.
## Autoloaded as `Game`. Every other system talks through the signals here so
## that ship, level, FX and HUD stay decoupled.

# ---------------------------------------------------------------- units ----
## World units are pixels. 1 metre = PX_PER_M pixels. Physics tuning is
## authored in SI units (metres, kg, newtons) and converted with this factor.
const PX_PER_M := 10.0

# ----------------------------------------------------- collision layers ----
## Bit VALUES (use with collision_layer / collision_mask directly).
const LAYER_WORLD := 1      # layer 1: station structures (Static/AnimatableBody2D)
const LAYER_PLAYER := 2     # layer 2: the player ship
const LAYER_PROPS := 4      # layer 3: free-floating props (containers, debris)
const LAYER_TRAFFIC := 8    # layer 4: AI traffic ships
const LAYER_TRIGGERS := 16  # layer 5: Area2D triggers (race gates, docking pads)
const LAYER_WALK := 32      # layer 6: on-foot obstacles only the walker hits (railings, furniture, interior walls)
const LAYER_WALKER := 64    # layer 7: the on-foot player character

# -------------------------------------------------------- z-index plan ----
## Absolute z_index values for top-level containers. Children stay relative 0.
const Z_BELOW_DECK := -50     # non-colliding decks/structure the ship flies OVER
const Z_STRUCTURE := -10      # colliding station structure (ship level)
const Z_PROPS := 0            # containers, traffic, gates
const Z_SHIP := 5             # player ship
const Z_FX := 8               # sparks, explosions, debris
const Z_OVERHEAD := 20        # non-colliding structure the ship flies UNDER
const Z_OVERHEAD_FX := 30     # lights/glows on overhead structure
## On foot the same plan applies: decks/floors are below, the walker stands at
## Z_WALKER (just above a landed ship), interior wall tops cover it.
const Z_WALKER := 6
const Z_WALL_TOP := 12

# --------------------------------------------------------- game mode ----
## FLIGHT: you fly the ship. ON_FOOT: you walk around (outside on a pad or
## inside an interior). Systems that only make sense in one mode check this
## or listen to `mode_changed`.
enum Mode { FLIGHT, ON_FOOT }
var mode: Mode = Mode.FLIGHT:
	set(v):
		if v == mode:
			return
		mode = v
		mode_changed.emit(v)

# -------------------------------------------------------------- signals ----
## A collision worth reacting to. `speed_mps` is the closing speed along the
## contact normal in metres/second. `source` is the body that reported it
## (the player reports all of its own contacts; props only report contacts
## that do NOT involve the player, to avoid double events).
signal impact(pos: Vector2, normal: Vector2, speed_mps: float, source: Node, other: Node)
## Emitted every physics frame while the player is sliding along something.
## Silence (no emission for ~0.1 s) means scraping stopped.
signal scrape(pos: Vector2, normal: Vector2, tangent_speed_mps: float, source: Node)
signal hull_changed(hull: float, max_hull: float)
signal ship_destroyed(pos: Vector2)
signal ship_respawned(pos: Vector2)
signal race_started()
signal checkpoint_passed(index: int, total: int, split_time: float)
signal race_finished(time: float, best: float)
signal docked(pad_name: String)
signal undocked(pad_name: String)
## HUD toast message.
signal message(text: String, duration: float)
signal mode_changed(new_mode: Mode)
## The ship you control changed (you boarded a different one).
signal player_changed(new_ship: RigidBody2D, old_ship: RigidBody2D)
## On-foot milestones (pad name / interior name), for HUD, audio and tests.
signal disembarked(pad_name: String)
signal boarded(pad_name: String)
signal entered_interior(interior_name: String)
signal exited_interior(interior_name: String)
signal debug_draw_changed(enabled: bool)

# ------------------------------------------------------ shared refs ------
var player: RigidBody2D      ## set by the player ship in _ready
var camera: Camera2D         ## set by the camera rig in _ready
var level: Node2D            ## set by the level root in _ready
var walker: Node2D           ## the on-foot character while it exists (else null)
## Playable area in pixels; the level overwrites this in _ready.
var world_bounds := Rect2(-8000, -6000, 16000, 12000)
## Physics/collision debug overlay (toggled with F3).
var debug_draw := false:
	set(v):
		debug_draw = v
		debug_draw_changed.emit(v)

## Parsed user command-line args (everything after `--`), e.g. `--spawn=0,0,90`.
var cmd := {}

# ---------------------------------------------------------- helpers ------
## Switch the controlled ship (systems listen to player_changed to reset
## per-ship state: camera look-ahead, damage, race, docking ...).
func set_player(ship: RigidBody2D) -> void:
	if ship == player:
		return
	var old := player
	player = ship
	player_changed.emit(ship, old)

static func to_m(px: float) -> float:
	return px / PX_PER_M

static func to_px(m: float) -> float:
	return m * PX_PER_M

func toast(text: String, duration := 2.5) -> void:
	message.emit(text, duration)

## Loads an audio stream and guarantees it loops (WAV or Ogg).
func get_loop(path: String) -> AudioStream:
	var s: AudioStream = load(path)
	if s == null:
		push_warning("Missing audio: " + path)
		return null
	if s is AudioStreamWAV:
		var w: AudioStreamWAV = s.duplicate()
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(round(w.get_length() * w.mix_rate))
		return w
	if s is AudioStreamOggVorbis:
		var o: AudioStreamOggVorbis = s.duplicate()
		o.loop = true
		return o
	return s

## Builds an AudioStreamRandomizer from several one-shot variations.
func get_variations(paths: Array, pitch_rand := 1.08, vol_rand_db := 2.0) -> AudioStream:
	var r := AudioStreamRandomizer.new()
	r.random_pitch = pitch_rand
	r.random_volume_offset_db = vol_rand_db
	for p in paths:
		var s: AudioStream = load(p)
		if s:
			r.add_stream(-1, s)
	return r

# ------------------------------------------------------------ input ------
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_register_inputs()
	_parse_args()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug_draw"):
		debug_draw = not debug_draw
		toast("Physics debug overlay: %s" % ("ON" if debug_draw else "OFF"), 1.5)

func _register_inputs() -> void:
	_action(&"thrust_forward", [KEY_W, KEY_UP], [], [[JOY_AXIS_TRIGGER_RIGHT, 1.0], [JOY_AXIS_LEFT_Y, -1.0]])
	_action(&"thrust_reverse", [KEY_S, KEY_DOWN], [], [[JOY_AXIS_TRIGGER_LEFT, 1.0], [JOY_AXIS_LEFT_Y, 1.0]])
	_action(&"turn_left", [KEY_A, KEY_LEFT], [JOY_BUTTON_DPAD_LEFT], [[JOY_AXIS_LEFT_X, -1.0]])
	_action(&"turn_right", [KEY_D, KEY_RIGHT], [JOY_BUTTON_DPAD_RIGHT], [[JOY_AXIS_LEFT_X, 1.0]])
	_action(&"strafe_left", [KEY_Q], [JOY_BUTTON_LEFT_SHOULDER])
	_action(&"strafe_right", [KEY_E], [JOY_BUTTON_RIGHT_SHOULDER])
	_action(&"boost", [KEY_SPACE, KEY_SHIFT], [JOY_BUTTON_A])
	_action(&"flight_assist", [KEY_F], [JOY_BUTTON_Y])
	_action(&"camera_mode", [KEY_C], [JOY_BUTTON_BACK])
	_action(&"zoom_in", [KEY_EQUAL, KEY_KP_ADD])
	_action(&"zoom_out", [KEY_MINUS, KEY_KP_SUBTRACT])
	_mouse_action(&"zoom_in", MOUSE_BUTTON_WHEEL_UP)
	_mouse_action(&"zoom_out", MOUSE_BUTTON_WHEEL_DOWN)
	_action(&"tuning_panel", [KEY_TAB, KEY_F1])
	_action(&"help", [KEY_H])
	_action(&"restart_race", [KEY_R], [JOY_BUTTON_START])
	_action(&"respawn", [KEY_T])
	_action(&"pause", [KEY_P, KEY_ESCAPE])
	_action(&"radar_toggle", [KEY_M])
	_action(&"debug_draw", [KEY_F3])
	# On foot. Separate actions from flight so the two control schemes can be
	# rebound independently even where they share keys (W, E, F ...).
	_action(&"move_up", [KEY_W, KEY_UP], [JOY_BUTTON_DPAD_UP], [[JOY_AXIS_LEFT_Y, -1.0]])
	_action(&"move_down", [KEY_S, KEY_DOWN], [JOY_BUTTON_DPAD_DOWN], [[JOY_AXIS_LEFT_Y, 1.0]])
	_action(&"move_left", [KEY_A, KEY_LEFT], [JOY_BUTTON_DPAD_LEFT], [[JOY_AXIS_LEFT_X, -1.0]])
	_action(&"move_right", [KEY_D, KEY_RIGHT], [JOY_BUTTON_DPAD_RIGHT], [[JOY_AXIS_LEFT_X, 1.0]])
	_action(&"run", [KEY_SHIFT], [JOY_BUTTON_B])
	_action(&"interact", [KEY_E, KEY_ENTER], [JOY_BUTTON_X])
	_action(&"flashlight", [KEY_F, KEY_L], [JOY_BUTTON_Y])
	# Docked: leave the cockpit. X is free in flight (E strafes, which would
	# release the docking clamps).
	_action(&"disembark", [KEY_X], [JOY_BUTTON_X])
	# PETREL shuttle (Space/Q/E/LMB/RMB mean something else in the WREN; each
	# ship reads only its own actions, so shared keys never clash).
	_action(&"ship_hover", [KEY_SPACE], [], [[JOY_AXIS_TRIGGER_LEFT, 1.0]])
	_action(&"ship_line", [KEY_Q], [], [[JOY_AXIS_TRIGGER_RIGHT, 1.0]])
	_mouse_action(&"ship_line", MOUSE_BUTTON_LEFT)
	_action(&"ship_reel", [KEY_E], [JOY_BUTTON_RIGHT_SHOULDER])
	_mouse_action(&"ship_reel", MOUSE_BUTTON_RIGHT)
	_action(&"aim_left", [], [], [[JOY_AXIS_RIGHT_X, -1.0]])
	_action(&"aim_right", [], [], [[JOY_AXIS_RIGHT_X, 1.0]])
	_action(&"aim_up", [], [], [[JOY_AXIS_RIGHT_Y, -1.0]])
	_action(&"aim_down", [], [], [[JOY_AXIS_RIGHT_Y, 1.0]])

func _action(action: StringName, keys: Array, joy_buttons := [], joy_axes := []) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.25)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)
	for b in joy_buttons:
		var e := InputEventJoypadButton.new()
		e.button_index = b
		InputMap.action_add_event(action, e)
	for a in joy_axes:
		var e := InputEventJoypadMotion.new()
		e.axis = a[0]
		e.axis_value = a[1]
		InputMap.action_add_event(action, e)

func _mouse_action(action: StringName, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var e := InputEventMouseButton.new()
	e.button_index = button
	InputMap.action_add_event(action, e)

# ------------------------------------------- debug / test harness --------
## User args (after `--` on the Godot command line):
##   --spawn=x_px,y_px,heading_deg   main.gd places the player here at start
##   --input=T0-T1:action+action;T2-T3:action   scripted input, seconds of physics time
##   --shots=1.0,2.5,4    capture viewport PNGs at these physics times (s)
##   --shot-dir=/abs/dir  where captures go (default user://shots)
##   --quit-at=6.0        quit after this many seconds of physics time
##   --debug-draw         start with the physics debug overlay on
##   --log=0.5            print player state every N seconds
var _sim_time := 0.0
var _harness_time := 0.0          # like _sim_time, but also runs while paused
var _input_spans: Array = []   # [{t0, t1, actions:[StringName], on:bool}]
var _shots: Array = []
var _shot_dir := "user://shots"
var _quit_at := -1.0
var _log_every := -1.0
var _log_accum := 0.0

func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if not s.begins_with("--"):
			continue
		s = s.substr(2)
		var eq := s.find("=")
		if eq == -1:
			cmd[s] = true
		else:
			cmd[s.substr(0, eq)] = s.substr(eq + 1)
	if cmd.has("input"):
		for span in String(cmd["input"]).split(";", false):
			var parts := span.split(":")
			if parts.size() != 2:
				continue
			var times := parts[0].split("-")
			_input_spans.append({
				"t0": float(times[0]), "t1": float(times[1]),
				"actions": Array(parts[1].split("+")).map(func(x): return StringName(x)),
				"on": false,
			})
	if cmd.has("shots"):
		for t in String(cmd["shots"]).split(",", false):
			_shots.append(float(t))
		_shots.sort()
	if cmd.has("shot-dir"):
		_shot_dir = String(cmd["shot-dir"])
	if cmd.has("quit-at"):
		_quit_at = float(cmd["quit-at"])
	if cmd.has("debug-draw"):
		debug_draw = true
	if cmd.has("log"):
		_log_every = float(cmd["log"])

func _physics_process(delta: float) -> void:
	# The harness clock keeps running while the tree is paused, so a scripted
	# `pause` span can release (and a later span unpause) and --quit-at still
	# fires. Outside a pause it equals the simulated time.
	_harness_time += delta
	if get_tree().paused:
		_run_input_spans()
		if _quit_at > 0.0 and _harness_time >= _quit_at and _shots.is_empty():
			get_tree().quit()
		return
	_sim_time += delta
	_run_input_spans()
	_tick_harness(delta)

func _run_input_spans() -> void:
	for span in _input_spans:
		var want: bool = _harness_time >= span.t0 and _harness_time < span.t1
		if want != span.on:
			span.on = want
			for act in span.actions:
				if want:
					Input.action_press(act)
				else:
					Input.action_release(act)

func _tick_harness(delta: float) -> void:
	if _log_every > 0.0 and is_instance_valid(player):
		_log_accum += delta
		if _log_accum >= _log_every:
			_log_accum = 0.0
			var v := player.linear_velocity / PX_PER_M
			print("[t=%.2f] pos_m=(%.1f, %.1f) speed=%.2f m/s vel=(%.2f, %.2f) heading=%.1f deg omega=%.3f rad/s" % [
				_sim_time, player.global_position.x / PX_PER_M, player.global_position.y / PX_PER_M,
				v.length(), v.x, v.y, rad_to_deg(player.global_rotation), player.angular_velocity])
	if not _shots.is_empty() and _harness_time >= _shots[0]:
		var t: float = _shots.pop_front()
		_capture(t)
	if _quit_at > 0.0 and _harness_time >= _quit_at and _shots.is_empty():
		get_tree().quit()

func _capture(t: float) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	var img := get_viewport().get_texture().get_image()
	var path := "%s/shot_%06.2f.png" % [_shot_dir, t]
	img.save_png(path)
	print("[shot] ", ProjectSettings.globalize_path(path))

## Seconds of simulated physics time since launch (for tests).
func sim_time() -> float:
	return _sim_time
