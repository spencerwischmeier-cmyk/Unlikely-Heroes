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
var chat_t := 0.0             # >0 while turned to grumble at a crewmate
var chat_cd := 0.0
var chat_dir := Vector3.ZERO

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
	# amber eye under the hard hat, a hat lamp, and a riveter arm on the right: flared as a telegraph
	var head: Node3D = cap if cap else model
	lamp_mats.append(add_eye(head, Vector3(0, 0.675, 0.33), 0.07, Color(1, 0.62, 0.12), 5.0))
	lamp_mats.append(add_eye(head, Vector3(0, 0.975, 0.36), 0.05, Color(1, 0.85, 0.45), 5.0, 0.3))
	arm = _build_arm(head)
	if cap: break_parts = [cap]
	scrap_count = 9
	cable_on = true
	chat_cd = randf_range(2.0, 6.0)
	# night-shift paint job: rust orange with a toolbox strapped to the back of the hat
	if roll_variant() and cap:
		apply_variant(Color(1.05, 0.74, 0.6), 1.05)
		var tb := Node3D.new(); tb.position = Vector3(0.05, 0.72, -0.42); tb.rotation = Vector3(0.15, 0, 0); cap.add_child(tb)
		add_prop(tb, box(Vector3(0.36, 0.2, 0.16)), Color(0.62, 0.2, 0.14), Vector3.ZERO)
		add_prop(tb, box(Vector3(0.37, 0.04, 0.17)), Color(0.12, 0.13, 0.15), Vector3(0, 0.06, 0), Vector3.ZERO, 0.6)
		add_prop(tb, box(Vector3(0.2, 0.025, 0.03)), Color(0.6, 0.62, 0.66), Vector3(0, 0.15, 0), Vector3.ZERO, 0.85)
		add_prop(tb, box(Vector3(0.025, 0.06, 0.03)), Color(0.6, 0.62, 0.66), Vector3(-0.09, 0.12, 0), Vector3.ZERO, 0.85)
		add_prop(tb, box(Vector3(0.025, 0.06, 0.03)), Color(0.6, 0.62, 0.66), Vector3(0.09, 0.12, 0), Vector3.ZERO, 0.85)

## The riveter arm (pivot at the shoulder; the crew swings it to hammer and cocks it back to fire).
func _build_arm(head: Node3D) -> Node3D:
	if ResourceLoader.exists("res://models/chars/crew_riveter.glb"):
		var r: Node3D = load("res://models/chars/crew_riveter.glb").instantiate()
		r.name = "arm"; r.position = Vector3(-0.5, 0.32, 0.02); head.add_child(r)
		_collect(r)
		return r
	var yellow := StandardMaterial3D.new(); yellow.albedo_color = Color(0.86, 0.6, 0.14); yellow.metallic = 0.4; yellow.roughness = 0.5
	var dark := StandardMaterial3D.new(); dark.albedo_color = Color(0.17, 0.19, 0.22); dark.metallic = 0.7; dark.roughness = 0.45
	var brass := StandardMaterial3D.new(); brass.albedo_color = Color(0.85, 0.62, 0.25); brass.metallic = 0.9; brass.roughness = 0.3
	var red := StandardMaterial3D.new(); red.albedo_color = Color(0.62, 0.2, 0.14); red.metallic = 0.4; red.roughness = 0.5
	for m in [yellow, dark, brass, red]:
		m.emission_enabled = true; m.emission = Color.WHITE; m.emission_energy_multiplier = 0.0; flash_mats.append(m)
	var a := Node3D.new(); a.name = "arm"; a.position = Vector3(-0.5, 0.32, 0.02); head.add_child(a)
	var parts := [
		["s", brass, Vector3.ZERO, Vector3.ZERO, Vector3(0.1, 0.2, 0.1)],
		["c", dark, Vector3(-0.05, -0.08, 0.15), Vector3(1.1, 0, 0), Vector3(0.045, 0.3, 0.045)],
		["b", yellow, Vector3(-0.08, -0.14, 0.36), Vector3.ZERO, Vector3(0.15, 0.17, 0.32)],
		["b", red, Vector3(-0.08, -0.05, 0.36), Vector3.ZERO, Vector3(0.155, 0.03, 0.33)],
		["c", dark, Vector3(-0.08, -0.14, 0.2), Vector3(PI / 2, 0, 0), Vector3(0.1, 0.06, 0.1)],
		["c", brass, Vector3(-0.08, -0.14, 0.58), Vector3(PI / 2, 0, 0), Vector3(0.04, 0.16, 0.04)],
	]
	for p in parts:
		var mesh: Mesh
		match p[0]:
			"s":
				var sm := SphereMesh.new(); sm.radius = p[4].x; sm.height = p[4].y; mesh = sm
			"c":
				var cm := CylinderMesh.new(); cm.top_radius = p[4].x; cm.bottom_radius = p[4].x * 1.1; cm.height = p[4].y; cm.radial_segments = 12; mesh = cm
			_:
				var bm := BoxMesh.new(); bm.size = p[4]; mesh = bm
		var mi := MeshInstance3D.new(); mi.mesh = mesh; mi.material_override = p[1]; mi.position = p[2]; mi.rotation = p[3]
		a.add_child(mi)
	var muzzle := Node3D.new(); muzzle.name = "crew_muzzle"; muzzle.position = Vector3(-0.08, -0.14, 0.68); a.add_child(muzzle)
	return a

func center() -> Vector3:
	return global_position + Vector3(0, 0.6, 0)

## Wind up and fire a rivet at Vesk (called by the crew).
func fire() -> void:
	if shoot_t < 0.0 and not dead and combat.claim_aim(self, WIND + 0.1):
		shoot_t = WIND
		# the riveter cocks: an audible cue to dodge (audio_space.gd plays enemy_windup_rivet when it exists)
		if not no_tells and not Snd.has_sound("enemy_windup_rivet"): Snd.at("hook_lock", center(), -9, 0.1, 0.05)

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
	if cap:
		cap.rotation.x = lerpf(cap.rotation.x, clampf(sp * 0.05, 0.0, 0.22) - (0.12 if shoot_t >= 0.0 else 0.0), 1.0 - exp(-6.0 * dt))
		cap.position.y = 0.5 + absf(sin(t * maxf(sp, 1.0) * 2.2)) * 0.03 + sin(t * 3.0) * 0.012 + (absf(sin(t * 12.0)) * 0.04 if build_t > 0.0 else 0.0)
	var face := face_dir
	if shoot_t >= 0.0 or face.length() < 0.1:
		face = player.global_position - global_position; face.y = 0
	if sp > 1.0 and shoot_t < 0.0 and build_t <= 0.0: face = flat
	_chat(dt)
	if chat_t > 0.0 and shoot_t < 0.0 and build_t <= 0.0: face = chat_dir
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

## Crew chatter: now and then a crewmate turns to the nearest other one and grumbles.
func _chat(dt: float) -> void:
	chat_t -= dt; chat_cd -= dt
	if chat_cd > 0.0 or shoot_t >= 0.0 or build_t > 0.0 or stun > 0.0: return
	chat_cd = randf_range(4.0, 9.0)
	var best: Node3D = null; var bd := 3.5
	for b in get_tree().get_nodes_in_group("bots"):
		if b == self or b.get_script() != get_script() or b.dead: continue
		var d := global_position.distance_to(b.global_position)
		if d < bd: bd = d; best = b
	if best == null: return
	chat_dir = best.global_position - global_position; chat_dir.y = 0
	chat_t = 1.1; pop = 0.25
	Snd.at("chars_crew_grumble", center(), -14, 0.15, 0.2)

func can_startle() -> bool:
	return shoot_t < 0.0 and build_t <= 0.0

func _startle(away: Vector3, k: float) -> void:
	super._startle(away, k)
	chat_t = 0.0
	Snd.at("chars_crew_grumble", center(), -8, 0.2, 0.2)

func _shoot() -> void:
	var muzzle: Node3D = model.find_child("crew_muzzle", true, false)
	var from: Vector3 = muzzle.global_position if muzzle else center() + Vector3(0, 0.3, 0)
	var to := player.global_position + Vector3(0, 0.9, 0)
	# rivets go over the barricade: start a little above it
	from.y = maxf(from.y, global_position.y + 1.7)
	combat.enemy_shot(from, to)
	FX.sparks(from, Color(1, 0.7, 0.3), 6, 3.0)
	pop = 0.4
