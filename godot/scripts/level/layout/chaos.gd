extends Node3D
## The panic left behind: luggage dropped mid-run, carts shoved aside, stalls knocked flat, sky cars that came
## down hard, fires, smoke columns, flickering broken signs and barricades somebody started and never finished.
## One Chaos node per route or area (it is also the parent of everything it places, so whole clusters cull
## together). Props come from godot/models/chaos/*.glb (art/chaos_kit.py) plus a few kit and docks models.
## Props of the same kind are merged into one mesh and drawn as a MultiMesh per Chaos node (cheap), fires and
## smoke are GPU particles, and the fire lights flicker only while Vesk is near.
## Use: var C := Chaos.make(L, "plaza_bridge"); C.prop("suitcase_teal", pos, yaw); ...; C.flush()

const DIR := "res://models/chaos/"
const M := preload("res://scripts/mats.gd")

static var _meshes := {}         # glb name -> ArrayMesh (all parts merged, one surface per material)
static var _fire_mat: Material
static var _smoke_mats := {}
static var _soft: Texture2D
static var _noise3d: Texture3D
## Shader fire/smoke, ember sparks and volumetric smoke columns (off with --no-hd-fx).
static var HD: bool = not OS.get_cmdline_user_args().has("--no-hd-fx")

var L: Node3D
var batch := {}                  # mesh name -> Array[Transform3D]
var fires: Array = []            # { light: OmniLight3D, base: float, ph: float }
var signs: Array = []            # { label: Label3D, ph: float, rate: float }
var center := Vector3.ZERO
var radius := 60.0
var t := 0.0

static func make(level: Node3D, name_: String) -> Node3D:
	var c: Node3D = load("res://scripts/level/layout/chaos.gd").new()
	c.name = "Chaos_" + name_
	c.L = level
	level.add_child(c)
	return c

# ------------------------------------------------------------------ merged prop meshes
static func mesh_of(name_: String) -> ArrayMesh:
	if _meshes.has(name_): return _meshes[name_]
	var path := DIR + name_ + ".glb"
	if not ResourceLoader.exists(path):
		path = "res://models/" + name_ + ".glb"
	if not ResourceLoader.exists(path):
		_meshes[name_] = null; return null
	var root: Node3D = (load(path) as PackedScene).instantiate()
	var by_mat := {}   # Material -> SurfaceTool
	var order: Array = []
	_collect(root, Transform3D.IDENTITY, by_mat, order)
	var am := ArrayMesh.new()
	for m in order:
		var st: SurfaceTool = by_mat[m]
		st.commit(am)
		am.surface_set_material(am.get_surface_count() - 1, m)
	root.free()
	_meshes[name_] = am
	return am

static func _collect(n: Node, xf: Transform3D, by_mat: Dictionary, order: Array) -> void:
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
	for c in n.get_children(): _collect(c, here, by_mat, order)

## place a prop (batched). tilt = extra rotation (x, z in radians) for knocked-over things
func prop(name_: String, pos: Vector3, yaw := 0.0, scale_ := 1.0, tilt := Vector2.ZERO, collide := false) -> void:
	var am := mesh_of(name_)
	if am == null: return
	var b := Basis.from_euler(Vector3(tilt.x, yaw, tilt.y)).scaled(Vector3.ONE * scale_)
	var xf := Transform3D(b, pos)
	if not batch.has(name_): batch[name_] = []
	batch[name_].append(xf)
	if collide:
		var ab := am.get_aabb()
		var sb := StaticBody3D.new(); var cs := CollisionShape3D.new(); var sh := BoxShape3D.new()
		sh.size = ab.size * 0.9; cs.shape = sh; cs.position = ab.get_center()
		sb.add_child(cs); sb.transform = xf; add_child(sb)

## a solid scene prop (not batched), e.g. the skycar or a docks model; returns the node
func model(path: String, pos: Vector3, yaw := 0.0, scale_ := 1.0, tilt := Vector2.ZERO) -> Node3D:
	if not ResourceLoader.exists(path): return null
	var n: Node3D = (load(path) as PackedScene).instantiate()
	n.position = pos; n.rotation = Vector3(tilt.x, yaw, tilt.y); n.scale = Vector3.ONE * scale_
	add_child(n)
	return n

func box_collider(pos: Vector3, size: Vector3, yaw := 0.0) -> void:
	var sb := StaticBody3D.new(); var cs := CollisionShape3D.new(); var sh := BoxShape3D.new()
	sh.size = size; cs.shape = sh; sb.add_child(cs); sb.position = pos; sb.rotation.y = yaw; add_child(sb)

func flush() -> void:
	var lo := Vector3(INF, INF, INF); var hi := -lo
	for k in batch:
		var xfs: Array = batch[k]
		var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh_of(k); mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, xfs[i])
			lo = lo.min(xfs[i].origin); hi = hi.max(xfs[i].origin)
		var mi := MultiMeshInstance3D.new(); mi.multimesh = mm; mi.name = "Chaos_" + k
		mi.visibility_range_end = 150.0; mi.visibility_range_end_margin = 10.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(mi)
	batch.clear()
	if lo.x < INF:
		center = (lo + hi) * 0.5; radius = maxf(30.0, (hi - lo).length() * 0.5 + 40.0)

# ------------------------------------------------------------------ groups of props
## luggage dropped in a hurry around c (some standing, most on their sides)
func luggage(c: Vector3, r: float, n: int, rng: RandomNumberGenerator) -> void:
	var kinds := ["suitcase_teal", "suitcase_coral", "suitcase_mustard", "duffel", "suitcase_teal", "duffel"]
	for i in n:
		var a := rng.randf() * TAU; var d := sqrt(rng.randf()) * r
		var p := c + Vector3(cos(a) * d, 0, sin(a) * d)
		var k: String = kinds[rng.randi() % kinds.size()]
		var lie := rng.randf() < 0.6 and k != "duffel"
		var tilt := Vector2(PI / 2 * (1 if rng.randf() < 0.5 else -1), 0) if lie else Vector2(0, rng.randf_range(-0.1, 0.1))
		var lift := 0.2 if lie else 0.0
		prop(k, p + Vector3(0, lift, 0), rng.randf() * TAU, rng.randf_range(0.9, 1.1), tilt)

## a barricade somebody started and gave up on: sawhorses, sandbags and cones from a to b with a gap
func barricade(a: Vector3, b: Vector3, rng: RandomNumberGenerator, gap_u := 0.5, gap_w := 2.6) -> void:
	var d := b - a; var len := d.length(); var yaw := atan2(d.x, d.z) + PI / 2
	var dir := d / maxf(len, 0.01)
	var u := 0.0
	var i := 0
	while u < len:
		var mid := u + 1.0
		if absf(mid - len * gap_u) < gap_w * 0.5 + 1.0: u += 0.8; continue
		var p := a + dir * mid
		var pick := i % 4
		if pick == 0 or pick == 2: prop("sawhorse", p, yaw + rng.randf_range(-0.15, 0.15), 1.0, Vector2.ZERO, true)
		elif pick == 1: prop("sandbags", p, yaw + rng.randf_range(-0.1, 0.1), 1.0, Vector2.ZERO, true)
		else:
			prop("sandbags", p + Vector3(0, 0, 0), yaw, 0.9, Vector2.ZERO, true)
			prop("cone", p + dir * 0.9 + Vector3(0.3, 0, 0), 0.0, 1.0, Vector2(0, 1.4) if rng.randf() < 0.4 else Vector2.ZERO)
		u += 2.1; i += 1
	# the leftover pile they never got to
	var pile := a + dir * (len * gap_u) + dir.cross(Vector3.UP) * 2.2
	prop("sandbags", pile, yaw + 0.4, 0.8)
	prop("cone", pile + Vector3(0.8, 0, 0.5), 0.0, 1.0, Vector2(0, 1.5))
	prop("cone", pile + Vector3(-0.6, 0, 0.9), 0.0)

## a sky car that came down hard: nose in, tilted, burning, smoking
func crashed_skycar(pos: Vector3, yaw: float, rng: RandomNumberGenerator, fire_ := true) -> void:
	var car := model("res://models/panic/skycar.glb", pos + Vector3(0, 0.55, 0), yaw, 1.0, Vector2(rng.randf_range(0.18, 0.35), rng.randf_range(-0.4, 0.4)))
	if car: _fit(car, 4.2)
	box_collider(pos + Vector3(0, 0.8, 0), Vector3(2.2, 1.6, 4.0), yaw)
	prop("rubble", pos + Vector3(cos(yaw) * 1.8, 0, -sin(yaw) * 1.8), rng.randf() * TAU, 0.8)
	if fire_:
		fire(pos + Vector3(0, 1.2, 0), 1.0)
		smoke(pos + Vector3(0, 1.8, 0), 1.2, true)

## scale a model so its longest side is `size` metres, resting on its pivot
static func _fit(n: Node3D, size: float) -> void:
	var ab := AABB(); var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var a: AABB = n.global_transform.affine_inverse() * m.global_transform * m.mesh.get_aabb() if n.is_inside_tree() else m.mesh.get_aabb()
		ab = a if first else ab.merge(a); first = false
	var s := size / maxf(0.01, maxf(ab.size.x, maxf(ab.size.y, ab.size.z)))
	n.scale *= s

# ------------------------------------------------------------------ fire and smoke
static func _soft_tex() -> Texture2D:
	if _soft: return _soft
	var g := GradientTexture2D.new(); g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5); g.fill_to = Vector2(1, 0.5); g.width = 64; g.height = 64
	var gr := Gradient.new(); gr.set_color(0, Color(1, 1, 1, 1)); gr.set_color(1, Color(1, 1, 1, 0)); g.gradient = gr
	_soft = g
	return g

func fire(pos: Vector3, size := 1.0, light := true) -> void:
	var p := GPUParticles3D.new()
	p.amount = int(18 * size) + 6; p.lifetime = 0.9
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE; pm.emission_sphere_radius = 0.35 * size
	pm.direction = Vector3(0, 1, 0); pm.spread = 12.0
	pm.initial_velocity_min = 1.2 * size; pm.initial_velocity_max = 2.4 * size
	pm.gravity = Vector3(0, 1.5, 0); pm.damping_min = 0.5; pm.damping_max = 1.0
	pm.scale_min = 0.7; pm.scale_max = 1.2
	var sc := CurveTexture.new(); var cv := Curve.new(); cv.add_point(Vector2(0, 0.6)); cv.add_point(Vector2(0.3, 1.0)); cv.add_point(Vector2(1, 0.1)); sc.curve = cv
	pm.scale_curve = sc
	var ramp := GradientTexture1D.new(); var gr := Gradient.new()
	gr.offsets = PackedFloat32Array([0.0, 0.35, 0.75, 1.0])
	gr.colors = PackedColorArray([Color(1.0, 0.9, 0.45, 1), Color(1.0, 0.55, 0.12, 0.95), Color(0.85, 0.22, 0.06, 0.6), Color(0.3, 0.1, 0.05, 0)])
	ramp.gradient = gr; pm.color_ramp = ramp
	p.process_material = pm
	var q := QuadMesh.new(); q.size = Vector2(0.9, 1.2) * size
	if _fire_mat == null:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.vertex_color_use_as_albedo = true; m.albedo_texture = _soft_tex(); m.albedo_color = Color(1.6, 1.3, 1.0)
		_fire_mat = m
	q.material = _fire_mat
	if HD:
		if not _smoke_mats.has("fire_hd"):
			var fm := ShaderMaterial.new(); fm.shader = load("res://shaders/fire_particle.gdshader"); _smoke_mats["fire_hd"] = fm
		q.material = _smoke_mats["fire_hd"]
		pm.color_ramp = _fire_ramp_hd()
		p.amount = int(26 * size) + 8
		q.size = Vector2(0.8, 1.5) * size
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-2, -1, -2) * size, Vector3(4, 5, 4) * size)
	p.position = pos
	add_child(p)
	if light:
		var l := OmniLight3D.new(); l.light_color = Color(1.0, 0.55, 0.2); l.light_energy = 2.4 * size; l.omni_range = 6.0 * size
		l.position = pos + Vector3(0, 0.6, 0); l.shadow_enabled = false
		l.distance_fade_enabled = true; l.distance_fade_begin = 50.0; l.distance_fade_length = 15.0
		add_child(l)
		fires.append({ light = l, base = l.light_energy, ph = randf() * TAU })
	if HD:
		embers(pos, size)
		scorch(pos, size)
		if size >= 0.9: haze(pos + Vector3(0, 1.4 * size, 0), size)

func smoke(pos: Vector3, size := 1.0, dark := true) -> void:
	var p := GPUParticles3D.new()
	p.amount = 16; p.lifetime = 7.0; p.preprocess = 7.0
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE; pm.emission_sphere_radius = 0.4 * size
	pm.direction = Vector3(0, 1, 0); pm.spread = 8.0
	pm.initial_velocity_min = 1.6 * size; pm.initial_velocity_max = 2.4 * size
	pm.gravity = Vector3(0.6, 0.25, 0.2)
	pm.angle_min = 0; pm.angle_max = 360; pm.angular_velocity_min = -12; pm.angular_velocity_max = 12
	var sc := CurveTexture.new(); var cv := Curve.new(); cv.add_point(Vector2(0, 0.4)); cv.add_point(Vector2(1, 1.0)); sc.curve = cv
	pm.scale_curve = sc; pm.scale_min = 1.4 * size; pm.scale_max = 2.2 * size
	var ramp := GradientTexture1D.new(); var gr := Gradient.new()
	gr.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
	if dark: gr.colors = PackedColorArray([Color(0.2, 0.18, 0.17, 0), Color(0.24, 0.21, 0.2, 0.7), Color(0.55, 0.52, 0.5, 0)])
	else: gr.colors = PackedColorArray([Color(0.9, 0.88, 0.85, 0), Color(0.85, 0.83, 0.8, 0.5), Color(1, 1, 1, 0)])
	ramp.gradient = gr; pm.color_ramp = ramp
	p.process_material = pm
	var q := QuadMesh.new(); q.size = Vector2(2.4, 2.4)
	var key := "dark" if dark else "light"
	if not _smoke_mats.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES; m.vertex_color_use_as_albedo = true; m.albedo_texture = _soft_tex()
		m.billboard_keep_scale = true
		_smoke_mats[key] = m
	q.material = _smoke_mats[key]
	if HD:
		var hk := key + "_hd"
		if not _smoke_mats.has(hk):
			var sm := ShaderMaterial.new(); sm.shader = load("res://shaders/smoke_particle.gdshader")
			sm.set_shader_parameter("ember", 1.2 if dark else 0.0)
			_smoke_mats[hk] = sm
		q.material = _smoke_mats[hk]
		p.amount = 28
		if dark: gr.colors = PackedColorArray([Color(0.16, 0.14, 0.13, 0), Color(0.2, 0.18, 0.17, 0.85), Color(0.42, 0.4, 0.38, 0)])
		q.size = Vector2(2.8, 2.8)
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-12, -2, -12) * size, Vector3(24, 30, 24) * size)
	p.position = pos
	add_child(p)

static func _fire_ramp_hd() -> GradientTexture1D:
	var ramp := GradientTexture1D.new(); var gr := Gradient.new()
	gr.offsets = PackedFloat32Array([0.0, 0.2, 0.55, 0.85, 1.0])
	gr.colors = PackedColorArray([Color(1.0, 0.85, 0.45, 0.0), Color(1.0, 0.7, 0.28, 1), Color(1.0, 0.42, 0.1, 0.85), Color(0.7, 0.16, 0.04, 0.4), Color(0.2, 0.05, 0.02, 0)])
	ramp.gradient = gr
	return ramp

## glowing sparks spiralling up out of a fire
func embers(pos: Vector3, size := 1.0) -> void:
	var p := GPUParticles3D.new()
	p.amount = int(14 * size) + 4; p.lifetime = 2.6; p.preprocess = 2.0
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE; pm.emission_sphere_radius = 0.4 * size
	pm.direction = Vector3(0, 1, 0); pm.spread = 25.0
	pm.initial_velocity_min = 1.5; pm.initial_velocity_max = 3.5 * size
	pm.gravity = Vector3(0.5, 0.6, 0.2)
	pm.turbulence_enabled = true; pm.turbulence_noise_strength = 2.0; pm.turbulence_noise_scale = 3.0; pm.turbulence_influence_min = 0.1; pm.turbulence_influence_max = 0.25
	pm.scale_min = 0.6; pm.scale_max = 1.2
	var ramp := GradientTexture1D.new(); var gr := Gradient.new()
	gr.offsets = PackedFloat32Array([0.0, 0.7, 1.0])
	gr.colors = PackedColorArray([Color(1.0, 0.75, 0.35, 1), Color(1.0, 0.35, 0.08, 1), Color(0.6, 0.1, 0.02, 0)])
	ramp.gradient = gr; pm.color_ramp = ramp
	p.process_material = pm
	var q := QuadMesh.new(); q.size = Vector2(0.05, 0.05)
	if not _smoke_mats.has("ember"):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.vertex_color_use_as_albedo = true; m.albedo_texture = _soft_tex(); m.albedo_color = Color(4.0, 3.0, 2.0)
		_smoke_mats["ember"] = m
	q.material = _smoke_mats["ember"]
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-4, -1, -4) * size, Vector3(8, 10, 8) * size)
	p.position = pos
	add_child(p)

## a burnt patch on whatever the fire stands on
func scorch(pos: Vector3, size := 1.0) -> void:
	if not _smoke_mats.has("scorch_tex"):
		var g := GradientTexture2D.new(); g.fill = GradientTexture2D.FILL_RADIAL
		g.fill_from = Vector2(0.5, 0.5); g.fill_to = Vector2(1, 0.5); g.width = 128; g.height = 128
		var gr := Gradient.new()
		gr.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
		gr.colors = PackedColorArray([Color(0.02, 0.015, 0.01, 0.95), Color(0.05, 0.03, 0.02, 0.7), Color(0.1, 0.06, 0.04, 0)])
		g.gradient = gr
		_smoke_mats["scorch_tex"] = g
	var d := Decal.new()
	d.texture_albedo = _smoke_mats["scorch_tex"]
	d.size = Vector3(3.2, 4.0, 3.2) * size
	d.position = pos + Vector3(0, -0.5, 0)
	d.rotation.y = randf() * TAU
	d.cull_mask = 1
	d.distance_fade_enabled = true; d.distance_fade_begin = 50.0; d.distance_fade_length = 10.0
	add_child(d)

## shimmering heat over a big fire (screen-space refraction on a billboard)
func haze(pos: Vector3, size := 1.0) -> void:
	if not _smoke_mats.has("haze"):
		var m := ShaderMaterial.new(); m.shader = load("res://shaders/heat_haze.gdshader")
		_smoke_mats["haze"] = m
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new(); q.size = Vector2(1.8, 3.0) * size
	mi.mesh = q; mi.material_override = _smoke_mats["haze"]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos + Vector3(0, 0.8 * size, 0)
	mi.visibility_range_end = 40.0
	add_child(mi)

static func _noise_tex3d() -> Texture3D:
	if _noise3d: return _noise3d
	var nt := NoiseTexture3D.new(); nt.width = 64; nt.height = 64; nt.depth = 64; nt.seamless = true
	var fn := FastNoiseLite.new(); fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH; fn.frequency = 0.06; fn.fractal_octaves = 4
	nt.noise = fn
	_noise3d = nt
	return nt

## A big volumetric smoke column: a FogVolume plume (lit by the sun and volumetric fog) over a fire, plus
## the particle smoke and flames at its foot. `height` in metres; `size` scales the fire.
func column(pos: Vector3, size := 1.0, height := 26.0, lean := 0.18) -> void:
	fire(pos, size)
	# the big fires are the few lights worth a shadow
	if HD and not fires.is_empty(): (fires[-1].light as OmniLight3D).shadow_enabled = true
	smoke(pos + Vector3(0, 0.8 * size, 0), size * 1.2, true)
	if not HD: return
	var fv := FogVolume.new()
	fv.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	var w := maxf(5.0, height * 0.36) * maxf(0.8, size)
	fv.size = Vector3(w, height, w)
	fv.position = pos + Vector3(w * lean * 0.35, height * 0.5 - 0.5, 0)
	var m := ShaderMaterial.new(); m.shader = load("res://shaders/smoke_column.gdshader")
	m.set_shader_parameter("noise_tex", _noise_tex3d()); m.set_shader_parameter("lean", lean)
	fv.material = m
	add_child(fv)

## a low, sunlit cloud bank drifting below the islands (FogVolume ellipsoid)
func cloud_bank(pos: Vector3, size: Vector3) -> void:
	if not HD: return
	var fv := FogVolume.new()
	fv.shape = RenderingServer.FOG_VOLUME_SHAPE_ELLIPSOID
	fv.size = size; fv.position = pos
	var m := ShaderMaterial.new(); m.shader = load("res://shaders/cloud_bank.gdshader")
	m.set_shader_parameter("noise_tex", _noise_tex3d())
	fv.material = m
	add_child(fv)

## a sign hanging off one bracket, its neon stuttering
func broken_sign(text: String, pos: Vector3, yaw: float, c := Color(1.0, 0.45, 0.3), tilt := 0.25, px := 0.012) -> void:
	var n := Node3D.new(); n.position = pos; n.rotation = Vector3(0, yaw, tilt); add_child(n)
	var bm := BoxMesh.new(); bm.size = Vector3(text.length() * px * 60.0 + 0.6, 1.0, 0.12)
	var mi := MeshInstance3D.new(); mi.mesh = bm; mi.material_override = M.std(Color(0.16, 0.17, 0.2), 0.5, 0.5); n.add_child(mi)
	for s in [-1, 1]:
		var l := Label3D.new(); l.text = text; l.font_size = 96; l.pixel_size = px; l.modulate = c
		l.outline_size = 0; l.shaded = false; l.position = Vector3(0, 0, 0.07 * s); l.rotation.y = 0.0 if s > 0 else PI
		n.add_child(l)
		signs.append({ label = l, ph = randf() * 10.0, rate = randf_range(0.6, 1.6), col = c })

# ------------------------------------------------------------------ life
func _process(dt: float) -> void:
	t += dt
	var cam := get_viewport().get_camera_3d()
	if cam and cam.global_position.distance_to(center) > radius + 60.0: return
	for f in fires:
		var l: OmniLight3D = f.light
		l.light_energy = f.base * (0.75 + 0.25 * sin(t * 13.0 + f.ph) * sin(t * 7.3 + f.ph * 2.0) + 0.1 * sin(t * 31.0 + f.ph))
	for s in signs:
		var u := fmod(t * s.rate + s.ph, 4.0)
		var on := not ((u > 1.2 and u < 1.35) or (u > 1.5 and u < 1.58) or (u > 3.0 and u < 3.6))
		(s.label as Label3D).modulate = s.col if on else Color(s.col.r * 0.25, s.col.g * 0.25, s.col.b * 0.25, 1)
