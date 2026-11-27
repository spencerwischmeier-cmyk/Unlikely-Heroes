extends CharacterBody3D
## Vesk: runs, jumps (hold for height), double-jumps with the jetpack, glides, dashes, long-jumps out
## of a dash, grinds rails, swings from hooks and bounces on pads. Faces where he runs and only
## strafes while shooting.

const GRAV := 28.0
const RUN := 8.4
const JUMP := 9.4
const BOOST := 8.2
const LONG_SPEED := 15.5
const LONG_UP := 8.0
const HOOK_RANGE := 15.0
const SWING_T := 1.05
const RELEASE := 0.8

var cam: Node3D
var combat: Node3D
var melee_cd := 0.0
var melee_hit := 0.0
var combo := 0               # wrench combo step: 1, 2, then 3 is a spinning finisher
var combo_window := 0.0      # time left to chain the next swing
var spin_t := 0.0            # finisher spin (adds a full turn to the model's facing)
var slam := 0                # wrench slam from the air: 1 = wind-up hang, 2 = plunging (see _slam_land)
var slam_t := 0.0
var slam_target: Node3D = null   # a ground bot the plunge drifts onto (a small assist)
var flip_t := 0.0           # forward flip on the double jump
var twist := 0.0             # swing wind-up: the first swing comes from the right, the second backhands from the left
var aim_point := Vector3.ZERO
var level: Node3D
var respawn_pos := Vector3.ZERO
var respawn_yaw := NAN          # camera yaw to face after a respawn (NAN: keep the current one)
var model: Node3D
var body: Node3D
var skel: Skeleton3D
var anim: AnimationPlayer
var bones := {}
var cur_anim := "idle"
var melee_t := 0.0
var melee_buf := 0.0
var land_play := 0.0
var jets: Array = []
# weapons in hand (the Arc Lancer is part of the hero mesh; the others are attached at the "gun" bone)
var gun_bone := -1
var gun_up_axis := Vector3(0, 0, -1)   # which gun-bone axis points up on the model
var weapon_models := {}                # id -> Node3D (top-level, follows the gun bone)
var held_weapon := "arc_lancer"
var lancer_fx: Node3D
var weapon_kick := 0.0
# jetpack flames
var chest_bone := -1
var jet_offsets: Array = []            # nozzle transforms relative to the chest bone
var flames: Array = []                 # { pivot: Node3D, core: MeshInstance3D, outer: MeshInstance3D, sparks: CPUParticles3D }
var flame_mat_core: StandardMaterial3D
var flame_mat_outer: StandardMaterial3D
var jet_power := 0.0
var jet_burst := 0.0
var jet_tilt := 0.0
var _prev_jumps := 0
var _prev_dash := 0.0
var _prev_long := false
var force_jets := -1.0               # debug: hold the flames at this power (--jets=0.8)

var grounded := false
var jumps := 0
var coyote := 0.0
var jump_buf := 0.0
var jump_age := 0.0
var jump_cut := false
var long_jump := false
var dash_t := 0.0
var dash_cd := 0.0
var dash_buf := 0.0
var since_dash := 9.0
var jet_t := 0.0
var land_t := 0.0
var step_t := 0.0
var face_yaw := PI
var turn_rate := 0.0
var aim_hold := 0.0
var using_pad := false
var ledge_used := false      # one ledge assist per time in the air
var ledge_t := 0.0           # > 0 while popping up onto a ledge (keeps the forward push going)
var ledge_dir := Vector3.ZERO
var _no_ledge := OS.get_cmdline_user_args().has("--no-ledge")
const LEDGE_MAX := 0.85      # highest lip (above Vesk's feet) a missed jump still pulls him onto

# rails and hooks
var riding := false
var rail: Dictionary
var rail_off := 0.0
var rail_dir := 1.0
var rail_speed := 0.0
var rail_cool := 0.0
var last_rail = null   # the rail just left: not re-caught for a moment (stops riding back up from the end)
var last_rail_t := 0.0
var swing_hook: Node3D = null
var swing_t := 0.0
var swing_L := 0.0
var swing_A := 0.0
var swing_dirv := Vector3.ZERO
var hook_target: Node3D = null
var rope: MeshInstance3D

# animation
var phase := 0.0
var lean := 0.0
var pitch_s := 0.0
const HERO_SCALE := 0.9
var arm_hold := 1.0          # 0..1: how much the right arm is posed to hold the blaster forward
var arm_bones := []          # [upper, fore, hand] bone ids (right arm)
var anim_t := 0.0
var hurt_t := 0.0            # flinch + red flash when hit
var fur_mats: Array = []

func _ready() -> void:
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new(); cap.radius = 0.38; cap.height = 1.7
	cs.shape = cap; cs.position.y = 0.85
	add_child(cs)
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(50)
	floor_stop_on_slope = true
	floor_constant_speed = true
	platform_on_leave = CharacterBody3D.PLATFORM_ON_LEAVE_ADD_VELOCITY
	model = Node3D.new(); add_child(model)
	body = Node3D.new(); model.add_child(body)
	var hero: Node3D = load("res://models/vesk.glb").instantiate()
	hero.scale = Vector3.ONE * HERO_SCALE
	body.add_child(hero)
	_shadows(hero)
	_fur(hero)
	skel = hero.find_child("Skeleton3D", true, false)
	anim = hero.find_child("AnimationPlayer", true, false)
	anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for n in ["idle", "run", "fall", "dash", "glide", "grind", "swing"]:
		anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	anim.play("idle")
	for b in ["pelvis", "spine", "chest", "neck", "head"]: bones[b] = skel.find_bone(b)
	for b in ["RightArm", "RightForeArm", "RightHand"]: arm_bones.append(maxi(skel.find_bone("mixamorig_" + b), skel.find_bone("mixamorig:" + b)))
	for sx in [-1, 1]:
		var l := OmniLight3D.new(); l.light_color = Color(0.3, 0.9, 1); l.light_energy = 0.0; l.omni_range = 2.5
		l.position = Vector3(0.17 * sx, 0.84, -0.36)
		body.add_child(l); jets.append(l)
	_build_weapons()
	_build_flames()
	rope = MeshInstance3D.new()
	var rm := CylinderMesh.new(); rm.top_radius = 0.035; rm.bottom_radius = 0.035; rm.height = 1.0
	rope.mesh = rm
	var gm := StandardMaterial3D.new(); gm.albedo_color = Color.BLACK; gm.emission_enabled = true; gm.emission = Color(1, 0.8, 0.35); gm.emission_energy_multiplier = 3
	rope.material_override = gm
	rope.top_level = true; rope.visible = false
	add_child(rope)
	level = get_parent().get_node_or_null("Level") if get_parent() else null
	Game.player_hurt.connect(func(_h): hurt_t = 0.35)

## Vesk's fur: a soft rim sheen and a touch of subsurface so he doesn't read as plastic (--no-fur to compare)
func _fur(n: Node) -> void:
	if OS.get_cmdline_user_args().has("--no-fur"): return
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		for i in mi.mesh.get_surface_count():
			var m := mi.get_active_material(i)
			if m is StandardMaterial3D:
				var f := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
				f.rim_enabled = true; f.rim = 0.55; f.rim_tint = 0.55
				f.subsurf_scatter_enabled = true; f.subsurf_scatter_strength = 0.12
				f.roughness = maxf(f.roughness, 0.55)
				mi.set_surface_override_material(i, f)

func _shadows(n: Node) -> void:
	if n is GeometryInstance3D: (n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for c in n.get_children(): _shadows(c)

func _input(e: InputEvent) -> void:
	if e is InputEventJoypadButton or (e is InputEventJoypadMotion and absf(e.axis_value) > 0.3): using_pad = true
	elif e is InputEventKey or e is InputEventMouseButton: using_pad = false

func wish_dir() -> Vector3:
	var v := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	var yaw: float = cam.yaw
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	var right := Vector3(-cos(yaw), 0, sin(yaw))
	return (fwd * v.y + right * v.x).limit_length(1.0) * RUN

func _physics_process(dt: float) -> void:
	if level == null: level = get_parent().level
	var wish := wish_dir()
	var jump_held := Input.is_action_pressed("jump")
	if Input.is_action_just_pressed("jump"): jump_buf = 0.14
	jump_buf -= dt
	aim_hold = 0.9 if Input.is_action_pressed("fire") else aim_hold - dt
	_combat(dt, wish)
	land_t = maxf(0.0, land_t - dt * 4.0)

	# --- swing hooks ---
	hook_target = _find_hook()
	if Input.is_action_just_pressed("hook") and hook_target and swing_hook == null:
		riding = false
		_start_swing(hook_target); Snd.play("hook_fire", -3); Snd.play("hook_latch", -2)
	if swing_hook:
		var released := _step_swing(dt, Input.is_action_just_pressed("jump"))
		jumps = 1; jump_cut = true; grounded = false
		if released:
			long_jump = true; Snd.play("double_jump", -3)
		else:
			_post(dt); return

	# --- grind rails ---
	rail_cool -= dt; last_rail_t -= dt
	if riding:
		if jump_buf > 0.0:
			jump_buf = 0.0; riding = false; rail_cool = 0.45
			velocity.y = maxf(velocity.y, 0.0) + JUMP; jumps = 1; jump_cut = true; long_jump = false
			Snd.play("jump", -4)
		else:
			# dash on a rail: a burst of speed (it eases back to the rail's normal top speed)
			dash_cd -= dt
			if Input.is_action_just_pressed("dash") and dash_cd <= 0.0:
				rail_speed = minf(rail_speed + 7.0, 29.0); dash_cd = 0.6; jet_burst = 1.0
				Snd.play("dash", -4); FX.sparks(global_position, Color(1, 0.8, 0.4), 10, 4.0)
			_step_rail(dt)
			_post(dt); return
	elif rail_cool <= 0.0 and level:
		_try_rail()
		if riding: Snd.play("grind_start", -3); _post(dt); return

	# --- dash ---
	dash_cd -= dt; since_dash += dt
	dash_buf -= dt
	if Input.is_action_just_pressed("dash"): dash_buf = 0.15
	if dash_buf > 0.0 and dash_cd <= 0.0:
		dash_buf = 0.0
		var dir := wish.normalized() if wish.length() > 0.8 else Vector3(sin(face_yaw), 0, cos(face_yaw))
		velocity.x = dir.x * 18.0; velocity.z = dir.z * 18.0
		dash_t = 0.16; dash_cd = 0.6; since_dash = 0.0; Snd.play("dash", -3)
		if combat: combat.invuln = maxf(combat.invuln, 0.25)   # a dash slips through shots and blasts

	var hs := Vector2(velocity.x, velocity.z).length()
	if dash_t > 0.0:
		dash_t -= dt
	elif grounded:
		# turn the run direction smoothly instead of sliding through a stop; get up to speed fast
		var want := Vector2(wish.x, wish.z).length()
		if want > 0.3:
			var cur := atan2(velocity.x, velocity.z) if hs > 0.5 else atan2(wish.x, wish.z)
			var tgt := atan2(wish.x, wish.z)
			var diff := angle_difference(cur, tgt)
			var turned := cur + clampf(diff, -16.0 * dt, 16.0 * dt)
			var speed := hs * exp(-14.0 * dt) if absf(diff) > 2.3 else hs
			speed = minf(want, speed + 55.0 * dt) if speed < want else lerpf(speed, want, 1.0 - exp(-7.0 * dt))
			velocity.x = sin(turned) * speed; velocity.z = cos(turned) * speed
		else:
			var k := exp(-16.0 * dt); velocity.x *= k; velocity.z *= k
	else:
		var cap := maxf(RUN, hs)
		var ac := 0.4 if long_jump else 1.0
		velocity.x += wish.x * 2.2 * dt * ac; velocity.z += wish.z * 2.2 * dt * ac
		if not long_jump:
			velocity.x = lerpf(velocity.x, clampf(wish.x, -cap, cap), 1.0 - exp(-2.5 * dt))
			velocity.z = lerpf(velocity.z, clampf(wish.z, -cap, cap), 1.0 - exp(-2.5 * dt))
		var nh := Vector2(velocity.x, velocity.z).length()
		if nh > cap: velocity.x *= cap / nh; velocity.z *= cap / nh

	# --- jumping ---
	coyote -= dt
	if jump_buf > 0.0:
		if grounded or coyote > 0.0:
			jump_buf = 0.0; grounded = false; coyote = 0.0; jumps = 1; jump_cut = false; jump_age = 0.0
			if since_dash < 0.28 and hs > 9.0:
				var d := Vector3(velocity.x, 0, velocity.z).normalized()
				velocity.x = d.x * LONG_SPEED; velocity.z = d.z * LONG_SPEED; velocity.y = LONG_UP
				long_jump = true; dash_t = 0.0; Snd.play("double_jump", -2)
			else:
				velocity.y = JUMP; long_jump = false; Snd.play("jump", -4)
		elif jumps < 2:
			jump_buf = 0.0; velocity.y = BOOST; jumps = 2; jet_t = 0.35; jump_cut = true; long_jump = false
			if Vector2(velocity.x, velocity.z).length() > 3.0 and aim_hold <= 0.0: flip_t = 0.42
			Snd.play("double_jump", -3)
	jump_age += dt
	if not jump_held and not jump_cut and jump_age > 0.09 and not grounded and velocity.y > 0.0 and jumps == 1 and not long_jump:
		velocity.y *= 0.55; jump_cut = true
	jet_t -= dt
	var gliding := not grounded and velocity.y < 0.0 and jump_held and jumps == 2
	var g := 0.35 if gliding else (0.7 if absf(velocity.y) < 2.5 else (1.25 if velocity.y < 0.0 else 1.0))
	velocity.y -= GRAV * dt * g
	if gliding: velocity.y = maxf(velocity.y, -3.0)
	velocity.y = maxf(velocity.y, -30.0)

	if ledge_t > 0.0:
		ledge_t -= dt
		velocity.x = ledge_dir.x * 3.2; velocity.z = ledge_dir.z * 3.2
	if slam > 0: _slam_step(dt)
	var vy_before := velocity.y
	var was_grounded := grounded
	move_and_slide()
	grounded = is_on_floor()
	if not grounded and not _no_ledge: _ledge_assist(wish)
	else: ledge_used = false
	if grounded: _edge_slip(dt, wish)
	if not grounded and vy_before < -2.0: _stomp()
	if grounded and slam == 2: _slam_land()
	if grounded:
		if not was_grounded:
			if vy_before < -6.0: land_t = clampf(-vy_before / 20.0, 0.3, 1.0)
			if vy_before < -3.0: Snd.play("land", lerpf(-10.0, 0.0, clampf(-vy_before / 20.0, 0, 1)))
			long_jump = false
		jumps = 0; coyote = 0.12
	elif was_grounded and velocity.y <= 0.0:
		jumps = 1   # walked off a ledge (coyote time still allows a jump)

	# --- bounce pads ---
	if grounded and level:
		for b in level.bouncers:
			if Vector2(global_position.x - b.pos.x, global_position.z - b.pos.z).length() < 1.15 and absf(global_position.y - b.pos.y) < 0.6:
				velocity.y = b.power; grounded = false; jumps = 1; jump_cut = true; long_jump = false; coyote = 0.0
				b.squash = 1.0; Snd.play("bounce_pad", -1); slam = 0

	# --- fell off ---
	if global_position.y < -25.0:
		respawn()
		Game.player_fell.emit()
		if combat: combat.hurt_player(1, null, true)
	if grounded and level:
		for c in level.checkpoints:
			if Vector2(global_position.x - c.pos.x, global_position.z - c.pos.z).length() < c.r and absf(global_position.y - c.pos.y) < 0.7:
				if respawn_pos.distance_to(c.pos) > 0.5: Snd.play("checkpoint", -4); Game.checkpoint_reached.emit(c.pos)
				respawn_pos = c.pos
	# footsteps and held loops
	var hs2 := Vector2(velocity.x, velocity.z).length()
	if grounded and not riding and hs2 > 2.0 and dash_t <= 0.0:
		step_t -= dt * hs2 / 8.4
		if step_t <= 0.0: step_t = 0.3; Snd.play("step_metal", -12, 0.12)
	_post(dt)

## A jump that comes up just short of a ledge (double jump already spent, Vesk pressed against its face
## and heading for it, the lip within LEDGE_MAX of his feet) pops him up onto it instead of sliding down.
func _ledge_assist(wish: Vector3) -> void:
	if ledge_used or jumps < 2 or riding or swing_hook or velocity.y > 0.5 or not is_on_wall() or level == null: return
	var n := get_wall_normal(); n.y = 0.0
	if n.length() < 0.5 or wish.length() < 2.0: return
	var into := -n.normalized()
	if wish.normalized().dot(into) < 0.55: return
	var space := get_world_3d().direct_space_state
	# only when he'd otherwise drop: with floor just below his feet he is simply walking into a step
	var q0 := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 0.1, 0), global_position - Vector3(0, 1.4, 0)); q0.collision_mask = 1; q0.exclude = [get_rid()]
	if not space.intersect_ray(q0).is_empty(): return
	var top := global_position + into * 0.62 + Vector3(0, LEDGE_MAX + 0.15, 0)
	var q := PhysicsRayQueryParameters3D.create(top, top - Vector3(0, LEDGE_MAX + 0.1, 0)); q.collision_mask = 1; q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty() or hit.normal.y < 0.75: return
	var h: float = hit.position.y - global_position.y
	if h < 0.2 or h > LEDGE_MAX: return
	# room to stand: nothing in the way from the lip up to head height, and nothing above Vesk's own head
	var q2 := PhysicsRayQueryParameters3D.create(hit.position + Vector3(0, 0.05, 0), hit.position + Vector3(0, 1.8, 0)); q2.collision_mask = 1; q2.exclude = [get_rid()]
	if not space.intersect_ray(q2).is_empty(): return
	var q3 := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 1.6, 0), global_position + Vector3(0, 1.75 + h, 0)); q3.collision_mask = 1; q3.exclude = [get_rid()]
	if not space.intersect_ray(q3).is_empty(): return
	ledge_used = true; ledge_t = 0.16; ledge_dir = into
	if OS.get_cmdline_user_args().has("--trace"): print("   LEDGE h=%.2f at %s vy=%.2f jumps=%d" % [h, global_position, velocity.y, jumps])
	velocity.y = sqrt(2.0 * GRAV * (h + 0.3)); jump_cut = true; long_jump = false
	land_t = 0.25
	Snd.play("land", -10)

var _no_slam := OS.get_cmdline_user_args().has("--no-slam")

## Height above whatever is below (INF over the void).
func _air_height() -> float:
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 0.1, 0), global_position - Vector3(0, 40, 0))
	q.collision_mask = 1; q.exclude = [get_rid()]
	var h := get_world_3d().direct_space_state.intersect_ray(q)
	return global_position.y - h.position.y if h else INF

## A slam needs real floor 2.2 m or more below (never over the void) and nothing to swing at up here.
func _slam_ok() -> bool:
	var h := _air_height()
	return h > 2.2 and h < 39.0 and not _air_target_near()

## The nearest ground bot below within 6 m (sideways) for the plunge to drift onto.
func _slam_pick() -> Node3D:
	var best: Node3D = null
	var bd := 6.0
	for b in get_tree().get_nodes_in_group("bots"):
		if b.get("dead") or not b.has_method("center") or b.get("collision_mask") == 0: continue
		var c: Vector3 = b.center()
		if c.y > global_position.y - 0.5: continue
		var d := Vector2(c.x - global_position.x, c.z - global_position.z).length()
		if d < bd: bd = d; best = b
	return best

## Something to swing at up here (a hornet at this height): then an air press stays a swing.
func _air_target_near() -> bool:
	var nt: Node3D = combat.nearest_target(global_position, 3.4) if combat else null
	return nt != null

func _slam_step(dt: float) -> void:
	if riding or swing_hook or grounded and slam == 1: slam = 0; return
	if combat: combat.invuln = maxf(combat.invuln, 0.1)
	if slam == 1:
		velocity = velocity * exp(-18.0 * dt)
		slam_t -= dt
		if slam_t <= 0.0: slam = 2
	else:
		velocity.y = -28.0
		if slam_target and is_instance_valid(slam_target) and not slam_target.get("dead"):
			# drift onto the target so it lands in the shockwave (arrives as Vesk does)
			var to: Vector3 = slam_target.center() - global_position
			var fall_t := maxf((global_position.y - slam_target.center().y) / 28.0, 0.05)
			var want := Vector3(to.x, 0, to.z) / fall_t
			if want.length() > 12.0: want = want.normalized() * 12.0
			velocity.x = lerpf(velocity.x, want.x, 1.0 - exp(-12.0 * dt)); velocity.z = lerpf(velocity.z, want.z, 1.0 - exp(-12.0 * dt))
		else:
			velocity.x *= exp(-6.0 * dt); velocity.z *= exp(-6.0 * dt)

## The slam hits the ground: a shockwave knocks back and hurts ground bots around Vesk.
func _slam_land() -> void:
	slam = 0; slam_target = null
	land_t = 0.9; jumps = 0
	if combat: combat.slam_wave(global_position)
	melee_cd = 0.3

## Coming down on top of a ground bot bounces Vesk off its head (and gives him his double jump back).
func _stomp() -> void:
	for b in get_tree().get_nodes_in_group("bots"):
		if b.get("dead") or not b.has_method("center") or b.get("state") == "drop": continue
		if b.is_class("Node3D") and b.get("collision_mask") == 0: continue   # fliers
		var c: Vector3 = b.center()
		var dy: float = global_position.y - c.y
		if dy < 0.2 or dy > 1.0: continue
		if Vector2(global_position.x - c.x, global_position.z - c.z).length() > 0.95: continue
		if slam == 2: _slam_land()
		b.damage(1.5, c + Vector3(0, 0.4, 0), Vector3.DOWN)
		if OS.get_cmdline_user_args().has("--et-stomp"): print("[enemy-test] stomp! hp now ", b.get("hp"))
		if combat: combat.damage_number(c, 1.5, b.dead)
		velocity.y = JUMP * 0.95; jumps = 1; jump_cut = true; long_jump = false; grounded = false
		land_t = 0.5; FX.puff(c + Vector3(0, 0.5, 0), Color(1, 0.85, 0.6)); FX.shake(0.35)
		Snd.play("bounce_pad", -6, 0.1, 0.0); Snd.play("melee_hit", -8)
		return

## Perched on a lip by the round bottom of his capsule (nothing under his middle): instead of hovering
## there, step him off it if he is heading out, otherwise settle him back onto the ledge (forgiving landings).
func _edge_slip(dt: float, wish: Vector3) -> void:
	var n := get_floor_normal()
	if n.y > 0.985 or riding: return
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 0.3, 0), global_position - Vector3(0, 0.3, 0)); q.collision_mask = 1; q.exclude = [get_rid()]
	if not get_world_3d().direct_space_state.intersect_ray(q).is_empty(): return
	var nh := Vector3(n.x, 0, n.z)
	if nh.length() < 0.05: return
	nh = nh.normalized()
	if wish.length() > 1.0 and wish.normalized().dot(nh) > 0.3: global_position += nh * 3.5 * dt
	else: move_and_collide(-nh * 2.5 * dt)

func respawn() -> void:
	slam = 0
	global_position = respawn_pos; velocity = Vector3.ZERO; riding = false; swing_hook = null; rope.visible = false
	dash_t = 0.0; long_jump = false; jumps = 0
	if not is_nan(respawn_yaw): cam.yaw = respawn_yaw; face_yaw = respawn_yaw
	if cam.has_method("snap"): cam.snap(self)
	Game.player_respawned.emit(respawn_pos)

func _muzzle() -> Vector3:
	var wm: Node3D = weapon_models.get(held_weapon)
	if wm and wm.visible:
		var mz: Node3D = wm.get_meta("muzzle")
		if mz: return mz.global_position
	var i := skel.find_bone("gun")
	var t := skel.global_transform * skel.get_bone_global_pose(i)
	return t.origin + t.basis.y.normalized() * 0.42

func _combat(dt: float, wish: Vector3) -> void:
	if combat == null: return
	# what's under the crosshair
	var from: Vector3 = cam.camera.global_position
	var dir: Vector3 = cam.aim_dir()
	var q := PhysicsRayQueryParameters3D.create(from + dir * 1.0, from + dir * 150.0)
	q.collision_mask = 1 | 4; q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	aim_point = hit.position if hit else from + dir * 150.0
	if combat.try_fire(dt, Input.is_action_pressed("fire") and swing_hook == null and not Game.input_locked, _muzzle(), aim_point, dir):
		weapon_kick = 1.0
	# melee: a wide swing with a small lunge toward the nearest bot
	melee_cd -= dt; combo_window -= dt
	# a press a moment early (mid-swing) is kept and fires when the swing allows, so combos flow
	melee_buf -= dt
	if Input.is_action_just_pressed("melee") and not Game.input_locked: melee_buf = 0.2
	var melee_go := melee_buf > 0.0 and melee_cd <= 0.0
	if melee_go: melee_buf = 0.0
	if melee_go and slam == 0 \
			and not grounded and not riding and swing_hook == null and velocity.y < 4.0 and not _no_slam and _slam_ok():
		# high in the air: the swing becomes a slam (hang a beat, plunge, shockwave on landing)
		slam = 1; slam_t = 0.14; spin_t = 0.3; melee_cd = 0.3; combo = 0
		slam_target = _slam_pick()
		Snd.play("melee_swing", -1, 0.05, 0.0); Snd.play("dash", -4, 0.0, 0.0, 0.8)
	elif melee_go and slam == 0:
		combo = combo + 1 if combo_window > 0.0 and combo < 3 else 1
		var fin := combo == 3
		melee_cd = 0.6 if fin else 0.24; combo_window = 0.0 if fin else 0.6
		melee_hit = 0.12 if fin else 0.09; melee_t = 0.42 if fin else 0.32
		if fin: spin_t = 0.3
		else: twist = 0.55 if combo == 1 else -0.65
		anim.play("melee", 0.04); anim.seek(0.0, true); cur_anim = "melee"
		Snd.play("melee_swing", -3 + (1.0 if fin else 0.0), 0.08, 0.0)
		var nt: Node3D = combat.nearest_target(global_position, 4.0 if fin else 3.4)
		if nt:
			var d: Vector3 = nt.center() - global_position
			face_yaw = atan2(d.x, d.z)
		var lunge := 7.5 if fin else (5.0 if combo == 1 else 5.8)
		var fwd := Vector3(sin(face_yaw), 0, cos(face_yaw))
		if grounded:
			var keep := Vector3(velocity.x, 0, velocity.z).dot(fwd)
			velocity.x = fwd.x * maxf(keep, 0.0) * 0.4 + fwd.x * lunge; velocity.z = fwd.z * maxf(keep, 0.0) * 0.4 + fwd.z * lunge
		else:
			velocity += fwd * lunge * 0.6
			if velocity.y < 0.0: velocity.y *= 0.4   # swings hang Vesk in the air a moment
	if melee_hit > 0.0:
		melee_hit -= dt
		if melee_hit <= 0.0:
			combat.melee(global_position, Vector3(sin(face_yaw), 0, cos(face_yaw)), combo)

func _post(dt: float) -> void:
	Snd.loop("grind_loop", riding, -6)
	Snd.loop("glide", not grounded and not riding and velocity.y < 0.0 and jumps == 2 and Input.is_action_pressed("jump"), -8)
	cam.update(dt, self)
	_face(dt)
	_animate(dt)

# ---------- rails ----------
func _try_rail() -> void:
	# test where Vesk is now and half a step back along his motion, so a fast drop or a jump across
	# the rail can't slip between two physics frames; the catch box is a little generous on purpose
	var dt := get_physics_process_delta_time()
	for p in [global_position, global_position - velocity * dt * 0.5]:
		if _catch_rail(p): return

func _catch_rail(p: Vector3) -> bool:
	for i in level.rails.size():
		var r: Dictionary = level.rails[i]
		if r.locked: continue
		if r == last_rail and last_rail_t > 0.0: continue
		var local: Vector3 = r.path.to_local(p)
		var off: float = r.curve.get_closest_offset(local)
		var q: Vector3 = r.path.to_global(r.curve.sample_baked(off))
		var dy := p.y - q.y
		var falling := velocity.y < -1.0
		if dy < (-0.8 if falling else -0.55) or dy > (1.0 if falling else 0.75): continue
		if Vector2(p.x - q.x, p.z - q.z).length() > (1.4 if not grounded else 1.0): continue
		if velocity.y > 2.0 and p.y < q.y: continue
		var t0: Vector3 = r.curve.sample_baked(clampf(off - 0.3, 0, r.length))
		var t1: Vector3 = r.curve.sample_baked(clampf(off + 0.3, 0, r.length))
		var along := velocity.dot((r.path.global_transform.basis * (t1 - t0)).normalized())
		# standing near an end with no clear direction: don't snap on and get carried back along it
		if absf(along) <= 1.0 and grounded and (off < 2.0 or off > r.length - 2.0): continue
		riding = true; rail = r; rail_off = off
		rail_dir = signf(along) if absf(along) > 1.0 else (1.0 if off < r.length * 0.5 else -1.0)
		rail_speed = maxf(12.0, absf(along))
		jumps = 0; grounded = true
		return true
	return false

func _rail_tangent() -> Vector3:
	var a: Vector3 = rail.curve.sample_baked(clampf(rail_off - 0.3, 0, rail.length))
	var b: Vector3 = rail.curve.sample_baked(clampf(rail_off + 0.3, 0, rail.length))
	return (rail.path.global_transform.basis * (b - a)).normalized()

func _step_rail(dt: float) -> void:
	var tan := _rail_tangent()
	rail_speed = clampf(rail_speed - tan.y * rail_dir * 14.0 * dt, 10.0, 29.0)
	if rail_speed > 22.0: rail_speed = lerpf(rail_speed, 22.0, 1.0 - exp(-1.2 * dt))
	rail_off += rail_dir * rail_speed * dt
	var done: bool = rail_off <= 0.0 or rail_off >= rail.length
	var q: Vector3 = rail.path.to_global(rail.curve.sample_baked(clampf(rail_off, 0, rail.length)))
	global_position = q + Vector3(0, 0.13, 0)
	velocity = tan * rail_dir * rail_speed
	grounded = true; jumps = 0; coyote = 0.12
	if Vector2(velocity.x, velocity.z).length() > 2.0:
		cam.yaw += angle_difference(cam.yaw, atan2(velocity.x, velocity.z)) * (1.0 - exp(-1.1 * dt))
	if done:
		last_rail = rail; last_rail_t = 1.2
		riding = false; rail_cool = 0.45; velocity.y += 3.0; grounded = false; jumps = 1

# ---------- swing hooks ----------
func _find_hook() -> Node3D:
	if level == null or swing_hook: return null
	var best: Node3D = null
	var bs := INF
	var look: Vector3 = cam.aim_dir(); look.y = 0; look = look.normalized()
	for h in level.hooks:
		var d: Vector3 = h.global_position - global_position
		var dist := d.length()
		if dist > HOOK_RANGE or dist < 4.0 or d.y < 1.5: continue
		var facing := Vector3(d.x, 0, d.z).normalized().dot(look)
		if facing < 0.2: continue
		var s := dist * (1.6 - facing)
		if s < bs: bs = s; best = h
	return best

func _start_swing(h: Node3D) -> void:
	var d := h.global_position - global_position
	swing_hook = h; swing_t = 0.0; swing_L = d.length()
	swing_dirv = Vector3(d.x, 0, d.z).normalized()
	swing_A = atan2(Vector2(d.x, d.z).length(), d.y)

func _step_swing(dt: float, let_go: bool) -> bool:
	swing_t += dt
	var k := minf(swing_t / SWING_T, RELEASE)
	var th := -swing_A * cos(PI * k)
	var N := swing_hook.global_position
	global_position = N + swing_dirv * swing_L * sin(th) + Vector3(0, -swing_L * cos(th), 0)
	var w := swing_A * PI / SWING_T * sin(PI * k)
	var sp := minf(16.0, swing_L * w)
	velocity = swing_dirv * cos(th) * sp + Vector3(0, sin(th) * sp, 0)
	var hand := global_position + Vector3(0, 1.2, 0)
	rope.visible = true
	rope.global_position = (hand + N) * 0.5
	var up := (N - hand).normalized()
	rope.global_basis = Basis(Quaternion(Vector3.UP, up)).scaled(Vector3(1, hand.distance_to(N), 1))
	if k >= RELEASE or (let_go and swing_t > 0.25):
		swing_hook = null; rope.visible = false
		velocity.y += 4.0
		velocity += Vector3(velocity.x, 0, velocity.z).normalized() * 2.0
		return true
	return false

# ---------- facing + procedural animation ----------
func _face(dt: float) -> void:
	var hv := Vector2(velocity.x, velocity.z)
	var target := face_yaw
	var aiming := aim_hold > 0.0
	if aiming:
		var ad := aim_point - global_position
		target = atan2(ad.x, ad.z) - asin(clampf(0.3 / maxf(Vector2(ad.x, ad.z).length(), 0.8), -0.6, 0.6)) if Vector2(ad.x, ad.z).length() > 0.8 else cam.yaw
	elif hv.length() > 0.8: target = atan2(hv.x, hv.y)
	var prev := face_yaw
	face_yaw += angle_difference(face_yaw, target) * (1.0 - exp(-(20.0 if aiming else 13.0) * dt))
	turn_rate = lerpf(turn_rate, angle_difference(prev, face_yaw) / maxf(dt, 1e-4), 1.0 - exp(-10.0 * dt))
	spin_t = maxf(0.0, spin_t - dt)
	twist = lerpf(twist, 0.0, 1.0 - exp(-11.0 * dt))
	model.rotation.y = face_yaw + twist - TAU * (1.0 - smoothstep(0.0, 0.3, spin_t)) * (1.0 if spin_t > 0.0 else 0.0)

## Holds the blaster out front with the right arm (the animation set has no gun-holding clips):
## the upper arm hangs slightly forward and the forearm and hand point where Vesk aims.
func _pose_gun_arm(dt: float, aiming: bool) -> void:
	if arm_bones.size() < 3 or arm_bones[0] < 0: return
	var want := 0.0 if (melee_t > 0.0 or swing_hook or riding) else 1.0
	arm_hold = lerpf(arm_hold, want, 1.0 - exp(-14.0 * dt))
	if arm_hold < 0.02: return
	var p := pitch_s * 0.8 + (0.0 if aiming else -0.15)
	var dirs := [Vector3(-0.18, -0.8, 0.45).normalized(), Vector3(0.12, sin(p), cos(p)).normalized(), Vector3(0.05, sin(p), cos(p)).normalized()]
	var parent_b := skel.get_bone_global_pose(skel.get_bone_parent(arm_bones[0])).basis.orthonormalized()
	for k in 3:
		var i: int = arm_bones[k]
		var anim_g := (parent_b * Basis(skel.get_bone_pose_rotation(i))).orthonormalized()
		var cur_y := anim_g.y.normalized()
		var q := Quaternion(cur_y, cur_y.slerp(dirs[k], arm_hold).normalized()) if cur_y.cross(dirs[k]).length() > 1e-4 else Quaternion()
		var tgt := (Basis(q) * anim_g).orthonormalized()
		skel.set_bone_pose_rotation(i, (parent_b.inverse() * tgt).get_rotation_quaternion())
		parent_b = tgt

func _play(n: String, blend := 0.15, spd := 1.0) -> void:
	anim.speed_scale = spd
	if n != cur_anim:
		cur_anim = n
		anim.play(n, blend)

func _animate(dt: float) -> void:
	anim_t += dt
	var aiming := aim_hold > 0.0
	var speed := Vector2(velocity.x, velocity.z).length()
	var run := minf(1.0, speed / 7.0)
	var vy := velocity.y
	var dashing := dash_t > 0.0 or long_jump
	melee_t = maxf(0.0, melee_t - dt)
	land_play = maxf(0.0, land_play - dt)
	if land_t > 0.55 and land_play <= 0.0 and grounded and speed < 4.0: land_play = 0.3
	# pick the animation for what Vesk is doing
	if melee_t > 0.0: _play("melee", 0.06, 3.0)
	elif swing_hook: _play("swing", 0.12)
	elif riding: _play("grind", 0.15)
	elif dashing and not grounded: _play("dash", 0.08)
	elif dash_t > 0.0: _play("dash", 0.05)
	elif not grounded:
		if jumps == 2 and vy < 0.0 and Input.is_action_pressed("jump"): _play("glide", 0.2)
		elif vy > 1.0: _play("jump", 0.08)
		else: _play("fall", 0.25)
	elif land_play > 0.0: _play("land", 0.05)
	elif speed > 0.6: _play("run", 0.12, clampf(speed / 8.4, 0.6, 1.7))
	else: _play("idle", 0.2)
	# bones we add to procedurally go back to rest first, so clips that don't key them can't let our offsets pile up
	for i in [bones.get("spine", -1), bones.get("chest", -1)] + arm_bones:
		if i >= 0: skel.reset_bone_pose(i)
	anim.advance(dt)
	# aim: lean the upper body toward the crosshair (or hold the blaster low when not shooting)
	var aim_pitch: float = cam.pitch if aiming else -0.25
	pitch_s = lerpf(pitch_s, aim_pitch, 1.0 - exp(-(20.0 if aiming else 8.0) * dt))
	# rotate about the model's sideways axis, expressed in each bone's own frame (the bones' rest axes vary)
	for b in ["spine", "chest"]:
		var i: int = bones[b]
		if i < 0: continue
		var gb := skel.get_bone_global_pose(i).basis.orthonormalized()
		var ax := (gb.inverse() * Vector3.RIGHT).normalized()
		skel.set_bone_pose_rotation(i, skel.get_bone_pose_rotation(i) * Quaternion(ax, -pitch_s * 0.5))
	_pose_gun_arm(dt, aiming)
	# body: bank into turns, squash on landing
	lean = lerpf(lean, clampf(-turn_rate * 0.09 * maxf(run, 0.3), -0.35, 0.35), 1.0 - exp(-10.0 * dt))
	if riding or swing_hook: lean = lerpf(lean, 0.0, 1.0 - exp(-12.0 * dt))
	# flinch: rock back away from the hit and flash red for a moment
	hurt_t = maxf(0.0, hurt_t - dt)
	var fl := sin(clampf(hurt_t / 0.35, 0.0, 1.0) * PI) * 0.35
	for m in fur_mats: (m as StandardMaterial3D).emission_energy_multiplier = (hurt_t / 0.35) * 1.6
	flip_t = maxf(0.0, flip_t - dt)
	if grounded or riding or swing_hook: flip_t = 0.0
	var flip := TAU * smoothstep(0.42, 0.0, flip_t) if flip_t > 0.0 else 0.0
	body.rotation = Vector3(-fl + flip, 0, lean)
	# the flip turns about Vesk's middle, not his feet
	var piv := Vector3(0, 0.85, 0)
	body.position = piv - Basis.from_euler(body.rotation) * piv if flip != 0.0 else Vector3.ZERO
	body.scale = Vector3(1 + land_t * 0.08, 1 - land_t * 0.1, 1 + land_t * 0.08)
	_update_weapon(dt)
	_update_jets(dt)

# ---------- weapons in hand ----------
const WEAPON_MODELS := { arc_lancer = "res://models/wpn_lancer.glb", scatter_bloom = "res://models/wpn_scatter.glb", thump_lobber = "res://models/wpn_lobber.glb",
	seeker_hive = "res://models/wpn_seeker.glb" }

func _build_weapons() -> void:
	gun_bone = skel.find_bone("gun")
	if gun_bone < 0: return
	# find which axis of the gun bone points up on the model, so attached guns sit upright
	var rest := skel.get_bone_global_rest(gun_bone)
	var up_s := (skel.global_transform.basis.inverse() * Vector3.UP).normalized()
	var best := -2.0
	for ax in [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]:
		var d: float = (rest.basis * ax).normalized().dot(up_s)
		if d > best: best = d; gun_up_axis = ax
	for id in WEAPON_MODELS:
		if not ResourceLoader.exists(WEAPON_MODELS[id]): continue
		var holder := Node3D.new(); holder.name = "Wpn_" + id; holder.top_level = true; holder.visible = false
		body.add_child(holder)
		var m: Node3D = load(WEAPON_MODELS[id]).instantiate()
		holder.add_child(m)
		_shadows(m)
		holder.set_meta("muzzle", m.find_child("muzzle_*", true, false))
		holder.set_meta("lv", 0)
		weapon_models[id] = holder
	# Arc Lancer level glow: coils that brighten with each level (gold and crackling at V5)
	lancer_fx = Node3D.new(); lancer_fx.top_level = true; lancer_fx.visible = false; body.add_child(lancer_fx)
	for i in 2:
		var tm := TorusMesh.new(); tm.inner_radius = 0.06; tm.outer_radius = 0.085; tm.rings = 16; tm.ring_segments = 8
		var mi := MeshInstance3D.new(); mi.mesh = tm; mi.position = Vector3(0, 0.02, 0.3 + i * 0.16); mi.rotation.x = PI / 2
		var mat := StandardMaterial3D.new(); mat.albedo_color = Color.BLACK; mat.emission_enabled = true
		mat.emission = Color(0.45, 0.95, 1.0); mat.emission_energy_multiplier = 3.0
		mi.material_override = mat; mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lancer_fx.add_child(mi)

## Paints a weapon for its level: glow parts brighten V1-V4, V5 turns them gold and the gun grows.
func _weapon_look(holder: Node3D, id: String, lv: int) -> void:
	holder.set_meta("lv", lv)
	var c: Color = combat.weapon_color(id)
	var m := StandardMaterial3D.new(); m.albedo_color = Color.BLACK; m.emission_enabled = true
	m.emission = c; m.emission_energy_multiplier = 2.0 + lv * 1.2
	for mi in holder.find_children("*", "MeshInstance3D", true, false):
		var n := String(mi.name)
		if n.contains("glow") or n.begins_with("petal") or n.begins_with("tip_") or n.begins_with("bomb_") or (lv >= 5 and (n.begins_with("shell") or n == "drum_band" or n == "pod_ring")):
			mi.material_override = m
	holder.set_meta("scale", 1.0 + 0.03 * (lv - 1) + (0.08 if lv >= 5 else 0.0))

func _update_weapon(dt: float) -> void:
	if gun_bone < 0 or combat == null: return
	held_weapon = combat.current
	weapon_kick = maxf(0.0, weapon_kick - dt * 9.0)
	var t := skel.global_transform * skel.get_bone_global_pose(gun_bone)
	var f := t.basis.y.normalized()
	var up := body.global_transform.basis.y.normalized()
	var right := up.cross(f).normalized()
	up = f.cross(right).normalized()
	var b := Basis(right, up, f)
	var origin := t.origin - f * 0.07 * weapon_kick
	for id in weapon_models:
		var h: Node3D = weapon_models[id]
		h.visible = id == held_weapon
		if not h.visible: continue
		var lv: int = combat.level(id)
		if int(h.get_meta("lv")) != lv: _weapon_look(h, id, lv)
		h.global_transform = Transform3D(b.scaled(Vector3.ONE * float(h.get_meta("scale", 1.0))), origin)
	# the Arc Lancer is skinned into the hero mesh: fold it away while another gun is out
	var llv: int = combat.level("arc_lancer")
	lancer_fx.visible = held_weapon == "arc_lancer" and llv >= 2
	if lancer_fx.visible:
		lancer_fx.global_transform = Transform3D(b, t.origin)
		var hot: float = combat.heat
		for c in lancer_fx.get_children():
			var mat: StandardMaterial3D = c.material_override
			mat.emission = combat.weapon_color("arc_lancer").lerp(Color(1, 0.35, 0.2), hot * hot)
			mat.emission_energy_multiplier = 1.5 + llv * 1.0 + (randf() * 4.0 if llv >= 5 else 0.0)

# ---------- jetpack flames ----------
func _build_flames() -> void:
	chest_bone = skel.find_bone("chest")
	if chest_bone < 0: return
	var rest_chest := skel.get_bone_global_rest(chest_bone)
	var skel_in_body := body.global_transform.affine_inverse() * skel.global_transform
	flame_mat_core = _flame_mat(Color(0.85, 0.97, 1.0), 6.0)
	flame_mat_outer = _flame_mat(Color(0.25, 0.8, 1.0), 3.5)
	flame_mat_outer.albedo_color.a = 0.55
	var spark_mat := _flame_mat(Color(0.5, 0.95, 1.0), 4.0)
	spark_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	spark_mat.vertex_color_use_as_albedo = true
	var g := GradientTexture2D.new(); g.fill = GradientTexture2D.FILL_RADIAL; g.fill_from = Vector2(0.5, 0.5); g.fill_to = Vector2(1, 0.5)
	var gr := Gradient.new(); gr.set_color(0, Color.WHITE); gr.set_color(1, Color(1, 1, 1, 0)); g.gradient = gr
	spark_mat.albedo_texture = g
	for sx in [-1, 1]:
		var nozzle_body := Transform3D(Basis(), Vector3(0.17 * sx, 0.86, -0.36))
		jet_offsets.append(rest_chest.affine_inverse() * skel_in_body.affine_inverse() * nozzle_body)
		var pivot := Node3D.new(); pivot.top_level = true; body.add_child(pivot)
		var core := MeshInstance3D.new(); var cm := CylinderMesh.new()
		cm.top_radius = 0.05; cm.bottom_radius = 0.0; cm.height = 0.5; cm.radial_segments = 12; cm.rings = 1
		core.mesh = cm; core.position.y = -0.25; core.material_override = flame_mat_core
		var outer := MeshInstance3D.new(); var om := CylinderMesh.new()
		om.top_radius = 0.08; om.bottom_radius = 0.012; om.height = 0.75; om.radial_segments = 12; om.rings = 1
		outer.mesh = om; outer.position.y = -0.37; outer.material_override = flame_mat_outer
		for mi in [core, outer]:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			pivot.add_child(mi)
		var p := CPUParticles3D.new()
		var q := QuadMesh.new(); q.size = Vector2(0.09, 0.09); p.mesh = q; p.material_override = spark_mat
		p.amount = 28; p.lifetime = 0.32; p.local_coords = false; p.emitting = false
		p.direction = Vector3(0, -1, 0); p.spread = 14.0
		p.initial_velocity_min = 5.0; p.initial_velocity_max = 9.0
		p.gravity = Vector3(0, 2.0, 0); p.damping_min = 4.0; p.damping_max = 8.0
		p.scale_amount_min = 0.6; p.scale_amount_max = 1.5
		var cr := Curve.new(); cr.add_point(Vector2(0, 1)); cr.add_point(Vector2(1, 0)); p.scale_amount_curve = cr
		var ramp := Gradient.new(); ramp.set_color(0, Color(1, 1, 1, 1)); ramp.set_color(1, Color(0.2, 0.6, 1.0, 0.0)); p.color_ramp = ramp
		pivot.add_child(p)
		pivot.scale = Vector3.ONE * 0.01
		flames.append({ pivot = pivot, core = core, outer = outer, sparks = p })

func _flame_mat(c: Color, e: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(c.r * e * 0.25, c.g * e * 0.25, c.b * e * 0.25, 1.0)
	return m

## Flames fire on jumps (a puff), the double jump and long jump (big bursts), the dash (a burst
## angled back) and burn steady while gliding.
func _update_jets(dt: float) -> void:
	var vy := velocity.y
	if jumps >= 1 and _prev_jumps == 0 and vy > 4.0 and vy < 11.5 and not riding and swing_hook == null:
		jet_burst = maxf(jet_burst, 0.6)
	if jumps == 2 and _prev_jumps < 2: jet_burst = 1.15
	if dash_t > _prev_dash + 0.05: jet_burst = 1.0
	if long_jump and not _prev_long: jet_burst = 1.2
	_prev_jumps = jumps; _prev_dash = dash_t; _prev_long = long_jump
	jet_burst = maxf(0.0, jet_burst - dt * 3.2)
	var gliding := not grounded and not riding and swing_hook == null and vy < 0.0 and jumps == 2 and Input.is_action_pressed("jump")
	var steady := 0.0
	if gliding: steady = 0.55
	if jet_t > 0.0: steady = maxf(steady, 0.9)
	if force_jets >= 0.0: steady = force_jets
	var target := maxf(steady, jet_burst)
	jet_power = lerpf(jet_power, target, 1.0 - exp(-(30.0 if target > jet_power else 10.0) * dt))
	var tilt_to := 1.05 if dash_t > 0.0 else (0.75 if long_jump and not grounded else 0.0)
	jet_tilt = lerpf(jet_tilt, tilt_to, 1.0 - exp(-14.0 * dt))
	for j in jets: j.light_energy = 0.3 + jet_power * (3.0 + randf())
	if chest_bone < 0: return
	var chest := skel.global_transform * skel.get_bone_global_pose(chest_bone)
	for i in flames.size():
		var fl: Dictionary = flames[i]
		var pv: Node3D = fl.pivot
		var on := jet_power > 0.04
		var flick := 0.85 + randf() * 0.3
		var xf: Transform3D = chest * jet_offsets[i]
		xf.basis = xf.basis.orthonormalized() * Basis(Vector3.RIGHT, jet_tilt)
		pv.global_transform = xf
		pv.scale = Vector3(0.6 + jet_power * 0.6, maxf(0.01, jet_power * flick * 1.3), 0.6 + jet_power * 0.6) if on else Vector3.ONE * 0.01
		(fl.sparks as CPUParticles3D).emitting = jet_power > 0.3
