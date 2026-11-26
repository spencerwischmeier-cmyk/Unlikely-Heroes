extends RefCounted
## Procedural garden pieces for the Roof Gardens (flowers, hedges, trees, lawns, water, glass domes, hives).
## Small repeated things (flower heads, leaf blobs, petals, ribs) are batched into MultiMeshes: call add_*()
## while building, then flush() once at the end. Everything here is visual unless a function says it collides.

const M := preload("res://scripts/mats.gd")
const DIR := "res://models/gardens/"

var L: Node3D
var root: Node3D
var rng := RandomNumberGenerator.new()
var _batches := {}          # key -> { mesh, mat, xf: Array[Transform3D], col: Array[Color], shadow }
var _aabbs := {}

var foliage_mat: ShaderMaterial
var flower_mat: StandardMaterial3D
var soil_mat: StandardMaterial3D
var bark_mat: StandardMaterial3D
var plank_mat: StandardMaterial3D
var stone_mat: StandardMaterial3D
var brass_mat: Material
var frame_mat: Material
var glass_mat: StandardMaterial3D
var water_mat: ShaderMaterial
var fall_mat: ShaderMaterial
var lawn_mat: ShaderMaterial
var honey_glow: StandardMaterial3D

var blob_mesh: SphereMesh
var petal_mesh: ArrayMesh
var dot_mesh: SphereMesh
var box_mesh: BoxMesh
var leaf_mesh: ArrayMesh

const FLOWER_COLS := [Color(1.0, 0.35, 0.55), Color(1.0, 0.82, 0.2), Color(0.62, 0.45, 1.0), Color(1.0, 0.55, 0.2),
	Color(1.0, 0.95, 0.92), Color(0.35, 0.7, 1.0), Color(1.0, 0.3, 0.3), Color(0.95, 0.5, 0.95)]

func _init(level: Node3D) -> void:
	L = level
	rng.seed = 8808
	root = Node3D.new(); root.name = "RoofGardens"; L.add_child(root)
	foliage_mat = ShaderMaterial.new(); foliage_mat.shader = _foliage_shader()
	flower_mat = StandardMaterial3D.new(); flower_mat.vertex_color_use_as_albedo = true; flower_mat.roughness = 0.6
	flower_mat.rim_enabled = true; flower_mat.rim = 0.3; flower_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	flower_mat.emission_enabled = true; flower_mat.emission = Color(0.12, 0.08, 0.1); flower_mat.emission_energy_multiplier = 1.0
	soil_mat = M.std(Color(0.3, 0.2, 0.13), 0.0, 1.0)
	bark_mat = M.std(Color(0.42, 0.29, 0.2), 0.0, 0.9); bark_mat.rim_enabled = true; bark_mat.rim = 0.2
	plank_mat = M.wood(Color(0.95, 0.78, 0.62))
	stone_mat = M.std(Color(0.62, 0.58, 0.52), 0.0, 0.9)
	brass_mat = M.brass()
	frame_mat = M.paint(Color(0.16, 0.34, 0.27))
	glass_mat = M.glass(Color(0.7, 0.95, 0.92))
	glass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	water_mat = ShaderMaterial.new(); water_mat.shader = _water_shader()
	fall_mat = ShaderMaterial.new(); fall_mat.shader = _fall_shader()
	lawn_mat = ShaderMaterial.new(); lawn_mat.shader = _lawn_shader()
	honey_glow = M.glow(Color(1.0, 0.62, 0.12), 3.5)
	blob_mesh = SphereMesh.new(); blob_mesh.radius = 1.0; blob_mesh.height = 2.0; blob_mesh.radial_segments = 14; blob_mesh.rings = 7
	dot_mesh = SphereMesh.new(); dot_mesh.radius = 1.0; dot_mesh.height = 2.0; dot_mesh.radial_segments = 6; dot_mesh.rings = 3
	box_mesh = BoxMesh.new()
	petal_mesh = _make_flower_mesh()
	leaf_mesh = _make_leaf_mesh()

# ------------------------------------------------------------------ batching
func add_inst(key: String, mesh: Mesh, mat: Material, xf: Transform3D, col := Color.WHITE, shadow := true) -> void:
	if not _batches.has(key):
		_batches[key] = { mesh = mesh, mat = mat, xf = [], col = [], shadow = shadow }
	_batches[key].xf.append(xf); _batches[key].col.append(col)

func flush() -> void:
	for k in _batches:
		var b: Dictionary = _batches[k]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = b.mesh
		mm.instance_count = b.xf.size()
		for i in b.xf.size():
			mm.set_instance_transform(i, b.xf[i]); mm.set_instance_color(i, b.col[i])
		var mmi := MultiMeshInstance3D.new(); mmi.name = "MM_" + k
		mmi.multimesh = mm; mmi.material_override = b.mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if b.shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mmi)
	_batches.clear()

static func xf_at(pos: Vector3, scale: Vector3, yaw := 0.0, tilt := Vector3.ZERO) -> Transform3D:
	var bs := Basis.from_euler(Vector3(tilt.x, yaw, tilt.z)).scaled_local(scale)
	return Transform3D(bs, pos)

# ------------------------------------------------------------------ simple pieces
func mesh(m: Mesh, mat: Material, pos: Vector3, parent: Node = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new(); mi.mesh = m; mi.material_override = mat; mi.position = pos
	(parent if parent else root).add_child(mi)
	return mi

func solid(pos: Vector3, size: Vector3, mat: Material, parent: Node = null) -> MeshInstance3D:
	var bm := BoxMesh.new(); bm.size = size
	var mi := mesh(bm, mat, pos, parent)
	collider(mi, size)
	return mi

func collider(host: Node3D, size: Vector3, offset := Vector3.ZERO) -> void:
	var sb := StaticBody3D.new(); var cs := CollisionShape3D.new(); var sh := BoxShape3D.new()
	sh.size = size; cs.shape = sh; cs.position = offset; sb.add_child(cs); host.add_child(sb)

func cyl_collider(host: Node3D, r: float, h: float, offset := Vector3.ZERO) -> void:
	var sb := StaticBody3D.new(); var cs := CollisionShape3D.new(); var sh := CylinderShape3D.new()
	sh.radius = r; sh.height = h; cs.shape = sh; cs.position = offset; sb.add_child(cs); host.add_child(sb)

func cylm(pos: Vector3, rt: float, rb: float, h: float, mat: Material, sides := 12, parent: Node = null) -> MeshInstance3D:
	var cm := CylinderMesh.new(); cm.top_radius = rt; cm.bottom_radius = rb; cm.height = h; cm.radial_segments = sides; cm.rings = 1
	return mesh(cm, mat, pos, parent)

func light(pos: Vector3, c: Color, energy := 2.0, rng_ := 8.0) -> OmniLight3D:
	var l := OmniLight3D.new(); l.light_color = c; l.light_energy = energy; l.omni_range = rng_; l.position = pos
	l.shadow_enabled = false; root.add_child(l)
	return l

# ------------------------------------------------------------------ Meshy models
func _load(name: String) -> Node3D:
	var p := DIR + name + ".glb"
	if not ResourceLoader.exists(p): return null
	return load(p).instantiate()

func _aabb(name: String, n: Node3D) -> AABB:
	if _aabbs.has(name): return _aabbs[name]
	var ab := AABB(); var first := true
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		var t := Transform3D(); var p: Node = mi
		while p != n and p is Node3D:
			t = (p as Node3D).transform * t; p = p.get_parent()
		var a := t * mi.get_aabb()
		ab = a if first else ab.merge(a); first = false
	_aabbs[name] = ab
	return ab

## Place a Meshy model with its base centre at pos, `height` metres tall (or `width` wide along its x if
## width > 0). collide adds a box collider shrunk by `shrink` in x/z. Returns null if the model is missing.
func model(name: String, pos: Vector3, yaw := 0.0, height := 1.0, collide := false, shrink := 0.85, width := 0.0, tint := Color(1, 1, 1)) -> Node3D:
	var n := _load(name)
	if n == null: return null
	var ab := _aabb(name, n)
	var s := (width / maxf(ab.size.x, 0.001)) if width > 0.0 else (height / maxf(ab.size.y, 0.001))
	var holder := Node3D.new(); holder.name = "G_" + name
	root.add_child(holder)
	holder.position = pos; holder.rotation.y = yaw
	holder.add_child(n)
	n.scale = Vector3.ONE * s
	n.position = -Vector3(ab.get_center().x, ab.position.y, ab.get_center().z) * s
	if tint != Color(1, 1, 1):
		for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
			for i in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(i)
				if m is StandardMaterial3D:
					var c: StandardMaterial3D = m.duplicate(); c.albedo_color = tint; mi.set_surface_override_material(i, c)
	if collide:
		collider(holder, Vector3(ab.size.x * s * shrink, ab.size.y * s, ab.size.z * s * shrink), Vector3(0, ab.size.y * s / 2, 0))
	return holder

func model_size(name: String) -> Vector3:
	var n := _load(name)
	if n == null: return Vector3.ONE
	var s := _aabb(name, n).size
	n.free()
	return s

# ------------------------------------------------------------------ plants
## a soft foliage clump: several overlapping blobs around c, overall radius r
func bush(c: Vector3, r: float, col := Color(0.36, 0.72, 0.36), n := 5, squash := 0.8) -> void:
	add_inst("leaf", blob_mesh, foliage_mat, xf_at(c, Vector3(r, r * squash, r), rng.randf() * TAU), _vary(col))
	for i in n:
		var a := rng.randf() * TAU
		var d := r * rng.randf_range(0.45, 0.75)
		var rr := r * rng.randf_range(0.45, 0.7)
		var p := c + Vector3(cos(a) * d, rng.randf_range(-0.15, 0.35) * r, sin(a) * d)
		add_inst("leaf", blob_mesh, foliage_mat, xf_at(p, Vector3(rr, rr * squash, rr), rng.randf() * TAU), _vary(col))

func _vary(c: Color, amt := 0.08) -> Color:
	return Color(clampf(c.r + rng.randf_range(-amt, amt), 0, 1), clampf(c.g + rng.randf_range(-amt, amt), 0, 1), clampf(c.b + rng.randf_range(-amt, amt) * 0.5, 0, 1))

## one flower head (5 cupped petals and a dot in the middle)
func flower(p: Vector3, col: Color, size := 0.22) -> void:
	var key := col.to_html(false)
	add_inst("petal_" + key, petal_mesh, _petal_mat(col), xf_at(p, Vector3.ONE * size, rng.randf() * TAU, Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))), Color.WHITE, false)
	add_inst("dot", dot_mesh, _petal_mat(Color(1.0, 0.82, 0.2)), xf_at(p + Vector3(0, 0.03, 0), Vector3.ONE * size * 0.28), Color.WHITE, false)

var _petal_mats := {}
## one material per flower colour (instance colours are not reliable for every renderer)
func _petal_mat(col: Color) -> StandardMaterial3D:
	var key := col.to_html(false)
	if not _petal_mats.has(key):
		var m := StandardMaterial3D.new(); m.albedo_color = col; m.roughness = 0.6; m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.emission_enabled = true; m.emission = col * 0.25; m.emission_energy_multiplier = 1.0
		m.rim_enabled = true; m.rim = 0.25
		_petal_mats[key] = m
	return _petal_mats[key]

## a patch of flowers and leaves filling a rect (x0..x1, z0..z1) at height y
func flower_patch(x0: float, z0: float, x1: float, z1: float, y: float, density := 6.0, palette: Array = []) -> void:
	var pal: Array = palette if palette.size() > 0 else FLOWER_COLS
	var area := absf(x1 - x0) * absf(z1 - z0)
	var n := int(area * density)
	# leafy base
	var nb := maxi(1, int(area * 1.3))
	for i in nb:
		var p := Vector3(rng.randf_range(x0, x1), y + 0.08, rng.randf_range(z0, z1))
		var r := rng.randf_range(0.28, 0.42)
		add_inst("leaf", blob_mesh, foliage_mat, xf_at(p, Vector3(r, r * 0.6, r), rng.randf() * TAU), _vary(Color(0.3, 0.62, 0.3)))
	for i in mini(n, 30):
		var p := Vector3(rng.randf_range(x0, x1), y + 0.1, rng.randf_range(z0, z1))
		add_inst("leafy", leaf_mesh, _petal_mat(Color(0.3, 0.6, 0.28)), xf_at(p, Vector3.ONE * rng.randf_range(0.6, 1.0), rng.randf() * TAU), _vary(Color(0.32, 0.66, 0.3)), false)
	var col: Color = pal[rng.randi() % pal.size()]
	for i in n:
		if rng.randf() < 0.3: col = pal[rng.randi() % pal.size()]
		var p := Vector3(rng.randf_range(x0, x1), y + rng.randf_range(0.25, 0.5), rng.randf_range(z0, z1))
		flower(p, col, rng.randf_range(0.22, 0.34))

## a raised wooden bed (top of the soil at y0 + h) full of flowers. collide=true makes it solid.
func flower_bed(cx: float, cz: float, w: float, d: float, y0: float, h := 0.5, collide := true, density := 6.0, palette: Array = []) -> void:
	var holder := Node3D.new(); holder.position = Vector3(cx, y0, cz); root.add_child(holder)
	var t := 0.14
	for s in [[Vector3(0, h / 2, -d / 2 + t / 2), Vector3(w, h, t)], [Vector3(0, h / 2, d / 2 - t / 2), Vector3(w, h, t)],
			[Vector3(-w / 2 + t / 2, h / 2, 0), Vector3(t, h, d - 2 * t)], [Vector3(w / 2 - t / 2, h / 2, 0), Vector3(t, h, d - 2 * t)]]:
		add_inst("plank", box_mesh, plank_mat, Transform3D(Basis().scaled_local(s[1]), holder.position + s[0]))
	# brass corner caps
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			add_inst("cap", box_mesh, brass_mat, Transform3D(Basis().scaled_local(Vector3(0.2, 0.08, 0.2)), holder.position + Vector3(sx * (w / 2 - 0.07), h + 0.02, sz * (d / 2 - 0.07))))
	add_inst("soil", box_mesh, soil_mat, Transform3D(Basis().scaled_local(Vector3(w - 2 * t, 0.06, d - 2 * t)), holder.position + Vector3(0, h - 0.06, 0)), Color.WHITE, false)
	if collide: collider(holder, Vector3(w, h, d), Vector3(0, h / 2, 0))
	flower_patch(cx - w / 2 + 0.25, cz - d / 2 + 0.25, cx + w / 2 - 0.25, cz + d / 2 - 0.25, y0 + h - 0.06, density, palette)

## a clipped hedge (solid) from a to b, standing on y
func hedge(a: Vector2, b: Vector2, y: float, h := 1.1, thick := 0.9, col := Color(0.24, 0.55, 0.3)) -> void:
	var len := a.distance_to(b)
	var mid := (a + b) / 2
	var yaw := atan2(b.x - a.x, b.y - a.y)
	var holder := Node3D.new(); holder.position = Vector3(mid.x, y, mid.y); holder.rotation.y = yaw; root.add_child(holder)
	collider(holder, Vector3(thick, h, len), Vector3(0, h / 2, 0))
	var bs := Basis(Vector3.UP, yaw)
	add_inst("leafbox", box_mesh, foliage_mat, Transform3D(bs.scaled_local(Vector3(thick * 0.92, h * 0.9, len)), holder.position + Vector3(0, h * 0.45, 0)), _vary(col, 0.03))
	var n := maxi(2, int(len / 0.55))
	for i in n:
		var u := (i + 0.5) / n
		var p2 := a.lerp(b, u)
		var r := thick * rng.randf_range(0.5, 0.62)
		add_inst("leaf", blob_mesh, foliage_mat, xf_at(Vector3(p2.x, y + h - r * 0.55, p2.y), Vector3(r, r * 0.75, r), rng.randf() * TAU), _vary(col, 0.05))
		for sd in [-1, 1]:
			var off := bs * Vector3(sd * thick * 0.42, 0, 0)
			var rr := thick * 0.38
			add_inst("leaf", blob_mesh, foliage_mat, xf_at(Vector3(p2.x, y + rng.randf_range(0.3, h - 0.3), p2.y) + off, Vector3(rr * 0.6, rr, rr), rng.randf() * TAU), _vary(col, 0.05))

## a stylised tree: curvy trunk and a crown of soft blobs. Solid trunk when collide.
func tree(base: Vector3, h := 4.5, crown := 1.8, col := Color(0.34, 0.7, 0.34), collide := true) -> void:
	var lean := Vector3(rng.randf_range(-0.4, 0.4), 0, rng.randf_range(-0.4, 0.4))
	var segs := 3
	var prev := base
	for i in segs:
		var u := float(i + 1) / segs
		var p := base + Vector3(0, h * 0.62 * u, 0) + lean * sin(u * PI * 0.8)
		var seg_len := prev.distance_to(p)
		var dir := (p - prev).normalized()
		var bs := Basis(Quaternion(Vector3.UP, dir))
		var r := lerpf(0.26, 0.14, u) * (h / 4.5)
		add_inst("bark", _trunk_mesh(), bark_mat, Transform3D(bs.scaled_local(Vector3(r, seg_len, r)), (prev + p) / 2))
		prev = p
	if collide:
		var holder := Node3D.new(); holder.position = base; root.add_child(holder)
		cyl_collider(holder, 0.3 * (h / 4.5), h * 0.6, Vector3(0, h * 0.3, 0))
	bush(prev + Vector3(0, crown * 0.55, 0), crown, col, 7, 0.78)
	# a few fruit or blossoms in the crown
	for i in 5:
		var a := rng.randf() * TAU
		var p := prev + Vector3(cos(a) * crown * 0.85, crown * rng.randf_range(0.2, 0.9), sin(a) * crown * 0.85)
		add_inst("fruit", dot_mesh, _petal_mat(Color(1.0, 0.55, 0.15)), xf_at(p, Vector3.ONE * 0.13), Color.WHITE, false)

var _trunk: CylinderMesh
func _trunk_mesh() -> CylinderMesh:
	if _trunk == null:
		_trunk = CylinderMesh.new(); _trunk.top_radius = 0.85; _trunk.bottom_radius = 1.0; _trunk.height = 1.0
		_trunk.radial_segments = 8; _trunk.rings = 1
	return _trunk

## a flat lawn patch (rounded rectangle look) on the deck
func lawn(cx: float, cz: float, w: float, d: float, y: float) -> void:
	var pm := PlaneMesh.new(); pm.size = Vector2(w, d)
	var mi := mesh(pm, lawn_mat, Vector3(cx, y + 0.025, cz))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# tufts along the border so the edge is soft
	var n := int((w + d) * 1.2)
	for i in n:
		var side := rng.randi() % 4
		var p := Vector3(cx, y + 0.05, cz)
		match side:
			0: p += Vector3(rng.randf_range(-w / 2, w / 2), 0, -d / 2)
			1: p += Vector3(rng.randf_range(-w / 2, w / 2), 0, d / 2)
			2: p += Vector3(-w / 2, 0, rng.randf_range(-d / 2, d / 2))
			3: p += Vector3(w / 2, 0, rng.randf_range(-d / 2, d / 2))
		var r := rng.randf_range(0.12, 0.22)
		add_inst("leaf", blob_mesh, foliage_mat, xf_at(p, Vector3(r * 1.4, r * 0.45, r * 1.4), rng.randf() * TAU), _vary(Color(0.36, 0.68, 0.3)))

## irregular paving stones along a polyline (visual, laid on a lawn)
var _pave: CylinderMesh
func stone_path(pts: Array, y: float, width := 1.4) -> void:
	if _pave == null:
		_pave = CylinderMesh.new(); _pave.top_radius = 1.0; _pave.bottom_radius = 1.0; _pave.height = 1.0; _pave.radial_segments = 7; _pave.rings = 1
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]; var b: Vector2 = pts[i + 1]
		var n := maxi(1, int(a.distance_to(b) / 0.55))
		var side := (b - a).normalized().orthogonal()
		for k in n:
			var p := a.lerp(b, (k + 0.5) / n)
			for j in 2:
				var q := p + side * (j - 0.5) * width * 0.5 + Vector2(rng.randf_range(-0.12, 0.12), rng.randf_range(-0.12, 0.12))
				var r := rng.randf_range(0.26, 0.36)
				add_inst("pave", _pave, stone_mat, xf_at(Vector3(q.x, y + 0.04, q.y), Vector3(r, 0.06, r * rng.randf_range(0.8, 1.1)), rng.randf() * TAU), Color.WHITE, false)

# ------------------------------------------------------------------ water
## a water surface quad (flows along `flow` in world xz)
func water(cx: float, cz: float, w: float, d: float, y: float, flow := Vector2(0, 0)) -> MeshInstance3D:
	var pm := PlaneMesh.new(); pm.size = Vector2(w, d)
	var m: ShaderMaterial = water_mat
	if flow != Vector2.ZERO:
		m = water_mat.duplicate(); m.set_shader_parameter("flow", flow)
	var mi := mesh(pm, m, Vector3(cx, y, cz))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

## a stone channel with flowing water from a to b (axis aligned), rim height h above y
func channel(a: Vector2, b: Vector2, y: float, wide := 1.0, h := 0.35) -> void:
	var along_x := absf(b.x - a.x) > absf(b.y - a.y)
	var len := a.distance_to(b)
	var mid := (a + b) / 2
	var dir := (b - a).normalized()
	for sd in [-1, 1]:
		var off := Vector2(0, sd * (wide / 2 + 0.1)) if along_x else Vector2(sd * (wide / 2 + 0.1), 0)
		var size := Vector3(len, h, 0.2) if along_x else Vector3(0.2, h, len)
		add_inst("stone", box_mesh, stone_mat, Transform3D(Basis().scaled_local(size), Vector3(mid.x + off.x, y + h / 2, mid.y + off.y)))
	add_inst("stone", box_mesh, stone_mat, Transform3D(Basis().scaled_local(Vector3(len if along_x else wide, 0.1, wide if along_x else len)), Vector3(mid.x, y + 0.05, mid.y)))
	water(mid.x, mid.y, len if along_x else wide, wide if along_x else len, y + h * 0.7, dir * 0.6)

## a waterfall sheet pouring from top (centre of its lip) down `drop` metres, facing out along `out` (xz)
func waterfall(top: Vector3, out: Vector2, width := 2.0, drop := 26.0) -> void:
	var n := Node3D.new(); n.position = top; root.add_child(n)
	n.rotation.y = atan2(out.x, out.y)
	# a curved lip then a long sheet; two layers for depth
	for layer in 2:
		var qm := QuadMesh.new(); qm.size = Vector2(width * (1.0 - layer * 0.18), drop)
		var mi := mesh(qm, fall_mat, Vector3(0, -drop / 2, 0.35 + layer * 0.25), n)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.rotation.x = -0.05 - layer * 0.04
	var lip := QuadMesh.new(); lip.size = Vector2(width, 0.8)
	var lm := mesh(lip, fall_mat, Vector3(0, -0.12, 0.22), n); lm.rotation.x = -PI / 2 + 0.6
	# mist at the lip and spray drifting down
	var p := CPUParticles3D.new()
	var q := QuadMesh.new(); q.size = Vector2(0.9, 0.9); p.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES; m.vertex_color_use_as_albedo = true
	var g := GradientTexture2D.new(); g.fill = GradientTexture2D.FILL_RADIAL; g.fill_from = Vector2(0.5, 0.5); g.fill_to = Vector2(1, 0.5)
	var gr := Gradient.new(); gr.set_color(0, Color(1, 1, 1, 0.5)); gr.set_color(1, Color(1, 1, 1, 0)); g.gradient = gr
	m.albedo_texture = g; p.material_override = m
	p.amount = 14; p.lifetime = 2.2; p.direction = Vector3(0, -1, 0.4); p.spread = 20
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX; p.emission_box_extents = Vector3(width * 0.45, 0.1, 0.1)
	p.initial_velocity_min = 1.0; p.initial_velocity_max = 2.5; p.gravity = Vector3(0, -3, 0)
	p.scale_amount_min = 0.8; p.scale_amount_max = 1.8
	var ramp := Gradient.new(); ramp.set_color(0, Color(0.9, 0.97, 1, 0.6)); ramp.set_color(1, Color(1, 1, 1, 0)); p.color_ramp = ramp
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.position = Vector3(0, -1.0, 0.5)
	n.add_child(p)

## petals drifting down over an area (box of half-extents ext centred at c)
func petals(c: Vector3, ext: Vector3, amount := 24, col := Color(1.0, 0.7, 0.85)) -> void:
	var p := CPUParticles3D.new()
	var q := QuadMesh.new(); q.size = Vector2(0.09, 0.07); p.mesh = q
	var m := StandardMaterial3D.new(); m.vertex_color_use_as_albedo = true; m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.emission_enabled = true; m.emission = Color(0.25, 0.15, 0.18); m.roughness = 0.7
	p.material_override = m
	p.amount = amount; p.lifetime = 7.0; p.preprocess = 7.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX; p.emission_box_extents = ext
	p.direction = Vector3(1, -0.3, 0.4); p.spread = 40; p.initial_velocity_min = 0.3; p.initial_velocity_max = 0.8
	p.gravity = Vector3(0.15, -0.35, 0.05)
	p.angular_velocity_min = -180; p.angular_velocity_max = 180
	p.particle_flag_rotate_y = true
	var g := Gradient.new(); g.set_color(0, col); g.set_color(1, Color(1.0, 0.95, 0.75))
	p.color_initial_ramp = g
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.position = c
	p.visibility_aabb = AABB(-ext - Vector3(2, 8, 2), ext * 2 + Vector3(4, 10, 4))
	root.add_child(p)

## terracotta pots with plants (batched)
func pots(c: Vector3, n := 3, spread := 0.6) -> void:
	var terracotta := Color(0.85, 0.45, 0.28)
	for i in n:
		var p := c + Vector3(rng.randf_range(-spread, spread), 0, rng.randf_range(-spread, spread))
		var r := rng.randf_range(0.18, 0.3)
		add_inst("pot", _pot_mesh(), pot_mat, Transform3D(Basis().scaled_local(Vector3(r, r * 1.3, r)), p + Vector3(0, r * 0.65, 0)), _vary(terracotta, 0.05))
		if rng.randf() < 0.5:
			add_inst("leaf", blob_mesh, foliage_mat, xf_at(p + Vector3(0, r * 1.5, 0), Vector3(r, r * 0.9, r)), _vary(Color(0.3, 0.62, 0.3)))
			flower(p + Vector3(0, r * 2.0, 0), FLOWER_COLS[rng.randi() % FLOWER_COLS.size()], 0.18)
		else:
			add_inst("leafy", leaf_mesh, _petal_mat(Color(0.3, 0.6, 0.28)), xf_at(p + Vector3(0, r * 1.2, 0), Vector3.ONE * r * 3.0, rng.randf() * TAU), _vary(Color(0.32, 0.66, 0.3)), false)

var pot_mat: StandardMaterial3D
var _pot: CylinderMesh
func _pot_mesh() -> CylinderMesh:
	if _pot == null:
		_pot = CylinderMesh.new(); _pot.top_radius = 1.0; _pot.bottom_radius = 0.7; _pot.height = 1.0; _pot.radial_segments = 10; _pot.rings = 1
		pot_mat = M.std(Color(0.8, 0.42, 0.26), 0.0, 0.85)
	return _pot

## gardening gear the bots left lying around: watering can, rake, seed sacks, a wheelbarrow of soil
func garden_tools(base: Vector3, yaw := 0.0) -> void:
	var n := Node3D.new(); n.position = base; n.rotation.y = yaw; root.add_child(n)
	var green := M.paint(Color(0.25, 0.6, 0.45))
	# watering can
	cylm(Vector3(0, 0.2, 0), 0.18, 0.2, 0.4, green, 12, n)
	var spout := cylm(Vector3(0.28, 0.32, 0), 0.025, 0.04, 0.4, green, 6, n); spout.rotation.z = -0.9
	var rose := cylm(Vector3(0.44, 0.45, 0), 0.06, 0.03, 0.05, brass_mat, 8, n); rose.rotation.z = -0.9
	var tm := TorusMesh.new(); tm.inner_radius = 0.1; tm.outer_radius = 0.13; tm.rings = 10; tm.ring_segments = 5
	var handle := mesh(tm, green, Vector3(-0.05, 0.42, 0), n); handle.rotation.x = PI / 2
	# rake leaning on a bag of seed
	var rake := Node3D.new(); rake.position = Vector3(-0.6, 0, 0.1); rake.rotation.z = 0.35; n.add_child(rake)
	cylm(Vector3(0, 0.75, 0), 0.025, 0.025, 1.5, plank_mat, 6, rake)
	var head := mesh(box_mesh, frame_mat, Vector3(0, 1.5, 0), rake); head.scale = Vector3(0.05, 0.06, 0.4)
	for k in 5:
		var tine := mesh(box_mesh, frame_mat, Vector3(0, 1.58, -0.16 + k * 0.08), rake); tine.scale = Vector3(0.02, 0.12, 0.02)
	var sack_mat := M.cloth(Color(0.85, 0.75, 0.55))
	for k in 2:
		var sack := mesh(blob_mesh, sack_mat, Vector3(-0.95 + k * 0.05, 0.25, -0.3 + k * 0.5), n)
		sack.scale = Vector3(0.28, 0.3, 0.22); sack.rotation.y = k * 0.6
	# wheelbarrow with soil and a sapling
	var wb := Node3D.new(); wb.position = Vector3(0.6, 0, -0.9); wb.rotation.y = 0.5; n.add_child(wb)
	var tub := mesh(box_mesh, M.paint(Color(0.9, 0.45, 0.2)), Vector3(0, 0.5, 0), wb); tub.scale = Vector3(0.7, 0.35, 1.0)
	var dirt := mesh(box_mesh, soil_mat, Vector3(0, 0.66, 0), wb); dirt.scale = Vector3(0.6, 0.05, 0.9)
	var wheel := cylm(Vector3(0, 0.2, 0.6), 0.2, 0.2, 0.08, M.rubber(), 12, wb); wheel.rotation.z = PI / 2
	for sx in [-1, 1]:
		var leg := mesh(box_mesh, frame_mat, Vector3(sx * 0.28, 0.2, -0.35), wb); leg.scale = Vector3(0.05, 0.4, 0.05)
		var arm := mesh(box_mesh, frame_mat, Vector3(sx * 0.3, 0.55, -0.75), wb); arm.scale = Vector3(0.05, 0.05, 0.7)
	bush(base + Basis(Vector3.UP, yaw) * (Vector3(0.6, 0.85, -0.9)), 0.22, Color(0.35, 0.7, 0.32), 2)

## a small floating garden islet for the skyline: rock cone, grass cap, a couple of trees, a waterfall
func islet(c: Vector3, r: float) -> Node3D:
	var n := Node3D.new(); n.position = c; root.add_child(n)
	var rock := M.std(Color(0.5, 0.42, 0.36), 0.0, 0.95)
	var cone := cylm(Vector3(0, -r * 0.9, 0), r, r * 0.12, r * 1.8, rock, 9, n)
	cone.rotation.y = rng.randf() * TAU
	for k in 4:
		var a := k * TAU / 4 + rng.randf()
		var chunk := cylm(Vector3(cos(a) * r * 0.55, -r * 0.5, sin(a) * r * 0.55), r * 0.35, r * 0.05, r * 1.0, rock, 6, n)
		chunk.rotation.y = rng.randf() * TAU
	var cap := cylm(Vector3(0, 0.15, 0), r * 1.02, r, 0.4, M.leaf(Color(0.36, 0.66, 0.3)), 18, n)
	cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for k in int(r * 1.5):
		var a := rng.randf() * TAU; var d := rng.randf_range(0.0, r * 0.75)
		tree(c + Vector3(cos(a) * d, 0.3, sin(a) * d), rng.randf_range(3.0, 5.0) * r / 4.0, rng.randf_range(1.2, 1.8) * r / 4.0, _vary(Color(0.38, 0.7, 0.34)), false)
	var wa := rng.randf() * TAU
	waterfall(c + Vector3(cos(wa) * r * 0.98, 0.3, sin(wa) * r * 0.98), Vector2(cos(wa), sin(wa)), r * 0.35, r * 6.0)
	return n

# ------------------------------------------------------------------ structures
## a glass dome (radius r) with brass ribs at centre c (floor y). Solid wall ring with door gaps at the
## given yaw angles (radians, 0 = +z). Returns the holder.
func glass_dome(c: Vector3, r: float, doors: Array = [], door_w := 2.6) -> Node3D:
	var holder := Node3D.new(); holder.position = c; root.add_child(holder)
	var wall_h := 1.4
	# low brass-capped stone wall ring, then the glass hemisphere on top of it
	var sm := SphereMesh.new(); sm.radius = r; sm.height = r; sm.is_hemisphere = true; sm.radial_segments = 32; sm.rings = 10
	var dome := mesh(sm, glass_mat, Vector3(0, wall_h, 0), holder)
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var cm := CylinderMesh.new(); cm.top_radius = r; cm.bottom_radius = r; cm.height = wall_h; cm.radial_segments = 32; cm.rings = 1
	cm.cap_top = false; cm.cap_bottom = false
	var wall := mesh(cm, glass_mat, Vector3(0, wall_h / 2, 0), holder)
	wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# ribs: meridians made of short segments, and latitude rings
	var ribs := 12
	for k in ribs:
		var a := k * TAU / ribs
		var segs := 8
		for i in segs:
			var t0 := float(i) / segs * PI / 2; var t1 := float(i + 1) / segs * PI / 2
			var p0 := Vector3(sin(a) * cos(t0) * r, wall_h + sin(t0) * r, cos(a) * cos(t0) * r)
			var p1 := Vector3(sin(a) * cos(t1) * r, wall_h + sin(t1) * r, cos(a) * cos(t1) * r)
			var dir := (p1 - p0)
			var bs := Basis(Quaternion(Vector3.UP, dir.normalized()))
			add_inst("rib", box_mesh, frame_mat, Transform3D(bs.scaled_local(Vector3(0.12, dir.length() + 0.04, 0.12)), c + (p0 + p1) / 2))
		add_inst("rib", box_mesh, frame_mat, Transform3D(Basis(Vector3.UP, a).scaled_local(Vector3(0.14, wall_h, 0.14)), c + Vector3(sin(a) * r, wall_h / 2, cos(a) * r)))
	for lat in [0.0, 0.35, 0.75]:
		var rr := cos(lat) * r
		var tm := TorusMesh.new(); tm.inner_radius = rr - 0.07; tm.outer_radius = rr + 0.07; tm.rings = 40; tm.ring_segments = 6
		mesh(tm, brass_mat if lat == 0.0 else frame_mat, Vector3(0, wall_h + sin(lat) * r, 0), holder)
	# finial on top
	cylm(Vector3(0, wall_h + r + 0.3, 0), 0.08, 0.25, 0.6, brass_mat, 8, holder)
	var s := SphereMesh.new(); s.radius = 0.22; s.height = 0.44
	mesh(s, M.glow(Color(1.0, 0.8, 0.4), 4.0), Vector3(0, wall_h + r + 0.7, 0), holder)
	# stone curb and its collision ring with gaps for the doors
	var segs := 28
	for i in segs:
		var a := (i + 0.5) * TAU / segs
		var skip := false
		for d in doors:
			if absf(wrapf(a - d, -PI, PI)) < (door_w / 2) / r: skip = true
		var seg_len := TAU * r / segs + 0.05
		var p := Vector3(sin(a) * r, 0, cos(a) * r)
		var bs := Basis(Vector3.UP, a)
		add_inst("stone", box_mesh, stone_mat, Transform3D(bs.scaled_local(Vector3(seg_len, 0.3, 0.35)), c + p + Vector3(0, 0.15, 0)))
		if skip: continue
		var sb := StaticBody3D.new(); var cs := CollisionShape3D.new(); var sh := BoxShape3D.new()
		sh.size = Vector3(seg_len, wall_h + r * 0.6, 0.4); cs.shape = sh; sb.add_child(cs)
		sb.position = p + Vector3(0, (wall_h + r * 0.6) / 2, 0); sb.rotation.y = a
		holder.add_child(sb)
	# door frames
	for d in doors:
		var dp := Vector3(sin(d) * r, 0, cos(d) * r)
		var side := Vector3(cos(d), 0, -sin(d))
		for sd in [-1, 1]:
			var post := cylm(dp + side * sd * door_w / 2 + Vector3(0, 1.4, 0), 0.12, 0.15, 2.8, brass_mat, 8, holder)
			post.position += Vector3.ZERO
		var lint := BoxMesh.new(); lint.size = Vector3(door_w + 0.4, 0.25, 0.3)
		var lm := mesh(lint, frame_mat, dp + Vector3(0, 2.85, 0), holder); lm.rotation.y = d
	# a solid cap over the top so nothing walks in through the roof
	var cap := StaticBody3D.new(); var ccs := CollisionShape3D.new(); var csh := CylinderShape3D.new()
	csh.radius = r * 0.85; csh.height = 0.4; ccs.shape = csh; cap.add_child(ccs); cap.position = Vector3(0, wall_h + r * 0.75, 0)
	holder.add_child(cap)
	return holder

## an ornate garden lamp: post, a curled brass arm and a hanging lantern (one light, no shadows)
func garden_lamp(base: Vector3, yaw := 0.0, c := Color(1.0, 0.8, 0.5), with_light := true) -> void:
	var holder := Node3D.new(); holder.position = base; holder.rotation.y = yaw; root.add_child(holder)
	cylm(Vector3(0, 0.15, 0), 0.25, 0.3, 0.3, frame_mat, 8, holder)
	cylm(Vector3(0, 2.0, 0), 0.07, 0.1, 4.0, frame_mat, 8, holder)
	cylm(Vector3(0, 4.05, 0), 0.12, 0.12, 0.12, brass_mat, 8, holder)
	# arm: a few segments curving out, then a little curl
	var pts := [Vector3(0, 3.8, 0), Vector3(0.35, 4.15, 0), Vector3(0.8, 4.3, 0), Vector3(1.25, 4.2, 0), Vector3(1.45, 3.95, 0)]
	for i in pts.size() - 1:
		var d: Vector3 = pts[i + 1] - pts[i]
		var bs := Basis(Quaternion(Vector3.UP, d.normalized()))
		var mi := mesh(box_mesh, brass_mat, (pts[i] + pts[i + 1]) / 2, holder)
		mi.basis = bs.scaled_local(Vector3(0.08, d.length() + 0.05, 0.08))
	var tm := TorusMesh.new(); tm.inner_radius = 0.12; tm.outer_radius = 0.2; tm.rings = 12; tm.ring_segments = 6
	var curl := mesh(tm, brass_mat, Vector3(0.25, 3.7, 0), holder); curl.rotation.x = PI / 2
	# lantern
	cylm(Vector3(1.45, 3.75, 0), 0.05, 0.2, 0.2, frame_mat, 6, holder)
	var gl := cylm(Vector3(1.45, 3.45, 0), 0.17, 0.17, 0.42, M.glow(c, 5.0), 6, holder)
	gl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cylm(Vector3(1.45, 3.2, 0), 0.2, 0.08, 0.1, frame_mat, 6, holder)
	if with_light:
		var l := OmniLight3D.new(); l.light_color = c; l.light_energy = 2.2; l.omni_range = 8.0; l.position = Vector3(1.45, 3.3, 0)
		holder.add_child(l)
	var sb := StaticBody3D.new(); var cs := CollisionShape3D.new(); var sh := CylinderShape3D.new()
	sh.radius = 0.2; sh.height = 4.0; cs.shape = sh; cs.position = Vector3(0, 2, 0); sb.add_child(cs); holder.add_child(sb)

## a pollinator hive: stacked hexagonal boxes with glowing honey slots. Solid, top at base.y + h.
func hive(base: Vector3, r := 1.1, h := 2.2, col := Color(0.95, 0.75, 0.35)) -> Node3D:
	var holder := Node3D.new(); holder.position = base; root.add_child(holder)
	var tiers := maxi(2, int(h / 0.75))
	var th := h / tiers
	var mat := ShaderMaterial.new(); mat.shader = _comb_shader(); mat.set_shader_parameter("base", col)
	for i in tiers:
		var rr := r * (1.0 if i % 2 == 0 else 0.94)
		var c := cylm(Vector3(0, th * i + th / 2, 0), rr, rr, th - 0.05, mat, 6, holder)
		c.rotation.y = i * 0.12
		# brass band and honey-glow slots
		var tm := TorusMesh.new(); tm.inner_radius = rr - 0.03; tm.outer_radius = rr + 0.06; tm.rings = 6; tm.ring_segments = 4
		mesh(tm, brass_mat, Vector3(0, th * i + 0.03, 0), holder).rotation.y = PI / 6
		for k in 3:
			var a := k * TAU / 3 + i * 0.7
			var slot := mesh(box_mesh, honey_glow, Vector3(sin(a) * rr * 0.9, th * i + th * 0.5, cos(a) * rr * 0.9), holder)
			slot.scale = Vector3(0.36, 0.1, 0.06); slot.rotation.y = a
	# a little peaked roof cap
	var roof := cylm(Vector3(0, h + 0.2, 0), 0.05, r * 1.08, 0.4, M.paint(Color(0.85, 0.42, 0.25)), 6, holder)
	roof.rotation.y = PI / 6
	cyl_collider(holder, r, h, Vector3(0, h / 2, 0))
	return holder

## a white trellis panel with climbing vines (visual)
func trellis(a: Vector2, b: Vector2, y: float, h := 2.4) -> void:
	var len := a.distance_to(b)
	var yaw := atan2(b.x - a.x, b.y - a.y)
	var bs := Basis(Vector3.UP, yaw)
	var mid := Vector3((a.x + b.x) / 2, y, (a.y + b.y) / 2)
	var wm := M.paint(Color(0.95, 0.94, 0.9))
	var n := maxi(2, int(len / 0.6))
	for i in n + 1:
		var u := float(i) / n - 0.5
		add_inst("trellis", box_mesh, wm, Transform3D(bs.scaled_local(Vector3(0.06, h, 0.06)), mid + bs * Vector3(0, h / 2, u * len)))
	for j in 5:
		add_inst("trellis", box_mesh, wm, Transform3D(bs.scaled_local(Vector3(0.05, 0.05, len)), mid + Vector3(0, 0.3 + j * (h - 0.3) / 4, 0)))
	for i in int(len * 4):
		var u := rng.randf_range(-0.5, 0.5)
		var hh := rng.randf_range(0.2, h) * (0.6 + 0.4 * absf(sin(u * 7.0)))
		var p := mid + bs * Vector3(rng.randf_range(-0.12, 0.12), hh, u * len)
		var r := rng.randf_range(0.14, 0.26)
		add_inst("leaf", blob_mesh, foliage_mat, xf_at(p, Vector3(r, r, r)), _vary(Color(0.3, 0.62, 0.3)))
		if rng.randf() < 0.35: flower(p + Vector3(0, 0.1, 0), FLOWER_COLS[rng.randi() % FLOWER_COLS.size()], 0.16)

## hanging vines down a deck edge: strings of leaves from (x,z) at y, `len` metres long
func vines(p: Vector3, len := 2.5) -> void:
	var n := int(len / 0.22)
	var sway := rng.randf_range(-0.2, 0.2)
	for i in n:
		var u := float(i) / n
		var q := p + Vector3(sin(u * 5.0) * 0.08 + sway * u, -u * len, cos(u * 4.0) * 0.08)
		var r := lerpf(0.16, 0.08, u)
		add_inst("leaf", blob_mesh, foliage_mat, xf_at(q, Vector3(r, r * 1.3, r)), _vary(Color(0.3, 0.6, 0.3)))
		if rng.randf() < 0.12: flower(q, FLOWER_COLS[rng.randi() % FLOWER_COLS.size()], 0.12)

## Re-skin a deck built by L.island() (found by position) as a garden terrace: flagstone deck, sandstone
## coping over the hazard edging, earthy rock underneath. Gameplay geometry is untouched.
var flag_mat: ShaderMaterial
var rock_mat: StandardMaterial3D
var coping_mat: StandardMaterial3D
func reskin_island(r: Rect2, y: float) -> void:
	if flag_mat == null:
		flag_mat = ShaderMaterial.new(); flag_mat.shader = _flag_shader()
		rock_mat = M.std(Color(0.47, 0.38, 0.32), 0.0, 0.95)
		coping_mat = M.std(Color(0.86, 0.78, 0.64), 0.0, 0.8)
	var g := r.grow(0.6)
	for c in L.get_children():
		if not (c is MeshInstance3D): continue
		var mi := c as MeshInstance3D
		var p := mi.position
		if not g.has_point(Vector2(p.x, p.z)) or p.y > y + 0.1 or p.y < y - 30.0: continue
		if mi.mesh is BoxMesh:
			var sz := (mi.mesh as BoxMesh).size
			if is_equal_approx(sz.y, 0.22) and absf(p.y - (y - 0.08)) < 0.01: mi.material_override = coping_mat
			elif absf(p.y - y + sz.y / 2) < 0.01 and sz.x > 3.0 and sz.z > 3.0: mi.material_override = flag_mat
		elif mi.mesh is CylinderMesh and (mi.mesh as CylinderMesh).radial_segments == 8:
			mi.material_override = rock_mat

# ------------------------------------------------------------------ meshes and shaders
func _make_flower_mesh() -> ArrayMesh:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var petals := 5
	for k in petals:
		var a := k * TAU / petals
		var dir := Vector3(cos(a), 0, sin(a)); var side := Vector3(-sin(a), 0, cos(a))
		var p0 := Vector3(0, 0, 0)
		var p1 := dir * 0.45 + side * 0.32 + Vector3(0, 0.12, 0)
		var p2 := dir * 1.0 + Vector3(0, 0.35, 0)
		var p3 := dir * 0.45 - side * 0.32 + Vector3(0, 0.12, 0)
		for tri in [[p0, p1, p2], [p0, p2, p3]]:
			var nrm: Vector3 = (tri[1] - tri[0]).cross(tri[2] - tri[0]).normalized()
			if nrm.y < 0: nrm = -nrm
			for v in tri:
				st.set_color(Color.WHITE)
				st.set_normal(nrm.lerp(Vector3.UP, 0.5).normalized()); st.add_vertex(v)
	return st.commit()

func _make_leaf_mesh() -> ArrayMesh:
	# a small rosette of long leaves fanning out of the soil
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 5:
		var a := k * TAU / 5 + 0.3
		var dir := Vector3(cos(a), 0, sin(a)); var side := Vector3(-sin(a), 0, cos(a))
		var p0 := Vector3.ZERO
		var p1 := dir * 0.18 + side * 0.07 + Vector3(0, 0.2, 0)
		var p2 := dir * 0.38 + Vector3(0, 0.18, 0)
		var p3 := dir * 0.18 - side * 0.07 + Vector3(0, 0.2, 0)
		for tri in [[p0, p1, p2], [p0, p2, p3]]:
			for v in tri:
				st.set_color(Color(1, 1, 1)); st.set_normal(Vector3.UP); st.add_vertex(v)
	return st.commit()

static func _foliage_shader() -> Shader:
	var s := Shader.new()
	s.code = """
shader_type spatial;
render_mode cull_back;
uniform float sway = 0.06;
varying vec3 wpos;
varying vec3 tint;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float ph = wpos.x * 0.35 + wpos.z * 0.27;
	float up = clamp(VERTEX.y + 0.6, 0.0, 1.6);
	VERTEX.x += sin(TIME * 1.3 + ph) * sway * up;
	VERTEX.z += cos(TIME * 1.1 + ph * 1.3) * sway * up;
	tint = COLOR.rgb;
}
float h3(vec3 p) { return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453); }
float n3(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h3(i), h3(i + vec3(1,0,0)), f.x), mix(h3(i + vec3(0,1,0)), h3(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(h3(i + vec3(0,0,1)), h3(i + vec3(1,0,1)), f.x), mix(h3(i + vec3(0,1,1)), h3(i + vec3(1,1,1)), f.x), f.y), f.z);
}
void fragment() {
	float n = n3(wpos * 3.1) * 0.6 + n3(wpos * 7.3) * 0.4;
	vec3 wn = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	float top = clamp(wn.y * 0.5 + 0.5, 0.0, 1.0);
	vec3 c = tint * mix(0.55, 1.15, top) * mix(0.82, 1.12, n);
	c = mix(c, c * vec3(1.1, 1.15, 0.75), smoothstep(0.65, 1.0, top) * 0.5);
	ALBEDO = c;
	ROUGHNESS = 0.8;
	SPECULAR = 0.2;
	BACKLIGHT = tint * 0.35;
	RIM = 0.35;
	RIM_TINT = 0.4;
}
"""
	return s

static func _water_shader() -> Shader:
	var s := Shader.new()
	s.code = """
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque;
uniform vec2 flow = vec2(0.0, 0.0);
uniform vec3 deep : source_color = vec3(0.12, 0.45, 0.55);
uniform vec3 shallow : source_color = vec3(0.35, 0.85, 0.85);
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
float h2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n2(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h2(i), h2(i + vec2(1, 0)), f.x), mix(h2(i + vec2(0, 1)), h2(i + vec2(1, 1)), f.x), f.y); }
void fragment() {
	vec2 uv = wpos.xz * 0.9 - flow * TIME * 1.5;
	float a = n2(uv * 1.7 + TIME * 0.15);
	float b = n2(uv * 3.3 - TIME * 0.22 + 4.0);
	float r = smoothstep(0.62, 0.8, a * 0.55 + b * 0.45);
	ALBEDO = mix(deep, shallow, a * 0.6) + vec3(r) * 0.55;
	ALPHA = 0.82;
	ROUGHNESS = 0.06;
	METALLIC = 0.0;
	SPECULAR = 0.8;
	NORMAL_MAP = normalize(vec3(a - 0.5, b - 0.5, 2.2)) * 0.5 + 0.5;
	EMISSION = shallow * 0.08 + vec3(r) * 0.12;
}
"""
	return s

static func _fall_shader() -> Shader:
	var s := Shader.new()
	s.code = """
shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded, depth_draw_never;
float h2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n2(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h2(i), h2(i + vec2(1, 0)), f.x), mix(h2(i + vec2(0, 1)), h2(i + vec2(1, 1)), f.x), f.y); }
void fragment() {
	vec2 uv = UV;
	float streak = n2(vec2(uv.x * 14.0, uv.y * 2.0 - TIME * 2.4)) * 0.6 + n2(vec2(uv.x * 30.0, uv.y * 5.0 - TIME * 3.6)) * 0.4;
	float edge = smoothstep(0.0, 0.18, uv.x) * smoothstep(1.0, 0.82, uv.x);
	float fade = smoothstep(1.0, 0.35, uv.y);
	vec3 c = mix(vec3(0.5, 0.85, 0.95), vec3(1.0), smoothstep(0.45, 0.85, streak));
	ALBEDO = c;
	ALPHA = edge * fade * (0.35 + 0.55 * streak);
}
"""
	return s

static func _flag_shader() -> Shader:
	var s := Shader.new()
	s.code = """
shader_type spatial;
varying vec3 wpos;
varying vec3 wnrm;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz); }
float h2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
vec2 h22(vec2 p) { return vec2(h2(p), h2(p + 19.19)); }
float n2(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h2(i), h2(i + vec2(1, 0)), f.x), mix(h2(i + vec2(0, 1)), h2(i + vec2(1, 1)), f.x), f.y); }
void fragment() {
	vec2 uv = abs(wnrm.y) > 0.5 ? wpos.xz : vec2(wpos.x + wpos.z, wpos.y * 1.6);
	uv *= 1.25;
	// voronoi flagstones
	vec2 i = floor(uv); vec2 f = fract(uv);
	float d1 = 9.0; float d2 = 9.0; vec2 id = vec2(0.0);
	for (int y = -1; y <= 1; y++) for (int x = -1; x <= 1; x++) {
		vec2 g = vec2(float(x), float(y));
		vec2 o = h22(i + g) * 0.8 + 0.1;
		float d = length(g + o - f);
		if (d < d1) { d2 = d1; d1 = d; id = i + g; } else if (d < d2) { d2 = d; }
	}
	float edge = d2 - d1;
	float grout = 1.0 - smoothstep(0.03, 0.09, edge);
	float tone = h2(id);
	float n = n2(uv * 6.0);
	vec3 stone = mix(vec3(0.62, 0.57, 0.49), vec3(0.76, 0.7, 0.6), tone) * mix(0.88, 1.06, n);
	stone = mix(stone, vec3(0.62, 0.66, 0.5), step(0.82, tone) * 0.4);
	vec3 moss = vec3(0.3, 0.46, 0.22) * mix(0.8, 1.1, n);
	ALBEDO = mix(stone, moss, grout * 0.85);
	ROUGHNESS = mix(0.85, 1.0, grout);
	SPECULAR = 0.25;
	NORMAL_MAP = normalize(vec3((n - 0.5) * 0.3, (n2(uv * 6.0 + 3.0) - 0.5) * 0.3, 1.0) - vec3(0.0, 0.0, grout * 0.5)) * 0.5 + 0.5;
}
"""
	return s

static var _comb: Shader
static func _comb_shader() -> Shader:
	if _comb: return _comb
	_comb = Shader.new()
	_comb.code = """
shader_type spatial;
uniform vec3 base : source_color = vec3(0.95, 0.75, 0.35);
varying vec3 lpos;
void vertex() { lpos = VERTEX; }
void fragment() {
	// hexagonal comb cells wrapped round the hive (angle, height)
	vec2 p = vec2(atan(lpos.x, lpos.z) * 2.2, lpos.y * 3.2);
	vec2 r = vec2(1.0, 1.732);
	vec2 h = r * 0.5;
	vec2 a = mod(p, r) - h;
	vec2 b = mod(p - h, r) - h;
	vec2 g = dot(a, a) < dot(b, b) ? a : b;
	vec2 q = abs(g);
	float hex = max(q.x * 0.866 + q.y * 0.5, q.y);
	float rim = smoothstep(0.36, 0.43, hex);
	vec3 c = mix(base * 1.05, base * 0.55, rim);
	ALBEDO = c;
	ROUGHNESS = mix(0.45, 0.8, rim);
	SPECULAR = 0.4;
	EMISSION = base * vec3(1.0, 0.6, 0.15) * (1.0 - rim) * 0.08;
}
"""
	return _comb

static func _lawn_shader() -> Shader:
	var s := Shader.new()
	s.code = """
shader_type spatial;
render_mode blend_mix;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
float h2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n2(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h2(i), h2(i + vec2(1, 0)), f.x), mix(h2(i + vec2(0, 1)), h2(i + vec2(1, 1)), f.x), f.y); }
void fragment() {
	vec2 p = wpos.xz;
	float n = n2(p * 0.8) * 0.5 + n2(p * 2.7) * 0.3 + n2(p * 9.0) * 0.2;
	float blades = h2(floor(p * 18.0));
	vec3 c = mix(vec3(0.22, 0.5, 0.2), vec3(0.45, 0.75, 0.3), n) * mix(0.85, 1.1, blades);
	// soft rounded edge
	vec2 e = min(UV, 1.0 - UV);
	float edge = smoothstep(0.0, 0.08, min(e.x, e.y) + (n - 0.5) * 0.06);
	ALBEDO = c;
	ALPHA = edge;
	ROUGHNESS = 0.9;
	SPECULAR = 0.15;
}
"""
	return s
