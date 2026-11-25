extends RefCounted
## Shared materials and procedural textures.

static var _cache := {}

static func panel_tex() -> ImageTexture:
	if _cache.has("panel"): return _cache.panel
	var s := 256
	var img := Image.create(s, s, true, Image.FORMAT_RGBA8)
	img.fill(Color(0.86, 0.9, 0.93))
	for i in s:
		for j in s:
			var n := (randf() - 0.5) * 0.025
			var c := img.get_pixel(i, j)
			img.set_pixel(i, j, Color(c.r + n, c.g + n, c.b + n))
	for k in range(0, s, 128):
		for t in s:
			for w in 3:
				img.set_pixel(clampi(k + w, 0, s - 1), t, Color(0.55, 0.6, 0.66))
				img.set_pixel(t, clampi(k + w, 0, s - 1), Color(0.55, 0.6, 0.66))
	for k in [64, 192]:
		for t in s:
			img.set_pixel(k, t, Color(0.74, 0.79, 0.84))
			img.set_pixel(t, k, Color(0.74, 0.79, 0.84))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache.panel = tex
	return tex

static func hazard_tex() -> ImageTexture:
	if _cache.has("hazard"): return _cache.hazard
	var img := Image.create(128, 32, true, Image.FORMAT_RGBA8)
	for x in 128:
		for y in 32:
			img.set_pixel(x, y, Color(1, 0.75, 0.1) if int((x + y) / 16) % 2 == 0 else Color(0.12, 0.12, 0.14))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache.hazard = tex
	return tex

static func std(color: Color, metal := 0.0, rough := 0.5) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metal
	m.roughness = rough
	return m

static func deck(tint := Color(1, 1, 1), scale := 0.28) -> StandardMaterial3D:
	var m := std(tint * 0.78, 0.45, 0.55)
	m.albedo_texture = panel_tex()
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m

static func hazard() -> StandardMaterial3D:
	var m := std(Color.WHITE, 0.2, 0.5)
	m.albedo_texture = hazard_tex()
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * 0.5
	return m

static func glow(color: Color, energy := 3.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.BLACK
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m
