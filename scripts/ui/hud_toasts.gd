extends Control
## Top-centre message stack fed by Game.message (Game.toast()). Messages
## slide in, hold, and fade; identical consecutive messages refresh instead
## of stacking.

const MAX_TOASTS := 4
const TOP := 34.0

var _items: Array[Dictionary] = []   # {text, life, total, age}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Game.message.connect(_on_message)

func _on_message(text: String, duration: float) -> void:
	for it in _items:
		if it.text == text:
			it.life = duration
			it.total = duration
			return
	_items.append({"text": text, "life": duration, "total": duration, "age": 0.0})
	while _items.size() > MAX_TOASTS:
		_items.pop_front()

func _process(delta: float) -> void:
	if _items.is_empty():
		return
	for it in _items:
		it.life -= delta
		it.age += delta
	_items = _items.filter(func(it: Dictionary) -> bool: return it.life > 0.0)
	queue_redraw()

func _draw() -> void:
	var y := TOP
	var f := HudStyle.font()
	for it in _items:
		var a := clampf(minf(it.age * 6.0, it.life * 2.5), 0.0, 1.0)
		var slide := (1.0 - clampf(it.age * 6.0, 0.0, 1.0)) * -12.0
		var w := f.get_string_size(it.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 56.0
		var r := Rect2(Vector2((size.x - w) * 0.5, y + slide), Vector2(w, 40))
		HudStyle.draw_panel(self, r, 10.0, Color(HudStyle.CYAN, 0.6 * a), Color(0.02, 0.05, 0.1, 0.62 * a))
		draw_circle(r.position + Vector2(18, 20), 3.0, Color(HudStyle.CYAN, a))
		HudStyle.text(self, r.position + Vector2(32, 27), it.text, 20, Color(HudStyle.WHITE, a))
		y += 48.0
