extends RefCounted
## Props built for the cutscenes (all procedural, chunky and bevel-free but layered): the coffee
## maker that clocks in, the growling toaster, the crane-cab wreck radio, Vesk's old hauler, the
## hologram beam, tiny hard hats for bots, and Grudd's office for the outro stinger.

const M := preload("res://scripts/mats.gd")

static func mesh(parent: Node3D, m: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new(); mi.mesh = m; mi.material_override = mat; mi.position = pos; mi.rotation = rot
	parent.add_child(mi); return mi

static func box(parent: Node3D, size: Vector3, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new(); b.size = size; return mesh(parent, b, mat, pos, rot)

static func cyl(parent: Node3D, r: float, h: float, mat: Material, pos: Vector3, rot := Vector3.ZERO, r2 := -1.0, seg := 20) -> MeshInstance3D:
	var c := CylinderMesh.new(); c.top_radius = r; c.bottom_radius = r if r2 < 0.0 else r2; c.height = h; c.radial_segments = seg
	return mesh(parent, c, mat, pos, rot)

static func sphere(parent: Node3D, r: float, mat: Material, pos: Vector3, hemi := false) -> MeshInstance3D:
	var s := SphereMesh.new(); s.radius = r; s.height = r * (1.0 if hemi else 2.0); s.is_hemisphere = hemi
	return mesh(parent, s, mat, pos)

static func label(parent: Node3D, text: String, pos: Vector3, size := 64, color := Color.WHITE, px := 0.005, rot := Vector3.ZERO) -> Label3D:
	var l := Label3D.new(); l.text = text; l.font_size = size; l.pixel_size = px; l.modulate = color
	l.position = pos; l.rotation = rot; l.outline_size = 0; l.shaded = true
	parent.add_child(l); return l

static func coffee_maker() -> Node3D:
	var n := Node3D.new(); n.name = "CoffeeMaker"
	var body := M.std(Color(0.2, 0.42, 0.45), 0.6, 0.35)
	var dark := M.std(Color(0.12, 0.13, 0.15), 0.5, 0.5)
	box(n, Vector3(0.26, 0.06, 0.22), dark, Vector3(0, 0.03, 0))
	box(n, Vector3(0.26, 0.34, 0.09), body, Vector3(0, 0.2, -0.07))
	box(n, Vector3(0.26, 0.07, 0.22), body, Vector3(0, 0.36, 0))
	var glass := M.std(Color(0.5, 0.6, 0.65), 0.1, 0.05); glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; glass.albedo_color.a = 0.45
	cyl(n, 0.075, 0.15, glass, Vector3(0, 0.14, 0.04))
	cyl(n, 0.07, 0.07, M.std(Color(0.22, 0.12, 0.06), 0, 0.3), Vector3(0, 0.1, 0.04))
	var eye := M.glow(Color(0.35, 0.9, 1.0), 2.5)
	n.set_meta("eye", eye)
	sphere(n, 0.025, eye, Vector3(-0.06, 0.3, -0.02))
	sphere(n, 0.025, eye, Vector3(0.06, 0.3, -0.02))
	var card := box(n, Vector3(0.11, 0.15, 0.004), M.std(Color(0.96, 0.93, 0.82), 0, 0.8), Vector3(0, 0.33, -0.07))
	card.name = "Card"
	var stamp := Node3D.new(); stamp.name = "Stamp"; stamp.position = Vector3(0, 0.46, 0.0); n.add_child(stamp)
	box(stamp, Vector3(0.05, 0.08, 0.05), dark, Vector3(0, 0, 0))
	var hat := hard_hat(0.1); hat.name = "Hat"; hat.position = Vector3(0, 0.4, 0); hat.scale = Vector3.ONE * 0.001; n.add_child(hat)
	return n

## A tiny yellow hard hat (radius r) for bots that just clocked in.
static func hard_hat(r: float) -> Node3D:
	var hat := Node3D.new()
	var yel := M.std(Color(1, 0.78, 0.1), 0.1, 0.35)
	sphere(hat, r, yel, Vector3.ZERO, true)
	cyl(hat, r * 1.3, r * 0.12, yel, Vector3(0, r * 0.05, r * 0.2))
	box(hat, Vector3(r * 0.25, r * 0.15, r * 1.6), yel, Vector3(0, r * 0.9, 0))
	return hat

static func toaster() -> Node3D:
	var n := Node3D.new(); n.name = "Toaster"
	var chrome := M.std(Color(0.8, 0.82, 0.85), 0.95, 0.2)
	box(n, Vector3(0.28, 0.18, 0.16), chrome, Vector3(0, 0.09, 0))
	box(n, Vector3(0.02, 0.04, 0.04), M.std(Color(0.1, 0.1, 0.1), 0, 0.5), Vector3(0.15, 0.12, 0))
	var toast := Node3D.new(); toast.name = "Toast"; n.add_child(toast)
	for x in [-0.05, 0.05]:
		box(toast, Vector3(0.02, 0.12, 0.11), M.std(Color(0.72, 0.45, 0.2), 0, 0.9), Vector3(x, 0.14, 0))
	var eye := M.glow(Color(1, 0.2, 0.1), 0.0)
	n.set_meta("eye", eye)
	box(n, Vector3(0.2, 0.02, 0.005), eye, Vector3(0, 0.1, 0.081))
	return n

static func radio() -> Node3D:
	var n := Node3D.new(); n.name = "WreckRadio"
	var rust := M.std(Color(0.5, 0.33, 0.22), 0.6, 0.6)
	var dark := M.std(Color(0.16, 0.17, 0.2), 0.7, 0.4)
	var yel := M.std(Color(0.95, 0.7, 0.15), 0.5, 0.4)
	box(n, Vector3(2.4, 1.6, 2.0), yel, Vector3(0, 0.6, 0), Vector3(0.15, 0.3, 0.35))
	box(n, Vector3(1.6, 0.9, 0.08), M.std(Color(0.3, 0.4, 0.5), 0.1, 0.1), Vector3(0.1, 0.9, 1.0), Vector3(0.15, 0.3, 0.35))
	box(n, Vector3(3.5, 0.35, 0.35), rust, Vector3(-1.6, 0.25, 1.2), Vector3(0, 0.7, 0.1))
	for i in 4: box(n, Vector3(0.3, 0.6, 0.02), M.std(Color(0.08, 0.08, 0.09)), Vector3(-0.6 + i * 0.4, 0.5, 1.02), Vector3(0.15, 0.3, 0.9))
	var horn := Node3D.new(); horn.name = "Horn"; horn.position = Vector3(0.9, 1.25, 1.1); horn.rotation = Vector3(-0.3, 0.4, 0); n.add_child(horn)
	cyl(horn, 0.32, 0.55, dark, Vector3(0, 0, 0.25), Vector3(PI / 2, 0, 0), 0.08)
	var lamp := M.glow(Color(1, 0.15, 0.1), 0.5)
	n.set_meta("lamp", lamp)
	sphere(n, 0.12, lamp, Vector3(0.4, 1.55, 0.8))
	var l := OmniLight3D.new(); l.light_color = Color(1, 0.2, 0.1); l.light_energy = 0.0; l.omni_range = 5; l.position = Vector3(0.4, 1.8, 1.0)
	n.add_child(l); n.set_meta("light", l)
	return n

static func ship() -> Node3D:
	# Vesk's old hauler: stubby, patched and loud
	var n := Node3D.new(); n.name = "Hauler"
	var hull := M.std(Color(0.93, 0.5, 0.18), 0.5, 0.4)
	var teal := M.std(Color(0.2, 0.55, 0.58), 0.6, 0.35)
	var dark := M.std(Color(0.18, 0.2, 0.24), 0.7, 0.4)
	var glass := M.std(Color(0.4, 0.75, 0.95), 0.2, 0.05)
	var body := Node3D.new(); body.name = "Body"; n.add_child(body)
	var cap := CapsuleMesh.new(); cap.radius = 1.3; cap.height = 6.5
	mesh(body, cap, hull, Vector3(0, 2.0, 0), Vector3(PI / 2, 0, 0))
	sphere(body, 0.95, glass, Vector3(0, 2.75, 1.9))
	box(body, Vector3(7.2, 0.25, 2.0), teal, Vector3(0, 1.8, -0.6))
	box(body, Vector3(0.25, 1.6, 1.4), teal, Vector3(0, 3.6, -2.4), Vector3(-0.3, 0, 0))
	box(body, Vector3(1.2, 0.8, 0.9), M.std(Color(0.7, 0.72, 0.75), 0.8, 0.3), Vector3(0.9, 2.9, -0.8))
	label(body, "V'S HAULING\nNO RIDES", Vector3(1.32, 2.0, 0.4), 48, Color(0.15, 0.12, 0.1), 0.006, Vector3(0, PI / 2, 0))
	for x in [-2.6, 2.6]:
		cyl(body, 0.45, 1.8, dark, Vector3(x, 1.8, -1.0), Vector3(PI / 2, 0, 0))
		var g := M.glow(Color(0.4, 0.9, 1.0), 0.0)
		cyl(body, 0.36, 0.05, g, Vector3(x, 1.8, -1.92), Vector3(PI / 2, 0, 0))
		n.set_meta("jet%d" % (0 if x < 0 else 1), g)
	for p in [Vector3(-1.1, 0.5, 1.6), Vector3(1.1, 0.5, 1.6), Vector3(0, 0.5, -2.2)]:
		cyl(body, 0.08, 1.0, dark, p)
		cyl(body, 0.25, 0.08, dark, p - Vector3(0, 0.5, 0))
	var l := OmniLight3D.new(); l.light_color = Color(0.4, 0.9, 1.0); l.light_energy = 0.0; l.omni_range = 8; l.position = Vector3(0, 1.6, -2.5)
	body.add_child(l); n.set_meta("light", l)
	return n

static func ship_jets(s: Node3D, e: float) -> void:
	for k in ["jet0", "jet1"]: (s.get_meta(k) as StandardMaterial3D).emission_energy_multiplier = e
	(s.get_meta("light") as OmniLight3D).light_energy = e * 0.8

## The broadcast beam: a soft additive cone from the dish up to the hologram, plus a base ring.
static func holo_beam(height: float, r_top: float) -> Node3D:
	var n := Node3D.new(); n.name = "HoloBeam"
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD; mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(1, 0.5, 0.15, 0.12); mat.no_depth_test = false
	var c := cyl(n, r_top, height, mat, Vector3(0, height * 0.5, 0), Vector3.ZERO, 0.25, 32)
	c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.set_meta("mat", mat)
	var rm := TorusMesh.new(); rm.inner_radius = r_top * 0.92; rm.outer_radius = r_top; rm.rings = 48
	var ring := mesh(n, rm, M.glow(Color(1, 0.5, 0.15), 3.0), Vector3(0, height, 0))
	ring.scale = Vector3(1, 0.2, 1)
	var l := OmniLight3D.new(); l.light_color = Color(1, 0.5, 0.18); l.light_energy = 3.0; l.omni_range = 12; l.position = Vector3(0, height * 0.6, 0)
	n.add_child(l)
	return n

## Grudd's office (the outro stinger): no windows and a great many posters. Origin at floor centre,
## Grudd's desk faces +Z. Returns the room; meta "desk_pos", "screen_mat", "lamp".
static func office() -> Node3D:
	var n := Node3D.new(); n.name = "GruddOffice"
	var wall := M.std(Color(0.3, 0.27, 0.25), 0.2, 0.8)
	var floor_m := M.std(Color(0.2, 0.19, 0.2), 0.3, 0.6)
	var trim := M.std(Color(0.96, 0.72, 0.12), 0.4, 0.4)
	var dark := M.std(Color(0.12, 0.12, 0.14), 0.7, 0.4)
	var wood := M.std(Color(0.4, 0.25, 0.15), 0.0, 0.6)
	var W := 14.0; var D := 12.0; var H := 7.0
	box(n, Vector3(W, 0.3, D), floor_m, Vector3(0, -0.15, 0))
	box(n, Vector3(W, 0.3, D), wall, Vector3(0, H + 0.15, 0))
	box(n, Vector3(W, H, 0.3), wall, Vector3(0, H * 0.5, -D * 0.5))
	box(n, Vector3(W, H, 0.3), wall, Vector3(0, H * 0.5, D * 0.5))
	box(n, Vector3(0.3, H, D), wall, Vector3(-W * 0.5, H * 0.5, 0))
	box(n, Vector3(0.3, H, D), wall, Vector3(W * 0.5, H * 0.5, 0))
	for z in [-D * 0.5 + 0.2]:
		box(n, Vector3(W, 0.25, 0.1), trim, Vector3(0, 1.2, z))
		for i in 14: box(n, Vector3(0.3, 0.25, 0.12), dark, Vector3(-W * 0.5 + 0.5 + i * 1.0, 1.2, z), Vector3(0, 0, 0.6))
	# pipes along the ceiling
	for x in [-4.0, -3.4, 4.5]: cyl(n, 0.16, D, M.std(Color(0.55, 0.32, 0.2), 0.6, 0.5), Vector3(x, H - 0.5, 0), Vector3(PI / 2, 0, 0))
	# desk and a huge chair
	var desk := Node3D.new(); desk.position = Vector3(0, 0, -2.5); n.add_child(desk)
	box(desk, Vector3(5.0, 0.25, 2.2), wood, Vector3(0, 1.55, 0))
	box(desk, Vector3(4.8, 1.4, 0.15), wood, Vector3(0, 0.75, 1.0))
	for s in [-1, 1]: box(desk, Vector3(0.9, 1.45, 2.0), wood, Vector3(2.0 * s, 0.72, 0))
	box(desk, Vector3(1.6, 0.06, 0.4), M.std(Color(0.95, 0.75, 0.3), 0.8, 0.3), Vector3(0, 1.72, 0.9))
	label(desk, "THE FOREMAN", Vector3(0, 1.72, 1.11), 56, Color(0.15, 0.1, 0.05), 0.005)
	# in/out trays, a stamp, a mug that says WORLD'S BEST BOSS
	for x in [-1.6, -1.0]: box(desk, Vector3(0.5, 0.12, 0.4), dark, Vector3(x, 1.75, 0.2))
	for i in 6: box(desk, Vector3(0.42, 0.02, 0.32), M.std(Color(0.95, 0.93, 0.85)), Vector3(-1.6, 1.8 + i * 0.025, 0.2))
	cyl(desk, 0.15, 0.3, M.std(Color(0.9, 0.9, 0.9), 0.0, 0.3), Vector3(1.5, 1.82, 0.3))
	label(desk, "WORLD'S\nBEST BOSS", Vector3(1.5, 1.85, 0.46), 24, Color(0.7, 0.1, 0.1), 0.003)
	# a monitor showing the junkyard (static and a blurry orange blob)
	var scr := M.glow(Color(0.35, 0.8, 0.9), 1.2)
	n.set_meta("screen_mat", scr)
	box(desk, Vector3(1.4, 0.9, 0.12), dark, Vector3(0.4, 2.3, -0.4), Vector3(0, -0.25, 0))
	box(desk, Vector3(1.25, 0.75, 0.02), scr, Vector3(0.4, 2.3, -0.33), Vector3(0, -0.25, 0))
	n.set_meta("desk_pos", desk.position)
	# posters: TEAMWORK, EMPLOYEE OF THE MONTH (him, twelve times), SAFETY FIRST (then productivity)
	var ps := [["TEAMWORK", "Because you have\nno choice."], ["EMPLOYEE\nOF THE MONTH", "G. GRUDD"], ["SAFETY FIRST", "(Productivity\nsecond. Also first.)"],
		["NO BREAKS", "Breaks are for\nbrakes."], ["EMPLOYEE\nOF THE MONTH", "G. GRUDD"], ["HARD HATS", "Not a suggestion.\nA hat."]]
	for i in ps.size():
		var side := -1.0 if i < 3 else 1.0
		var z := -3.0 + (i % 3) * 3.0
		var p := Node3D.new(); p.position = Vector3(side * (W * 0.5 - 0.17), 3.6, z); p.rotation.y = -side * PI * 0.5; n.add_child(p)
		var col: Color = [Color(0.75, 0.2, 0.12), Color(0.15, 0.35, 0.6), Color(0.2, 0.5, 0.25)][i % 3]
		box(p, Vector3(2.0, 2.7, 0.04), M.std(Color(0.96, 0.9, 0.72), 0.0, 0.8), Vector3.ZERO)
		box(p, Vector3(1.8, 0.9, 0.05), M.std(col, 0.0, 0.7), Vector3(0, 0.75, 0))
		label(p, ps[i][0], Vector3(0, 0.75, 0.04), 64, Color(1, 0.95, 0.8), 0.0045)
		label(p, ps[i][1], Vector3(0, -0.55, 0.04), 40, Color(0.2, 0.15, 0.1), 0.0045)
		if ps[i][1] == "G. GRUDD":
			box(p, Vector3(0.8, 0.7, 0.05), M.std(Color(0.42, 0.45, 0.5), 0.7, 0.4), Vector3(0, 0.0, 0.01))
			cyl(p, 0.14, 0.5, M.std(Color(0.55, 0.3, 0.18)), Vector3(0, 0.5, 0.02))
	# the big board behind the desk: a map with fourteen pins and string
	var board := Node3D.new(); board.position = Vector3(0, 3.9, -D * 0.5 + 0.2); n.add_child(board)
	box(board, Vector3(6.5, 3.2, 0.06), M.std(Color(0.7, 0.55, 0.35), 0.0, 0.9), Vector3.ZERO)
	label(board, "THE GREAT WORKS  -  PHASE ONE", Vector3(0, 1.3, 0.05), 64, Color(0.2, 0.1, 0.05), 0.005)
	var rng := RandomNumberGenerator.new(); rng.seed = 14
	var prev := Vector3.ZERO
	for i in 14:
		var p := Vector3(rng.randf_range(-2.8, 2.8), rng.randf_range(-1.2, 0.9), 0.06)
		sphere(board, 0.07, M.glow(Color(1, 0.25, 0.15), 2.0) if i == 0 else M.std(Color(0.8, 0.15, 0.1)), p)
		if i > 0:
			var mid := (p + prev) * 0.5; var d := p - prev
			box(board, Vector3(d.length(), 0.015, 0.01), M.std(Color(0.8, 0.1, 0.1)), mid, Vector3(0, 0, atan2(d.y, d.x)))
		prev = p
	# lights: a green-shaded banker's lamp and harsh office tubes
	var lamp := OmniLight3D.new(); lamp.light_color = Color(1, 0.75, 0.45); lamp.light_energy = 2.5; lamp.omni_range = 7; lamp.position = Vector3(-1.2, 2.6, -2.0)
	n.add_child(lamp); n.set_meta("lamp", lamp)
	box(desk, Vector3(0.5, 0.15, 0.25), M.glow(Color(0.3, 0.9, 0.4), 0.6), Vector3(-1.2, 2.3, 0.4))
	for x in [-3.5, 3.5]:
		var tube := OmniLight3D.new(); tube.light_color = Color(0.85, 0.95, 1.0); tube.light_energy = 1.2; tube.omni_range = 9; tube.position = Vector3(x, H - 0.8, 1.0)
		n.add_child(tube)
		box(n, Vector3(0.3, 0.08, 3.0), M.glow(Color(0.9, 0.97, 1.0), 2.0), Vector3(x, H - 0.1, 1.0))
	var red := OmniLight3D.new(); red.light_color = Color(1, 0.35, 0.15); red.light_energy = 1.5; red.omni_range = 8; red.position = Vector3(0, 5.5, -4.5)
	n.add_child(red)
	return n
