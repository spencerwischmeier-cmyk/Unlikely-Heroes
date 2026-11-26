extends RefCounted
## The Dock Plaza, Skyharbor's bustling hub (island "plaza": x -22..22, z 14..46, floor 0).
## Ground level: the captain's fountain in the middle, shopfronts with awnings and neon signs on the west and
## south edges, market stalls on the north edge, a cafe, potted trees, lamps, a notice board and the bank.
## Upper ring (walkable roofs, all at H = 5): cafe roof -> bridge over the Terrace exit -> Gizmart Bulk roof ->
## Lucky Lug Nut roof -> the entrance arch -> bank roof -> bridge over the docks exit -> clock tower balcony,
## then two ledges up to the clock gallery (12.2) and a zip rail back down to the north gate.
## Ways up: crates and the cafe awning (west), the hat stall and crates by the bank (east).
## Kept clear: the chute rail landing (-17.5, 17.5), the cargo lift landing (x 22, z 12..20), every exit lane,
## the vault approach (x 2..11, z 39..43), Gizmart (-15, 42) and the bot spawn ring (r 9.6 round (0, 30)).

const M := preload("res://scripts/mats.gd")
const LIFE := preload("res://scripts/level/plaza/plaza_life.gd")
const H := 5.0                 # walkable height of the upper ring
const GALLERY := 12.2          # clock gallery
const TOWER := Vector3(17, 0, 22.5)
const PARK := Rect2(-22.5, 50, 9.5, 8.5)   # Pigeon Park, a floating pocket south-west (glide down from the Lug Nut roof)
const PARK_Y := 2.4

static var L: Node3D
static var _mats := {}
static var _aabbs := {}
static var life: Node3D
static var cables: Array = []
static var _made: Array = []       # primitive MeshInstance3Ds to merge into one mesh per material      # [from, to, sag, kind] kind "lantern" | "bunting" | "plain"

const SPOTS := {
	plaza_gate = [Vector3(0, 0.1, 53.5), PI],          # arriving from the junkyard, looking at the arch
	plaza_fountain = [Vector3(-9, 0.1, 38), PI * 0.8],
	plaza_west = [Vector3(-6, 0.1, 25), -PI / 2 + 0.3],
	plaza_roof = [Vector3(-20, H + 0.1, 30), PI * 0.7],
	plaza_clock = [Vector3(13.6, GALLERY + 0.1, 19.4), PI * 0.6],
	plaza_east = [Vector3(4, 0.1, 30), PI / 2 - 0.5],
	plaza_park = [Vector3(-14.5, PARK_Y + 0.1, 57.0), -PI * 0.7],
}

static func build(level: Node3D) -> void:
	L = level
	cables = []
	_made = []
	life = LIFE.new(); life.name = "PlazaLife"; L.add_child(life)
	_fountain()
	_floor_art()
	_shops()
	_arch()
	_bank_dressing()
	_bridges()
	_clock_tower()
	_stalls()
	_cafe()
	_props()
	_cables()
	_banners()
	_park()
	_sky_life()
	_merge_static()
	# hidden sprocket crates up on the ring
	L.crate_spots.append_array([
		Vector3(-20.6, 7.4, 21.4),     # on the cafe roof shed
		Vector3(-21, H, 44.6),         # Gizmart Bulk roof corner
		Vector3(0, H, 45.5),           # on top of the arch
		Vector3(20.3, H, 44.2),        # bank roof, behind the sign
		Vector3(20.2, GALLERY, 25.6),  # clock gallery, two of them
		Vector3(20.2, GALLERY, 22.6),
		Vector3(14.6, 0, 26.9),        # ground: under the tower balcony
		Vector3(-21.6, PARK_Y, 57.4),  # Pigeon Park, two of them
		Vector3(-20.2, PARK_Y, 57.6),
	])
	for k in SPOTS: L.debug_spots[k] = SPOTS[k]
	# level_skyharbor rebuilds debug_spots after the areas, so honour --at=<plaza spot> here
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--at=") and SPOTS.has(a.substr(5)):
			L.start_pos = SPOTS[a.substr(5)][0]; L.start_yaw = SPOTS[a.substr(5)][1]

## Scripted hops for the test: forward held until `go`, a single jump or a double jump.
static func _tap(go: float, double := true) -> Array:
	var st := [[0.0, "move_forward", true], [0.04, "jump", true], [go, "move_forward", false]]
	if double: st.append_array([[0.3, "jump", false], [0.36, "jump", true], [0.55, "jump", false]])
	else: st.append([0.45, "jump", false])
	st.sort_custom(func(x, y): return x[0] < y[0])
	return st

static func traversal_cases(moves: Dictionary) -> Dictionary:
	var hop := [[0.0, "move_forward", true], [0.04, "jump", true], [0.3, "jump", false], [0.36, "jump", true], [0.5, "jump", false], [0.7, "move_forward", false]]
	var out := {
		# west way up: crate (1.2) -> cafe awning (2.5) -> cafe roof (5)
		plaza_awning = [Vector3(-15.0, 1.3, 27.5), -PI / 2, moves.dj_short, 2.5, Rect2(-18, 21, 1.7, 7)],
		plaza_roof = [Vector3(-16.6, 2.6, 26.5), -PI / 2, hop, H, Rect2(-22.3, 20.3, 4.6, 8.4)],
		plaza_bank = [Vector3(15.5, 2.7, 34.4), 0.0, moves.dj, H, Rect2(10.7, 36.7, 10.6, 8.6)],
		plaza_zip = [Vector3(20.6, GALLERY + 0.1, 19.4), -PI / 2, moves.run, 0.0, Rect2(-22, 14, 44, 32)],
	}
	for r in [0.3, 0.4]:
		var k := str(int(r * 100))
		out["plaza_crate_" + k] = [Vector3(-11.4, 0.1, 27.6), -PI / 2, _tap(r - 0.1, false), 1.2, Rect2(-15.2, 27.0, 2.4, 1.2)]
		out["plaza_stall_" + k] = [Vector3(12.4, 1.3, 35.0), PI / 2, _tap(r - 0.1), 2.6, Rect2(13.8, 33.8, 3.4, 2.6)]
		out["plaza_ledge1_" + k] = [Vector3(15.2, H + 0.1, 26.2), -PI / 2, _tap(r), 7.4, Rect2(8.3, 25.9, 2.6, 2.6)]
		if r > 0.35: out["plaza_ledge2_" + k] = [Vector3(9.6, 7.5, 27.8), PI, _tap(r), 9.8, Rect2(8.3, 20.5, 2.6, 2.6)]
		out["plaza_gallery_" + k] = [Vector3(9.0, 9.9, 21.8), PI / 2, _tap(r), GALLERY, Rect2(13, 18.5, 8, 8)]
	# Pigeon Park: glide off the Lug Nut roof, then hop the stepping pad back to the junkyard bridge
	# Pigeon Park: glide/double jump off the Lug Nut roof, then the stepping pad back to the junkyard bridge
	out["plaza_park"] = [Vector3(-17.5, H + 0.1, 44.6), 0.0, _tap(0.8), PARK_Y, PARK]
	out["plaza_park_back"] = [Vector3(-9.5, 0.1, 55.5), PI / 2, _tap(0.5), 0.0, Rect2(-5, 53, 5, 5)]
	out["plaza_park_pad"] = [Vector3(-14.0, PARK_Y + 0.1, 55.5), PI / 2, _tap(0.35), 0.0, Rect2(-10.5, 54, 3, 3)]
	return out

# ---------------------------------------------------------------- helpers
static func mat(key: String) -> Material:
	if _mats.has(key): return _mats[key]
	var m: Material
	match key:
		"plaster": m = M.surface("paint", Color(0.97, 0.92, 0.83), 0.0, 0.8, 0.6, true)
		"plaster_teal": m = M.surface("paint", Color(0.56, 0.8, 0.78), 0.0, 0.8, 0.6, true)
		"plaster_peach": m = M.surface("paint", Color(0.98, 0.74, 0.56), 0.0, 0.8, 0.6, true)
		"plaster_blue": m = M.surface("paint", Color(0.6, 0.72, 0.9), 0.0, 0.8, 0.6, true)
		"stone": m = M.surface("deck", Color(0.68, 0.64, 0.6), 0.05, 0.8, 0.5, true)
		"roof": m = M.worn("deck", Color(0.86, 0.8, 0.72), 0.14, 0.2, 0.7, 0.35)
		"brass": m = M.brass(true)
		"teal": m = M.paint(Color(0.16, 0.5, 0.53), true)
		"red": m = M.paint(Color(0.78, 0.24, 0.18), true)
		"cream": m = M.paint(Color(0.95, 0.9, 0.78), true)
		"dark": m = M.metal(Color(0.2, 0.22, 0.26), true)
		"wood": m = M.wood(Color(0.82, 0.6, 0.42))
		"window": m = M.glow(Color(1.0, 0.72, 0.4), 1.5)
		"window_dim": m = M.glow(Color(0.95, 0.6, 0.35), 0.6)
		"glass": m = M.std(Color(0.1, 0.14, 0.18), 0.6, 0.12)
		"leaf": m = M.leaf(Color(0.33, 0.68, 0.35))
		"water": m = _water()
		"lantern": m = M.glow(Color(1.0, 0.62, 0.25), 4.5)
		"bulb": m = M.glow(Color(1.0, 0.85, 0.55), 5.0)
		"cable": m = M.std(Color(0.12, 0.12, 0.14), 0.3, 0.6)
		"clockface": m = M.std(Color(0.98, 0.95, 0.86), 0.0, 0.5)
		"gold": m = M.std(Color(0.95, 0.72, 0.3), 1.0, 0.25)
		"paper": m = M.std(Color(0.95, 0.92, 0.82), 0.0, 0.9)
		_:
			if key.begins_with("cloth_"): m = M.cloth(Color.html(key.substr(6)))
			elif key.begins_with("glow_"): m = M.glow(Color.html(key.substr(5)), 3.0)
			else: m = M.std(Color.html(key), 0.1, 0.6)
	_mats[key] = m
	return m

static func _water() -> StandardMaterial3D:
	var m := M.std(Color(0.3, 0.75, 0.9, 0.7), 0.1, 0.05)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true; m.emission = Color(0.2, 0.6, 0.8); m.emission_energy_multiplier = 0.6
	return m

static func bx(pos: Vector3, size: Vector3, m: String, collide := false, parent: Node = null) -> MeshInstance3D:
	var mi: MeshInstance3D = L.box(pos, size, mat(m), collide, parent if parent else L)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if size.length() > 2.0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_made.append(mi)
	return mi

static func cy(pos: Vector3, r_top: float, r_bot: float, h: float, m: String, sides := 16, parent: Node = null) -> MeshInstance3D:
	var cm := CylinderMesh.new(); cm.top_radius = r_top; cm.bottom_radius = r_bot; cm.height = h; cm.radial_segments = sides
	cm.rings = 1
	var mi: MeshInstance3D = L.mesh_at(cm, mat(m), pos, parent if parent else L)
	_made.append(mi)
	return mi

static func sphere(pos: Vector3, r: float, m: String, parent: Node = null, hemi := false) -> MeshInstance3D:
	var s := SphereMesh.new(); s.radius = r; s.height = r * (1.0 if hemi else 2.0); s.is_hemisphere = hemi
	s.radial_segments = 16; s.rings = 8
	var mi: MeshInstance3D = L.mesh_at(s, mat(m), pos, parent if parent else L)
	_made.append(mi)
	return mi

static func frame(pos: Vector3, yaw: float, parent: Node = null) -> Node3D:
	var n := Node3D.new(); n.position = pos; n.rotation.y = yaw
	(parent if parent else L).add_child(n)
	return n

static func light(pos: Vector3, c: Color, energy := 2.0, rng := 8.0, parent: Node = null) -> OmniLight3D:
	var l := OmniLight3D.new(); l.light_color = c; l.light_energy = energy; l.omni_range = minf(rng, 12.0)
	l.shadow_enabled = false; l.position = pos
	(parent if parent else L).add_child(l)
	return l

## A neon-ish sign: pale core with a thick coloured outline and a soft glow panel behind it.
static func neon(text: String, pos: Vector3, yaw: float, c: Color, px := 0.01, parent: Node = null, board := true) -> Label3D:
	var n := frame(pos, yaw, parent)
	var l := Label3D.new(); l.text = text; l.font_size = 96; l.pixel_size = px
	l.modulate = c.lerp(Color.WHITE, 0.65); l.outline_modulate = c; l.outline_size = 22
	l.shaded = false; l.double_sided = false; l.position.z = 0.06
	n.add_child(l)
	if board:
		var w := text.length() * 96 * px * 0.62 + 0.5
		bx(Vector3(0, 0, -0.02), Vector3(w, 96 * px * 1.5, 0.08), "glass", false, n)
		bx(Vector3(0, 0, -0.06), Vector3(w + 0.14, 96 * px * 1.5 + 0.14, 0.06), "brass", false, n)
	return l

static func text(t: String, pos: Vector3, yaw: float, c: Color, px := 0.006, parent: Node = null, width := 0.0) -> Label3D:
	var l := Label3D.new(); l.text = t; l.font_size = 64; l.pixel_size = px; l.modulate = c; l.outline_size = 8
	l.outline_modulate = Color(0, 0, 0, 0.6); l.position = pos; l.rotation.y = yaw; l.double_sided = false
	if width > 0.0: l.width = width; l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	(parent if parent else L).add_child(l)
	return l

static func _load(path: String) -> Node3D:
	if not ResourceLoader.exists(path): return null
	var n: Node3D = load(path).instantiate()
	return n

static func _aabb(path: String, n: Node3D) -> AABB:
	if _aabbs.has(path): return _aabbs[path]
	var ab := AABB(); var first := true
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		var tr := Transform3D()
		var p: Node = mi
		while p != n and p is Node3D:
			tr = (p as Node3D).transform * tr; p = p.get_parent()
		var a := tr * mi.get_aabb()
		ab = a if first else ab.merge(a); first = false
	_aabbs[path] = ab
	return ab

## A Meshy model with its base centre at pos, scaled to `height` metres (or to `width` if height is 0).
static func model(path: String, pos: Vector3, yaw := 0.0, height := 1.0, width := 0.0, collide := false, shrink := 0.85, parent: Node = null) -> Node3D:
	var n := _load(path)
	if n == null: return null
	var ab := _aabb(path, n)
	var s := (width / maxf(ab.size.x, 0.001)) if width > 0.0 else (height / maxf(ab.size.y, 0.001))
	var holder := Node3D.new(); holder.position = pos; holder.rotation.y = yaw
	(parent if parent else L).add_child(holder)
	holder.add_child(n)
	n.scale = Vector3.ONE * s
	n.position = -Vector3(ab.get_center().x, ab.position.y, ab.get_center().z) * s
	if collide:
		var sb := StaticBody3D.new(); var cs := CollisionShape3D.new(); var sh := BoxShape3D.new()
		sh.size = Vector3(ab.size.x * s * shrink, ab.size.y * s, ab.size.z * s * shrink)
		cs.shape = sh; cs.position = Vector3(0, ab.size.y * s / 2, 0)
		sb.add_child(cs); holder.add_child(sb)
	holder.set_meta("size", ab.size * s)
	return holder

static func bonsai(pos: Vector3, yaw := 0.0, h := 2.2) -> void:
	if model("res://models/plaza/bonsai.glb", pos, yaw, h, 0.0, false) == null:
		L.prop("planter", pos, yaw)
		return
	# collide with the pot only
	var sb := StaticBody3D.new(); var cs := CollisionShape3D.new(); var sh := BoxShape3D.new()
	sh.size = Vector3(1.0, 0.8, 1.0) * (h / 2.2); cs.shape = sh; sb.position = pos + Vector3(0, sh.size.y / 2, 0)
	sb.add_child(cs); L.add_child(sb)

static func solid(pos: Vector3, size: Vector3) -> void:
	var sb := StaticBody3D.new(); var cs := CollisionShape3D.new(); var sh := BoxShape3D.new()
	sh.size = size; cs.shape = sh; sb.position = pos; sb.add_child(cs); L.add_child(sb)

# ---------------------------------------------------------------- the fountain
static func _fountain() -> void:
	var c := Vector3(0, 0, 28)
	var f := model("res://models/plaza/fountain.glb", c, PI, 0.0, 7.4, false)
	var hgt := 7.6
	if f:
		hgt = (f.get_meta("size") as Vector3).y
	else:
		cy(c + Vector3(0, 0.5, 0), 3.4, 3.6, 1.0, "teal", 32)
		cy(c + Vector3(0, 2.5, 0), 0.6, 0.8, 5.0, "brass", 12)
	# colliders: the outer rim and the central column
	for p in [[3.5, 1.15, 0.0], [1.3, hgt, 0.0]]:
		var sb := StaticBody3D.new(); var cs := CollisionShape3D.new(); var sh := CylinderShape3D.new()
		sh.radius = p[0]; sh.height = p[1]; cs.shape = sh; sb.position = c + Vector3(0, p[1] / 2, 0)
		sb.add_child(cs); L.add_child(sb)
	# water: spill from the upper basin, a spray from the statue's feet, glints in the pool
	_water_fx(c + Vector3(0, hgt * 0.37, 0), 2.75, 26, 0.9, Vector3(0, -9, 0), 0.6)
	_water_fx(c + Vector3(0, hgt * 0.5, 0), 0.7, 14, 1.0, Vector3(0, -7, 0), 2.4)
	light(c + Vector3(0, 1.4, 0), Color(0.45, 0.9, 1.0), 2.2, 8.0)
	light(c + Vector3(0, hgt + 0.5, 2.0), Color(1.0, 0.78, 0.5), 1.6, 7.0)
	life.add_loop("plaza_fountain", c + Vector3(0, 1.5, 0), -4.0, 5.0, 26.0)
	# a little brass plaque on the south side of the rim
	var pl := frame(c + Vector3(0, 0.75, 3.75), 0.0)
	bx(Vector3.ZERO, Vector3(1.6, 0.5, 0.06), "brass", false, pl)
	text("CAPT. ODO BRANNIGAN-FLOOP\nFOUNDER OF SKYHARBOR. PROBABLY.", Vector3(0, 0, 0.04), 0.0, Color(0.2, 0.12, 0.05), 0.0028, pl)

static func _water_fx(pos: Vector3, radius: float, amount: int, life_s: float, grav: Vector3, up: float) -> void:
	var p := CPUParticles3D.new()
	var q := QuadMesh.new(); q.size = Vector2(0.16, 0.34); p.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES; m.vertex_color_use_as_albedo = true
	p.material_override = m
	p.amount = amount; p.lifetime = life_s
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP; p.emission_ring_radius = radius; p.emission_ring_inner_radius = radius * 0.92; p.emission_ring_height = 0.05
	p.direction = Vector3(0, 1, 0); p.spread = 25; p.initial_velocity_min = up * 0.6; p.initial_velocity_max = up
	p.gravity = grav; p.scale_amount_min = 0.7; p.scale_amount_max = 1.3
	var ramp := Gradient.new(); ramp.set_color(0, Color(0.85, 0.97, 1.0, 0.85)); ramp.set_color(1, Color(0.7, 0.9, 1.0, 0.0)); p.color_ramp = ramp
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.position = pos
	L.add_child(p)

# ---------------------------------------------------------------- floor inlays
static func _floor_art() -> void:
	var c := Vector3(0, 0, 28)
	cy(c + Vector3(0, 0.012, 0), 5.6, 5.6, 0.02, "stone", 40)
	var ring := TorusMesh.new(); ring.inner_radius = 5.45; ring.outer_radius = 5.75; ring.rings = 48
	var rm: MeshInstance3D = L.mesh_at(ring, mat("brass"), c + Vector3(0, 0.0, 0)); rm.scale = Vector3(1, 0.12, 1)
	var ring2 := TorusMesh.new(); ring2.inner_radius = 4.3; ring2.outer_radius = 4.45; ring2.rings = 40
	var rm2: MeshInstance3D = L.mesh_at(ring2, mat("glow_5fe0ff"), c); rm2.scale = Vector3(1, 0.1, 1)
	# painted guide stripes from the fountain to the exits (gold, like the concept's yellow lanes)
	for s in [[Vector3(-3.2, 0.015, 41.0), Vector3(0.5, 0.02, 9.0)], [Vector3(3.2, 0.015, 41.0), Vector3(0.5, 0.02, 9.0)],
			[Vector3(-14.0, 0.015, 31.0), Vector3(14.0, 0.02, 0.5)], [Vector3(-14.0, 0.015, 35.0), Vector3(14.0, 0.02, 0.5)],
			[Vector3(13.5, 0.015, 28.5), Vector3(15.0, 0.02, 0.5)], [Vector3(13.5, 0.015, 31.5), Vector3(15.0, 0.02, 0.5)],
			[Vector3(-4.4, 0.015, 18.0), Vector3(0.5, 0.02, 7.0)], [Vector3(-7.6, 0.015, 18.0), Vector3(0.5, 0.02, 7.0)]]:
		bx(s[0], s[1], "e8b84a")
	# a compass rose of tiles under the arch
	for i in 8:
		var a := i * TAU / 8.0
		var t := bx(Vector3(sin(a) * 1.4, 0.016, 41.5 + cos(a) * 1.4), Vector3(0.35, 0.02, 1.2 if i % 2 == 0 else 0.7), "e8b84a" if i % 2 == 0 else "3fa6a8")
		t.rotation.y = a

# ---------------------------------------------------------------- shopfronts
## A two-storey shop: footprint r, front face "n"/"s"/"e"/"w", roof walkable at H. canopy = [from, to] along the
## facade (local x, metres from the facade centre); the canopy top (2.5) is a solid step.
static func shop(r: Rect2, face: String, wall: String, title: String, sub: String, c: Color, stripes: Array, canopy: Vector2, door := 0.0) -> Node3D:
	var ctr := r.get_center()
	bx(Vector3(ctr.x, (H - 0.4) / 2, ctr.y), Vector3(r.size.x, H - 0.4, r.size.y), wall, true)
	bx(Vector3(ctr.x, H - 0.2, ctr.y), Vector3(r.size.x + 0.4, 0.4, r.size.y + 0.4), "roof", true)
	bx(Vector3(ctr.x, H - 0.5, ctr.y), Vector3(r.size.x + 0.3, 0.2, r.size.y + 0.3), "brass")
	bx(Vector3(ctr.x, 0.3, ctr.y), Vector3(r.size.x + 0.24, 0.6, r.size.y + 0.24), "stone")
	bx(Vector3(ctr.x, 2.3, ctr.y), Vector3(r.size.x + 0.1, 0.14, r.size.y + 0.1), "teal")
	var yaw: float = {"s": 0.0, "e": PI / 2, "n": PI, "w": -PI / 2}[face]
	var along: float = r.size.x if face == "n" or face == "s" else r.size.y
	var depth: float = r.size.y if face == "n" or face == "s" else r.size.x
	var f := frame(Vector3(ctr.x, 0, ctr.y) + Vector3(sin(yaw), 0, cos(yaw)) * depth / 2, yaw)
	# pilasters
	var bays := maxi(2, roundi(along / 3.0))
	for i in bays + 1:
		var x := -along / 2 + along * i / bays
		bx(Vector3(x, 2.2, 0.08), Vector3(0.32, 4.4, 0.16), "cream", false, f)
	# door with a brass frame and a warm lamp
	bx(Vector3(door, 1.15, 0.03), Vector3(1.3, 2.2, 0.1), "glass", false, f)
	bx(Vector3(door, 2.3, 0.1), Vector3(1.6, 0.14, 0.14), "brass", false, f)
	for s in [-1, 1]: bx(Vector3(door + s * 0.72, 1.15, 0.1), Vector3(0.12, 2.3, 0.14), "brass", false, f)
	bx(Vector3(door + 0.4, 1.1, 0.1), Vector3(0.1, 0.1, 0.1), "glow_ffd27a", false, f)
	# shop windows either side of the door (ground floor) and a row of small upper windows
	var x0 := -along / 2 + 0.9
	while x0 < along / 2 - 0.9:
		if absf(x0 - door) > 1.4:
			bx(Vector3(x0, 1.35, 0.04), Vector3(1.2, 1.3, 0.08), "window", false, f)
			bx(Vector3(x0, 0.68, 0.14), Vector3(1.4, 0.1, 0.24), "cream", false, f)
			bx(Vector3(x0, 1.35, 0.1), Vector3(0.06, 1.3, 0.06), "dark", false, f)
		x0 += 1.7
	x0 = -along / 2 + 1.0
	var k := 0
	while x0 < along / 2 - 0.8:
		bx(Vector3(x0, 3.95, 0.04), Vector3(0.8, 0.8, 0.08), "window" if k % 3 != 1 else "window_dim", false, f)
		for s in [-1, 1]: bx(Vector3(x0 + s * 0.52, 3.95, 0.1), Vector3(0.2, 0.86, 0.06), stripes[1], false, f)
		bx(Vector3(x0, 3.47, 0.2), Vector3(0.9, 0.16, 0.3), "wood", false, f)
		for j in 3: sphere(Vector3(x0 - 0.28 + j * 0.28, 3.62, 0.2), 0.13, "leaf" if j != 1 else "e25b8a", f)
		x0 += 1.6; k += 1
	# the sign board between the floors
	if title != "":
		neon(title, Vector3(door if absf(door) < along / 2 - 2.5 else 0.0, 2.95, 0.18), 0.0, c, 0.0055, f)
		if sub != "": text(sub, Vector3(door if absf(door) < along / 2 - 2.5 else 0.0, 2.6, 0.24), 0.0, Color(1, 0.95, 0.85), 0.0032, f)
	# a blade sign sticking out at the end of the facade, with a little icon
	var bl := frame(Vector3(along / 2 - 0.5, 3.6, 0.0), 0.0, f)
	bx(Vector3(0, 0.45, 0.35), Vector3(0.08, 0.08, 0.8), "dark", false, bl)
	var plate := bx(Vector3(0, 0.0, 0.62), Vector3(0.08, 0.8, 0.8), stripes[1], false, bl)
	bx(Vector3(0, 0.0, 0.62), Vector3(0.1, 0.86, 0.86), "brass", false, bl).scale = Vector3(0.9, 1, 1)
	plate.position.x = 0.02
	for sx in [-1, 1]:
		var ic := frame(Vector3(sx * 0.07, 0, 0.62), sx * PI / 2, bl)
		if title.begins_with("THE RUSTY"):
			sphere(Vector3(0, -0.05, 0), 0.2, "cream", ic); cy(Vector3(0.22, 0.0, 0), 0.03, 0.06, 0.25, "cream", 6, ic).rotation.z = -0.9
			sphere(Vector3(0, 0.17, 0), 0.06, "brass", ic)
		elif title.begins_with("LUCKY"):
			var nut := cy(Vector3.ZERO, 0.26, 0.26, 0.08, "brass", 6, ic); nut.rotation.x = PI / 2
			var hole := cy(Vector3(0, 0, 0.03), 0.11, 0.11, 0.06, "dark", 12, ic); hole.rotation.x = PI / 2
		else:
			bx(Vector3(0, 0, 0), Vector3(0.36, 0.44, 0.06), "e04a3a", false, ic)
			bx(Vector3(0, 0.05, 0.04), Vector3(0.24, 0.06, 0.02), "glow_8cff6a", false, ic)
	# the awning: solid striped slats (a step up to the roof) with a scalloped valance and a row of bulbs
	if canopy.y > canopy.x:
		var w := canopy.y - canopy.x
		var n := maxi(2, roundi(w / 0.55))
		for i in n:
			var cx := canopy.x + (i + 0.5) * w / n
			bx(Vector3(cx, 2.44, 0.8), Vector3(w / n, 0.12, 1.6), "cloth_" + stripes[i % 2], true, f)
			bx(Vector3(cx, 2.24, 1.62), Vector3(w / n * 0.94, 0.34, 0.05), "cloth_" + stripes[(i + 1) % 2], false, f)
		bx(Vector3((canopy.x + canopy.y) / 2, 2.52, 1.6), Vector3(w, 0.06, 0.06), "dark", false, f)
		for s in [canopy.x + 0.15, canopy.y - 0.15]:
			var br := bx(Vector3(s, 2.0, 0.45), Vector3(0.08, 0.08, 1.1), "dark", false, f); br.rotation.x = -0.6
		var nb := int(w / 0.7)
		for i in nb: sphere(Vector3(canopy.x + (i + 0.5) * w / nb, 2.02, 1.66), 0.06, "bulb", f)
		light(Vector3((canopy.x + canopy.y) / 2, 1.9, 1.2), Color(1.0, 0.75, 0.45), 1.4, 6.0, f)
	return f

static func _shops() -> void:
	# west: the Rusty Kettle cafe (its awning is the way up to the ring)
	var cafe := shop(Rect2(-22, 20.5, 4, 8), "e", "plaster_teal", "THE RUSTY KETTLE", "TEA  ·  COFFEE  ·  SUSPICIOUS SCONES",
		Color(0.35, 1.0, 0.85), ["f2e6c8", "2a8c8a"], Vector2(-3.8, 3.8), -1.2)
	# west-south: Gizmart Bulk & Surplus behind the kiosk
	shop(Rect2(-22, 37.5, 4, 8.5), "e", "plaster_peach", "GIZMART BULK", "NO REFUNDS  ·  NO REGRETS  ·  NO KIDDING",
		Color(0.55, 1.0, 0.4), ["f6d24a", "e0533a"], Vector2(-4.0, -2.1), 2.5)
	# south: the Lucky Lug Nut, charms and spare parts
	shop(Rect2(-18, 43.4, 8, 2.6), "n", "plaster_blue", "LUCKY LUG NUT", "CHARMS & SPARE PARTS  ·  MOSTLY PARTS",
		Color(1.0, 0.45, 0.8), ["f4efe6", "d9473f"], Vector2(-3.8, -1.2), -2.2)
	# roof railings on the outer edges (the plaza side stays open for the jumps)
	L.railing(-22.1, 20.3, -22.1, 46.1, H)
	L.railing(-22.1, 46.1, -19.5, 46.1, H)   # gap: glide off to Pigeon Park
	L.railing(-15.0, 46.1, -10, 46.1, H)
	L.railing(-22.1, 20.3, -18, 20.3, H)
	# cafe roof pocket: a little glasshouse shed with a crate on top (one more double jump)
	bx(Vector3(-20.6, H + 1.2, 21.6), Vector3(2.6, 2.4, 2.0), "plaster_teal", true)
	bx(Vector3(-20.6, H + 2.45, 21.6), Vector3(2.9, 0.1, 2.3), "roof", true)
	bx(Vector3(-19.28, H + 1.3, 21.6), Vector3(0.05, 1.4, 1.5), "window", false)
	bonsai(Vector3(-21.3, H, 25.8), 0.4, 1.6)
	L.prop("vent_stack", Vector3(-21.0, H, 27.6), 0.0, 0.8, true)
	DocksDressing.steam(L, Vector3(-21.0, H + 2.6, 27.6), 0.6)
	L.prop("antenna", Vector3(-21.4, H, 39.0), 0.0, 0.8, false)
	L.prop("water_tower", Vector3(-20.2, H, 41.5), 0.3, 0.55, true)
	L.prop("vent_stack", Vector3(-12, H, 45.4), 0.0, 0.7, true)

# ---------------------------------------------------------------- the entrance arch
static func _arch() -> void:
	for x in [-9.25, 9.25]:
		bx(Vector3(x, 0.35, 45.5), Vector3(1.8, 0.7, 1.8), "stone", true)
		bx(Vector3(x, 2.4, 45.5), Vector3(1.4, 4.0, 1.4), "plaster", true)
		for s in [-1, 1]: bx(Vector3(x + s * 0.72, 2.4, 45.5), Vector3(0.12, 3.6, 1.0), "teal")
		bx(Vector3(x, 4.25, 45.5), Vector3(1.7, 0.3, 1.7), "brass")
		var lt := frame(Vector3(x - signf(x) * 0.76, 3.1, 44.9), 0.0)
		cy(Vector3.ZERO, 0.18, 0.14, 0.45, "lantern", 8, lt)
		cy(Vector3(0, 0.3, 0), 0.0, 0.22, 0.2, "dark", 8, lt)
	# the deck across the top (part of the ring), joining the Lug Nut roof and the bank roof
	bx(Vector3(0.35, H - 0.3, 45.5), Vector3(20.7, 0.6, 1.8), "roof", true)
	bx(Vector3(0.35, H - 0.62, 45.5), Vector3(20.7, 0.1, 1.9), "brass")
	L.railing(-10, 46.45, 10.7, 46.45, H)
	# sweeping brackets under the deck
	for x in [-7.6, 7.6]:
		var b := bx(Vector3(x, 3.75, 45.5), Vector3(2.4, 0.3, 0.5), "brass"); b.rotation.z = 0.45 * signf(x)
	# signs: welcome on the way in, the plaza name on the way out
	neon("WELCOME TO DOCK PLAZA", Vector3(0, 3.95, 46.42), 0.0, Color(1.0, 0.7, 0.25), 0.0085)
	neon("DOCK PLAZA", Vector3(0, 3.95, 44.58), PI, Color(0.35, 0.9, 1.0), 0.0085)
	# a big brass gear emblem standing on the deck's south edge
	var g := frame(Vector3(0, H + 1.2, 46.2), 0.0)
	var d := cy(Vector3.ZERO, 0.95, 0.95, 0.2, "gold", 20, g); d.rotation.x = PI / 2
	for i in 10:
		var t := bx(Vector3(cos(i * TAU / 10) * 1.05, sin(i * TAU / 10) * 1.05, 0), Vector3(0.3, 0.3, 0.2), "gold", false, g)
		t.rotation.z = i * TAU / 10
	cy(Vector3(0, 0, 0.12), 0.45, 0.45, 0.06, "teal", 16, g).rotation.x = PI / 2
	bx(Vector3(0, -1.0, 0), Vector3(0.3, 0.6, 0.3), "dark", false, g)
	life.spin(g, 0.25); g.set_meta("plaza_anim", true)
	for x in [-9.25, 9.25]: L.prop("flag_pole", Vector3(x, H, 45.5), 0.0, 0.7, false)

# ---------------------------------------------------------------- the bank (built in level_skyharbor.gd)
static func _bank_dressing() -> void:
	# columns either side of the vault door, a pediment band and the neon name
	for z in [38.7, 43.3]:
		bx(Vector3(10.55, 0.25, z), Vector3(0.9, 0.5, 0.9), "stone", true)
		cy(Vector3(10.55, 2.25, z), 0.3, 0.34, 3.6, "cream", 14)
		bx(Vector3(10.55, 4.2, z), Vector3(0.8, 0.3, 0.8), "brass")
	neon("SAVINGS & LOAN", Vector3(10.62, 3.75, 41.0), -PI / 2, Color(1.0, 0.82, 0.35), 0.006)
	L.railing(21.4, 36.8, 21.4, 45.4, H)
	L.railing(10.7, 45.4, 21.4, 45.4, H)
	# a rooftop sign (the crate hides behind it)
	var s := frame(Vector3(18.6, H, 43.4), PI * 0.5)
	for x in [-1.4, 1.4]: bx(Vector3(x, 0.9, 0), Vector3(0.12, 1.8, 0.12), "dark", false, s)
	bx(Vector3(0, 1.7, 0), Vector3(3.4, 1.0, 0.12), "teal", true, s)
	text("YOUR SPROCKETS ARE SAFE WITH US*", Vector3(0, 1.78, 0.08), 0.0, Color(1, 0.93, 0.7), 0.0042, s)
	text("*NOT A LEGALLY BINDING STATEMENT", Vector3(0, 1.4, 0.08), 0.0, Color(1, 0.93, 0.7, 0.8), 0.0025, s)
	L.prop("dish_small", Vector3(13, H, 38), 2.4, 1.0, false)

# ---------------------------------------------------------------- bridges over the exits
static func _bridges() -> void:
	# west, over the Terrace exit
	bx(Vector3(-20.5, H - 0.25, 33), Vector3(3.2, 0.5, 9.4), "roof", true)
	bx(Vector3(-20.5, H - 0.6, 33), Vector3(3.0, 0.2, 9.2), "dark")
	for z in [29.6, 33, 36.4]: bx(Vector3(-20.5, H - 0.9, z), Vector3(3.0, 0.4, 0.3), "dark")
	neon("MARKET TERRACE", Vector3(-18.86, H - 0.95, 33), PI / 2, Color(1.0, 0.6, 0.3), 0.005, null, false)
	neon("DOCK PLAZA", Vector3(-22.14, H - 0.95, 33), -PI / 2, Color(0.35, 0.9, 1.0), 0.005, null, false)
	# east, over the docks exit, from the bank roof to the clock tower balcony
	bx(Vector3(20.75, H - 0.25, 31.6), Vector3(2.5, 0.5, 10.4), "roof", true)
	bx(Vector3(20.75, H - 0.6, 31.6), Vector3(2.3, 0.2, 10.2), "dark")
	for z in [27.5, 31.6, 35.6]: bx(Vector3(20.75, H - 0.9, z), Vector3(2.3, 0.4, 0.3), "dark")
	neon("CARGO DOCKS", Vector3(19.48, H - 0.95, 30), -PI / 2, Color(0.4, 0.95, 1.0), 0.005, null, false)
	L.railing(22.05, 26.4, 22.05, 36.8, H)

# ---------------------------------------------------------------- the clock tower
static func _clock_tower() -> void:
	var T := TOWER
	bx(T + Vector3(0, 0.3, 0), Vector3(5.6, 0.6, 5.6), "stone", true)
	bx(T + Vector3(0, 2.5, 0), Vector3(5, 5.0, 5), "plaster", true)
	bx(T + Vector3(-2.52, 1.15, 0), Vector3(0.1, 2.2, 1.3), "glass")
	bx(T + Vector3(-2.56, 2.35, 0), Vector3(0.12, 0.16, 1.6), "brass")
	neon("HARBOR CLOCK", Vector3(T.x - 2.56, 3.2, T.z), -PI / 2, Color(1.0, 0.8, 0.4), 0.0045)
	text("ALWAYS FIVE MINUTES LATE. EST. WHENEVER.", Vector3(T.x - 2.58, 2.75, T.z), -PI / 2, Color(0.2, 0.15, 0.1), 0.003)
	# the balcony (part of the ring) on four posts
	bx(Vector3(17.5, H - 0.25, 22.75), Vector3(9, 0.5, 7.5), "roof", true)
	bx(Vector3(17.5, H - 0.55, 22.75), Vector3(9.1, 0.12, 7.6), "brass")
	for p in [Vector2(13.3, 19.3), Vector2(21.7, 19.3), Vector2(13.3, 26.2), Vector2(21.7, 26.2)]:
		cy(Vector3(p.x, (H - 0.5) / 2, p.y), 0.16, 0.2, H - 0.5, "dark", 8)
		bx(Vector3(p.x, 0.2, p.y), Vector3(0.6, 0.4, 0.6), "stone", true)
	L.railing(22.05, 19.0, 22.05, 26.4, H)
	L.railing(13.0, 19.0, 22.05, 19.0, H)
	# the shaft up to the belfry
	bx(T + Vector3(0, H + 5.5, 0), Vector3(4.4, 11.0, 4.4), "plaster", true)
	for sx in [-1, 1]:
		for sz in [-1, 1]: bx(T + Vector3(sx * 2.1, H + 5.5, sz * 2.1), Vector3(0.4, 11.0, 0.4), "teal")
	for y in [H + 0.2, 8.7, 15.9]: bx(T + Vector3(0, y, 0), Vector3(4.7, 0.25, 4.7), "brass")
	for i in 4:
		var a := i * PI / 2
		var w := frame(T + Vector3(sin(a) * 2.22, 7.0, cos(a) * 2.22), a)
		bx(Vector3.ZERO, Vector3(0.7, 1.2, 0.06), "window", false, w)
		bx(Vector3(0, 0.66, 0.04), Vector3(0.9, 0.12, 0.1), "brass", false, w)
	# the gallery ring (12.2) round the shaft
	var g := GALLERY
	for b in [[Vector3(17, g - 0.2, 19.4), Vector3(8, 0.4, 1.8)], [Vector3(17, g - 0.2, 25.6), Vector3(8, 0.4, 1.8)],
			[Vector3(13.9, g - 0.2, 22.5), Vector3(1.8, 0.4, 4.4)], [Vector3(20.1, g - 0.2, 22.5), Vector3(1.8, 0.4, 4.4)]]:
		bx(b[0], b[1], "roof", true)
		bx(b[0] + Vector3(0, -0.3, 0), b[1] + Vector3(0.1, -0.25, 0.1), "brass")
	for p in [Vector2(13.2, 18.7), Vector2(20.8, 18.7), Vector2(13.2, 26.3), Vector2(20.8, 26.3)]:
		var st := bx(Vector3(p.x, g - 1.6, p.y), Vector3(0.25, 2.4, 0.25), "dark")
		st.rotation = Vector3((p.y - T.z) * 0.12, 0, -(p.x - T.x) * 0.12)
	L.railing(21.0, 18.5, 21.0, 26.5, g)
	L.railing(13.0, 26.5, 21.0, 26.5, g)
	L.railing(13.0, 18.5, 21.0, 18.5, g)
	L.railing(13.0, 23.6, 13.0, 26.5, g)
	light(T + Vector3(-3.2, g + 1.5, 0), Color(1.0, 0.8, 0.5), 1.6, 8.0)
	# PA horns on the gallery corners
	for p in [Vector3(20.6, g + 1.6, 18.9), Vector3(13.4, g + 1.6, 26.1)]:
		var hn := cy(p, 0.32, 0.08, 0.6, "brass", 12); hn.rotation.z = PI / 2 if p.x < T.x else -PI / 2
	# clock faces
	for i in 4:
		var a := i * PI / 2
		var cf := frame(T + Vector3(sin(a) * 2.25, 14.0, cos(a) * 2.25), a)
		var disc := cy(Vector3.ZERO, 1.6, 1.6, 0.12, "clockface", 32, cf); disc.rotation.x = PI / 2
		var rim := TorusMesh.new(); rim.inner_radius = 1.55; rim.outer_radius = 1.78; rim.rings = 32
		var rm: MeshInstance3D = L.mesh_at(rim, mat("brass"), Vector3(0, 0, 0.05), cf); rm.rotation.x = PI / 2; rm.scale = Vector3(1, 0.5, 1)
		for h in 12:
			var ha := h * TAU / 12
			var tk := bx(Vector3(sin(ha) * 1.3, cos(ha) * 1.3, 0.08), Vector3(0.08, 0.3 if h % 3 == 0 else 0.16, 0.04), "dark", false, cf)
			tk.rotation.z = -ha
		var hp := Node3D.new(); hp.position.z = 0.1; cf.add_child(hp)
		bx(Vector3(0, 0.4, 0), Vector3(0.14, 0.85, 0.04), "dark", false, hp)
		var mp := Node3D.new(); mp.position.z = 0.14; cf.add_child(mp)
		bx(Vector3(0, 0.6, 0), Vector3(0.08, 1.25, 0.04), "red", false, mp)
		sphere(Vector3(0, 0, 0.16), 0.1, "brass", cf)
		life.clock_hands.append([hp, mp]); hp.set_meta("plaza_anim", true); mp.set_meta("plaza_anim", true)
	# belfry: four piers, the bell, a gold dome and the spire
	for sx in [-1, 1]:
		for sz in [-1, 1]: bx(T + Vector3(sx * 1.85, 17.3, sz * 1.85), Vector3(0.7, 2.6, 0.7), "cream", true)
	var bell := frame(T + Vector3(0, 17.8, 0), 0.0)
	sphere(Vector3(0, -0.2, 0), 0.75, "gold", bell, true)
	cy(Vector3(0, -0.55, 0), 0.75, 0.95, 0.3, "gold", 16, bell)
	life.bell = bell; bell.set_meta("plaza_anim", true)
	bx(T + Vector3(0, 18.75, 0), Vector3(4.9, 0.3, 4.9), "brass", true)
	sphere(T + Vector3(0, 18.9, 0), 2.45, "plaster", null, true).scale = Vector3(1, 1.15, 1)
	for i in 8:
		var a := i * TAU / 8
		var rib := bx(T + Vector3(sin(a) * 1.55, 19.95, cos(a) * 1.55), Vector3(0.14, 2.1, 0.14), "gold")
		rib.rotation = Vector3(cos(a) * 0.75, 0, -sin(a) * 0.75)
	cy(T + Vector3(0, 21.9, 0), 0.5, 0.7, 0.8, "gold", 12)
	sphere(T + Vector3(0, 22.5, 0), 0.4, "gold")
	cy(T + Vector3(0, 24.0, 0), 0.0, 0.12, 2.6, "gold", 8)
	light(T + Vector3(0, 17.6, 0), Color(1.0, 0.75, 0.4), 2.0, 9.0)
	# a weathervane flag
	L.prop("flag_pole", T + Vector3(1.85, 18.9, 1.85), 0.0, 0.5, false)
	# tower ledges: balcony -> 7.4 -> 9.8 -> gallery
	for p in [[Vector3(9.6, 7.4, 27.2)], [Vector3(9.6, 9.8, 21.8)]]:
		var top: Vector3 = p[0]
		L.block(top.x, top.z, 2.6, 2.6, 0.5, top.y - 0.5, mat("roof"))
		var arm := bx(Vector3(12.9, top.y - 0.95, minf(top.z, 24.6)), Vector3(4.4, 0.22, 0.3), "dark"); arm.rotation.z = -0.3
		bx(Vector3(top.x, top.y - 0.62, top.z), Vector3(2.7, 0.1, 2.7), "brass")
	# zip rail from the gallery's north-west corner down over the market to the north gate
	L.rail([Vector3(19.4, GALLERY + 0.4, 19.4), Vector3(16.5, GALLERY + 0.35, 19.4), Vector3(13.0, GALLERY + 0.1, 19.0), Vector3(9.5, 10.6, 18.4),
		Vector3(5, 7.5, 18.6), Vector3(1, 4.4, 19.4), Vector3(-3.5, 1.6, 20.0), Vector3(-6.5, 0.5, 20.3)])
	L.hint_sign("ZIP LINE TO THE NORTH GATE. HOLD ON TO YOUR HAT", Vector3(17, GALLERY, 20.25), PI)
	life.chime_pos = T + Vector3(0, 17.6, 0)
	life.pa_pos = T + Vector3(0, GALLERY + 2, 0)
	# the sky-side wall of the tower gets a ladder look and pipes
	for y in range(1, 11):
		bx(T + Vector3(2.56, y * 1.0, 1.2), Vector3(0.08, 0.06, 0.7), "dark")
	cy(T + Vector3(2.4, 8, -1.6), 0.12, 0.12, 16, "brass", 8)

# ---------------------------------------------------------------- market stalls
static func stall(pos: Vector3, yaw: float, title: String, stripes: Array, goods: Array, glow: Color) -> void:
	var f := frame(pos, yaw)
	bx(Vector3(0, 0.5, 0.55), Vector3(3.0, 1.0, 0.9), "wood", true, f)
	bx(Vector3(0, 1.03, 0.62), Vector3(3.2, 0.08, 1.05), "cream", false, f)
	bx(Vector3(0, 0.45, 0.99), Vector3(3.0, 0.5, 0.04), "cloth_" + stripes[0], false, f)
	bx(Vector3(0, 1.0, -0.7), Vector3(3.0, 2.0, 0.3), "wood", true, f)
	for x in [-1.45, 1.45]:
		for z in [-0.8, 1.0]: bx(Vector3(x, 1.25, z), Vector3(0.1, 2.5, 0.1), "dark", false, f)
	# striped roof (solid: a step)
	for i in 6:
		bx(Vector3(-1.4 + i * 0.56, 2.56, 0.1), Vector3(0.56, 0.12, 2.4), "cloth_" + stripes[i % 2], true, f)
		bx(Vector3(-1.4 + i * 0.56, 2.33, 1.32), Vector3(0.53, 0.36, 0.04), "cloth_" + stripes[(i + 1) % 2], false, f)
	neon(title, Vector3(0, 2.95, 1.25), 0.0, glow, 0.0045, f)
	for x in [-1.2, 1.2]: bx(Vector3(x, 2.88, 1.2), Vector3(0.05, 0.5, 0.05), "dark", false, f)
	# goods on the counter and the shelf
	var rng := RandomNumberGenerator.new(); rng.seed = int(pos.x * 31 + pos.z * 7)
	for i in 9:
		var g: String = goods[i % goods.size()]
		var p := Vector3(-1.25 + (i % 5) * 0.62 + rng.randf_range(-0.1, 0.1), 1.17, 0.45 + (0.35 if i >= 5 else 0.0))
		if i % 3 == 0: bx(p + Vector3(0, -0.02, 0), Vector3(0.45, 0.18, 0.3), "wood", false, f)
		sphere(p + Vector3(0, 0.1, 0), rng.randf_range(0.1, 0.15), g, f)
		sphere(p + Vector3(0.14, 0.08, 0.05), 0.09, goods[(i + 1) % goods.size()], f)
	for i in 5:
		bx(Vector3(-1.2 + i * 0.6, 1.5, -0.5), Vector3(0.4, 0.35, 0.25), goods[i % goods.size()], false, f)
	var bot := model("res://models/docks/dock_bot.glb", Vector3(-0.6, 0, -0.15), PI, 1.25, 0.0, false, 0.85, f)
	if bot: life.bob(bot)
	var lt := sphere(Vector3(1.1, 2.15, 0.9), 0.12, "lantern", f)
	cy(Vector3(1.1, 2.35, 0.9), 0.01, 0.01, 0.3, "cable", 4, f)
	light(Vector3(0, 2.0, 1.0), Color(1, 0.75, 0.45), 1.2, 5.0, f)
	lt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

static func _stalls() -> void:
	stall(Vector3(4.5, 0, 16.2), 0.0, "SKY-FRUIT", ["f6d24a", "3c9a5c"], ["e8543c", "f2a33a", "a5d04a", "f6d24a"], Color(1.0, 0.85, 0.3))
	stall(Vector3(10.0, 0, 16.2), 0.0, "PROP-POPS", ["f4efe6", "e05a9a"], ["f07ab0", "7ad0f0", "f6e07a", "ffffff"], Color(1.0, 0.45, 0.8))
	# hat stall by the bank: its roof is the east way up
	stall(Vector3(15.5, 0, 35.2), PI, "HATS FOR HEADS", ["f4efe6", "3a7fd0"], ["3a4a6a", "d9473f", "5a3a2a", "e8c87a"], Color(0.4, 0.8, 1.0))
	L.prop("crate_small", Vector3(12.4, 0, 35.0), 0.2, 1.2, true)
	L.prop("barrel", Vector3(13.2, 0, 32.4), 0.0, 1.0, true)

# ---------------------------------------------------------------- the cafe terrace
static func _cafe() -> void:
	for t: Vector3 in [Vector3(-14.2, 0, 21.8), Vector3(-11.8, 0, 24.9), Vector3(-14.4, 0, 24.6)]:
		cy(t + Vector3(0, 0.38, 0), 0.06, 0.28, 0.76, "dark", 10)
		var top := cy(t + Vector3(0, 0.78, 0), 0.55, 0.55, 0.06, "cream", 18)
		top.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		solid(t + Vector3(0, 0.4, 0), Vector3(1.0, 0.8, 1.0))
		cy(t + Vector3(0, 1.6, 0), 0.03, 0.03, 1.7, "dark", 6)
		var um := cy(t + Vector3(0, 2.5, 0), 0.06, 1.35, 0.5, "cloth_e0533a" if t.z < 23 else "cloth_2a8c8a", 12)
		um.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		cy(t + Vector3(0, 2.26, 0), 1.36, 1.36, 0.1, "cloth_f2e6c8", 12)
		for i in 2:
			var a := i * PI + 0.6
			var ch: Vector3 = t + Vector3(sin(a) * 0.85, 0, cos(a) * 0.85)
			bx(ch + Vector3(0, 0.45, 0), Vector3(0.42, 0.06, 0.42), "wood")
			bx(ch + Vector3(sin(a) * 0.2, 0.75, cos(a) * 0.2), Vector3(0.42, 0.55, 0.06), "wood").rotation.y = a
			for s in [-1, 1]: bx(ch + Vector3(s * 0.17, 0.22, 0), Vector3(0.04, 0.44, 0.36), "dark")
		sphere(t + Vector3(0.15, 0.88, 0.1), 0.07, "cream")
		cy(t + Vector3(-0.15, 0.87, -0.05), 0.06, 0.05, 0.12, "e0533a", 8)
	# a chalkboard sandwich sign
	var s := frame(Vector3(-16.6, 0, 27.4), PI / 2 + 0.3)
	var b1 := bx(Vector3(0, 0.55, 0.15), Vector3(0.7, 1.0, 0.05), "2a2e2c", false, s); b1.rotation.x = -0.25
	text("TODAY:\nSCONE\n(DON'T ASK)", Vector3(0, 0.6, 0.3), 0.0, Color(1, 1, 0.95), 0.0035, s).rotation.x = -0.25

# ---------------------------------------------------------------- props round the plaza
static func _props() -> void:
	# benches round the fountain, facing out
	for i in 4:
		var a := PI / 4 + i * PI / 2
		L.prop("bench", Vector3(sin(a) * 5.4, 0, 28 + cos(a) * 5.4), a, 1.0, true)
	# potted trees framing the exits
	for p in [Vector3(-16.6, 0, 29.6), Vector3(-16.6, 0, 36.4), Vector3(20.6, 0, 25.0), Vector3(20.6, 0, 35.0),
			Vector3(-7.0, 0, 44.6), Vector3(7.0, 0, 44.6), Vector3(1.4, 0, 15.2), Vector3(-12.6, 0, 15.2)]:
		bonsai(p, randf() * TAU, 2.1)
	# lamp posts with warm lights
	for p in [Vector3(-12.5, 0, 18.6), Vector3(12.0, 0, 19.8), Vector3(-10.5, 0, 41.2), Vector3(7.6, 0, 37.2), Vector3(-16.8, 0, 39.0)]:
		L.prop("lamp_post", p, 0.0, 1.0, true)
	# notice board by the north gate
	var nb := frame(Vector3(-15.6, 0, 15.4), 0.0)
	for x in [-1.2, 1.2]: bx(Vector3(x, 1.1, 0), Vector3(0.14, 2.2, 0.14), "wood", true, nb)
	bx(Vector3(0, 1.45, 0), Vector3(2.5, 1.4, 0.1), "8a5a3a", false, nb)
	bx(Vector3(0, 2.25, 0), Vector3(2.8, 0.14, 0.4), "teal", false, nb)
	text("NOTICES", Vector3(0, 2.02, 0.07), 0.0, Color(1, 0.92, 0.7), 0.004, nb)
	var notes := [["LOST: ROLLER BOT.\nANSWERS TO 'GRRK'.\nDO NOT FEED.", "fff4c8", Vector2(-0.75, 1.55)],
		["FOR SALE: ONE CHAIR.\nSLIGHTLY EATEN.\nSEE V. IN JUNKYARD.", "d8f0ff", Vector2(0.0, 1.62)],
		["BAND PRACTICE\nCANCELLED\n(BOTS ATE DRUMS)", "ffd8e8", Vector2(0.75, 1.5)],
		["HAS ANYONE SEEN\nMY OTHER EYE?\n-D", "e0ffd8", Vector2(-0.4, 0.95)],
		["CRANE YARD NOISE\nCOMPLAINTS: TAKE\nA NUMBER", "fff4c8", Vector2(0.55, 0.98)]]
	for n in notes:
		var pp: Vector2 = n[2]
		var paper := bx(Vector3(pp.x, pp.y, 0.06), Vector3(0.66, 0.5, 0.01), n[1], false, nb)
		paper.rotation.z = randf_range(-0.08, 0.08)
		text(n[0], Vector3(pp.x, pp.y, 0.075), 0.0, Color(0.15, 0.12, 0.1), 0.0017, nb).rotation.z = paper.rotation.z
		sphere(Vector3(pp.x, pp.y + 0.2, 0.08), 0.03, "d9473f", nb)
	# crates, barrels and sacks along the edges (Meshy dock props reused)
	model("res://models/docks/crates.glb", Vector3(-8.2, 0, 16.0), 0.5, 1.5, 0.0, true)
	model("res://models/docks/barrels.glb", Vector3(13.4, 0, 16.0), 1.2, 1.2, 0.0, true)
	model("res://models/docks/crates.glb", Vector3(-19.6, 0, 44.3), 2.0, 1.4, 0.0, true)
	model("res://models/docks/barrels.glb", Vector3(-11.2, 0, 43.0), 0.3, 1.1, 0.0, true)
	model("res://models/docks/crates.glb", Vector3(19.8, 0, 21.0), -0.6, 1.3, 0.0, true)
	model("res://models/docks/cable_spool.glb", Vector3(15.8, 0, 27.4), 0.0, 1.0, 0.0, true)
	L.prop("crate_small", Vector3(-14.6, 0, 27.6), 0.1, 1.2, true)    # the west way up
	L.prop("crate_small", Vector3(-13.4, 0, 27.6), -0.05, 1.2, true)
	L.prop("barrel", Vector3(-16.9, 0, 21.0), 0.0, 1.0, true)
	L.prop("crate_small", Vector3(2.6, 0, 17.6), 0.4, 0.8, true)
	# a brass telescope for tourists on the south-east corner
	var tel := frame(Vector3(9.6, 0, 43.2), PI * 0.8)
	cy(Vector3(0, 0.6, 0), 0.08, 0.16, 1.2, "dark", 8, tel)
	var tube := cy(Vector3(0, 1.3, 0.2), 0.12, 0.16, 1.0, "brass", 12, tel); tube.rotation.x = 1.2

# ---------------------------------------------------------------- lantern strings and bunting
static func _cables() -> void:
	cables = [
		[Vector3(-18.0, 5.6, 22.5), Vector3(13.0, 6.2, 22.5), 2.2, "lantern"],
		[Vector3(-19.0, 5.6, 29.0), Vector3(-4.0, 5.5, 44.6), 1.6, "bunting"],
		[Vector3(10.7, 5.6, 36.8), Vector3(-19.0, 5.6, 34.0), 2.0, "bunting"],
		[Vector3(-19.0, 5.6, 37.0), Vector3(-10.0, 5.6, 43.4), 1.0, "lantern"],
		[Vector3(19.5, 5.6, 27.0), Vector3(11.0, 5.6, 36.8), 1.2, "lantern"],
		[Vector3(-18.0, 5.6, 24.0), Vector3(-12.0, 3.2, 15.4), 0.6, "bunting"],
		[Vector3(13.0, 12.8, 26.4), Vector3(-9.25, 5.4, 44.6), 3.2, "bunting"],
		[Vector3(-12.6, 4.4, 15.2), Vector3(1.4, 4.4, 15.2), 1.0, "lantern"],
	]
	var seg_mm := MultiMesh.new(); seg_mm.transform_format = MultiMesh.TRANSFORM_3D
	var seg := CylinderMesh.new(); seg.top_radius = 0.025; seg.bottom_radius = 0.025; seg.height = 1.0; seg.radial_segments = 5; seg.rings = 1
	seg_mm.mesh = seg
	var lan_mm := MultiMesh.new(); lan_mm.transform_format = MultiMesh.TRANSFORM_3D
	var lan := CylinderMesh.new(); lan.top_radius = 0.13; lan.bottom_radius = 0.16; lan.height = 0.34; lan.radial_segments = 8; lan.rings = 1
	lan_mm.mesh = lan
	var flag_mm := MultiMesh.new(); flag_mm.transform_format = MultiMesh.TRANSFORM_3D; flag_mm.use_colors = true
	var fl := PrismMesh.new(); fl.size = Vector3(0.45, 0.55, 0.02); fl.left_to_right = 0.5
	flag_mm.mesh = fl
	var segs: Array = []; var lans: Array = []; var flags: Array = []
	var cols := [Color(0.9, 0.3, 0.22), Color(0.98, 0.8, 0.25), Color(0.2, 0.62, 0.85), Color(0.3, 0.75, 0.45), Color(0.95, 0.95, 0.9)]
	for cdef in cables:
		var a: Vector3 = cdef[0]; var b: Vector3 = cdef[1]; var sag: float = cdef[2]
		var n := maxi(8, int(a.distance_to(b) / 0.9))
		var pts: Array = []
		for i in n + 1:
			var u := float(i) / n
			pts.append(a.lerp(b, u) + Vector3(0, -sag * 4.0 * u * (1.0 - u), 0))
		for i in n:
			var p0: Vector3 = pts[i]; var p1: Vector3 = pts[i + 1]
			var d := p1 - p0
			var basis := Basis.looking_at(d.normalized(), Vector3.UP if absf(d.normalized().y) < 0.99 else Vector3.RIGHT)
			basis = basis * Basis(Vector3.RIGHT, PI / 2)
			segs.append(Transform3D(basis * Basis.from_scale(Vector3(1, d.length(), 1)), (p0 + p1) / 2))
			var mid: Vector3 = (p0 + p1) / 2
			if cdef[3] == "lantern" and i % 2 == 1:
				lans.append(Transform3D(Basis(), mid + Vector3(0, -0.28, 0)))
			elif cdef[3] == "bunting":
				var yaw := atan2(-d.z, d.x)
				flags.append([Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, PI), mid + Vector3(0, -0.3, 0)), cols[flags.size() % cols.size()]])
	seg_mm.instance_count = segs.size()
	for i in segs.size(): seg_mm.set_instance_transform(i, segs[i])
	lan_mm.instance_count = lans.size()
	for i in lans.size(): lan_mm.set_instance_transform(i, lans[i])
	flag_mm.instance_count = flags.size()
	for i in flags.size():
		flag_mm.set_instance_transform(i, flags[i][0]); flag_mm.set_instance_color(i, flags[i][1])
	var fm := M.cloth(Color.WHITE); fm.vertex_color_use_as_albedo = true
	for pair in [[seg_mm, mat("cable")], [lan_mm, mat("lantern")], [flag_mm, fm]]:
		var mmi := MultiMeshInstance3D.new(); mmi.multimesh = pair[0]; mmi.material_override = pair[1]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		L.add_child(mmi)
	# a few of the lanterns actually light the floor
	for p in [Vector3(-2.5, 3.6, 22.5), Vector3(-14.5, 4.6, 40.2), Vector3(15.2, 4.6, 32.0)]:
		light(p, Color(1.0, 0.65, 0.3), 1.4, 7.0)

# ---------------------------------------------------------------- Pigeon Park
static func _park() -> void:
	var r := PARK; var y := PARK_Y; var c := r.get_center()
	L.island("plaza_park", r, y, Color(0.95, 0.97, 0.9), 1.6)
	L.fence(r, y, [["n", r.position.x, r.end.x], ["e", 53.5, 57.5]], "nsew")
	# a lawn with stepping stones
	bx(Vector3(c.x - 0.8, y + 0.03, c.y + 0.8), Vector3(6.4, 0.06, 5.6), "leaf")
	for i in 5: cy(Vector3(c.x + 3.2 - i * 0.2, y + 0.07, r.position.y + 1.2 + i * 1.4), 0.35, 0.35, 0.05, "stone", 10)
	bonsai(Vector3(r.position.x + 1.2, y, r.position.y + 1.3), 0.5, 2.4)
	bonsai(Vector3(r.position.x + 1.3, y, r.end.y - 3.4), 2.0, 1.9)
	# a bird bath with pigeons, a bench facing the sky and a coin telescope
	var bb := Vector3(c.x - 0.8, y, c.y + 0.2)
	cy(bb + Vector3(0, 0.45, 0), 0.18, 0.3, 0.9, "cream", 12)
	cy(bb + Vector3(0, 0.95, 0), 0.75, 0.4, 0.2, "cream", 16)
	cy(bb + Vector3(0, 1.04, 0), 0.62, 0.62, 0.02, "water", 16)
	solid(bb + Vector3(0, 0.5, 0), Vector3(1.2, 1.0, 1.2))
	for i in 4:
		var a := i * TAU / 4 + 0.4
		_pigeon(bb + Vector3(sin(a) * 0.7, 1.08, cos(a) * 0.7), a + PI / 2)
	for p in [Vector3(c.x + 1.5, y, r.end.y - 1.5), Vector3(c.x - 2.5, y, r.position.y + 2.5)]: _pigeon(p + Vector3(0, 0.0, 0), randf() * TAU)
	L.prop("bench", Vector3(c.x + 0.5, y, r.end.y - 0.9), PI, 1.0, true)
	var tel := frame(Vector3(r.end.x - 1.0, y, r.end.y - 1.0), PI * 0.75)
	cy(Vector3(0, 0.6, 0), 0.08, 0.16, 1.2, "dark", 8, tel)
	cy(Vector3(0, 1.3, 0.2), 0.12, 0.16, 1.0, "brass", 12, tel).rotation.x = 1.2
	L.prop("lamp_post", Vector3(r.position.x + 0.6, y, c.y + 0.5), 0.0, 1.0, true)
	var sg := frame(Vector3(c.x + 2.0, y, r.position.y + 0.6), PI)
	for x in [-0.8, 0.8]: bx(Vector3(x, 0.7, 0), Vector3(0.1, 1.4, 0.1), "wood", false, sg)
	bx(Vector3(0, 1.3, 0), Vector3(2.0, 0.75, 0.08), "3c9a5c", false, sg)
	text("PIGEON PARK", Vector3(0, 1.45, 0.05), 0.0, Color(1, 0.97, 0.85), 0.005, sg)
	text("NO BOTS ALLOWED. THIS MEANS YOU, GRRK.", Vector3(0, 1.15, 0.05), 0.0, Color(1, 0.97, 0.85), 0.0026, sg)
	# under the park: hanging roots and a lantern; and the stepping pad back to the junkyard bridge
	L.sky_pad(-9.0, 55.5, 3, 3, 0.0)
	light(Vector3(c.x, y + 3.2, c.y), Color(1, 0.8, 0.5), 1.4, 7.0)
	L.hint_sign("PIGEON PARK THIS WAY. GLIDE!", Vector3(-12.6, H, 45.2), PI)

static func _pigeon(p: Vector3, yaw: float) -> void:
	var f := frame(p, yaw)
	sphere(Vector3(0, 0.13, 0), 0.12, "9aa3ad", f).scale = Vector3(0.8, 0.8, 1.2)
	sphere(Vector3(0, 0.26, 0.11), 0.07, "6f7a86", f)
	bx(Vector3(0, 0.25, 0.19), Vector3(0.03, 0.03, 0.06), "e8a83a", false, f)
	bx(Vector3(0, 0.15, -0.16), Vector3(0.1, 0.03, 0.12), "6f7a86", false, f)

# ---------------------------------------------------------------- hanging banners
static func banner(pos: Vector3, yaw: float, c: String, h := 2.6) -> void:
	var f := frame(pos, yaw)
	bx(Vector3(0, 0, 0.08), Vector3(1.2, 0.08, 0.08), "brass", false, f)
	bx(Vector3(0, -h / 2, 0.1), Vector3(1.0, h, 0.03), "cloth_" + c, false, f)
	bx(Vector3(0, -h + 0.05, 0.11), Vector3(1.0, 0.14, 0.03), "cloth_f2c94c", false, f)
	var e := cy(Vector3(0, -h * 0.4, 0.13), 0.3, 0.3, 0.02, "gold", 10, f); e.rotation.x = PI / 2
	var e2 := cy(Vector3(0, -h * 0.4, 0.14), 0.14, 0.14, 0.02, "cloth_" + c, 10, f); e2.rotation.x = PI / 2

static func _banners() -> void:
	# clock tower west face, flanking the window, and the arch pillars (both faces)
	for z in [21.0, 24.0]: banner(Vector3(TOWER.x - 2.22, 10.2, z), -PI / 2, "c0392b", 3.0)
	for x in [-9.25, 9.25]:
		banner(Vector3(x, 4.0, 46.22), 0.0, "1f6f8b", 2.4)
		banner(Vector3(x, 4.0, 44.78), PI, "1f6f8b", 2.4)
	# shop gable banners
	banner(Vector3(-18.95, 4.4, 30.0), PI / 2, "2a8c8a", 1.6)
	banner(Vector3(-18.95, 4.4, 36.0), PI / 2, "e0533a", 1.6)

# ---------------------------------------------------------------- airship and birds
static func _sky_life() -> void:
	var ship := model("res://models/docks/airship.glb", Vector3.ZERO, 0.0, 3.2)
	if ship: DocksDressing.drift(ship, Vector3(-24, 24, 54), Vector3(24, 27, 10), 38.0)
	life.make_birds(TOWER + Vector3(0, 20, 0), 7)
	life.add_loop("plaza_crowd", Vector3(0, 3, 30), -9.0, 18.0, 60.0)

# ---------------------------------------------------------------- draw-call diet
## Bake every static primitive made above into one mesh per material (hundreds of boxes become a few dozen
## draw calls). The original nodes stay (their colliders are children) but stop drawing.
static func _merge_static() -> void:
	var groups := {}   # Material -> [SurfaceTool, casts_shadow]
	var root_inv := L.global_transform.affine_inverse()
	for mi: MeshInstance3D in _made:
		if not is_instance_valid(mi) or mi.mesh == null or not mi.visible: continue
		var animated := false
		var p: Node = mi
		while p and p != L:
			if p.has_meta("plaza_anim"): animated = true; break
			p = p.get_parent()
		if animated: continue
		var m: Material = mi.material_override
		if m == null: continue
		if not groups.has(m):
			var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
			groups[m] = [st, false]
		groups[m][0].append_from(mi.mesh, 0, root_inv * mi.global_transform)
		if mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF: groups[m][1] = true
		mi.mesh = null
	for m in groups:
		var out := MeshInstance3D.new(); out.name = "PlazaMerged"
		out.mesh = groups[m][0].commit(); out.material_override = m
		out.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if groups[m][1] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		L.add_child(out)
	_made = []
