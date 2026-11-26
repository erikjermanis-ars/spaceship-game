@tool
class_name VendingMachine
extends Interactable
## Drinks machine (front = local +X). Each use dispenses one can (motor,
## clunk) until it runs out; the stock is remembered across visits.

const DRINKS := ["Nova Fizz", "Orbit Cola", "Comet Citrus", "Ion Tonic", "Hydro+ Water"]

@export var stock := 5

var _panel: Node2D
var _t := 0.0
var _dispensing := 0.0


## Batched painter used by the draw callbacks (see OnFootPainter).
var pen: OnFootPainter

func _ready() -> void:
	z_as_relative = false
	z_index = 2
	reach_m = 1.7
	prompt_offset_m = Vector2(0, -1.6)
	if Engine.is_editor_hint():
		return
	add_to_group(&"persist")
	var body := StaticBody2D.new()
	body.collision_layer = Game.LAYER_WALK
	var cs := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = Vector2(8.6, 15.6)
	cs.shape = rs
	body.add_child(cs)
	add_child(body)
	var occ := LightOccluder2D.new()
	var op := OccluderPolygon2D.new()
	op.polygon = PackedVector2Array([Vector2(-4.3, -7.8), Vector2(4.3, -7.8), Vector2(4.3, 7.8), Vector2(-4.3, 7.8)])
	occ.occluder = op
	add_child(occ)
	_panel = Node2D.new()
	_panel.material = OnFootArt.unshaded()
	_panel.draw.connect(_draw_panel)
	add_child(_panel)
	_update_prompt()


func _update_prompt() -> void:
	prompt = "Buy a drink" if stock > 0 else "Sold out"


func _use(_by: Node2D) -> void:
	if stock <= 0:
		GameplayUtil.play_oneshot(self, GameplayUtil.load_audio("console_beep.wav"), -10.0, 0.7)
		Game.toast("SOLD OUT  ·  restock scheduled at the next supply run", 2.5)
		return
	stock -= 1
	var drink: String = DRINKS[(DRINKS.size() - 1 - stock) % DRINKS.size()]
	_dispensing = 1.2
	GameplayUtil.play_oneshot(self, GameplayUtil.load_audio("vending_dispense.wav"), -6.0)
	Game.toast("%s  ·  ice cold  (%d left)" % [drink.to_upper(), stock], 2.5)
	_update_prompt()


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _panel == null:
		return
	_t += delta
	_dispensing = maxf(0.0, _dispensing - delta)
	if int(_t * 8.0) != int((_t - delta) * 8.0):
		_panel.queue_redraw()


func save_state() -> Dictionary:
	return {"stock": stock}


func load_state(d: Dictionary) -> void:
	stock = int(d.get("stock", stock))
	_update_prompt()


func _draw() -> void:
	pen = OnFootPainter.new(self)
	_paint_draw()
	pen.flush()


func _paint_draw() -> void:
	var r := Rect2(Vector2(-4.5, -8.0), Vector2(9.0, 16.0))
	pen.rect_flat(Rect2(r.position + Vector2(0.9, 1.4), r.size), Color(0, 0.01, 0.03, 0.3))
	pen.rrect(r, 0.6, Color("E76F51"), OnFootArt.INK, 0.15)
	pen.rect(Rect2(Vector2(-4.0, -7.4), Vector2(5.2, 14.8)), Color("C4573C"))
	pen.rect(Rect2(Vector2(2.8, -7.0), Vector2(1.3, 14.0)), Color("2B3440"), OnFootArt.INK, 0.08)   # glass front edge


func _draw_panel() -> void:
	pen = OnFootPainter.new(_panel)
	_paint_draw_panel()
	pen.flush()


func _paint_draw_panel() -> void:
	# lit product window + price strip + a pulsing "dispensing" light
	var glass := Rect2(Vector2(2.9, -6.6), Vector2(1.1, 9.2))
	pen.rect_flat(glass, Color(0.75, 0.9, 1.0, 0.35))
	var cols := [Color("4EA8DE"), Color("E9EEF3"), Color("FFB000"), Color("8AB17D"), Color("E76F51")]
	for i in 5:
		var c: Color = cols[i]
		if i >= stock:
			c = Color(0.2, 0.22, 0.26)
		pen.circle(Vector2(3.45, -5.6 + i * 1.9), 0.55, c)
	pen.rect_flat(Rect2(Vector2(3.0, 3.4), Vector2(0.9, 2.2)), Color(0.3, 1.0, 0.6, 0.9) if stock > 0 else Color(1.0, 0.3, 0.25, 0.9))
	if _dispensing > 0.0 and fmod(_t, 0.25) < 0.14:
		pen.circle(Vector2(3.45, 6.4), 0.5, Color(1.0, 0.85, 0.4))
	pen.text(Vector2(-1.4, 1.0), "DRINKS", 2.0, Color(1, 1, 1, 0.9))
