class_name FrigateDamage
extends RefCounted
## The KESTREL's damage model. The WREN has one hull number; a 158 m frigate
## is a set of systems that fail one by one, so a hit has consequences you
## can feel at the helm:
##
##   * DEFLECTOR SHIELD first. A hit drains shield (x SHIELD_COST) and only a
##     little bleeds through to the hull. It regenerates after a quiet spell,
##     powered by Engineering: a damaged Engineering section gives a weaker,
##     slower shield, and a wrecked one none at all.
##   * SIX SECTIONS take what gets through, by where you were hit: Bow, Port
##     and Starboard hull, Engineering, Port and Starboard nacelle. `hull`
##     (the number every HUD shows) is their weighted average.
##   * EFFECTS. Each nacelle gives 30 % of the main thrust and Engineering
##     (the impulse deck) 40 %, so a hurt nacelle makes the ship pull to one
##     side; below 40 % a nacelle sputters, and a wrecked one goes dark. The
##     bow RCS turns the ship, Engineering's RCS is the other half of the turn
##     couple, and the hull sides carry the strafe quads.
##   * BREACHES. Hard hits leave a breach where they landed: a scorched hole
##     with glowing edges that vents atmosphere while its section is badly
##     hurt (the gas even pushes the ship a little).
##   * CORE BREACH. When Engineering hits zero the reactor goes critical: a
##     countdown, then the ship is lost. Dock before it blows, or don't let it
##     get there.
## Repairs happen in the berth (clamped): shields first, then the sections,
## and the breach marks close up as their section is patched.

enum Sec { BOW, PORT, STARBOARD, ENGINEERING, NACELLE_P, NACELLE_S }
const NAMES := ["BOW", "PORT HULL", "STBD HULL", "ENGINEERING", "PORT NACELLE", "STBD NACELLE"]
const WEIGHT := [0.18, 0.17, 0.17, 0.2, 0.14, 0.14]

const SHIELD_MAX := 100.0
## Shield points one point of hull damage costs while the shield holds.
const SHIELD_COST := 1.5
## Fraction of a shielded hit that still reaches the hull.
const BLEED := 0.1
## A section is a sixth of the ship: it takes this much more than the total.
const FRAGILITY := 1.7
const REGEN_DELAY := 2.5
const REGEN_RATE := 7.0           ## shield points per second at full power
const CORE_BREACH_TIME := 8.0
const MAX_BREACHES := 24

var integrity := PackedFloat32Array([100, 100, 100, 100, 100, 100])
var shield := SHIELD_MAX
var shield_online := true
## Seconds since the last hit (shield regen waits for a quiet spell).
var since_hit := 99.0
## Core breach countdown (s), -1 when the reactor is fine.
var core_breach := -1.0
## [{pos (local m), size (m), heat (1 = fresh .. 0), sec, seed}]
var breaches: Array[Dictionary] = []
## Shield impacts for the bubble shader: [{pos (local m), t (s), power}]
var shield_hits: Array[Dictionary] = []
## Per-nacelle sputter gate (1 = running), port then starboard.
var sputter := Vector2.ONE

var _sputter_t := Vector2.ZERO
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.seed = 4711


## Which section a local point (metres) belongs to.
static func section_at(p: Vector2) -> int:
	if absf(p.y) > 22.0 and p.x < -12.0:
		return Sec.NACELLE_S if p.y > 0.0 else Sec.NACELLE_P
	if p.x > 22.0:
		return Sec.BOW
	if p.x > -8.0:
		return Sec.STARBOARD if p.y > 0.0 else Sec.PORT
	return Sec.ENGINEERING


## Weighted total, 0..100 (the HUD hull number).
func hull() -> float:
	var h := 0.0
	for i in integrity.size():
		h += integrity[i] * WEIGHT[i]
	return h


func lowest() -> float:
	var m := 100.0
	for v in integrity:
		m = minf(m, v)
	return m


## How well a section's machinery still works: full above 90 %, falling to a
## third at 10 %, and nothing once it is wrecked.
func eff(sec: int) -> float:
	var i := integrity[sec]
	if i < 8.0:
		return 0.0
	return lerpf(0.35, 1.0, clampf((i - 8.0) / 82.0, 0.0, 1.0))


## Shield ceiling: Engineering powers the emitters.
func shield_cap() -> float:
	return SHIELD_MAX * clampf(integrity[Sec.ENGINEERING] / 80.0, 0.0, 1.0)


## Red alert: shields down, a section badly hurt, or the core going.
func red_alert() -> bool:
	return not shield_online or lowest() < 35.0 or core_breach >= 0.0


## Applies `amount` hull damage at local point `p` (m). Returns what the
## shield took (for the bubble flash) and what reached the hull.
func hit(amount: float, p: Vector2) -> Dictionary:
	since_hit = 0.0
	var res := {"shield": 0.0, "hull": 0.0, "sec": section_at(p), "shield_fell": false, "breach": false}
	var through := amount
	if shield_online and shield > 0.0:
		var want := amount * SHIELD_COST
		var used := minf(shield, want)
		shield -= used
		res.shield = used
		through = amount * BLEED + (want - used) / SHIELD_COST
		shield_hits.append({"pos": p, "t": 0.0, "power": clampf(amount / 12.0, 0.25, 1.0)})
		if shield_hits.size() > 6:
			shield_hits.pop_front()
		if shield <= 0.01:
			shield = 0.0
			shield_online = false
			res.shield_fell = true
	if through > 0.01:
		var sec: int = res.sec
		integrity[sec] = maxf(0.0, integrity[sec] - through * FRAGILITY)
		res.hull = through
		if through > 2.2:
			res.breach = _add_breach(p, through, sec)
		if sec == Sec.ENGINEERING and integrity[sec] <= 0.0 and core_breach < 0.0:
			core_breach = CORE_BREACH_TIME
	return res


func _add_breach(p: Vector2, dmg: float, sec: int) -> bool:
	var size := clampf(1.2 + dmg * 0.18, 1.2, 6.0)
	# Hits close together widen one breach instead of stacking marks.
	for b in breaches:
		if (b.pos as Vector2).distance_to(p) < float(b.size) * 0.8:
			b.size = minf(7.0, float(b.size) + size * 0.35)
			b.heat = 1.0
			return false
	if breaches.size() >= MAX_BREACHES:
		var smallest := 0
		for i in breaches.size():
			if float(breaches[i].size) < float(breaches[smallest].size):
				smallest = i
		breaches.remove_at(smallest)
	breaches.append({"pos": p, "size": size, "heat": 1.0, "sec": sec, "seed": _rng.randi() % 997})
	return true


## Is this breach venting atmosphere right now? (Its section is badly hurt.)
func venting(b: Dictionary) -> bool:
	return float(b.size) >= 1.8 and integrity[int(b.sec)] < 70.0


## Per-tick upkeep: shield regen, breach cooling, nacelle sputter, the core
## breach clock. `docked` = clamped in the berth (repairs run).
func tick(delta: float, docked: bool) -> void:
	since_hit += delta
	for h in shield_hits:
		h.t = float(h.t) + delta
	while not shield_hits.is_empty() and float(shield_hits[0].t) > 1.6:
		shield_hits.pop_front()
	for b in breaches:
		b.heat = maxf(0.0, float(b.heat) - delta * 0.12)
	if docked:
		_repair(delta)
	else:
		var cap := shield_cap()
		var eng := eff(Sec.ENGINEERING)
		if since_hit > REGEN_DELAY and eng > 0.0 and shield < cap:
			shield = minf(cap, shield + REGEN_RATE * eng * delta)
			if not shield_online and shield >= 25.0:
				shield_online = true
	if core_breach >= 0.0:
		core_breach = maxf(0.0, core_breach - delta)
	_tick_sputter(delta)


func _repair(delta: float) -> void:
	shield = minf(SHIELD_MAX, shield + 30.0 * delta)
	if shield >= 25.0:
		shield_online = true
	for i in integrity.size():
		integrity[i] = minf(100.0, integrity[i] + 6.0 * delta)
	core_breach = -1.0
	# Patched breaches shrink away once their section is sound again.
	for i in range(breaches.size() - 1, -1, -1):
		var b := breaches[i]
		if integrity[int(b.sec)] > 92.0:
			b.size = float(b.size) - delta * 1.2
			if float(b.size) <= 0.2:
				breaches.remove_at(i)


func _tick_sputter(delta: float) -> void:
	for k in 2:
		var sec := Sec.NACELLE_P if k == 0 else Sec.NACELLE_S
		var i := integrity[sec]
		_sputter_t[k] -= delta
		if _sputter_t[k] > 0.0:
			continue
		if i >= 40.0 or i < 8.0:
			sputter[k] = 1.0
			_sputter_t[k] = 0.3
			continue
		# The worse the nacelle, the more often (and longer) it cuts out.
		var bad := 1.0 - i / 40.0
		if sputter[k] > 0.5 and _rng.randf() < 0.25 + 0.5 * bad:
			sputter[k] = 0.0
			_sputter_t[k] = _rng.randf_range(0.05, 0.12 + 0.35 * bad)
		else:
			sputter[k] = 1.0
			_sputter_t[k] = _rng.randf_range(0.1, 0.9 - 0.6 * bad)


func reset() -> void:
	for i in integrity.size():
		integrity[i] = 100.0
	shield = SHIELD_MAX
	shield_online = true
	since_hit = 99.0
	core_breach = -1.0
	breaches.clear()
	shield_hits.clear()
	sputter = Vector2.ONE
