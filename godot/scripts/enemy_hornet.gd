extends "res://scripts/enemy.gd"
## Tin Hornet: swoops in from above, circles Vesk at a distance and fires red bolts.
##   Telegraph   it buzzes, its eye charges up and a thin red aim line points at Vesk; the line freezes
##               for the last moment before the shot, so a sidestep or a jump dodges it
##   Hit         it is batted off course and wobbles; a hit while charging staggers it and delays the shot
##   Death       it spins down trailing smoke and bursts when it hits the ground (or after a moment)

const AIM_T := 0.95       # how long the aim line shows before the shot
const LOCK_T := 0.22      # the aim freezes this long before firing

var inner: Node3D
var fire_t := 2.0
var orbit_a := 0.0
var orbit_r := 10.0
var height := 4.0
var spawn_t := 1.0
var eye_light: OmniLight3D
var aim_line: MeshInstance3D
var aim_mat: StandardMaterial3D
var aim_at := Vector3.ZERO
var aiming := false
var wobble := 0.0
var fall_t := 0.0
var spin_v := 0.0
var buzz_t := 0.0
var wings: Array = []

var beacon_mat: StandardMaterial3D

func _ready() -> void:
	hp = 4.0; max_hp = 4.0; nuts = 8
	stagger_time = 0.3
	burst_color = Color(1, 0.3, 0.2)
	var cs := CollisionShape3D.new(); var sh := SphereShape3D.new(); sh.radius = 0.85
	cs.shape = sh; add_child(cs)
	collision_mask = 0
	setup_model("res://models/hornet.glb")
	inner = model.find_child("inner", true, false)
	wings = [model.find_child("wing_L", true, false), model.find_child("wing_R", true, false)]
	wings = wings.filter(func(w): return w != null)
	for x in [-0.14, 0.14]: add_eye(inner if inner else model, Vector3(x, 0.2, 0.56), 0.065, Color(1, 0.15, 0.08), 5.0)
	scrap_count = 11
	# night-shift paint job: rust orange, a touch smaller and quicker-looking, with a spinning beacon
	if roll_variant() and inner:
		apply_variant(Color(1.05, 0.74, 0.6), 0.9)
		add_prop(inner, cyl(0.07, 0.05, 0.09), Color(0.17, 0.19, 0.22), Vector3(0, 0.5, 0.3), Vector3.ZERO, 0.7)
		beacon_mat = add_prop(inner, ball_mesh(0.065), Color(1, 0.45, 0.1), Vector3(0, 0.55, 0.3), Vector3.ZERO, 0.0, 4.0).material_override
	fire_t = randf_range(1.8, 3.0); orbit_a = randf() * TAU; orbit_r = randf_range(8, 12); height = randf_range(3, 5.5)
	eye_light = OmniLight3D.new(); eye_light.light_color = Color(1, 0.2, 0.1); eye_light.light_energy = 0.5; eye_light.omni_range = 4
	add_child(eye_light)
	aim_mat = StandardMaterial3D.new(); aim_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	aim_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; aim_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	aim_mat.albedo_color = Color(1, 0.15, 0.1, 0.6)
	var cm := CylinderMesh.new(); cm.top_radius = 0.018; cm.bottom_radius = 0.018; cm.height = 1.0; cm.radial_segments = 6; cm.rings = 1
	aim_line = MeshInstance3D.new(); aim_line.mesh = cm; aim_line.material_override = aim_mat; aim_line.top_level = true
	aim_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; aim_line.visible = false
	add_child(aim_line)
	buzz_t = randf_range(0.5, 3.0)

func center() -> Vector3:
	return global_position

func knock(v: Vector3) -> void:
	velocity += v * 2.2 + Vector3(randf_range(-1, 1), randf_range(0.5, 2), randf_range(-1, 1))
	wobble = 1.0
	stun = maxf(stun, stagger_time)
	if aiming: fire_t = maxf(fire_t, LOCK_T + 0.35)   # a hit while charging delays the shot

func _physics_process(dt: float) -> void:
	if dead:
		if fall_t > 0.0: _fall(dt)
		return
	tick_common(dt)
	if beacon_mat: beacon_mat.emission_energy_multiplier = 1.0 + 7.0 * maxf(0.0, sin(t * 9.0))
	if paused(): aim_line.visible = false; return
	if spawn_t > 0.0 and spawn_t + 0.02 >= 1.0: Snd.at("chars_hornet_dive", global_position, -6, 0.12, 0.2)
	var hp_ := player.global_position
	var hero_c := hp_ + Vector3(0, 0.9, 0)
	orbit_a += dt * 0.35
	var want := Vector3(hp_.x + cos(orbit_a) * orbit_r, hp_.y + height + sin(t * 1.3) * 0.5, hp_.z + sin(orbit_a) * orbit_r)
	var steer := (want - global_position) * (3.0 if spawn_t > 0.0 else 1.4)
	var away := global_position - hero_c
	if away.length() < 6.0: steer += away.normalized() * (6.0 - away.length()) * 4.0
	if stun <= 0.0: velocity = velocity.lerp(steer, 1.0 - exp(-2.0 * dt))
	else: velocity *= exp(-1.5 * dt)
	global_position += velocity * dt
	spawn_t -= dt
	look_at(hero_c, Vector3.UP, true)
	wobble = maxf(0.0, wobble - dt * 2.0)
	if inner:
		inner.rotation.z = clampf(-velocity.x * 0.05, -0.5, 0.5) + sin(t * 2.0) * 0.08 + sin(t * 30.0) * wobble * 0.5
		inner.rotation.x = sin(t * 23.0) * wobble * 0.3 + sin(t * 3.1) * 0.06
		_flap(1.0 + wobble)
		inner.position = Vector3(sin(t * 61.0) * 0.012, sin(t * 2.4) * 0.08 + sin(t * 53.0) * 0.012, 0)
	buzz_t -= dt
	if buzz_t <= 0.0: buzz_t = randf_range(2.5, 4.5); Snd.at("hornet_buzz", global_position, -10, 0.12, 0.3)
	# attack: charge with an aim line, freeze the aim, fire
	if spawn_t <= 0.0: fire_t -= dt
	if fire_t < AIM_T and fire_t > 0.0:
		if not aiming:
			aiming = true; Snd.at("hornet_buzz", global_position, -3, 0.0, 0.0)
		if fire_t > LOCK_T: aim_at = hero_c + player.velocity * 0.15
		var charge := 1.0 - fire_t / AIM_T
		eye_light.light_energy = 0.5 + charge * 7.0
		for e in eyes: (e.mat as StandardMaterial3D).emission_energy_multiplier = 5.0 + charge * 16.0
		eye_open = 1.0 - charge * 0.45     # it squints down the sights
		_aim_line(charge, fire_t <= LOCK_T)
	else:
		eye_light.light_energy = 0.5
		aim_line.visible = false
		eye_open = 1.0
		for e in eyes: (e.mat as StandardMaterial3D).emission_energy_multiplier = 5.0
	if spawn_t > -0.1: _arrive()
	if fire_t <= 0.0:
		aiming = false; aim_line.visible = false
		fire_t = randf_range(2.4, 3.6)
		var from := global_position + (aim_at - global_position).normalized() * 0.9
		combat.enemy_shot(from, aim_at)
		FX.sparks(from, Color(1, 0.35, 0.2), 6, 3.0)
		velocity -= (aim_at - global_position).normalized() * 2.0   # recoil

## Arrival: it dives in tucked up in a spin, snaps its wings open, brakes and boots its eyes on.
func _arrive() -> void:
	var k := clampf(1.0 - spawn_t, 0.0, 1.0)          # 0 at spawn .. 1 when it takes up its orbit
	var unfold := smoothstep(0.35, 0.7, k)
	for w in wings: (w as Node3D).scale = Vector3.ONE * lerpf(0.15, 1.0, unfold)
	if inner: inner.rotation.z += (1.0 - unfold) * k * TAU * 2.0
	eye_open = 0.05 if k < 0.6 else minf(1.0, (k - 0.6) * 5.0)
	if k >= 0.6 and not has_meta("booted"):
		set_meta("booted", true); flash = 0.6; pop = 0.7
		FX.sparks(center(), Color(1, 0.5, 0.3), 5, 2.0)

## Buzzing wings: a fast flap that the frame rate turns into a blur, flaring when it is knocked about.
func _flap(k: float) -> void:
	for i in wings.size():
		var w: Node3D = wings[i]
		var sx := 1.0 if i == 0 else -1.0
		w.rotation.z = sx * (0.15 + sin(t * 57.0 + i * 0.6) * 0.42 * k)

func _aim_line(charge: float, locked: bool) -> void:
	var from := global_position
	var to := aim_at
	var d := to - from
	var l := d.length()
	if l < 0.1: aim_line.visible = false; return
	aim_line.visible = true
	aim_line.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, d / l)).scaled(Vector3(1.0 + charge * 1.5, l, 1.0 + charge * 1.5)), from + d * 0.5)
	aim_mat.albedo_color = Color(1, 0.9 if locked else 0.15, 0.1 if not locked else 0.6, (0.9 if locked else 0.25 + charge * 0.4))

func _death_fx(self_destruct: bool) -> void:
	aim_line.visible = false; eye_light.light_energy = 0.0
	if self_destruct:
		_burst(); queue_free(); return
	# spin down in flames, burst on impact
	fall_t = 1.1; spin_v = randf_range(8, 12) * (1 if randf() < 0.5 else -1)
	velocity = velocity * 0.4 + Vector3(0, 2.0, 0)
	FX.sparks(center(), Color(1, 0.6, 0.3), 14, 6)
	Snd.at("explode_small", center(), -6, 0.2)
	Snd.at("chars_hornet_dive", center(), -4, 0.0, 0.1)

func _fall(dt: float) -> void:
	fall_t -= dt; t += dt
	velocity.y -= 16.0 * dt
	global_position += velocity * dt
	rotate_y(spin_v * dt)
	if model: model.rotation.z += dt * 4.0
	_flap(0.5)
	for m in flash_mats: m.emission = Color(1, 0.4, 0.1); m.emission_energy_multiplier = 0.8 + sin(t * 30.0) * 0.6
	if randf() < 0.7: FX.smoke_trail(global_position, 0.8)
	var q := PhysicsRayQueryParameters3D.create(global_position, global_position + Vector3(0, -0.9, 0) + velocity * dt); q.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit or fall_t <= 0.0:
		_burst(); FX.ring(global_position, Color(1, 0.5, 0.2), 1.0)
		queue_free()
