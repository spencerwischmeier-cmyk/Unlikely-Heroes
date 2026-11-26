extends RefCounted
## Building blocks for the Market Terrace: sandstone rock, sailcloth, lanterns, bunting, laundry, stalls,
## stairs and bridges. Small repeated decorations go through a batcher (add/flush) so the whole cliffside
## market draws as a few dozen MultiMeshes instead of thousands of nodes. Materials and meshes are shared.

const M := preload("res://scripts/mats.gd")

static var root: Node3D
static var _mats := {}
static var _meshes := {}
static var _batches := {}

const CLOTH := {
	saffron = Color(1.0, 0.66, 0.2), teal = Color(0.16, 0.6, 0.62), crimson = Color(0.84, 0.24, 0.2),
	cream = Color(0.98, 0.92, 0.78), plum = Color(0.58, 0.3, 0.6), green = Color(0.42, 0.72, 0.3), sky = Color(0.35, 0.66, 0.95),
}

static func begin(L: Node3D) -> Node3D:
	root = Node3D.new(); root.name = "MarketTerrace"; L.add_child(root)
	_batches.clear()
	return root

## Turn every batched decoration into MultiMeshInstance3D nodes (call once at the end of the build).
static func flush() -> void:
	for key in _batches:
		var b: Dictionary = _batches[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = b.colors.size() == b.xf.size() and b.colors.size() > 0
		mm.mesh = b.mesh
		mm.instance_count = b.xf.size()
		for i in b.xf.size():
			mm.set_instance_transform(i, b.xf[i])
			if mm.use_colors: mm.set_instance_color(i, b.colors[i])
		var mmi := MultiMeshInstance3D.new(); mmi.multimesh = mm; mmi.material_override = b.mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if b.shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mmi)
	_batches.clear()

static func add(mesh: Mesh, mat: Material, xf: Transform3D, shadow := true, color = null) -> void:
	var key := "%d_%d" % [mesh.get_instance_id(), mat.get_instance_id()]
	if not _batches.has(key): _batches[key] = { mesh = mesh, mat = mat, xf = [], colors = [], shadow = shadow }
	var b: Dictionary = _batches[key]
	b.xf.append(xf)
	if color != null: b.colors.append(color)

static func tf(pos: Vector3, size := Vector3.ONE, rot := Vector3.ZERO) -> Transform3D:
	return Transform3D(Basis.from_euler(rot) * Basis.from_scale(size), pos)

# ------------------------------------------------------------------ meshes
static func box_mesh() -> Mesh:
	if not _meshes.has("box"): var b := BoxMesh.new(); b.size = Vector3.ONE; _meshes["box"] = b
	return _meshes["box"]

static func cyl_mesh(sides := 12) -> Mesh:
	var k := "cyl%d" % sides
	if not _meshes.has(k):
		var c := CylinderMesh.new(); c.top_radius = 0.5; c.bottom_radius = 0.5; c.height = 1.0; c.radial_segments = sides; c.rings = 1
		_meshes[k] = c
	return _meshes[k]

static func sphere_mesh() -> Mesh:
	if not _meshes.has("sphere"):
		var s := SphereMesh.new(); s.radius = 0.5; s.height = 1.0; s.radial_segments = 12; s.rings = 6
		_meshes["sphere"] = s
	return _meshes["sphere"]

static func cone_mesh() -> Mesh:
	if not _meshes.has("cone"):
		var c := CylinderMesh.new(); c.top_radius = 0.0; c.bottom_radius = 0.5; c.height = 1.0; c.radial_segments = 8; c.rings = 1
		_meshes["cone"] = c
	return _meshes["cone"]

## a hanging cloth (top edge at the origin), subdivided so the flutter shader can ripple it
static func cloth_mesh() -> Mesh:
	if not _meshes.has("cloth"):
		var q := QuadMesh.new(); q.size = Vector2(1, 1); q.subdivide_width = 2; q.subdivide_depth = 3
		q.center_offset = Vector3(0, -0.5, 0)
		_meshes["cloth"] = q
	return _meshes["cloth"]

## a bunting pennant: a downward triangle hanging from its top edge
static func pennant_mesh() -> Mesh:
	if not _meshes.has("pennant"):
		var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for v in [Vector3(-0.5, 0, 0), Vector3(0.5, 0, 0), Vector3(0, -1, 0)]:
			st.set_normal(Vector3(0, 0, 1)); st.add_vertex(v)
		_meshes["pennant"] = st.commit()
	return _meshes["pennant"]

static func _hash3(p: Vector3) -> float:
	return fposmod(sin(p.dot(Vector3(12.9898, 78.233, 37.719))) * 43758.5453, 1.0)

## Low-poly jittered rock chunks (unit size, flat shaded). kind 0-2 boulders, 3 a downward spike.
static func rock_mesh(kind: int) -> Mesh:
	var key := "rock%d" % kind
	if _meshes.has(key): return _meshes[key]
	var src: PrimitiveMesh
	if kind < 3:
		var s := SphereMesh.new(); s.radial_segments = 6 + kind; s.rings = 3 + kind % 2; s.radius = 0.5; s.height = 1.0
		src = s
	else:
		var c := CylinderMesh.new(); c.top_radius = 0.5; c.bottom_radius = 0.08; c.height = 1.0; c.radial_segments = 7; c.rings = 3
		src = c
	var arr := src.get_mesh_arrays()
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	for i in v.size():
		var p := v[i]
		var h := _hash3(p * 9.7 + Vector3(kind, kind * 3, 1))
		var h2 := _hash3(p * 5.3 + Vector3(2, kind, 7))
		var r := 1.0 + (h - 0.5) * 0.4
		v[i] = Vector3(p.x * r, p.y + (h2 - 0.5) * 0.12, p.z * r)
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	for i in idx.size(): st.add_vertex(v[idx[i]])
	st.generate_normals()
	var m := st.commit()
	_meshes[key] = m
	return m

## A gear-shaped sprocket (radius ~0.3, lies in the XY plane).
static func sprocket_mesh() -> Mesh:
	if _meshes.has("sprocket"): return _meshes["sprocket"]
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var disc := CylinderMesh.new(); disc.top_radius = 0.24; disc.bottom_radius = 0.24; disc.height = 0.09; disc.radial_segments = 16; disc.rings = 1
	st.append_from(disc, 0, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3.ZERO))
	var tooth := BoxMesh.new(); tooth.size = Vector3(0.1, 0.12, 0.09)
	for i in 8:
		var a := i * TAU / 8
		st.append_from(tooth, 0, Transform3D(Basis(Vector3.FORWARD, a), Vector3(sin(a), cos(a), 0) * 0.28))
	var m := st.commit()
	_meshes["sprocket"] = m
	return m

# ------------------------------------------------------------------ materials
static func mat(n: String) -> Material:
	if _mats.has(n): return _mats[n]
	var m: Material = null
	match n:
		"rock": m = _rock_mat(Color(0.93, 0.7, 0.5), Color(0.62, 0.4, 0.3), 0.16)
		"rock_dark": m = _rock_mat(Color(0.7, 0.5, 0.4), Color(0.38, 0.27, 0.25), 0.12)
		"plaster": m = M.std(Color(0.96, 0.88, 0.74), 0.0, 0.85)
		"wood": m = M.wood(Color(1.0, 0.95, 0.9))
		"wood_dark": m = M.wood(Color(0.6, 0.48, 0.4))
		"brass": m = M.brass()
		"iron": m = M.metal(Color(0.24, 0.26, 0.29))
		"terracotta": m = M.paint(Color(0.82, 0.42, 0.28))
		"teal": m = M.paint(Color(0.2, 0.56, 0.58))
		"pave": m = M.worn("deck", Color(1.0, 0.88, 0.72), 0.14, 0.25, 0.7, 0.55)
		"rope": m = M.std(Color(0.55, 0.43, 0.31), 0.0, 0.95)
		"lantern": m = M.glow(Color(1.0, 0.6, 0.24), 3.2)
		"lantern_red": m = M.glow(Color(1.0, 0.32, 0.2), 3.0)
		"lantern_teal": m = M.glow(Color(0.3, 0.95, 0.9), 2.6)
		"cyan": m = M.glow(Color(0.25, 0.94, 1.0), 4.0)
		"leaf": m = M.leaf(Color(0.33, 0.66, 0.3))
		"leaf_dark": m = M.leaf(Color(0.22, 0.5, 0.26))
		"blossom": m = M.leaf(Color(1.0, 0.62, 0.72))
		"moss": m = M.leaf(Color(0.46, 0.7, 0.3))
		"pot": m = M.std(Color(0.8, 0.45, 0.3), 0.0, 0.8)
		"spice_red": m = M.std(Color(0.85, 0.2, 0.12), 0.0, 0.95)
		"spice_orange": m = M.std(Color(0.98, 0.55, 0.15), 0.0, 0.95)
		"spice_yellow": m = M.std(Color(1.0, 0.82, 0.2), 0.0, 0.95)
		"spice_green": m = M.std(Color(0.45, 0.62, 0.2), 0.0, 0.95)
		"flutter": m = _flutter_mat(0.07)
		"flutter_soft": m = _flutter_mat(0.025)
		"wind": m = _wind_mat()
		"wind_column": m = _column_mat()
		"glass_warm":
			var g := M.std(Color(1, 0.85, 0.55, 0.5), 0.0, 0.1); g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			g.emission_enabled = true; g.emission = Color(1, 0.7, 0.35); g.emission_energy_multiplier = 1.2; m = g
	if m == null and n.begins_with("cloth_"):
		m = M.cloth(CLOTH.get(n.substr(6), Color.WHITE))
	if m == null: m = M.std(Color.MAGENTA)
	_mats[n] = m
	return m

static func _rock_mat(hi: Color, lo: Color, scale: float) -> StandardMaterial3D:
	var n := FastNoiseLite.new(); n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH; n.frequency = 0.02; n.fractal_octaves = 4
	var g := Gradient.new(); g.set_color(0, lo); g.set_color(1, hi); g.add_point(0.6, hi.lerp(lo, 0.25))
	var alb := NoiseTexture2D.new(); alb.width = 256; alb.height = 256; alb.seamless = true; alb.noise = n; alb.color_ramp = g
	var cn := FastNoiseLite.new(); cn.noise_type = FastNoiseLite.TYPE_CELLULAR; cn.frequency = 0.035
	cn.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	var nor := NoiseTexture2D.new(); nor.width = 256; nor.height = 256; nor.seamless = true; nor.noise = cn
	nor.as_normal_map = true; nor.bump_strength = 5.0
	var m := StandardMaterial3D.new()
	m.albedo_texture = alb; m.normal_enabled = true; m.normal_texture = nor; m.normal_scale = 0.9
	m.roughness = 0.92
	m.uv1_triplanar = true; m.uv1_world_triplanar = true; m.uv1_scale = Vector3.ONE * scale; m.uv1_triplanar_sharpness = 3.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m

## Cloth that ripples in the breeze (vertex shader); colour comes from the instance / vertex colour.
static func _flutter_mat(amp: float) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_disabled;
uniform float amp = 0.07;
void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float k = clamp(-VERTEX.y * 1.4 + 0.15, 0.0, 1.0);
	float s = sin(TIME * 3.1 + w.x * 1.3 + w.z * 0.9) + 0.5 * sin(TIME * 5.3 + w.y * 2.0 + w.x);
	VERTEX.z += s * amp * k * 3.0;
	VERTEX.x += sin(TIME * 2.2 + w.z * 1.7) * amp * k;
}
void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.85;
	BACKLIGHT = COLOR.rgb * 0.45;
	RIM = 0.2;
}
"""
	var m := ShaderMaterial.new(); m.shader = sh; m.set_shader_parameter("amp", amp)
	return m

## a see-through column of rising air: bright streaks scrolling up, fading out at the top and bottom
static func _column_mat() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
void fragment() {
	float a = UV.x * 6.2831;
	float s = smoothstep(0.55, 1.0, sin(a * 7.0 + UV.y * 9.0 + TIME * 7.0)) * smoothstep(0.3, 1.0, sin(UV.y * 22.0 + TIME * 9.0 + a * 3.0) * 0.5 + 0.5);
	float fade = smoothstep(0.0, 0.25, UV.y) * smoothstep(1.0, 0.7, UV.y);
	ALBEDO = vec3(0.55, 0.95, 1.0) * (s * 0.9 + 0.12) * fade;
}
"""
	var m := ShaderMaterial.new(); m.shader = sh
	return m

static func _wind_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	var g := GradientTexture2D.new(); g.fill_from = Vector2(0.5, 0); g.fill_to = Vector2(0.5, 1)
	var gr := Gradient.new(); gr.set_color(0, Color(1, 1, 1, 0)); gr.add_point(0.5, Color(1, 1, 1, 0.8)); gr.set_color(2, Color(1, 1, 1, 0))
	g.gradient = gr; g.width = 8; g.height = 64
	m.albedo_texture = g
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

# ------------------------------------------------------------------ primitives
static func solid(pos: Vector3, size: Vector3, basis := Basis()) -> StaticBody3D:
	var sb := StaticBody3D.new(); var cs := CollisionShape3D.new(); var sh := BoxShape3D.new()
	sh.size = size; cs.shape = sh; sb.add_child(cs)
	sb.transform = Transform3D(basis, pos)
	root.add_child(sb)
	return sb

static func block(pos: Vector3, size: Vector3, m: String, collide := true, rot := Vector3.ZERO) -> void:
	add(box_mesh(), mat(m), tf(pos, size, rot))
	if collide: solid(pos, size, Basis.from_euler(rot))

static func post(pos: Vector3, h: float, r := 0.08, m := "brass") -> void:
	add(cyl_mesh(8), mat(m), tf(pos + Vector3(0, h / 2, 0), Vector3(r * 2, h, r * 2)))

static func rock(pos: Vector3, size: Vector3, yaw := 0.0, kind := -1, m := "rock") -> void:
	if kind < 0: kind = int(_hash3(pos) * 3.0) % 3
	add(rock_mesh(kind), mat(m), tf(pos, size, Vector3(0, yaw, 0)))

## a sandstone cliff face along a line: stacked, staggered slabs (strata) from y0 up to y1, `out` metres thick,
## pushed out from the line by `push` toward `side` (a unit vector on the ground plane)
static func cliff(a: Vector2, b: Vector2, y0: float, y1: float, side: Vector2, out := 0.9, push := 0.0) -> void:
	var len := a.distance_to(b)
	var dir := (b - a) / len
	var yaw := atan2(dir.x, dir.y) + PI / 2
	var layer_h := 1.1
	var y := y0
	var li := 0
	while y < y1 - 0.05:
		var h := minf(layer_h * (0.8 + _hash3(Vector3(a.x, y, b.y)) * 0.5), y1 - y)
		var n := maxi(1, ceili(len / 2.6))
		for i in n:
			var u := (i + 0.5 + (_hash3(Vector3(i, y, li)) - 0.5) * 0.3) / n
			var p := a.lerp(b, u) + side * (push + out * 0.5 * (0.6 + _hash3(Vector3(y, i, a.x)) * 0.5))
			var w := len / n * (1.25 + _hash3(Vector3(i, li, 3)) * 0.3)
			rock(Vector3(p.x, y + h / 2, p.y), Vector3(w, h * 1.15, out * (0.8 + _hash3(Vector3(li, i, 9)) * 0.5)), yaw + (_hash3(Vector3(i, li, y)) - 0.5) * 0.2)
		y += h; li += 1

## an upside-down rocky mountain under a floating shelf: centre, radii on x/z, top height and depth
static func under_rock(c: Vector2, rx: float, rz: float, top: float, depth: float, m := "rock") -> void:
	add(rock_mesh(3), mat(m), tf(Vector3(c.x, top - depth / 2, c.y), Vector3(rx * 2, depth, rz * 2), Vector3(0, _hash3(Vector3(c.x, 0, c.y)) * TAU, 0)))
	# a few smaller hanging spikes around it
	for i in 4:
		var a := i * TAU / 4 + _hash3(Vector3(c.x, i, c.y)) * 1.2
		var r := Vector2(cos(a) * rx * 0.55, sin(a) * rz * 0.55)
		var d := depth * (0.35 + _hash3(Vector3(i, c.x, 1)) * 0.25)
		add(rock_mesh(3), mat("rock_dark" if i % 2 else m), tf(Vector3(c.x + r.x, top - 0.4 - d / 2, c.y + r.y), Vector3(rx * 0.7, d, rz * 0.7), Vector3(0, a, 0)))
	# a chunky rim of boulders just under the deck edge
	var n := maxi(6, int((rx + rz) * 0.7))
	for i in n:
		var a := i * TAU / n
		rock(Vector3(c.x + cos(a) * rx * 0.92, top - 0.9, c.y + sin(a) * rz * 0.92), Vector3(3.2, 1.8, 3.2) * (0.8 + _hash3(Vector3(i, 2, c.x)) * 0.5), a)

## moss and little bushes on a rock top (decor only)
static func moss(pos: Vector3, r := 1.0) -> void:
	for i in 5:
		var a := i * 1.7 + pos.x
		var p := pos + Vector3(cos(a), 0, sin(a)) * r * (0.2 + _hash3(Vector3(i, pos.x, pos.z)) * 0.7)
		var s := r * (0.45 + _hash3(Vector3(pos.z, i, 1)) * 0.5)
		add(sphere_mesh(), mat("moss" if i % 2 else "leaf_dark"), tf(p, Vector3(s, s * 0.55, s)), false)

# ------------------------------------------------------------------ cloth, ropes and lights
## rope segments along a sagging curve from a to b; returns the sampled points
static func rope(a: Vector3, b: Vector3, sag := 0.6, segs := 8, r := 0.025) -> Array:
	var pts := []
	for i in segs + 1:
		var u := float(i) / segs
		pts.append(a.lerp(b, u) + Vector3(0, -sag * 4.0 * u * (1.0 - u), 0))
	for i in segs:
		var p: Vector3 = pts[i]; var q: Vector3 = pts[i + 1]
		var d := q - p
		var bas := Basis.looking_at(d.normalized(), Vector3.UP if absf(d.normalized().y) < 0.95 else Vector3.RIGHT) * Basis(Vector3.RIGHT, PI / 2)
		add(cyl_mesh(5), mat("rope"), Transform3D(bas * Basis.from_scale(Vector3(r * 2, d.length(), r * 2)), (p + q) / 2), false)
	return pts

## a paper lantern: glowing body with brass caps
static func lantern(pos: Vector3, s := 1.0, kind := "lantern") -> void:
	add(sphere_mesh(), mat(kind), tf(pos, Vector3(0.34, 0.42, 0.34) * s), false)
	add(cyl_mesh(8), mat("brass"), tf(pos + Vector3(0, 0.21 * s, 0), Vector3(0.18, 0.06, 0.18) * s), false)
	add(cyl_mesh(8), mat("brass"), tf(pos - Vector3(0, 0.21 * s, 0), Vector3(0.14, 0.05, 0.14) * s), false)

## a string of lanterns between two points
static func lantern_string(a: Vector3, b: Vector3, sag := 0.7, every := 1.6) -> void:
	var len := a.distance_to(b)
	var segs := maxi(4, int(len / 1.2))
	var pts := rope(a, b, sag, segs)
	var kinds := ["lantern", "lantern_red", "lantern", "lantern_teal"]
	var n := maxi(1, int(len / every))
	for i in n:
		var u := (i + 0.5) / n
		var p := a.lerp(b, u) + Vector3(0, -sag * 4.0 * u * (1.0 - u) - 0.3, 0)
		lantern(p, 0.9, kinds[i % kinds.size()])

## triangular bunting flags along a rope
static func bunting(a: Vector3, b: Vector3, sag := 0.5, cols: Array = ["saffron", "teal", "crimson", "cream"]) -> void:
	var len := a.distance_to(b)
	rope(a, b, sag, maxi(4, int(len / 1.2)), 0.018)
	var n := maxi(2, int(len / 0.55))
	var yaw := atan2(b.x - a.x, b.z - a.z) + PI / 2
	for i in n:
		var u := (i + 0.5) / n
		var p := a.lerp(b, u) + Vector3(0, -sag * 4.0 * u * (1.0 - u), 0)
		add(pennant_mesh(), mat("flutter"), tf(p, Vector3(0.36, 0.42, 1), Vector3(0, yaw, 0)), false, CLOTH[cols[i % cols.size()]])

## a laundry line: shirts, sheets and socks pegged on a rope
static func laundry(a: Vector3, b: Vector3, sag := 0.4) -> void:
	var len := a.distance_to(b)
	rope(a, b, sag, maxi(4, int(len / 1.2)), 0.018)
	var yaw := atan2(b.x - a.x, b.z - a.z) + PI / 2
	var u := 0.08
	var cols := CLOTH.values()
	var i := 0
	while u < 0.92:
		var h := _hash3(Vector3(a.x, i, b.z))
		var w := 0.35 + h * 0.8
		var hh := 0.5 + _hash3(Vector3(i, a.z, 2)) * 0.7
		var p := a.lerp(b, u) + Vector3(0, -sag * 4.0 * u * (1.0 - u), 0)
		add(cloth_mesh(), mat("flutter"), tf(p, Vector3(w, hh, 1), Vector3(0, yaw, 0)), true, (cols[int(h * 97.0) % cols.size()] as Color).lightened(0.1))
		u += (w + 0.25) / len
		i += 1

## a sailcloth shade over four corners (a, b, c, d in order), sagging in the middle, with ropes to its poles
static func sail(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, sag := 0.5, stripe := Color(0, 0, 0, 0)) -> void:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 6
	var P := func(u: float, v: float) -> Vector3:
		var p: Vector3 = a.lerp(b, u).lerp(d.lerp(c, u), v)
		return p + Vector3(0, -sag * 16.0 * u * (1.0 - u) * v * (1.0 - v), 0)
	for i in n:
		for j in n:
			var u0 := float(i) / n; var u1 := float(i + 1) / n; var v0 := float(j) / n; var v1 := float(j + 1) / n
			var colr := col if stripe.a == 0.0 or i % 2 == 0 else stripe
			for q in [[u0, v0], [u1, v0], [u1, v1], [u0, v0], [u1, v1], [u0, v1]]:
				st.set_color(colr); st.add_vertex(P.call(q[0], q[1]))
	st.generate_normals()
	var mi := MeshInstance3D.new(); mi.mesh = st.commit(); mi.material_override = mat("flutter_soft")
	root.add_child(mi)

## a hanging cluster of brass chime tubes (returns the node so it can sway)
static func chimes(pos: Vector3, s := 1.0) -> Node3D:
	var n := Node3D.new(); n.position = pos; root.add_child(n)
	var top := MeshInstance3D.new(); top.mesh = cyl_mesh(10); top.material_override = mat("wood")
	top.scale = Vector3(0.5, 0.06, 0.5) * s; n.add_child(top)
	for i in 6:
		var a := i * TAU / 6
		var t := MeshInstance3D.new(); t.mesh = cyl_mesh(6); t.material_override = mat("brass")
		var h := (0.5 + 0.12 * i) * s
		t.scale = Vector3(0.05, h, 0.05) * Vector3(s, 1, s)
		t.position = Vector3(cos(a) * 0.18 * s, -0.1 - h / 2, sin(a) * 0.18 * s)
		n.add_child(t)
	var clap := MeshInstance3D.new(); clap.mesh = sphere_mesh(); clap.material_override = mat("cloth_crimson")
	clap.scale = Vector3(0.12, 0.2, 0.02) * s; clap.position = Vector3(0, -0.9 * s, 0); n.add_child(clap)
	return n

static func light(pos: Vector3, col: Color, energy := 2.0, rng := 9.0) -> void:
	var l := OmniLight3D.new(); l.light_color = col; l.light_energy = energy; l.omni_range = minf(rng, 12.0)
	l.shadow_enabled = false; l.position = pos; root.add_child(l)

# ------------------------------------------------------------------ walkways
## stairs from a to b (points on the walking surface at the bottom and the top): visible steps over a smooth
## ramp collider, so the character glides up them
static func stairs(a: Vector3, b: Vector3, width: float, step_mat := "pave", side_mat := "rock") -> void:
	var d := b - a
	var run := Vector2(d.x, d.z).length()
	var yaw := atan2(d.x, d.z)
	var n := maxi(2, ceili(d.y / 0.3))
	var fwd := Vector3(d.x, 0, d.z).normalized()
	for i in n:
		var u := (i + 0.5) / n
		var top := a.y + d.y * (i + 0.5) / n
		var h := top - (a.y - 0.4)
		var c := a + fwd * run * u
		add(box_mesh(), mat(step_mat), tf(Vector3(c.x, a.y - 0.4 + h / 2, c.z), Vector3(width, h, run / n + 0.02), Vector3(0, yaw, 0)))
		if h > 0.6: solid(Vector3(c.x, a.y - 0.4 + (h - 0.35) / 2, c.z), Vector3(width, h - 0.35, run / n + 0.02), Basis(Vector3.UP, yaw))
		# brass nosing on each step
		add(box_mesh(), mat("brass"), tf(Vector3(c.x, top + 0.01, c.z) - fwd * (run / n * 0.5 - 0.04), Vector3(width, 0.04, 0.08), Vector3(0, yaw, 0)), false)
	ramp(a, b, width)

## an invisible sloped floor from a to b
static func ramp(a: Vector3, b: Vector3, width: float, walls := 0.0) -> void:
	var d := b - a
	var run := Vector2(d.x, d.z).length()
	var pitch := atan2(d.y, run)
	var bas := Basis(Vector3.UP, atan2(d.x, d.z)) * Basis(Vector3.RIGHT, -pitch)
	var len := d.length()
	solid((a + b) / 2 - bas.y * 0.2, Vector3(width, 0.4, len + 0.3), bas)
	if walls > 0.0:
		for s in [-1, 1]:
			solid((a + b) / 2 + bas.x * (width / 2 + 0.1) * s + Vector3(0, walls / 2, 0), Vector3(0.2, walls, len), bas)

## a plank footbridge from a to b with rope handrails on posts (walkable, with side walls)
static func bridge(a: Vector3, b: Vector3, width := 2.4) -> void:
	var d := b - a
	var len := d.length()
	var fwd := d / len
	var side := Vector3(fwd.z, 0, -fwd.x).normalized()
	var bas := Basis(Vector3.UP, atan2(d.x, d.z)) * Basis(Vector3.RIGHT, -atan2(d.y, Vector2(d.x, d.z).length()))
	var n := int(len / 0.42)
	for i in n:
		var p := a + d * ((i + 0.5) / n) - bas.y * 0.06
		var w := width * (0.94 + _hash3(Vector3(i, a.x, 1)) * 0.06)
		add(box_mesh(), mat("wood" if i % 3 else "wood_dark"), Transform3D(bas * Basis(Vector3.UP, (_hash3(Vector3(i, 2, a.z)) - 0.5) * 0.06) * Basis.from_scale(Vector3(w, 0.12, 0.36)), p))
	# stringers underneath
	for s in [-1, 1]:
		add(box_mesh(), mat("wood_dark"), Transform3D(bas * Basis.from_scale(Vector3(0.18, 0.26, len)), (a + b) / 2 + side * s * (width / 2 - 0.15) - bas.y * 0.25))
	# posts and rope rails
	var posts := maxi(2, int(len / 2.6) + 1)
	for s in [-1, 1]:
		var tops := []
		for i in posts:
			var p: Vector3 = a + d * (float(i) / (posts - 1)) + side * s * (width / 2)
			post(p - Vector3(0, 0.2, 0), 1.35, 0.07, "wood_dark")
			add(sphere_mesh(), mat("brass"), tf(p + Vector3(0, 1.17, 0), Vector3.ONE * 0.16), false)
			tops.append(p + Vector3(0, 1.05, 0))
		for i in posts - 1:
			rope(tops[i], tops[i + 1], 0.18, 4, 0.03)
			rope(tops[i] - Vector3(0, 0.45, 0), tops[i + 1] - Vector3(0, 0.45, 0), 0.12, 4, 0.02)
	ramp(a, b, width, 1.2)

## a wooden railing between two points at floor height y (solid)
static func rail_fence(a: Vector3, b: Vector3) -> void:
	var d := b - a
	var len := d.length()
	if len < 0.4: return
	var yaw := atan2(d.x, d.z)
	var n := maxi(1, roundi(len / 1.8))
	for i in n + 1:
		var p := a.lerp(b, float(i) / n)
		post(p, 1.05, 0.07, "wood_dark")
		add(sphere_mesh(), mat("brass"), tf(p + Vector3(0, 1.1, 0), Vector3.ONE * 0.14), false)
	add(box_mesh(), mat("wood"), tf((a + b) / 2 + Vector3(0, 1.0, 0), Vector3(0.12, 0.1, len), Vector3(0, yaw, 0)))
	add(box_mesh(), mat("wood_dark"), tf((a + b) / 2 + Vector3(0, 0.55, 0), Vector3(0.06, 0.06, len), Vector3(0, yaw, 0)), false)
	solid((a + b) / 2 + Vector3(0, 0.6, 0), Vector3(0.25, 1.2, len), Basis(Vector3.UP, yaw))

# ------------------------------------------------------------------ props
## place a model from res://models/<dir>/<name>.glb with its base centre at pos, `height` metres tall
static var _aabbs := {}
static func model(path: String, pos: Vector3, yaw := 0.0, height := 1.0, collide := false, shrink := 0.85) -> Node3D:
	if not ResourceLoader.exists(path): return null
	var n: Node3D = (load(path) as PackedScene).instantiate()
	var ab: AABB
	if _aabbs.has(path): ab = _aabbs[path]
	else:
		var first := true
		for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
			var t := Transform3D(); var p: Node = mi
			while p != n and p is Node3D:
				t = (p as Node3D).transform * t; p = p.get_parent()
			var a := t * mi.get_aabb()
			ab = a if first else ab.merge(a); first = false
		_aabbs[path] = ab
	var s := height / maxf(ab.size.y, 0.001)
	var holder := Node3D.new(); holder.position = pos; holder.rotation.y = yaw; root.add_child(holder)
	holder.add_child(n)
	n.scale = Vector3.ONE * s
	n.position = -Vector3(ab.get_center().x, ab.position.y, ab.get_center().z) * s
	if collide:
		var sb := StaticBody3D.new(); var cs := CollisionShape3D.new(); var sh := BoxShape3D.new()
		sh.size = Vector3(ab.size.x * s * shrink, ab.size.y * s, ab.size.z * s * shrink)
		cs.shape = sh; cs.position = Vector3(0, ab.size.y * s / 2, 0)
		sb.add_child(cs); holder.add_child(sb)
	return holder

## a sign: a wooden board with a painted label, facing +z of yaw
static func sign_board(text: String, pos: Vector3, yaw := 0.0, w := 3.0, col := Color(1, 0.9, 0.62), board := "wood_dark") -> void:
	var bas := Basis(Vector3.UP, yaw)
	var px := 0.0042
	var lines := ceili(text.length() * 64.0 * px * 0.62 / (w * 0.92))
	var h := lines * 64.0 * px * 1.15 + 0.22
	add(box_mesh(), mat(board), Transform3D(bas * Basis.from_scale(Vector3(w, h, 0.1)), pos))
	add(box_mesh(), mat("brass"), Transform3D(bas * Basis.from_scale(Vector3(w + 0.1, 0.06, 0.12)), pos + Vector3(0, h / 2 + 0.02, 0)), false)
	add(box_mesh(), mat("brass"), Transform3D(bas * Basis.from_scale(Vector3(w + 0.1, 0.06, 0.12)), pos - Vector3(0, h / 2 + 0.02, 0)), false)
	for s in [1, -1]:
		var l := Label3D.new(); l.text = text; l.font_size = 64; l.pixel_size = px
		l.modulate = col; l.outline_size = 8; l.outline_modulate = Color(0.2, 0.1, 0.05)
		l.width = w / px * 0.92; l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.position = pos + bas * Vector3(0, 0, 0.07 * s); l.rotation.y = yaw + (0.0 if s == 1 else PI)
		l.double_sided = false
		root.add_child(l)

## spice mounds in bowls on a counter (local frame xf)
static func spice_bowls(xf: Transform3D, w: float) -> void:
	var kinds := ["spice_red", "spice_orange", "spice_yellow", "spice_green"]
	var n := maxi(2, int(w / 0.6))
	for i in n:
		var x := -w / 2 + (i + 0.5) * w / n
		add(cyl_mesh(10), mat("pot"), xf * tf(Vector3(x, 0.08, 0), Vector3(0.5, 0.16, 0.5)), false)
		add(sphere_mesh(), mat(kinds[(i + int(xf.origin.x)) % 4]), xf * tf(Vector3(x, 0.18, 0), Vector3(0.44, 0.3, 0.44)), false)

## a market stall facing +z (local) at pos with a striped awning, goods, a lantern and a sign
static func stall(pos: Vector3, yaw: float, c1: String, c2: String, text: String, goods := "spice") -> void:
	var T := Transform3D(Basis(Vector3.UP, yaw), pos)
	# counter, back shelf and side posts
	add(box_mesh(), mat("wood_dark"), T * tf(Vector3(0, 0.5, 0.35), Vector3(2.8, 1.0, 0.8)))
	add(box_mesh(), mat("wood"), T * tf(Vector3(0, 1.04, 0.4), Vector3(3.0, 0.08, 1.0)))
	add(box_mesh(), mat("terracotta"), T * tf(Vector3(0, 0.5, 0.76), Vector3(2.6, 0.7, 0.04)), false)
	add(box_mesh(), mat("wood"), T * tf(Vector3(0, 1.1, -0.9), Vector3(2.8, 2.2, 0.35)))
	for sh_y in [1.0, 1.6]:
		add(box_mesh(), mat("wood_dark"), T * tf(Vector3(0, sh_y, -0.68), Vector3(2.7, 0.06, 0.4)), false)
		for i in 5:
			var jar := Vector3(-1.1 + i * 0.55, sh_y + 0.16, -0.68)
			add(cyl_mesh(8), mat(["pot", "brass", "teal", "pot", "terracotta"][(i + int(sh_y * 3)) % 5]), T * tf(jar, Vector3(0.24, 0.28 + 0.06 * (i % 2), 0.24)), false)
	for p in [Vector3(-1.45, 0, 0.85), Vector3(1.45, 0, 0.85), Vector3(-1.45, 0, -1.05), Vector3(1.45, 0, -1.05)]:
		add(cyl_mesh(8), mat("brass"), T * tf(p + Vector3(0, 1.4 if p.z > 0 else 1.55, 0), Vector3(0.1, 2.8 if p.z > 0 else 3.1, 0.1)))
	# striped awning sloping down to the front, with a scalloped valance
	for i in 6:
		var x := -1.5 + 0.25 + i * 0.5
		add(box_mesh(), mat("cloth_" + (c1 if i % 2 == 0 else c2)), T * tf(Vector3(x, 2.95, -0.1), Vector3(0.5, 0.05, 2.5), Vector3(-0.2, 0, 0)))
	for i in 8:
		add(pennant_mesh(), mat("flutter"), T * tf(Vector3(-1.5 + 0.19 + i * 0.375, 2.72, 1.15), Vector3(0.38, 0.32, 1)), false, CLOTH[c1 if i % 2 == 0 else c2])
	# goods on the counter
	if goods == "spice": spice_bowls(T * tf(Vector3(0, 1.08, 0.4)), 2.5)
	elif goods == "fruit":
		for i in 14:
			var gp := Vector3(-1.2 + (i % 7) * 0.4, 1.17 + 0.16 * (i / 7), 0.25 + 0.3 * (i / 7))
			add(sphere_mesh(), mat("spice_orange" if i % 3 else "spice_green"), T * tf(gp, Vector3.ONE * 0.28), false)
	elif goods == "cloth":
		for i in 5:
			add(cyl_mesh(10), mat("cloth_" + CLOTH.keys()[i % CLOTH.size()]), T * tf(Vector3(-1.0 + i * 0.5, 1.22, 0.4), Vector3(0.3, 1.0, 0.3), Vector3(0, 0, PI / 2)), false)
	elif goods == "gears":
		for i in 6:
			add(sprocket_mesh(), mat("brass"), T * tf(Vector3(-1.1 + i * 0.44, 1.35, 0.45), Vector3.ONE * (1.0 + (i % 3) * 0.3), Vector3(0, 0, i)), false)
	lantern((T * Vector3(0, 2.4, 0.95)), 0.8)
	# the shop sign on the awning front
	var l := Label3D.new(); l.text = text; l.font_size = 56; l.pixel_size = 0.005
	l.modulate = Color(1, 0.93, 0.7); l.outline_size = 10; l.outline_modulate = Color(0.25, 0.1, 0.05)
	l.position = T * Vector3(0, 3.35, 1.05); l.rotation.y = yaw; l.double_sided = true
	root.add_child(l)
	solid(T * Vector3(0, 0.6, -0.2), Vector3(3.0, 1.2, 1.9), Basis(Vector3.UP, yaw))

## a small round tea table with two stools
static func tea_table(pos: Vector3, yaw := 0.0) -> void:
	var T := Transform3D(Basis(Vector3.UP, yaw), pos)
	add(cyl_mesh(14), mat("wood"), T * tf(Vector3(0, 0.78, 0), Vector3(1.2, 0.08, 1.2)))
	add(cyl_mesh(8), mat("brass"), T * tf(Vector3(0, 0.4, 0), Vector3(0.12, 0.76, 0.12)))
	add(cyl_mesh(10), mat("brass"), T * tf(Vector3(0, 0.03, 0), Vector3(0.6, 0.06, 0.6)))
	add(sphere_mesh(), mat("teal"), T * tf(Vector3(0.1, 0.95, 0), Vector3(0.28, 0.24, 0.28)), false)   # teapot
	add(cyl_mesh(8), mat("teal"), T * tf(Vector3(0.28, 0.98, 0), Vector3(0.05, 0.18, 0.05), Vector3(0, 0, -0.9)), false)
	for s in [-1, 1]:
		add(cyl_mesh(8), mat("plaster"), T * tf(Vector3(-0.25 * s, 0.86, 0.3 * s), Vector3(0.12, 0.1, 0.12)), false)
		add(cyl_mesh(8), mat("wood_dark"), T * tf(Vector3(1.0 * s, 0.2, 0), Vector3(0.36, 0.4, 0.36)))
		add(sphere_mesh(), mat("cloth_crimson" if s > 0 else "cloth_saffron"), T * tf(Vector3(1.0 * s, 0.45, 0), Vector3(0.55, 0.2, 0.55)), false)
	solid(T * Vector3(0, 0.45, 0), Vector3(1.1, 0.9, 1.1))

## crates, sacks and pots in a little heap (decor with one collider)
static func goods_heap(pos: Vector3, yaw := 0.0, s := 1.0) -> void:
	var T := Transform3D(Basis(Vector3.UP, yaw), pos)
	add(box_mesh(), mat("wood"), T * tf(Vector3(0, 0.35, 0) * s, Vector3(0.8, 0.7, 0.8) * s))
	add(box_mesh(), mat("wood_dark"), T * tf(Vector3(0.75, 0.3, 0.1) * s, Vector3(0.6, 0.6, 0.7) * s, Vector3(0, 0.3, 0)))
	add(box_mesh(), mat("wood"), T * tf(Vector3(0.1, 0.95, 0.05) * s, Vector3(0.55, 0.5, 0.55) * s, Vector3(0, 0.5, 0)))
	add(sphere_mesh(), mat("cloth_cream"), T * tf(Vector3(-0.7, 0.4, 0.2) * s, Vector3(0.7, 0.85, 0.6) * s))
	add(sphere_mesh(), mat(["spice_red", "spice_yellow", "spice_orange"][int(absf(pos.x)) % 3]), T * tf(Vector3(-0.7, 0.82, 0.2) * s, Vector3(0.5, 0.2, 0.45) * s), false)
	add(cyl_mesh(10), mat("pot"), T * tf(Vector3(0.2, 0.3, 0.75) * s, Vector3(0.45, 0.6, 0.45) * s))
	solid(T * (Vector3(0, 0.5, 0.1) * s), Vector3(1.9, 1.0, 1.3) * s, Basis(Vector3.UP, yaw))

## a potted tree with a puffy canopy (blossom or green)
static func tree(pos: Vector3, h := 3.0, kind := "leaf") -> void:
	add(cyl_mesh(10), mat("pot"), tf(pos + Vector3(0, 0.35, 0), Vector3(1.0, 0.7, 1.0)))
	add(cyl_mesh(6), mat("wood_dark"), tf(pos + Vector3(0, 0.7 + h * 0.3, 0), Vector3(0.18, h * 0.6, 0.18)), false)
	for i in 5:
		var a := i * TAU / 5 + pos.x
		var r := 0.5 + _hash3(Vector3(i, pos.x, pos.z)) * 0.4
		add(sphere_mesh(), mat(kind if i % 2 == 0 else ("leaf" if kind == "blossom" else "leaf_dark")), tf(pos + Vector3(cos(a) * 0.55, 0.6 + h * 0.6 + (i % 2) * 0.3, sin(a) * 0.55), Vector3.ONE * r * 1.5), true)
	add(sphere_mesh(), mat(kind), tf(pos + Vector3(0, 0.9 + h * 0.65, 0), Vector3.ONE * 1.3))
	solid(pos + Vector3(0, 0.5, 0), Vector3(0.9, 1.0, 0.9))

## a tall mast with a pennant on top (for ropes, sails and lantern strings)
static func mast(pos: Vector3, h: float, flag := "saffron") -> Vector3:
	post(pos, h, 0.12, "wood_dark")
	add(cyl_mesh(8), mat("brass"), tf(pos + Vector3(0, 0.15, 0), Vector3(0.45, 0.3, 0.45)))
	add(sphere_mesh(), mat("brass"), tf(pos + Vector3(0, h + 0.1, 0), Vector3.ONE * 0.22), false)
	add(cloth_mesh(), mat("flutter"), tf(pos + Vector3(0.45, h - 0.05, 0), Vector3(0.9, 0.55, 1), Vector3(0, 0, PI / 2)), false, CLOTH[flag])
	solid(pos + Vector3(0, h / 2, 0), Vector3(0.3, h, 0.3))
	return pos + Vector3(0, h - 0.3, 0)

## ivy hanging down a cliff edge from a to b (at the top of the face), pushed out toward `side`
static func vines(a: Vector3, b: Vector3, side: Vector3, density := 1.2) -> void:
	var len := a.distance_to(b)
	var n := int(len * density)
	var yaw := atan2(b.x - a.x, b.z - a.z) + PI / 2
	for i in n:
		var u := (i + _hash3(Vector3(i, a.x, b.z))) / n
		var h := 0.8 + _hash3(Vector3(a.z, i, 4)) * 2.2
		var p := a.lerp(b, u) + side * 0.35
		var g := Color(0.3, 0.58, 0.24).lerp(Color(0.5, 0.75, 0.3), _hash3(Vector3(i, 7, a.x)))
		add(cloth_mesh(), mat("flutter_soft"), tf(p, Vector3(0.35 + _hash3(Vector3(i, 1, 1)) * 0.3, h, 1), Vector3(0, yaw, 0)), false, g)
		if i % 3 == 0: add(sphere_mesh(), mat("moss"), tf(p + Vector3(0, -0.05, 0), Vector3(0.7, 0.35, 0.6)), false)
