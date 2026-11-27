extends RefCounted
## Roof Gardens look pass (built by areas/y_gardens_look.gd, in final coordinates, after the layout spread).
## Pushes the gardens toward the high-end look-target renders (art/lookdev/junkyard_look.py and the Gardens
## concept): lush, leafy, sunlit, with the city's panic still in the air.
##   - foliage: every bush, hedge, tree crown and vine (the old smooth leaf balls) becomes a clump of
##     leaf cards (shaders/leaf_clump.gdshader): ragged leafy silhouettes, soft volume shading, translucent
##     leaves glowing in the low sun, wind sway. Leaf size stays about the same at every clump size.
##   - grass: tufts of blades over the lawns (shaders/grass_tuft.gdshader), only where the lawn is open
##   - weathered surfaces (shaders/garden_surface.gdshader): stained planter wood with bevelled edges and
##     moss at the soil line, mossy limestone, furrowed bark; the green ironwork becomes chipped painted
##     steel (shaders/painted_steel.gdshader)
##   - air: waterfall mist, pollen and dust motes hanging in the sun shafts, ash drifting over from the fires
##   - panic: smoke pouring up past the grove's edge from a fire below, a sky car down in the
##     orchard, a hedge on fire at the entrance, picnics dropped mid-run
## The grade (warm golden hour, thicker haze for light shafts) is the "gardens" entry in systems/area_mood.gd.
## Gameplay geometry and colliders are untouched.

const Chaos := preload("res://scripts/level/layout/chaos.gd")
const Scatter := preload("res://scripts/level/layout/scatter.gd")
const JK := preload("res://scripts/level/junkyard/junk_kit.gd")
const LEAF_SHADER := "res://shaders/leaf_clump.gdshader"
const GRASS_SHADER := "res://shaders/grass_tuft.gdshader"
const SURF_SHADER := "res://shaders/garden_surface.gdshader"
const STEEL_SHADER := "res://shaders/painted_steel.gdshader"

## clump tiers: [max radius (m), cards, card size in unit-sphere space, casts shadow]
const TIERS := [
	[0.3, 16, 0.9, false],
	[0.7, 40, 0.72, false],
	[1.3, 120, 0.5, true],
	[2.2, 240, 0.38, true],
	[99.0, 420, 0.3, true],
]
const CELL := 24.0           # foliage is batched per 24 m cell so off-screen cells are culled

static func on() -> bool:
	return not OS.get_cmdline_user_args().has("--no-gardens-look")

static func build(L) -> void:
	var K = L.get_meta("garden_kit") if L.has_meta("garden_kit") else null
	if K == null or K.root == null: return
	var root: Node3D = K.root
	var t0 := Time.get_ticks_msec()
	var leaves := _foliage(root)
	var surf := _surfaces(K, root)
	_grass_seed(L, K, root)
	_mist(L)
	_air(L)
	_panic(L)
	print("[gardens-look] %d leaf clumps, %d surfaces restyled, built in %d ms" % [leaves, surf, Time.get_ticks_msec() - t0])

# ------------------------------------------------------------------ foliage
static var _clumps := {}
static var _leaf_mat: ShaderMaterial

static func leaf_mat() -> ShaderMaterial:
	if _leaf_mat == null:
		_leaf_mat = ShaderMaterial.new(); _leaf_mat.shader = load(LEAF_SHADER)
	return _leaf_mat

## A unit-radius clump of leaf cards. Cards sit between 0.45 and 1.08 of the radius facing roughly outward;
## normals are blended toward the clump's centre so it shades as one volume.
static func clump_mesh(tier: int) -> ArrayMesh:
	if _clumps.has(tier): return _clumps[tier]
	var n: int = TIERS[tier][1]
	var size: float = TIERS[tier][2]
	var rng := RandomNumberGenerator.new(); rng.seed = 5150 + tier
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var golden := PI * (3.0 - sqrt(5.0))
	for i in n:
		# fibonacci sphere, a little jittered; fewer cards underneath
		var y := 1.0 - (i + 0.5) / n * 2.0
		y = y * 0.9 + 0.1
		var rr := sqrt(maxf(0.0, 1.0 - y * y))
		var a := golden * i + rng.randf_range(-0.3, 0.3)
		var dir := Vector3(cos(a) * rr, y, sin(a) * rr).normalized()
		var depth := rng.randf_range(0.45, 1.0)
		if i % 4 == 0: depth = rng.randf_range(0.2, 0.55)      # some inner cards fill the core
		var c := dir * depth
		var nrm := (dir + Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.3, 0.6), rng.randf_range(-0.6, 0.6))).normalized()
		var ref := Vector3.UP if absf(nrm.y) < 0.9 else Vector3.RIGHT
		var t := ref.cross(nrm).normalized().rotated(nrm, rng.randf() * TAU)
		var b := nrm.cross(t).normalized()
		# leaves grow outward: point the card's "up" (uv.y) away from the clump centre
		if b.dot(dir) < 0.0: b = -b; t = -t
		var s := size * rng.randf_range(0.8, 1.2)
		var base := c - b * s * 0.25
		var corners := [base - t * s * 0.5, base + t * s * 0.5, base + t * s * 0.5 + b * s, base - t * s * 0.5 + b * s]
		var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		var rnd := rng.randf()
		var vs := []
		for k in 4:
			var p: Vector3 = corners[k]
			vs.append([p, uvs[k], (p.normalized() * 0.75 + nrm * 0.25).normalized(), clampf(p.length() / 1.05, 0.0, 1.0)])
		for tri in [[0, 1, 2], [0, 2, 3]]:
			for k in tri:
				var v: Array = vs[k]
				st.set_uv(Vector2(v[1].x, 1.0 - v[1].y)); st.set_uv2(Vector2(v[3], rnd)); st.set_normal(v[2]); st.add_vertex(v[0])
	var m := st.commit()
	_clumps[tier] = m
	return m

static func _tier(r: float) -> int:
	for i in TIERS.size():
		if r <= TIERS[i][0]: return i
	return TIERS.size() - 1

## Replace the kit's leaf-ball MultiMeshes with leaf-card clumps (per tier, per cell). Hedge boxes keep their
## box as a dense core and get a row of clumps along the top and sides.
static func _foliage(root: Node3D) -> int:
	var groups := {}       # "tier|cx|cz" -> { xf: [], col: [] }
	var add := func(xf: Transform3D, col: Color) -> void:
		var s := xf.basis.get_scale()
		var r := maxf(s.x, maxf(s.y, s.z))
		var tier := _tier(r)
		var key := "%d|%d|%d" % [tier, floori(xf.origin.x / CELL), floori(xf.origin.z / CELL)]
		if not groups.has(key): groups[key] = { tier = tier, xf = [], col = [] }
		groups[key].xf.append(xf); groups[key].col.append(col)
	var count := 0
	for c in root.get_children():
		if not (c is MultiMeshInstance3D): continue
		var mmi := c as MultiMeshInstance3D
		var mm := mmi.multimesh
		if mm == null: continue
		if mmi.name == "MM_leaf":
			for i in mm.instance_count:
				var xf := mm.get_instance_transform(i)
				var sc := xf.basis.get_scale()
				# the flattened tufts along lawn borders: the grass tufts take over there
				if sc.y < 0.5 * maxf(sc.x, sc.z) and sc.x < 0.4: continue
				add.call(xf, mm.get_instance_color(i))
				count += 1
			mmi.visible = false
			mmi.queue_free()
		elif mmi.name == "MM_leafbox":
			# hedges: shrink the box into a dark core and cover it with clumps
			var core := mm.duplicate() as MultiMesh
			for i in mm.instance_count:
				var xf := mm.get_instance_transform(i)
				var col := mm.get_instance_color(i)
				var s := xf.basis.get_scale()
				var bx := xf.basis.orthonormalized()
				var r := clampf(minf(s.x, s.y) * 0.5, 0.3, 0.6)
				var along := s.z
				var nz := maxi(2, int(along / (r * 1.1)))
				for k in nz + 1:
					var lz := lerpf(-along / 2 + r * 0.5, along / 2 - r * 0.5, float(k) / nz)
					for ly in [s.y * 0.32, -s.y * 0.05]:
						for lx in ([0.0] if ly > 0.0 else [-s.x * 0.3, s.x * 0.3]):
							var p: Vector3 = xf.origin + bx * Vector3(lx, ly, lz)
							add.call(Transform3D(Basis(Vector3.UP, randf() * TAU).scaled(Vector3.ONE * r * randf_range(0.9, 1.1)), p), _vary(col))
							count += 1
				core.set_instance_transform(i, Transform3D(bx.scaled_local(s * Vector3(0.82, 0.86, 0.96)), xf.origin))
				core.set_instance_color(i, col * Color(0.55, 0.6, 0.55))
			mmi.multimesh = core
	var mat := leaf_mat()
	var holder := Node3D.new(); holder.name = "LeafClumps"; root.add_child(holder)
	for key in groups:
		var g: Dictionary = groups[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D; mm.use_colors = true
		mm.mesh = clump_mesh(g.tier)
		mm.instance_count = g.xf.size()
		for i in g.xf.size():
			mm.set_instance_transform(i, g.xf[i]); mm.set_instance_color(i, g.col[i])
		var mi := MultiMeshInstance3D.new(); mi.name = "Clumps_" + key.replace("|", "_")
		mi.multimesh = mm; mi.material_override = mat
		var shadow: bool = TIERS[g.tier][3]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if g.tier <= 1:
			mi.visibility_range_end = 70.0; mi.visibility_range_end_margin = 8.0
		holder.add_child(mi)
	return count

static func _vary(c: Color) -> Color:
	return Color(c.r * randf_range(0.92, 1.08), c.g * randf_range(0.94, 1.06), c.b * randf_range(0.9, 1.1))

# ------------------------------------------------------------------ surfaces
static func _surf(kind: int, col: Color, moss: float, unit: bool, extra := {}) -> ShaderMaterial:
	var m := ShaderMaterial.new(); m.shader = load(SURF_SHADER)
	m.set_shader_parameter("kind", kind)
	m.set_shader_parameter("base_col", col)
	m.set_shader_parameter("moss", moss)
	m.set_shader_parameter("unit_half", 0.5 if unit else 0.0)
	for k in extra: m.set_shader_parameter(k, extra[k])
	return m

static func _steel(unit: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new(); m.shader = load(STEEL_SHADER)
	m.set_shader_parameter("paint", Color(0.11, 0.25, 0.19))
	m.set_shader_parameter("paint_metal", 0.15); m.set_shader_parameter("paint_rough", 0.4)
	m.set_shader_parameter("chip", 0.75); m.set_shader_parameter("rust", 0.35); m.set_shader_parameter("streaks", 0.5)
	m.set_shader_parameter("grime", 0.5)
	m.set_shader_parameter("unit_half", 0.5 if unit else 0.0)
	m.set_shader_parameter("pit_nrm", JK._pit_tex())
	return m

## Swap the kit's flat materials (planks, stone, bark, green ironwork) for the weathered shaders.
static func _surfaces(K, root: Node3D) -> int:
	var table := {}     # kit material -> [plain variant, unit-box variant]
	table[K.plank_mat] = [_surf(0, Color(0.46, 0.28, 0.16), 0.55, false), _surf(0, Color(0.46, 0.28, 0.16), 0.55, true)]
	table[K.stone_mat] = [_surf(1, Color(0.7, 0.64, 0.55), 0.6, false), _surf(1, Color(0.7, 0.64, 0.55), 0.6, true)]
	table[K.bark_mat] = [_surf(2, Color(0.4, 0.28, 0.19), 0.65, false, { bump = 1.4 }), _surf(2, Color(0.4, 0.28, 0.19), 0.65, true, { bump = 1.4 })]
	table[K.frame_mat] = [_steel(false), _steel(true)]
	var n := 0
	for g in root.find_children("*", "GeometryInstance3D", true, false):
		var gi := g as GeometryInstance3D
		var m: Material = gi.material_override
		if m == null or not table.has(m): continue
		var pair: Array = table[m]
		if gi is MultiMeshInstance3D:
			var mm: MultiMesh = (gi as MultiMeshInstance3D).multimesh
			var unit := mm != null and mm.mesh is BoxMesh and (mm.mesh as BoxMesh).size.is_equal_approx(Vector3.ONE)
			gi.material_override = pair[1] if unit else pair[0]
		elif gi is MeshInstance3D:
			gi.material_override = pair[0]
			var mesh: Mesh = (gi as MeshInstance3D).mesh
			if mesh is BoxMesh: gi.set_instance_shader_parameter("box_half", (mesh as BoxMesh).size * 0.5)
		else: continue
		n += 1
	# richer, darker soil in the beds
	if K.soil_mat is StandardMaterial3D:
		var s := K.soil_mat as StandardMaterial3D
		s.albedo_color = Color(0.2, 0.13, 0.08); s.roughness = 0.95
	return n

# ------------------------------------------------------------------ grass
## Grass is seeded a few physics frames after load: each tuft is raycast onto the deck and kept only where
## the lawn is open (not under a bed, pond rim, shed or tree, and not on the paving).
static func _grass_seed(L: Node3D, K, root: Node3D) -> void:
	var lawns := []
	for c in root.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).material_override == K.lawn_mat and (c as MeshInstance3D).mesh is PlaneMesh:
			var mi := c as MeshInstance3D
			lawns.append({ pos = mi.global_position, size = (mi.mesh as PlaneMesh).size })
	var pave := []
	for c in root.get_children():
		if c is MultiMeshInstance3D and (c.name == "MM_pave" or c.name == "MM_stone"):
			var mm: MultiMesh = (c as MultiMeshInstance3D).multimesh
			for i in mm.instance_count:
				var xf := mm.get_instance_transform(i)
				var s := xf.basis.get_scale()
				pave.append([Vector2(xf.origin.x, xf.origin.z), maxf(s.x, s.z) * (0.6 if c.name == "MM_stone" else 1.0) + 0.15])
	var seeder := GrassSeeder.new(); seeder.name = "GardenGrass"
	seeder.lawns = lawns; seeder.pave = pave
	root.add_child(seeder)

class GrassSeeder extends Node3D:
	var lawns := []
	var pave := []
	var _frames := 0
	const DENSITY := 7.0

	func _physics_process(_dt: float) -> void:
		_frames += 1
		if _frames < 4: return
		set_physics_process(false)
		var t0 := Time.get_ticks_usec()
		var space := get_world_3d().direct_space_state
		var rng := RandomNumberGenerator.new(); rng.seed = 7171
		var mat := ShaderMaterial.new(); mat.shader = load("res://shaders/grass_tuft.gdshader")
		var mesh := _tuft_mesh()
		var total := 0
		for lw in lawns:
			var c: Vector3 = lw.pos; var sz: Vector2 = lw.size
			var deck := c.y - 0.025
			var n := int(sz.x * sz.y * DENSITY)
			var xfs := []
			for i in n:
				var p := Vector3(c.x + rng.randf_range(-0.485, 0.485) * sz.x, deck, c.z + rng.randf_range(-0.485, 0.485) * sz.y)
				var q := Vector2(p.x, p.z)
				var blocked := false
				for pv in pave:
					if q.distance_squared_to(pv[0]) < pv[1] * pv[1]: blocked = true; break
				if blocked: continue
				var ray := PhysicsRayQueryParameters3D.create(p + Vector3(0, 3.0, 0), p - Vector3(0, 0.5, 0))
				var hit := space.intersect_ray(ray)
				if hit.is_empty() or absf(hit.position.y - deck) > 0.06: continue
				var w := rng.randf_range(0.32, 0.5); var h := rng.randf_range(0.2, 0.36)
				xfs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(w, h, w)), Vector3(p.x, deck + 0.02, p.z)))
			if xfs.is_empty(): continue
			var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D; mm.mesh = mesh
			mm.instance_count = xfs.size()
			for i in xfs.size(): mm.set_instance_transform(i, xfs[i])
			var mi := MultiMeshInstance3D.new(); mi.multimesh = mm; mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visibility_range_end = 45.0; mi.visibility_range_end_margin = 6.0
			add_child(mi)
			total += xfs.size()
		print("[gardens-look] grass: %d tufts on %d lawns in %.1f ms" % [total, lawns.size(), (Time.get_ticks_usec() - t0) / 1000.0])

	static func _tuft_mesh() -> ArrayMesh:
		var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for k in 3:
			var a := k * PI / 3.0
			var d := Vector3(cos(a), 0, sin(a)) * 0.5
			var v := [-d, d, d + Vector3.UP, -d + Vector3.UP]
			var uv := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
			for tri in [[0, 1, 2], [0, 2, 3]]:
				for i in tri:
					st.set_normal(Vector3.UP); st.set_uv(uv[i]); st.add_vertex(v[i])
		return st.commit()

# ------------------------------------------------------------------ waterfall mist
const FALLS := [[Vector3(-70.1, 9.04, 0.8), Vector2(-1, 0)], [Vector3(-76.6, 9.0, -35.85), Vector2(0, 1)], [Vector3(-72.0, 10.2, -70.1), Vector2(0, -1)]]

static func _mist(L: Node3D) -> void:
	var holder := Node3D.new(); holder.name = "GardenMist"; L.add_child(holder)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES; mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true; mat.albedo_texture = Chaos._soft_tex()
	mat.albedo_color = Color(1.25, 1.2, 1.12)
	mat.proximity_fade_enabled = true; mat.proximity_fade_distance = 0.8
	for f in FALLS:
		var top: Vector3 = f[0]; var out: Vector2 = f[1]
		var o := Vector3(out.x, 0, out.y)
		for stage in 2:
			var p := GPUParticles3D.new()
			p.amount = 22 if stage == 0 else 30
			p.lifetime = 2.6 if stage == 0 else 5.0
			p.preprocess = 4.0
			var pm := ParticleProcessMaterial.new()
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
			pm.emission_box_extents = Vector3(0.8, 0.2, 0.8) if stage == 0 else Vector3(2.0, 3.0, 2.0)
			pm.direction = o + Vector3(0, -0.6, 0); pm.spread = 25.0
			pm.initial_velocity_min = 0.4; pm.initial_velocity_max = 1.2
			pm.gravity = Vector3(0, -1.2, 0) if stage == 0 else Vector3(0, 0.15, 0)
			pm.damping_min = 0.3; pm.damping_max = 0.6
			pm.scale_min = 0.8 if stage == 0 else 2.0; pm.scale_max = 1.6 if stage == 0 else 3.6
			pm.angle_min = 0; pm.angle_max = 360
			var sc := CurveTexture.new(); var cv := Curve.new(); cv.add_point(Vector2(0, 0.4)); cv.add_point(Vector2(1, 1.0)); sc.curve = cv
			pm.scale_curve = sc
			var ramp := GradientTexture1D.new(); var gr := Gradient.new()
			gr.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
			gr.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.22 if stage == 0 else 0.14), Color(1, 1, 1, 0)])
			ramp.gradient = gr; pm.color_ramp = ramp
			p.process_material = pm
			var q := QuadMesh.new(); q.size = Vector2(1.6, 1.6); q.material = mat
			p.draw_pass_1 = q
			p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			p.visibility_aabb = AABB(Vector3(-8, -14, -8), Vector3(16, 20, 16))
			p.position = top + o * 0.9 + (Vector3(0, -0.3, 0) if stage == 0 else Vector3(0, -7.0, 0) + o * 1.2)
			holder.add_child(p)

# ------------------------------------------------------------------ air: pollen, dust motes, ash
static func _air(L: Node3D) -> void:
	var holder := Node3D.new(); holder.name = "GardenAir"; L.add_child(holder)
	# warm motes and pollen hanging in the light shafts (additive, tiny)
	var mote := StandardMaterial3D.new()
	mote.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; mote.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mote.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; mote.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mote.vertex_color_use_as_albedo = true; mote.albedo_texture = Chaos._soft_tex(); mote.albedo_color = Color(2.2, 1.8, 1.1)
	for z in [[Vector3(-62, 12.5, -6), Vector3(14, 4, 12)], [Vector3(-53, 12.5, -27), Vector3(5, 4, 14)],
			[Vector3(-72, 13, -43), Vector3(13, 5, 9)], [Vector3(-68, 14, -63), Vector3(14, 5, 9)], [Vector3(-90, 20, -45), Vector3(8, 7, 10)]]:
		var p := GPUParticles3D.new()
		p.amount = 140; p.lifetime = 9.0; p.preprocess = 9.0
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX; pm.emission_box_extents = z[1]
		pm.direction = Vector3(1, 0.2, 0.3); pm.spread = 180.0
		pm.initial_velocity_min = 0.05; pm.initial_velocity_max = 0.25
		pm.gravity = Vector3(0.05, 0.02, 0.03)
		pm.turbulence_enabled = true; pm.turbulence_noise_strength = 0.6; pm.turbulence_noise_scale = 4.0
		pm.turbulence_influence_min = 0.02; pm.turbulence_influence_max = 0.06
		pm.scale_min = 0.6; pm.scale_max = 1.4
		var ramp := GradientTexture1D.new(); var gr := Gradient.new()
		gr.offsets = PackedFloat32Array([0.0, 0.3, 0.7, 1.0])
		gr.colors = PackedColorArray([Color(1, 0.9, 0.6, 0), Color(1, 0.9, 0.6, 0.55), Color(1, 0.85, 0.5, 0.5), Color(1, 0.8, 0.5, 0)])
		ramp.gradient = gr; pm.color_ramp = ramp
		p.process_material = pm
		var q := QuadMesh.new(); q.size = Vector2(0.035, 0.035); q.material = mote
		p.draw_pass_1 = q
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.visibility_aabb = AABB(-z[1] * 1.5, z[1] * 3.0)
		p.position = z[0]
		holder.add_child(p)
	# ash flakes blowing in from the burning city: dark, tumbling, slowly falling
	var ash := StandardMaterial3D.new()
	ash.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; ash.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	ash.vertex_color_use_as_albedo = true; ash.albedo_texture = Chaos._soft_tex(); ash.roughness = 1.0
	var pa := GPUParticles3D.new()
	pa.amount = 220; pa.lifetime = 12.0; pa.preprocess = 12.0
	var pam := ParticleProcessMaterial.new()
	pam.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX; pam.emission_box_extents = Vector3(30, 2, 40)
	pam.direction = Vector3(1, -0.3, 0.2); pam.spread = 30.0
	pam.initial_velocity_min = 0.8; pam.initial_velocity_max = 1.6
	pam.gravity = Vector3(0.3, -0.25, 0.1)
	pam.turbulence_enabled = true; pam.turbulence_noise_strength = 1.2; pam.turbulence_noise_scale = 6.0
	pam.angle_min = 0; pam.angle_max = 360; pam.angular_velocity_min = -90; pam.angular_velocity_max = 90
	pam.scale_min = 0.6; pam.scale_max = 1.5
	var ar := GradientTexture1D.new(); var ag := Gradient.new()
	ag.offsets = PackedFloat32Array([0.0, 0.15, 0.85, 1.0])
	ag.colors = PackedColorArray([Color(0.2, 0.18, 0.17, 0), Color(0.22, 0.2, 0.19, 0.8), Color(0.3, 0.28, 0.26, 0.7), Color(0.3, 0.28, 0.26, 0)])
	ar.gradient = ag; pam.color_ramp = ar
	pa.process_material = pam
	var aq := QuadMesh.new(); aq.size = Vector2(0.05, 0.04); aq.material = ash
	pa.draw_pass_1 = aq
	pa.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pa.visibility_aabb = AABB(Vector3(-50, -20, -60), Vector3(100, 40, 120))
	pa.position = Vector3(-72, 20, -32)
	holder.add_child(pa)

# ------------------------------------------------------------------ panic
static func _panic(L: Node3D) -> void:
	var C: Node3D = Chaos.make(L, "gardens_panic")
	C.center = Vector3(-68, 10, -32); C.radius = 90.0
	# smoke pouring up past the Hive Grove's east edge from a fire on the deck below (kept narrow: a FogVolume
	# darkens everything seen through it, and the sky behind it is not fogged)
	C.column(Vector3(-54.0, -2.0, -66.0), 0.8, 30.0, 0.24)
	for f in C.fires: (f.light as OmniLight3D).shadow_enabled = false
	# a hedge caught fire by the entrance arch (sparks from a crash on the promenade)
	C.fire(Vector3(-59.0, 9.9, -13.55), 0.6)
	C.smoke(Vector3(-59.0, 10.6, -13.55), 0.8, true)
	C.flush()
	# things dropped where people ran: picnics on the lawn, bags on the promenade, a sky car down in the orchard
	var plan := [
		{ area = "west", c = Vector3(-63.5, 8.8, -6.0), r = 3.5, items = [["luggage", 3], ["sign_bent", 1]] },
		{ area = "west", c = Vector3(-53.0, 8.8, -30.0), r = 2.0, items = [["luggage", 2]] },
		{ area = "west", c = Vector3(-74.0, 8.8, -47.0), r = 2.5, items = [["luggage", 2], ["rubble", 1]] },
		{ area = "west", c = Vector3(-58.5, 10.0, -62.5), r = 2.5, items = [["skycar", 1]] },
	]
	var s: Node3D = Scatter.new()
	s.name = "GardensScatter"
	s.setup(L, plan)
	L.add_child(s)
