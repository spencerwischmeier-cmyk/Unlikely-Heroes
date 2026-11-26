extends RefCounted
## The distant world around Skyharbor: the sky city's towers (tiered spires in multimeshes plus clusters of
## Meshy towers on floating districts), a sea of clouds below with drifting cloud banks, sun shafts, airship
## traffic lanes and flocks of birds. Nothing here collides; everything sits > 40 m from the playable islands
## except the birds, which wheel high over the docks and the plaza.

const M := preload("res://scripts/mats.gd")
const Anim := preload("res://scripts/level/docks/anim.gd")

const CLOUD_SEA := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled;
uniform vec3 lit : source_color = vec3(1.0, 0.9, 0.78);
uniform vec3 shade : source_color = vec3(0.6, 0.64, 0.8);
uniform vec3 haze : source_color = vec3(0.95, 0.86, 0.78);
uniform float scale = 0.004;
uniform vec2 wind = vec2(0.004, 0.0015);
varying vec3 wpos;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) { float v = 0.0; float a = 0.5; for (int i = 0; i < 5; i++) { v += a * noise(p); p = p * 2.07 + 3.1; a *= 0.5; } return v; }
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = wpos.xz * scale + TIME * wind;
	float n = fbm(p);
	float n2 = fbm(p * 2.3 + vec2(4.0, 1.0) - TIME * wind * 0.7);
	float cover = smoothstep(0.38, 0.72, n * 0.75 + n2 * 0.35);
	float light = smoothstep(0.3, 0.9, n2) * 0.6 + 0.4;
	vec3 c = mix(shade, lit, light);
	float d = length(wpos.xz - CAMERA_POSITION_WORLD.xz);
	c = mix(c, haze, smoothstep(250.0, 1100.0, d));
	ALBEDO = c;
	ALPHA = cover * (0.35 + 0.6 * smoothstep(0.0, 0.6, cover)) * (1.0 - smoothstep(1300.0, 1900.0, d));
}
"""

const PUFF := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
uniform vec3 lit : source_color = vec3(1.0, 0.92, 0.8);
uniform vec3 shade : source_color = vec3(0.62, 0.66, 0.82);
uniform float opacity = 0.85;
varying float seed;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) { float v = 0.0; float a = 0.5; for (int i = 0; i < 4; i++) { v += a * noise(p); p = p * 2.1 + 1.7; a *= 0.5; } return v; }
void vertex() {
	// camera-facing billboard that keeps the instance scale
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0, 0, 0), vec4(0, length(MODEL_MATRIX[1].xyz), 0, 0), vec4(0, 0, 1, 0), vec4(0, 0, 0, 1));
	seed = INSTANCE_CUSTOM.x;
}
void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float n = fbm(UV * 3.0 + seed * 17.0 + TIME * 0.01);
	float blob = 1.0 - smoothstep(0.35, 1.0, length(uv * vec2(1.0, 1.4)) + (n - 0.5) * 0.7);
	float top = clamp(0.5 - uv.y * 0.6 + (n - 0.5) * 0.4, 0.0, 1.0);
	ALBEDO = mix(shade, lit, top);
	ALPHA = blob * opacity * COLOR.a;
}
"""

const SHAFT := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, fog_disabled;
uniform vec3 tint : source_color = vec3(1.0, 0.82, 0.55);
uniform float strength = 0.12;
void fragment() {
	float edge = pow(abs(dot(NORMAL, VIEW)), 2.5);
	float along = smoothstep(0.0, 0.25, UV.y) * (1.0 - smoothstep(0.55, 1.0, UV.y));
	float flick = 0.8 + 0.2 * sin(TIME * 0.3 + UV.x * 6.2831);
	ALBEDO = tint * edge * along * strength * flick;
}
"""

const BIRD := """
shader_type spatial;
render_mode cull_disabled;
uniform vec3 col : source_color = vec3(0.16, 0.15, 0.17);
void vertex() {
	float side = abs(VERTEX.x);
	float ph = INSTANCE_CUSTOM.x * 6.2831;
	float sp = 9.0 + INSTANCE_CUSTOM.y * 4.0;
	VERTEX.y += sin(TIME * sp + ph) * side * 0.9;
	VERTEX.y += sin(TIME * 0.7 + ph) * 0.6;
}
void fragment() { ALBEDO = col; ROUGHNESS = 0.9; }
"""

static func _shader(code: String) -> ShaderMaterial:
	var sh := Shader.new(); sh.code = code
	var m := ShaderMaterial.new(); m.shader = sh
	return m

static func build(L: Node3D, A: Node3D) -> void:
	var root := Node3D.new(); root.name = "SkyWorld"; L.add_child(root)
	_towers(root)
	_districts(root, A)
	_clouds(root)
	_shafts(root)
	_lanes(root, A)
	_birds(root, A)

## Tiered city towers far around the islands, all in a handful of multimeshes.
static func _towers(root: Node3D) -> void:
	var rng := RandomNumberGenerator.new(); rng.seed = 7
	var cyl := CylinderMesh.new(); cyl.top_radius = 1.0; cyl.bottom_radius = 1.0; cyl.height = 1.0; cyl.radial_segments = 16; cyl.rings = 1
	var taper := CylinderMesh.new(); taper.top_radius = 0.8; taper.bottom_radius = 1.0; taper.height = 1.0; taper.radial_segments = 16; taper.rings = 1
	var dome := SphereMesh.new(); dome.radius = 1.0; dome.height = 1.0; dome.is_hemisphere = true; dome.radial_segments = 16; dome.rings = 6
	var band := TorusMesh.new(); band.inner_radius = 0.92; band.outer_radius = 1.0; band.rings = 16; band.ring_segments = 4
	var spire := CylinderMesh.new(); spire.top_radius = 0.0; spire.bottom_radius = 1.0; spire.height = 1.0; spire.radial_segments = 8; spire.rings = 1
	var body_mat := M.std(Color.WHITE, 0.5, 0.4); body_mat.vertex_color_use_as_albedo = true
	var dome_mat := M.std(Color(0.6, 0.85, 1.0), 0.3, 0.1); dome_mat.vertex_color_use_as_albedo = true
	var win := M.glow(Color(1.0, 0.82, 0.5), 1.6)
	var tints := [Color(0.72, 0.81, 0.88), Color(0.62, 0.77, 0.85), Color(0.84, 0.89, 0.92), Color(0.9, 0.82, 0.72), Color(0.78, 0.74, 0.8)]
	var bodies := []; var domes := []; var bands := []; var spires := []; var tapers := []
	for i in 150:
		var ang := rng.randf() * TAU
		var dist := 190.0 + pow(rng.randf(), 0.8) * 620.0
		var p := Vector3(sin(ang) * dist, 0, -cos(ang) * dist - 10)
		var r := rng.randf_range(5, 12) * (0.8 + dist / 400.0)
		var top := rng.randf_range(-30, 45) + dist * 0.045
		var bottom := -280.0
		var c: Color = tints[i % tints.size()]
		# shaft, then one or two setbacks, a dome and sometimes a spire
		var tiers := rng.randi_range(1, 3)
		var h_total := top - bottom
		var cur_b := bottom; var cur_r := r
		for k in tiers:
			var h := h_total * (0.7 if k == 0 else 0.3 / (tiers - 1)) if tiers > 1 else h_total
			var tr := Transform3D(Basis().scaled(Vector3(cur_r, h, cur_r)), Vector3(p.x, cur_b + h / 2, p.z))
			(tapers if k > 0 else bodies).append([tr, c.darkened(0.04 * k)])
			bands.append([Transform3D(Basis().scaled(Vector3(cur_r * 1.12, cur_r * 0.6, cur_r * 1.12)), Vector3(p.x, cur_b + h - rng.randf_range(2, 6), p.z)), Color.WHITE])
			cur_b += h; cur_r *= 0.72
		domes.append([Transform3D(Basis().scaled(Vector3(cur_r / 0.72, cur_r * 0.9, cur_r / 0.72)), Vector3(p.x, cur_b, p.z)), Color(0.6, 0.85, 1.0) if i % 4 else Color(1.0, 0.8, 0.5)])
		if rng.randf() < 0.45:
			var sh := r * rng.randf_range(1.5, 3.0)
			spires.append([Transform3D(Basis().scaled(Vector3(r * 0.12, sh, r * 0.12)), Vector3(p.x, cur_b + r * 0.4 + sh / 2, p.z)), c])
	_mm(root, cyl, body_mat, bodies)
	_mm(root, taper, body_mat, tapers)
	_mm(root, dome, dome_mat, domes)
	_mm(root, band, win, bands)
	_mm(root, spire, body_mat, spires)

static func _mm(root: Node3D, mesh: Mesh, mat: Material, items: Array, custom := false) -> MultiMeshInstance3D:
	var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D; mm.use_colors = true; mm.use_custom_data = custom
	mm.mesh = mesh; mm.instance_count = items.size()
	for i in items.size():
		mm.set_instance_transform(i, items[i][0]); mm.set_instance_color(i, items[i][1])
		if custom: mm.set_instance_custom_data(i, items[i][2])
	var mi := MultiMeshInstance3D.new(); mi.multimesh = mm; mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return mi

## Floating districts: rocky disks with clusters of tall towers, much nearer than the city ring.
static func _districts(root: Node3D, A: Node3D) -> void:
	var rng := RandomNumberGenerator.new(); rng.seed = 21
	var rock := M.std(Color(0.42, 0.4, 0.46), 0.1, 0.9)
	var deck := M.std(Color(0.82, 0.84, 0.86), 0.4, 0.5)
	var glow := M.glow(Color(0.3, 0.9, 1.0), 3.0)
	# [centre, radius, tower count]
	var ds := [[Vector3(205, -6, 10), 26.0, 5], [Vector3(170, 4, -120), 20.0, 4], [Vector3(60, -12, 175), 22.0, 4],
		[Vector3(-150, 0, -150), 24.0, 5], [Vector3(-190, -10, 60), 20.0, 4], [Vector3(110, 14, -210), 28.0, 6],
		[Vector3(260, -24, 120), 30.0, 5], [Vector3(-60, 8, -230), 22.0, 4]]
	for d in ds:
		var c: Vector3 = d[0]; var r: float = d[1]
		var top := CylinderMesh.new(); top.top_radius = r; top.bottom_radius = r * 0.92; top.height = 3.0; top.radial_segments = 20
		var mi := MeshInstance3D.new(); mi.mesh = top; mi.material_override = deck; mi.position = c - Vector3(0, 1.5, 0); root.add_child(mi)
		var under := CylinderMesh.new(); under.top_radius = r * 0.92; under.bottom_radius = r * 0.12; under.height = r * 1.6; under.radial_segments = 9
		var um := MeshInstance3D.new(); um.mesh = under; um.material_override = rock; um.position = c - Vector3(0, 3.0 + r * 0.8, 0); root.add_child(um)
		var gl := SphereMesh.new(); gl.radius = r * 0.15; gl.height = r * 0.3
		var gm := MeshInstance3D.new(); gm.mesh = gl; gm.material_override = glow; gm.position = c - Vector3(0, 3.0 + r * 1.6, 0); root.add_child(gm)
		for k in int(d[2]):
			var a := rng.randf() * TAU; var rr := rng.randf_range(0.0, r * 0.65)
			var p := c + Vector3(cos(a) * rr, 0, sin(a) * rr)
			DocksDressing.place(root, "sky_tower", p, rng.randf() * TAU, rng.randf_range(28.0, 62.0), false)
		# a beacon on the rim
		var bm := SphereMesh.new(); bm.radius = 0.8; bm.height = 1.6
		var bmat := M.glow(Color(1, 0.3, 0.2), 8.0)
		var bmi := MeshInstance3D.new(); bmi.mesh = bm; bmi.material_override = bmat; bmi.position = c + Vector3(r * 0.9, 1.0, 0); root.add_child(bmi)
		A.blinkers.append({ mat = bmat, on = 0.2, period = 2.2, ph = rng.randf(), peak = 10.0, low = 0.3 })

## A sea of clouds under everything, banks of cloud puffs drifting between the islands' feet and a few high wisps.
static func _clouds(root: Node3D) -> void:
	var sea := PlaneMesh.new(); sea.size = Vector2(4000, 4000); sea.subdivide_width = 0; sea.subdivide_depth = 0
	for lay in [[-62.0, 0.004, 1.0], [-95.0, 0.0028, 0.85]]:
		var m := _shader(CLOUD_SEA)
		m.set_shader_parameter("scale", lay[1])
		var mi := MeshInstance3D.new(); mi.mesh = sea; mi.material_override = m; mi.position = Vector3(30, lay[0], 0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	var q := QuadMesh.new(); q.size = Vector2(1, 1)
	var pm := _shader(PUFF)
	var rng := RandomNumberGenerator.new(); rng.seed = 99
	var items := []
	# low banks: rings of big puffs around and under the islands, below the walking decks
	for i in 220:
		var a := rng.randf() * TAU
		var dist := rng.randf_range(60.0, 420.0)
		var p := Vector3(25 + cos(a) * dist, rng.randf_range(-58.0, -18.0) - dist * 0.03, -5 + sin(a) * dist)
		var s := rng.randf_range(22.0, 60.0) * (0.7 + dist / 400.0)
		for k in rng.randi_range(2, 4):
			var o := Vector3(rng.randf_range(-1, 1) * s * 0.6, rng.randf_range(-0.15, 0.3) * s, rng.randf_range(-1, 1) * s * 0.6)
			var ss := s * rng.randf_range(0.6, 1.1)
			items.append([Transform3D(Basis().scaled(Vector3(ss, ss * 0.6, 1)), p + o), Color(1, 1, 1, rng.randf_range(0.6, 1.0)), Color(rng.randf(), 0, 0, 0)])
	# high thin wisps far out
	for i in 40:
		var a := rng.randf() * TAU
		var dist := rng.randf_range(250.0, 600.0)
		var p := Vector3(25 + cos(a) * dist, rng.randf_range(40.0, 110.0), -5 + sin(a) * dist)
		var s := rng.randf_range(50.0, 110.0)
		items.append([Transform3D(Basis().scaled(Vector3(s, s * 0.22, 1)), p), Color(1, 1, 1, 0.45), Color(rng.randf(), 0, 0, 0)])
	_mm(root, q, pm, items, true)

## Long soft beams of sunlight slanting down through the cloud gaps (additive cylinders along the sun).
static func _shafts(root: Node3D) -> void:
	var sun_dir := Basis.from_euler(Vector3(deg_to_rad(-30), deg_to_rad(150), 0)) * Vector3(0, 0, -1)
	var cm := CylinderMesh.new(); cm.top_radius = 1.0; cm.bottom_radius = 1.0; cm.height = 1.0; cm.radial_segments = 16; cm.rings = 1
	cm.cap_top = false; cm.cap_bottom = false
	var m := _shader(SHAFT)
	var rng := RandomNumberGenerator.new(); rng.seed = 5
	var spots := [Vector3(150, -30, -60), Vector3(-120, -35, 40), Vector3(90, -40, 140), Vector3(-60, -40, -160),
		Vector3(200, -45, 60), Vector3(-170, -30, -60), Vector3(40, -50, -230), Vector3(110, -38, 30)]
	for s in spots:
		var len := rng.randf_range(160.0, 260.0)
		var r := rng.randf_range(6.0, 16.0)
		var mi := MeshInstance3D.new(); mi.mesh = cm; mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		# the cylinder's axis (local y) along the sun direction, the beam's lower end at the spot
		var up := -sun_dir
		var x := up.cross(Vector3.FORWARD).normalized(); var z := x.cross(up)
		mi.transform = Transform3D(Basis(x * r, up * len, z * r), s + up * len * 0.5)

## Airship traffic: lanes of ships gliding past far out, each looping end to end.
static func _lanes(root: Node3D, A: Node3D) -> void:
	var rng := RandomNumberGenerator.new(); rng.seed = 13
	var lanes := [[Vector3(-400, 38, -170), Vector3(500, 30, -150), 5, 9.0], [Vector3(480, 20, 170), Vector3(-380, 26, 210), 4, 8.0],
		[Vector3(220, 55, 420), Vector3(240, 48, -420), 4, 10.0], [Vector3(-230, 15, -380), Vector3(-260, 22, 380), 3, 7.0],
		[Vector3(-500, 70, 20), Vector3(500, 75, -60), 3, 12.0]]
	var lamp := M.glow(Color(1, 0.75, 0.4), 6.0)
	var red := M.glow(Color(1, 0.25, 0.2), 8.0)
	A.blinkers.append({ mat = red, on = 0.25, period = 1.5, ph = 0.0, peak = 9.0, low = 0.2 })
	for ln in lanes:
		var a: Vector3 = ln[0]; var b: Vector3 = ln[1]
		for k in int(ln[2]):
			var n := Node3D.new(); root.add_child(n)
			var big := rng.randf() < 0.3
			var model := "freighter" if big else "airship"
			var h := rng.randf_range(14.0, 22.0) if big else rng.randf_range(5.0, 10.0)
			var ship := DocksDressing.place(n, model, Vector3.ZERO, 0.0, h, false)
			if ship:
				ship.look_at_from_position(Vector3.ZERO, b - a, Vector3.UP)
				ship.rotate_object_local(Vector3.UP, PI / 2 if big else PI)
			for s in [-1, 1]:
				var lm := SphereMesh.new(); lm.radius = h * 0.04; lm.height = h * 0.08
				var mi := MeshInstance3D.new(); mi.mesh = lm; mi.material_override = lamp if s < 0 else red
				mi.position = Vector3(0, -h * 0.35, 0) + (b - a).normalized().cross(Vector3.UP) * s * h * 0.3; n.add_child(mi)
			A.lanes.append({ node = n, a = a, b = b, len = a.distance_to(b), speed = ln[3] * rng.randf_range(0.8, 1.2),
				u = (k + rng.randf() * 0.6) / float(ln[2]), bob = rng.randf() * TAU })

## Flocks of birds wheeling over the islands (flapping in the shader).
static func _birds(root: Node3D, A: Node3D) -> void:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# a tiny gull: body wedge and two swept wings (x = span)
	var v := [Vector3(0, 0, 0.35), Vector3(-0.08, 0, -0.3), Vector3(0.08, 0, -0.3),
		Vector3(0, 0.02, 0.1), Vector3(-0.75, 0.05, -0.15), Vector3(0, 0.02, -0.12),
		Vector3(0, 0.02, 0.1), Vector3(0, 0.02, -0.12), Vector3(0.75, 0.05, -0.15)]
	for p in v: st.set_normal(Vector3.UP); st.add_vertex(p)
	var bird := st.commit()
	var mat := _shader(BIRD)
	var rng := RandomNumberGenerator.new(); rng.seed = 31
	# [centre, radii, height wobble, angular speed, count]
	var fl := [[Vector3(40, 26, 10), Vector2(45, 30), 3.0, 0.07, 12], [Vector3(-10, 34, -40), Vector2(60, 40), 4.0, -0.05, 9],
		[Vector3(-30, 22, 60), Vector2(35, 45), 3.0, 0.08, 10], [Vector3(95, 30, 30), Vector2(40, 28), 2.5, -0.09, 14],
		[Vector3(70, 18, -60), Vector2(30, 30), 2.0, 0.1, 8], [Vector3(0, 60, 0), Vector2(160, 140), 6.0, 0.03, 16]]
	for f in fl:
		var n := Node3D.new(); root.add_child(n)
		var items := []
		for k in int(f[4]):
			var o := Vector3(rng.randf_range(-6, 6), rng.randf_range(-1.5, 1.5), rng.randf_range(-6, 6) - k * 0.4)
			var s := rng.randf_range(0.8, 1.3)
			items.append([Transform3D(Basis().scaled(Vector3.ONE * s), o), Color.WHITE, Color(rng.randf(), rng.randf(), 0, 0)])
		var mm := _mm(n, bird, mat, items, true)
		mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		A.flocks.append({ node = n, c = f[0], r = f[1], h = f[2], w = f[3], ph = rng.randf() * TAU })
		A.horns.append({ node = n, every = 26.0, t = rng.randf_range(4.0, 20.0), sound = "docks_birds", db = -8.0, near = 45.0 })
