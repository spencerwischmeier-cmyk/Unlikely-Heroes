extends RefCounted
## Junkyard retrofit: the Junkyard (yard, home, Scrap Heap, Hull Dock, Lookout, Sorting Works) still had
## plenty of plain primitive blocks and cylinders from before the HD scrap pass: crates, trestles, posts,
## tanks, walls, ledges. Their flat paint read bland next to the bevelled scrap and bales. This late pass
## (final coordinates, after the ground pass) finds those primitives inside the Junkyard and
##   - swaps each BoxMesh for a chamfered box of the same size, so edges catch the light like the HD pieces;
##   - gives boxes and cylinders shaders/kitbash.gdshader: chipped edges, rust streaks, seams and rivets,
##     grime and dust (planks for wooden ones), tinted from their old colour.
## Colliders are separate nodes and keep their exact shapes, so routes don't change. Glowing, see-through,
## textured-model and ground pieces are left alone. `--no-junk-retrofit` keeps the old look.

const JK := preload("res://scripts/level/junkyard/junk_kit.gd")

## The Junkyard in final coordinates (area_mood.gd's region plus the Sorting Works side).
const REGION := Rect2(-58, 80, 116, 132)
const MAX_DIM := 26.0      # floors and island slabs are the ground pass's job

## average colour of textures/<set>_albedo.png
const TEX_MEAN := { "wood": Color(0.55, 0.38, 0.23), "deck": Color(0.73, 0.74, 0.76), "paint": Color(0.93, 0.93, 0.93) }

static var _mats := {}
static var _boxes := {}

static func build(L) -> void:
	if OS.get_cmdline_user_args().has("--no-junk-retrofit"): return
	var n := 0
	for g in L.find_children("*", "MeshInstance3D", true, false):
		var mi := g as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree(): continue
		var p := mi.global_position
		if not REGION.has_point(Vector2(p.x, p.z)): continue
		var is_box := mi.mesh is BoxMesh
		var is_cyl := mi.mesh is CylinderMesh
		if not (is_box or is_cyl): continue
		var src := mi.material_override if mi.material_override else mi.mesh.surface_get_material(0)
		var sm := src as StandardMaterial3D
		if sm == null or not _plain(sm): continue
		var sc := mi.global_transform.basis.get_scale()
		var he: Vector3
		if is_box:
			var s: Vector3 = (mi.mesh as BoxMesh).size
			if maxf(s.x * sc.x, s.z * sc.z) > MAX_DIM or minf(s.x, minf(s.y, s.z)) < 0.03: continue
			he = s * 0.5
			mi.mesh = _chamfer_box(s)
		else:
			var cm := mi.mesh as CylinderMesh
			var r := maxf(cm.top_radius, cm.bottom_radius)
			if r * 2.0 * maxf(sc.x, sc.z) > MAX_DIM or cm.height < 0.03: continue
			he = Vector3(r, cm.height * 0.5, r)
			mi.set_instance_shader_parameter("is_cyl", 1.0)
		mi.material_override = _mat(sm, sm == L.get("mat_wood"))
		mi.set_instance_shader_parameter("half_ext", he)
		n += 1
	if OS.get_cmdline_user_args().has("--scatter-log"): print("[junk-retrofit] %d pieces" % n)

## plain painted/wood/metal surface (no glow, glass, decal or vertex-coloured batch material)
static func _plain(m: StandardMaterial3D) -> bool:
	if m.emission_enabled or m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED: return false
	if m.vertex_color_use_as_albedo or m.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED: return false
	# a coloured texture (hazard stripes, labels, printed art) carries the look; only the neutral tileable
	# sets take their colour from albedo_color
	if m.albedo_texture:
		var tp := m.albedo_texture.resource_path
		if not (tp.contains("paint") or tp.contains("wood") or tp.contains("deck")): return false
	var c := m.albedo_color
	return c.a > 0.99 and (c.r + c.g + c.b) > 0.06

static func _is_wood(m: StandardMaterial3D) -> bool:
	return m.albedo_texture != null and m.albedo_texture.resource_path.contains("wood")

static func _mat(src: StandardMaterial3D, wood_hint := false) -> ShaderMaterial:
	if _mats.has(src): return _mats[src]
	var m := ShaderMaterial.new(); m.shader = load("res://shaders/kitbash.gdshader")
	var wood := wood_hint or _is_wood(src)
	var c := src.albedo_color
	# the tileable sets aren't white: fold their average colour into the tint
	if src.albedo_texture:
		var tp := src.albedo_texture.resource_path
		for k in TEX_MEAN:
			if tp.contains(k): c *= TEX_MEAN[k]
	m.set_shader_parameter("base_col", Vector3(c.r, c.g, c.b))
	m.set_shader_parameter("metal", src.metallic)
	m.set_shader_parameter("wood", 1.0 if wood else 0.0)
	# bright cream/teal paint chips more, dark metal rusts more
	var lum := c.get_luminance()
	m.set_shader_parameter("rust", clampf(0.95 - lum * 0.7, 0.45, 0.85))
	m.set_shader_parameter("pit_nrm", JK._pit_tex())
	_mats[src] = m
	return m

## A box with chamfered edges and corners (bevel ~4% of its smallest side, 1.5..7 cm).
static func _chamfer_box(size: Vector3) -> ArrayMesh:
	var key := "%.3f_%.3f_%.3f" % [size.x, size.y, size.z]
	if _boxes.has(key): return _boxes[key]
	var h := size * 0.5
	var b := clampf(minf(size.x, minf(size.y, size.z)) * 0.08, 0.015, 0.07)
	b = minf(b, minf(h.x, minf(h.y, h.z)) * 0.45)
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# point on the face of axis `ax` at corner signs s
	var P := func(s: Vector3, ax: int) -> Vector3:
		var v := Vector3(s.x * (h.x - b), s.y * (h.y - b), s.z * (h.z - b))
		v[ax] = s[ax] * h[ax]
		return v
	var signs := []
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]: signs.append(Vector3(sx, sy, sz))
	# 6 faces
	for ax in 3:
		for sv in [-1.0, 1.0]:
			var q := []
			for s: Vector3 in signs:
				if s[ax] == sv: q.append(P.call(s, ax))
			var nrm := Vector3.ZERO; nrm[ax] = sv
			_quad(st, q, nrm)
	# 12 edge chamfers: between faces ax1 and ax2, along the third axis
	for pair in [[0, 1], [0, 2], [1, 2]]:
		var a1: int = pair[0]; var a2: int = pair[1]
		for s1 in [-1.0, 1.0]:
			for s2 in [-1.0, 1.0]:
				var q := []
				for s: Vector3 in signs:
					if s[a1] == s1 and s[a2] == s2:
						q.append(P.call(s, a1)); q.append(P.call(s, a2))
				var nrm := Vector3.ZERO; nrm[a1] = s1; nrm[a2] = s2
				_quad(st, q, nrm.normalized())
	# 8 corner triangles
	for s: Vector3 in signs:
		_tri(st, P.call(s, 0), P.call(s, 1), P.call(s, 2), s.normalized())
	var m := st.commit()
	_boxes[key] = m
	return m

## four coplanar points in any order -> two triangles facing `n`
static func _quad(st: SurfaceTool, pts: Array, n: Vector3) -> void:
	var c := Vector3.ZERO
	for p: Vector3 in pts: c += p
	c /= pts.size()
	# sort around the centre
	var u: Vector3 = (pts[0] - c).normalized(); var v: Vector3 = n.cross(u)
	pts.sort_custom(func(a: Vector3, bb: Vector3) -> bool: return atan2((a - c).dot(v), (a - c).dot(u)) < atan2((bb - c).dot(v), (bb - c).dot(u)))
	_tri(st, pts[0], pts[1], pts[2], n)
	_tri(st, pts[0], pts[2], pts[3], n)

static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	# Godot's front faces wind clockwise seen from outside
	if (b - a).cross(c - a).dot(n) > 0.0:
		var t := b; b = c; c = t
	for p in [a, b, c]:
		st.set_normal(n); st.set_uv(Vector2(p.x + p.z, p.y)); st.add_vertex(p)
