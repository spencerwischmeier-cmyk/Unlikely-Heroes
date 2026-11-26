extends RefCounted
## Roof Gardens (zone "gardens"): a lush sky garden west of the Signal Mast, as far from the metal docks as
## it gets. Pieces (floor heights in brackets):
##   Roof Gardens (8.8)       lawns, raised flower beds, hedges, a water channel spilling off the west edge
##   Promenade (8.8)          flower boxes, vine arches and lanterns north to the hook chain
##   Conservatory Isle (8.8)  west of the promenade over a plank bridge: a glass dome with a koi pond,
##                            greenhouse sheds, a waterfall off the south edge
##   Sky Tree (10.8 .. 19.6)  the upper canopy route: branch pads spiral up a giant tree west of the
##                            conservatory to the Canopy Crown (Lucky Washer), then a vine zipline back down
##                            to the Roof Gardens
##   Hive Grove (10.0)        north of the conservatory over lily-pad hops: pollinator hives and drones,
##                            a flower meadow, climbable hives with a Lucky Washer on top
## Geometry stays in x -120..-16, z -90..6, y >= 6 (not over the terrace's tier 4 block below y 8).

const Kit := preload("res://scripts/level/gardens/garden_kit.gd")
const Life := preload("res://scripts/level/gardens/garden_life.gd")
const M := preload("res://scripts/mats.gd")

const Y := 8.8
const CONS := Rect2(-50, -50, 19, 14)          # Conservatory Isle
const DOME := Vector3(-41.5, 8.8, -43)
const DOME_R := 4.6
const GROVE := Rect2(-50, -70, 17, 14)         # Hive Grove
const GROVE_Y := 10.0
const TREE := Vector2(-60.8, -43)              # Sky Tree trunk axis
const PAD_R := 5.2
const PAD_ANG := [0.0, -70.0, -140.0, -210.0]  # degrees around the trunk (0 = +x, negative = north)
const PAD_TOP := [10.6, 12.6, 14.6, 16.6]
const CROWN_Y := 18.8
const CROWN_R := 3.0
const LILY := [Vector3(-41, 9.0, -53.8)]
const HIVES := [[Vector3(-37.0, 10.0, -60.5), 2.0], [Vector3(-38.5, 10.0, -66.3), 4.0]]   # climbable hives: base, height
const WLEDGE := Vector3(-42.6, 6.6, 2.0)   # secret ledge beside the gardens waterfall
const ZIP := [Vector3(-58.4, 19.25, -41.6), Vector3(-54.6, 18.6, -38.4), Vector3(-48.5, 17.2, -33.0), Vector3(-42, 15.2, -25.5),
	Vector3(-36.5, 12.4, -18.5), Vector3(-33.0, 10.2, -12.6), Vector3(-31.0, 9.4, -8.5)]

static func pad_pos(i: int) -> Vector3:
	var a := deg_to_rad(PAD_ANG[i])
	return Vector3(TREE.x + PAD_R * cos(a), PAD_TOP[i], TREE.y + PAD_R * sin(a))

static func build(L: Node3D) -> void:
	var K = Kit.new(L)
	var life: Node3D = Life.new(); life.name = "GardenLife"; L.add_child(life)
	life.amb_center = Vector3(-40, 10, -32); life.amb_radius = 32.0
	_gardens(L, K, life)
	_promenade(L, K, life)
	_conservatory(L, K, life)
	_sky_tree(L, K, life)
	_hive_grove(L, K, life)
	_vista(L, K, life)
	K.petals(Vector3(-30, Y + 4.0, -5), Vector3(10, 1.5, 9), 30)
	K.petals(Vector3(-23, Y + 4.0, -27), Vector3(3, 1.5, 12), 20, Color(1.0, 0.85, 0.4))
	K.petals(Vector3(-40.5, Y + 4.0, -43), Vector3(9, 1.5, 7), 24)
	K.petals(Vector3(TREE.x, CROWN_Y + 4.0, TREE.y), Vector3(6, 2, 6), 30, Color(0.7, 0.95, 0.5))
	K.petals(Vector3(-41.5, GROVE_Y + 3.0, -63), Vector3(8, 1.5, 7), 24, Color(1.0, 0.8, 0.3))
	# garden bots' tools and pots near the sheds and hives
	K.garden_tools(Vector3(-34.6, Y, 2.4), 0.0)
	K.garden_tools(Vector3(-36.4, Y, -47.6), 0.4)
	K.garden_tools(Vector3(-44.5, GROVE_Y, -68.6), PI * 0.1)
	for p in [Vector3(-28.8, Y, 3.5), Vector3(-29.2, Y, -1.6), Vector3(-32.4, Y, -49.4), Vector3(-49.2, Y, -36.6),
			Vector3(-46.5, Y, -40.5), Vector3(-35.2, GROVE_Y, -69.0), Vector3(-49.0, GROVE_Y, -56.8), Vector3(TREE.x - 1.2, CROWN_Y, TREE.y - 1.8)]:
		K.pots(p, 3, 0.45)
	# Vesk and Dodger have opinions (once each)
	life.add_quip(DOME, 2.6, ["gardens_dome_1", "gardens_dome_2"])
	life.add_quip(Vector3(-48.5, Y, -43), 2.5, ["gardens_tree_1"])
	life.add_quip(Vector3(TREE.x, CROWN_Y, TREE.y), 3.2, ["gardens_crown_1"])
	life.add_quip(ZIP[2], 3.5, ["gardens_zip_1"], true)
	life.add_quip(Vector3(-41, GROVE_Y, -58.5), 3.0, ["gardens_hive_1"])
	life.add_quip(Vector3(-41, Y, -37.3), 2.0, ["gardens_bot_1"])
	K.flush()
	_debug_spots(L)

# ------------------------------------------------------------------ Roof Gardens (x -40..-20, z -14..4)
static func _gardens(L: Node3D, K, life) -> void:
	# lawns soften the deck; the raised beds replace the old white planters (same footprints, still solid)
	K.lawn(-30.5, -4.0, 9.0, 8.0, Y)
	K.lawn(-23.0, -9.5, 4.5, 6.0, Y)
	var beds := [[-36, 0, 4, 2.4], [-26, -10, 4, 2.4], [-37, -8, 2.4, 4], [-27, 1, 2.4, 3]]
	for b in beds:
		K.flower_bed(b[0], b[1], b[2], b[3], Y, 0.8, true, 5.0)
	K.tree(Vector3(-37, Y + 0.74, -8), 4.2, 1.5, Color(0.36, 0.72, 0.36), false)
	K.tree(Vector3(-26, Y + 0.74, -10), 3.6, 1.3, Color(0.45, 0.74, 0.3), false)
	# water channel down the west edge, pouring off the side as a waterfall (seen from the terrace tiers)
	K.channel(Vector2(-39.25, -10.2), Vector2(-39.25, 1.2), Y, 0.8, 0.32)
	K.channel(Vector2(-39.9, 0.8), Vector2(-39.0, 0.8), Y, 0.8, 0.32)
	K.waterfall(Vector3(-40.1, Y + 0.24, 0.8), Vector2(-1, 0), 1.4, 30.0)
	life.loop_at("gardens_waterfall", Vector3(-40, Y + 0.5, 0.8), -6.0, 5.0, 35.0)
	# secret: a mossy ledge just off the west edge beside the waterfall (drop down, double jump back up)
	var wl: Node3D = K.solid(Vector3(WLEDGE.x, WLEDGE.y - 0.35, WLEDGE.z), Vector3(3.0, 0.7, 3.2), K.stone_mat)
	K.cylm(Vector3(WLEDGE.x, WLEDGE.y - 1.6, WLEDGE.z), 1.3, 0.2, 2.0, M.std(Color(0.5, 0.42, 0.36), 0.0, 0.95), 7)
	K.lawn(WLEDGE.x, WLEDGE.z, 2.8, 3.0, WLEDGE.y)
	K.bush(Vector3(WLEDGE.x - 1.1, WLEDGE.y + 0.3, WLEDGE.z + 1.1), 0.5, Color(0.3, 0.62, 0.32))
	for k in 3: K.vines(Vector3(WLEDGE.x - 1.2 + k * 1.2, WLEDGE.y - 0.7, WLEDGE.z + 1.62), randf_range(1.0, 2.0))
	L.prop("gull_nest", Vector3(WLEDGE.x - 0.8, WLEDGE.y, WLEDGE.z - 1.0), 0.3, 1.0, false)
	L.crate_spots.append(Vector3(WLEDGE.x + 0.5, WLEDGE.y, WLEDGE.z - 0.9))
	life.sprocket_line(Vector3(-39.3, Y + 0.6, 2.2), Vector3(WLEDGE.x, WLEDGE.y + 1.0, WLEDGE.z + 0.5), 3)
	# hedges: south-west corner and the north edge between the pillar landing and the promenade
	K.hedge(Vector2(-38.6, 3.55), Vector2(-33.2, 3.55), Y, 1.0, 0.8)
	K.hedge(Vector2(-31.0, -13.55), Vector2(-27.0, -13.55), Y, 1.0, 0.8)
	for p in [Vector2(-38.6, -1.5), Vector2(-33.6, 3.0)]:
		K.bush(Vector3(p.x, Y + 0.5, p.y), 0.7, Color(0.3, 0.62, 0.32))
	# greenhouse shed in the south gap, door to the north
	K.model("greenhouse", Vector3(-31.0, Y, 2.3), PI, 3.0, true, 0.9)
	K.flower_patch(-33.0, 3.4, -29.0, 3.9, Y, 4.0)
	# lanterns on curled brass arms (replacing the old lamp posts)
	K.garden_lamp(Vector3(-20.6, Y, -6.5), PI)
	K.garden_lamp(Vector3(-39.5, Y, 3.5), -PI / 4)
	# entrance arch over the pillar landing: two posts and a hanging sign
	_entrance_arch(L, K)
	# a garden bot trimming the beds, a bench, potted trees
	life.add_bot(K.model("garden_bot", Vector3(-32, Y, -10.8), 0.0, 1.1), Vector3(-33.5, Y, -11.2), Vector3(-29, Y, -11.2))
	L.prop("bench", Vector3(-23.2, Y, -13.2), 0.0)
	K.model("garden_tree", Vector3(-21.0, Y, -13.0), 0.0, 2.6, true, 0.4, 0.0, Color(0.85, 1.0, 0.8))
	K.model("garden_tree", Vector3(-39.0, Y, -3.4), 0.0, 2.2, true, 0.4)
	# vines hanging over the edges
	for z in [-9.0, -5.5, -2.0, 2.5]: K.vines(Vector3(-40.15, Y - 0.1, z), randf_range(1.8, 3.2))
	for x in [-37.0, -33.5, -29.0]: K.vines(Vector3(x, Y - 0.1, 4.15), randf_range(1.8, 3.0))
	for i in 5: life.add_butterfly(Vector3(randf_range(-38, -22), Y + 0.6, randf_range(-12, 2)), randf_range(1.5, 3.0))

static func _entrance_arch(L: Node3D, K) -> void:
	var y0 := Y
	for x in [-39.6, -30.6]:
		K.cylm(Vector3(x, y0 + 2.6, -13.75), 0.14, 0.18, 5.2, K.frame_mat, 8)
		K.cylm(Vector3(x, y0 + 5.3, -13.75), 0.22, 0.22, 0.2, K.brass_mat, 8)
		K.bush(Vector3(x, y0 + 0.4, -13.75), 0.55, Color(0.3, 0.62, 0.32))
		K.vines(Vector3(x, y0 + 5.0, -13.6), 4.6)
	var beam := BoxMesh.new(); beam.size = Vector3(9.4, 0.22, 0.22)
	K.mesh(beam, K.brass_mat, Vector3(-35.1, y0 + 5.2, -13.75))
	var board := BoxMesh.new(); board.size = Vector3(4.6, 0.9, 0.12)
	K.mesh(board, K.frame_mat, Vector3(-35.1, y0 + 4.5, -13.75))
	for sx in [-1, 1]: K.cylm(Vector3(-35.1 + sx * 2.0, y0 + 4.95, -13.75), 0.02, 0.02, 0.5, K.brass_mat, 4)
	for zs in [-1, 1]:
		var l := Label3D.new(); l.text = "ROOF GARDENS"; l.font_size = 64; l.pixel_size = 0.0075; l.outline_size = 12
		l.modulate = Color(1.0, 0.9, 0.55); l.outline_modulate = Color(0.1, 0.18, 0.12)
		l.position = Vector3(-35.1, y0 + 4.5, -13.75 + zs * 0.07); l.rotation.y = 0.0 if zs > 0 else PI
		K.root.add_child(l)
	for i in 9:
		K.flower(Vector3(-35.1 + (i - 4) * 1.0, y0 + 5.32, -13.75), Kit.FLOWER_COLS[i % Kit.FLOWER_COLS.size()], 0.2)

# ------------------------------------------------------------------ Promenade (x -26..-20, z -40..-14)
static func _promenade(L: Node3D, K, life) -> void:
	# flower boxes down both sides (solid, so it reads as a garden path and keeps you on it)
	K.flower_bed(-25.55, -24.5, 0.8, 20.0, Y, 0.55, true, 7.0)
	K.flower_bed(-20.45, -25.5, 0.8, 22.0, Y, 0.55, true, 7.0)
	# vine arches over the path, lanterns between
	for z in [-18.0, -25.5, -33.0]:
		K.model("vine_arch", Vector3(-23.0, Y + 0.4, z), 0.0, 0.0, false, 0.85, 5.6)
	K.garden_lamp(Vector3(-25.55, Y + 0.55, -21.7), 0.0, Color(1.0, 0.8, 0.5), false)
	K.garden_lamp(Vector3(-20.45, Y + 0.55, -29.3), PI, Color(1.0, 0.8, 0.5), true)
	# the far end: a hook-arm lamp pair framing the swing (like gate posts to the mast)
	K.garden_lamp(Vector3(-25.6, Y, -39.6), 0.0)
	for z in [-16.0, -22.0, -28.0, -34.0]:
		K.vines(Vector3(-26.1, Y - 0.1, z), randf_range(1.5, 3.0))
		K.vines(Vector3(-19.9, Y - 0.1, z + 3.0), randf_range(1.5, 3.0))
	for i in 4: life.add_butterfly(Vector3(-23, Y + 0.8, randf_range(-36, -16)), randf_range(1.0, 2.0))
	# sprockets down the path, leading on to the bridge
	life.sprocket_line(Vector3(-23, Y + 1.0, -20), Vector3(-23, Y + 1.0, -32), 4)

# ------------------------------------------------------------------ Conservatory Isle (x -50..-31, z -50..-36)
static func _conservatory(L: Node3D, K, life) -> void:
	L.island("conservatory", CONS, Y, Color(0.9, 0.96, 0.9))
	L.checkpoints.append({ pos = Vector3(-33.5, Y + 0.1, -43), r = 2.4 })
	# plank bridge from the promenade
	K.solid(Vector3(-28.5, Y - 0.3, -37.5), Vector3(5.4, 0.6, 3.0), K.plank_mat)
	for x in [-30.8, -26.2]:
		for z in [-38.95, -36.05]: K.cylm(Vector3(x, Y + 0.6, z), 0.09, 0.11, 1.2, K.brass_mat, 8)
	L.railing(-31, -39, -26, -39, Y); L.railing(-31, -36, -26, -36, Y)
	for z in [-39.0, -36.0]:
		for i in 6: K.bush(Vector3(-30.6 + i * 0.85, Y + 0.95, z), 0.22, Color(0.32, 0.64, 0.3), 2)
		K.vines(Vector3(-28.5, Y - 0.6, z), 2.0)
	life.sprocket_line(Vector3(-25.0, Y + 1.0, -37.5), Vector3(-31.5, Y + 1.0, -37.5), 3)
	# lawn over most of the isle with stone paths: bridge -> dome, round the dome to the lily pads and the tree
	K.lawn(-40.5, -43.0, 18.2, 13.2, Y)
	K.stone_path([Vector2(-31.2, -37.5), Vector2(-33.5, -39.5), Vector2(-35.0, -43.0), Vector2(-36.8, -43.0)], Y)
	K.stone_path([Vector2(-46.2, -43.0), Vector2(-49.6, -43.0)], Y)
	K.stone_path([Vector2(-35.0, -43.0), Vector2(-35.4, -46.8), Vector2(-38.0, -48.8), Vector2(-41.0, -49.4)], Y)
	K.stone_path([Vector2(-41.0, -49.4), Vector2(-44.5, -48.6), Vector2(-47.8, -46.0), Vector2(-49.0, -43.0)], Y)
	# the glass dome: doors east (to the bridge) and west (to the Sky Tree)
	K.glass_dome(DOME, DOME_R, [PI / 2, -PI / 2])
	K.light(DOME + Vector3(0, 3.5, 0), Color(1.0, 0.85, 0.6), 2.0, 8.0)
	# koi pond in the middle: stone rim (solid, low) and a little fountain
	var pc := DOME
	var rim: Node3D = K.cylm(pc + Vector3(0, 0.17, 0), 2.0, 2.05, 0.34, K.stone_mat, 24)
	K.cyl_collider(rim, 2.05, 0.34)
	K.water(pc.x, pc.z, 3.5, 3.5, Y + 0.3).mesh = _disc(1.8)
	K.cylm(pc + Vector3(0, 0.6, 0), 0.25, 0.4, 0.6, K.stone_mat, 10)
	K.cylm(pc + Vector3(0, 1.0, 0), 0.6, 0.1, 0.18, K.stone_mat, 14)
	var spout: Node3D = K.cylm(pc + Vector3(0, 1.25, 0), 0.06, 0.12, 0.4, K.fall_mat, 8)
	spout.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for i in 6: life.add_koi(pc + Vector3(0, Y + 0.26 - pc.y, 0), randf_range(0.9, 1.5))
	for i in 5:
		var a := randf() * TAU
		var lp := MeshInstance3D.new(); var cm := CylinderMesh.new(); cm.top_radius = 0.28; cm.bottom_radius = 0.28; cm.height = 0.02
		lp.mesh = cm; lp.material_override = M.leaf(Color(0.3, 0.65, 0.3)); lp.position = pc + Vector3(cos(a) * 1.2, 0.32, sin(a) * 1.2)
		K.root.add_child(lp)
		if i % 2 == 0: K.flower(lp.position + Vector3(0, 0.06, 0), Color(1.0, 0.6, 0.85), 0.16)
	# planting round the inside of the dome (leaving the east-west walk clear)
	for k in 14:
		var a := k * TAU / 14 + 0.2
		if absf(wrapf(a - PI / 2, -PI, PI)) < 0.5 or absf(wrapf(a + PI / 2, -PI, PI)) < 0.5: continue
		var p := pc + Vector3(sin(a) * 3.6, 0, cos(a) * 3.6)
		if k % 3 == 0: K.tree(p, 3.2, 1.0, Color(0.3, 0.68, 0.36), true)
		else:
			K.bush(p + Vector3(0, 0.45, 0), 0.6, Color(0.28, 0.6, 0.34))
			K.flower_patch(p.x - 0.5, p.z - 0.5, p.x + 0.5, p.z + 0.5, Y, 8.0)
	# outside: greenhouse sheds, beds, hedges, lamps
	K.model("greenhouse", Vector3(-34.0, Y, -48.0), PI / 2 + PI, 3.0, true, 0.9)
	K.model("greenhouse", Vector3(-48.0, Y, -37.8), PI / 2, 2.8, true, 0.9)
	K.flower_bed(-40.5, -36.75, 7.0, 1.1, Y, 0.45, true, 7.0)
	K.flower_bed(-34.0, -44.5, 1.2, 4.0, Y, 0.45, true, 7.0)
	K.flower_bed(-47.5, -49.2, 3.6, 1.1, Y, 0.45, true, 7.0)
	K.hedge(Vector2(-44.5, -49.55), Vector2(-43.2, -49.55), Y, 0.9, 0.7)
	K.hedge(Vector2(-38.8, -49.55), Vector2(-35.8, -49.55), Y, 0.9, 0.7)
	K.trellis(Vector2(-49.6, -40.0), Vector2(-49.6, -38.2), Y, 2.2)
	K.trellis(Vector2(-49.6, -46.2), Vector2(-49.6, -48.6), Y, 2.2)
	K.garden_lamp(Vector3(-32.0, Y, -40.2), -PI / 2)
	K.garden_lamp(Vector3(-46.0, Y, -49.4), PI / 2)
	L.prop("bench", Vector3(-37.0, Y, -48.9), 0.0)
	K.model("garden_tree", Vector3(-31.8, Y, -49.0), 0.0, 2.4, true, 0.4)
	K.model("garden_tree", Vector3(-31.8, Y, -35.4 - 0.8), 0.0, 2.0, true, 0.4)
	life.add_bot(K.model("garden_bot", Vector3(-44, Y, -36.9), PI / 2, 1.0), Vector3(-45.5, Y, -37.3), Vector3(-37.0, Y, -37.3))
	# a stream along the south edge pouring off as a second waterfall
	K.channel(Vector2(-48.6, -36.5), Vector2(-44.6, -36.5), Y, 0.7, 0.3)
	K.waterfall(Vector3(-46.6, Y + 0.2, -35.85), Vector2(0, 1), 1.6, 30.0)
	life.loop_at("gardens_waterfall", Vector3(-46.6, Y + 0.5, -35.9), -6.0, 5.0, 35.0)
	for x in [-44.0, -40.0, -36.0]: K.vines(Vector3(x, Y - 0.1, -35.85), randf_range(2.0, 3.5))
	for z in [-48.0, -44.0, -40.0]: K.vines(Vector3(-50.15, Y - 0.1, z), randf_range(2.0, 3.5))
	for i in 4: life.add_butterfly(Vector3(randf_range(-48, -33), Y + 0.6, randf_range(-49, -37)), randf_range(1.5, 2.5))
	L.crate_spots.append(Vector3(-48.6, Y, -46.8))
	L.crate_spots.append(Vector3(-32.4, Y, -46.0))

static func _disc(r: float) -> Mesh:
	var cm := CylinderMesh.new(); cm.top_radius = r; cm.bottom_radius = r; cm.height = 0.01; cm.radial_segments = 28; cm.rings = 1
	return cm

# ------------------------------------------------------------------ Sky Tree and the Canopy Crown
static func _sky_tree(L: Node3D, K, life) -> void:
	var T := Vector3(TREE.x, 0, TREE.y)
	# trunk from the clouds up to the crown, solid
	var trunk: Node3D = K.cylm(T + Vector3(0, -6.0, 0), 1.35, 2.3, 50.0, K.bark_mat, 14)
	K.cyl_collider(trunk, 1.5, 50.0)
	for i in 5:
		var a := i * TAU / 5 + 0.4
		var root_: Node3D = K.cylm(T + Vector3(cos(a) * 2.0, -12.0, sin(a) * 2.0), 0.5, 0.9, 14.0, K.bark_mat, 8)
		root_.rotation = Vector3(sin(a) * 0.25, 0, -cos(a) * 0.25)
	# vines spiralling round the trunk
	for i in 60:
		var u := float(i) / 60
		var a := u * TAU * 3.0
		var p := T + Vector3(cos(a) * 1.6, 2.0 + u * 16.5, sin(a) * 1.6)
		K.add_inst("leaf", K.blob_mesh, K.foliage_mat, K.xf_at(p, Vector3.ONE * randf_range(0.25, 0.4)), Color(0.3, 0.62, 0.3))
		if i % 6 == 0: K.flower(p + Vector3(cos(a) * 0.3, 0, sin(a) * 0.3), Color(1.0, 0.5, 0.75), 0.2)
	# branch pads spiralling up
	for i in PAD_TOP.size():
		var p := pad_pos(i)
		var pad: Node3D = K.cylm(p - Vector3(0, 0.25, 0), 1.65, 1.45, 0.5, K.bark_mat, 14)
		K.cyl_collider(pad, 1.6, 0.5)
		var top: Node3D = K.cylm(p + Vector3(0, 0.005, 0), 1.6, 1.6, 0.02, M.leaf(Color(0.4, 0.66, 0.32)), 14)
		top.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# branch from the trunk under the pad
		var from := T + Vector3(0, p.y - 1.6, 0)
		var to := p - Vector3(0, 0.55, 0)
		var d := to - from
		var br: Node3D = K.mesh(K._trunk_mesh(), K.bark_mat, (from + to) / 2)
		br.basis = Basis(Quaternion(Vector3.UP, d.normalized())).scaled_local(Vector3(0.32, d.length(), 0.32))
		# leaves fringing the pad underside, a glow-pod lantern hanging below
		for k in 6:
			var a := k * TAU / 6 + i
			K.add_inst("leaf", K.blob_mesh, K.foliage_mat, K.xf_at(p + Vector3(cos(a) * 1.55, -0.5, sin(a) * 1.55), Vector3(0.55, 0.35, 0.55)), Color(0.34, 0.66, 0.32))
		var pod := MeshInstance3D.new(); var sm := SphereMesh.new(); sm.radius = 0.22; sm.height = 0.5; pod.mesh = sm
		pod.material_override = M.glow(Color(0.6, 1.0, 0.5), 3.0); pod.position = p + Vector3(0.6, -1.3, 0.4); K.root.add_child(pod)
		life.add_bobber(pod, 0.12, 1.5)
		life.add_sprocket(p + Vector3(0, 1.0, 0))
	# the Canopy Crown: a round deck on top of the trunk with the canopy billowing above
	var crown: Node3D = K.cylm(T + Vector3(0, CROWN_Y - 0.3, 0), CROWN_R, CROWN_R * 0.85, 0.6, K.bark_mat, 20)
	K.cyl_collider(crown, CROWN_R, 0.6)
	var cdeck: Node3D = K.cylm(T + Vector3(0, CROWN_Y + 0.01, 0), CROWN_R - 0.05, CROWN_R - 0.05, 0.02, K.plank_mat, 20)
	cdeck.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for k in 10:
		var a := k * TAU / 10
		K.bush(T + Vector3(cos(a) * 2.9, CROWN_Y - 0.9, sin(a) * 2.9), 1.1, Color(0.35, 0.7, 0.34), 3, 0.7)
	for k in 7:
		var a := k * TAU / 7 + 0.3
		K.bush(T + Vector3(cos(a) * 3.4, CROWN_Y + 5.0 + randf() * 1.2, sin(a) * 3.4), 2.0, Color(0.38, 0.74, 0.34), 4, 0.75)
	K.bush(T + Vector3(0, CROWN_Y + 7.2, 0), 3.2, Color(0.42, 0.76, 0.36), 6, 0.7)
	# hanging lanterns under the canopy, a gull nest and a little lookout sign
	for k in 4:
		var a := k * TAU / 4 + 0.6
		var lp := T + Vector3(cos(a) * 2.2, CROWN_Y + 3.4, sin(a) * 2.2)
		K.cylm(lp + Vector3(0, 0.9, 0), 0.01, 0.01, 1.6, K.brass_mat, 4)
		var lm: Node3D = K.cylm(lp, 0.16, 0.16, 0.36, M.glow(Color(1.0, 0.75, 0.4), 4.0), 6)
		lm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	K.light(T + Vector3(0, CROWN_Y + 3.0, 0), Color(1.0, 0.8, 0.5), 2.0, 7.0)
	L.prop("gull_nest", T + Vector3(-1.6, CROWN_Y, 1.4), 0.6, 1.0, false)
	L.checkpoints.append({ pos = T + Vector3(0.6, CROWN_Y + 0.1, -0.6), r = 1.6 })
	L.pickup_spots.append({ kind = "washer", id = "w_gd1", pos = T + Vector3(-0.8, CROWN_Y + 0.9, -1.2) })
	L.hint_sign("VINE ZIPLINE: BACK TO THE GARDENS", T + Vector3(1.0, CROWN_Y, 1.9), PI * 0.8)
	# the vine zipline down to the Roof Gardens (its support posts would poke through tier 4: drop them)
	var before := L.get_child_count()
	L.rail(ZIP, false)
	for i in range(L.get_child_count() - 1, before - 1, -1):
		var c := L.get_child(i)
		if c is MeshInstance3D and c.mesh is CylinderMesh and (c.mesh as CylinderMesh).height >= 29.0: c.queue_free()
	# leafy garlands hanging off the zipline, sprockets to grab on the ride
	var curve: Curve3D = L.rails[L.rails.size() - 1].curve
	var length := curve.get_baked_length()
	var u := 1.5
	while u < length - 1.0:
		var p := curve.sample_baked(u)
		K.add_inst("leaf", K.blob_mesh, K.foliage_mat, K.xf_at(p + Vector3(randf_range(-0.1, 0.1), -0.22, randf_range(-0.1, 0.1)), Vector3(0.15, 0.12, 0.15)), Color(0.3, 0.62, 0.3))
		if randf() < 0.3: K.flower(p + Vector3(0, -0.2, 0), Kit.FLOWER_COLS[randi() % Kit.FLOWER_COLS.size()], 0.14)
		if int(u * 3.0) % 7 == 0: K.vines(p + Vector3(0, -0.3, 0), randf_range(0.6, 1.4))
		u += 0.45
	for k in [8.0, 14.0, 20.0, 26.0, 32.0]:
		if k < length: life.add_sprocket(curve.sample_baked(k) + Vector3(0, 0.8, 0))
	for i in 3: life.add_butterfly(T + Vector3(0, CROWN_Y + 0.5, 0), 3.5)

# ------------------------------------------------------------------ Hive Grove (x -48..-34, z -68..-56)
static func _hive_grove(L: Node3D, K, life) -> void:
	L.island("hive_grove", GROVE, GROVE_Y, Color(0.95, 0.92, 0.8))
	L.checkpoints.append({ pos = Vector3(-41, GROVE_Y + 0.1, -58), r = 2.4 })
	# lily-pad hop from the conservatory's north edge
	for p in LILY:
		var pad: Node3D = K.cylm(p - Vector3(0, 0.2, 0), 1.55, 1.2, 0.4, M.leaf(Color(0.35, 0.68, 0.32)), 18)
		K.cyl_collider(pad, 1.5, 0.4)
		var bloom := MeshInstance3D.new(); bloom.position = p + Vector3(0.7, 0.05, 0.4); K.root.add_child(bloom)
		K.flower(bloom.position, Color(1.0, 0.65, 0.85), 0.4)
		K.cylm(p - Vector3(0, 1.4, 0), 0.06, 0.08, 2.4, M.leaf(Color(0.3, 0.55, 0.28)), 6)
		life.add_sprocket(p + Vector3(0, 1.0, 0))
	life.add_sprocket(Vector3(-41, Y + 1.0, -49.0))
	# meadow carpet with paths left clear between the hives
	K.lawn(-41.5, -63, 16.0, 13.0, GROVE_Y)
	K.flower_patch(-47.4, -67.4, -43.5, -60.5, GROVE_Y, 3.5)
	K.flower_patch(-35.5, -60.0, -34.6, -56.6, GROVE_Y, 5.0)
	K.flower_patch(-44.0, -67.5, -42.5, -66.0, GROVE_Y, 5.0)
	K.flower_patch(-38.5, -67.5, -34.6, -65.0, GROVE_Y, 4.0)
	# the hives: two climbable (washer on the tall one), one squat
	var hp := []
	for h in HIVES:
		K.hive(h[0], 1.4, h[1])
		hp.append(h[0] + Vector3(0, h[1], 0))
	K.hive(Vector3(-45.5, GROVE_Y, -58.5), 0.9, 1.5, Color(0.95, 0.62, 0.3))
	K.light(Vector3(-39.5, GROVE_Y + 2.5, -64.0), Color(1.0, 0.7, 0.3), 2.0, 8.0)
	L.pickup_spots.append({ kind = "washer", id = "w_gd2", pos = hp[1] + Vector3(0, 0.9, 0) })
	L.hint_sign("POLLINATOR HIVES: DO NOT POKE", Vector3(-36.0, GROVE_Y, -57.3), PI * 0.9)
	# drones commuting from the hives to the flower beds (and some to the conservatory)
	var flowers := [Vector3(-46, GROVE_Y + 0.9, -65), Vector3(-35, GROVE_Y + 0.9, -58.5), Vector3(-43, GROVE_Y + 0.9, -66.5),
		Vector3(-36.5, GROVE_Y + 0.9, -66), Vector3(-40.5, Y + 1.0, -36.8), Vector3(-34, Y + 1.0, -44.5), Vector3(-47.5, Y + 1.0, -49.2)]
	var hive_tops := [hp[0] + Vector3(0, 0.6, 0), hp[1] + Vector3(0, 0.6, 0), Vector3(-45.5, GROVE_Y + 2.1, -58.5)]
	for i in 7:
		var route := [hive_tops[i % 3], flowers[i % flowers.size()], flowers[(i * 3 + 1) % flowers.size()]]
		life.add_drone(route, i < 2)
	life.loop_at("gardens_drone", Vector3(-40, GROVE_Y + 2.0, -64), -14.0, 3.0, 20.0)
	# trees, a garden bot, crates, a gull nest on a stump at the north-west corner
	K.tree(Vector3(-46.8, GROVE_Y, -57.2), 4.6, 1.7, Color(0.4, 0.72, 0.32), true)
	K.tree(Vector3(-34.8, GROVE_Y, -67.0), 4.0, 1.5, Color(0.5, 0.75, 0.3), true)
	K.tree(Vector3(-47.0, GROVE_Y, -67.0), 3.8, 1.4, Color(0.36, 0.7, 0.36), true)
	life.add_bot(K.model("garden_bot", Vector3(-43, GROVE_Y, -61.5), 0.0, 1.05), Vector3(-44.5, GROVE_Y, -61.5), Vector3(-42.5, GROVE_Y, -57.5))
	L.crate_spots.append(Vector3(-46.8, GROVE_Y, -63.0))
	L.crate_spots.append(Vector3(-35.0, GROVE_Y, -62.0))
	var stump: Node3D = K.cylm(Vector3(-47.0, GROVE_Y + 0.6, -60.6), 0.55, 0.7, 1.2, K.bark_mat, 10)
	K.cyl_collider(stump, 0.6, 1.2)
	L.prop("gull_nest", Vector3(-47.0, GROVE_Y + 1.2, -60.6), 1.2, 0.8, false)
	# a stream across the north edge pouring off as a waterfall
	K.channel(Vector2(-43.5, -69.45), Vector2(-39.5, -69.45), GROVE_Y, 0.7, 0.3)
	K.waterfall(Vector3(-42.0, GROVE_Y + 0.2, -70.1), Vector2(0, -1), 1.5, 32.0)
	life.loop_at("gardens_waterfall", Vector3(-42, GROVE_Y + 0.5, -70.1), -8.0, 5.0, 30.0)
	for x in [-48.0, -45.0, -37.0, -34.5]: K.vines(Vector3(x, GROVE_Y - 0.1, -70.15), randf_range(2.0, 3.5))
	for z in [-68.0, -64.0, -60.0]: K.vines(Vector3(-50.15, GROVE_Y - 0.1, z), randf_range(2.0, 3.5))
	K.garden_lamp(Vector3(-34.6, GROVE_Y, -56.6), -PI / 2, Color(1.0, 0.8, 0.5), false)
	for i in 6: life.add_butterfly(Vector3(randf_range(-46, -36), GROVE_Y + 0.5, randf_range(-67, -57)), randf_range(1.2, 2.5))

# ------------------------------------------------------------------ sky dressing: gulls and far islands
static func _vista(L: Node3D, K, life) -> void:
	life.add_bird(Vector3(-40, 24, -32), 22.0, 0.0)
	life.add_bird(Vector3(-40, 26, -32), 18.0, 2.0)
	life.add_bird(Vector3(-55, 28, -45), 9.0, 0.0)
	life.add_bird(Vector3(-41, 17, -62), 8.0, 0.0)
	life.add_bird(Vector3(-30, 16, -5), 12.0, 1.0)
	for v in [[Vector3(-92, 14, -36), 6.0], [Vector3(-82, 20, -78), 4.5], [Vector3(-108, 22, -4), 5.0], [Vector3(-66, 27, -86), 3.5], [Vector3(-104, 9, -62), 4.0]]:
		K.islet(v[0], v[1])

# ------------------------------------------------------------------ debug spots (--at=<name>)
static func _debug_spots(L: Node3D) -> void:
	var spots := {
		gd_gardens = [Vector3(-23.5, Y + 0.1, -13.0), -0.6],
		gd_promenade = [Vector3(-23, Y + 0.1, -15), PI],
		gd_cons = [Vector3(-28.5, Y + 0.1, -37.5), -PI / 2],
		gd_dome = [Vector3(-36.0, Y + 0.1, -43), -PI / 2],
		gd_tree = [Vector3(-47.5, Y + 0.1, -41.0), -PI * 0.6],
		gd_crown = [Vector3(TREE.x + 1.8, CROWN_Y + 0.1, TREE.y + 1.4), PI * 0.75],
		gd_grove = [Vector3(-41, Y + 0.1, -48.5), PI],
		gd_vista = [Vector3(-26.5, Y + 0.1, -24), -PI * 0.6],
	}
	for k in spots: L.debug_spots[k] = spots[k]
	# the level resets debug_spots after the areas build, so apply our own --at here as well
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--at=") and spots.has(a.substr(5)):
			L.start_pos = spots[a.substr(5)][0]; L.start_yaw = spots[a.substr(5)][1]

# ------------------------------------------------------------------ traversal cases
static func traversal_cases(moves: Dictionary) -> Dictionary:
	var c := {}
	# conservatory -> first branch pad, then up the spiral to the crown
	var p0 := pad_pos(0)
	c["gd_pad0"] = [Vector3(p0.x + 6.2, Y + 0.1, p0.z), -PI / 2, moves.dj, PAD_TOP[0], Rect2(p0.x - 1.4, p0.z - 1.4, 2.8, 2.8)]
	for i in range(1, PAD_TOP.size()):
		var a := pad_pos(i - 1); var b := pad_pos(i)
		var d := Vector2(b.x - a.x, b.z - a.z).normalized()
		c["gd_pad%d" % i] = [Vector3(a.x, a.y + 0.1, a.z), atan2(d.x, d.y), moves.dj, b.y, Rect2(b.x - 1.4, b.z - 1.4, 2.8, 2.8)]
	var l := pad_pos(PAD_TOP.size() - 1)
	var dc := Vector2(TREE.x - l.x, TREE.y - l.z).normalized()
	c["gd_crown"] = [Vector3(l.x + dc.x * 0.5, l.y + 0.1, l.z + dc.y * 0.5), atan2(dc.x, dc.y), moves.dj, CROWN_Y, Rect2(TREE.x - 2.8, TREE.y - 2.8, 5.6, 5.6)]
	# the vine zipline from the crown back down to the Roof Gardens
	var z0: Vector3 = ZIP[0]; var z1: Vector3 = ZIP[1]
	var dz := Vector2(z1.x - z0.x, z1.z - z0.z).normalized()
	c["rail_gd_zip"] = [Vector3(z0.x - dz.x * 1.6, CROWN_Y + 0.1, z0.z - dz.y * 1.6), atan2(dz.x, dz.y), moves.run, Y, Rect2(-40, -14, 20, 18)]
	# lily-pad hops to the Hive Grove, then up the hives
	var lp: Vector3 = LILY[0]
	c["gd_lily1"] = [Vector3(lp.x, Y + 0.1, CONS.position.y + 0.8), PI, moves.sj, lp.y, Rect2(lp.x - 1.4, lp.z - 1.4, 2.8, 2.8)]
	c["gd_lily2"] = [Vector3(lp.x, lp.y + 0.1, lp.z), PI, moves.sj, GROVE_Y, GROVE]
	var h0: Vector3 = HIVES[0][0]; var h1: Vector3 = HIVES[1][0]
	var t0: float = GROVE_Y + HIVES[0][1]; var t1: float = GROVE_Y + HIVES[1][1]
	c["gd_hive1"] = [Vector3(h0.x - 6.0, GROVE_Y + 0.1, h0.z), PI / 2, moves.dj, t0, Rect2(h0.x - 1.2, h0.z - 1.2, 2.4, 2.4)]
	var dh := Vector2(h1.x - h0.x, h1.z - h0.z).normalized()
	c["gd_hive2"] = [Vector3(h0.x, t0 + 0.1, h0.z), atan2(dh.x, dh.y), moves.dj, t1, Rect2(h1.x - 1.2, h1.z - 1.2, 2.4, 2.4)]
	c["gd_ledge_down"] = [Vector3(-38.8, Y + 0.1, WLEDGE.z), -PI / 2, moves.run, WLEDGE.y, Rect2(WLEDGE.x - 1.5, WLEDGE.z - 1.6, 3.0, 3.2)]
	c["gd_ledge_up"] = [Vector3(WLEDGE.x - 0.6, WLEDGE.y + 0.1, WLEDGE.z), PI / 2, moves.dj, Y, Rect2(-40, -14, 20, 18)]
	return c
