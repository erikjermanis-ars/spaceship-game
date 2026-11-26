extends CanvasLayer
## Live flight-model tuning panel (Tab / F1). Edits the PlayerShip's exported
## SI tunables and the CameraRig's juice settings while you fly. Never pauses.
## All controls use FOCUS_NONE so A/D/arrows keep flying the ship instead of
## nudging a slider; the mouse operates the panel.

const C_BG := Color(0.02, 0.045, 0.08, 0.84)
const C_CYAN := Color("#7FE6FF")
const C_TEAL := Color("#2A9D8F")
const C_TEXT := Color(0.86, 0.92, 0.97)
const C_DIM := Color(0.55, 0.64, 0.74)

## [label, target ("ship"|"cam"), property, min, max, step, unit]
const SLIDERS := [
	["THRUSTERS"],
	["Main thrust", "ship", "main_thrust_n", 0.0, 15000.0, 100.0, "N"],
	["Side thrust (bow RCS)", "ship", "side_thrust_n", 0.0, 10000.0, 50.0, "N"],
	["Thrust point ahead of CoM", "ship", "thrust_point_m", 0.0, 7.0, 0.1, "m"],
	["Strafe thrust", "ship", "strafe_thrust_n", 0.0, 5000.0, 50.0, "N"],
	["Boost multiplier", "ship", "boost_multiplier", 1.0, 4.0, 0.05, "×"],
	["Reverse scale", "ship", "reverse_scale", 0.0, 1.5, 0.05, "×"],
	["MASS & DRAG"],
	["Mass", "ship", "mass_kg", 200.0, 8000.0, 50.0, "kg"],
	["Inertia / mass", "ship", "inertia_per_mass_m2", 1.0, 30.0, 0.01, "m²"],
	["Linear drag", "ship", "linear_drag", 0.0, 1.0, 0.005, "/s"],
	["Angular drag", "ship", "angular_drag", 0.0, 3.0, 0.01, "/s"],
	["COLLISION"],
	["Bounce (restitution)", "ship", "bounce", 0.0, 1.0, 0.01, ""],
	["Friction", "ship", "friction", 0.0, 1.0, 0.01, ""],
	["CAMERA"],
	["Speed zoom amount", "cam", "speed_zoom_amount", 0.0, 1.5, 0.01, ""],
	["Screen shake amount", "cam", "shake_amount", 0.0, 3.0, 0.01, ""],
]

const PRESETS := {
	"Pat Kerr classic": {
		"main_thrust_n": 5000.0, "side_thrust_n": 2600.0, "thrust_point_m": 4.0, "strafe_thrust_n": 1200.0,
		"boost_multiplier": 2.0, "reverse_scale": 0.6, "mass_kg": 1000.0, "inertia_per_mass_m2": 8.37,
		"linear_drag": 0.12, "angular_drag": 0.35, "bounce": 0.05, "friction": 0.2,
	},
	"Nimble racer": {
		"main_thrust_n": 6200.0, "side_thrust_n": 2600.0, "thrust_point_m": 3.4, "strafe_thrust_n": 1800.0,
		"boost_multiplier": 1.8, "reverse_scale": 0.8, "mass_kg": 700.0, "inertia_per_mass_m2": 4.8,
		"linear_drag": 0.16, "angular_drag": 1.1, "bounce": 0.05, "friction": 0.15,
	},
	"Heavy freighter": {
		"main_thrust_n": 13000.0, "side_thrust_n": 5200.0, "thrust_point_m": 5.0, "strafe_thrust_n": 2600.0,
		"boost_multiplier": 1.5, "reverse_scale": 0.4, "mass_kg": 4000.0, "inertia_per_mass_m2": 14.0,
		"linear_drag": 0.07, "angular_drag": 0.22, "bounce": 0.1, "friction": 0.35,
	},
}

var _rows := {}            # property -> {slider, value_label, target, unit}
var _assist: CheckButton
var _derived: Label
var _panel: PanelContainer
var _syncing := false


func _ready() -> void:
	add_to_group(&"tuning_panel")   # the radar steps aside while it is open
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false
	# Test-harness convenience: --tuning opens the panel at start.
	if Game.cmd.has("tuning"):
		visible = true
		_sync_from_targets.call_deferred()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"tuning_panel"):
		visible = not visible
		if visible:
			_sync_from_targets()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not visible:
		return
	# Keep the assist toggle honest if F was pressed while the panel is open.
	var ship := _ship()
	if ship and _assist.button_pressed != ship.flight_assist:
		_syncing = true
		_assist.button_pressed = ship.flight_assist
		_syncing = false


func _ship() -> PlayerShip:
	return Game.player as PlayerShip if is_instance_valid(Game.player) else null


func _target(kind: String) -> Object:
	if kind == "cam":
		return Game.camera if is_instance_valid(Game.camera) else null
	return _ship()


# --------------------------------------------------------------- build --
func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_panel = PanelContainer.new()
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -430
	_panel.offset_right = -16
	_panel.offset_top = 16
	_panel.offset_bottom = -16
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.custom_minimum_size = Vector2(414, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_BG
	sb.border_color = Color(C_CYAN, 0.55)
	sb.set_border_width_all(1)
	sb.border_width_left = 3
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(16)
	sb.shadow_color = Color(0, 0, 0, 0.4)
	sb.shadow_size = 10
	_panel.add_theme_stylebox_override(&"panel", sb)
	root.add_child(_panel)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.focus_mode = Control.FOCUS_NONE
	_panel.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override(&"margin_right", 14)
	scroll.add_child(margin)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override(&"separation", 3)
	margin.add_child(vb)

	var title := _label("FLIGHT MODEL  ·  LIVE TUNING", 20, C_CYAN)
	vb.add_child(title)
	var sub := _label("Pat Kerr barbell ship · side thrusters at the bow · Tab/F1 closes", 13, C_DIM)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size = Vector2(360, 0)
	vb.add_child(sub)
	var reset := _button("Reset to Pat Kerr defaults")
	reset.pressed.connect(_apply_preset.bind("Pat Kerr classic"))
	vb.add_child(reset)
	# Presets.
	var presets := HBoxContainer.new()
	presets.add_theme_constant_override(&"separation", 6)
	for pname in PRESETS.keys():
		var b := _button(pname)
		b.pressed.connect(_apply_preset.bind(pname))
		presets.add_child(b)
	vb.add_child(presets)

	for def in SLIDERS:
		if def.size() == 1:
			vb.add_child(_section(def[0]))
			continue
		vb.add_child(_slider_row(def))

	_assist = CheckButton.new()
	_assist.text = "Flight assist (F)"
	_assist.focus_mode = Control.FOCUS_NONE
	_assist.add_theme_color_override(&"font_color", C_TEXT)
	_assist.add_theme_font_size_override(&"font_size", 15)
	_assist.toggled.connect(func(on: bool) -> void:
		if _syncing:
			return
		var ship := _ship()
		if ship:
			ship.flight_assist = on)
	vb.add_child(_assist)

	vb.add_child(_section("DERIVED"))
	_derived = _label("", 13, C_TEXT)
	_derived.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_derived)


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _section(text: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 2)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 4)
	box.add_child(spacer)
	box.add_child(_label(text, 13, C_TEAL))
	var line := ColorRect.new()
	line.color = Color(C_TEAL, 0.5)
	line.custom_minimum_size = Vector2(0, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(line)
	return box


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override(&"font_size", 13)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.06, 0.14, 0.2, 0.9)
	normal.border_color = Color(C_CYAN, 0.45)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(5)
	normal.set_content_margin_all(6)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.1, 0.25, 0.33, 0.95)
	hover.border_color = C_CYAN
	var pressed := hover.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(C_TEAL, 0.8)
	b.add_theme_stylebox_override(&"normal", normal)
	b.add_theme_stylebox_override(&"hover", hover)
	b.add_theme_stylebox_override(&"pressed", pressed)
	b.add_theme_color_override(&"font_color", C_TEXT)
	b.add_theme_color_override(&"font_hover_color", Color.WHITE)
	return b


func _slider_row(def: Array) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 0)
	var head := HBoxContainer.new()
	var name_l := _label(def[0], 14, C_TEXT)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var val_l := _label("", 14, C_CYAN)
	val_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(name_l)
	head.add_child(val_l)
	box.add_child(head)
	var s := HSlider.new()
	s.min_value = def[3]
	s.max_value = def[4]
	s.step = def[5]
	s.focus_mode = Control.FOCUS_NONE
	# The wheel must never nudge a flight-model number by accident (players
	# zoom with it while the panel is open); it scrolls the panel instead.
	s.scrollable = false
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size = Vector2(0, 18)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.15, 0.22, 0.3, 0.9)
	track.set_corner_radius_all(3)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(C_CYAN, 0.75)
	fill.set_corner_radius_all(3)
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	s.add_theme_stylebox_override(&"slider", track)
	s.add_theme_stylebox_override(&"grabber_area", fill)
	s.add_theme_stylebox_override(&"grabber_area_highlight", fill)
	var prop: String = def[2]
	s.value_changed.connect(_on_slider.bind(prop))
	box.add_child(s)
	_rows[prop] = {"slider": s, "label": val_l, "target": def[1], "unit": def[6], "step": def[5]}
	return box


# ------------------------------------------------------------- logic --
func _fmt(v: float, step: float, unit: String) -> String:
	var txt: String
	if step >= 1.0:
		txt = "%d" % int(round(v))
	elif step >= 0.1:
		txt = "%.1f" % v
	elif step >= 0.01:
		txt = "%.2f" % v
	else:
		txt = "%.3f" % v
	return txt + (" " + unit if unit != "" else "")


func _on_slider(value: float, prop: String) -> void:
	var row: Dictionary = _rows[prop]
	(row.label as Label).text = _fmt(value, row.step, row.unit)
	if _syncing:
		return
	var t := _target(row.target)
	if t:
		t.set(prop, value)
	_update_derived()


func _sync_from_targets() -> void:
	_syncing = true
	for prop in _rows:
		var row: Dictionary = _rows[prop]
		var t := _target(row.target)
		if t == null:
			continue
		var v = t.get(prop)
		if v == null:
			continue
		var s: HSlider = row.slider
		s.value = float(v)
		(row.label as Label).text = _fmt(float(v), row.step, row.unit)
	var ship := _ship()
	if ship:
		_assist.button_pressed = ship.flight_assist
	_syncing = false
	_update_derived()


func _apply_preset(pname: String) -> void:
	var p: Dictionary = PRESETS[pname]
	var ship := _ship()
	if ship:
		for k in p:
			ship.set(k, p[k])
	if pname == "Pat Kerr classic":
		var cam := _target("cam")
		if cam:
			cam.set("speed_zoom_amount", 1.0)
			cam.set("shake_amount", 1.0)
	_sync_from_targets()
	Game.toast("Flight model: %s" % pname, 1.8)


func _update_derived() -> void:
	var s := _ship()
	if s == null:
		_derived.text = "(no ship)"
		return
	var m := s.mass_kg
	var inertia_si := m * s.inertia_per_mass_m2
	var term := s.main_thrust_n / maxf(m * s.linear_drag, 0.0001)
	var omega := s.side_thrust_n * s.thrust_point_m / maxf(inertia_si * s.angular_drag, 0.0001)
	var lat := s.side_thrust_n / m
	_derived.text = ("Terminal speed  %.1f m/s   (boost %.1f)\nMax spin rate  %.2f rad/s  (%.0f°/s)\nForward accel  %.1f m/s²   sideways kick %.1f m/s²\nSpin-up time const  %.1f s" % [
		term, term * s.boost_multiplier, omega, rad_to_deg(omega),
		s.main_thrust_n / m, lat, 1.0 / maxf(s.angular_drag, 0.0001)])
