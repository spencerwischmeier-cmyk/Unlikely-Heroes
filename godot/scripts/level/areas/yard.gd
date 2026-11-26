extends RefCounted
## The Crane Yard: Foreman Grudd's heavy-industry beachhead (north of the plaza).
##   Causeway (x -10..-2, z -34..9)     crane-slung platform, propaganda, loudspeakers
##   Gate island yard_gate (x -18..18, z -71..-57)  receiving checkpoint; the R_YARD rail lands at (1, 1, -61.5)
##   Conveyor bridge (x -30..-18, z -66..-62)  a moving belt carries Vesk west into...
##   Container Row yard_row (x -58..-30, z -100..-62)  the gauntlet: container cover, smelter, waves
##   Catwalk (x -30..-22, z -99..-93) -> the arena's west gate (opens when the Row is cleared)
##   Holding pen yard_pen (x 28..52, z -85..-63)  optional: caged cargo bots, a release lever, a washer
##   Arena (x -22..22, z -114..-80)     boss stage: overhead crane, crowd stands, the foundry behind it
## Geometry lives in _build_crane_yard() in level_skyharbor.gd; this file dresses it and adds the life.

const K := preload("res://scripts/level/yard/yard_kit.gd")
const Life := preload("res://scripts/level/yard/yard_life.gd")
const POSTER := "res://textures/yard/poster_grudd.png"
const POSTER2 := "res://textures/yard/poster_fist.png"

static func build(L) -> void:
	if not L.islands.has("yard_row"): return
	var life: Node3D = Life.new(); life.name = "YardLife"; life.level = L
	L.add_child(life)
	_causeway(L, life)
	_gate_island(L, life)
	_conveyor(L, life)
	_row(L, life)
	_pen(L, life)
	_arena(L, life)
	_foundry(L, life)
	_vista(L, life)
	# collectibles and crates
	L.pickup_spots.append({ kind = "washer", id = "yard_w1", pos = Vector3(-56.6, 5.6, -77.5) })   # top of the Row container stack
	L.pickup_spots.append({ kind = "washer", id = "yard_w2", pos = Vector3(48.5, 0.8, -80.5) })   # inside the last holding-pen cage
	for p in [Vector3(-52, 0, -63.5), Vector3(-33, 0, -88), Vector3(-53.5, 0, -90), Vector3(-41.5, 0, -97.5),
			Vector3(30, 0, -78), Vector3(42, 0, -64.5), Vector3(15.5, 0, -58.5), Vector3(-8.6, 0, -27.5)]:
		L.crate_spots.append(p)
	# debug start spots (the level rebuilds debug_spots after the area files run, so apply --at here too)
	var spots := {
		yard_row = [Vector3(-34, 0.1, -64), -PI / 2], yard_pen = [Vector3(30, 0.1, -66), PI / 2],
		yard_arena = [Vector3(-26, 0.1, -96), PI / 2], yard_view = [Vector3(4, 0.1, -59), -PI * 0.7],
		yard_gate_view = [Vector3(0, 0.1, -58.5), PI], yard_causeway = [Vector3(-6, 0.1, 6), PI],
		yard_boss = [Vector3(-12, 0.1, -86), PI * 0.8],
	}
	for k in spots: L.debug_spots[k] = spots[k]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--at=") and spots.has(a.substr(5)):
			L.start_pos = spots[a.substr(5)][0]; L.start_yaw = spots[a.substr(5)][1]

static func traversal_cases(moves: Dictionary) -> Dictionary:
	return {
		yard_belt = [Vector3(-19.5, 0.1, -64), -PI / 2, [[0.0, "move_forward", true], [1.4, "move_forward", false]], 0.0, Rect2(-58, -100, 28, 38)],
		yard_stack1 = [Vector3(-56.6, 0.1, -62.6), PI, moves.sj, 1.2, Rect2(-57.5, -66.8, 1.8, 2.7)],
		yard_stack2 = [Vector3(-56.6, 1.3, -64.9), PI, moves.sj, 2.4, Rect2(-57.8, -72, 2.4, 5)],
		yard_stack3 = [Vector3(-56.6, 2.5, -71.4), PI, moves.dj_short, 4.8, Rect2(-57.8, -79, 2.4, 5)],
	}

# ---------------------------------------------------------------- causeway (x -14..2, z -40..12)
static func _causeway(L, life) -> void:
	# a gantry girder over the sliding platform; its trolley follows the platform with four cables
	for z in [3.0, -29.0]:
		for x in [-9.6, -2.4]:
			K.bx(L, Vector3(x, 4.6, z), Vector3(0.5, 9.2, 0.5), "yellow", true)
			K.bx(L, Vector3(x, 0.15, z), Vector3(1.0, 0.3, 1.0), "dark")
		K.bx(L, Vector3(-6, 9.4, z), Vector3(7.8, 0.6, 0.8), "yellow")
		K.stripe(L, Vector3(-6, 9.7, z), Vector2(7.8, 0.4))
	K.girder(L, Vector3(-6, 9.7, 3), Vector3(-6, 9.7, -29), 1.1, "yellow")
	for m in L.movers:
		if m.a == Vector3(-6, -0.3, -6):
			life.add_trolley(Vector3(-6, 9.7, 0), m.body, 4.5, 10.0)
		elif m.id == "yard_pallet":
			life.add_trolley(Vector3(0, 8.0, -66), m.body, 4.4, 8.3)
	K.girder(L, Vector3(16.8, 8.0, -66), Vector3(29.0, 8.0, -66), 0.9, "yellow")
	for x in [16.8, 29.0]:
		K.lattice(L, Vector3(x, 0, -69.6), 1.2, 8.0)
		K.bx(L, Vector3(x, 8.4, -67.8), Vector3(0.4, 0.4, 4.4), "yellow")
	# propaganda along the walk
	K.poster(L, Vector3(-9.4, 0, 6.0), PI / 2, "WELCOME TO THE CRANE YARD", POSTER2, Vector2(3.0, 2.0), "NOW HIRING: NOBODY")
	K.poster(L, Vector3(-2.6, 0, -31.0), -PI / 2, "BREAKS ARE FOR BRAKES", POSTER, Vector2(3.0, 2.0), "- FOREMAN GRUDD")
	life.add_speaker(K.loudspeaker(L, Vector3(-9.2, 0, -33.0), 0.4))
	for p in [Vector3(-9.2, 0, -26.8), Vector3(-2.8, 0, -33.2)]:
		K.model(L, "docks/hazard_barrier", p, randf() * 0.6, 1.1, true)
	K.model(L, "docks/crates", Vector3(-8.9, 0, -30.2), 0.3, 1.6, true)
	K.model(L, "docks/barrels", Vector3(-2.9, 0, -27.0), 1.2, 1.2, true)
	K.work_light(L, Vector3(-9.6, 0, 7.8), PI * 0.8)
	K.work_light(L, Vector3(-2.4, 0, -33.4), -PI * 0.2)
	K.stripe(L, Vector3(-6, 0, -26.3), Vector2(8, 0.5))
	K.stripe(L, Vector3(-6, 0, -0.7), Vector2(8, 0.5))

# ---------------------------------------------------------------- gate island (x -18..18, z -71..-57)
static func _gate_island(L, life) -> void:
	# big GRUDD INDUSTRIES sign frame on the north rim, looking out over the arena
	for x in [-13.0, 13.0]:
		K.lattice(L, Vector3(x, 0, -70.2), 1.4, 9.0)
		K.work_light(L, Vector3(x, 9.0, -70.2), 0.0 if x < 0 else 0.0, Color(1, 0.8, 0.55), 1.2)
	var sign_ := K.node(L, Vector3(0, 7.6, -70.2))
	K.bx(sign_, Vector3.ZERO, Vector3(25, 2.6, 0.5), "dark")
	K.bx(sign_, Vector3(0, 1.45, 0), Vector3(25.4, 0.3, 0.6), "yellow")
	K.bx(sign_, Vector3(0, -1.45, 0), Vector3(25.4, 0.3, 0.6), "hazard")
	for s in [-1, 1]:
		var lab := Label3D.new(); lab.text = "GRUDD INDUSTRIES  //  CRANE YARD 7" if s > 0 else "NO HEROES BEYOND THIS POINT"
		lab.font_size = 160; lab.pixel_size = 0.009; lab.outline_size = 18
		lab.modulate = Color(1, 0.78, 0.25) if s > 0 else Color(1, 0.35, 0.25); lab.outline_modulate = Color(0.05, 0.04, 0.03)
		lab.position = Vector3(0, 0, 0.27 * s); lab.rotation.y = 0.0 if s > 0 else PI; lab.double_sided = false
		sign_.add_child(lab)
	K.bx(sign_, Vector3(0, -1.75, 0.3), Vector3(22, 0.08, 0.1), "glow_amber")
	# the incident counter board
	var board := K.poster(L, Vector3(-6.5, 0, -69.6), 0.0, "DAYS WITHOUT A\nHERO INCIDENT:", "", Vector2(3.4, 2.2))
	var num := Label3D.new(); num.text = "0"; num.font_size = 200; num.pixel_size = 0.008; num.outline_size = 18
	num.modulate = Color(1, 0.3, 0.2); num.position = Vector3(0, 1.5, 0.03); num.double_sided = false
	board.add_child(num); life.counter = num
	K.poster(L, Vector3(6.5, 0, -69.6), 0.0, "SAFETY THIRD!", POSTER, Vector2(3.2, 2.2), "(FIRST AND SECOND ARE PRODUCTIVITY)")
	life.add_speaker(K.loudspeaker(L, Vector3(-16.4, 0, -58.6), PI * 0.25))
	life.add_speaker(K.loudspeaker(L, Vector3(16.4, 0, -58.6), -PI * 0.25))
	# guard booth by the east exit, with a raised boom barrier
	var booth := K.node(L, Vector3(15.6, 0, -69.0))
	K.bx(booth, Vector3(0, 1.3, 0), Vector3(2.4, 2.6, 2.2), "cream", true)
	K.bx(booth, Vector3(0, 2.75, 0), Vector3(2.8, 0.3, 2.6), "red")
	K.bx(booth, Vector3(-1.22, 1.6, 0), Vector3(0.05, 0.9, 1.6), "glass")
	K.bx(booth, Vector3(0, 1.6, -1.12), Vector3(1.8, 0.9, 0.05), "glass")
	K.omni(booth, Vector3(0, 2.0, 0), Color(1, 0.8, 0.5), 1.2, 5.0)
	var boom := K.node(L, Vector3(16.6, 1.0, -63.2))
	K.bx(boom, Vector3(0, -0.5, 0), Vector3(0.5, 1.0, 0.5), "yellow")
	var arm := K.bx(boom, Vector3(0, 2.4, 0), Vector3(0.18, 4.6, 0.18), "hazard")
	arm.rotation.z = 0.15
	K.bx(L, Vector3(15.6, 3.4, -67.85), Vector3(1.6, 0.6, 0.1), "dark").add_child(_text("CHECKPOINT", 0.006, Color(1, 0.8, 0.3)))
	# cargo stacks and clutter (keeps the middle clear for the rail landing and the fight)
	K.container(L, Vector3(12.2, 0, -59.6), true, Color(0.85, 0.36, 0.2))
	K.container(L, Vector3(-12.4, 0, -59.2), true, Color(0.25, 0.5, 0.62))
	K.container(L, Vector3(-12.4, 2.4, -59.2), true, Color(0.9, 0.66, 0.2))
	K.model(L, "docks/crates", Vector3(9.0, 0, -69.6), 0.4, 1.7, true)
	K.model(L, "docks/barrels", Vector3(-16.4, 0, -69.6), 0.0, 1.2, true)
	K.model(L, "docks/cable_spool", Vector3(3.4, 0, -70.0), 0.0, 1.2, true)
	K.model(L, "docks/hazard_barrier", Vector3(-16.6, 0, -67.8), PI / 2, 1.1, false)
	K.model(L, "docks/hazard_barrier", Vector3(-16.6, 0, -60.2), PI / 2, 1.1, false)
	K.model(L, "docks/forklift", Vector3(9.0, 0, -65.8), PI * 0.6, 2.1, true)
	K.model(L, "docks/dock_bot", Vector3(5.5, 0, -58.6), PI * 1.2, 1.2, true)
	K.stripe(L, Vector3(-16.4, 0, -64), Vector2(3.0, 6.0))
	K.stripe(L, Vector3(0, 0, -57.6), Vector2(6, 0.6))
	K.stripe(L, Vector3(16.4, 0, -66), Vector2(3.0, 5.0))
	K.work_light(L, Vector3(-17.2, 0, -70.4), PI * 0.8)
	K.work_light(L, Vector3(17.2, 0, -57.6), -PI * 0.2)

# ---------------------------------------------------------------- conveyor bridge (x -30..-18, z -66..-62)
static func _conveyor(L, life) -> void:
	var c := Vector3(-24, 0, -64)
	var belt := StaticBody3D.new(); belt.position = c + Vector3(0, -0.25, 0)
	var cs := CollisionShape3D.new(); var sh := BoxShape3D.new(); sh.size = Vector3(12.6, 0.5, 4.0); cs.shape = sh
	belt.add_child(cs); belt.constant_linear_velocity = Vector3(-1.8, 0, 0)
	L.add_child(belt)
	var bm := MeshInstance3D.new(); var top := BoxMesh.new(); top.size = Vector3(12.6, 0.5, 4.0); bm.mesh = top
	bm.material_override = life.belt_material(); belt.add_child(bm)
	# frame, rollers, side guards and legs down into the clouds
	for s in [-1, 1]:
		K.bx(L, c + Vector3(0, -0.2, s * 2.2), Vector3(12.8, 0.7, 0.4), "yellow")
		K.bx(L, c + Vector3(0, 0.18, s * 2.2), Vector3(12.8, 0.06, 0.42), "hazard")
	for i in 7:
		K.cy(L, c + Vector3(-6 + i * 2.0, -0.62, 0), 0.22, 4.2, "chrome", Vector3(PI / 2, 0, 0))
	for x in [-28.0, -20.0]:
		K.bx(L, Vector3(x, -9, -64), Vector3(0.5, 17, 0.5), "steel")
	L.railing(-30, -66.3, -18, -66.3); L.railing(-30, -61.7, -18, -61.7)
	# the overhead chain conveyor: crates on hooks travelling from the yard into the Row
	K.girder(L, Vector3(-16, 6.4, -67.2), Vector3(-34, 6.4, -67.2), 0.7, "steel")
	for x in [-17.0, -33.0]:
		K.bx(L, Vector3(x, 3.2, -67.4), Vector3(0.35, 6.4, 0.35), "yellow", true)
	life.add_chain(Vector3(-16, 6.2, -67.2), Vector3(-34, 6.2, -67.2), 5)
	life.add_loop("yard_conveyor", c + Vector3(0, 0.5, 0), -4.0)
	var arrow := _text("<<<  CONTAINER ROW  <<<", 0.012, Color(1, 0.85, 0.3))
	arrow.rotation = Vector3(-PI / 2, 0, 0); arrow.position = c + Vector3(0, 0.03, 0); L.add_child(arrow)

# ---------------------------------------------------------------- Container Row (x -58..-30, z -100..-62)
static func _row(L, life) -> void:
	var rust := Color(0.72, 0.32, 0.2); var teal := Color(0.22, 0.52, 0.55); var mustard := Color(0.9, 0.65, 0.18)
	var navy := Color(0.24, 0.32, 0.5); var cream := Color(0.85, 0.82, 0.72)
	# climbable stack in the south-west corner: crate -> container -> double stack (washer on top)
	L.block(-56.6, -65.45, 1.8, 2.7, 1.2, 0.0, L.mat_rust)
	K.container(L, Vector3(-56.6, 0, -69.5), false, teal)
	K.container(L, Vector3(-56.6, 0, -76.5), false, rust)
	K.container(L, Vector3(-56.6, 2.4, -76.5), false, mustard)
	# west wall of stacked containers (backdrop)
	for z in [-83.5, -89.0]:
		K.container(L, Vector3(-56.6, 0, z), false, navy if z < -85 else cream)
		K.container(L, Vector3(-56.6, 2.4, z), false, rust if z < -85 else teal)
	K.container(L, Vector3(-56.6, 4.8, -86.2), false, mustard)
	# cover through the middle (the ring 8 m round the centre stays open for the waves)
	K.container(L, Vector3(-36.5, 0, -71.0), true, rust)
	K.container(L, Vector3(-50.0, 0, -86.0), false, teal)
	K.container(L, Vector3(-38.0, 0, -91.6), true, cream)
	K.container(L, Vector3(-38.0, 2.4, -91.6), true, navy)
	L.block(-44, -81, 2.2, 2.2, 1.2, 0.0, L.mat_rust)
	K.model(L, "docks/crates", Vector3(-44, 1.2, -81), 0.6, 1.3, false)
	for p in [[Vector3(-41.5, 0, -75.5), 0.2], [Vector3(-47.5, 0, -76.0), -0.3], [Vector3(-36.5, 0, -84.5), PI / 2], [Vector3(-48.0, 0, -92.5), 0.1]]:
		K.model(L, "docks/hazard_barrier", p[0], p[1], 1.1, true)
	K.model(L, "docks/barrels", Vector3(-31.6, 0, -76.0), 0.5, 1.2, true)
	K.model(L, "docks/barrels", Vector3(-52.4, 0, -65.0), 2.0, 1.2, true)
	K.model(L, "docks/cable_spool", Vector3(-31.8, 0, -88.0), 0.0, 1.3, true)
	K.model(L, "docks/crates", Vector3(-31.8, 0, -68.6), 1.0, 1.6, true)
	# welding robots working on a container
	for p in [[Vector3(-33.2, 0, -73.4), -0.42], [Vector3(-40.0, 0, -73.4), 0.42]]:
		var arm := K.model(L, "robot_arm", p[0], p[1], 2.6, true, 0.5)
		if arm: life.add_welder(arm, p[0] + Vector3(0, 2.0, 0) + Vector3(sin(p[1]), 0, cos(p[1])) * 0.9)
	# smelter corner (north-west): furnace, a glowing trough to a casting mould, sparks and smoke
	var sm := K.model(L, "smelter", Vector3(-53.0, 0, -96.5), PI * 0.5, 4.2, true, 0.7)
	if sm:
		K.omni(L, Vector3(-50.5, 1.4, -96.5), Color(1, 0.5, 0.15), 3.0, 10.0)
		life.add_sparks(K.sparks(L, Vector3(-51.0, 1.2, -96.5), Color(1, 0.6, 0.2), 20, 3.0), 0.0)
		K.smoke(L, Vector3(-55.5, 6.5, -97.5), 0.9, true)
	K.bx(L, Vector3(-45.0, 0.05, -98.6), Vector3(10, 0.12, 0.8), "glow_molten")
	K.bx(L, Vector3(-45.0, 0.1, -98.15), Vector3(10, 0.2, 0.12), "dark")
	K.bx(L, Vector3(-45.0, 0.1, -99.05), Vector3(10, 0.2, 0.12), "dark")
	K.bx(L, Vector3(-39.2, 0.4, -98.6), Vector3(1.6, 0.8, 1.6), "dark", true)
	K.bx(L, Vector3(-39.2, 0.81, -98.6), Vector3(1.3, 0.04, 1.3), "glow_molten")
	K.omni(L, Vector3(-44, 1.2, -97.6), Color(1, 0.45, 0.12), 2.2, 9.0)
	life.add_loop("yard_smelter", Vector3(-51, 1.5, -96), -6.0)
	# overhead gantry crane spanning the Row, carrying a container back and forth
	for x in [-58.3, -30.6]:
		for z in [-68.5 if x > -40 else -62.6, -99.4]:
			K.bx(L, Vector3(x, 5.5, z), Vector3(0.6, 11, 0.6), "yellow", true)
		K.girder(L, Vector3(x, 10.4, -62.5), Vector3(x, 10.4, -99.5), 1.0, "yellow")
	var bridge := K.node(L, Vector3(-44, 11.4, -80))
	K.girder(bridge, Vector3(-15.5, 0, 0), Vector3(15.5, 0, 0), 1.0, "yellow")
	K.bx(bridge, Vector3(0, 0.5, 0), Vector3(2.2, 1.6, 2.0), "dark")
	K.bx(bridge, Vector3(0, 1.4, 0), Vector3(2.4, 0.2, 2.2), "hazard")
	for s in [-1, 1]: K.cy(bridge, Vector3(s * 0.6, -3.2, 0), 0.04, 6.4, "cable")
	var load_ := K.node(bridge, Vector3(0, -7.6, 0))
	K.bx(load_, Vector3(0, 0, 0), Vector3(5.0, 2.2, 2.4), "red")
	K.bx(load_, Vector3(0, 1.2, 0), Vector3(1.6, 0.25, 0.4), "dark")
	life.add_slider(bridge, Vector3(-44, 11.4, -70), Vector3(-44, 11.4, -92), 26.0)
	# Grudd's words of encouragement
	K.poster(L, Vector3(-57.6, 0, -94.0), PI / 2, "A HAPPY BOT IS A BUSY BOT", POSTER, Vector2(3.4, 2.3), "A BUSY BOT ASKS NO QUESTIONS")
	K.poster(L, Vector3(-30.6, 0, -82.0), -PI / 2, "TODAY'S QUOTA: EVERYTHING", POSTER2, Vector2(3.2, 2.2), "TOMORROW'S QUOTA: MORE")
	K.poster(L, Vector3(-46.0, 0, -62.6), PI, "IF YOU CAN READ THIS\nYOU ARE NOT WORKING", "", Vector2(3.2, 2.0))
	life.add_speaker(K.loudspeaker(L, Vector3(-31.0, 0, -95.0), -PI * 0.25))
	for z in [-72.0, -91.0]:
		life.add_sway(K.banner(L, Vector3(-57.7, 10.3, z), PI / 2, Vector2(1.8, 4.4)))
	for p in [Vector3(-54.2, 0, -80.6), Vector3(-31.6, 0, -73.0)]:
		L.prop("vent_stack", p, 0.0, 1.0, true)
		DocksDressing.steam(L, p + Vector3(0, 3.1, 0))
	life.add_speaker(K.loudspeaker(L, Vector3(-57.4, 0, -63.0), PI * 0.75))
	K.work_light(L, Vector3(-30.8, 0, -62.8), -PI * 0.75)
	K.work_light(L, Vector3(-57.2, 0, -99.2), PI * 0.25)
	K.work_light(L, Vector3(-44.0, 0, -99.4), 0.0, Color(1, 0.7, 0.45))
	for z in [-66.0, -96.0]: K.stripe(L, Vector3(-31.2, 0, z), Vector2(2.4, 6.0))
	var lab := _text("CONTAINER ROW", 0.05, Color(1, 0.75, 0.3))
	lab.rotation = Vector3(-PI / 2, PI / 2, 0); lab.position = Vector3(-34.0, 0.03, -80); lab.modulate.a = 0.6
	L.add_child(lab)
	# catwalk to the arena
	K.stripe(L, Vector3(-26, 0, -93.4), Vector2(8, 0.4)); K.stripe(L, Vector3(-26, 0, -98.6), Vector2(8, 0.4))
	L.railing(-30, -99.2, -22.8, -99.2); L.railing(-30, -92.8, -22.8, -92.8)

# ---------------------------------------------------------------- holding pen (x 28..52, z -85..-63)
static func _pen(L, life) -> void:
	var cages: Array = []
	for c in [[Vector3(33.0, 0, -82.0), 0.0], [Vector3(40.5, 0, -82.0), 0.0], [Vector3(48.5, 0, -80.5), -PI / 2]]:
		cages.append(_cage(L, c[0], c[1]))
	# a few captives in each cage (the docks cargo bot)
	var bots := []
	for i in cages.size():
		var cp: Vector3 = cages[i].pos
		for j in 2:
			var b := K.model(L, "docks/dock_bot", cp + Vector3(-0.9 + j * 1.8, 0, 0.2) if i < 2 else cp + Vector3(0.2, 0, -0.9 + j * 1.8), PI if i < 2 else -PI / 2, 1.1)
			if b: bots.append(b)
	life.pen_cages = cages; life.pen_bots = bots
	var sw: Node3D = preload("res://scripts/level/switch_target.gd").new(); sw.label_text = "RELEASE"
	sw.position = Vector3(36.8, 0, -72.5); sw.rotation.y = PI * 0.25; L.add_child(sw)
	sw.activated.connect(func(_n): life.release_pen())
	K.poster(L, Vector3(44.0, 0, -64.0), PI, "HOLDING PEN", "", Vector2(3.4, 1.6), "BOTS WHO ASKED FOR A RAISE")
	K.poster(L, Vector3(51.4, 0, -70.0), -PI / 2, "COMPLAINTS DEPARTMENT", POSTER2, Vector2(3.0, 2.0), "SEE SMELTER")
	life.add_speaker(K.loudspeaker(L, Vector3(51.0, 0, -84.2), -PI * 0.75))
	# guard tower with a searchlight sweeping the pen
	var tp := Vector3(30.6, 0, -75.0)
	K.lattice(L, tp, 2.0, 5.0)
	K.bx(L, tp + Vector3(0, 5.15, 0), Vector3(2.8, 0.3, 2.8), "dark", true)
	K.bx(L, tp + Vector3(0, 6.9, 0), Vector3(2.9, 0.25, 2.9), "red")
	for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		K.bx(L, tp + Vector3(c.x * 1.3, 6.0, c.y * 1.3), Vector3(0.14, 1.7, 0.14), "dark")
	var sl := K.node(L, tp + Vector3(0, 5.9, 0))
	K.cy(sl, Vector3(0, 0, 0.3), 0.35, 0.6, "yellow_obj", Vector3(PI / 2, 0, 0))
	K.cy(sl, Vector3(0, 0, 0.62), 0.3, 0.04, "glow_white", Vector3(PI / 2, 0, 0))
	var spot := SpotLight3D.new(); spot.light_color = Color(1, 0.92, 0.7); spot.light_energy = 6.0; spot.spot_range = 22.0
	spot.spot_angle = 14.0; spot.shadow_enabled = false; spot.position = Vector3(0, 0, 0.7); spot.rotation.y = PI; sl.add_child(spot)
	life.add_searchlight(sl, Vector3(40, 0, -76))
	K.model(L, "docks/crates", Vector3(46.0, 0, -66.5), 0.3, 1.8, true)
	K.model(L, "docks/barrels", Vector3(50.8, 0, -64.4), 0.0, 1.2, true)
	K.model(L, "docks/floodlight", Vector3(51.0, 0, -77.0), -PI / 2, 6.0, true, 0.3)
	K.stripe(L, Vector3(28.8, 0, -66.0), Vector2(1.6, 5.0))
	K.work_light(L, Vector3(28.6, 0, -84.4), PI * 0.25)

## A cage of bars with a roof and a red padlock light; its front bars lift away when the pen is released.
static func _cage(L, pos: Vector3, yaw: float) -> Dictionary:
	var n := K.node(L, pos, yaw)
	var w := 4.4; var d := 3.2; var h := 2.8
	K.bx(n, Vector3(0, 0.1, 0), Vector3(w, 0.2, d), "dark", true)
	K.bx(n, Vector3(0, h, 0), Vector3(w + 0.2, 0.2, d + 0.2), "yellow", true)
	K.bx(n, Vector3(0, h + 0.12, 0), Vector3(w + 0.1, 0.05, d + 0.1), "hazard")
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			K.bx(n, Vector3(sx * w * 0.5, h * 0.5, sz * d * 0.5), Vector3(0.2, h, 0.2), "yellow")
	# back and side bars (static)
	for i in 9:
		K.cy(n, Vector3(-w * 0.5 + 0.45 + i * (w - 0.9) / 8.0, h * 0.5, -d * 0.5), 0.04, h, "steel")
	for s in [-1, 1]:
		for i in 5:
			K.cy(n, Vector3(s * w * 0.5, h * 0.5, -d * 0.5 + 0.5 + i * (d - 1.0) / 4.0), 0.04, h, "steel")
	K.add_collider(n, Vector3(w, h, 0.2), Vector3(0, h * 0.5, -d * 0.5))
	for s in [-1, 1]: K.add_collider(n, Vector3(0.2, h, d), Vector3(s * w * 0.5, h * 0.5, 0))
	# front door: bars on a frame that slides up
	var door := K.node(n, Vector3(0, 0, d * 0.5))
	for i in 9:
		K.cy(door, Vector3(-w * 0.5 + 0.45 + i * (w - 0.9) / 8.0, h * 0.5, 0), 0.045, h - 0.2, "steel")
	K.bx(door, Vector3(0, h * 0.5, 0.05), Vector3(w - 0.4, 0.12, 0.12), "yellow")
	var lock_ := K.bx(door, Vector3(0, h * 0.5 - 0.3, 0.12), Vector3(0.3, 0.36, 0.14), "glow_red")
	var dsb := K.add_collider(door, Vector3(w, h, 0.2), Vector3(0, h * 0.5, 0))
	return { node = n, door = door, lock = lock_, collider = dsb, pos = pos }

# ---------------------------------------------------------------- the arena (x -22..22, z -114..-80)
static func _arena(L, life) -> void:
	var c := Vector3(0, 0, -97)
	# the stage mark under the boss drop point and hazard edging
	var ring := MeshInstance3D.new(); var tm := TorusMesh.new(); tm.inner_radius = 4.6; tm.outer_radius = 5.4; tm.rings = 48
	ring.mesh = tm; ring.material_override = K.mat("hazard"); ring.scale = Vector3(1, 0.03, 1); ring.position = Vector3(0, 0.03, -102)
	L.add_child(ring)
	for z in [-81.2, -112.8]: K.stripe(L, Vector3(0, 0, z), Vector2(42, 0.8))
	# floor grates with a hot glow under them, and oil stains: the stage is a working deck
	for g in [Vector3(-14, 0, -84.5), Vector3(14, 0, -84.5), Vector3(-17, 0, -97), Vector3(17, 0, -97), Vector3(-14, 0, -109.5), Vector3(14, 0, -109.5)]:
		K.bx(L, g + Vector3(0, 0.015, 0), Vector3(3.0, 0.03, 2.0), "dark")
		for i in 6: K.bx(L, g + Vector3(-1.25 + i * 0.5, 0.035, 0), Vector3(0.12, 0.03, 1.8), "steel")
		K.bx(L, g + Vector3(0, 0.02, 0), Vector3(2.8, 0.02, 1.8), "glow_molten")
	for o in [Vector3(-6, 0, -90), Vector3(7, 0, -108), Vector3(4, 0, -88), Vector3(-9, 0, -104)]:
		var st := K.cy(L, o + Vector3(0, 0.012, 0), randf_range(0.8, 1.5), 0.01, "cable", Vector3.ZERO, 16)
		st.scale = Vector3(1.0, 1.0, randf_range(0.6, 1.0))
	for x in [-20.8, 20.8]: K.stripe(L, Vector3(x, 0, -97), Vector2(0.8, 30))
	# overhead crane: runway girders on lattice towers, a travelling bridge with a trolley and a hanging load
	for x in [-24.5, 24.5]:
		for z in [-115.5, -104.0, -78.5]:
			K.lattice(L, Vector3(x, 0, z), 1.4, 13.0)
		K.girder(L, Vector3(x, 13.2, -116.5), Vector3(x, 13.2, -77.5), 1.2, "yellow")
		K.bx(L, Vector3(x, 13.0, -97), Vector3(0.6, 0.3, 39), "hazard")
	var bridge := K.node(L, Vector3(0, 14.4, -97), 0.0, "ArenaBridge")
	K.girder(bridge, Vector3(-25.5, 0, 0), Vector3(25.5, 0, 0), 1.4, "yellow")
	for s in [-1, 1]:
		K.bx(bridge, Vector3(s * 24.5, 0.6, 0), Vector3(1.6, 1.8, 2.4), "dark")
		K.cy(bridge, Vector3(s * 24.5, -0.4, 0.7), 0.35, 0.5, "glow_amber", Vector3(0, 0, PI / 2))
	var trolley := K.node(bridge, Vector3(0, 0, 0), 0.0, "Trolley")
	K.bx(trolley, Vector3(0, 0.7, 0), Vector3(3.0, 1.6, 2.6), "dark")
	K.bx(trolley, Vector3(0, 1.6, 0), Vector3(3.2, 0.25, 2.8), "hazard")
	K.cy(trolley, Vector3(0, 0.7, 1.4), 0.55, 0.3, "glow_red", Vector3(PI / 2, 0, 0))
	for s in [-1, 1]: K.cy(trolley, Vector3(s * 0.5, -2.5, 0), 0.04, 5.0, "cable")
	var hook_block := K.node(trolley, Vector3(0, -5.2, 0))
	K.bx(hook_block, Vector3.ZERO, Vector3(1.2, 0.8, 0.8), "yellow")
	K.bx(hook_block, Vector3(0, -0.6, 0), Vector3(1.8, 0.4, 1.8), "dark")
	K.omni(trolley, Vector3(0, -1.0, 0), Color(1, 0.75, 0.45), 2.0, 12.0)
	life.arena_bridge = bridge; life.arena_trolley = trolley; life.arena_hook = hook_block
	# crowd stands on the east side: three steps of cheering cargo bots
	for i in 3:
		var y := 0.6 + i * 0.8
		K.bx(L, Vector3(26.6 + i * 1.6, y * 0.5 - 0.6, -97), Vector3(1.6, y + 1.2, 26), "steel", true)
		K.bx(L, Vector3(26.6 + i * 1.6, y + 0.01, -97), Vector3(1.6, 0.04, 26), "deck")
		K.bx(L, Vector3(25.8 + i * 1.6, y - 0.05, -97), Vector3(0.08, 0.1, 26), "glow_amber")
		for k in 7:
			var z := -108.5 + k * 3.6 + (i % 2) * 1.6
			var b := K.model(L, "docks/dock_bot", Vector3(26.6 + i * 1.6, y, z), -PI / 2, 1.0)
			if b: life.add_fan(b)
	K.bx(L, Vector3(28.6, -2.6, -97), Vector3(5.6, 3.0, 28), "dark")
	for s in [-1, 1]:
		var banner := K.node(L, Vector3(31.2, 5.0, -97 + s * 7))
		K.bx(banner, Vector3(0, 0, 0), Vector3(0.1, 4.0, 5.0), "red")
		banner.add_child(_text("GO\nCRANE\nBOT!", 0.012, Color(1, 0.85, 0.3), -PI / 2, Vector3(-0.08, 0, 0)))
		K.bx(L, Vector3(31.2, 3.5, -97 + s * 7), Vector3(0.2, 7.0, 0.2), "dark")
	# the west entrance: Grudd's yard gate (doors slide open once the Row is clear), flanked by towers
	var g := Kit.place(L, "crane_yard_gate", Vector3(-22.4, 0, -96), PI / 2, 1.0, true)
	life.add_doors(g, "arena_gate")
	var field: Node3D = L.gates.get("arena_gate")
	if field:
		for mi in field.find_children("*", "MeshInstance3D", true, false): mi.visible = false
	for z in [-101.0, -91.0]:
		K.lattice(L, Vector3(-23.0, 0, z), 1.6, 9.0)
		var wl := K.work_light(L, Vector3(-23.0, 9.0, z), PI / 2, Color(1, 0.4, 0.25), 1.0)
		life.add_alarm(wl)
	var arch := K.node(L, Vector3(-23.0, 9.4, -96))
	K.bx(arch, Vector3.ZERO, Vector3(0.6, 1.6, 11.2), "dark")
	K.bx(arch, Vector3(0, 0.9, 0), Vector3(0.7, 0.2, 11.4), "yellow")
	for s in [-1, 1]:
		var t := _text("THE PIT" if s < 0 else "THE PIT", 0.03, Color(1, 0.4, 0.25), PI / 2 if s < 0 else -PI / 2, Vector3(s * 0.32, 0, 0))
		arch.add_child(t)
	# floodlight towers in the far corners
	for p in [Vector3(17.0, 0, -113.2), Vector3(-17.0, 0, -113.2)]:
		var f := K.model(L, "docks/floodlight", p, atan2(-p.x, -p.z - 97), 9.0, true, 0.3)
		if f: K.omni(L, p + Vector3(0, 8.0, 0) + (Vector3(0, 0, -97) - p).normalized() * 2.0, Color(1, 0.85, 0.65), 2.5, 12.0)
	life.add_speaker(K.loudspeaker(L, Vector3(-17.0, 0, -80.8), PI * 0.75, 6.0))
	life.add_speaker(K.loudspeaker(L, Vector3(17.0, 0, -80.8), -PI * 0.75, 6.0))
	K.poster(L, Vector3(12.0, 0, -113.6), 0.0, "EMPLOYEE OF THE MONTH", POSTER, Vector2(3.4, 2.4), "THE CRANE BOT (AGAIN)")
	K.poster(L, Vector3(-12.0, 0, -113.6), 0.0, "OVERTIME IS ITS\nOWN REWARD", POSTER2, Vector2(3.2, 2.2))
	life.arena_center = c
	# Grudd banners hanging from the crane runways, facing the stage
	for x in [-24.5, 24.5]:
		for z in [-110.0, -85.0]:
			life.add_sway(K.banner(L, Vector3(x + (0.6 if x < 0 else -0.6), 13.1, z), PI / 2 if x < 0 else -PI / 2, Vector2(2.2, 5.5)))

# ---------------------------------------------------------------- the foundry behind the arena (z -150..-118)
static func _foundry(L, life) -> void:
	var y0 := -1.0
	L.island("yard_foundry", L.rect(0, -132, 52, 24), y0, Color(0.6, 0.55, 0.5), 1.6)
	var sm := K.model(L, "smelter", Vector3(-10.0, y0, -134.0), PI, 12.0, false)
	var sm2 := K.model(L, "smelter", Vector3(14.0, y0, -136.0), PI * 0.9, 9.0, false)
	for p in [Vector3(-10.0, 3.5, -129.5), Vector3(13.0, 2.6, -132.0)]:
		K.omni(L, p, Color(1, 0.45, 0.12), 4.0, 12.0)
		life.add_sparks(K.sparks(L, p, Color(1, 0.55, 0.15), 30, 5.0), 0.0)
	# smokestacks
	for p in [Vector3(-22.0, y0, -140.0), Vector3(-17.0, y0, -143.0), Vector3(22.0, y0, -141.0)]:
		K.cy(L, p + Vector3(0, 11, 0), 1.3, 22.0, "rust", Vector3.ZERO, 16, 1.7)
		for k in 3: K.cy(L, p + Vector3(0, 6 + k * 6, 0), 1.55 - k * 0.12, 0.6, "hazard", Vector3.ZERO, 16)
		K.cy(L, p + Vector3(0, 22.2, 0), 1.45, 0.5, "glow_molten", Vector3.ZERO, 16)
		K.smoke(L, p + Vector3(0, 23.0, 0), 2.2, true)
	# the big ladle on a gantry, tipping molten metal into a mould
	K.girder(L, Vector3(8, 16, -126), Vector3(24, 16, -126), 1.2, "yellow")
	for x in [8.0, 24.0]:
		K.bx(L, Vector3(x, y0 + 8.5, -126), Vector3(0.8, 17, 0.8), "yellow")
	var ladle := K.node(L, Vector3(15.0, 10.5, -126.0), 0.0, "Ladle")
	K.cy(ladle, Vector3(0, 0, 0), 2.0, 2.6, "dark", Vector3.ZERO, 16, 1.6)
	K.cy(ladle, Vector3(0, 1.31, 0), 1.85, 0.06, "glow_molten", Vector3.ZERO, 16)
	K.bx(ladle, Vector3(0, 2.6, 0), Vector3(4.6, 0.3, 0.3), "yellow")
	for s in [-1, 1]: K.bx(ladle, Vector3(s * 2.2, 1.6, 0), Vector3(0.3, 2.2, 0.3), "yellow")
	K.cy(L, Vector3(15.0, 14.2, -126), 0.06, 3.6, "cable")
	var pour := K.cy(L, Vector3(17.0, 5.2, -126.0), 0.22, 9.0, "glow_hot")
	pour.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	K.bx(L, Vector3(17.0, y0 + 0.5, -126), Vector3(5.0, 1.0, 3.0), "dark")
	K.bx(L, Vector3(17.0, y0 + 1.02, -126), Vector3(4.4, 0.05, 2.4), "glow_molten")
	var ps := K.sparks(L, Vector3(17.0, y0 + 1.2, -126), Color(1, 0.6, 0.2), 30, 4.0)
	K.omni(L, Vector3(17.0, 2.0, -124.0), Color(1, 0.5, 0.15), 4.0, 12.0)
	life.add_pour(ladle, pour, ps)
	# Grudd's balcony overlooking the arena: a dark booth with a glowing logo
	var bal := K.node(L, Vector3(0, 0, -121.6))
	K.bx(bal, Vector3(0, 7.0, 0), Vector3(10.0, 0.5, 3.4), "dark", true)
	K.bx(bal, Vector3(0, 9.2, -1.4), Vector3(10.0, 4.0, 0.4), "dark")
	K.bx(bal, Vector3(0, 11.3, 0), Vector3(10.6, 0.4, 3.8), "yellow")
	K.bx(bal, Vector3(0, 8.0, 1.6), Vector3(10.0, 0.1, 0.1), "glow_amber")
	for x in [-4.6, 4.6]: K.bx(bal, Vector3(x, y0 * 0.5 + 3.3, 0), Vector3(0.7, 7.6, 0.7), "steel")
	var logo := K.node(bal, Vector3(0, 9.4, -1.15))
	K.cy(logo, Vector3.ZERO, 1.5, 0.12, "yellow_obj", Vector3(PI / 2, 0, 0), 24)
	logo.add_child(_text("G", 0.03, Color(0.15, 0.1, 0.08), 0.0, Vector3(0, -0.05, 0.08)))
	K.bx(logo, Vector3(0, 0.85, 0.05), Vector3(2.4, 0.35, 0.14), "yellow_obj")
	K.omni(bal, Vector3(0, 9.0, 1.0), Color(1, 0.6, 0.25), 2.0, 8.0)
	bal.add_child(_text("FOREMAN'S BOX", 0.009, Color(1, 0.8, 0.35), 0.0, Vector3(0, 7.55, 1.76)))
	life.add_speaker(K.loudspeaker(L, Vector3(-5.6, 7.25, -120.6), 0.0, 3.0))
	# little work crews shuttling across the foundry floor
	life.add_patrol(K.model(L, "docks/forklift", Vector3.ZERO, 0.0, 2.0), [Vector3(-20, y0, -126), Vector3(-4, y0, -126), Vector3(-4, y0, -139)], 2.2)
	life.add_patrol(K.model(L, "docks/dock_bot", Vector3.ZERO, 0.0, 1.2), [Vector3(22, y0, -138), Vector3(22, y0, -122), Vector3(4, y0, -121)], 1.5)
	life.add_patrol(K.model(L, "docks/dock_bot", Vector3.ZERO, 0.0, 1.2), [Vector3(-24, y0, -122), Vector3(-12, y0, -122)], 1.2)

# ---------------------------------------------------------------- background: cargo stacks and cranes out in the sky
static func _vista(L, life) -> void:
	var cols := [Color(0.72, 0.32, 0.2), Color(0.22, 0.52, 0.55), Color(0.9, 0.65, 0.18), Color(0.24, 0.32, 0.5)]
	for v in [[Vector3(-48, -4, -126), 0.4], [Vector3(46, -6, -118), -0.3]]:
		L.island("yard_bg_%d" % roundi(v[0].x), L.rect(v[0].x, v[0].z, 16, 14), v[0].y, Color(0.6, 0.58, 0.55), 1.4)
		for i in 5:
			var p: Vector3 = v[0] + Vector3(-4 + (i % 3) * 4, (i / 3) * 2.4, -2 + (i % 2) * 3.0)
			K.container(L, p, true, cols[i % 4])
		K.lattice(L, v[0] + Vector3(6, 0, 4), 1.6, 14.0, "yellow", false)
		K.girder(L, v[0] + Vector3(6, 14, 4), v[0] + Vector3(-8, 14, 4), 1.0, "yellow")
		K.cy(L, v[0] + Vector3(-6, 10.5, 4), 0.05, 7.0, "cable")
		K.bx(L, v[0] + Vector3(-6, 6.6, 4), Vector3(4.6, 2.2, 2.4), "red")

static func _text(t: String, px: float, c: Color, yaw := 0.0, pos := Vector3(0, 0, 0.07)) -> Label3D:
	var l := Label3D.new(); l.text = t; l.font_size = 96; l.pixel_size = px; l.outline_size = 12
	l.modulate = c; l.outline_modulate = Color(0.05, 0.04, 0.03); l.rotation.y = yaw; l.position = pos
	l.double_sided = false
	return l
