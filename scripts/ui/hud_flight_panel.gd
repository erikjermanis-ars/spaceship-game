extends Control
## Bottom-left flight panel: speed, heading & drift, hull and boost bars,
## flight-assist state and a live thruster diagram (top-down ship icon whose
## jets light up from the ship's actual thruster outputs).

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

	# --- boost ---
	var bf := clampf(float(GameplayUtil.pget(ship, &"boost_energy", 1.0)), 0.0, 1.0)
	var boosting := bool(GameplayUtil.pget(ship, &"boosting", false))
	var bcol := Color(0.75, 0.95, 1.0) if boosting else HudStyle.CYAN_DIM.lerp(HudStyle.CYAN, 0.5)
	if bf < 0.15 and not boosting:
		bcol = HudStyle.AMBER
	HudStyle.label(self, o + Vector2(0, 190), "Boost")
	HudStyle.seg_bar(self, Rect2(o + Vector2(56, 178), Vector2(250, 12)), bf, bcol, 20)
	HudStyle.text(self, o + Vector2(316, 191), "%d%%" % int(round(bf * 100.0)), 18, bcol, HORIZONTAL_ALIGNMENT_LEFT, -1, HudStyle.mono())

	# --- flight assist ---
	var fa := bool(GameplayUtil.pget(ship, &"flight_assist", false))
	var fa_rect := Rect2(o + Vector2(0, 204), Vector2(150, 22))
	var fa_col := HudStyle.GREEN if fa else HudStyle.MUTED
	draw_rect(fa_rect, Color(fa_col.r, fa_col.g, fa_col.b, 0.14 if fa else 0.06))
	draw_rect(fa_rect, Color(fa_col.r, fa_col.g, fa_col.b, 0.7), false, 1.0)
	HudStyle.text(self, fa_rect.position + Vector2(8, 17), "FLIGHT ASSIST  %s" % ("ON" if fa else "OFF"), 14, fa_col)
	HudStyle.text(self, fa_rect.position + Vector2(160, 17), "[F]", 14, HudStyle.MUTED)

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
	var boosting := bool(GameplayUtil.pget(ship, &"boosting", false))
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

	var hot := Color(0.75, 0.95, 1.0) if boosting else HudStyle.CYAN
	# Main engine (forward thrust): flame out of the stern pod.
	if main > 0.02:
		_jet(pod + Vector2(0, 18), Vector2.DOWN, main * (1.6 if boosting else 1.0), hot)
	# Retro: twin jets out of the bow, pointing forward.
	elif main < -0.02:
		_jet(head + Vector2(-9, -12), Vector2(-0.25, -1).normalized(), -main, hot)
		_jet(head + Vector2(9, -12), Vector2(0.25, -1).normalized(), -main, hot)
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

func _jet(at: Vector2, dir: Vector2, amount: float, col: Color) -> void:
	var a := clampf(amount, 0.0, 2.0)
	var flick := 0.85 + 0.15 * sin(_t * 47.0 + at.x)
	var jet_len := (10.0 + 26.0 * a) * flick
	var side := dir.orthogonal() * (4.0 + 2.0 * a)
	var tri := PackedVector2Array([at + side, at + dir * jet_len, at - side])
	draw_colored_polygon(tri, Color(col.r, col.g, col.b, 0.85))
	draw_line(at, at + dir * jet_len * 0.55, Color(1, 1, 1, 0.9), 2.0, true)
