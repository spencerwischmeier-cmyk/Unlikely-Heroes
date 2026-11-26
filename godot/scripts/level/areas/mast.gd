extends RefCounted
## The Signal Mast (region x 4..54, z -80..-26, up to 50). Built by scripts/level/mast/mast_build.gd on top of
## the gallery, landing, ledges, dish deck and yard rail from level_skyharbor.gd's _build_mast().

const MastBuild := preload("res://scripts/level/mast/mast_build.gd")

static func build(L) -> void:
	MastBuild.build(L)

static func traversal_cases(moves: Dictionary) -> Dictionary:
	var B := MastBuild
	var c1: Rect2 = B.C1
	var hop := [[0.0, "move_forward", true], [0.04, "jump", true], [0.12, "move_forward", false], [0.3, "jump", false]]
	var dj_shorter := [[0.0, "move_forward", true], [0.04, "jump", true], [0.3, "jump", false], [0.36, "jump", true], [0.5, "jump", false], [0.3, "move_forward", false]]
	var hop_up := [[0.0, "move_forward", true], [0.04, "jump", true], [0.4, "jump", false], [0.36, "move_forward", false]]
	return {
		# ledge 2 -> east catwalk
		mast_catwalk = [Vector3(19.8, 12.9, -29.9), PI / 2, moves.sj, B.C1_Y, c1],
		# the cable rail from the catwalk to the relay pylon
		rail_mast_cable = [Vector3(27.6, 12.9, -29.7), PI / 2, moves.run, B.P1_Y, B.P1],
		# pylon top -> two hooks -> dish deck
		hooks_mast = [B.LAUNCH + Vector3(0, 0.1, 0), atan2(-0.858, 0.514), moves.hooks2, 20.0, Rect2(10, -38, 8, 8)],
		# risky perches
		mast_perch_c1 = [Vector3(25.8, 12.9, -28.75), 0.0, hop, B.C1_Y, B.PERCH_C1],
		mast_perch_p2 = [Vector3(47.3, 23.1, -55.0), atan2(3.3, -2.9), dj_shorter, B.PERCH_P2_Y, B.PERCH_P2],
		# maintenance ring -> old fourth ledge (the way back up to the deck)
		mast_ring_ledge4 = [Vector3(11.5, B.RING_Y + 0.1, -31.2), 0.0, hop_up, 17.6, Rect2(10.42, -29.18, 2.5, 2.5)],
		# gallery -> crate -> hut roof
		mast_hut_crate = [Vector3(19.4, 8.1, -26.2), -PI / 2, hop_up, 9.6, Rect2(16.8, -27.0, 1.6, 1.6)],
	}
