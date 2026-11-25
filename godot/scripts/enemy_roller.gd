extends "res://scripts/enemy.gd"
## Scrap Roller: drops in, rolls at Vesk and blows itself up when it gets close.

var ball: Node3D
var cap: Node3D
var fuse := -1.0
var eye_mat: StandardMaterial3D

func _ready() -> void:
	hp = 2.0; max_hp = 2.0; nuts = 4
	var cs := CollisionShape3D.new(); var sh := SphereShape3D.new(); sh.radius = 0.6
	cs.shape = sh; cs.position.y = 0.6; add_child(cs)
	setup_model("res://models/roller.glb")
	ball = model.find_child("ball", true, false)
	cap = model.find_child("cap", true, false)
	floor_snap_length = 0.3

func center() -> Vector3:
	return global_position + Vector3(0, 0.55, 0)

func _physics_process(dt: float) -> void:
	if dead: return
	tick_common(dt)
	var to := player.global_position - global_position; to.y = 0
	var dist := to.length()
	if fuse < 0.0:
		if is_on_floor() and stun <= 0.0:
			var want := to.normalized() * 4.4
			velocity.x = lerpf(velocity.x, want.x, 1.0 - exp(-2.5 * dt))
			velocity.z = lerpf(velocity.z, want.z, 1.0 - exp(-2.5 * dt))
		if dist < 1.4 and is_on_floor(): fuse = 0.55
	else:
		velocity.x *= exp(-6.0 * dt); velocity.z *= exp(-6.0 * dt)
		fuse -= dt
		for m in flash_mats: m.emission = Color(1, 0.2, 0.1); m.emission_energy_multiplier = 3.0 if sin(t * 50.0) > 0.0 else 0.0
		model.scale = Vector3.ONE * (1.0 + (0.55 - fuse) * 0.4)
		if fuse <= 0.0:
			if dist < 2.2: combat.hurt_player(1, global_position)
			die(true)
			return
	velocity.y -= 25.0 * dt
	var was := is_on_floor()
	move_and_slide()
	if is_on_floor() and not was: FX.puff(global_position + Vector3(0, 0.1, 0), Color(1, 0.75, 0.7))
	if zone.size.x > 0.0:
		global_position.x = clampf(global_position.x, zone.position.x + 0.6, zone.end.x - 0.6)
		global_position.z = clampf(global_position.z, zone.position.y + 0.6, zone.end.y - 0.6)
	var sp := Vector2(velocity.x, velocity.z).length()
	if sp > 0.05 and ball:
		var axis := Vector3(velocity.z, 0, -velocity.x).normalized()
		ball.rotate(axis, sp * dt / 0.55)
		if cap: cap.rotation.y = atan2(velocity.x, velocity.z)
	if global_position.y < -40.0: die(true)
