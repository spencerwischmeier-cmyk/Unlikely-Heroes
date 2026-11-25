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

func _ready() -> void:
	hp = 2.0; max_hp = 2.0; nuts = 4
	burst_color = Color(1, 0.45, 0.2)
	var cs := CollisionShape3D.new(); var sh := SphereShape3D.new(); sh.radius = 0.6
	cs.shape = sh; cs.position.y = 0.6; add_child(cs)
	setup_model("res://models/roller.glb")
	ball = model.find_child("ball", true, false)
	cap = model.find_child("cap", true, false)
	floor_snap_length = 0.3
	roll_snd = randf_range(0.5, 2.0)

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
				pop = 1.0
		"wake":
			# a little shake and hop before it starts rolling
			st_t -= dt
			if model: model.rotation.y = sin(t * 40.0) * 0.15
			if st_t <= 0.0:
				state = "chase"; velocity.y = 3.0
				if model: model.rotation.y = 0
		"chase":
			if is_on_floor() and stun <= 0.0:
				var want := to.normalized() * SPEED
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
	if global_position.y < -40.0: die(true)

func _spin(dt: float) -> void:
	var sp := Vector2(velocity.x, velocity.z).length()
	if sp > 0.05 and ball:
		var axis := Vector3(velocity.z, 0, -velocity.x).normalized()
		ball.rotate(axis, sp * dt / 0.55)
		if cap: cap.rotation.y = atan2(velocity.x, velocity.z)

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
