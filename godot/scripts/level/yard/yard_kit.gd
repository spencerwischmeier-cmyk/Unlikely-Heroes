extends RefCounted
## Building blocks for Foreman Grudd's Crane Yard (static helpers used by scripts/level/areas/yard.gd).
## Meshes are shared through a small cache so the many girders, bars and stripes stay cheap to draw.

const M := preload("res://scripts/mats.gd")

static var _mats := {}
static var _meshes := {}
static var _aabbs := {}

# ---------------------------------------------------------------- materials
static func mat(key: String) -> Material:
	if _mats.has(key): return _mats[key]
	var m: Material
	match key:
		"steel": m = M.metal(Color(0.27, 0.29, 0.33), true)
		"dark": m = M.metal(Color(0.15, 0.16, 0.19), true)
		"yellow": m = M.paint(Color(0.95, 0.68, 0.12), true)
		"yellow_obj": m = M.paint(Color(0.95, 0.68, 0.12))
		"red": m = M.paint(Color(0.78, 0.2, 0.16), true)
		"cream": m = M.paint(Color(0.9, 0.86, 0.76), true)
		"rust": m = M.worn("paint", Color(0.62, 0.38, 0.24), 0.2, 0.5, 0.75, 0.0)
		"deck": m = M.worn("deck", Color(0.78, 0.74, 0.68), 0.14, 0.45, 0.6, 0.0)
		"hazard": m = M.hazard()
		"rubber": m = M.rubber()
		"chrome": m = M.chrome()
		"brass": m = M.brass(true)
		"glow_red": m = M.glow(Color(1, 0.18, 0.12), 5.0)
		"glow_amber": m = M.glow(Color(1, 0.62, 0.15), 4.0)
		"glow_white": m = M.glow(Color(1, 0.93, 0.78), 6.0)
		"glow_molten": m = M.glow(Color(1, 0.42, 0.08), 7.0)
		"glow_hot": m = M.glow(Color(1, 0.75, 0.3), 9.0)
		"glow_green": m = M.glow(Color(0.4, 1, 0.45), 4.0)
		"glow_cyan": m = M.glow(Color(0.25, 0.94, 1.0), 4.0)
		"cable": m = M.std(Color(0.08, 0.08, 0.09), 0.2, 0.7)
		"glass": m = M.glass(Color(1, 0.8, 0.5))
		_: m = M.std(Color.MAGENTA)
	_mats[key] = m
	return m

static func box_mesh(size: Vector3) -> BoxMesh:
	var k := "b%s" % size
	if not _meshes.has(k):
		var b := BoxMesh.new(); b.size = size; _meshes[k] = b
	return _meshes[k]

static func cyl_mesh(rt: float, rb: float, h: float, sides := 12) -> CylinderMesh:
	var k := "c%s_%s_%s_%d" % [rt, rb, h, sides]
	if not _meshes.has(k):
		var c := CylinderMesh.new(); c.top_radius = rt; c.bottom_radius = rb; c.height = h; c.radial_segments = sides
		c.rings = 1; _meshes[k] = c
	return _meshes[k]

# ---------------------------------------------------------------- primitives
static func part(parent: Node, mesh: Mesh, m: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new(); mi.mesh = mesh; mi.material_override = m
	mi.position = pos; mi.rotation = rot
	parent.add_child(mi)
	return mi

static func bx(parent: Node, pos: Vector3, size: Vector3, m: String, collide := false, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := part(parent, box_mesh(size), mat(m), pos, rot)
	if collide: add_collider(mi, size)
	return mi

static func cy(parent: Node, pos: Vector3, r: float, h: float, m: String, rot := Vector3.ZERO, sides := 12, r_bot := -1.0) -> MeshInstance3D:
	return part(parent, cyl_mesh(r, r if r_bot < 0 else r_bot, h, sides), mat(m), pos, rot)

static func add_collider(host: Node3D, size: Vector3, offset := Vector3.ZERO) -> StaticBody3D:
	var sb := StaticBody3D.new(); var cs := CollisionShape3D.new(); var sh := BoxShape3D.new()
	sh.size = size; cs.shape = sh; cs.position = offset; sb.add_child(cs); host.add_child(sb)
	return sb

static func node(parent: Node, pos: Vector3, yaw := 0.0, name_ := "") -> Node3D:
	var n := Node3D.new(); n.position = pos; n.rotation.y = yaw
	if name_ != "": n.name = name_
	parent.add_child(n)
	return n

static func omni(parent: Node, pos: Vector3, c: Color, energy := 2.0, rng := 9.0) -> OmniLight3D:
	var l := OmniLight3D.new(); l.light_color = c; l.light_energy = energy; l.omni_range = minf(rng, 12.0)
	l.shadow_enabled = false; l.position = pos; parent.add_child(l)
	return l

## A beam between two points (any direction), square section.
static func beam(parent: Node, a: Vector3, b: Vector3, w: float, m: String) -> MeshInstance3D:
	var d := b - a
	var mi := part(parent, box_mesh(Vector3(w, w, d.length())), mat(m), (a + b) * 0.5)
	if d.length() > 0.001:
		mi.look_at_from_position((a + b) * 0.5, b, Vector3.UP if absf(d.normalized().y) < 0.99 else Vector3.RIGHT)
	return mi

# ---------------------------------------------------------------- models
static func _load(path: String) -> Node3D:
	if not ResourceLoader.exists(path): return null
	var n: Node3D = load(path).instantiate()
	return n

static func _aabb(path: String, n: Node3D) -> AABB:
	if _aabbs.has(path): return _aabbs[path]
	var ab := AABB(); var first := true
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		var t := Transform3D(); var p: Node = mi
		while p != n and p is Node3D:
			t = (p as Node3D).transform * t; p = p.get_parent()
		var a := t * mi.get_aabb()
		ab = a if first else ab.merge(a); first = false
	_aabbs[path] = ab
	return ab

## Place a glb (res://models/yard/<name>.glb, or "docks/<name>") with its base centre at pos, `height` tall.
static func model(parent: Node3D, name_: String, pos: Vector3, yaw := 0.0, height := 1.0, collide := false, shrink := 0.8) -> Node3D:
	var path := ("res://models/" + name_ + ".glb") if name_.contains("/") else ("res://models/yard/" + name_ + ".glb")
	var n := _load(path)
	if n == null: return null
	var ab := _aabb(path, n)
	var s := height / maxf(ab.size.y, 0.001)
	var holder := Node3D.new(); holder.name = "Y_" + name_.get_file()
	parent.add_child(holder)
	holder.position = pos; holder.rotation.y = yaw
	holder.add_child(n)
	n.scale = Vector3.ONE * s
	n.position = -Vector3(ab.get_center().x, ab.position.y, ab.get_center().z) * s
	if collide:
		add_collider(holder, Vector3(ab.size.x * s * shrink, ab.size.y * s, ab.size.z * s * shrink), Vector3(0, ab.size.y * s / 2, 0))
	return holder

# ---------------------------------------------------------------- set pieces
## Many boxes with one material as a single MultiMesh (girders and towers are built from hundreds of beams).
static func _mm(parent: Node, m: String, tfs: Array) -> MultiMeshInstance3D:
	var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D; mm.mesh = box_mesh(Vector3.ONE)
	mm.instance_count = tfs.size()
	for i in tfs.size(): mm.set_instance_transform(i, tfs[i])
	var mi := MultiMeshInstance3D.new(); mi.multimesh = mm; mi.material_override = mat(m)
	parent.add_child(mi)
	return mi

static func _beam_tf(a: Vector3, b: Vector3, w: float) -> Transform3D:
	var d := b - a
	var up := Vector3.UP if absf(d.normalized().y) < 0.99 else Vector3.RIGHT
	return Transform3D(Basis.looking_at(d, up) * Basis.from_scale(Vector3(w, w, d.length())), (a + b) * 0.5)

static func _box_tf(pos: Vector3, size: Vector3) -> Transform3D:
	return Transform3D(Basis.from_scale(size), pos)

## A lattice tower (square, 4 legs with X bracing) from pos up to pos.y + h.
static func lattice(parent: Node, pos: Vector3, w: float, h: float, m := "yellow", collide := true) -> Node3D:
	var n := node(parent, pos)
	var hw := w * 0.5
	var main := []; var web := []
	for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		main.append(_box_tf(Vector3(c.x * hw, h * 0.5, c.y * hw), Vector3(0.28, h, 0.28)))
	var steps := maxi(1, roundi(h / (w * 1.2)))
	var sh := h / steps
	for i in steps:
		var y0 := i * sh
		for side in 4:
			var a := Vector2(-1, -1).rotated(side * PI / 2) * hw
			var b := Vector2(1, -1).rotated(side * PI / 2) * hw
			web.append(_beam_tf(Vector3(a.x, y0, a.y), Vector3(b.x, y0 + sh, b.y), 0.12))
			main.append(_box_tf(Vector3((a.x + b.x) * 0.5, y0 + sh, (a.y + b.y) * 0.5), Vector3(absf(b.x - a.x) + 0.2, 0.2, absf(b.y - a.y) + 0.2)))
	_mm(n, m, main); _mm(n, "steel", web)
	if collide: add_collider(n, Vector3(w + 0.2, h, w + 0.2), Vector3(0, h * 0.5, 0))
	return n

## A long box-truss girder from a to b (horizontal), height gh: top/bottom chords and zigzag web.
static func girder(parent: Node, a: Vector3, b: Vector3, gh := 1.0, m := "yellow") -> Node3D:
	var n := node(parent, Vector3.ZERO)
	var d := b - a; var L := d.length(); var dir := d / L
	var side := dir.cross(Vector3.UP).normalized() * 0.45
	var main := []; var web := []
	for s in [-1.0, 1.0]:
		main.append(_beam_tf(a + side * s, b + side * s, 0.24))
		main.append(_beam_tf(a + side * s + Vector3(0, gh, 0), b + side * s + Vector3(0, gh, 0), 0.24))
		var k := maxi(2, roundi(L / gh))
		for i in k:
			var p0: Vector3 = a + dir * (L * i / k) + side * s
			var p1: Vector3 = a + dir * (L * (i + 1) / k) + side * s
			if i % 2 == 0: web.append(_beam_tf(p0, p1 + Vector3(0, gh, 0), 0.1))
			else: web.append(_beam_tf(p0 + Vector3(0, gh, 0), p1, 0.1))
			if i % 3 == 0: web.append(_beam_tf(p0 + Vector3(0, gh, 0), p0 + Vector3(0, gh, 0) - side * s * 2.0, 0.1))
	_mm(n, m, main); _mm(n, "steel", web)
	return n

## Hazard stripe band on the floor (thin, no collision).
static func stripe(parent: Node, pos: Vector3, size: Vector2, yaw := 0.0) -> void:
	bx(parent, pos + Vector3(0, 0.012, 0), Vector3(size.x, 0.025, size.y), "hazard", false, Vector3(0, yaw, 0))

## A cartoon-industrial work light: pole with a cage lamp head (warm), small light without shadows.
static func work_light(parent: Node, pos: Vector3, yaw := 0.0, c := Color(1, 0.85, 0.6), h := 4.2) -> Node3D:
	var n := node(parent, pos, yaw)
	cy(n, Vector3(0, h * 0.5, 0), 0.09, h, "dark")
	bx(n, Vector3(0, 0.1, 0), Vector3(0.6, 0.2, 0.6), "yellow")
	bx(n, Vector3(0, h, 0.35), Vector3(0.12, 0.12, 0.8), "dark")
	var head := cy(n, Vector3(0, h - 0.1, 0.7), 0.32, 0.4, "yellow_obj", Vector3(-1.1, 0, 0), 12, 0.22)
	head.name = "head"
	cy(n, Vector3(0, h - 0.27, 0.82), 0.25, 0.05, "glow_white", Vector3(-1.1, 0, 0))
	omni(n, Vector3(0, h - 0.9, 1.4), c, 2.2, 10.0)
	return n

## A propaganda poster board on two legs. `text` is the slogan, `img` an optional texture path.
static func poster(parent: Node, pos: Vector3, yaw: float, text: String, img := "", size := Vector2(3.2, 2.2), sub := "", lit := true) -> Node3D:
	var n := node(parent, pos, yaw)
	var top := 1.0 + size.y
	for sx in [-1, 1]:
		bx(n, Vector3(sx * (size.x * 0.5 - 0.2), top * 0.5, -0.12), Vector3(0.16, top, 0.16), "dark")
	bx(n, Vector3(0, 1.0 + size.y * 0.5, -0.06), Vector3(size.x + 0.24, size.y + 0.24, 0.1), "dark", true)
	var face := MeshInstance3D.new(); var q := QuadMesh.new(); q.size = size; face.mesh = q
	var fm := StandardMaterial3D.new(); fm.roughness = 0.8
	if img != "" and ResourceLoader.exists(img):
		fm.albedo_texture = load(img)
	else:
		fm.albedo_color = Color(0.85, 0.2, 0.15)
	face.material_override = fm; face.position = Vector3(0, 1.0 + size.y * 0.5, 0.0); n.add_child(face)
	var l := Label3D.new(); l.text = text; l.font_size = 72; l.pixel_size = size.x / 1700.0 * 1.3
	l.outline_size = 14; l.modulate = Color(1, 0.95, 0.82); l.outline_modulate = Color(0.12, 0.08, 0.06)
	l.width = 1200; l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.position = Vector3(0, 1.0 + size.y * (0.2 if img != "" else 0.5), 0.02)
	l.double_sided = false; n.add_child(l)
	if sub != "":
		var s2: Label3D = l.duplicate(); s2.text = sub; s2.font_size = 40; s2.modulate = Color(1, 0.8, 0.3)
		s2.position = Vector3(0, 1.0 + size.y * 0.07, 0.02); n.add_child(s2)
	if lit:
		bx(n, Vector3(0, top + 0.3, 0.4), Vector3(size.x * 0.6, 0.1, 0.1), "dark")
		bx(n, Vector3(0, top + 0.22, 0.42), Vector3(size.x * 0.55, 0.06, 0.12), "glow_white")
	return n

## A propaganda loudspeaker pole: four horns and a red beacon. Returns the pole; "beacon" child spins.
static func loudspeaker(parent: Node, pos: Vector3, yaw := 0.0, h := 5.5) -> Node3D:
	var n := node(parent, pos, yaw, "loudspeaker")
	cy(n, Vector3(0, h * 0.5, 0), 0.12, h, "dark", Vector3.ZERO, 10, 0.16)
	bx(n, Vector3(0, 0.15, 0), Vector3(0.8, 0.3, 0.8), "yellow")
	bx(n, Vector3(0, h - 0.2, 0), Vector3(0.6, 0.5, 0.6), "yellow")
	for i in 4:
		var horn := node(n, Vector3(0, h - 0.25 - (i % 2) * 0.55, 0), i * PI / 2 + PI / 4)
		cy(horn, Vector3(0, 0, 0.55), 0.42, 0.9, "yellow_obj", Vector3(PI / 2, 0, 0), 12, 0.1)
		cy(horn, Vector3(0, 0, 1.0), 0.36, 0.02, "dark", Vector3(PI / 2, 0, 0), 12)
	var beacon := node(n, Vector3(0, h + 0.2, 0), 0.0, "beacon")
	cy(beacon, Vector3.ZERO, 0.18, 0.35, "glow_red", Vector3.ZERO, 10)
	bx(beacon, Vector3(0.13, 0, 0), Vector3(0.1, 0.3, 0.3), "chrome")
	omni(n, Vector3(0, h + 0.3, 0), Color(1, 0.2, 0.12), 1.6, 7.0)
	return n

## A cargo container (box collider, skinned with the docks container model).
static func container(L: Node3D, pos: Vector3, along_x: bool, tint: Color, h := 2.4) -> MeshInstance3D:
	var size := Vector3(5.0, h, 2.4) if along_x else Vector3(2.4, h, 5.0)
	var b: MeshInstance3D = L.box(pos + Vector3(0, h * 0.5, 0), size, M.paint(tint))
	if ClassDB.class_exists("Node") and ResourceLoader.exists("res://models/docks/container.glb"):
		DocksDressing.skin_box(b, "container", tint)
	return b

## Smoke rising from a stack (soft particles, no shadows).
static func smoke(parent: Node3D, pos: Vector3, scale := 1.0, dark := false) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var q := QuadMesh.new(); q.size = Vector2(1.4, 1.4) * scale; p.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES; m.vertex_color_use_as_albedo = true
	var g := GradientTexture2D.new(); g.fill = GradientTexture2D.FILL_RADIAL; g.fill_from = Vector2(0.5, 0.5); g.fill_to = Vector2(1, 0.5)
	var gr := Gradient.new(); gr.set_color(0, Color(1, 1, 1, 0.6)); gr.set_color(1, Color(1, 1, 1, 0)); g.gradient = gr
	m.albedo_texture = g; p.material_override = m
	p.amount = 14; p.lifetime = 5.0; p.direction = Vector3(0, 1, 0); p.spread = 10
	p.initial_velocity_min = 1.5 * scale; p.initial_velocity_max = 2.5 * scale; p.gravity = Vector3(0.5, 0.15, 0)
	p.scale_amount_min = 0.9; p.scale_amount_max = 1.6
	var c := Curve.new(); c.add_point(Vector2(0, 0.5)); c.add_point(Vector2(1, 3.0)); p.scale_amount_curve = c
	var ramp := Gradient.new()
	if dark:
		ramp.set_color(0, Color(0.32, 0.29, 0.28, 0.75)); ramp.set_color(1, Color(0.6, 0.55, 0.52, 0))
	else:
		ramp.set_color(0, Color(1, 0.92, 0.82, 0.6)); ramp.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = ramp
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p); p.position = pos
	return p

## Glowing sparks (welding, grinding, molten splashes). Emitting is toggled by the yard's life node.
static func sparks(parent: Node3D, pos: Vector3, color := Color(1, 0.7, 0.25), amount := 24, speed := 4.0) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var q := QuadMesh.new(); q.size = Vector2(0.06, 0.06); p.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true; m.albedo_color = Color(1, 1, 1)
	m.emission_enabled = true; m.emission = color; m.emission_energy_multiplier = 6.0
	p.material_override = m
	p.amount = amount; p.lifetime = 0.7; p.explosiveness = 0.15; p.direction = Vector3(0, 1, 0); p.spread = 70
	p.initial_velocity_min = speed * 0.5; p.initial_velocity_max = speed; p.gravity = Vector3(0, -12, 0)
	p.scale_amount_min = 0.6; p.scale_amount_max = 1.4
	var ramp := Gradient.new(); ramp.set_color(0, Color(1, 0.95, 0.7)); ramp.set_color(1, Color(1, 0.35, 0.05, 0.0)); p.color_ramp = ramp
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p); p.position = pos
	return p

## A hanging cloth banner (double sided). Returns the pivot at its top edge (sway it about x).
static func banner(parent: Node, top: Vector3, yaw: float, size := Vector2(2.0, 5.0), tex := "res://textures/yard/banner_g.png") -> Node3D:
	var n := node(parent, top, yaw)
	var q := QuadMesh.new(); q.size = size
	var mi := MeshInstance3D.new(); mi.mesh = q; mi.position = Vector3(0, -size.y * 0.5, 0)
	var m := M.cloth(Color.WHITE)
	if ResourceLoader.exists(tex): m.albedo_texture = load(tex)
	m.uv1_triplanar = false; m.uv1_scale = Vector3.ONE
	mi.material_override = m; n.add_child(mi)
	bx(n, Vector3(0, 0.05, 0), Vector3(size.x + 0.3, 0.12, 0.12), "dark")
	return n
