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
var level: Node3D
var respawn_pos := Vector3.ZERO
var model: Node3D
var body: Node3D
var skel: Skeleton3D
var anim: AnimationPlayer
var bones := {}
var cur_anim := "idle"
var melee_t := 0.0
var land_play := 0.0
var jets: Array = []

var grounded := false
var jumps := 0
var coyote := 0.0
var jump_buf := 0.0
var jump_age := 0.0
var jump_cut := false
var long_jump := false
var dash_t := 0.0
var dash_cd := 0.0
var since_dash := 9.0
var jet_t := 0.0
var land_t := 0.0
var face_yaw := PI
var turn_rate := 0.0
var aim_hold := 0.0
var using_pad := false

# rails and hooks
var riding := false
var rail: Dictionary
var rail_off := 0.0
var rail_dir := 1.0
var rail_speed := 0.0
var rail_cool := 0.0
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
var anim_t := 0.0

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
	body.add_child(hero)
	_shadows(hero)
	skel = hero.find_child("Skeleton3D", true, false)
	anim = hero.find_child("AnimationPlayer", true, false)
	anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for n in ["idle", "run", "fall", "dash", "glide", "grind", "swing"]:
		anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	anim.play("idle")
	for b in ["pelvis", "spine", "chest", "neck", "head"]: bones[b] = skel.find_bone(b)
	for sx in [-1, 1]:
		var l := OmniLight3D.new(); l.light_color = Color(0.3, 0.9, 1); l.light_energy = 0.0; l.omni_range = 2.5
		l.position = Vector3(0.15 * sx, 0.66, -0.3)
		body.add_child(l); jets.append(l)
	rope = MeshInstance3D.new()
	var rm := CylinderMesh.new(); rm.top_radius = 0.035; rm.bottom_radius = 0.035; rm.height = 1.0
	rope.mesh = rm
	var gm := StandardMaterial3D.new(); gm.albedo_color = Color.BLACK; gm.emission_enabled = true; gm.emission = Color(1, 0.8, 0.35); gm.emission_energy_multiplier = 3
	rope.material_override = gm
	rope.top_level = true; rope.visible = false
	add_child(rope)
	level = get_parent().get_node_or_null("Level") if get_parent() else null

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
	land_t = maxf(0.0, land_t - dt * 4.0)

	# --- swing hooks ---
	hook_target = _find_hook()
	if Input.is_action_just_pressed("hook") and hook_target and swing_hook == null:
		riding = false
		_start_swing(hook_target)
	if swing_hook:
		var released := _step_swing(dt, Input.is_action_just_pressed("jump"))
		jumps = 1; jump_cut = true; grounded = false
		if released:
			long_jump = true
		else:
			_post(dt); return

	# --- grind rails ---
	rail_cool -= dt
	if riding:
		if jump_buf > 0.0:
			jump_buf = 0.0; riding = false; rail_cool = 0.45
			velocity.y = maxf(velocity.y, 0.0) + JUMP; jumps = 1; jump_cut = true; long_jump = false
		else:
			_step_rail(dt)
			_post(dt); return
	elif rail_cool <= 0.0 and level:
		_try_rail()
		if riding: _post(dt); return

	# --- dash ---
	dash_cd -= dt; since_dash += dt
	if Input.is_action_just_pressed("dash") and dash_cd <= 0.0:
		var dir := wish.normalized() if wish.length() > 0.8 else Vector3(sin(face_yaw), 0, cos(face_yaw))
		velocity.x = dir.x * 18.0; velocity.z = dir.z * 18.0
		dash_t = 0.16; dash_cd = 0.6; since_dash = 0.0

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
				long_jump = true; dash_t = 0.0
			else:
				velocity.y = JUMP; long_jump = false
		elif jumps < 2:
			jump_buf = 0.0; velocity.y = BOOST; jumps = 2; jet_t = 0.35; jump_cut = true; long_jump = false
	jump_age += dt
	if not jump_held and not jump_cut and jump_age > 0.09 and not grounded and velocity.y > 0.0 and jumps == 1 and not long_jump:
		velocity.y *= 0.55; jump_cut = true
	jet_t -= dt
	var gliding := not grounded and velocity.y < 0.0 and jump_held and jumps == 2
	var g := 0.35 if gliding else (0.7 if absf(velocity.y) < 2.5 else (1.25 if velocity.y < 0.0 else 1.0))
	velocity.y -= GRAV * dt * g
	if gliding: velocity.y = maxf(velocity.y, -3.0)
	velocity.y = maxf(velocity.y, -30.0)

	var vy_before := velocity.y
	var was_grounded := grounded
	move_and_slide()
	grounded = is_on_floor()
	if grounded:
		if not was_grounded:
			if vy_before < -6.0: land_t = clampf(-vy_before / 20.0, 0.3, 1.0)
			long_jump = false
		jumps = 0; coyote = 0.12
	elif was_grounded and velocity.y <= 0.0:
		jumps = 1   # walked off a ledge (coyote time still allows a jump)

	# --- bounce pads ---
	if grounded and level:
		for b in level.bouncers:
			if Vector2(global_position.x - b.pos.x, global_position.z - b.pos.z).length() < 1.15 and absf(global_position.y - b.pos.y) < 0.6:
				velocity.y = b.power; grounded = false; jumps = 1; jump_cut = true; long_jump = false; coyote = 0.0
				b.squash = 1.0

	# --- fell off ---
	if global_position.y < -25.0:
		global_position = respawn_pos; velocity = Vector3.ZERO
	if grounded and level:
		for c in level.checkpoints:
			if Vector2(global_position.x - c.pos.x, global_position.z - c.pos.z).length() < c.r and absf(global_position.y - c.pos.y) < 0.7:
				respawn_pos = c.pos
	_post(dt)

func _post(dt: float) -> void:
	cam.update(dt, self)
	_face(dt)
	_animate(dt)

# ---------- rails ----------
func _try_rail() -> void:
	var p := global_position
	for i in level.rails.size():
		var r: Dictionary = level.rails[i]
		if r.locked: continue
		var local: Vector3 = r.path.to_local(p)
		var off: float = r.curve.get_closest_offset(local)
		var q: Vector3 = r.path.to_global(r.curve.sample_baked(off))
		var dy := p.y - q.y
		if dy < -0.55 or dy > 0.7: continue
		if Vector2(p.x - q.x, p.z - q.z).length() > 1.0: continue
		if velocity.y > 2.0 and p.y < q.y: continue
		riding = true; rail = r; rail_off = off
		var tan := _rail_tangent()
		var along := velocity.dot(tan)
		rail_dir = signf(along) if absf(along) > 1.0 else (1.0 if off < r.length * 0.5 else -1.0)
		rail_speed = maxf(12.0, absf(along))
		jumps = 0; grounded = true
		return

func _rail_tangent() -> Vector3:
	var a: Vector3 = rail.curve.sample_baked(clampf(rail_off - 0.3, 0, rail.length))
	var b: Vector3 = rail.curve.sample_baked(clampf(rail_off + 0.3, 0, rail.length))
	return (rail.path.global_transform.basis * (b - a)).normalized()

func _step_rail(dt: float) -> void:
	var tan := _rail_tangent()
	rail_speed = clampf(rail_speed - tan.y * rail_dir * 14.0 * dt, 10.0, 22.0)
	rail_off += rail_dir * rail_speed * dt
	var done: bool = rail_off <= 0.0 or rail_off >= rail.length
	var q: Vector3 = rail.path.to_global(rail.curve.sample_baked(clampf(rail_off, 0, rail.length)))
	global_position = q + Vector3(0, 0.13, 0)
	velocity = tan * rail_dir * rail_speed
	grounded = true; jumps = 0; coyote = 0.12
	if Vector2(velocity.x, velocity.z).length() > 2.0:
		cam.yaw += angle_difference(cam.yaw, atan2(velocity.x, velocity.z)) * (1.0 - exp(-1.1 * dt))
	if done:
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
	if aiming: target = cam.yaw
	elif hv.length() > 0.8: target = atan2(hv.x, hv.y)
	var prev := face_yaw
	face_yaw += angle_difference(face_yaw, target) * (1.0 - exp(-(20.0 if aiming else 13.0) * dt))
	turn_rate = lerpf(turn_rate, angle_difference(prev, face_yaw) / maxf(dt, 1e-4), 1.0 - exp(-10.0 * dt))
	model.rotation.y = face_yaw

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
	if melee_t > 0.0: _play("melee", 0.06)
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
	anim.advance(dt)
	# aim: lean the upper body toward the crosshair (or hold the blaster low when not shooting)
	var aim_pitch: float = cam.pitch if aiming else -0.25
	pitch_s = lerpf(pitch_s, aim_pitch, 1.0 - exp(-(20.0 if aiming else 8.0) * dt))
	for b in ["spine", "chest"]:
		var i: int = bones[b]
		skel.set_bone_pose_rotation(i, skel.get_bone_pose_rotation(i) * Quaternion(Vector3.RIGHT, -pitch_s * 0.5))
	# body: bank into turns, squash on landing
	lean = lerpf(lean, clampf(-turn_rate * 0.09 * maxf(run, 0.3), -0.35, 0.35), 1.0 - exp(-10.0 * dt))
	if riding or swing_hook: lean = lerpf(lean, 0.0, 1.0 - exp(-12.0 * dt))
	body.rotation = Vector3(0, 0, lean)
	body.scale = Vector3(1 + land_t * 0.08, 1 - land_t * 0.1, 1 + land_t * 0.08)
	var jetting := jet_t > 0.0 or (not grounded and jumps == 2 and vy > -3.0)
	for j in jets: j.light_energy = (2.5 + randf()) if jetting else 0.3
