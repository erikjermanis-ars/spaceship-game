class_name LandingOverlay
extends Node2D
## Deck-level landing guidance for the PETREL, drawn in world space:
##   * footprint ghost: the hull outline where you would touch down, with skid
##     dots (green on deck, red off) and a colour for the probe result
##     (green = clear, amber = edge, red = obstructed, grey = too fast/spinning)
##   * altitude ring that shrinks onto the ghost as you descend
##   * downwash rings near the deck, and the touchdown grade call-out
## So you can see why a landing would fail before you try.

var ship: ShuttleShip
var _t := 0.0
var _a := 0.0
var _callout := ""
var _callout_t := 0.0
var _wash := []          ## [radius, alpha]


func _ready() -> void:
	top_level = true
	z_as_relative = false
	z_index = Game.Z_BELOW_DECK + 12
	ship.touched_down.connect(func(grade: String) -> void:
		_callout = grade
		_callout_t = 2.2
		for i in 3:
			_wash.append([30.0 + i * 12.0, 0.5]))
	ship.lifted_off.connect(func() -> void:
		for i in 3:
			_wash.append([30.0 + i * 12.0, 0.4]))


func _process(delta: float) -> void:
	if ship == null or not is_instance_valid(ship):
		return
	_t += delta
	var mine := Game.player == ship and Game.mode == Game.Mode.FLIGHT and ship.alive
	var show := mine and not ship.probe.is_empty() and ship.land_state != ShuttleShip.Land.LANDED \
		and ship.land_state != ShuttleShip.Land.LIFTING
	_a = move_toward(_a, 1.0 if show else 0.0, delta * 5.0)
	_callout_t = maxf(0.0, _callout_t - delta)
	for w in _wash:
		w[0] += delta * 60.0
		w[1] -= delta * 0.6
	_wash = _wash.filter(func(w: Array) -> bool: return w[1] > 0.0)
	if ship.land_state == ShuttleShip.Land.DESCENT and fmod(_t, 0.25) < delta and ship.altitude_m < 1.5:
		_wash.append([26.0, 0.25])
	queue_redraw()


func _draw() -> void:
	if ship == null or not is_instance_valid(ship):
		return
	var xf: Transform2D = ship.render_transform()
	var pen := OnFootPainter.new(self, 0.9)
	for w in _wash:
		pen.ring(xf.origin, w[0], Color(0.85, 0.92, 1.0, w[1] * 0.5), 1.6, 40)
	if _a > 0.01:
		var reason := String(ship.probe.get("reason", ""))
		var col := Color(0.3, 1.0, 0.5)
		match reason:
			"EDGE", "RAMP":
				col = OnFootArt.AMBER
			"OBSTRUCTED":
				col = OnFootArt.NAV_RED
			"NO_DECK":
				col = Color(0.6, 0.65, 0.7)
			"TOO_FAST", "SPINNING":
				col = Color(0.75, 0.8, 0.85)
		var hull := xf * ship.hull_polygon()
		var pulse := 0.65 + 0.25 * sin(_t * 6.0)
		pen.fill(hull, Color(col, 0.08 * _a), false)
		pen.polyline(hull, Color(col, 0.8 * _a * pulse), 1.4, true)
		for i in LandingProbe.SKIDS.size():
			var on: bool = ship.skid_ok[i] if i < ship.skid_ok.size() else false
			var p := xf * ((LandingProbe.SKIDS[i] as Vector2) * Game.PX_PER_M)
			pen.circle(p, 2.6, Color(Color(0.3, 1.0, 0.5) if on else OnFootArt.NAV_RED, 0.85 * _a), OnFootArt.INK, 0.6, 12)
		# Altitude ring: converges on the ghost as height drops.
		var r := 80.0 + ship.altitude_m * 26.0
		pen.ring(xf.origin, r, Color(col, 0.35 * _a), 1.2, 48)
		var dname := String(ship.probe.get("deck_name", ""))
		if dname != "":
			pen.text(xf.origin + Vector2(0, -r - 10.0), dname.to_upper(), 11.0, Color(col, 0.75 * _a))
	if _callout_t > 0.0:
		var a := clampf(_callout_t, 0.0, 1.0)
		var c := Color(1.0, 0.95, 0.6) if _callout == "BULLSEYE" else (Color(0.6, 1.0, 0.8) if _callout == "SILK" else (OnFootArt.AMBER if _callout == "SKID" else Color(0.85, 0.92, 1.0)))
		pen.text(xf.origin + Vector2(0, -95.0 - (2.2 - _callout_t) * 12.0), _callout, 22.0, Color(c, a))
	pen.flush()
