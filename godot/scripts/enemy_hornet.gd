extends "res://scripts/enemy.gd"
## Rivet Hornet: circles Vesk at a distance, charges its eye and fires red bolts.

var inner: Node3D
var fire_t := 2.0
var orbit_a := 0.0
var orbit_r := 10.0
var height := 4.0
var spawn_t := 1.0
var eye_light: OmniLight3D

func _ready() -> void:
	hp = 4.0; max_hp = 4.0; nuts = 8
	var cs := CollisionShape3D.new(); var sh := SphereShape3D.new(); sh.radius = 0.85
	cs.shape = sh; add_child(cs)
	collision_mask = 0
	setup_model("res://models/hornet.glb")
	inner = model.find_child("inner", true, false)
	fire_t = randf_range(1.5, 2.8); orbit_a = randf() * TAU; orbit_r = randf_range(8, 12); height = randf_range(3, 5.5)
	eye_light = OmniLight3D.new(); eye_light.light_color = Color(1, 0.2, 0.1); eye_light.light_energy = 0.5; eye_light.omni_range = 4
	add_child(eye_light)

func center() -> Vector3:
	return global_position

func knock(v: Vector3) -> void:
	velocity += v * 2.2 + Vector3(randf_range(-1, 1), randf_range(0.5, 2), randf_range(-1, 1))

func _physics_process(dt: float) -> void:
	if dead: return
	tick_common(dt)
	var hp_ := player.global_position
	var hero_c := hp_ + Vector3(0, 0.9, 0)
	orbit_a += dt * 0.35
	var want := Vector3(hp_.x + cos(orbit_a) * orbit_r, hp_.y + height + sin(t * 1.3) * 0.5, hp_.z + sin(orbit_a) * orbit_r)
	var steer := (want - global_position) * (3.0 if spawn_t > 0.0 else 1.4)
	var away := global_position - hero_c
	if away.length() < 6.0: steer += away.normalized() * (6.0 - away.length()) * 4.0
	velocity = velocity.lerp(steer, 1.0 - exp(-2.0 * dt))
	global_position += velocity * dt
	spawn_t -= dt
	look_at(hero_c, Vector3.UP, true)
	if inner: inner.rotation.z = clampf(-velocity.x * 0.05, -0.5, 0.5) + sin(t * 2.0) * 0.08
	fire_t -= dt
	var charge := 1.0 - fire_t / 0.7 if (fire_t < 0.7 and fire_t > 0.0) else 0.0
	eye_light.light_energy = 0.5 + charge * 6.0
	if fire_t <= 0.0:
		fire_t = randf_range(2.2, 3.4)
		var lead := hero_c + player.velocity * 0.35 * randf()
		combat.enemy_shot(global_position + (lead - global_position).normalized() * 0.9, lead)
