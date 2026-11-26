class_name HudStyle
extends RefCounted
## Shared look for the HUD: palette, fonts and the chamfered-panel primitive.
## Original "clean civic tech" style: thin cyan/white rules, dark translucent
## glass, amber for warnings. No franchise styling.

const CYAN := Color(0.5, 0.9, 1.0)          # #7FE6FF
const CYAN_DIM := Color(0.5, 0.9, 1.0, 0.45)
const WHITE := Color(0.94, 0.96, 0.98)
const MUTED := Color(0.62, 0.7, 0.78)
const AMBER := Color(1.0, 0.69, 0.0)         # #FFB000
const RED := Color(1.0, 0.23, 0.23)         # #FF3B3B
const GREEN := Color(0.23, 1.0, 0.48)       # #3BFF7A
const PANEL := Color(0.02, 0.05, 0.1, 0.62)
const PANEL_EDGE := Color(0.5, 0.9, 1.0, 0.55)

static var _font: Font
static var _font_mono: Font

## Proportional UI font. Tries clean condensed system faces (macOS ships DIN
## Alternate / Avenir Next Condensed); falls back to Godot's default font.
static func font() -> Font:
	if _font == null:
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray(["DIN Alternate", "Avenir Next Condensed", "Bahnschrift", "Helvetica Neue", "Arial"])
		sf.font_weight = 500
		sf.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		sf.fallbacks = [ThemeDB.fallback_font]
		_font = sf
	return _font

## Tabular digits for timers and readouts that change every frame.
static func mono() -> Font:
	if _font_mono == null:
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray(["DIN Alternate", "SF Mono", "Menlo", "Consolas", "DejaVu Sans Mono"])
		sf.fallbacks = [ThemeDB.fallback_font]
		_font_mono = sf
	return _font_mono

## Chamfered panel: translucent fill, thin outline, a brighter accent along
## the top-left edge and small corner ticks.
static func draw_panel(ci: CanvasItem, r: Rect2, cut := 14.0, edge := PANEL_EDGE, fill := PANEL) -> void:
	var p := PackedVector2Array([
		r.position + Vector2(cut, 0), Vector2(r.end.x, r.position.y),
		Vector2(r.end.x, r.end.y - cut), Vector2(r.end.x - cut, r.end.y),
		Vector2(r.position.x, r.end.y), r.position + Vector2(0, cut)])
	ci.draw_colored_polygon(p, fill)
	var outline := p.duplicate()
	outline.append(p[0])
	ci.draw_polyline(outline, Color(edge.r, edge.g, edge.b, edge.a * 0.6), 1.0, true)
	# Accent: brighter rule on the top edge, short.
	ci.draw_line(r.position + Vector2(cut, 0), r.position + Vector2(cut + minf(90.0, r.size.x * 0.35), 0), edge, 2.0, true)
	ci.draw_line(Vector2(r.end.x - cut - 18.0, r.end.y), Vector2(r.end.x - cut, r.end.y), edge, 2.0, true)

static func text(ci: CanvasItem, pos: Vector2, s: String, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, f: Font = null) -> void:
	ci.draw_string(f if f else font(), pos, s, align, width, size, col)

## Small caps-style label: letter-spaced, muted.
static func label(ci: CanvasItem, pos: Vector2, s: String, col := MUTED, size := 15) -> void:
	ci.draw_string(font(), pos, s.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

## Segmented horizontal bar (hull / boost).
static func seg_bar(ci: CanvasItem, r: Rect2, frac: float, col: Color, segments := 20) -> void:
	var gap := 3.0
	var w := (r.size.x - gap * (segments - 1)) / segments
	var lit := frac * segments
	for i in segments:
		var x := r.position.x + i * (w + gap)
		var rect := Rect2(x, r.position.y, w, r.size.y)
		var on := clampf(lit - i, 0.0, 1.0)
		ci.draw_rect(rect, Color(col.r, col.g, col.b, 0.12))
		if on > 0.0:
			ci.draw_rect(Rect2(x, r.position.y, w * on, r.size.y), col)

## Key-cap prompt: a small outlined key with its label to the right, e.g.
## [X] EXIT SHIP. `pos` is the left end of the baseline row. Returns the width.
static func key_hint(ci: CanvasItem, pos: Vector2, key: String, label_text: String, a := 1.0, size := 18, col := CYAN) -> float:
	var f := font()
	var kw := maxf(f.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 16.0, size * 1.6)
	var kr := Rect2(pos + Vector2(0, -size * 1.05), Vector2(kw, size * 1.45))
	ci.draw_rect(kr, Color(0.02, 0.05, 0.1, 0.8 * a))
	ci.draw_rect(kr, Color(col, 0.9 * a), false, 1.5, true)
	ci.draw_line(kr.position + Vector2(2, kr.size.y + 1.5), kr.end + Vector2(-2, 1.5), Color(col, 0.45 * a), 2.0)
	ci.draw_string(f, Vector2(kr.position.x, pos.y), key, HORIZONTAL_ALIGNMENT_CENTER, kw, size, Color(WHITE, a))
	ci.draw_string(f, pos + Vector2(kw + 10.0, 0), label_text.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, size - 1, Color(WHITE, 0.92 * a))
	return kw + 10.0 + f.get_string_size(label_text.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, size - 1).x
