extends RefCounted
## Vesk's Junkyard: his home, a sprawling scrapyard on a floating rock (region x -50..50, z 58..160).
## The walled tutorial yard (x -18..18, z 68..96) is built by level_skyharbor.gd's _build_junkyard(); the
## island runs on south to the home yard (z 96..112). This file dresses all of it and adds:
##   Home yard (z 96..112)      Vesk's shack behind the porch, bolt garden, clothesline, oil tank (stash on top),
##                              radio, wind chimes, string lights
##   Scrap Heap (west, x -46..-24)  climbable scrap towers 1.2 / 2.4 / 3.6, then a double-jump teaser up to
##                              the summit (6.0) and a hidden ledge (7.2); scrap windmill on the big mound
##   Hull Dock (east, x 24..46)     the half-built sky skiff on trestles, scaffold (2.4), magnet crane with a
##                              deck (4.8) and a stash; welding sparks
##   Lookout (south, z 131..143)    pad and sliding platform from the home yard; Vesk's thinking spot and
##                              a hidden ledge further south (2.4)
## Cutscene anchors kept: porch chair (-2.5, 0.4, 93.5), workbench gear (3.6, 1.45, 94), Dodger's crash spot
## (-12.5, 2.4, 74.5). The intro's high shot from (1..3, 5.5..6.5, 98.5..99.5) stays clear of the shack roof.

const M := preload("res://scripts/mats.gd")
const JK := preload("res://scripts/level/junkyard/junk_kit.gd")
const Life := preload("res://scripts/level/junkyard/junk_life.gd")

const HEAP := Rect2(-46, 68, 22, 32)
const HULL := Rect2(24, 68, 22, 32)
const LOOKOUT := Rect2(-8, 131, 16, 12)
## Discovery chatter (audio/voice/<id>.ogg); subtitles are registered with Snd at build time so the shared
## script.json stays untouched.
const LINES := [
	["junkyard_heap_1", "dodger", "The Scrap Heap! I'm ninety percent sure there's a whole other toaster buried in there."],
	["junkyard_heap_2", "vesk", "Then it stays buried."],
	["junkyard_summit_1", "vesk", "Huh. Nice view. Still a dump. My dump."],
	["junkyard_hull_1", "dodger", "Ooh, Project Someday! Are we finishing the ship? Is today Someday?"],
	["junkyard_hull_2", "vesk", "No."],
	["junkyard_crane_1", "dodger", "Is the crane supposed to be swinging a car around by itself?"],
	["junkyard_crane_2", "vesk", "It gets bored."],
	["junkyard_lookout_1", "vesk", "My thinking spot. No talking."],
	["junkyard_lookout_2", "dodger", "Got it. ...Is whispering talking?"],
	["junkyard_statue_1", "dodger", "Wait. Is that supposed to be me? My eye is way bigger than that."],
	["junkyard_statue_2", "vesk", "It says approximate."],
	["junkyard_garden_1", "dodger", "Your bolt garden looks great, Vesk. The washers are really blooming this year."],
]

static func build(L) -> void:
	var rng := RandomNumberGenerator.new(); rng.seed = 4417
	var B := JK.Batch.new()
	var life: Node3D = Life.new(); life.name = "JunkLife"; L.add_child(life)
	_yard(L, B, rng, life)
	_home(L, B, rng, life)
	_heap(L, B, rng, life)
	_hull_dock(L, B, rng, life)
	_lookout(L, B, rng, life)
	_vista(L, B, rng, life)
	B.flush(L, JK)
	_chatter(L, life)
	L.debug_spots["junk_home"] = [Vector3(1.0, 0.1, 111.0), PI]
	L.debug_spots["junk_heap"] = [Vector3(-25, 0.1, 82), -PI * 0.6]
	L.debug_spots["junk_hull"] = [Vector3(26.5, 0.1, 79.5), 0.84]
	L.debug_spots["junk_lookout"] = [Vector3(0, 0.1, 133), PI]
	L.debug_spots["junk_summit"] = [Vector3(-38.4, 6.1, 86.6), PI / 2]
	L.debug_spots["junk_shack"] = [Vector3(-1, 0.1, 86.5), 0.0]

static func _chatter(L, life) -> void:
	var snd: Node = L.get_node_or_null("/root/Snd")
	if snd and snd.has_method("_load_script"):
		snd._load_script()
		for ln in LINES: snd.script_lines[ln[0]] = [ln[1], ln[2]]
	life.talk(Rect2(-36, 70, 12, 18), -1.0, 3.0, ["junkyard_heap_1", "junkyard_heap_2"])
	life.talk(Rect2(-42.2, 83.4, 5.2, 5.2), 5.5, 7.0, ["junkyard_summit_1"])
	life.talk(Rect2(24, 74, 10, 12), -1.0, 3.0, ["junkyard_hull_1", "junkyard_hull_2"])
	life.talk(Rect2(36, 68, 10, 14), -1.0, 6.0, ["junkyard_crane_1", "junkyard_crane_2"])
	life.talk(Rect2(-8, 131, 16, 12), -1.0, 2.0, ["junkyard_lookout_1", "junkyard_lookout_2"])
	life.talk(Rect2(-17, 102, 10, 9), -1.0, 2.0, ["junkyard_garden_1"])
	life.talk(Rect2(9.6, 97.5, 6, 6), -1.0, 2.0, ["junkyard_statue_1", "junkyard_statue_2"])

# ---------------------------------------------------------------- the tutorial yard (dressing only)
static func _yard(L, B, rng: RandomNumberGenerator, life) -> void:
	# keep the run lanes clear: porch -> hop wall -> Dodger's pile; the crank; the gate; the side gaps
	var avoid := [Rect2(-7, 84.5, 14, 12), Rect2(-15, 68, 30, 4), Rect2(-15, 72, 10, 9.5), Rect2(4.5, 84, 6, 6),
		Rect2(-18, 76, 6, 5.5), Rect2(12, 75, 6, 5.5), Rect2(-4, 68, 8, 14), Rect2(7, 85, 6, 6)]
	JK.litter(B, rng, Rect2(-17.5, 68.5, 35, 27), 0.0, 70, avoid)
	# corner heaps (visual, with a stubby collider)
	for h in [[Vector3(15.5, 0, 69.8), 2.3, 2.6], [Vector3(-16, 0, 95.5), 1.8, 2.0], [Vector3(16.2, 0, 88), 1.8, 2.2]]:
		JK.pile(B, rng, h[0], h[1], h[2], 46)
		JK.cyl_collider(L, h[0], h[1] * 0.6, h[2] * 0.55)
		life.creaks.append(h[0] + Vector3(0, 1, 0))
	# dress Dodger's scrap pile (the blocks stay the real footing; pieces stay below their tops)
	JK.pile(B, rng, Vector3(-12.5, 0, 74.5), 2.9, 2.1, 60)
	JK.pile(B, rng, Vector3(-9.0, 0, 78.5), 2.6, 1.0, 34)
	JK.pile(B, rng, Vector3(-16.2, 0, 70.6), 1.6, 2.8, 30)
	life.creaks.append(Vector3(-12.5, 2.0, 74.5))
	# oil stains and patched floor plates
	_grime(L, B, rng, [Vector2(8.5, 93.0), Vector2(-9.5, 89.0), Vector2(3.0, 79.0), Vector2(12.0, 98.5), Vector2(-12.0, 99.5), Vector2(6.0, 72.0), Vector2(-2.0, 104.0), Vector2(7.0, 106.5), Vector2(-5.5, 111.0), Vector2(9.5, 110.8), Vector2(-14.0, 72.5)])
	# wrench practice: a few crates by the start, and a sign that says what F does
	L.crate_spots.append(Vector3(10.6, 0, 89.6)); L.crate_spots.append(Vector3(11.4, 0, 88.4))
	L.hint_sign("F: WRENCH IT. CRATES COUGH UP SPROCKETS", Vector3(12.6, 0, 90.2), PI * 0.85)
	L.hint_sign("SCRAP HEAP. CLIMB AT YOUR OWN RISK", Vector3(-16.6, 0, 82.2), PI * 0.6)
	L.hint_sign("HULL DOCK. DON'T TOUCH THE SHIP", Vector3(16.6, 0, 81.4), -PI * 0.6)
	# corrugated patches and posts on the yard walls so they read as a scrap fence
	for w in [[-18.0, 72.3, 8.6], [-18.0, 96.7, 31.4], [18.0, 71.8, 7.6], [18.0, 96.2, 32.4]]:
		var z0: float = w[1] - w[2] / 2
		var n := int(w[2] / 2.2)
		for i in n:
			var z: float = z0 + (i + 0.5) * w[2] / n
			var col: Color = JK.PALETTE[rng.randi() % JK.PALETTE.size()]
			var s: float = signf(w[0])
			B.add("plate", "scrap", JK.xform(Vector3(w[0] - s * 0.05, rng.randf_range(1.0, 1.5), z), Vector3(rng.randf_range(-0.08, 0.08), 0, PI / 2 + rng.randf_range(-0.06, 0.06)), Vector3(rng.randf_range(1.8, 2.6), 1, rng.randf_range(1.6, 2.2))), col)
			if i % 2 == 0: B.add("beam", "scrap", JK.xform(Vector3(w[0] - s * 0.12, 1.5, z0 + i * w[2] / n), Vector3(PI / 2, 0, 0), Vector3(1.1, 1.1, 3.2)), JK.GUN)
	# the gate arch: scrap pillars and a big rusty name board (kept above the intro's view of the mast)
	for x in [-5.0, 5.0]:
		L.box(Vector3(x, 2.9, 68.3), Vector3(1.0, 5.8, 1.0), JK.mat("rust"))
		for i in 4: B.add("drum", "scrap", JK.xform(Vector3(x + rng.randf_range(-0.2, 0.2), 0.5 + i * 1.35, 68.3), Vector3(0, rng.randf() * TAU, rng.randf_range(-0.1, 0.1)), Vector3(1.6, 1.3, 1.6)), JK.PALETTE[rng.randi() % JK.PALETTE.size()])
		B.add("tire", "rubber", JK.xform(Vector3(x, 6.0, 68.3), Vector3(PI / 2, 0, 0), Vector3.ONE * 1.1))
	var arch := JK.sign(L, "VESK'S JUNKYARD", Vector3(0, 0, 68.3), 0.0, 10.6, 1.3, 5.1, Color(1.0, 0.8, 0.4), Color(0.45, 0.26, 0.14))
	for c in arch.get_children(): if c is MeshInstance3D and (c.mesh as BoxMesh).size.y > 5.0: c.visible = false   # pillars do the holding
	for x in [-4.2, -1.4, 1.4, 4.2]: B.add("ball", "bulb", JK.xform(Vector3(x, 6.6, 68.25), Vector3.ZERO, Vector3.ONE * 0.2))
	# hanging chains and a hook off the porch roofline beam, and tools on the wall
	var beam: MeshInstance3D = L.box(Vector3(0, 3.35, 90.8), Vector3(12.6, 0.22, 0.22), JK.mat("dark"), false)
	beam.name = "PorchBeam"
	for p in [Vector3(-4.2, 3.24, 90.8), Vector3(4.6, 3.24, 90.8)]:
		var end := JK.chain(B, p, 0.9)
		B.add("gear", "scrap", JK.xform(end + Vector3(0, -0.1, 0), Vector3(PI / 2, 0, 0), Vector3.ONE * 0.5), JK.YELLOW)
	for x in [-5.6, 5.6]: L.cyl(Vector3(x, 2.35, 90.8), 0.1, 0.1, 2.0, JK.mat("wood"), 8)
	# a few kit props for density
	L.prop("crate_small", Vector3(16.8, 0, 79.6 + 3.2), 0.4)
	L.prop("barrel", Vector3(-16.9, 0, 75.4), 0.0)
	L.prop("vent_stack", Vector3(-16.6, 0, 92.2), 0.0, 0.8, true)
	DocksDressing.place(L, "cable_spool", Vector3(-6.6, 0, 72.6), 0.4, 1.2, true)
	DocksDressing.place(L, "barrels", Vector3(16.2, 0, 85.0), 1.0, 1.3, true)
	DocksDressing.steam(L, Vector3(-16.6, 2.2, 92.2), 0.7)

## Dark oil stains (flat transparent discs) and riveted patch plates on the floor at the given spots.
static func _grime(L, B, rng: RandomNumberGenerator, spots: Array, y := 0.0) -> void:
	var stain := M.std(Color(0.08, 0.07, 0.06, 0.55), 0.3, 0.2); stain.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var cm := CylinderMesh.new(); cm.top_radius = 0.5; cm.bottom_radius = 0.5; cm.height = 0.01; cm.radial_segments = 14
	for p: Vector2 in spots:
		var sm := MeshInstance3D.new(); sm.mesh = cm; sm.material_override = stain; sm.position = Vector3(p.x, y + 0.012, p.y)
		sm.scale = Vector3(rng.randf_range(1.0, 2.4), 1, rng.randf_range(0.8, 1.8)); sm.rotation.y = rng.randf() * TAU
		sm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; L.add_child(sm)
		var q := p + Vector2(rng.randf_range(-2.5, 2.5), rng.randf_range(-2.5, 2.5))
		B.add("plate", "scrap", JK.xform(Vector3(q.x, y + 0.02, q.y), Vector3(0, rng.randf_range(-0.3, 0.3), 0), Vector3(rng.randf_range(1.2, 2.4), 0.5, rng.randf_range(1.0, 2.0))), JK.RUST * rng.randf_range(0.7, 1.0))

# ---------------------------------------------------------------- home yard (z 96..112)
static func _home(L, B, rng: RandomNumberGenerator, life) -> void:
	# Vesk's shack, right behind the porch; front door faces the yard (north)
	var shack: Node3D = JK.place(L, "shack", Vector3(-3, 0, 98.7), PI, 5.4)
	JK.box_collider(L, Vector3(-3, 2.0, 98.7), Vector3(5.6, 4.0, 3.9))
	JK.omni(L, Vector3(-3, 1.9, 95.4), Color(1.0, 0.7, 0.38), 1.6, 7.0)
	DocksDressing.steam(L, Vector3(-1.7, 5.4, 98.9), 0.6)
	# string lights from the shack eaves out to the porch lamps
	JK.bulbs(B, L, Vector3(-5.8, 3.3, 96.6), Vector3(-6.5, 3.2, 91.0), 0.5, 9)
	JK.bulbs(B, L, Vector3(-0.2, 3.5, 96.6), Vector3(6.5, 3.2, 91.0), 0.6, 11)
	JK.bulbs(B, L, Vector3(-6.5, 3.2, 91.0), Vector3(6.5, 3.2, 91.0), 0.4, 14)
	# the shop sign
	JK.sign(L, "VESK'S SALVAGE & REPAIR\nNO REFUNDS. NO RETURNS. NO VISITORS.", Vector3(5.0, 0, 98.2), 0.0, 4.6, 1.3, 2.0, Color(1.0, 0.86, 0.5), Color(0.5, 0.3, 0.18), 0.16)
	# the radio on a crate by the generator, playing to nobody
	L.prop("crate_small", Vector3(8.0, 0, 97.8), 0.2)
	var radio: MeshInstance3D = L.box(Vector3(8.0, 1.2, 97.8), Vector3(0.6, 0.38, 0.26), JK.paint(JK.TEAL), false)
	radio.rotation.y = 0.2
	L.box(Vector3(0.12, 0.0, -0.14), Vector3(0.22, 0.16, 0.02), JK.mat("window"), false, radio)
	L.cyl(Vector3(7.85, 1.62, 97.8), 0.01, 0.01, 0.5, JK.mat("chain"), 4)
	life.ambient("junkyard_radio", Vector3(8.0, 1.2, 97.8), -12.0, 2.5, 22.0)
	# wind chimes on a crooked pole by the shack corner
	_chimes(L, B, life, Vector3(-7.4, 0, 97.4), 3.0)
	life.ambient("junkyard_chimes", Vector3(-7.4, 2.6, 97.4), -10.0, 3.0, 30.0)
	# bolt garden: two raised beds of bolt-and-gear "flowers", a watering can and a scrap scarecrow
	for bed in [Vector3(-12.6, 0, 104.4), Vector3(-12.6, 0, 108.2)]:
		L.box(bed + Vector3(0, 0.25, 0), Vector3(5.0, 0.5, 1.4), JK.mat("wood"), true)
		L.box(bed + Vector3(0, 0.49, 0), Vector3(4.7, 0.04, 1.1), M.std(Color(0.3, 0.22, 0.15), 0.0, 1.0), false)
		for i in 9:
			var p: Vector3 = bed + Vector3(-2.1 + i * 0.52 + rng.randf_range(-0.08, 0.08), 0.5, rng.randf_range(-0.35, 0.35))
			var h := rng.randf_range(0.45, 1.0)
			B.add("pipe", "scrap", JK.xform(p + Vector3(0, h / 2, 0), Vector3(rng.randf_range(-0.12, 0.12), 0, rng.randf_range(-0.12, 0.12)), Vector3(0.05, h, 0.05)), Color(0.35, 0.55, 0.3))
			var top := p + Vector3(0, h, 0)
			var col: Color = [JK.YELLOW, JK.ORANGE, JK.TEAL, JK.RED, JK.CREAM][rng.randi() % 5]
			if i % 3 == 0: B.add("gear", "scrap", JK.xform(top, Vector3(PI / 2, rng.randf() * TAU, 0), Vector3.ONE * 0.36), col)
			elif i % 3 == 1: B.add("nut", "scrap", JK.xform(top, Vector3(PI / 2, 0, rng.randf() * TAU), Vector3(0.22, 0.12, 0.22)), col)
			else: B.add("ball", "bulb" if rng.randf() < 0.5 else "scrap", JK.xform(top, Vector3.ZERO, Vector3.ONE * 0.16), col)
			B.add("plate", "scrap", JK.xform(p + Vector3(0, h * 0.5, 0), Vector3(0, rng.randf() * TAU, 0.5), Vector3(0.18, 1, 0.08)), Color(0.35, 0.6, 0.3))
	L.cyl(Vector3(-9.6, 0.25, 106.3), 0.2, 0.24, 0.5, JK.paint(JK.TEAL), 12)
	_scarecrow(L, B, life, Vector3(-16.0, 0, 106.3))
	L.hint_sign("BOLT GARDEN. DO NOT WATER.", Vector3(-9.0, 0, 110.4), PI * 0.9)
	# clothesline: Vesk's spare overalls and rags, swaying
	for p in [Vector3(-7.2, 0, 102.6), Vector3(-7.2, 0, 110.6)]: L.cyl(p + Vector3(0, 1.3, 0), 0.06, 0.08, 2.6, JK.mat("wood"), 8)
	JK.rope(L, Vector3(-7.2, 2.5, 102.6), Vector3(-7.2, 2.5, 110.6), 0.3, 0.012)
	var cloths := [Color(0.85, 0.45, 0.18), Color(0.3, 0.36, 0.45), Color(0.9, 0.85, 0.7), Color(0.75, 0.25, 0.2), Color(0.25, 0.55, 0.55)]
	for i in 5:
		var z := 103.8 + i * 1.45
		var u := (z - 102.6) / 8.0
		var y := 2.5 - 0.3 * 4.0 * u * (1.0 - u)
		var hang := Node3D.new(); hang.position = Vector3(-7.2, y, z); L.add_child(hang)
		var q := MeshInstance3D.new(); var qm := BoxMesh.new(); qm.size = Vector3(0.03, rng.randf_range(0.6, 1.1), rng.randf_range(0.6, 1.0)); q.mesh = qm
		q.material_override = JK.cloth(cloths[i]); q.position.y = -qm.size.y / 2; hang.add_child(q)
		life.swing(hang, Vector3(0.0, 0.0, 0.22), 1.3 + i * 0.17, i * 1.3)
	# the old oil tank: steps up the side, a stash on top
	var tank_c := Vector3(11.6, 0, 107.2)
	L.cyl(tank_c + Vector3(0, 1.8, 0), 2.1, 2.1, 3.6, JK.mat("rust_obj"), 20, true)
	for y in [0.5, 1.8, 3.1]: L.cyl(tank_c + Vector3(0, y, 0), 2.16, 2.16, 0.14, JK.mat("dark"), 20)
	L.cyl(tank_c + Vector3(0, 3.62, 0), 2.0, 2.1, 0.08, JK.mat("dark"), 20)
	L.label("OIL", tank_c + Vector3(0, 3.64, 0.6), 1.6, Color(1, 0.85, 0.5), 0.0)
	for i in 10:  # ladder rungs on the west side (decor; the crates are the real way up)
		L.box(tank_c + Vector3(-2.2, 0.35 + i * 0.33, 0), Vector3(0.06, 0.05, 0.7), JK.mat("dark"), false)
	for s in [-0.35, 0.35]: L.box(tank_c + Vector3(-2.22, 1.7, s), Vector3(0.06, 3.4, 0.06), JK.mat("dark"), false)
	L.block(15.3, 103.6, 2.0, 2.0, 1.2, 0, JK.mat("rust"), false)
	L.block(15.5, 106.6, 2.0, 2.6, 2.4, 0, JK.mat("rust"), false)
	L.prop("crate_small", Vector3(16.0, 1.2, 103.0), 0.3, 0.6, false)
	DocksDressing.place(L, "pipes", tank_c + Vector3(0.6, 0, -2.6), PI, 2.0, true, 0.6)
	DocksDressing.steam(L, tank_c + Vector3(0.6, 2.1, -2.6), 0.5)
	L.crate_spots.append(tank_c + Vector3(0.4, 3.6, 0.3))
	# tarp-covered junk along the south fence
	JK.tarp(L, Vector3(4.4, 0, 108.6), Vector3(3.0, 1.6, 2.2), 0.15, Color(0.25, 0.5, 0.5))
	JK.tarp(L, Vector3(-3.4, 0, 109.6), Vector3(2.4, 1.2, 1.8), -0.2, Color(0.8, 0.42, 0.2))
	JK.tarp(L, Vector3(6.6, 0, 103.4), Vector3(1.6, 1.0, 1.6), 0.6, Color(0.55, 0.5, 0.35))
	# south fence with the gap to the lookout
	for seg in [[-10.25, 15.5], [10.25, 15.5]]:
		L.box(Vector3(seg[0], 0.6, 112.2), Vector3(seg[1], 1.2, 0.3), JK.mat("rust"))
		for i in 6:
			B.add("plate", "scrap", JK.xform(Vector3(seg[0] - seg[1] / 2 + (i + 0.5) * seg[1] / 6, rng.randf_range(0.6, 0.9), 112.0), Vector3(PI / 2 + rng.randf_range(-0.1, 0.1), 0, rng.randf_range(-0.1, 0.1)), Vector3(rng.randf_range(2.2, 2.8), 1, rng.randf_range(1.0, 1.5))), JK.PALETTE[rng.randi() % JK.PALETTE.size()])
	JK.sign(L, "LOOKOUT  ->  MIND THE GAP", Vector3(4.0, 0, 111.6), 0.0, 2.6, 0.6, 1.4, Color(1, 0.9, 0.6), Color(0.2, 0.36, 0.38))
	JK.litter(B, rng, Rect2(-17.5, 96.5, 35, 15), 0.0, 40, [Rect2(-7, 96, 9, 7), Rect2(-3, 96, 6, 17), Rect2(9, 104.5, 8, 6), Rect2(13.5, 102.5, 3.5, 5.5)])
	L.lamp(-2.4, 110.8, Color(1, 0.72, 0.42))
	life.creaks.append(tank_c + Vector3(0, 2, 0))
	# lawn ornament: a welded scrap statue of Dodger, roughly
	var st := Vector3(12.6, 0, 101.0)
	L.box(st + Vector3(0, 0.35, 0), Vector3(1.4, 0.7, 1.4), JK.mat("rust"))
	var body := MeshInstance3D.new(); body.mesh = JK.mesh("ball"); body.material_override = JK.paint(JK.CREAM)
	body.position = st + Vector3(0, 1.55, 0); body.scale = Vector3.ONE * 1.5; L.add_child(body)
	var band := MeshInstance3D.new(); var bt := TorusMesh.new(); bt.inner_radius = 0.72; bt.outer_radius = 0.8; band.mesh = bt
	band.material_override = JK.paint(JK.ORANGE); band.position = st + Vector3(0, 1.55, 0); L.add_child(band)
	var eye := MeshInstance3D.new(); var em := CylinderMesh.new(); em.top_radius = 0.28; em.bottom_radius = 0.3; em.height = 0.12; eye.mesh = em
	eye.material_override = JK.mat("glow_cyan"); eye.rotation.x = PI / 2; eye.position = st + Vector3(0, 1.62, -0.72); L.add_child(eye)
	for sd in [-1, 1]:
		var arm: MeshInstance3D = L.box(st + Vector3(sd * 0.95, 1.7, 0), Vector3(0.5, 0.08, 0.08), JK.mat("dark"), false)
		var rot := Node3D.new(); rot.position = st + Vector3(sd * 1.2, 1.78, 0); L.add_child(rot)
		L.box(Vector3.ZERO, Vector3(0.9, 0.03, 0.12), JK.paint(JK.TEAL), false, rot)
		L.box(Vector3.ZERO, Vector3(0.12, 0.03, 0.9), JK.paint(JK.TEAL), false, rot)
		life.spin(rot, Vector3.UP, 0.7 * sd)
	JK.sign(L, "DODGER (APPROX.)", st + Vector3(0, 0, -0.95), PI, 1.3, 0.3, 0.25, Color(1, 0.9, 0.6), Color(0.35, 0.22, 0.12), 0.3)
	# steam vents poking out of the yard floor
	for v in [Vector3(-14.2, 0, 99.5), Vector3(16.4, 0, 100.4)]:
		L.cyl(v + Vector3(0, 0.45, 0), 0.18, 0.22, 0.9, JK.mat("dark"), 10)
		L.cyl(v + Vector3(0, 0.92, 0), 0.24, 0.24, 0.08, JK.mat("brass"), 10)
		DocksDressing.steam(L, v + Vector3(0, 1.0, 0), 0.45)

static func _chimes(L, B, life, pos: Vector3, h: float) -> void:
	L.cyl(pos + Vector3(0, h / 2, 0), 0.06, 0.09, h, JK.mat("dark"), 8)
	L.box(pos + Vector3(0.35, h - 0.05, 0), Vector3(0.8, 0.08, 0.08), JK.mat("dark"), false)
	var top := Node3D.new(); top.position = pos + Vector3(0.6, h - 0.1, 0); L.add_child(top)
	var ring := MeshInstance3D.new(); var rm := TorusMesh.new(); rm.inner_radius = 0.2; rm.outer_radius = 0.25; ring.mesh = rm
	ring.material_override = JK.mat("brass"); ring.position.y = -0.3; top.add_child(ring)
	for i in 6:
		var a := i * TAU / 6
		var piv := Node3D.new(); piv.position = Vector3(cos(a) * 0.22, -0.32, sin(a) * 0.22); top.add_child(piv)
		var p := MeshInstance3D.new(); var pm := CylinderMesh.new(); pm.top_radius = 0.035; pm.bottom_radius = 0.035
		pm.height = 0.4 + i * 0.09; p.mesh = pm; p.material_override = JK.mat("brass") if i % 2 == 0 else JK.paint(JK.TEAL)
		p.position.y = -pm.height / 2 - 0.08; piv.add_child(p)
		life.swing(piv, Vector3(0.25, 0, 0.25), 2.2 + i * 0.31, i * 0.9)
	life.swing(top, Vector3(0.06, 0.3, 0.06), 0.8)

static func _scarecrow(L, B, life, pos: Vector3) -> void:
	L.cyl(pos + Vector3(0, 1.1, 0), 0.07, 0.09, 2.2, JK.mat("wood"), 8)
	var body := Node3D.new(); body.position = pos + Vector3(0, 1.6, 0); L.add_child(body)
	L.box(Vector3(0, 0, 0), Vector3(1.6, 0.1, 0.1), JK.mat("wood"), false, body)
	L.box(Vector3(0, -0.15, 0), Vector3(0.7, 0.8, 0.4), JK.cloth(Color(0.85, 0.45, 0.18)), false, body)
	var head: MeshInstance3D = L.box(Vector3(0, 0.55, 0), Vector3(0.45, 0.4, 0.45), JK.paint(JK.TEAL), false, body)
	L.box(Vector3(0, 0, -0.23), Vector3(0.16, 0.16, 0.02), JK.mat("glow_orange"), false, head)  # one big eye, like a drone
	var pot := MeshInstance3D.new(); var pm := CylinderMesh.new(); pm.top_radius = 0.18; pm.bottom_radius = 0.26; pm.height = 0.3
	pot.mesh = pm; pot.material_override = JK.mat("rust_obj"); pot.position = Vector3(0.05, 0.36, 0); pot.rotation.z = 0.2; head.add_child(pot)
	for s in [-1, 1]:
		var g := MeshInstance3D.new(); var gm := BoxMesh.new(); gm.size = Vector3(0.18, 0.28, 0.12); g.mesh = gm
		g.material_override = JK.mat("dark"); g.position = Vector3(s * 0.85, -0.12, 0); body.add_child(g)
	life.swing(body, Vector3(0, 0.12, 0.05), 0.9)

# ---------------------------------------------------------------- Scrap Heap (west)
static func _heap(L, B, rng: RandomNumberGenerator, life) -> void:
	JK.slab(L, "junk_heap", HEAP, 0.0, Color(0.86, 0.74, 0.6))
	JK.plank_bridge(L, Vector3(-18.6, 0, 78.8), Vector3(-24.4, 0, 78.8), 3.0, rng)
	L.checkpoints.append({ pos = Vector3(-26.5, 0.1, 79.0), r = 2.0 })
	# the climb: three scrap towers, then the summit (double jump), then a hidden ledge (double jump)
	var steps := [[Vector2(-27.5, 84.0), 3.0, 1.2], [Vector2(-31.0, 86.6), 3.0, 2.4], [Vector2(-34.6, 89.2), 3.0, 3.6], [Vector2(-39.6, 86.0), 5.0, 6.0]]
	for s in steps:
		var p: Vector2 = s[0]
		var tw: MeshInstance3D = L.block(p.x, p.y, s[1], s[1], s[2], 0, JK.mat("rust"), not JK.hd_on())   # no glowing lip on a bale stack
		if JK.hd_on():
			# the block stays as the collider; what you see is a stack of crushed-scrap bales
			tw.visible = false
			var n := maxi(1, roundi(s[2] / 1.2)); var bh: float = s[2] / n
			for k in n:
				B.add("bale", "bale", JK.xform(Vector3(p.x, bh * (k + 0.5), p.y), Vector3(0, rng.randf_range(-0.05, 0.05) + (k % 2) * PI / 2, 0), Vector3(s[1] - 0.04, bh - 0.02, s[1] - 0.04)), JK.PALETTE[rng.randi() % JK.PALETTE.size()])
		# junk piled against each tower so it reads as a heap, not a pillar
		JK.pile(B, rng, Vector3(p.x, 0, p.y), s[1] * 0.85, s[2] * 0.95, int(18 + s[2] * 9))
		# a lip of loose plates on top
		for i in 3:
			B.add("plate", "scrap", JK.xform(Vector3(p.x + rng.randf_range(-0.6, 0.6), s[2] + 0.04, p.y + rng.randf_range(-0.6, 0.6)), Vector3(0, rng.randf() * TAU, 0), Vector3(rng.randf_range(0.8, 1.4), 1, rng.randf_range(0.6, 1.0))), JK.PALETTE[rng.randi() % JK.PALETTE.size()])
		life.creaks.append(Vector3(p.x, s[2], p.y))
	L.hint_sign("JETPACK: TAP JUMP AGAIN IN MID-AIR", Vector3(-35.6, 3.6, 90.2), -PI * 0.35)
	# summit: chimes, a rag flag on a pipe, the stash, and the view back over the yard
	var top := Vector3(-39.6, 6.0, 86.0)
	_chimes(L, B, life, top + Vector3(-1.8, 0, 1.8), 2.4)
	life.ambient("junkyard_chimes", top + Vector3(-1.4, 2.0, 1.8), -8.0, 4.0, 40.0)
	L.cyl(top + Vector3(1.8, 1.8, 1.8), 0.06, 0.08, 3.6, JK.mat("dark"), 8)
	var flag := Node3D.new(); flag.position = top + Vector3(1.8, 3.4, 1.8); L.add_child(flag)
	L.box(Vector3(0.55, -0.3, 0), Vector3(1.1, 0.6, 0.03), JK.cloth(Color(0.85, 0.45, 0.18)), false, flag)
	life.swing(flag, Vector3(0.05, 0.5, 0.08), 1.6)
	L.crate_spots.append(top + Vector3(-0.6, 0, -0.8))
	L.crate_spots.append(top + Vector3(0.9, 0, -1.0))
	# hidden ledge off the summit's north side (double jump), a tyre nest with a stash
	var lg := Vector3(-42.5, 7.2, 79.4)
	L.ledge(lg.x, lg.z, 3.0, 3.0, lg.y, JK.mat("rust"))
	for i in 3: B.add("tire", "rubber", JK.xform(lg + Vector3(0.9, 0.12 + i * 0.2, -0.9), Vector3(0, i * 0.7, 0), Vector3.ONE * 0.8))
	L.crate_spots.append(lg + Vector3(-1.0, 0, -1.0))
	# the big mound at the back with a scrap windmill on top
	var mound := Vector3(-41.0, 0, 95.0)
	JK.pile(B, rng, mound, 5.2, 8.5, 150)
	JK.cyl_collider(L, mound, 3.4, 5.5)
	var mill := mound + Vector3(0.4, 7.4, 0.2)
	L.cyl(mill, 0.1, 0.14, 4.0, JK.mat("dark"), 8)
	var rotor := Node3D.new(); rotor.position = mill + Vector3(0, 2.1, -0.3); L.add_child(rotor)
	for i in 4:
		var bl := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = Vector3(0.42, 1.7, 0.05); bl.mesh = bm
		bl.material_override = JK.paint([JK.ORANGE, JK.CREAM, JK.TEAL, JK.RED][i]); bl.rotation.z = i * TAU / 4
		bl.position = Vector3(-sin(i * TAU / 4) * 0.95, cos(i * TAU / 4) * 0.95, 0); rotor.add_child(bl)
	var hub := MeshInstance3D.new(); var hm := CylinderMesh.new(); hm.top_radius = 0.2; hm.bottom_radius = 0.2; hm.height = 0.3
	hub.mesh = hm; hub.material_override = JK.mat("brass"); hub.rotation.x = PI / 2; rotor.add_child(hub)
	rotor.rotation.y = 0.5
	life.spin(rotor, Vector3.FORWARD, 1.4)
	life.creaks.append(mound + Vector3(0, 4, 0))
	# more heaps around the edges, an old car, a broken dock bot
	for h in [[Vector3(-44, 0, 71), 2.2, 3.0], [Vector3(-27, 0, 97), 2.6, 3.2], [Vector3(-44.2, 0, 84), 1.6, 2.4], [Vector3(-30.0, 0, 71.5), 1.8, 2.2]]:
		JK.pile(B, rng, h[0], h[1], h[2], 50)
		JK.cyl_collider(L, h[0], h[1] * 0.6, h[2] * 0.55)
	_car(L, B, Vector3(-30.5, 0, 93.0), 0.6, JK.TEAL)
	DocksDressing.place(L, "dock_bot", Vector3(-26.2, 0, 90.6), -2.2, 1.3, true)
	DocksDressing.place(L, "barrels", Vector3(-25.6, 0, 73.4), 0.6, 1.3, true)
	L.prop("scrap_heap", Vector3(-35.5, 0, 75.5), 1.0, 1.0, true)
	L.prop("junk_pile", Vector3(-38.0, 0, 97.5), 2.2, 1.0, true)
	JK.litter(B, rng, HEAP.grow(-0.6), 0.0, 60, [Rect2(-29, 76.5, 5, 5), Rect2(-37, 82, 14, 10)])
	L.label("SCRAP HEAP", Vector3(-30, 0, 78.5), 4, Color(1, 0.8, 0.55))
	_grime(L, B, rng, [Vector2(-27.0, 89.0), Vector2(-33.0, 80.0), Vector2(-40.0, 75.0), Vector2(-29.0, 75.5), Vector2(-35.0, 96.0)])
	# long-jump teaser: a junk raft off the heap's south edge (dash, then jump), a stash on it
	var raft := Rect2(-37, 106, 6, 7)
	JK.slab(L, "junk_raft", raft, 0.0, Color(0.8, 0.7, 0.58), "nsew", 0.8)
	L.hint_sign("LONG JUMP: DASH (SHIFT), THEN JUMP", Vector3(-31.2, 0, 98.6), PI * 0.15)
	L.crate_spots.append(Vector3(-35.4, 0, 110.2))
	L.prop("barrel", Vector3(-32.4, 0, 110.8), 0.4)
	JK.pile(B, rng, Vector3(-32.6, 0, 107.4), 1.0, 1.0, 14)
	JK.bulbs(B, L, Vector3(-37, 1.6, 106), Vector3(-31, 1.6, 106), 0.3, 6)
	for x in [-37.0, -31.0]: L.cyl(Vector3(x, 0.8, 106), 0.05, 0.06, 1.6, JK.mat("dark"), 6)

static func _car(L, B, pos: Vector3, yaw: float, col: Color) -> void:
	var n := Node3D.new(); n.position = pos; n.rotation = Vector3(0.05, yaw, 0.08); L.add_child(n)
	L.box(Vector3(0, 0.75, 0), Vector3(1.8, 0.8, 3.6), JK.paint(col), false, n)
	L.box(Vector3(0, 1.4, 0.2), Vector3(1.6, 0.6, 1.8), JK.paint(col.lightened(0.15)), false, n)
	L.box(Vector3(0, 1.4, -0.71), Vector3(1.45, 0.45, 0.04), M.std(Color(0.2, 0.3, 0.35), 0.5, 0.2), false, n)
	for p in [Vector3(-0.92, 0.38, 1.1), Vector3(0.92, 0.38, 1.1), Vector3(-0.92, 0.38, -1.1)]:
		var w := MeshInstance3D.new(); w.mesh = JK.mesh("tire"); w.material_override = JK.mat("rubber"); w.position = p; w.rotation.z = PI / 2
		w.scale = Vector3.ONE * 0.85; n.add_child(w)
	L.box(Vector3(0.6, 0.1, -1.6), Vector3(0.5, 0.2, 0.5), JK.mat("dark"), false, n)  # sat on a block where a wheel was
	JK.box_collider(L, pos + Vector3(0, 0.8, 0), Vector3(1.8, 1.6, 3.6), yaw)

# ---------------------------------------------------------------- Hull Dock (east)
static func _hull_dock(L, B, rng: RandomNumberGenerator, life) -> void:
	JK.slab(L, "junk_hull", HULL, 0.0, Color(0.88, 0.8, 0.7))
	JK.plank_bridge(L, Vector3(18.6, 0, 77.8), Vector3(24.4, 0, 77.8), 3.0, rng)
	L.checkpoints.append({ pos = Vector3(26.5, 0.1, 78.0), r = 2.0 })
	# the half-built skiff on its trestles, bow north; boards laid across the gunwales to work from
	var hc := Vector3(33.4, 0, 88.0)
	var hull: Node3D = JK.place(L, "hull", hc, -PI / 2, 4.2)
	JK.box_collider(L, hc + Vector3(0, 1.15, 0), Vector3(3.2, 2.3, 7.4))
	for i in 7:
		L.box(hc + Vector3(rng.randf_range(-0.1, 0.1), 2.36, -2.4 + i * 0.75), Vector3(3.0, 0.08, 0.5), JK.mat("plank"), false).rotation.y = rng.randf_range(-0.05, 0.05)
	life.welder(hc + Vector3(-1.75, 1.4, 1.2))
	life.welder(hc + Vector3(1.75, 1.7, -1.8))
	JK.omni(L, hc + Vector3(-2.6, 1.4, 1.2), Color(0.5, 0.8, 1.0), 0.8, 5.0)
	# a patched tarp canopy over the skiff on four scaffold poles
	for c in [Vector2(30.2, 82.6), Vector2(36.4, 82.6), Vector2(30.2, 93.4), Vector2(36.4, 93.4)]:
		L.cyl(Vector3(c.x, 3.3, c.y), 0.12, 0.14, 6.6, JK.mat("dark"), 8)
	for k in 3:
		var pc: Color = [Color(0.25, 0.5, 0.5), Color(0.8, 0.42, 0.2), Color(0.86, 0.8, 0.66)][k]
		var cv: MeshInstance3D = L.box(Vector3(33.3, 6.7 - k * 0.02, 84.6 + k * 3.6), Vector3(7.0, 0.05, 3.9), JK.cloth(pc), false)
		cv.rotation.x = 0.06 * (k - 1); cv.rotation.z = 0.08
	JK.rope(L, Vector3(30.2, 6.6, 82.6), Vector3(36.4, 6.6, 82.6), 0.4, 0.02)
	JK.bulbs(B, L, Vector3(30.2, 6.2, 93.4), Vector3(30.2, 6.2, 82.6), 0.6, 10)
	_grime(L, B, rng, [Vector2(29.0, 89.0), Vector2(33.0, 80.0), Vector2(41.0, 86.0), Vector2(27.0, 95.0), Vector2(42.0, 72.0), Vector2(35.5, 96.0)])
	# scaffold along the east side (top 2.4), with a crate step at its south end
	var sc := Vector3(37.9, 2.4, 88.0)
	L.box(sc + Vector3(0, -0.1, 0), Vector3(2.4, 0.2, 8.0), JK.mat("plank"))
	for z in [-3.8, 0.0, 3.8]:
		for x in [-1.1, 1.1]:
			L.cyl(Vector3(sc.x + x, 1.2, sc.z + z), 0.07, 0.07, 2.4, JK.mat("wood"), 6)
			L.cyl(Vector3(sc.x + x, 2.95, sc.z + z), 0.05, 0.05, 1.1, JK.mat("wood"), 6)
		B.add("beam", "scrap", JK.xform(Vector3(sc.x, 1.2, sc.z + z), Vector3(0.0, PI / 2, 0.9), Vector3(0.5, 0.5, 2.9)), Color(0.6, 0.45, 0.3))
	L.railing(sc.x + 1.15, sc.z - 4, sc.x + 1.15, sc.z + 4, 2.4)
	L.block(38.4, 93.6, 2.0, 2.4, 1.2, 0, JK.mat("rust"), false)
	L.prop("crate_small", Vector3(37.3, 2.4, 85.0), 0.5, 1.0, true)
	# hanging tools off the scaffold rail
	for i in 4:
		var hp := Node3D.new(); hp.position = Vector3(sc.x + 1.18, 3.3, sc.z - 2.6 + i * 1.6); L.add_child(hp)
		var tl := MeshInstance3D.new(); var tm := BoxMesh.new(); tm.size = Vector3(0.05, 0.55, 0.12); tl.mesh = tm
		tl.material_override = JK.mat("dark") if i % 2 else JK.mat("brass"); tl.position.y = -0.35; hp.add_child(tl)
		var hd := MeshInstance3D.new(); hd.mesh = JK.mesh("nut"); hd.material_override = tl.material_override; hd.scale = Vector3(0.18, 0.06, 0.18)
		hd.rotation.z = PI / 2; hd.position.y = -0.66; hp.add_child(hd)
		life.swing(hp, Vector3(0, 0, 0.15), 1.4 + i * 0.3, i)
	# magnet crane: lattice tower, cab, a swinging jib with a magnet holding a squashed car
	_crane(L, B, life, Vector3(42.6, 0, 76.4))
	# crane deck halfway up (double jump from the scaffold's north end): a stash
	L.block(40.2, 79.2, 3.0, 3.0, 0.4, 4.4, JK.mat("rust"), true)
	for x in [-1.3, 1.3]:
		for z in [-1.3, 1.3]:
			if x > 0 and z < 0: continue
			L.cyl(Vector3(40.2 + x, 2.2, 79.2 + z), 0.08, 0.08, 4.4, JK.mat("dark"), 6)
	L.crate_spots.append(Vector3(39.7, 4.8, 79.6))
	JK.pile(B, rng, Vector3(41.0, 4.8, 78.4), 0.7, 0.5, 10)
	for z in [78.0, 80.4]: JK.chain(B, Vector3(38.75, 4.35, z), 1.6)
	L.box(Vector3(40.2, 4.9, 80.65), Vector3(3.0, 0.2, 0.1), L.glow_warm, false)
	JK.pile(B, rng, Vector3(40.2, 0, 79.2), 1.6, 1.4, 26)
	# engine on a stand, tarps, workbench, the floodlight and piles
	var eng := Vector3(28.6, 0, 92.6)
	L.box(eng + Vector3(0, 0.45, 0), Vector3(1.4, 0.9, 1.0), JK.mat("dark"))
	L.cyl(eng + Vector3(0, 1.35, 0), 0.5, 0.55, 0.9, JK.paint(JK.ORANGE), 14).rotation.z = PI / 2
	for i in 4: L.cyl(eng + Vector3(-0.3 + i * 0.2, 1.35, 0), 0.6, 0.6, 0.05, JK.mat("dark"), 14).rotation.z = PI / 2
	L.cyl(eng + Vector3(0.7, 1.35, 0), 0.2, 0.3, 0.4, JK.mat("brass"), 10).rotation.z = PI / 2
	L.prop("workbench", Vector3(28.4, 0, 85.0), PI / 2)
	JK.tarp(L, Vector3(27.4, 0, 72.6), Vector3(3.2, 1.8, 2.4), 0.3, Color(0.3, 0.42, 0.5))
	JK.tarp(L, Vector3(44.0, 0, 97.0), Vector3(2.4, 1.4, 2.0), -0.4, Color(0.8, 0.42, 0.2))
	DocksDressing.place(L, "floodlight", Vector3(44.4, 0, 90.6), -PI / 2, 4.2, true)
	JK.omni(L, Vector3(42.0, 3.6, 89.6), Color(1.0, 0.85, 0.6), 1.5, 9.0)
	DocksDressing.place(L, "crates", Vector3(25.6, 0, 96.2), 0.3, 1.8, true)
	DocksDressing.place(L, "cable_spool", Vector3(30.0, 0, 97.2), 1.2, 1.3, true)
	DocksDressing.place(L, "hazard_barrier", Vector3(30.0, 0, 82.2), 0.1, 1.0, true)
	for h in [[Vector3(44.2, 0, 70.4), 1.8, 2.6], [Vector3(34.4, 0, 98.0), 1.6, 2.0], [Vector3(25.6, 0, 69.8), 1.5, 1.8]]:
		JK.pile(B, rng, h[0], h[1], h[2], 44)
		JK.cyl_collider(L, h[0], h[1] * 0.6, h[2] * 0.55)
		life.creaks.append(h[0] + Vector3(0, 1, 0))
	JK.litter(B, rng, HULL.grow(-0.6), 0.0, 55, [Rect2(24, 76, 6, 4), Rect2(31, 83, 10, 11), Rect2(38, 75, 6, 6)])
	JK.sign(L, "PROJECT SOMEDAY", Vector3(32.6, 0, 81.4), PI, 2.6, 0.6, 1.0, Color(1, 0.9, 0.6), Color(0.22, 0.3, 0.38))
	L.label("HULL DOCK", Vector3(28, 0, 79), 4, Color(1, 0.8, 0.55))

static func _crane(L, B, life, base: Vector3) -> void:
	var yel := Color(0.92, 0.68, 0.16)
	var h := 10.0
	L.box(base + Vector3(0, 0.3, 0), Vector3(2.4, 0.6, 2.4), JK.mat("dark"))
	JK.box_collider(L, base + Vector3(0, h / 2, 0), Vector3(1.3, h, 1.3))
	for cx in [-0.6, 0.6]:
		for cz in [-0.6, 0.6]:
			B.add("beam", "scrap", JK.xform(base + Vector3(cx, h / 2, cz), Vector3(PI / 2, 0, 0), Vector3(1, 1, h)), yel)
	var y := 0.8
	var k := 0
	while y < h - 0.6:
		for side in 4:
			var a := side * PI / 2
			var off := Vector3(sin(a), 0, cos(a)) * 0.6
			B.add("beam", "scrap", JK.xform(base + off + Vector3(0, y + 0.6, 0), Vector3((0.8 if k % 2 else -0.8), a + PI / 2, 0), Vector3(0.55, 0.55, 1.65)), yel * 0.9)
		y += 1.2; k += 1
	# turntable, cab and the jib (rotates)
	var jib := Node3D.new(); jib.position = base + Vector3(0, h, 0); L.add_child(jib)
	L.cyl(Vector3(0, 0.15, 0), 0.9, 0.9, 0.3, JK.mat("dark"), 16).reparent(jib, false)
	var cab: MeshInstance3D = L.box(Vector3(0.9, 1.0, 0.6), Vector3(1.6, 1.5, 1.5), JK.paint(yel), false, jib)
	L.box(Vector3(0, 0.1, -0.76), Vector3(1.2, 0.6, 0.03), JK.mat("window"), false, cab)
	L.box(Vector3(0, 1.0, -4.0), Vector3(0.5, 0.5, 9.0), JK.paint(yel), false, jib)
	L.box(Vector3(0, 1.0, 2.0), Vector3(0.5, 0.5, 3.0), JK.paint(yel), false, jib)
	L.box(Vector3(0, 0.6, 3.1), Vector3(1.4, 1.2, 1.0), JK.mat("dark"), false, jib)
	L.box(Vector3(0, 1.32, -4.0), Vector3(0.1, 0.1, 9.0), L.glow_warm, false, jib)
	var tip := MeshInstance3D.new(); var tm := SphereMesh.new(); tm.radius = 0.18; tm.height = 0.36; tip.mesh = tm
	tip.material_override = M.glow(Color(1, 0.3, 0.2), 5.0); tip.position = Vector3(0, 1.4, -8.4); jib.add_child(tip)
	# trolley, cable, magnet and its load
	var trolley_z := -6.4
	L.box(Vector3(0, 0.62, trolley_z), Vector3(0.7, 0.25, 0.8), JK.mat("dark"), false, jib)
	var hook := Node3D.new(); hook.position = Vector3(0, -3.4, trolley_z); jib.add_child(hook)
	var cable := MeshInstance3D.new(); var cm := CylinderMesh.new(); cm.top_radius = 0.03; cm.bottom_radius = 0.03; cm.height = 4.0
	cable.mesh = cm; cable.material_override = JK.mat("chain"); cable.position.y = 2.0; hook.add_child(cable)
	var mag := MeshInstance3D.new(); var mm := CylinderMesh.new(); mm.top_radius = 0.8; mm.bottom_radius = 0.9; mm.height = 0.45
	mag.mesh = mm; mag.material_override = JK.mat("dark"); hook.add_child(mag)
	var ring := MeshInstance3D.new(); var rm := CylinderMesh.new(); rm.top_radius = 0.82; rm.bottom_radius = 0.82; rm.height = 0.06
	ring.mesh = rm; ring.material_override = JK.mat("glow_orange"); ring.position.y = -0.25; hook.add_child(ring)
	var car := Node3D.new(); car.position = Vector3(0, -1.0, 0); car.rotation = Vector3(0.12, 0.4, -0.1); hook.add_child(car)
	L.box(Vector3(0, 0, 0), Vector3(1.5, 0.7, 2.6), JK.paint(JK.RED), false, car)
	L.box(Vector3(0, 0.45, 0.2), Vector3(1.3, 0.35, 1.2), JK.paint(JK.RED.lightened(0.2)), false, car)
	for p in [Vector3(-0.78, -0.3, 0.8), Vector3(0.78, -0.3, -0.8), Vector3(0.78, -0.3, 0.8)]:
		var w := MeshInstance3D.new(); w.mesh = JK.mesh("tire"); w.material_override = JK.mat("rubber"); w.position = p; w.rotation.z = PI / 2
		w.scale = Vector3.ONE * 0.7; car.add_child(w)
	jib.rotation.y = 0.0
	life.crane(jib, 0.75, 0.16, hook)
	life.bob(car, 0.05, 1.7)

# ---------------------------------------------------------------- Lookout (south)
static func _lookout(L, B, rng: RandomNumberGenerator, life) -> void:
	L.sky_pad(0, 117, 5, 5)
	L.moving_platform(Vector3(0, -0.3, 122.6), Vector3(0, -0.3, 128.6), 7.0, Vector3(4.5, 0.6, 4.5), "junk_lookout")
	JK.slab(L, "junk_lookout", LOOKOUT, 0.0, Color(0.9, 0.84, 0.72))
	L.checkpoints.append({ pos = Vector3(0, 0.1, 133.5), r = 2.4 })
	L.fence(LOOKOUT, 0.0, [["n", -3, 3], ["s", 1.5, 6.5]], "nsew")
	# the thinking spot: a bench facing the city, a telescope, the toaster graveyard
	L.prop("bench", Vector3(-1.2, 0, 134.6), PI)
	var tel := Node3D.new(); tel.position = Vector3(2.4, 0, 133.0); L.add_child(tel)
	for i in 3:
		var a := i * TAU / 3
		var leg := MeshInstance3D.new(); var lm := CylinderMesh.new(); lm.top_radius = 0.03; lm.bottom_radius = 0.04; lm.height = 1.5
		leg.mesh = lm; leg.material_override = JK.mat("dark"); leg.position = Vector3(cos(a) * 0.3, 0.72, sin(a) * 0.3)
		leg.rotation = Vector3(sin(a) * 0.22, 0, -cos(a) * 0.22); tel.add_child(leg)
	var tube := MeshInstance3D.new(); var tb := CylinderMesh.new(); tb.top_radius = 0.1; tb.bottom_radius = 0.15; tb.height = 1.3
	tube.mesh = tb; tube.material_override = JK.mat("brass"); tube.position = Vector3(0, 1.6, -0.2); tube.rotation.x = -1.2; tel.add_child(tube)
	var names := ["TOASTER MK I", "TOASTER MK II", "TOASTER MK III"]
	for i in 3:
		var gp := Vector3(-5.6 + i * 1.3, 0, 140.6)
		L.box(gp + Vector3(0, 0.4, 0), Vector3(0.9, 0.8, 0.16), JK.mat("rust_obj"), true).rotation.z = (i - 1) * 0.06
		var l := Label3D.new(); l.text = "R.I.P.\n" + names[i]; l.font_size = 40; l.pixel_size = 0.004; l.modulate = Color(1, 0.9, 0.7)
		l.outline_size = 8; l.position = gp + Vector3(0, 0.45, -0.09); l.rotation.y = PI; L.add_child(l)
		B.add("gear", "scrap", JK.xform(gp + Vector3(0, 0.05, -0.5), Vector3(0, i, 0), Vector3.ONE * 0.4), JK.YELLOW)
	JK.sign(L, "VESK'S THINKING SPOT. NO TALKING. NO DRONES.", Vector3(-5.0, 0, 132.4), PI, 2.8, 0.9, 1.0, Color(1.0, 0.86, 0.5), Color(0.5, 0.3, 0.18), 0.17)
	DocksDressing.place(L, "fuel_tanks", Vector3(5.4, 0, 136.4), 0.0, 2.4, true)
	L.lamp(-6.6, 132.6, Color(1, 0.72, 0.42))
	L.crate_spots.append(Vector3(-1.0, 0, 141.4))
	# the hidden ledge south of the fence gap (double jump), a stash under a little tarp roof
	var lg := Vector3(4.0, 2.4, 147.6)
	L.ledge(lg.x, lg.z, 2.6, 2.6, lg.y, JK.mat("rust"))
	L.crate_spots.append(lg + Vector3(0.3, 0, 0.3))
	JK.pile(B, rng, Vector3(-6.0, 0, 136.8), 1.4, 1.6, 30)
	JK.cyl_collider(L, Vector3(-6.0, 0, 136.8), 0.9, 0.9)
	_grime(L, B, rng, [Vector2(-3.0, 138.5), Vector2(4.0, 140.0), Vector2(-6.0, 134.0), Vector2(2.0, 132.0)])
	JK.bulbs(B, L, Vector3(-6.6, 3.2, 132.6), Vector3(7.6, 1.2, 131.4), 0.5, 12)
	L.cyl(Vector3(7.6, 0.6, 131.4), 0.05, 0.06, 1.2, JK.mat("dark"), 6)
	JK.litter(B, rng, LOOKOUT.grow(-0.6), 0.0, 22, [Rect2(-3, 131, 6, 12), Rect2(2.5, 132, 3, 3)])

# ---------------------------------------------------------------- floating junk around the rock
static func _vista(L, B, rng: RandomNumberGenerator, life) -> void:
	# scrap gulls circling over the heap and the hull dock
	var wing_m := JK.paint(Color(0.92, 0.9, 0.85))
	for g in [[Vector3(-34, 15, 86), 9.0, 0.45], [Vector3(-30, 18, 90), 13.0, -0.32], [Vector3(36, 16, 82), 10.0, 0.4]]:
		var piv := Node3D.new(); piv.position = g[0]; L.add_child(piv)
		var bird := Node3D.new(); bird.position = Vector3(g[1], 0, 0); bird.rotation.y = 0.0 if g[2] > 0 else PI; piv.add_child(bird)
		L.box(Vector3.ZERO, Vector3(0.22, 0.2, 0.7), wing_m, false, bird)
		L.box(Vector3(0, 0.02, -0.42), Vector3(0.1, 0.08, 0.16), JK.paint(JK.YELLOW), false, bird)
		for sd in [-1, 1]:
			var w := Node3D.new(); w.position = Vector3(sd * 0.1, 0.05, 0); bird.add_child(w)
			L.box(Vector3(sd * 0.55, 0, 0.05), Vector3(1.1, 0.04, 0.38), wing_m, false, w)
			life.swing(w, Vector3(0, 0, 0.5 * sd), 5.0 + rng.randf(), 0.0)
		life.spin(piv, Vector3.UP, g[2])
		life.bob(bird, 0.6, 0.8, g[1])
	for c in [Vector3(-36, -6, 118), Vector3(34, -9, 122), Vector3(-22, 4, 150), Vector3(26, 1, 146), Vector3(46, -4, 108), Vector3(-48, -3, 110)]:
		var r := rng.randf_range(2.2, 3.8)
		var rock := MeshInstance3D.new(); var cm := CylinderMesh.new(); cm.top_radius = r; cm.bottom_radius = r * 0.2; cm.height = r * 1.6; cm.radial_segments = 7
		rock.mesh = cm; rock.material_override = L.mat_dark; rock.position = c + Vector3(0, -r * 0.8, 0); L.add_child(rock)
		var top := MeshInstance3D.new(); var tm := CylinderMesh.new(); tm.top_radius = r * 0.95; tm.bottom_radius = r; tm.height = 0.4; tm.radial_segments = 7
		top.mesh = tm; top.material_override = M.worn("deck", Color(0.85, 0.75, 0.6), 0.14, 0.4, 0.65, 0.6); top.position = c + Vector3(0, 0.2, 0); L.add_child(top)
		JK.pile(B, rng, c + Vector3(0, 0.4, 0), r * 0.8, r * 0.9, 26)
		var glow := MeshInstance3D.new(); var gm := SphereMesh.new(); gm.radius = 0.3; gm.height = 0.6
		glow.mesh = gm; glow.material_override = L.glow_cyan; glow.position = c + Vector3(0, -r * 1.65, 0); L.add_child(glow)

# ---------------------------------------------------------------- traversal cases
static func traversal_cases(moves: Dictionary) -> Dictionary:
	var sj: Array = moves.sj
	var dj: Array = moves.dj
	var dj_short: Array = moves.dj_short
	var lj := [[0.0, "move_forward", true], [0.1, "dash", true], [0.15, "dash", false], [0.2, "jump", true], [0.5, "jump", false], [0.75, "move_forward", false]]
	return {
		junk_raft = [Vector3(-34.0, 0.1, 97.8), 0.0, lj, 0.0, Rect2(-37, 106, 6, 7)],
		junk_raft_back = [Vector3(-34.0, 0.1, 108.4), PI, lj, 0.0, Rect2(-40, 88, 12, 12)],
		junk_heap_1 = [Vector3(-27.5, 0.1, 80.0), 0.0, sj, 1.2, Rect2(-29, 82.5, 3, 3)],
		junk_heap_2 = [Vector3(-28.0, 1.3, 83.6), atan2(-3.0, 3.0), sj, 2.4, Rect2(-32.5, 85.1, 3, 3)],
		junk_heap_3 = [Vector3(-30.6, 2.5, 86.2), atan2(-4.0, 3.0), sj, 3.6, Rect2(-36.1, 87.7, 3, 3)],
		junk_heap_summit = [Vector3(-34.0, 3.7, 89.6), atan2(-5.6, -3.6), dj, 6.0, Rect2(-42.1, 83.5, 5, 5)],
		junk_heap_ledge = [Vector3(-41.7, 6.1, 85.2), PI, dj_short, 7.2, Rect2(-44.0, 77.9, 3.0, 3.0)],
		junk_hull_step = [Vector3(38.0, 0.1, 98.4), PI, sj, 1.2, Rect2(37.4, 92.4, 2.0, 2.4)],
		junk_hull_scaffold = [Vector3(38.0, 1.3, 94.4), PI, sj, 2.4, Rect2(36.7, 84, 2.4, 8)],
		junk_hull_deck = [Vector3(37.2, 2.5, 88.0), -PI / 2, sj, 2.3, Rect2(31.8, 84.3, 3.2, 7.4)],
		junk_hull_crane = [Vector3(38.0, 2.5, 85.0), atan2(2.2, -5.8), dj, 4.8, Rect2(38.7, 77.7, 3, 3)],
		junk_tank_1 = [Vector3(15.3, 0.1, 99.4), 0.0, sj, 1.2, Rect2(14.3, 102.6, 2, 2)],
		junk_tank_2 = [Vector3(15.3, 1.3, 102.9), 0.0, sj, 2.4, Rect2(14.5, 105.3, 2, 2.6)],
		junk_tank_top = [Vector3(15.6, 2.5, 106.8), -PI / 2, sj, 3.6, Rect2(9.6, 105.2, 4, 4)],
		junk_south_pad = [Vector3(0, 0.1, 111.0), 0.0, sj, 0.0, Rect2(-2.5, 114.5, 5, 5)],
		junk_lookout_ledge = [Vector3(4.0, 0.1, 141.0), 0.0, dj, 2.4, Rect2(2.7, 146.3, 2.6, 2.6)],
	}
