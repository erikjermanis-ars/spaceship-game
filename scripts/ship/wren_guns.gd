class_name WrenGuns
extends Node
## The WREN's twin pulse cannons (node `Guns` in player_ship.tscn; the PETREL
## and the frigate have their own scenes and no such node).
##
## Fixed forward guns at the wing roots, fired alternately while `ship_fire`
## is held. The bolts themselves belong to WeaponSystem (group
## `weapon_system`); this node owns the trigger, the heat and everything you
## see and hear at the ship: the gun pods, muzzle flash, barrel glow, vent
## steam, a small camera kick and the aim line.
##
## Heat: every shot adds some, it bleeds off once you stop. At 100 % the guns
## lock out and vent until they are back under `ready_below`.

const PX := 10.0
## Muzzles in ship pixels (port, starboard): must match wren_guns.svg.
const MUZZLES: Array[Vector2] = [Vector2(18.0, -13.3), Vector2(18.0, 13.3)]
const GUN_ART := preload("res://assets/art/ship/wren_guns.svg")
const FLASH_S := 0.075
const VENT_S := 1.5
const C_FLASH := Color(1.0, 0.7, 0.35)
const C_HOT := Color(1.0, 0.45, 0.1)

@export_group("Guns")
## Shots per second while the trigger is held (the two guns alternate).
@export_range(1.0, 20.0, 0.5, "suffix:/s") var fire_rate_hz := 6.0
## The two bolt lines cross this far ahead, so aiming the nose at a small
## target lands both guns on it.
@export_range(20.0, 400.0, 5.0, "suffix:m") var converge_m := 90.0
@export_group("Heat")
## Heat added per shot (1 = lockout): 23 shots, 3.7 s of holding the trigger.
@export_range(0.0, 0.5, 0.005) var heat_per_shot := 0.045
## Cooling per second once the guns have been quiet for `cool_delay_s`.
@export_range(0.0, 2.0, 0.01, "suffix:/s") var cool_per_s := 0.28
@export_range(0.0, 2.0, 0.05, "suffix:s") var cool_delay_s := 0.25
## After an overheat the guns come back when heat drops below this.
@export_range(0.0, 0.9, 0.05) var ready_below := 0.3
@export_group("Feel")
## Camera kick per shot, screen pixels (the ship itself has no recoil).
@export_range(0.0, 8.0, 0.1, "suffix:px") var kick_px := 1.6
@export_range(-40.0, 0.0, 0.5, "suffix:dB") var shot_db := -7.0

## 0..1, for the HUD gauge.
var heat := 0.0
## Locked out until the heat is back under ready_below.
var overheated := false
## Shots fired since the session started (tests).
var shots := 0
## 0..1: how visible the aim line is (firing, or just stopped).
var aim_alpha := 0.0

var ship: PlayerShip
var _cooldown := 0.0
var _since_shot := 100.0
var _side := 0
var _held := false
var _flash := PackedFloat32Array([0.0, 0.0])
var _vent := 0.0
var _vent_acc := 0.0
var _warned := false
var _t := 0.0

var _art: Node2D
var _fans: Array[Sprite2D] = []
var _blooms: Array[Sprite2D] = []
var _cores: Array[Sprite2D] = []
var _flares: Array[Sprite2D] = []
var _barrel_glow: Array[Sprite2D] = []
var _barrel_hot: Array[Sprite2D] = []
var _steam: ShipParticles
var _aim: GunAimLine
var _snd_shot: AudioStreamPlayer
var _snd_overheat: AudioStreamPlayer
var _snd_ready: AudioStreamPlayer
var _snd_dry: AudioStreamPlayer


func _ready() -> void:
	ship = get_parent() as PlayerShip
	if ship == null:
		set_process(false)
		set_physics_process(false)
		return
	_build_art()
	_snd_shot = _player(GameplayUtil.load_variations("pulse_shot_", 3, 1.05, 1.0), shot_db, 4)
	_snd_overheat = _player(GameplayUtil.load_audio("gun_overheat.wav"), -6.0, 1)
	_snd_ready = _player(GameplayUtil.load_audio("gun_ready.wav"), -9.0, 1)
	_snd_dry = _player(GameplayUtil.load_audio("ui_click.wav"), -14.0, 1, &"UI")
	Game.ship_respawned.connect(_on_respawned)


## Null when the file isn't there (the sounds are made by another workstream)
## and in headless runs; every caller copes.
func _player(stream: AudioStream, db: float, polyphony: int, bus: StringName = &"SFX") -> AudioStreamPlayer:
	if stream == null:
		return null
	var p := GameplayUtil.make_player(self, stream, bus, db)
	p.max_polyphony = polyphony
	return p


# ------------------------------------------------------------- building --
## All gun art lives under the ship's `Visuals` node: it is drawn at the
## interpolated transform, and the on-foot layer fades and hides that node
## when the detailed landed model takes over.
func _build_art() -> void:
	var visuals := ship.get_node_or_null(^"Visuals") as Node2D
	_art = Node2D.new()
	_art.name = "GunArt"
	(visuals if visuals else ship).add_child(_art)
	var pods := Sprite2D.new()
	pods.name = "Pods"
	pods.texture = GUN_ART
	pods.scale = Vector2.ONE / 6.0          # the SVG is imported at 6x, like the hull
	pods.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_art.add_child(pods)
	for m in MUZZLES:
		# Heat: an additive glow along the barrel, plus a normal-blend ember on
		# the muzzle brake that still shows over a white hull.
		var glow := _sprite(ShipFxTextures.glow(), m + Vector2(-6.0, 0.0), true)
		glow.scale = Vector2(30.0, 11.0) / 128.0
		_barrel_glow.append(glow)
		var hot := _sprite(FxTextures.hot_core(), m + Vector2(-1.3, 0.0), false)
		hot.scale = Vector2(7.0, 5.0) / 64.0
		_barrel_hot.append(hot)
		var fan := _sprite(WeaponTextures.muzzle(), m, true)
		fan.centered = false
		fan.offset = Vector2(0, -16)
		_fans.append(fan)
		_blooms.append(_sprite(ShipFxTextures.glow(), m + Vector2(3.0, 0.0), true))
		# A thin flare across the muzzle: the "pulse" in pulse cannon.
		var flare := _sprite(WeaponTextures.streak(), m + Vector2(1.5, 0.0), true)
		flare.rotation = PI * 0.5
		_flares.append(flare)
		_cores.append(_sprite(FxTextures.hot_core(), m + Vector2(1.0, 0.0), false))
	_steam = ShipParticles.new()
	_steam.name = "VentSteam"
	_steam.z_as_relative = false
	_steam.z_index = Game.Z_SHIP + 1
	_art.add_child(_steam)
	_aim = GunAimLine.new()
	_aim.name = "AimLine"
	_aim.guns = self
	_art.add_child(_aim)


func _sprite(tex: Texture2D, pos: Vector2, additive: bool) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex
	s.position = pos
	s.modulate.a = 0.0
	s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if additive:
		s.material = ShipFxTextures.additive()
	_art.add_child(s)
	return s


# -------------------------------------------------------------- trigger --
func _physics_process(delta: float) -> void:
	var want := _trigger()
	if want and not _held and overheated and _snd_dry:
		_snd_dry.pitch_scale = 0.7       # dry click: the lockout is why nothing fires
		_snd_dry.play()
	_held = want
	# The interval is counted down without rounding (and the remainder kept),
	# so 6 /s at a 120 Hz tick really is a shot every 20 ticks.
	_cooldown = maxf(_cooldown - delta, -0.5 * delta)
	_since_shot += delta
	if want and not overheated and _cooldown <= 0.0001:
		_shoot()
	if overheated or _since_shot >= cool_delay_s:
		heat = maxf(heat - cool_per_s * delta, 0.0)
	if overheated and heat <= ready_below:
		overheated = false
		if _snd_ready:
			_snd_ready.play()
	_aim.track()


## The pilot is holding fire and may shoot: your ship, in flight, controls on.
func _trigger() -> bool:
	if Game.player != ship or Game.mode != Game.Mode.FLIGHT:
		return false
	if ship.pilot_action(&"ship_fire") < 0.5:
		return false
	# A click on a panel (the tuning sliders) is not a trigger pull.
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and ship.get_viewport().gui_get_hovered_control() != null \
			and not Input.is_physical_key_pressed(KEY_SPACE):
		return false
	return true


func _shoot() -> void:
	var weapons := get_tree().get_first_node_in_group(&"weapon_system") as WeaponSystem
	if weapons == null:
		return
	var side := _side
	_side = 1 - _side
	var xf := ship.global_transform
	var muzzle := MUZZLES[side]
	var origin := xf * muzzle
	# Toe-in toward the convergence point on the ship's axis.
	var toe := atan2(-muzzle.y, converge_m * PX - muzzle.x)
	var dir := Vector2.from_angle(xf.get_rotation() + toe)
	# The muzzle's own velocity: the ship's plus what its spin adds out there.
	var r := origin - xf.origin
	var w := ship.angular_velocity
	weapons.fire(origin, dir, ship.linear_velocity + Vector2(-w * r.y, w * r.x), ship)
	shots += 1
	_cooldown += 1.0 / fire_rate_hz
	_since_shot = 0.0
	_flash[side] = 1.0
	_fans[side].rotation = toe + randf_range(-0.06, 0.06)
	_fans[side].scale = Vector2(randf_range(40.0, 56.0) / 64.0, randf_range(20.0, 28.0) / 32.0)
	_fans[side].flip_v = randf() < 0.5
	if _snd_shot:
		_snd_shot.play()
	_kick(dir, side)
	heat += heat_per_shot
	if heat >= 1.0:
		heat = 1.0
		_overheat()


func _kick(dir: Vector2, side: int) -> void:
	var cam := Game.camera
	if cam == null or not is_instance_valid(cam):
		return
	if cam.has_method(&"punch"):
		# Back along the shot, nudged toward the gun that fired.
		cam.call(&"punch", -dir + dir.orthogonal() * (0.25 if side == 0 else -0.25), kick_px)
	if &"trauma" in cam:
		cam.set(&"trauma", maxf(float(cam.get(&"trauma")), 0.14))


func _overheat() -> void:
	overheated = true
	_vent = VENT_S
	if _snd_overheat:
		_snd_overheat.play()
	# Explain it once; after that the HUD gauge and the vent say enough.
	if not _warned:
		_warned = true
		Game.toast("Guns overheated: venting", 2.2)


func _on_respawned(_pos: Vector2) -> void:
	if Game.player != ship:
		return
	heat = 0.0
	overheated = false
	_vent = 0.0
	_cooldown = 0.0
	_steam.clear()


# --------------------------------------------------------------- visuals --
func _process(delta: float) -> void:
	_t += delta
	var alive := ship.alive
	for i in 2:
		_flash[i] = maxf(_flash[i] - delta / FLASH_S, 0.0)
		var e := _flash[i] * _flash[i] if alive else 0.0
		# Sprites at zero alpha would still be draw calls: hide them when dark.
		var lit := e > 0.004
		_fans[i].visible = lit
		_blooms[i].visible = lit
		_flares[i].visible = lit
		_cores[i].visible = lit
		_fans[i].modulate = Color(C_FLASH, e)
		_blooms[i].modulate = Color(C_FLASH, e * 0.9)
		_blooms[i].scale = Vector2.ONE * (44.0 + 44.0 * _flash[i]) / 128.0
		_flares[i].modulate = Color(1.0, 0.85, 0.6, e)
		_flares[i].scale = Vector2((26.0 + 30.0 * _flash[i]) / 64.0, 5.0 / 32.0)
		_cores[i].modulate = Color(1.0, 0.97, 0.88, e)
		_cores[i].scale = Vector2.ONE * (9.0 + 9.0 * _flash[i]) / 64.0
		# Barrels start to glow past 35 % and pulse while locked out.
		var h := smoothstep(0.35, 1.0, heat) if alive else 0.0
		if overheated:
			h *= 0.75 + 0.25 * sin(_t * 18.0)
		_barrel_glow[i].visible = h > 0.004
		_barrel_hot[i].visible = h > 0.004
		_barrel_glow[i].modulate = Color(C_HOT, 0.85 * h)
		_barrel_hot[i].modulate = Color(C_HOT.lerp(Color(1.0, 0.9, 0.6), h), h)
	_update_vent(delta)
	# The aim line comes up fast with the first shot and lingers after the last.
	var aiming := _since_shot < 0.9 and alive and Game.player == ship
	aim_alpha = move_toward(aim_alpha, 1.0 if aiming else 0.0, delta * (8.0 if aiming else 2.5))


## Steam jets out of both barrels after an overheat, thinning as they cool.
func _update_vent(delta: float) -> void:
	if _vent <= 0.0:
		return
	_vent -= delta
	if not ship.alive:
		return
	var k := clampf(_vent / VENT_S, 0.0, 1.0)
	_vent_acc += delta * lerpf(10.0, 110.0, k)
	var xf := ship.render_transform()
	while _vent_acc >= 1.0:
		_vent_acc -= 1.0
		var i := randi() % 2
		var out := xf.basis_xform(Vector2(0.55, -1.0 if i == 0 else 1.0)).normalized().rotated(randf_range(-0.4, 0.4))
		_steam.emit(xf * (MUZZLES[i] + Vector2(-3.0, 0.0)), ship.linear_velocity, out * randf_range(50.0, 170.0) * (0.5 + k),
			randf_range(0.45, 0.95), 4.0, randf_range(22.0, 40.0),
			Color(1.0, 0.82, 0.62, 0.8), Color(0.82, 0.88, 0.95, 0.0), 3.5)
