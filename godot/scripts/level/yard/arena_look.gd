extends RefCounted
## Crane Bot arena look pass (built by areas/yz_arena.gd, in final coordinates, after the floors).
## Chases the Junkyard look target (art/lookdev/junkyard_look.py) on the boss stage and the foundry behind it:
##   - weathered paint-over-steel on the Crane Yard's structure (shaders/painted_steel.gdshader): rounded
##     edges, chipped paint, rust streaks and grime, instead of flat clean colours
##   - a darker, oilier, scorched stage floor
##   - the foundry's stacks become flare stacks with tall volumetric smoke columns; burning scrap heaps,
##     bales and drums fill the foundry floor and the corners; embers drift over the whole stage
##   - the floodlights become volumetric spotlights cutting through the haze
##   - hanging chains and hooks under the crane runways
## The grade (darker smoky golden hour) is the "arena" entry in systems/area_mood.gd.
## Shared pieces come from the Junkyard pass: junk_kit.gd (bevelled scrap + bales) and layout/chaos.gd (fire,
## smoke, embers, scorch, heat haze, FogVolume columns).

const K := preload("res://scripts/level/yard/yard_kit.gd")
const JK := preload("res://scripts/level/junkyard/junk_kit.gd")
const Chaos := preload("res://scripts/level/layout/chaos.gd")
const STEEL_SHADER := "res://shaders/painted_steel.gdshader"

## yard_kit material key -> [paint colour, paint metallic, paint roughness, chip, rust, streaks, hazard]
const PAINTS := {
	"yellow": [Color(0.93, 0.64, 0.1), 0.1, 0.42, 1.0, 0.55, 0.8, 0.0],
	"red": [Color(0.7, 0.17, 0.12), 0.1, 0.45, 0.9, 0.5, 0.7, 0.0],
	"cream": [Color(0.84, 0.79, 0.68), 0.05, 0.5, 0.9, 0.5, 0.8, 0.0],
	"steel": [Color(0.3, 0.31, 0.33), 0.55, 0.42, 0.6, 0.45, 0.6, 0.0],
	"dark": [Color(0.15, 0.155, 0.17), 0.45, 0.48, 0.55, 0.4, 0.5, 0.0],
	"hazard": [Color(0.93, 0.64, 0.1), 0.1, 0.45, 0.9, 0.45, 0.5, 1.0],
}

static func on() -> bool:
	return not OS.get_cmdline_user_args().has("--no-arena-look")

static func build(L) -> void:
	var r: Rect2 = L.islands.get("arena")
	var c2 := r.get_center()
	var c := Vector3(c2.x, 0, c2.y)
	var t0 := Time.get_ticks_msec()
	var n := _materials(L, Rect2(c2.x - 80, c2.y - 60, 160, 160))
	_floor(L, c)
	_fx(L, c)
	_dress(L, c)
	_lights(L, c)
	print("[arena-look] %d pieces repainted, built in %d ms" % [n, Time.get_ticks_msec() - t0])

# ------------------------------------------------------------------ materials
static var _steel := {}       # key|unit -> ShaderMaterial

static func steel_mat(key: String, unit: bool) -> ShaderMaterial:
	var k := key + ("|u" if unit else "")
	if _steel.has(k): return _steel[k]
	var p: Array = PAINTS[key]
	var m := ShaderMaterial.new(); m.shader = load(STEEL_SHADER)
	m.set_shader_parameter("paint", p[0]); m.set_shader_parameter("paint_metal", p[1]); m.set_shader_parameter("paint_rough", p[2])
	m.set_shader_parameter("chip", p[3]); m.set_shader_parameter("rust", p[4]); m.set_shader_parameter("streaks", p[5])
	m.set_shader_parameter("hazard", p[6])
	m.set_shader_parameter("unit_half", 0.5 if unit else 0.0)
	m.set_shader_parameter("pit_nrm", JK._pit_tex())
	_steel[k] = m
	return m

## Swap the yard kit's flat paints for the weathered steel shader on everything in the region (the whole
## Crane Yard north half: the Row, the arena, the foundry). Returns how many pieces changed.
static func _materials(L: Node3D, region: Rect2) -> int:
	var by_mat := {}
	for key in PAINTS: by_mat[K.mat(key)] = key
	var count := 0
	for gi in L.find_children("*", "GeometryInstance3D", true, false):
		var g := gi as GeometryInstance3D
		var m: Material = g.material_override
		if m == null or not by_mat.has(m): continue
		var gp := g.global_position
		if not region.has_point(Vector2(gp.x, gp.z)): continue
		var key: String = by_mat[m]
		if g is MultiMeshInstance3D:
			var mm: MultiMesh = (g as MultiMeshInstance3D).multimesh
			var unit := mm != null and mm.mesh is BoxMesh and (mm.mesh as BoxMesh).size.is_equal_approx(Vector3.ONE)
			g.material_override = steel_mat(key, unit)
		elif g is MeshInstance3D:
			g.material_override = steel_mat(key, false)
			var mesh: Mesh = (g as MeshInstance3D).mesh
			if mesh is BoxMesh: g.set_instance_shader_parameter("box_half", (mesh as BoxMesh).size * 0.5)
		else: continue
		count += 1
	return count

# ------------------------------------------------------------------ the stage floor
## Darker, oilier concrete on the arena and foundry floors (a copy of the Crane Yard floor material).
static func _floor(L: Node3D, c: Vector3) -> void:
	var stage := Rect2(c.x - 26, c.z - 52, 52, 72)
	var done := {}
	for mi in L.find_children("*", "MeshInstance3D", true, false):
		var g := mi as MeshInstance3D
		var sm := g.material_override as ShaderMaterial
		if sm == null or sm.shader == null or not sm.shader.resource_path.ends_with("ground.gdshader"): continue
		var gp := g.global_position
		if not stage.has_point(Vector2(gp.x, gp.z)): continue
		if not done.has(sm):
			var d := sm.duplicate() as ShaderMaterial
			var tint: Color = d.get_shader_parameter("tint") if d.get_shader_parameter("tint") != null else Color.WHITE
			d.set_shader_parameter("tint", Color(tint.r * 0.62, tint.g * 0.58, tint.b * 0.55))
			d.set_shader_parameter("oil", 1.0)
			d.set_shader_parameter("puddles", 0.7)
			d.set_shader_parameter("edge_grime", 0.85)
			d.set_shader_parameter("grime_col", Color(0.2, 0.15, 0.11))
			d.set_shader_parameter("moss", 0.0)
			done[sm] = d
		g.material_override = done[sm]
	# soot fans and scorch where the boss's magnet slams land, and around the grates
	var C: Node3D = Chaos.make(L, "arena_floor")
	C.center = c; C.radius = 90.0
	var rng := RandomNumberGenerator.new(); rng.seed = 9707
	for i in 9:
		var p := c + Vector3(rng.randf_range(-16, 16), 0.0, rng.randf_range(-14, 14))
		C.scorch(p, rng.randf_range(0.8, 1.6))

# ------------------------------------------------------------------ fire, smoke, embers
static func _fx(L: Node3D, c: Vector3) -> void:
	var C: Node3D = Chaos.make(L, "arena_fx")
	C.center = c + Vector3(0, 0, -20); C.radius = 90.0
	# the foundry's three stacks flare and pour smoke columns into the sky (they replace the old puffs)
	var y0 := -1.0
	var stacks := [Vector3(-22.0, y0, -43.0), Vector3(-17.0, y0, -46.0), Vector3(22.0, y0, -44.0)]
	for s in stacks:
		var top: Vector3 = c + s + Vector3(0, 22.6, 0)
		_drop_particles_near(L, top + Vector3(0, 0.4, 0), 2.0)
		C.column(top, 1.4, 34.0, 0.22)
	# burning scrap at the foundry and the stage's back corners
	for f in [[Vector3(-19.5, y0, -28.0), 1.3], [Vector3(21.0, y0, -30.0), 1.1], [Vector3(-3.0, y0, -44.0), 1.5],
			[Vector3(-23.5, 0.0, -14.5), 0.9], [Vector3(31.5, 0.0, 15.5), 0.8]]:
		C.fire(c + f[0] + Vector3(0, 0.9, 0), f[1])
	# a slow drift of embers over the whole stage, blown off the foundry
	_ember_field(C, c + Vector3(0, 6, -6), Vector3(52, 12, 56))
	# heat shimmer over the pour and the smelters' mouths
	for h in [Vector3(17.0, y0 + 1.0, -29.0), Vector3(-10.0, 2.0, -32.5), Vector3(13.0, 1.0, -35.0)]:
		C.haze(c + h, 1.6)

static func _drop_particles_near(L: Node3D, p: Vector3, r: float) -> void:
	for n in L.find_children("*", "CPUParticles3D", true, false):
		if (n as Node3D).global_position.distance_to(p) < r: (n as Node3D).visible = false; (n as CPUParticles3D).emitting = false

static func _ember_field(parent: Node3D, pos: Vector3, box: Vector3) -> void:
	var p := GPUParticles3D.new()
	p.amount = 260; p.lifetime = 7.0; p.preprocess = 7.0
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX; pm.emission_box_extents = box * 0.5
	pm.direction = Vector3(0.2, 1, 0.4); pm.spread = 40.0
	pm.initial_velocity_min = 0.3; pm.initial_velocity_max = 1.2
	pm.gravity = Vector3(0.5, 0.35, 0.8)
	pm.turbulence_enabled = true; pm.turbulence_noise_strength = 1.5; pm.turbulence_noise_scale = 6.0
	pm.turbulence_influence_min = 0.05; pm.turbulence_influence_max = 0.2
	pm.scale_min = 0.5; pm.scale_max = 1.4
	var ramp := GradientTexture1D.new(); var gr := Gradient.new()
	gr.offsets = PackedFloat32Array([0.0, 0.1, 0.75, 1.0])
	gr.colors = PackedColorArray([Color(1, 0.6, 0.2, 0), Color(1, 0.7, 0.3, 1), Color(1, 0.35, 0.08, 0.9), Color(0.6, 0.1, 0.02, 0)])
	ramp.gradient = gr; pm.color_ramp = ramp
	p.process_material = pm
	var q := QuadMesh.new(); q.size = Vector2(0.06, 0.06)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true; m.albedo_color = Color(4.0, 2.8, 1.8)
	q.material = m
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(-box * 0.5 - Vector3(4, 4, 4), box + Vector3(8, 14, 8))
	p.position = pos - parent.global_position
	parent.add_child(p)

# ------------------------------------------------------------------ set dressing
static func _dress(L: Node3D, c: Vector3) -> void:
	var B := JK.Batch.new()
	var rng := RandomNumberGenerator.new(); rng.seed = 4411
	var y0 := -1.0
	# scrap heaps on the foundry floor (off the patrol lanes)
	for h in [[Vector3(-19.5, y0, -28.0), 3.0, 2.4, 46], [Vector3(21.0, y0, -30.0), 2.6, 2.0, 38], [Vector3(-3.0, y0, -44.0), 3.4, 2.6, 52],
			[Vector3(-25.0, y0, -40.0), 2.4, 2.0, 30], [Vector3(24.0, y0, -40.0), 2.4, 1.8, 30]]:
		JK.pile(B, rng, c + h[0], h[1], h[2], h[3])
	# bale walls: crushed scrap waiting for the smelters
	for s in [[Vector3(-14.0, y0, -46.5), 4, 2], [Vector3(6.0, y0, -46.5), 3, 2], [Vector3(-24.5, y0, -33.0), 2, 3]]:
		var base: Vector3 = c + s[0]
		for i in s[1]:
			for k in s[2]:
				var p := base + Vector3(i * 1.55 + rng.randf_range(-0.06, 0.06), 0.62 + k * 1.22, rng.randf_range(-0.08, 0.08))
				B.add("bale", "bale", JK.xform(p, Vector3(0, rng.randf_range(-0.06, 0.06) + (k % 2) * PI / 2, 0), Vector3(1.5, 1.2, 1.4)),
					JK.PALETTE[rng.randi() % JK.PALETTE.size()])
	# drums by the stage edges (outside the fighting floor)
	for d in [Vector3(-23.6, 0, -12.6), Vector3(-23.2, 0, -11.2), Vector3(-24.0, 0, 13.2), Vector3(23.8, 0, -15.0), Vector3(23.4, 0, -16.2)]:
		B.add("drum", "scrap", JK.xform(c + d + Vector3(0, 0.45, 0), Vector3(0, rng.randf() * TAU, 0), Vector3.ONE * 0.9),
			JK.PALETTE[rng.randi() % JK.PALETTE.size()])
	# chains and hooks hanging from the crane runways (they sway nothing; visual only)
	for x in [-24.5, 24.5]:
		for z in [-12.0, -4.0, 6.0, 12.5]:
			var top := c + Vector3(x + (0.7 if x < 0 else -0.7), 12.6, z)
			var bot: Vector3 = JK.chain(B, top, rng.randf_range(3.0, 6.5))
			B.add("gear", "scrap", JK.xform(bot + Vector3(0, -0.2, 0), Vector3(PI / 2, 0, 0), Vector3.ONE * 0.45), Color(0.3, 0.3, 0.32))
	# litter on the foundry floor
	JK.litter(B, rng, Rect2(c.x - 24, c.z - 48, 48, 22), y0, 90)
	var host := Node3D.new(); host.name = "ArenaDress"; L.add_child(host)
	B.flush(host, JK)
	for mi in host.get_children():
		(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mi.visibility_range_end = 140.0

# ------------------------------------------------------------------ lights
## The floodlights become shadowed volumetric spots raking the stage; the foundry's molten glow lights the haze.
static func _lights(L: Node3D, c: Vector3) -> void:
	var stage := Rect2(c.x - 30, c.z - 55, 60, 75)
	for l in L.find_children("*", "OmniLight3D", true, false):
		var o := l as OmniLight3D
		var p := o.global_position
		if not stage.has_point(Vector2(p.x, p.z)): continue
		var warm := o.light_color.g < 0.6
		o.light_volumetric_fog_energy = 2.5 if warm else 0.8
		if warm and p.z < c.z - 25: o.light_energy *= 1.4; o.omni_range = minf(o.omni_range * 1.3, 16.0)
	for s in [-1.0, 1.0]:
		var base := c + Vector3(17.0 * s, 9.5, -16.2)
		var sp := SpotLight3D.new()
		sp.light_color = Color(1.0, 0.86, 0.66); sp.light_energy = 6.0; sp.spot_range = 34.0; sp.spot_angle = 26.0
		sp.spot_attenuation = 0.9; sp.light_volumetric_fog_energy = 3.0
		sp.shadow_enabled = s > 0.0          # one shadowed beam is enough
		L.add_child(sp)
		sp.global_position = base
		sp.look_at(c + Vector3(-5.0 * s, 0, 6.0), Vector3.UP)
