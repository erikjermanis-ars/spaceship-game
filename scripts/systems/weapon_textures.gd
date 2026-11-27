class_name WeaponTextures
extends RefCounted
## Procedural textures for the pulse cannons, built once at first use.
##
## Bolts have to read against black space AND against the pearl station, where
## additive light vanishes. So the bolt BODY is an opaque-cored dart drawn with
## normal blending (white-hot core, orange flank, dark red rim: the rim is
## what you see over a white hull) and a separate additive halo makes it glow
## in space.

static var _cache := {}


## Bolt body, 96x24, nose toward +X. Colours are baked in; tint with alpha only.
static func bolt() -> Texture2D:
	if not _cache.has("bolt"):
		var w := 96
		var h := 24
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		var core := Color(1.0, 0.98, 0.9)
		var flank := Color(1.0, 0.62, 0.16)
		var rim := Color(0.86, 0.13, 0.04)
		for y in h:
			var v := absf((y + 0.5) / h * 2.0 - 1.0)            # 0 on the axis .. 1 at the edge
			for x in w:
				var u := (x + 0.5) / w                             # 0 tail .. 1 nose
				# Teardrop: full width near the nose, tapering to a point at the tail.
				var half := sqrt(clampf(u * 1.25, 0.0, 1.0)) * sqrt(clampf((1.0 - u) * 9.0, 0.0, 1.0))
				var d := v / maxf(half, 0.001)                     # 0 axis .. 1 outline
				var col := core.lerp(flank, smoothstep(0.18, 0.5, d)).lerp(rim, smoothstep(0.55, 0.95, d))
				var a := (1.0 - smoothstep(0.82, 1.0, d)) * smoothstep(0.0, 0.18, u)
				img.set_pixel(x, y, Color(col, a if half > 0.02 else 0.0))
		img.generate_mipmaps()
		_cache["bolt"] = ImageTexture.create_from_image(img)
	return _cache["bolt"]


## Soft elongated halo, 64x32, white (tint it; additive).
static func streak() -> Texture2D:
	if not _cache.has("streak"):
		var w := 64
		var h := 32
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		for y in h:
			var v := (y + 0.5) / h * 2.0 - 1.0
			for x in w:
				var u := (x + 0.5) / w * 2.0 - 1.0
				var r := sqrt(u * u + v * v)
				img.set_pixel(x, y, Color(1, 1, 1, pow(clampf(1.0 - r, 0.0, 1.0), 2.0)))
		img.generate_mipmaps()
		_cache["streak"] = ImageTexture.create_from_image(img)
	return _cache["streak"]


## Muzzle flash, 64x32: a hot fan opening from the LEFT edge (the muzzle).
static func muzzle() -> Texture2D:
	if not _cache.has("muzzle"):
		var w := 64
		var h := 32
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		for y in h:
			var v := absf((y + 0.5) / h * 2.0 - 1.0)
			for x in w:
				var u := (x + 0.5) / w
				# A short fat bloom at the muzzle plus a long thin spike.
				var bloom := clampf(1.0 - Vector2(u * 2.6, v * 1.25).length(), 0.0, 1.0)
				var spike := clampf(1.0 - v * 5.0, 0.0, 1.0) * pow(1.0 - u, 1.5)
				img.set_pixel(x, y, Color(1, 1, 1, clampf(bloom * bloom * 1.4 + spike * 0.9, 0.0, 1.0)))
		img.generate_mipmaps()
		_cache["muzzle"] = ImageTexture.create_from_image(img)
	return _cache["muzzle"]


## 1x1 quad the bolt MultiMeshes instance (shared).
static func quad() -> Mesh:
	if not _cache.has("quad"):
		var q := QuadMesh.new()
		q.size = Vector2.ONE
		_cache["quad"] = q
	return _cache["quad"]
