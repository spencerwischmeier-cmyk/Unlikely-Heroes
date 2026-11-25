extends Node
## Breakable sprocket crates at every Game.level.crate_spots position. A wrench hit or shots break
## them: a burst of splinters, Snd "crate_break", a shower of sprockets and sometimes an ammo canister.
## Crates are in the "targets" and "crate" groups (combat skips them for aim assist and homing).
## Debug: --crate-test drops a crate in front of Vesk and breaks it after a moment (screenshots).

class Crate extends StaticBody3D:
	var dead := false
	var hp := 1.0
	var size := 1.0
	var big := false
	var model: Node3D
	var flash_mats: Array = []
	var chunk_mats: Array = []
	var flash := 0.0
	var wob := 0.0

	func _ready() -> void:
		collision_layer = 1 | 4
		collision_mask = 0
		add_to_group("targets"); add_to_group("crate")
		size = 1.6 if big else 1.0
		hp = 2.5 if big else 1.0
		model = Kit.place(self, "crate_large" if big else "crate_small", Vector3.ZERO, 0.0, 1.0, false)
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			for s in (mi as MeshInstance3D).mesh.get_surface_count():
				var m := (mi as MeshInstance3D).get_active_material(s)
				if m is StandardMaterial3D:
					if chunk_mats.size() < 2: chunk_mats.append(m)
					if not (m as StandardMaterial3D).emission_enabled:
						var c := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
						c.emission_enabled = true; c.emission = Color(1, 0.85, 0.5); c.emission_energy_multiplier = 0.0
						(mi as MeshInstance3D).set_surface_override_material(s, c); flash_mats.append(c)
		var cs := CollisionShape3D.new(); var sh := BoxShape3D.new(); sh.size = Vector3.ONE * size
		cs.shape = sh; cs.position.y = size / 2; add_child(cs)
		# a brass sprocket badge on two faces so the crate reads as "break me"
		var tm := TorusMesh.new(); tm.inner_radius = size * 0.12; tm.outer_radius = size * 0.2; tm.ring_segments = 6; tm.rings = 8
		var bm := StandardMaterial3D.new(); bm.albedo_color = Color(1.0, 0.76, 0.24); bm.metallic = 1.0; bm.roughness = 0.25
		bm.emission_enabled = true; bm.emission = Color(1.0, 0.6, 0.1); bm.emission_energy_multiplier = 0.8
		for sz in [-1.0, 1.0]:
			var mi := MeshInstance3D.new(); mi.mesh = tm; mi.material_override = bm
			mi.position = Vector3(0, size * 0.5, sz * (size * 0.5 + 0.02)); mi.rotation.x = PI / 2; mi.scale = Vector3(1, 0.25, 1)
			add_child(mi)

	func center() -> Vector3:
		return global_position + Vector3(0, size / 2, 0)

	func damage(amount: float, point: Vector3, dir: Vector3) -> bool:
		if dead: return false
		hp -= amount; flash = 1.0; wob = 1.0
		FX.hit_sparks(point, dir, Color(1, 0.85, 0.55), 5)
		Snd.at("melee_hit", point, -12, 0.2, 0.05)
		if hp <= 0.0:
			smash()
			return true
		return false

	func smash() -> void:
		if dead: return
		dead = true
		remove_from_group("targets"); collision_layer = 0
		var c := center()
		FX.explosion(c, 0.55 if not big else 0.8, chunk_mats)
		FX.puff(c, Color(0.85, 0.75, 0.6))
		FX.shake(0.3)
		Snd.at("crate_break", c, 0, 0.1, 0.0)
		var combat := Game.combat
		if combat:
			combat.drop_nuts(c, randi_range(6, 9) if big else randi_range(3, 5))
			if randf() < (0.6 if big else 0.3): combat.drop_ammo(c + Vector3(0, 0.2, 0))
			elif randf() < 0.1: combat.drop_cell(c + Vector3(0, 0.2, 0))
		queue_free()

	func _process(dt: float) -> void:
		flash = maxf(0.0, flash - dt * 8.0)
		wob = maxf(0.0, wob - dt * 6.0)
		for m in flash_mats: m.emission_energy_multiplier = flash * 1.5
		if model:
			var s := 1.0 + wob * 0.12
			model.scale = Vector3(s, 2.0 - s, s)

var crates: Array = []

func _ready() -> void:
	_place.call_deferred()
	if OS.get_cmdline_user_args().has("--crate-test"):
		get_tree().create_timer(1.0).timeout.connect(_crate_test)

func _place() -> void:
	if Game.level == null: return
	var spots = Game.level.get("crate_spots")
	if not (spots is Array): return
	var rng := RandomNumberGenerator.new(); rng.seed = 4242
	for p in spots:
		crates.append(spawn(p, rng.randf() < 0.35, rng.randf() * TAU))

func spawn(pos: Vector3, big := false, yaw := 0.0) -> Node3D:
	var c := Crate.new(); c.big = big; c.name = "Crate%d" % crates.size()
	Game.level.add_child(c)
	c.global_position = pos; c.rotation.y = yaw
	return c

func _crate_test() -> void:
	var p: Node3D = Game.player
	if p == null: return
	var f := Vector3(sin(p.face_yaw), 0, cos(p.face_yaw))
	var c := spawn(p.global_position + f * 3.0, true, 0.3)
	var c2 := spawn(p.global_position + f * 3.2 + Vector3(-f.z, 0, f.x) * 1.8, false, 0.8)
	get_tree().create_timer(1.6).timeout.connect(func():
		if is_instance_valid(c): c.damage(5.0, c.center(), f)
		if is_instance_valid(c2): c2.damage(0.5, c2.center(), f))
