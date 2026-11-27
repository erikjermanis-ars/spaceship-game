class_name ShuttleVisuals
extends Node2D
## Everything you see of the PETREL in flight. Pure presentation: reads the
## ShuttleShip's outputs every frame (local px, nose = +X).
##   * hull sprite that grows slightly with altitude, shadow that slides away
##     with it (the fake Z you land from)
##   * two stern plumes that follow the throttle (cruise flame up to 50 %,
##     then hotter, longer, with shock diamonds up to 100 %)
##   * RCS puffs from the quads that actually fire: turning is a couple, so
##     a bow quad and the opposite stern quad puff together
##   * nav lights, strobe, floodlight cone, skid legs
## The landing ghost / altitude ring live in LandingOverlay (deck level).

const HULL_TEX := "res://assets/art/ship/shuttle_hull.svg"
const SVG_SCALE := 6.0
## RCS quads: position (px) and gas exit direction (local).
## Matches the quads painted in shuttle_hull.svg: two lateral pairs (bow and
## stern flanks), plus fore/aft gas from the bow pair and the stern block.
const QUADS := [
	[Vector2(50.5, -19.6), Vector2(0, -1)], [Vector2(50.5, 19.6), Vector2(0, 1)],
	[Vector2(-46, -32), Vector2(0, -1)], [Vector2(-46, 32), Vector2(0, 1)],
	[Vector2(43, -22.4), Vector2(1, 0)], [Vector2(43, 22.4), Vector2(1, 0)],
	[Vector2(-57.5, -29.4), Vector2(-1, 0)], [Vector2(-57.5, 29.4), Vector2(-1, 0)],
]

var ship: ShuttleShip
var _hull: Node2D
var _shadow: Node2D
var _fx: Node2D
var _flood: Sprite2D
var _tex: Texture2D
var _t := 0.0
var _plume := Vector2.ZERO
var _puff := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0])
var _overlay: LandingOverlay
## Hold lamps: slots lit last frame, and a flash (1 -> 0) when that changes.
var _hold_used := 0
var _hold_flash := 0.0


func _ready() -> void:
	ship = get_parent() as ShuttleShip
	if ResourceLoader.exists(HULL_TEX):
		_tex = load(HULL_TEX)
	_shadow = _make_hull(Color(0, 0.01, 0.03, 0.32))
	_shadow.show_behind_parent = true
	_hull = _make_hull(Color.WHITE)
	_hull.show_behind_parent = true
	_fx = Node2D.new()
	_fx.name = "FX"
	_fx.material = OnFootArt.add_unshaded()
	_fx.draw.connect(_draw_fx)
	add_child(_fx)
	_flood = Sprite2D.new()
	_flood.texture = OnFootArt.cone_texture()
	_flood.material = OnFootArt.add_unshaded()
	_flood.modulate = Color(1.0, 0.95, 0.85, 0.0)
	_flood.position = Vector2(60, 0)
	_flood.scale = Vector2.ONE * (260.0 * 2.0 / 256.0)
	add_child(_flood)
	_overlay = LandingOverlay.new()
	_overlay.ship = ship
	ship.add_child.call_deferred(_overlay)


## The hull: SVG sprite if the art exists, else a drawn placeholder.
func _make_hull(mod: Color) -> Node2D:
	var n: Node2D
	if _tex:
		var s := Sprite2D.new()
		s.texture = _tex
		s.scale = Vector2.ONE / SVG_SCALE
		s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		n = s
	else:
		n = Node2D.new()
		n.draw.connect(func() -> void:
			var pen := OnFootPainter.new(n, 0.8)
			pen.poly(PackedVector2Array(ShuttleShip.HULL), Color("E9EEF3"), Color("4A5563"), 1.0)
			pen.rect_flat(Rect2(Vector2(-55, -31), Vector2(80, 6)), Color("2A9D8F"))
			pen.rect_flat(Rect2(Vector2(-55, 25), Vector2(80, 6)), Color("2A9D8F"))
			pen.ellipse(Vector2(40, 0), 14, 9, Color("1D3557"))
			pen.flush())
	n.modulate = mod
	add_child(n)
	return n


func _process(delta: float) -> void:
	if ship == null:
		return
	_t += delta
	var h := ship.altitude_m
	var k := 1.0 + 0.025 * h
	_hull.scale = (Vector2.ONE / SVG_SCALE if _tex else Vector2.ONE) * k
	_shadow.scale = _hull.scale * 0.98
	# Shadow slides along the station's light direction as we rise.
	_shadow.position = (Vector2(6.0, 9.0) + Vector2(0.6, 0.8) * 8.0 * h).rotated(-global_rotation)
	_shadow.modulate.a = lerpf(0.34, 0.18, clampf(h / 3.0, 0.0, 1.0))
	# Plumes spool (fast attack, slower decay), per engine.
	var target := ship.engine_out if ship.powered and ship.alive else Vector2.ZERO
	_plume.x = move_toward(_plume.x, target.x, delta * (9.0 if target.x > _plume.x else 4.0))
	_plume.y = move_toward(_plume.y, target.y, delta * (9.0 if target.y > _plume.y else 4.0))
	# RCS puffs. + lateral output = push to starboard = gas out of the PORT
	# quad; fore/aft quads fire for retro and hover station-keeping.
	var g := ship.rcs_levels()
	var wants := [g[0], g[1], g[2], g[3], g[4], g[4], g[5], g[5]]
	for i in QUADS.size():
		var want := clampf(float(wants[i]) * 1.5, 0.0, 1.0) if ship.powered and ship.alive else 0.0
		_puff[i] = move_toward(_puff[i], want, delta * 10.0)
	_flood.modulate.a = move_toward(_flood.modulate.a, 0.35 if ship.floodlights and ship.powered else 0.0, delta * 4.0)
	var used := ship.hold.used() if ship.hold else 0
	if used != _hold_used:
		_hold_used = used
		_hold_flash = 1.0
	_hold_flash = maxf(0.0, _hold_flash - delta * 2.0)
	_fx.queue_redraw()


func _draw_fx() -> void:
	var pen := OnFootPainter.new(_fx, 0.8)
	# --- stern plumes
	for i in 2:
		var amt := _plume.x if i == 0 else _plume.y
		if amt <= 0.01:
			continue
		var y := -14.0 if i == 0 else 14.0
		var lvl := clampf(amt * 2.0, 0.0, 1.0)            # cruise flame
		var hot := clampf(amt * 2.0 - 1.0, 0.0, 1.0)      # top half of the throttle
		var L := 14.0 + 46.0 * lvl + 40.0 * hot + sin(_t * 41.0 + i) * 2.0
		var w := 5.0 + 2.0 * lvl + 1.6 * hot
		var base := Vector2(-73, y)   # bell exit lip
		var core := Color(0.8, 0.97, 1.0, 0.9).lerp(Color(1, 1, 1, 0.95), hot)
		var glow := Color(0.35, 0.8, 1.0, 0.55).lerp(Color(0.6, 0.65, 1.0, 0.7), hot)
		var vis := smoothstep(0.0, 0.08, amt)
		glow.a *= vis
		core.a *= vis
		pen.fill(PackedVector2Array([base + Vector2(0, -w), base + Vector2(-L, 0), base + Vector2(0, w)]), glow, false)
		pen.fill(PackedVector2Array([base + Vector2(0, -w * 0.45), base + Vector2(-L * 0.55, 0), base + Vector2(0, w * 0.45)]), core, false)
		if hot > 0.01:
			for d in 3:   # shock diamonds fade in towards full throttle
				var c := base + Vector2(-12.0 - d * 12.0 * (0.8 + 0.2 * hot), 0)
				pen.fill(PackedVector2Array([c + Vector2(4, 0), c + Vector2(0, -2.6), c + Vector2(-4, 0), c + Vector2(0, 2.6)]), Color(1, 1, 1, (0.6 - d * 0.15) * hot), false)
	# --- RCS puffs
	for i in QUADS.size():
		if _puff[i] <= 0.02:
			continue
		var p: Vector2 = QUADS[i][0]
		var d: Vector2 = QUADS[i][1]
		var a := _puff[i]
		pen.fill(PackedVector2Array([p + d.orthogonal() * 2.0, p + d * (8.0 + 10.0 * a), p - d.orthogonal() * 2.0]), Color(0.9, 0.95, 1.0, 0.55 * a), false)
	# --- nav lights + strobe
	var nav := 0.8 + 0.2 * sin(_t * 2.0)
	pen.circle(Vector2(-37, -34), 2.4, Color(1.0, 0.25, 0.25, nav))
	pen.circle(Vector2(-37, 34), 2.4, Color(0.25, 1.0, 0.45, nav))
	var ph := fmod(_t, 1.6)
	if ph < 0.06:
		pen.circle(Vector2(-64, 0), 4.0, Color(1, 1, 1, 0.9))
	# --- hold lamps: one per slot in a row across the navy stern block (the
	# only dark stretch of hull, so additive light shows), lit amber when used
	if ship.hold and ship.powered and ship.alive:
		var cap := ship.hold.capacity
		for i in cap:
			var p := Vector2(-59.6, lerpf(-18.0, 18.0, i / maxf(cap - 1.0, 1.0)))
			if i < _hold_used:
				pen.circle(p, 2.5 + 2.5 * _hold_flash, Color(1.0, 0.62, 0.15, 0.2 + 0.45 * _hold_flash))
				pen.circle(p, 1.35, Color(1.0, 0.86, 0.55, 0.95))
			else:
				pen.circle(p, 1.1, Color(0.45, 0.85, 1.0, 0.3))
	# --- skid legs (extend below 2 m)
	if ship.skids > 0.01:
		for s in LandingProbe.SKIDS:
			var c := (s as Vector2) * Game.PX_PER_M
			var r := 2.2 * ship.skids
			pen.circle(c, r, Color(1.0, 0.7, 0.2, 0.55 * ship.skids))
	pen.flush()
