class_name ShipFxTextures
extends RefCounted
## Procedurally generated, cached FX textures (soft glows, plume, gas puff)
## plus the shared additive material. Generated once at first use so the
## ship needs no bitmap assets for its effects and they stay smooth at any zoom.

static var _glow: ImageTexture
static var _plume: ImageTexture
static var _puff: ImageTexture
static var _add_mat: CanvasItemMaterial


## Soft round glow, 128x128, white with alpha falloff (tint with modulate).
static func glow() -> Texture2D:
	if _glow == null:
		var n := 128
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		var c := (n - 1) * 0.5
		for y in n:
			for x in n:
				var r := Vector2(x - c, y - c).length() / c
				var a := pow(clampf(1.0 - r, 0.0, 1.0), 2.2)
				img.set_pixel(x, y, Color(1, 1, 1, a))
		img.generate_mipmaps()
		_glow = ImageTexture.create_from_image(img)
	return _glow


## Exhaust plume, 128x32: nozzle at the LEFT edge (u = 0), fading to the right.
static func plume() -> Texture2D:
	if _plume == null:
		var w := 128
		var h := 32
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		for y in h:
			var v := (y - (h - 1) * 0.5) / ((h - 1) * 0.5)
			for x in w:
				var u := float(x) / float(w - 1)
				# Slight bulge after the nozzle, then a long taper.
				var width := lerpf(0.55, 0.95, smoothstep(0.0, 0.15, u)) * (1.0 - 0.75 * u)
				var across := exp(-pow(v / maxf(width, 0.05), 2.0) * 2.6)
				var along := pow(1.0 - u, 1.4) * smoothstep(0.0, 0.03, u + 0.01)
				img.set_pixel(x, y, Color(1, 1, 1, clampf(across * along * 1.15, 0.0, 1.0)))
		img.generate_mipmaps()
		_plume = ImageTexture.create_from_image(img)
	return _plume


## Soft gas puff disc, 64x64.
static func puff() -> Texture2D:
	if _puff == null:
		var n := 64
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		var c := (n - 1) * 0.5
		for y in n:
			for x in n:
				var r := Vector2(x - c, y - c).length() / c
				var a := smoothstep(1.0, 0.0, r)
				img.set_pixel(x, y, Color(1, 1, 1, pow(a, 1.4)))
		img.generate_mipmaps()
		_puff = ImageTexture.create_from_image(img)
	return _puff


static func additive() -> CanvasItemMaterial:
	if _add_mat == null:
		_add_mat = CanvasItemMaterial.new()
		_add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _add_mat
