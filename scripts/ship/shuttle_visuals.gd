class_name ShuttleVisuals
extends Node2D
## Everything you see of the PETREL in flight. Pure presentation: reads the
## ShuttleShip's outputs every frame (local px, nose = +X).
##   * hull sprite that grows slightly with altitude, shadow that slides away
##     with it (the fake Z you land from)
##   * two separate stern plumes (uneven during differential trim)
##   * RCS puffs from the quads opposite to the push
##   * gyro shimmer around the centre of mass (red when saturated)
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
	# RCS puffs: gas leaves the quads facing away from the push.
	var f_local := ship.rcs_force.rotated(-ship.global_rotation) / maxf(ship.hover_cap_n, 1.0)
	for i in QUADS.size():
		var out_dir: Vector2 = QUADS[i][1]
		var want := clampf(-out_dir.dot(f_local) * 3.0, 0.0, 1.0) if ship.powered else 0.0
		_puff[i] = move_toward(_puff[i], want, delta * 10.0)
	_flood.modulate.a = move_toward(_flood.modulate.a, 0.35 if ship.floodlights and ship.powered else 0.0, delta * 4.0)
	_fx.queue_redraw()


func _draw_fx() -> void:
	var pen := OnFootPainter.new(_fx, 0.8)
	# --- stern plumes
	for i in 2:
		var amt := _plume.x if i == 0 else _plume.y
		if amt <= 0.01:
			continue
		var y := -14.0 if i == 0 else 14.0
		var L := 14.0 + 46.0 * amt + sin(_t * 41.0 + i) * 2.0
		var w := 5.0 + 2.0 * minf(amt, 1.5)
		var base := Vector2(-73, y)   # bell exit lip
		var core := Color(0.8, 0.97, 1.0, 0.9)
		var glow := Color(0.35, 0.8, 1.0, 0.55) if amt <= 1.05 else Color(0.6, 0.65, 1.0, 0.7)
		pen.fill(PackedVector2Array([base + Vector2(0, -w), base + Vector2(-L, 0), base + Vector2(0, w)]), glow, false)
		pen.fill(PackedVector2Array([base + Vector2(0, -w * 0.45), base + Vector2(-L * 0.55, 0), base + Vector2(0, w * 0.45)]), core, false)
		if amt > 1.05:
			for d in 3:   # afterburner shock diamonds
				var c := base + Vector2(-12.0 - d * 12.0, 0)
				pen.fill(PackedVector2Array([c + Vector2(4, 0), c + Vector2(0, -2.6), c + Vector2(-4, 0), c + Vector2(0, 2.6)]), Color(1, 1, 1, 0.6 - d * 0.15), false)
	# --- RCS puffs
	for i in QUADS.size():
		if _puff[i] <= 0.02:
			continue
		var p: Vector2 = QUADS[i][0]
		var d: Vector2 = QUADS[i][1]
		var a := _puff[i]
		pen.fill(PackedVector2Array([p + d.orthogonal() * 2.0, p + d * (8.0 + 10.0 * a), p - d.orthogonal() * 2.0]), Color(0.9, 0.95, 1.0, 0.55 * a), false)
	# --- gyro shimmer
	if ship.powered and ship.gyro_frac > 0.05:
		var col := Color(1.0, 0.35, 0.3, 0.55) if ship.gyro_saturated else Color(0.5, 0.9, 1.0, 0.35)
		var a0 := _t * 9.0
		pen.arc(Vector2.ZERO, 22.0, a0, a0 + PI * 0.7 * ship.gyro_frac + 0.2, Color(col, col.a * ship.gyro_frac + 0.1), 1.6, 16)
		pen.arc(Vector2.ZERO, 22.0, a0 + PI, a0 + PI + PI * 0.7 * ship.gyro_frac + 0.2, Color(col, col.a * ship.gyro_frac + 0.1), 1.6, 16)
	# --- nav lights + strobe
	var nav := 0.8 + 0.2 * sin(_t * 2.0)
	pen.circle(Vector2(-37, -34), 2.4, Color(1.0, 0.25, 0.25, nav))
	pen.circle(Vector2(-37, 34), 2.4, Color(0.25, 1.0, 0.45, nav))
	var ph := fmod(_t, 1.6)
	if ph < 0.06:
		pen.circle(Vector2(-64, 0), 4.0, Color(1, 1, 1, 0.9))
	# --- skid legs (extend below 2 m)
	if ship.skids > 0.01:
		for s in LandingProbe.SKIDS:
			var c := (s as Vector2) * Game.PX_PER_M
			var r := 2.2 * ship.skids
			pen.circle(c, r, Color(1.0, 0.7, 0.2, 0.55 * ship.skids))
	pen.flush()
