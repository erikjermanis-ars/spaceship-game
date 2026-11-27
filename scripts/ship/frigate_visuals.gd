class_name FrigateVisuals
extends Node2D
## Everything you see of a frigate in flight. Pure presentation: it reads
## the FrigateShip's outputs and FrigateDamage's state every frame (local px,
## bow = +X).
##
## Layers, bottom to top: drop shadow (on the below-deck band only), painted
## hull, livery stripes (white art tinted per ship), breach scorch marks,
## window lights (additive; they turn red at red alert), the ship's name,
## then the live FX: impulse glow and plumes from the stern arms, light that
## runs round the two drive rings (faster with the throttle, blazing white
## when the quantum drive spools), the nose deflector, the flight deck's
## atmosphere field across the bay mouth, RCS puffs, nav lights and strobes,
## hot breach edges, venting gas and sparks, and the shield bubble
## (frigate_shield.gdshader).

const HULL_TEX := "res://assets/art/ship/frigate_hull.svg"
const LIVERY_TEX := "res://assets/art/ship/frigate_livery.svg"
const LIGHTS_TEX := "res://assets/art/ship/frigate_lights.svg"
const SHIELD_SHADER := "res://assets/art/fx/frigate_shield.gdshader"
const PX := 10.0
const SHIELD_PAD := Vector2(12.0, 14.0)    ## bubble clearance around the hull (m)

## RCS quads: [position (m), gas direction (local)]. Lateral quads in
## port/starboard pairs (bow group, stern group), then the fore quads (fire
## forward) and the aft quads (fire aft). Built from FrigateShape.
var _quads_bow: Array = []
var _quads_stern: Array = []
var _quads_fore: Array[Vector2] = []
var _quads_aft: Array[Vector2] = []
var _ring_mid := PackedVector2Array()   ## starboard emitter loop (px)
var _ring_glow := 0.0

var ship: FrigateShip
var _shadow: Sprite2D
var _hull: Sprite2D
var _livery: Sprite2D
var _lights: Sprite2D
var _decals: Node2D
var _name: Node2D
var _fx: Node2D
var _glows: Node2D
var _shield: Sprite2D
var _shield_mat: ShaderMaterial
var _particles: ShipParticles
var _glow_tex: Texture2D
var _t := 0.0
var _eng := Vector3.ZERO               ## spooled engine outputs
var _idle := 0.0                       ## powered-up glow (0 parked .. 1)
var _rcs := PackedFloat32Array([0, 0, 0, 0, 0, 0])
var _shield_glow := 0.0
var _shield_flicker := 0.0
var _decal_key := -1.0
var _alert := 0.0
var _vent_acc := 0.0


func _ready() -> void:
	ship = get_parent() as FrigateShip
	for p: Vector2 in FrigateShape.RCS_BOW:
		_quads_bow.append([Vector2(p.x, -p.y), Vector2(0, -1)])
		_quads_bow.append([p, Vector2(0, 1)])
	for p: Vector2 in FrigateShape.RCS_STERN:
		_quads_stern.append([Vector2(p.x, -p.y), Vector2(0, -1)])
		_quads_stern.append([p, Vector2(0, 1)])
	for sgn: float in [-1.0, 1.0]:
		_quads_fore.append(Vector2(FrigateShape.RCS_FORE.x, FrigateShape.RCS_FORE.y * sgn))
		_quads_aft.append(Vector2(FrigateShape.RCS_AFT.x, FrigateShape.RCS_AFT.y * sgn))
	for v: Vector2 in FrigateShape.RING_MID:
		_ring_mid.append(v * PX)
	_glow_tex = ShipFxTextures.glow()
	var add := OnFootArt.add_unshaded()
	_shadow = _sprite(HULL_TEX, 0.5, Color(0, 0.01, 0.03, 0.34))
	_shadow.z_as_relative = false
	_shadow.z_index = Game.Z_BELOW_DECK + 4
	_hull = _sprite(HULL_TEX, 0.5, Color.WHITE)
	_livery = _sprite(LIVERY_TEX, 1.0, ship.livery if ship else Color.WHITE)
	_decals = Node2D.new()
	_decals.name = "Breaches"
	_decals.draw.connect(_draw_decals)
	add_child(_decals)
	_lights = _sprite(LIGHTS_TEX, 1.0, Color.WHITE)
	_lights.material = add
	_name = Node2D.new()
	_name.name = "Name"
	_name.draw.connect(_draw_name)
	add_child(_name)
	_glows = Node2D.new()
	_glows.name = "Glows"
	_glows.material = add
	_glows.draw.connect(_draw_glows)
	add_child(_glows)
	_fx = Node2D.new()
	_fx.name = "FX"
	_fx.material = add
	_fx.draw.connect(_draw_fx)
	add_child(_fx)
	_build_shield()
	_particles = ShipParticles.new()
	_particles.name = "Particles"
	_particles.z_as_relative = false
	_particles.z_index = Game.Z_FX
	add_child(_particles)
	if ship:
		ship.damage_event.connect(_on_damage)


func _sprite(path: String, scl: float, mod: Color) -> Sprite2D:
	var s := Sprite2D.new()
	if ResourceLoader.exists(path):
		s.texture = load(path)
	s.scale = Vector2.ONE * scl
	s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	s.modulate = mod
	add_child(s)
	return s


func _build_shield() -> void:
	_shield = Sprite2D.new()
	_shield.name = "Shield"
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	_shield.texture = ImageTexture.create_from_image(img)
	var half := (Vector2(FrigateShape.HALF_LENGTH, FrigateShape.HALF_BEAM) + SHIELD_PAD) * PX
	_shield.scale = half * 2.0 / 4.0
	_shield.position = Vector2(FrigateShape.CENTRE_X, 0.0) * PX
	_shield_mat = ShaderMaterial.new()
	_shield_mat.shader = load(SHIELD_SHADER)
	_shield_mat.set_shader_parameter(&"half_size", half)
	_shield.material = _shield_mat
	_shield.z_as_relative = false
	_shield.z_index = Game.Z_FX + 1
	_shield.visible = false
	add_child(_shield)


# ================================================================ per frame

func _process(delta: float) -> void:
	if ship == null:
		return
	_t += delta
	var live := ship.alive and ship.powered
	var tgt := ship.engine_out if live else Vector3.ZERO
	_eng.x = move_toward(_eng.x, tgt.x, delta * (3.0 if tgt.x > _eng.x else 1.5))
	_eng.y = move_toward(_eng.y, tgt.y, delta * (3.0 if tgt.y > _eng.y else 1.5))
	_eng.z = move_toward(_eng.z, tgt.z, delta * (3.0 if tgt.z > _eng.z else 1.5))
	# Parked: the drive sleeps (dim rings); powered: idle glow comes up.
	_idle = move_toward(_idle, 1.0 if live else 0.25, delta * 0.6)
	_ring_glow = move_toward(_ring_glow, ship.jump_glow if live else 0.0, delta * 3.0)
	var lv := ship.rcs_levels() if live else PackedFloat32Array([0, 0, 0, 0, 0, 0])
	for i in 6:
		_rcs[i] = move_toward(_rcs[i], clampf(lv[i] * 1.4, 0.0, 1.0), delta * 8.0)
	# Shadow: the station's light falls from the upper left.
	_shadow.position = Vector2(26.0, 40.0).rotated(-global_rotation)
	# Red alert: the corridors behind the windows go red and pulse.
	_alert = move_toward(_alert, 1.0 if ship.red_alert and ship.alive else 0.0, delta * 2.0)
	var pulse := 0.5 + 0.5 * sin(_t * 4.2)
	_lights.modulate = Color.WHITE.lerp(Color(1.0, 0.28 + 0.12 * pulse, 0.22), _alert)
	_tick_shield(delta)
	_tick_particles(delta)
	var key := _breach_key()
	if key != _decal_key:
		_decal_key = key
		_decals.queue_redraw()
	_fx.queue_redraw()
	_glows.queue_redraw()


func _breach_key() -> float:
	var k := 0.0
	for b in ship.damage.breaches:
		k += float(b.size) * 13.0 + float(b.seed)
	return snappedf(k, 0.1) + ship.damage.breaches.size() * 1000.0


# ================================================================== shield

func _on_damage(kind: String, data: Dictionary) -> void:
	match kind:
		"hit":
			if float(data.shield) > 0.0:
				_shield_glow = minf(1.0, _shield_glow + 0.35 + float(data.shield) / 40.0)
			if float(data.hull) > 0.0:
				_sparks(data.pos * PX, 10 + int(float(data.hull) * 3.0))
		"shields_down":
			_shield_glow = 1.0
			_shield_flicker = 1.0
		"shields_up":
			_shield_glow = 0.8
			_shield_flicker = 0.5


func _tick_shield(delta: float) -> void:
	var d := ship.damage
	_shield_glow = maxf(0.0, _shield_glow - delta * 0.7)
	_shield_flicker = maxf(0.0, _shield_flicker - delta * 0.9)
	# A weak shield shimmers on its own.
	var weak := 1.0 - clampf(d.shield / 30.0, 0.0, 1.0) if d.shield_online else 0.0
	var show := _shield_glow > 0.01 or _shield_flicker > 0.01 or not d.shield_hits.is_empty() or (weak > 0.0 and ship.powered)
	_shield.visible = show and ship.alive
	if not _shield.visible:
		return
	var half: Vector2 = _shield_mat.get_shader_parameter(&"half_size")
	var hits: Array[Vector4] = []
	for h in d.shield_hits:
		# Project the hull hit point out onto the bubble surface.
		var p: Vector2 = (h.pos as Vector2) * PX - _shield.position
		var n := Vector2(p.x / half.x, p.y / half.y)
		if n.length() < 0.001:
			n = Vector2.RIGHT
		var on := n.normalized() * half
		hits.append(Vector4(on.x, on.y, float(h.t), float(h.power)))
	while hits.size() < 6:
		hits.append(Vector4.ZERO)
	_shield_mat.set_shader_parameter(&"hits", hits)
	_shield_mat.set_shader_parameter(&"hit_count", d.shield_hits.size())
	_shield_mat.set_shader_parameter(&"strength", clampf(d.shield / FrigateDamage.SHIELD_MAX, 0.0, 1.0))
	_shield_mat.set_shader_parameter(&"glow", _shield_glow)
	_shield_mat.set_shader_parameter(&"flicker", maxf(_shield_flicker, weak * 0.35))
	_shield_mat.set_shader_parameter(&"time_s", _t)


# =============================================================== particles

func _tick_particles(delta: float) -> void:
	if not ship.alive:
		return
	var xf := ship.get_global_transform()
	var vel := ship.linear_velocity
	_vent_acc += delta
	var step := 1.0 / 30.0
	while _vent_acc >= step:
		_vent_acc -= step
		for b in ship.damage.breaches:
			var p: Vector2 = (b.pos as Vector2) * PX
			if ship.damage.venting(b):
				# Atmosphere streams out of the breach: white, fast, short-lived.
				var out := Vector2(0.0, signf(p.y)) if absf(p.y) > 20.0 else Vector2(signf(p.x), 0.0)
				var dir := xf.basis_xform(out.rotated(randf_range(-0.5, 0.5))).normalized()
				var s := float(b.size)
				_particles.emit(xf * p, vel, dir * randf_range(60.0, 140.0) * (0.6 + s * 0.15), randf_range(0.5, 1.1),
					6.0 + s * 3.0, 26.0 + s * 9.0, Color(0.9, 0.95, 1.0, 0.55), Color(0.7, 0.8, 0.9, 0.0), 1.6)
			if float(b.heat) > 0.3 and randf() < 0.08 * float(b.heat):
				_sparks(p, 3)
	# RCS gas (inherits the ship's velocity: in vacuum the puff travels with it)
	var groups := [[0, 1], [2, 3]]
	for g in 2:
		var quads: Array = _quads_bow if g == 0 else _quads_stern
		for q in quads.size():
			var lvl := _rcs[groups[g][q % 2]]
			if lvl > 0.1 and randf() < lvl * 0.6:
				var at: Vector2 = (quads[q][0] as Vector2) * PX
				var d: Vector2 = quads[q][1]
				_particles.emit(xf * at, vel, xf.basis_xform(d) * randf_range(120.0, 200.0), 0.45, 8.0, 34.0,
					Color(0.92, 0.96, 1.0, 0.5 * lvl), Color(0.8, 0.85, 0.95, 0.0), 3.0)


func _sparks(local_px: Vector2, n: int) -> void:
	if ship == null:
		return
	var xf := ship.get_global_transform()
	for i in n:
		var dir := Vector2.from_angle(randf() * TAU)
		_particles.emit(xf * local_px, ship.linear_velocity, dir * randf_range(80.0, 320.0), randf_range(0.3, 0.8),
			2.2, 1.0, Color(1.0, 0.85, 0.5, 1.0), Color(1.0, 0.4, 0.1, 0.0), 2.0, ShipParticles.Kind.SPARK)


# ===================================================================== art

func _draw_name() -> void:
	if ship == null:
		return
	var f := LevelArt.font()
	var name_txt := String(ship.vehicle_name).to_upper()
	var col := Color(0.11, 0.21, 0.34, 0.82)
	# Name to starboard, registry to port, in the clear band between the
	# livery sweep and the window rows.
	_name.draw_set_transform(Vector2(260, 153), 0.0)
	_name.draw_string(f, Vector2.ZERO, " ".join(name_txt.split("")), HORIZONTAL_ALIGNMENT_CENTER, 300, 28, col)
	_name.draw_set_transform(Vector2(260, -131), 0.0)
	_name.draw_string(f, Vector2.ZERO, ship.registry, HORIZONTAL_ALIGNMENT_CENTER, 300, 28, col)
	# Registry again across the hangar block's roof, readable from astern.
	_name.draw_set_transform(Vector2(-318, 60), -PI * 0.5)
	_name.draw_string(f, Vector2.ZERO, ship.registry, HORIZONTAL_ALIGNMENT_CENTER, 120, 15, Color(col, 0.6))
	_name.draw_set_transform(Vector2.ZERO)


func _draw_decals() -> void:
	if ship == null:
		return
	var pen := OnFootPainter.new(_decals, 0.8)
	for b in ship.damage.breaches:
		var c: Vector2 = (b.pos as Vector2) * PX
		var s := float(b.size) * PX
		var rng := RandomNumberGenerator.new()
		rng.seed = int(b.seed)
		pen.fill(_blob(c, s * 1.5, rng, 14), Color(0.08, 0.06, 0.05, 0.42))
		pen.fill(_blob(c, s * 0.95, rng, 12), Color(0.1, 0.08, 0.07, 0.78))
		pen.fill(_blob(c, s * 0.5, rng, 9), Color(0.01, 0.01, 0.02, 0.95))
		# torn plating and exposed ribs
		for k in 4:
			var a := rng.randf() * TAU
			pen.line(c + Vector2.from_angle(a) * s * 0.3, c + Vector2.from_angle(a + rng.randf_range(-0.3, 0.3)) * s * 1.1, Color(0.55, 0.6, 0.66, 0.8), 1.4)
	pen.flush()


func _blob(c: Vector2, r: float, rng: RandomNumberGenerator, n: int) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		p.append(c + Vector2.from_angle(a) * r * rng.randf_range(0.6, 1.15))
	return p


## Soft glows (textured, batched): engine light, drive rings, deflector, lamps.
func _draw_glows() -> void:
	if ship == null:
		return
	if not ship.alive:
		return
	var thr := maxf(_eng.x, maxf(_eng.y, _eng.z))
	var jg := _ring_glow
	# impulse exhausts in the stern faces of the bay arms
	for s: float in [-1.0, 1.0]:
		for y: float in FrigateShape.IMPULSE_Y:
			var p := Vector2(FrigateShape.IMPULSE_X, y * s) * PX
			_glow(p + Vector2(-8, 0), Color(1.0, 0.35, 0.15, 0.35 * _idle + 0.55 * _eng.x), 36.0 + 56.0 * _eng.x)
	# drive rings: a halo that follows the emitter channel
	for k in 2:
		var s := -1.0 if k == 0 else 1.0
		var e := _eng.y if k == 0 else _eng.z
		var a := (0.1 + 0.03 * sin(_t * 1.7 + k)) * _idle + 0.22 * e + 0.22 * jg
		var col := Color(0.4, 0.62, 1.0, a).lerp(Color(0.7, 0.8, 1.0, a), jg)
		var rad := 62.0 + 26.0 * e + 40.0 * jg
		for i in range(0, _ring_mid.size(), 2):
			_glow(Vector2(_ring_mid[i].x, _ring_mid[i].y * s), col, rad)
	if jg > 0.02:
		# the drive charging: the whole stern lights up
		for s: float in [-1.0, 1.0]:
			_glow(Vector2(FrigateShape.RING_CENTRE.x, FrigateShape.RING_CENTRE.y * s) * PX, Color(0.5, 0.65, 1.0, 0.16 * jg), 380.0 + 40.0 * sin(_t * 9.0) * jg)
	# navigational deflector in the nose
	_glow(FrigateShape.DEFLECTOR * PX, Color(0.45, 0.8, 1.0, 0.3 * _idle + 0.2 * thr + 0.3 * jg), 110.0 + 60.0 * jg)
	# nav lights: red to port, green to starboard, white strobes on the tails
	var nav := 0.75 + 0.25 * sin(_t * 2.0)
	if _alert > 0.0:
		nav = lerpf(nav, 0.5 + 0.5 * sin(_t * 8.0), _alert)
	var wide := Vector2(22.0, FrigateShape.half_beam(22.0)) * PX
	var ring_tip := Vector2(FrigateShape.RING_CENTRE.x, FrigateShape.HALF_BEAM) * PX
	for at: Vector2 in [wide, ring_tip]:
		_glow(Vector2(at.x, -at.y), Color(1.0, 0.25, 0.25, 0.8 * nav), 46.0)
		_glow(at, Color(0.25, 1.0, 0.45, 0.8 * nav), 46.0)
	var tail := FrigateShape.RCS_AFT * PX
	if fmod(_t, 1.8) < 0.08:
		for s: float in [-1.0, 1.0]:
			_glow(Vector2(tail.x, tail.y * s), Color(1, 1, 1, 0.95), 70.0)
	if fmod(_t + 0.9, 1.8) < 0.07:
		_glow(Vector2(FrigateShape.BOW_X * PX - 20.0, 0), Color(1, 1, 1, 0.8), 60.0)
	# bridge beacon
	_glow(FrigateShape.BRIDGE * PX + Vector2(10, 0), Color(1.0, 0.3, 0.25, 0.5 + 0.5 * maxf(0.0, sin(_t * 3.0))), 30.0)
	# flight deck: the atmosphere field's glow across the bay mouth
	var bay := FrigateShape.BAY
	var fa := 0.14 + 0.04 * sin(_t * 2.3)
	for i in 5:
		var y := lerpf(bay.position.y + 2.0, bay.end.y - 2.0, i / 4.0)
		_glow(Vector2(bay.position.x, y) * PX, Color(0.45, 0.85, 1.0, fa), 60.0)
	# hot breach edges
	for b in ship.damage.breaches:
		var heat := float(b.heat)
		var vent := ship.damage.venting(b)
		if heat > 0.02 or vent:
			var fl := 0.7 + 0.3 * sin(_t * 23.0 + float(b.seed))
			_glow((b.pos as Vector2) * PX, Color(1.0, 0.45, 0.15, (0.15 + 0.6 * heat) * fl), float(b.size) * PX * 1.6)


func _glow(p: Vector2, col: Color, radius: float) -> void:
	if col.a <= 0.01:
		return
	_glows.draw_texture_rect(_glow_tex, Rect2(p - Vector2(radius, radius), Vector2(radius, radius) * 2.0), false, col)


## Shapes (one batched triangle array): plumes, ring flow, bay field, RCS.
func _draw_fx() -> void:
	if ship == null or not ship.alive:
		return
	var pen := OnFootPainter.new(_fx, 0.9)
	var jg := _ring_glow
	# --- impulse plumes
	for s: float in [-1.0, 1.0]:
		for y: float in FrigateShape.IMPULSE_Y:
			var base := Vector2(FrigateShape.IMPULSE_X, y * s) * PX
			var e := _eng.x
			if e > 0.02:
				var L := 30.0 + 120.0 * e + sin(_t * 37.0 + y) * 4.0
				var w := 6.0 + 3.0 * e
				pen.fill(PackedVector2Array([base + Vector2(0, -w), base + Vector2(-L, 0), base + Vector2(0, w)]), Color(1.0, 0.4, 0.18, 0.5 * e), false)
				pen.fill(PackedVector2Array([base + Vector2(0, -w * 0.45), base + Vector2(-L * 0.5, 0), base + Vector2(0, w * 0.45)]), Color(1.0, 0.85, 0.6, 0.7 * e), false)
			pen.rect_flat(Rect2(base + Vector2(-2, -5), Vector2(5, 10)), Color(1.0, 0.45, 0.2, 0.35 * _idle + 0.6 * e))
	# --- drive rings: light runs round each emitter channel, faster with the
	# throttle; spooling the quantum drive turns the whole hoop white-hot
	var n := _ring_mid.size()
	for k in 2:
		var s := -1.0 if k == 0 else 1.0
		var e := _eng.y if k == 0 else _eng.z
		var speed := 0.6 + 2.6 * e + 9.0 * jg
		for i in n:
			var a0 := Vector2(_ring_mid[i].x, _ring_mid[i].y * s)
			var a1 := Vector2(_ring_mid[(i + 1) % n].x, _ring_mid[(i + 1) % n].y * s)
			var flow := 0.5 + 0.5 * sin(float(i) * TAU * 3.0 / n - _t * speed * 2.2)
			var a := (0.3 + 0.2 * flow) * _idle + (0.3 + 0.3 * flow) * e
			a = lerpf(a, 0.85 + 0.15 * flow, jg)
			var col := Color(0.35, 0.62, 1.0, a).lerp(Color(0.8, 0.88, 1.0, a), jg)
			pen.line(a0, a1, col, 9.0 + 6.0 * jg)
			pen.line(a0, a1, Color(0.85, 0.94, 1.0, a * 0.8), 3.0 + 2.0 * jg)
	# --- deflector crescent in the nose
	var thr := maxf(_eng.y, _eng.z)
	var dc := Color(0.5, 0.85, 1.0, 0.5 * _idle + 0.25 * thr + 0.25 * jg)
	var dpos := FrigateShape.DEFLECTOR * PX - Vector2(18, 0)
	pen.arc(dpos, 36.0, -PI * 0.36, PI * 0.36, dc, 7.0, 16)
	pen.arc(dpos, 36.0, -PI * 0.36, PI * 0.36, Color(1.0, 0.85, 0.55, dc.a * 0.7), 2.4, 16)
	# --- flight deck atmosphere field: a shimmering curtain across the mouth
	var bay := FrigateShape.BAY
	var x := bay.position.x * PX + 3.0
	var y0 := bay.position.y * PX
	var segs := 24
	var h := bay.size.y * PX / segs
	for i in segs:
		var sh := 0.5 + 0.5 * sin(float(i) * 1.3 + _t * 3.1) * sin(float(i) * 0.37 - _t * 1.7)
		pen.line(Vector2(x, y0 + i * h + 1.0), Vector2(x, y0 + (i + 1) * h - 1.0), Color(0.5, 0.9, 1.0, 0.22 + 0.3 * sh), 3.0)
	# --- RCS puffs (short cones at the quads that fire)
	for q in _quads_bow.size():
		_puff(pen, (_quads_bow[q][0] as Vector2) * PX, _quads_bow[q][1], _rcs[q % 2])
	for q in _quads_stern.size():
		_puff(pen, (_quads_stern[q][0] as Vector2) * PX, _quads_stern[q][1], _rcs[2 + q % 2])
	for p: Vector2 in _quads_fore:
		_puff(pen, p * PX, Vector2(1, 0), _rcs[4])
	for p: Vector2 in _quads_aft:
		_puff(pen, p * PX, Vector2(-1, 0), _rcs[5])
	pen.flush()


func _puff(pen: OnFootPainter, p: Vector2, d: Vector2, a: float) -> void:
	if a <= 0.03:
		return
	var o := d.orthogonal()
	pen.fill(PackedVector2Array([p + o * 6.0, p + d * (30.0 + 40.0 * a), p - o * 6.0]), Color(0.9, 0.95, 1.0, 0.55 * a), false)
