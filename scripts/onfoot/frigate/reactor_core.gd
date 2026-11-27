@tool
class_name ReactorCore
extends Interactable
## Engineering's reactor core, seen from above: a containment housing, the
## glowing core, magnetic rings turning around it and a safety rail. Its
## light fills the room and breathes with the drive hum. It shows the ship's
## real state: a hurt Engineering section makes it stutter and shift toward
## amber, and a core breach turns it red and strobing.

@export var radius_m := 2.4

var _fx: Node2D
var _light: PointLight2D
var _hum: AudioStreamPlayer2D
var _t := 0.0
var _health := 1.0
var _breach := false


func _ready() -> void:
	z_as_relative = false
	z_index = 2
	prompt = "Reactor status"
	reach_m = radius_m + 1.6
	prompt_offset_m = Vector2(0, -radius_m - 0.9)
	if Engine.is_editor_hint():
		return
	var body := StaticBody2D.new()
	body.collision_layer = Game.LAYER_WALK
	var cs := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = (radius_m + 0.9) * OnFootArt.PX
	cs.shape = c
	body.add_child(cs)
	add_child(body)
	_fx = Node2D.new()
	_fx.material = OnFootArt.add_unshaded()
	_fx.z_index = 1
	_fx.draw.connect(_draw_fx)
	add_child(_fx)
	_light = PointLight2D.new()
	_light.texture = OnFootArt.radial_texture()
	_light.texture_scale = 12.0 * OnFootArt.PX * 2.0 / 128.0
	_light.color = Color(0.45, 0.75, 1.0)
	_light.energy = 0.9
	add_child(_light)
	var s := GameplayUtil.load_loop("frigate_drive_hum_loop.wav")
	if s:
		_hum = AudioStreamPlayer2D.new()
		_hum.stream = s
		_hum.bus = GameplayUtil.bus(&"Ambient")
		_hum.volume_db = -9.0
		_hum.max_distance = 420.0
		add_child(_hum)
		_hum.play()
	var f := FrigateShip.aboard
	if f:
		_health = f.damage.integrity[FrigateDamage.Sec.ENGINEERING] / 100.0
		_breach = f.damage.core_breach >= 0.0


func _use(_by: Node2D) -> void:
	GameplayUtil.play_oneshot(self, GameplayUtil.load_audio("console_beep.wav"), -8.0, 0.9)
	var txt := "REACTOR  ·  output %d %%  ·  containment nominal" % int(round(lerpf(60.0, 100.0, _health)))
	if _breach:
		txt = "REACTOR  ·  CONTAINMENT FAILING  ·  get the ship to its berth"
	elif _health < 0.5:
		txt = "REACTOR  ·  output %d %%  ·  Engineering damaged, shields running weak" % int(round(lerpf(60.0, 100.0, _health)))
	Game.toast(txt, 4.0)


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _fx == null:
		return
	_t += delta
	var pulse := 0.5 + 0.5 * sin(_t * TAU * 0.5)
	var stutter := 1.0
	if _health < 0.5 and fmod(_t * 7.3, 1.0) < (0.5 - _health) * 0.6:
		stutter = 0.4
	_light.energy = (0.75 + 0.25 * pulse) * stutter
	_light.color = _core_color()
	_fx.queue_redraw()


func _core_color() -> Color:
	if _breach:
		return Color(1.0, 0.25, 0.2) if fmod(_t, 0.5) < 0.3 else Color(1.0, 0.6, 0.2)
	return Color(0.45, 0.75, 1.0).lerp(Color(1.0, 0.7, 0.3), clampf(1.0 - _health * 1.4, 0.0, 1.0))


func _draw() -> void:
	var pen := OnFootPainter.new(self)
	var px := OnFootArt.PX
	var r := radius_m * px
	pen.circle(Vector2.ZERO, r + 0.9 * px, Color(0.13, 0.16, 0.21), OnFootArt.INK, 0.2)
	# safety rail with stanchions
	pen.ring(Vector2.ZERO, r + 0.75 * px, Color(1.0, 0.69, 0.0, 0.85), 0.3, 64)
	for i in 12:
		var p := Vector2.from_angle(TAU * i / 12.0) * (r + 0.75 * px)
		pen.circle(p, 0.5, Color("D9E0E7"), OnFootArt.INK, 0.1)
	# containment housing: segmented collar
	pen.circle(Vector2.ZERO, r, Color("5C6878"), OnFootArt.INK, 0.2)
	for i in 8:
		var a := TAU * i / 8.0
		pen.line(Vector2.from_angle(a) * r * 0.62, Vector2.from_angle(a) * r, Color("2B3440"), 0.5)
	pen.circle(Vector2.ZERO, r * 0.62, Color("1B2533"), OnFootArt.INK, 0.15)
	pen.flush()


func _draw_fx() -> void:
	var pen := OnFootPainter.new(_fx)
	var r := radius_m * OnFootArt.PX
	var col := _core_color()
	var pulse := 0.5 + 0.5 * sin(_t * TAU * 0.5)
	# the core: layered discs, brightest in the middle
	pen.circle(Vector2.ZERO, r * 0.58, Color(col, 0.35 + 0.15 * pulse))
	pen.circle(Vector2.ZERO, r * 0.42, Color(col, 0.55))
	pen.circle(Vector2.ZERO, r * 0.24, Color(col.lerp(Color.WHITE, 0.6), 0.85))
	# magnetic rings turning in opposite directions
	for k in 3:
		var rr := r * (0.68 + 0.1 * k)
		var spin := _t * (0.8 + 0.5 * k) * (1.0 if k % 2 == 0 else -1.0)
		for j in 3:
			var a0 := spin + TAU * j / 3.0
			pen.arc(Vector2.ZERO, rr, a0, a0 + 1.2, Color(col, 0.6 - 0.12 * k), 0.25, 14)
	# energy streaks pulsing outward
	for i in 6:
		var a := TAU * i / 6.0 + _t * 0.3
		var t := fmod(_t * 0.8 + i * 0.17, 1.0)
		pen.line(Vector2.from_angle(a) * r * 0.25, Vector2.from_angle(a) * r * (0.3 + 0.3 * t), Color(col, 0.5 * (1.0 - t)), 0.3)
	pen.flush()
