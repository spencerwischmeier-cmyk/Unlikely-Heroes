extends RefCounted
## Building blocks for Vesk's Junkyard (scripts/level/areas/junkyard.gd): scrap clutter batched into
## MultiMeshes, floor slabs, plank bridges, tarps, chains, rusty signs, string lights and the Meshy props in
## res://models/junkyard/. Everything here is static; `L` is the level node.

const M := preload("res://scripts/mats.gd")
const DIR := "res://models/junkyard/"

# scrap paint colours (vertex-tinted, so one material per piece shape)
const RUST := Color(0.62, 0.36, 0.2)
const ORANGE := Color(0.86, 0.45, 0.17)
const TEAL := Color(0.22, 0.52, 0.55)
const CREAM := Color(0.86, 0.8, 0.66)
const GUN := Color(0.32, 0.34, 0.38)
const RED := Color(0.7, 0.2, 0.15)
const YELLOW := Color(0.9, 0.7, 0.2)
const PALETTE := [RUST, RUST, ORANGE, TEAL, CREAM, GUN, GUN, RED, YELLOW]

static var _mats := {}
static var _meshes := {}
static var _aabbs := {}

static func mat(kind: String) -> Material:
	if _mats.has(kind): return _mats[kind]
	var m: StandardMaterial3D
	match kind:
		"scrap": m = M.surface("paint", Color.WHITE, 0.55, 0.62, 0.6); m.vertex_color_use_as_albedo = true
		"rubber": m = M.rubber(); m.vertex_color_use_as_albedo = false
		"wood": m = M.surface("wood", Color(0.78, 0.6, 0.42), 0.0, 0.7, 0.8)
		"plank": m = M.surface("wood", Color(0.66, 0.5, 0.36), 0.0, 0.75, 0.8, true)
		"brass": m = M.brass()
		"dark": m = M.surface("paint", Color(0.2, 0.22, 0.25), 0.8, 0.45, 0.6)
		"rust": m = M.surface("paint", Color(0.55, 0.32, 0.18), 0.5, 0.75, 0.4, true)
		"rust_obj": m = M.surface("paint", Color(0.6, 0.36, 0.2), 0.5, 0.72, 0.6)
		"chain": m = M.std(Color(0.3, 0.3, 0.32), 0.9, 0.45)
		"rope": m = M.std(Color(0.55, 0.45, 0.3), 0.0, 0.9)
		"bulb": m = M.glow(Color(1.0, 0.72, 0.38), 4.0)
		"glow_orange": m = M.glow(Color(1.0, 0.5, 0.15), 3.0)
		"glow_green": m = M.glow(Color(0.5, 1.0, 0.55), 2.5)
		"glow_cyan": m = M.glow(Color(0.3, 0.9, 1.0), 3.0)
		"window": m = M.glow(Color(1.0, 0.78, 0.4), 2.2)
		_: m = M.std(Color.MAGENTA)
	_mats[kind] = m
	return m

static func cloth(c: Color) -> Material:
	var k := "cloth_" + c.to_html()
	if not _mats.has(k): _mats[k] = M.cloth(c)
	return _mats[k]

static func paint(c: Color) -> Material:
	var k := "paint_" + c.to_html()
	if not _mats.has(k): _mats[k] = M.paint(c)
	return _mats[k]

## Unit meshes for clutter pieces (scaled per instance).
static func mesh(kind: String) -> Mesh:
	if _meshes.has(kind): return _meshes[kind]
	var m: Mesh
	match kind:
		"plate": var b := BoxMesh.new(); b.size = Vector3(1, 0.07, 1); m = b
		"beam": var b := BoxMesh.new(); b.size = Vector3(0.18, 0.18, 1); m = b
		"block": var b := BoxMesh.new(); b.size = Vector3.ONE; m = b
		"pipe": var c := CylinderMesh.new(); c.top_radius = 0.5; c.bottom_radius = 0.5; c.height = 1; c.radial_segments = 10; c.rings = 1; m = c
		"drum": var c := CylinderMesh.new(); c.top_radius = 0.36; c.bottom_radius = 0.36; c.height = 0.95; c.radial_segments = 14; c.rings = 2; m = c
		"tire": var t := TorusMesh.new(); t.inner_radius = 0.24; t.outer_radius = 0.48; t.rings = 16; t.ring_segments = 8; m = t
		"gear": var c := CylinderMesh.new(); c.top_radius = 0.5; c.bottom_radius = 0.5; c.height = 0.12; c.radial_segments = 12; c.rings = 1; m = c
		"nut": var c := CylinderMesh.new(); c.top_radius = 0.5; c.bottom_radius = 0.5; c.height = 0.5; c.radial_segments = 6; c.rings = 1; m = c
		"ball": var s := SphereMesh.new(); s.radius = 0.5; s.height = 1.0; s.radial_segments = 10; s.rings = 6; m = s
		"link": var t := TorusMesh.new(); t.inner_radius = 0.05; t.outer_radius = 0.11; t.rings = 8; t.ring_segments = 5; m = t
		"cone": var c := CylinderMesh.new(); c.top_radius = 0.0; c.bottom_radius = 0.5; c.height = 1; c.radial_segments = 8; c.rings = 1; m = c
	_meshes[kind] = m
	return m

## Collects instances by (mesh kind, material kind) and turns each bucket into one MultiMeshInstance3D.
class Batch:
	var buckets := {}   # "mesh|mat" -> { xf: Array[Transform3D], col: Array[Color] }
	func add(mesh_kind: String, mat_kind: String, xf: Transform3D, col := Color.WHITE) -> void:
		var k := mesh_kind + "|" + mat_kind
		if not buckets.has(k): buckets[k] = { xf = [], col = [] }
		buckets[k].xf.append(xf); buckets[k].col.append(col)
	func flush(parent: Node3D, script: GDScript) -> void:
		for k in buckets:
			var parts: PackedStringArray = k.split("|")
			var b: Dictionary = buckets[k]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.mesh = script.mesh(parts[0])
			mm.instance_count = b.xf.size()
			for i in b.xf.size():
				mm.set_instance_transform(i, b.xf[i]); mm.set_instance_color(i, b.col[i])
			var mi := MultiMeshInstance3D.new(); mi.multimesh = mm; mi.material_override = script.mat(parts[1])
			mi.name = "Scrap_" + parts[0]
			parent.add_child(mi)
		buckets.clear()

static func xform(pos: Vector3, rot: Vector3, scale: Vector3) -> Transform3D:
	return Transform3D(Basis.from_euler(rot).scaled_local(scale), pos)

## A heap of scrap: plates, beams, drums, tyres, gears and pipes piled into a rough cone.
## Visual only; give it a collider with pile_collider() if Vesk can walk into it.
static func pile(B: Batch, rng: RandomNumberGenerator, c: Vector3, radius: float, height: float, n: int) -> void:
	for i in n:
		var u := sqrt(rng.randf())
		var a := rng.randf() * TAU
		var r := u * radius
		var y := c.y + height * (1.0 - u) * rng.randf_range(0.35, 1.0)
		var p := Vector3(c.x + cos(a) * r, y, c.z + sin(a) * r)
		var rot := Vector3(rng.randf_range(-0.9, 0.9), rng.randf() * TAU, rng.randf_range(-0.9, 0.9))
		var col: Color = PALETTE[rng.randi() % PALETTE.size()] * rng.randf_range(0.8, 1.1)
		col.a = 1.0
		var pick := rng.randf()
		if pick < 0.34: B.add("plate", "scrap", xform(p, rot, Vector3(rng.randf_range(0.6, 1.8), 1, rng.randf_range(0.5, 1.4))), col)
		elif pick < 0.5: B.add("beam", "scrap", xform(p, rot, Vector3(1, 1, rng.randf_range(1.0, 3.2))), col)
		elif pick < 0.62: B.add("drum", "scrap", xform(p, rot, Vector3.ONE * rng.randf_range(0.8, 1.2)), col)
		elif pick < 0.72: B.add("tire", "rubber", xform(p, rot, Vector3.ONE * rng.randf_range(0.8, 1.3)))
		elif pick < 0.8: B.add("gear", "scrap", xform(p, rot, Vector3(1, 1, 1) * rng.randf_range(0.5, 1.3)), col.lerp(YELLOW, 0.4))
		elif pick < 0.9: B.add("pipe", "scrap", xform(p, rot, Vector3(rng.randf_range(0.12, 0.26), rng.randf_range(0.7, 1.7), rng.randf_range(0.12, 0.26))), col)
		else: B.add("block", "scrap", xform(p, rot, Vector3(rng.randf_range(0.4, 1.0), rng.randf_range(0.3, 0.8), rng.randf_range(0.4, 1.0))), col)

## Scrap pieces scattered flat on the ground around a rect (small stuff underfoot, no colliders).
static func litter(B: Batch, rng: RandomNumberGenerator, r: Rect2, y: float, n: int, avoid: Array = []) -> void:
	var placed := 0
	var tries := 0
	while placed < n and tries < n * 6:
		tries += 1
		var p := Vector3(rng.randf_range(r.position.x, r.end.x), y, rng.randf_range(r.position.y, r.end.y))
		var bad := false
		for a: Rect2 in avoid:
			if a.has_point(Vector2(p.x, p.z)): bad = true; break
		if bad: continue
		placed += 1
		var col: Color = PALETTE[rng.randi() % PALETTE.size()] * rng.randf_range(0.75, 1.0); col.a = 1.0
		var pick := rng.randf()
		if pick < 0.4: B.add("plate", "scrap", xform(p + Vector3(0, 0.035, 0), Vector3(rng.randf_range(-0.05, 0.05), rng.randf() * TAU, 0), Vector3(rng.randf_range(0.3, 0.9), 1, rng.randf_range(0.3, 0.8))), col)
		elif pick < 0.6: B.add("nut", "scrap", xform(p + Vector3(0, 0.05, 0), Vector3(0, rng.randf() * TAU, 0), Vector3(0.22, 0.2, 0.22)), col.lerp(GUN, 0.5))
		elif pick < 0.75: B.add("gear", "scrap", xform(p + Vector3(0, 0.03, 0), Vector3(0, rng.randf() * TAU, 0), Vector3.ONE * rng.randf_range(0.25, 0.5)), YELLOW * 0.8)
		elif pick < 0.88: B.add("pipe", "scrap", xform(p + Vector3(0, 0.07, 0), Vector3(PI / 2, rng.randf() * TAU, 0), Vector3(0.14, rng.randf_range(0.6, 1.6), 0.14)), col)
		else: B.add("tire", "rubber", xform(p + Vector3(0, 0.12, 0), Vector3(0, rng.randf() * TAU, 0), Vector3(0.8, 0.8, 0.8)))

static func cyl_collider(L: Node3D, pos: Vector3, radius: float, height: float) -> void:
	var sb := StaticBody3D.new(); var cs := CollisionShape3D.new(); var sh := CylinderShape3D.new()
	sh.radius = radius; sh.height = height; cs.shape = sh; sb.add_child(cs)
	sb.position = pos + Vector3(0, height / 2, 0); L.add_child(sb)

static func box_collider(L: Node3D, pos: Vector3, size: Vector3, rot_y := 0.0) -> void:
	var sb := StaticBody3D.new(); var cs := CollisionShape3D.new(); var sh := BoxShape3D.new()
	sh.size = size; cs.shape = sh; sb.add_child(cs)
	sb.position = pos; sb.rotation.y = rot_y; L.add_child(sb)

## A floating floor slab with a rocky underside, a hazard trim and a glow strip on the given sides
## ("nsew"); `y` is the walking height. Registered in L.islands / L.heights.
static func slab(L: Node3D, name_: String, r: Rect2, y: float, tint: Color, sides := "nsew", thick := 1.2) -> void:
	L.islands[name_] = r; L.heights[name_] = y
	var c := r.get_center()
	L.box(Vector3(c.x, y - thick / 2, c.y), Vector3(r.size.x, thick, r.size.y), M.worn("deck", tint, 0.14, 0.4, 0.65, 0.35))
	var rad: float = min(r.size.x, r.size.y) * 0.48
	var top := y - thick
	var under: MeshInstance3D = L.cyl(Vector3(c.x, top - rad * 0.85, c.y), rad, rad * 0.22, rad * 1.7, L.mat_dark, 8)
	under.scale = Vector3(r.size.x / min(r.size.x, r.size.y), 1, r.size.y / min(r.size.x, r.size.y))
	L.cyl(Vector3(c.x, top - rad * 1.7, c.y), rad * 0.3, rad * 0.3, 0.6, L.glow_cyan)
	var hz := M.hazard()
	var edges := { n = [Vector3(c.x, y - 0.08, r.position.y), Vector3(r.size.x, 0.22, 0.3)], s = [Vector3(c.x, y - 0.08, r.end.y), Vector3(r.size.x, 0.22, 0.3)],
		w = [Vector3(r.position.x, y - 0.08, c.y), Vector3(0.3, 0.22, r.size.y)], e = [Vector3(r.end.x, y - 0.08, c.y), Vector3(0.3, 0.22, r.size.y)] }
	for s in sides:
		var e: Array = edges[s]
		L.box(e[0], e[1], hz, false)
		L.box(e[0] + Vector3(0, -0.2, 0), e[1] * Vector3(1, 0.25, 1) + Vector3(0.02, 0, 0.02), L.glow_cyan, false)

## Rickety plank bridge between two points on the same height (top at y), with rope rails.
static func plank_bridge(L: Node3D, a: Vector3, b: Vector3, width: float, rng: RandomNumberGenerator) -> void:
	var d := b - a; var len := d.length(); var dir := d / len
	var yaw := atan2(dir.x, dir.z)
	# one solid collider, planks are visual
	box_collider(L, (a + b) / 2 + Vector3(0, -0.15, 0), Vector3(width, 0.3, len), yaw)
	var n := int(len / 0.55)
	for i in n:
		var p := a + dir * (len * (i + 0.5) / n) + Vector3(0, -0.08 + rng.randf_range(-0.02, 0.02), 0)
		var pl := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = Vector3(width + rng.randf_range(-0.3, 0.2), 0.12, 0.48); pl.mesh = bm
		pl.material_override = mat("plank"); pl.position = p; pl.rotation.y = yaw + rng.randf_range(-0.06, 0.06)
		L.add_child(pl)
	var side := Vector3(dir.z, 0, -dir.x)
	for s in [-1.0, 1.0]:
		for e in [a, b]:
			var post := MeshInstance3D.new(); var pm := CylinderMesh.new(); pm.top_radius = 0.07; pm.bottom_radius = 0.09; pm.height = 1.3; post.mesh = pm
			post.material_override = mat("wood"); post.position = e + side * s * (width / 2 - 0.1) + Vector3(0, 0.55, 0); L.add_child(post)
		rope(L, a + side * s * (width / 2 - 0.1) + Vector3(0, 1.1, 0), b + side * s * (width / 2 - 0.1) + Vector3(0, 1.1, 0), 0.35)
		# rope rail colliders so nobody walks off the side by accident
		box_collider(L, (a + b) / 2 + side * s * (width / 2) + Vector3(0, 0.55, 0), Vector3(0.2, 1.1, len), yaw)

## A sagging rope (or cable) from a to b, as a few straight segments (cheap, no CSG).
static func rope(L: Node3D, a: Vector3, b: Vector3, sag: float, thick := 0.03, m: Material = null) -> void:
	var n := 6
	var pts := []
	for i in n + 1:
		var u := float(i) / n
		pts.append(a.lerp(b, u) + Vector3(0, -sag * 4.0 * u * (1.0 - u), 0))
	var cm := CylinderMesh.new(); cm.top_radius = thick; cm.bottom_radius = thick; cm.height = 1.0; cm.radial_segments = 5; cm.rings = 1
	for i in n:
		var p0: Vector3 = pts[i]; var p1: Vector3 = pts[i + 1]
		var seg := MeshInstance3D.new(); seg.mesh = cm; seg.material_override = m if m else mat("rope")
		seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		L.add_child(seg)
		var d := p1 - p0
		var up := d.normalized()
		var side := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
		seg.global_transform = Transform3D(Basis(side, up, side.cross(up)).scaled_local(Vector3(1, d.length() + 0.02, 1)), (p0 + p1) / 2)

## String of warm bulbs hanging between two points (glowing spheres, no lights).
static func bulbs(B: Batch, L: Node3D, a: Vector3, b: Vector3, sag: float, n: int) -> void:
	rope(L, a, b, sag, 0.015, mat("dark"))
	for i in n:
		var u := (i + 0.5) / n
		var p := a.lerp(b, u) + Vector3(0, -sag * 4.0 * u * (1.0 - u) - 0.12, 0)
		B.add("ball", "bulb", xform(p, Vector3.ZERO, Vector3.ONE * 0.16))

## A hanging chain of links from top down `length` metres; returns the bottom point.
static func chain(B: Batch, top: Vector3, length: float) -> Vector3:
	var n := int(length / 0.17)
	for i in n:
		B.add("link", "chain", xform(top + Vector3(0, -i * 0.17, 0), Vector3(PI / 2, (PI / 2) * (i % 2), 0), Vector3.ONE))
	return top + Vector3(0, -n * 0.17, 0)

## A tarp thrown over a lump of junk: a box of junk with a cloth skin that sags at the sides, tied down.
static func tarp(L: Node3D, pos: Vector3, size: Vector3, yaw: float, c: Color) -> void:
	var n := Node3D.new(); n.position = pos; n.rotation.y = yaw; L.add_child(n)
	var body := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = size * Vector3(0.68, 0.9, 0.68); body.mesh = bm
	body.material_override = mat("dark"); body.position.y = size.y * 0.45; n.add_child(body)
	var top := MeshInstance3D.new(); var tm := SphereMesh.new(); tm.radius = 0.5; tm.height = 1.0; tm.is_hemisphere = true
	top.mesh = tm; top.material_override = cloth(c); top.scale = Vector3(size.x * 1.08, size.y * 0.5, size.z * 1.08)
	top.position.y = size.y * 0.82; n.add_child(top)
	var skirt := MeshInstance3D.new(); var sm := CylinderMesh.new(); sm.top_radius = 0.5; sm.bottom_radius = 0.56; sm.height = 1.0; sm.radial_segments = 12
	skirt.mesh = sm; skirt.material_override = cloth(c); skirt.scale = Vector3(size.x * 1.06, size.y * 0.84, size.z * 1.06)
	skirt.position.y = size.y * 0.42; n.add_child(skirt)
	# a couple of lumps poking up under the cloth
	for k in 2:
		var lump := MeshInstance3D.new(); lump.mesh = sm; lump.material_override = cloth(c)
		lump.scale = Vector3(size.x * 0.3, size.y * 0.35, size.z * 0.3); lump.position = Vector3((k - 0.5) * size.x * 0.4, size.y * 1.05, (0.5 - k) * size.z * 0.2)
		n.add_child(lump)
	var sb := StaticBody3D.new(); var cs := CollisionShape3D.new(); var sh := BoxShape3D.new(); sh.size = size * Vector3(0.95, 1.0, 0.95)
	cs.shape = sh; cs.position.y = size.y / 2; sb.add_child(cs); n.add_child(sb)

## A rusty sign board on two posts with chunky lettering (both sides readable).
static func sign(L: Node3D, text: String, pos: Vector3, yaw: float, w: float, h: float, lift: float, c := Color(1.0, 0.86, 0.5), board := Color(0.5, 0.3, 0.18), text_scale := 0.32) -> Node3D:
	var n := Node3D.new(); n.position = pos; n.rotation.y = yaw; L.add_child(n)
	for s in [-1, 1]:
		var p := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = Vector3(0.16, lift + h, 0.16); p.mesh = bm
		p.material_override = mat("dark"); p.position = Vector3(s * (w / 2 - 0.3), (lift + h) / 2, -0.12); n.add_child(p)
	var b := MeshInstance3D.new(); var bb := BoxMesh.new(); bb.size = Vector3(w, h, 0.12); b.mesh = bb
	b.material_override = paint(board); b.position = Vector3(0, lift + h / 2, 0); n.add_child(b)
	# riveted trim
	for y in [lift + 0.06, lift + h - 0.06]:
		var t := MeshInstance3D.new(); var tb := BoxMesh.new(); tb.size = Vector3(w + 0.06, 0.1, 0.16); t.mesh = tb
		t.material_override = mat("rust_obj"); t.position = Vector3(0, y, 0); n.add_child(t)
	for side in [1.0, -1.0]:
		var l := Label3D.new(); l.text = text; l.font_size = 64; l.pixel_size = h / 64.0 * text_scale
		l.modulate = c; l.outline_size = 12; l.outline_modulate = Color(0.15, 0.08, 0.04)
		l.width = w / l.pixel_size * 0.92; l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.position = Vector3(0, lift + h / 2, 0.075 * side); l.rotation.y = 0.0 if side > 0 else PI
		l.double_sided = false
		n.add_child(l)
	return n

static func _load(name: String) -> Node3D:
	var p := DIR + name + ".glb"
	if not ResourceLoader.exists(p): return null
	var n: Node3D = load(p).instantiate()
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return n

static func _aabb(name: String, n: Node3D) -> AABB:
	if _aabbs.has(name): return _aabbs[name]
	var ab := AABB(); var first := true
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		var t := Transform3D()
		var p: Node = mi
		while p != n and p is Node3D:
			t = (p as Node3D).transform * t; p = p.get_parent()
		var a := t * mi.get_aabb()
		ab = a if first else ab.merge(a); first = false
	_aabbs[name] = ab
	return ab

## A Meshy prop from models/junkyard with its base centre at pos, `height` metres tall. Returns the holder
## (or null if the model is missing). Colliders are added by the caller (shapes differ per prop).
static func place(parent: Node3D, name: String, pos: Vector3, rot_y: float, height: float) -> Node3D:
	var n := _load(name)
	if n == null: return null
	var ab := _aabb(name, n)
	var s := height / maxf(ab.size.y, 0.001)
	var holder := Node3D.new(); holder.name = "J_" + name
	parent.add_child(holder)
	holder.position = pos; holder.rotation.y = rot_y
	holder.add_child(n)
	n.scale = Vector3.ONE * s
	n.position = -Vector3(ab.get_center().x, ab.position.y, ab.get_center().z) * s
	holder.set_meta("size", ab.size * s)
	return holder

static func omni(L: Node3D, pos: Vector3, c: Color, energy: float, range_: float) -> OmniLight3D:
	var l := OmniLight3D.new(); l.light_color = c; l.light_energy = energy; l.omni_range = minf(range_, 12.0)
	l.shadow_enabled = false; l.position = pos; L.add_child(l)
	return l
