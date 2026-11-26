extends Control
## H: controls overlay (works while paused). Also hosts the intro card shown
## for the first few seconds of a session.

const CONTROLS := [
	["Flight", ""],
	["W / ↑", "Main engine (thrust at the bow)"],
	["S / ↓", "Retro thrust"],
	["A D / ← →", "Bow side thrusters — turn AND push sideways"],
	["Q / E", "Strafe thrusters"],
	["Space / Shift", "Boost (alone = punch forward)"],
	["F", "Flight assist (damps spin and slip)"],
	["Game", ""],
	["R", "Race: restart with 3-2-1 countdown"],
	["T", "Reset to last gate / spawn pad"],
	["Dock", "Settle on a pad < 1.5 m/s, aligned, no spin"],
	["View", ""],
	["C", "Camera: north-up / rotate with ship"],
	["Wheel  = / -", "Zoom"],
	["M", "Radar / station map"],
	["G", "Flight guide (prograde + predicted path)"],
	["Tab / F1", "Flight-model tuning panel"],
	["F3", "Physics debug overlay"],
	["P / Esc", "Pause"],
	["X", "Exit the ship (when docked)"],
	["H", "This help"],
]
const CONTROLS_PETREL := [
	["PETREL shuttle", ""],
	["W A S D / ↑ ← ↓ →", "Go that way: the gyro swings the nose, engines open as it lines up"],
	["Shift", "Afterburner"],
	["Space (hold)", "Hover: brake to a stop, heading locked, WASD slides"],
	["Space over a deck", "Keep holding: descend onto mag-skids (land anywhere)"],
	["Q / LMB (hold)", "Mag-line: hook cargo, structure or traffic; let go to fling"],
	["E / RMB (hold)", "Reel the line in (stalls under heavy load)"],
	["F", "Floodlights"],
	["X", "Get out (when landed)  ·  any move input lifts off"],
	["View", ""],
	["C · Wheel · M · G", "Camera · zoom · map · flight guide"],
	["R / T", "Race / reset (best lap kept per ship)"],
	["P / Esc · H", "Pause · this help"],
]
const CONTROLS_ON_FOOT := [
	["On foot", ""],
	["W A S D / ↑ ← ↓ →", "Walk"],
	["Shift", "Run"],
	["E / Enter", "Use: doors, switches, terminals, board ship"],
	["F", "Helmet flashlight"],
	["Wheel  = / -", "Zoom"],
	["Docked ship", ""],
	["X", "Exit the ship (when docked and clamped)"],
	["Game", ""],
	["P / Esc", "Pause"],
	["H", "This help"],
]
const INTRO_TIME := 7.0

var showing := false
var _intro_t := 0.0
var _a := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	if Game.cmd.has("no-intro"):
		_intro_t = INTRO_TIME

func _poll_input() -> void:
	if Input.is_action_just_pressed(&"help"):
		showing = not showing
		_intro_t = INTRO_TIME
		GameplayUtil.play_oneshot(self, GameplayUtil.load_audio("ui_click.wav"), -10.0, 1.0, &"UI")

func _process(delta: float) -> void:
	_poll_input()
	_intro_t += delta
	_a = move_toward(_a, 1.0 if showing else 0.0, delta * 6.0)
	queue_redraw()

func _draw() -> void:
	if _intro_t < INTRO_TIME and not showing:
		_draw_intro(clampf(minf(_intro_t * 2.0, (INTRO_TIME - _intro_t) * 1.2), 0.0, 1.0))
	if _a <= 0.01:
		return
	var rows: Array = CONTROLS
	if Game.mode == Game.Mode.ON_FOOT:
		rows = CONTROLS_ON_FOOT
	elif Game.player is ShuttleShip:
		rows = CONTROLS_PETREL
	var w := 940.0 if rows == CONTROLS_PETREL else 720.0
	var h := 64.0 + rows.size() * 30.0
	var r := Rect2((size - Vector2(w, h)) * 0.5, Vector2(w, h))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0.01, 0.03, 0.45 * _a))
	HudStyle.draw_panel(self, r, 18.0, Color(HudStyle.CYAN, 0.8 * _a), Color(0.02, 0.05, 0.1, 0.88 * _a))
	HudStyle.text(self, r.position + Vector2(32, 44), "CONTROLS", 26, Color(HudStyle.WHITE, _a))
	HudStyle.text(self, r.position + Vector2(0, 44), "H to close", 16, Color(HudStyle.MUTED, _a), HORIZONTAL_ALIGNMENT_RIGHT, w - 32.0)
	var y := r.position.y + 84.0
	for row in rows:
		if row[1] == "":
			HudStyle.label(self, Vector2(r.position.x + 32, y), row[0], Color(HudStyle.CYAN, _a), 15)
			draw_line(Vector2(r.position.x + 110, y - 5), Vector2(r.end.x - 32, y - 5), Color(HudStyle.CYAN, 0.2 * _a), 1.0)
		else:
			HudStyle.text(self, Vector2(r.position.x + 48, y), row[0], 18, Color(HudStyle.WHITE, _a))
			HudStyle.text(self, Vector2(r.position.x + 230, y), row[1], 18, Color(HudStyle.MUTED.lightened(0.2), _a))
		y += 30.0

func _draw_intro(a: float) -> void:
	if a <= 0.0:
		return
	var w := 900.0
	var r := Rect2(Vector2((size.x - w) * 0.5, size.y * 0.24), Vector2(w, 150))
	HudStyle.draw_panel(self, r, 18.0, Color(HudStyle.CYAN, 0.8 * a), Color(0.02, 0.05, 0.1, 0.7 * a))
	HudStyle.text(self, r.position + Vector2(0, 54), "MERIDIAN APPROACH", 40, Color(HudStyle.WHITE, a), HORIZONTAL_ALIGNMENT_CENTER, w)
	HudStyle.text(self, r.position + Vector2(0, 84), "Meridian Station · traffic control space · courier flight", 17, Color(HudStyle.CYAN, a), HORIZONTAL_ALIGNMENT_CENTER, w)
	var line := "W thrust   A/D bow thrusters   Q/E strafe   Space boost   F flight assist"
	var line2 := "R start race   H help   Tab tuning   F3 physics debug"
	HudStyle.text(self, r.position + Vector2(0, 114), line, 18, Color(HudStyle.WHITE, 0.9 * a), HORIZONTAL_ALIGNMENT_CENTER, w)
	HudStyle.text(self, r.position + Vector2(0, 138), line2, 18, Color(HudStyle.MUTED.lightened(0.2), a), HORIZONTAL_ALIGNMENT_CENTER, w)
