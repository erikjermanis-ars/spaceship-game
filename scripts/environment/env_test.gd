extends Node2D
## Test bed for the space backdrop. A Camera2D sweeps over the world while
## zooming in and out so parallax/zoom of every layer can be checked, and a few
## pearl-white "hull" shapes stand in for the station to judge contrast.
##
## User args (after `--`):
##   --cam=x,y,zoom   hold the camera still at this world position / zoom
##   --path-speed=1   multiplier for the sweep speed
##   --fps            print FPS every second (run WITHOUT --fixed-fps)
##   --novsync        disable vsync so the FPS print shows real headroom
##   --no-ref         hide the white reference shapes
##   --sky-look=vesper  start on the Vesper sky (read by SpaceBackground); the
##                    camera path and reference shapes move to that look's origin
##   --warp-demo      loop a scripted light-speed jump (see warp_demo.gd)

@onready var cam: Camera2D = $Camera2D
@onready var bg: SpaceBackground = $SpaceBackground

var _t := 0.0
var _fixed := false
var _fixed_pos := Vector2.ZERO
var _fixed_zoom := 1.0
var _speed := 1.0
var _fps_acc := 0.0
var _show_ref := true
var _demo: WarpDemo


func _ready() -> void:
	var c: Dictionary = Game.cmd
	if c.has("cam"):
		var parts := String(c["cam"]).split(",")
		if parts.size() >= 2:
			_fixed = true
			_fixed_pos = Vector2(float(parts[0]), float(parts[1]))
			_fixed_zoom = float(parts[2]) if parts.size() >= 3 else 1.0
	if c.has("path-speed"):
		_speed = float(c["path-speed"])
	if c.has("novsync"):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_show_ref = not c.has("no-ref")
	# Everything here (camera path, reference shapes) is relative to the place
	# the sky look is composed around, so `--sky-look=vesper` frames Vesper.
	position = bg.look_origin()
	cam.make_current()
	if c.has("warp-demo"):
		# The jump preview holds the camera on the ship unless --cam says otherwise.
		_fixed = true
		_demo = WarpDemo.new()
		_demo.name = "WarpDemo"
		add_child(_demo)
		_demo.setup(self, bg, cam)
	_place_camera()
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta * _speed
	_place_camera()
	if Game.cmd.has("fps"):
		_fps_acc += delta
		if _fps_acc >= 1.0:
			_fps_acc = 0.0
			print("[fps] t=%.1f fps=%d process_ms=%.2f draw_calls=%d" % [
				_t, Engine.get_frames_per_second(),
				Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])


func _place_camera() -> void:
	if _fixed:
		cam.position = _fixed_pos
		cam.zoom = Vector2.ONE * _fixed_zoom
		return
	# Lissajous sweep over a big chunk of the world (~ +-4 km by +-2.5 km in
	# px terms: +-4000 x +-2500 px) with a slow breathing zoom 1.0 <-> 0.45.
	cam.position = Vector2(4000.0 * sin(_t * 0.11), 2500.0 * sin(_t * 0.083 + 0.6))
	var z := lerpf(1.0, 0.45, 0.5 - 0.5 * cos(_t * 0.19))
	cam.zoom = Vector2(z, z)


func _draw() -> void:
	if not _show_ref:
		return
	# Stand-ins for station hulls (pearl white / light grey with navy accents)
	# and a ~9 m ship, spread over the world so they pass through the frame.
	var hull := Color("#E9EEF3")
	var grey := Color("#C9D2DC")
	var panel := Color("#8E9AA8")
	var navy := Color("#1D3557")
	for i in 7:
		var c := Vector2(-3600.0 + 1200.0 * float(i), 300.0 * sin(float(i) * 1.7))
		draw_rect(Rect2(c - Vector2(220, 60), Vector2(440, 120)), grey)
		draw_rect(Rect2(c - Vector2(210, 50), Vector2(420, 100)), hull)
		draw_rect(Rect2(c - Vector2(210, 50), Vector2(420, 100)), panel, false, 2.0)
		draw_rect(Rect2(c - Vector2(40, 50), Vector2(80, 100)), navy)
		draw_circle(c + Vector2(0, 400), 140.0, hull)
		draw_arc(c + Vector2(0, 400), 140.0, 0.0, TAU, 64, Color("#2A9D8F"), 4.0, true)
	if _demo != null:
		return   # the demo flies its own ship
	var ship := PackedVector2Array([Vector2(45, 0), Vector2(-40, -26), Vector2(-28, 0), Vector2(-40, 26)])
	draw_colored_polygon(ship, hull)
	draw_polyline(ship + PackedVector2Array([ship[0]]), panel, 2.0, true)

