extends Node3D
## Skyharbor, the first planet: floating islands above a sky city, joined by stepping pads, moving
## platforms, a bounce pad, swing hooks and grind rails.
##   Dockside (start) -> sky steps -> Market Terrace -> bounce up to the lookout -> swing hooks ->
##   Cargo Yard -> rail up -> Signal Mast -> rail down -> Fan Gardens -> moving platform -> swing ->
##   Crane Yard (boss)

const M := preload("res://scripts/mats.gd")

var start_pos := Vector3(0, 0.1, 70)
var start_yaw := PI
var rails: Array = []          # { curve: Curve3D, path: Path3D, locked: bool, glow: StandardMaterial3D }
var hooks: Array = []          # Node3D (hook position = global_position)
var bouncers: Array = []       # { pos: Vector3, power: float, node: Node3D, squash: float }
var movers: Array = []         # { body: AnimatableBody3D, a: Vector3, b: Vector3, period: float }
var checkpoints: Array = []    # { pos: Vector3, r: float }
var islands := {}
## Story zones in play order (read by story.gd; see the key list at the top of that script).
var zones: Array = []
## Spots other systems read (filled in _define_zones; systems must cope with these being empty):
var shop_spots: Array = []      # { pos: Vector3, yaw: float, stock: Array of item ids }
var crate_spots: Array = []     # Vector3 (breakable nut crates)
var pickup_spots: Array = []    # { kind: "washer"|"page", id: String, pos: Vector3 }
var gripe_ids: Array = []       # skill tasks on this level, e.g. "return_to_sender"
var t := 0.0

var mat_white := M.std(Color(0.93, 0.95, 0.97), 0.6, 0.3)
var mat_blue := M.std(Color(0.37, 0.56, 0.69), 0.7, 0.32)
var mat_teal := M.std(Color(0.25, 0.62, 0.63), 0.7, 0.3)
var mat_dark := M.std(Color(0.2, 0.25, 0.3), 0.75, 0.4)
var mat_brass := M.std(Color(0.85, 0.64, 0.26), 0.9, 0.3)
var glow_cyan := M.glow(Color(0.25, 0.94, 1.0), 4.0)
var glow_warm := M.glow(Color(1.0, 0.63, 0.19), 3.0)

func _ready() -> void:
	_build()

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

## a raised block standing on y0 with a glowing lip, like the web version's `block`
func block(x: float, z: float, sx: float, sz: float, h: float, y0 := 0.0, mat: Material = null, lip := true) -> MeshInstance3D:
	var m := box(Vector3(x, y0 + h / 2, z), Vector3(sx, h, sz), mat if mat else M.deck(Color(0.75, 0.82, 0.88)))
	if lip: box(Vector3(x, y0 + h - 0.03, z), Vector3(sx + 0.03, 0.05, sz + 0.03), glow_warm, false)
	return m

func cyl(pos: Vector3, r_top: float, r_bot: float, h: float, mat: Material, sides := 24) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = sides
	return mesh_at(cm, mat, pos)

func island(r: Rect2, tint := Color(1, 1, 1)) -> void:
	var c := r.get_center()
	box(Vector3(c.x, -0.6, c.y), Vector3(r.size.x, 1.2, r.size.y), M.deck(tint))
	var rad: float = min(r.size.x, r.size.y) * 0.48
	var under := cyl(Vector3(c.x, -1.2 - rad * 0.85, c.y), rad, rad * 0.22, rad * 1.7, mat_dark, 8)
	under.scale = Vector3(r.size.x / min(r.size.x, r.size.y), 1, r.size.y / min(r.size.x, r.size.y))
	cyl(Vector3(c.x, -1.2 - rad * 1.7, c.y), rad * 0.3, rad * 0.3, 0.6, glow_cyan)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(0.3, 0.9, 1.0)
	lamp.light_energy = 3.0
	lamp.omni_range = rad * 1.5
	lamp.position = Vector3(c.x, -1.2 - rad * 1.9, c.y)
	add_child(lamp)
	# hazard edging with a glowing strip so the drop is easy to see
	var hz := M.hazard()
	for e in [[Vector3(c.x, -0.08, r.position.y), Vector3(r.size.x, 0.22, 0.3)], [Vector3(c.x, -0.08, r.end.y), Vector3(r.size.x, 0.22, 0.3)],
			[Vector3(r.position.x, -0.08, c.y), Vector3(0.3, 0.22, r.size.y)], [Vector3(r.end.x, -0.08, c.y), Vector3(0.3, 0.22, r.size.y)]]:
		box(e[0], e[1], hz, false)
		box(e[0] + Vector3(0, -0.2, 0), e[1] * Vector3(1, 0.25, 1) + Vector3(0.02, 0, 0.02), glow_cyan, false)

## railing along an island edge; solid so you don't walk off by accident
func railing(x1: float, z1: float, x2: float, z2: float) -> void:
	var len := Vector2(x2 - x1, z2 - z1).length()
	var mid := Vector3((x1 + x2) / 2, 0, (z1 + z2) / 2)
	var along_x := absf(x2 - x1) > absf(z2 - z1)
	box(mid + Vector3(0, 1.0, 0), Vector3(len if along_x else 0.1, 0.1, 0.1 if along_x else len), mat_white, false)
	box(mid + Vector3(0, 0.88, 0), Vector3(len if along_x else 0.04, 0.04, 0.04 if along_x else len), glow_cyan, false)
	var n := maxi(1, roundi(len / 2.4))
	for i in n + 1:
		var u := float(i) / n
		cyl(Vector3(lerpf(x1, x2, u), 0.5, lerpf(z1, z2, u)), 0.05, 0.06, 1.0, mat_white, 8)
	# invisible wall
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(len if along_x else 0.25, 1.1, 0.25 if along_x else len)
	cs.shape = sh
	sb.position = mid + Vector3(0, 0.55, 0)
	sb.add_child(cs)
	add_child(sb)

func lamp(x: float, z: float, c := Color(1.0, 0.75, 0.45)) -> void:
	cyl(Vector3(x, 1.6, z), 0.07, 0.1, 3.2, mat_dark, 8)
	var s := SphereMesh.new(); s.radius = 0.2; s.height = 0.4
	mesh_at(s, M.glow(c, 6.0), Vector3(x, 3.25, z))
	var l := OmniLight3D.new()
	l.light_color = c; l.light_energy = 2.5; l.omni_range = 9.0
	l.position = Vector3(x, 3.1, z)
	add_child(l)

func label(text: String, pos: Vector3, size := 2.0, color := Color(1, 0.9, 0.6)) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 160
	l.pixel_size = size / 160.0
	l.modulate = Color(color, 0.55)
	l.outline_size = 0
	l.rotation_degrees = Vector3(-90, 0, 0)
	l.position = pos + Vector3(0, 0.02, 0)
	l.shaded = false
	add_child(l)

func sky_pad(x: float, z: float, w: float, d: float) -> void:
	block(x, z, w, d, 0.6, -0.6, M.deck(Color(0.78, 0.86, 0.92)))
	var cone := cyl(Vector3(x, -1.7, z), 0.0, min(w, d) * 0.45, 2.2, mat_dark, 6)
	var s := SphereMesh.new(); s.radius = 0.3; s.height = 0.6
	mesh_at(s, glow_cyan, Vector3(x, -2.9, z))

func crate_stack(x: float, z: float, s := 1.0, y := 0.0) -> void:
	box(Vector3(x, y + 0.4 * s, z), Vector3(0.8, 0.8, 0.8) * s, M.std(Color(1.0, 0.56, 0.12), 0.35, 0.45))

func moving_platform(a: Vector3, b: Vector3, period: float, size := Vector3(4.5, 0.6, 4.5)) -> void:
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
	var lm := MeshInstance3D.new(); lm.mesh = lip; lm.material_override = glow_cyan; lm.position.y = size.y / 2 - 0.03
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
	movers.append({ body = body, a = a, b = b, period = period })

func bounce_pad(pos: Vector3, power: float) -> void:
	var n := Node3D.new(); n.position = pos; add_child(n)
	var base := CylinderMesh.new(); base.top_radius = 1.1; base.bottom_radius = 1.25; base.height = 0.25
	mesh_at(base, mat_dark, Vector3(0, 0.12, 0), n)
	var top := CylinderMesh.new(); top.top_radius = 0.95; top.bottom_radius = 0.95; top.height = 0.1
	mesh_at(top, M.glow(Color(0.5, 1.0, 0.6), 3.0), Vector3(0, 0.27, 0), n)
	var l := OmniLight3D.new(); l.light_color = Color(0.5, 1, 0.6); l.light_energy = 2.0; l.omni_range = 5; l.position.y = 0.8
	n.add_child(l)
	bouncers.append({ pos = pos, power = power, node = n, squash = 0.0 })

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

func rail(points: Array, locked := false) -> void:
	var path := Path3D.new()
	var curve := Curve3D.new()
	curve.bake_interval = 0.2
	for p in points: curve.add_point(p)
	# smooth Catmull-Rom style handles
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
	tube.path_node = tube.get_path_to(path) if false else NodePath("..")
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
	# support posts hanging into the sky
	var L := curve.get_baked_length()
	var u := 4.0
	while u < L - 2.0:
		var p := curve.sample_baked(u)
		cyl(p + Vector3(0, -15.15, 0), 0.1, 0.16, 30, mat_dark, 8)
		u += 10.0
	rails.append({ curve = curve, path = path, locked = locked, glow = g, length = L })

func set_rail_locked(i: int, v: bool) -> void:
	var r: Dictionary = rails[i]
	r.locked = v
	r.glow.emission = Color(1.0, 0.19, 0.19) if v else Color(1.0, 0.7, 0.23)

# ---------- the level ----------
func _build() -> void:
	islands = {
		dock = rect(0, 62, 34, 24), terrace = rect(0, 4, 30, 24), cargo = rect(12, -56, 32, 24),
		gardens = rect(-30, -96, 22, 20), yard = rect(-58, -130, 30, 30),
	}
	island(islands.dock)
	island(islands.terrace, Color(1.0, 0.95, 0.88))
	island(islands.cargo, Color(0.92, 0.95, 0.97))
	island(islands.gardens, Color(0.88, 0.96, 0.9))
	island(islands.yard, Color(0.86, 0.88, 0.9))

	# --- Dockside ---
	var d: Rect2 = islands.dock
	railing(d.position.x, d.end.y, d.end.x, d.end.y)
	railing(d.position.x, d.position.y, -2.5, d.position.y); railing(2.5, d.position.y, d.end.x, d.position.y)
	railing(d.position.x, d.position.y, d.position.x, d.end.y); railing(d.end.x, d.position.y, d.end.x, d.end.y)
	for p in [Vector2(-16.4, 52), Vector2(-16.4, 72), Vector2(16.4, 52), Vector2(16.4, 72)]:
		cyl(Vector3(p.x, 0.35, p.y), 0.3, 0.38, 0.7, mat_brass, 12)
	crate_stack(10, 71, 1.2); crate_stack(11.2, 71.2, 1.1); crate_stack(10.6, 71.1, 1.0, 0.96); crate_stack(-6, 53.5, 1.2)
	block(8.5, 57, 3, 2, 1.1, 0, mat_blue)
	block(-9, 60, 5, 3, 1.4, 0, mat_blue); block(-9, 60, 3, 3, 1.2, 1.4, mat_teal)
	lamp(-16, 63); lamp(16, 63); lamp(-3.5, 50.6, Color(0.4, 0.95, 1)); lamp(3.5, 50.6, Color(0.4, 0.95, 1))
	label("SKYHARBOR DOCKS", Vector3(0, 0, 64), 12)
	cyl(Vector3(14, 3.5, 66), 0.35, 0.5, 7, mat_dark, 10)

	# --- Sky steps ---
	sky_pad(0, 45.5, 4.5, 4.5); sky_pad(3, 39.2, 4.5, 4.5); sky_pad(2, 19.3, 5, 3.4)
	moving_platform(Vector3(3, -0.3, 33), Vector3(3, -0.3, 25.5), 5.5)
	checkpoints.append({ pos = Vector3(0, 0.1, 45.5), r = 2.4 })

	# --- Market Terrace ---
	var tr: Rect2 = islands.terrace
	railing(tr.position.x, tr.position.y, tr.position.x, tr.end.y); railing(tr.end.x, tr.position.y, tr.end.x, tr.end.y)
	railing(tr.position.x, tr.end.y, -1, tr.end.y); railing(5, tr.end.y, tr.end.x, tr.end.y)
	railing(tr.position.x, tr.position.y, 5, tr.position.y)
	var awn := [Color(1, 0.42, 0.29), Color(0.29, 0.69, 1), Color(1, 0.75, 0.25), Color(0.48, 0.82, 0.42)]
	for s in [[-10, 12, 0, 0], [-10, 2, 90, 1], [-4, -4, 0, 2], [11, 10, 180, 3]]:
		var n := Node3D.new(); n.position = Vector3(s[0], 0, s[1]); n.rotation_degrees.y = s[2]; add_child(n)
		box(Vector3(0, 0.55, 0), Vector3(3.2, 1.1, 1.2), mat_white, true, n)
		for sx in [-1, 1]: box(Vector3(1.5 * sx, 1.3, -0.5), Vector3(0.1, 2.6, 0.1), mat_dark, false, n)
		var aw := box(Vector3(0, 2.6, 0.1), Vector3(3.6, 0.15, 1.8), M.std(awn[s[3]], 0.1, 0.55), false, n)
		aw.rotation_degrees.x = 14
	cyl(Vector3(1, 0.4, 5), 2.0, 2.3, 0.8, mat_teal)
	cyl(Vector3(1, 0.82, 5), 1.7, 1.7, 0.08, M.glow(Color(0.38, 0.88, 1), 1.5))
	for p in [Vector2(-14, -7), Vector2(14, -7), Vector2(-14, 15), Vector2(14, 15)]: lamp(p.x, p.y, Color(1, 0.82, 0.5))
	label("MARKET TERRACE", Vector3(0, 0, -2), 9)
	block(10, -11, 6, 6, 6, 0)   # the lookout
	bounce_pad(Vector3(10, 0, -4), 19.0)
	checkpoints.append({ pos = Vector3(10, 6.1, -11), r = 3.0 })
	hook(Vector3(10, 12.5, -21)); hook(Vector3(10, 12.5, -35))

	# --- Cargo Yard ---
	var cg: Rect2 = islands.cargo
	railing(cg.end.x, cg.position.y, cg.end.x, cg.end.y); railing(cg.position.x, cg.position.y, cg.position.x, cg.end.y)
	railing(cg.position.x, cg.position.y, 10, cg.position.y); railing(14, cg.position.y, cg.end.x, cg.position.y)
	var cm := [M.std(Color(0.82, 0.27, 0.18), 0.5, 0.45), M.std(Color(0.18, 0.5, 0.82), 0.5, 0.45), M.std(Color(0.91, 0.7, 0.16), 0.5, 0.45), M.std(Color(0.23, 0.65, 0.48), 0.5, 0.45)]
	for c in [[2, -60, 0, 0, 0], [2, -60, 0, 2.5, 2], [22, -52, 1, 0, 1], [9, -50, 0, 0, 3], [20, -63, 0, 0, 2], [20, -63, 0, 2.5, 1], [-1, -48, 1, 0, 3]]:
		var sz := Vector3(2.4, 2.5, 5) if c[2] else Vector3(5, 2.5, 2.4)
		box(Vector3(c[0], c[3] + 1.25, c[1]), sz, cm[c[4]])
	lamp(-3.4, -67.4); lamp(27.4, -45); lamp(10, -67.6, Color(0.4, 0.95, 1)); lamp(14, -67.6, Color(0.4, 0.95, 1))
	label("CARGO YARD", Vector3(12, 0, -46.5), 9, Color(0.75, 0.98, 1))

	# --- Signal Mast ---
	block(12, -96, 14, 14, 28, 8 - 28, M.deck(Color(0.7, 0.78, 0.85)))
	cyl(Vector3(12, 8 - 68, -96), 4.5, 5.5, 80, mat_dark, 12)
	block(18.75, -96, 0.5, 14, 0.9, 8, mat_dark, false)
	rail([Vector3(12, 0.45, -67.6), Vector3(12.5, 2.2, -73), Vector3(11.5, 4.6, -79), Vector3(12.5, 7.4, -85), Vector3(12, 8.6, -88.6)], true)
	rail([Vector3(6.2, 8.4, -96), Vector3(1, 8.6, -99), Vector3(-4, 6.6, -101), Vector3(-12, 4, -97), Vector3(-17, 1.8, -95.5), Vector3(-19.6, 1.0, -96)], true)

	# --- Fan Gardens ---
	var gd: Rect2 = islands.gardens
	railing(gd.position.x, gd.end.y, gd.end.x, gd.end.y); railing(gd.position.x, gd.position.y, gd.end.x, gd.position.y)
	railing(gd.end.x, gd.position.y, gd.end.x, -98); railing(gd.end.x, -94, gd.end.x, gd.end.y)
	railing(gd.position.x, gd.position.y, gd.position.x, -98.5); railing(gd.position.x, -93.5, gd.position.x, gd.end.y)
	var leaf := M.std(Color(0.31, 0.72, 0.42), 0.0, 0.7)
	for p in [[-35, -90, 4, 2.4], [-25, -102, 4, 2.4], [-36, -102, 2.4, 4], [-23, -89, 2.4, 3]]:
		block(p[0], p[1], p[2], p[3], 0.8, 0, mat_white, false)
		for i in 6:
			var s := SphereMesh.new(); s.radius = randf_range(0.35, 0.65); s.height = s.radius * 2.4
			mesh_at(s, leaf, Vector3(p[0] + randf_range(-p[2] / 2 + 0.5, p[2] / 2 - 0.5), 1.1, p[1] + randf_range(-p[3] / 2 + 0.5, p[3] / 2 - 0.5)))
	cyl(Vector3(-30, -1, -96), 0.9, 1.35, 9, mat_dark, 10)
	label("FAN GARDENS", Vector3(-30, 0, -88.5), 7, Color(0.78, 1, 0.82))
	moving_platform(Vector3(-45, -0.3, -96), Vector3(-52.5, -0.3, -96), 5.0)
	sky_pad(-58, -97, 6, 6)
	checkpoints.append({ pos = Vector3(-58, 0.1, -97), r = 3.0 })
	hook(Vector3(-58, 11, -107))

	# --- Crane Yard ---
	var y: Rect2 = islands.yard
	railing(y.position.x, y.position.y, y.end.x, y.position.y); railing(y.position.x, y.position.y, y.position.x, y.end.y)
	railing(y.end.x, y.position.y, y.end.x, y.end.y)
	var c := y.get_center()
	for o in [Vector2(-9, -9), Vector2(9, -9), Vector2(-9, 9), Vector2(9, 9)]: block(c.x + o.x, c.y + o.y, 2.4, 2.4, 1.6, 0, mat_blue)
	for o in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]: lamp(c.x + o.x * 14.6, c.y + o.y * 14.6, Color(1, 0.45, 0.3))
	label("CRANE YARD", Vector3(c.x, 0, y.end.y - 2.5), 8, Color(1, 0.78, 0.85))

	_build_city()
	_define_zones()

func _define_zones() -> void:
	shop_spots = [{ pos = Vector3(-12, 0, 66), yaw = PI * 0.5, stock = ["scatter_bloom", "thump_lobber"] },
		{ pos = Vector3(-50, 0, -118), yaw = 0.0, stock = ["seeker_hive"] }]
	crate_spots = [Vector3(6, 0, 70), Vector3(-14, 0, 56), Vector3(-6, 0, 12), Vector3(24, 0, -60), Vector3(0, 0, -50)]
	pickup_spots = [{ kind = "washer", id = "w1", pos = Vector3(10, 6.6, -12) }, { kind = "washer", id = "w2", pos = Vector3(26, 0.8, -46) },
		{ kind = "washer", id = "w3", pos = Vector3(-36, 0.8, -104) }, { kind = "page", id = "p1", pos = Vector3(12, 9.2, -101) }]
	gripe_ids = ["return_to_sender"]
	zones = [
		{ id = "dock", name = "SKYHARBOR DOCKS", rect = islands.dock, objective = "Clear the bots off the dock",
			enter_lines = ["dock_intro_1", "dock_intro_2"], clear_lines = ["dock_clear_1", "dock_clear_2", "dock_clear_3"],
			waves = [{ roller = 3 }, { roller = 2, hornet = 1 }] },
		{ id = "terrace", name = "MARKET TERRACE", rect = islands.terrace, objective = "Cross the sky steps to the Market Terrace",
			enter_lines = ["terrace_intro"], clear_lines = ["swing_hint"],
			waves = [{ roller = 3, hornet = 1 }, { hornet = 2 }] },
		{ id = "cargo", name = "CARGO YARD", rect = islands.cargo, objective = "Swing across to the Cargo Yard",
			enter_lines = ["cargo_intro"], clear_lines = ["cargo_clear_1", "cargo_clear_2"],
			waves = [{ roller = 4 }, { roller = 2, hornet = 2 }], unlock_rails = [0] },
		{ id = "mast", name = "SIGNAL MAST", kind = "relay", rect = rect(12, -96, 14, 14), y = 8.0,
			objective = "Ride the rail up the Signal Mast", relay_pos = Vector3(15, 8.0, -100),
			enter_lines = ["mast_intro"], clear_lines = ["mast_clear_1", "mast_clear_2", "mast_clear_3"], unlock_rails = [1] },
		{ id = "gardens", name = "FAN GARDENS", rect = islands.gardens, objective = "Grind down to the Fan Gardens",
			enter_lines = ["gardens_intro"], waves = [{ roller = 3, hornet = 1 }, { roller = 2, hornet = 2 }] },
		{ id = "yard", name = "CRANE YARD", kind = "boss", rect = islands.yard, objective = "Take on whatever is in the Crane Yard",
			enter_lines = ["yard_intro_1", "yard_intro_2", "yard_intro_3"], boss_pos = Vector3(-58, 0, -136) },
	]

## the sky city far below and around: towers poking through the haze
func _build_city() -> void:
	var rng := RandomNumberGenerator.new(); rng.seed = 7
	var tower_mats := [M.std(Color(0.72, 0.81, 0.88), 0.6, 0.35), M.std(Color(0.62, 0.77, 0.85), 0.6, 0.35), M.std(Color(0.84, 0.89, 0.92), 0.6, 0.3)]
	var win := M.glow(Color(1.0, 0.85, 0.55), 1.2)
	for i in 140:
		var ang := rng.randf() * TAU
		var dist := 150.0 + pow(rng.randf(), 0.8) * 600.0
		var p := Vector3(sin(ang) * dist, 0, -cos(ang) * dist + -30)
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
		var u := 0.5 - 0.5 * cos(t / m.period * TAU)
		m.body.position = m.a.lerp(m.b, u)
	for b in bouncers:
		b.squash = maxf(0.0, b.squash - dt * 5)
		b.node.scale = Vector3(1 + b.squash * 0.15, 1 - b.squash * 0.3, 1 + b.squash * 0.15)
	for h in hooks:
		var ring: Node3D = h.get_meta("ring")
		ring.rotate_y(dt)
