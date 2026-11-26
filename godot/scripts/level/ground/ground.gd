extends Node3D
## Ground pass: gives every Skyharbor area its own floor instead of the same grey deck plates everywhere.
##
## Runs after the other area files (scripts/level/areas/y_ground.gd). It finds every floor-like mesh that uses
## the shared deck material (M.deck / M.worn("deck") / the terrace "pave" and yard "deck" kit materials),
## works out which area it belongs to from the island it sits on, and swaps in that area's ground material
## (shaders/ground.gdshader with a layer of the ground texture array made by art/ground_textures.py):
##   Junkyard   packed earth, gravel and patched scrap plates      Plaza       warm cobbles (roof decks: tiles)
##   Terrace    terracotta tiles with glazed accents                Gardens     mossy flagstones
##   Bazaar     big dusty sandstone flags
##   Docks      weathered boardwalk planks                          Signal Mast steel tread plate
##   Crane Yard cast concrete slabs (and the docks depot)
## Each slab also gets per-instance edge grime and a random offset so neighbouring slabs never line up.
## The hazard edging is swapped for stone curbs, wooden beams or rusty plate where hazard stripes don't fit.
## On the first physics frames it scatters ground clutter (pebbles, leaves, nuts, scrap, weed tufts, petals) as
## MultiMeshes and lays decals (oil, cracks, manholes, lane paint, chalk, rugs), raycasting so nothing lands
## inside a building or on a prop. Moving platforms keep the old deck look.
## Flags: --no-ground (skip all of it), --no-ground-dress (materials only), --ground-stats (print counts),
## --ground-tour=<prefix> (visit each area, save <prefix>_<spot>.png and print the fps there, then quit;
## run with --no-title --no-capture --no-bots).

const M := preload("res://scripts/mats.gd")
const DIR := "res://textures/ground/"
const LAYERS := ["deck", "junk", "cobble", "terracotta", "flagstone", "planks", "tread", "concrete", "side", "sandstone"]
enum { DECK, JUNK, COBBLE, TERRA, FLAG, PLANKS, TREAD, CONCRETE, CURB, SAND }
const NONE_RECT := Vector4(-100000.0, -100000.0, 100000.0, 100000.0)

var L: Node3D
var alb_arr: Texture2DArray
var nrm_arr: Texture2DArray
var macro: Texture2D
var mats := {}                 # style -> ShaderMaterial
var floors: Array = []         # { node, style, rect: Rect2 (or empty), top: float, box: bool }
var counts := {}
var rng := RandomNumberGenerator.new()
var _frames := 0
var dress := true
var stats := false

# ------------------------------------------------------------------ entry
func setup(level: Node3D) -> void:
	L = level
	rng.seed = 2611
	var args := OS.get_cmdline_user_args()
	dress = not args.has("--no-ground-dress")
	stats = args.has("--ground-stats")
	var off := args.has("--no-ground")   # keep the old floors (the tour still runs, for comparisons)
	if not off:
		_make_arrays()
		_make_mats()
		_reskin(L)
	if stats:
		print("[ground] floors=%d by style %s" % [floors.size(), counts])
	set_physics_process(dress and not off)
	for a in args:
		if a.begins_with("--ground-tour="): tour_prefix = a.substr(14)
	set_process(tour_prefix != "")

func _physics_process(_dt: float) -> void:
	_frames += 1
	if _frames < 3: return   # let the colliders register first
	set_physics_process(false)
	var t0 := Time.get_ticks_msec()
	_dress()
	if stats: print("[ground] dressed in %d ms" % (Time.get_ticks_msec() - t0))

# ------------------------------------------------------------------ screenshot + fps tour
## [name, player position, facing yaw, camera pitch]
const TOUR := [
	["junkyard", Vector3(2, 0.1, 84), PI * 0.9, -0.25], ["junk_heap", Vector3(-28, 0.1, 84), -PI / 2, -0.25],
	["plaza", Vector3(-3, 0.1, 40), PI * 0.85, -0.22], ["plaza_side", Vector3(-12, 0.1, 22), PI * 0.35, -0.25],
	["terrace", Vector3(-34, 0.1, 40), -PI / 2, -0.22], ["bazaar", Vector3(-58, 0.1, 44), -PI / 2, -0.22],
	["gardens", Vector3(-23, 8.9, -36), PI / 2, -0.2], ["docks", Vector3(39, 0.1, 22), PI, -0.25],
	["pier_c", Vector3(64, 6.1, -38), -PI / 2, -0.22], ["gallery", Vector3(20, 8.1, -40), -PI / 2, -0.25],
	["dish", Vector3(17, 20.1, -31), -PI * 0.75, -0.3], ["yard", Vector3(0, 0.1, -60), PI, -0.25],
	["row", Vector3(-38, 0.1, -70), PI, -0.25], ["arena", Vector3(-12, 0.1, -88), PI * 0.8, -0.22],
]
var tour_prefix := ""
var _ti := -1
var _tf := 0
var _ft := 0.0
var _fn := 0
var tour_fps := []

func _process(dt: float) -> void:
	if tour_prefix == "": return
	var game := get_tree().root.get_node_or_null("Game")
	if game == null or game.get("player") == null: return
	var p = game.player
	var cam = game.get("cam")
	_tf += 1
	if _ti < 0 and _tf < 90: return
	if _ti < 0 or _tf > 110:
		_ti += 1; _tf = 0; _ft = 0.0; _fn = 0
		if _ti >= TOUR.size():
			var tot := 0.0
			for f in tour_fps: tot += f
			print("[ground-tour] done, mean fps %.1f" % (tot / maxf(1.0, tour_fps.size())))
			get_tree().quit(); return
		var s: Array = TOUR[_ti].duplicate()
		s[1] = preload("res://scripts/level/layout/spread.gd").at(s[1])   # tour spots are original positions
		p.global_position = s[1]; p.velocity = Vector3.ZERO; p.face_yaw = s[2]
		if cam: cam.yaw = s[2]; cam.pitch = s[3]; cam.global_position = s[1] + Vector3(0, 1.55, 0); cam.cam_y = s[1].y
		return
	if cam: cam.yaw = TOUR[_ti][2]; cam.pitch = TOUR[_ti][3]
	if _tf > 40: _ft += dt; _fn += 1
	if _tf == 105:
		var fps := _fn / maxf(_ft, 0.001)
		tour_fps.append(fps)
		print("[ground-tour] %s fps %.1f" % [TOUR[_ti][0], fps])
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s_%s.png" % [tour_prefix, TOUR[_ti][0]])

# ------------------------------------------------------------------ textures and materials
func _img(path: String, size: int) -> Image:
	var img: Image = null
	if ResourceLoader.exists(path):
		var t = load(path)
		if t is Texture2D: img = (t as Texture2D).get_image()
	if img == null: img = Image.load_from_file(path)
	if img == null:
		img = Image.create(size, size, false, Image.FORMAT_RGBA8); img.fill(Color(0.6, 0.6, 0.6, 0.7))
	if img.is_compressed(): img.decompress()
	if img.has_mipmaps(): img.clear_mipmaps()
	img.convert(Image.FORMAT_RGBA8)
	if img.get_width() != size or img.get_height() != size: img.resize(size, size, Image.INTERPOLATE_LANCZOS)
	img.generate_mipmaps()
	return img

func _make_arrays() -> void:
	var a: Array[Image] = []; var n: Array[Image] = []
	for l in LAYERS:
		a.append(_img(DIR + l + "_albedo.png", 1024))
		n.append(_img(DIR + l + "_normal.png", 1024))
	alb_arr = Texture2DArray.new(); alb_arr.create_from_images(a)
	nrm_arr = Texture2DArray.new(); nrm_arr.create_from_images(n)
	var mi := _img(DIR + "macro.png", 512)
	macro = ImageTexture.create_from_image(mi)

func _mat(p: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/ground.gdshader")
	m.set_shader_parameter("alb", alb_arr)
	m.set_shader_parameter("nrm", nrm_arr)
	m.set_shader_parameter("macro", macro)
	for k in p: m.set_shader_parameter(k, p[k])
	return m

func _make_mats() -> void:
	mats[DECK] = _mat({ layer = 0.0, side_layer = 0.0, tile_m = 7.1, side_m = 7.1, tint = Color(0.82, 0.86, 0.9), side_tint = Color(0.82, 0.86, 0.9),
		metal = 0.4, edge_grime = 0.3, puddles = 0.1, oil = 0.15, variation = 0.6, grime_col = Color(0.45, 0.42, 0.4) })
	mats[JUNK] = _mat({ layer = 1.0, side_layer = 1.0, tile_m = 9.0, side_m = 6.0, organic = 1.0, puddles = 0.55, oil = 0.6, moss = 0.2,
		edge_grime = 0.6, grime_col = Color(0.42, 0.32, 0.24), nrm_depth = 1.2 })
	mats[COBBLE] = _mat({ layer = 2.0, side_layer = 8.0, tile_m = 3.5, side_m = 3.2, organic = 0.7, puddles = 0.3, moss = 0.45,
		edge_grime = 0.45, nrm_depth = 1.3, side_tint = Color(1.0, 0.96, 0.9) })
	mats[TERRA] = _mat({ layer = 3.0, side_layer = 8.0, tile_m = 5.4, side_m = 3.2, puddles = 0.0, moss = 0.15, edge_grime = 0.4,
		grime_col = Color(0.5, 0.36, 0.28), side_tint = Color(1.0, 0.9, 0.78), nrm_depth = 1.1 })
	mats[FLAG] = _mat({ layer = 4.0, side_layer = 8.0, tile_m = 6.0, side_m = 3.2, organic = 0.8, puddles = 0.12, moss = 0.65,
		edge_grime = 0.35, side_tint = Color(1.0, 0.95, 0.86) })
	mats[PLANKS] = _mat({ layer = 5.0, side_layer = 0.0, tile_m = 6.0, side_m = 7.1, side_tint = Color(0.62, 0.66, 0.7), puddles = 0.35, oil = 0.25, moss = 0.15,
		edge_grime = 0.5, grime_col = Color(0.4, 0.36, 0.32), nrm_depth = 1.2 })
	mats[TREAD] = _mat({ layer = 6.0, side_layer = 6.0, tile_m = 3.0, side_m = 3.0, puddles = 0.2, oil = 0.3, edge_grime = 0.4,
		metal = 0.6, rough_mul = 1.1, grime_col = Color(0.4, 0.38, 0.36) })
	mats[CONCRETE] = _mat({ layer = 7.0, side_layer = 7.0, tile_m = 5.0, side_m = 6.0, puddles = 0.55, oil = 0.8, moss = 0.08,
		edge_grime = 0.55, grime_col = Color(0.42, 0.38, 0.34) })
	mats[SAND] = _mat({ layer = 9.0, side_layer = 8.0, tile_m = 7.0, side_m = 3.2, puddles = 0.0, moss = 0.05, edge_grime = 0.45,
		grime_col = Color(0.55, 0.45, 0.32), side_tint = Color(1.0, 0.92, 0.8) })
	mats[CURB] = _mat({ layer = 8.0, side_layer = 8.0, tile_m = 3.2, side_m = 3.2, edge_grime = 0.0, variation = 0.5,
		tint = Color(1.0, 0.96, 0.9), side_tint = Color(1.0, 0.96, 0.9) })

# ------------------------------------------------------------------ which area a floor belongs to
static func name_style(n: String) -> int:
	if n.begins_with("junk"): return JUNK
	if n.begins_with("plaza") or n.begins_with("causeway"): return COBBLE
	if n in ["bazaar", "wash_nook"]: return SAND
	if n in ["terrace", "tier2", "tier3", "tier4", "tea_terrace", "lantern_loft", "chime_perch"]: return TERRA
	if n in ["gardens", "promenade", "conservatory", "hive_grove"]: return FLAG
	if n.begins_with("pier") or n == "berth": return PLANKS
	if n == "depot" or n.begins_with("yard") or n == "arena": return CONCRETE
	if n.begins_with("mast") or n == "gallery" or n == "dish_deck": return TREAD
	return DECK

## the island a point (x, floor top, z) belongs to: one at the same height under it, else the highest one
## under it, else the nearest one within 30 m. Returns [name, height] or ["", 0].
func island_at(p: Vector3) -> Array:
	var best := ""; var best_s := INF; var bh := 0.0
	var q := Vector2(p.x, p.z)
	for n in L.islands:
		var r: Rect2 = L.islands[n]
		var h: float = L.heights.get(n, 0.0)
		if not r.grow(0.7).has_point(q): continue
		if p.y < h - 1.0 or p.y > h + 14.0: continue
		var s := absf(p.y - h) * 10.0 + r.get_area() * 0.0005
		if s < best_s: best_s = s; best = n; bh = h
	if best != "": return [best, bh]
	for n in L.islands:
		var r: Rect2 = L.islands[n]
		var h: float = L.heights.get(n, 0.0)
		var d := Vector2(maxf(maxf(r.position.x - q.x, q.x - r.end.x), 0.0), maxf(maxf(r.position.y - q.y, q.y - r.end.y), 0.0)).length()
		var s := d + absf(p.y - h) * 0.5
		if d < 30.0 and s < best_s: best_s = s; best = n; bh = h
	return [best, bh]

func style_at(p: Vector3) -> int:
	var isl := island_at(p)
	if isl[0] == "": return DECK
	var s := name_style(isl[0])
	if s == COBBLE and p.y > float(isl[1]) + 2.5: s = TERRA   # the plaza's upper decks and rooftops: tiles
	return s

# ------------------------------------------------------------------ reskin
func _is_deck(m: Material) -> bool:
	var dt: Texture2D = M._tex("deck_albedo")
	if dt == null: return false
	if m is StandardMaterial3D:
		var sm := m as StandardMaterial3D
		return sm.albedo_texture == dt and sm.uv1_triplanar and sm.uv1_world_triplanar
	if m.has_meta("ground"): return true
	if m is ShaderMaterial:
		var sh := m as ShaderMaterial
		return sh.shader != null and sh.shader.resource_path.ends_with("worn_surface.gdshader") and sh.get_shader_parameter("albedo_tex") == dt
	return false

func _is_hazard(m: Material) -> bool:
	var ht: Texture2D = M._tex("hazard_albedo")
	return ht != null and m is StandardMaterial3D and (m as StandardMaterial3D).albedo_texture == ht

func _mat_of(g: GeometryInstance3D) -> Material:
	if g.material_override: return g.material_override
	if g is MeshInstance3D:
		var mi := g as MeshInstance3D
		if mi.mesh == null or mi.mesh.get_surface_count() == 0: return null
		var o := mi.get_surface_override_material(0)
		return o if o else mi.mesh.surface_get_material(0)
	return null

var _curb_wood: Material
var _curb_rust: Material
func _reskin(n: Node) -> void:
	for c in n.get_children():
		if c is AnimatableBody3D or c is RigidBody3D or c is CharacterBody3D: continue
		if c is MeshInstance3D or c is MultiMeshInstance3D:
			_consider(c as GeometryInstance3D)
		if c.get_child_count() > 0: _reskin(c)

func _consider(g: GeometryInstance3D) -> void:
	var m := _mat_of(g)
	if m == null: return
	var deck := _is_deck(m)
	var hz := not deck and _is_hazard(m)
	if not deck and not hz: return
	var aabb: AABB
	if g is MeshInstance3D:
		if (g as MeshInstance3D).mesh == null: return
		aabb = g.global_transform * (g as MeshInstance3D).mesh.get_aabb()
	else:
		var mm := (g as MultiMeshInstance3D).multimesh
		if mm == null or mm.instance_count == 0 or mm.mesh == null: return
		if deck and _split_multimesh(g as MultiMeshInstance3D): return
		aabb = g.global_transform * mm.get_aabb()
	var c := aabb.get_center()
	var top := aabb.end.y
	var style := style_at(Vector3(c.x, top, c.z))
	if hz:
		# hazard edging: keep it on the industrial areas, swap it where it looks out of place
		if not (g is MeshInstance3D and (g as MeshInstance3D).mesh is BoxMesh): return
		match style:
			COBBLE, FLAG, TERRA, SAND: g.material_override = mats[CURB]
			PLANKS:
				if _curb_wood == null: _curb_wood = M.wood(Color(0.75, 0.55, 0.4))
				g.material_override = _curb_wood
			JUNK:
				if _curb_rust == null: _curb_rust = M.worn("paint", Color(0.62, 0.38, 0.24), 0.2, 0.5, 0.75, 0.0)
				g.material_override = _curb_rust
			_: return
		g.set_instance_shader_parameter("seed", fposmod(c.x * 0.37 + c.z * 0.11, 7.0))
		counts["curb"] = counts.get("curb", 0) + 1
		return
	g.material_override = mats[style]
	if g is MeshInstance3D: (g as MeshInstance3D).set_surface_override_material(0, null)
	var is_box := g is MeshInstance3D and (g as MeshInstance3D).mesh is BoxMesh
	var axis_aligned := g.global_transform.basis.get_euler().length() < 0.01
	var rect := Rect2()
	if is_box and axis_aligned:
		rect = Rect2(aabb.position.x, aabb.position.z, aabb.size.x, aabb.size.z)
		g.set_instance_shader_parameter("rect", Vector4(rect.position.x, rect.position.y, rect.end.x, rect.end.y))
	else:
		g.set_instance_shader_parameter("rect", NONE_RECT)
	g.set_instance_shader_parameter("seed", fposmod(c.x * 0.137 + c.z * 0.291 + top * 0.07, 10.0))
	floors.append({ node = g, style = style, rect = rect, top = top })
	counts[LAYERS[style]] = counts.get(LAYERS[style], 0) + 1

## A batched MultiMesh of deck blocks can span several areas (the terrace kit batches the whole market):
## split its instances by area into one MultiMesh per style. Returns false when they all share one style.
func _split_multimesh(g: MultiMeshInstance3D) -> bool:
	var mm := g.multimesh
	var by := {}
	var maabb := mm.mesh.get_aabb()
	# the instance transforms as built (the RenderingServer copy can't be read back without a GPU)
	var xfs: Array = g.get_meta("xforms") if g.has_meta("xforms") else []
	if xfs.size() != mm.instance_count:
		xfs = []
		for i in mm.instance_count: xfs.append(mm.get_instance_transform(i))
	for i in mm.instance_count:
		var a: AABB = g.global_transform * (xfs[i] as Transform3D) * maabb
		var c := a.get_center()
		var st := style_at(Vector3(c.x, a.end.y, c.z))
		if not by.has(st): by[st] = []
		by[st].append(i)
		# big flat blocks count as floors for the clutter and decals
		if a.size.x >= 3.0 and a.size.z >= 3.0 and (xfs[i] as Transform3D).basis.get_euler().length() < 0.01:
			floors.append({ node = g, style = st, rect = Rect2(a.position.x, a.position.z, a.size.x, a.size.z), top = a.end.y })
	if by.size() < 2: return false
	for st in by:
		var n := MultiMesh.new()
		n.transform_format = MultiMesh.TRANSFORM_3D
		n.use_colors = mm.use_colors
		n.mesh = mm.mesh
		n.instance_count = by[st].size()
		for k in by[st].size():
			var i: int = by[st][k]
			n.set_instance_transform(k, xfs[i])
			if mm.use_colors: n.set_instance_color(k, mm.get_instance_color(i))
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = n; mi.transform = g.transform; mi.cast_shadow = g.cast_shadow
		mi.material_override = mats[st]
		mi.set_instance_shader_parameter("rect", NONE_RECT)
		mi.set_instance_shader_parameter("seed", float(st) * 1.7)
		g.get_parent().add_child(mi)
		counts[LAYERS[st]] = counts.get(LAYERS[st], 0) + 1
	g.visible = false
	g.queue_free()
	return true

# ------------------------------------------------------------------ clutter and decals
## clutter kinds per style: [kind, weight]; density = pieces per square metre (before rejections)
const CLUTTER := {
	JUNK: [0.4, [["pebble", 2], ["nut", 2], ["scrap", 3], ["tuft", 3]]],
	COBBLE: [0.2, [["leaf", 4], ["paper", 1], ["pebble", 1], ["tuft", 2]]],
	TERRA: [0.16, [["petal", 3], ["leaf", 2], ["paper", 1]]],
	FLAG: [0.22, [["leaf", 3], ["petal", 3], ["tuft", 3]]],
	PLANKS: [0.08, [["nut", 1], ["paper", 1], ["leaf", 1], ["rope", 1]]],
	SAND: [0.12, [["petal", 2], ["leaf", 2]]],
	TREAD: [0.06, [["nut", 3], ["scrap", 1]]],
	CONCRETE: [0.16, [["pebble", 2], ["nut", 2], ["scrap", 2], ["paper", 1], ["tuft", 1]]],
}
## decals per style: [square metres per decal, [[texture, w, d, weight, unique]]]
const DECALS := {
	JUNK: [40.0, [["oil1", 2.6, 2.6, 2, false], ["oil2", 2.0, 2.0, 2, false], ["tyre", 1.2, 4.6, 2, false], ["crack", 2.6, 2.6, 1, false]]],
	COBBLE: [45.0, [["manhole_brass", 1.3, 1.3, 2, false], ["drain", 0.9, 0.9, 2, false], ["hopscotch", 1.4, 4.2, 1, true],
		["chalk_bot", 2.0, 2.0, 1, true], ["leaves", 2.2, 2.2, 3, false], ["crack", 2.0, 2.0, 1, false]]],
	TERRA: [40.0, [["rug_a", 2.6, 1.7, 2, false], ["rug_b", 2.6, 1.7, 2, false], ["leaves", 2.0, 2.0, 2, false]]],
	FLAG: [30.0, [["leaves", 2.4, 2.4, 1, false]]],
	PLANKS: [60.0, [["leaves", 1.8, 1.8, 1, false], ["pier_text", 4.4, 1.1, 2, true]]],
	TREAD: [40.0, [["mast_text", 3.6, 0.9, 1, true], ["stripes", 3.6, 0.9, 2, false], ["oil2", 1.4, 1.4, 1, false]]],
	SAND: [28.0, [["rug_a", 2.8, 1.8, 3, false], ["rug_b", 2.8, 1.8, 3, false], ["leaves", 2.0, 2.0, 1, false]]],
	CONCRETE: [20.0, [["oil1", 2.8, 2.8, 3, false], ["oil2", 2.2, 2.2, 2, false], ["arrow", 1.4, 2.8, 2, false], ["stripes", 4.0, 1.0, 2, false],
		["yard_text", 4.0, 1.0, 1, true], ["manhole_steel", 1.3, 1.3, 2, false], ["crack", 2.8, 2.8, 2, false], ["tyre", 1.2, 4.8, 2, false]]],
}

var _meshes := {}
var _cmats := {}
var _space: PhysicsDirectSpaceState3D

func _ray_floor(x: float, z: float, top: float) -> bool:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, top + 1.6, z), Vector3(x, top - 0.4, z))
	var hit := _space.intersect_ray(q)
	return not hit.is_empty() and absf(hit.position.y - top) < 0.07 and hit.normal.y > 0.9

func _pick(list: Array) -> Array:
	var tot := 0.0
	for e in list: tot += e[e.size() - 2] if e.size() > 3 else e[1]
	var r := rng.randf() * tot
	for e in list:
		r -= e[e.size() - 2] if e.size() > 3 else e[1]
		if r <= 0.0: return e
	return list[list.size() - 1]

func _dress() -> void:
	_space = get_world_3d().direct_space_state
	var batches := {}   # "floor_i:kind" -> { xf: [], col: [] }
	var n_cl := 0; var n_dec := 0
	var used_unique := {}
	for fi in floors.size():
		var f: Dictionary = floors[fi]
		var r: Rect2 = f.rect
		if r.size.x < 2.5 or r.size.y < 2.5 or not CLUTTER.has(f.style): continue
		var area := r.get_area()
		var cfg: Array = CLUTTER[f.style]
		var want := mini(int(area * cfg[0]), 450)
		var parent := Node3D.new(); parent.name = "GroundDress%d" % fi; add_child(parent)
		var per := {}
		for i in want:
			var x := rng.randf_range(r.position.x + 0.15, r.end.x - 0.15)
			var z := rng.randf_range(r.position.y + 0.15, r.end.y - 0.15)
			var e := minf(minf(x - r.position.x, r.end.x - x), minf(z - r.position.y, r.end.y - z))
			var kind: String = _pick(cfg[1])[0]
			# weeds only grow along the edges; everything else drifts toward them too
			if kind == "tuft" and e > 0.9: continue
			if rng.randf() > 0.3 + 0.7 * (1.0 - smoothstep(0.0, 3.0, e)): continue
			if not _ray_floor(x, z, f.top): continue
			if not per.has(kind): per[kind] = { xf = [], col = [] }
			var xc := _clutter_xf(kind, Vector3(x, f.top, z))
			per[kind].xf.append(xc[0]); per[kind].col.append(xc[1])
			n_cl += 1
		for kind in per:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.mesh = _mesh(kind)
			mm.instance_count = per[kind].xf.size()
			for i in mm.instance_count:
				mm.set_instance_transform(i, per[kind].xf[i]); mm.set_instance_color(i, per[kind].col[i])
			var mmi := MultiMeshInstance3D.new(); mmi.multimesh = mm; mmi.material_override = _cmat(kind)
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_end = 55.0; mmi.visibility_range_end_margin = 6.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			parent.add_child(mmi)
		# decals
		if not DECALS.has(f.style) or area < 20.0: continue
		var dc: Array = DECALS[f.style]
		var nd := mini(int(area / dc[0]) + 1, 14 if f.style == CONCRETE else 9)
		var tries := 0
		while nd > 0 and tries < 40:
			tries += 1
			var d: Array = _pick(dc[1])
			var key := "%d:%s" % [f.style, d[0]]
			if d[4] and (used_unique.get(key, 0) >= 2 or area < 90.0): continue
			var w: float = d[1] * rng.randf_range(0.85, 1.15); var dd: float = d[2] * (w / d[1])
			var yaw := rng.randf() * TAU
			if d[0] in ["arrow", "stripes", "yard_text", "pier_text", "mast_text", "hopscotch", "tyre", "rug_a", "rug_b"]: yaw = rng.randi_range(0, 3) * PI / 2 + rng.randf_range(-0.06, 0.06)
			var ext := maxf(w, dd) * 0.5 + 0.2
			if r.size.x < ext * 2 + 0.4 or r.size.y < ext * 2 + 0.4: continue
			var x := rng.randf_range(r.position.x + ext, r.end.x - ext)
			var z := rng.randf_range(r.position.y + ext, r.end.y - ext)
			var ok := _ray_floor(x, z, f.top)
			var b := Basis(Vector3.UP, yaw)
			for k in [Vector3(w, 0, dd), Vector3(-w, 0, dd), Vector3(w, 0, -dd), Vector3(-w, 0, -dd)]:
				if not ok: break
				var p: Vector3 = b * (k * 0.5)
				ok = _ray_floor(x + p.x, z + p.z, f.top)
			if not ok: continue
			var dec := Decal.new()
			dec.texture_albedo = load(DIR + "decals/" + d[0] + ".png")
			dec.size = Vector3(w, 0.5, dd)
			dec.position = Vector3(x, f.top, z)
			dec.rotation.y = yaw
			dec.normal_fade = 0.4
			dec.upper_fade = 0.15; dec.lower_fade = 0.15
			dec.distance_fade_enabled = true; dec.distance_fade_begin = 45.0; dec.distance_fade_length = 12.0
			if d[0].begins_with("oil"): dec.modulate = Color(1, 1, 1, rng.randf_range(0.55, 0.9))
			parent.add_child(dec)
			if d[4]: used_unique[key] = used_unique.get(key, 0) + 1
			nd -= 1; n_dec += 1
	# set pieces that fill the big open floors of the Crane Yard
	for sp in [["arena", "arena_ring", Vector2(0, 0), 13.0, 13.0, 0.0], ["arena", "skid", Vector2(-7, 9), 6.0, 6.0, 0.6],
			["arena", "oil1", Vector2(6, -6), 4.5, 4.5, 0.0], ["yard_gate", "bay_text", Vector2(4, 1), 6.0, 2.25, PI],
			["yard_gate", "skid", Vector2(-8, 0), 5.0, 5.0, 2.0], ["yard_row", "skid", Vector2(0, 4), 6.0, 6.0, 1.0],
			["yard_row", "oil1", Vector2(-3, -6), 4.0, 4.0, 0.0], ["arena", "skid", Vector2(-9, 4), 6.5, 6.5, 2.4],
			["arena", "bay_text", Vector2(-4, 10), 6.0, 2.25, PI / 2], ["arena", "oil2", Vector2(-13, -2), 3.5, 3.5, 0.0], ["yard_pen", "skid", Vector2(0, 0), 6.0, 6.0, 2.6]]:
		if not L.islands.has(sp[0]): continue
		var c: Vector2 = (L.islands[sp[0]] as Rect2).get_center() + sp[2]
		var y: float = L.heights.get(sp[0], 0.0)
		if not _ray_floor(c.x, c.y, y): continue
		var dec := Decal.new()
		dec.texture_albedo = load(DIR + "decals/" + sp[1] + ".png")
		dec.size = Vector3(sp[3], 0.5, sp[4]); dec.position = Vector3(c.x, y, c.y); dec.rotation.y = sp[5]
		dec.normal_fade = 0.4; dec.upper_fade = 0.15; dec.lower_fade = 0.15
		dec.distance_fade_enabled = true; dec.distance_fade_begin = 70.0; dec.distance_fade_length = 15.0
		add_child(dec); n_dec += 1
	if stats: print("[ground] clutter=%d decals=%d" % [n_cl, n_dec])

const LEAF_COLS := [Color(0.78, 0.47, 0.2), Color(0.85, 0.63, 0.24), Color(0.62, 0.35, 0.16), Color(0.45, 0.6, 0.24), Color(0.8, 0.32, 0.2)]
const PEBBLE_COLS := [Color(0.45, 0.38, 0.31), Color(0.52, 0.45, 0.36), Color(0.38, 0.33, 0.29), Color(0.56, 0.5, 0.42)]
const SCRAP_COLS := [Color(0.55, 0.3, 0.18), Color(0.35, 0.52, 0.58), Color(0.5, 0.52, 0.55), Color(0.72, 0.56, 0.22), Color(0.4, 0.5, 0.34)]
const PAPER_COLS := [Color(0.95, 0.93, 0.86), Color(0.98, 0.86, 0.7), Color(0.8, 0.9, 0.98), Color(0.98, 0.8, 0.85)]
const PETAL_COLS := [Color(1.0, 0.62, 0.72), Color(1.0, 0.82, 0.86), Color(0.98, 0.55, 0.4), Color(1.0, 0.9, 0.6)]

func _clutter_xf(kind: String, p: Vector3) -> Array:
	var yaw := rng.randf() * TAU
	var tilt := Basis(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.0, 0.25))
	var b := tilt * Basis(Vector3.UP, yaw)
	var s := 1.0; var col := Color.WHITE; var lift := 0.0
	match kind:
		"pebble":
			s = rng.randf_range(0.03, 0.09); col = PEBBLE_COLS[rng.randi() % PEBBLE_COLS.size()]
			b = b.scaled(Vector3(rng.randf_range(0.8, 1.3), rng.randf_range(0.45, 0.7), rng.randf_range(0.8, 1.2)) * s); lift = s * 0.12
		"nut":
			s = rng.randf_range(0.04, 0.07); col = Color(0.5, 0.48, 0.45) if rng.randf() < 0.6 else Color(0.62, 0.48, 0.26)
			b = b.scaled(Vector3(s, s * 0.6, s)); lift = s * 0.3
		"scrap":
			col = SCRAP_COLS[rng.randi() % SCRAP_COLS.size()]
			b = b.scaled(Vector3(rng.randf_range(0.12, 0.42), 0.025, rng.randf_range(0.05, 0.2))); lift = 0.015
		"leaf":
			s = rng.randf_range(0.8, 1.3); col = LEAF_COLS[rng.randi() % LEAF_COLS.size()]
			b = b.scaled(Vector3.ONE * s); lift = 0.01
		"petal":
			s = rng.randf_range(0.45, 0.7); col = PETAL_COLS[rng.randi() % PETAL_COLS.size()]
			b = b.scaled(Vector3.ONE * s); lift = 0.01
		"paper":
			col = PAPER_COLS[rng.randi() % PAPER_COLS.size()]
			b = Basis(Vector3.UP, yaw).scaled(Vector3(rng.randf_range(0.8, 1.2), 1, rng.randf_range(0.8, 1.2))); lift = 0.012
		"tuft":
			s = rng.randf_range(0.7, 1.5); col = Color(0.36, 0.55, 0.2).lerp(Color(0.55, 0.62, 0.25), rng.randf())
			b = Basis(Vector3.UP, yaw).scaled(Vector3(s, s * rng.randf_range(0.8, 1.4), s)); lift = 0.0
		"rope":
			s = rng.randf_range(0.4, 0.55); col = Color(0.55, 0.44, 0.3)
			b = Basis(Vector3.UP, yaw).scaled(Vector3(s, s * 0.6, s)); lift = 0.04 * s
	return [Transform3D(b, p + Vector3(0, lift, 0)), col]

func _mesh(kind: String) -> Mesh:
	if _meshes.has(kind): return _meshes[kind]
	var m: Mesh
	match kind:
		"pebble":
			var s := SphereMesh.new(); s.radius = 0.5; s.height = 1.0; s.radial_segments = 7; s.rings = 3; m = s
		"nut":
			var c := CylinderMesh.new(); c.top_radius = 0.5; c.bottom_radius = 0.5; c.height = 0.5; c.radial_segments = 6; c.rings = 1; m = c
		"scrap":
			var b := BoxMesh.new(); b.size = Vector3.ONE; m = b
		"leaf", "petal": m = _leaf_mesh()
		"paper":
			var q := PlaneMesh.new(); q.size = Vector2(0.18, 0.24); m = q
		"tuft": m = _tuft_mesh()
		"rope":
			var t := TorusMesh.new(); t.inner_radius = 0.14; t.outer_radius = 0.24; t.rings = 10; t.ring_segments = 5; m = t
	_meshes[kind] = m
	return m

func _cmat(kind: String) -> Material:
	var key := "metal" if kind in ["nut", "scrap"] else ("thin" if kind in ["leaf", "petal", "paper", "tuft"] else "solid")
	if _cmats.has(key): return _cmats[key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.8
	match key:
		"metal": m.metallic = 0.6; m.roughness = 0.45
		"thin":
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.backlight_enabled = true; m.backlight = Color(0.2, 0.25, 0.1)
	_cmats[key] = m
	return m

func _leaf_mesh() -> ArrayMesh:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := [Vector3(0, 0.01, -0.09), Vector3(0.04, 0.02, 0), Vector3(0, 0.0, 0.09), Vector3(-0.04, 0.02, 0)]
	for tri in [[0, 1, 2], [0, 2, 3]]:
		for i in tri:
			st.set_normal(Vector3.UP); st.add_vertex(pts[i])
	return st.commit()

func _tuft_mesh() -> ArrayMesh:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var g := RandomNumberGenerator.new(); g.seed = 77
	for k in 7:
		var a := k * TAU / 7 + g.randf() * 0.5
		var dir := Vector3(cos(a), 0, sin(a)); var side := Vector3(-sin(a), 0, cos(a))
		var h := g.randf_range(0.16, 0.3)
		var base0 := side * 0.025; var base1 := -side * 0.025
		var tip := dir * g.randf_range(0.06, 0.13) + Vector3(0, h, 0)
		var nrm := dir.lerp(Vector3.UP, 0.6).normalized()
		for v in [base0, base1, tip]:
			st.set_normal(nrm); st.add_vertex(v)
	return st.commit()
