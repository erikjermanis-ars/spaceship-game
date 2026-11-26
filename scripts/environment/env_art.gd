class_name EnvArt
extends RefCounted
## Shared palette, sun direction and tiny helpers for the space backdrop.
## Background art is deliberately darker and bluer than gameplay structure
## (contract section 6) so pearl-white station hulls always pop in front of it.

const HULL_DARK := Color(0.062, 0.080, 0.122)
const HULL_MID := Color(0.105, 0.130, 0.185)
const HULL_PANEL := Color(0.150, 0.180, 0.240)
const RIM_LIGHT := Color(0.47, 0.56, 0.70)
const WINDOW_WARM := Color("#FFE2A0")
const TECH_CYAN := Color("#7FE6FF")
const NAV_RED := Color("#FF3B3B")
const NAV_GREEN := Color("#3BFF7A")
const HAZARD_AMBER := Color("#FFB000")
const STROBE := Color(0.95, 0.97, 1.0)

static var _glow: Texture2D

## Soft radial sprite used for every additive light dot (cheap fake bloom).
static func glow_texture() -> Texture2D:
	if _glow == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.12, 0.35, 1.0])
		g.colors = PackedColorArray([
			Color(1, 1, 1, 1), Color(1, 1, 1, 0.7), Color(1, 1, 1, 0.16), Color(1, 1, 1, 0)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.width = 64
		t.height = 64
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		_glow = t
	return _glow

## Additive CanvasItemMaterial (glow is faked additively, renderer-agnostic).
static func additive_material() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return m

## Blink envelope: 1 at the flash, decaying with `decay` per second.
## period <= 0 means a steady light.
static func blink(t: float, period: float, phase: float, decay: float) -> float:
	if period <= 0.0:
		return 1.0
	var k := fposmod(t + phase, period)
	return exp(-k * decay)

static func draw_glow(ci: CanvasItem, pos: Vector2, size: float, col: Color) -> void:
	var half := size * 0.5
	ci.draw_texture_rect(glow_texture(), Rect2(pos.x - half, pos.y - half, size, size), false, col)
