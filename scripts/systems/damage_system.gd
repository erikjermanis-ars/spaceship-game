class_name DamageSystem
extends Node
## Converts player collisions into hull damage, and owns the
## destroy -> explode -> respawn loop.
##
## Damage curve: k * max(0, v - threshold)^1.5 on the closing speed, so
## gentle docking bumps are free, a 10 m/s knock costs a few percent and a
## 40 m/s head-on hit nearly kills you. Scraping chips a little hull per
## second proportional to slide speed.

@export var threshold_mps := 3.0
@export var damage_k := 0.41               ## 40 m/s head-on ≈ 92 hp
@export var exponent := 1.5
@export var prop_multiplier := 0.55        ## light containers give way
@export var scrape_dps_per_mps := 0.12
@export var respawn_delay := 2.6
@export var invulnerable_after_respawn := 1.2

var _invuln := 0.0
var _scrape_accum := 0.0
var _last_scrape_ms := 0
var _last_velocity := Vector2.ZERO
var _respawn_pending := false
## Seconds until respawn while destroyed (HUD reads it), -1 otherwise.
var respawn_countdown := -1.0

func _ready() -> void:
	add_to_group(&"damage_system")
	Game.impact.connect(_on_impact)
	Game.scrape.connect(_on_scrape)
	Game.ship_destroyed.connect(_on_destroyed)
	Game.ship_respawned.connect(_on_respawned)
	# Boarding another ship: fresh velocity memory and a moment of grace.
	Game.player_changed.connect(func(ship: RigidBody2D, _old: RigidBody2D) -> void:
		_invuln = maxf(_invuln, 1.0)
		_scrape_accum = 0.0
		_last_velocity = ship.linear_velocity if ship else Vector2.ZERO)

func _physics_process(delta: float) -> void:
	_invuln = maxf(0.0, _invuln - delta)
	if GameplayUtil.player_alive():
		# Remember the pre-destruction velocity so debris inherits momentum
		# even if destroy() zeroes the body.
		_last_velocity = Game.player.linear_velocity
	if respawn_countdown > 0.0:
		respawn_countdown = maxf(0.0, respawn_countdown - delta)
	# Test hook: --kill-at=2.0 destroys the ship at that physics time.
	if Game.cmd.has("kill-at") and GameplayUtil.player_alive() and Game.sim_time() >= float(Game.cmd["kill-at"]):
		Game.cmd.erase("kill-at")
		_apply(10000.0, Game.player.global_position)

func damage_for_speed(speed_mps: float) -> float:
	return damage_k * pow(maxf(0.0, speed_mps - threshold_mps), exponent)

func _on_impact(pos: Vector2, _normal: Vector2, speed_mps: float, source: Node, other: Node) -> void:
	if not GameplayUtil.player_alive() or _invuln > 0.0:
		return
	var ship := Game.player
	if source != ship and other != ship:
		return
	var hit: Node = other if source == ship else source
	var mult := 1.0
	if hit is RigidBody2D and is_instance_valid(hit) and ((hit as RigidBody2D).collision_layer & Game.LAYER_PROPS) != 0:
		mult = prop_multiplier
	# Backstop for the blast doors: a moving leaf pinning the ship against the
	# other leaf reads as a huge closing speed. Treat it as a firm shove.
	if hit is AnimatableBody2D and is_instance_valid(hit) and hit.get_parent() != null \
			and hit.get_parent().has_method(&"open_amount"):
		speed_mps = minf(speed_mps, 12.0)
	# Ships can soften some hits (the PETREL's own towed load).
	if ship.has_method(&"damage_scale"):
		mult *= float(ship.call(&"damage_scale", hit, speed_mps))
	var dmg := damage_for_speed(speed_mps) * mult
	if dmg > 0.05:
		_apply(dmg, pos)

func _on_scrape(pos: Vector2, _normal: Vector2, tangent_speed_mps: float, source: Node) -> void:
	if source != Game.player or not GameplayUtil.player_alive() or _invuln > 0.0:
		return
	# Scrape arrives once per physics frame; integrate with the real step.
	var now := Time.get_ticks_msec()
	var dt := clampf((now - _last_scrape_ms) / 1000.0, 0.0, 1.0 / 30.0)
	_last_scrape_ms = now
	# Capped: a kinematic body teleporting past the ship can report absurd
	# tangent speeds for a tick.
	var slide := minf(tangent_speed_mps, 40.0)
	_scrape_accum += scrape_dps_per_mps * maxf(0.0, slide - 2.0) * dt * Engine.time_scale
	# Batch tiny chips so hull_changed isn't emitted every frame.
	if _scrape_accum >= 0.5:
		_apply(_scrape_accum, pos)
		_scrape_accum = 0.0

func _apply(amount: float, pos: Vector2) -> void:
	var ship := Game.player
	if ship.has_method(&"take_damage"):
		ship.call(&"take_damage", amount, pos)

# ========================================================= destruction ===
func _on_destroyed(pos: Vector2) -> void:
	# Spawned deferred: destroy() is usually triggered from inside a physics
	# callback, where adding new bodies is not allowed.
	_spawn_explosion.call_deferred(pos, _last_velocity)
	_respawn_pending = true
	respawn_countdown = respawn_delay
	_respawn_after_delay()

func _spawn_explosion(pos: Vector2, vel_px: Vector2) -> void:
	var fx := ShipExplosion.new()
	var host := _fx_host()
	host.add_child(fx)
	fx.explode(pos, vel_px)
	var impact_fx := get_tree().get_first_node_in_group(&"impact_fx") as ImpactFX
	if impact_fx:
		impact_fx.hit_stop(0.11, 0.18)

func _respawn_after_delay() -> void:
	await get_tree().create_timer(respawn_delay, false).timeout
	respawn_countdown = -1.0
	if not _respawn_pending:
		return
	_respawn_pending = false
	# Someone else (race restart) may have already brought the ship back.
	if not GameplayUtil.player_valid() or GameplayUtil.player_alive():
		return
	respawn_player()

## Respawn at the last passed race gate, else the spawn pad.
func respawn_player() -> void:
	if not GameplayUtil.player_valid():
		return
	# Racing: the last gate. Otherwise the ship's own home (the WREN's spawn
	# pad, the PETREL's hangar berth).
	var xf := GameplayUtil.spawn_transform(get_tree())
	if Game.player.has_method(&"home_transform"):
		xf = Game.player.call(&"home_transform")
	var race := get_tree().get_first_node_in_group(&"race_system")
	var gate_habit := int(race.get(&"last_gate_index")) >= 0 if race else false
	if Game.player.has_method(&"uses_pad_clamps") and not bool(Game.player.call(&"uses_pad_clamps")):
		gate_habit = false   # the PETREL goes home to its berth unless racing
	if race and race.has_method(&"get_respawn_transform") and (race.call(&"is_running") or gate_habit):
		xf = race.call(&"get_respawn_transform")
	teleport_player(xf)

## Shared by race restart / manual reset: puts the ship somewhere fresh.
func teleport_player(xf: Transform2D) -> void:
	var ship := Game.player
	if ship.has_method(&"respawn_at"):
		ship.call(&"respawn_at", xf)
	else:
		ship.global_transform = xf
		ship.linear_velocity = Vector2.ZERO
		ship.angular_velocity = 0.0
		Game.ship_respawned.emit(xf.origin)
	if Game.camera and Game.camera.has_method(&"snap"):
		Game.camera.call(&"snap")

func _on_respawned(pos: Vector2) -> void:
	_respawn_pending = false
	respawn_countdown = -1.0
	_invuln = invulnerable_after_respawn
	_scrape_accum = 0.0
	var rot := Game.player.global_rotation if GameplayUtil.player_valid() else 0.0
	var fx := WarpInFX.new()
	_fx_host().add_child(fx)
	fx.play(pos, rot)

func _fx_host() -> Node:
	var fx := get_tree().get_first_node_in_group(&"impact_fx")
	if fx:
		return fx
	return get_tree().current_scene
