extends StaticBody3D
## A striped barricade section the Work-Crew Rollers hammer up. Solid (blocks Vesk and bolts), and a
## target: bolts, the wrench and blasts break it. It rises out of the ground while being built, and
## falls apart once its crew is gone.

signal broken(b)

const W := 2.4
var hp := 5.0
var dead := false
var rise := 0.0           # 0..1 while being built
var model: Node3D
var lamp: MeshInstance3D
var lamp_mat: StandardMaterial3D
var flash_mats: Array = []
var flash := 0.0
var t := 0.0
var shake := 0.0
var col: CollisionShape3D

func _ready() -> void:
	collision_layer = 1 | 4
	collision_mask = 0
	add_to_group("targets"); add_to_group("barricade")
	model = load("res://models/crew_barricade.glb").instantiate()
	add_child(model)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for s in (mi as MeshInstance3D).mesh.get_surface_count():
			var m := (mi as MeshInstance3D).get_active_material(s)
			if m is StandardMaterial3D:
				var c := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
				if not c.emission_enabled:
					c.emission_enabled = true; c.emission = Color.WHITE; c.emission_energy_multiplier = 0.0; flash_mats.append(c)
				else: lamp_mat = c
				(mi as MeshInstance3D).set_surface_override_material(s, c)
	var cs := CollisionShape3D.new(); var sh := BoxShape3D.new(); sh.size = Vector3(W, 1.3, 0.55)
	cs.shape = sh; cs.position.y = -0.65; add_child(cs); col = cs
	model.position.y = -1.3

func center() -> Vector3:
	return global_position + Vector3(0, 0.7, 0)

func damage(amount: float, point: Vector3, dir: Vector3) -> bool:
	if dead: return false
	hp -= amount; flash = 1.0; shake = 1.0
	FX.hit_sparks(point, dir, Color(1, 0.75, 0.35), 5)
	Snd.at("bolt_hit", point, -8, 0.15, 0.05)
	if hp <= 0.0:
		smash()
		return true
	return false

## Break apart: planks fly, a few sprockets drop.
func smash(quiet := false) -> void:
	if dead: return
	dead = true
	remove_from_group("targets")
	collision_layer = 0
	var c := center()
	FX.explosion(c, 0.6, flash_mats.slice(0, 1))
	FX.puff(c, Color(1, 0.85, 0.6))
	if not quiet:
		Snd.at("crate_break", c, 0)
		if Game.combat: Game.combat.drop_nuts(c, 2)
	broken.emit(self)
	queue_free()

## The crew is gone: the barricade sinks and folds up.
func collapse() -> void:
	if dead: return
	dead = true
	remove_from_group("targets"); collision_layer = 0
	FX.puff(center(), Color(1, 0.85, 0.6))
	var tw := create_tween()
	tw.tween_property(model, "position:y", -1.4, 0.8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)

func _physics_process(dt: float) -> void:
	t += dt
	flash = maxf(0.0, flash - dt * 8.0)
	shake = maxf(0.0, shake - dt * 6.0)
	for m in flash_mats: m.emission_energy_multiplier = flash * 1.5
	if not dead:
		model.position.y = lerpf(-1.3, 0.0, rise)
		col.position.y = lerpf(-0.65, 0.65, rise)
		model.position.x = sin(t * 60.0) * 0.04 * shake
	if lamp_mat: lamp_mat.emission_energy_multiplier = 6.0 if fmod(t, 0.8) < 0.4 else 1.0
