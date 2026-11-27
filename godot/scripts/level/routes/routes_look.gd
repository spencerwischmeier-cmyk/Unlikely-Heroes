extends RefCounted
## The routes' look pass (run by areas/w_routes_look.gd in final coordinates, right after w_routes.gd, before the
## chaos scatter and the floors). Brings the connectors between the key areas up to the market and the gardens:
##   - the Scrapline tram viaduct (junkyard -> plaza): stone piers and round arches dropping into the clouds
##     instead of a thin slab on steel trusses, stone parapets with iron cresting, double lamp posts over the
##     piers, city banners, flower boxes on the plaza half; broken arch stones at the collapsed span
##   - the Lantern Bridge (plaza -> market): lacquered timber railings, two roofed lantern gates with name boards,
##     timber stringers on stone piers with knee braces underneath, lanterns under the deck
##   - the freight routes (gangway to Pier A, the freight approach and haul span to the Crane Yard): yellow guard
##     rails with mesh panels, plate girders with pipe runs and cable trays under the decks, sign gantries,
##     floodlight masts throwing pools of light
##   - the stations (Scrapline Halt, the cableway station and terminal, the balloon barge): brass and white
##     railings from the Skyharbor kit
##   - banks of cloud drifting under the bridges, so the drop reads as sky, and an area grade per route
##     ("viaduct", "lantern_bridge", "freight_*" in systems/area_mood.gd)
## w_routes.gd registers each styled railing (segs: it builds only the collider) and each deck whose structure
## this rebuilds (decks: it skips its steel trusses and keel lamps). Props come from art/route_kit.py
## (godot/models/routes/*.glb), merged per prop and drawn as MultiMeshes; k_stone_* becomes a weathered,
## world-space sandstone with moss in the joints.
##   --no-routes-look   skip all of it (w_routes builds the old railings, frames and trusses)

const M := preload("res://scripts/mats.gd")
const SkyW := preload("res://scripts/level/docks/sky.gd")
const DIR := "res://models/routes/"

static var segs: Array = []      # [style, Vector2 a, Vector2 b, y] from w_routes._railing
static var decks: Array = []     # [style, name, Rect2, y, along_z] from w_routes._deck
static var _kits := {}
static var _stone := {}
static var root: Node3D
static var batches := {}         # "zone|path" -> Array[Transform3D]
static var n_lights := 0
static var n_props := 0
static var _L: Node3D

static func on() -> bool:
	return not OS.get_cmdline_user_args().has("--no-routes-look")

# ------------------------------------------------------------------ kit loading (as market_look.gd)
static func _mat(m: Material) -> Material:
	var n := m.resource_name
	if n.begins_with("k_stone_"):
		if not _stone.has(n):
			var c := Color.html(n.substr(8))
			var sm: ShaderMaterial = M.worn("ground/sandstone", c * Color(1.25, 1.22, 1.18), 0.22, 0.0, 0.88, 0.55)
			sm = sm.duplicate()
			sm.set_shader_parameter("rust", 0.0)
			sm.set_shader_parameter("grime", 0.45)
			_stone[n] = sm
		return _stone[n]
	var k := M.kit(n)
	return k if k else m

static func kit(path: String) -> Dictionary:
	if _kits.has(path): return _kits[path]
	var full := path if path.begins_with("res://") else DIR + path + ".glb"
	var out := { mesh = null, marks = {} }
	if ResourceLoader.exists(full):
		var scn: Node3D = (load(full) as PackedScene).instantiate()
		var by_mat := {}; var order: Array = []
		_collect(scn, Transform3D.IDENTITY, by_mat, order, out.marks)
		var am := ArrayMesh.new()
		for m in order:
			var st: SurfaceTool = by_mat[m]
			st.commit(am)
			am.surface_set_material(am.get_surface_count() - 1, _mat(m))
		out.mesh = am
		scn.free()
	else:
		push_warning("[routes] missing " + full)
	_kits[path] = out
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

## place a prop (zone groups the MultiMeshes so each route culls on its own); basis lets pieces stretch
static func put(zone: String, path: String, xf: Transform3D) -> Transform3D:
	var key := zone + "|" + path
	if not batches.has(key): batches[key] = []
	batches[key].append(xf)
	n_props += 1
	return xf

static func xf(pos: Vector3, yaw := 0.0, scale := Vector3.ONE) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw).scaled_local(scale), pos)

static func light(pos: Vector3, c: Color, energy := 1.4, rng := 8.0) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = c; l.light_energy = energy; l.omni_range = rng; l.omni_attenuation = 1.3
	l.shadow_enabled = false; l.light_specular = 0.35
	l.distance_fade_enabled = true; l.distance_fade_begin = 50.0; l.distance_fade_length = 12.0
	l.position = pos
	root.add_child(l)
	n_lights += 1
	return l

static func spot(pos: Vector3, target: Vector3, c: Color, energy := 3.0, rng := 18.0, angle := 38.0) -> SpotLight3D:
	var l := SpotLight3D.new()
	l.light_color = c; l.light_energy = energy; l.spot_range = rng; l.spot_angle = angle; l.spot_attenuation = 0.8
	l.shadow_enabled = false; l.light_specular = 0.3
	l.distance_fade_enabled = true; l.distance_fade_begin = 60.0; l.distance_fade_length = 15.0
	root.add_child(l)
	l.global_position = pos
	l.look_at(target, Vector3.UP if absf((target - pos).normalized().y) < 0.98 else Vector3.RIGHT)
	n_lights += 1
	return l

static func label(text: String, pos: Vector3, yaw: float, size := 64, px := 0.006, c := Color(1, 0.9, 0.62), outline := Color(0.18, 0.08, 0.03)) -> void:
	var l := Label3D.new(); l.text = text; l.font_size = size; l.pixel_size = px
	l.modulate = c; l.outline_size = 10; l.outline_modulate = outline
	l.position = pos; l.rotation.y = yaw; l.double_sided = false
	l.visibility_range_end = 90.0
	root.add_child(l)

static func flush() -> void:
	for key in batches:
		var xfs: Array = batches[key]
		var path: String = key.get_slice("|", 1)
		var mesh: Mesh = kit(path).mesh
		if mesh == null: continue
		var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh; mm.instance_count = xfs.size()
		for i in xfs.size(): mm.set_instance_transform(i, xfs[i])
		var mi := MultiMeshInstance3D.new(); mi.multimesh = mm; mi.name = "Route_" + key.replace("|", "_").replace("/", "_").replace(":", "")
		var big := path.contains("pier") or path.contains("arch") or path.contains("gate") or path.contains("gantry") or path.contains("mast") or path.contains("bay")
		mi.visibility_range_end = 260.0 if big else 90.0
		mi.visibility_range_end_margin = 10.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		# the small dressing (rails, flowers) skips the shadow pass; the structure casts
		if path.contains("flowers") or path.contains("rail_") or path.contains("post") or path.contains("parapet"):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	batches.clear()

# ------------------------------------------------------------------ build
static func build(L: Node3D) -> void:
	var t0 := Time.get_ticks_msec()
	_L = L
	root = Node3D.new(); root.name = "RoutesLook"; L.add_child(root)
	n_lights = 0; n_props = 0
	_railings()
	for d in decks:
		match d[0]:
			"viaduct": pass   # the viaduct is built as one piece below
			"lantern": _timber_deck(d[2], d[3], d[4])
			"freight": _girder_deck(d[2], d[3], d[4])
	_viaduct()
	_lantern_bridge()
	_freight()
	flush()
	_clouds()
	segs.clear(); decks.clear()
	print("[routes] %d props, %d lights, built in %d ms" % [n_props, n_lights, Time.get_ticks_msec() - t0])

# ------------------------------------------------------------------ railings
const RAILS := {   # style -> [piece, post, piece length]
	"viaduct": ["rt_parapet", "rt_parapet_post", 2.0],
	"lantern": ["rt_rail_lacquer", "rt_lacquer_post", 2.0],
	"freight": ["rt_rail_freight", "rt_freight_post", 2.0],
	"iron": ["res://models/kit/railing_2m.glb", "res://models/kit/railing_post.glb", 2.0],
}

## which side of a railing is open air: the side whose point 1 m out isn't on any island
static func _outward(a: Vector2, b: Vector2, y: float) -> Vector2:
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x)
	var mid := (a + b) * 0.5
	for k in _L.islands:
		var r: Rect2 = _L.islands[k]
		if absf(float(_L.heights.get(k, 0.0)) - y) > 0.5: continue
		if r.has_point(mid + n * 1.0): return -n
	return n

static func _railings() -> void:
	var fl := 0
	for s in segs:
		var style: String = s[0]; var a: Vector2 = s[1]; var b: Vector2 = s[2]; var y: float = s[3]
		var spec: Array = RAILS.get(style, RAILS.iron)
		var len := a.distance_to(b)
		var n := maxi(1, int(ceil(len / spec[2] - 0.15)))
		var stretch: float = len / (n * spec[2])
		var d := (b - a) / len
		var yaw := atan2(-d.y, d.x)
		var out := _outward(a, b, y)
		# local -Z (where the flower boxes hang) should point outward
		var face := Basis(Vector3.UP, yaw) * Vector3(0, 0, -1)
		if Vector2(face.x, face.z).dot(out) < 0: yaw += PI
		var zone := style
		for i in n:
			var c := a.lerp(b, (i + 0.5) / n)
			put(zone, spec[0], xf(Vector3(c.x, y, c.y), yaw, Vector3(stretch, 1, 1)))
			if style == "viaduct" or style == "lantern":
				# flower boxes on every third piece (more of them toward the plaza and the market)
				var hp := hash(Vector2i(int(c.x * 10), int(c.y * 10)))
				if (style == "lantern" or c.y < 70.0) and hp % 3 == 0:
					var fx := Basis(Vector3.UP, yaw)
					var o := Vector3(0, -0.02, 0) if style == "lantern" else Vector3(0, 0.0, -0.05)
					put(zone, "rt_flowers_a" if hp % 2 == 0 else "rt_flowers_b", Transform3D(fx, Vector3(c.x, y, c.y) + fx * o))
					fl += 1
		for i in n + 1:
			if style == "viaduct" and i % 3 != 0 and i != n: continue
			var p := a.lerp(b, float(i) / n)
			put(zone, spec[1], xf(Vector3(p.x, y, p.y), yaw))

# ------------------------------------------------------------------ the Scrapline viaduct
const PIERS := [92.4, 82.2, 72.4, 66.6, 57.0, 47.2]

static func _viaduct() -> void:
	# piers and arch bays (the deck runs along z at x 0, top at y 0)
	for z in PIERS: put("viaduct", "rt_pier", xf(Vector3(0, 0, z)))
	for pair in [[82.2, 92.4], [72.4, 82.2], [47.2, 57.0], [57.0, 66.6]]:
		var z0: float = pair[0]; var z1: float = pair[1]
		put("viaduct", "rt_arch", xf(Vector3(0, 0, (z0 + z1) / 2), 0.0, Vector3(1, 1, (z1 - z0) / 10.0)))
	# the collapsed span: broken arch stones jutting from both piers, a few hanging below
	var rng := RandomNumberGenerator.new(); rng.seed = 7070
	var bm := BoxMesh.new(); bm.size = Vector3(1, 1, 1)
	var stone: Material = _mat(_stone_named("k_stone_d9c4a4"))
	var mmx: Array = []
	for e in [[72.4, -1.0], [66.6, 1.0]]:
		var z0: float = e[0]; var dir: float = e[1]
		for k in 9:
			var x := rng.randf_range(-4.0, 4.0)
			var reach := rng.randf_range(0.4, 2.0)
			var p := Vector3(x, rng.randf_range(-6.5, -1.6), z0 + dir * (1.1 + reach * 0.5))
			var sz := Vector3(rng.randf_range(0.6, 1.4), rng.randf_range(0.5, 0.9), reach)
			mmx.append(Transform3D(Basis.from_euler(Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.3, 0.3), rng.randf_range(-0.3, 0.3))).scaled_local(sz), p))
	var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D; mm.mesh = bm; mm.instance_count = mmx.size()
	for i in mmx.size(): mm.set_instance_transform(i, mmx[i])
	var mi := MultiMeshInstance3D.new(); mi.multimesh = mm; mi.material_override = stone; mi.name = "Route_viaduct_rubble"
	root.add_child(mi)
	# double lamp posts over the piers, one each side, staggered; a warm light each
	var lamps := [[92.4, 1], [82.2, -1], [72.4, 1], [66.6, -1], [57.0, 1], [47.2, -1]]
	for lp in lamps:
		var z: float = lp[0]; var s: int = lp[1]
		for side in [-1, 1]:
			put("viaduct", "rt_lamp_twin", xf(Vector3(side * 4.15, 0, z), PI / 2))
			if side == s: light(Vector3(side * 3.6, 3.7, z), Color(1.0, 0.74, 0.46), 1.6, 9.0)
	# the niche lamps on the piers' faces glow down the stonework
	for z in [82.2, 57.0]:
		for sx in [-1, 1]: light(Vector3(sx * 6.0, -4.2, z), Color(1.0, 0.7, 0.42), 1.2, 6.0)
	# city banners outside the parapets
	var bn := ["rt_banner_teal", "rt_banner_crimson", "rt_banner_plum"]
	var k := 0
	for z in [87.3, 77.3, 61.8, 52.1]:
		for sx in [-1, 1]:
			put("viaduct", bn[k % 3], xf(Vector3(sx * 4.75, 0, z), 0.0 if sx > 0 else PI))
			k += 1
	label("SCRAPLINE", Vector3(4.42, -0.85, 52.1), PI / 2, 96, 0.008, Color(1, 0.92, 0.75), Color(0.25, 0.18, 0.1))
	label("SCRAPLINE", Vector3(-4.42, -0.85, 52.1), -PI / 2, 96, 0.008, Color(1, 0.92, 0.75), Color(0.25, 0.18, 0.1))

static func _stone_named(n: String) -> Material:
	var m := StandardMaterial3D.new(); m.resource_name = n
	return m

# ------------------------------------------------------------------ the Lantern Bridge
static func _timber_deck(r: Rect2, y: float, along_z: bool) -> void:
	var len: float = r.size.y if along_z else r.size.x
	var c := r.get_center()
	var n := maxi(1, int(round(len / 6.0)))
	var yaw := 0.0 if along_z else PI / 2
	for i in n:
		var u := -len / 2 + len * (i + 0.5) / n
		var p := Vector3(c.x + (0.0 if along_z else u), y, c.y + (u if along_z else 0.0))
		put("lantern", "rt_timber_bay", xf(p, yaw, Vector3(1, 1, len / n / 6.0)))

static func _lantern_bridge() -> void:
	if not _L.islands.has("plaza_bridge_west"): return
	for x in [-46.0, -34.0]:
		put("lantern", "rt_lantern_pier", xf(Vector3(x, 0, 33), PI / 2))
		for s in [-1, 1]: light(Vector3(x, -2.2, 33 + s * 5.0), Color(1.0, 0.55, 0.28), 1.3, 6.0)
	for g in [[-31.0, "MARKET TERRACE", "DOCK PLAZA"], [-49.0, "LANTERN BRIDGE", "LANTERN BRIDGE"]]:
		var x: float = g[0]
		put("lantern", "rt_lantern_gate", xf(Vector3(x, 0, 33)))
		label(g[1], Vector3(x + 0.12, 5.0, 33), PI / 2, 72, 0.0062, Color(1, 0.86, 0.5))
		label(g[2], Vector3(x - 0.12, 5.0, 33), -PI / 2, 72, 0.0062, Color(1, 0.86, 0.5))
		for s in [-1, 1]: light(Vector3(x, 3.6, 33 + s * 2.6), Color(1.0, 0.6, 0.3), 1.2, 7.0)
	for p in [[-24.5, 37.6, PI], [-55.5, 28.4, 0.0]]:
		put("lantern", "rt_banner_crimson", xf(Vector3(p[0], 0, p[1]), p[2]))

# ------------------------------------------------------------------ the freight routes
static func _girder_deck(r: Rect2, y: float, along_z: bool) -> void:
	var len: float = r.size.y if along_z else r.size.x
	var wid: float = r.size.x if along_z else r.size.y
	var c := r.get_center()
	var n := maxi(1, int(round(len / 6.0)))
	var yaw := 0.0 if along_z else PI / 2
	for i in n:
		var u := -len / 2 + len * (i + 0.5) / n
		var p := Vector3(c.x + (0.0 if along_z else u), y, c.y + (u if along_z else 0.0))
		put("freight", "rt_girder_bay", xf(p, yaw, Vector3(wid / 8.0, 1, len / n / 6.0)))

static func _freight() -> void:
	var white := Color(0.95, 0.98, 1.0)
	var flood := Color(1.0, 0.9, 0.72)
	# the gangway (x 22..58, z 26..34)
	if _L.islands.has("pier_gangway"):
		_gantry(Vector3(28.0, 0, 30), -PI / 2, "PIER A  >>  EVACUATION", "DOCK PLAZA")
		for p in [[Vector3(44, 0, 25.4), PI], [Vector3(52, 0, 34.6), 0.0]]:
			_mast(p[0], p[1], flood)
	# the freight approach, the haul span and the lift bridge (x -10..-2)
	if _L.islands.has("yard_approach"):
		_gantry(Vector3(-6, 0, 5.0), PI, "CHECKPOINT 7  /  CRANE YARD", "DOCK PLAZA")
		_gantry(Vector3(-6, 0, -43.5), PI, "GRUDD INDUSTRIES  CRANE YARD", "CHECKPOINT 7")
		for p in [[Vector3(-10.6, 0, -26.0), PI / 2], [Vector3(-1.4, 0, -55.0), -PI / 2], [Vector3(-10.6, 0, -86.0), PI / 2]]:
			_mast(p[0], p[1], flood)

static func _gantry(pos: Vector3, yaw: float, front: String, back: String) -> void:
	var t := xf(pos, yaw, Vector3(0.86, 1, 1))
	put("freight", "rt_sign_gantry", t)
	var sm: Dictionary = kit("rt_sign_gantry").marks
	var sp: Vector3 = t * (sm.get("sign", Vector3(0, 5.7, 0.54)) as Vector3)
	label(front, sp + t.basis.z.normalized() * 0.02, yaw, 64, 0.0072, Color(0.95, 1, 0.96), Color(0.05, 0.2, 0.16))
	label(back, t * Vector3(0, 5.7, -0.1), yaw + PI, 56, 0.0062, Color(0.95, 1, 0.96), Color(0.05, 0.2, 0.16))
	spot(t * Vector3(0, 6.6, 1.2), t * Vector3(0, 0, 5.0), Color(1.0, 0.93, 0.8), 2.0, 14.0, 42.0)

static func _mast(pos: Vector3, yaw: float, c: Color) -> void:
	var t := xf(pos, yaw)
	put("freight", "rt_flood_mast", t)
	spot(t * Vector3(0, 9.2, 0.6), t * Vector3(0, 0, 7.0), c, 3.2, 22.0, 46.0)

# ------------------------------------------------------------------ clouds under the bridges
static func _clouds() -> void:
	var q := QuadMesh.new(); q.size = Vector2(1, 1)
	var pm: ShaderMaterial = SkyW._shader(SkyW.PUFF)
	var rng := RandomNumberGenerator.new(); rng.seed = 4242
	var items := []
	# [start, end, spread] along each route, well below the decks
	for ln in [[Vector2(0, 95), Vector2(0, 44), 9.0], [Vector2(-58, 33), Vector2(-22, 33), 8.0], [Vector2(22, 30), Vector2(58, 30), 8.0],
			[Vector2(-6, 9), Vector2(-6, -97), 9.0]]:
		var a: Vector2 = ln[0]; var b: Vector2 = ln[1]
		var n := int(a.distance_to(b) / 7.0) + 2
		for i in n:
			var u := (i + rng.randf()) / n
			var c := a.lerp(b, u)
			var side := Vector2(-(b - a).normalized().y, (b - a).normalized().x) * rng.randf_range(-1, 1) * float(ln[2])
			var s := rng.randf_range(12.0, 22.0)
			var p := Vector3(c.x + side.x, rng.randf_range(-24.0, -14.0), c.y + side.y)
			items.append([Transform3D(Basis().scaled(Vector3(s, s * 0.55, 1)), p), Color(1, 1, 1, rng.randf_range(0.5, 0.85)), Color(rng.randf(), 0, 0, 0)])
	var mi := SkyW._mm(root, q, pm, items, true)
	mi.name = "Route_clouds"
