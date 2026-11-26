class_name DocksDressing
## Set dressing for the Cargo Docks (the first area built out to the "full art" target).
## Models in res://models/docks/<name>.glb were generated with Meshy (see art/meshy/README.md). Each is
## fitted by height (or to an exact box for containers), sat on the floor at its base centre, and given a
## box collider when it stands where Vesk can walk. Missing models are skipped, so the level still loads.

const DIR := "res://models/docks/"
const M := preload("res://scripts/mats.gd")

static var _aabbs := {}
static var _tinted := {}   # shared tinted copies so containers of one colour batch

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

## Place a model with its base centre at pos, scaled so it is `height` metres tall.
static func place(parent: Node3D, name: String, pos: Vector3, rot_y := 0.0, height := 1.0, collide := false, shrink := 0.85) -> Node3D:
	var n := _load(name)
	if n == null: return null
	var ab := _aabb(name, n)
	var s := height / maxf(ab.size.y, 0.001)
	var holder := Node3D.new(); holder.name = "D_" + name
	parent.add_child(holder)
	holder.position = pos; holder.rotation.y = rot_y
	holder.add_child(n)
	n.scale = Vector3.ONE * s
	n.position = -Vector3(ab.get_center().x, ab.position.y, ab.get_center().z) * s
	if collide:
		var sb := StaticBody3D.new(); var cs := CollisionShape3D.new(); var sh := BoxShape3D.new()
		sh.size = Vector3(ab.size.x * s * shrink, ab.size.y * s, ab.size.z * s * shrink)
		cs.shape = sh; cs.position = Vector3(0, ab.size.y * s / 2, 0)
		sb.add_child(cs); holder.add_child(sb)
	return holder

## Place a model with its base centre at pos, stretched to exactly `size` (x along the model's own x).
static func place_fit(parent: Node3D, name: String, pos: Vector3, rot_y: float, size: Vector3) -> Node3D:
	var n := _load(name)
	if n == null: return null
	var ab := _aabb(name, n)
	var holder := Node3D.new(); holder.name = "D_" + name
	parent.add_child(holder)
	holder.position = pos; holder.rotation.y = rot_y
	holder.add_child(n)
	n.scale = Vector3(size.x / ab.size.x, size.y / ab.size.y, size.z / ab.size.z)
	n.position = -Vector3(ab.get_center().x, ab.position.y, ab.get_center().z) * n.scale
	return holder

## Fit a model exactly into a box (used to skin the gameplay containers, which keep their own colliders).
static func skin_box(box_mi: MeshInstance3D, name: String, tint: Color) -> void:
	var n := _load(name)
	if n == null: return
	var ab := _aabb(name, n)
	var size: Vector3 = (box_mi.mesh as BoxMesh).size
	var holder := Node3D.new()
	box_mi.add_child(holder)
	var long_x := size.x >= size.z
	var model_long_x := ab.size.x >= ab.size.z
	if long_x != model_long_x: holder.rotation.y = PI / 2
	var target := size if not (long_x != model_long_x) else Vector3(size.z, size.y, size.x)
	holder.add_child(n)
	n.scale = Vector3(target.x / ab.size.x, target.y / ab.size.y, target.z / ab.size.z)
	n.position = -ab.get_center() * n.scale
	box_mi.mesh = null   # the collider (a child StaticBody3D) stays
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		for i in mi.get_surface_override_material_count():
			var m := mi.mesh.surface_get_material(i)
			if m is StandardMaterial3D:
				var key := "%s|%d|%d|%s" % [name, m.get_instance_id(), i, tint.to_html()]
				if not _tinted.has(key):
					var c: StandardMaterial3D = m.duplicate(); c.albedo_color = tint
					_tinted[key] = c
				mi.set_surface_override_material(i, _tinted[key])

## A striped cargo balloon whose ring sits at `ring` (it floats the hanging containers over the rails).
static func balloon(L: Node3D, ring: Vector3, rot_y: float, tint_mat: Material) -> void:
	var n := Node3D.new(); n.position = ring; n.rotation.y = rot_y; L.add_child(n)
	var c: Color = (tint_mat as StandardMaterial3D).albedo_color if tint_mat is StandardMaterial3D else Color(0.9, 0.4, 0.2)
	var key := "balloon_" + c.to_html()
	if not _tinted.has(key): _tinted[key] = M.cloth(c.lightened(0.1))
	if not _tinted.has("balloon_cream"): _tinted["balloon_cream"] = M.cloth(Color(0.95, 0.9, 0.8))
	var tor := TorusMesh.new(); tor.inner_radius = 0.3; tor.outer_radius = 0.42; tor.ring_segments = 8; tor.rings = 16
	var rm := MeshInstance3D.new(); rm.mesh = tor; rm.material_override = M.brass(); n.add_child(rm)
	var env := SphereMesh.new(); env.radius = 2.6; env.height = 5.2; env.radial_segments = 24; env.rings = 12
	var em := MeshInstance3D.new(); em.mesh = env; em.material_override = _tinted[key]; em.position.y = 3.6
	em.scale = Vector3(1.25, 0.95, 1.0); n.add_child(em)
	for k in [-1, 0, 1]:   # cream bands round the envelope
		var b := TorusMesh.new(); b.inner_radius = 2.45 - absf(k) * 0.5; b.outer_radius = 2.68 - absf(k) * 0.5; b.rings = 24; b.ring_segments = 6
		var bm := MeshInstance3D.new(); bm.mesh = b; bm.material_override = _tinted["balloon_cream"]
		bm.position = Vector3(k * 1.5, 3.6, 0); bm.rotation.z = PI / 2; bm.scale = Vector3(1, 1.0, 0.98)
		n.add_child(bm)
	for s in [-1, 1]:   # rigging lines from the ring to the envelope
		var l := CylinderMesh.new(); l.top_radius = 0.025; l.bottom_radius = 0.025; l.height = 1.9; l.radial_segments = 4
		var lm := MeshInstance3D.new(); lm.mesh = l; lm.material_override = M.std(Color(0.2, 0.2, 0.22), 0.3, 0.7)
		lm.position = Vector3(s * 0.7, 0.9, 0); lm.rotation.z = -s * 0.65; n.add_child(lm)
	var fin := BoxMesh.new(); fin.size = Vector3(1.2, 1.4, 0.08)
	var fm := MeshInstance3D.new(); fm.mesh = fin; fm.material_override = _tinted["balloon_cream"]; fm.position = Vector3(-3.3, 3.8, 0); n.add_child(fm)

static func steam(parent: Node3D, pos: Vector3, scale := 1.0) -> void:
	var p := CPUParticles3D.new()
	var q := QuadMesh.new(); q.size = Vector2(0.7, 0.7) * scale; p.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES; m.vertex_color_use_as_albedo = true
	var g := GradientTexture2D.new(); g.fill = GradientTexture2D.FILL_RADIAL; g.fill_from = Vector2(0.5, 0.5); g.fill_to = Vector2(1, 0.5)
	var gr := Gradient.new(); gr.set_color(0, Color(1, 1, 1, 0.55)); gr.set_color(1, Color(1, 1, 1, 0)); g.gradient = gr
	m.albedo_texture = g; p.material_override = m
	p.amount = 18; p.lifetime = 2.6; p.direction = Vector3(0, 1, 0); p.spread = 12
	p.initial_velocity_min = 1.2 * scale; p.initial_velocity_max = 2.2 * scale; p.gravity = Vector3(0.6, 0.2, 0)
	p.scale_amount_min = 0.8; p.scale_amount_max = 1.6
	var c := Curve.new(); c.add_point(Vector2(0, 0.4)); c.add_point(Vector2(1, 2.4)); p.scale_amount_curve = c
	var ramp := Gradient.new(); ramp.set_color(0, Color(1, 0.97, 0.92, 0.7)); ramp.set_color(1, Color(1, 1, 1, 0)); p.color_ramp = ramp
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p); p.position = pos

## A slow drifting loop for airships (bobbing, a gentle sway and a long back-and-forth path).
static func drift(n: Node3D, from: Vector3, to: Vector3, period: float) -> void:
	if n == null: return
	n.position = from
	n.look_at_from_position(from, to, Vector3.UP)
	n.rotate_object_local(Vector3.UP, PI)
	var tw := n.create_tween().set_loops()
	tw.tween_property(n, "position", to, period).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(n, "rotation:y", n.rotation.y + PI, 6.0).set_trans(Tween.TRANS_SINE)
	tw.tween_property(n, "position", from, period).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(n, "rotation:y", n.rotation.y, 6.0).set_trans(Tween.TRANS_SINE)
	var bob := n.get_child(0).create_tween().set_loops()
	bob.tween_property(n.get_child(0), "position:y", n.get_child(0).position.y + 0.8, 3.5).set_trans(Tween.TRANS_SINE)
	bob.tween_property(n.get_child(0), "position:y", n.get_child(0).position.y, 3.5).set_trans(Tween.TRANS_SINE)

## Everything placed around the three piers. Pier A: x 28..50, z 16..44, y 0. Pier B: x 50..66, z -16..0,
## y 4. Pier C: x 60..76, z -46..-30, y 6. Paths kept clear: the plaza gaps on Pier A's west edge, the rail
## starts (44, 18) and (60, -15), the lift at (57.5, -38) and the hook chain west of Pier C.
static func dress(L: Node3D) -> void:
	# ---- Pier A
	place(L, "dock_crane", Vector3(31, 0, 42), PI * 0.75, 13.0, true, 0.35)
	place(L, "crates", Vector3(29.6, 0, 36.5), 0.4, 2.2, true)
	place(L, "crates", Vector3(48.6, 0, 31), -1.2, 1.9, true)
	place(L, "barrels", Vector3(30.2, 0, 23.5), 0.0, 1.3, true)
	place(L, "barrels", Vector3(48.4, 0, 22), 2.0, 1.3, true)
	place(L, "pipes", Vector3(49, 0, 17.2), 0.0, 3.2, true, 0.6)
	steam(L, Vector3(49, 3.3, 17.2))
	place(L, "forklift", Vector3(40.5, 0, 41.2), PI * 0.5, 2.3, true)
	place(L, "dock_bot", Vector3(37, 0, 40.2), PI, 1.3, true)
	place(L, "cable_spool", Vector3(29.8, 0, 18.4), 0.0, 1.4, true)
	place(L, "hazard_barrier", Vector3(46.8, 0, 17.0), 0.3, 1.1, false)
	# more clutter along the edges so the open deck reads as a working dock
	place(L, "crates", Vector3(29.4, 0, 29.5), 1.9, 1.5, true)
	place(L, "barrels", Vector3(48.9, 0, 37.5), 0.7, 1.2, true)
	place(L, "crates", Vector3(34.5, 0, 17.0), -0.3, 1.2, true)
	place(L, "cable_spool", Vector3(48.6, 0, 27.2), 1.1, 1.1, true)
	for b in [Vector3(28.6, 0, 40.5), Vector3(28.6, 0, 22.5), Vector3(49.4, 0, 36.5), Vector3(49.4, 0, 26.5)]:
		place(L, "bollard", b, randf() * TAU, 0.7, true)
	place(L, "floodlight", Vector3(49.2, 0, 43.2), PI * 1.25, 7.0, true, 0.3)
	# ---- Pier B
	place(L, "fuel_tanks", Vector3(64.2, 4, -9.5), PI * 0.5, 2.8, true)
	place(L, "barrels", Vector3(65.0, 4, -13.0), 1.0, 1.3, true)   # clear of the depot rail's landing
	place(L, "dock_bot", Vector3(55, 4, -12.5), 0.6, 1.3, true)
	place(L, "floodlight", Vector3(51, 4, -15.2), PI * 0.25, 6.0, true, 0.3)
	place(L, "bollard", Vector3(65.4, 4, -14.5), 0.0, 0.7, true)
	# ---- Pier C
	place(L, "pipes", Vector3(75, 6, -34), PI * 0.5, 3.4, true, 0.6)
	steam(L, Vector3(75, 9.5, -34))
	place(L, "crates", Vector3(74.6, 6, -40), 0.2, 2.0, true)
	place(L, "dock_bot", Vector3(70.5, 6, -36.5), -0.8, 1.3, true)
	place(L, "cable_spool", Vector3(66, 6, -45), 0.5, 1.4, true)
	place(L, "barrels", Vector3(61.2, 6, -44.6), 0.4, 1.2, true)
	place(L, "crates", Vector3(75.2, 6, -31.2), 2.6, 1.4, true)
	place(L, "hazard_barrier", Vector3(60.8, 6, -33.2), PI * 0.5, 1.1, false)
	place(L, "floodlight", Vector3(75.4, 6, -45.4), PI * 1.75, 6.5, true, 0.3)
	# ---- supports: steel trusses under the piers, down into the clouds
	for t in [[Vector3(30, -1.2, 18), 34.0], [Vector3(48, -1.2, 18), 30.0], [Vector3(30, -1.2, 42), 30.0], [Vector3(48, -1.2, 42), 36.0],
			[Vector3(52, 2.0, -14), 32.0], [Vector3(64, 2.0, -2), 34.0], [Vector3(62, 4.0, -44), 36.0], [Vector3(74, 4.0, -32), 32.0]]:
		place(L, "truss", t[0] - Vector3(0, t[1], 0), randf() * 0.3, t[1], false)
	# ---- vista: floating islands, airships
	for v in [[Vector3(185, -14, 30), 26.0, 0.3], [Vector3(150, 6, -95), 18.0, 2.0], [Vector3(195, 18, -40), 34.0, 4.0],
			[Vector3(120, -30, 105), 16.0, 1.0], [Vector3(215, -6, 95), 22.0, 5.2], [Vector3(80, 30, -135), 30.0, 3.0]]:
		place(L, "island", v[0], v[2], v[1], false)
	drift(place(L, "airship", Vector3.ZERO, 0.0, 6.0, false), Vector3(70, 22, 30), Vector3(105, 26, -40), 70.0)
	drift(place(L, "airship", Vector3.ZERO, 0.0, 4.5, false), Vector3(30, 30, -70), Vector3(95, 24, -95), 60.0)
	drift(place(L, "airship", Vector3.ZERO, 0.0, 8.0, false), Vector3(140, 34, 60), Vector3(150, 30, -60), 95.0)
