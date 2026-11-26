class_name OnFootDirector
extends Node
## Runs the "on foot" layer of the game: getting out of a docked ship,
## walking around the pad, going into an interior and back, and boarding.
##
##   FLIGHT ──X (docked)──▶ EXTERIOR ──airlock──▶ INTERIOR
##      ▲                     │  ▲                   │
##      └──E at the hatch─────┘  └─────airlock───────┘
##
## Design (see README "On foot"):
##  * Exterior = the SAME world, zoomed in. The station is already loaded and
##    simulated, so stepping out is a camera move (one continuous zoom, no
##    loading, traffic keeps flying past). Flight-only systems (race, damage,
##    boundary, docking, flight HUD) are paused while you walk; only small
##    on-foot pieces are added: the walker, a detailed ship model (LOD swap)
##    and the pad "site" (railings, airlock, props).
##  * Interior = a SEPARATE scene (level) loaded when you go in. It is a
##    different space with its own lighting, so instead of keeping the whole
##    station running behind it we suspend the flight world (process off,
##    hidden, physics bodies removed from the simulation) and add the
##    interior. Coming out resumes the world exactly as it was. The interior
##    scene is preloaded on a background thread while you walk to the door,
##    so the swap behind the fade has no hitch.
##  * Interior state (lights, shutters...) is saved here when you leave and
##    restored when you return, so the interior itself can be freed.

enum State { FLIGHT, BUSY, EXTERIOR, INTERIOR }

const ZOOM := 8.5                ## on-foot camera zoom (flight rests at ~1.0)
const BLEND := 1.7               ## seconds for the zoom in/out
## Flight systems paused while on foot (names under Main/Systems).
const FLIGHT_SYSTEMS := [&"DamageSystem", &"RaceSystem", &"DockingSystem", &"BoundarySystem", &"FlightGuide"]
## HUD widgets that only make sense while flying (names under Main/HUD).
const FLIGHT_HUD := [&"DamageVignette", &"GatePointer", &"CenterStatus", &"FlightPanel", &"RacePanel", &"Radar"]
## Main's children that stay alive inside interiors.
const KEEP_INSIDE := [&"SpaceBackground", &"CameraRig", &"HUD", &"OnFoot"]

var state := State.FLIGHT
var walker: Walker
## The ship you're flying, or the one you just got out of.
var _vehicle: RigidBody2D
var hud: OnFootHUD
var landed: LandedShip
var pad: Area2D
var pad_name := ""

var _main: Node
var _dock: DockingSystem
var _site_root: Node2D
var _extras: Node2D
var _interior_root: Node2D
var _interior: InteriorLevel
var _interior_path := ""
var _loading_path := ""
var _packed := {}                ## path -> PackedScene (cached for re-entry)
var _states := {}                ## path -> saved interior state
var _suspended := {}             ## Node -> [process_mode, visible or null]
var _engine_db := 0.0
var _engine_tween: Tween
var _hatch_mark: Node2D
var _shown_hint := false
var _petrel_tip_shown := false
var _dark_hint_shown := false


func _ready() -> void:
	_main = get_parent()
	add_to_group(&"on_foot_director")
	hud = OnFootHUD.new()
	hud.name = "OnFootHUD"
	add_child(hud)
	_site_root = Node2D.new()
	_site_root.name = "Site"
	add_child(_site_root)
	_interior_root = Node2D.new()
	_interior_root.name = "Interior"
	add_child(_interior_root)
	if Game.cmd.has("dock-at"):
		_harness_dock.call_deferred(String(Game.cmd["dock-at"]))
	if Game.cmd.has("perf"):
		_perf_log()
	if Game.cmd.has("fly"):
		_harness_fly.call_deferred(String(Game.cmd["fly"]))


func _exit_tree() -> void:
	# Collect a background load that was never used (otherwise it leaks).
	if _loading_path != "":
		ResourceLoader.load_threaded_get(_loading_path)
		_loading_path = ""
	_packed.clear()
	OnFootArt.cleanup()


# ================================================================ per frame

func _process(_delta: float) -> void:
	if _dock == null:
		_dock = get_tree().get_first_node_in_group(&"docking_system") as DockingSystem
	match state:
		State.FLIGHT:
			hud.target = null
			if Input.is_action_just_pressed(&"disembark"):
				if can_exit():
					disembark()
				elif GameplayUtil.player_alive() and Game.player.has_method(&"disembark_hint"):
					var hint := String(Game.player.call(&"disembark_hint"))
					if hint != "":
						Game.toast(hint, 2.0)
		State.EXTERIOR, State.INTERIOR:
			var t := _pick_target() if walker and walker.controls_enabled else null
			hud.target = t
			if t and Input.is_action_just_pressed(&"interact"):
				t.interact(walker)
			if state == State.INTERIOR:
				_dark_room_hint()
		_:
			hud.target = null


## Closest usable thing within reach, preferring what you're facing.
func _pick_target() -> Interactable:
	var best: Interactable = null
	var best_score := INF
	var wp := walker.global_position
	var fwd := Vector2.from_angle(walker.facing)
	for n in get_tree().get_nodes_in_group(&"interactable"):
		var it := n as Interactable
		if it == null or not it.can_use(walker):
			continue
		var to := it.reach_point() - wp
		var d := to.length() / Game.PX_PER_M
		if d > it.reach_m:
			continue
		var behind := 0.0
		if d > 0.4:
			behind = (1.0 - fwd.dot(to / (d * Game.PX_PER_M))) * 0.5
		var score := d + behind * 1.2
		if score < best_score:
			best_score = score
			best = it
	return best


func _dark_room_hint() -> void:
	if _dark_hint_shown or walker == null or walker.flashlight_on or _interior == null:
		return
	# Standing in a room whose lights are off? Suggest the flashlight once.
	for room in _interior.find_children("*", "InteriorRoom", true, false):
		var r := (room as InteriorRoom).rect_global()
		if not r.has_point(walker.global_position):
			continue
		for l in _interior.find_children("*", "RoomLight", true, false):
			if (l as RoomLight).on and r.has_point((l as RoomLight).global_position):
				return
		_dark_hint_shown = true
		hud.show_hint("F:Flashlight|E:Light switch by the door", 7.0)
		return


# ============================================================== disembark

## Can the pilot get out right now (docked on a pad, or the shuttle anchored)?
func can_exit() -> bool:
	return state == State.FLIGHT and GameplayUtil.player_alive() \
		and Game.player.has_method(&"can_disembark") and bool(Game.player.call(&"can_disembark"))


func disembark() -> void:
	if not can_exit():
		return
	var ship := Game.player as RigidBody2D
	var loc := WalkSite.locate(get_tree(), ship.global_position)
	if loc.is_empty():
		Game.toast("Nothing to stand on here  ·  land on a pad or a station deck", 2.5)
		return
	state = State.BUSY
	_vehicle = ship
	ship.call(&"park")
	Game.mode = Game.Mode.ON_FOOT
	_set_flight_layer(false)
	_fade_engine(true)
	GameplayUtil.play_oneshot(self, GameplayUtil.load_audio("ui_click.wav"), -10.0, 0.8, &"UI")

	# Level-of-detail swap: detailed landed model in, flight sprite out.
	landed = ship.call(&"landed_model") as LandedShip
	landed.modulate.a = 0.0
	_hatch_mark = _mark_on(landed)
	var vis := ship.get_node_or_null(^"Visuals") as CanvasItem
	var tw := create_tween().set_parallel()
	tw.tween_property(landed, ^"modulate:a", 1.0, 0.8).set_delay(0.35)
	if vis:
		tw.tween_property(vis, ^"modulate:a", 0.0, 0.6).set_delay(0.55)

	_build_site(loc)
	_site_root.modulate.a = 0.0
	create_tween().tween_property(_site_root, ^"modulate:a", 1.0, 1.0).set_delay(0.6)
	var cam := Game.camera as CameraRig
	if cam:
		cam.set_focus(_hatch_mark, ZOOM, BLEND)
	_tween_depth(0.0, BLEND)

	await get_tree().create_timer(BLEND * 0.75, false).timeout
	if vis:
		vis.visible = false
	landed.open_hatch(1.1)
	await landed.hatch_finished
	walker = Walker.new()
	walker.name = "Walker"
	walker.controls_enabled = false
	walker.helmet = true
	add_child(walker)
	walker.place(landed.door_global(), landed.outward_angle())
	walker.modulate.a = 0.0
	create_tween().tween_property(walker, ^"modulate:a", 1.0, 0.25)
	if cam:
		cam.set_focus(walker, ZOOM, BLEND)
	await _walk(landed.foot_global(), 1.3)
	walker.controls_enabled = true
	state = State.EXTERIOR
	_show_site_card("Vacuum outside  ·  mag-boots on  ·  suit sealed")
	if not _shown_hint:
		_shown_hint = true
		hud.show_hint("WASD:Walk|Shift:Run|E:Use|F:Flashlight|H:Help", 10.0)
	Game.disembarked.emit(pad_name)
	if _extras and _extras.has_method(&"get_interior_path"):
		_preload(_extras.call(&"get_interior_path"))


func _mark_on(model: Node2D) -> Node2D:
	var m := model.get_node_or_null(^"HatchMark") as Node2D
	if m == null:
		m = Node2D.new()
		m.name = "HatchMark"
		model.add_child(m)
	m.global_position = model.call(&"door_global")
	m.position += Vector2(0, -8)
	return m


func _show_site_card(sub: String) -> void:
	hud.show_location("%s  ·  MERIDIAN STATION" % pad_name.to_upper(), sub)


# ================================================================== board

## Board any parked ship in reach (called by its landed model's interactable).
func board(ship: RigidBody2D = null) -> void:
	if ship == null:
		ship = _vehicle
	if state != State.EXTERIOR or ship == null or not ship.has_method(&"landed_model"):
		return
	state = State.BUSY
	var model := ship.call(&"landed_model") as LandedShip
	walker.controls_enabled = false
	if model.hatch_t < 0.95:
		model.open_hatch(0.9)
		await model.hatch_finished
	await _walk(model.foot_global(), 1.6)
	await _walk(model.door_global(), 1.1)
	create_tween().tween_property(walker, ^"modulate:a", 0.0, 0.2)
	var cam0 := Game.camera as CameraRig
	if cam0:
		cam0.set_focus(_mark_on(model), ZOOM, BLEND)   # look at the ship, not the departing walker
	await get_tree().create_timer(0.2, false).timeout
	walker.queue_free()
	walker = null
	model.close_hatch(1.0)
	await model.hatch_finished

	# This ship is now yours; the one you came in (if different) stays parked.
	_vehicle = ship
	ship.call(&"take_control")
	var vis := ship.get_node_or_null(^"Visuals") as CanvasItem
	var cam := Game.camera as CameraRig
	if cam:
		cam.clear_focus(BLEND)
	_tween_depth(1.0, BLEND)
	if vis:
		vis.visible = true
		vis.modulate.a = 0.0
	var tw := create_tween().set_parallel()
	if vis:
		tw.tween_property(vis, ^"modulate:a", 1.0, 0.6).set_delay(0.3)
	tw.tween_property(model, ^"modulate:a", 0.0, 0.7).set_delay(0.5)
	tw.tween_property(_site_root, ^"modulate:a", 0.0, 0.8)
	_fade_engine(false)
	await get_tree().create_timer(BLEND, false).timeout
	ship.call(&"drop_landed_model")
	landed = null
	_free_site()
	_set_flight_layer(true)
	Game.mode = Game.Mode.FLIGHT
	ship.call(&"on_boarded")
	state = State.FLIGHT
	if ship is ShuttleShip and not _petrel_tip_shown:
		_petrel_tip_shown = true
		Game.toast("PETREL  ·  flies like the WREN, heavier · A/D turn in place · Shift/Ctrl throttle · Space hover / land · LMB hook · RMB reel · L lights · H help", 8.0)
	else:
		Game.toast("%s  ·  welcome aboard" % String(ship.get(&"vehicle_name")).to_upper(), 3.0)
	Game.boarded.emit(pad_name)


# ============================================================== interiors

func _enter_interior() -> void:
	if state != State.EXTERIOR or _extras == null:
		return
	var path: String = _extras.call(&"get_interior_path")
	if path == "":
		return
	state = State.BUSY
	walker.controls_enabled = false
	var door: SlidingDoor = _extras.get(&"door")
	_extras.call(&"set_cycling", true)
	door.open()
	await _walk(_extras.call(&"outside_point"), 1.4)
	while not door.is_open():
		await get_tree().process_frame
	walker.auto_walk(_extras.call(&"inside_point"), 1.3)
	await get_tree().create_timer(0.35, false).timeout
	await hud.fade_to(1.0, 0.4).finished

	# ---- swap levels behind the fade
	var packed := _packed_scene(path)
	_interior = packed.instantiate() as InteriorLevel
	_interior_path = path
	_interior.position = _extras.global_position    # the cut-away sits where the pier really is
	_suspend_world(true)
	_interior_root.add_child(_interior)
	if _states.has(path):
		_interior.load_state(_states[path])
	door.close()
	_extras.call(&"set_cycling", false)
	var al := _interior.get_airlock() as Airlock
	walker.place(al.arrival_global(), 0.0)
	walker.set_flashlight_energy(1.25)
	(Game.camera as CameraRig).snap_focus()
	var amb := _ambient()
	if amb:
		amb.set_level_offset(_interior.music_offset_db, 2.0)
	al.exit_requested.connect(_leave_interior)
	var outer := al.get_node_or_null(al.outer_door) as SlidingDoor
	if outer:
		outer.snap(1.0)
	al.cycle_in()
	_dark_hint_shown = false
	await hud.fade_to(0.0, 0.5).finished
	walker.controls_enabled = true
	state = State.INTERIOR
	hud.show_location(_interior.interior_name.to_upper(), "Airlock cycling  ·  equalising pressure")
	Game.entered_interior.emit(_interior.interior_name)
	await al.cycle_done
	if walker:
		walker.helmet = false
		Game.toast("Pressure nominal  ·  helmet stowed", 2.5)


func _leave_interior() -> void:
	if state != State.INTERIOR or _interior == null:
		return
	state = State.BUSY
	walker.controls_enabled = false
	walker.helmet = true
	var al := _interior.get_airlock() as Airlock
	al.cycle_out()
	var outer := al.get_node_or_null(al.outer_door) as SlidingDoor
	await get_tree().create_timer(1.2, false).timeout
	if outer:
		outer.open()
		walker.auto_walk(outer.global_position + Vector2(-6, 0), 1.2)
	await get_tree().create_timer(0.5, false).timeout
	await hud.fade_to(1.0, 0.45).finished

	var iname := _interior.interior_name
	_states[_interior_path] = _interior.save_state()
	_interior.queue_free()
	_interior = null
	_suspend_world(false)
	var amb := _ambient()
	if amb:
		amb.set_level_offset(0.0, 2.0)
	var door: SlidingDoor = _extras.get(&"door")
	door.snap(1.0)
	door.close()
	walker.place(_extras.call(&"outside_point"), PI)
	walker.set_flashlight_energy(0.5)
	(Game.camera as CameraRig).snap_focus()
	await hud.fade_to(0.0, 0.5).finished
	walker.controls_enabled = true
	state = State.EXTERIOR
	_show_site_card("Back outside  ·  suit sealed")
	Game.exited_interior.emit(iname)


# ================================================================ helpers

## Scripted walk; resolves when the walker arrives (or is gone).
func _walk(to: Vector2, speed: float) -> void:
	if walker == null:
		return
	var done := [false]
	walker.auto_walk(to, speed, func() -> void: done[0] = true)
	var guard := 0.0
	while not done[0] and walker != null and guard < 6.0:
		await get_tree().process_frame
		guard += get_process_delta_time()


func _build_site(loc: Dictionary) -> void:
	_free_site()
	var site := WalkSite.new()
	site.name = "WalkSite"
	_site_root.add_child(site)
	if loc.kind == "pad":
		pad = loc.pad
		var extra: String = loc.extras
		if extra != "":
			_extras = (load(extra) as PackedScene).instantiate() as Node2D
			_site_root.add_child(_extras)
			if _extras.has_signal(&"enter_requested"):
				_extras.connect(&"enter_requested", _enter_interior)
		site.setup_pad(pad, _extras)
		pad_name = String(_extras.call(&"get_title")) if _extras and _extras.has_method(&"get_title") else site.title
	else:
		pad = null
		site.setup_deck(loc.polys, String(loc.get("title", "Station deck")))
		pad_name = site.title


func _free_site() -> void:
	for c in _site_root.get_children():
		c.queue_free()
	_extras = null


## Background-thread load of the interior while you walk to the door.
func _preload(path: String) -> void:
	if path == "" or _packed.has(path) or _loading_path == path:
		return
	if ResourceLoader.load_threaded_request(path) == OK:
		_loading_path = path


func _packed_scene(path: String) -> PackedScene:
	if not _packed.has(path):
		var ps: PackedScene
		if _loading_path == path:
			ps = ResourceLoader.load_threaded_get(path) as PackedScene   # waits if still loading
			_loading_path = ""
		else:
			ps = load(path) as PackedScene
		_packed[path] = ps
	return _packed[path]


func _ambient() -> AmbientAudio:
	return _main.get_node_or_null(^"Systems/AmbientAudio") as AmbientAudio


## Pause/hide everything that only matters while flying (and back).
func _set_flight_layer(on: bool) -> void:
	for n in FLIGHT_SYSTEMS:
		var node := _main.get_node_or_null(NodePath("Systems/%s" % n))
		if node:
			_suspend(node, not on)
	for n in FLIGHT_HUD:
		var node := _main.get_node_or_null(NodePath("HUD/%s" % n))
		if node:
			_suspend(node, not on)
	var tp := _main.get_node_or_null(^"TuningPanel")
	if tp:
		_suspend(tp, not on)


## Inside an interior the whole station is suspended (only the background,
## camera, HUD, music and this director keep running).
func _suspend_world(on: bool) -> void:
	for c in _main.get_children():
		if c.name in KEEP_INSIDE:
			continue
		if c.name == &"Systems":
			for s in c.get_children():
				if s.name != &"AmbientAudio":
					_suspend(s, on)
			continue
		_suspend(c, on)
	_suspend(_site_root, on)


## process_mode DISABLED stops _process/_physics_process/input, pauses audio
## players, and removes physics bodies from the simulation (CollisionObject
## disable_mode REMOVE) until re-enabled. Visibility is handled too, including
## drawables under plain Nodes (e.g. Systems/DockingSystem's ring).
## Reference counted: the flight layer and the interior both suspend some of
## the same nodes, and a node only resumes when nobody wants it suspended.
func _suspend(node: Node, on: bool) -> void:
	if on:
		if _suspended.has(node):
			_suspended[node][2] += 1
			return
		var vis: Variant = null
		var hidden_children: Array = []
		if node is CanvasItem or node is CanvasLayer:
			vis = node.get(&"visible")
			node.set(&"visible", false)
		else:
			for c in node.get_children():
				if c is CanvasItem and (c as CanvasItem).visible:
					(c as CanvasItem).visible = false
					hidden_children.append(c)
		_suspended[node] = [node.process_mode, vis, 1, hidden_children]
		node.process_mode = Node.PROCESS_MODE_DISABLED
	else:
		if not _suspended.has(node):
			return
		var st: Array = _suspended[node]
		st[2] -= 1
		if st[2] > 0:
			return
		_suspended.erase(node)
		node.process_mode = st[0]
		if st[1] != null:
			node.set(&"visible", st[1])
		for c in st[3]:
			if is_instance_valid(c):
				(c as CanvasItem).visible = true


func _tween_depth(to: float, time: float) -> void:
	create_tween().tween_method(func(v: float) -> void: LevelArt.depth_amount = v, LevelArt.depth_amount, to, time).set_trans(Tween.TRANS_SINE)


## The ship powers down while you're out (its engine idle hum fades) and
## spools back up when you board: we fade the Engine bus.
func _fade_engine(out: bool) -> void:
	var idx := AudioServer.get_bus_index(&"Engine")
	if idx < 0:
		return
	if out:
		_engine_db = AudioServer.get_bus_volume_db(idx)
	if _engine_tween:
		_engine_tween.kill()
	var from := AudioServer.get_bus_volume_db(idx)
	var to := -60.0 if out else _engine_db
	_engine_tween = create_tween()
	_engine_tween.tween_method(func(v: float) -> void: AudioServer.set_bus_volume_db(idx, v), from, to, 1.6 if out else 1.0)


# ================================================================ harness

## --perf: print frame time / draw calls every 2 s (compare flight, pad, interior).
func _perf_log() -> void:
	while is_inside_tree():
		await get_tree().create_timer(2.0, false, false, true).timeout
		print("[perf] state=%s fps=%d frame_ms=%.2f process_ms=%.2f physics_ms=%.2f draw_calls=%d objects=%d nodes=%d" % [
			State.keys()[state], Engine.get_frames_per_second(),
			1000.0 / maxf(Engine.get_frames_per_second(), 1.0),
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])


## --fly=petrel: start aboard that ship (where it is parked), the WREN parked.
## --fly=petrel@x_px,y_px,deg also moves it there (flying) first.
func _harness_fly(arg: String) -> void:
	var id := arg.get_slice("@", 0)
	var at := arg.get_slice("@", 1) if arg.contains("@") else ""
	await get_tree().create_timer(0.3, false).timeout
	for n in get_tree().get_nodes_in_group(&"player_ship"):
		if n.has_method(&"ship_id") and String(n.call(&"ship_id")) == id and n != Game.player:
			var old := Game.player
			old.call(&"park")
			var ov := old.get_node_or_null(^"Visuals") as CanvasItem
			if ov:
				ov.visible = false
			old.call(&"landed_model")
			n.call(&"take_control")
			n.call(&"drop_landed_model")
			var vis := n.get_node_or_null(^"Visuals") as CanvasItem
			if vis:
				vis.visible = true
				vis.modulate.a = 1.0
			n.call(&"on_boarded")
			_vehicle = n
			if at != "":
				var p := at.split(",")
				n.call(&"respawn_at", Transform2D(deg_to_rad(float(p[2]) if p.size() > 2 else 0.0), Vector2(float(p[0]), float(p[1]))))
			if Game.camera and Game.camera.has_method(&"snap"):
				Game.camera.call(&"snap")
			return
	push_warning("--fly: no ship with id %s" % id)


## --dock-at=Pad 2 (or 2): put the ship on that pad and dock immediately.
## With --on-foot it also gets out. For tests and screenshots.
func _harness_dock(which: String) -> void:
	# "2", "Pad2", "Pad 2" or a full name like "Hangar Bay" / "HangarBay".
	var key := which.to_lower().replace(" ", "").replace("_", "")
	if key.is_valid_int():
		key = "pad" + key
	await get_tree().create_timer(0.3, false).timeout
	var target: Area2D
	var want := which
	for n in get_tree().get_nodes_in_group(&"docking_pad"):
		if String(n.get_meta(&"pad_name", "")).to_lower().replace(" ", "") == key:
			target = n
	if target == null or not GameplayUtil.player_valid():
		push_warning("--dock-at: no pad named %s" % want)
		return
	var ship := Game.player
	if not (target as Area2D).overlaps_body(ship) and ship.has_method(&"respawn_at"):
		ship.call(&"respawn_at", Transform2D(target.global_rotation, target.global_position))
		await get_tree().create_timer(0.4, false).timeout
	if _dock == null:
		_dock = get_tree().get_first_node_in_group(&"docking_system") as DockingSystem
	_dock.force_dock(target)
	if Game.cmd.has("on-foot"):
		await get_tree().create_timer(0.6, false).timeout
		disembark()
