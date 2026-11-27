extends RefCounted
## The market build-up (run by areas/w_market.gd in final coordinates, before the routes, the scatter and the
## floors). Fills the Market Terrace and the Spice Bazaar so they read as a dense, lived-in market that was
## abandoned in a hurry when the signal sent the bots haywire:
##   - a row of four plastered shop-houses along the terrace's north edge (open shopfronts, shuttered windows,
##     balconies, rooftop clutter) on a new rock shelf, replacing the bare railing there
##   - canopy stalls, produce tables, spice sacks, shelves, barrels, crates, baskets, jars and rugs
##   - abandoned vehicles: a tipped barrow, a loaded barrow, a cargo trike in a mast, a hover barrow that dropped
##   - the panic: parasols and stools knocked over, a stall collapsed and burning, fruit rolled everywhere,
##     bags dropped, smoke over the rooftops, embers; more citizens fleeing through (scripts/level/panic/panic.gd)
##   - hanging shop signs, lamp posts, lantern strings, bunting and laundry between the houses and the masts
## Props are Blender models from art/market_kit.py (godot/models/market/*.glb), merged per prop and drawn as
## MultiMeshes; their k_* materials become the game's textured materials (mats.gd), k_plaster_* a weathered
## world-space plaster. Big pieces get box colliders; litter has none, so it can never block a route.
## The area grade is the "market" entry in systems/area_mood.gd.
##   --no-market      skip all of it (and the market grade), for before/after shots

const M := preload("res://scripts/mats.gd")
const TK := preload("res://scripts/level/terrace/tkit.gd")
const Chaos := preload("res://scripts/level/layout/chaos.gd")
const DIR := "res://models/market/"

static var _kits := {}           # prop name -> { mesh: ArrayMesh, marks: { name: Vector3 } }
static var _plaster := {}
static var root: Node3D
static var batches := {}         # "zone|prop" -> Array[Transform3D]
static var n_lights := 0
static var n_props := 0
static var _no_lights := false

static func on() -> bool:
	return not OS.get_cmdline_user_args().has("--no-market")

# ------------------------------------------------------------------ kit loading
static func _mat(m: Material) -> Material:
	var n := m.resource_name
	if n.begins_with("k_plaster_"):
		if not _plaster.has(n):
			var c := Color.html(n.substr(10))
			_plaster[n] = M.worn("paint", c * Color(1.08, 1.06, 1.04), 0.2, 0.0, 0.88, 0.18)
		return _plaster[n]
	var k := M.kit(n)
	return k if k else m

static func kit(name_: String) -> Dictionary:
	if _kits.has(name_): return _kits[name_]
	var path := DIR + name_ + ".glb"
	var out := { mesh = null, marks = {} }
	if ResourceLoader.exists(path):
		var scn: Node3D = (load(path) as PackedScene).instantiate()
		var by_mat := {}; var order: Array = []
		_collect(scn, Transform3D.IDENTITY, by_mat, order, out.marks)
		var am := ArrayMesh.new()
		for m in order:
			var st: SurfaceTool = by_mat[m]
			st.commit(am)
			am.surface_set_material(am.get_surface_count() - 1, _mat(m))
		out.mesh = am
		scn.free()
	_kits[name_] = out
	return out

static func _collect(n: Node, xf: Transform3D, by_mat: Dictionary, order: Array, marks: Dictionary) -> void:
	var here := xf * (n as Node3D).transform if n is Node3D else xf
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var mi := n as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var m: Material = mi.get_active_material(s)
			if m == null: m = StandardMaterial3D.new()
			if not by_mat.has(m):
				var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
				by_mat[m] = st; order.append(m)
			(by_mat[m] as SurfaceTool).append_from(mi.mesh, s, here)
	elif n is Node3D and n.get_child_count() == 0 and (n.name.begins_with("light_") or n.name == "sign"):
		marks[String(n.name)] = here.origin
	for c in n.get_children(): _collect(c, here, by_mat, order, marks)

# ------------------------------------------------------------------ placing
## place a prop: zone groups the MultiMeshes (so the culling and draw distance work per corner of the market);
## tilt = (x, z) extra rotation for knocked-over things; col = box collider from the prop's bounds (shrunk);
## lit = add a small warm light at each light_* mark
static func put(zone: String, name_: String, pos: Vector3, yaw := 0.0, opts := {}) -> Transform3D:
	var k := kit(name_)
	var tilt: Vector2 = opts.get("tilt", Vector2.ZERO)
	var s: float = opts.get("scale", 1.0)
	var xf := Transform3D(Basis.from_euler(Vector3(tilt.x, yaw, tilt.y)).scaled(Vector3.ONE * s), pos)
	if k.mesh == null: return xf
	var key := zone + "|" + name_
	if not batches.has(key): batches[key] = []
	batches[key].append(xf)
	n_props += 1
	if opts.get("col", false):
		var ab: AABB = (k.mesh as ArrayMesh).get_aabb()
		var shrink: float = opts.get("shrink", 0.85)
		var sz := ab.size * s * Vector3(shrink, 1.0, shrink)
		if opts.has("col_h"): sz.y = opts.col_h
		var sb := StaticBody3D.new(); var cs := CollisionShape3D.new(); var sh := BoxShape3D.new()
		sh.size = sz; cs.shape = sh; sb.add_child(cs)
		var c := ab.get_center() * s; c.y = sz.y * 0.5
		sb.transform = Transform3D(Basis(Vector3.UP, yaw), pos + Basis(Vector3.UP, yaw) * c)
		root.add_child(sb)
	if opts.get("lit", false):
		for mk in k.marks:
			if not String(mk).begins_with("light_"): continue
			light(xf * (k.marks[mk] as Vector3), Color(1.0, 0.72, 0.42), opts.get("energy", 1.3), opts.get("range", 6.0))
	return xf

static func light(pos: Vector3, c: Color, energy := 1.3, rng := 6.0) -> OmniLight3D:
	var l := OmniLight3D.new()
	if _no_lights: l.visible = false
	l.light_color = c; l.light_energy = energy; l.omni_range = rng; l.omni_attenuation = 1.3
	l.shadow_enabled = false; l.light_specular = 0.35
	l.distance_fade_enabled = true; l.distance_fade_begin = 45.0; l.distance_fade_length = 12.0
	l.position = pos
	root.add_child(l)
	n_lights += 1
	return l

## two_sided: lettering on both faces of a hanging board (0.07 thick) centred at pos, facing yaw and yaw + PI
static func label(text: String, pos: Vector3, yaw: float, size := 64, px := 0.006, c := Color(1, 0.9, 0.62), two_sided := false) -> void:
	for s in ([1, -1] if two_sided else [1]):
		var l := Label3D.new(); l.text = text; l.font_size = size; l.pixel_size = px
		l.modulate = c; l.outline_size = 10; l.outline_modulate = Color(0.18, 0.08, 0.03)
		var face: Vector3 = Basis(Vector3.UP, yaw) * Vector3(0, 0, 1) * float(s)
		l.position = pos + (face * 0.05 if two_sided else Vector3.ZERO); l.rotation.y = yaw + (0.0 if s > 0 else PI); l.double_sided = false
		l.visibility_range_end = 70.0
		root.add_child(l)

static func flush() -> void:
	for key in batches:
		var xfs: Array = batches[key]
		var name_: String = key.get_slice("|", 1)
		var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = kit(name_).mesh; mm.instance_count = xfs.size()
		for i in xfs.size(): mm.set_instance_transform(i, xfs[i])
		var mi := MultiMeshInstance3D.new(); mi.multimesh = mm; mi.name = "Market_" + key.replace("|", "_")
		var big := name_.begins_with("mk_house") or name_.begins_with("mk_stall") or name_.begins_with("mk_awning")
		mi.visibility_range_end = 220.0 if big else 80.0
		# small goods are a lot of little triangles: the shadow pass skips them (SSAO grounds them)
		if not big and not name_.begins_with("mk_hand") and not name_.begins_with("mk_cargo") and not name_.begins_with("mk_hover") and not name_.begins_with("mk_parasol") and not name_.begins_with("mk_crate_wall") and not name_.begins_with("mk_lamp"):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end_margin = 10.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		root.add_child(mi)
	batches.clear()

# ------------------------------------------------------------------ build
static func build(L: Node3D) -> void:
	var t0 := Time.get_ticks_msec()
	root = Node3D.new(); root.name = "MarketBuildUp"; L.add_child(root)
	n_lights = 0; n_props = 0
	var args := OS.get_cmdline_user_args()   # --market-skip=houses,props,overhead,fx,lights (profiling)
	var skip: Array = []
	for a in args: if a.begins_with("--market-skip="): skip = Array(a.substr(14).split(","))
	_no_lights = skip.has("lights")
	_clear_north_railing(L)
	TK.begin(L).name = "MarketBuildUpKit"   # bunting, lantern strings and laundry go through the terrace kit's batcher
	if not skip.has("houses"): _shophouses(L)
	if not skip.has("props"):
		_terrace()
		_bazaar()
	if not skip.has("overhead"): _overhead()
	TK.flush()
	flush()
	if not skip.has("fx"): _panic(L)
	_spots(L)
	print("[market] %d props, %d lights, built in %d ms" % [n_props, n_lights, Time.get_ticks_msec() - t0])

## the terrace's north edge railing (z 24) goes: the shop-houses stand there now
static func _clear_north_railing(L: Node3D) -> void:
	var gone := 0
	for n in L.find_children("*", "Node3D", true, false):
		if not (n is GeometryInstance3D or n is StaticBody3D): continue
		if n.get_parent() is StaticBody3D: continue
		var p: Vector3 = (n as Node3D).global_position
		if absf(p.z - 24.0) < 0.2 and p.y > 0.3 and p.y < 1.2 and p.x > -80.5 and p.x < -57.5:
			if n is MultiMeshInstance3D: continue
			n.queue_free(); gone += 1
	if gone == 0: push_warning("[market] north railing not found")

# ------------------------------------------------------------------ the shop-houses (terrace north edge)
const HOUSES := [   # prop, centre x, width, floors, sign, sign colour
	["mk_house_d", -77.4, 5.2, 3, "LANTERNS & WICKS", Color(1.0, 0.86, 0.5)],
	["mk_house_a", -72.1, 5.4, 2, "PIP'S PANTRY", Color(1.0, 0.92, 0.7)],
	["mk_house_c", -66.3, 6.2, 2, "THE COPPER KETTLE", Color(1.0, 0.86, 0.55)],
	["mk_house_b", -60.7, 5.0, 3, "BOLT & BLOSSOM", Color(1.0, 0.9, 0.65)],
]

static func _shophouses(L: Node3D) -> void:
	# a rock shelf under the row (the terrace deck ends at z 24), with the cliff face and ivy below it
	TK.block(Vector3(-69, -0.6, 21.7), Vector3(22.4, 1.2, 4.8), "pave", false)
	TK.under_rock(Vector2(-69, 21.4), 11.5, 3.6, -1.0, 14.0)
	TK.under_rock(Vector2(-64, 20.5), 5.0, 2.6, -1.2, 9.0, "rock_dark")
	TK.vines(Vector3(-80, -1.1, 19.1), Vector3(-58, -1.1, 19.1), Vector3(0, 0, -1), 0.8)
	for h in HOUSES:
		var x: float = h[1]
		put("houses", h[0], Vector3(x, 0, 24.0), 0.0, { lit = true, energy = 1.1, range = 5.0 })
		var H: float = 3.1 * h[3]
		var sb := StaticBody3D.new(); var cs := CollisionShape3D.new(); var sh := BoxShape3D.new()
		sh.size = Vector3(h[2], H + 1.0, 4.4); cs.shape = sh; sb.add_child(cs)
		sb.position = Vector3(x, (H + 1.0) / 2, 24.0 - 0.15 - 2.2); root.add_child(sb)
		var sm: Dictionary = kit(h[0]).marks
		if sm.has("sign"): label(h[4], Vector3(x, 0, 24.0) + (sm.sign as Vector3) + Vector3(0, 0, 0.02), 0.0, 72, 0.0062, h[5])
	# awnings over the shopfronts that have no tree in front of them
	put("houses", "mk_awning_saffron", Vector3(-77.4, 0, 24.0), 0.0)
	put("houses", "mk_awning_teal", Vector3(-66.3, 0, 24.0), 0.0, { scale = 1.0 })
	# goods spilling out of the shops onto the terrace
	put("houses", "mk_spice_sacks", Vector3(-77.6, 0, 25.0), 0.0)
	put("houses", "mk_jars", Vector3(-74.2, 0, 24.8), 0.6)
	put("houses", "mk_baskets", Vector3(-69.3, 0, 24.9), 0.3)
	put("houses", "mk_crate_stack", Vector3(-63.9, 0, 25.0), -0.1, { col = true })
	put("houses", "mk_barrel", Vector3(-58.9, 0, 24.7), 0.0, { col = true })
	put("houses", "mk_stools", Vector3(-68.6, 0, 26.3), 0.8)

# ------------------------------------------------------------------ the Market Terrace (x -80..-58, z 24..50)
static func _terrace() -> void:
	# the café corner by the entrance: a parasol still up, one blown over, stools everywhere
	put("terrace", "mk_parasol_teal", Vector3(-62.6, 0, 27.6), 0.3, { col = true, shrink = 0.12, col_h = 2.4 })
	put("terrace", "mk_stools", Vector3(-62.5, 0, 27.7), 2.0)
	put("terrace", "mk_parasol_red", Vector3(-65.6, 0.35, 29.0), 1.1, { tilt = Vector2(1.32, 0.1) })
	# the middle of the terrace: an island of stalls splitting the crowd into two lanes
	put("terrace", "mk_stall_fruit", Vector3(-71.0, 0, 40.4), PI, { col = true, shrink = 0.9, lit = true })
	put("terrace", "mk_produce_table", Vector3(-66.4, 0, 39.6), PI + 0.05, { col = true })
	put("terrace", "mk_spice_shelf", Vector3(-66.4, 0, 41.0), 0.0, { col = true })
	put("terrace", "mk_crate_wall", Vector3(-74.6, 0, 41.6), PI / 2 + 0.05, { col = true, shrink = 0.95 })
	put("terrace", "mk_barrels", Vector3(-68.6, 0, 42.2), 0.4, { col = true })
	put("terrace", "mk_sacks", Vector3(-63.6, 0, 40.2), 1.0)
	# the south lane: a loaded barrow left in the way, a hover barrow that fell out of the air
	put("terrace", "mk_handcart", Vector3(-70.0, 0, 45.9), PI / 2 + 0.2, { col = true, shrink = 0.8 })
	put("terrace", "mk_hover_barrow", Vector3(-63.5, 0.0, 44.4), -0.5, { col = true, tilt = Vector2(0.0, 0.06) })
	put("terrace", "mk_crate_spill", Vector3(-66.2, 0, 46.4), 2.4)
	put("terrace", "mk_baskets", Vector3(-77.6, 0, 45.6), 1.2)
	put("terrace", "mk_tarp_pile", Vector3(-78.4, 0, 48.6), 0.1, { col = true })
	put("terrace", "mk_jars", Vector3(-58.9, 0, 46.6), -0.4)
	# by the entrance arch and along the north lane
	put("terrace", "mk_crate_fruit", Vector3(-59.4, 0, 38.5), 0.3, { col = true })
	put("terrace", "mk_crate_spill", Vector3(-60.4, 0, 36.6), -1.2)
	put("terrace", "mk_jars", Vector3(-79.0, 0, 34.4), 1.0)
	put("terrace", "mk_lamp_post", Vector3(-74.0, 0, 37.9), 0.0, { col = true, shrink = 0.15, lit = true })
	put("terrace", "mk_lamp_post", Vector3(-63.0, 0, 37.9), 0.0, { col = true, shrink = 0.15, lit = true })
	# hanging shop signs on the masts and the arch
	put("terrace", "mk_sign_teal", Vector3(-75.5, 0.9, 27.2), 0.0)
	label("SPICE BAZAAR  >", Vector3(-75.5, 3.0, 27.85), PI / 2, 48, 0.0055, Color(1, 0.92, 0.7), true)
	put("terrace", "mk_sign_red", Vector3(-60.2, 0.9, 44.6), PI)
	label("FRESH-ISH FISH", Vector3(-60.2, 3.0, 43.95), PI / 2, 48, 0.0055, Color(1, 0.92, 0.7), true)

# ------------------------------------------------------------------ the Spice Bazaar (x -110..-80, z 30..54)
static func _bazaar() -> void:
	# west side: a spice row along the rail and a stall facing the square
	put("bazaar", "mk_spice_sacks", Vector3(-108.6, 0, 43.4), PI / 2)
	put("bazaar", "mk_stall_spice", Vector3(-104.6, 0, 52.5), PI, { col = true, shrink = 0.9, lit = true })
	put("bazaar", "mk_barrels", Vector3(-109.0, 0, 37.6), 0.3, { col = true })
	put("bazaar", "mk_handcart", Vector3(-104.0, 0, 44.6), 0.15, { col = true, shrink = 0.8 })
	# round the spice pyramid: everything dropped where it stood
	put("bazaar", "mk_handcart_tipped", Vector3(-98.6, 0, 46.2), 2.6, { col = true, shrink = 0.55, col_h = 1.2 })
	put("bazaar", "mk_parasol_red", Vector3(-91.6, 0.35, 38.8), -0.6, { tilt = Vector2(1.3, -0.15) })
	put("bazaar", "mk_stools", Vector3(-92.4, 0, 40.1), 0.3)
	put("bazaar", "mk_crate_spill", Vector3(-97.6, 0, 38.6), 0.9)
	put("bazaar", "mk_baskets", Vector3(-92.2, 0, 45.0), 2.0)
	# the cargo trike ran into the north-east mast
	put("bazaar", "mk_cargo_trike", Vector3(-87.3, 0, 38.9), -0.8 + PI, { col = true, shrink = 0.75, tilt = Vector2(0.0, 0.1) })
	# east edge: a cloth stall facing the square, rugs and a crate wall by the terrace threshold
	put("bazaar", "mk_stall_cloth", Vector3(-82.3, 0, 43.4), -PI / 2, { col = true, shrink = 0.9, lit = true })
	put("bazaar", "mk_rug_rolls", Vector3(-92.2, 0, 33.7), 0.0, { col = true })
	put("bazaar", "mk_crate_wall", Vector3(-81.6, 0, 48.6), -PI / 2, { col = true, shrink = 0.95 })
	put("bazaar", "mk_sacks", Vector3(-84.8, 0, 47.0), 0.6)
	# south row: the pots stall, then the collapsed one (burning, see _panic)
	put("bazaar", "mk_stall_pots", Vector3(-89.6, 0, 50.2), PI + 0.08, { col = true, shrink = 0.9, lit = true })
	put("bazaar", "mk_stall_collapsed", Vector3(-99.4, 0, 51.6), PI + 0.2, { col = true, shrink = 0.7, col_h = 1.0 })
	put("bazaar", "mk_jars", Vector3(-95.8, 0, 50.0), 0.4)
	put("bazaar", "mk_lamp_post", Vector3(-100.6, 0, 40.4), 0.0, { col = true, shrink = 0.15, lit = true })
	put("bazaar", "mk_lamp_post", Vector3(-88.4, 0, 45.6), 0.0, { col = true, shrink = 0.15, lit = true })
	put("bazaar", "mk_crate_stack", Vector3(-102.0, 0, 34.8), 0.2, { col = true })
	put("bazaar", "mk_sign_red", Vector3(-104.0, 0.9, 37.0), PI / 2)
	label("STAIRS TO THE TEA TERRACE", Vector3(-103.35, 3.0, 37.0), 0.0, 44, 0.0045, Color(1, 0.92, 0.7), true)

# ------------------------------------------------------------------ overhead: bunting, lanterns, laundry
static func _overhead() -> void:
	# from the shop-house balconies and roofs out to the terrace masts
	TK.lantern_string(Vector3(-72.1, 6.4, 24.4), Vector3(-75.5, 5.6, 44.6), 1.4)
	TK.lantern_string(Vector3(-66.3, 6.4, 24.4), Vector3(-60.2, 5.6, 44.6), 1.4)
	TK.bunting(Vector3(-77.4, 9.4, 24.2), Vector3(-75.5, 6.2, 27.2), 0.4)
	TK.bunting(Vector3(-60.7, 9.4, 24.2), Vector3(-58.6, 5.4, 28.6), 0.5)
	TK.bunting(Vector3(-77.4, 6.0, 24.6), Vector3(-60.7, 6.0, 24.6), 0.9, ["crimson", "saffron", "teal", "cream", "plum"])
	TK.laundry(Vector3(-79.8, 7.6, 24.5), Vector3(-75.5, 5.9, 27.2), 0.3)
	TK.laundry(Vector3(-63.0, 4.6, 24.6), Vector3(-58.6, 4.6, 28.4), 0.25)
	# across the bazaar square, from the cliff to the south row
	TK.lantern_string(Vector3(-96, 4.4, 30.6), Vector3(-95, 6.6, 42.8), 0.8)
	TK.bunting(Vector3(-110, 3.2, 41), Vector3(-104, 5.4, 37.0), 0.5)

# ------------------------------------------------------------------ the panic: fire, smoke, bags, cars
static func _panic(L: Node3D) -> void:
	var C: Node3D = Chaos.make(L, "market")
	var rng := RandomNumberGenerator.new(); rng.seed = 919
	# the collapsed stall is burning; smoke rolls up over the bazaar
	C.fire(Vector3(-99.6, 0.4, 51.0), 0.85)
	C.smoke(Vector3(-99.6, 1.4, 51.0), 1.2, true)
	C.fire(Vector3(-98.2, 0.2, 52.2), 0.6, false)
	# a fire on the roof behind the shop-houses: a smoke column over the whole market
	C.column(Vector3(-69.0, 6.4, 21.0), 1.0, 30.0, 0.22)
	# the hover barrow's pods are shorting out: sparks and a little smoke
	C.smoke(Vector3(-63.2, 0.5, 44.0), 0.6, false)
	C.embers(Vector3(-63.2, 0.3, 44.4), 0.6)
	# bags dropped in the rush
	C.luggage(Vector3(-69.5, 0, 33.0), 2.2, 5, rng)
	C.luggage(Vector3(-94.0, 0, 36.2), 1.8, 4, rng)
	C.luggage(Vector3(-84.5, 0, 33.5), 1.5, 3, rng)
	C.prop("cone", Vector3(-79.4, 0, 29.4), 0.0, 1.0, Vector2(0, 1.5))
	C.broken_sign("FRESH BREAD", Vector3(-60.7, 7.4, 24.35), 0.0, Color(1.0, 0.7, 0.35), -0.18, 0.008)
	C.flush()

# ------------------------------------------------------------------ debug spots (--at=<name>)
static func _spots(L: Node3D) -> void:
	L.debug_spots["market_in"] = [Vector3(-56.5, 0.1, 33.0), -PI / 2]
	L.debug_spots["market_houses"] = [Vector3(-68.0, 0.1, 34.0), PI]
	L.debug_spots["market_bazaar"] = [Vector3(-82.0, 0.1, 36.0), -PI / 2]
