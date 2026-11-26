extends RefCounted
## Market Terrace area hooks: the cliffside market build-out (scripts/level/terrace/) and its traversal cases.

static func build(L) -> void:
	preload("res://scripts/level/terrace/terrace_layout.gd").build(L)

static func traversal_cases(moves: Dictionary) -> Dictionary:
	var run2 := [[0.0, "move_forward", true], [1.4, "move_forward", false]]
	var run3 := [[0.0, "move_forward", true], [2.9, "move_forward", false]]
	# ride the loft fan straight up holding jump, then glide south onto the Chime Perch
	var fan_up := [[0.0, "jump", true], [1.2, "move_forward", true], [2.6, "move_forward", false]]
	return {
		terrace_tea_step = [Vector3(-60.0, 2.5, 22.0), -PI / 2, moves.sj, 3.6, Rect2(-80, 12, 18, 18)],
		terrace_bazaar_stairs = [Vector3(-76.75, 0.1, 40.0), PI, run2, 3.6, Rect2(-80, 12, 18, 18)],
		terrace_loft_stairs = [Vector3(-78.8, 3.7, 29.0), PI, [[0.0, "move_forward", true], [1.75, "move_forward", false]], 7.8, Rect2(-82, 13.4, 4.4, 3.6)],
		terrace_loft_bridge = [Vector3(-85.0, 7.9, 7.8), PI / 2, run3, 4.8, Rect2(-62, -3, 14, 12)],
		terrace_fan_perch = [Vector3(-93.0, 8.3, 17.4), 0.0, fan_up, 12.6, Rect2(-95.5, 21.5, 5, 4)],
		terrace_nook_bounce = [Vector3(-56.0, -3.1, 59.2), PI, [[0.0, "move_forward", true], [0.9, "move_forward", false]], 0.0, Rect2(-80, 30, 30, 24)],
	}
