extends Node3D
## Skyharbor, the first planet: a floating sky city at dawn, hub and spoke around the Dock Plaza.
## North is -z. Areas (floor height in brackets):
##   Junkyard (south, start, 0)      Vesk's porch and workbench; tutorial: run, jump, wrench, Dodger's crank
##   Dock Plaza (hub, 0)             Gizmart, the sealed bank vault, gates north to the Crane Yard
##   Terrace -> Roof Gardens (west)  double jump tiers (0, 2.4, 4.8), glide gap (4.0), pillars, gardens (8.8);
##                                   bounce pad and chute rail back to the plaza
##   Cargo Docks (east)              Pier A (0) -rail-> Pier B (4) -rail-> Pier C (6) between hanging containers,
##                                   3 wind turbines; the cargo lift from Pier C back to the plaza once powered
##   Signal Mast (center)            hook chains from the Gardens promenade and from Pier C; gallery (8),
##                                   ledges spiral up the mast to the dish deck (20); rail down to the Crane Yard
##   Crane Yard (north)              gate island (0, second Gizmart) and the boss arena; sealed until the dish
##                                   is aligned
## Debug: `-- --at=<spot>` starts at a named spot (see debug_spots).

const M := preload("res://scripts/mats.gd")

var start_pos := Vector3(0, 0.5, 91)
var start_yaw := PI
var rails: Array = []          # { curve: Curve3D, path: Path3D, locked: bool, glow: StandardMaterial3D }
var hooks: Array = []          # Node3D (hook position = global_position)
var bouncers: Array = []       # { pos: Vector3, power: float, node: Node3D, squash: float }
var movers: Array = []         # { id, body: AnimatableBody3D, a: Vector3, b: Vector3, period: float, powered: bool, t: float }
var checkpoints: Array = []    # { pos: Vector3, r: float }
var gates := {}                # id -> Node3D (a force-field gate, removed by open_gate)
var islands := {}              # name -> Rect2
var heights := {}              # name -> floor height
## Story zones in play order (read by story.gd; see the key list at the top of that script).
var zones: Array = []
## Spots other systems read (filled in _define_zones; systems must cope with these being empty):
var shop_spots: Array = []      # { pos: Vector3, yaw: float, stock: Array of item ids }
var crate_spots: Array = []     # Vector3 (breakable nut crates)
var pickup_spots: Array = []    # { kind: "washer"|"page", id: String, pos: Vector3 }
var gripe_ids: Array = []       # skill tasks on this level, e.g. "return_to_sender"
## Locked-for-later spots (gadgets from later planets).
var vault_door := { pos = Vector3(11, 0, 41), yaw = -PI / 2, needs = "pulse_key" }
var mast_top := Vector3(14, 20, -34)     # landmark: the relay dish
var debug_spots := {}
var t := 0.0

# rail indexes (set in _build)
var R_DOCKS_1 := -1
var R_DOCKS_2 := -1
var R_CHUTE := -1
var R_YARD := -1

var turbines: Array = []       # { node: Node3D, rotor: Node3D, spin: float }
var dish_pivot: Node3D
var dish_glow: StandardMaterial3D
var dish_light: OmniLight3D
var dish_target := Vector2.ZERO   # yaw, pitch the pivot eases toward

var mat_white := M.std(Color(0.93, 0.95, 0.97), 0.6, 0.3)
var mat_blue := M.std(Color(0.37, 0.56, 0.69), 0.7, 0.32)
var mat_teal := M.std(Color(0.25, 0.62, 0.63), 0.7, 0.3)
var mat_dark := M.std(Color(0.2, 0.25, 0.3), 0.75, 0.4)
var mat_brass := M.std(Color(0.85, 0.64, 0.26), 0.9, 0.3)
var mat_rust := M.std(Color(0.55, 0.36, 0.24), 0.5, 0.7)
var mat_wood := M.std(Color(0.55, 0.38, 0.24), 0.0, 0.8)
var glow_cyan := M.glow(Color(0.25, 0.94, 1.0), 4.0)
var glow_warm := M.glow(Color(1.0, 0.63, 0.19), 3.0)

func _ready() -> void:
	_build()
	_debug_start()

func rect(cx: float, cz: float, w: float, d: float) -> Rect2:
	return Rect2(cx - w / 2, cz - d / 2, w, d)

# ---------- building blocks ----------
func mesh_at(m: Mesh, mat: Material, pos: Vector3, parent: Node = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi

func box(pos: Vector3, size: Vector3, mat: Material, collide := true, parent: Node = self) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	var mi := mesh_at(bm, mat, pos, parent)
	if collide:
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		sb.add_child(cs)
		mi.add_child(sb)
	return mi

## a raised block standing on y0 with a glowing lip
func block(x: float, z: float, sx: float, sz: float, h: float, y0 := 0.0, mat: Material = null, lip := true) -> MeshInstance3D:
	var m := box(Vector3(x, y0 + h / 2, z), Vector3(sx, h, sz), mat if mat else M.deck(Color(0.75, 0.82, 0.88)))
	if lip: box(Vector3(x, y0 + h - 0.03, z), Vector3(sx + 0.03, 0.05, sz + 0.03), glow_warm, false)
	return m

func cyl(pos: Vector3, r_top: float, r_bot: float, h: float, mat: Material, sides := 24, collide := false) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = sides
	var mi := mesh_at(cm, mat, pos)
	if collide:
		var sb := StaticBody3D.new(); var cs := CollisionShape3D.new(); var sh := CylinderShape3D.new()
		sh.radius = maxf(r_top, r_bot); sh.height = h; cs.shape = sh; sb.add_child(cs); mi.add_child(sb)
	return mi

## a floating deck with a rocky, glowing underside; y is the walking height
func island(name_: String, r: Rect2, y := 0.0, tint := Color(1, 1, 1), thick := 1.2) -> void:
	islands[name_] = r; heights[name_] = y
	var c := r.get_center()
	var deck_mat: Material = M.worn("deck", tint * 0.92, 0.14, 0.45, 0.6, 0.55) if name_.begins_with("pier") else M.deck(tint)
	box(Vector3(c.x, y - thick / 2, c.y), Vector3(r.size.x, thick, r.size.y), deck_mat)
	var rad: float = min(r.size.x, r.size.y) * 0.48
	var top := y - thick
	var under := cyl(Vector3(c.x, top - rad * 0.85, c.y), rad, rad * 0.22, rad * 1.7, mat_dark, 8)
	under.scale = Vector3(r.size.x / min(r.size.x, r.size.y), 1, r.size.y / min(r.size.x, r.size.y))
	cyl(Vector3(c.x, top - rad * 1.7, c.y), rad * 0.3, rad * 0.3, 0.6, glow_cyan)
	if rad > 4.0:
		var lamp_ := OmniLight3D.new()
		lamp_.light_color = Color(0.3, 0.9, 1.0)
		lamp_.light_energy = 3.0
		lamp_.omni_range = rad * 1.5
		lamp_.position = Vector3(c.x, top - rad * 1.9, c.y)
		add_child(lamp_)
	# hazard edging with a glowing strip so the drop is easy to see
	var hz := M.hazard()
	for e in [[Vector3(c.x, y - 0.08, r.position.y), Vector3(r.size.x, 0.22, 0.3)], [Vector3(c.x, y - 0.08, r.end.y), Vector3(r.size.x, 0.22, 0.3)],
			[Vector3(r.position.x, y - 0.08, c.y), Vector3(0.3, 0.22, r.size.y)], [Vector3(r.end.x, y - 0.08, c.y), Vector3(0.3, 0.22, r.size.y)]]:
		box(e[0], e[1], hz, false)
		box(e[0] + Vector3(0, -0.2, 0), e[1] * Vector3(1, 0.25, 1) + Vector3(0.02, 0, 0.02), glow_cyan, false)

## a plain walkway slab (top at y)
func walkway(x1: float, z1: float, x2: float, z2: float, y := 0.0) -> void:
	var r := Rect2(minf(x1, x2), minf(z1, z2), absf(x2 - x1), absf(z2 - z1))
	var c := r.get_center()
	box(Vector3(c.x, y - 0.3, c.y), Vector3(r.size.x, 0.6, r.size.y), M.deck(Color(0.86, 0.8, 0.7)))
	for sx in [r.position.x, r.end.x]:
		if r.size.x < r.size.y: box(Vector3(sx, y + 0.06, c.y), Vector3(0.12, 0.12, r.size.y), glow_cyan, false)
	for sz in [r.position.y, r.end.y]:
		if r.size.x >= r.size.y: box(Vector3(c.x, y + 0.06, sz), Vector3(r.size.x, 0.12, 0.12), glow_cyan, false)

## railing along an edge; solid so you don't walk off by accident
func railing(x1: float, z1: float, x2: float, z2: float, y := 0.0) -> void:
	var len := Vector2(x2 - x1, z2 - z1).length()
	if len < 0.5: return
	var mid := Vector3((x1 + x2) / 2, y, (z1 + z2) / 2)
	var along_x := absf(x2 - x1) > absf(z2 - z1)
	box(mid + Vector3(0, 1.0, 0), Vector3(len if along_x else 0.1, 0.1, 0.1 if along_x else len), mat_white, false)
	box(mid + Vector3(0, 0.88, 0), Vector3(len if along_x else 0.04, 0.04, 0.04 if along_x else len), glow_cyan, false)
	var n := maxi(1, roundi(len / 2.4))
	for i in n + 1:
		var u := float(i) / n
		cyl(Vector3(lerpf(x1, x2, u), y + 0.5, lerpf(z1, z2, u)), 0.05, 0.06, 1.0, mat_white, 8)
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(len if along_x else 0.25, 1.1, 0.25 if along_x else len)
	cs.shape = sh
	sb.position = mid + Vector3(0, 0.55, 0)
	sb.add_child(cs)
	add_child(sb)

## railings round a rect, leaving gaps: gaps = [[side, from, to], ...] side "n","s","e","w"
func fence(r: Rect2, y: float, gaps: Array, sides := "nsew") -> void:
	for side in sides:
		var horiz: bool = side == "n" or side == "s"
		var a: float = r.position.x if horiz else r.position.y
		var b: float = r.end.x if horiz else r.end.y
		var fixed: float = (r.position.y if side == "n" else r.end.y) if horiz else (r.position.x if side == "w" else r.end.x)
		var cuts := []
		for g in gaps: if g[0] == side: cuts.append(Vector2(g[1], g[2]))
		cuts.sort_custom(func(p, q): return p.x < q.x)
		var cur := a
		for cut in cuts:
			if cut.x > cur:
				if horiz: railing(cur, fixed, cut.x, fixed, y)
				else: railing(fixed, cur, fixed, cut.x, y)
			cur = maxf(cur, cut.y)
		if b > cur:
			if horiz: railing(cur, fixed, b, fixed, y)
			else: railing(fixed, cur, fixed, b, y)

func lamp(x: float, z: float, c := Color(1.0, 0.75, 0.45), y := 0.0) -> void:
	cyl(Vector3(x, y + 1.6, z), 0.07, 0.1, 3.2, mat_dark, 8)
	var s := SphereMesh.new(); s.radius = 0.2; s.height = 0.4
	mesh_at(s, M.glow(c, 6.0), Vector3(x, y + 3.25, z))
	var l := OmniLight3D.new()
	l.light_color = c; l.light_energy = 2.5; l.omni_range = 9.0
	l.position = Vector3(x, y + 3.1, z)
	add_child(l)

func label(text: String, pos: Vector3, size := 2.0, color := Color(1, 0.9, 0.6), yaw := 0.0) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 160
	l.pixel_size = size / 160.0
	l.modulate = Color(color, 0.55)
	l.outline_size = 0
	l.rotation = Vector3(-PI / 2, yaw, 0)
	l.position = pos + Vector3(0, 0.02, 0)
	l.shaded = false
	add_child(l)

## an upright hint sign on a post
func hint_sign(text: String, pos: Vector3, yaw := 0.0, color := Color(1, 0.88, 0.55)) -> void:
	var n := Node3D.new(); n.position = pos; n.rotation.y = yaw; add_child(n)
	Kit.place(n, "sign_board", Vector3.ZERO, 0.0, 1.0, false)
	var l := Label3D.new(); l.text = text; l.font_size = 48; l.pixel_size = 0.005
	l.modulate = color; l.outline_size = 10; l.position = Vector3(0, 2.2, 0.08); l.width = 420.0
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; l.double_sided = false
	n.add_child(l)
	var l2: Label3D = l.duplicate(); l2.rotation.y = PI; l2.position.z = -0.08; n.add_child(l2)

func sky_pad(x: float, z: float, w: float, d: float, y := 0.0) -> void:
	block(x, z, w, d, 0.6, y - 0.6, M.deck(Color(0.78, 0.86, 0.92)))
	cyl(Vector3(x, y - 1.7, z), 0.0, min(w, d) * 0.45, 2.2, mat_dark, 6)
	var s := SphereMesh.new(); s.radius = 0.3; s.height = 0.6
	mesh_at(s, glow_cyan, Vector3(x, y - 2.9, z))

## a floating ledge (top at y) for climbing
func ledge(x: float, z: float, w: float, d: float, y: float, mat: Material = null) -> void:
	block(x, z, w, d, 0.5, y - 0.5, mat if mat else M.deck(Color(0.82, 0.78, 0.7)))
	cyl(Vector3(x, y - 1.1, z), 0.05, min(w, d) * 0.4, 1.2, mat_dark, 6)

func prop(name_: String, pos: Vector3, rot_y := 0.0, scale_ := 1.0, collide := true) -> Node3D:
	return Kit.place(self, name_, pos, rot_y, scale_, collide)

func moving_platform(a: Vector3, b: Vector3, period: float, size := Vector3(4.5, 0.6, 4.5), id := "", powered := true) -> void:
	var body := AnimatableBody3D.new()
	body.sync_to_physics = true
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new(); sh.size = size
	cs.shape = sh
	body.add_child(cs)
	var bm := BoxMesh.new(); bm.size = size
	var mi := MeshInstance3D.new(); mi.mesh = bm; mi.material_override = M.deck(Color(0.8, 0.88, 0.94))
	body.add_child(mi)
	var lip := BoxMesh.new(); lip.size = Vector3(size.x + 0.03, 0.05, size.z + 0.03)
	var lm := MeshInstance3D.new(); lm.mesh = lip; lm.material_override = glow_cyan if powered else M.glow(Color(1, 0.2, 0.2), 3.0)
	lm.position.y = size.y / 2 - 0.03
	body.add_child(lm)
	for sx in [-1, 1]:
		var j := CylinderMesh.new(); j.top_radius = 0.35; j.bottom_radius = 0.5; j.height = 0.6
		var jm := MeshInstance3D.new(); jm.mesh = j; jm.material_override = mat_dark; jm.position = Vector3(sx * size.x * 0.3, -0.55, 0)
		body.add_child(jm)
		var f := SphereMesh.new(); f.radius = 0.28; f.height = 0.56
		var fm := MeshInstance3D.new(); fm.mesh = f; fm.material_override = glow_cyan; fm.position = Vector3(sx * size.x * 0.3, -0.9, 0)
		body.add_child(fm)
	body.position = a
	add_child(body)
	movers.append({ id = id, body = body, a = a, b = b, period = period, powered = powered, t = 0.0, lip = lm })

func bounce_pad(pos: Vector3, power_: float) -> void:
	var n := Node3D.new(); n.position = pos; add_child(n)
	var base := CylinderMesh.new(); base.top_radius = 1.1; base.bottom_radius = 1.25; base.height = 0.25
	mesh_at(base, mat_dark, Vector3(0, 0.12, 0), n)
	var top := CylinderMesh.new(); top.top_radius = 0.95; top.bottom_radius = 0.95; top.height = 0.1
	mesh_at(top, M.glow(Color(0.5, 1.0, 0.6), 3.0), Vector3(0, 0.27, 0), n)
	var l := OmniLight3D.new(); l.light_color = Color(0.5, 1, 0.6); l.light_energy = 2.0; l.omni_range = 5; l.position.y = 0.8
	n.add_child(l)
	bouncers.append({ pos = pos, power = power_, node = n, squash = 0.0 })

func hook(pos: Vector3) -> void:
	var n := Node3D.new(); n.position = pos; add_child(n)
	var tor := TorusMesh.new(); tor.inner_radius = 0.42; tor.outer_radius = 0.66
	var ring := mesh_at(tor, mat_brass, Vector3.ZERO, n); ring.rotation_degrees.x = 90
	var s := SphereMesh.new(); s.radius = 0.22; s.height = 0.44
	mesh_at(s, M.glow(Color(1.0, 0.8, 0.35), 5.0), Vector3.ZERO, n)
	var body := BoxMesh.new(); body.size = Vector3(1.2, 0.45, 1.2)
	mesh_at(body, mat_dark, Vector3(0, 0.9, 0), n)
	for sx in [-1, 1]:
		var p := CylinderMesh.new(); p.top_radius = 0.5; p.bottom_radius = 0.5; p.height = 0.04
		var pm := M.std(Color(1, 1, 1, 0.4), 0.3, 0.4); pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mesh_at(p, pm, Vector3(sx * 0.8, 1.2, 0), n)
	var l := OmniLight3D.new(); l.light_color = Color(1, 0.8, 0.35); l.light_energy = 2.0; l.omni_range = 6
	n.add_child(l)
	n.set_meta("ring", ring)
	hooks.append(n)

## returns the rail's index
func rail(points: Array, locked := false) -> int:
	var path := Path3D.new()
	var curve := Curve3D.new()
	curve.bake_interval = 0.2
	for p in points: curve.add_point(p)
	for i in curve.point_count:
		var prev: Vector3 = curve.get_point_position(maxi(i - 1, 0))
		var nxt: Vector3 = curve.get_point_position(mini(i + 1, curve.point_count - 1))
		var tan := (nxt - prev) / 6.0
		curve.set_point_in(i, -tan)
		curve.set_point_out(i, tan)
	path.curve = curve
	add_child(path)
	var tube := CSGPolygon3D.new()
	tube.mode = CSGPolygon3D.MODE_PATH
	tube.path_node = NodePath("..")
	var poly := PackedVector2Array()
	for k in 10: poly.append(Vector2(cos(k * TAU / 10), sin(k * TAU / 10)) * 0.13)
	tube.polygon = poly
	tube.path_interval_type = CSGPolygon3D.PATH_INTERVAL_DISTANCE
	tube.path_interval = 0.5
	tube.path_rotation = CSGPolygon3D.PATH_ROTATION_PATH_FOLLOW
	tube.smooth_faces = true
	tube.material = M.std(Color(0.85, 0.89, 0.92), 0.95, 0.18)
	path.add_child(tube)
	var g := M.glow(Color(1.0, 0.19, 0.19) if locked else Color(1.0, 0.7, 0.23), 3.0)
	var glow_tube := CSGPolygon3D.new()
	glow_tube.mode = CSGPolygon3D.MODE_PATH
	glow_tube.path_node = NodePath("..")
	var gp := PackedVector2Array()
	for k in 6: gp.append(Vector2(cos(k * TAU / 6), sin(k * TAU / 6)) * 0.04 + Vector2(0, -0.17))
	glow_tube.polygon = gp
	glow_tube.path_interval_type = CSGPolygon3D.PATH_INTERVAL_DISTANCE
	glow_tube.path_interval = 0.5
	glow_tube.path_rotation = CSGPolygon3D.PATH_ROTATION_PATH_FOLLOW
	glow_tube.material = g
	path.add_child(glow_tube)
	var L := curve.get_baked_length()
	var u := 4.0
	while u < L - 2.0:
		var p := curve.sample_baked(u)
		cyl(p + Vector3(0, -15.15, 0), 0.1, 0.16, 30, mat_dark, 8)
		u += 10.0
	rails.append({ curve = curve, path = path, locked = locked, glow = g, length = L })
	return rails.size() - 1

func set_rail_locked(i: int, v: bool) -> void:
	if i < 0 or i >= rails.size(): return
	var r: Dictionary = rails[i]
	r.locked = v
	r.glow.emission = Color(1.0, 0.19, 0.19) if v else Color(1.0, 0.7, 0.23)

## a red force-field gate; open_gate(id) drops it
func gate(id: String, center: Vector3, width: float, height := 4.0, along_x := true) -> void:
	var n := Node3D.new(); n.position = center; add_child(n)
	var field := M.std(Color(1, 0.25, 0.2, 0.35), 0.0, 0.2)
	field.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; field.emission_enabled = true
	field.emission = Color(1, 0.3, 0.2); field.emission_energy_multiplier = 1.5
	field.cull_mode = BaseMaterial3D.CULL_DISABLED
	var size := Vector3(width, height, 0.3) if along_x else Vector3(0.3, height, width)
	box(Vector3(0, height / 2, 0), size, field, true, n)
	for s in [-1, 1]:
		var off: Vector3 = Vector3(s * width / 2, 0, 0) if along_x else Vector3(0, 0, s * width / 2)
		box(off + Vector3(0, height / 2 + 0.2, 0), Vector3(0.5, height + 0.4, 0.5), mat_dark, true, n)
		mesh_at(SphereMesh.new(), M.glow(Color(1, 0.3, 0.2), 5.0), off + Vector3(0, height + 0.6, 0), n).scale = Vector3.ONE * 0.5
	gates[id] = n

func open_gate(id: String) -> void:
	print_verbose("[level] open gate ", id)
	var n: Node3D = gates.get(id)
	if n == null or not is_instance_valid(n): return
	gates.erase(id)
	for sb in n.find_children("*", "StaticBody3D", true, false): sb.queue_free()
	Snd.at("rail_unlock", n.global_position, 0)
	FX.ring(n.global_position + Vector3(0, 0.1, 0), Color(0.5, 1, 0.6))
	var tw := create_tween(); tw.tween_property(n, "position:y", n.position.y - 6.0, 1.2).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(n.queue_free)

## start a mover that was waiting for power (the cargo lift)
func power(id: String) -> void:
	for m in movers:
		if m.id == id and not m.powered:
			m.powered = true; m.t = 0.0
			m.lip.material_override = glow_cyan
			Snd.at("rail_unlock", m.body.global_position, 0)

func turbine(pos: Vector3, rot_y := 0.0) -> void:
	var n := prop("wind_turbine", pos, rot_y, 1.0, true)
	var rotor: Node3D = n.find_child("*otor*", true, false)
	if rotor == null: rotor = n.find_child("*lade*", true, false)
	if rotor == null:
		rotor = Node3D.new(); rotor.position = Vector3(0, 7.4, 1.6); n.add_child(rotor)
		var hub := SphereMesh.new(); hub.radius = 0.35; hub.height = 0.7
		mesh_at(hub, mat_brass, Vector3.ZERO, rotor)
		for i in 3:
			var bmesh := BoxMesh.new(); bmesh.size = Vector3(0.4, 3.2, 0.08)
			var bl := mesh_at(bmesh, M.std(Color(0.95, 0.93, 0.85), 0.1, 0.5), Vector3.ZERO, rotor)
			bl.rotation.z = i * TAU / 3; bl.position = Vector3(sin(i * TAU / 3) * -1.6, cos(i * TAU / 3) * 1.6, 0)
	turbines.append({ node = n, rotor = rotor, spin = 0.08 })

# ---------- the level ----------
func _build() -> void:
	_build_junkyard()
	_build_plaza()
	_build_terrace()
	_build_docks()
	_build_mast()
	_build_crane_yard()
	_build_city()
	_define_zones()
	preload("res://scripts/level/areas.gd").build_all(self)
	debug_spots = {
		start = [start_pos, PI], plaza = [Vector3(0, 0.1, 40), PI], docks = [Vector3(39, 0.1, 24), PI],
		pier_c = [Vector3(64, 6.1, -38), -PI / 2], terrace = [Vector3(-32, 0.1, 40), -PI / 2],
		glide = [Vector3(-55, 4.9, -1), PI], gardens = [Vector3(-23, 8.9, -36), PI / 2], gallery = [Vector3(20, 8.1, -40), -PI / 2],
		dish = [Vector3(17, 20.1, -31), -PI * 0.75], yard = [Vector3(0, 0.1, -62), PI], arena = [Vector3(0, 0.1, -84), PI],
		vault = [Vector3(2, 0.1, 41), PI / 2],
	}

func _build_junkyard() -> void:
	# Vesk's junkyard: a walled pocket south of the plaza. Tutorial: run, hop the junk walls, climb the
	# scrap pile to Dodger, wrench the bots, then crank Dodger's launcher to open the gate.
	var r := rect(0, 82, 36, 28)
	island("junkyard", r, 0.0, Color(0.92, 0.86, 0.76))
	for w in [[0, 96.4, 36.8, 0.8], [-18.4, 82, 0.8, 28.8], [18.4, 82, 0.8, 28.8]]:
		box(Vector3(w[0], 1.25, w[1]), Vector3(w[2], 2.5, w[3]), mat_rust)
	railing(-18, 68, -3.5, 68); railing(3.5, 68, 18, 68)
	gate("junk_gate", Vector3(0, 0, 68), 7.0, 3.5)
	# porch and workbench (the brass gear "paperweight" sits on the bench)
	block(0, 93, 12, 5, 0.4, 0, mat_wood, false)
	for x in [-5.6, 5.6]: cyl(Vector3(x, 0.9, 90.8), 0.1, 0.1, 1.0, mat_wood, 8)
	prop("porch_chair", Vector3(-2.5, 0.4, 93.5), PI)
	prop("workbench", Vector3(4, 0.4, 94), PI)
	var gear := Node3D.new(); gear.name = "BrassGear"; gear.position = Vector3(3.6, 1.45, 94); add_child(gear)
	var gm := CylinderMesh.new(); gm.top_radius = 0.24; gm.bottom_radius = 0.24; gm.height = 0.08
	var g0 := mesh_at(gm, mat_brass, Vector3.ZERO, gear)
	for i in 10:
		var tm := BoxMesh.new(); tm.size = Vector3(0.08, 0.08, 0.06)
		var tooth := mesh_at(tm, mat_brass, Vector3(cos(i * TAU / 10) * 0.27, 0, sin(i * TAU / 10) * 0.27), gear)
		tooth.rotation.y = -i * TAU / 10
	g0.set_meta("heart_cog", true)
	lamp(-6.5, 91, Color(1, 0.7, 0.4)); lamp(6.5, 91, Color(1, 0.7, 0.4))
	prop("water_tower", Vector3(14, 0, 92))
	prop("generator", Vector3(10, 0, 94.5), 0.3)
	prop("antenna", Vector3(-15, 0, 94))
	# tutorial run: low junk walls to hop
	block(0, 86, 9, 0.8, 0.8, 0, mat_rust)
	block(-3, 80.5, 0.8, 7, 1.0, 0, mat_rust)
	hint_sign("HOP OVER", Vector3(4.8, 0, 87), PI)
	# the scrap pile where Dodger crashed (two jumps up), and a hidden shelf above it
	block(-9, 78.5, 4, 4, 1.2, 0, mat_rust)
	block(-12.5, 74.5, 4, 3.4, 2.4, 0, mat_rust)
	ledge(-16.2, 70.6, 2.2, 2.2, 3.6, mat_rust)
	prop("scrap_heap", Vector3(-12, 0, 85), 0.4, 1.0, true)
	prop("junk_pile", Vector3(10, 0, 76), 1.2)
	prop("junk_pile", Vector3(-14.5, 0, 90), 0.2)
	prop("scrap_heap", Vector3(13, 0, 84), 2.0)
	for b in [Vector3(15.5, 0, 70.5), Vector3(16.5, 0, 72), Vector3(-6, 0, 70.5)]: prop("barrel", b, randf() * TAU)
	label("JUNKYARD", Vector3(0, 0, 76), 7, Color(1, 0.8, 0.55))
	hint_sign("KEEP OUT. I MEAN IT. -V", Vector3(-6, 0, 69), PI)
	checkpoints.append({ pos = start_pos, r = 2.4 })
	# bridge to the plaza: two pads and a sliding platform
	sky_pad(0, 63.5, 5, 5)
	sky_pad(-2.5, 55.5, 5, 5)
	moving_platform(Vector3(-5, -0.3, 49.8), Vector3(5, -0.3, 49.8), 7.0)

func _build_plaza() -> void:
	var r := rect(0, 30, 44, 32)
	island("plaza", r, 0.0, Color(1.0, 0.97, 0.92))
	fence(r, 0.0, [["s", -8, 8], ["w", 29, 37], ["e", 26, 34], ["e", 12, 20], ["n", -11, -1]])
	# fountain in the middle
	cyl(Vector3(0, 0.4, 28), 3.0, 3.3, 0.8, mat_teal, 24, true)
	cyl(Vector3(0, 0.82, 28), 2.7, 2.7, 0.08, M.glow(Color(0.38, 0.88, 1), 1.5))
	cyl(Vector3(0, 1.6, 28), 0.4, 0.6, 1.6, mat_brass, 12)
	for p in [Vector2(-8, 20), Vector2(8, 20), Vector2(-8, 38), Vector2(8, 38)]: prop("bench", Vector3(p.x, 0, p.y), 0.0 if p.y > 30 else PI)
	for p in [Vector2(-20, 16), Vector2(20, 16), Vector2(-20, 44), Vector2(20, 22), Vector2(-4, 44), Vector2(4, 44)]:
		lamp(p.x, p.y, Color(1, 0.8, 0.5))
	for p in [Vector2(-12, 24), Vector2(12, 24)]: prop("planter", Vector3(p.x, 0, p.y))
	prop("market_stall", Vector3(-17, 0, 22), PI / 2)
	prop("awning", Vector3(-17, 0, 26), PI / 2, 1.0, false)
	prop("flag_pole", Vector3(-6, 0, 15), 0.0, 1.0, false); prop("flag_pole", Vector3(6, 0, 15), 0.0, 1.0, false)
	label("DOCK PLAZA", Vector3(0, 0, 34), 9)
	checkpoints.append({ pos = Vector3(0, 0.1, 40), r = 3.0 })
	# the bank: a sealed vault (needs the Pulse Key from Dustvein Gulch); the Pink Slip Page is inside
	var bx := 16.0; var bz := 41.0
	for w in [[bx, bz - 4, 10, 0.5], [bx, bz + 4, 10, 0.5], [bx + 5, bz, 0.5, 8], [bx - 5, bz - 2.75, 0.5, 2.5], [bx - 5, bz + 2.75, 0.5, 2.5]]:
		box(Vector3(w[0], 2.25, w[1]), Vector3(w[2], 4.5, w[3]), M.std(Color(0.88, 0.84, 0.74), 0.2, 0.5))
	box(Vector3(bx, 4.75, bz), Vector3(10.6, 0.5, 8.6), mat_brass)
	box(Vector3(bx - 5, 3.75, bz), Vector3(0.5, 1.5, 3.0), M.std(Color(0.88, 0.84, 0.74), 0.2, 0.5))
	prop("bank_vault_door", Vector3(bx - 5.1, 0, bz), -PI / 2)
	hint_sign("SKYHARBOR SAVINGS & LOAN. VAULT SEALED: PULSE KEY REQUIRED", Vector3(bx - 6.5, 0, bz - 3.4), -PI / 2)
	# bridges: west to the Terrace, east to the docks, north to the causeway
	walkway(-28, 30, -22, 36)
	walkway(22, 27, 28, 33)
	walkway(-9, 9, -3, 14)
	gate("causeway_gate", Vector3(-6, 0, 11.5), 7.0, 4.0)
	hint_sign("CRANE YARD: CLOSED FOR SIGNAL MAINTENANCE", Vector3(-1, 0, 15.5), 0.0)

func _build_terrace() -> void:
	# Market Terrace (west of the plaza), then tiers that need the double jump, a glide gap, pillars,
	# and the Roof Gardens on top
	var t1 := rect(-39, 37, 22, 26)
	island("terrace", t1, 0.0, Color(1.0, 0.95, 0.88))
	# (the market dressing, the bazaar, tea terrace and loft are built in scripts/level/terrace/)
	fence(t1, 0.0, [["e", 29, 37], ["w", 24, 50]], "nsew")
	label("MARKET TERRACE", Vector3(-39, 0, 38), 7)
	checkpoints.append({ pos = Vector3(-36, 0.1, 37), r = 3.0 })
	hint_sign("DOUBLE JUMP: JUMP AGAIN IN THE AIR", Vector3(-47, 0, 31), PI / 2)
	# tier 2 (2.4) and tier 3 (4.8): double jumps
	island("tier2", rect(-56, 22, 12, 16), 2.4, Color(0.95, 0.9, 0.82), 3.6)
	island("tier3", rect(-55, 3, 14, 12), 4.8, Color(0.95, 0.9, 0.82), 1.6)
	prop("planter", Vector3(-53, 2.4, 21)); prop("vent_stack", Vector3(-60, 2.4, 16), 0.0, 1.0, true)
	prop("chimney", Vector3(-60.5, 4.8, -0.5), 0.0, 1.0, true)
	checkpoints.append({ pos = Vector3(-55, 4.9, 3), r = 3.0 })
	hint_sign("GLIDE: HOLD JUMP AFTER THE DOUBLE JUMP", Vector3(-50, 4.8, -2), PI)
	# the glide gap to tier 4 (4.0)
	island("tier4", rect(-47, -20, 14, 12), 4.0, Color(0.9, 0.95, 0.88))
	prop("water_tower", Vector3(-52, 4.0, -24))
	checkpoints.append({ pos = Vector3(-46, 4.1, -18), r = 3.0 })
	# chimney pillars up to the gardens
	block(-37, -17, 3, 3, 0.8, 5.6, M.deck(Color(0.85, 0.6, 0.45)))
	cyl(Vector3(-37, 2.6, -17), 1.0, 1.2, 6, mat_rust, 10)
	block(-33, -17.5, 3, 3, 0.8, 6.8, M.deck(Color(0.85, 0.6, 0.45)))
	cyl(Vector3(-33, 3.2, -17.5), 1.0, 1.2, 7.2, mat_rust, 10)
	# Roof Gardens (8.8) with a long promenade north to the hook chain
	var gd := rect(-30, -5, 20, 18)
	island("gardens", gd, 8.8, Color(0.88, 0.96, 0.9))
	island("promenade", rect(-23, -27, 6, 26), 8.8, Color(0.88, 0.96, 0.9), 0.8)
	var leaf := M.std(Color(0.31, 0.72, 0.42), 0.0, 0.7)
	for p in [[-36, 0, 4, 2.4], [-26, -10, 4, 2.4], [-37, -8, 2.4, 4], [-27, 1, 2.4, 3]]:
		block(p[0], p[1], p[2], p[3], 0.8, 8.8, mat_white, false)
		for i in 6:
			var s := SphereMesh.new(); s.radius = randf_range(0.35, 0.65); s.height = s.radius * 2.4
			mesh_at(s, leaf, Vector3(p[0] + randf_range(-p[2] / 2 + 0.5, p[2] / 2 - 0.5), 9.9, p[1] + randf_range(-p[3] / 2 + 0.5, p[3] / 2 - 0.5)))
	label("ROOF GARDENS", Vector3(-30, 8.8, -3), 6, Color(0.78, 1, 0.82))
	for p in [Vector2(-21, -6), Vector2(-21, -38)]: lamp(p.x, p.y, Color(1, 0.85, 0.55), 8.8)
	checkpoints.append({ pos = Vector3(-30, 8.9, -5), r = 3.0 })
	checkpoints.append({ pos = Vector3(-23, 8.9, -37), r = 2.4 })
	# gull-nest ledge (Lucky Washer): planter, then a high ledge over tier 4
	block(-38, -12, 2, 2, 1.0, 8.8, M.deck(Color(0.7, 0.6, 0.5)))
	ledge(-42.5, -16.5, 2.6, 2.6, 11.8)
	prop("gull_nest", Vector3(-42.5, 11.8, -16.5), 0.0, 1.0, false)
	# shortcuts home: bounce pad off the edge (glide down to the plaza) and a chute rail
	bounce_pad(Vector3(-25, 8.8, 2.5), 14.0)
	hint_sign("EXPRESS TO THE PLAZA", Vector3(-27.5, 8.8, 3), PI)
	R_CHUTE = rail([Vector3(-21, 9.25, -1), Vector3(-20.5, 8.4, 4), Vector3(-19.5, 5.6, 8.5), Vector3(-18.5, 2.6, 13), Vector3(-17.5, 0.5, 17.5)], true)
	# hook chain east to the Signal Mast gallery
	hint_sign("SWING: PRESS HOOK NEAR A RING", Vector3(-24.5, 8.8, -38.5), -PI / 2)
	hook(Vector3(-14, 15.3, -40)); hook(Vector3(-4, 15.3, -40))

func _build_docks() -> void:
	# Pier A (0), Pier B (4), Pier C (6): grind rails between hanging containers, three turbines
	var pa := rect(39, 30, 22, 28)
	island("pier_a", pa, 0.0, Color(0.92, 0.95, 0.97))
	fence(pa, 0.0, [["w", 26, 34], ["w", 12, 21], ["n", 40, 48]], "nsew")
	var cm := [M.std(Color(0.82, 0.27, 0.18), 0.5, 0.45), M.std(Color(0.18, 0.5, 0.82), 0.5, 0.45), M.std(Color(0.91, 0.7, 0.16), 0.5, 0.45), M.std(Color(0.23, 0.65, 0.48), 0.5, 0.45)]
	for c in [[33, 38, 0, 0, 0], [33, 38, 0, 2.5, 2], [45, 26, 1, 0, 1], [34, 24, 1, 0, 3]]:
		var sz := Vector3(2.4, 2.5, 5) if c[2] else Vector3(5, 2.5, 2.4)
		var cb := box(Vector3(c[0], c[3] + 1.25, c[1]), sz, cm[c[4]])
		DocksDressing.skin_box(cb, "container", (cm[c[4]] as StandardMaterial3D).albedo_color.lightened(0.15))
	lamp(29, 43, Color(0.4, 0.95, 1)); lamp(49, 43, Color(0.4, 0.95, 1)); lamp(29, 17); lamp(49, 17)
	label("CARGO DOCKS", Vector3(39, 0, 33), 8, Color(0.75, 0.98, 1))
	checkpoints.append({ pos = Vector3(39, 0.1, 22), r = 3.0 })
	turbine(Vector3(46, 0, 39), PI)
	# rail 1: Pier A -> Pier B between hanging containers
	R_DOCKS_1 = rail([Vector3(44, 0.45, 18), Vector3(45, 1.5, 12), Vector3(48, 2.8, 6), Vector3(52, 3.8, 1), Vector3(55, 4.5, -2.5)], true)
	_hanging(Vector3(40.5, 6.0, 7.5), 0.5, cm[1])
	_hanging(Vector3(52.5, 7.0, 6.5), -0.4, cm[2])
	_hanging(Vector3(46, 7.5, 3), 0.9, cm[0])
	# Pier B
	island("pier_b", rect(58, -8, 16, 16), 4.0, Color(0.9, 0.93, 0.96), 2.0)
	turbine(Vector3(63, 4, -3), PI)
	prop("crate_large", Vector3(53, 4, -13), 0.3); prop("barrel", Vector3(65, 4, -14))
	checkpoints.append({ pos = Vector3(57, 4.1, -8), r = 3.0 })
	# the washer container: hangs off Pier B's west edge (double jump up from the pier)
	_hanging(Vector3(47, 3.9, -4), 0.0, cm[3])
	# rail 2: Pier B -> Pier C, weaving between containers
	R_DOCKS_2 = rail([Vector3(60, 4.45, -15), Vector3(57, 5.8, -20), Vector3(57.5, 7.6, -25), Vector3(62, 7.4, -28.5), Vector3(65, 6.6, -32)])
	_hanging(Vector3(53, 6.5, -24), 1.4, cm[2])
	_hanging(Vector3(63, 9.0, -22), 0.2, cm[1])
	# Pier C (the far side): last turbine, the cargo lift home, the hook chain to the mast
	island("pier_c", rect(68, -38, 16, 16), 6.0, Color(0.9, 0.93, 0.96), 2.0)
	turbine(Vector3(73, 6, -43), PI)
	prop("generator", Vector3(70, 6, -31), 0.0)
	checkpoints.append({ pos = Vector3(66, 6.1, -38), r = 3.0 })
	moving_platform(Vector3(57.5, 5.7, -38), Vector3(25, -0.3, 16), 22.0, Vector3(5, 0.6, 5), "cargo_lift", false)
	prop("gantry", Vector3(60, 6, -43.5), 0.0, 1.0, false)
	hint_sign("CARGO LIFT TO THE PLAZA (NEEDS TURBINE POWER)", Vector3(61, 6, -33), -PI / 2)
	hook(Vector3(55, 12.5, -36)); hook(Vector3(45, 12.5, -36))
	lamp(74.5, -31.5, Color(0.4, 0.95, 1), 6.0)
	DocksDressing.dress(self)

func _hanging(pos: Vector3, rot_y: float, mat: Material) -> void:
	var c := box(pos + Vector3(0, 1.25, 0), Vector3(5, 2.5, 2.4), mat)
	c.rotation.y = rot_y
	if mat is StandardMaterial3D: DocksDressing.skin_box(c, "container", (mat as StandardMaterial3D).albedo_color.lightened(0.15))
	for s in [-1, 1]:
		var off: Vector3 = Vector3(cos(rot_y), 0, -sin(rot_y)) * 1.8 * s
		cyl(pos + off + Vector3(0, 2.5 + 6, 0), 0.04, 0.04, 12, mat_dark, 6)

func _build_mast() -> void:
	# the Signal Mast at the center: east landing (3) -> gallery (8) -> spiral ledges -> dish deck (20)
	var C := Vector3(14, 0, -34)
	cyl(Vector3(C.x, -42, C.z), 2.6, 4.5, 124, mat_dark, 16)
	cyl(Vector3(C.x, 14, C.z), 2.4, 2.6, 12, M.std(Color(0.78, 0.8, 0.84), 0.7, 0.35), 16, true)
	for y in [10.0, 14.0, 18.0]: cyl(Vector3(C.x, y, C.z), 2.75, 2.75, 0.3, glow_warm, 16)
	island("gallery", rect(C.x, C.z, 18, 18), 8.0, Color(0.8, 0.84, 0.9))
	label("SIGNAL MAST", Vector3(C.x, 8, C.z + 6.5), 5, Color(1, 0.85, 0.6))
	checkpoints.append({ pos = Vector3(8, 8.1, -27), r = 2.4 })
	# east landing (from the docks' hook chain) and its step up to the gallery
	island("mast_landing", rect(28, -34, 8, 12), 3.0, Color(0.85, 0.88, 0.92), 1.0)
	block(26.5, -31, 2, 2, 1.9, 3.0, M.deck(Color(0.8, 0.75, 0.68)))
	block(24.6, -33.6, 2.4, 2.4, 3.1, 3.0, M.deck(Color(0.8, 0.75, 0.68)))
	# catch ledge under the west edge, where the promenade hook chain drops you
	ledge(2.5, -40, 5, 6, 6.6)
	checkpoints.append({ pos = Vector3(29, 3.1, -36), r = 2.4 })
	# ledges spiralling up the mast
	var tops := [10.4, 12.8, 15.2, 17.6]
	for i in tops.size():
		var a := deg_to_rad(37.0 * i)
		var p := Vector2(C.x + 6.5 * cos(a), C.z + 6.5 * sin(a))
		if i == 0: block(p.x, p.y, 2.5, 2.5, tops[i] - 8.0, 8.0, M.deck(Color(0.8, 0.75, 0.68)))
		else: ledge(p.x, p.y, 2.5, 2.5, tops[i])
	# dish deck on top with the relay dish (aligned by three cranks)
	island("dish_deck", rect(C.x, C.z, 8, 8), 20.0, Color(0.8, 0.82, 0.86), 0.8)
	checkpoints.append({ pos = Vector3(16.5, 20.1, -36), r = 1.4 })
	dish_pivot = Node3D.new(); dish_pivot.position = Vector3(C.x, 21.5, C.z - 0.5); add_child(dish_pivot)
	cyl(Vector3(C.x, 20.75, C.z - 0.5), 0.35, 0.5, 1.5, mat_dark, 10)
	if ResourceLoader.exists("res://models/kit/dish_small.glb"):
		Kit.place(dish_pivot, "dish_small", Vector3.ZERO, 0.0, 3.0, false)
	else:
		var d := CylinderMesh.new(); d.top_radius = 2.0; d.bottom_radius = 0.35; d.height = 0.8
		mesh_at(d, mat_white, Vector3(0, 0.6, 0), dish_pivot).rotation.x = -1.1
	dish_glow = M.glow(Color(1, 0.45, 0.1), 6.0)
	var e := SphereMesh.new(); e.radius = 0.4; e.height = 0.8
	mesh_at(e, dish_glow, Vector3(0, 1.1, 0.6), dish_pivot)
	dish_light = OmniLight3D.new(); dish_light.light_color = Color(1, 0.5, 0.15); dish_light.light_energy = 6.0; dish_light.omni_range = 14
	dish_light.position = Vector3(0, 1.4, 0.8); dish_pivot.add_child(dish_light)
	dish_pivot.rotation = Vector3(0.5, 2.2, 0)
	dish_target = Vector2(2.2, 0.5)
	# rail from the dish deck down to the Crane Yard gate (opens when the dish is aligned)
	R_YARD = rail([Vector3(14, 20.45, -36.6), Vector3(13, 19.4, -41), Vector3(11, 15.5, -47), Vector3(7, 9.5, -53), Vector3(3, 4, -58.5), Vector3(1, 1.0, -61.5)], true)

func _build_crane_yard() -> void:
	# causeway from the plaza: walkway, sliding platform, pads, then the gate island and the arena
	island("causeway", rect(-6, 4, 8, 10), 0.0, Color(0.9, 0.9, 0.92), 0.8)
	moving_platform(Vector3(-6, -0.3, -6), Vector3(-6, -0.3, -22), 8.0)
	island("causeway_2", rect(-6, -30, 8, 8), 0.0, Color(0.9, 0.9, 0.92), 0.8)
	sky_pad(-6, -40, 4, 4); sky_pad(-3, -46, 4, 4); sky_pad(0, -52, 4, 4)
	var gi := rect(0, -64, 28, 14)
	island("yard_gate", gi, 0.0, Color(0.86, 0.88, 0.9))
	fence(gi, 0.0, [], "ew")
	prop("gantry", Vector3(8, 0, -70), 0.0, 1.0, false)
	for p in [Vector3(9, 0, -60), Vector3(11, 0, -66)]: prop("cargo_container", p, PI / 2)
	lamp(-13, -58, Color(1, 0.45, 0.3)); lamp(13, -58, Color(1, 0.45, 0.3))
	label("CRANE YARD", Vector3(0, 0, -62), 6, Color(1, 0.78, 0.85))
	checkpoints.append({ pos = Vector3(0, 0.1, -62), r = 3.0 })
	gate("yard_gate", Vector3(0, 0, -71.6), 50.0, 12.0)
	walkway(-3, -82, 3, -71)
	# the boss arena
	var y := rect(0, -97, 36, 30)
	island("arena", y, 0.0, Color(0.86, 0.88, 0.9))
	fence(y, 0.0, [["s", -3, 3]])
	var c := y.get_center()
	for o in [Vector2(-10, -9), Vector2(10, -9), Vector2(-10, 9), Vector2(10, 9)]: block(c.x + o.x, c.y + o.y, 2.4, 2.4, 1.6, 0, mat_blue)
	for o in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]: lamp(c.x + o.x * 16.6, c.y + o.y * 13.6, Color(1, 0.45, 0.3))
	prop("gantry", Vector3(0, 0, -111), 0.0, 1.6, false)
	checkpoints.append({ pos = Vector3(0, 0.1, -84.5), r = 2.4 })

func _define_zones() -> void:
	shop_spots = [{ pos = Vector3(-15, 0, 42), yaw = PI * 0.5, stock = ["scatter_bloom", "thump_lobber"] },
		{ pos = Vector3(-10, 0, -66), yaw = PI * 0.5, stock = ["seeker_hive"] }]
	crate_spots = [
		Vector3(12, 0, 73), Vector3(13.2, 0, 74.4), Vector3(-5, 0, 73), Vector3(9, 0, 89),            # junkyard
		Vector3(-18, 0, 18), Vector3(17, 0, 18), Vector3(-8, 0, 44), Vector3(6, 0, 19),              # plaza
		Vector3(31, 0, 41), Vector3(48, 0, 20), Vector3(31, 0, 19),                                   # pier A
		Vector3(62, 4, -12), Vector3(52, 4, -9), Vector3(72, 6, -33), Vector3(62, 6, -44),           # piers B, C
		Vector3(-47, 0, 47), Vector3(-30, 0, 27), Vector3(-58, 4.8, 5),                               # terrace
		Vector3(-38, 8.8, 3), Vector3(-23, 8.8, -12), Vector3(-24.5, 8.8, -31),                       # gardens
		Vector3(21, 8, -42), Vector3(6, 0, -59), Vector3(-9, 0, -69),                                 # mast, yard
	]
	pickup_spots = [
		{ kind = "washer", id = "w1", pos = Vector3(-42.5, 12.6, -16.5) },    # gull-nest ledge above tier 4
		{ kind = "washer", id = "w2", pos = Vector3(47, 7.2, -4) },           # on the hanging container by Pier B
		{ kind = "washer", id = "w3", pos = Vector3(-16.2, 4.4, 70.6) },      # junkyard shelf above the scrap pile
		{ kind = "page", id = "p1", pos = Vector3(17, 0.8, 41) },             # inside the sealed bank vault
	]
	gripe_ids = ["return_to_sender"]
	var gal: Rect2 = islands.gallery
	var dd: Rect2 = islands.dish_deck
	zones = [
		{ id = "junk_crash", kind = "reach", rect = rect(-12.5, 74.5, 4, 3.4), y = 2.4, y_range = 1.2,
			objective = "Find Dodger on top of the scrap pile (WASD to run, Space to jump)",
			enter_lines = ["sky_junk_found_1", "sky_junk_found_2", "sky_junk_found_3"] },
		{ id = "junkyard", name = "THE JUNKYARD", rect = islands.junkyard, objective = "Wrench the bots out of the junkyard (F to swing)",
			enter_lines = ["sky_junk_bots_1", "sky_junk_bots_2"], clear_lines = ["sky_junk_clear_1"],
			waves = [{ roller = 2 }, { roller = 3 }, { roller = 2, hornet = 1 }] },
		{ id = "dodger_launch", kind = "activate", rect = islands.junkyard, banner = "DODGER AIRBORNE",
			objective = "Whack the launch crank to get Dodger airborne",
			switches = [{ pos = Vector3(7.5, 0, 86.5), yaw = PI * 0.75, label = "LAUNCH CRANK" }],
			clear_lines = ["sky_dodger_up_1", "sky_dodger_up_2", "sky_dodger_up_3"], open_gates = ["junk_gate"] },
		{ id = "plaza", name = "DOCK PLAZA", rect = islands.plaza, objective = "Head out to the Dock Plaza",
			enter_lines = ["dock_intro_1", "dock_intro_2"], clear_lines = ["dock_clear_1", "dock_clear_2", "dock_clear_3", "sky_plaza_turbines_1"],
			waves = [{ roller = 3 }, { roller = 2, hornet = 1 }, { roller = 3, hornet = 1 }] },
		{ id = "docks", name = "CARGO DOCKS", rect = islands.pier_a, objective = "Cross east to the Cargo Docks",
			enter_lines = ["cargo_intro"], clear_lines = ["sky_docks_clear_1", "sky_docks_clear_2"],
			waves = [{ roller = 4 }, { roller = 2, hornet = 2 }], unlock_rails = [R_DOCKS_1] },
		{ id = "turbines", kind = "activate", rect = islands.pier_a, banner = "TURBINES ONLINE", name = "WIND TURBINES",
			objective = "Restart the dock wind turbines", progress_text = "Restart the dock wind turbines (%d/%d)",
			switches = [{ pos = Vector3(43.5, 0, 39.5), yaw = PI, label = "TURBINE 1" }, { pos = Vector3(60.5, 4, -3.5), yaw = PI, label = "TURBINE 2" },
				{ pos = Vector3(70.5, 6, -43.5), yaw = PI, label = "TURBINE 3" }],
			guards = [{ rect = islands.pier_b, y = 4.0, roller = 2, hornet = 1 }, { rect = islands.pier_c, y = 6.0, roller = 2, hornet = 1 }],
			enter_lines = ["sky_turbines_1"], clear_lines = ["sky_turbines_done_1", "sky_turbines_done_2", "sky_turbines_done_3"],
			power = ["cargo_lift"] },
		{ id = "terrace", name = "MARKET TERRACE", rect = islands.terrace, skippable = true,
			objective = "Ride the cargo lift home, then climb the Terrace west of the plaza",
			enter_lines = ["terrace_intro", "sky_terrace_jump_1"], clear_lines = ["sky_terrace_clear_1"],
			waves = [{ roller = 3, hornet = 1 }, { hornet = 2, roller = 1 }] },
		{ id = "gardens", name = "ROOF GARDENS", rect = islands.gardens, y = 8.8, skippable = true,
			objective = "Double jump and glide up to the Roof Gardens",
			enter_lines = ["gardens_intro"], clear_lines = ["sky_gardens_clear_1", "swing_hint"],
			waves = [{ roller = 3, hornet = 1 }, { roller = 2, hornet = 2 }], unlock_rails = [R_CHUTE] },
		{ id = "mast_climb", kind = "reach", rect = gal, y = 8.0, y_range = 2.5, skip_to = true,
			objective = "Swing from the promenade hooks to the Signal Mast",
			enter_lines = ["sky_mast_climb_1", "sky_mast_climb_2"] },
		{ id = "mast", name = "SIGNAL MAST", kind = "activate", rect = dd, y = 20.0, y_range = 3.0, banner = "DISH ALIGNED",
			objective = "Climb the mast and align the relay dish", progress_text = "Turn the dish cranks to align the relay dish (%d/%d)",
			switches = [{ pos = Vector3(11, 20, -31), yaw = PI * 0.25, label = "CRANK" }, { pos = Vector3(17, 20, -31), yaw = -PI * 0.25, label = "CRANK" },
				{ pos = Vector3(11, 20, -37), yaw = PI * 0.75, label = "CRANK" }],
			guards = [{ rect = dd, y = 20.0, hornet = 2 }, { rect = gal, y = 8.0, hornet = 1 }],
			enter_lines = ["sky_mast_dish_1", "sky_mast_dish_2"],
			clear_lines = ["sky_shard_1", "sky_shard_2", "sky_shard_3", "sky_shard_4", "sky_shard_5"],
			unlock_rails = [R_YARD], open_gates = ["causeway_gate", "yard_gate"], grants = ["shard_1"] },
		{ id = "yard_gate", name = "CRANE YARD GATE", rect = islands.yard_gate, objective = "Ride the rail down to the Crane Yard",
			enter_lines = ["sky_yard_gate_1"], clear_lines = ["sky_yard_gate_clear_1", "sky_yard_gate_clear_2"],
			waves = [{ roller = 3 }, { crew = 1, hornet = 1 }, { roller = 2, hornet = 2 }] },
		{ id = "yard", name = "CRANE YARD", kind = "boss", rect = islands.arena, objective = "Take on whatever is in the Crane Yard",
			enter_lines = ["yard_intro_1", "yard_intro_2", "yard_intro_3"], boss_pos = Vector3(0, 0, -102) },
	]

## story hooks: switches thrown and zones cleared
func on_switch(zone_id: String, i: int, done: int, total: int) -> void:
	match zone_id:
		"turbines":
			if i < turbines.size(): turbines[i].spin = 9.0
			Snd.play("checkpoint", -4)
		"mast":
			# each crank swings the dish a step toward the sky; the last one locks it on
			var u := float(done) / total
			dish_target = Vector2(lerpf(2.2, 0.0, u), lerpf(0.5, -0.9, u))
			FX.shake(0.4)

func on_zone_cleared(zone_id: String) -> void:
	match zone_id:
		"mast":
			dish_glow.emission = Color(0.3, 0.95, 1.0)
			dish_light.light_color = Color(0.35, 0.95, 1.0)
			dish_target = Vector2(0.0, -0.9)

func _debug_start() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--traverse"):
			var tt: Node = load("res://scripts/level/traversal_test.gd").new()
			tt.process_physics_priority = -100; add_child(tt)
		if a.begins_with("--at=") and debug_spots.has(a.substr(5)):
			var s: Array = debug_spots[a.substr(5)]
			start_pos = s[0]; start_yaw = s[1]

## the sky city far below and around: towers poking through the haze
func _build_city() -> void:
	var rng := RandomNumberGenerator.new(); rng.seed = 7
	var tower_mats := [M.std(Color(0.72, 0.81, 0.88), 0.6, 0.35), M.std(Color(0.62, 0.77, 0.85), 0.6, 0.35), M.std(Color(0.84, 0.89, 0.92), 0.6, 0.3)]
	var win := M.glow(Color(1.0, 0.85, 0.55), 1.2)
	for i in 140:
		var ang := rng.randf() * TAU
		var dist := 180.0 + pow(rng.randf(), 0.8) * 600.0
		var p := Vector3(sin(ang) * dist, 0, -cos(ang) * dist + -10)
		var r := rng.randf_range(5, 12) * (0.8 + dist / 400.0)
		var top := rng.randf_range(-30, 40) + dist * 0.04
		var bottom := -260.0
		cyl(Vector3(p.x, (top + bottom) / 2, p.z), r, r * 1.15, top - bottom, tower_mats[i % 3], 24)
		var dome := SphereMesh.new(); dome.radius = r; dome.height = r * 1.2; dome.is_hemisphere = true
		mesh_at(dome, M.std(Color(0.6, 0.85, 1.0), 0.3, 0.1), Vector3(p.x, top, p.z))
		var band := TorusMesh.new(); band.inner_radius = r * 1.15; band.outer_radius = r * 1.3
		mesh_at(band, win, Vector3(p.x, top - rng.randf_range(3, 12), p.z))

func _physics_process(dt: float) -> void:
	t += dt
	for m in movers:
		if not m.powered: continue
		m.t += dt
		var u := 0.5 - 0.5 * cos(m.t / m.period * TAU)
		m.body.position = m.a.lerp(m.b, u)
	for b in bouncers:
		b.squash = maxf(0.0, b.squash - dt * 5)
		b.node.scale = Vector3(1 + b.squash * 0.15, 1 - b.squash * 0.3, 1 + b.squash * 0.15)
	for h in hooks:
		var ring: Node3D = h.get_meta("ring")
		ring.rotate_y(dt)
	for tb in turbines:
		tb.rotor.rotate_object_local(Vector3.FORWARD, tb.spin * dt)
	if dish_pivot:
		dish_pivot.rotation.y = lerp_angle(dish_pivot.rotation.y, dish_target.x, 1.0 - exp(-2.0 * dt))
		dish_pivot.rotation.x = lerpf(dish_pivot.rotation.x, dish_target.y, 1.0 - exp(-2.0 * dt))
		# the dish pulses orange with the broadcast until it is aligned
		if dish_glow.emission.r > 0.5: dish_glow.emission_energy_multiplier = 4.0 + 3.0 * maxf(0.0, sin(t * 2.2))
