extends Control
## Bottom-left flight panel: speed, heading & drift, hull bar, the throttle
## setting, flight-assist state and a live thruster diagram (top-down ship
## icon whose jets light up from the ship's actual thruster outputs). Flying
## the PETREL it shows that ship's own instruments instead: mode + assist, a
## nav compass (nose, velocity, engine plumes), an altitude tape, the landing
## status line and the mag-line panel.

const PANEL_SIZE := Vector2(560, 236)
const MARGIN := Vector2(32, 32)

var _hull := 100.0
var _max_hull := 100.0
var _hit_flash := 0.0
var _t := 0.0
var _accum := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Game.hull_changed.connect(_on_hull)

func _on_hull(h: float, mh: float) -> void:
	if h < _hull - 0.4:
		_hit_flash = 1.0
	_hull = h
	_max_hull = maxf(mh, 1.0)

func _process(delta: float) -> void:
	_t += delta
	_hit_flash = maxf(0.0, _hit_flash - delta * 2.5)
	# Readouts refresh at ~30 Hz; plenty for numbers, half the draw cost.
	_accum += delta
	if _accum >= 1.0 / 30.0:
		_accum = 0.0
		queue_redraw()

func _draw() -> void:
	var r := Rect2(Vector2(MARGIN.x, size.y - MARGIN.y - PANEL_SIZE.y), PANEL_SIZE)
	HudStyle.draw_panel(self, r)
	var ship := Game.player if GameplayUtil.player_valid() else null
	var vel := GameplayUtil.player_velocity_mps()
	var speed := vel.length()
	var o := r.position + Vector2(24, 0)

	# --- speed ---
	HudStyle.label(self, o + Vector2(0, 30), "Velocity")
	var spd_txt := "%.1f" % speed
	HudStyle.text(self, o + Vector2(0, 92), spd_txt, 64, HudStyle.WHITE, HORIZONTAL_ALIGNMENT_LEFT, -1, HudStyle.mono())
	var w := HudStyle.mono().get_string_size(spd_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 64).x
	HudStyle.text(self, o + Vector2(w + 8, 92), "m/s", 20, HudStyle.MUTED)

	# --- heading / drift ---
	var heading := 0.0
	if ship:
		heading = fposmod(rad_to_deg(ship.global_rotation) + 90.0, 360.0)
	HudStyle.label(self, o + Vector2(0, 124), "HDG")
	HudStyle.text(self, o + Vector2(40, 124), "%03d°" % (int(round(heading)) % 360), 20, HudStyle.WHITE, HORIZONTAL_ALIGNMENT_LEFT, -1, HudStyle.mono())
	if ship and speed > 0.5:
		var drift := rad_to_deg(angle_difference(ship.global_rotation, vel.angle()))
		var dcol := HudStyle.MUTED if absf(drift) < 20.0 else (HudStyle.AMBER if absf(drift) < 90.0 else HudStyle.RED)
		HudStyle.label(self, o + Vector2(112, 124), "Drift")
		HudStyle.text(self, o + Vector2(160, 124), "%+04d°" % int(round(drift)), 20, dcol, HORIZONTAL_ALIGNMENT_LEFT, -1, HudStyle.mono())

	# --- hull ---
	var hf := clampf(_hull / _max_hull, 0.0, 1.0)
	var hcol := HudStyle.CYAN
	if hf < 0.25:
		hcol = HudStyle.RED if fmod(_t, 0.5) < 0.3 else HudStyle.RED.darkened(0.4)
	elif hf < 0.5:
		hcol = HudStyle.AMBER
	hcol = hcol.lerp(Color.WHITE, _hit_flash * 0.8)
	HudStyle.label(self, o + Vector2(0, 162), "Hull")
	HudStyle.seg_bar(self, Rect2(o + Vector2(56, 150), Vector2(250, 12)), hf, hcol, 20)
	HudStyle.text(self, o + Vector2(316, 163), "%d%%" % int(ceil(hf * 100.0)), 18, hcol, HORIZONTAL_ALIGNMENT_LEFT, -1, HudStyle.mono())

	# --- throttle setting (Shift / Ctrl·Z); bright while the engine burns ---
	var petrel := ship as ShuttleShip
	var tf := clampf(float(GameplayUtil.pget(ship, &"throttle_setting", 0.0)), 0.0, 1.0)
	var burning := float(GameplayUtil.pget(ship, &"main_output", 0.0)) > 0.01
	var tcol := HudStyle.CYAN_DIM.lerp(HudStyle.CYAN, 0.5)
	if burning:
		tcol = HudStyle.CYAN.lerp(Color(0.75, 0.95, 1.0), smoothstep(0.5, 1.0, tf))
	HudStyle.label(self, o + Vector2(0, 190), "Thr")
	var tbar := Rect2(o + Vector2(56, 178), Vector2(250, 12))
	HudStyle.seg_bar(self, tbar, tf, tcol, 20)
	# 50 % tick: cruise flame below, the hot top range above.
	var mid := tbar.position.x + tbar.size.x * 0.5
	draw_line(Vector2(mid, tbar.position.y - 3), Vector2(mid, tbar.end.y + 3), Color(1, 1, 1, 0.35), 1.0)
	HudStyle.text(self, o + Vector2(316, 191), "%d%%" % int(round(tf * 100.0)), 18, tcol, HORIZONTAL_ALIGNMENT_LEFT, -1, HudStyle.mono())

	if petrel:
		_draw_petrel(r, o, petrel)
		return
	var frigate := ship as FrigateShip
	if frigate:
		_draw_frigate(r, o, frigate)
		return

	# --- flight assist ---
	var fa := bool(GameplayUtil.pget(ship, &"flight_assist", false))
	var fa_rect := Rect2(o + Vector2(0, 204), Vector2(150, 22))
	var fa_col := HudStyle.GREEN if fa else HudStyle.MUTED
	draw_rect(fa_rect, Color(fa_col.r, fa_col.g, fa_col.b, 0.14 if fa else 0.06))
	draw_rect(fa_rect, Color(fa_col.r, fa_col.g, fa_col.b, 0.7), false, 1.0)
	HudStyle.text(self, fa_rect.position + Vector2(8, 17), "FLIGHT ASSIST  %s" % ("ON" if fa else "OFF"), 14, fa_col)
	HudStyle.text(self, fa_rect.position + Vector2(160, 17), "[F]", 14, HudStyle.MUTED)

	# --- pulse cannon heat (only a ship with a Guns node: the WREN) ---
	var guns := (ship.get_node_or_null(^"Guns") as WrenGuns) if ship else null
	if guns:
		_draw_heat(o + Vector2(196, 204), guns)

	# --- thruster diagram ---
	_draw_thrusters(r.position + Vector2(PANEL_SIZE.x - 92, 120), ship, vel)

## Ship icon pointing up (ship +X = up, starboard +Y = right).
func _draw_thrusters(c: Vector2, ship: Object, vel: Vector2) -> void:
	HudStyle.label(self, c + Vector2(-44, -96), "Thrusters")
	var main := float(GameplayUtil.pget(ship, &"main_output", GameplayUtil.pget(ship, &"throttle_input", 0.0)))
	var turn := float(GameplayUtil.pget(ship, &"turn_input", 0.0))
	var strafe := float(GameplayUtil.pget(ship, &"strafe_input", 0.0))
	var bow := float(GameplayUtil.pget(ship, &"bow_lateral_output", turn + strafe * 0.5))
	var stern := float(GameplayUtil.pget(ship, &"stern_lateral_output", strafe * 0.5))
	var head := c + Vector2(0, -40)
	var pod := c + Vector2(0, 28)
	var hull_col := Color(0.85, 0.9, 0.95, 0.9)
	var line_col := Color(0.5, 0.9, 1.0, 0.6)

	# Drift vector relative to the hull (where the ship is actually going).
	if ship and vel.length() > 0.3:
		var rel := vel.rotated(-(ship as Node2D).global_rotation - PI * 0.5)
		var dlen := clampf(vel.length() / 40.0, 0.12, 1.0) * 70.0
		var d := rel.normalized() * dlen
		draw_line(c, c + d, Color(0.6, 1.0, 0.75, 0.55), 2.0, true)
		draw_circle(c + d, 3.0, Color(0.6, 1.0, 0.75, 0.8))

	# Spine and hull.
	draw_line(head, pod, line_col, 3.0, true)
	var nose := PackedVector2Array([head + Vector2(0, -26), head + Vector2(15, 10), head + Vector2(-15, 10)])
	draw_colored_polygon(nose, Color(0.1, 0.18, 0.3, 0.9))
	draw_polyline(nose + PackedVector2Array([nose[0]]), hull_col, 1.5, true)
	draw_circle(pod, 17.0, Color(0.1, 0.18, 0.3, 0.9))
	draw_arc(pod, 17.0, 0.0, TAU, 28, hull_col, 1.5, true)
	draw_arc(c, 2.5, 0.0, TAU, 8, HudStyle.WHITE, 1.5, true)   # CoM

	var hot := HudStyle.CYAN.lerp(Color(0.75, 0.95, 1.0), clampf(main * 2.0 - 1.0, 0.0, 1.0))
	# Main engine (forward thrust): flame out of the stern pod (main is a
	# fraction of full thrust; 100 % draws as long as the old boost).
	if main > 0.02:
		_jet(pod + Vector2(0, 18), Vector2.DOWN, main * 1.6, hot)
	# Retro: twin jets out of the bow, pointing forward.
	elif main < -0.02:
		var retro := -main / maxf(float(GameplayUtil.pget(ship, &"reverse_scale", 0.6)), 0.05)
		_jet(head + Vector2(-9, -12), Vector2(-0.25, -1).normalized(), retro, hot)
		_jet(head + Vector2(9, -12), Vector2(0.25, -1).normalized(), retro, hot)
	# Bow lateral: pushing to starboard (+) means exhaust to port (left).
	if absf(bow) > 0.02:
		var s := signf(bow)
		_jet(head + Vector2(-s * 13.0, 2), Vector2(-s, 0), absf(bow), hot)
	if absf(stern) > 0.02:
		var s2 := signf(stern)
		_jet(pod + Vector2(-s2 * 18.0, 0), Vector2(-s2, 0), absf(stern), hot)
	# Nozzle markers (always visible, dim).
	for p in [head + Vector2(-13, 2), head + Vector2(13, 2), pod + Vector2(-18, 0), pod + Vector2(18, 0), pod + Vector2(0, 18)]:
		draw_circle(p, 2.5, Color(0.5, 0.9, 1.0, 0.35))

## Compact gun-heat gauge on the bottom row: cyan while cool, amber when
## hot, and a flashing red OVERHEAT while the guns are locked out.
func _draw_heat(pos: Vector2, guns: WrenGuns) -> void:
	var col := HudStyle.MUTED
	var label := "HEAT"
	if guns.overheated:
		col = HudStyle.RED if fmod(_t, 0.3) < 0.18 else HudStyle.RED.darkened(0.45)
		label = "OVERHEAT"
	elif guns.heat >= 0.7:
		col = HudStyle.AMBER
	elif guns.heat > 0.01:
		col = HudStyle.CYAN
	HudStyle.text(self, pos + Vector2(0, 17), label, 14, col, HORIZONTAL_ALIGNMENT_RIGHT, 72.0)
	var bar := Rect2(pos + Vector2(80, 5), Vector2(118, 12))
	HudStyle.seg_bar(self, bar, clampf(guns.heat, 0.0, 1.0), col, 12)
	# Where the guns come back after a lockout.
	var mark := bar.position.x + bar.size.x * guns.ready_below
	draw_line(Vector2(mark, bar.position.y - 3), Vector2(mark, bar.end.y + 3), Color(1, 1, 1, 0.35), 1.0)


func _jet(at: Vector2, dir: Vector2, amount: float, col: Color) -> void:
	var a := clampf(amount, 0.0, 2.0)
	var flick := 0.85 + 0.15 * sin(_t * 47.0 + at.x)
	var jet_len := (10.0 + 26.0 * a) * flick
	var side := dir.orthogonal() * (4.0 + 2.0 * a)
	var tri := PackedVector2Array([at + side, at + dir * jet_len, at - side])
	draw_colored_polygon(tri, Color(col.r, col.g, col.b, 0.85))
	draw_line(at, at + dir * jet_len * 0.55, Color(1, 1, 1, 0.9), 2.0, true)


# ================================================================ PETREL

const MODE_NAMES := ["CRUISE", "HOVER", "DESCENT", "LANDED", "LIFT-OFF"]


func _draw_petrel(r: Rect2, o: Vector2, ship: ShuttleShip) -> void:
	# --- mode chips: flight mode, flight assist, floodlights
	var mode: String = MODE_NAMES[ship.land_state]
	if ship.line and ship.line.is_attached():
		mode = "TETHERED"
	var chip := Rect2(o + Vector2(0, 204), Vector2(120, 22))
	draw_rect(chip, Color(HudStyle.GREEN, 0.14))
	draw_rect(chip, Color(HudStyle.GREEN, 0.7), false, 1.0)
	HudStyle.text(self, chip.position + Vector2(8, 17), mode, 14, HudStyle.GREEN)
	var fa := ship.flight_assist
	var fa_col := HudStyle.GREEN if fa else HudStyle.MUTED
	var fa_rect := Rect2(o + Vector2(128, 204), Vector2(120, 22))
	draw_rect(fa_rect, Color(fa_col, 0.14 if fa else 0.06))
	draw_rect(fa_rect, Color(fa_col, 0.7), false, 1.0)
	HudStyle.text(self, fa_rect.position + Vector2(8, 17), "ASSIST %s [F]" % ("ON" if fa else "OFF"), 14, fa_col)
	HudStyle.text(self, o + Vector2(262, 221), "LIGHTS %s [L]" % ("ON" if ship.floodlights else "OFF"), 13, HudStyle.MUTED)
	_draw_compass(r.position + Vector2(PANEL_SIZE.x - 120, 128), ship)
	_draw_hold(r.position + Vector2(208, 0), r.position + Vector2(PANEL_SIZE.x - 120, 128), ship)
	_draw_altitude(r.position + Vector2(PANEL_SIZE.x - 34, 46), ship)
	_draw_landing_line(Vector2(r.position.x, r.position.y - 14), ship)
	if ship.line:
		var tall := ship.line.is_attached()
		var h := 84.0 if tall else 40.0
		_draw_line_panel(Rect2(Vector2(r.position.x, r.position.y - 36 - h), Vector2(PANEL_SIZE.x, h)), ship.line)


## North-up nav compass: the ship icon at its heading with its two engine
## plumes (hotter in the top half of the throttle), the turn thrusters'
## puffs and the velocity vector (where you are actually going).
func _draw_compass(c: Vector2, ship: ShuttleShip) -> void:
	HudStyle.label(self, c + Vector2(-26, -82), "Nav")
	var R := 58.0
	var ring := HudStyle.CYAN
	draw_arc(c, R, 0.0, TAU, 48, Color(ring, 0.55), 2.0, true)
	for i in 8:
		var a := TAU * i / 8.0
		var d := Vector2.from_angle(a)
		draw_line(c + d * (R - (8.0 if i % 2 == 0 else 4.0)), c + d * R, Color(ring, 0.6), 1.5, true)
	HudStyle.text(self, c + Vector2(-5, -R - 6), "N", 12, HudStyle.MUTED)
	var hd := ship.global_rotation
	# Ship icon at the centre, rotated to the heading, with two plume bars.
	var f := Vector2.from_angle(hd)
	var rt := f.orthogonal()
	var nose := PackedVector2Array([c + f * 22.0, c - f * 14.0 + rt * 11.0, c - f * 14.0 - rt * 11.0])
	draw_colored_polygon(nose, Color(0.1, 0.18, 0.3, 0.9))
	draw_polyline(nose + PackedVector2Array([nose[0]]), Color(0.85, 0.9, 0.95, 0.9), 1.5, true)
	for i in 2:
		var amt := ship.engine_out.x if i == 0 else ship.engine_out.y
		var base := c - f * 15.0 + rt * (-5.0 if i == 0 else 5.0)
		if amt > 0.02:
			var col := HudStyle.CYAN.lerp(Color(0.75, 0.95, 1.0), clampf(amt * 2.0 - 1.0, 0.0, 1.0))
			draw_line(base, base - f * (6.0 + 30.0 * amt), col, 3.0, true)
	# Turn couple: bow and stern puffs (+ = push to starboard).
	for end in 2:
		var o := ship.bow_lateral_output if end == 0 else ship.stern_lateral_output
		if absf(o) > 0.05:
			var at := c + f * (16.0 if end == 0 else -10.0)
			var gas := -rt * signf(o)
			draw_line(at + gas * 8.0, at + gas * (8.0 + 12.0 * minf(absf(o), 1.0)), Color(0.9, 0.95, 1.0, 0.8), 2.0, true)
	# Velocity vector (where you are actually going).
	var v := ship.linear_velocity / Game.PX_PER_M
	if v.length() > 0.3:
		var tip := c + v.normalized() * clampf(v.length() / 36.0, 0.15, 1.0) * (R - 6.0)
		draw_line(c, tip, Color(0.6, 1.0, 0.75, 0.6), 2.0, true)
		draw_circle(tip, 3.0, Color(0.6, 1.0, 0.75, 0.8))


const HOLD_SLOT_W := 13.6
const HOLD_SLOT_GAP := 2.8
# Hold readout memory: what it showed last (per ship), and which slots changed.
var _hold_ship := 0
var _hold_used := 0
var _hold_flash_at := -10.0
var _hold_flash_a := 0
var _hold_flash_b := 0
var _hold_flash_in := true


## Cargo hold: HOLD n/10 over ten slot boxes in the liveries of what is aboard
## (a 12 m container spans two), the weight it adds, and where to take it. The
## slots that just filled or emptied flash. `compass` is the nav ring's centre:
## with cargo aboard it carries a marker toward the nearest freight intake.
func _draw_hold(p: Vector2, compass: Vector2, ship: ShuttleShip) -> void:
	var hold := ship.hold
	if hold == null:
		return
	var used := hold.used()
	if ship.get_instance_id() != _hold_ship:
		_hold_ship = ship.get_instance_id()
		_hold_used = used
	elif used != _hold_used:
		_hold_flash_at = _t
		_hold_flash_in = used > _hold_used
		_hold_flash_a = mini(used, _hold_used)
		_hold_flash_b = maxi(used, _hold_used)
		_hold_used = used
	var fl := clampf(1.0 - (_t - _hold_flash_at) / 0.7, 0.0, 1.0)
	var pitch := HOLD_SLOT_W + HOLD_SLOT_GAP
	var width := hold.capacity * pitch - HOLD_SLOT_GAP
	var full := hold.free_slots() <= 0
	var ccol := HudStyle.AMBER if full else (HudStyle.WHITE if used > 0 else HudStyle.MUTED)
	HudStyle.label(self, p + Vector2(0, 30), "Hold")
	HudStyle.text(self, p + Vector2(0, 31), "%d/%d" % [used, hold.capacity], 18, ccol.lerp(Color.WHITE, fl), HORIZONTAL_ALIGNMENT_RIGHT, width, HudStyle.mono())
	var top := p + Vector2(0, 40)
	var h := 20.0
	for i in hold.capacity:
		var cell := Rect2(top + Vector2(i * pitch, 0), Vector2(HOLD_SLOT_W, h))
		draw_rect(cell, Color(HudStyle.CYAN, 0.07))
		draw_rect(cell, Color(HudStyle.CYAN, 0.32), false, 1.0)
	var slot := 0
	var top_brand := ""
	for it: Dictionary in hold.items():
		var n := int(it.slots)
		var box := Rect2(top + Vector2(slot * pitch, 0), Vector2(n * pitch - HOLD_SLOT_GAP, h))
		var c: Color = it.color
		draw_rect(box, c)
		draw_rect(Rect2(box.position, Vector2(box.size.x, 3.0)), c.lightened(0.3))
		# Light rim: navy and plum liveries would vanish into the panel.
		draw_rect(box, Color(1, 1, 1, 0.5), false, 1.0)
		slot += n
		top_brand = String(it.brand)
	if fl > 0.0:
		var changed := Rect2(top + Vector2(_hold_flash_a * pitch, 0), Vector2((_hold_flash_b - _hold_flash_a) * pitch - HOLD_SLOT_GAP, h))
		if _hold_flash_in:
			draw_rect(changed, Color(1, 1, 1, 0.85 * fl))
		else:
			draw_rect(changed, Color(HudStyle.CYAN, 0.3 * fl))
		draw_rect(changed.grow(2.0 + 4.0 * (1.0 - fl)), Color(HudStyle.CYAN, fl), false, 1.5)
	if used == 0:
		HudStyle.text(self, p + Vector2(0, 79), "hook a container, reel to stow", 13, HudStyle.MUTED)
		return
	HudStyle.text(self, p + Vector2(0, 79), "+%d kg" % int(hold.mass_kg()), 14, HudStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, -1, HudStyle.mono())
	HudStyle.text(self, p + Vector2(0, 79), "[U] unload", 14, HudStyle.MUTED, HORIZONTAL_ALIGNMENT_RIGHT, width)
	# Nearest intake that takes what comes out next (else just the nearest).
	var best: FreightReceiver = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group(&"freight_receiver"):
		var rc := n as FreightReceiver
		if rc == null:
			continue
		var d := rc.global_position.distance_to(ship.global_position) * (1.0 if rc.takes(top_brand) else 1000.0)
		if d < best_d:
			best_d = d
			best = rc
	if best == null:
		return
	var to := best.global_position - ship.global_position
	var dist := to.length() / Game.PX_PER_M
	var tcol := HudStyle.AMBER.lerp(HudStyle.WHITE, 0.25)
	HudStyle.text(self, p + Vector2(0, 98), "INTAKE", 14, tcol)
	HudStyle.text(self, p + Vector2(0, 98), ("%d m" % int(dist)) if dist < 1000.0 else ("%.1f km" % (dist / 1000.0)), 14, tcol, HORIZONTAL_ALIGNMENT_RIGHT, width, HudStyle.mono())
	if dist > 5.0:
		var dir := to.normalized()
		var tip := compass + dir * 70.0
		var side := dir.orthogonal() * 5.0
		draw_colored_polygon(PackedVector2Array([tip, tip - dir * 9.0 + side, tip - dir * 9.0 - side]), tcol)


func _draw_altitude(top: Vector2, ship: ShuttleShip) -> void:
	var h := 150.0
	var bar := Rect2(top, Vector2(10, h))
	draw_rect(bar, Color(HudStyle.CYAN, 0.1))
	var k := clampf(ship.altitude_m / ship.cruise_alt_m, 0.0, 1.0)
	draw_rect(Rect2(Vector2(top.x, top.y + h * (1.0 - k)), Vector2(10, h * k)), Color(HudStyle.CYAN, 0.7))
	draw_rect(bar, Color(HudStyle.CYAN, 0.5), false, 1.0)
	HudStyle.text(self, top + Vector2(-12, -8), "ALT", 12, HudStyle.MUTED)
	HudStyle.text(self, top + Vector2(-14, h + 16), "%.1f" % ship.altitude_m, 13, HudStyle.WHITE, HORIZONTAL_ALIGNMENT_LEFT, -1, HudStyle.mono())
	var gear := "LOCKED" if ship.land_state == ShuttleShip.Land.LANDED else ("DOWN" if ship.skids > 0.5 else "UP")
	HudStyle.text(self, top + Vector2(-26, h + 32), gear, 11, HudStyle.GREEN if gear != "UP" else HudStyle.MUTED)


## One line above the panel: can I land here, and if not, why.
func _draw_landing_line(pos: Vector2, ship: ShuttleShip) -> void:
	var txt := ""
	var col := HudStyle.MUTED
	match ship.land_state:
		ShuttleShip.Land.LANDED:
			txt = "LANDED  ·  X get out  ·  move to lift off"
			col = HudStyle.GREEN
		ShuttleShip.Land.DESCENT:
			txt = "DESCENDING  ·  keep Space held, hold still  ·  %.1f m" % ship.altitude_m
			col = HudStyle.CYAN
		_:
			if ship.land_status == "":
				return
			if ship.land_ok:
				txt = "LAND HERE  ·  hold [Space]  ·  %s" % ship.probe.get("deck_name", "")
				col = HudStyle.GREEN
			else:
				txt = "LAND  ·  " + ship.land_status
	HudStyle.text(self, pos + Vector2(24, 0), txt, 16, col)


func _draw_line_panel(r: Rect2, line: MagLine) -> void:
	HudStyle.draw_panel(self, r, 10.0, Color(HudStyle.CYAN, 0.45), Color(0.02, 0.05, 0.1, 0.5))
	var o := r.position + Vector2(24, 0)
	HudStyle.label(self, o + Vector2(0, 26), "Mag-line")
	var state := "READY  ·  LMB / V hold to hook"
	var col := HudStyle.MUTED
	match line.state:
		MagLine.State.ATTACHED:
			state = "ATTACHED  ·  %s%s" % [line.target_kind, ("  %.1f t" % (line.target_mass / 1000.0)) if line.target_mass > 0.0 else ""]
			col = HudStyle.CYAN
			# A container on the line can go in the hold: say how.
			var petrel := line.ship as ShuttleShip
			if petrel and petrel.hold and is_instance_valid(line.target) and line.target.is_in_group(&"cargo_container"):
				state += "  ·  reel in to stow" if petrel.hold.can_take(line.target) else "  ·  no room in the hold"
		MagLine.State.COOLDOWN:
			state = "COOLDOWN"
	if line.state == MagLine.State.READY and not line.scan_result().is_empty():
		state = "TARGET  ·  %s  ·  hold LMB / V" % line.scan_result().kind
		col = HudStyle.WHITE
	HudStyle.text(self, o + Vector2(96, 26), state, 15, col)
	if line.state != MagLine.State.ATTACHED:
		return
	HudStyle.text(self, o + Vector2(0, 56), "L %4.1f / %d m" % [line.length_m, int(MagLine.MAX_LEN_M)], 15, HudStyle.WHITE, HORIZONTAL_ALIGNMENT_LEFT, -1, HudStyle.mono())
	var bar := Rect2(o + Vector2(140, 46), Vector2(260, 12))
	var k := clampf(line.tension_n / 60000.0, 0.0, 1.0)
	var tc := HudStyle.CYAN if line.tension_n < 30000.0 else (HudStyle.AMBER if line.tension_n < 45000.0 else HudStyle.RED)
	draw_rect(bar, Color(tc, 0.12))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * k, bar.size.y)), tc)
	for kn: float in [30.0, 45.0]:
		var x := bar.position.x + bar.size.x * kn / 60.0
		draw_line(Vector2(x, bar.position.y - 3), Vector2(x, bar.end.y + 3), Color(1, 1, 1, 0.5), 1.0)
	HudStyle.text(self, bar.end + Vector2(8, 0), "%d kN" % int(line.tension_n / 1000.0), 14, tc, HORIZONTAL_ALIGNMENT_LEFT, -1, HudStyle.mono())
	if line.slipping and fmod(_t, 0.3) < 0.18:
		HudStyle.text(self, o + Vector2(140, 74), "CLUTCH SLIP", 13, HudStyle.RED)
	elif line.winch_state != "":
		HudStyle.text(self, o + Vector2(140, 74), "WINCH %s" % line.winch_state, 13, HudStyle.AMBER if line.winch_state == "STALL" else HudStyle.CYAN)


# ================================================================ KESTREL

const DOCK_NAMES := ["FREE", "SOFT CAPTURE", "DOCKED", "UNDOCKING"]


func _sec_color(v: float) -> Color:
	if v <= 0.5:
		return Color(0.25, 0.08, 0.08, 0.9)
	if v < 35.0:
		return HudStyle.RED if fmod(_t, 0.6) < 0.4 else HudStyle.RED.darkened(0.45)
	if v < 70.0:
		return HudStyle.AMBER
	return HudStyle.CYAN.lerp(HudStyle.GREEN, 0.35)


func _draw_frigate(r: Rect2, o: Vector2, ship: FrigateShip) -> void:
	var dmg := ship.damage
	# --- chips: dock state, assist, all stop, alert
	var dname: String = DOCK_NAMES[ship.dock.state]
	var dcol := HudStyle.GREEN if ship.dock.state == FrigateDock.State.LOCKED else (HudStyle.AMBER if ship.dock.busy() else HudStyle.MUTED)
	var chip := Rect2(o + Vector2(0, 204), Vector2(112, 22))
	draw_rect(chip, Color(dcol, 0.14))
	draw_rect(chip, Color(dcol, 0.7), false, 1.0)
	HudStyle.text(self, chip.position + Vector2(8, 17), dname, 14, dcol)
	var fa_col := HudStyle.GREEN if ship.flight_assist else HudStyle.MUTED
	var fa := Rect2(o + Vector2(120, 204), Vector2(112, 22))
	draw_rect(fa, Color(fa_col, 0.14 if ship.flight_assist else 0.06))
	draw_rect(fa, Color(fa_col, 0.7), false, 1.0)
	HudStyle.text(self, fa.position + Vector2(8, 17), "ASSIST %s [F]" % ("ON" if ship.flight_assist else "OFF"), 14, fa_col)
	if ship.red_alert:
		var on := fmod(_t, 0.8) < 0.5
		var ra := Rect2(o + Vector2(240, 204), Vector2(110, 22))
		draw_rect(ra, Color(HudStyle.RED, 0.3 if on else 0.1))
		draw_rect(ra, Color(HudStyle.RED, 0.9), false, 1.0)
		HudStyle.text(self, ra.position + Vector2(10, 17), "RED ALERT", 14, HudStyle.RED if on else HudStyle.RED.darkened(0.3))
	elif ship.all_stop > 0.1:
		HudStyle.text(self, o + Vector2(244, 221), "ALL STOP", 14, HudStyle.AMBER)
	else:
		HudStyle.text(self, o + Vector2(244, 221), "SPACE all stop", 13, HudStyle.MUTED)
	# --- ship schematic (bow up): sections by integrity, shield ring
	var c := r.position + Vector2(PANEL_SIZE.x - 92, 120)
	HudStyle.label(self, c + Vector2(-46, -96), "Systems")
	var sh := clampf(dmg.shield / FrigateDamage.SHIELD_MAX, 0.0, 1.0)
	var ring_col := HudStyle.CYAN if dmg.shield_online else HudStyle.RED.darkened(0.3)
	var segs := 24
	for i in segs:
		var a0 := -PI * 0.5 + TAU * i / segs + 0.03
		var a1 := -PI * 0.5 + TAU * (i + 1) / segs - 0.03
		var lit := float(i) / segs < sh
		_ellipse_arc(c, Vector2(46, 78), a0, a1, Color(ring_col, 0.85 if lit else 0.15), 3.0)
	var D := FrigateDamage.Sec
	var k := 0.9      # px per metre (bow up: ship +X -> screen -Y)
	var mid_x := FrigateShape.CENTRE_X
	var to := func(p: Vector2) -> Vector2: return c + Vector2(p.y, -(p.x - mid_x)) * k
	# Sections as outlined cells of a deck-plan schematic (ship metres,
	# clipped from the generated hull outline so the cells share borders).
	var body := PackedVector2Array()
	for v: Vector2 in FrigateShape.BODY:
		body.append(v / 10.0)
	var ring_o := PackedVector2Array()
	var ring_i := PackedVector2Array()
	for v: Vector2 in FrigateShape.RING_OUTER:
		ring_o.append(v / 10.0)
	for v: Vector2 in FrigateShape.RING_INNER:
		ring_i.append(v / 10.0)
	var bx := FrigateDamage.BOW_X
	var ex := FrigateDamage.ENG_X
	var cells := [
		[D.BOW, Geometry2D.intersect_polygons(body, _box(bx, -30.0, 90.0, 30.0))],
		[D.PORT, Geometry2D.intersect_polygons(body, _box(ex, -30.0, bx, 0.0))],
		[D.STARBOARD, Geometry2D.intersect_polygons(body, _box(ex, 0.0, bx, 30.0))],
		[D.ENGINEERING, Geometry2D.intersect_polygons(body, _box(-70.0, -30.0, ex, 30.0))],
	]
	for cell in cells:
		var col := _sec_color(dmg.integrity[int(cell[0])])
		for poly: PackedVector2Array in cell[1]:
			var sp := PackedVector2Array()
			for v in poly:
				sp.append(to.call(v))
			draw_colored_polygon(sp, Color(col, 0.28))
			sp.append(sp[0])
			draw_polyline(sp, Color(col, 0.95), 1.5, true)
	# Drive rings: hoops, brighter with that ring's output.
	for side: float in [-1.0, 1.0]:
		var col := _sec_color(dmg.integrity[D.NACELLE_S if side > 0.0 else D.NACELLE_P])
		var e := ship.engine_out.z if side > 0.0 else ship.engine_out.y
		for src: PackedVector2Array in [ring_o, ring_i]:
			var sp := PackedVector2Array()
			for v in src:
				sp.append(to.call(Vector2(v.x, v.y * side)))
			sp.append(sp[0])
			draw_polyline(sp, Color(col, 0.95), 1.5, true)
		var mid := PackedVector2Array()
		for v: Vector2 in FrigateShape.RING_MID:
			mid.append(to.call(Vector2(v.x, v.y * side)))
		mid.append(mid[0])
		draw_polyline(mid, Color(0.5, 0.75, 1.0, 0.15 + 0.8 * e), 2.0, true)
	for b in dmg.breaches:
		var p: Vector2 = to.call(b.pos)
		draw_circle(p, 2.5, Color(1.0, 0.45, 0.15, 0.95))
	HudStyle.text(self, c + Vector2(-60, 104), "SHIELD %d%%" % int(round(sh * 100.0)), 14, ring_col, HORIZONTAL_ALIGNMENT_CENTER, 120)
	if dmg.core_breach >= 0.0:
		var on := fmod(_t, 0.4) < 0.25
		HudStyle.text(self, Vector2(r.position.x, r.position.y - 16), "CORE BREACH IN %.1f s  ·  REACTOR CONTAINMENT FAILING" % dmg.core_breach, 20, HudStyle.RED if on else HudStyle.AMBER)


func _box(x0: float, y0: float, x1: float, y1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)])


func _ellipse_arc(c: Vector2, radii: Vector2, a0: float, a1: float, col: Color, w: float) -> void:
	var pts := PackedVector2Array()
	for i in 5:
		var a := lerpf(a0, a1, i / 4.0)
		pts.append(c + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	draw_polyline(pts, col, w, true)
