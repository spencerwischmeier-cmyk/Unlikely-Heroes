extends RefCounted
## The Market Terrace build-out: a stacked cliffside market on a floating sandstone rock, climbing west of the
## Dock Plaza toward the Roof Gardens. North is -z. Floors (walking height):
##   Market Terrace (0)     x -50..-28, z 24..50   the old terrace: entrance arch, stall row, sails  (level file)
##   Spice Bazaar (0)       x -80..-50, z 30..54   stalls carved into the cliff, masts, sails, lanterns
##   Tier 2 (2.4)           x -62..-50, z 14..30   double jump tutorial                               (level file)
##   Tea Terrace (3.6)      x -80..-62, z 12..30   the Rusty Kettle tea house; stairs up from the bazaar
##   Lantern Loft (7.8)     x -98..-82, z 6..20    stairs from the tea terrace, an updraft fan to the Chime Perch
##   Chime Perch (12.6)     x -95.5..-90.5, z 21.5..25.5   side pocket with sprockets
##   Loft Bridge            plank bridge from the loft down to tier 3 (4.8)
##   Tier 3 (4.8), glide gap with two updraft fans, Tier 4 (4.0)                                (level file)
##   Wash Nook (-3.2)       x -61..-51, z 55..60   laundry pocket under the bazaar edge; bounce pad back up

const TK := preload("res://scripts/level/terrace/tkit.gd")
const Life := preload("res://scripts/level/terrace/terrace_life.gd")
const MODELS := "res://models/terrace/"

static var life: Node3D

static func build(L: Node3D) -> void:
	TK.begin(L)
	life = Life.new(); life.name = "TerraceLife"; L.add_child(life)
	_islands(L)
	_rock_massif()
	_market_terrace(L)
	_bazaar(L)
	_tea_terrace(L)
	_loft(L)
	_tiers(L)
	_glide_gap(L)
	_wash_nook(L)
	_sky_lanterns()
	TK.flush()
	_spots(L)

# ------------------------------------------------------------------ islands
## a market deck: warm paving with a brass and glowing edge trim; registered with the level like island()
static func _deck(L: Node3D, name_: String, r: Rect2, y: float, thick := 1.2) -> void:
	L.islands[name_] = r; L.heights[name_] = y
	var c := r.get_center()
	TK.block(Vector3(c.x, y - thick / 2, c.y), Vector3(r.size.x, thick, r.size.y), "pave")
	for e in [[Vector3(c.x, y - 0.06, r.position.y), Vector3(r.size.x + 0.2, 0.16, 0.2)], [Vector3(c.x, y - 0.06, r.end.y), Vector3(r.size.x + 0.2, 0.16, 0.2)],
			[Vector3(r.position.x, y - 0.06, c.y), Vector3(0.2, 0.16, r.size.y)], [Vector3(r.end.x, y - 0.06, c.y), Vector3(0.2, 0.16, r.size.y)]]:
		TK.add(TK.box_mesh(), TK.mat("brass"), TK.tf(e[0], e[1]), false)
		TK.add(TK.box_mesh(), TK.mat("lantern"), TK.tf(e[0] - Vector3(0, 0.14, 0), e[1] * Vector3(1, 0.4, 1) + Vector3(0.03, 0, 0.03)), false)

static func _islands(L: Node3D) -> void:
	_deck(L, "bazaar", Rect2(-80, 30, 30, 24), 0.0, 1.2)
	_deck(L, "tea_terrace", Rect2(-80, 12, 18, 18), 3.6, 4.8)
	_deck(L, "lantern_loft", Rect2(-98, 6, 16, 14), 7.8, 1.4)
	_deck(L, "chime_perch", Rect2(-95.5, 21.5, 5, 4), 12.6, 0.8)
	_deck(L, "wash_nook", Rect2(-61, 55, 10, 5), -3.2, 0.8)
	# landing at the top of the loft stairs
	TK.block(Vector3(-79.8, 7.5, 15.2), Vector3(4.4, 0.6, 3.6), "pave")
	# a paved threshold over the old terrace's west edge strip, where the bazaar joins it
	TK.add(TK.box_mesh(), TK.mat("pave"), TK.tf(Vector3(-50, 0.0, 40), Vector3(1.4, 0.07, 20)), false)

# ------------------------------------------------------------------ the rock
static func _rock_massif() -> void:
	# big upside-down mountains under each shelf
	TK.under_rock(Vector2(-65, 42), 15.5, 12.5, -1.0, 26.0)
	TK.under_rock(Vector2(-66, 21), 15.0, 10.0, -1.0, 22.0, "rock_dark")
	TK.under_rock(Vector2(-39, 37), 11.0, 13.0, -1.0, 20.0)
	TK.under_rock(Vector2(-90, 13), 8.5, 7.5, 6.6, 12.0)
	TK.under_rock(Vector2(-55, 3), 7.0, 6.0, 3.4, 14.0)
	TK.under_rock(Vector2(-47, -20), 7.0, 6.0, 3.0, 11.0, "rock_dark")
	TK.under_rock(Vector2(-93, 23.5), 2.6, 2.2, 12.0, 5.0)
	TK.under_rock(Vector2(-56, 57.5), 5.0, 2.6, -3.8, 6.0)
	# a stack of boulders carrying the loft down into the main rock
	for i in 6:
		var y := 5.6 - i * 2.3
		var p := Vector2(-88.5 + i * 1.6, 14.5 + i * 0.6)
		TK.rock(Vector3(p.x, y, p.y), Vector3(9.0 - i * 0.4, 3.0, 8.0 - i * 0.3), i * 0.9, i % 3, "rock" if i % 2 else "rock_dark")
	# cliff faces (sandstone strata) round the tiers
	TK.cliff(Vector2(-62, 30), Vector2(-50, 30), -1.2, 2.3, Vector2(0, 1), 0.5)
	TK.cliff(Vector2(-80, 30), Vector2(-62, 30), -1.2, 3.5, Vector2(0, 1), 0.5)
	TK.cliff(Vector2(-50, 14), Vector2(-50, 24), -1.2, 2.3, Vector2(1, 0), 0.6)
	TK.cliff(Vector2(-50, 24), Vector2(-50, 30), -1.2, 2.3, Vector2(1, 0), 0.35)
	TK.cliff(Vector2(-62, 14), Vector2(-50, 14), -1.2, 2.3, Vector2(0, -1), 0.7)
	TK.cliff(Vector2(-80, 12), Vector2(-62, 12), -1.2, 3.5, Vector2(0, -1), 0.7)
	TK.cliff(Vector2(-80, 12), Vector2(-80, 30), -1.2, 3.5, Vector2(-1, 0), 0.7)
	TK.cliff(Vector2(-62, 12), Vector2(-62, 14), -1.2, 3.5, Vector2(1, 0), 0.6)
	TK.cliff(Vector2(-62, 9), Vector2(-48, 9), 0.0, 4.7, Vector2(0, 1), 0.6)
	TK.cliff(Vector2(-62, -3), Vector2(-62, 6.2), 0.0, 4.7, Vector2(-1, 0), 0.7)
	TK.cliff(Vector2(-98, 20), Vector2(-82, 20), 4.0, 7.7, Vector2(0, 1), 0.7)
	TK.cliff(Vector2(-98, 6), Vector2(-98, 20), 4.0, 7.7, Vector2(-1, 0), 0.7)
	TK.cliff(Vector2(-98, 6), Vector2(-82, 6), 4.0, 7.7, Vector2(0, -1), 0.7)
	TK.cliff(Vector2(-80, 54), Vector2(-61.6, 54), -4.0, -0.15, Vector2(0, 1), 0.9)
	TK.cliff(Vector2(-50.6, 54), Vector2(-50, 54), -4.0, -0.15, Vector2(0, 1), 0.9)
	TK.cliff(Vector2(-80, 30), Vector2(-80, 54), -4.0, -0.15, Vector2(-1, 0), 0.9)
	# ivy over the cliff edges
	TK.vines(Vector3(-80.2, 3.55, 12), Vector3(-80.2, 3.55, 30), Vector3(-1, 0, 0), 1.0)
	TK.vines(Vector3(-62, 3.55, 11.8), Vector3(-80, 3.55, 11.8), Vector3(0, 0, -1), 1.0)
	TK.vines(Vector3(-62, 2.35, 13.8), Vector3(-50, 2.35, 13.8), Vector3(0, 0, -1), 0.8)
	TK.vines(Vector3(-98, 7.75, 20.2), Vector3(-82, 7.75, 20.2), Vector3(0, 0, 1), 1.0)
	TK.vines(Vector3(-98.2, 7.75, 6), Vector3(-98.2, 7.75, 20), Vector3(-1, 0, 0), 1.0)
	TK.vines(Vector3(-80, -0.05, 54.2), Vector3(-62, -0.05, 54.2), Vector3(0, 0, 1), 0.9)
	TK.vines(Vector3(-80.2, -0.05, 30), Vector3(-80.2, -0.05, 54), Vector3(-1, 0, 0), 0.8)
	TK.vines(Vector3(-62, 4.75, 9.2), Vector3(-48, 4.75, 9.2), Vector3(0, 0, 1), 0.8)
	# moss and bushes tucked along the ledges
	for p in [Vector3(-80.6, 3.5, 13), Vector3(-80.6, 3.5, 22), Vector3(-62.5, 2.3, 13.6), Vector3(-50.4, 2.3, 15.5),
			Vector3(-98.5, 7.7, 9), Vector3(-90, 7.7, 20.6), Vector3(-80.5, -0.1, 45), Vector3(-66, -0.1, 54.8), Vector3(-62.4, 4.7, 0)]:
		TK.moss(p, 1.3)

# ------------------------------------------------------------------ the old terrace (x -50..-28, z 24..50)
static func _market_terrace(L: Node3D) -> void:
	# entrance arch from the plaza walkway
	for z in [28.6, 37.4]:
		TK.block(Vector3(-28.6, 2.6, z), Vector3(1.2, 5.2, 1.2), "plaster")
		TK.add(TK.box_mesh(), TK.mat("terracotta"), TK.tf(Vector3(-28.6, 0.4, z), Vector3(1.5, 0.8, 1.5)))
		TK.add(TK.box_mesh(), TK.mat("brass"), TK.tf(Vector3(-28.6, 5.3, z), Vector3(1.45, 0.2, 1.45)), false)
		TK.lantern(Vector3(-27.7, 3.4, z), 1.2)
		TK.add(TK.box_mesh(), TK.mat("brass"), TK.tf(Vector3(-28.0, 3.9, z), Vector3(0.9, 0.06, 0.06)), false)
	TK.add(TK.box_mesh(), TK.mat("teal"), TK.tf(Vector3(-28.6, 5.75, 33), Vector3(1.0, 0.7, 10.2)))
	TK.add(TK.box_mesh(), TK.mat("brass"), TK.tf(Vector3(-28.6, 6.2, 33), Vector3(1.15, 0.12, 10.5)), false)
	for s in [1, -1]:
		var l := Label3D.new(); l.text = "MARKET TERRACE"; l.font_size = 96; l.pixel_size = 0.009
		l.modulate = Color(1, 0.86, 0.5); l.outline_size = 14; l.outline_modulate = Color(0.15, 0.08, 0.03)
		l.position = Vector3(-28.6 + 0.52 * s, 5.75, 33); l.rotation.y = PI / 2 * s; l.double_sided = false
		TK.root.add_child(l)
	TK.bunting(Vector3(-28.6, 5.3, 28.6), Vector3(-28.6, 5.3, 37.4), 0.9)
	for z in [30.5, 33.0, 35.5]: TK.lantern(Vector3(-28.6, 4.9 - (0.3 if z == 33.0 else 0.0), z), 1.0, "lantern_red" if z == 33.0 else "lantern")
	# a row of stalls along the south rail
	TK.stall(Vector3(-43, 0, 48.4), PI, "teal", "cream", "SECONDHAND SPROCKETS", "gears")
	TK.stall(Vector3(-37.5, 0, 48.4), PI, "crimson", "saffron", "AUNTIE COG'S DUMPLINGS", "fruit")
	TK.stall(Vector3(-32, 0, 48.4), PI, "plum", "cream", "BOLTS & BROTH", "spice")
	# masts and a big sailcloth shade over the stall row
	var m1 := TK.mast(Vector3(-45.5, 0, 44.6), 6.4, "teal")
	var m2 := TK.mast(Vector3(-30.2, 0, 44.6), 6.4, "crimson")
	var b1 := Vector3(-45.5, 5.0, 49.9); var b2 := Vector3(-30.2, 5.0, 49.9)
	TK.post(b1 - Vector3(0, 5.0, 0), 5.2, 0.09, "wood_dark"); TK.post(b2 - Vector3(0, 5.0, 0), 5.2, 0.09, "wood_dark")
	TK.sail(m1, m2, b2, b1, TK.CLOTH.cream, 0.5, TK.CLOTH.saffron)
	TK.lantern_string(m1 + Vector3(0, -0.4, 0), Vector3(-28.6, 5.2, 37.4), 1.0)
	TK.lantern_string(m2 + Vector3(0, -0.4, 0), Vector3(-45.5, 4.0, 27.2), 1.4, 2.0)
	var m3 := TK.mast(Vector3(-45.5, 0, 27.2), 5.0, "saffron")
	TK.bunting(m3, Vector3(-28.6, 5.3, 28.6), 1.2)
	TK.bunting(m1, m3, 1.0)
	# north rail dressing: planters, a coin telescope, goods
	TK.tree(Vector3(-41, 0, 25.2), 2.4, "blossom")
	TK.tree(Vector3(-31, 0, 25.2), 2.2)
	_telescope(Vector3(-36, 0, 24.9), PI)
	TK.model(MODELS + "spice_goods.glb", Vector3(-48.8, 0, 43.0), 0.6, 1.5, true)
	TK.model(MODELS + "spice_goods.glb", Vector3(-29.6, 0, 42.4), -1.9, 1.3, true)
	TK.goods_heap(Vector3(-48.4, 0, 37.0), 1.2)
	TK.sign_board("TERRACE RULES: NO HAGGLING WITH GIZMART. HE ALWAYS WINS.", Vector3(-29.4, 2.4, 40.8), -PI / 2, 3.2)
	TK.post(Vector3(-29.4, 0, 40.8), 2.1, 0.07, "wood_dark")
	TK.light(Vector3(-37.5, 3.6, 46.0), Color(1, 0.72, 0.42), 2.2, 11.0)
	TK.light(Vector3(-30.0, 4.2, 33.0), Color(1, 0.75, 0.45), 1.8, 9.0)

static func _telescope(pos: Vector3, yaw: float) -> void:
	var T := Transform3D(Basis(Vector3.UP, yaw), pos)
	TK.add(TK.cyl_mesh(10), TK.mat("iron"), T * TK.tf(Vector3(0, 0.55, 0), Vector3(0.22, 1.1, 0.22)))
	TK.add(TK.cyl_mesh(12), TK.mat("brass"), T * TK.tf(Vector3(0, 1.25, 0.1), Vector3(0.36, 1.0, 0.36), Vector3(PI / 2 - 0.3, 0, 0)))
	TK.add(TK.cyl_mesh(12), TK.mat("brass"), T * TK.tf(Vector3(0, 1.38, 0.55), Vector3(0.48, 0.12, 0.48), Vector3(PI / 2 - 0.3, 0, 0)), false)
	TK.add(TK.box_mesh(), TK.mat("teal"), T * TK.tf(Vector3(0, 1.0, -0.12), Vector3(0.4, 0.3, 0.2)), false)
	TK.solid(pos + Vector3(0, 0.6, 0), Vector3(0.5, 1.2, 0.5))

# ------------------------------------------------------------------ Spice Bazaar (x -80..-50, z 30..54, y 0)
static func _bazaar(L: Node3D) -> void:
	# stairs up the cliff to the tea terrace
	TK.stairs(Vector3(-76.75, 0, 37.6), Vector3(-76.75, 3.6, 30.0), 2.5)
	TK.rail_fence(Vector3(-75.4, 0, 37.6), Vector3(-75.4, 0, 34.2))
	# stalls carved into the cliff: arches of rock round each one
	var cliff_stalls := [[-71, "saffron", "crimson", "SPICE OF LIFE", "spice"], [-66, "teal", "cream", "KITE & SAIL REPAIR", "cloth"],
		[-58.5, "green", "cream", "FRESH-ISH FRUIT", "fruit"], [-53.5, "crimson", "cream", "GEARS BY THE POUND", "gears"]]
	for s in cliff_stalls:
		TK.stall(Vector3(s[0], 0, 31.3), 0.0, s[1], s[2], s[3], s[4])
	for x in [-73.6, -68.5, -63.4, -61.0, -56.0, -51.0]:
		TK.rock(Vector3(x, 1.6, 30.7), Vector3(1.3, 3.6, 1.4), x, 0)
		TK.rock(Vector3(x, 3.5, 30.6), Vector3(1.8, 1.0, 1.5), x * 2.0, 1)
	for x in [-71, -66]:
		TK.rock(Vector3(x, 3.95, 30.5), Vector3(5.6, 0.9, 1.3), 0.0, 2, "rock_dark")
	# south row
	TK.stall(Vector3(-76.5, 0, 52.4), PI, "sky", "cream", "LOST & FOUND (MOSTLY FOUND)", "cloth")
	TK.stall(Vector3(-71, 0, 52.4), PI, "saffron", "teal", "DUMPLINGS 2 SPROCKETS", "fruit")
	TK.model(MODELS + "spice_stall.glb", Vector3(-64.5, 0, 52.2), PI, 3.6, true, 0.7)
	TK.goods_heap(Vector3(-60.0, 0, 52.8), 2.9)
	TK.goods_heap(Vector3(-52.0, 0, 52.6), 0.4, 0.9)
	TK.sign_board("WASH LINE BELOW. PLEASE DO NOT GLIDE THROUGH THE SOCKS.", Vector3(-56, 2.0, 54.2), PI, 3.6)
	for x in [-58.0, -54.0]: TK.post(Vector3(x, 0, 54.2), 2.3, 0.07, "wood_dark")
	# masts, sails, lanterns and bunting over the square
	var a := TK.mast(Vector3(-74, 0, 37.0), 7.2, "crimson")
	var b := TK.mast(Vector3(-56, 0, 37.0), 7.2, "teal")
	var c := TK.mast(Vector3(-56, 0, 48.5), 6.4, "saffron")
	var d := TK.mast(Vector3(-74, 0, 48.5), 6.4, "plum")
	var mid := Vector3(-65, 7.4, 42.8)
	TK.sail(a, (a + b) / 2 + Vector3(0, 0.6, 0), mid, (a + d) / 2, TK.CLOTH.saffron, 0.35, TK.CLOTH.cream)
	TK.sail((a + b) / 2 + Vector3(0, 0.6, 0), b, (b + c) / 2, mid, TK.CLOTH.teal, 0.35)
	TK.sail(mid, (b + c) / 2, c, (c + d) / 2 + Vector3(0, -0.3, 0), TK.CLOTH.crimson, 0.35, TK.CLOTH.cream)
	TK.sail((a + d) / 2, mid, (c + d) / 2 + Vector3(0, -0.3, 0), d, TK.CLOTH.plum, 0.35)
	TK.post(Vector3(-65, 0, 42.8), 7.4, 0.12, "wood_dark")
	TK.solid(Vector3(-65, 1.0, 42.8), Vector3(0.4, 2.0, 0.4))
	TK.lantern_string(a + Vector3(0, -1.2, 0), Vector3(-76.75, 5.2, 30.4), 0.6)
	TK.lantern_string(b + Vector3(0, -1.2, 0), Vector3(-56, 4.4, 30.4), 0.5)
	TK.lantern_string(d + Vector3(0, -1.0, 0), c + Vector3(0, -1.0, 0), 1.1)
	TK.lantern_string(c + Vector3(0, -1.0, 0), Vector3(-50.5, 4.4, 47.0), 0.8)
	TK.bunting(d + Vector3(0, -0.4, 0), Vector3(-79.6, 3.0, 53.6), 0.6)
	TK.bunting(a + Vector3(0, -0.6, 0), d + Vector3(0, -0.6, 0), 1.0)
	TK.bunting(b + Vector3(0, -0.6, 0), c + Vector3(0, -0.6, 0), 1.0)
	# the centrepiece: a spice pyramid round the big centre pole
	TK.add(TK.cyl_mesh(16), TK.mat("terracotta"), TK.tf(Vector3(-65, 0.3, 42.8), Vector3(4.2, 0.6, 4.2)))
	TK.add(TK.cyl_mesh(16), TK.mat("brass"), TK.tf(Vector3(-65, 0.62, 42.8), Vector3(4.3, 0.06, 4.3)), false)
	TK.solid(Vector3(-65, 0.3, 42.8), Vector3(3.6, 0.6, 3.6))
	for i in 6:
		var an := i * TAU / 6
		if i % 2 == 0: TK.model(MODELS + "spice_goods.glb", Vector3(-65 + cos(an) * 1.3, 0.6, 42.8 + sin(an) * 1.3), -an + PI / 2, 1.1, false)
		else: TK.spice_bowls(TK.tf(Vector3(-65 + cos(an) * 1.4, 0.62, 42.8 + sin(an) * 1.4), Vector3.ONE, Vector3(0, -an, 0)), 1.0)
	for p in [Vector3(-78.6, 0, 46), Vector3(-51.4, 0, 33.6)]: TK.tree(p, 2.6, "blossom")
	TK.tree(Vector3(-78.6, 0, 40.5), 2.2)
	for p in [Vector3(-79, 0, 50.2), Vector3(-68.2, 0, 34.6), Vector3(-61.6, 0, 46.2)]:
		TK.goods_heap(p, p.x, 0.9)
	TK.model("res://models/docks/crates.glb", Vector3(-78.8, 0, 34.0), 0.4, 1.6, true)
	# fences
	TK.rail_fence(Vector3(-80, 0, 30.2), Vector3(-80, 0, 54))
	TK.rail_fence(Vector3(-80, 0, 54), Vector3(-58, 0, 54))
	TK.rail_fence(Vector3(-54, 0, 54), Vector3(-50, 0, 54))
	TK.rail_fence(Vector3(-50, 0, 50.2), Vector3(-50, 0, 54))
	TK.light(Vector3(-65, 4.6, 36.5), Color(1, 0.72, 0.4), 2.4, 12.0)
	TK.light(Vector3(-65, 4.4, 49.0), Color(1, 0.7, 0.4), 2.2, 12.0)
	TK.light(Vector3(-76.7, 3.0, 36.0), Color(1, 0.6, 0.35), 1.6, 8.0)
	life.ambience("terrace_market", Vector3(-65, 2.0, 42), -4.0, 10.0, 50.0)

# ------------------------------------------------------------------ Tea Terrace (x -80..-62, z 12..30, y 3.6)
static func _tea_terrace(L: Node3D) -> void:
	var y := 3.6
	TK.model(MODELS + "tea_house.glb", Vector3(-71.5, y, 19.0), 0.25, 6.2, false)
	# stepped colliders that follow the walls and the domed roof, so the roof is a (secret) climb
	var tb := Basis(Vector3.UP, 0.25)
	TK.solid(Vector3(-71.5, y + 1.5, 19.0), Vector3(6.2, 3.0, 6.2), tb)
	TK.solid(Vector3(-71.5, y + 2.3, 19.0), Vector3(4.4, 4.6, 4.4), tb)
	TK.solid(Vector3(-71.5, y + 2.95, 19.0), Vector3(2.2, 5.9, 2.2), tb)
	life.kettle_pos = Vector3(-71.5, y + 5.0, 19.0)
	DocksDressing.steam(TK.root, Vector3(-70.2, y + 6.0, 19.6), 0.6)
	for i in 6:
		var an := i * TAU / 6 + 0.3
		var ch := TK.chimes(Vector3(-71.5 + cos(an) * 3.6, y + 3.5, 19.0 + sin(an) * 3.6), 0.8)
		life.add_swinger(ch, 0.14, 1.1 + i * 0.13)
	TK.tea_table(Vector3(-66.0, y, 25.8), 0.3)
	TK.tea_table(Vector3(-74.8, y, 26.0), -0.5)
	TK.tea_table(Vector3(-65.6, y, 16.0), 1.0)
	TK.tree(Vector3(-63.6, y, 13.6), 2.6, "blossom")
	TK.tree(Vector3(-63.4, y, 28.6), 2.2, "blossom")
	TK.tree(Vector3(-78.6, y, 12.9), 2.0)
	TK.sign_board("THE RUSTY KETTLE: TEA, CAKES & GOSSIP. NO BOTS (YES, DODGER, THAT MEANS YOU)", Vector3(-73.2, y + 2.3, 29.6), 0.0, 4.0)
	for x in [-75.2, -71.2]: TK.post(Vector3(x, y, 29.6), 2.0, 0.07, "wood_dark")
	# lantern strings from the tea house to the corners
	for p in [Vector3(-63, y + 3.4, 12.6), Vector3(-63, y + 3.4, 29.4), Vector3(-79.4, y + 3.4, 29.4)]:
		TK.lantern_string(Vector3(-71.5, y + 5.4, 19.0), p, 0.9)
	for p in [Vector3(-63, y, 12.6), Vector3(-63, y, 29.4), Vector3(-79.4, y, 29.4)]: TK.post(p, 3.5, 0.08, "brass")
	# stairs up to the loft (walls on both sides) and the landing
	TK.stairs(Vector3(-78.8, y, 27.2), Vector3(-78.8, 7.8, 17.2), 2.4)
	TK.ramp(Vector3(-78.8, y, 27.2), Vector3(-78.8, 7.8, 17.2), 2.4, 1.1)
	TK.rail_fence(Vector3(-77.6, 7.8, 13.4), Vector3(-77.6, 7.8, 17.0))
	TK.rail_fence(Vector3(-82, 7.8, 13.4), Vector3(-77.6, 7.8, 13.4))
	TK.rail_fence(Vector3(-82, 7.8, 17.0), Vector3(-80, 7.8, 17.0))
	# fences
	TK.rail_fence(Vector3(-80, y, 12), Vector3(-62, y, 12))
	TK.rail_fence(Vector3(-62, y, 12), Vector3(-62, y, 14))
	TK.rail_fence(Vector3(-80, y, 12), Vector3(-80, y, 17.2))
	TK.rail_fence(Vector3(-80, y, 27.2), Vector3(-80, y, 30))
	TK.rail_fence(Vector3(-75.4, y, 30), Vector3(-62, y, 30))
	# a little stair down to tier 2
	TK.stairs(Vector3(-58.4, 2.4, 26.4), Vector3(-62.0, 3.6, 26.4), 2.2)
	# cosy under-the-stairs nook (two sprockets hide here)
	TK.goods_heap(Vector3(-76.0, y, 13.4), PI / 2, 0.8)
	TK.light(Vector3(-67.5, y + 3.0, 21.0), Color(1, 0.7, 0.4), 2.0, 11.0)
	TK.light(Vector3(-74.5, y + 3.0, 25.0), Color(1, 0.65, 0.35), 1.6, 9.0)
	life.ambience("terrace_chimes", Vector3(-71.5, y + 3.0, 19.0), -8.0, 6.0, 30.0)

# ------------------------------------------------------------------ Lantern Loft (x -98..-82, z 6..20, y 7.8)
static func _loft(L: Node3D) -> void:
	var y := 7.8
	# a pergola of beams with lanterns, laundry and chimes
	var corners := [Vector3(-96.5, y, 9.8), Vector3(-85.2, y, 9.8), Vector3(-85.2, y, 15.0), Vector3(-96.5, y, 15.0)]
	for p in corners:
		TK.post(p, 4.2, 0.13, "wood_dark")
		TK.solid(p + Vector3(0, 2.1, 0), Vector3(0.3, 4.2, 0.3))
	for i in 4:
		var p: Vector3 = corners[i]; var q: Vector3 = corners[(i + 1) % 4]
		var mid2 := (p + q) / 2 + Vector3(0, 4.15, 0)
		var dd := q - p
		TK.add(TK.box_mesh(), TK.mat("wood"), TK.tf(mid2, Vector3(0.25, 0.25, dd.length() + 0.5), Vector3(0, atan2(dd.x, dd.z), 0)))
	for z in [11.5, 13.3]:
		TK.add(TK.box_mesh(), TK.mat("wood_dark"), TK.tf(Vector3(-90.85, y + 4.3, z), Vector3(11.8, 0.16, 0.16)))
	TK.laundry(Vector3(-96.3, y + 3.9, 10.0), Vector3(-85.4, y + 3.9, 10.0), 0.5)
	TK.laundry(Vector3(-96.3, y + 3.7, 14.8), Vector3(-85.4, y + 3.7, 14.8), 0.4)
	for i in 4:
		TK.lantern_string(Vector3(-96.4, y + 4.1, 10.4 + i * 1.3), Vector3(-85.3, y + 4.1, 10.4 + i * 1.3), 0.4 + 0.15 * (i % 2), 1.3)
	for p in [Vector3(-93.5, y + 3.9, 11.5), Vector3(-87.5, y + 3.9, 13.3), Vector3(-90.5, y + 3.9, 13.3), Vector3(-86.2, y + 3.9, 11.5)]:
		life.add_swinger(TK.chimes(p, 0.9), 0.16, 1.4)
	# more of the loft: blossom trees, lantern racks, paper stock, a folding table
	TK.tree(Vector3(-97.0, y, 19.0), 2.4, "blossom")
	TK.tree(Vector3(-83.4, y, 19.0), 2.0)
	TK.tree(Vector3(-94.5, y, 6.9), 2.2)
	for rp in [Vector3(-85.5, y, 17.6), Vector3(-87.5, y, 6.6)]:
		TK.post(rp + Vector3(-0.8, 0, 0), 2.4, 0.06, "wood_dark"); TK.post(rp + Vector3(0.8, 0, 0), 2.4, 0.06, "wood_dark")
		TK.add(TK.box_mesh(), TK.mat("wood"), TK.tf(rp + Vector3(0, 2.35, 0), Vector3(1.9, 0.1, 0.1)))
		for i in 4: TK.lantern(rp + Vector3(-0.6 + i * 0.4, 1.95, 0), 0.75, ["lantern", "lantern_teal", "lantern_red", "lantern"][i])
		TK.solid(rp + Vector3(0, 1.2, 0), Vector3(1.8, 2.4, 0.3))
	TK.add(TK.box_mesh(), TK.mat("wood"), TK.tf(Vector3(-90.8, y + 0.8, 12.4), Vector3(2.6, 0.1, 1.3)))
	for lp in [Vector2(-91.9, 11.9), Vector2(-89.7, 11.9), Vector2(-91.9, 12.9), Vector2(-89.7, 12.9)]:
		TK.post(Vector3(lp.x, y, lp.y), 0.78, 0.05, "wood_dark")
	for i in 6:
		var cl: String = ["saffron", "teal", "crimson", "cream", "plum", "sky"][i]
		TK.add(TK.box_mesh(), TK.mat("cloth_" + cl), TK.tf(Vector3(-91.8 + i * 0.4, y + 0.87 + (i % 2) * 0.02, 12.3 + (i % 3) * 0.12), Vector3(0.45, 0.02, 0.55), Vector3(0, i * 0.3, 0)), false)
	TK.lantern(Vector3(-90.0, y + 1.05, 12.6), 0.9, "lantern_teal")
	TK.solid(Vector3(-90.8, y + 0.45, 12.4), Vector3(2.6, 0.9, 1.3))
	TK.goods_heap(Vector3(-85.9, y, 19.2), 0.5, 0.7)
	# the lantern maker's bench and stock
	TK.add(TK.box_mesh(), TK.mat("wood"), TK.tf(Vector3(-96.6, y + 0.9, 13), Vector3(1.0, 0.1, 4.0)))
	for z in [11.3, 14.7]: TK.add(TK.box_mesh(), TK.mat("wood_dark"), TK.tf(Vector3(-96.6, y + 0.45, z), Vector3(0.9, 0.9, 0.12)))
	TK.solid(Vector3(-96.6, y + 0.5, 13), Vector3(1.0, 1.0, 4.0))
	for i in 7:
		TK.lantern(Vector3(-96.6 + (i % 2) * 0.1, y + 1.15, 11.4 + i * 0.5), 0.65, ["lantern", "lantern_red", "lantern_teal"][i % 3])
	TK.goods_heap(Vector3(-96.4, y, 17.0), 0.0, 0.8)
	TK.model("res://models/docks/crates.glb", Vector3(-97.0, y, 7.2), 0.2, 1.4, true)
	TK.sign_board("SKY LANTERNS: HAND-FOLDED, WIND-TESTED. DO NOT LICK.", Vector3(-90.85, y + 4.65, 15.1), 0.0, 4.4)
	# the updraft fan up to the Chime Perch
	_fan(Vector3(-93, y, 17.4), 1.7, y + 7.4, 8.5, 45.0, true)
	TK.sign_board("UPDRAFT: JUMP, THEN HOLD JUMP", Vector3(-89.0, y + 1.6, 19.6), 0.0, 2.6)
	TK.post(Vector3(-89.0, y, 19.6), 1.3, 0.06, "wood_dark")
	# the perch: chimes, a windsock, sprockets
	var py := 12.6
	TK.post(Vector3(-95.2, py, 25.2), 3.2, 0.08, "brass")
	TK.post(Vector3(-90.8, py, 25.2), 3.2, 0.08, "brass")
	TK.add(TK.box_mesh(), TK.mat("wood"), TK.tf(Vector3(-93, py + 3.2, 25.2), Vector3(4.8, 0.14, 0.14)))
	for x in [-94.3, -93, -91.7]: life.add_swinger(TK.chimes(Vector3(x, py + 3.05, 25.2), 0.85), 0.2, 1.7 + x * 0.01)
	TK.rail_fence(Vector3(-95.5, py, 25.5), Vector3(-90.5, py, 25.5))
	TK.rail_fence(Vector3(-95.5, py, 21.5), Vector3(-95.5, py, 25.5))
	TK.rail_fence(Vector3(-90.5, py, 21.5), Vector3(-90.5, py, 25.5))
	# fences round the loft (gaps: bridge east, stairs landing)
	TK.rail_fence(Vector3(-98, y, 6), Vector3(-82, y, 6))
	TK.rail_fence(Vector3(-98, y, 6), Vector3(-98, y, 20))
	TK.rail_fence(Vector3(-98, y, 20), Vector3(-82, y, 20))
	TK.rail_fence(Vector3(-82, y, 9.3), Vector3(-82, y, 13.4))
	TK.rail_fence(Vector3(-82, y, 17.0), Vector3(-82, y, 20))
	# the plank bridge down to tier 3
	TK.bridge(Vector3(-82.4, y, 7.8), Vector3(-61.6, 4.8, 7.8), 2.4)
	TK.post(Vector3(-82.6, y, 6.2), 4.0, 0.08, "brass")
	TK.post(Vector3(-61.4, 4.8, 6.2), 4.0, 0.08, "brass")
	TK.lantern_string(Vector3(-82.6, y + 3.9, 6.2), Vector3(-61.4, 8.7, 6.2), 1.2, 2.2)
	TK.light(Vector3(-90, y + 3.2, 13), Color(1, 0.68, 0.38), 2.2, 11.0)
	life.ambience("terrace_chimes", Vector3(-90, y + 3.5, 14), -6.0, 6.0, 30.0)
	life.ambience("terrace_fan", Vector3(-93, y + 1.0, 17.4), -10.0, 4.0, 22.0)

## an updraft fan: housing, spinning rotor, glowing core and rising wind streaks; lifts Vesk while he holds jump
static func _fan(pos: Vector3, r: float, top: float, vmax: float, accel: float, standable := false) -> void:
	TK.add(TK.cyl_mesh(20), TK.mat("iron"), TK.tf(pos + Vector3(0, 0.2, 0), Vector3(r * 2 + 0.4, 0.4, r * 2 + 0.4)))
	TK.add(TK.cyl_mesh(20), TK.mat("cyan"), TK.tf(pos + Vector3(0, 0.27, 0), Vector3(r * 2 - 0.1, 0.3, r * 2 - 0.1)), false)
	var tor := TorusMesh.new(); tor.inner_radius = r; tor.outer_radius = r + 0.28; tor.rings = 24; tor.ring_segments = 8
	TK.add(tor, TK.mat("brass"), TK.tf(pos + Vector3(0, 0.42, 0), Vector3(1, 1.4, 1)))
	for i in 4:
		TK.add(TK.box_mesh(), TK.mat("iron"), TK.tf(pos + Vector3(0, 0.48, 0), Vector3(r * 2, 0.06, 0.08), Vector3(0, i * PI / 4, 0)), false)
	var rotor := Node3D.new(); rotor.position = pos + Vector3(0, 0.36, 0); TK.root.add_child(rotor)
	for i in 5:
		var bl := MeshInstance3D.new(); bl.mesh = TK.box_mesh(); bl.material_override = TK.mat("teal")
		bl.basis = Basis(Vector3.UP, i * TAU / 5) * Basis(Vector3.RIGHT, 0.45) * Basis.from_scale(Vector3(r * 0.95, 0.04, 0.42))
		bl.position = Basis(Vector3.UP, i * TAU / 5) * Vector3(r * 0.48, 0, 0)
		rotor.add_child(bl)
	var hub := MeshInstance3D.new(); hub.mesh = TK.sphere_mesh(); hub.material_override = TK.mat("brass"); hub.scale = Vector3(0.5, 0.3, 0.5)
	rotor.add_child(hub)
	if standable: TK.solid(pos + Vector3(0, 0.2, 0), Vector3(r * 2 + 0.3, 0.4, r * 2 + 0.3))
	# a column of rising air and wind streaks
	var col := CylinderMesh.new(); col.top_radius = r * 1.05; col.bottom_radius = r * 0.9; col.height = top - pos.y - 0.4
	col.cap_top = false; col.cap_bottom = false; col.radial_segments = 20
	var cm := MeshInstance3D.new(); cm.mesh = col; cm.material_override = TK.mat("wind_column")
	cm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; cm.position = pos + Vector3(0, 0.4 + col.height / 2, 0)
	TK.root.add_child(cm)
	var p := CPUParticles3D.new()
	var q := QuadMesh.new(); q.size = Vector2(0.07, 1.6); p.mesh = q
	p.material_override = TK.mat("wind")
	p.amount = 36; p.lifetime = (top - pos.y) / 8.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX; p.emission_box_extents = Vector3(r * 0.85, 0.1, r * 0.85)
	p.direction = Vector3.UP; p.spread = 4.0; p.gravity = Vector3.ZERO
	p.initial_velocity_min = 7.0; p.initial_velocity_max = 10.0
	p.scale_amount_min = 0.6; p.scale_amount_max = 1.3
	var ramp := Gradient.new(); ramp.set_color(0, Color(0.8, 1, 1, 0.0)); ramp.add_point(0.2, Color(0.8, 1, 1, 0.55)); ramp.set_color(2, Color(0.8, 1, 1, 0.0))
	p.color_ramp = ramp
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.position = pos + Vector3(0, 0.6, 0)
	p.visibility_aabb = AABB(Vector3(-r * 2, -1, -r * 2), Vector3(r * 4, top - pos.y + 3, r * 4))
	TK.root.add_child(p)
	TK.light(pos + Vector3(0, 1.0, 0), Color(0.35, 0.95, 1.0), 1.6, 6.0)
	life.add_fan(pos, r + 0.3, top, vmax, accel, rotor)

# ------------------------------------------------------------------ tiers 2-4
static func _tiers(L: Node3D) -> void:
	# tier 2 (2.4): crates, a lantern line across to the tea terrace, laundry high over the chasm
	TK.goods_heap(Vector3(-52.6, 2.4, 15.6), 0.3, 0.9)
	TK.post(Vector3(-50.6, 2.4, 14.6), 4.0, 0.08, "brass")
	TK.post(Vector3(-50.6, 4.8, 8.4), 5.0, 0.08, "brass")
	TK.laundry(Vector3(-50.6, 9.6, 8.4), Vector3(-50.6, 6.2, 14.6), 0.5)
	TK.lantern_string(Vector3(-50.6, 6.3, 14.6), Vector3(-63, 7.0, 29.4), 0.8)
	# tier 3 (4.8): a windsock mast at the gap and a sign about the fans
	var ws := TK.mast(Vector3(-48.8, 4.8, 8.2), 4.6, "crimson")
	var sock := TK.cyl_mesh(10)
	var sn := Node3D.new(); sn.position = ws + Vector3(0, -0.1, 0); TK.root.add_child(sn)
	for i in 4:
		var sm := MeshInstance3D.new(); sm.mesh = sock; sm.material_override = TK.mat("cloth_" + ("crimson" if i % 2 == 0 else "cream"))
		sm.scale = Vector3(0.56 - i * 0.08, 0.42, 0.56 - i * 0.08); sm.rotation.x = PI / 2; sm.position = Vector3(0, 0, -0.25 - i * 0.42)
		sn.add_child(sm)
	life.add_swinger(sn, 0.18, 0.9)
	TK.sign_board("UPDRAFT FANS AHEAD: GLIDE OVER THEM AND RIDE THE WIND", Vector3(-58.5, 6.5, -2.6), PI, 3.6)
	for x in [-60.2, -56.8]: TK.post(Vector3(x, 4.8, -2.6), 1.7, 0.07, "wood_dark")
	TK.goods_heap(Vector3(-60.6, 4.8, 3.0), 1.4, 0.9)
	TK.tree(Vector3(-49.4, 4.8, 6.6), 2.0, "blossom")
	# tier 4 (4.0): lantern posts and a fan mechanic's stand
	TK.post(Vector3(-53.2, 4.0, -14.8), 5.2, 0.08, "brass")
	TK.post(Vector3(-40.8, 4.0, -14.8), 5.2, 0.08, "brass")
	TK.lantern_string(Vector3(-53.2, 9.0, -14.8), Vector3(-40.8, 9.0, -14.8), 0.6)
	TK.stall(Vector3(-44.5, 4.0, -24.4), 0.0, "teal", "saffron", "FAN PARTS & FIBS", "gears")
	TK.goods_heap(Vector3(-41.4, 4.0, -24.6), 0.8, 0.8)
	TK.light(Vector3(-47, 7.0, -18.5), Color(1, 0.7, 0.4), 1.8, 10.0)

# ------------------------------------------------------------------ the glide gap fans
static func _glide_gap(L: Node3D) -> void:
	for z in [-6.6, -10.8]:
		_fan(Vector3(-51, 2.0, z), 1.9, 6.8, 1.6, 26.0)
		TK.add(TK.rock_mesh(3), TK.mat("rock"), TK.tf(Vector3(-51, -2.2, z), Vector3(5.2, 8.4, 5.2), Vector3(0, z, 0)))
		TK.rock(Vector3(-51, 1.4, z), Vector3(5.0, 1.4, 5.0), z * 3.0, 1)
		TK.moss(Vector3(-51, 2.0, z), 2.2)
	life.ambience("terrace_fan", Vector3(-51, 2.0, -8.7), -8.0, 5.0, 30.0)

# ------------------------------------------------------------------ Wash Nook (x -61..-51, z 55..60, y -3.2)
static func _wash_nook(L: Node3D) -> void:
	var y := -3.2
	for x in [-60.4, -51.6]: TK.post(Vector3(x, y, 59.4), 3.0, 0.08, "wood_dark")
	TK.laundry(Vector3(-60.4, y + 2.9, 59.4), Vector3(-51.6, y + 2.9, 59.4), 0.5)
	TK.add(TK.cyl_mesh(14), TK.mat("wood_dark"), TK.tf(Vector3(-59.4, y + 0.45, 56.4), Vector3(1.4, 0.9, 1.4)))   # wash tub
	TK.add(TK.cyl_mesh(14), TK.mat("cyan"), TK.tf(Vector3(-59.4, y + 0.86, 56.4), Vector3(1.2, 0.04, 1.2)), false)
	TK.solid(Vector3(-59.4, y + 0.45, 56.4), Vector3(1.3, 0.9, 1.3))
	TK.goods_heap(Vector3(-52.4, y, 56.0), 0.0, 0.8)
	TK.rail_fence(Vector3(-61, y, 60), Vector3(-51, y, 60))
	TK.rail_fence(Vector3(-61, y, 55), Vector3(-61, y, 60))
	TK.rail_fence(Vector3(-51, y, 55), Vector3(-51, y, 60))
	L.bounce_pad(Vector3(-56, y, 57.6), 16.0)
	TK.sign_board("BOING HOME", Vector3(-56, y + 1.6, 59.7), PI, 1.8)
	TK.post(Vector3(-56, y, 59.75), 1.3, 0.06, "wood_dark")
	TK.light(Vector3(-56, y + 2.0, 57.0), Color(1, 0.7, 0.4), 1.5, 7.0)

# ------------------------------------------------------------------ sky lanterns drifting up
static func _sky_lanterns() -> void:
	# kites tethered to the market, bobbing in the wind
	for k in [[Vector3(-79.6, 1.0, 52.6), Vector3(-90, 17, 64), "crimson", "saffron"], [Vector3(-50.6, 2.4, 14.8), Vector3(-44, 16, 4), "teal", "cream"],
			[Vector3(-96.8, 7.8, 19.6), Vector3(-108, 21, 28), "plum", "saffron"]]:
		var kn := Node3D.new(); kn.position = k[1]; TK.root.add_child(kn)
		for i in 2:
			var km := MeshInstance3D.new(); km.mesh = TK.pennant_mesh(); km.material_override = TK.mat("cloth_" + (k[2] if i == 0 else k[3]))
			km.scale = Vector3(1.6, 1.3 if i == 0 else 0.5, 1); km.rotation.z = 0.0 if i == 0 else PI
			kn.add_child(km)
		for j in 4:
			var tail := MeshInstance3D.new(); tail.mesh = TK.pennant_mesh(); tail.material_override = TK.mat("cloth_" + k[3])
			tail.scale = Vector3(0.3, 0.3, 1); tail.position = Vector3(0, -1.6 - j * 0.45, 0); tail.rotation.z = PI
			kn.add_child(tail)
		kn.look_at_from_position(k[1], k[0], Vector3.UP)
		life.add_swinger(kn, 0.25, 0.8)
		TK.rope(k[0], k[1] + Vector3(0, -0.6, 0), 2.0, 10, 0.012)
	# a goods basket on a pulley, going up and down between the bazaar and the tea terrace
	TK.post(Vector3(-79.3, 3.6, 29.5), 4.4, 0.1, "wood_dark")
	TK.add(TK.box_mesh(), TK.mat("wood"), TK.tf(Vector3(-79.3, 7.9, 30.4), Vector3(0.2, 0.2, 2.0)))
	TK.add(TK.cyl_mesh(12), TK.mat("brass"), TK.tf(Vector3(-79.3, 7.75, 31.2), Vector3(0.5, 0.12, 0.5), Vector3(PI / 2, 0, 0)), false)
	var basket := Node3D.new(); basket.position = Vector3(-79.3, 1.8, 31.2); TK.root.add_child(basket)
	var bm := MeshInstance3D.new(); bm.mesh = TK.cyl_mesh(10); bm.material_override = TK.mat("wood"); bm.scale = Vector3(0.9, 0.6, 0.9); basket.add_child(bm)
	for i in 3:
		var fr := MeshInstance3D.new(); fr.mesh = TK.sphere_mesh(); fr.material_override = TK.mat(["spice_orange", "spice_green", "spice_red"][i])
		fr.scale = Vector3.ONE * 0.32; fr.position = Vector3(cos(i * 2.1) * 0.2, 0.35, sin(i * 2.1) * 0.2); basket.add_child(fr)
	TK.add(TK.cyl_mesh(5), TK.mat("rope"), TK.tf(Vector3(-79.3, 4.6, 31.2), Vector3(0.03, 6.3, 0.03)), false)
	var tw := basket.create_tween().set_loops()
	tw.tween_interval(3.0)
	tw.tween_property(basket, "position:y", 4.4, 4.0).set_trans(Tween.TRANS_SINE)
	tw.tween_interval(3.0)
	tw.tween_property(basket, "position:y", 1.8, 4.0).set_trans(Tween.TRANS_SINE)
	var bases := [Vector3(-92, 9, 12), Vector3(-66, 2, 45), Vector3(-72, 6, 20), Vector3(-100, 6, 26), Vector3(-58, 1, 60), Vector3(-84, 3, 40)]
	for i in bases.size():
		var n := Node3D.new(); TK.root.add_child(n)
		var body := MeshInstance3D.new(); body.mesh = TK.sphere_mesh(); body.material_override = TK.mat("lantern" if i % 2 == 0 else "lantern_red")
		body.scale = Vector3(0.55, 0.7, 0.55); n.add_child(body)
		life.floaters.append({ node = n, base = bases[i], phase = i / float(bases.size()), rise = 1.0 / 46.0 })

# ------------------------------------------------------------------ gameplay spots
static func _spots(L: Node3D) -> void:
	for p in [Vector3(-79.0, 0, 31.4), Vector3(-52.4, 0, 40.0), Vector3(-91.5, 7.8, 7.2), Vector3(-63.4, 3.6, 22.6), Vector3(-42.0, 4.0, -21.0)]:
		L.crate_spots.append(p)
	var sp: Array = []
	for i in 6: sp.append(Vector3(-93 + cos(i * TAU / 6) * 1.3, 13.5, 23.5 + sin(i * TAU / 6) * 1.2))   # chime perch
	for y in [10.0, 11.8, 13.6]: sp.append(Vector3(-93, y, 17.4))                                         # loft updraft
	for z in [-6.6, -8.7, -10.8]: sp.append(Vector3(-51, 7.0, z))                                         # glide gap updraft
	for x in [-59.5, -57.5, -55.5, -53.5]: sp.append(Vector3(x, -2.3, 58.2))                              # wash nook
	for z in [14.8, 16.2]: sp.append(Vector3(-79.0, 4.5, z))                                              # under the loft stairs
	sp.append(Vector3(-79.2, 0.9, 32.6))                                                                  # behind the bazaar stairs
	for i in 4: sp.append(Vector3(-71.5 + cos(i * TAU / 4 + 0.6) * 0.9, 10.4, 19.0 + sin(i * TAU / 4 + 0.6) * 0.9))  # tea house roof                                                                  # behind the bazaar stairs
	for p in sp: life.add_sprocket(p)
	life.triggers = [
		{ rect = Rect2(-80, 12, 18, 18), y = 3.6, ids = ["terrace_tea_1", "terrace_tea_2"] },
		{ rect = Rect2(-97, 14, 8, 6), y = 7.8, ids = ["terrace_fan_1"] },
		{ rect = Rect2(-95.5, 21.5, 5, 4), y = 12.6, ids = ["terrace_perch_1"] },
		{ rect = Rect2(-61, 55, 10, 5), y = -3.2, ids = ["terrace_nook_1"] },
	]
	var spots := {
		bazaar = [Vector3(-65, 0.1, 47), PI], tea = [Vector3(-66, 3.7, 28), -2.6], loft = [Vector3(-84.5, 7.9, 12), -PI / 2],
		market = [Vector3(-25, 0.1, 33), -PI / 2], fans = [Vector3(-49.5, 4.1, -20.5), 0.15], perch = [Vector3(-93, 12.7, 23.5), PI], roof = [Vector3(-78.6, 7.9, 15.6), PI / 2], nook = [Vector3(-56, -3.1, 56.0), 0.0],
	}
	for k in spots: L.debug_spots["terrace_" + k] = spots[k]
	# debug_spots is filled after the area files run, so honour --at=terrace_* here
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--at=terrace_") and spots.has(a.substr(13)):
			var s: Array = spots[a.substr(13)]
			L.start_pos = s[0]; L.start_yaw = s[1]
