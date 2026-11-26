extends RefCounted
## Cargo Docks area (east) and the distant sky world. See scripts/level/docks/ for the pieces:
##   depot.gd  Pier D's container canyon, the Freight Depot warehouse (conveyor puzzle) and the sky berth
##   sky.gd    the city towers, floating districts, cloud layers, sun shafts, airship lanes and birds
##   anim.gd   the node that moves all of it
## The piers A/B/C, the rails and the turbines stay in level_skyharbor.gd (_build_docks) and docks_dressing.gd.

const Anim := preload("res://scripts/level/docks/anim.gd")
const Depot := preload("res://scripts/level/docks/depot.gd")
const SkyWorld := preload("res://scripts/level/docks/sky.gd")

static func build(L) -> void:
	var A: Node3D = Anim.new()
	A.name = "DocksAnim"
	L.add_child(A)
	Depot.build(L, A)
	SkyWorld.build(L, A)
	# my debug spots (level._build re-assigns debug_spots after the area files run, so apply --at here too)
	var spots := { canyon = [Vector3(58, 0.1, 30), PI / 2], depot = [Vector3(87, 0.1, 39.5), PI / 2],
		berth = [Vector3(115, 0.1, 30), PI / 2], depot_in = [Vector3(88.5, 0.1, 27), PI * 0.6],
		canyon_top = [Vector3(59, 4.9, 26.2), PI * 0.6], docks_vista = [Vector3(64, 6.1, -38), PI * 0.1] }
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--at=") and spots.has(a.substr(5)):
			L.start_pos = spots[a.substr(5)][0]; L.start_yaw = spots[a.substr(5)][1]

static func traversal_cases(moves: Dictionary) -> Dictionary:
	var run_long := [[0.0, "move_forward", true], [1.6, "move_forward", false]]
	var hop := [[0.0, "move_forward", true], [0.04, "jump", true], [0.28, "move_forward", false], [0.4, "jump", false]]
	return {
		# Pier A across the gangway into the container canyon
		depot_gangway = [Vector3(46, 0.1, 30), PI / 2, run_long, 0.0, Rect2(56, 26, 10, 8)],
		# the rail from Pier D's north yard up to Pier B
		rail_depot = [Vector3(74, 0.1, 16.5), PI, moves.run, 4.0, Rect2(50, -16, 16, 16)],
		# crate step, then up onto a one-high container in corridor A
		canyon_crate = [Vector3(67.3, 0.1, 31.0), PI, moves.sj, 1.3, Rect2(66.3, 28.0, 2.0, 2.0)],
		canyon_top = [Vector3(67.3, 1.4, 28.6), PI, hop, 2.4, Rect2(62, 25, 6, 2.5)],
	}
