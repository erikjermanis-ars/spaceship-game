@tool
class_name LevelArt
extends RefCounted
## Shared palette, textures, materials, fonts and geometry helpers for the
## procedural "station kit". Everything is lazily created once and shared, so
## hundreds of modules reuse the same glow texture / materials (= batching).

const GameScript := preload("res://scripts/autoload/game.gd")
const PX := 10.0  # px per metre (mirrors Game.PX_PER_M; usable in the editor)

# ------------------------------------------------------------ palette ------
const PEARL := Color("E9EEF3")
const LIGHT_GREY := Color("C9D2DC")
const PANEL := Color("8E9AA8")
const NAVY := Color("1D3557")
const TEAL := Color("2A9D8F")
const WARM := Color("FFE2A0")
const CYAN := Color("7FE6FF")
const NAV_RED := Color("FF3B3B")
const NAV_GREEN := Color("3BFF7A")
const AMBER := Color("FFB000")
const WHITE := Color(1, 1, 1)

const OUTLINE := Color(0.03, 0.05, 0.09, 0.92)
const HULL_SHADOW := Color(0.0, 0.0, 0.02, 0.42)
const OVER_SHADOW := Color(0.0, 0.0, 0.02, 0.26)
const STRIPE_DARK := Color("17202B")

## Light comes from the top-left of the screen: lit edges face this way.
const LIGHT_DIR := Vector2(-0.6, -0.8)

# ------------------------------------------------------- depth bands ------
## Fake 2.5D: below-deck layers scale about the camera centre by DECK_SCALE,
## overhead layers by OVER_SCALE (true perspective parallax, aligned exactly
## under the camera). Colliding structure always stays at 1.0.
const DECK_SCALE := 0.95
const OVER_SCALE := 1.06
## Shadows are offsets in GLOBAL space (fixed sun), in px.
const HULL_SHADOW_OFFSET := Vector2(16, 24)
const OVER_SHADOW_OFFSET := Vector2(24, 36)

## Hull styles: edge = bevel/outer colour, fill = plate colour, rim = lit rim,
## shade = unlit rim, bevel = bevel width in metres.
const STYLES := {
	&"pearl": {"edge": Color("BFC9D4"), "fill": Color("E9EEF3"), "rim": Color(1, 1, 1), "shade": Color("8E9AA8"), "bevel": 0.9},
	&"grey": {"edge": Color("98A4B3"), "fill": Color("C3CCD6"), "rim": Color("F4F7FA"), "shade": Color("6D7A8A"), "bevel": 0.8},
	&"steel": {"edge": Color("6B7787"), "fill": Color("8E9AA8"), "rim": Color("DCE3EA"), "shade": Color("4A5564"), "bevel": 0.6},
	&"navy": {"edge": Color("15284A"), "fill": Color("1D3557"), "rim": Color("9DB8DC"), "shade": Color("0C1830"), "bevel": 0.6},
	&"teal": {"edge": Color("1F7A70"), "fill": Color("2A9D8F"), "rim": Color("B8F2EA"), "shade": Color("155A52"), "bevel": 0.6},
	&"amber": {"edge": Color("C98A00"), "fill": Color("FFB000"), "rim": Color("FFF1C9"), "shade": Color("8A5E00"), "bevel": 0.5},
	&"solar": {"edge": Color("0F1E3D"), "fill": Color("1A2E5C"), "rim": Color("DDE8F5"), "shade": Color("A8B6C8"), "bevel": 0.6},
	&"glass": {"edge": Color("23485A"), "fill": Color("2B5D6E"), "rim": Color("D8F6FF"), "shade": Color("7EA4B4"), "bevel": 0.6},
}

## Corporate liveries for cargo containers / ships (fictional companies).
const LIVERIES := [
	{"name": "HELIOS", "color": Color("E76F51")},
	{"name": "KESTREL", "color": Color("2A9D8F")},
	{"name": "VEGA LOG", "color": Color("1D3557")},
	{"name": "AURORA", "color": Color("F4A261")},
	{"name": "TIDEWAY", "color": Color("4EA8DE")},
	{"name": "MERIDIAN", "color": Color("E9EEF3")},
	{"name": "NORDHAV", "color": Color("6D597A")},
	{"name": "CASSINI", "color": Color("8AB17D")},
]

static var _glow: Texture2D
static var _add_mat: CanvasItemMaterial
static var _blink_mat: ShaderMaterial
static var _font: Font
static var _font_regular: Font

## Registry of depth-band canvas items for the Level's parallax pass.
static var depth_layers: Array = []


## Drops shared static resources (avoids "leaked ObjectDB" noise at exit).
static func cleanup() -> void:
	_glow = null
	_add_mat = null
	_blink_mat = null
	_font = null
	_font_regular = null
	depth_layers.clear()


static func glow_texture() -> Texture2D:
	if _glow == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.12, 0.35, 0.65, 1.0])
		g.colors = PackedColorArray([
			Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.62), Color(1, 1, 1, 0.22),
			Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.0)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.width = 128
		t.height = 128
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		_glow = t
	return _glow


static func add_material() -> CanvasItemMaterial:
	if _add_mat == null:
		_add_mat = CanvasItemMaterial.new()
		_add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _add_mat


static func blink_material() -> ShaderMaterial:
	if _blink_mat == null:
		_blink_mat = ShaderMaterial.new()
		_blink_mat.shader = load("res://scripts/level/shaders/beacon_blink.gdshader")
	return _blink_mat


## Condensed bold signage font (MSDF => razor sharp at any zoom).
static func font() -> Font:
	if _font == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Avenir Next Condensed", "DIN Condensed", "Helvetica Neue", "Arial Narrow", "Arial"])
		f.font_weight = 700
		f.multichannel_signed_distance_field = true
		f.msdf_pixel_range = 14
		f.msdf_size = 64
		f.allow_system_fallback = true
		_font = f
	return _font


static func font_regular() -> Font:
	if _font_regular == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Avenir Next Condensed", "Helvetica Neue", "Arial"])
		f.font_weight = 500
		f.multichannel_signed_distance_field = true
		f.msdf_pixel_range = 14
		f.msdf_size = 64
		_font_regular = f
	return _font_regular


## False in headless runs (the dummy audio driver never releases playbacks,
## which spams "leaked instance" warnings at exit).
static func audio_enabled() -> bool:
	return DisplayServer.get_name() != "headless"


## Encodes a blink pattern into a colour alpha for beacon_blink.gdshader.
static func blink_color(c: Color, phase: float, strobe: bool) -> Color:
	var a := fposmod(phase, 1.0) * 0.5 * 0.998
	if strobe:
		a += 0.5
	return Color(c.r, c.g, c.b, a)

# ------------------------------------------------------ geometry (px) -----

static func rect_poly(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


## Rect given in METRES, returned in px.
static func rect_m(x0: float, y0: float, x1: float, y1: float) -> PackedVector2Array:
	return rect_poly(Rect2(Vector2(minf(x0, x1), minf(y0, y1)) * PX, Vector2(absf(x1 - x0), absf(y1 - y0)) * PX))


static func circle_poly(c: Vector2, r: float, n := 32, a0 := 0.0) -> PackedVector2Array:
	var p := PackedVector2Array()
	p.resize(n)
	for i in n:
		var a := a0 + TAU * float(i) / float(n)
		p[i] = c + Vector2(cos(a), sin(a)) * r
	return p


## Rounded rectangle (px), `rad` corner radius.
static func rounded_rect(r: Rect2, rad: float, seg := 4) -> PackedVector2Array:
	var p := PackedVector2Array()
	rad = minf(rad, minf(r.size.x, r.size.y) * 0.5)
	var corners := [
		[Vector2(r.end.x - rad, r.position.y + rad), -PI * 0.5],
		[Vector2(r.end.x - rad, r.end.y - rad), 0.0],
		[Vector2(r.position.x + rad, r.end.y - rad), PI * 0.5],
		[Vector2(r.position.x + rad, r.position.y + rad), PI],
	]
	for c in corners:
		for i in seg + 1:
			var a: float = c[1] + PI * 0.5 * float(i) / float(seg)
			p.append(c[0] + Vector2(cos(a), sin(a)) * rad)
	return p


## Capsule/oblong along X centred on `c` (px).
static func capsule(c: Vector2, length: float, width: float, seg := 8) -> PackedVector2Array:
	var p := PackedVector2Array()
	var h := width * 0.5
	var l := maxf(length * 0.5 - h, 0.0)
	for i in seg + 1:
		var a := -PI * 0.5 + PI * float(i) / float(seg)
		p.append(c + Vector2(l, 0) + Vector2(cos(a), sin(a)) * h)
	for i in seg + 1:
		var a := PI * 0.5 + PI * float(i) / float(seg)
		p.append(c + Vector2(-l, 0) + Vector2(cos(a), sin(a)) * h)
	return p


## Annular sector polygon (outer arc then inner arc back), angles in radians.
static func arc_band(c: Vector2, r_in: float, r_out: float, a0: float, a1: float, n := 32) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in n + 1:
		var a := lerpf(a0, a1, float(i) / float(n))
		p.append(c + Vector2(cos(a), sin(a)) * r_out)
	for i in range(n, -1, -1):
		var a := lerpf(a0, a1, float(i) / float(n))
		p.append(c + Vector2(cos(a), sin(a)) * r_in)
	return p


## Polyline along an arc.
static func arc_points(c: Vector2, r: float, a0: float, a1: float, n := 32) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in n + 1:
		var a := lerpf(a0, a1, float(i) / float(n))
		p.append(c + Vector2(cos(a), sin(a)) * r)
	return p


## Oriented box (px): centre, length along `dir`, width across.
static func obox(c: Vector2, dir: Vector2, length: float, width: float) -> PackedVector2Array:
	var d := dir.normalized() * length * 0.5
	var n := dir.normalized().orthogonal() * width * 0.5
	return PackedVector2Array([c - d - n, c + d - n, c + d + n, c - d + n])


static func transform_poly(xf: Transform2D, poly: PackedVector2Array) -> PackedVector2Array:
	return xf * poly


static func poly_bounds(poly: PackedVector2Array) -> Rect2:
	if poly.is_empty():
		return Rect2()
	var r := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		r = r.expand(p)
	return r


## Deterministic hash -> [0,1) for stable "random" decoration.
static func hash01(i: int, salt := 0) -> float:
	var h := (i * 73856093) ^ (salt * 19349663) ^ 0x5bd1e995
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFF) / 65536.0
