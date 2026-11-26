extends Node2D
## Everything you SEE of the ship besides the hull art itself: engine plumes,
## RCS jets and gas puffs (fired from the nozzle that the physics actually
## uses), retro jets, engine trail ribbons, nav lights & strobe, engine light
## spill, impact flash, damage scorch/smoke/sparks and a drop shadow.
##
## Pure presentation: reads the PlayerShip's thruster outputs each frame.
## Local coordinates are ship pixels (1 m = 10 px), nose toward +X.

signal rcs_onset(strength: float)   # a nozzle just opened (audio listens)

const SHADOW_OFFSET := Vector2(12, 16)           # global, light from upper-left
const ENGINE_NOZZLES: Array[Vector2] = [Vector2(-50.5, -21), Vector2(-50.5, 21)]
const NACELLE_CENTRES: Array[Vector2] = [Vector2(-23, -21), Vector2(-23, 21)]
# RCS nozzles: position and gas exit direction (local).
const BOW_PORT := Vector2(40.6, -9.4)
const BOW_STBD := Vector2(40.6, 9.4)
const STERN_PORT := Vector2(-36, -11)
const STERN_STBD := Vector2(-36, 11)
const RETRO_PORT := Vector2(43.6, -6.9)
const RETRO_STBD := Vector2(43.6, 6.9)
const DAMAGE_POINTS: Array[Vector2] = [Vector2(16, 6), Vector2(-33, 2), Vector2(-8, -8), Vector2(-16, -15)]

const C_PLUME := Color(0.30, 0.78, 1.0)
const C_PLUME_BOOST := Color(0.55, 0.62, 1.0)
const C_CORE := Color(0.80, 0.96, 1.0)
const C_GAS := Color(0.86, 0.92, 0.98)
const C_NAV_PORT := Color("#FF3B3B")
const C_NAV_STBD := Color("#3BFF7A")
const C_ENGINE_LIGHT := Color(0.45, 0.78, 1.0)

@export var trail_lifetime := 1.6
@export var shadow_alpha := 0.32

var ship: PlayerShip
## 0..1 summed RCS activity (audio reads this).
var rcs_activity := 0.0

var _t := 0.0
var _eng := 0.0          # smoothed main engine output, 0..1 of full thrust
var _lvl := 0.0          # cruise flame, full by 50 % throttle
var _boost_vis := 0.0    # hot "boost" look (shock diamonds), 50 -> 100 % throttle
var _retro := 0.0
var _flash := 0.0
var _flash_color := Color.WHITE
var _hull_frac := 1.0
var _noise := FastNoiseLite.new()
var _rcs_raw := PackedFloat32Array([0, 0, 0, 0, 0, 0])     # bp, bs, sp, ss, rp, rs
var _rcs_vis := PackedFloat32Array([0, 0, 0, 0, 0, 0])
var _rcs_emit_acc := PackedFloat32Array([0, 0, 0, 0, 0, 0])
var _smoke_acc := 0.0
var _spark_timer := 0.0

var _plumes: Array[Dictionary] = []
var _rcs_jets: Array[Sprite2D] = []
var _trails: Array[Line2D] = []
var _trail_pts: Array = [[], []]       # per nacelle: Array of [pos, time]
var _trail_sample := 0.0
var _gas: ShipParticles
var _glow_fx: ShipParticles
var _nav_port: Sprite2D
var _nav_stbd: Sprite2D
var _strobe: Sprite2D
var _strobe_core: Sprite2D
var _coil_glows: Array[Sprite2D] = []
var _engine_glow: Sprite2D
var _engine_light: PointLight2D
var _cockpit_glow: Sprite2D

@onready var _hull: Sprite2D = $Hull
@onready var _damage: Sprite2D = $Damage
@onready var _flash_sprite: Sprite2D = $Flash
@onready var _shadow: Sprite2D = $Shadow


func _ready() -> void:
	ship = get_parent() as PlayerShip
	_noise.frequency = 0.9
	_noise.seed = 7
	_flash_sprite.material = ShipFxTextures.additive()
	_flash_sprite.modulate.a = 0.0
	_damage.modulate.a = 0.0
	_shadow.top_level = true
	_shadow.z_as_relative = false
	_shadow.z_index = Game.Z_BELOW_DECK + 4
	_shadow.modulate = Color(0, 0, 0, shadow_alpha)
	_build_engines()
	_build_rcs()
	_build_lights()
	_build_trails()
	_gas = ShipParticles.new()
	_gas.name = "GasParticles"
	_gas.z_as_relative = false
	_gas.z_index = Game.Z_SHIP + 1
	add_child(_gas)
	_glow_fx = ShipParticles.new()
	_glow_fx.name = "GlowParticles"
	_glow_fx.material = ShipFxTextures.additive()
	_glow_fx.texture = ShipFxTextures.glow()
	_glow_fx.z_as_relative = false
	_glow_fx.z_index = Game.Z_FX
	add_child(_glow_fx)
	if ship:
		ship.contact_impact.connect(_on_impact)
	Game.hull_changed.connect(_on_hull_changed)
	Game.ship_respawned.connect(func(_p: Vector2) -> void: _reset_fx())


# ------------------------------------------------------------ building --
func _glow_sprite(pos: Vector2, color: Color, size_px: float, z := 0) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = ShipFxTextures.glow()
	s.material = ShipFxTextures.additive()
	s.position = pos
	s.modulate = color
	s.scale = Vector2.ONE * (size_px / 128.0)
	s.z_index = z
	s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(s)
	return s


func _plume_sprite(parent: Node2D, color: Color) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = ShipFxTextures.plume()
	s.material = ShipFxTextures.additive()
	s.centered = false
	s.offset = Vector2(0, -16)
	s.modulate = color
	s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	parent.add_child(s)
	return s


func _build_engines() -> void:
	for i in ENGINE_NOZZLES.size():
		var root := Node2D.new()
		root.name = "Plume%d" % i
		root.position = ENGINE_NOZZLES[i]
		root.rotation = PI    # local +X now points out the back
		root.z_index = -1      # under the hull
		add_child(root)
		var outer := _plume_sprite(root, C_PLUME)
		var core := _plume_sprite(root, C_CORE)
		var diamonds: Array[Sprite2D] = []
		for k in 3:
			var d := Sprite2D.new()
			d.texture = ShipFxTextures.glow()
			d.material = ShipFxTextures.additive()
			d.modulate = Color(1, 1, 1, 0)
			root.add_child(d)
			diamonds.append(d)
		var nozzle := Sprite2D.new()
		nozzle.texture = ShipFxTextures.glow()
		nozzle.material = ShipFxTextures.additive()
		nozzle.modulate = Color(C_PLUME, 0)
		root.add_child(nozzle)
		_plumes.append({"root": root, "outer": outer, "core": core, "diamonds": diamonds, "nozzle": nozzle, "seed": i * 37.0})
	_engine_glow = _glow_sprite(Vector2(-62, 0), Color(C_ENGINE_LIGHT, 0), 180.0, -2)
	_engine_light = PointLight2D.new()
	_engine_light.texture = ShipFxTextures.glow()
	_engine_light.texture_scale = 4.0
	_engine_light.color = C_ENGINE_LIGHT
	_engine_light.energy = 0.0
	_engine_light.blend_mode = Light2D.BLEND_MODE_ADD
	_engine_light.position = Vector2(-70, 0)
	add_child(_engine_light)


func _build_rcs() -> void:
	# Order matches _rcs_raw: bow port, bow stbd, stern port, stern stbd, retro port, retro stbd.
	var defs := [
		[BOW_PORT, -PI * 0.5], [BOW_STBD, PI * 0.5],
		[STERN_PORT, -PI * 0.5], [STERN_STBD, PI * 0.5],
		[RETRO_PORT, -0.25], [RETRO_STBD, 0.25],
	]
	for d in defs:
		var root := Node2D.new()
		root.position = d[0]
		root.rotation = d[1]
		root.z_index = 1
		add_child(root)
		var jet := _plume_sprite(root, Color(C_GAS, 0))
		_rcs_jets.append(jet)


func _build_lights() -> void:
	_nav_port = _glow_sprite(Vector2(-9, -25.6), C_NAV_PORT, 22.0, 2)
	_nav_stbd = _glow_sprite(Vector2(-9, 25.6), C_NAV_STBD, 22.0, 2)
	_strobe = _glow_sprite(Vector2(-43.5, 0), Color(1, 1, 1, 0), 70.0, 2)
	_strobe_core = _glow_sprite(Vector2(-43.5, 0), Color(1, 1, 1, 0), 12.0, 2)
	_cockpit_glow = _glow_sprite(Vector2(25, 0), Color(1.0, 0.85, 0.55, 0.22), 26.0, 1)
	for c in NACELLE_CENTRES:
		var g := _glow_sprite(c, Color(0.5, 0.9, 1.0, 0.2), 1.0, 1)
		g.scale = Vector2(40.0 / 128.0, 7.0 / 128.0)
		_coil_glows.append(g)


func _build_trails() -> void:
	for i in 2:
		var line := Line2D.new()
		line.top_level = true
		line.z_as_relative = false
		line.z_index = Game.Z_SHIP - 1
		line.width = 5.0
		line.antialiased = true
		line.joint_mode = Line2D.LINE_JOINT_ROUND
		line.material = ShipFxTextures.additive()
		var grad := Gradient.new()
		grad.set_color(0, Color(0.3, 0.7, 1.0, 0.0))
		grad.set_color(1, Color(0.55, 0.85, 1.0, 0.55))
		line.gradient = grad
		var curve := Curve.new()
		curve.add_point(Vector2(0, 0.1))
		curve.add_point(Vector2(1, 1))
		line.width_curve = curve
		add_child(line)
		_trails.append(line)


# --------------------------------------------------------------- frame --
func _process(delta: float) -> void:
	if ship == null:
		return
	_t += delta
	_update_engines(delta)
	_update_rcs(delta)
	_update_lights()
	_update_trails(delta)
	_update_damage(delta)
	# Impact flash decay.
	_flash = maxf(_flash - delta * 4.0, 0.0)
	_flash_sprite.modulate = Color(_flash_color, _flash * 0.9)
	# Drop shadow offset in WORLD space (light from a fixed direction).
	var rx := ship.render_transform()
	_shadow.global_position = rx.origin + SHADOW_OFFSET
	_shadow.global_rotation = rx.get_rotation()
	_shadow.global_scale = _hull.global_scale * 1.03


func _approach(cur: float, target: float, up: float, down: float, delta: float) -> float:
	var rate := up if target > cur else down
	return lerpf(cur, target, 1.0 - exp(-rate * delta))


func _update_engines(delta: float) -> void:
	var target := maxf(ship.main_output, 0.0) if ship.alive else 0.0
	_eng = _approach(_eng, target, 16.0, 7.0, delta)
	# Throttle maps onto the old two-stage look: 0-50 % grows the cruise
	# flame, 50-100 % blends into what boost used to be (longer, bluer plume,
	# shock diamonds, brighter glow). 100 % throttle == the old boost.
	_lvl = clampf(_eng * 2.0, 0.0, 1.0)
	_boost_vis = smoothstep(0.0, 1.0, clampf(_eng * 2.0 - 1.0, 0.0, 1.0))
	var lvl := _lvl
	for p in _plumes:
		var fl := _noise.get_noise_2d(_t * 40.0, p.seed) * 0.5 + 0.5      # 0..1 flicker
		var fl2 := _noise.get_noise_2d(p.seed, _t * 55.0) * 0.5 + 0.5
		var length := (12.0 + 40.0 * lvl + 55.0 * _boost_vis) * (0.86 + 0.22 * fl)
		var width := (6.5 + 3.5 * lvl + 4.0 * _boost_vis) * (0.92 + 0.12 * fl2)
		var vis := smoothstep(0.0, 0.08, _eng)
		var outer: Sprite2D = p.outer
		outer.scale = Vector2(length / 128.0, width / 32.0 * 1.25)
		outer.modulate = Color(C_PLUME.lerp(C_PLUME_BOOST, _boost_vis), (0.7 + 0.3 * fl) * vis)
		var core: Sprite2D = p.core
		core.scale = Vector2(length * 0.55 / 128.0, width * 0.45 / 32.0)
		core.modulate = Color(C_CORE.lerp(Color.WHITE, _boost_vis), (0.75 + 0.25 * fl2) * vis)
		var nozzle: Sprite2D = p.nozzle
		nozzle.scale = Vector2.ONE * ((10.0 + 10.0 * lvl + 10.0 * _boost_vis) / 128.0)
		nozzle.modulate = Color(C_CORE, (0.5 + 0.4 * fl) * vis)
		# Shock diamonds fade in over the upper half of the throttle.
		var diamonds: Array = p.diamonds
		for k in diamonds.size():
			var d: Sprite2D = diamonds[k]
			var f := 0.16 + 0.17 * k
			d.position = Vector2(length * f, 0)
			var dsz := (6.0 - k * 1.2) * (0.8 + 0.4 * fl2)
			d.scale = Vector2(dsz * 1.6, dsz) / 128.0 * 1.6
			d.modulate = Color(0.85, 0.9, 1.0, _boost_vis * (0.9 - 0.2 * k) * (0.7 + 0.3 * fl))
	var glow_a := 0.10 * lvl + 0.12 * _boost_vis
	_engine_glow.modulate = Color(C_ENGINE_LIGHT.lerp(C_PLUME_BOOST, _boost_vis), glow_a)
	_engine_glow.scale = Vector2.ONE * ((150.0 + 90.0 * _boost_vis) / 128.0)
	_engine_light.energy = 0.22 * lvl + 0.22 * _boost_vis
	_engine_light.enabled = _engine_light.energy > 0.01
	for g in _coil_glows:
		g.modulate.a = 0.18 + 0.35 * lvl + 0.3 * _boost_vis


func _update_rcs(delta: float) -> void:
	var bow := ship.bow_lateral_output if ship.alive else 0.0
	var stern := ship.stern_lateral_output if ship.alive else 0.0
	# + lateral output = force toward starboard = gas exits the PORT nozzle.
	var retro := maxf(-ship.main_output, 0.0) / maxf(ship.reverse_scale, 0.05) if ship.alive else 0.0
	_rcs_raw[0] = maxf(bow, 0.0)
	_rcs_raw[1] = maxf(-bow, 0.0)
	_rcs_raw[2] = maxf(stern, 0.0)
	_rcs_raw[3] = maxf(-stern, 0.0)
	_rcs_raw[4] = retro
	_rcs_raw[5] = retro
	var gt := ship.render_transform()
	var base_v := ship.linear_velocity
	var w := ship.angular_velocity
	var activity := 0.0
	for i in 6:
		var raw := minf(_rcs_raw[i], 2.0)
		var prev := _rcs_vis[i]
		_rcs_vis[i] = _approach(prev, raw, 40.0, 14.0, delta)
		var lvl := _rcs_vis[i]
		activity += minf(raw, 1.0) * (0.5 if i >= 4 else 1.0)
		var jet := _rcs_jets[i]
		var fl := _noise.get_noise_2d(_t * 60.0, 100.0 + i * 13.0) * 0.5 + 0.5
		var len_px := (6.0 + 12.0 * minf(lvl, 1.5)) * (0.8 + 0.4 * fl)
		jet.scale = Vector2(len_px / 128.0, (4.0 + 2.0 * lvl) / 32.0)
		jet.modulate = Color(C_GAS, clampf(lvl, 0.0, 1.0) * (0.65 + 0.3 * fl))
		# Gas puffs: onset burst + continuous stream proportional to output.
		var root := jet.get_parent() as Node2D
		var local_dir := Vector2.RIGHT.rotated(root.rotation)
		var pos := gt * root.position
		var dir := gt.basis_xform(local_dir).normalized()
		var r := pos - gt.origin
		var inherit := base_v + Vector2(-w * r.y, w * r.x)
		if raw > 0.05 and prev < 0.03:
			rcs_onset.emit(minf(raw, 1.5))
			for k in 6:
				_emit_gas(pos, inherit, dir, 1.3)
		if raw > 0.02:
			_rcs_emit_acc[i] += delta * 70.0 * minf(raw, 1.5)
			while _rcs_emit_acc[i] >= 1.0:
				_rcs_emit_acc[i] -= 1.0
				_emit_gas(pos, inherit, dir, 1.0)
		else:
			_rcs_emit_acc[i] = 0.0
	rcs_activity = clampf(activity, 0.0, 1.5)


func _emit_gas(pos: Vector2, inherit: Vector2, dir: Vector2, strength: float) -> void:
	var spread := dir.rotated(randf_range(-0.28, 0.28))
	var speed := randf_range(90.0, 170.0) * strength
	var life := randf_range(0.28, 0.5)
	_gas.emit(pos + spread * 2.0, inherit, spread * speed, life,
		randf_range(3.0, 5.0), randf_range(14.0, 22.0) * strength,
		Color(C_GAS, 0.6), Color(0.75, 0.85, 0.95, 0.0), 5.5)


func _update_lights() -> void:
	var alive_mul := 1.0 if ship.alive else 0.0
	# Steady nav lights with a slow, subtle breathing.
	var breathe := 0.85 + 0.15 * sin(_t * 2.1)
	_nav_port.modulate = Color(C_NAV_PORT, breathe * alive_mul)
	_nav_stbd.modulate = Color(C_NAV_STBD, breathe * alive_mul)
	# Strobe: double flash every 1.6 s.
	var ph := fmod(_t, 1.6)
	var on := (ph < 0.05) or (ph > 0.16 and ph < 0.21)
	var a := (1.0 if on else 0.0) * alive_mul
	_strobe.modulate = Color(1, 1, 1, a * 0.8)
	_strobe_core.modulate = Color(1, 1, 1, a)


func _update_trails(delta: float) -> void:
	_trail_sample += delta
	var add_point := _trail_sample >= 1.0 / 30.0
	if add_point:
		_trail_sample = 0.0
	var gt := ship.render_transform()
	var active := _lvl > 0.12 and ship.alive
	for i in 2:
		var pts: Array = _trail_pts[i]
		var nozzle := gt * (ENGINE_NOZZLES[i] + Vector2(-10, 0))
		# Drop old points.
		while not pts.is_empty() and _t - float(pts[0][1]) > trail_lifetime:
			pts.pop_front()
		if active and add_point:
			pts.append([nozzle, _t])
		var line := _trails[i]
		if pts.size() < 2 and not active:
			line.clear_points()
			continue
		var packed := PackedVector2Array()
		packed.resize(pts.size() + (1 if active else 0))
		for k in pts.size():
			packed[k] = pts[k][0]
		if active:
			packed[pts.size()] = nozzle   # head glued to the nozzle every frame
		line.points = packed
		line.width = 1.6 + 1.4 * _lvl + 1.6 * _boost_vis
		line.modulate.a = 0.55 + 0.3 * _boost_vis
		if not active and pts.is_empty():
			line.clear_points()


func _update_damage(delta: float) -> void:
	var dmg := 1.0 - _hull_frac
	_damage.modulate.a = smoothstep(0.1, 0.8, dmg)
	if not ship.alive:
		return
	var gt := ship.render_transform()
	# Smoke below 55 % hull, thicker as it drops.
	if _hull_frac < 0.55:
		_smoke_acc += delta * lerpf(4.0, 28.0, inverse_lerp(0.55, 0.0, _hull_frac))
		while _smoke_acc >= 1.0:
			_smoke_acc -= 1.0
			var p := gt * DAMAGE_POINTS[randi() % DAMAGE_POINTS.size()]
			var drift := Vector2.from_angle(randf() * TAU) * randf_range(8.0, 25.0)
			# Light grey so it reads against black space; darkens as it thins.
			var g := randf_range(0.5, 0.72)
			_gas.emit(p, ship.linear_velocity * 0.8, drift, randf_range(0.9, 1.8),
				randf_range(6.0, 10.0), randf_range(30.0, 52.0),
				Color(g, g * 0.97, g * 0.95, 1.0), Color(g * 0.6, g * 0.6, g * 0.65, 0.55), 0.8)
	# Sparks below 30 %.
	if _hull_frac < 0.3:
		_spark_timer -= delta
		if _spark_timer <= 0.0:
			_spark_timer = randf_range(0.15, 0.7)
			var p2 := gt * DAMAGE_POINTS[randi() % DAMAGE_POINTS.size()]
			_spark_burst(p2, Vector2.from_angle(randf() * TAU), randi_range(3, 7), 160.0)


func _spark_burst(pos: Vector2, dir: Vector2, count: int, speed: float) -> void:
	for k in count:
		var d := dir.rotated(randf_range(-0.9, 0.9))
		_glow_fx.emit(pos, ship.linear_velocity * 0.9, d * randf_range(0.4, 1.0) * speed,
			randf_range(0.2, 0.5), 1.6, 0.8, Color(1.0, 0.85, 0.5, 1.0), Color(1.0, 0.4, 0.15, 1.0),
			2.0, ShipParticles.Kind.SPARK)


# -------------------------------------------------------------- events --
func _on_impact(pos: Vector2, normal: Vector2, speed_mps: float, _other: Node) -> void:
	var k := clampf(speed_mps / 18.0, 0.15, 1.0)
	_flash = maxf(_flash, k)
	_flash_color = Color(1.0, 0.95, 0.9).lerp(Color(1.0, 0.45, 0.3), clampf((speed_mps - 8.0) / 15.0, 0.0, 1.0))
	# Paint flecks / hull chips knocked off at the contact (ship-local juice;
	# the big sparks & sounds belong to the gameplay ImpactFX).
	var n := int(clampf(speed_mps * 0.6, 2.0, 14.0))
	for i in n:
		var d := normal.rotated(randf_range(-1.1, 1.1))
		_gas.emit(pos, Vector2.ZERO, d * randf_range(30.0, 120.0) * (0.5 + k), randf_range(0.3, 0.7),
			randf_range(1.5, 3.0), 1.0, Color(0.93, 0.95, 0.98, 0.9), Color(0.6, 0.65, 0.7, 0.0), 1.5)


func _on_hull_changed(h: float, max_h: float) -> void:
	_hull_frac = clampf(h / maxf(max_h, 1.0), 0.0, 1.0)


func _reset_fx() -> void:
	_eng = 0.0
	_lvl = 0.0
	_boost_vis = 0.0
	_flash = 0.0
	_trail_pts = [[], []]
	for line in _trails:
		line.clear_points()
	_gas.clear()
	_glow_fx.clear()
