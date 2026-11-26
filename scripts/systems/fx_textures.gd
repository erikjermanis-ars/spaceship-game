class_name FxTextures
extends RefCounted
## Procedurally generated, cached FX textures and materials.
## Everything is built once at first use (a few small images / gradient
## textures), so no image assets need importing and every effect shares the
## same GPU textures.

static var _cache := {}

## Soft round glow (white, alpha falls off smoothly). Use with additive blend.
static func glow() -> Texture2D:
	if not _cache.has("glow"):
		_cache["glow"] = _radial(128, PackedFloat32Array([0.0, 0.18, 0.45, 1.0]), [
			Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.12), Color(1, 1, 1, 0)])
	return _cache["glow"]

## Tight hot core glow (sharper falloff) for flashes.
static func hot_core() -> Texture2D:
	if not _cache.has("hot_core"):
		_cache["hot_core"] = _radial(64, PackedFloat32Array([0.0, 0.25, 0.6, 1.0]), [
			Color(1, 1, 1, 1), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0.15), Color(1, 1, 1, 0)])
	return _cache["hot_core"]

## Thin bright ring with soft edges (shockwaves). Ring sits at ~85% radius.
static func ring() -> Texture2D:
	if not _cache.has("ring"):
		_cache["ring"] = _radial(256, PackedFloat32Array([0.0, 0.62, 0.8, 0.86, 0.92, 1.0]), [
			Color(1, 1, 1, 0), Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.35),
			Color(1, 1, 1, 1), Color(1, 1, 1, 0.25), Color(1, 1, 1, 0)])
	return _cache["ring"]

## Soft puff for smoke (use with normal blend).
static func smoke() -> Texture2D:
	if not _cache.has("smoke"):
		_cache["smoke"] = _radial(64, PackedFloat32Array([0.0, 0.4, 1.0]), [
			Color(1, 1, 1, 0.7), Color(1, 1, 1, 0.35), Color(1, 1, 1, 0)])
	return _cache["smoke"]

## Dark scorch / scuff mark (normal blend).
static func scorch() -> Texture2D:
	if not _cache.has("scorch"):
		_cache["scorch"] = _radial(64, PackedFloat32Array([0.0, 0.35, 0.7, 1.0]), [
			Color(0.05, 0.05, 0.06, 0.85), Color(0.12, 0.11, 0.11, 0.6),
			Color(0.2, 0.2, 0.22, 0.2), Color(0.2, 0.2, 0.22, 0)])
	return _cache["scorch"]

## Vertical streak, bright in the middle, used for velocity-aligned sparks
## (CPUParticles2D particle_flag_align_y aligns the texture's Y with velocity).
static func spark() -> Texture2D:
	if not _cache.has("spark"):
		var w := 6
		var h := 30
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		for y in h:
			var fy := absf((float(y) + 0.5) / h * 2.0 - 1.0)
			# Brighter head, longer tail: skew the falloff.
			var along := pow(1.0 - fy, 1.6)
			for x in w:
				var fx := absf((float(x) + 0.5) / w * 2.0 - 1.0)
				var across := clampf(1.0 - fx * fx, 0.0, 1.0)
				img.set_pixel(x, y, Color(1, 1, 1, along * across))
		_cache["spark"] = ImageTexture.create_from_image(img)
	return _cache["spark"]

## Small rounded square chunk (hot debris bits).
static func chunk() -> Texture2D:
	if not _cache.has("chunk"):
		var s := 8
		var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
		for y in s:
			for x in s:
				var d := Vector2(x + 0.5 - s * 0.5, y + 0.5 - s * 0.5).length() / (s * 0.5)
				img.set_pixel(x, y, Color(1, 1, 1, clampf(1.4 - d, 0.0, 1.0)))
		_cache["chunk"] = ImageTexture.create_from_image(img)
	return _cache["chunk"]

## 2x2 white texture for shader quads.
static func white() -> Texture2D:
	if not _cache.has("white"):
		var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_cache["white"] = ImageTexture.create_from_image(img)
	return _cache["white"]

## Shared additive material (one instance -> batching friendly).
static func additive() -> CanvasItemMaterial:
	if not _cache.has("add"):
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_cache["add"] = m
	return _cache["add"]

## Spark colour ramp: white-hot -> yellow -> orange -> dull red, fading out.
static func spark_ramp() -> Gradient:
	if not _cache.has("spark_ramp"):
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.15, 0.45, 0.8, 1.0])
		g.colors = PackedColorArray([
			Color(1.0, 1.0, 0.95, 1.0), Color(1.0, 0.9, 0.55, 1.0),
			Color(1.0, 0.6, 0.2, 0.9), Color(0.9, 0.25, 0.05, 0.5), Color(0.6, 0.1, 0.0, 0.0)])
		_cache["spark_ramp"] = g
	return _cache["spark_ramp"]

## Cool cyan-white ramp (warp / energy effects).
static func energy_ramp() -> Gradient:
	if not _cache.has("energy_ramp"):
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
		g.colors = PackedColorArray([
			Color(1, 1, 1, 1), Color(0.5, 0.9, 1.0, 0.8), Color(0.2, 0.5, 1.0, 0.0)])
		_cache["energy_ramp"] = g
	return _cache["energy_ramp"]

## Fire ramp for explosion fireballs.
static func fire_ramp() -> Gradient:
	if not _cache.has("fire_ramp"):
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.12, 0.35, 0.7, 1.0])
		g.colors = PackedColorArray([
			Color(1, 1, 1, 1), Color(1, 0.92, 0.6, 1), Color(1, 0.55, 0.15, 0.85),
			Color(0.7, 0.18, 0.05, 0.4), Color(0.25, 0.05, 0.02, 0)])
		_cache["fire_ramp"] = g
	return _cache["fire_ramp"]

static func smoke_ramp() -> Gradient:
	if not _cache.has("smoke_ramp"):
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
		g.colors = PackedColorArray([
			Color(0.35, 0.3, 0.3, 0.0), Color(0.32, 0.31, 0.33, 0.55), Color(0.2, 0.21, 0.25, 0.0)])
		_cache["smoke_ramp"] = g
	return _cache["smoke_ramp"]

## Curve that shrinks particles over their lifetime.
static func shrink_curve() -> Curve:
	if not _cache.has("shrink"):
		var c := Curve.new()
		c.add_point(Vector2(0, 1))
		c.add_point(Vector2(0.6, 0.7))
		c.add_point(Vector2(1, 0))
		_cache["shrink"] = c
	return _cache["shrink"]

## Curve that grows particles (smoke expanding).
static func grow_curve() -> Curve:
	if not _cache.has("grow"):
		var c := Curve.new()
		c.add_point(Vector2(0, 0.3))
		c.add_point(Vector2(1, 1))
		_cache["grow"] = c
	return _cache["grow"]

static func _radial(size: int, offsets: PackedFloat32Array, colors: Array) -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = offsets
	g.colors = PackedColorArray(colors)
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = size
	t.height = size
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	return t
