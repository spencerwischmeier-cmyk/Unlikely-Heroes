extends RefCounted
## The Signal Mast set piece (area "mast"). North is -z. Heights are walking heights.
##   gallery (8)         x 5..23, z -43..-25 around the tower; control hut, screens, windsocks
##   lattice tower       gallery (8) -> dish deck (20) at (14, -34), maintenance ring at 16.2
##   antenna spire       (20.6, -40.6) from the gallery up to 46 with blinking beacons
##   the long way up     ledges (10.4, 12.8) -> east catwalk C1 (12.8, wind gusts) -> cable rail -> relay
##                       pylon P1 (13) -> lift -> P2 (23) -> hook chain -> dish deck (20)
##   risky perches       sprockets on the C1 wind perch, the P2 storm perch, the maintenance ring, the hut
##                       roof and the old fourth ledge under the deck
## Runtime animation lives in mast_fx.gd.

const M := preload("res://scripts/mats.gd")
const FXS := preload("res://scripts/level/mast/mast_fx.gd")
const DIR := "res://models/mast/"

const C := Vector3(14, 0, -34)                 # tower centre
const SPIRE := Vector3(20.6, 0.0, -40.6)       # antenna spire (x, z); foot on the gallery at 8
const C1 := Rect2(21.4, -30.9, 9.2, 2.4)       # east catwalk, top 12.8
const C1_Y := 12.8
const P1 := Rect2(37.5, -57.0, 10.5, 10.5)     # relay pylon base, top 13
const P1_Y := 13.0
const P2 := Rect2(41.9, -55.5, 6.1, 6.2)       # pylon top, top 23
const P2_Y := 23.0
const LIFT := Vector3(50.2, 0, -52.4)          # lift shaft centre (x, z)
const LAUNCH := Vector3(42.4, 23.0, -49.8)     # where the hook chain to the deck starts
const HOOK1 := Vector3(37.8, 29.4, -47.0)
const HOOK2 := Vector3(29.2, 29.4, -41.9)
const RING_Y := 16.2                           # maintenance ring round the tower
const HELIX_Y0 := 20.3                         # spiral catwalk round the spire: bottom (by the deck) ...
const HELIX_Y1 := 28.4                         # ... and the lookout at the top
const PERCH_C1 := Rect2(24.9, -27.9, 1.8, 1.8) # wind perch off the catwalk, top 12.8
const PERCH_P2 := Rect2(49.4, -59.4, 2.6, 2.6) # storm perch off P2, top 24.6
const PERCH_P2_Y := 24.6

static var _unit: BoxMesh
static var _gear: Mesh
static var mats := {}

static func build(L: Node3D) -> void:
	var fx: Node3D = FXS.new(); fx.name = "MastFX"; fx.level = L; L.add_child(fx)
	_make_mats()
	_tower(L, fx)
	_spire(L, fx)
	_deck_crown(L, fx)
	_gallery(L, fx)
	_east_route(L, fx)
	_pylon(L, fx)
	_cables(L, fx)
	_perches(L, fx)
	_dish_beam(L, fx)
	flush(L)
	_story(L)
	_debug(L)

# ================================================================= helpers
static func _make_mats() -> void:
	if not mats.is_empty(): return
	mats.red = M.paint(Color(0.86, 0.3, 0.2), true)
	mats.white = M.paint(Color(0.93, 0.91, 0.86), true)
	mats.steel = M.metal(Color(0.28, 0.32, 0.37), true)
	mats.teal = M.paint(Color(0.24, 0.55, 0.58), true)
	mats.brass = M.brass(true)
	mats.rubber = M.rubber(Color(0.1, 0.1, 0.11))
	mats.grate = M.deck(Color(0.72, 0.76, 0.8))
	mats.hazard = M.hazard()
	mats.cyan = M.glow(Color(0.25, 0.94, 1.0), 3.0)
	mats.warm = M.glow(Color(1.0, 0.63, 0.19), 3.0)
	mats.screen = M.glow(Color(0.3, 0.95, 0.85), 1.6)
	mats.bar = M.glow(Color(0.4, 1.0, 0.6), 3.0)

static func unit_box() -> BoxMesh:
	if _unit == null:
		_unit = BoxMesh.new(); _unit.size = Vector3.ONE
	return _unit

## a beam from a to b, t thick (square section). Struts are static, so they are batched per material into
## MultiMeshes (flush() at the end of build) to keep the draw calls down.
static var _batches := {}

static func strut(parent: Node3D, a: Vector3, b: Vector3, t: float, mat: Material) -> void:
	var d := b - a; var len := d.length()
	if len < 0.001: return
	var y := d / len
	var x := y.cross(Vector3.UP if absf(y.y) < 0.99 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	var tr := parent.global_transform * Transform3D(Basis(x * t, y * len, z * t), (a + b) * 0.5) if parent.is_inside_tree() else Transform3D(Basis(x * t, y * len, z * t), (a + b) * 0.5)
	if not _batches.has(mat): _batches[mat] = []
	_batches[mat].append(tr)

static func flush(L: Node3D) -> void:
	for mat in _batches:
		var list: Array = _batches[mat]
		var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D; mm.mesh = unit_box()
		mm.instance_count = list.size()
		for i in list.size(): mm.set_instance_transform(i, list[i])
		var mmi := MultiMeshInstance3D.new(); mmi.multimesh = mm; mmi.material_override = mat; mmi.name = "MastStruts"
		L.add_child(mmi)
	_batches.clear()

static func boxm(parent: Node3D, pos: Vector3, size: Vector3, mat: Material, collide := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new(); mi.mesh = unit_box(); mi.material_override = mat
	mi.position = pos; mi.scale = size
	parent.add_child(mi)
	if collide:
		var sb := StaticBody3D.new(); var cs := CollisionShape3D.new(); var sh := BoxShape3D.new()
		sh.size = size; cs.shape = sh; sb.position = pos; sb.add_child(cs); parent.add_child(sb)
	return mi

static func collider(parent: Node3D, pos: Vector3, size: Vector3) -> void:
	var sb := StaticBody3D.new(); var cs := CollisionShape3D.new(); var sh := BoxShape3D.new()
	sh.size = size; cs.shape = sh; sb.position = pos; sb.add_child(cs); parent.add_child(sb)

static func sphere(parent: Node3D, pos: Vector3, r: float, mat: Material) -> MeshInstance3D:
	var s := SphereMesh.new(); s.radius = r; s.height = r * 2; s.radial_segments = 12; s.rings = 6
	var mi := MeshInstance3D.new(); mi.mesh = s; mi.material_override = mat; mi.position = pos
	parent.add_child(mi)
	return mi

static func cylm(parent: Node3D, pos: Vector3, r_top: float, r_bot: float, h: float, mat: Material, sides := 12) -> MeshInstance3D:
	var cm := CylinderMesh.new(); cm.top_radius = r_top; cm.bottom_radius = r_bot; cm.height = h; cm.radial_segments = sides; cm.rings = 1
	var mi := MeshInstance3D.new(); mi.mesh = cm; mi.material_override = mat; mi.position = pos
	parent.add_child(mi)
	return mi

## a model from res://models/mast/, base centre at pos, scaled to `height`
static func model(parent: Node3D, name: String, pos: Vector3, rot_y := 0.0, height := 1.0) -> Node3D:
	var p := DIR + name + ".glb"
	if not ResourceLoader.exists(p): return null
	var n: Node3D = load(p).instantiate()
	var ab := AABB(); var first := true
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		var tr := Transform3D(); var q: Node = mi
		while q != n and q is Node3D:
			tr = (q as Node3D).transform * tr; q = q.get_parent()
		var a := tr * mi.get_aabb()
		ab = a if first else ab.merge(a); first = false
	var s := height / maxf(ab.size.y, 0.001)
	var holder := Node3D.new(); holder.name = "M_" + name
	parent.add_child(holder)
	holder.position = pos; holder.rotation.y = rot_y
	holder.add_child(n)
	n.scale = Vector3.ONE * s
	n.position = -Vector3(ab.get_center().x, ab.position.y, ab.get_center().z) * s
	holder.set_meta("size", ab.size * s)
	return holder

## a sagging cable (tube) from a to b
static func cable(parent: Node3D, a: Vector3, b: Vector3, sag: float, r: float, mat: Material, segs := 16) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for i in segs + 1:
		var u := float(i) / segs
		pts.append(a.lerp(b, u) - Vector3(0, sag * 4.0 * u * (1.0 - u), 0))
	tube(parent, pts, r, mat)
	return pts

static func tube(parent: Node3D, pts: PackedVector3Array, r: float, mat: Material, sides := 6) -> MeshInstance3D:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array = []
	for i in pts.size():
		var tng := (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var side := tng.cross(Vector3.UP if absf(tng.y) < 0.95 else Vector3.RIGHT).normalized()
		var up := side.cross(tng)
		var ring := []
		for k in sides:
			var ang := k * TAU / sides
			ring.append([pts[i] + (side * cos(ang) + up * sin(ang)) * r, side * cos(ang) + up * sin(ang)])
		rings.append(ring)
	for i in pts.size() - 1:
		for k in sides:
			var k2 := (k + 1) % sides
			for v in [rings[i][k], rings[i + 1][k], rings[i + 1][k2], rings[i][k], rings[i + 1][k2], rings[i][k2]]:
				st.set_normal(v[1]); st.add_vertex(v[0])
	var mi := MeshInstance3D.new(); mi.mesh = st.commit(); mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

## a square lattice tower: legs at the corners of a w0 -> w1 square, girders and X braces per section
static func lattice(parent: Node3D, c: Vector3, h0: float, h1: float, w0: float, w1: float, n: int, leg_t: float, brace_t: float,
		leg_mats: Array, brace_mat: Material, ring_mats: Array = []) -> void:
	for i in n:
		var ya := lerpf(h0, h1, float(i) / n); var yb := lerpf(h0, h1, float(i + 1) / n)
		var wa := lerpf(w0, w1, float(i) / n) * 0.5; var wb := lerpf(w0, w1, float(i + 1) / n) * 0.5
		var ca := [Vector3(-wa, ya, -wa), Vector3(wa, ya, -wa), Vector3(wa, ya, wa), Vector3(-wa, ya, wa)]
		var cb := [Vector3(-wb, yb, -wb), Vector3(wb, yb, -wb), Vector3(wb, yb, wb), Vector3(-wb, yb, wb)]
		for k in 4:
			var k2 := (k + 1) % 4
			strut(parent, c + ca[k], c + cb[k], leg_t, leg_mats[i % leg_mats.size()])
			strut(parent, c + cb[k], c + cb[k2], brace_t * 1.3, brace_mat)
			strut(parent, c + ca[k], c + cb[k2], brace_t, brace_mat)
			strut(parent, c + ca[k2], c + cb[k], brace_t, brace_mat)
		if i < ring_mats.size() and ring_mats[i] != null:
			for k in 4:
				var k2 := (k + 1) % 4
				strut(parent, c + cb[k] * Vector3(1.04, 1, 1.04) + Vector3(0, -0.22, 0), c + cb[k2] * Vector3(1.04, 1, 1.04) + Vector3(0, -0.22, 0), 0.09, ring_mats[i])

static func beacon(fx: Node3D, parent: Node3D, pos: Vector3, r := 0.22, light := false, rate := 0.8, phase := 0.0, col := Color(1, 0.12, 0.08)) -> void:
	var m := M.glow(col, 7.0)
	cylm(parent, pos - Vector3(0, r * 0.9, 0), r * 0.7, r * 0.8, r * 0.6, mats.steel, 10)
	sphere(parent, pos, r, m)
	var l: OmniLight3D = null
	if light:
		l = OmniLight3D.new(); l.light_color = col; l.omni_range = 10.0; l.light_energy = 2.0; l.position = pos
		l.shadow_enabled = false
		parent.add_child(l)
	fx.beacons.append({ mat = m, light = l, phase = phase, rate = rate, base = 7.0 })

static func gear_mesh() -> Mesh:
	if _gear: return _gear
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hub := CylinderMesh.new(); hub.top_radius = 0.26; hub.bottom_radius = 0.26; hub.height = 0.1; hub.radial_segments = 16; hub.rings = 1
	st.append_from(hub, 0, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3.ZERO))
	var tooth := BoxMesh.new(); tooth.size = Vector3(0.11, 0.12, 0.1)
	for k in 8:
		var a := k * TAU / 8
		st.append_from(tooth, 0, Transform3D(Basis(Vector3.BACK, a), Vector3(sin(a), cos(a), 0) * 0.3))
	st.generate_normals()
	_gear = st.commit()
	return _gear

static func sprocket(L: Node3D, fx: Node3D, id: String, pos: Vector3) -> void:
	if Game.is_collected("mast_sprocket", id): return
	var n := Node3D.new(); n.position = pos + Vector3(0, 0.75, 0); L.add_child(n)
	var mi := MeshInstance3D.new(); mi.mesh = gear_mesh()
	var m := M.std(Color(0.95, 0.72, 0.3), 0.9, 0.25); m.emission_enabled = true; m.emission = Color(1, 0.65, 0.2); m.emission_energy_multiplier = 0.8
	mi.material_override = m; n.add_child(mi)
	fx.sprockets.append({ node = n, id = id, pos = n.position })

## a pennant / bunting material that flaps with the wind (fx sets "gust")
static func flag_mat(fx: Node3D) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_disabled;
uniform float gust = 0.0;
uniform vec3 wind = vec3(0.0, 0.0, 1.0);
void vertex() {
	float k = UV.y;
	float w = 0.4 + gust * 1.1;
	float ph = TIME * (5.0 + gust * 9.0) + UV.x * 2.3 + k * 2.0;
	VERTEX += (wind * (0.15 + 0.35 * w) + vec3(0.0, 0.6, 0.0) * sin(ph) * 0.35 * w + cross(wind, vec3(0.0, 1.0, 0.0)) * cos(ph * 1.3) * 0.2 * w) * k;
}
void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.8;
}
"""
	var m := ShaderMaterial.new(); m.shader = sh
	fx.flag_mats.append(m)
	return m

const FLAG_COLS := [Color(0.95, 0.42, 0.18), Color(0.95, 0.85, 0.3), Color(0.25, 0.7, 0.75), Color(0.93, 0.92, 0.86), Color(0.85, 0.25, 0.22)]

## a string of triangle flags hanging under a sagging line from a to b
static func bunting(parent: Node3D, fx: Node3D, a: Vector3, b: Vector3, sag: float, n: int, mat: ShaderMaterial) -> void:
	var pts := cable(parent, a, b, sag, 0.025, mats.rubber, 12)
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n:
		var u := (i + 0.5) / n
		var f := u * 12.0; var j := mini(int(f), 11)
		var p := pts[j].lerp(pts[j + 1], f - j)
		var tng := (pts[j + 1] - pts[j]).normalized()
		var col: Color = FLAG_COLS[i % FLAG_COLS.size()]
		for v in [[p - tng * 0.22, 0.0], [p + tng * 0.22, 0.0], [p + Vector3(0, -0.55, 0), 1.0]]:
			st.set_color(col); st.set_uv(Vector2(i * 0.7, v[1])); st.set_normal(Vector3.UP); st.add_vertex(v[0])
	var mi := MeshInstance3D.new(); mi.mesh = st.commit(); mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)

## a long pennant flying from a pole top, pointing along dir
static func pennant(parent: Node3D, top: Vector3, dir: Vector3, length: float, col: Color, mat: ShaderMaterial) -> void:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 6
	for i in segs:
		var u0 := float(i) / segs; var u1 := float(i + 1) / segs
		var h0 := 0.45 * (1.0 - u0); var h1 := 0.45 * (1.0 - u1)
		var p0 := top + dir * length * u0; var p1 := top + dir * length * u1
		var c := col if i % 2 == 0 else col.lightened(0.25)
		for v in [[p0 + Vector3(0, h0, 0), u0], [p1 + Vector3(0, h1, 0), u1], [p1 - Vector3(0, h1, 0), u1],
				[p0 + Vector3(0, h0, 0), u0], [p1 - Vector3(0, h1, 0), u1], [p0 - Vector3(0, h0, 0), u0]]:
			st.set_color(c); st.set_uv(Vector2(top.x, v[1])); st.set_normal(Vector3.UP); st.add_vertex(v[0] - Vector3(0, 0.45, 0))
	var mi := MeshInstance3D.new(); mi.mesh = st.commit(); mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)

static func flag_pole(parent: Node3D, fx: Node3D, base: Vector3, h: float, dir: Vector3, col: Color, mat: ShaderMaterial) -> void:
	cylm(parent, base + Vector3(0, h * 0.5, 0), 0.05, 0.08, h, mats.steel, 8)
	sphere(parent, base + Vector3(0, h + 0.05, 0), 0.09, mats.brass)
	pennant(parent, base + Vector3(0, h - 0.1, 0), dir, 2.2, col, mat)

static func windsock(parent: Node3D, fx: Node3D, base: Vector3, h: float, dir: Vector3, gust := "") -> void:
	cylm(parent, base + Vector3(0, h * 0.5, 0), 0.05, 0.08, h, mats.white, 8)
	var piv := Node3D.new(); piv.position = base + Vector3(0, h, 0); parent.add_child(piv)
	var ring := TorusMesh.new(); ring.inner_radius = 0.22; ring.outer_radius = 0.28
	var rm := MeshInstance3D.new(); rm.mesh = ring; rm.material_override = mats.steel; rm.rotation.x = PI / 2; rm.position.z = 0.1
	piv.add_child(rm)
	var sock := Node3D.new(); sock.position.z = 0.1; piv.add_child(sock)
	# the sock hangs from its ring: four striped hoops tapering away along +z
	for k in 4:
		var cm := CylinderMesh.new(); cm.top_radius = 0.26 - k * 0.045; cm.bottom_radius = 0.26 - (k + 1) * 0.045; cm.height = 0.42; cm.radial_segments = 10; cm.rings = 1
		var mi := MeshInstance3D.new(); mi.mesh = cm
		mi.material_override = M.cloth(Color(0.95, 0.4, 0.15) if k % 2 == 0 else Color(0.95, 0.93, 0.88))
		mi.rotation.x = PI / 2; mi.position.z = 0.21 + k * 0.42
		sock.add_child(mi)
	fx.socks.append({ pivot = piv, sock = sock, dir = dir, gust = gust, phase = randf() * TAU })

# ================================================================= the tower
static func _tower(L: Node3D, fx: Node3D) -> void:
	var root := Node3D.new(); root.name = "MastTower"; L.add_child(root)
	# power rings (warm until the dish is aligned, then they light cyan from the bottom up)
	var rings := []
	for i in 4:
		var m := M.glow(Color(1.0, 0.63, 0.19), 3.0); rings.append(m); fx.power_rings.append(m)
	lattice(root, Vector3(C.x, 0, C.z), 8.0, 20.0, 3.8, 3.4, 4, 0.34, 0.13, [mats.red, mats.white], mats.steel, rings)
	# the cable trunk in the middle, with conduits that glow
	cylm(root, Vector3(C.x, 14, C.z), 0.55, 0.65, 12, mats.steel, 12)
	for y in [9.5, 12.5, 15.5, 18.5]: cylm(root, Vector3(C.x, y, C.z), 0.72, 0.72, 0.25, mats.brass, 12)
	for k in 3:
		var a := k * TAU / 3
		var cm := M.glow(Color(1.0, 0.63, 0.19), 2.0)
		fx.power_rings.append(cm)
		strut(root, Vector3(C.x + cos(a) * 0.62, 8.2, C.z + sin(a) * 0.62), Vector3(C.x + cos(a) * 0.62, 19.6, C.z + sin(a) * 0.62), 0.07, cm)
	# base plates and gussets on the gallery
	for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var p := Vector3(C.x + s.x * 1.9, 8.0, C.z + s.y * 1.9)
		boxm(root, p + Vector3(0, 0.12, 0), Vector3(0.9, 0.24, 0.9), mats.steel)
		for b in [Vector3(0.3, 0.3, 0.3), Vector3(-0.3, 0.3, 0.3), Vector3(0.3, 0.3, -0.3), Vector3(-0.3, 0.3, -0.3)]:
			sphere(root, p + b * Vector3(1, 0.85, 1), 0.06, mats.brass)
		fx.spark_spots.append(p + Vector3(0, 6.0, 0))
	# panel antennas and microwave drums bolted to the faces (above head height on the gallery)
	for f: Vector3 in [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0)]:
		var side := Vector3(-f.z, 0, f.x)
		for k in [-0.75, 0.75]:
			var p: Vector3 = Vector3(C.x, 11.4, C.z) + f * 2.15 + side * k
			var pn := boxm(root, p, Vector3(0.36, 1.5, 0.14), mats.white)
			pn.rotation.y = atan2(f.x, f.z)
			strut(root, p - f * 0.07 + Vector3(0, 0.5, 0), p - f * 0.4 + Vector3(0, 0.5, 0), 0.06, mats.steel)
			strut(root, p - f * 0.07 - Vector3(0, 0.5, 0), p - f * 0.4 - Vector3(0, 0.5, 0), 0.06, mats.steel)
		if f.z != 0:
			var dp: Vector3 = Vector3(C.x, 13.6, C.z) + f * 2.3 + side * 0.4
			var drum := cylm(root, dp, 0.5, 0.5, 0.35, mats.white, 16)
			drum.rotation = Vector3(PI / 2, atan2(f.x, f.z), 0)
			cylm(root, dp + f * 0.19, 0.42, 0.42, 0.04, mats.steel, 16).rotation = Vector3(PI / 2, atan2(f.x, f.z), 0)
	# the service ladder up the west face, cut off halfway (Grudd's crews took the top half)
	for z in [-0.35, 0.35]:
		strut(root, Vector3(C.x - 2.05, 8.0, C.z + z), Vector3(C.x - 2.05, 13.4, C.z + z), 0.06, mats.brass)
	for k in 17: strut(root, Vector3(C.x - 2.05, 8.3 + k * 0.3, C.z - 0.35), Vector3(C.x - 2.05, 8.3 + k * 0.3, C.z + 0.35), 0.04, mats.brass)
	strut(root, Vector3(C.x - 2.05, 13.4, C.z + 0.35), Vector3(C.x - 2.6, 13.9, C.z + 0.6), 0.06, mats.brass)
	fx.spark_spots.append(Vector3(C.x - 2.1, 13.4, C.z))
	# the maintenance ring (16.2): a square balcony round the tower, solid railings, a gap toward the old
	# fourth ledge (south-west) so you can climb back to the deck
	var y := RING_Y
	var w_in := 1.95; var w_out := 3.3
	var dm: Material = mats.grate
	boxm(root, Vector3(C.x, y - 0.15, C.z - (w_in + w_out) * 0.5), Vector3(w_out * 2, 0.3, w_out - w_in), dm, true)
	boxm(root, Vector3(C.x, y - 0.15, C.z + (w_in + w_out) * 0.5), Vector3(w_out * 2, 0.3, w_out - w_in), dm, true)
	boxm(root, Vector3(C.x - (w_in + w_out) * 0.5, y - 0.15, C.z), Vector3(w_out - w_in, 0.3, w_in * 2), dm, true)
	boxm(root, Vector3(C.x + (w_in + w_out) * 0.5, y - 0.15, C.z), Vector3(w_out - w_in, 0.3, w_in * 2), dm, true)
	for e in [[Vector3(C.x, y - 0.32, C.z - w_out), Vector3(w_out * 2, 0.06, 0.06)], [Vector3(C.x, y - 0.32, C.z + w_out), Vector3(w_out * 2, 0.06, 0.06)],
			[Vector3(C.x - w_out, y - 0.32, C.z), Vector3(0.06, 0.06, w_out * 2)], [Vector3(C.x + w_out, y - 0.32, C.z), Vector3(0.06, 0.06, w_out * 2)]]:
		boxm(root, e[0], e[1], mats.cyan)
	# brackets under the ring
	for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		strut(root, Vector3(C.x + s.x * 1.75, y - 2.2, C.z + s.y * 1.75), Vector3(C.x + s.x * 3.1, y - 0.3, C.z + s.y * 3.1), 0.12, mats.steel)
	L.railing(C.x - w_out, C.z - w_out, C.x + w_out, C.z - w_out, y)
	L.railing(C.x + w_out, C.z - w_out, C.x + w_out, C.z + w_out, y)
	L.railing(C.x - w_out, C.z - w_out, C.x - w_out, C.z + w_out, y)
	L.railing(C.x - 1.3, C.z + w_out, C.x + w_out, C.z + w_out, y)
	# the cut ladder stub where the third ledge was: a dangling broken bracket and a sign
	strut(root, Vector3(C.x + 2.2, 13.6, C.z + 3.8), Vector3(C.x + 3.6, 13.0, C.z + 4.6), 0.12, mats.steel)
	strut(root, Vector3(C.x + 3.6, 13.0, C.z + 4.6), Vector3(C.x + 3.9, 11.9, C.z + 4.9), 0.1, mats.steel)
	fx.spark_spots.append(Vector3(C.x + 3.6, 13.0, C.z + 4.6))
	L.hint_sign("LADDER'S OUT (GRUDD'S CREWS). TAKE THE CATWALK EAST", Vector3(20.2, 8.0, -37.4), PI * 0.5)
	# the underside of the dish deck: a steel skirt on brackets instead of a rock
	boxm(root, Vector3(C.x, 19.0, C.z), Vector3(7.6, 0.5, 7.6), mats.steel)
	for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		strut(root, Vector3(C.x + s.x * 1.75, 16.6, C.z + s.y * 1.75), Vector3(C.x + s.x * 3.7, 18.8, C.z + s.y * 3.7), 0.18, mats.red)

static func _spire(L: Node3D, fx: Node3D) -> void:
	var root := Node3D.new(); root.name = "MastSpire"; L.add_child(root)
	var s := SPIRE
	lattice(root, s, 8.0, 44.0, 1.7, 0.5, 12, 0.18, 0.07, [mats.red, mats.white], mats.steel)
	collider(root, s + Vector3(0, 11.5, 0), Vector3(1.7, 7.0, 1.7))
	boxm(root, s + Vector3(0, 8.15, 0), Vector3(2.2, 0.3, 2.2), mats.steel)
	# the whip on top and its beacons
	cylm(root, s + Vector3(0, 46.5, 0), 0.03, 0.1, 5.0, mats.white, 8)
	beacon(fx, root, s + Vector3(0, 49.1, 0), 0.32, true, 0.75, 0.0)
	beacon(fx, root, s + Vector3(0, 44.2, 0), 0.24, false, 0.75, 0.0)
	beacon(fx, root, s + Vector3(0.55, 35.2, 0), 0.2, false, 0.75, 0.5)
	beacon(fx, root, s + Vector3(-0.55, 35.2, 0), 0.2, false, 0.75, 0.5)
	# yardarm with dangling whips, a crow's nest and a little dish
	strut(root, s + Vector3(-2.6, 38.0, 0), s + Vector3(2.6, 38.0, 0), 0.14, mats.steel)
	for x in [-2.4, -1.2, 1.2, 2.4]:
		cylm(root, s + Vector3(x, 36.6, 0), 0.02, 0.03, 2.8, mats.white, 6)
		sphere(root, s + Vector3(x, 35.2, 0), 0.07, mats.cyan)
	boxm(root, s + Vector3(0, 33.0, 0), Vector3(2.0, 0.18, 2.0), mats.grate)
	for e in [[Vector3(0, 33.55, -1.0), Vector3(2.0, 0.06, 0.06)], [Vector3(0, 33.55, 1.0), Vector3(2.0, 0.06, 0.06)],
			[Vector3(-1.0, 33.55, 0), Vector3(0.06, 0.06, 2.0)], [Vector3(1.0, 33.55, 0), Vector3(0.06, 0.06, 2.0)]]:
		boxm(root, s + e[0], e[1], mats.white)
	var small := Kit.place(root, "dish_small", s + Vector3(0.5, 33.1, 0.5), PI * 0.25, 1.0, false)
	if small: small.rotation.x = -0.3
	# braces tying the spire to the tower
	for y in [12.0, 16.0]:
		strut(root, s + Vector3(-0.7, y, 0.7), Vector3(C.x + 1.8, y + 0.8, C.z - 1.8), 0.14, mats.steel)
	# a flag from the crow's nest
	flag_pole(root, fx, s + Vector3(-0.9, 33.1, -0.9), 2.6, Vector3(0, 0, 1), Color(0.95, 0.42, 0.18), flag_mat(fx))
	_helix(L, fx, root)

## a box collider (and optional mesh) with an arbitrary basis (columns scaled by size)
static func obox(parent: Node3D, basis: Basis, size: Vector3, pos: Vector3, mat: Material, collide := true) -> void:
	if mat:
		var mi := MeshInstance3D.new(); mi.mesh = unit_box(); mi.material_override = mat
		parent.add_child(mi); mi.transform = Transform3D(basis.scaled_local(size), pos)
	if collide:
		var sb := StaticBody3D.new(); var cs := CollisionShape3D.new(); var sh := BoxShape3D.new(); sh.size = size
		cs.shape = sh; sb.add_child(cs); parent.add_child(sb); sb.transform = Transform3D(basis, pos)

## the spiral catwalk round the spire: from the dish deck's north-east corner (20) one and a half turns up to
## a windy lookout (28.4) with sprockets
static func _helix(L: Node3D, fx: Node3D, root: Node3D) -> void:
	var s := SPIRE
	var r := 1.95; var y0 := HELIX_Y0; var y1 := HELIX_Y1
	var a0 := deg_to_rad(135.0); var turn := deg_to_rad(540.0); var n := 18
	for i in n:
		var aa := a0 + turn * i / n; var ab := a0 + turn * (i + 1) / n; var am := (aa + ab) * 0.5
		var pa := Vector3(s.x + cos(aa) * r, lerpf(y0, y1, float(i) / n), s.z + sin(aa) * r)
		var pb := Vector3(s.x + cos(ab) * r, lerpf(y0, y1, float(i + 1) / n), s.z + sin(ab) * r)
		var rad := Vector3(cos(am), 0, sin(am))
		var dir := (pb - pa).normalized()
		var up := dir.cross(rad)
		var x := rad
		if up.y < 0: up = -up; x = -rad
		var b := Basis(x, up, dir)
		var mid := (pa + pb) * 0.5 + rad * 0.0
		var len := pa.distance_to(pb) + 0.16
		obox(root, b, Vector3(1.15, 0.16, len), mid - up * 0.08, mats.grate)
		obox(root, b, Vector3(1.2, 0.05, len), mid - up * 0.2, mats.steel, false)
		# outer rail (solid) and inner guard (solid, a thin pipe to look at)
		obox(root, b, Vector3(0.08, 0.9, len), mid - rad * 0.62 + up * 0.45, null)
		if i > 0:   # the first step is open on the outside: that's where the bridge from the deck joins
			obox(root, b, Vector3(0.08, 1.05, len), mid + rad * 0.62 + up * 0.5, null)
			strut(root, pa + rad * 0.62 + Vector3(0, 1.0, 0), pb + rad * 0.62 + Vector3(0, 1.0, 0), 0.07, mats.white)
			strut(root, pa + rad * 0.62 + Vector3(0, 0.88, 0), pb + rad * 0.62 + Vector3(0, 0.88, 0), 0.03, mats.cyan)
		strut(root, pa - rad * 0.62 + Vector3(0, 0.85, 0), pb - rad * 0.62 + Vector3(0, 0.85, 0), 0.05, mats.steel)
		strut(root, pa + rad * 0.62, pa + rad * 0.62 + Vector3(0, 1.0, 0), 0.06, mats.white)
		# a bracket back to the spire
		strut(root, pa - rad * 0.55 - Vector3(0, 0.15, 0), Vector3(s.x, pa.y - 1.2, s.z) + rad * 0.45, 0.07, mats.steel)
	# bridge from the deck corner onto the first step
	var d0 := Vector3(C.x + 3.6, 20.0, C.z - 3.6)
	var h0 := Vector3(s.x + cos(a0) * r, y0, s.z + sin(a0) * r)
	var dir0 := (h0 - d0).normalized()
	var side0 := dir0.cross(Vector3.UP).normalized()
	var b0 := Basis(side0, dir0.cross(side0) if dir0.cross(side0).y > 0 else -dir0.cross(side0), dir0)
	obox(root, b0, Vector3(1.1, 0.16, d0.distance_to(h0) + 0.3), (d0 + h0) * 0.5 - Vector3(0, 0.08, 0), mats.grate)
	# the lookout at the top
	var ae := a0 + turn
	var rd := Vector3(cos(ae), 0, sin(ae))
	var lc := Vector3(s.x, y1, s.z) + rd * 3.5
	var lb := Basis(Vector3.UP, atan2(rd.x, rd.z))
	var lx := lb.x; var lz := lb.z
	var lr := Rect2(lc.x - 1.4, lc.z - 1.4, 2.8, 2.8)
	obox(root, lb, Vector3(2.4, 0.24, 2.4), Vector3(lc.x, y1 - 0.12, lc.z), mats.grate)
	for e in [[lz * 1.2, Vector3(2.4, 0.22, 0.2)], [lx * 1.2, Vector3(0.2, 0.22, 2.4)], [-lx * 1.2, Vector3(0.2, 0.22, 2.4)]]:
		obox(root, lb, e[1], Vector3(lc.x, y1 - 0.08, lc.z) + e[0], mats.hazard, false)
	# far railing (solid); the sides are open to the wind
	obox(root, lb, Vector3(2.4, 1.05, 0.1), Vector3(lc.x, y1 + 0.52, lc.z) + lz * 1.2, null)
	strut(root, Vector3(lc.x, y1 + 1.0, lc.z) + lz * 1.2 - lx * 1.2, Vector3(lc.x, y1 + 1.0, lc.z) + lz * 1.2 + lx * 1.2, 0.08, mats.white)
	strut(root, Vector3(lc.x, y1 + 0.88, lc.z) + lz * 1.2 - lx * 1.2, Vector3(lc.x, y1 + 0.88, lc.z) + lz * 1.2 + lx * 1.2, 0.03, mats.cyan)
	for k in [-1.2, 0.0, 1.2]: strut(root, Vector3(lc.x, y1, lc.z) + lz * 1.2 + lx * k, Vector3(lc.x, y1 + 1.0, lc.z) + lz * 1.2 + lx * k, 0.06, mats.white)
	strut(root, Vector3(lc.x, y1 - 0.25, lc.z), Vector3(s.x, y1 - 3.2, s.z) + rd * 0.4, 0.14, mats.steel)
	for i in 5: sprocket(L, fx, "helix%d" % i, Vector3(lc.x, y1, lc.z) + lx * (-0.8 + (i % 3) * 0.8) + lz * (-0.6 + (i / 3) * 0.9))
	beacon(fx, root, Vector3(lc.x, y1 + 1.2, lc.z) + lz * 1.2 + lx * 1.2, 0.14, false, 0.75, 0.2)
	# a coin-op viewer, because of course there is one
	var vw := Node3D.new(); vw.position = Vector3(lc.x, y1, lc.z) + lz * 0.85 - lx * 0.8; vw.rotation.y = atan2(rd.x, rd.z); root.add_child(vw)
	cylm(vw, Vector3(0, 0.55, 0), 0.08, 0.14, 1.1, mats.steel, 8)
	boxm(vw, Vector3(0, 1.2, 0), Vector3(0.36, 0.3, 0.42), mats.teal)
	for x in [-0.09, 0.09]: cylm(vw, Vector3(x, 1.24, 0.28), 0.07, 0.07, 0.2, mats.brass, 10).rotation.x = PI / 2
	_gust(root, fx, "lookout", lr.grow(1.4), y1 - 1.0, y1 + 4.0, Vector3(1, 0, 0.3).normalized(), 3.5, 6.5, 1.2, [], lc + Vector3(0, 1, 0))
	L.label("LOOKOUT", Vector3(lc.x, y1, lc.z) - lz * 0.2, 0.9, Color(1, 0.85, 0.5), atan2(rd.x, rd.z) + PI)

static func _deck_crown(L: Node3D, fx: Node3D) -> void:
	var root := Node3D.new(); root.name = "MastCrown"; L.add_child(root)
	var fm := flag_mat(fx)
	# beacon posts on the deck corners, windsock and pennants on the north-west corner
	for s in [Vector2(-1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var p := Vector3(C.x + s.x * 3.75, 20.0, C.z + s.y * 3.75)
		cylm(root, p + Vector3(0, 0.45, 0), 0.08, 0.12, 0.9, mats.steel, 8)
		beacon(fx, root, p + Vector3(0, 1.05, 0), 0.16, false, 0.75, 0.25)
	windsock(root, fx, Vector3(C.x - 3.6, 20.0, C.z - 1.5), 2.6, Vector3(0.3, 0, 1).normalized())
	flag_pole(root, fx, Vector3(C.x + 3.65, 20.0, C.z + 1.6), 3.2, Vector3(0, 0, 1), Color(0.25, 0.7, 0.75), fm)
	fx.loop_at("mast_flag_loop", Vector3(C.x, 22.0, C.z), -12.0, 5.0, 30.0)
	# junction boxes and cable runs over the deck edge
	boxm(root, Vector3(C.x - 3.5, 20.4, C.z + 1.2), Vector3(0.5, 0.8, 0.9), mats.teal)
	sphere(root, Vector3(C.x - 3.22, 20.6, C.z + 1.2), 0.06, mats.cyan)
	cable(root, Vector3(C.x - 3.5, 20.1, C.z + 1.2), Vector3(C.x - 0.5, 20.05, C.z - 0.2), 0.0, 0.07, mats.rubber, 4)
	fx.spark_spots.append(Vector3(C.x - 3.5, 20.9, C.z + 1.2))
	# bunting from the spire's crow's nest down to the deck corners and the gallery
	bunting(root, fx, SPIRE + Vector3(0, 31.5, 0), Vector3(31.6, 6.5, -39.6), 3.0, 30, fm)
	bunting(root, fx, SPIRE + Vector3(0, 30.5, 0), Vector3(5.4, 11.6, -42.6), 2.5, 30, fm)

# ================================================================= the gallery (8)
static func _gallery(L: Node3D, fx: Node3D) -> void:
	var root := Node3D.new(); root.name = "MastGallery"; L.add_child(root)
	var fm := flag_mat(fx)
	# the control hut on the south edge, door toward the mast
	var hut := model(root, "control_hut", Vector3(14.6, 8.0, -26.6), PI, 3.3)
	var hs: Vector3 = hut.get_meta("size") if hut else Vector3(3.2, 3.3, 3.0)
	collider(root, Vector3(14.6, 8.0 + hs.y * 0.5 - 0.2, -26.6), Vector3(hs.x * 0.92, hs.y - 0.4, hs.z * 0.85))
	var roof_y := 8.0 + hs.y - 0.4
	var hl := OmniLight3D.new(); hl.light_color = Color(0.4, 1.0, 0.85); hl.light_energy = 1.4; hl.omni_range = 6.0
	hl.position = Vector3(14.6, 9.8, -28.6); root.add_child(hl)
	fx.loop_at("mast_radio", Vector3(14.6, 9.5, -27.5), -8.0, 3.0, 22.0)
	# step up to the hut roof (sprockets up there)
	L.prop("crate_large", Vector3(17.6, 8.0, -26.2), 0.2)
	for i in 3: sprocket(L, fx, "hut%d" % i, Vector3(13.6 + i * 1.0, roof_y, -26.6))
	# the outdoor screen bank: three monitors with readouts and a bar graph
	var bank := Node3D.new(); bank.position = Vector3(7.0, 8.0, -31.0); bank.rotation.y = PI * 0.5; root.add_child(bank)
	boxm(bank, Vector3(0, 0.55, 0), Vector3(3.0, 1.1, 0.8), mats.teal)
	collider(bank, Vector3(0, 0.75, 0), Vector3(3.0, 1.5, 0.8))
	boxm(bank, Vector3(0, 1.12, 0.12), Vector3(3.1, 0.08, 0.95), mats.steel)
	for i in 3:
		var x := -1.0 + i * 1.0
		var frame := boxm(bank, Vector3(x, 1.75, -0.05), Vector3(0.92, 0.72, 0.18), mats.steel)
		frame.rotation.x = -0.25
		boxm(bank, Vector3(x, 1.76, 0.05), Vector3(0.8, 0.6, 0.02), mats.screen).rotation.x = -0.25
		if i == 1:
			for k in 6:
				var b := boxm(bank, Vector3(x - 0.3 + k * 0.12, 1.5, 0.1), Vector3(0.08, 0.5, 0.02), mats.bar)
				b.set_meta("y0", 1.5); b.set_meta("h", 0.5)
				fx.bars.append(b)
		else:
			var l := Label3D.new(); l.font_size = 40; l.pixel_size = 0.0045; l.outline_size = 0; l.shaded = false
			l.modulate = Color(0.45, 1, 0.9); l.position = Vector3(x, 1.78, 0.08); l.rotation.x = -0.25
			l.set_meta("kind", "signal" if i == 0 else "freq"); l.text = "..."
			bank.add_child(l); fx.screen_labels.append(l)
		for k in 5:
			sphere(bank, Vector3(x - 0.3 + k * 0.15, 1.2, 0.4), 0.035, [mats.cyan, mats.warm, M.glow(Color(1, 0.2, 0.2), 3.0)][(i + k) % 3])
	# windsocks and flags on the gallery corners
	windsock(root, fx, Vector3(22.4, 8.0, -25.6), 3.6, Vector3(0, 0, 1), "c1")
	windsock(root, fx, Vector3(5.6, 8.0, -42.4), 3.6, Vector3(0.4, 0, 1).normalized())
	flag_pole(root, fx, Vector3(5.6, 8.0, -25.6), 4.5, Vector3(0.2, 0, 1).normalized(), Color(0.95, 0.42, 0.18), fm)
	flag_pole(root, fx, Vector3(22.4, 8.0, -42.4), 4.5, Vector3(0.2, 0, 1).normalized(), Color(0.95, 0.85, 0.3), fm)
	for p in [Vector3(6.2, 8, -26.2), Vector3(21.8, 8, -26.2), Vector3(6.2, 8, -41.8), Vector3(21.8, 8, -41.8)]:
		cylm(root, p + Vector3(0, 0.35, 0), 0.07, 0.1, 0.7, mats.steel, 8)
		beacon(fx, root, p + Vector3(0, 0.85, 0), 0.13, false, 0.75, 0.4)
	# clutter: generator, cable spool, crates, antennas, lamps
	L.prop("generator", Vector3(9.0, 8.0, -41.4), 0.0)
	fx.spark_spots.append(Vector3(9.0, 9.7, -41.4))
	L.prop("antenna", Vector3(22.0, 8.0, -38.0), 0.0, 1.0)
	L.prop("antenna", Vector3(6.0, 8.0, -36.0), 0.0, 0.8)
	L.prop("barrel", Vector3(17.6, 8.0, -42.4), 0.0)
	L.prop("barrel", Vector3(18.5, 8.0, -42.5), 0.4)
	L.prop("crate_small", Vector3(11.2, 8.0, -42.2), 0.3)
	L.lamp(18.0, -25.8, Color(1.0, 0.75, 0.45), 8.0)
	L.lamp(10.0, -42.4, Color(0.4, 0.95, 1.0), 8.0)
	cable(root, Vector3(9.0, 9.4, -41.4), Vector3(C.x - 1.9, 9.6, C.z - 1.9), 0.5, 0.08, mats.rubber, 8)
	cable(root, Vector3(14.6, 10.8, -27.6), Vector3(C.x + 0.3, 11.0, C.z + 1.9), 0.4, 0.07, mats.rubber, 8)

# ================================================================= the long way up (east)
static func _east_route(L: Node3D, fx: Node3D) -> void:
	var root := Node3D.new(); root.name = "MastEast"; L.add_child(root)
	# C1: the windy catwalk from the second ledge out east, hung from the tower on tension rods
	var c := C1.get_center()
	boxm(root, Vector3(c.x, C1_Y - 0.18, c.y), Vector3(C1.size.x, 0.36, C1.size.y), mats.grate, true)
	for e in [[Vector3(c.x, C1_Y - 0.1, C1.position.y), Vector3(C1.size.x, 0.22, 0.2)], [Vector3(c.x, C1_Y - 0.1, C1.end.y), Vector3(C1.size.x, 0.22, 0.2)]]:
		boxm(root, e[0], e[1], mats.hazard)
		boxm(root, e[0] + Vector3(0, -0.16, 0), Vector3(e[1].x, 0.05, 0.06), mats.cyan)
	for x in [25.0, 28.0, 30.4]:
		strut(root, Vector3(x, C1_Y - 0.35, C1.position.y), Vector3(x, C1_Y - 0.35, C1.end.y), 0.12, mats.steel)
		strut(root, Vector3(x, C1_Y - 0.3, C1.end.y), Vector3(C.x + 1.8, 19.4, C.z + 1.8), 0.05, mats.steel)
	# wind baffles: stand south of one and the gust can't reach you
	var shelters: Array = []
	for bx in [23.4, 27.2]:
		var b := Node3D.new(); b.position = Vector3(bx + 0.7, C1_Y, C1.position.y + 0.12); root.add_child(b)
		boxm(b, Vector3(0, 1.2, 0), Vector3(1.5, 2.4, 0.12), mats.teal, true)
		for k in 5: boxm(b, Vector3(0, 0.4 + k * 0.42, 0.08), Vector3(1.4, 0.06, 0.06), mats.steel)
		boxm(b, Vector3(0, 2.45, 0), Vector3(1.6, 0.1, 0.2), mats.hazard)
		shelters.append(Rect2(bx + 0.05, C1.position.y, 1.3, C1.size.y))
	# gusts from the north sweep the catwalk (and the little perch south of it)
	var gr := Rect2(C1.position.x, C1.position.y - 0.5, C1.size.x, C1.size.y + 4.0)
	_gust(root, fx, "c1", gr, C1_Y - 1.0, C1_Y + 5.0, Vector3(0, 0, 1), 5.0, 7.0, 0.0, shelters, Vector3(c.x, C1_Y + 1.5, c.y - 2.5))
	windsock(root, fx, Vector3(30.3, C1_Y, C1.position.y + 0.15), 2.4, Vector3(0, 0, 1), "c1")
	fx.loop_at("mast_flag_loop", Vector3(c.x, C1_Y + 1.5, c.y), -14.0, 4.0, 25.0)
	var wl := Label3D.new(); wl.font_size = 44; wl.pixel_size = 0.005; wl.outline_size = 8; wl.set_meta("kind", "wind")
	wl.position = Vector3(22.6, C1_Y + 2.3, C1.position.y + 0.02); wl.text = "WIND"; wl.modulate = Color(0.6, 0.95, 1)
	boxm(root, Vector3(22.6, C1_Y + 2.3, C1.position.y - 0.06), Vector3(1.1, 0.6, 0.1), mats.steel)
	cylm(root, Vector3(22.6, C1_Y + 1.0, C1.position.y - 0.06), 0.04, 0.04, 2.0, mats.steel, 6)
	root.add_child(wl); fx.screen_labels.append(wl)
	L.label("GUSTS: DUCK BEHIND THE BAFFLES", Vector3(25.8, C1_Y, -29.7), 0.9, Color(1, 0.85, 0.5))
	# the cable rail: a thick power cable sagging from the catwalk to the relay pylon
	var pts := [Vector3(29.6, 13.2, -29.7), Vector3(32.8, 12.7, -31.2), Vector3(35.6, 12.35, -34.6), Vector3(37.7, 12.4, -38.6),
		Vector3(39.2, 12.8, -42.4), Vector3(40.2, 13.4, -45.4), Vector3(40.5, 13.75, -46.7)]
	cable_rail(L, root, pts)
	boxm(root, Vector3(29.6, 13.0, -29.7), Vector3(0.6, 0.5, 0.6), mats.steel)
	sphere(root, Vector3(29.6, 13.3, -29.7), 0.22, mats.brass)

## a grind rail that looks like a fat power cable (no posts), with a glowing underline
static func cable_rail(L: Node3D, parent: Node3D, points: Array) -> int:
	var path := Path3D.new(); var curve := Curve3D.new(); curve.bake_interval = 0.2
	for p in points: curve.add_point(p)
	for i in curve.point_count:
		var prev := curve.get_point_position(maxi(i - 1, 0)); var nxt := curve.get_point_position(mini(i + 1, curve.point_count - 1))
		var tn := (nxt - prev) / 6.0
		curve.set_point_in(i, -tn); curve.set_point_out(i, tn)
	path.curve = curve
	L.add_child(path)
	var baked := curve.get_baked_points()
	var pts := PackedVector3Array()
	var step := maxi(1, baked.size() / 40)
	for i in range(0, baked.size(), step): pts.append(baked[i])
	if pts[pts.size() - 1] != baked[baked.size() - 1]: pts.append(baked[baked.size() - 1])
	tube(parent, pts, 0.16, mats.rubber, 8)
	var g := M.glow(Color(1.0, 0.7, 0.23), 3.0)
	var under := PackedVector3Array()
	for p in pts: under.append(p + Vector3(0, -0.17, 0))
	tube(parent, under, 0.045, g, 5)
	# clamps along it
	for i in range(3, pts.size() - 2, 6):
		cylm(parent, pts[i], 0.21, 0.21, 0.18, mats.brass, 10).rotation = Vector3(PI / 2, 0, 0)
	L.rails.append({ curve = curve, path = path, locked = false, glow = g, length = curve.get_baked_length() })
	return L.rails.size() - 1

static func _gust(parent: Node3D, fx: Node3D, gname: String, r: Rect2, y0: float, y1: float, dir: Vector3, power: float, period: float, offset: float, shelters: Array, snd: Vector3) -> void:
	var p := CPUParticles3D.new()
	var bm := BoxMesh.new(); bm.size = Vector3(0.025, 1.6, 0.025); p.mesh = bm
	var m := StandardMaterial3D.new(); m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; m.albedo_color = Color(1, 1, 1, 0.35)
	p.material_override = m
	p.emitting = false; p.amount = 40; p.lifetime = 0.8
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(r.size.x * 0.5 + 1.0, (y1 - y0) * 0.4, 1.0)
	p.direction = dir; p.spread = 4.0; p.gravity = Vector3.ZERO
	p.initial_velocity_min = 14.0; p.initial_velocity_max = 20.0
	p.particle_flag_align_y = true
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var c := r.get_center()
	p.position = Vector3(c.x, (y0 + y1) * 0.5, c.y) - dir * (r.size.y * 0.5 + 3.0)
	parent.add_child(p)
	fx.gusts.append({ name = gname, rect = r, y0 = y0, y1 = y1, dir = dir, power = power, period = period, offset = offset, shelters = shelters,
		parts = p, snd = snd, amount = 0.0, was = 0.0 })

# ================================================================= relay pylon (P1 13, lift, P2 23)
static func _pylon(L: Node3D, fx: Node3D) -> void:
	var root := Node3D.new(); root.name = "MastPylon"; L.add_child(root)
	var c1 := P1.get_center()
	L.islands["mast_pylon"] = P1; L.heights["mast_pylon"] = P1_Y
	boxm(root, Vector3(c1.x, P1_Y - 0.3, c1.y), Vector3(P1.size.x, 0.6, P1.size.y), mats.grate, true)
	_edges(root, P1, P1_Y)
	# the pylon under P1 down into the clouds
	lattice(root, Vector3(c1.x, 0, c1.y), -40.0, P1_Y - 0.6, 6.5, 4.2, 6, 0.4, 0.15, [mats.red, mats.white], mats.steel)
	for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		strut(root, Vector3(c1.x + s.x * 2.1, P1_Y - 3.5, c1.y + s.y * 2.1), Vector3(c1.x + s.x * 4.9, P1_Y - 0.6, c1.y + s.y * 4.9), 0.22, mats.steel)
	# railings: north and west all along, south either side of the cable, east either side of the lift
	L.railing(P1.position.x, P1.position.y, P1.end.x, P1.position.y, P1_Y)
	L.railing(P1.position.x, P1.position.y, P1.position.x, P1.end.y, P1_Y)
	L.railing(P1.position.x, P1.end.y, 38.8, P1.end.y, P1_Y)
	L.railing(42.4, P1.end.y, P1.end.x, P1.end.y, P1_Y)
	L.railing(P1.end.x, P1.position.y, P1.end.x, LIFT.z - 2.0, P1_Y)
	L.railing(P1.end.x, LIFT.z + 2.0, P1.end.x, P1.end.y, P1_Y)
	L.checkpoints.append({ pos = Vector3(40.0, P1_Y + 0.1, -49.0), r = 2.2 })
	L.label("RELAY PYLON", Vector3(c1.x - 1.0, P1_Y, c1.y + 1.5), 3.2, Color(0.75, 0.98, 1))
	L.crate_spots.append(Vector3(38.8, P1_Y, -55.6)); L.crate_spots.append(Vector3(46.6, P1_Y, -47.6))
	L.prop("generator", Vector3(39.6, P1_Y, -55.2), PI * 0.5)
	L.prop("barrel", Vector3(46.8, P1_Y, -56.0), 0.0)
	L.prop("barrel", Vector3(46.0, P1_Y, -56.2), 0.7)
	L.lamp(38.2, -47.3, Color(0.4, 0.95, 1.0), P1_Y)
	fx.spark_spots.append(Vector3(39.6, P1_Y + 1.6, -55.2))
	L.hint_sign("LIFT TO THE TOP, THEN HOOKS TO THE DISH", Vector3(46.4, P1_Y, -48.0), -PI * 0.5)
	# P2 on four legs, lift shaft beside it
	var c2 := P2.get_center()
	L.islands["mast_pylon_top"] = P2; L.heights["mast_pylon_top"] = P2_Y
	boxm(root, Vector3(c2.x, P2_Y - 0.3, c2.y), Vector3(P2.size.x, 0.6, P2.size.y), mats.grate, true)
	_edges(root, P2, P2_Y)
	for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var top := Vector3(c2.x + s.x * (P2.size.x * 0.5 - 0.3), P2_Y - 0.6, c2.y + s.y * (P2.size.y * 0.5 - 0.3))
		var bot := Vector3(top.x, P1_Y, top.z)
		strut(root, bot, top, 0.3, mats.red)
		collider(root, (bot + top) * 0.5, Vector3(0.3, top.y - bot.y, 0.3))
	for s in [-1, 1]:
		strut(root, Vector3(P2.position.x + 0.3, P1_Y + 0.4, c2.y + s * 2.8), Vector3(P2.position.x + 0.3, P2_Y - 0.9, c2.y - s * 2.8), 0.12, mats.steel)
		strut(root, Vector3(c2.x + s * 2.75, P1_Y + 0.4, P2.position.y + 0.3), Vector3(c2.x - s * 2.75, P2_Y - 0.9, P2.position.y + 0.3), 0.12, mats.steel)
	L.railing(P2.position.x, P2.position.y, P2.end.x - 1.6, P2.position.y, P2_Y)
	L.railing(P2.position.x + 2.0, P2.end.y, P2.end.x, P2.end.y, P2_Y)
	L.railing(P2.position.x, P2.position.y, P2.position.x, P2.end.y - 2.0, P2_Y)
	L.railing(P2.end.x, LIFT.z + 2.0, P2.end.x, P2.end.y, P2_Y)
	L.checkpoints.append({ pos = Vector3(45.0, P2_Y + 0.1, -52.4), r = 1.8 })
	# the launch corner: hazard chevrons pointing at the hooks
	boxm(root, Vector3(LAUNCH.x + 0.1, P2_Y + 0.01, LAUNCH.z - 0.2), Vector3(1.4, 0.03, 1.4), mats.hazard)
	L.label("HOOKS >", Vector3(44.6, P2_Y, -50.6), 1.6, Color(1, 0.85, 0.5), -2.6)
	# lift and its shaft
	L.moving_platform(Vector3(LIFT.x, P1_Y - 0.3, LIFT.z), Vector3(LIFT.x, P2_Y - 0.3, LIFT.z), 9.0, Vector3(3.6, 0.6, 3.6), "mast_lift")
	for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var x: float = LIFT.x + s.x * 2.05; var z: float = LIFT.z + s.y * 2.05
		cylm(root, Vector3(x, (P1_Y - 3.0 + P2_Y + 3.0) * 0.5, z), 0.12, 0.12, P2_Y - P1_Y + 6.0, mats.white, 8)
	for y in [P1_Y - 2.5, P2_Y + 2.8]:
		for k in 4:
			var a := Vector2(-1, -1); var b := Vector2(1, -1)
			match k:
				1: a = Vector2(1, -1); b = Vector2(1, 1)
				2: a = Vector2(1, 1); b = Vector2(-1, 1)
				3: a = Vector2(-1, 1); b = Vector2(-1, -1)
			strut(root, Vector3(LIFT.x + a.x * 2.05, y, LIFT.z + a.y * 2.05), Vector3(LIFT.x + b.x * 2.05, y, LIFT.z + b.y * 2.05), 0.16, mats.steel)
	# pulley head and cables
	cylm(root, Vector3(LIFT.x, P2_Y + 3.3, LIFT.z), 0.6, 0.6, 0.4, mats.brass, 16).rotation.x = PI / 2
	for s in [-1, 1]: cylm(root, Vector3(LIFT.x + s * 0.5, (P2_Y + 3.0 + P1_Y) * 0.5, LIFT.z), 0.025, 0.025, P2_Y + 3.0 - P1_Y, mats.rubber, 6)
	beacon(fx, root, Vector3(LIFT.x + 2.05, P2_Y + 3.3, LIFT.z + 2.05), 0.16, false, 1.4, 0.0, Color(1, 0.75, 0.15))
	beacon(fx, root, Vector3(LIFT.x - 2.05, P2_Y + 3.3, LIFT.z - 2.05), 0.16, false, 1.4, 0.5, Color(1, 0.75, 0.15))
	# a mini lattice crown on P2 with a beacon and a small dish, windsock and flags
	var cr := Vector3(P2.position.x + 0.7, 0, P2.position.y + 0.7)
	lattice(root, cr, P2_Y, P2_Y + 6.0, 1.0, 0.4, 3, 0.12, 0.05, [mats.red, mats.white], mats.steel)
	collider(root, cr + Vector3(0, P2_Y + 1.5, 0), Vector3(1.0, 3.0, 1.0))
	beacon(fx, root, cr + Vector3(0, P2_Y + 6.4, 0), 0.25, true, 0.75, 0.1)
	var sd := Kit.place(root, "dish_small", cr + Vector3(0, P2_Y + 4.0, 0.3), 0.6, 1.0, false)
	if sd: sd.rotation.x = -0.4
	var fm := flag_mat(fx)
	windsock(root, fx, Vector3(P2.position.x + 0.3, P2_Y, -52.6), 2.8, Vector3(1, 0, 0), "p2")
	flag_pole(root, fx, Vector3(P2.end.x - 0.3, P2_Y, P2.end.y - 0.3), 3.2, Vector3(1, 0, 0), Color(0.85, 0.25, 0.22), fm)
	flag_pole(root, fx, Vector3(P1.position.x + 0.3, P1_Y, P1.position.y + 0.3), 4.0, Vector3(0.6, 0, 0.8).normalized(), Color(0.25, 0.7, 0.75), fm)
	# the hook chain from the launch corner to the dish deck
	L.hook(HOOK1); L.hook(HOOK2)

static func _edges(root: Node3D, r: Rect2, y: float) -> void:
	var c := r.get_center()
	for e in [[Vector3(c.x, y - 0.08, r.position.y), Vector3(r.size.x, 0.22, 0.25)], [Vector3(c.x, y - 0.08, r.end.y), Vector3(r.size.x, 0.22, 0.25)],
			[Vector3(r.position.x, y - 0.08, c.y), Vector3(0.25, 0.22, r.size.y)], [Vector3(r.end.x, y - 0.08, c.y), Vector3(0.25, 0.22, r.size.y)]]:
		boxm(root, e[0], e[1], mats.hazard)
		boxm(root, e[0] + Vector3(0, -0.2, 0), e[1] * Vector3(1, 0.25, 1) + Vector3(0.02, 0, 0.02), mats.cyan)

# ================================================================= cables to the rocks, vista
static func _cables(L: Node3D, fx: Node3D) -> void:
	var root := Node3D.new(); root.name = "MastCables"; L.add_child(root)
	var rocks := [[Vector3(28, -15, -71), 19.0, 0.6], [Vector3(48, -22, -75), 22.0, 2.4], [Vector3(26, -9, -60), 12.0, 4.0]]
	var tops := []
	for r in rocks:
		DocksDressing.place(L, "island", r[0], r[2], r[1], false)
		tops.append(r[0] + Vector3(0, r[1] * 0.78, 0))
	# anchor blocks on the rocks
	for p in tops:
		boxm(root, p + Vector3(0, 0.6, 0), Vector3(1.6, 1.2, 1.6), mats.steel)
		cylm(root, p + Vector3(0, 1.4, 0), 0.4, 0.5, 0.5, mats.brass, 12)
		beacon(fx, root, p + Vector3(0, 1.9, 0), 0.14, false, 0.75, 0.7)
	var rub: Material = mats.rubber
	cable(root, Vector3(C.x + 1.75, 18.6, C.z - 1.75), tops[0] + Vector3(0, 1.4, 0), 4.0, 0.14, rub, 24)
	cable(root, Vector3(C.x - 1.75, 18.2, C.z - 1.75), tops[2] + Vector3(-0.3, 1.4, 0), 3.0, 0.12, rub, 24)
	cable(root, SPIRE + Vector3(0.3, 34.5, -0.3), tops[1] + Vector3(0, 1.4, 0), 6.0, 0.12, rub, 28)
	cable(root, SPIRE + Vector3(-0.3, 33.0, -0.3), tops[0] + Vector3(0.3, 1.4, 0), 5.0, 0.1, rub, 24)
	cable(root, Vector3(P1.position.x + 0.5, P1_Y - 0.5, P1.position.y + 0.5), tops[2] + Vector3(0.3, 1.2, 0.3), 2.0, 0.12, rub, 16)
	cable(root, Vector3(P1.end.x - 0.5, P1_Y - 0.5, P1.position.y + 0.5), tops[1] + Vector3(-0.3, 1.2, 0), 3.0, 0.12, rub, 16)
	# warning orbs hanging along the big spans
	for k in 3:
		var a := Vector3(C.x + 1.75, 18.6, C.z - 1.75); var b: Vector3 = tops[0] + Vector3(0, 1.4, 0)
		var u := 0.25 + k * 0.25
		sphere(root, a.lerp(b, u) - Vector3(0, 4.0 * 4.0 * u * (1.0 - u), 0) - Vector3(0, 0.3, 0), 0.3, M.paint(Color(0.95, 0.45, 0.15)))

# ================================================================= risky perches with sprockets
static func _perches(L: Node3D, fx: Node3D) -> void:
	var root := Node3D.new(); root.name = "MastPerches"; L.add_child(root)
	# C1 wind perch: hop south off the catwalk; the gust blows straight over it
	var pc := PERCH_C1.get_center()
	boxm(root, Vector3(pc.x, C1_Y - 0.15, pc.y), Vector3(PERCH_C1.size.x, 0.3, PERCH_C1.size.y), mats.grate, true)
	_edges(root, PERCH_C1, C1_Y)
	strut(root, Vector3(pc.x, C1_Y - 0.3, pc.y), Vector3(pc.x, C1_Y - 0.3, C1.end.y), 0.1, mats.steel)
	for i in 3: sprocket(L, fx, "c1_%d" % i, Vector3(pc.x - 0.5 + i * 0.5, C1_Y, pc.y))
	# P2 storm perch: north-east of the pylon top, gusts shove you east into the void
	var pp := PERCH_P2.get_center()
	boxm(root, Vector3(pp.x, PERCH_P2_Y - 0.2, pp.y), Vector3(PERCH_P2.size.x, 0.4, PERCH_P2.size.y), mats.grate, true)
	_edges(root, PERCH_P2, PERCH_P2_Y)
	strut(root, Vector3(pp.x, PERCH_P2_Y - 0.4, pp.y), Vector3(P2.end.x - 0.3, P1_Y + 2.0, P2.position.y + 0.3), 0.16, mats.steel)
	for i in 4: sprocket(L, fx, "p2_%d" % i, Vector3(pp.x - 0.6 + (i % 2) * 1.2, PERCH_P2_Y, pp.y - 0.6 + (i / 2) * 1.2))
	beacon(fx, root, Vector3(PERCH_P2.end.x - 0.1, PERCH_P2_Y + 0.25, PERCH_P2.position.y + 0.1), 0.12, false, 0.75, 0.3)
	_gust(root, fx, "p2", PERCH_P2.grow(1.2), PERCH_P2_Y - 1.0, PERCH_P2_Y + 4.0, Vector3(1, 0, 0), 4.5, 6.0, 2.5, [], Vector3(pp.x, PERCH_P2_Y + 1.0, pp.y))
	# the maintenance ring under the deck: drop down from the deck, grab them, climb out by the fourth ledge
	for p in [Vector3(C.x - 1.6, RING_Y, C.z - 2.6), Vector3(C.x, RING_Y, C.z - 2.6), Vector3(C.x + 1.6, RING_Y, C.z - 2.6), Vector3(C.x + 2.6, RING_Y, C.z)]:
		sprocket(L, fx, "ring%d" % int(p.x * 10 + p.z), p)
	# the old fourth ledge, now only reachable from above
	sprocket(L, fx, "ledge4a", Vector3(11.3, 17.6, -28.2))
	sprocket(L, fx, "ledge4b", Vector3(12.1, 17.6, -27.6))

# ================================================================= the dish beam (shown once aligned)
static func _dish_beam(L: Node3D, fx: Node3D) -> void:
	if L.dish_pivot == null: return
	var beam := Node3D.new(); beam.name = "DishBeam"; beam.visible = false
	L.dish_pivot.add_child(beam)
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 col : source_color = vec4(0.3, 0.95, 1.0, 1.0);
uniform float power = 0.0;
uniform float core = 1.0;
void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float along = UV.y;
	float bands = 0.65 + 0.35 * sin(along * 90.0 + TIME * 14.0);
	float fade = smoothstep(0.0, 0.05, along) * (1.0 - smoothstep(0.55, 1.0, along));
	ALBEDO = col.rgb * power * pow(facing, 2.0) * bands * fade * core;
}
"""
	for spec in [[0.5, 2.6, 0.55], [0.18, 0.9, 1.6]]:
		var m := ShaderMaterial.new(); m.shader = sh; m.set_shader_parameter("core", spec[2])
		fx.beam_mats.append(m)
		var cm := CylinderMesh.new(); cm.bottom_radius = spec[0]; cm.top_radius = spec[1]; cm.height = 50.0; cm.radial_segments = 16; cm.rings = 1
		cm.cap_top = false; cm.cap_bottom = false
		var mi := MeshInstance3D.new(); mi.mesh = cm; mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.rotation.x = PI / 2; mi.position.z = 1.2 + 25.0
		beam.add_child(mi)
	var rm := StandardMaterial3D.new(); rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD; rm.albedo_color = Color(0.3, 0.9, 1.0)
	rm.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in 5:
		var tor := TorusMesh.new(); tor.inner_radius = 0.92; tor.outer_radius = 1.0; tor.rings = 24; tor.ring_segments = 6
		var mi := MeshInstance3D.new(); mi.mesh = tor; mi.material_override = rm; mi.rotation.x = PI / 2
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		beam.add_child(mi); fx.beam_rings.append(mi)
	fx.beam = beam

# ================================================================= story and debug
static func _story(L: Node3D) -> void:
	# a fight on the relay pylon between the gallery and the dish
	var at := -1
	for i in L.zones.size():
		if L.zones[i].id == "mast": at = i
	if at < 0: return
	L.zones[at]["skip_to"] = true
	L.zones.insert(at, { id = "mast_pylon", name = "RELAY PYLON", rect = P1, y = P1_Y, y_range = 3.0, skippable = true,
		objective = "Take the catwalk and the cable east to the relay pylon",
		enter_lines = ["sky_mast_pylon_1", "sky_mast_pylon_2"], clear_lines = ["sky_mast_pylon_clear_1"],
		waves = [{ roller = 2 }, { hornet = 2 }] })
	L.zones[at + 1]["guards"] = [{ rect = L.islands.dish_deck, y = 20.0, hornet = 2 }, { rect = P2, y = P2_Y, hornet = 1 }]

static func _debug(L: Node3D) -> void:
	var spots := {
		mast_catwalk = [Vector3(21.8, C1_Y + 0.1, -29.7), PI / 2],
		mast_pylon = [Vector3(40.0, P1_Y + 0.1, -49.0), PI * 0.75],
		mast_top = [Vector3(43.0, P2_Y + 0.1, -50.5), -1.03],
		mast_view = [Vector3(30.0, 3.1, -31.0), -PI * 0.75],
	}
	for k in spots: L.debug_spots[k] = spots[k]
	# the level resets debug_spots after the areas are built, so apply --at for these spots here
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--at=") and spots.has(a.substr(5)):
			L.start_pos = spots[a.substr(5)][0]; L.start_yaw = spots[a.substr(5)][1]
