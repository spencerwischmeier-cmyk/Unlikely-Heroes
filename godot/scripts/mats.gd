extends RefCounted
## Shared materials and textures.
##
## Surfaces use the tileable texture sets in res://textures/ (made by art/skyharbor_textures.py): an albedo,
## a normal map and a roughness map each for deck plates, painted metal, brass, hazard stripes, sailcloth,
## rubber and wood. They are mapped triplanar, so any box or imported mesh gets detail without UVs:
## level geometry uses world space (panels line up across blocks), kit props use object space (the pattern
## travels with the prop). If a texture is missing, a small procedural fallback is generated instead.
##
## Old API (kept): std, deck, hazard, glow, panel_tex, hazard_tex.
## New: paint, metal, chrome, brass, rubber, cloth, wood, glass, leaf, surface, kit.

const TEX := "res://textures/"
static var _cache := {}

# ---------------------------------------------------------------- textures
static func _tex(name: String) -> Texture2D:
	if _cache.has("t_" + name): return _cache["t_" + name]
	var t: Texture2D = null
	var p := TEX + name + ".png"
	if ResourceLoader.exists(p): t = load(p)
	_cache["t_" + name] = t
	return t

## Deck plate albedo (light grey, meant to be tinted).
static func panel_tex() -> Texture2D:
	var t := _tex("deck_albedo")
	return t if t else _panel_fallback()

static func hazard_tex() -> Texture2D:
	var t := _tex("hazard_albedo")
	return t if t else _hazard_fallback()

static func _panel_fallback() -> ImageTexture:
	if _cache.has("panel"): return _cache.panel
	var s := 256
	var img := Image.create(s, s, true, Image.FORMAT_RGBA8)
	img.fill(Color(0.86, 0.9, 0.93))
	for k in range(0, s, 128):
		for t in s:
			for w in 3:
				img.set_pixel(clampi(k + w, 0, s - 1), t, Color(0.55, 0.6, 0.66))
				img.set_pixel(t, clampi(k + w, 0, s - 1), Color(0.55, 0.6, 0.66))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache.panel = tex
	return tex

static func _hazard_fallback() -> ImageTexture:
	if _cache.has("hazard"): return _cache.hazard
	var img := Image.create(128, 32, true, Image.FORMAT_RGBA8)
	for x in 128:
		for y in 32:
			img.set_pixel(x, y, Color(1, 0.75, 0.1) if int((x + y) / 16) % 2 == 0 else Color(0.12, 0.12, 0.14))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache.hazard = tex
	return tex

# ---------------------------------------------------------------- base helpers
static func std(color: Color, metal := 0.0, rough := 0.5) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metal
	m.roughness = rough
	return m

## Average value of each roughness map, so `rough` arguments mean the same thing with or without textures.
const _ROUGH_MEAN := {"deck": 0.6, "paint": 0.42, "brass": 0.34, "hazard": 0.5, "cloth": 0.82, "rubber": 0.75, "wood": 0.66}

## A textured surface: `set` is a texture set name (deck, paint, brass, hazard, cloth, rubber, wood).
## scale is texture repeats per metre; world=true maps in world space, false in object space.
static func surface(set: String, color: Color, metal: float, rough: float, scale := 0.5, world := false, normal_depth := 1.0) -> StandardMaterial3D:
	var m := std(color, metal, rough)
	var a := _tex(set + "_albedo")
	if a == null: return m
	m.albedo_texture = a
	var n := _tex(set + "_normal")
	if n:
		m.normal_enabled = true
		m.normal_texture = n
		m.normal_scale = normal_depth
	var r := _tex(set + "_rough")
	if r:
		m.roughness_texture = r
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		m.roughness = clampf(rough / _ROUGH_MEAN.get(set, 0.5), 0.0, 2.0)
	m.uv1_triplanar = true
	m.uv1_world_triplanar = world
	m.uv1_triplanar_sharpness = 4.0
	m.uv1_scale = Vector3.ONE * scale
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m

# ---------------------------------------------------------------- level materials (old API)
static func deck(tint := Color(1, 1, 1), scale := 0.28) -> StandardMaterial3D:
	# the deck texture holds 4x4 plates (the old one 2x2), so halve the repeat to keep the same plate size
	var m := surface("deck", tint * 0.9, 0.45, 0.55, scale * 0.5, true)
	if m.albedo_texture == null:
		m.albedo_color = tint * 0.78
		m.albedo_texture = panel_tex()
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE * scale
	return m

static func hazard() -> StandardMaterial3D:
	var m := surface("hazard", Color.WHITE, 0.25, 0.5, 0.5, true)
	if m.albedo_texture == null:
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

# ---------------------------------------------------------------- prop materials
static func paint(color: Color, world := false) -> StandardMaterial3D:
	var m := surface("paint", color, 0.3, 0.42, 0.5, world)
	m.clearcoat_enabled = true
	m.clearcoat = 0.35
	m.clearcoat_roughness = 0.3
	return m

static func metal(color := Color(0.23, 0.26, 0.31), world := false) -> StandardMaterial3D:
	return surface("paint", color, 0.85, 0.4, 0.5, world, 0.7)

static func chrome(color := Color(0.84, 0.86, 0.89)) -> StandardMaterial3D:
	return surface("paint", color, 1.0, 0.15, 0.5, false, 0.3)

static func brass(world := false) -> StandardMaterial3D:
	return surface("brass", Color.WHITE, 0.95, 0.3, 0.7, world)

static func rubber(color := Color(0.15, 0.16, 0.18)) -> StandardMaterial3D:
	return surface("rubber", color, 0.0, 0.8, 2.0)

static func cloth(color: Color) -> StandardMaterial3D:
	var m := surface("cloth", color, 0.0, 0.85, 0.6)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.rim_enabled = true
	m.rim = 0.25
	m.rim_tint = 0.6
	return m

static func wood(color := Color(1, 1, 1)) -> StandardMaterial3D:
	return surface("wood", color, 0.0, 0.65, 1.0)

static func glass(color := Color(0.66, 0.89, 0.96)) -> StandardMaterial3D:
	var m := std(Color(color.r, color.g, color.b, 0.3), 0.2, 0.04)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	m.rim_enabled = true
	m.rim = 0.4
	return m

static func leaf(color: Color) -> StandardMaterial3D:
	var m := std(color, 0.0, 0.75)
	m.rim_enabled = true
	m.rim = 0.35
	m.rim_tint = 0.2
	m.backlight_enabled = true
	m.backlight = Color(0.25, 0.4, 0.1)
	return m

## Material for a kit material name "k_<kind>_<rrggbb>" (see art/skyharbor_kit.py). Returns null for names it
## does not know (the imported material is kept then). Shared between all props.
static func kit(mat_name: String) -> Material:
	var key := "k:" + mat_name
	if _cache.has(key): return _cache[key]
	var parts := mat_name.split("_")
	var m: Material = null
	if parts.size() >= 3 and parts[0] == "k":
		var kind := parts[1]
		var c := Color.html(parts[2]) if parts[2].is_valid_hex_number() and parts[2].length() == 6 else Color.WHITE
		match kind:
			"paint": m = paint(c)
			"metal": m = metal(c)
			"chrome": m = chrome(c)
			"brass": m = brass()
			"rubber": m = rubber(c)
			"cloth": m = cloth(c)
			"wood":  # the wood texture is already brown (#b07a48); tint relative to that
				var base := Color("b07a48")
				m = wood(Color(minf(c.r / base.r, 1.5), minf(c.g / base.g, 1.5), minf(c.b / base.b, 1.5)))
			"glass": m = glass(c)
			"glow": m = glow(c, 3.0)
			"leaf": m = leaf(c)
			"soil": m = std(c, 0.0, 1.0)
			"deck": m = surface("deck", Color(0.92, 0.94, 0.97), 0.45, 0.55, 0.25)
			"rust": m = surface("paint", c, 0.45, 0.8, 0.7, false, 1.5)
			"hazard": m = surface("hazard", Color.WHITE, 0.25, 0.5, 1.0)
			"sign": m = null
	_cache[key] = m
	return m

## A weathered, world-triplanar version of a texture set (grime, rust, moss, wet patches).
static func worn(set: String, tint := Color(1, 1, 1), scale := 0.14, metal := 0.4, rough := 0.6, moss := 0.5) -> ShaderMaterial:
	var key := "worn_%s_%s_%s_%s" % [set, tint.to_html(), scale, moss]
	if _cache.has(key): return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/worn_surface.gdshader")
	var a := _tex(set + "_albedo")
	m.set_shader_parameter("albedo_tex", a if a else panel_tex())
	var n := _tex(set + "_normal"); if n: m.set_shader_parameter("normal_tex", n)
	var r := _tex(set + "_rough"); if r: m.set_shader_parameter("rough_tex", r)
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("tex_scale", scale)
	m.set_shader_parameter("metallic_v", metal)
	m.set_shader_parameter("rough_v", rough)
	m.set_shader_parameter("moss", moss)
	_cache[key] = m
	return m
