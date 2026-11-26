extends TextureRect
## Red screen-edge vignette: a sharp pulse on every hull hit (strength scales
## with damage) plus a slow heartbeat while the hull is critical.

var _pulse := 0.0
var _hull_frac := 1.0
var _prev_hull := -1.0
var _t := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.62, 0.86, 1.0])
	g.colors = PackedColorArray([Color(1, 0.1, 0.05, 0.0), Color(1, 0.1, 0.05, 0.0), Color(1, 0.12, 0.06, 0.22), Color(0.85, 0.0, 0.0, 0.75)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 256
	t.height = 256
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.08, 0.5)
	texture = t
	modulate.a = 0.0
	Game.hull_changed.connect(_on_hull)
	Game.ship_respawned.connect(func(_p: Vector2) -> void: _pulse = 0.0)

func _on_hull(h: float, mh: float) -> void:
	if _prev_hull >= 0.0 and h < _prev_hull:
		var dmg := _prev_hull - h
		_pulse = clampf(_pulse + 0.2 + dmg / 45.0, 0.0, 0.9)
	_prev_hull = h
	_hull_frac = h / maxf(mh, 1.0)

func _process(delta: float) -> void:
	_t += delta
	_pulse = maxf(0.0, _pulse - delta * 1.6)
	var critical := 0.0
	if _hull_frac < 0.3 and GameplayUtil.player_alive():
		var beat := pow(maxf(0.0, sin(_t * 5.5)), 6.0)
		critical = (0.18 + 0.25 * beat) * (1.0 - _hull_frac / 0.3)
	modulate.a = clampf(maxf(_pulse, critical), 0.0, 1.0)
	visible = modulate.a > 0.005
