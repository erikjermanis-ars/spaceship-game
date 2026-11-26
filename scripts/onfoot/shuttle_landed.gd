class_name ShuttleLanded
extends LandedShip
## The PETREL's close-up model (on foot / parked). Same machinery as the
## WREN's (hatch, board interactable, LOD cross-fade) with its own art: a port
## door that slides aft and a fold-down ramp, four lit mag-skids, cooling
## twin bells and its registration.

const TEX_PATH := "res://assets/art/onfoot/shuttle_landed.svg"

var _skid_glows: Array[Sprite2D] = []


func _configure() -> void:
	if ResourceLoader.exists(TEX_PATH):
		tex = load(TEX_PATH)
	else:
		tex = null
	svg_scale = 12.0
	hatch_x0 = -14.0
	hatch_x1 = 4.0
	hatch_y = -31.0
	ramp_len = 26.0
	ramp_w = 16.0
	door_point = Vector2(-5.0, -26.0)
	foot_point = Vector2(-5.0, -60.0)
	shadow_offset = Vector2(3.0, 4.5)


func _ready() -> void:
	super._ready()
	if tex == null:
		# No art yet: draw the hull ourselves (placeholder until the SVG exists).
		_hull.visible = false
		_shadow.visible = false
	_board.prompt = "Board PETREL"
	_snd_open = GameplayUtil.load_audio("ramp_servo.wav")
	_snd_close = _snd_open


func _build_glows() -> void:
	_glows.nav_port = OnFootArt.glow_sprite(self, Vector2(-37, -34), OnFootArt.NAV_RED, 8.0)
	_glows.nav_stbd = OnFootArt.glow_sprite(self, Vector2(-37, 34), OnFootArt.NAV_GREEN, 8.0)
	_glows.strobe = OnFootArt.glow_sprite(self, Vector2(-64, 0), Color.WHITE, 9.0)
	_glows.beacon = OnFootArt.glow_sprite(self, Vector2(-10, 0), Color(1.0, 0.7, 0.2, 0.5), 4.0)
	_glows.bell_p = OnFootArt.glow_sprite(self, Vector2(-68, -14), Color(1.0, 0.45, 0.15), 7.0)
	_glows.bell_s = OnFootArt.glow_sprite(self, Vector2(-68, 14), Color(1.0, 0.45, 0.15), 7.0)
	for s in LandingProbe.SKIDS:
		var g := OnFootArt.glow_sprite(self, (s as Vector2) * Game.PX_PER_M, Color("7FE6FF"), 4.0)
		_skid_glows.append(g)


func _animate(delta: float) -> void:
	super._animate(delta)
	# Skid lock lamps (cyan, as painted): steady while clamped.
	for g in _skid_glows:
		g.modulate.a = 0.7 + 0.15 * sin(_t * 3.0)


func _paint_details() -> void:
	if tex == null:
		pen.poly(PackedVector2Array(ShuttleShip.HULL), Color("E9EEF3"), Color("4A5563"), 0.4)
		pen.rect_flat(Rect2(Vector2(-55, -31), Vector2(80, 6)), Color("2A9D8F"))
		pen.rect_flat(Rect2(Vector2(-55, 25), Vector2(80, 6)), Color("2A9D8F"))
		pen.ellipse(Vector2(40, 0), 14, 9, Color("1D3557"))
	if _heat > 0.01:
		for s: float in [-1.0, 1.0]:
			pen.circle(Vector2(-67, s * 14), 3.2, Color(1.0, 0.45, 0.15, 0.4 * _heat))
	# Registration along the starboard flank, upright on screen.
	var flip := cos(global_rotation) < 0.0
	var k := -1.0 if flip else 1.0
	pen.text(Vector2(-30, 21.5 * k + (0.8 if not flip else -0.8)), "MSV PETREL · H2", 2.0, Color(0.11, 0.21, 0.34, 0.85), HORIZONTAL_ALIGNMENT_CENTER, -1.0, true, PI if flip else 0.0)
