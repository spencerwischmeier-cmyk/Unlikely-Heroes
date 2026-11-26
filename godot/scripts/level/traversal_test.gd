extends Node
## Debug: checks that the level's jumps, glides, hook chains and rails can be made with Vesk's real
## movement. Run headless with `-- --no-bots --no-capture --traverse=all` (or one case name); each case
## places Vesk, plays scripted input and prints PASS/FAIL with where he ended up. Added by the level
## only when the flag is given.

# name: [start, yaw, script, expect_y, expect_rect]
# script steps: [time, action, press(bool)]; "hook" presses only fire once a hook is in reach
var cases := {}
var order: Array = []
var cur := -1
var t := 0.0
var steps: Array = []
var step_i := 0
var level: Node3D
var results: Array = []
var hook_wait := false

func _ready() -> void:
	level = get_parent()
	var dj := [[0.0, "move_forward", true], [0.04, "jump", true], [0.3, "jump", false], [0.36, "jump", true], [0.5, "jump", false], [0.85, "move_forward", false]]
	var dj_short := [[0.0, "move_forward", true], [0.04, "jump", true], [0.3, "jump", false], [0.36, "jump", true], [0.5, "jump", false], [0.6, "move_forward", false]]
	var glide := [[0.0, "move_forward", true], [0.04, "jump", true], [0.3, "jump", false], [0.36, "jump", true], [1.5, "move_forward", false]]
	var sj := [[0.0, "move_forward", true], [0.04, "jump", true], [0.4, "jump", false], [0.6, "move_forward", false]]
	var hooks2 := [[0.0, "move_forward", true], [0.05, "hook", true], [0.1, "hook", false], [0.45, "hook", true], [0.5, "hook", false], [2.6, "move_forward", false]]
	var run := [[0.0, "move_forward", true], [0.6, "move_forward", false]]
	cases = {
		junk_j1 = [Vector3(-5.8, 0.1, 78.5), -PI / 2, sj, 1.2, Rect2(-11, 76.5, 4, 4)],
		junk_j2 = [Vector3(-8.6, 1.3, 77.2), atan2(-3.0, -2.6), sj, 2.4, Rect2(-14.5, 72.8, 4, 3.4)],
		junk_shelf = [Vector3(-13.6, 2.5, 73.4), atan2(-2.6, -2.8), sj, 3.6, Rect2(-17.3, 69.5, 2.2, 2.2)],
		bridge_pad1 = [Vector3(0, 0.1, 69), PI, sj, 0.0, Rect2(-2.5, 61, 5, 5)],
		tier2 = [Vector3(-48.8, 0.1, 27), -PI / 2, dj, 2.4, Rect2(-62, 14, 12, 16)],
		tier3 = [Vector3(-55, 2.5, 15.2), PI, dj, 4.8, Rect2(-62, -3, 14, 12)],
		glide_gap = [Vector3(-51, 4.9, -2.2), PI, glide, 4.0, Rect2(-54, -26, 14, 12)],
		pillar1 = [Vector3(-40.8, 4.1, -17), PI / 2, dj, 6.4, Rect2(-38.5, -18.5, 3, 3)],
		gardens_up = [Vector3(-37, 6.5, -16.2), PI * 0.0, dj, 8.8, Rect2(-40, -14, 20, 18)],
		gull_ledge = [Vector3(-38.3, 9.9, -12.3), atan2(-4.2, -4.2), dj, 11.8, Rect2(-43.8, -17.8, 2.6, 2.6)],
		hooks_gardens = [Vector3(-20.6, 8.9, -40), PI / 2, hooks2, 6.6, Rect2(0, -43, 5, 6)],
		hooks_docks = [Vector3(60.4, 6.1, -36), -PI / 2, hooks2, 3.0, Rect2(24, -40, 8, 12)],
		landing_step = [Vector3(28.0, 3.1, -31), -PI / 2, dj_short, 4.9, Rect2(25.5, -32, 2, 2)],
		landing_step2 = [Vector3(26.3, 5.0, -31.6), atan2(-1.8, -1.4), sj, 6.1, Rect2(23.4, -34.8, 2.4, 2.4)],
		gallery_up = [Vector3(24.4, 6.2, -33), -PI / 2, dj_short, 8.0, Rect2(5, -43, 18, 18)],
		ledge1 = [Vector3(17.6, 8.1, -34), PI / 2, dj, 10.4, Rect2(19.25, -35.25, 2.5, 2.5)],
		ledge2 = [Vector3(20.5, 10.5, -34.6), atan2(-1.3, 3.9), dj, 12.8, Rect2(17.94, -31.34, 2.5, 2.5)],
		ledge4_deck = [Vector3(11.67, 17.7, -27.4), PI, dj, 20.0, Rect2(10, -38, 8, 8)],
		rail_docks = [Vector3(44, 0.1, 21), PI, run, 4.0, Rect2(50, -16, 16, 16)],
		rail_docks2 = [Vector3(60, 4.1, -13), PI, run, 6.0, Rect2(60, -46, 16, 16)],
		rail_yard = [Vector3(14, 20.1, -34.5), PI, run, 0.0, Rect2(-14, -71, 28, 14)],
		rail_chute = [Vector3(-21, 8.9, -4), 0.0, run, 0.0, Rect2(-22, 14, 44, 32)],
		container_washer = [Vector3(50.6, 4.1, -4), -PI / 2, dj, 6.4, Rect2(44.5, -5.2, 5, 2.4)],
	}
	# extra cases from each area's own file: res://scripts/level/areas/<area>.gd may define
	# `static func traversal_cases(moves: Dictionary) -> Dictionary` (same format as above)
	var moves := { dj = dj, dj_short = dj_short, glide = glide, sj = sj, hooks2 = hooks2, run = run }
	for f in preload("res://scripts/level/areas.gd").files():
		var sc: Script = load(f)
		if sc.has_method("traversal_cases"): cases.merge(sc.traversal_cases(moves), true)
	var which := "all"
	for a in OS.get_cmdline_user_args(): if a.begins_with("--traverse="): which = a.substr(11)
	order = cases.keys() if which == "all" else which.split(",")
	for i in level.rails.size(): level.set_rail_locked(i, false)
	for g in level.gates.keys(): level.open_gate(g)

func _release_all() -> void:
	for a in ["move_forward", "jump", "hook", "move_left", "move_right"]: Input.action_release(a)

func _start(i: int) -> void:
	var c: Array = cases[order[i]]
	var p: CharacterBody3D = Game.player
	_release_all()
	p.riding = false; p.swing_hook = null
	p.global_position = c[0]; p.velocity = Vector3.ZERO; p.respawn_pos = c[0]
	p.face_yaw = c[1]; Game.cam.yaw = c[1]
	t = -0.4; steps = c[2]; step_i = 0

func _finish() -> void:
	var c: Array = cases[order[cur]]
	var p: CharacterBody3D = Game.player
	var pos := p.global_position
	var r: Rect2 = c[4]
	var ok: bool = r.grow(0.3).has_point(Vector2(pos.x, pos.z)) and absf(pos.y - c[3]) < 0.4
	var line := "[traverse] %s %s  end=(%.1f, %.1f, %.1f) want y=%.1f in %s" % ["PASS" if ok else "FAIL", order[cur], pos.x, pos.y, pos.z, c[3], r]
	print(line); results.append(ok)

func _physics_process(dt: float) -> void:
	if Game.player == null: return
	if cur == -1 or t > (8.0 if order[cur].begins_with("rail") or order[cur].begins_with("hooks") else 3.5):
		if cur >= 0: _finish()
		cur += 1
		if cur >= order.size():
			_release_all()
			print("[traverse] done: %d/%d passed" % [results.count(true), results.size()])
			get_tree().quit(); set_physics_process(false); return
		_start(cur)
		return
	t += dt
	if OS.get_cmdline_user_args().has("--trace") and Engine.get_physics_frames() % 6 == 0:
		var p: CharacterBody3D = Game.player
		print("   t=%.2f pos=%s vel=%s gr=%s jumps=%d" % [t, p.global_position, p.velocity, p.grounded, p.jumps])
	if t < 0.0:
		Game.player.velocity = Vector3.ZERO
		return
	while step_i < steps.size() and t >= steps[step_i][0]:
		var s: Array = steps[step_i]
		if s[1] == "hook" and s[2] and Game.player.hook_target == null:
			break   # wait until a hook is in reach
		if s[2]: Input.action_press(s[1])
		else: Input.action_release(s[1])
		step_i += 1
