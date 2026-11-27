class_name WarpFX
extends CanvasLayer
## The screen effect of a faster-than-light jump. It knows nothing about ships
## or sectors: whoever runs the jump animates the properties below every frame
## and this node turns them into picture. It draws above the world (layer 0)
## and below the HUD (layer 10).
##
## Stages, in the order a jump plays them:
##   charge  energy gathers on the ship: the picture is pinched towards it,
##           motes spiral in, rings collapse, a core glow builds.
##   streak  the real stars smear into radial streaks, extra streaks shoot out
##           and a shock ring bursts when it peaks.
##   flash   white-out that hides the cut.
##   tunnel  the opaque light-speed tunnel; `progress` drifts its colour from
##           the origin's palette to the destination's.
## At all-zero every rect is hidden and _process returns at once, so the node
## costs nothing between jumps. For its first few frames it draws every pass
## once with no visible effect, so the shaders compile at creation and not on
## the first frame of the first jump.
##
## Five fullscreen rects at most, never all at once: lens + streaks while the
## world is visible, tunnel (+ ship snapshot) while it is not, flash on top.

const FX := "res://assets/art/fx/"
const EPS := 0.002
## Seconds the shock ring takes to cross the screen.
const SHOCK_TIME := 0.75
## Side of the bow-shock quad, in ship lengths.
const BOW_EXTENT := 5.0
## Frames every pass is drawn (invisibly) after creation to compile shaders.
const WARM_FRAMES := 3
## The shock ring bursts when `streak` rises through this value: early enough
## that the ring has crossed the screen before the flash whites it out.
const SHOCK_AT := 0.5

## Spool-up: energy gathering on the ship.
var charge := 0.0
## Stars stretching into radial streaks as the ship leaps.
var streak := 0.0
## The light-speed tunnel; covers the world completely at 1.
var tunnel := 0.0
## Full-screen white-out (the cut hides under it).
var flash := 0.0
## 0..1 along the journey: drifts the tunnel's colour.
var progress := 0.0
## +1 = towards Vesper (cool to warm), -1 = back to Meridian (warm to cool).
var direction := 1.0
## The ship's on-screen heading in radians. The vanishing point sits ahead of
## the ship along it, and the bow shock faces it.
var heading := 0.0

## How far ahead of the ship the vanishing point sits once the ship has leapt,
## as a fraction of the view height. 0 puts it under the ship. A big snapshot
## pushes it farther out (clear of the bow), up to `focus_lead_max`.
@export var focus_lead := 0.24
@export var focus_lead_max := 0.40
## Bend the picture on screen while charging and streaking (reads the screen
## texture). Off leaves only the additive overlays.
@export var screen_lens := true

var _time := 0.0
var _shock := 1.0              # 0..1 ring progress, 1 = idle
var _prev_streak := 0.0
var _active := false
var _warm_left := WARM_FRAMES
var _has_ship := false
var _ship_pos := Vector2.ZERO
var _ship_rot := 0.0
var _ship_len := 0.0           # snapshot length on screen, canvas units

var _lens: ColorRect
var _streaks: ColorRect
var _tunnel: ColorRect
var _flash: ColorRect
var _ship_root: Node2D
var _bow_pivot: Node2D
var _bow: ColorRect
var _ship: Sprite2D
var _lens_mat: ShaderMaterial
var _streak_mat: ShaderMaterial
var _tunnel_mat: ShaderMaterial
var _flash_mat: ShaderMaterial
var _bow_mat: ShaderMaterial
var _ship_mat: ShaderMaterial


func _ready() -> void:
	layer = 5
	# After whoever animates us this frame, so the uniforms are never a frame late.
	process_priority = 900
	_lens = _full_rect("Lens", "warp_lens.gdshader")
	_lens_mat = _lens.material
	_streaks = _full_rect("Streaks", "warp_streak.gdshader")
	_streak_mat = _streaks.material
	_tunnel = _full_rect("Tunnel", "warp_tunnel.gdshader")
	_tunnel_mat = _tunnel.material
	_tunnel_mat.set_shader_parameter("noise_tex", _bake_noise())
	_build_ship()
	_flash = _full_rect("Flash", "warp_flash.gdshader")
	_flash_mat = _flash.material
	# Warm-up: with these values the lens copies the screen unchanged and the
	# other passes add nothing, so drawing them is invisible.
	_tunnel_mat.set_shader_parameter("tunnel", 0.0)
	_bow_mat.set_shader_parameter("intensity", 0.0)
	_bow.size = Vector2(64.0, 64.0)
	_ship.texture = EnvArt.glow_texture()
	_ship.self_modulate.a = 0.0


## Draw this texture of the ship over the tunnel (the real ship is in the
## world, which the tunnel covers). `screen_pos` is in viewport canvas units,
## the rotation and scale are what a Sprite2D would need to match the ship on
## screen; the texture's +x is taken to be the bow. Pass null to draw none.
func set_ship_snapshot(tex: Texture2D, screen_pos: Vector2, p_rotation: float, p_scale: Vector2) -> void:
	_has_ship = tex != null
	_ship.texture = tex
	if not _has_ship:
		return
	_ship_pos = screen_pos
	_ship_rot = p_rotation
	_ship.scale = p_scale
	# The bow shock is sized from the ship's length on screen.
	_ship_len = maxf(float(tex.get_width()) * absf(p_scale.x), 24.0)
	var side := _ship_len * BOW_EXTENT
	_bow.size = Vector2(side, side)
	_bow.position = -_bow.size * 0.5


func clear_ship_snapshot() -> void:
	_has_ship = false
	_ship.texture = null


func _full_rect(rect_name: String, shader_file: String) -> ColorRect:
	var r := ColorRect.new()
	r.name = rect_name
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	var m := ShaderMaterial.new()
	m.shader = load(FX + shader_file)
	r.material = m
	add_child(r)
	return r


func _build_ship() -> void:
	_ship_root = Node2D.new()
	_ship_root.name = "ShipSnapshot"
	add_child(_ship_root)
	_bow_pivot = Node2D.new()
	_ship_root.add_child(_bow_pivot)
	_bow = ColorRect.new()
	_bow.name = "BowShock"
	_bow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bow_mat = ShaderMaterial.new()
	_bow_mat.shader = load(FX + "warp_bow.gdshader")
	_bow_mat.set_shader_parameter("extent", BOW_EXTENT)
	_bow.material = _bow_mat
	_bow_pivot.add_child(_bow)
	_ship = Sprite2D.new()
	_ship.name = "Ship"
	_ship_mat = ShaderMaterial.new()
	_ship_mat.shader = load(FX + "warp_ship.gdshader")
	_ship.material = _ship_mat
	_ship_root.add_child(_ship)


## One small tileable noise texture for the tunnel, rendered once.
func _bake_noise() -> Texture2D:
	var vp := SubViewport.new()
	vp.name = "WarpNoiseBake"
	vp.size = Vector2i(512, 512)
	vp.disable_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var rect := ColorRect.new()
	rect.size = Vector2(vp.size)
	var mat := ShaderMaterial.new()
	mat.shader = load(FX + "warp_noise_bake.gdshader")
	rect.material = mat
	vp.add_child(rect)
	add_child(vp)
	return vp.get_texture()


func _hide_all() -> void:
	_lens.visible = false
	_streaks.visible = false
	_tunnel.visible = false
	_flash.visible = false
	_ship_root.visible = false


func _process(delta: float) -> void:
	var busy := charge > EPS or streak > EPS or tunnel > EPS or flash > EPS or _shock < 1.0
	if _warm_left > 0:
		_warm_left -= 1
		if _warm_left == 0:
			if not _has_ship:
				_ship.texture = null
			_hide_all()
		elif not busy:
			return
	if not busy:
		if _active:
			_active = false
			_hide_all()
			_time = 0.0
		_prev_streak = streak
		return
	_active = true
	_time += delta
	_update_shock(delta)

	var view := get_viewport().get_visible_rect().size
	var ship_at := _ship_pos if _has_ship else view * 0.5
	# The vanishing point slides out ahead of the ship as it leaps.
	var reach := focus_lead * view.y
	if _has_ship:
		reach = clampf(_ship_len * 0.8, reach, maxf(focus_lead_max * view.y, reach))
	var lead := smoothstep(0.0, 1.0, maxf(streak, tunnel)) * reach
	var focus := ship_at + Vector2.from_angle(heading) * lead
	var m := progress if direction >= 0.0 else 1.0 - progress

	var world_seen := tunnel < 1.0 - EPS
	var warping := charge > EPS or streak > EPS or _shock < 1.0
	_lens.visible = screen_lens and world_seen and warping
	if _lens.visible:
		_lens_mat.set_shader_parameter("view_size", view)
		_lens_mat.set_shader_parameter("focus", focus)
		_lens_mat.set_shader_parameter("time", _time)
		_lens_mat.set_shader_parameter("charge", charge)
		_lens_mat.set_shader_parameter("streak", streak)
		_lens_mat.set_shader_parameter("shock", _shock)
	_streaks.visible = world_seen and warping
	if _streaks.visible:
		_streak_mat.set_shader_parameter("view_size", view)
		_streak_mat.set_shader_parameter("focus", focus)
		_streak_mat.set_shader_parameter("time", _time)
		_streak_mat.set_shader_parameter("charge", charge)
		_streak_mat.set_shader_parameter("streak", streak)
		_streak_mat.set_shader_parameter("shock", _shock)
		_streak_mat.set_shader_parameter("mix_m", m)
	_tunnel.visible = tunnel > EPS
	if _tunnel.visible:
		_tunnel_mat.set_shader_parameter("view_size", view)
		_tunnel_mat.set_shader_parameter("focus", focus)
		_tunnel_mat.set_shader_parameter("r_max", _farthest_corner(focus, view) / view.y)
		_tunnel_mat.set_shader_parameter("time", _time)
		_tunnel_mat.set_shader_parameter("tunnel", tunnel)
		_tunnel_mat.set_shader_parameter("mix_m", m)
		_tunnel_mat.set_shader_parameter("progress", progress)
	_update_ship(m)
	_flash.visible = flash > EPS
	if _flash.visible:
		_flash_mat.set_shader_parameter("view_size", view)
		_flash_mat.set_shader_parameter("focus", focus)
		_flash_mat.set_shader_parameter("flash", flash)
		# The flash carries a breath of the place it opens onto.
		_flash_mat.set_shader_parameter("tint", Vector3(0.80, 0.93, 1.0).lerp(Vector3(1.0, 0.90, 0.74), m))


## The shock ring is timed here, not by the caller: it bursts once as the
## streaks take off on the way out, and once more when they start to collapse on
## arrival (the ship punching back into normal space).
func _update_shock(delta: float) -> void:
	var leaping := _prev_streak < SHOCK_AT and streak >= SHOCK_AT
	var arriving := _prev_streak >= 0.98 and streak < 0.98 and tunnel < 0.5
	if leaping or arriving:
		_shock = 0.0
	elif _shock < 1.0:
		_shock = minf(_shock + delta / SHOCK_TIME, 1.0)
	_prev_streak = streak


func _update_ship(m: float) -> void:
	# The snapshot fades in with the tunnel; the bow shock already starts to
	# form around the real ship while the stars streak.
	var shown := maxf(smoothstep(0.0, 0.3, tunnel), streak * streak * 0.8)
	_ship_root.visible = _has_ship and shown > EPS
	if not _ship_root.visible:
		return
	# Shudder: two beating sines per axis, a pixel or two, plus a hair of roll.
	var amp := 1.6 * tunnel
	var jitter := Vector2(
		sin(_time * 47.0) + sin(_time * 31.3 + 1.0),
		sin(_time * 41.0 + 2.0) + sin(_time * 27.7)) * 0.5 * amp
	_ship_root.position = _ship_pos + jitter
	_ship.rotation = _ship_rot + 0.004 * tunnel * sin(_time * 23.0)
	_ship.self_modulate.a = smoothstep(0.0, 0.3, tunnel)
	_bow_pivot.rotation = heading
	_ship_mat.set_shader_parameter("time", _time)
	_ship_mat.set_shader_parameter("glow", tunnel)
	_ship_mat.set_shader_parameter("mix_m", m)
	_bow_mat.set_shader_parameter("time", _time)
	_bow_mat.set_shader_parameter("intensity", shown)
	_bow_mat.set_shader_parameter("mix_m", m)


static func _farthest_corner(from: Vector2, view: Vector2) -> float:
	var dx := maxf(from.x, view.x - from.x)
	var dy := maxf(from.y, view.y - from.y)
	return sqrt(dx * dx + dy * dy)
