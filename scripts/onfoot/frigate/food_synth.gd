@tool
class_name FoodSynth
extends Interactable
## The mess hall's food synthesizer: a wall niche with a glowing pad. Ask it
## for something and it shimmers a dish into being (sparkle + sound), which
## sits on the pad for a while. The menu is the crew's, not the galaxy's.

const MENU := [
	"Coffee, black. Very black.",
	"Miso noodles, extra ginger",
	"Peach cobbler (it remembers your last order)",
	"Ration bar, synthesized. Regrettable.",
	"Hot chocolate, too much cream",
	"Lemon-grass tea, steeped exactly four minutes",
	"Station-style dumplings, six",
]

var _glow: Node2D
var _t := 0.0
var _dish_t := -1.0
var _i := 0


func _ready() -> void:
	z_as_relative = false
	z_index = 11
	prompt = "Synthesizer"
	reach_m = 1.6
	prompt_offset_m = Vector2(0.6, -1.0)
	if Engine.is_editor_hint():
		return
	add_to_group(&"persist")
	_glow = Node2D.new()
	_glow.material = OnFootArt.unshaded()
	_glow.draw.connect(_draw_glow)
	add_child(_glow)


func _use(_by: Node2D) -> void:
	GameplayUtil.play_oneshot(self, GameplayUtil.load_audio("synth_materialize.wav"), -6.0)
	Game.toast("SYNTHESIZER  ·  %s" % MENU[_i % MENU.size()], 3.5)
	_i += 1
	_dish_t = 0.0


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _glow == null:
		return
	_t += delta
	if _dish_t >= 0.0:
		_dish_t += delta
		if _dish_t > 12.0:
			_dish_t = -1.0
	_glow.queue_redraw()


func _draw() -> void:
	# wall niche (local +X faces into the room)
	var pen := OnFootPainter.new(self)
	pen.rect(Rect2(Vector2(-6, -9), Vector2(8, 18)), Color("C9D2DC"), OnFootArt.INK, 0.15)
	pen.rect(Rect2(Vector2(-4.5, -7), Vector2(6, 14)), Color("1B2533"))
	pen.flush()


func _draw_glow() -> void:
	var pen := OnFootPainter.new(_glow)
	var a := 0.4 + 0.1 * sin(_t * 2.0)
	pen.rect_flat(Rect2(Vector2(-4.0, -6.5), Vector2(5, 13)), Color(0.5, 0.9, 1.0, a * 0.35))
	pen.line(Vector2(0.6, -6.5), Vector2(0.6, 6.5), Color(0.5, 0.9, 1.0, a), 0.3)
	if _dish_t >= 0.0:
		var k := clampf(_dish_t / 1.1, 0.0, 1.0)
		# sparkles while it forms, then the dish
		if k < 1.0:
			for i in 8:
				var p := Vector2(-1.5 + LevelArt.hash01(i + int(_t * 20.0), 3) * 3.0, -5.0 + LevelArt.hash01(i, int(_t * 20.0)) * 10.0)
				pen.circle(p, 0.35, Color(0.8, 0.95, 1.0, 0.9 * (1.0 - k)))
		pen.circle(Vector2(-1.5, 0), 2.6 * k, Color(0.95, 0.97, 1.0, 0.9 * k))
		pen.circle(Vector2(-1.5, 0), 1.6 * k, Color(0.75, 0.45, 0.25, 0.9 * k))
	pen.flush()


func save_state() -> Dictionary:
	return {"i": _i}


func load_state(d: Dictionary) -> void:
	_i = int(d.get("i", 0))
