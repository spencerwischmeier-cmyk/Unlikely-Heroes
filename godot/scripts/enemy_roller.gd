extends "res://scripts/enemy.gd"
## Scrap Roller: drops in, shakes itself awake, rolls at Vesk and blows itself up when it gets close.
##   Telegraph   when it is in range it stops dead, swells and blinks red while a red ring fills the
##               blast radius (0.8 s, plenty of time to step out)
##   Hit         flashes, leans and staggers; bolts knock it back
##   Wrench      a wrench hit launches it like a ball ("Return to Sender"): it flies off, and blows up
##               on the first bot (or the Crane Bot) it hits, hurting them instead of Vesk.
##               Launched rollers carry meta "returned_to_sender" = true in Game.bot_killed when they hit a bot.

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
	if roll_variant() and cap:
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

## A wrench hit (heavy and up close) launches the roller instead of breaking it.
func damage(amount: float, point: Vector3, dir: Vector3) -> bool:
	if dead: return false
	if amount >= 2.0 and player and global_position.distance_to(player.global_position) < 3.6:
		var d := dir; d.y = 0
		if d.length() < 0.01: d = global_position - player.global_position; d.y = 0
		_launch(d.normalized())
		return true
	return super.damage(amount, point, dir)

func _launch(d: Vector3) -> void:
	dead = true
	remove_from_group("targets"); remove_from_group("bots")
	collision_layer = 0
	state = "launched"; st_t = 1.0
	if warn: warn.queue_free(); warn = null
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
				Snd.at("chars_roller_hop", global_position, -9, 0.15, 0.1)
				if model: model.rotation.y = 0
		"chase":
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
