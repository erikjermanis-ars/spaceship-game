@tool
class_name OnFootArt
extends RefCounted
## Shared palette, materials, light textures and drawing helpers for the
## on-foot layer (walker, landed ship, pad site, interiors).
##
## Same units as the rest of the game: 1 m = 10 px. On foot the camera is
## zoomed ~7.5x, so a 0.1 px line is ~1 screen pixel. Everything is vector
## drawn into cached canvas items (no per-frame cost unless something
## animates), and resolution independent at any zoom.
##
## Drawing goes through OnFootPainter, which batches shapes into one triangle
## array per canvas item and feathers their edges (the Compatibility renderer
## has no 2D MSAA, and per-shape antialiased draw calls are expensive there).

const PX := 10.0

# Palette: matches the station (docs/CONTRACT.md §6) with interior tones.
const PEARL := Color("E9EEF3")
const LIGHT_GREY := Color("C9D2DC")
const PANEL := Color("8E9AA8")
const NAVY := Color("1D3557")
const TEAL := Color("2A9D8F")
const WARM := Color("FFE2A0")
const CYAN := Color("7FE6FF")
const AMBER := Color("FFB000")
const NAV_RED := Color("FF3B3B")
const NAV_GREEN := Color("3BFF7A")
const INK := Color(0.04, 0.06, 0.1, 0.9)         # outlines
const SHADOW := Color(0.0, 0.01, 0.03, 0.32)
## Drop shadows on foot: light from the top-left, short (things are low).
const SHADOW_OFFSET := Vector2(0.9, 1.4)

static var _unshaded: CanvasItemMaterial
static var _add_unshaded: CanvasItemMaterial
static var _soft_box: Texture2D
static var _radial: Texture2D
static var _cone: Texture2D


## Drops shared statics (avoids "leaked ObjectDB" noise at exit).
static func cleanup() -> void:
	_unshaded = null
	_add_unshaded = null
	_soft_box = null
	_radial = null
	_cone = null


## For emissive things (screens, lamps, LEDs, space outside a window): ignores
## 2D lighting and the interior's CanvasModulate darkness.
static func unshaded() -> CanvasItemMaterial:
	if _unshaded == null:
		_unshaded = CanvasItemMaterial.new()
		_unshaded.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	return _unshaded


## Additive + unshaded: glows and light spill sprites.
static func add_unshaded() -> CanvasItemMaterial:
	if _add_unshaded == null:
		_add_unshaded = CanvasItemMaterial.new()
		_add_unshaded.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_add_unshaded.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	return _add_unshaded


## Ceiling-panel light: a rounded box that is flat in the middle and falls
## off smoothly to zero at the edge. Scaled (non-uniformly) to a room's size,
## so a room light fills its room and doesn't bleed through the walls (no
## shadow maps needed for room lights = cheap).
static func soft_box_texture() -> Texture2D:
	if _soft_box == null:
		var n := 128
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		for y in n:
			for x in n:
				var u := absf((x + 0.5) / n * 2.0 - 1.0)
				var v := absf((y + 0.5) / n * 2.0 - 1.0)
				# Superellipse distance: boxy, with soft corners.
				var d := pow(pow(u, 5.0) + pow(v, 5.0), 0.2)
				var k := 1.0 - smoothstep(0.62, 1.0, d)
				img.set_pixel(x, y, Color(1, 1, 1, k * k * (3.0 - 2.0 * k)))
		_soft_box = ImageTexture.create_from_image(img)
	return _soft_box


## Round lamp / glow falloff.
static func radial_texture() -> Texture2D:
	if _radial == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.25, 0.6, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.7), Color(1, 1, 1, 0.18), Color(1, 1, 1, 0)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.width = 128
		t.height = 128
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		_radial = t
	return _radial


## Flashlight beam pointing along +X from the texture centre: a soft cone
## (±26°) with a bright hotspot and a faint wide spill.
static func cone_texture() -> Texture2D:
	if _cone == null:
		var n := 256
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		for y in n:
			for x in n:
				var p := Vector2((x + 0.5) / n * 2.0 - 1.0, (y + 0.5) / n * 2.0 - 1.0)
				var r := p.length()
				var a := absf(p.angle())
				var cone := 1.0 - smoothstep(0.32, 0.5, a)
				var hot := 1.0 - smoothstep(0.0, 0.2, a)
				var spill := 1.0 - smoothstep(0.0, 1.4, a)
				var fall := clampf(1.0 - r, 0.0, 1.0)
				fall = fall * fall
				var near := smoothstep(0.0, 0.08, r)      # no blob at the lens
				var k := (cone * (0.75 + 0.25 * hot) + spill * 0.12) * fall * near
				k += (1.0 - smoothstep(0.0, 0.12, r)) * 0.35  # glow around the wearer
				img.set_pixel(x, y, Color(1, 1, 1, clampf(k, 0.0, 1.0)))
		_cone = ImageTexture.create_from_image(img)
	return _cone


# ---------------------------------------------------------------- shapes --
# Shapes are drawn through OnFootPainter (one batched draw call per item);
# these are just the geometry helpers it and the scripts share.

static func ellipse_poly(c: Vector2, rx: float, ry: float, rot := 0.0, n := 20) -> PackedVector2Array:
	var p := PackedVector2Array()
	p.resize(n)
	for i in n:
		var a := TAU * float(i) / float(n)
		p[i] = c + Vector2(cos(a) * rx, sin(a) * ry).rotated(rot)
	return p


static func rect_poly(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


## Upright text that stays readable whatever the parent's rotation.
static func text(ci: CanvasItem, pos: Vector2, s: String, size: float, col: Color, align := HORIZONTAL_ALIGNMENT_CENTER, width := -1.0, bold := true, rot := 0.0) -> void:
	# Fonts are rasterised at 64 px (MSDF) and scaled down, so tiny world
	# sizes stay razor sharp when the camera zooms in.
	var f: Font = LevelArt.font() if bold else LevelArt.font_regular()
	var k := size / 64.0
	ci.draw_set_transform(pos, rot, Vector2(k, k))
	var w := width / k if width > 0.0 else -1.0
	var x := -w * 0.5 if align == HORIZONTAL_ALIGNMENT_CENTER and w > 0.0 else 0.0
	ci.draw_string(f, Vector2(x, 0), s, align, w, 64, col)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Soft additive glow sprite (unshaded, so it shines in the dark).
static func glow_sprite(parent: Node, pos: Vector2, col: Color, radius_px: float, z := 0) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = radial_texture()
	s.material = add_unshaded()
	s.modulate = col
	s.position = pos
	s.scale = Vector2.ONE * (radius_px * 2.0 / 128.0)
	s.z_index = z
	parent.add_child(s)
	return s
