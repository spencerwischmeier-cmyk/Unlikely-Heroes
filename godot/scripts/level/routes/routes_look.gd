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
##   - the sky routes (--no-routes-sky turns just these off): lattice cable pylons with lantern heads and arms
##     along the viaduct's overhead cable; the Skyline Cableway's bullwheel towers, a tall support tower in the
##     clouds under each station and one mid-span on the haul rope, garden lamps, flower boxes and pennants on
##     the haul rope; the balloon barge's painted airship hull and striped gas envelope, pennants on the tether;
##     the dish rail standing on lattice pylons with signal lamps
##   - banks of cloud drifting under the bridges, so the drop reads as sky, and an area grade per route
##     ("viaduct", "lantern_bridge", "freight_*" in systems/area_mood.gd)
## w_routes.gd registers each styled railing (segs: it builds only the collider) and each deck whose structure
## this rebuilds (decks: it skips its steel trusses and keel lamps). Props come from art/route_kit.py
## (godot/models/routes/*.glb), merged per prop and drawn as MultiMeshes; k_stone_* becomes a weathered,
## world-space sandstone with moss in the joints.
##   --no-routes-look   skip all of it (w_routes builds the old railings, frames and trusses)
##   --no-routes-sky    keep the first routes pass but skip the sky routes (cableway, barge, dish rail, pylons)

const M := preload("res://scripts/mats.gd")
const SkyW := preload("res://scripts/level/docks/sky.gd")
const DIR := "res://models/routes/"

static var segs: Array = []      # [style, Vector2 a, Vector2 b, y] from w_routes._railing
static var decks: Array = []     # [style, name, Rect2, y, along_z] from w_routes._deck
static var masts: Array = []     # [foot, height, arm_to] from w_routes._cable_mast
static var _kits := {}
static var _stone := {}
static var root: Node3D
static var batches := {}         # "zone|path" -> Array[Transform3D]
static var n_lights := 0
static var n_props := 0
static var _L: Node3D

static func on() -> bool:
	return not OS.get_cmdline_user_args().has("--no-routes-look")

static func sky_on() -> bool:
	return on() and not OS.get_cmdline_user_args().has("--no-routes-sky")

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
		var big := path.contains("pier") or path.contains("arch") or path.contains("gate") or path.contains("gantry") or path.contains("mast") or path.contains("bay") \
			or path.contains("cable_") or path.contains("hull") or path.contains("envelope")
		mi.visibility_range_end = 260.0 if big else 90.0
		mi.visibility_range_end_margin = 10.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		# the small dressing (rails, flowers) skips the shadow pass; the structure casts
		if path.contains("flowers") or path.contains("rail_") or path.contains("post") or path.contains("parapet") \
				or path.contains("pennant") or path.contains("head") or path.contains("arm") or path.contains("signal") or path.contains("garden_lamp"):
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
	if sky_on():
		_viaduct_masts()
		_cableway()
		_barge()
		_dish_rail()
	flush()
	_clouds()
	segs.clear(); decks.clear(); masts.clear()
	print("[routes] %d props, %d lights, built in %d ms" % [n_props, n_lights, Time.get_ticks_msec() - t0])

# ------------------------------------------------------------------ railings
const RAILS := {   # style -> [piece, post, piece length]
	"viaduct": ["rt_parapet", "rt_parapet_post", 2.0],
	"lantern": ["rt_rail_lacquer", "rt_lacquer_post", 2.0],
	"freight": ["rt_rail_freight", "rt_freight_post", 2.0],
	"iron": ["res://models/kit/railing_2m.glb", "res://models/kit/railing_post.glb", 2.0],
	"station": ["res://models/kit/railing_2m.glb", "res://models/kit/railing_post.glb", 2.0],   # + flower boxes
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
			if style == "station" and i % 2 == 0:
				var hs := hash(Vector2i(int(c.x * 10), int(c.y * 10)))
				put(zone, "rt_flowers_a" if hs % 2 == 0 else "rt_flowers_b", Transform3D(Basis(Vector3.UP, yaw), Vector3(c.x, y + 0.04, c.y)))
				fl += 1
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
			if _near_mast(Vector3(side * 4.15, 0, z), 1.6): continue
			put("viaduct", "rt_lamp_twin", xf(Vector3(side * 4.15, 0, z), PI / 2))
			if side == s: light(Vector3(side * 3.6, 3.7, z), Color(1.0, 0.74, 0.46), 1.6, 9.0)
	# the niche lamps on the piers' faces glow down the stonework
	for z in [82.2, 57.0]:
		for sx in [-1, 1]: light(Vector3(sx * 6.0, -4.2, z), Color(1.0, 0.7, 0.42), 1.2, 6.0)
	# city banners outside the parapets
	var bn := ["rt_banner_teal", "rt_banner_crimson", "rt_banner_plum"]
	var k := 0
	for z in ([85.6, 75.8, 61.8, 52.1] if sky_on() else [87.3, 77.3, 61.8, 52.1]):   # clear of the cable pylons
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
	var lines := [[Vector2(0, 95), Vector2(0, 44), 9.0], [Vector2(-58, 33), Vector2(-22, 33), 8.0], [Vector2(22, 30), Vector2(58, 30), 8.0],
			[Vector2(-6, 9), Vector2(-6, -97), 9.0]]
	if sky_on():   # the cableway, the barge's tether and the dish rail
		lines += [[Vector2(-30, -40), Vector2(6, -54), 10.0], [Vector2(62, -34), Vector2(36, -48), 9.0], [Vector2(20, -52), Vector2(2, -98), 9.0]]
	for ln in lines:
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

# ------------------------------------------------------------------ the sky routes (--no-routes-sky)
## a lattice pylon from `foot` up to `top_y` (stretched to fit; `width` widens the tall ones that drop into the
## clouds); `head` puts the lantern crown on top
static func _pylon(zone: String, foot: Vector3, top_y: float, width := 1.0, head := true) -> Vector3:
	var h := maxf(top_y - foot.y, 1.0)
	put(zone, "rt_cable_pylon", Transform3D(Basis().scaled(Vector3(width, h / 8.0, width)), foot))
	var top := Vector3(foot.x, top_y + 0.07 * h / 8.0, foot.z)
	if head: put(zone, "rt_pylon_head", xf(top, float(hash(Vector2i(int(foot.x), int(foot.z))) % 628) / 100.0))
	return top

## a lattice arm from `from` reaching horizontally to over `to` (its saddle ends there)
static func _arm(zone: String, from: Vector3, to: Vector3) -> void:
	var d := Vector2(to.x - from.x, to.z - from.z)
	if d.length() < 0.3: return
	put(zone, "rt_pylon_arm", xf(from, atan2(-d.y, d.x), Vector3(d.length(), 1, 1)))

static func _near_mast(p: Vector3, r: float) -> bool:
	if not sky_on(): return false
	for m in masts:
		var f: Vector3 = m[0]
		if Vector2(f.x - p.x, f.z - p.z).length() < r: return true
	return false

static func _over_island(p: Vector3, grow := 1.5) -> bool:
	for k in _L.islands:
		if (_L.islands[k] as Rect2).grow(grow).has_point(Vector2(p.x, p.z)): return true
	return false

## pennants hanging under a rail every `step` metres (skipping the first and last `margin` metres)
static func _pennants(zone: String, curve: Curve3D, step: float, margin := 2.0, drop := 0.2) -> void:
	var L := curve.get_baked_length()
	var u := margin
	var k := 0
	var names := ["rt_pennant_a", "rt_pennant_b", "rt_pennant_c"]
	while u < L - margin:
		var p := curve.sample_baked(u)
		var q := curve.sample_baked(minf(u + 0.5, L))
		var d := q - p
		put(zone, names[k % 3], xf(p + Vector3(0, -drop, 0), atan2(-d.z, d.x)))
		u += step; k += 1

static func _rail_curve(meta_or_index) -> Curve3D:
	var i: int = -1
	if meta_or_index is String:
		if not _L.has_meta(meta_or_index): return null
		i = int(_L.get_meta(meta_or_index))
	else:
		i = int(meta_or_index)
	if i < 0 or i >= _L.rails.size(): return null
	return _L.rails[i].curve

## the viaduct's overhead cable: iron lattice pylons on the cornice, lantern heads, arms over the cable
static func _viaduct_masts() -> void:
	for m in masts:
		var foot: Vector3 = m[0]; var h: float = m[1]; var to: Vector3 = m[2]
		_pylon("viaduct", foot, foot.y + h - 0.05)
		_arm("viaduct", Vector3(foot.x, foot.y + h - 0.05, foot.z), to)
	var c := _rail_curve("rail_scrapline")
	if c: _pennants("viaduct", c, 2.2, 3.0)

## the Skyline Cableway (Roof Gardens -> signal mast terminal)
static func _cableway() -> void:
	if not _L.islands.has("mast_cable_station"): return
	var warm := Color(1.0, 0.72, 0.42)
	var y := 6.6
	# bullwheel towers over the station and the terminal
	for t in [[Vector3(-24.5, y, -40), 0.0, "TO THE SIGNAL MAST", "SKYLINE CABLEWAY"], [Vector3(3.0, y, -53.5), PI, "SIGNAL MAST", "SKYLINE CABLEWAY"]]:
		var pos: Vector3 = t[0]; var yaw: float = t[1]
		var tx := xf(pos, yaw)
		put("cableway", "rt_cable_tower", tx)
		var ax := tx.basis.x
		label(t[2], tx * Vector3(0.1, 4.35, 0) + ax * 0.03, yaw + PI / 2, 64, 0.0062, Color(1, 0.9, 0.62))
		label(t[3], tx * Vector3(-0.1, 4.35, 0) - ax * 0.03, yaw - PI / 2, 64, 0.0062, Color(1, 0.9, 0.62))
		for s in [-1, 1]: light(tx * Vector3(0, 4.4, s * 3.6), warm, 1.1, 7.0)
		# a tall support tower under the deck, down into the clouds
		_pylon("cableway", Vector3(pos.x - (2.0 if yaw == 0.0 else -0.5), -26.0, pos.z), y - 0.85, 4.2, false)
	# a mid-span tower carrying the haul rope, standing clear of the grind cable
	var haul_a := Vector3(-24.5, 11.5, -42.0); var haul_b := Vector3(4.5, 11.0, -55.0)
	var hp := haul_a.lerp(haul_b, 0.776)
	var foot := Vector3(hp.x, -26.0, hp.z - 2.4)
	var top := _pylon("cableway", foot, hp.y + 0.22, 2.4)
	_arm("cableway", Vector3(foot.x, hp.y + 0.22, foot.z), hp)
	light(top + Vector3(0, 0.5, 0), warm, 1.0, 6.0)
	# pennants on the haul rope (not over the stalled car)
	var n := 18
	var names := ["rt_pennant_a", "rt_pennant_b", "rt_pennant_c"]
	var d := haul_b - haul_a
	for i in n:
		var u := (i + 0.5) / n
		if u > 0.36 and u < 0.54: continue
		put("cableway", names[i % 3], xf(haul_a.lerp(haul_b, u) + Vector3(0, -0.05, 0), atan2(-d.z, d.x)))
	# garden lamps on the station and terminal corners (crooks pointing in)
	for l in [[Vector3(-30.6, y, -43.6), PI / 4], [Vector3(-23.4, y, -36.4), -3 * PI / 4], [Vector3(-23.4, y, -43.6), 3 * PI / 4],
			[Vector3(0.4, y, -56.6), PI / 4], [Vector3(5.6, y, -56.6), 3 * PI / 4]]:
		var lt := xf(l[0], l[1])
		put("cableway", "rt_garden_lamp", lt)
	for l in [[Vector3(-30.6, y, -43.6), PI / 4], [Vector3(5.6, y, -56.6), 3 * PI / 4]]:
		light(xf(l[0], l[1]) * Vector3(0.56, 2.98, 0), warm, 1.0, 6.0)
	# banners on the terminal's open side, toward the gardens
	put("cableway", "rt_banner_teal", xf(Vector3(0.3, y, -57.4), PI))
	put("cableway", "rt_banner_plum", xf(Vector3(-30.7, y, -44.4), 0.0))

## the balloon barge at Pier C and its tether to the mast landing
static func _barge() -> void:
	if not _L.islands.has("pier_barge"): return
	var c := Vector3(58, 3.0, -34)
	put("barge", "rt_barge_hull", xf(c))
	put("barge", "rt_barge_envelope", xf(c))
	light(c + Vector3(0, -0.3, -8.8), Color(1.0, 0.7, 0.4), 1.2, 7.0)
	# under-hull glow from the portholes, and the envelope lit from below by the deck lamps
	for sx in [-1, 1]: light(c + Vector3(sx * 4.6, -1.2, 0), Color(1.0, 0.74, 0.46), 0.9, 6.0)
	for l in [[Vector3(54.4, 3.0, -28.4), -PI / 4], [Vector3(61.6, 3.0, -28.4), -3 * PI / 4], [Vector3(54.4, 3.0, -39.6), PI / 4]]:
		put("barge", "rt_garden_lamp", xf(l[0], l[1]))
	light(xf(Vector3(54.4, 3.0, -28.4), -PI / 4) * Vector3(0.56, 2.98, 0), Color(1.0, 0.72, 0.42), 1.0, 6.0)
	var tc := _rail_curve("rail_balloon")
	if tc: _pennants("barge", tc, 1.6, 1.5)
	# the landing end: a lamp and a pylon the tether is made fast to
	put("barge", "rt_garden_lamp", xf(Vector3(37.6, 3.0, -50.6), PI / 2))
	_pylon("barge", Vector3(37.4, 3.0, -46.6), 7.2, 0.8)
	for sx in [-1, 1]:
		label("BALLOON LINE", Vector3(58 + sx * 3.97, 2.45, -34.3), sx * PI / 2, 48, 0.006, Color(0.2, 0.16, 0.1), Color(1, 0.93, 0.8))

## the dish rail (signal mast -> Crane Yard gate): the rail stands on lattice pylons rising out of the clouds,
## with red-over-green signals on short arms beside it
static func _dish_rail() -> void:
	var c := _rail_curve(_L.R_YARD)
	if c == null: return
	var L := c.get_baked_length()
	var u := 6.0
	var k := 0
	while u < L - 3.0:
		var p := c.sample_baked(u)
		if not _over_island(p):
			var q := c.sample_baked(minf(u + 0.5, L))
			var d := (q - p); d.y = 0; d = d.normalized()
			var side := Vector3(-d.z, 0, d.x) * (1.0 if k % 2 == 0 else -1.0)
			_pylon("dish", Vector3(p.x, -26.0, p.z), p.y - 0.2, 1.6 + (p.y + 26.0) / 30.0, false)
			if k % 2 == 0:
				var at := p + side * 1.3 + Vector3(0, -0.45, 0)
				_arm("dish", Vector3(p.x, p.y - 0.25, p.z), at)
				put("dish", "rt_signal_lamp", xf(at + Vector3(0, -0.2, 0), atan2(-d.x, -d.z)))   # facing the riders coming down
				if k % 4 == 0: light(at + Vector3(0, 1.9, 0), Color(1.0, 0.35, 0.25), 0.9, 6.0)
			k += 1
		u += 10.0
	_pennants("dish", c, 2.6, 4.0)
