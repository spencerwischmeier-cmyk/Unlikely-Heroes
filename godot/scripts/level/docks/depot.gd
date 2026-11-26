extends RefCounted
## The Freight Depot: the Cargo Docks' new east wing.
##   Pier D "Container Canyon" (x 56..84, z 10..50, y 0): reached by a gangway from Pier A's east edge. Stacked
##     containers make a winding canyon (corridor A east, a jog south, corridor B east to the warehouse);
##     crate steps lead up onto the container tops, where sprockets wait. Jib cranes swing loads overhead,
##     a forklift and dock bots run loops, and a rail climbs from the north yard to Pier B.
##   The warehouse (x 84..112, z 14..46): LINE 1, a raised conveyor running against you with crates riding it,
##     leads to the big red button that reverses LINE 2, the ramp belt up to the mezzanine (Lucky Washer,
##     sprockets and the switch that rolls up the east loading-bay door).
##   The sky berth (x 112..138, z 18..42): a cargo freighter moored in its cradle, a second jib crane loading it.

const M := preload("res://scripts/mats.gd")
const Anim := preload("res://scripts/level/docks/anim.gd")
const CH := 2.4        # container height (a double jump clears one)
const CL := 6.0        # container length
const CW := 2.5        # container width

static var _mats := {}

static func _m(key: String, make: Callable) -> Material:
	if not _mats.has(key): _mats[key] = make.call()
	return _mats[key]

static func cont_mat(ci: int) -> StandardMaterial3D:
	var cols := [Color(0.82, 0.27, 0.18), Color(0.18, 0.5, 0.82), Color(0.91, 0.7, 0.16), Color(0.23, 0.65, 0.48),
		Color(0.93, 0.48, 0.16), Color(0.86, 0.84, 0.78), Color(0.55, 0.3, 0.6)]
	return _m("cont%d" % ci, func(): return M.std(cols[ci % cols.size()], 0.5, 0.45)) as StandardMaterial3D

## A container standing on the floor (level 0) or stacked (level 1, 2...). Returns the box (keeps its collider).
static func container(L: Node3D, x: float, z: float, lvl: int, along_x: bool, ci: int, y0 := 0.0, yaw := 0.0) -> MeshInstance3D:
	var size := Vector3(CL, CH, CW) if along_x else Vector3(CW, CH, CL)
	var mat := cont_mat(ci)
	var cb: MeshInstance3D = L.box(Vector3(x, y0 + lvl * CH + CH / 2, z), size, mat)
	if yaw != 0.0: cb.rotation.y = yaw
	DocksDressing.skin_box(cb, "container", mat.albedo_color.lightened(0.15))
	return cb

## A crate pile you can hop onto: the Meshy crates for looks, a forgiving square collider for feet.
static func step_crates(L: Node3D, pos: Vector3, h: float, yaw: float) -> void:
	DocksDressing.place(L, "crates", pos, yaw, h, false)
	L.box(pos + Vector3(0, h / 2, 0), Vector3(1.7, h, 1.7), L.mat_wood, true).visible = false

## A spinning brass sprocket you collect by touching it.
static func sprocket(A: Node3D, pos: Vector3, value := 5) -> void:
	var holder := Node3D.new(); A.add_child(holder); holder.position = pos
	var tor := TorusMesh.new(); tor.inner_radius = 0.13; tor.outer_radius = 0.3; tor.ring_segments = 6; tor.rings = 10
	var mat := _m("sprocket", func():
		var m := M.std(Color(1.0, 0.76, 0.24), 1.0, 0.22)
		m.emission_enabled = true; m.emission = Color(0.6, 0.35, 0.0); m.emission_energy_multiplier = 0.9
		return m)
	var mi := MeshInstance3D.new(); mi.mesh = tor; mi.material_override = mat; mi.rotation.x = PI / 2
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(mi)
	for k in 6:   # teeth
		var tb := BoxMesh.new(); tb.size = Vector3(0.12, 0.1, 0.12)
		var tm := MeshInstance3D.new(); tm.mesh = tb; tm.material_override = mat
		tm.position = Vector3(cos(k * TAU / 6), 0, sin(k * TAU / 6)) * 0.33
		tm.rotation.y = -k * TAU / 6
		mi.add_child(tm)
	A.sprockets.append({ node = holder, pos = pos, taken = false, value = value })

static func sprocket_line(A: Node3D, a: Vector3, b: Vector3, n: int, value := 5) -> void:
	for i in n:
		sprocket(A, a.lerp(b, float(i) / maxf(n - 1, 1)), value)

## A blinking signal light (shared material per colour/period/phase so blinkers batch).
static func beacon(L: Node3D, A: Node3D, pos: Vector3, c: Color, period := 1.6, ph := 0.0, on := 0.3, r := 0.18, light := false, parent: Node3D = null) -> void:
	if parent == null: parent = L
	var key := "bk_%s_%s_%s_%s" % [c.to_html(), period, snappedf(ph, 0.05), on]
	var fresh := not _mats.has(key)
	var mat := _m(key, func(): return M.glow(c, 8.0)) as StandardMaterial3D
	if fresh: A.blinkers.append({ mat = mat, on = on, period = period, ph = ph, peak = 9.0, low = 0.4 })
	var s := SphereMesh.new(); s.radius = r; s.height = r * 2; s.radial_segments = 10; s.rings = 6
	var mi: MeshInstance3D = L.mesh_at(s, mat, pos, parent)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var cage := CylinderMesh.new(); cage.top_radius = r * 0.9; cage.bottom_radius = r * 1.2; cage.height = r * 0.8
	L.mesh_at(cage, L.mat_dark, pos - Vector3(0, r * 0.9, 0), parent)
	if light:
		var l := OmniLight3D.new(); l.light_color = c; l.light_energy = 1.2; l.omni_range = 5.0; l.shadow_enabled = false
		l.position = pos; parent.add_child(l)

## A conveyor belt from `a` to `b` (points on the belt's top surface, centre line). Returns its record.
static func belt(L: Node3D, A: Node3D, id: String, a: Vector3, b: Vector3, width: float, speed: float, side_h := 0.25) -> Dictionary:
	var dir := (b - a).normalized()
	var len := a.distance_to(b)
	var x := dir; var z := x.cross(Vector3.UP).normalized(); var y := z.cross(x)
	var frame := Node3D.new(); L.add_child(frame)
	frame.transform = Transform3D(Basis(x, y, z), (a + b) / 2)
	var sb := StaticBody3D.new(); frame.add_child(sb)
	var cs := CollisionShape3D.new(); var sh := BoxShape3D.new(); sh.size = Vector3(len, 0.4, width)
	cs.shape = sh; cs.position.y = -0.2; sb.add_child(cs)
	sb.constant_linear_velocity = dir * speed
	# belt surface: a scrolling striped rubber plane
	var bm := _m("belt_tex", func():
		var img := Image.create(64, 8, false, Image.FORMAT_RGB8)
		for px in 64:
			var v := 0.13 if (px % 16) < 3 else 0.2
			for py in 8: img.set_pixel(px, py, Color(v, v, v * 1.1))
		var m := StandardMaterial3D.new()
		m.albedo_texture = ImageTexture.create_from_image(img); m.roughness = 0.8
		return m) as StandardMaterial3D
	var mat: StandardMaterial3D = bm.duplicate()
	mat.uv1_scale = Vector3(len / 2.0, 1, 1)
	var pm := PlaneMesh.new(); pm.size = Vector2(len, width - 0.3)
	var top := MeshInstance3D.new(); top.mesh = pm; top.material_override = mat; top.position.y = 0.01; frame.add_child(top)
	var body := BoxMesh.new(); body.size = Vector3(len, 0.36, width - 0.3)
	var bmi := MeshInstance3D.new(); bmi.mesh = body; bmi.material_override = L.mat_dark; bmi.position.y = -0.19; frame.add_child(bmi)
	# side rails in hazard paint with chevrons and roller caps
	for s in [-1, 1]:
		var rb := BoxMesh.new(); rb.size = Vector3(len, 0.5 + side_h, 0.15)
		var rm := MeshInstance3D.new(); rm.mesh = rb; rm.material_override = _m("belt_side", func(): return M.paint(Color(0.95, 0.72, 0.15)))
		rm.position = Vector3(0, -0.25 + side_h * 0.5, s * (width / 2 - 0.075)); frame.add_child(rm)
		var stripe := BoxMesh.new(); stripe.size = Vector3(len, 0.06, 0.16)
		var st := MeshInstance3D.new(); st.mesh = stripe; st.material_override = L.glow_cyan if speed >= 0 else L.glow_warm
		st.position = Vector3(0, side_h - 0.02, s * (width / 2 - 0.075)); frame.add_child(st)
		var nrol := int(len / 1.2)
		for i in nrol:
			var c := CylinderMesh.new(); c.top_radius = 0.12; c.bottom_radius = 0.12; c.height = 0.05; c.radial_segments = 8
			var cm := MeshInstance3D.new(); cm.mesh = c; cm.material_override = L.mat_brass
			cm.rotation.x = PI / 2; cm.position = Vector3(-len / 2 + 0.6 + i * 1.2, -0.2, s * (width / 2 + 0.01)); frame.add_child(cm)
	var rec := { body = sb, dir = dir, speed = speed, mat = mat, scroll = 0.0, id = id, a = a, b = b, frame = frame, len = len }
	A.belts.append(rec)
	return rec

## Crates riding a belt (moving obstacles); they loop from end to start.
static func belt_crates(L: Node3D, A: Node3D, bl: Dictionary, n: int, size := 1.2) -> void:
	var a: Vector3 = bl.a + Vector3(0, size / 2 + 0.02, 0)
	var b: Vector3 = bl.b + Vector3(0, size / 2 + 0.02, 0)
	for i in n:
		var body := AnimatableBody3D.new(); body.sync_to_physics = true
		var cs := CollisionShape3D.new(); var sh := BoxShape3D.new(); sh.size = Vector3.ONE * size * 0.95
		cs.shape = sh; body.add_child(cs)
		L.add_child(body)
		var vis := DocksDressing.place(body, "crates", Vector3(0, -size / 2, 0), randf() * TAU, size, false)
		if vis == null:
			var bm := BoxMesh.new(); bm.size = Vector3.ONE * size
			var mi := MeshInstance3D.new(); mi.mesh = bm; mi.material_override = L.mat_wood; body.add_child(mi)
		var u := float(i) / n
		body.position = a.lerp(b, u)
		A.riders.append({ body = body, a = a, b = b, belt = bl, u = u })

## A big floor button. fn runs when Vesk steps on it.
static func button(L: Node3D, A: Node3D, pos: Vector3, label: String, fn: Callable, color := Color(1, 0.25, 0.2)) -> void:
	var n := Node3D.new(); n.position = pos; L.add_child(n)
	var base := CylinderMesh.new(); base.top_radius = 1.0; base.bottom_radius = 1.15; base.height = 0.2
	L.mesh_at(base, M.hazard(), Vector3(0, 0.1, 0), n)
	var cap := Node3D.new(); n.add_child(cap)
	var c := CylinderMesh.new(); c.top_radius = 0.7; c.bottom_radius = 0.75; c.height = 0.25
	L.mesh_at(c, M.glow(color, 3.0), Vector3(0, 0.3, 0), cap)
	var l := OmniLight3D.new(); l.light_color = color; l.light_energy = 1.5; l.omni_range = 4.0; l.position.y = 0.8; n.add_child(l)
	var t := Label3D.new(); t.text = label; t.font_size = 64; t.pixel_size = 0.006; t.outline_size = 12
	t.modulate = Color(1, 0.9, 0.6); t.billboard = BaseMaterial3D.BILLBOARD_ENABLED; t.position.y = 2.0; n.add_child(t)
	A.buttons.append({ pos = pos, r = 1.0, y = pos.y, cap = cap, fn = fn, done = false, down = false, once = true, light = l, label = t })

## A rolling loading-bay shutter in a wall gap. Returns the record (open with A.open_door).
static func shutter(L: Node3D, A: Node3D, id: String, center_bottom: Vector3, width: float, height: float, along_x: bool, trigger = null) -> Dictionary:
	var n := Node3D.new(); n.position = center_bottom; L.add_child(n)
	var size := Vector3(width, height, 0.25) if along_x else Vector3(0.25, height, width)
	var mat := _m("shutter", func():
		var m := M.surface("paint", Color(0.78, 0.74, 0.66), 0.6, 0.45, 1.6)
		return m)
	L.box(Vector3(0, height / 2, 0), size, mat, true, n)
	# horizontal slat ribs and a hazard kick plate
	for i in int(height / 0.5):
		var rib := Vector3(width, 0.06, 0.32) if along_x else Vector3(0.32, 0.06, width)
		L.box(Vector3(0, 0.25 + i * 0.5, 0), rib, L.mat_dark, false, n)
	L.box(Vector3(0, 0.3, 0), Vector3(width, 0.6, 0.3) if along_x else Vector3(0.3, 0.6, width), M.hazard(), false, n)
	var rec := { node = n, open_y = center_bottom.y + height - 0.4, closed_y = center_bottom.y, trigger = trigger, id = id, open = false }
	A.doors.append(rec)
	return rec

## a moving prop (forklift, dock bot, overhead trolley) on a closed loop; pushes Vesk instead of ghosting through
static func looper(L: Node3D, A: Node3D, model: String, height: float, pts: Array, speed: float, yaw_off := 0.0, solid := Vector3.ZERO) -> Node3D:
	var n := Node3D.new(); L.add_child(n)
	DocksDressing.place(n, model, Vector3.ZERO, 0.0, height, false)
	if solid != Vector3.ZERO:
		var body := AnimatableBody3D.new(); body.sync_to_physics = false
		var cs := CollisionShape3D.new(); var sh := BoxShape3D.new(); sh.size = solid
		cs.shape = sh; cs.position.y = solid.y / 2; body.add_child(cs); n.add_child(body)
	var pv := PackedVector3Array(pts)
	n.position = pv[0]
	A.loopers.append({ node = n, pts = pv, len = Anim.loop_len(pv), speed = speed, d = randf() * 5.0, yaw_off = yaw_off })
	return n

## A slewing jib crane on a steel plinth: swings its boom back and forth with a container hanging off the hook.
static func jib_crane(L: Node3D, A: Node3D, pos: Vector3, plinth: float, height: float, base_yaw: float, amp: float, period: float, ci: int) -> void:
	# plinth: a stout lattice tower with a ladder stripe and a light on each corner
	L.box(pos + Vector3(0, plinth / 2, 0), Vector3(3.2, plinth, 3.2), L.mat_dark)
	L.box(pos + Vector3(0, plinth - 0.15, 0), Vector3(3.6, 0.3, 3.6), M.hazard(), false)
	for c in [Vector3(-1.5, 0, -1.5), Vector3(1.5, 0, -1.5), Vector3(-1.5, 0, 1.5), Vector3(1.5, 0, 1.5)]:
		L.cyl(pos + c + Vector3(0, plinth / 2, 0), 0.14, 0.18, plinth, L.mat_brass, 8)
	var piv := Node3D.new(); piv.position = pos + Vector3(0, plinth, 0); piv.rotation.y = base_yaw; L.add_child(piv)
	var s := height / 1.47
	var cr := DocksDressing.place(piv, "jib_crane", Vector3(-0.33 * s, 0, 0), 0.0, height, false)
	if cr == null:
		L.box(Vector3(0, height * 0.4, 0), Vector3(2, height * 0.8, 2), M.paint(Color(0.95, 0.75, 0.2)), false, piv)
	# the load: a container on a cable under the hook
	var tip := Vector3(-1.21 * s, 0.47 * s, 0)
	var hang := Node3D.new(); hang.position = tip; piv.add_child(hang)
	var cable := CylinderMesh.new(); cable.top_radius = 0.04; cable.bottom_radius = 0.04; cable.height = 1.6; cable.radial_segments = 6
	for sx in [-1.6, 1.6]:
		var cmi := MeshInstance3D.new(); cmi.mesh = cable; cmi.material_override = L.mat_dark
		cmi.position = Vector3(sx * 0.6, -0.8, 0); cmi.rotation.z = sx * 0.35; hang.add_child(cmi)
	var bm := BoxMesh.new(); bm.size = Vector3(CL, CH, CW)
	var cmesh := MeshInstance3D.new(); cmesh.mesh = bm; cmesh.material_override = cont_mat(ci); cmesh.position.y = -1.6 - CH / 2
	cmesh.rotation.y = PI / 2
	hang.add_child(cmesh)
	DocksDressing.skin_box(cmesh, "container", cont_mat(ci).albedo_color.lightened(0.15))
	beacon(L, A, tip + Vector3(0, 0.6, 0), Color(1, 0.25, 0.15), 1.4, 0.0, 0.35, 0.22, false, piv)
	A.cranes.append({ node = piv, base = base_yaw, amp = amp, w = TAU / period, ph = randf() * TAU, hang = hang, last_dir = 0.0 })

static func build(L: Node3D, A: Node3D) -> void:
	_canyon(L, A)
	_warehouse(L, A)
	_berth(L, A)
	_piers_abc(L, A)

# ------------------------------------------------------------------ Pier D: the container canyon
static func _canyon(L: Node3D, A: Node3D) -> void:
	var pd: Rect2 = L.rect(70, 30, 28, 40)
	L.island("pier_d", pd, 0.0, Color(0.9, 0.92, 0.95))
	# railings: gangway gap west, rail gap north, open to the warehouse east, freighter gangway south
	L.fence(pd, 0.0, [["w", 27, 33], ["n", 71, 77], ["s", 66, 72]], "nsw")
	L.railing(84, 10, 84, 14, 0.0); L.railing(84, 46, 84, 50, 0.0)
	# gangway from Pier A
	L.walkway(50, 27.5, 56, 32.5, 0.0)
	L.label("CONTAINER CANYON", Vector3(61, 0, 30), 2.6, Color(1, 0.8, 0.45), PI / 2)
	L.hint_sign("FREIGHT DEPOT 7. HARD HATS REQUIRED. SOFT HEADS DISCOURAGED.", Vector3(57.5, 0, 26.6), PI * 0.5)
	L.checkpoints.append({ pos = Vector3(58, 0.1, 30), r = 2.5 })
	A.triggers.append({ box = AABB(Vector3(56, -1, 26), Vector3(5, 5, 8)), fn = A.say.bind(["depot_canyon_1", "depot_canyon_2"]), done = false })
	A.triggers.append({ box = AABB(Vector3(84.5, -1, 16), Vector3(6, 6, 28)), fn = A.say.bind(["depot_belt_1", "depot_belt_2"]), done = false })
	A.triggers.append({ box = AABB(Vector3(112.5, -1, 24), Vector3(6, 6, 12)), fn = A.say.bind(["depot_berth_1", "depot_berth_2"]), done = false })
	# --- the canyon walls (x, z, level, along_x, colour)
	var stacks := [
		# corridor A, north wall (z 25..27.5)
		[59, 26.2, 0, true, 1], [59, 26.2, 1, true, 4], [65, 26.2, 0, true, 3],
		# corridor A, south wall (z 32.5..35)
		[59, 33.8, 0, true, 2], [65, 33.8, 0, true, 0], [65, 33.8, 1, true, 5],
		# the jog: north cap and east wall
		[71, 24.0, 0, true, 6], [71, 24.0, 1, true, 1],
		[74.4, 29.0, 0, false, 0], [74.4, 29.0, 1, false, 2], [74.4, 34.6, 0, false, 3],
		# jog west wall (x 65.5..68, z 35.5..47.5)
		[66.75, 38.6, 0, false, 4], [66.75, 38.6, 1, false, 1], [66.75, 44.6, 0, false, 5],
		# corridor B north wall (z 34.5..37) and south wall (z 42..44.5)
		[79.5, 35.75, 0, true, 1], [79.5, 35.75, 1, true, 3], [79.5, 35.75, 2, true, 0],
		[71, 43.25, 0, true, 2], [77, 43.25, 0, true, 6], [77, 43.25, 1, true, 4],
	]
	for s in stacks: container(L, s[0], s[1], s[2], s[3], s[4])
	# a couple of doors-open containers in the north yard, and one knocked askew
	container(L, 80.5, 21.5, 0, false, 5, 0.0, 0.12)
	container(L, 58.6, 46.5, 0, true, 3, 0.0, -0.05)
	# crate steps up onto the container tops
	step_crates(L, Vector3(67.3, 0, 29.0), 1.3, 0.3)
	step_crates(L, Vector3(69.2, 0, 40.2), 1.3, 1.2)
	step_crates(L, Vector3(82.6, 0, 38.4), 1.4, 2.0)
	step_crates(L, Vector3(57.4, 0, 23.0), 1.3, 0.2)
	step_crates(L, Vector3(74.4, 0, 38.9), 1.3, 0.7)
	L.crate_spots.append(Vector3(81.5, CH * 3, 35.75))   # a sprocket crate on the tallest stack
	# sprockets along the tops (upper route) and down the corridors
	var top1 := CH + 0.9; var top2 := CH * 2 + 0.9; var top3 := CH * 3 + 0.9
	sprocket_line(A, Vector3(63, top1, 26.2), Vector3(67, top1, 26.2), 3)
	sprocket_line(A, Vector3(57, top2, 26.2), Vector3(61, top2, 26.2), 3)
	sprocket_line(A, Vector3(63, top2, 33.8), Vector3(67, top2, 33.8), 3)
	sprocket_line(A, Vector3(74.4, top2, 26.5), Vector3(74.4, top2, 31.5), 3)
	sprocket_line(A, Vector3(74.4, top1, 33.0), Vector3(74.4, top1, 36.5), 2)
	sprocket_line(A, Vector3(66.75, top2, 36.5), Vector3(66.75, top2, 40.8), 3)
	sprocket_line(A, Vector3(77.5, top3, 35.75), Vector3(81.5, top3, 35.75), 3, 10)
	sprocket_line(A, Vector3(60, 1.0, 30), Vector3(66, 1.0, 30), 4)
	sprocket_line(A, Vector3(70.5, 1.0, 31), Vector3(70.5, 1.0, 38), 3)
	sprocket_line(A, Vector3(75, 1.0, 39.5), Vector3(81, 1.0, 39.5), 3)
	# dock bots trundling the corridors, a forklift doing laps of the north yard
	looper(L, A, "dock_bot", 1.3, [Vector3(62, 0, 28.6), Vector3(66, 0, 28.6), Vector3(71.5, 0, 31.5), Vector3(71.5, 0, 40.5),
		Vector3(70.5, 0, 31.5), Vector3(66, 0, 28.9)], 1.6, 0.0, Vector3(0.9, 1.2, 0.9))
	var fk1 := looper(L, A, "forklift", 2.3, [Vector3(63, 0, 16.5), Vector3(78, 0, 16.5), Vector3(78.5, 0, 20.5), Vector3(63, 0, 20.5)], 2.6, -PI / 2, Vector3(1.4, 2.0, 1.4))
	looper(L, A, "dock_bot", 1.2, [Vector3(76, 0, 47.5), Vector3(60, 0, 47.5)], 1.3, 0.0, Vector3(0.9, 1.1, 0.9))
	A.horns.append({ node = fk1, every = 11.0, t = 3.0, sound = "docks_forklift_beep", db = -8.0, near = 22.0 })
	# jib cranes swinging loads over the canyon and the north yard
	jib_crane(L, A, Vector3(59.6, 0, 13.2), 4.5, 12.0, PI * 0.15, 0.55, 26.0, 4)
	jib_crane(L, A, Vector3(81.5, 0, 47.5), 4.5, 12.0, PI * 1.1, 0.45, 30.0, 1)
	# north yard: fuel tanks, fuel lines out to the moored airship, mooring mast
	DocksDressing.place(L, "fuel_tanks", Vector3(81.2, 0, 13.0), 0.0, 2.8, true)
	_fuel_line(L, [Vector3(79, 0.5, 11.2), Vector3(70, 0.5, 11.2), Vector3(66, 0.5, 11.2)])
	_fuel_line(L, [Vector3(83.2, 0.5, 15.5), Vector3(83.2, 0.5, 23.5)])
	DocksDressing.place(L, "pipes", Vector3(66, 0, 11.5), PI, 2.6, true, 0.6)
	DocksDressing.steam(L, Vector3(66, 2.8, 11.5), 0.8)
	DocksDressing.place(L, "cable_spool", Vector3(68.6, 0, 22.4), 0.8, 1.3, true)
	DocksDressing.place(L, "barrels", Vector3(62.4, 0, 22.6), 0.5, 1.3, true)
	DocksDressing.place(L, "hazard_barrier", Vector3(74, 0, 15.6), 0.0, 1.1, false)
	for b in [Vector3(57, 0, 11), Vector3(83, 0, 49), Vector3(57, 0, 49), Vector3(64.5, 0, 49.2), Vector3(73.5, 0, 49.2)]:
		DocksDressing.place(L, "bollard", b, randf() * TAU, 0.7, true)
	DocksDressing.place(L, "floodlight", Vector3(57.0, 0, 37.0), PI * 0.5, 7.0, true, 0.3)
	DocksDressing.place(L, "floodlight", Vector3(83.0, 0, 24.5), -PI * 0.5, 7.0, true, 0.3)
	# the rail up to Pier B starts here
	L.hint_sign("RAIL TO PIER B", Vector3(76.5, 0, 14.2), PI)
	for i in 6:
		beacon(L, A, Vector3(71 + i * 1.2, 0.15, 10.2), Color(1, 0.6, 0.15), 1.2, i * 0.12, 0.25, 0.1)
	# landing lights chasing along the south and west edges
	for i in 12:
		beacon(L, A, Vector3(57 + i * 2.3, 0.15, 49.85), Color(0.3, 0.95, 1), 2.4, -i * 0.08, 0.15, 0.1)
	# floodlit work lights between the stacks (no shadows, short range)
	for p in [Vector3(62, 4.2, 30), Vector3(70.5, 4.2, 36), Vector3(78, 4.2, 39.5), Vector3(70, 4.5, 18)]:
		var l := OmniLight3D.new(); l.light_color = Color(1, 0.8, 0.55); l.light_energy = 1.6; l.omni_range = 10.0
		l.position = p; L.add_child(l)
	# the south gangway out to the moored cargo blimp's gondola
	_moored_blimp(L, A)
	Anim.Snd3.loop(A, "docks_harbor_amb", Vector3(70, 3, 30), -8.0, 20.0, 80.0)

static func _fuel_line(L: Node3D, pts: Array) -> void:
	var pm := _m("fuel", func(): return M.paint(Color(0.85, 0.3, 0.18)))
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]; var b: Vector3 = pts[i + 1]
		var mid := (a + b) / 2; var len := a.distance_to(b)
		var c := CylinderMesh.new(); c.top_radius = 0.16; c.bottom_radius = 0.16; c.height = len; c.radial_segments = 10
		var mi: MeshInstance3D = L.mesh_at(c, pm, mid)
		mi.look_at_from_position(mid, b, Vector3.UP if absf((b - a).normalized().y) < 0.9 else Vector3.FORWARD)
		mi.rotate_object_local(Vector3.RIGHT, PI / 2)
		var k := 0.0
		while k < len:
			var p := a.lerp(b, k / len)
			var ring := CylinderMesh.new(); ring.top_radius = 0.22; ring.bottom_radius = 0.22; ring.height = 0.12; ring.radial_segments = 10
			var rm: MeshInstance3D = L.mesh_at(ring, L.mat_brass, p)
			rm.transform.basis = mi.transform.basis
			L.box(p - Vector3(0, 0.3, 0), Vector3(0.3, 0.4, 0.3), L.mat_dark, false)
			k += 2.5

static func _moored_blimp(L: Node3D, A: Node3D) -> void:
	# a stubby cargo blimp hovering off the south edge with a gondola deck you can walk onto
	var deck_y := 1.2
	var g: Rect2 = L.rect(69, 55, 10, 5)
	L.box(Vector3(g.get_center().x, deck_y - 0.25, g.get_center().y), Vector3(g.size.x, 0.5, g.size.y), M.wood(Color(0.9, 0.75, 0.6)))
	L.box(Vector3(g.get_center().x, deck_y - 1.0, g.get_center().y), Vector3(g.size.x - 0.6, 1.0, g.size.y - 0.6), L.mat_rust, false)
	L.fence(g, deck_y, [["n", 67, 71]])
	# ramp from the pier edge (z 50, y 0) up to the gondola (z 52.5, y 1.2)
	var ramp: MeshInstance3D = L.box(Vector3(69, 0.6, 51.25), Vector3(3.6, 0.25, 2.9), M.wood(Color(0.85, 0.7, 0.55)))
	ramp.rotation.x = -atan2(deck_y, 2.5)
	L.railing(67.2, 50, 67.2, 52.5, 0.6); L.railing(70.8, 50, 70.8, 52.5, 0.6)
	var ship := Node3D.new(); ship.position = Vector3(69, deck_y + 9.0, 56); L.add_child(ship)
	DocksDressing.place(ship, "airship", Vector3.ZERO, PI / 2, 9.0, false)
	A.bobbers.append({ node = ship, base = ship.position, amp = 0.35, w = 0.6, ph = 0.0, roll = 0.02 })
	for c in [Vector3(64.5, deck_y, 52.8), Vector3(73.5, deck_y, 52.8), Vector3(64.5, deck_y, 57.2), Vector3(73.5, deck_y, 57.2)]:
		L.cyl(c + Vector3(0, 4.5, 0), 0.05, 0.05, 9.0, L.mat_dark, 6)
	DocksDressing.place(L, "crates", Vector3(65.5, deck_y, 55.5), 0.4, 1.4, true)
	DocksDressing.place(L, "barrels", Vector3(72.8, deck_y, 56.2), 1.0, 1.2, true)
	sprocket_line(A, Vector3(67, deck_y + 0.9, 55.5), Vector3(71.5, deck_y + 0.9, 55.5), 4)
	beacon(L, A, Vector3(64.2, deck_y + 1.4, 52.6), Color(1, 0.2, 0.15), 1.8, 0.0, 0.3, 0.14, true)
	beacon(L, A, Vector3(73.8, deck_y + 1.4, 52.6), Color(0.2, 1, 0.4), 1.8, 0.5, 0.3, 0.14, true)
	L.crate_spots.append(Vector3(72.5, deck_y, 54))

# ------------------------------------------------------------------ the warehouse and its conveyor puzzle
static func _warehouse(L: Node3D, A: Node3D) -> void:
	var r: Rect2 = L.rect(98, 30, 28, 32)
	L.island("depot", r, 0.0, Color(0.86, 0.85, 0.82))
	var H := 9.0
	var wall := _m("wall", func(): return M.surface("paint", Color(0.83, 0.79, 0.7), 0.35, 0.55, 0.35, true)) as Material
	var trim := _m("trim", func(): return M.paint(Color(0.2, 0.42, 0.5), true)) as Material
	# west wall with two loading bays (z 37..42 from the canyon, z 18..23 from the north yard)
	_wall_x(L, 84.3, 14, 46, H, [[37, 42], [18, 23]], wall)
	_wall_x(L, 111.7, 14, 46, H, [[27, 33]], wall)
	L.box(Vector3(98, H / 2, 14.3), Vector3(28, H, 0.6), wall)
	L.box(Vector3(98, H / 2, 45.7), Vector3(28, H, 0.6), wall)
	# pilasters, a top trim band and signage
	for x in range(86, 112, 4):
		for z in [13.9, 46.1]: L.box(Vector3(x, H / 2, z), Vector3(0.5, H, 0.3), trim, false)
	for z in range(16, 46, 4):
		for x in [83.9, 112.1]: L.box(Vector3(x, H / 2, z), Vector3(0.3, H, 0.5), trim, false)
	L.box(Vector3(98, H + 0.25, 30), Vector3(28.6, 0.5, 32.6), trim, false)
	_sign(L, "DEPOT 7", Vector3(83.7, 7.3, 30), -PI / 2, 2.2, Color(1, 0.85, 0.4))
	_sign(L, "GRUDDCO FREIGHT\nNO LOITERING. NO WHISTLING. NO JOY.", Vector3(98, 7.2, 46.2), 0.0, 0.9, Color(1, 0.55, 0.35))
	_sign(L, "BAY 1", Vector3(83.7, 5.8, 39.5), -PI / 2, 0.9, Color(0.5, 1, 1))
	_sign(L, "BAY 2", Vector3(83.7, 5.8, 20.5), -PI / 2, 0.9, Color(0.5, 1, 1))
	_sign(L, "BAY 3: SKY BERTH", Vector3(112.3, 6.2, 30), PI / 2, 0.9, Color(0.5, 1, 1))
	# roof: slabs over the trusses with long skylight gaps (no collision, the camera may pass)
	for z in [16.5, 24.5, 32.5, 40.5, 44.75]:
		var w := 5.0 if z != 44.75 else 2.5
		L.box(Vector3(98, H + 0.1, z), Vector3(28, 0.3, w), _m("roof", func(): return M.surface("paint", Color(0.55, 0.6, 0.62), 0.6, 0.5, 0.4, true)), false)
	for x in range(86, 112, 6):
		L.box(Vector3(x, H - 0.4, 30), Vector3(0.35, 0.6, 31.4), L.mat_dark, false)
	for z in [20.5, 28.5, 36.5]:
		var glass: MeshInstance3D = L.box(Vector3(98, H + 0.05, z), Vector3(28, 0.08, 3.0), M.glass(Color(0.75, 0.9, 1.0)), false)
		glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# loading bay doors: bay 1 rolls up as you come down the canyon, bay 2 from the yard, bay 3 by the mezzanine switch
	shutter(L, A, "bay1", Vector3(84.3, 0, 39.5), 5.0, 5.2, false, AABB(Vector3(76, -1, 36.5), Vector3(14, 6, 6.5)))
	shutter(L, A, "bay2", Vector3(84.3, 0, 20.5), 5.0, 5.2, false, AABB(Vector3(78, -1, 17.5), Vector3(12, 6, 6)))
	shutter(L, A, "bay3", Vector3(111.7, 0, 30), 6.0, 5.2, false)
	for d in [[84.3, 39.5, 5.0], [84.3, 20.5, 5.0], [111.7, 30, 6.0]]:
		L.box(Vector3(d[0], 5.45, d[1]), Vector3(0.9, 0.5, d[2] + 0.8), M.hazard(), false)
		for s in [-1, 1]: L.box(Vector3(d[0], 2.6, d[1] + s * (d[2] / 2 + 0.2)), Vector3(0.9, 5.2, 0.4), M.hazard(), false)
		beacon(L, A, Vector3(d[0] + (-0.6 if d[0] < 100 else 0.6), 6.0, d[1]), Color(1, 0.55, 0.1), 1.0, 0.0, 0.5, 0.2, false)
	# interior lights
	for p in [Vector3(90, 7.5, 22), Vector3(90, 7.5, 38), Vector3(100, 7.5, 22), Vector3(100, 7.5, 38), Vector3(108, 7.5, 30)]:
		var l := OmniLight3D.new(); l.light_color = Color(1, 0.82, 0.6); l.light_energy = 2.2; l.omni_range = 11.0
		l.position = p; L.add_child(l)
		L.cyl(p + Vector3(0, 0.6, 0), 0.02, 0.02, 1.2, L.mat_dark, 4)
		var shade := CylinderMesh.new(); shade.top_radius = 0.15; shade.bottom_radius = 0.55; shade.height = 0.35
		L.mesh_at(shade, L.mat_dark, p + Vector3(0, 0.1, 0))
		var bulb := SphereMesh.new(); bulb.radius = 0.18; bulb.height = 0.36
		L.mesh_at(bulb, M.glow(Color(1, 0.85, 0.6), 6.0), p - Vector3(0, 0.05, 0))

	# ---- LINE 1: the raised belt running west with crates riding it; the red button at its far end
	var y1 := 3.0
	var l1 := belt(L, A, "line1", Vector3(106, y1, 30.5), Vector3(88, y1, 30.5), 3.0, 4.5)
	belt_crates(L, A, l1, 3, 1.2)
	for x in range(89, 106, 3):
		for s in [-1, 1]: L.box(Vector3(x, (y1 - 0.4) / 2, 30.5 + s * 1.2), Vector3(0.3, y1 - 0.4, 0.3), L.mat_dark, false)
	# steps up to its west end
	L.block(86.5, 30.5, 1.4, 3.0, 1.0, 0.0, M.deck(Color(0.75, 0.75, 0.72)))
	L.block(87.6, 32.6, 1.6, 1.4, 2.0, 0.0, M.deck(Color(0.75, 0.75, 0.72)))
	L.hint_sign("LINE 1 RUNS AWAY FROM THE BUTTON. OBVIOUSLY.", Vector3(86.4, 0, 27.0), -PI / 2)
	# the button stand at the east end (too high to reach from the floor)
	var bs: Rect2 = L.rect(108, 30.5, 4, 5)
	L.block(bs.get_center().x, bs.get_center().y, bs.size.x, bs.size.y, y1, 0.0, M.deck(Color(0.7, 0.72, 0.75)))
	L.fence(bs, y1, [["w", 29, 32]], "nse")
	button(L, A, Vector3(108.3, y1, 30.5), "REVERSE\nLINE 2", func():
		A.set_belt("line2", 5.0)
		Game.say("depot_button_1")
		Anim.Snd3.at(A, "docks_button", Vector3(108.3, y1, 30.5), 0.0)
		if Game.hud and Game.hud.has_method("toast_small"): Game.hud.toast_small("LINE 2 REVERSED", Color(0.5, 1, 0.6))
		FX.ring(Vector3(108.3, y1 + 0.1, 30.5), Color(1, 0.4, 0.3)))
	L.crate_spots.append(Vector3(109.2, y1, 32.2))

	# ---- LINE 2: the ramp belt up to the mezzanine; runs downhill until the button flips it
	var y2 := 5.0
	var l2 := belt(L, A, "line2", Vector3(89.5, 0.05, 19.5), Vector3(104, y2, 19.5), 3.0, -9.0, 0.35)
	var ramp_supports := 5
	for i in ramp_supports:
		var u := (i + 0.5) / ramp_supports
		var p: Vector3 = Vector3(89.5, 0.05, 19.5).lerp(Vector3(104, y2, 19.5), u)
		for s in [-1, 1]: L.box(Vector3(p.x, (p.y - 0.4) / 2, 19.5 + s * 1.2), Vector3(0.3, maxf(p.y - 0.4, 0.1), 0.3), L.mat_dark, false)
	L.hint_sign("LINE 2: UP TO THE MEZZANINE (WHEN SOMEBODY FLIPS IT)", Vector3(88.2, 0, 22.4), -PI / 2)
	# the mezzanine (x 104..111.4, z 14.6..26)
	var mz: Rect2 = Rect2(104, 14.6, 7.4, 11.4)
	L.block(mz.get_center().x, mz.get_center().y, mz.size.x, mz.size.y, 0.5, y2 - 0.5, M.deck(Color(0.8, 0.78, 0.72)))
	for c in [Vector2(104.4, 15), Vector2(104.4, 25.6)]:
		L.box(Vector3(c.x, (y2 - 0.5) / 2, c.y), Vector3(0.4, y2 - 0.5, 0.4), L.mat_dark, false)
	L.fence(mz, y2, [["w", 17.8, 21.2]], "nw")
	L.railing(104, 26, 111.4, 26, y2)
	DocksDressing.place(L, "crates", Vector3(110.4, y2, 15.8), 0.0, 1.5, true)
	DocksDressing.place(L, "barrels", Vector3(110.6, y2, 24.8), 0.4, 1.2, true)
	sprocket_line(A, Vector3(105.5, y2 + 0.9, 23.5), Vector3(109.5, y2 + 0.9, 23.5), 4, 10)
	L.pickup_spots.append({ kind = "washer", id = "dw1", pos = Vector3(107.5, y2 + 0.8, 16.2) })
	button(L, A, Vector3(108.2, y2, 20.0), "OPEN\nBAY 3", func():
		A.open_door_id("bay3")
		Anim.Snd3.at(A, "docks_button", Vector3(108.2, y2, 20.0), 0.0)
		if Game.hud and Game.hud.has_method("toast_small"): Game.hud.toast_small("BAY 3 OPEN: SKY BERTH", Color(0.5, 1, 1))
		FX.ring(Vector3(108.2, y2 + 0.1, 20.0), Color(0.4, 1, 1)), Color(0.3, 0.9, 1))
	Anim.Snd3.loop(A, "docks_conveyor_loop", Vector3(97, 3.0, 26), -4.0, 6.0, 30.0)
	# ---- warehouse floor clutter: pallet racks, crates, a forklift and an overhead trolley
	for rk in [[95, 43.6], [101, 43.6], [107, 43.6]]:
		_rack(L, Vector3(rk[0], 0, rk[1]))
	DocksDressing.place(L, "crates", Vector3(88.5, 0, 44.0), 0.6, 1.6, true)
	DocksDressing.place(L, "barrels", Vector3(110.5, 0, 36), 1.0, 1.3, true)
	DocksDressing.place(L, "cable_spool", Vector3(93, 0, 16.2), 0.0, 1.2, true)
	var fk2 := looper(L, A, "forklift", 2.3, [Vector3(88, 0, 36.5), Vector3(108, 0, 36.5), Vector3(108, 0, 40), Vector3(88, 0, 40)], 2.2, -PI / 2, Vector3(1.4, 2.0, 1.4))
	A.horns.append({ node = fk2, every = 12.0, t = 6.0, sound = "docks_forklift_beep", db = -8.0, near = 22.0 })
	looper(L, A, "dock_bot", 1.3, [Vector3(95, 0, 24.5), Vector3(102, 0, 24.5), Vector3(102, 0, 27), Vector3(95, 0, 27)], 1.2, 0.0, Vector3(0.9, 1.2, 0.9))
	# overhead gantry trolley on a beam (purely visual)
	L.box(Vector3(98, 7.6, 34.5), Vector3(27, 0.4, 0.5), M.paint(Color(0.95, 0.72, 0.15)), false)
	var trolley := Node3D.new(); L.add_child(trolley)
	L.box(Vector3(0, 7.2, 0), Vector3(1.2, 0.6, 1.0), L.mat_dark, false, trolley)
	L.cyl(Vector3(0, 6.0, 0), 0.03, 0.03, 2.2, L.mat_dark, 4).reparent(trolley, false)
	var tc: MeshInstance3D = L.box(Vector3(0, 4.3, 0), Vector3(2.4, 1.2, 1.6), cont_mat(2), false, trolley)
	DocksDressing.skin_box(tc, "container", cont_mat(2).albedo_color)
	A.loopers.append({ node = trolley, pts = PackedVector3Array([Vector3(87, 0, 34.5), Vector3(109, 0, 34.5)]), len = 44.0, speed = 2.0, d = 0.0, yaw_off = 0.0 })

static func _rack(L: Node3D, p: Vector3) -> void:
	var steel := _m("rack", func(): return M.paint(Color(0.2, 0.42, 0.62)))
	for sx in [-2.7, 2.7]:
		for sz in [-0.8, 0.8]:
			L.box(p + Vector3(sx, 2.0, sz), Vector3(0.15, 4.0, 0.15), steel, false)
	for y in [0.15, 1.5, 2.9]:
		L.box(p + Vector3(0, y, 0), Vector3(5.6, 0.12, 1.8), _m("rack_shelf", func(): return M.paint(Color(0.95, 0.55, 0.15))), false)
		if randf() < 0.85: DocksDressing.place(L, "crates", p + Vector3(randf_range(-1.6, 1.6), y + 0.06, 0), randf() * TAU, 1.1, false)
	var sb := StaticBody3D.new(); var cs := CollisionShape3D.new(); var sh := BoxShape3D.new()
	sh.size = Vector3(5.6, 4.0, 1.8); cs.shape = sh; sb.add_child(cs); sb.position = p + Vector3(0, 2.0, 0); L.add_child(sb)

## a wall along z at x with door gaps [[z0, z1], ...]; a lintel above each gap
static func _wall_x(L: Node3D, x: float, z0: float, z1: float, h: float, gaps: Array, mat: Material) -> void:
	var cuts := gaps.duplicate(); cuts.sort_custom(func(a, b): return a[0] < b[0])
	var cur := z0
	for g in cuts:
		if g[0] > cur: L.box(Vector3(x, h / 2, (cur + g[0]) / 2), Vector3(0.6, h, g[0] - cur), mat)
		L.box(Vector3(x, (h + 5.2) / 2, (g[0] + g[1]) / 2), Vector3(0.6, h - 5.2, g[1] - g[0]), mat)
		cur = g[1]
	if z1 > cur: L.box(Vector3(x, h / 2, (cur + z1) / 2), Vector3(0.6, h, z1 - cur), mat)

static func _sign(L: Node3D, text: String, pos: Vector3, yaw: float, size: float, c: Color) -> void:
	var l := Label3D.new(); l.text = text; l.font_size = 96; l.pixel_size = size / 96.0 * 0.5
	l.modulate = c; l.outline_size = 16; l.outline_modulate = Color(0.08, 0.06, 0.05)
	l.position = pos; l.rotation.y = yaw; l.double_sided = false
	L.add_child(l)

# ------------------------------------------------------------------ the sky berth and the moored freighter
static func _berth(L: Node3D, A: Node3D) -> void:
	var r: Rect2 = Rect2(112, 18, 26, 24)
	L.island("berth", r, 0.0, Color(0.88, 0.9, 0.93))
	L.fence(r, 0.0, [], "nse")
	L.label("SKY BERTH", Vector3(117, 0, 30), 2.4, Color(0.75, 0.98, 1), PI / 2)
	# the freighter rides above the cradle, bow north
	var ship := Node3D.new(); ship.position = Vector3(129, 0, 30); L.add_child(ship)
	var hull := DocksDressing.place(ship, "freighter", Vector3(0, 2.0, 0), PI / 2, 20.0, false)
	A.bobbers.append({ node = ship, base = ship.position, amp = 0.25, w = 0.45, ph = 1.0, roll = 0.01 })
	# cradle arms reaching up to the hull, a gangway stair up to the hatch platform
	for z in [22.0, 38.0]:
		for x in [123.0, 135.0]:
			L.box(Vector3(x, 1.0, z), Vector3(0.6, 2.0, 0.6), L.mat_dark, false)
		L.box(Vector3(129, 1.9, z), Vector3(13, 0.4, 0.7), M.hazard(), false)
	# hatch platform (y 4) on the hull's west flank, reached by a stair from the berth deck
	var hp: Rect2 = Rect2(119.5, 27, 3.5, 6)
	L.block(hp.get_center().x, hp.get_center().y, hp.size.x, hp.size.y, 0.4, 3.6, M.deck(Color(0.8, 0.78, 0.72)))
	for i in 4:
		L.block(116.4 + i * 0.85, 30, 0.85, 3.0, 0.4, (i + 1) * 0.8 - 0.4, M.deck(Color(0.78, 0.74, 0.7)), i == 3)
	L.railing(119.5, 27, 123, 27, 4.0); L.railing(119.5, 33, 123, 33, 4.0)
	sprocket_line(A, Vector3(120.5, 4.9, 28), Vector3(120.5, 4.9, 32), 3, 10)
	DocksDressing.place(L, "crates", Vector3(127, 0, 21), 0.3, 1.6, true)
	DocksDressing.place(L, "crates", Vector3(133, 0, 39.5), 1.4, 1.4, true)
	DocksDressing.place(L, "barrels", Vector3(136, 0, 20), 0.0, 1.3, true)
	DocksDressing.place(L, "fuel_tanks", Vector3(124, 0, 39.6), 0.0, 2.6, true)
	_fuel_line(L, [Vector3(126.5, 0.5, 39.6), Vector3(129, 0.5, 39.6), Vector3(129, 3.2, 37.0)])
	L.crate_spots.append(Vector3(117, 0, 21)); L.crate_spots.append(Vector3(117, 0, 39))
	sprocket_line(A, Vector3(126, 1.0, 30), Vector3(134, 1.0, 30), 5)
	jib_crane(L, A, Vector3(115.5, 0, 40.0), 3.0, 11.0, -PI * 0.6, 0.5, 24.0, 6)
	for z in range(19, 42, 3):
		beacon(L, A, Vector3(137.85, 0.15, z), Color(1, 0.3, 0.2) if z < 30 else Color(0.25, 1, 0.45), 2.0, z * 0.03, 0.2, 0.1)
	A.horns.append({ node = ship, every = 38.0, t = 12.0, sound = "docks_ship_horn", db = 2.0 })

# ------------------------------------------------------------------ extra life on Piers A, B and C
static func _piers_abc(L: Node3D, A: Node3D) -> void:
	# corner and edge signal lights: red to port (north), green to starboard
	for c in [[28.3, 16.3, 0.0], [49.7, 16.3, 0.0], [28.3, 43.7, 0.0], [49.7, 43.7, 0.0], [50.3, -15.7, 4.0], [65.7, -15.7, 4.0],
			[65.7, -0.3, 4.0], [60.3, -45.7, 6.0], [75.7, -45.7, 6.0], [75.7, -30.3, 6.0], [60.3, -30.3, 6.0]]:
		beacon(L, A, Vector3(c[0], c[2] + 1.35, c[1]), Color(1, 0.25, 0.2) if c[1] < 0 else Color(0.25, 1, 0.45), 2.0, randf(), 0.25, 0.14)
		L.cyl(Vector3(c[0], c[2] + 0.6, c[1]), 0.06, 0.08, 1.2, L.mat_dark, 6)
	# fuel lines along Pier A's south rail and Pier B's east edge
	_fuel_line(L, [Vector3(30, 0.35, 43.4), Vector3(48, 0.35, 43.4)])
	_fuel_line(L, [Vector3(65.4, 4.35, -12), Vector3(65.4, 4.35, -3.5)])
	# a tall crane pylon east of Pier C swinging a load over the deck (well above head height)
	jib_crane(L, A, Vector3(82, -11, -38), 20.0, 12.0, PI, 0.5, 34.0, 0)
	L.box(Vector3(82, -11.5, -38), Vector3(5, 1.0, 5), L.mat_dark, false)
	# cargo drones ferrying crates between the piers, the depot and the berth
	_drone(L, A, [Vector3(39, 14, 30), Vector3(70, 15, 19), Vector3(98, 15, 12), Vector3(126, 17, 26), Vector3(98, 16, 8), Vector3(70, 15, 15)], 6.0)
	_drone(L, A, [Vector3(58, 15, -8), Vector3(70, 16, -38), Vector3(92, 18, -22), Vector3(100, 16, 4)], 5.0)
	_drone(L, A, [Vector3(60, 13, 46), Vector3(100, 14, 50), Vector3(126, 15, 44), Vector3(90, 13, 40)], 5.5)
	_drone(L, A, [Vector3(34, 12, 12), Vector3(44, 13, -12), Vector3(76, 14, -14), Vector3(62, 12, 8)], 4.5)

## a little quad-rotor cargo drone with a crate slung underneath
static func _drone(L: Node3D, A: Node3D, pts: Array, speed: float) -> void:
	var n := Node3D.new(); L.add_child(n)
	var body := _m("drone_body", func(): return M.paint(Color(0.95, 0.72, 0.15))) as Material
	L.box(Vector3(0, 0, 0), Vector3(1.1, 0.4, 1.1), body, false, n)
	L.box(Vector3(0, 0.25, 0), Vector3(0.6, 0.2, 0.6), L.mat_dark, false, n)
	for c in [Vector3(-0.9, 0.1, -0.9), Vector3(0.9, 0.1, -0.9), Vector3(-0.9, 0.1, 0.9), Vector3(0.9, 0.1, 0.9)]:
		var arm: MeshInstance3D = L.box(c * 0.55, Vector3(0.9, 0.08, 0.1), L.mat_dark, false, n)
		arm.rotation.y = atan2(-c.z, c.x)
		var rotor := Node3D.new(); rotor.position = c + Vector3(0, 0.12, 0); n.add_child(rotor)
		var disc := CylinderMesh.new(); disc.top_radius = 0.55; disc.bottom_radius = 0.55; disc.height = 0.02; disc.radial_segments = 16
		var dm := M.std(Color(0.2, 0.22, 0.25, 0.35), 0.2, 0.5); dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		L.mesh_at(disc, _m("rotor_disc", func(): return dm), Vector3.ZERO, rotor)
		L.box(Vector3.ZERO, Vector3(1.0, 0.03, 0.1), L.mat_dark, false, rotor)
		A.spinners.append({ node = rotor, axis = Vector3.UP, speed = 30.0 })
	L.cyl(Vector3(0, -0.8, 0), 0.02, 0.02, 1.2, L.mat_dark, 4).reparent(n, false)
	DocksDressing.place(n, "crates", Vector3(0, -2.4, 0), randf() * TAU, 1.0, false)
	beacon(L, A, Vector3(0, -0.25, 0.58), Color(1, 0.3, 0.2), 0.8, randf(), 0.3, 0.07, false, n)
	var pv := PackedVector3Array(pts)
	n.position = pv[0]
	A.loopers.append({ node = n, pts = pv, len = Anim.loop_len(pv), speed = speed, d = randf() * 20.0, yaw_off = 0.0 })
