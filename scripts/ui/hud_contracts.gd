extends Control
## Top-right contracts panel: the standing contracts (see Contracts), each
## with a progress bar and its payout, and the session's credits. A row
## flashes when it advances and glows green for a moment when it pays out.
## Contracts that belong to the other station are dimmed, so the list also
## tells you what there is to do where you are.

const WIDTH := 400.0
const ROW := 52.0
const MARGIN := Vector2(32, 32)
## Which station a contract is worked at.
const WHERE := {&"yards": &"meridian", &"gunnery": &"meridian", &"resupply": &"vesper", &"clearance": &"vesper", &"ore": &"meridian"}

var _contracts: Contracts
var _accum := 0.0
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(delta: float) -> void:
	_t += delta
	if _contracts == null or not is_instance_valid(_contracts):
		_contracts = get_tree().get_first_node_in_group(&"contracts") as Contracts
	_accum += delta
	if _accum >= 1.0 / 20.0:
		_accum = 0.0
		queue_redraw()


func _draw() -> void:
	if _contracts == null:
		return
	var n := Contracts.DEFS.size()
	var r := Rect2(Vector2(size.x - MARGIN.x - WIDTH, MARGIN.y), Vector2(WIDTH, 48.0 + n * ROW + 8.0))
	HudStyle.draw_panel(self, r)
	HudStyle.label(self, r.position + Vector2(20, 30), "Contracts")
	var cr := "%s cr" % _thousands(_contracts.credits)
	HudStyle.text(self, r.position + Vector2(0, 31), cr, 18, HudStyle.AMBER, HORIZONTAL_ALIGNMENT_RIGHT, WIDTH - 20, HudStyle.mono())
	var y := r.position.y + 48.0
	for d: Dictionary in Contracts.DEFS:
		var s: Dictionary = _contracts.state[d.id]
		var here := StringName(WHERE.get(d.id, &"")) == Game.sector
		var a := 1.0 if here else 0.5
		var flash := clampf(float(s.flash), 0.0, 1.0)
		var paid := float(s.flash) > 1.0
		var col := HudStyle.CYAN.lerp(HudStyle.GREEN if paid else HudStyle.WHITE, flash)
		var o := Vector2(r.position.x + 20, y)
		if flash > 0.0:
			draw_rect(Rect2(Vector2(r.position.x + 6, y + 2), Vector2(WIDTH - 12, ROW - 4)), Color(col, 0.1 * flash))
		HudStyle.text(self, o + Vector2(0, 16), String(d.title), 15, Color(HudStyle.WHITE, a))
		HudStyle.text(self, o + Vector2(0, 16), "%d / %d" % [int(s.count), int(s.target)], 15, Color(col, a), HORIZONTAL_ALIGNMENT_RIGHT, WIDTH - 40, HudStyle.mono())
		HudStyle.seg_bar(self, Rect2(o + Vector2(0, 23), Vector2(WIDTH - 40, 6)), float(s.count) / maxf(float(s.target), 1.0), Color(col, a), int(s.target))
		HudStyle.text(self, o + Vector2(0, 45), String(d.brief), 12, Color(HudStyle.MUTED, 0.9 * a))
		HudStyle.text(self, o + Vector2(0, 45), "+%d cr" % int(s.reward), 12, Color(HudStyle.AMBER, 0.85 * a), HORIZONTAL_ALIGNMENT_RIGHT, WIDTH - 40)
		y += ROW


func _thousands(v: int) -> String:
	var s := str(v)
	var out := ""
	while s.length() > 3:
		out = " " + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out
