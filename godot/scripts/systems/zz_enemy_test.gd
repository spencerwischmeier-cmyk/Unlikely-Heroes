extends Node
## Enemy / boss test harness. Does nothing unless the game is started with `-- --enemy-test[=mode]`
## (add --no-bots so the story doesn't run alongside). Modes:
##   boss    (default) Vesk at the Crane Yard arena entrance, the Crane Bot drops in
##   boss2   as boss, then knocks it to 50% after the intro: watch the jib rip and phase 2
##   crew    a Work Crew of three marches at Vesk in the empty arena and builds barricades
##   bots    Scrap Rollers and Tin Hornets in the arena
##   mix     a Work Crew plus two Scrap Rollers and a Tin Hornet
##   tour    the whole boss fight in order: intro, a magnet slam, the phase change, a jib sweep that
##           Vesk double-jumps over, then a ride up the track rail into the cab (good with --et-snap)
## Extra flags:
##   --et-force=<attack>  boss always picks this attack (slam, spray, crew, sweep)
##   --et-god             Vesk's hull is refilled every frame
##   --et-grind           (phase 2) put Vesk on the track rail each time it unlocks: tests the cab strike
##   --et-wrench          Vesk wrenches any roller that gets close (tests Return to Sender)
##   --et-kill            chips the boss down steadily (tests the phase change and death)
##   --et-fast            allow many physics steps per rendered frame (slow software renders reach the
##                        interesting part sooner)
##   --et-skip1           tour: skip the phase 1 slam and go straight to the phase change
##   --et-cam             a fixed overview camera on the fight (for screenshots)
##   --et-jump            Vesk double-jumps over the sweeping jib (on in tour mode)
##   --et-bot             a simple autoplayer fights: aims at the nearest bot, fires, strafes, dashes away
##                        from fusing rollers and locked-on hornets, wrenches rollers that get close
##   --et-secs=<s>        quit after s game seconds (headless runs default to 240) with a summary line
##   --et-stay            don't quit by itself when the fight is over
##   --et-snap=a@t,b@t    save a screenshot t seconds into each boss state a, b... to --et-out=<prefix>
##                        (<prefix>_<state>.png), then quit after the last one. Needs a rendering run.
## Prints "[enemy-test]" lines for boss state changes, hits on Vesk and kills.

const CraneBot := preload("res://scripts/cranebot.gd")

var mode := ""
var flags := {}
var boss: Node3D
var last := ""
var n := 0
var cam: Camera3D
var kill_t := 0.0
var grind_done := 0.0
var arena := Rect2()
var state_t := 0.0
var snaps: Array = []        # [state, delay, taken]
var snapping := false
var seen := {}
var jump_phase := 0
var kills := 0
var hurts := 0

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--enemy-test": mode = "boss"
		elif a.begins_with("--enemy-test="): mode = a.substr(13)
		elif a.begins_with("--et-"):
			var kv := a.substr(5).split("=")
			flags[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if mode == "":
		set_physics_process(false); set_process(false)
		return
	if mode == "tour": flags["god"] = "1"; flags["jump"] = "1"
	if flags.has("fast"): Engine.max_physics_steps_per_frame = 30
	if flags.has("snap"):
		for part in String(flags.snap).split(","):
			var kv := part.split("@")
			snaps.append([kv[0], float(kv[1]) if kv.size() > 1 else 0.5, false])
	print("[enemy-test] mode ", mode, " flags ", flags)
	Game.player_hurt.connect(func(h): hurts += 1; print("[enemy-test] vesk hurt, hull ", h, " t=", snappedf(float(n) / Engine.physics_ticks_per_second, 0.01)))
	Game.bot_killed.connect(func(b, _p, k): kills += 1; print("[enemy-test] killed ", k, " returned_to_sender=", b.get_meta("returned_to_sender", false)))
	Game.slam_landed.connect(func(hit): print("[enemy-test] slam landed hit=", hit, " t=", snappedf(float(n) / Engine.physics_ticks_per_second, 0.01)))
	Game.close_call.connect(func(): print("[enemy-test] close call t=", snappedf(float(n) / Engine.physics_ticks_per_second, 0.01)))
	Game.boss_health.connect(func(nm, f): print("[enemy-test] boss_health ", nm, " ", snappedf(f, 0.01)))
	_setup.call_deferred()

func _setup() -> void:
	arena = Game.level.islands.get("arena", Rect2(-18, -112, 36, 30))
	var c := arena.get_center()
	_place_player(Vector3(c.x, 0.1, arena.end.y - 3.0), PI)
	if mode == "tour": _place_player(Vector3(c.x + 3.5, 0.1, c.y + 3.0), PI)
	match mode:
		"boss", "boss2", "tour":
			boss = CraneBot.new(); boss.combat = Game.combat; boss.player = Game.player
			boss.spawn_roller = func(p: Vector3): Game.main.spawn_bot("roller", p, arena)
			Game.main.add_child(boss)
			boss.spawn(Vector3(c.x, 0, c.y - 5.0), arena)
			if flags.has("force"): boss.force_next = flags.force
			if mode == "tour": boss.force_next = "slam"
			Game.boss_started.emit("CRANE BOT")
		"crew", "mix":
			Game.main.spawn_bot("crew", Vector3(c.x, 0, c.y - 10.0), arena)
			if mode == "mix":
				for i in 2: Game.main.spawn_bot("roller", Vector3(c.x - 6 + i * 12, 0, c.y + 4), arena)
				Game.main.spawn_bot("hornet", Vector3(c.x + 6, 0, c.y), arena)
		"bots":
			for i in 3: Game.main.spawn_bot("roller", Vector3(c.x - 5 + i * 5, 0, c.y - 4), arena)
			for i in 2: Game.main.spawn_bot("hornet", Vector3(c.x - 4 + i * 8, 0, c.y - 8), arena)

## Ends the run (exit code 0) once the fight is over: the boss gone after dying, or every bot and crew
## cleared. A time cap (--et-secs, 240 s by default when headless) ends it too, with exit code 0 as long
## as no script went wrong; the summary line says which.
func _check_done() -> void:
	if snaps.size() > 0 or flags.has("stay"): return
	var t := float(n) / Engine.physics_ticks_per_second
	var cap := float(flags.get("secs", "240" if DisplayServer.get_name() == "headless" else "0"))
	var why := ""
	if boss:
		if not is_instance_valid(boss) or (seen.has("dying") and boss.state == "off"): why = "boss defeated"
	elif mode in ["crew", "mix", "bots"] and t > 2.0:
		if get_tree().get_nodes_in_group("bots").filter(func(b): return not b.dead).is_empty() \
				and get_tree().get_nodes_in_group("crews").is_empty():
			why = "all bots cleared"
	if why == "" and cap > 0.0 and t >= cap: why = "time cap"
	if why == "": return
	print("[enemy-test] done (%s) t=%.2f kills %d vesk hits %d" % [why, t, kills, hurts])
	set_physics_process(false)
	get_tree().quit.call_deferred(0)

func _place_player(p: Vector3, yaw: float) -> void:
	var pl := Game.player
	pl.global_position = p; pl.velocity = Vector3.ZERO; pl.respawn_pos = p
	pl.face_yaw = yaw; Game.cam.yaw = yaw

func _physics_process(dt: float) -> void:
	n += 1
	_check_done()
	if flags.has("god") and Game.combat: Game.combat.hull = Game.combat.MAX_HULL
	if boss and is_instance_valid(boss):
		var s := "%s p%d" % [boss.state, boss.phase]
		state_t += dt
		if s != last:
			last = s; state_t = 0.0; seen[boss.state] = true
			print("[enemy-test] t=%.2f boss %s hp %.0f" % [float(n) / Engine.physics_ticks_per_second, s, boss.hp])
		if mode == "boss2" and boss.phase == 1 and boss.state == "idle" and boss.hp > boss.BOSS_HP * 0.5:
			boss._hurt(boss.hp - boss.BOSS_HP * 0.5 + 1.0)
		if mode == "tour": _tour()
		if flags.has("jump") and boss.state in ["sweep", "sweep_end"]: _jump_over()
		elif jump_phase != 0: jump_phase = 0; Input.action_release("jump")
		if flags.has("kill") and boss.state not in ["off", "intro", "rip", "dying"]:
			kill_t -= dt
			if kill_t <= 0.0: kill_t = 0.25; boss.damage(4.0, boss.center(), Vector3.ZERO)
		if flags.has("grind") and boss.phase == 2 and not boss.rail.locked and not Game.player.riding and boss.state in ["idle", "spray", "crew"]:
			grind_done -= dt
			if grind_done <= 0.0:
				grind_done = 3.0
				var r: Dictionary = boss.rail
				var p0: Vector3 = r.path.to_global(r.curve.sample_baked(0.3))
				var p1: Vector3 = r.path.to_global(r.curve.sample_baked(1.3))
				Game.player.global_position = p0 + Vector3(0, 0.1, 0)
				Game.player.velocity = (p1 - p0).normalized() * 13.0
				Game.player.rail_cool = 0.0
				print("[enemy-test] put vesk on the track rail")
		if flags.has("cam"): _overview(boss.global_position)
	elif flags.has("cam"):
		_overview(Vector3(arena.get_center().x, 0, arena.get_center().y - 6))
	for c in get_tree().get_nodes_in_group("crews"):
		var cs := "%s %d/%d builds %d barricades %d" % [c.state, c.members.size(), 3, c.builds, c.barricades.size()]
		if c.get_meta("et_last", "") != cs:
			c.set_meta("et_last", cs); print("[enemy-test] t=%.2f crew %s" % [float(n) / Engine.physics_ticks_per_second, cs])
	if flags.has("bot"): _autoplay(dt)
	if flags.has("stomp"):
		stomp_t -= dt
		if stomp_t <= 0.0:
			stomp_t = 2.5
			for b in get_tree().get_nodes_in_group("bots"):
				if not b.dead and b.has_method("_launch") and b.state == "chase":
					print("[enemy-test] drop vesk on a roller, hp ", b.hp)
					Game.player.global_position = b.global_position + Vector3(0, 3.5, 0); Game.player.velocity = Vector3.ZERO
					break
	if flags.has("wrench"):
		for b in get_tree().get_nodes_in_group("bots"):
			if b.dead or not b.has_method("_launch"): continue
			var d: Vector3 = b.global_position - Game.player.global_position
			if Vector2(d.x, d.z).length() < 2.4 and absf(d.y) < 1.0 and b.state != "drop":
				var face := Vector3(d.x, 0, d.z).normalized()
				Game.combat.melee(Game.player.global_position, face)
				print("[enemy-test] wrenched a roller")
				break

var stomp_t := 3.0
var ap_strafe := 1.0
var ap_strafe_t := 0.0
var ap_dash_cd := 0.0
var ap_slam := 0
var ap_slam_t := 0.0
func _ap_hold(a: String, on: bool) -> void:
	if on and not Input.is_action_pressed(a): Input.action_press(a)
	elif not on and Input.is_action_pressed(a): Input.action_release(a)

func _autoplay(dt: float) -> void:
	var pl := Game.player
	var pp := pl.global_position
	var best: Node3D = null
	var bd := INF
	var threat := false
	for b in get_tree().get_nodes_in_group("bots"):
		if b.dead: continue
		var d: float = (b.global_position - pp).length()
		if d < bd: bd = d; best = b
		if b.get("state") == "fuse" and d < 3.2: threat = true
		if b.get("aiming") and float(b.get("fire_t")) < 0.3: threat = true
	if best == null and boss and is_instance_valid(boss) and not boss.dead and boss.state not in ["off", "intro", "dying"]:
		best = boss; bd = (boss.global_position - pp).length()
	if best == null:
		for a in ["fire", "move_left", "move_right", "move_back", "move_forward", "dash", "melee"]: _ap_hold(a, false)
		return
	var to: Vector3 = (best.center() - Game.cam.camera.global_position).normalized()
	var k := 1.0 - exp(-7.0 * dt)
	Game.cam.yaw += angle_difference(Game.cam.yaw, atan2(to.x, to.z)) * k
	Game.cam.pitch = lerpf(Game.cam.pitch, asin(clampf(to.y, -1, 1)), k)
	_ap_hold("fire", not flags.has("dodge") and not flags.has("slam"))
	ap_strafe_t -= dt
	if ap_strafe_t <= 0.0: ap_strafe_t = randf_range(1.2, 2.6); ap_strafe = -ap_strafe
	_ap_hold("move_left", ap_strafe < 0.0); _ap_hold("move_right", ap_strafe > 0.0)
	var roller_close: bool = best.has_method("_launch") and bd < 5.0
	_ap_hold("move_back", roller_close and best.get("state") != "fuse")
	ap_dash_cd -= dt
	_ap_hold("dash", false)
	# --et-dodge: dash just as an enemy shot is about to arrive (exercises the close-call dodge)
	if flags.has("dodge"):
		threat = false
		for sh in Game.combat.shots:
			var to_me: Vector3 = pp + Vector3(0, 0.9, 0) - sh.node.global_position
			if to_me.length() < 3.0 and to_me.dot(sh.vel) > 0.0: threat = true
	if threat and ap_dash_cd <= 0.0: Input.action_press("dash"); ap_dash_cd = 0.7
	# --et-slam: every few seconds near a ground bot: jump, double jump, slam down onto it
	if flags.has("slam"):
		ap_slam_t -= dt
		match ap_slam:
			0:
				if ap_slam_t <= 0.0 and pl.grounded and bd < 6.0 and best.has_method("_launch"): Input.action_press("jump"); ap_slam = 1; ap_slam_t = 0.35
			1:
				if ap_slam_t <= 0.0: Input.action_release("jump"); Input.action_press("jump"); ap_slam = 2; ap_slam_t = 0.3
			2:
				if pl.velocity.y < 0.0:
					Input.action_release("jump"); Input.action_press("melee"); ap_slam = 3; ap_slam_t = 0.1
					print("[enemy-test] slam press, height %.1f" % pl._air_height())
			3:
				if ap_slam_t <= 0.0: Input.action_release("melee"); ap_slam = 0; ap_slam_t = 3.0
		return
	_ap_hold("melee", best.has_method("_launch") and bd < 2.3 and best.get("state") == "chase")

func _overview(at: Vector3) -> void:
	if cam == null:
		cam = Camera3D.new(); cam.fov = 62; Game.main.add_child(cam)
	cam.current = true
	var mid := (at + Game.player.global_position) * 0.5
	cam.global_position = mid + Vector3(15, 10, 9)
	cam.look_at(mid + Vector3(0, 1.2, 0))

## tour: slam first; after it, knock the boss to half; in phase 2 sweep, then ride the rail.
func _tour() -> void:
	if boss.phase == 1 and (seen.has("hold") or flags.has("skip1")) and boss.state == "idle" and boss.hp > boss.BOSS_HP * 0.5:
		boss._hurt(boss.hp - boss.BOSS_HP * 0.5 + 1.0)
	if boss.phase == 2:
		boss.force_next = "spray" if seen.has("sweep_end") else "sweep"
		if seen.has("sweep_end") and not seen.has("stunned"): flags["grind"] = "1"
		elif seen.has("stunned"): flags.erase("grind"); flags["kill"] = "1"

## Double-jump over the jib: jump when it is ~0.35 s away, boost near the top of the jump.
func _jump_over() -> void:
	var pl := Game.player
	var d := pl.global_position - boss.global_position
	var ap := atan2(d.x, d.z)
	var gap: float = angle_difference(boss.turn_yaw, ap) * boss.sweep_dir
	if gap < 0.0: gap += TAU
	var eta: float = gap / maxf(boss.spin_v, 2.6)
	match jump_phase:
		0:
			if eta < 0.5 and pl.is_on_floor(): Input.action_press("jump"); jump_phase = 1
		1:
			Input.action_release("jump"); jump_phase = 2
		2:
			if pl.velocity.y < 4.0: Input.action_press("jump"); jump_phase = 3; print("[enemy-test] double jump over the jib")
		3:
			if pl.is_on_floor(): Input.action_release("jump"); jump_phase = 0

var total_t := 0.0
var crew_state := ""
var crew_t := 0.0
func _process(dt: float) -> void:
	total_t += dt
	var st := ""
	var st_time := 0.0
	if boss and is_instance_valid(boss): st = boss.state; st_time = state_t
	else:
		var crews := get_tree().get_nodes_in_group("crews")
		if not crews.is_empty():
			if crews[0].state != crew_state: crew_state = crews[0].state; crew_t = 0.0
			crew_t += dt; st = crew_state; st_time = crew_t
	if snapping: return
	for sn in snaps:
		var hit_state: bool = (sn[0] == "t" and total_t >= sn[1]) or (st == sn[0] and st_time >= sn[1])
		if not sn[2] and hit_state:
			sn[2] = true; snapping = true
			await RenderingServer.frame_post_draw
			var path := "%s_%s.png" % [flags.get("out", "/tmp/claude-0/godot/enemy"), sn[0] if sn[0] != "t" else "t%d" % int(sn[1])]
			get_viewport().get_texture().get_image().save_png(path)
			print("[enemy-test] saved ", path)
			snapping = false
			if snaps.all(func(x): return x[2]): get_tree().quit()
			return
