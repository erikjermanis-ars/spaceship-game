@tool
extends Interactable
## Yard Control's FREIGHT BOARD: a tilted table-top screen (it reads well in a
## top-down game, like the frigate's systems table) with the session's live
## freight numbers:
##   * the freight contracts (Contracts.DEFS / state): progress, tier, reward
##   * containers delivered per receiver and per shipping line (FreightLedger)
##   * how many containers are still out on the apron
##   * the credits earned
## Contracts stays alive while you are indoors and FreightLedger is static, so
## the board is always current. E reads the contracts out one at a time,
## which is also where a new player learns what to haul where.
##
## The node's origin is the board's centre; it is drawn unrotated (the text
## is laid out for a board whose long side runs along X).

## Contracts that are about hauling freight (the others are gunnery).
const FREIGHT_IDS: Array[StringName] = [&"yards", &"resupply", &"ore"]
const RECEIVERS := [["yards", "YARDS INTAKE"], ["vesper", "VESPER DROP"]]
const SCREEN := Color(0.05, 0.11, 0.17)
const TEXT := Color(0.78, 0.93, 1.0)
const DIM := Color(0.45, 0.62, 0.74)
const ORE := Color("2A9D8F")

@export var size_m := Vector2(6.8, 3.0)
## Cargo Yard C with the loose boxes that float just off its apron (world
## px): containers inside it count as "in the yard".
@export var yard_rect := Rect2(-3200, 4200, 6400, 3800)

var _screen: Node2D
var _t := 0.0
var _sig := ""
var _page := 0


func _ready() -> void:
	z_as_relative = false
	z_index = 1
	prompt = "Read the freight board"
	reach_m = 1.3
	prompt_offset_m = Vector2(0, -size_m.y * 0.5 - 0.7)
	if Engine.is_editor_hint():
		return
	var body := StaticBody2D.new()
	body.collision_layer = Game.LAYER_WALK
	body.collision_mask = 0
	var cs := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = size_m * OnFootArt.PX - Vector2(0.4, 0.4)
	cs.shape = rs
	body.add_child(cs)
	add_child(body)
	_screen = Node2D.new()
	_screen.material = OnFootArt.unshaded()
	_screen.draw.connect(_draw_screen)
	add_child(_screen)


## The board is long: reach is measured to its nearest edge, not its centre.
func reach_point() -> Vector2:
	var w := Game.walker
	if w == null or not is_instance_valid(w):
		return global_position
	var h := size_m * OnFootArt.PX * 0.5
	var l := to_local(w.global_position)
	return to_global(Vector2(clampf(l.x, -h.x, h.x), clampf(l.y, -h.y, h.y)))


func _contracts() -> Contracts:
	return get_tree().get_first_node_in_group(&"contracts") as Contracts


## One row per freight contract: {id, title, brief, count, target, reward, tier, flash}.
func _rows() -> Array:
	var c := _contracts()
	var out: Array = []
	for d: Dictionary in Contracts.DEFS:
		if not d.id in FREIGHT_IDS:
			continue
		var s: Dictionary = c.state.get(d.id, {}) if c else {}
		out.append({"id": d.id, "title": d.title, "brief": d.brief,
			"count": int(s.get("count", 0)), "target": int(s.get("target", d.target)),
			"reward": int(s.get("reward", d.reward)), "tier": int(s.get("tier", 1)),
			"flash": float(s.get("flash", 0.0))})
	return out


func _in_yard() -> int:
	var n := 0
	for b in get_tree().get_nodes_in_group(&"cargo_container"):
		if yard_rect.has_point((b as Node2D).global_position):
			n += 1
	return n


func _credits() -> int:
	var c := _contracts()
	return c.credits if c else 0


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _screen == null:
		return
	# Text is a draw call per string, so the screen is only repainted when a
	# number on it changed (checked twice a second) or a row is flashing.
	var before := int(_t * 2.0)
	_t += delta
	if int(_t * 2.0) == before:
		return
	var sig := "%d|%d|%d" % [_credits(), FreightLedger.total(), _in_yard()]
	var flashing := false
	for r: Dictionary in _rows():
		sig += "|%d/%d" % [r.count, r.target]
		flashing = flashing or r.flash > 0.0
	if sig != _sig or flashing:
		_sig = sig
		_screen.queue_redraw()


func _use(_by: Node2D) -> void:
	GameplayUtil.play_oneshot(self, GameplayUtil.load_audio("console_beep.wav"), -8.0, 1.0 + 0.05 * (_page % 3))
	var rows := _rows()
	if _page < rows.size():
		var r: Dictionary = rows[_page]
		Game.toast("%s  ·  %s  ·  %d of %d  ·  pays %d cr" % [r.title, r.brief, r.count, r.target, r.reward], 5.0)
	else:
		var n := FreightLedger.total()
		Game.toast("FREIGHT BOARD  ·  %s  ·  %d still in the yard  ·  %d cr earned" % [
			"nothing delivered yet this shift" if n == 0 else "%d delivered (%d hold slots)" % [n, FreightLedger.total_slots()],
			_in_yard(), _credits()], 5.0)
	_page = (_page + 1) % (rows.size() + 1)
	prompt = "Next line (%d/%d)" % [_page + 1, rows.size() + 1]


func _draw() -> void:
	var pen := OnFootPainter.new(self)
	var s := size_m * OnFootArt.PX
	var r := Rect2(-s * 0.5, s)
	pen.set_transform(OnFootArt.SHADOW_OFFSET)
	pen.rrect(r, 1.5, Color(0, 0.01, 0.03, 0.25))
	pen.set_transform()
	pen.rrect(r, 1.5, Color("C9D2DC"), OnFootArt.INK, 0.15)
	pen.rrect(r.grow(-0.9), 1.0, Color("0F1722"))
	# the back edge is raised against the wall: a navy hood with an amber stripe
	pen.rect(Rect2(r.position + Vector2(1.6, 0.25), Vector2(r.size.x - 3.2, 0.9)), OnFootArt.NAVY, OnFootArt.INK, 0.08)
	pen.rect_flat(Rect2(r.position + Vector2(2.2, 0.55), Vector2(r.size.x - 4.4, 0.25)), OnFootArt.AMBER)
	pen.flush()


func _draw_screen() -> void:
	var pen := OnFootPainter.new(_screen)
	var s := size_m * OnFootArt.PX
	var r := Rect2(-s * 0.5, s).grow(-1.5)
	r.position.y += 0.6
	r.size.y -= 0.6
	pen.rect_flat(r, SCREEN)
	var left := r.position.x + 1.4
	var right := r.end.x - 1.4
	var split := r.position.x + r.size.x * 0.66
	var top := r.position.y
	# header rule, column split, footer rule
	pen.line(Vector2(left, top + 4.1), Vector2(right, top + 4.1), Color(TEXT, 0.35), 0.12)
	pen.line(Vector2(split, top + 5.0), Vector2(split, r.end.y - 5.2), Color(TEXT, 0.2), 0.1)
	pen.line(Vector2(left, r.end.y - 4.4), Vector2(right, r.end.y - 4.4), Color(TEXT, 0.2), 0.1)
	var rows := _rows()
	var pitch := (r.size.y - 9.6) / maxf(rows.size(), 1.0)
	var bar_x := left + 19.5
	var bar_w := split - 7.5 - bar_x
	# bars first (one batch), then the text over them
	for i in rows.size():
		var row: Dictionary = rows[i]
		var y := top + 5.4 + pitch * i
		var hot := float(row.flash) > 0.0 and fmod(_t, 0.5) < 0.3
		if hot:
			pen.rect_flat(Rect2(Vector2(left - 0.6, y - 0.3), Vector2(split - left - 0.4, pitch - 0.5)), Color(1.0, 0.69, 0.0, 0.22))
		var bar := Rect2(Vector2(bar_x, y + 0.75), Vector2(bar_w, 1.5))
		pen.rect_flat(bar, Color(TEXT, 0.12))
		# one pip per container while they fit, a plain bar for the big tiers
		var target := maxi(int(row.target), 1)
		var col := OnFootArt.AMBER if row.id != &"ore" else ORE.lightened(0.25)
		if target <= 14:
			var w := bar.size.x / target
			for k in int(row.count):
				pen.rect_flat(Rect2(Vector2(bar.position.x + k * w + 0.15, bar.position.y + 0.15), Vector2(w - 0.3, bar.size.y - 0.3)), col)
		else:
			pen.rect_flat(Rect2(bar.position, Vector2(bar.size.x * clampf(float(row.count) / target, 0.0, 1.0), bar.size.y)).grow(-0.15), col)
	# shipping-line chips in the footer
	var chips := _brand_chips()
	var cx := left
	for chip in chips:
		pen.rect(Rect2(Vector2(cx, r.end.y - 3.3), Vector2(2.6, 1.5)), chip[1], Color(TEXT, 0.5), 0.08)
		cx += 3.2 + 1.25 * String(chip[0]).length() + 2.2
	pen.flush()
	# ---- text (each string is a draw call: kept to a couple of dozen)
	var L := HORIZONTAL_ALIGNMENT_LEFT
	var R := HORIZONTAL_ALIGNMENT_RIGHT
	_text(Vector2(left, top + 3.1), "FREIGHT BOARD  ·  CARGO YARD C", 2.3, TEXT, L)
	_text(Vector2(right - 30.0, top + 3.1), "%d cr" % _credits(), 2.3, OnFootArt.AMBER, R, 30.0)
	for i in rows.size():
		var row: Dictionary = rows[i]
		var y := top + 5.4 + pitch * i
		_text(Vector2(left, y + 2.25), String(row.title), 2.0, TEXT, L)
		_text(Vector2(split - 7.0, y + 2.25), "%d/%d" % [row.count, row.target], 2.0, TEXT, L)
		_text(Vector2(left, y + 4.3), "tier %d  ·  %d cr" % [row.tier, row.reward], 1.5, DIM, L, -1.0, false)
	var x2 := split + 1.4
	_text(Vector2(x2, top + 7.4), "DELIVERED", 1.6, DIM, L)
	for i in RECEIVERS.size():
		var y := top + 10.2 + i * 2.9
		_text(Vector2(x2, y), String(RECEIVERS[i][1]), 1.9, TEXT, L)
		_text(Vector2(right - 8.0, y), str(FreightLedger.count(String(RECEIVERS[i][0]))), 2.1, OnFootArt.AMBER, R, 8.0)
	var y3 := top + 10.2 + RECEIVERS.size() * 2.9 + 0.6
	_text(Vector2(x2, y3), "IN THE YARD", 1.9, TEXT, L)
	_text(Vector2(right - 8.0, y3), str(_in_yard()), 2.1, OnFootArt.CYAN, R, 8.0)
	if chips.is_empty():
		_text(Vector2(left, r.end.y - 1.9), "No deliveries logged this shift", 1.6, DIM, L, -1.0, false)
	cx = left
	for chip in chips:
		_text(Vector2(cx + 3.2, r.end.y - 1.9), "%s %d" % [chip[0], chip[2]], 1.6, TEXT, L)
		cx += 3.2 + 1.25 * String(chip[0]).length() + 2.2


## [brand, colour, count] for the lines delivered so far, busiest first, as
## many as fit along the footer.
func _brand_chips() -> Array:
	var out: Array = []
	for brand: String in FreightLedger.brands:
		var col := ORE if brand.nocasecmp_to("ORE") == 0 else Color("8E9AA8")
		for lv: Dictionary in LevelArt.LIVERIES:
			if String(lv.name) == brand:
				col = lv.color
		out.append([brand, col, int(FreightLedger.brands[brand])])
	out.sort_custom(func(a: Array, b: Array) -> bool: return a[2] > b[2])
	var room := size_m.x * OnFootArt.PX - 6.0
	var used := 0.0
	var fit: Array = []
	for chip in out:
		used += 3.2 + 1.25 * String(chip[0]).length() + 2.2
		if used > room:
			break
		fit.append(chip)
	return fit


func _text(pos: Vector2, s: String, size: float, col: Color, align: HorizontalAlignment, width := -1.0, bold := true) -> void:
	OnFootArt.text(_screen, pos, s, size, col, align, width, bold)
