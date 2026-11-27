class_name JumpSystem
extends Node
## The quantum drive: sectors, the star map and the light-speed jump.
##
## SECTORS. Every station lives in the same world, kilometres apart (see
## Sectors). This node watches where the player's ship is and keeps
## Game.sector, Game.world_bounds and the sky in step, whatever moved the
## ship (a jump, a respawn at home, a harness flag).
##
## COURSE. The star map (StarMap, opened at the bridge's nav table or with N
## at a frigate's helm) lays in a course to another sector.
##
## THE JUMP, flown from a frigate's helm with a course laid in:
##   SPOOL   hold J for 3.2 s: the drive rings charge (you can still steer).
##           Needs a free ship (not clamped) and a ship's length of clear
##           space around the hull; letting go aborts.
##   LEAP    the drive takes the helm (FrigateShip.jump_ctl): the ship holds
##           still while the stars stretch, then a flash
##   TUNNEL  ~4.5 s at light speed. Behind the tunnel the ship (with whatever
##           is parked on its flight deck) is moved to the destination's
##           arrival point, and the bounds and the sky are switched
##   ARRIVE  a second flash, the ship drops out doing 60 m/s and brakes to a
##           crawl in about 40 m; the helm is handed back.
## The look of each stage is WarpFX's (scripts/environment/warp_fx.gd): this
## node only drives its dials.

enum Phase { IDLE, SPOOL, LEAP, TUNNEL, ARRIVE }

const SPOOL_TIME := 3.2
const LEAP_TIME := 0.9
const TUNNEL_TIME := 4.6
const ARRIVE_TIME := 2.6
const ARRIVE_SPEED := 60.0        ## m/s out of the tunnel
const ARRIVE_BRAKE := 1.6         ## 1/s exponential braking after the drop-out
const CLEARANCE_M := 40.0         ## free space needed round the hull to spool
const WARP_FX := "res://scripts/environment/warp_fx.gd"
const HULL_TEX := "res://assets/art/ship/frigate_hull.svg"

var phase := Phase.IDLE
## Where the drive is set to go (&"" = no course).
var course: StringName = &""
## 0..1 through the current phase (HUD).
var progress := 0.0
var from_sector: StringName = &""
var to_sector: StringName = &""
var map: StarMap

var _t := 0.0
var _ship: FrigateShip
var _fx: CanvasLayer
var _old_mask := 0
var _deny_t := 0.0
var _clear := true
var _clear_t := 0.0
var _snd := {}
var _loop: AudioStreamPlayer
var _spool: AudioStreamPlayer
var _hud: Control


func _ready() -> void:
	add_to_group(&"jump_system")
	_register_inputs()
	for n in ["jump_spool", "jump_engage", "jump_arrive", "jump_abort", "cargo_deny"]:
		_snd[n] = GameplayUtil.load_audio(n + ".wav")
	var loop := GameplayUtil.load_loop("warp_tunnel_loop.wav")
	if loop:
		_loop = GameplayUtil.make_player(self, loop, &"Engine", -60.0)
	if _snd["jump_spool"]:
		_spool = GameplayUtil.make_player(self, _snd["jump_spool"], &"Engine", -4.0)
	map = StarMap.new()
	map.name = "StarMap"
	map.jump = self
	add_child(map)
	if ResourceLoader.exists(WARP_FX):
		_fx = (load(WARP_FX) as GDScript).new() as CanvasLayer
		_fx.name = "WarpFX"
		add_child(_fx)
	Game.ship_destroyed.connect(func(_p: Vector2) -> void: _cancel())
	Game.player_changed.connect(func(_n: RigidBody2D, _o: RigidBody2D) -> void: _cancel())
	_apply_sector.call_deferred(Sectors.at(Game.player.global_position) if GameplayUtil.player_valid() else Sectors.MERIDIAN, true)
	if Game.cmd.has("jump"):
		_harness_jump.call_deferred(StringName(String(Game.cmd["jump"])))


func _register_inputs() -> void:
	for def: Array in [[&"jump_engage", KEY_J], [&"star_map", KEY_N]]:
		if not InputMap.has_action(def[0]):
			InputMap.add_action(def[0], 0.25)
			var e := InputEventKey.new()
			e.physical_keycode = def[1]
			InputMap.action_add_event(def[0], e)


## A jump is running (nobody leaves the bridge, the map stays shut).
func busy() -> bool:
	return phase != Phase.IDLE


func open_map() -> void:
	if not busy():
		map.open()


func set_course(id: StringName) -> void:
	if id != &"" and (not Sectors.has(id) or id == Game.sector):
		return
	course = id
	Game.jump_event.emit("course", {"to": id})


# ================================================================ sectors

func _apply_sector(id: StringName, force := false) -> void:
	if id == Game.sector and not force:
		return
	Game.sector = id
	Game.world_bounds = Sectors.bounds(id)
	var bg := get_tree().get_first_node_in_group(&"space_background")
	if bg == null:
		bg = get_node_or_null(^"/root/Main/SpaceBackground")
	if bg == null and get_parent() and get_parent().get_parent():
		bg = get_parent().get_parent().get_node_or_null(^"SpaceBackground")
	if bg and bg.has_method(&"set_look"):
		bg.call(&"set_look", Sectors.DEFS[id].look, Sectors.origin(id))
	if course == id:
		course = &""
	Game.sector_changed.emit(id)


# ============================================================== per frame

func _physics_process(delta: float) -> void:
	_deny_t = maxf(0.0, _deny_t - delta)
	if phase == Phase.IDLE:
		if GameplayUtil.player_valid():
			_apply_sector(Sectors.at(Game.player.global_position))
		_tick_idle(delta)
		return
	if _ship == null or not is_instance_valid(_ship) or not _ship.alive:
		_cancel()
		return
	_t += delta
	match phase:
		Phase.SPOOL:
			progress = _t / SPOOL_TIME
			_ship.jump_glow = smoothstep(0.0, 1.0, progress)
			if Input.get_action_strength(&"jump_engage") < 0.5:
				_abort("released")
			elif not _can_jump(_ship, false):
				_abort("")
			elif _t >= SPOOL_TIME:
				_leap()
		Phase.LEAP:
			progress = _t / LEAP_TIME
			if _t >= LEAP_TIME:
				_enter_tunnel()
		Phase.TUNNEL:
			progress = _t / TUNNEL_TIME
			if _t >= TUNNEL_TIME:
				_drop_out()
		Phase.ARRIVE:
			progress = _t / ARRIVE_TIME
			_ship.jump_glow = 1.0 - smoothstep(0.0, 0.6, progress)
			if _t >= ARRIVE_TIME:
				_finish()


func _tick_idle(delta: float) -> void:
	var ship := Game.player as FrigateShip
	if ship == null or not ship.alive or Game.mode != Game.Mode.FLIGHT or map.is_open():
		_clear = true
		return
	if ship.controls_enabled and Input.is_action_just_pressed(&"star_map"):
		open_map()
		return
	# Clearance is a physics query: a few times a second is plenty.
	_clear_t -= delta
	if _clear_t <= 0.0 and course != &"":
		_clear_t = 0.25
		_clear = _clearance_ok(ship)
	if ship.controls_enabled and Input.is_action_just_pressed(&"jump_engage"):
		if _can_jump(ship, true):
			_start_spool(ship)


## Why the drive won't spool right now ("" = it will).
func blocker(ship: FrigateShip) -> String:
	if course == &"":
		return "NO COURSE  ·  N star map"
	if ship.dock.state != FrigateDock.State.FREE:
		return "UNDOCK FIRST"
	if ship.damage.core_breach >= 0.0:
		return "REACTOR FAILING"
	if not _clear:
		return "TOO CLOSE TO STRUCTURE"
	return ""


func _can_jump(ship: FrigateShip, announce: bool) -> bool:
	_clear = _clearance_ok(ship)
	var why := blocker(ship)
	if why == "":
		return true
	if announce and _deny_t <= 0.0:
		_deny_t = 1.5
		GameplayUtil.play_oneshot(self, _snd["cargo_deny"], -8.0, 1.0, &"UI")
		Game.toast("QUANTUM DRIVE  ·  %s" % why.replace("STRUCTURE", "STRUCTURE  ·  clear it by a ship's length"), 2.6)
	return false


## A ship's length of empty space round the hull (station structure only:
## traffic and cargo move out of the way of physics, structure doesn't).
func _clearance_ok(ship: FrigateShip) -> bool:
	var q := PhysicsShapeQueryParameters2D.new()
	var c := CircleShape2D.new()
	c.radius = (FrigateShape.HALF_LENGTH + CLEARANCE_M) * Game.PX_PER_M
	q.shape = c
	q.transform = Transform2D(0.0, ship.to_global(Vector2(FrigateShape.CENTRE_X * Game.PX_PER_M, 0.0)))
	q.collision_mask = Game.LAYER_WORLD
	var ex: Array[RID] = [ship.get_rid()]
	for e in ship.bay.stowed:
		if is_instance_valid(e.ship):
			ex.append((e.ship as PlayerShip).get_rid())
	q.exclude = ex
	return ship.get_world_2d().direct_space_state.intersect_shape(q, 1).is_empty()


# ================================================================ the jump

func _start_spool(ship: FrigateShip) -> void:
	_ship = ship
	phase = Phase.SPOOL
	_t = 0.0
	progress = 0.0
	from_sector = Game.sector
	to_sector = course
	if _spool:
		_spool.play()
	Game.jump_event.emit("spool", {"to": to_sector})


func _abort(why: String) -> void:
	if _spool:
		_spool.stop()
	GameplayUtil.play_oneshot(self, _snd["jump_abort"], -5.0, 1.0, &"Engine")
	if why == "released":
		Game.toast("QUANTUM DRIVE  ·  spool aborted  ·  hold J until the rings fold", 2.4)
	elif _ship:
		Game.toast("QUANTUM DRIVE  ·  spool aborted  ·  %s" % blocker(_ship), 2.4)
	Game.jump_event.emit("abort", {"why": why})
	_reset()


## Anything that takes the ship away mid-jump: drop everything.
func _cancel() -> void:
	if phase == Phase.IDLE:
		return
	if _spool:
		_spool.stop()
	_reset()


func _reset() -> void:
	if _ship and is_instance_valid(_ship):
		_ship.jump_glow = 0.0
		if _ship.jump_ctl == self:
			_ship.jump_ctl = null
			_ship.collision_mask = _old_mask
	_ship = null
	phase = Phase.IDLE
	progress = 0.0
	if _loop:
		_loop.stop()
	_drive_fx(0.0)


func _leap() -> void:
	phase = Phase.LEAP
	_t = 0.0
	_old_mask = _ship.collision_mask
	# Nothing may touch the ship while the drive has it.
	_ship.collision_mask = 0
	_ship.jump_ctl = self
	GameplayUtil.play_oneshot(self, _snd["jump_engage"], -2.0, 1.0)
	if Game.camera and Game.camera.has_method(&"add_trauma"):
		Game.camera.call(&"add_trauma", 0.45)
	Game.jump_event.emit("leap", {"to": to_sector})


func _enter_tunnel() -> void:
	phase = Phase.TUNNEL
	_t = 0.0
	# Behind the flash: the ship is already at the far end, held still.
	var at := Sectors.arrival(to_sector)
	_ship.warp_to(at, Vector2.ZERO)
	_apply_sector(to_sector, true)
	if Game.camera and Game.camera.has_method(&"snap"):
		Game.camera.call(&"snap")
	if _loop:
		_loop.volume_db = -6.0
		_loop.play()
	if _fx and _fx.has_method(&"set_ship_snapshot") and ResourceLoader.exists(HULL_TEX):
		var cam := Game.camera
		var zoom := cam.zoom if cam else Vector2.ONE
		var rot := _ship.global_rotation - (cam.global_rotation if cam else 0.0)
		_fx.call(&"set_ship_snapshot", load(HULL_TEX), get_viewport().get_visible_rect().size * 0.5, rot, zoom * 0.5)


func _drop_out() -> void:
	phase = Phase.ARRIVE
	_t = 0.0
	if _loop:
		_loop.stop()
	if _fx and _fx.has_method(&"clear_ship_snapshot"):
		_fx.call(&"clear_ship_snapshot")
	GameplayUtil.play_oneshot(self, _snd["jump_arrive"], -2.0, 1.0)
	_ship.linear_velocity = Vector2.from_angle(_ship.global_rotation) * ARRIVE_SPEED * Game.PX_PER_M
	if Game.camera and Game.camera.has_method(&"add_trauma"):
		Game.camera.call(&"add_trauma", 0.35)


func _finish() -> void:
	var ship := _ship
	var dest := to_sector
	_reset()
	Game.toast("ARRIVED  ·  %s  ·  you have the helm" % Sectors.display_name(dest), 4.0)
	Game.jump_event.emit("arrive", {"sector": dest})
	if ship:
		ship.jump_glow = 0.0


## FrigateShip calls this instead of its own flight model while jump_ctl is
## set (inside the physics callback).
func apply(state: PhysicsDirectBodyState2D, _ship_body: FrigateShip) -> void:
	state.angular_velocity = 0.0
	match phase:
		Phase.ARRIVE:
			# Dropping out: bleed the speed off smoothly to a crawl.
			var v := state.linear_velocity
			state.linear_velocity = v * exp(-ARRIVE_BRAKE * state.step)
		_:
			state.linear_velocity = state.linear_velocity * exp(-4.0 * state.step)


# =============================================================== the look

func _process(_delta: float) -> void:
	match phase:
		Phase.IDLE:
			return
		Phase.SPOOL:
			_drive_fx(progress)
		Phase.LEAP:
			# stars stretch, then the flash hides the cut to the tunnel
			_drive_fx(1.0, smoothstep(0.0, 0.75, progress), 0.0, smoothstep(0.72, 1.0, progress), 0.0)
		Phase.TUNNEL:
			var a := clampf(_t / 0.5, 0.0, 1.0)
			var out := smoothstep(0.93, 1.0, progress)
			_drive_fx(1.0 - a, 1.0, 1.0, maxf(1.0 - a, out), progress)
		Phase.ARRIVE:
			var k := clampf(_t / 0.9, 0.0, 1.0)
			_drive_fx(0.0, 1.0 - k, 0.0, 1.0 - clampf(_t / 0.45, 0.0, 1.0), 1.0)


func _drive_fx(charge: float, streak := 0.0, tunnel := 0.0, flash := 0.0, along := 0.0) -> void:
	if _fx == null:
		return
	_fx.set(&"charge", charge)
	_fx.set(&"streak", streak)
	_fx.set(&"tunnel", tunnel)
	_fx.set(&"flash", flash)
	_fx.set(&"progress", along)
	_fx.set(&"direction", 1.0 if to_sector != Sectors.MERIDIAN else -1.0)
	if _ship and is_instance_valid(_ship):
		var cam := Game.camera
		_fx.set(&"heading", _ship.global_rotation - (cam.global_rotation if cam else 0.0))


# ================================================================ harness

## --jump=vesper: lay in that course and jump as soon as a frigate is flown
## (skips the clearance check and the held key: for tests and screenshots).
func _harness_jump(id: StringName) -> void:
	while is_inside_tree():
		await get_tree().create_timer(0.5, false).timeout
		var ship := Game.player as FrigateShip
		if ship == null or phase != Phase.IDLE or Game.mode != Game.Mode.FLIGHT:
			continue
		if ship.dock.state != FrigateDock.State.FREE or not Sectors.has(id) or id == Game.sector:
			continue
		set_course(id)
		force_jump(ship)
		return


## Start a jump right now, from the end of the spool (tests).
func force_jump(ship: FrigateShip) -> void:
	if course == &"" or phase != Phase.IDLE:
		return
	_start_spool(ship)
	_t = SPOOL_TIME
	_leap()
