class_name OnFootDirector
extends Node
## Runs the "on foot" layer of the game: getting out of a docked ship,
## walking around the pad, going into an interior and back, and boarding.
##
##   FLIGHT ──X (docked)──▶ EXTERIOR ──airlock──▶ INTERIOR ◀──gangway──▶ INTERIOR (frigate)
##      ▲                     │  ▲                   │                         │   ▲
##      └──E at the hatch─────┘  └─────airlock───────┘   FLIGHT (frigate) ◀──chair   X┘
##
## A frigate has no deck model: you board it on foot through a berth's
## gangway (an InteriorPortal from the station interior into the frigate's
## own) and fly it from the captain's chair (take_helm). X at its helm
## (leave_helm) puts you back on its bridge.
##
## A frigate also has a FLIGHT DECK. X in a small ship parked on it takes you
## straight into the frigate's interior, standing by your ship in the hangar
## (_disembark_to_hangar); E at that ship's hatch there flies it again
## (board_stowed). So the WREN and the PETREL travel with the frigate.
##
## Other links between interiors are InteriorPortals too: transit pods (a
## `ride`), and the lift along a frigate's keel (ride_lift, same interior).
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
const FLIGHT_SYSTEMS := [&"DamageSystem", &"RaceSystem", &"DockingSystem", &"BoundarySystem", &"FlightGuide", &"Weapons"]
## HUD widgets that only make sense while flying (names under Main/HUD).
const FLIGHT_HUD := [&"DamageVignette", &"GatePointer", &"CenterStatus", &"FlightPanel", &"RacePanel", &"Radar", &"ContractsPanel"]
## Main's children that stay alive inside interiors.
const KEEP_INSIDE := [&"SpaceBackground", &"CameraRig", &"HUD", &"OnFoot"]
## Systems that keep running indoors: the music bed, and the quantum drive
## (its star map is used at the bridge's nav table).
const KEEP_SYSTEMS := [&"AmbientAudio", &"JumpSystem", &"Contracts"]

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
var _states := {}                ## state key (path, plus the ship for a frigate's deck) -> saved state
var _state_key := ""
var _suspended := {}             ## Node -> [process_mode, visible or null]
var _engine_db := 0.0
var _engine_tween: Tween
var _hatch_mark: Node2D
var _shown_hint := false
var _petrel_tip_shown := false
var _dark_hint_shown := false
var _helm_hint_shown := false


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
	if Game.cmd.has("interior"):
		_harness_interior.call_deferred(String(Game.cmd["interior"]))
	if Game.cmd.has("walk-to"):
		# --walk-to=Marker: on entering an interior, start at that marker.
		Game.entered_interior.connect(func(_n: String) -> void:
			var m := _interior.get_node_or_null(NodePath(String(Game.cmd["walk-to"]))) as Node2D if _interior else null
			if m and walker:
				walker.place(m.global_position, m.global_rotation)
				(Game.camera as CameraRig).snap_focus())


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
				if can_exit() and _jump_idle():
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
	if ship.has_method(&"interior_scene"):
		leave_helm()
		return
	var host := _bay_host(ship)
	if host:
		_disembark_to_hangar(ship, host)
		return
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

## Through an airlock door from the deck. `entry` is whatever owns the door:
## the pad's extras scene (Pad 2's vestibule, the default) or an ExteriorDoor.
func _enter_interior(entry: Node2D = null) -> void:
	if entry == null:
		entry = _extras
	if state != State.EXTERIOR or entry == null:
		return
	var path: String = entry.call(&"get_interior_path")
	if path == "":
		return
	state = State.BUSY
	walker.controls_enabled = false
	var door: SlidingDoor = entry.get(&"door")
	entry.call(&"set_cycling", true)
	door.open()
	await _walk(entry.call(&"outside_point"), 1.4)
	while not door.is_open():
		await get_tree().process_frame
	walker.auto_walk(entry.call(&"inside_point"), 1.3)
	await get_tree().create_timer(0.35, false).timeout
	await hud.fade_to(1.0, 0.4).finished

	# ---- swap levels behind the fade
	_suspend_world(true)
	_install_interior(path)
	door.close()
	entry.call(&"set_cycling", false)
	var al := _interior.get_airlock() as Airlock
	if entry is ExteriorDoor:
		var named := _interior.get_node_or_null(NodePath((entry as ExteriorDoor).airlock_name)) as Airlock
		if named:
			al = named
	walker.place(al.arrival_global(), 0.0)
	walker.set_flashlight_energy(1.25)
	(Game.camera as CameraRig).snap_focus()
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
	_preload("res://scenes/onfoot/interiors/frigate_deck.tscn")
	await al.cycle_done
	if walker:
		walker.helmet = false
		Game.toast("Pressure nominal  ·  helmet stowed", 2.5)


## Out through airlock `al` (default: the interior's main one). An airlock
## with an `exit_point` lets you out there, on whatever pad or deck that is;
## otherwise you come out where you went in (Pad 2's airlock 7B).
func _leave_interior(al: Airlock = null) -> void:
	if state != State.INTERIOR or _interior == null:
		return
	if al == null:
		al = _interior.get_airlock() as Airlock
	if al == null:
		return
	state = State.BUSY
	walker.controls_enabled = false
	walker.helmet = true
	var exit_point := al.exit_point
	var exit_facing := al.exit_facing
	al.cycle_out()
	var outer := al.get_node_or_null(al.outer_door) as SlidingDoor
	await get_tree().create_timer(1.2, false).timeout
	if outer:
		outer.open()
		walker.auto_walk(outer.global_position + Vector2(-6, 0), 1.2)
	await get_tree().create_timer(0.5, false).timeout
	await hud.fade_to(1.0, 0.45).finished

	var iname := _interior.interior_name
	_drop_interior()
	_suspend_world(false)
	var amb := _ambient()
	if amb:
		amb.set_level_offset(0.0, 2.0)
	if exit_point != Vector2.ZERO:
		# This airlock opens onto a deck of its own: build the site there.
		var loc := WalkSite.locate(get_tree(), exit_point)
		if not loc.is_empty():
			_build_site(loc)
			_site_root.modulate.a = 1.0
		var out_door := _door_at(exit_point)
		if out_door:
			out_door.door.snap(1.0)
			out_door.door.close()
		walker.place(exit_point, exit_facing)
	else:
		if _extras == null:
			# We came in through the frigate's gangway: the pad outside this
			# airlock has no site yet (you never walked it).
			_build_pad_site("Pad 2")
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


# ========================================================== frigate & portals

## Builds an interior (cached PackedScene), places it, restores its state and
## wires its airlock (if it has one) to the way out.
func _install_interior(path: String, frigate: FrigateShip = null) -> void:
	var packed := _packed_scene(path)
	# A frigate's deck reads its ship from FrigateShip.aboard as it loads.
	FrigateShip.aboard = frigate
	_interior = packed.instantiate() as InteriorLevel
	_interior_path = path
	# Both frigates share one deck scene: their states are kept apart.
	_state_key = path if frigate == null else "%s|%s" % [path, frigate.vehicle_name]
	_interior.position = _interior_origin(_interior)
	_interior_root.add_child(_interior)
	if _states.has(_state_key):
		_interior.load_state(_states[_state_key])
	for n in _interior.find_children("*", "Node2D", true, false):
		var al := n as Airlock
		if al:
			al.exit_requested.connect(_leave_interior.bind(al))
	var amb := _ambient()
	if amb:
		amb.set_level_offset(_interior.music_offset_db, 2.0)


## Where an interior's origin goes: a frigate's deck rides with the ship,
## a pier cut-away sits where the pier really is.
func _interior_origin(il: InteriorLevel) -> Vector2:
	if il.anchor_to_frigate:
		var f := FrigateShip.aboard
		if f:
			return f.global_position
	if il.use_world_origin:
		return il.world_origin
	return _extras.global_position if _extras else Vector2.ZERO


## Saves the current interior's state and frees it.
func _drop_interior() -> void:
	if _interior == null:
		return
	_states[_state_key] = _interior.save_state()
	_interior.queue_free()
	_interior = null


## The frigate whose flight deck `ship` is parked on (null: it isn't on one).
func _bay_host(ship: Node2D) -> FrigateShip:
	for n in get_tree().get_nodes_in_group(&"frigate"):
		var f := n as FrigateShip
		if f and f != ship and f.alive and f.bay.contains(ship.global_position):
			return f
	return null


## No quantum jump in progress (nobody gets out mid-jump).
func _jump_idle() -> bool:
	var j := get_tree().get_first_node_in_group(&"jump_system")
	return j == null or not bool(j.call(&"busy"))


func _build_pad_site(pname: String) -> void:
	for n in get_tree().get_nodes_in_group(&"docking_pad"):
		if String(n.get_meta(&"pad_name", "")) == pname:
			_build_site(WalkSite.locate(get_tree(), (n as Node2D).global_position))
			_site_root.modulate.a = 1.0
			return


## Through an InteriorPortal into another interior: a berth's gangway to or
## from a frigate, or a transit pod (a `ride`: it plays the pod's journey).
func transfer(portal: InteriorPortal) -> void:
	if state != State.INTERIOR or walker == null:
		return
	var link := portal.resolve()
	if link.is_empty():
		return
	state = State.BUSY
	walker.controls_enabled = false
	var door := portal.get_door()
	if door:
		door.open()
		var guard := 0.0
		while not door.is_open() and guard < 3.0:
			await get_tree().process_frame
			guard += get_process_delta_time()
	# The portal belongs to the interior we're about to free: keep what we need.
	var walk_to := portal.to_global(portal.walk_in)
	await _walk(walk_to, 1.4)
	await hud.fade_to(1.0, 0.4).finished
	_drop_interior()
	if bool(link.ride):
		GameplayUtil.play_oneshot(self, GameplayUtil.load_audio("transit_pod.wav"), -5.0, 1.0)
		hud.show_location("MERIDIAN TRANSIT", "Pod under way  ·  next stop: %s" % String(link.note))
		await get_tree().create_timer(2.6, false).timeout
	_install_interior(String(link.scene), link.frigate as FrigateShip)
	var at := _interior.get_node_or_null(NodePath(String(link.arrival))) as Node2D
	walker.place(at.global_position if at else _interior.global_position, at.global_rotation if at else 0.0)
	walker.helmet = false
	(Game.camera as CameraRig).snap_focus()
	await hud.fade_to(0.0, 0.5).finished
	walker.controls_enabled = true
	state = State.INTERIOR
	hud.show_location(_interior.interior_name.to_upper(), String(link.note))
	Game.entered_interior.emit(_interior.interior_name)
	_frigate_hint()


## The lift along a frigate's keel: same interior, the far stop.
func ride_lift(lift: Node2D) -> void:
	if state != State.INTERIOR or walker == null or _interior == null:
		return
	var at := _interior.get_node_or_null(NodePath(String(lift.get(&"to_marker")))) as Node2D
	if at == null:
		return
	state = State.BUSY
	walker.controls_enabled = false
	await _walk(lift.global_position, 1.4)
	GameplayUtil.play_oneshot(self, GameplayUtil.load_audio("door_swish.wav"), -6.0, 0.8)
	await hud.fade_to(1.0, 0.3).finished
	if walker == null:
		return
	walker.place(at.global_position, at.global_rotation)
	(Game.camera as CameraRig).snap_focus()
	await get_tree().create_timer(0.35, false).timeout
	GameplayUtil.play_oneshot(self, GameplayUtil.load_audio("door_swish.wav"), -6.0, 1.0)
	await hud.fade_to(0.0, 0.35).finished
	walker.controls_enabled = true
	state = State.INTERIOR
	hud.show_location(_interior.interior_name.to_upper(), String(lift.get(&"destination")))


func _frigate_hint() -> void:
	if _interior is FrigateDeck and not _helm_hint_shown:
		_helm_hint_shown = true
		hud.show_hint("E:Use  ·  the captain's chair on the bridge (forward) takes the helm  ·  lifts run bow to stern", 9.0)


## The captain's chair: sit down, power up the bridge, cut to the ship outside.
func take_helm(chair: Node2D) -> void:
	var ship := FrigateShip.aboard
	if state != State.INTERIOR or walker == null or ship == null:
		return
	state = State.BUSY
	walker.controls_enabled = false
	await _walk(chair.call(&"seat_global"), 1.2)
	if walker:
		walker.place(chair.call(&"seat_global"), float(chair.call(&"facing")))
	GameplayUtil.play_oneshot(self, GameplayUtil.load_audio("helm_engage.wav"), -4.0, 1.0, &"UI")
	await get_tree().create_timer(0.7, false).timeout
	await hud.fade_to(1.0, 0.5).finished
	_to_flight(ship)
	await hud.fade_to(0.0, 0.8).finished
	if ship.dock.state == FrigateDock.State.LOCKED:
		Game.toast("%s  ·  you have the helm  ·  hold any flight key to undock  ·  X leave the bridge" % ship.vehicle_name, 6.0)
	else:
		Game.toast("%s  ·  you have the helm" % ship.vehicle_name, 3.0)
	Game.boarded.emit(ship.vehicle_name)


## X at the frigate's helm: back on its bridge, on foot.
func leave_helm() -> void:
	var ship := Game.player as FrigateShip
	if state != State.FLIGHT or ship == null:
		return
	state = State.BUSY
	GameplayUtil.play_oneshot(self, GameplayUtil.load_audio("ui_click.wav"), -10.0, 0.8, &"UI")
	await hud.fade_to(1.0, 0.5).finished
	_vehicle = ship
	ship.park()
	Game.mode = Game.Mode.ON_FOOT
	_set_flight_layer(false)
	_fade_engine(true)
	LevelArt.depth_amount = 0.0
	_suspend_world(true)
	_install_interior(ship.interior_scene(), ship)
	var at := _interior.get_node_or_null(^"BridgeStand") as Node2D
	_spawn_walker_inside(at.global_position if at else _interior.global_position, at.global_rotation if at else 0.0)
	pad_name = ship.vehicle_name
	await hud.fade_to(0.0, 0.6).finished
	walker.controls_enabled = true
	state = State.INTERIOR
	var where := "All stop  ·  holding position"
	if ship.dock.state == FrigateDock.State.LOCKED:
		where = "Clamped in Berth %s  ·  the gangway is at the %s airlock" % [ship.berth_name(), "starboard" if ship.dock.side() > 0.0 else "port"]
		_preload(String(ship.dock.berth.get(&"gangway_scene")))
	hud.show_location(_interior.interior_name.to_upper() + "  ·  BRIDGE", where)
	Game.disembarked.emit(ship.vehicle_name)
	Game.entered_interior.emit(_interior.interior_name)


## The on-foot character, indoors (no helmet), with the camera on it.
func _spawn_walker_inside(pos: Vector2, facing: float) -> void:
	walker = Walker.new()
	walker.name = "Walker"
	walker.controls_enabled = false
	walker.helmet = false
	add_child(walker)
	walker.place(pos, facing)
	walker.set_flashlight_energy(1.25)
	var cam := Game.camera as CameraRig
	if cam:
		cam.set_focus(walker, ZOOM, 0.001)
		cam.snap_focus()


## Behind a black screen: leave the interior and the on-foot layer, and put
## the player at the controls of `ship` in the (resumed) flight world.
func _to_flight(ship: PlayerShip) -> void:
	_drop_interior()
	FrigateShip.aboard = null
	_suspend_world(false)
	if walker:
		walker.queue_free()
		walker = null
	hud.clear_hint()
	_free_site()
	_site_root.modulate.a = 1.0
	_vehicle = ship
	ship.take_control()
	var cam := Game.camera as CameraRig
	if cam:
		cam.clear_focus(0.001)
		cam.snap()
	LevelArt.depth_amount = 1.0
	_set_flight_layer(true)
	_fade_engine(false)
	var amb := _ambient()
	if amb:
		amb.set_level_offset(0.0, 1.0)
	Game.mode = Game.Mode.FLIGHT
	ship.on_boarded()
	state = State.FLIGHT


# ============================================================ flight deck

## X in a small ship parked on a frigate's flight deck: the field holds the
## air in, so you step straight out into the frigate's hangar, by your ship.
func _disembark_to_hangar(ship: PlayerShip, host: FrigateShip) -> void:
	state = State.BUSY
	_vehicle = ship
	ship.park()
	Game.mode = Game.Mode.ON_FOOT
	_set_flight_layer(false)
	_fade_engine(true)
	GameplayUtil.play_oneshot(self, GameplayUtil.load_audio("ui_click.wav"), -10.0, 0.8, &"UI")
	await hud.fade_to(1.0, 0.5).finished
	var vis := ship.get_node_or_null(^"Visuals") as CanvasItem
	if vis:
		vis.visible = false
	ship.landed_model()        # parked ships show their close-up model outside
	LevelArt.depth_amount = 0.0
	_suspend_world(true)
	_install_interior(host.interior_scene(), host)
	var model := (_interior as FrigateDeck).stowed_model(ship)
	var stand := _interior.get_node_or_null(^"DeckStand") as Node2D
	var start := model.door_global() if model else stand.global_position
	_spawn_walker_inside(start, model.outward_angle() if model else 0.0)
	pad_name = "%s flight deck" % host.vehicle_name
	if model:
		model.hatch_t = 1.0
	await hud.fade_to(0.0, 0.6).finished
	if model:
		await _walk(model.foot_global(), 1.3)
	walker.controls_enabled = true
	state = State.INTERIOR
	hud.show_location("%s  ·  FLIGHT DECK" % host.vehicle_name, "Atmosphere field holding  ·  the bridge is forward, by the lift")
	if not _shown_hint:
		_shown_hint = true
		hud.show_hint("WASD:Walk|Shift:Run|E:Use|H:Help", 8.0)
	Game.disembarked.emit(pad_name)
	Game.entered_interior.emit(_interior.interior_name)
	_frigate_hint()


## E at the hatch of a ship parked in the hangar: climb in and fly it.
func board_stowed(ship: PlayerShip) -> void:
	var deck := _interior as FrigateDeck
	if state != State.INTERIOR or walker == null or deck == null:
		return
	var model := deck.stowed_model(ship)
	if model == null:
		return
	state = State.BUSY
	walker.controls_enabled = false
	if model.hatch_t < 0.95:
		model.open_hatch(0.9)
		await model.hatch_finished
	await _walk(model.foot_global(), 1.6)
	await _walk(model.door_global(), 1.1)
	await hud.fade_to(1.0, 0.45).finished
	_to_flight(ship)
	var vis := ship.get_node_or_null(^"Visuals") as CanvasItem
	if vis:
		vis.visible = true
		vis.modulate.a = 1.0
	ship.drop_landed_model()
	await hud.fade_to(0.0, 0.7).finished
	Game.toast("%s  ·  on the flight deck  ·  back out through the field, astern" % String(ship.vehicle_name).to_upper(), 4.5)
	Game.boarded.emit(pad_name)


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
	# Airlock doors in the walls around this deck (ExteriorDoors).
	for d: Dictionary in ExteriorDoors.on_site(site):
		var ed := ExteriorDoor.new()
		ed.name = "Door_%s" % String(d.id)
		_site_root.add_child(ed)
		ed.setup(d)
		ed.enter_requested.connect(_enter_interior.bind(ed))


## The ExteriorDoor of the current site that stands at global point `p`.
func _door_at(p: Vector2) -> ExteriorDoor:
	for c in _site_root.get_children():
		var ed := c as ExteriorDoor
		if ed and not ed.is_queued_for_deletion() and ed.global_position.distance_to(p) < 20.0:
			return ed
	return null


func _free_site() -> void:
	for c in _site_root.get_children():
		c.queue_free()
	_extras = null


## Background-thread load of the interior while you walk to the door.
func _preload(path: String) -> void:
	if path == "" or _packed.has(path) or _loading_path == path or not ResourceLoader.exists(path):
		return
	if _loading_path != "":
		# One background load at a time: collect the previous one first.
		_packed[_loading_path] = ResourceLoader.load_threaded_get(_loading_path)
		_loading_path = ""
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
				if not s.name in KEEP_SYSTEMS:
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


## --interior=res://scenes/onfoot/interiors/x.tscn[@Marker]: start on foot
## inside that interior (at the marker, else its airlock, else its origin).
## --interior=frigate:kestrel[@Marker] is that frigate's deck. For building
## and checking interiors without walking there first.
func _harness_interior(arg: String) -> void:
	var path := arg.get_slice("@", 0)
	var marker := arg.get_slice("@", 1) if arg.contains("@") else ""
	await get_tree().create_timer(0.4, false).timeout
	if state != State.FLIGHT or not GameplayUtil.player_valid():
		return
	var frigate: FrigateShip = null
	if path.begins_with("frigate:"):
		for n in get_tree().get_nodes_in_group(&"frigate"):
			if String(n.call(&"ship_id")) == path.trim_prefix("frigate:"):
				frigate = n as FrigateShip
		if frigate == null:
			push_warning("--interior: no frigate %s" % path)
			return
		path = frigate.interior_scene()
	if not ResourceLoader.exists(path):
		push_warning("--interior: no scene %s" % path)
		return
	state = State.BUSY
	var ship := Game.player as PlayerShip
	_vehicle = ship
	ship.park()
	Game.mode = Game.Mode.ON_FOOT
	_set_flight_layer(false)
	_fade_engine(true)
	LevelArt.depth_amount = 0.0
	_suspend_world(true)
	_install_interior(path, frigate)
	var at := _interior.get_node_or_null(NodePath(marker)) as Node2D if marker != "" else null
	var al := _interior.get_airlock() as Airlock
	var pos := _interior.global_position
	var face := 0.0
	if at:
		pos = at.global_position
		face = at.global_rotation
	elif al:
		pos = al.arrival_global()
	_spawn_walker_inside(pos, face)
	walker.controls_enabled = true
	state = State.INTERIOR
	hud.show_location(_interior.interior_name.to_upper(), "")
	Game.entered_interior.emit(_interior.interior_name)


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
