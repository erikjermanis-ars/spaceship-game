@tool
class_name FreightReceiver
extends StationModule
## A freight intake: somewhere to deliver cargo containers.
##
## A below-deck set-down pad with a hazard border, a conveyor lane and an
## intake hatch under a hood on its far (-Y) edge. Nothing here collides: ships
## fly over it and containers slide across it. Any container that rests inside
## the border (slower than 1 m/s for 0.6 s) is taken: it is drawn to the hatch,
## shrinks away and is freed. So it works whether you unload right over the pad
## or shove a container in with the hull. A soft mag-brake slows cargo inside
## the border, otherwise a container pushed out of a hold at 1.5 m/s would
## coast straight across.
##
## Each delivery is tallied in FreightLedger and announced on
## Game.cargo_delivered(brand, receiver_id, slots). The module knows nothing
## about the station around it: place as many as you like (group
## `freight_receiver`). Local origin = pad centre, metres; approach from +Y.

## Key of this receiver in FreightLedger and Game.cargo_delivered.
@export var receiver_id := "intake"
@export var title := "FREIGHT INTAKE":
	set(v): title = v; queue_rebuild()
## Brands (container liveries) taken here. Empty = anything.
@export var accepts: PackedStringArray = PackedStringArray():
	set(v): accepts = v; queue_rebuild()
## Brands this receiver turns away even though it takes everything else
## (Vesper Rock ships ore out: it won't take it back in).
@export var rejects: PackedStringArray = PackedStringArray()
## The marked set-down area: containers inside it are taken.
@export var size_m := Vector2(48, 30):
	set(v): size_m = v; queue_rebuild()
## Length of the below-deck conveyor trunk that runs on from the hatch (toward
## whatever the freight is for). 0 = none.
@export var trunk_m := 0.0:
	set(v): trunk_m = v; queue_rebuild()

const MAX_SPEED_MPS := 1.0
const DWELL_S := 0.6
## Mag-brake on containers inside the border: F = -m * this * v.
const BRAKE_PER_S := 1.5
const TAKE_TIME_S := 0.9
const HATCH_HALF_M := 8.0
const LANE_HALF_M := 4.2

var _area: Area2D
var _fx: Node2D
var _inside := {}            # instance id -> {body, t, rejected}
var _t := 0.0
var _accum := 0.0
var _flash := 0.0            # 1 -> 0 after a delivery (green) or a refusal (amber)
var _flash_col := Color.WHITE
var _snd_accept: AudioStream
var _snd_deny: AudioStream


# ================================================================== art

func _build() -> void:
	var hx := size_m.x * 0.5
	var hy := size_m.y * 0.5
	var hw := minf(HATCH_HALF_M, hx - 6.0)
	var D := Band.DECK
	# --- conveyor trunk running on from the hatch (drawn first: the pad covers its end)
	if trunk_m > 0.0:
		var y0 := -hy - 5.0 - trunk_m
		var y1 := -hy - 2.0
		fill(D, A.rect_m(-5.0, y0, 5.0, y1), Color("141B25"))
		fill(D, A.rect_m(-3.8, y0, 3.8, y1), Color("1C2532"))
		var rollers := PackedVector2Array()
		var y := y0 + 1.0
		while y < y1:
			rollers.append_array([m(-3.6, y), m(3.6, y)])
			y += 2.0
		lines(D, rollers, Color("2B384B"), 1.5)
		for s: float in [-1.0, 1.0]:
			line(D, m(s * 5.0, y0), m(s * 5.0, y1), Color("4A5D75"), 2.0)
		var n := maxi(1, int(trunk_m / 14.0))
		for i in n:
			lamp(m(-5.0 if i % 2 == 0 else 5.0, lerpf(y0, y1, (i + 0.5) / n)), A.CYAN, 18.0, 0)
	# --- pad, with an apron on the approach side for the name
	deck(A.rounded_rect(Rect2(m(-hx - 3.0, -hy - 5.0), m(size_m.x + 6.0, size_m.y + 16.0)), 30.0),
		4.0, Color("1A2330"), Color("222D3E"), Color("2B384B"), Color("64798F"))
	# --- hazard border = the acceptance zone (open where the hatch is)
	var b := 2.0
	hazard(D, A.rect_m(-hx, -hy, -hw - 1.4, -hy + b), 1.1)
	hazard(D, A.rect_m(hw + 1.4, -hy, hx, -hy + b), 1.1)
	hazard(D, A.rect_m(-hx, hy - b, hx, hy), 1.1)
	hazard(D, A.rect_m(-hx, -hy + b, -hx + b, hy - b), 1.1, -PI * 0.25)
	hazard(D, A.rect_m(hx - b, -hy + b, hx, hy - b), 1.1, -PI * 0.25)
	# --- conveyor lane up the middle to the hatch
	var lip := -hy + 5.2
	fill(D, A.rect_m(-LANE_HALF_M, lip, LANE_HALF_M, hy - b), Color("161D28"))
	var rl := PackedVector2Array()
	var ry := lip + 0.8
	while ry < hy - b - 0.4:
		rl.append_array([m(-LANE_HALF_M + 0.5, ry), m(LANE_HALF_M - 0.5, ry)])
		ry += 1.3
	lines(D, rl, Color("2F3C50"), 1.5)
	for s: float in [-1.0, 1.0]:
		line(D, m(s * LANE_HALF_M, lip), m(s * LANE_HALF_M, hy - b), Color("5A6D85"), 2.5)
	# --- set-down bays either side of the lane (corner marks, sized for a 12 m box)
	var bay_w := hx - b - LANE_HALF_M - 3.0
	if bay_w >= 8.0:
		var rows := maxi(1, int((size_m.y - 2.0 * b - 3.0) / 6.5))
		for s: float in [-1.0, 1.0]:
			var cx := s * (LANE_HALF_M + 1.5 + bay_w * 0.5)
			for i in rows:
				var cy := lerpf(-hy + b + 4.0, hy - b - 4.0, (i + 0.5) / rows) if rows > 1 else 0.0
				_bay(Rect2(m(cx - bay_w * 0.5, cy - 2.0), m(bay_w, 4.0)))
	# --- intake hatch: steel frame, dark pit, depth slats, striped lip
	fill(D, A.rect_m(-hw - 1.0, -hy - 4.0, hw + 1.0, lip + 0.2), Color("3A4759"))
	fill(D, A.rect_m(-hw, -hy - 3.2, hw, lip - 0.9), Color("06090E"))
	for i in 5:
		var sy := lerpf(lip - 1.6, -hy - 2.6, i / 4.0)
		var inset := 0.4 + i * 0.35
		line(D, m(-hw + inset, sy), m(hw - inset, sy), Color(0.35, 0.5, 0.65, 0.5 - i * 0.09), 2.0)
	hazard(D, A.rect_m(-hw, lip - 0.9, hw, lip + 0.2), 0.8)
	outline(D, A.rect_m(-hw - 1.0, -hy - 4.0, hw + 1.0, lip + 0.2), Color("7C8FA6"), 2.0)
	glow(m(0.0, -hy + 1.0), Color(A.CYAN, 0.2), hw * PX * 1.6, Band.DECK_FX)
	# --- name on the apron, what it takes underneath
	text(D, m(0.0, hy + 4.4), title, 36, Color(0.82, 0.9, 1.0, 0.82))
	var takes := "ALL CARGO" if accepts.is_empty() else "  ·  ".join(accepts)
	text(D, m(0.0, hy + 8.0), "%s  ·  SET DOWN INSIDE THE STRIPES" % takes, 15, Color(0.7, 0.8, 0.92, 0.55), 0.0, false)
	# --- lights: cyan edge lamps, amber corner beacons, green lamps at the lip
	var nx := maxi(3, int(size_m.x / 8.0))
	var ny := maxi(2, int(size_m.y / 8.0))
	for i in nx:
		lamp(m(lerpf(-hx, hx, (i + 0.5) / nx), hy + 11.0), A.CYAN, 24.0, 0)
	for i in ny:
		for s: float in [-1.0, 1.0]:
			lamp(m(s * (hx + 3.0), lerpf(-hy, hy, (i + 0.5) / ny)), A.CYAN, 24.0, 0)
	for sx: float in [-1.0, 1.0]:
		lamp(m(sx * (hw + 1.0), lip + 0.2), A.NAV_GREEN, 26.0, 0)
		for sy: float in [-1.0, 1.0]:
			beacon(m(sx * (hx - 1.0), sy * (hy - 1.0)), A.AMBER, 60.0, 0.25 * (sx + 1.0) + 0.12 * (sy + 1.0), false, 0)
	# --- hood over the hatch (overhead: cargo slides under it)
	overhead(A.rect_m(-hw - 2.0, -hy - 6.0, hw + 2.0, -hy + 1.6), Color(0.78, 0.82, 0.88, 0.6))
	fill(Band.OVER, A.rect_m(-hw - 2.0, -hy + 0.8, hw + 2.0, -hy + 1.6), Color(1.0, 0.69, 0.0, 0.75))
	for s: float in [-1.0, 1.0]:
		lamp(m(s * (hw - 1.0), -hy - 2.0), A.WARM, 46.0, 2)


## Painted corner marks of one set-down bay.
func _bay(r: Rect2) -> void:
	var k := 14.0
	var col := Color(0.85, 0.92, 1.0, 0.3)
	for c: Vector2 in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var sx := 1.0 if c.x < r.get_center().x else -1.0
		var sy := 1.0 if c.y < r.get_center().y else -1.0
		polyline(Band.DECK, PackedVector2Array([c + Vector2(0, sy * k), c, c + Vector2(sx * k, 0)]), col, 2.5)


func _after_build() -> void:
	# The zone: a sensor for free props (containers), nothing else.
	_area = Area2D.new()
	_area.name = "IntakeZone"
	_area.collision_layer = 0
	_area.collision_mask = G.LAYER_PROPS
	_area.monitorable = false
	var cs := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = size_m * PX
	cs.shape = rs
	_area.add_child(cs)
	add_child(_area)
	_generated.append(_area)
	set_process(not Engine.is_editor_hint())
	set_physics_process(not Engine.is_editor_hint())
	if Engine.is_editor_hint():
		return
	add_to_group(&"freight_receiver")
	_inside.clear()
	_area.body_entered.connect(_on_body_entered)
	_area.body_exited.connect(func(body: Node2D) -> void: _inside.erase(body.get_instance_id()))
	# Live lights (chevrons marching into the hatch, the tally): one small
	# additive item at deck level, redrawn only while it is on screen.
	_fx = Node2D.new()
	_fx.name = "IntakeFX"
	_fx.z_as_relative = false
	_fx.z_index = G.Z_BELOW_DECK + 2
	_fx.material = A.add_material()
	_fx.draw.connect(_draw_fx)
	add_child(_fx)
	_generated.append(_fx)
	A.depth_layers.append([_fx, A.DECK_SCALE, Vector2.ZERO])
	_snd_accept = GameplayUtil.load_audio("delivery_accept.wav")
	_snd_deny = GameplayUtil.load_audio("cargo_deny.wav")


# ============================================================== receiving

## Does this receiver take containers of that brand?
func takes(brand: String) -> bool:
	for r in rejects:
		if r.nocasecmp_to(brand) == 0:
			return false
	if accepts.is_empty():
		return true
	for a in accepts:
		if a.nocasecmp_to(brand) == 0:
			return true
	return false


## The hatch (global px): where taken containers go.
func hatch_position() -> Vector2:
	return to_global(m(0.0, -size_m.y * 0.5 - 1.0))


func _on_body_entered(body: Node2D) -> void:
	if body is RigidBody2D and body.is_in_group(&"cargo_container"):
		_inside[body.get_instance_id()] = {"body": body, "t": 0.0, "rejected": false}


func _physics_process(delta: float) -> void:
	if _inside.is_empty():
		return
	var zone := Rect2(-size_m * 0.5 * PX, size_m * PX)
	for id: int in _inside.keys():
		var e: Dictionary = _inside[id]
		if not is_instance_valid(e.body) or not (e.body as Node).is_inside_tree():
			_inside.erase(id)
			continue
		var box: RigidBody2D = e.body
		# Its centre has to be inside the stripes, not just a corner.
		if box.freeze or not zone.has_point(to_local(box.global_position)):
			e.t = 0.0
			continue
		var v := box.linear_velocity
		if not box.sleeping:
			box.apply_central_force(-v * box.mass * BRAKE_PER_S)
		if v.length() > MAX_SPEED_MPS * PX:
			e.t = 0.0
			continue
		e.t += delta
		if e.t < DWELL_S:
			continue
		var brand := String(CargoHold.describe(box).brand)
		if takes(brand):
			_inside.erase(id)
			_accept(box)
		elif not e.rejected:
			# Told once; it can sit there until someone hauls it away.
			e.rejected = true
			_flash = 1.0
			_flash_col = A.AMBER
			_say(_snd_deny, -8.0)
			_game().toast("%s doesn't take %s" % [title, brand], 2.6)


func _accept(box: RigidBody2D) -> void:
	var it := CargoHold.describe(box)
	FreightLedger.record(receiver_id, it.brand, it.slots)
	# The body goes at once (the zone is free for the next one); its picture
	# rides the conveyor into the hatch.
	var from := global_transform.affine_inverse() * box.global_transform
	var g := CargoGhost.of(it)
	g.from_local = Transform2D(from.get_rotation(), from.origin)
	g.to_local = Transform2D(PI * 0.5, m(0.0, -size_m.y * 0.5 - 1.0))
	g.scale_to = 0.55
	g.duration = TAKE_TIME_S
	g.z_index = G.Z_PROPS
	add_child(g)
	box.queue_free()
	_flash = 1.0
	_flash_col = A.NAV_GREEN
	_say(_snd_accept, -4.0)
	var game := _game()
	game.cargo_delivered.emit(it.brand, receiver_id, it.slots)
	game.toast("DELIVERED  ·  %s  ·  %s" % [it.brand, title], 2.6)


func _say(s: AudioStream, db: float) -> void:
	if s == null:
		return
	var p := AudioStreamPlayer2D.new()
	p.stream = s
	p.bus = GameplayUtil.bus(&"SFX")
	p.volume_db = db
	p.max_distance = 1800.0
	p.position = m(0.0, -size_m.y * 0.5)
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


# ============================================================== live lights

func _process(delta: float) -> void:
	_t += delta
	_flash = maxf(0.0, _flash - delta / 1.4)
	_accum += delta
	if _accum < 1.0 / 20.0 or _fx == null:
		return
	_accum = 0.0
	# Only worth redrawing while the camera can see the pad.
	var vp := get_viewport()
	var view := vp.get_canvas_transform().affine_inverse() * Rect2(Vector2.ZERO, vp.get_visible_rect().size)
	var reach := size_m.length() * PX
	if view.grow(reach).has_point(global_position):
		_fx.queue_redraw()


func _draw_fx() -> void:
	var pen := OnFootPainter.new(_fx, 0.8)
	var hy := size_m.y * 0.5
	var hw := minf(HATCH_HALF_M, size_m.x * 0.5 - 6.0)
	var col := A.CYAN.lerp(_flash_col, _flash)
	var busy := 0.0
	for id in _inside:
		busy = maxf(busy, float(_inside[id].t) / DWELL_S)
	# Chevrons march up the lane into the hatch; faster while it is taking one.
	var y_in := hy - 3.2
	var y_out := -hy + 5.6
	var gap := 4.2
	var y := y_in - fmod(_t * (2.2 + 5.0 * _flash), gap)
	while y > y_out:
		var k := (y_in - y) / (y_in - y_out)
		var a := smoothstep(0.0, 0.18, k) * (1.0 - smoothstep(0.82, 1.0, k)) * (0.34 + 0.4 * _flash)
		# Two flat quads per chevron (additive: overlapping line caps would
		# show as a bright dot at the tip).
		for s: float in [-1.0, 1.0]:
			pen.fill(PackedVector2Array([m(0.0, y), m(s * 2.5, y + 1.3), m(s * 2.5, y + 1.95), m(0.0, y + 0.65)]), Color(col, a), false)
		y -= gap
	# Hatch lip: a light bar that fills while a container settles (the dwell).
	var lip := -hy + 5.9
	pen.line(m(-hw + 0.6, lip), m(hw - 0.6, lip), Color(col, 0.16 + 0.1 * sin(_t * 2.4)), 3.0)
	if busy > 0.02 and _flash <= 0.0:
		var w := (hw - 0.6) * clampf(busy, 0.0, 1.0)
		pen.line(m(-w, lip), m(w, lip), Color(A.CYAN, 0.8), 3.0)
	elif _flash > 0.0:
		pen.line(m(-hw + 0.6, lip), m(hw - 0.6, lip), Color(_flash_col, 0.9 * _flash), 4.0)
	# Tally beside the hatch.
	var n := FreightLedger.count(receiver_id)
	pen.text(m(hw + 2.2, -hy + 4.9), "RECEIVED  %02d" % n, 15.0, Color(col, 0.75), HORIZONTAL_ALIGNMENT_LEFT)
	pen.flush()
