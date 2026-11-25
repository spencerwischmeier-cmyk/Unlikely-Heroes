extends "res://scripts/enemy.gd"
## Work-Crew Roller: a hard-hatted roller that works in a crew of three (see enemy_crew.gd, which
## steers them). It rolls to wherever its crew tells it, hammers up barricade sections, and fires
## rivets over them with its riveter arm. It doesn't explode; it bumps Vesk if he gets in its way.
##   Telegraph   before a rivet the arm cocks back and the hat lamp flares for 0.6 s
##   Hit         flash, lean, stagger, knockback

const SPEED := 4.0
const WIND := 0.6

var ball: Node3D
var cap: Node3D
var arm: Node3D
var lamp_mats: Array = []
var goal := Vector3.ZERO      # set by the crew
var has_goal := false
var speed_mul := 1.0
var face_dir := Vector3.ZERO  # look this way when standing still (set by the crew)
var shoot_t := -1.0           # winding up a rivet when >= 0
var bump_cd := 0.0
var build_t := 0.0            # hammering animation while > 0
var landed := false

func _ready() -> void:
	hp = 3.0; max_hp = 3.0; nuts = 5
	burst_color = Color(1, 0.7, 0.15)
	var cs := CollisionShape3D.new(); var sh := SphereShape3D.new(); sh.radius = 0.55
	cs.shape = sh; cs.position.y = 0.55; add_child(cs)
	setup_model("res://models/crew_roller.glb")
	ball = model.find_child("ball", true, false)
	cap = model.find_child("cap", true, false)
	arm = model.find_child("arm", true, false)
	floor_snap_length = 0.3
	# the visor + hat lamp share the glowing material: collect it to flare it as a telegraph
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		for s in (mi as MeshInstance3D).mesh.get_surface_count():
			var m := (mi as MeshInstance3D).get_active_material(s)
			if m is StandardMaterial3D and (m as StandardMaterial3D).emission_enabled and not flash_mats.has(m):
				var c := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
				(mi as MeshInstance3D).set_surface_override_material(s, c); lamp_mats.append(c)

func center() -> Vector3:
	return global_position + Vector3(0, 0.6, 0)

## Wind up and fire a rivet at Vesk (called by the crew).
func fire() -> void:
	if shoot_t < 0.0 and not dead: shoot_t = WIND

func _physics_process(dt: float) -> void:
	if dead: return
	tick_common(dt)
	if paused(): return
	bump_cd -= dt
	var on_floor := is_on_floor()
	if on_floor and not landed:
		landed = true; FX.puff(global_position + Vector3(0, 0.1, 0), Color(1, 0.85, 0.5)); Snd.at("land", global_position, -6)
	var flat := Vector3(velocity.x, 0, velocity.z)
	if on_floor and stun <= 0.0:
		var want := Vector3.ZERO
		if has_goal:
			var to := goal - global_position; to.y = 0
			if to.length() > 0.35: want = to.normalized() * SPEED * speed_mul * clampf(to.length() / 1.2, 0.3, 1.0)
		velocity.x = lerpf(velocity.x, want.x, 1.0 - exp(-4.0 * dt))
		velocity.z = lerpf(velocity.z, want.z, 1.0 - exp(-4.0 * dt))
	velocity.y -= 25.0 * dt
	move_and_slide()
	clamp_to_zone()
	# rolling + facing
	var sp := flat.length()
	if sp > 0.05 and ball:
		ball.rotate(Vector3(flat.z, 0, -flat.x).normalized(), sp * dt / 0.5)
	var face := face_dir
	if shoot_t >= 0.0 or face.length() < 0.1:
		face = player.global_position - global_position; face.y = 0
	if sp > 1.0 and shoot_t < 0.0 and build_t <= 0.0: face = flat
	if cap and face.length() > 0.05:
		cap.rotation.y = lerp_angle(cap.rotation.y, atan2(face.x, face.z), 1.0 - exp(-8.0 * dt))
	# arm: hammering, winding up, or resting
	var arm_x := 0.0
	if build_t > 0.0:
		build_t -= dt; arm_x = -0.9 + absf(sin(t * 12.0)) * 1.3
	elif shoot_t >= 0.0:
		arm_x = -lerpf(0.0, 1.1, 1.0 - shoot_t / WIND)
	if arm: arm.rotation.x = lerpf(arm.rotation.x, arm_x, 1.0 - exp(-20.0 * dt))
	var glow := 5.0
	if shoot_t >= 0.0:
		shoot_t -= dt
		glow = 5.0 + (1.0 - shoot_t / WIND) * 14.0 * (0.6 + 0.4 * sin(t * 40.0))
		if shoot_t < 0.0: _shoot()
	for m in lamp_mats: m.emission_energy_multiplier = glow
	# bump Vesk if he walks into the crew
	var dp := player.global_position - global_position
	if Vector2(dp.x, dp.z).length() < 1.15 and absf(dp.y) < 1.2 and bump_cd <= 0.0:
		bump_cd = 1.2
		combat.hurt_player(1, global_position)
		velocity -= Vector3(dp.x, 0, dp.z).normalized() * 4.0
	if global_position.y < -40.0: die(true)

func _shoot() -> void:
	var muzzle: Node3D = model.find_child("crew_muzzle", true, false)
	var from: Vector3 = muzzle.global_position if muzzle else center() + Vector3(0, 0.3, 0)
	var to := player.global_position + Vector3(0, 0.9, 0)
	# rivets go over the barricade: start a little above it
	from.y = maxf(from.y, global_position.y + 1.7)
	combat.enemy_shot(from, to)
	FX.sparks(from, Color(1, 0.7, 0.3), 6, 3.0)
	pop = 0.4
