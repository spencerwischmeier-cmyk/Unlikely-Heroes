extends AnimatableBody3D
## A steel cargo crate in the Crane Yard arena. The Crane Bot's magnet slam drags these toward where it
## lands (where Vesk was standing): they glow and rattle while the magnet charges, then slide in. A
## sliding crate knocks Vesk over. Breakable for a few sprockets; the boss drops in new ones.

const Kit := preload("res://scripts/kit.gd")
const SIZE := 1.6

var hp := 4.0
var dead := false
var model: Node3D
var glow_mats: Array = []
var flash := 0.0
var charge := 0.0          # magnet charge glow (0..1), set by the boss each frame
var pull_to := Vector3.ZERO
var pull_t := 0.0
var speed := 0.0
var hurt_cd := 0.0
var dropping := false
var drop_t := 0.0          # < 0: waiting above, 0..1: falling
var drop_from := Vector3.ZERO
var drop_to := Vector3.ZERO
var t := 0.0
var player: Node3D
var combat: Node3D

func _ready() -> void:
	collision_layer = 1 | 4
	collision_mask = 0
	add_to_group("targets"); add_to_group("crate"); add_to_group("magnet_crate")
	model = Kit.place(self, "crate_large", Vector3.ZERO, randf() * 0.2 - 0.1, 1.0, false)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		for s in (mi as MeshInstance3D).mesh.get_surface_count():
			var m := (mi as MeshInstance3D).get_active_material(s)
			if m is StandardMaterial3D and not (m as StandardMaterial3D).emission_enabled:
				var c := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
				c.emission_enabled = true; c.emission = Color(1, 0.3, 0.2); c.emission_energy_multiplier = 0.0
				(mi as MeshInstance3D).set_surface_override_material(s, c); glow_mats.append(c)
	var cs := CollisionShape3D.new(); var sh := BoxShape3D.new(); sh.size = Vector3.ONE * SIZE
	cs.shape = sh; cs.position.y = SIZE / 2; add_child(cs)

func center() -> Vector3:
	return global_position + Vector3(0, SIZE / 2, 0)

func damage(amount: float, point: Vector3, dir: Vector3) -> bool:
	if dead or dropping: return false
	hp -= amount; flash = 1.0
	FX.hit_sparks(point, dir, Color(1, 0.8, 0.5), 5)
	if hp <= 0.0:
		smash()
		return true
	return false

func smash(drop := true) -> void:
	if dead: return
	dead = true
	remove_from_group("targets"); collision_layer = 0
	var c := center()
	FX.explosion(c, 0.7, glow_mats.slice(0, 1)); FX.shake(0.4)
	Snd.at("crate_break", c, 0)
	if drop and combat: combat.drop_nuts(c, 3)
	queue_free()

## Drop in from the sky onto `pos` after a warning ring.
func drop_in(pos: Vector3, delay := 0.9) -> void:
	drop_to = pos; drop_from = pos + Vector3(0, 16, 0); drop_t = -delay; dropping = true
	global_position = drop_from
	visible = false
	FX.warn_ring(pos, 1.4, delay + 0.45, Color(1, 0.55, 0.15))

## Magnet pull: slide to `to` (start now).
func pull(to: Vector3) -> void:
	if dead or dropping: return
	pull_to = Vector3(to.x, global_position.y, to.z); pull_t = 1.2; speed = 0.0

func _physics_process(dt: float) -> void:
	if dead: return
	t += dt
	hurt_cd -= dt
	flash = maxf(0.0, flash - dt * 6.0)
	for m in glow_mats: m.emission_energy_multiplier = flash * 1.5 + charge * (2.0 + sin(t * 30.0) * 1.2)
	model.position = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * 0.04 * charge
	# falling in
	if dropping:
		if drop_t < 0.0:
			drop_t = minf(drop_t + dt, 0.0)
			if drop_t >= 0.0: visible = true
			return
		drop_t += dt / 0.45
		var u := minf(drop_t, 1.0)
		global_position = drop_from.lerp(drop_to, u * u)
		if drop_t >= 1.0:
			dropping = false; global_position = drop_to
			FX.puff(drop_to + Vector3(0, 0.2, 0)); FX.ring(drop_to + Vector3(0, 0.05, 0), Color(1, 0.7, 0.4), 0.6); FX.shake(0.3)
			Snd.at("land", drop_to, 0)
			if player and Vector2(player.global_position.x - drop_to.x, player.global_position.z - drop_to.z).length() < 1.3 and combat:
				combat.hurt_player(1, drop_to)
		return
	# sliding toward the magnet
	if pull_t > 0.0:
		pull_t -= dt
		var to := pull_to - global_position; to.y = 0
		speed = minf(speed + 30.0 * dt, 13.0)
		var step := minf(speed * dt, to.length())
		if to.length() < 0.05 or step <= 0.0: pull_t = 0.0
		else:
			global_position += to.normalized() * step
			if randf() < 0.6: FX.sparks(global_position + Vector3(0, 0.05, 0), Color(1, 0.75, 0.4), 3, 3.0)
			if player and combat and hurt_cd <= 0.0 and speed > 3.0:
				var d := player.global_position - global_position
				if Vector2(d.x, d.z).length() < SIZE * 0.5 + 0.5 and d.y < SIZE - 0.2 and d.y > -0.5:
					hurt_cd = 1.0
					combat.hurt_player(1, global_position)
		if pull_t <= 0.0: FX.puff(global_position + Vector3(0, 0.2, 0)); Snd.at("land", global_position, -4)
