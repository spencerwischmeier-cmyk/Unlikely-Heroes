extends "res://scripts/enemy.gd"
## Scrap Roller: drops in, shakes itself awake, rolls at Vesk and blows itself up when it gets close.
##   Telegraph   when it is in range it stops dead, swells and blinks red while a red ring fills the
##               blast radius (0.8 s, plenty of time to step out)
##   Hit         flashes, leans and staggers; bolts knock it back
##   Wrench      a wrench hit launches it like a ball ("Return to Sender"): it flies off, and blows up
##               on the first bot (or the Crane Bot) it hits, hurting them instead of Vesk.
##               Launched rollers carry meta "returned_to_sender" = true in Game.bot_killed when they hit a bot.
## Plated Roller (main.spawn_bot("plated"), `plated` = true): the same bot bolted into riveted steel
## plates. It rolls a little slower and shrugs off light hits: bolts glance off with a "TINK" (a lot of
## them do wear the plates through). A heavy hit (wrench, stomp, air slam, lobber, a batted shot)
## cracks the shell at once: the plates burst off, it reels dizzy for a moment, then charges, angry and
## faster, as a plain roller (a second wrench sends it back). `--no-plated` spawns plain rollers instead.

const SPEED := 4.4
const FUSE := 0.8
const BLAST_R := 2.3
const LAUNCH_SPEED := 19.0

var ball: Node3D
var cap: Node3D
var fuse := -1.0
var state := "drop"       # drop, wake, chase, fuse, launched
var st_t := 0.0
var roll_snd := 0.0
var warn: Node3D
var launch_dir := Vector3.ZERO
var eye_mat: StandardMaterial3D
var tilt := 0.0           # head leans into the roll
var bulb_mat: StandardMaterial3D
var flank := 0.0          # each roller curves in from its own side instead of queueing up in a line
var pace := 1.0           # and rolls at its own pace
var sep_t := 0.0
var sep := Vector3.ZERO   # push away from nearby bots (refreshed a few times a second)
var plated := false       # set before adding to the tree (Plated Roller)
var armor := 0.0          # plate strength left; light hits chip it, heavy hits crack it at once
var plates: Array = []
var plate_mat: StandardMaterial3D
var daze := 0.0           # reeling after its shell cracks
var angry := false

func _ready() -> void:
	hp = 2.0; max_hp = 2.0; nuts = 4
	burst_color = Color(1, 0.45, 0.2)
	var cs := CollisionShape3D.new(); var sh := SphereShape3D.new(); sh.radius = 0.6
	cs.shape = sh; cs.position.y = 0.6; add_child(cs)
	setup_model("res://models/roller.glb")
	ball = model.find_child("ball", true, false)
	cap = model.find_child("cap", true, false)
	floor_snap_length = 0.3
	# one big red eye under the horned helmet; starts shut (it wakes up when it lands)
	eye_mat = add_eye(cap if cap else model, Vector3(0, 0.83, 0.42), 0.1, Color(1, 0.16, 0.08), 5.0)
	eye_open = 0.1
	if cap: break_parts = [cap]
	scrap_count = 10
	cable_on = true
	# the night-shift paint job: rust orange, a bit bigger, with a bent antenna and a blinking bulb
	if plated: _build_plates()
	elif roll_variant() and cap:
		apply_variant(Color(1.05, 0.74, 0.6), 1.08)
		var ant := Node3D.new(); ant.position = Vector3(0.16, 1.0, -0.18); ant.rotation = Vector3(-0.35, 0, -0.3); cap.add_child(ant)
		add_prop(ant, cyl(0.045, 0.08), Color(0.17, 0.19, 0.22), Vector3(0, 0.0, 0), Vector3.ZERO, 0.7)
		add_prop(ant, cyl(0.014, 0.42), Color(0.6, 0.62, 0.66), Vector3(0, 0.22, 0), Vector3.ZERO, 0.85)
		add_prop(ant, cyl(0.014, 0.16), Color(0.6, 0.62, 0.66), Vector3(0.05, 0.47, 0), Vector3(0, 0, -0.7), 0.85)
		bulb_mat = add_prop(ant, ball_mesh(0.05), Color(1, 0.25, 0.12), Vector3(0.1, 0.54, 0), Vector3.ZERO, 0.0, 3.0).material_override
	roll_snd = randf_range(0.5, 2.0)
	flank = randf_range(-1.0, 1.0); pace = randf_range(0.9, 1.12); sep_t = randf() * 0.2

func center() -> Vector3:
	return global_position + Vector3(0, 0.55, 0)

## Riveted steel plates: six round plates on the ball (they roll with it) and a welded brow plate and
## side cheeks on the helmet. They are thrown off as debris when the shell cracks.
func _build_plates() -> void:
	armor = 3.0; nuts = 7; scrap_count = 12; pace *= 0.82
	burst_color = Color(0.75, 0.85, 1.0)
	plate_mat = StandardMaterial3D.new(); plate_mat.albedo_color = Color(0.46, 0.5, 0.56); plate_mat.metallic = 0.85; plate_mat.roughness = 0.32
	plate_mat.emission_enabled = true; plate_mat.emission = Color.WHITE; plate_mat.emission_energy_multiplier = 0.0
	flash_mats.append(plate_mat)
	var rivet := StandardMaterial3D.new(); rivet.albedo_color = Color(0.85, 0.68, 0.3); rivet.metallic = 0.9; rivet.roughness = 0.3
	var dirs := [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK, Vector3.DOWN, Vector3.UP]
	var host: Node3D = ball if ball else model
	for d in dirs:
		var pl := MeshInstance3D.new(); pl.mesh = cyl(0.3, 0.07, 0.34); pl.material_override = plate_mat
		pl.basis = Basis(Vector3.RIGHT, PI) if d == Vector3.DOWN else Basis(Quaternion(Vector3.UP, d)); pl.position = d * 0.56
		for k in 4:
			var r := MeshInstance3D.new(); r.mesh = ball_mesh(0.035); r.material_override = rivet
			var a := TAU * k / 4.0 + 0.4
			r.position = Vector3(cos(a) * 0.22, 0.04, sin(a) * 0.22); pl.add_child(r)
		host.add_child(pl); plates.append(pl)
	if cap:
		var brow := MeshInstance3D.new(); brow.mesh = box(Vector3(0.62, 0.13, 0.1)); brow.material_override = plate_mat
		brow.position = Vector3(0, 0.96, 0.4); brow.rotation.x = -0.35; cap.add_child(brow); plates.append(brow)
		for x in [-0.5, 0.5]:
			var ch := MeshInstance3D.new(); ch.mesh = box(Vector3(0.08, 0.3, 0.42)); ch.material_override = plate_mat
			ch.position = Vector3(x, 0.72, 0.12); cap.add_child(ch); plates.append(ch)
	break_parts = break_parts + plates

## The plates crack and burst off; it reels, then comes on angrier and quicker.
func _crack(point: Vector3, dir: Vector3) -> void:
	if Engine.has_meta("et_log"): print("[enemy-test] plated roller cracked (armor left %.2f)" % armor)
	armor = 0.0
	no_number_frame = Engine.get_physics_frames()
	var live := plates.filter(func(n): return is_instance_valid(n))
	break_parts = break_parts.filter(func(n): return not (n in plates))
	plates.clear()
	var c := center()
	ScrapBurst.burst(get_parent(), c, 0.8, [plate_mat], 5, live)
	FX.sparks(c, Color(0.85, 0.92, 1.0), 26, 8); FX.ring(c, Color(0.8, 0.9, 1.0), 0.8)
	FX.stop(0.08); FX.shake(0.6)
	Snd.at("armor_crack" if Snd.has_sound("armor_crack") else "crate_break", c, 0, 0.1, 0.05)
	Snd.at("chars_bot_break", c, -6, 0.1, 0.05)
	if combat: combat.float_text(c + Vector3(0, 0.9, 0), "CRACK!", Color(0.8, 0.92, 1.0), 56)
	var push := dir; push.y = 0
	if push.length() < 0.01: push = global_position - point; push.y = 0
	push = push.normalized() if push.length() > 0.01 else Vector3.FORWARD
	velocity += push * 7.0 + Vector3(0, 3.5, 0)
	lean = Vector3(push.z, 0, -push.x) * 0.6; lean_v = lean * 7.0
	flash = 1.0; pop = 1.0
	daze = 1.0; stun = maxf(stun, 1.0)
	angry = true; pace *= 1.4
	if warn: warn.queue_free(); warn = null
	if state == "fuse":
		state = "chase"; fuse = -1.0
		for m in flash_mats: m.emission = Color.WHITE

## A light hit on the plates: a white ping, a little shove, the plates wear down.
func _glance(amount: float, point: Vector3, dir: Vector3) -> void:
	armor -= amount * 0.3
	no_number_frame = Engine.get_physics_frames()
	flash = maxf(flash, 0.5); pop = maxf(pop, 0.25)
	var push := dir; push.y = 0
	if push.length() > 0.01: velocity += push.normalized() * 1.2
	FX.hit_sparks(point, dir if dir.length() > 0.01 else Vector3.UP, Color(0.85, 0.92, 1.0), 5)
	Snd.at("armor_tink" if Snd.has_sound("armor_tink") else "rail_spark", point, -8, 0.15, 0.06)
	if combat and randf() < 0.6: combat.float_text(point + Vector3(0, 0.3, 0), "TINK", Color(0.75, 0.82, 0.92), 30)

func can_startle() -> bool:
	return state == "chase" and daze <= 0.0

## A wrench hit (heavy and up close) launches the roller instead of breaking it.
func damage(amount: float, point: Vector3, dir: Vector3) -> bool:
	if dead: return false
	if armor > 0.0:
		Game.bot_hit.emit(self, amount)
		if amount >= 1.5 or armor - amount * 0.3 <= 0.0: _crack(point, dir)
		else: _glance(amount, point, dir)
		return false
	if amount >= 2.0 and player and global_position.distance_to(player.global_position) < 3.6:
		var d := dir; d.y = 0
		if d.length() < 0.01: d = global_position - player.global_position; d.y = 0
		Game.bot_hit.emit(self, amount)
		_launch(d.normalized())
		return true
	return super.damage(amount, point, dir)

func _launch(d: Vector3) -> void:
	dead = true
	remove_from_group("targets"); remove_from_group("bots")
	collision_layer = 0
	state = "launched"; st_t = 1.0
	if warn: warn.queue_free(); warn = null
	d = _sender_aim(d)
	launch_dir = d
	velocity = d * LAUNCH_SPEED + Vector3(0, 3.5, 0)
	flash = 1.0; pop = 1.0
	FX.sparks(center(), Color(1, 0.95, 0.7), 18, 7); FX.ring(center(), Color(1, 0.85, 0.4), 0.6)
	Snd.at("melee_hit", center(), 2)
	died.emit(self)

func _physics_process(dt: float) -> void:
	if state == "launched": _fly(dt); return
	if dead: return
	tick_common(dt)
	if paused(): return
	var to := player.global_position - global_position; to.y = 0
	var dist := to.length()
	match state:
		"drop":
			if is_on_floor():
				state = "wake"; st_t = 0.45
				FX.puff(global_position + Vector3(0, 0.1, 0), Color(1, 0.75, 0.7)); FX.ring(global_position + Vector3(0, 0.05, 0), Color(1, 0.6, 0.4), 0.5)
				Snd.at("land", global_position, -6)
				Snd.at("chars_roller_wake", global_position, -6, 0.12, 0.1)
				pop = 1.0
		"wake":
			# a little shake and hop before it starts rolling
			st_t -= dt
			eye_open = lerpf(eye_open, 1.0, 1.0 - exp(-10.0 * dt))
			if model: model.rotation.y = sin(t * 40.0) * 0.15
			if st_t <= 0.0:
				state = "chase"; velocity.y = 3.0; eye_open = 1.0; pop = 0.8
				if plated and combat and not Engine.has_meta("plated_seen"):
					Engine.set_meta("plated_seen", true)    # the first one of a run says how to beat it
					combat.float_text(center() + Vector3(0, 1.2, 0), "PLATED! WRENCH IT", Color(0.8, 0.92, 1.0), 40)
				Snd.at("chars_roller_hop", global_position, -9, 0.15, 0.1)
				if model: model.rotation.y = 0
		"chase":
			if daze > 0.0:
				daze -= dt
				if cap: cap.rotation.y += dt * 14.0 * daze
				if randf() < 0.25: FX.sparks(center() + Vector3(0, 0.8, 0), Color(1, 0.95, 0.5), 2, 1.5)
				if daze <= 0.0:
					pop = 0.9; velocity.y = 3.2
					Snd.at("chars_roller_hop", global_position, -6, 0.15, 0.1)
					if eye_mat: eye_mat.emission_energy_multiplier = 9.0
			if is_on_floor() and stun <= 0.0:
				sep_t -= dt
				if sep_t <= 0.0: sep_t = 0.2; sep = _separation()
				# far off it swings wide to its side, closing in it straightens up and commits
				var dirn := to.normalized()
				var side := Vector3(-dirn.z, 0, dirn.x) * flank * clampf((dist - 3.0) / 6.0, 0.0, 0.8)
				var want := (dirn + side + sep).normalized() * SPEED * pace * (1.15 if dist < 5.0 else 1.0)
				velocity.x = lerpf(velocity.x, want.x, 1.0 - exp(-2.5 * dt))
				velocity.z = lerpf(velocity.z, want.z, 1.0 - exp(-2.5 * dt))
			roll_snd -= dt
			if roll_snd <= 0.0: roll_snd = randf_range(1.6, 2.6); Snd.at("roller_roll", global_position, -12, 0.1, 0.2)
			if dist < 1.9 and is_on_floor() and stun <= 0.0 and absf(player.global_position.y - global_position.y) < 1.5:
				state = "fuse"; fuse = FUSE
				Snd.at("roller_fuse", global_position, -2, 0.0)
				warn = FX.warn_ring(global_position, BLAST_R, FUSE)
		"fuse":
			velocity.x *= exp(-8.0 * dt); velocity.z *= exp(-8.0 * dt)
			fuse -= dt
			var blink := sin(t * lerpf(25.0, 60.0, 1.0 - fuse / FUSE)) > 0.0
			for m in flash_mats: m.emission = Color(1, 0.2, 0.1); m.emission_energy_multiplier = 3.0 if blink else 0.3
			if eye_mat: eye_mat.emission_energy_multiplier = 14.0 if blink else 4.0
			if cap: cap.position.y = 0.55 + absf(sin(t * 30.0)) * 0.05
			if model: model.scale = Vector3.ONE * (1.0 + (FUSE - fuse) * 0.45)
			if warn: warn.global_position = global_position + Vector3(0, 0.06, 0)
			if fuse <= 0.0:
				var hd := Vector2(to.x, to.z).length()
				if hd < BLAST_R and absf(player.global_position.y - global_position.y) < 1.8: combat.hurt_player(1, global_position)
				warn = null
				die(true)
				return
	velocity.y -= 25.0 * dt
	var was := is_on_floor()
	move_and_slide()
	if is_on_floor() and not was and state == "chase": FX.puff(global_position + Vector3(0, 0.1, 0), Color(1, 0.75, 0.7))
	clamp_to_zone()
	_spin(dt)
	if bulb_mat: bulb_mat.emission_energy_multiplier = (8.0 if fmod(t, 1.1) < 0.12 else 0.6) if state != "fuse" else (12.0 if sin(t * 50.0) > 0.0 else 0.5)
	if global_position.y < -40.0: die(true)

func _spin(dt: float) -> void:
	var sp := Vector2(velocity.x, velocity.z).length()
	if sp > 0.05 and ball:
		var axis := Vector3(velocity.z, 0, -velocity.x).normalized()
		ball.rotate(axis, sp * dt / 0.55)
		if cap: cap.rotation.y = lerp_angle(cap.rotation.y, atan2(velocity.x, velocity.z), 1.0 - exp(-12.0 * dt))
	# the head leans into the roll and bobs a little while rolling
	tilt = lerpf(tilt, clampf(sp * 0.05, 0.0, 0.25), 1.0 - exp(-6.0 * dt))
	if cap and state != "fuse":
		cap.rotation.x = tilt
		cap.position.y = 0.55 + absf(sin(t * sp * 2.2)) * 0.035 * minf(1.0, sp / 3.0)

## Return to Sender aims itself a little: if a bot or the boss is roughly where it was knocked, it flies at that.
func _sender_aim(d: Vector3) -> Vector3:
	var best: Node3D = null
	var bs := 0.82   # cos of ~35 degrees
	for b in get_tree().get_nodes_in_group("bots") + get_tree().get_nodes_in_group("boss"):
		if b == self or b.get("dead") or not (b is Node3D): continue
		var to: Vector3 = (b.center() if b.has_method("center") else (b as Node3D).global_position) - center()
		to.y = 0
		var l := to.length()
		if l < 1.5 or l > 26.0: continue
		var c := to.normalized().dot(d) + (0.05 if b.is_in_group("boss") else 0.0)
		if c > bs: bs = c; best = b
	if best == null: return d
	var to2: Vector3 = (best.center() if best.has_method("center") else best.global_position) - center(); to2.y = 0
	return to2.normalized()

func _separation() -> Vector3:
	var push := Vector3.ZERO
	for b in get_tree().get_nodes_in_group("bots"):
		if b == self or not (b is Node3D) or b.get("dead"): continue
		var d: Vector3 = global_position - (b as Node3D).global_position; d.y = 0
		var l := d.length()
		if l < 2.2 and l > 0.01: push += d / l * (2.2 - l) / 2.2
	return push.limit_length(1.0) * 1.2

## Return to Sender: fly until hitting a bot, the boss or a wall, then blow up on them.
func _fly(dt: float) -> void:
	t += dt; st_t -= dt
	flash = maxf(0.0, flash - dt * 4.0); pop = maxf(0.0, pop - dt * 5.0)
	for m in flash_mats: m.emission = Color(1, 0.9, 0.6); m.emission_energy_multiplier = 1.5 + sin(t * 40.0)
	velocity.y -= 9.0 * dt
	var was_wall := false
	var col := move_and_collide(velocity * dt)
	if col and col.get_normal().y < 0.6: was_wall = true
	elif col: velocity = velocity.slide(col.get_normal())
	_spin(dt * 3.0)
	if randf() < 0.5: FX.sparks(center(), Color(1, 0.8, 0.4), 2, 2.0)
	var hit: Node3D = null
	for b in get_tree().get_nodes_in_group("targets"):
		if b == self or b.dead or b.is_in_group("crate"): continue
		if b.is_in_group("boss"):
			var bp: Vector3 = b.global_position
			if Vector2(bp.x - global_position.x, bp.z - global_position.z).length() < 3.3: hit = b; break
		elif b.has_method("center") and (b.center() as Vector3).distance_to(center()) < 1.5:
			hit = b; break
	if hit or was_wall or st_t <= 0.0 or global_position.y < -40.0:
		_return_blast(hit)

func _return_blast(hit: Node3D) -> void:
	var c := center()
	if hit: set_meta("returned_to_sender", true)
	for b in get_tree().get_nodes_in_group("targets"):
		if b == self or b.dead: continue
		var d: float
		if b.is_in_group("boss"):
			var bp: Vector3 = b.global_position
			d = Vector2(bp.x - c.x, bp.z - c.z).length() - 2.0
		else:
			d = (b.center() as Vector3).distance_to(c)
		if d < 2.8 or b == hit:
			var dmg := 8.0 if b.is_in_group("boss") else 3.0
			b.damage(dmg, c, (b.center() - c).normalized())
			if combat and not b.is_in_group("crate"): combat.damage_number(b.center(), dmg, b.dead)
	if combat: combat.drop_nuts(c, nuts)
	Game.bot_killed.emit(self, c, kind())
	_burst()
	FX.shake(0.9)
	queue_free()

func _exit_tree() -> void:
	if warn and is_instance_valid(warn): warn.queue_free()
