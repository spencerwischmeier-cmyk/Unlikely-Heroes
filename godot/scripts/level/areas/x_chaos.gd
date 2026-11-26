extends RefCounted
## The panic inside the areas: luggage dropped mid-run, carts shoved aside, stalls knocked flat, sky cars that
## came down hard and fires, scattered by scripts/level/layout/scatter.gd (which checks every prop against the
## real geometry once the level is loaded), plus smoke columns rising out of the city below.
## Named x_ so it runs after the spread (final coordinates) and the routes. `--no-chaos` turns it off.

const Scatter := preload("res://scripts/level/layout/scatter.gd")
const Chaos := preload("res://scripts/level/layout/chaos.gd")

static func build(L) -> void:
	if OS.get_cmdline_user_args().has("--no-chaos"): return
	var s: Node3D = Scatter.new()
	s.name = "ChaosScatter"
	s.setup(L, plan())
	L.add_child(s)
	_plumes(L)
	_junk_columns(L)

## the Junkyard is burning: volumetric smoke columns over the Scrap Heap, the Hull Dock and the Sorting Works
static func _junk_columns(L) -> void:
	var C: Node3D = Chaos.make(L, "junk_columns")
	C.center = Vector3(-5, 0, 125); C.radius = 70.0
	C.column(Vector3(-44.5, 0.0, 141.5), 1.3, 30.0, 0.22)    # behind the Scrap Heap summit
	C.column(Vector3(43.0, 0.0, 140.5), 1.1, 24.0, 0.2)      # the far corner of the Hull Dock
	C.column(Vector3(-47.5, 0.0, 106.5), 1.0, 22.0, 0.25)    # the Sorting Works' back fence
	# cloud banks drifting below the island edges give the drop some depth
	for cb in [[Vector3(-80, -22, 150), Vector3(70, 16, 50)], [Vector3(75, -26, 160), Vector3(80, 18, 60)],
			[Vector3(0, -30, 230), Vector3(110, 20, 50)], [Vector3(-60, -18, 95), Vector3(50, 12, 40)]]:
		C.cloud_bank(cb[0], cb[1])

## clusters: area, centre (final coords, y = that floor's height), radius, what to drop
static func plan() -> Array:
	var P: Array = []
	var add := func(area: String, c: Vector3, r: float, items: Array) -> void:
		P.append({ area = area, c = c, r = r, items = items })
	# Dock Plaza: where it started. Bags everywhere, carts abandoned, a sky car down in the corner
	add.call("plaza", Vector3(-14, 0, 40), 5.0, [["luggage", 9], ["luggage_cart", 1], ["cone", 2]])
	add.call("plaza", Vector3(14, 0, 20), 5.0, [["luggage", 7], ["luggage_cart", 1], ["sign_bent", 1]])
	add.call("plaza", Vector3(0, 0, 30), 9.0, [["luggage", 6], ["stall_wreck", 1], ["rubble", 1]])
	add.call("plaza", Vector3(-16, 0, 22), 5.0, [["stall_wreck", 1], ["luggage", 3], ["fire", 1]])
	add.call("plaza", Vector3(16, 0, 41), 5.0, [["skycar", 1], ["cone", 3]])
	# Market Terrace and the Bazaar: stalls flattened by the crowd, goods and bags left behind
	add.call("west", Vector3(-70, 0, 40), 6.0, [["luggage", 8], ["stall_wreck", 1], ["luggage_cart", 1]])
	add.call("west", Vector3(-66, 0, 28), 5.0, [["stall_wreck", 1], ["luggage", 3], ["fire", 1]])
	add.call("west", Vector3(-95, 0, 42), 9.0, [["stall_wreck", 2], ["luggage", 10], ["cone", 2], ["rubble", 1]])
	add.call("west", Vector3(-104, 0, 49), 5.0, [["skycar", 1], ["luggage", 2]])
	add.call("west", Vector3(-101, 3.6, 21), 6.0, [["luggage", 4], ["sign_bent", 1]])
	add.call("west", Vector3(-86, 4.8, 3), 5.0, [["luggage", 3], ["rubble", 1]])
	# Roof Gardens: picnics abandoned, one planter on fire
	add.call("west", Vector3(-60, 8.8, -5), 7.0, [["luggage", 5], ["fire", 1], ["sign_bent", 1]])
	add.call("west", Vector3(-71, 8.8, -43), 5.0, [["luggage", 3], ["rubble", 1]])
	# the Docks: the evacuation queue's overflow, cargo dropped where it was, a wreck on Pier D
	add.call("docks", Vector3(69, 0, 38), 7.0, [["luggage", 10], ["luggage_cart", 2], ["sawhorse", 2]])
	add.call("docks", Vector3(98, 0, 40), 8.0, [["luggage", 8], ["luggage_cart", 1], ["cone", 2]])
	add.call("docks", Vector3(100, 0, 18), 7.0, [["skycar", 1], ["rubble", 1], ["cone", 2]])
	add.call("docks", Vector3(128, 0, 30), 10.0, [["fire", 2], ["rubble", 2], ["cone", 3], ["sandbags", 2]])
	add.call("docks", Vector3(155, 0, 30), 8.0, [["luggage", 6], ["luggage_cart", 1]])
	add.call("docks", Vector3(88, 4.0, -8), 5.0, [["luggage", 3], ["cone", 1]])
	# Signal Mast: the gallery staff left in a hurry
	add.call("mast", Vector3(20, 8.0, -48), 6.0, [["rubble", 1], ["cone", 2], ["luggage", 2], ["sign_bent", 1]])
	add.call("mast", Vector3(34, 3.0, -48), 3.0, [["luggage", 2]])
	# Crane Yard: Grudd's crews dropped everything when the bots turned
	add.call("yard", Vector3(0, 0, -104), 12.0, [["cone", 4], ["sawhorse", 2], ["rubble", 2], ["fire", 1]])
	add.call("yard", Vector3(-44, 0, -121), 10.0, [["rubble", 2], ["cone", 3], ["fire", 1]])
	add.call("yard", Vector3(40, 0, -114), 8.0, [["sandbags", 2], ["cone", 2]])
	# Junkyard: more fires among the heaps
	add.call("junk", Vector3(0, 0, 135), 14.0, [["fire", 2], ["rubble", 2], ["cone", 2]])
	return P

## smoke columns rising out of the city far below: the whole skyline is burning somewhere
static func _plumes(L) -> void:
	var C: Node3D = Chaos.make(L, "plumes")
	for p in [Vector3(-190, -60, 60), Vector3(-150, -70, -140), Vector3(40, -65, -230), Vector3(230, -60, -60),
			Vector3(220, -70, 120), Vector3(-60, -60, 230), Vector3(90, -70, 220)]:
		C.smoke(p, 7.0, true)
	C.radius = 100000.0          # nothing to flicker, never sleeps
