extends Node3D
## The relay dish on top of the Signal Mast: a shootable story target that boosts Grudd's signal.

signal destroyed

const HP := 30.0
var hp := HP
var dead := false
var flash := 0.0
var dish := Node3D.new()
var eye_mat := StandardMaterial3D.new()
var body_mat := StandardMaterial3D.new()

func _ready() -> void:
	add_to_group("targets")
	body_mat.albedo_color = Color(0.25, 0.28, 0.33); body_mat.metallic = 0.8; body_mat.roughness = 0.35
	body_mat.emission_enabled = true; body_mat.emission = Color(1, 0.9, 0.8); body_mat.emission_energy_multiplier = 0
	eye_mat.albedo_color = Color.BLACK; eye_mat.emission_enabled = true; eye_mat.emission = Color(1, 0.45, 0.1); eye_mat.emission_energy_multiplier = 6
	var post := CylinderMesh.new(); post.top_radius = 0.25; post.bottom_radius = 0.4; post.height = 3.0
	var pm := MeshInstance3D.new(); pm.mesh = post; pm.material_override = body_mat; pm.position.y = 1.5; add_child(pm)
	dish.position.y = 3.2; add_child(dish)
	var d := CylinderMesh.new(); d.top_radius = 1.8; d.bottom_radius = 0.4; d.height = 0.7
	var dm := MeshInstance3D.new(); dm.mesh = d; dm.material_override = body_mat; dm.rotation.x = -1.2; dish.add_child(dm)
	var e := SphereMesh.new(); e.radius = 0.45; e.height = 0.9
	var em := MeshInstance3D.new(); em.mesh = e; em.material_override = eye_mat; em.position = Vector3(0, 0.3, 0.5); dish.add_child(em)
	var l := OmniLight3D.new(); l.light_color = Color(1, 0.5, 0.15); l.light_energy = 5; l.omni_range = 9; l.position = Vector3(0, 0.4, 0.8); dish.add_child(l)
	var sb := StaticBody3D.new(); sb.collision_layer = 4; sb.collision_mask = 0
	var cs := CollisionShape3D.new(); var sh := BoxShape3D.new(); sh.size = Vector3(3.2, 4.4, 3.2); cs.shape = sh; cs.position.y = 2.4
	sb.add_child(cs); add_child(sb); sb.set_meta("owner", self)

func center() -> Vector3:
	return dish.global_position

func damage(amount: float, _p: Vector3, _d: Vector3) -> bool:
	if dead: return false
	hp -= amount; flash = 1.0
	Game.boss_health.emit("SIGNAL RELAY", maxf(0.0, hp / HP))
	if hp <= 0.0:
		dead = true
		FX.explosion(center(), 1.8); FX.shake(1.2); Snd.at("relay_destroy", center(), 4)
		destroyed.emit()
		var tw := create_tween(); tw.tween_property(dish, "rotation:x", 1.4, 0.6); tw.tween_property(self, "scale", Vector3(1, 0.05, 1), 0.4)
		tw.tween_callback(queue_free)
		return true
	return false

func _process(dt: float) -> void:
	dish.rotation.y += dt * 0.8
	flash = maxf(0.0, flash - dt * 7.0)
	body_mat.emission_energy_multiplier = flash * 1.5
	eye_mat.emission_energy_multiplier = 6.0 + sin(Time.get_ticks_msec() * 0.008) * 3.0
