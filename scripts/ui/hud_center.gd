extends Control
## Centre-screen status: race countdown (3-2-1-GO), docking guidance,
## boundary warning and the destroyed/respawning card.

var _race: RaceSystem
var _dock: DockingSystem
var _bound: BoundarySystem
var _dmg: DamageSystem
var _count_pop := 0.0
var _count_val := -1
var _t := 0.0
var _dead_t := 0.0               # seconds since the ship was destroyed

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

func _process(delta: float) -> void:
	_t += delta
	if _race == null:
		_race = get_tree().get_first_node_in_group(&"race_system") as RaceSystem
		if _race:
			_race.countdown_tick.connect(_on_tick)
	if _dock == null:
		_dock = get_tree().get_first_node_in_group(&"docking_system") as DockingSystem
	if _bound == null:
		_bound = get_tree().get_first_node_in_group(&"boundary_system") as BoundarySystem
	if _dmg == null:
		_dmg = get_tree().get_first_node_in_group(&"damage_system") as DamageSystem
	_count_pop = maxf(0.0, _count_pop - delta)
	if GameplayUtil.player_valid() and not GameplayUtil.player_alive():
		_dead_t += delta
	else:
		_dead_t = 0.0
	queue_redraw()

func _on_tick(v: int) -> void:
	_count_val = v
	_count_pop = 1.0 if v > 0 else 1.2

func _draw() -> void:
	var c := size * 0.5
	# --- countdown ---
	if _count_pop > 0.0 and _count_val >= 0:
		var k := _count_pop
		var txt := str(_count_val) if _count_val > 0 else "GO"
		var fs := int(lerpf(110.0, 150.0, k * k))
		var col := HudStyle.WHITE if _count_val > 0 else HudStyle.GREEN
		col.a = clampf(k * 1.6, 0.0, 1.0)
		HudStyle.text(self, c + Vector2(-300, -120), txt, fs, col, HORIZONTAL_ALIGNMENT_CENTER, 600)
		draw_arc(c + Vector2(0, -160), 110.0 + (1.0 - k) * 40.0, 0.0, TAU, 64, Color(col, col.a * 0.4), 2.0, true)

	# --- destroyed ---
	if GameplayUtil.player_valid() and not GameplayUtil.player_alive():
		# Lower third, fading in after the first burst so the explosion's
		# fireball and shock ring are unobstructed at their peak.
		var a := clampf((_dead_t - 0.6) * 3.0, 0.0, 1.0)
		if a <= 0.0:
			return
		var r := Rect2(c + Vector2(-260, 210), Vector2(520, 96))
		HudStyle.draw_panel(self, r, 14.0, Color(HudStyle.RED, 0.8 * a), Color(0.12, 0.0, 0.0, 0.55 * a))
		HudStyle.text(self, r.position + Vector2(0, 46), "HULL BREACH", 36, Color(HudStyle.RED, a), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		var left := _dmg.respawn_countdown if _dmg else -1.0
		var sub := "Recovering ship…" if left < 0.0 else "Recovery drone launching in %.1f s" % left
		HudStyle.text(self, r.position + Vector2(0, 78), sub, 18, Color(HudStyle.WHITE, a), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		return

	# --- boundary ---
	if _bound and _bound.outside:
		var blink := 0.65 + 0.35 * sin(_t * 8.0)
		var r2 := Rect2(c + Vector2(-330, -300), Vector2(660, 84))
		HudStyle.draw_panel(self, r2, 12.0, Color(HudStyle.AMBER, blink), Color(0.1, 0.06, 0.0, 0.55))
		_stripes(Rect2(r2.position + Vector2(14, 8), Vector2(26, r2.size.y - 16)))
		_stripes(Rect2(Vector2(r2.end.x - 40, r2.position.y + 8), Vector2(26, r2.size.y - 16)))
		HudStyle.text(self, r2.position + Vector2(0, 40), "LEAVING STATION CONTROL SPACE", 28, Color(HudStyle.AMBER, blink), HORIZONTAL_ALIGNMENT_CENTER, r2.size.x)
		HudStyle.text(self, r2.position + Vector2(0, 68), "Turn back  ·  %d m outside the traffic perimeter" % int(_bound.distance_out_m), 17, HudStyle.WHITE, HORIZONTAL_ALIGNMENT_CENTER, r2.size.x)

	# --- docking ---
	var exit_at := c + Vector2(-70.0, 250.0)
	var frigate := Game.player as FrigateShip if GameplayUtil.player_alive() else null
	if frigate:
		exit_at = _draw_berth(c, frigate)
	if _dock and _dock.phase != DockingSystem.Phase.NONE:
		var visible_prompt := _dock.phase != DockingSystem.Phase.APPROACH or _dock.hint != ""
		if visible_prompt:
			var r3 := Rect2(c + Vector2(-220, 150), Vector2(440, 70))
			var title := ""
			var col2 := HudStyle.CYAN
			match _dock.phase:
				DockingSystem.Phase.APPROACH:
					title = "%s  ·  %s" % [_dock.pad_name.to_upper(), _dock.hint]
					col2 = HudStyle.AMBER
				DockingSystem.Phase.HOLDING:
					title = "DOCKING…  HOLD STEADY"
				DockingSystem.Phase.DOCKED:
					title = "DOCKED  ·  %s" % _dock.pad_name.to_upper()
					col2 = HudStyle.GREEN
			HudStyle.draw_panel(self, r3, 10.0, Color(col2, 0.7))
			HudStyle.text(self, r3.position + Vector2(0, 32), title, 20, col2, HORIZONTAL_ALIGNMENT_CENTER, r3.size.x)
			var bar := Rect2(r3.position + Vector2(40, 46), Vector2(r3.size.x - 80, 6))
			draw_rect(bar, Color(col2, 0.15))
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * _dock.progress, bar.size.y)), col2)
			exit_at = r3.position + Vector2(r3.size.x * 0.5 - 70.0, r3.size.y + 40.0)
	_draw_exit_prompt(exit_at)


func _draw_exit_prompt(at: Vector2) -> void:
	# Landed (docked on a pad, or the shuttle anchored): you can get out and
	# walk. Otherwise the ship may explain what it still needs.
	var dir := get_tree().get_first_node_in_group(&"on_foot_director")
	if dir == null or Game.mode != Game.Mode.FLIGHT or not GameplayUtil.player_alive():
		return
	if bool(dir.call(&"can_exit")):
		var pulse := 0.75 + 0.25 * sin(_t * 3.0)
		var label := String(Game.player.call(&"exit_label")) if Game.player.has_method(&"exit_label") else "Exit ship"
		HudStyle.key_hint(self, at, "X", label, pulse)


## The KESTREL's berth approach: state, distance and closing speed, an
## alignment scope (capture box to scale, where the ship's centre is, heading
## error) and what still needs fixing. Returns where the X prompt goes.
func _draw_berth(c: Vector2, ship: FrigateShip) -> Vector2:
	var dk := ship.dock
	# The frigate fills the middle of the screen: guidance sits at the top
	# and the X prompt at the bottom.
	var exit_at := Vector2(c.x - 90.0, size.y - 70.0)
	var showing := dk.state != FrigateDock.State.FREE or (dk.in_range and dk.dist < 260.0 and (dk.speed < 6.0 or dk.dist < 120.0))
	if not showing or (dk.state == FrigateDock.State.LOCKED and dk.gangway_t >= 1.0):
		return exit_at
	var r := Rect2(Vector2(c.x - 250.0, 70.0), Vector2(500, 150))
	var col := HudStyle.CYAN
	var title := "BERTH %s  ·  APPROACH" % ship.berth_name()
	match dk.state:
		FrigateDock.State.CAPTURE:
			title = "SOFT CAPTURE  ·  CLAMPS ENGAGING"
			col = HudStyle.AMBER
		FrigateDock.State.LOCKED:
			title = "HARD DOCK  ·  GANGWAY EXTENDING"
			col = HudStyle.GREEN
		FrigateDock.State.UNDOCKING:
			title = "UNDOCKING  ·  GANGWAY RETRACTING" if dk.gangway_t > 0.0 else "UNDOCKING  ·  CLAMPS RELEASING"
			col = HudStyle.AMBER
	if dk.state == FrigateDock.State.FREE and dk.hint == "" and dk.in_box:
		col = HudStyle.GREEN
		title = "CAPTURE  ·  HOLD STEADY"
	HudStyle.draw_panel(self, r, 12.0, Color(col, 0.7))
	HudStyle.text(self, r.position + Vector2(18, 30), title, 19, col)
	# alignment scope: +/-12 m fore/aft across, +/-8 m lateral (pier up)
	var sc := Rect2(r.position + Vector2(18, 44), Vector2(200, 92))
	draw_rect(sc, Color(0.0, 0.03, 0.06, 0.5))
	draw_rect(sc, Color(col, 0.35), false, 1.0)
	var kx := sc.size.x * 0.5 / 12.0
	var ky := sc.size.y * 0.5 / 8.0
	var mid := sc.get_center()
	var box := Rect2(mid + Vector2(-FrigateDock.BOX_AXIAL * kx, -FrigateDock.BOX_IN * ky), Vector2(FrigateDock.BOX_AXIAL * 2.0 * kx, (FrigateDock.BOX_IN + FrigateDock.BOX_OUT) * ky))
	draw_rect(box, Color(col, 0.12))
	draw_rect(box, Color(col, 0.8), false, 1.5)
	draw_line(Vector2(sc.position.x, mid.y), Vector2(sc.end.x, mid.y), Color(col, 0.25), 1.0)
	draw_line(Vector2(mid.x, sc.position.y), Vector2(mid.x, sc.end.y), Color(col, 0.25), 1.0)
	HudStyle.text(self, Vector2(sc.position.x + 4, sc.position.y + 13), "PIER", 11, HudStyle.MUTED)
	var p := mid + Vector2(clampf(dk.err.x, -12.0, 12.0) * kx, -clampf(dk.err.y, -8.0, 8.0) * ky)
	var hd := Vector2.from_angle(deg_to_rad(dk.heading_err))
	draw_circle(p, 5.0, HudStyle.WHITE)
	draw_line(p, p + hd * 16.0, HudStyle.WHITE, 2.0, true)
	# readouts
	var tx := r.position + Vector2(236, 62)
	HudStyle.label(self, tx, "Range")
	HudStyle.text(self, tx + Vector2(84, 0), "%.1f m" % dk.dist, 18, HudStyle.WHITE, HORIZONTAL_ALIGNMENT_LEFT, -1, HudStyle.mono())
	HudStyle.label(self, tx + Vector2(0, 24), "Speed")
	var sp_col := HudStyle.WHITE if dk.speed <= FrigateDock.MAX_SPEED else HudStyle.AMBER
	HudStyle.text(self, tx + Vector2(84, 24), "%.2f m/s" % dk.speed, 18, sp_col, HORIZONTAL_ALIGNMENT_LEFT, -1, HudStyle.mono())
	HudStyle.label(self, tx + Vector2(0, 48), "Heading")
	var hd_col := HudStyle.WHITE if absf(dk.heading_err) <= FrigateDock.MAX_HEADING_DEG else HudStyle.AMBER
	HudStyle.text(self, tx + Vector2(84, 48), "%+.1f°" % dk.heading_err, 18, hd_col, HORIZONTAL_ALIGNMENT_LEFT, -1, HudStyle.mono())
	if dk.state == FrigateDock.State.FREE and dk.hint != "":
		HudStyle.text(self, tx + Vector2(0, 74), dk.hint, 15, HudStyle.AMBER)
	var prog := dk.hold
	match dk.state:
		FrigateDock.State.CAPTURE: prog = dk.clamp_t
		FrigateDock.State.LOCKED: prog = dk.gangway_t
		FrigateDock.State.UNDOCKING: prog = 1.0 - (dk.gangway_t * 0.6 + dk.clamp_t * 0.4)
	var bar := Rect2(r.position + Vector2(236, 138), Vector2(r.size.x - 254, 5))
	draw_rect(bar, Color(col, 0.15))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(prog, 0.0, 1.0), bar.size.y)), col)
	return exit_at


func _stripes(r: Rect2) -> void:
	# Amber hazard stripes: thin parallelograms rising to the right.
	draw_rect(r, Color(0.05, 0.04, 0.0, 0.6))
	var rise := 10.0
	var thick := 6.0
	var y := r.position.y + rise
	while y + thick <= r.end.y:
		var pts := PackedVector2Array([Vector2(r.position.x, y), Vector2(r.end.x, y - rise),
			Vector2(r.end.x, y - rise + thick), Vector2(r.position.x, y + thick)])
		draw_colored_polygon(pts, Color(HudStyle.AMBER, 0.85))
		y += thick * 2.0
