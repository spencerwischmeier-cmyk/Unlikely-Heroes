extends Node3D
## Crane Bot: Foreman Grudd's heavy lifter and Skyharbor's boss. A tracked crane with a magnet on a boom.
##   Magnet slam  the magnet tracks Vesk, a red ring marks where it will land, then it drops
##   Rivet spray  a fan of hot rivets from the cab
##   Work crew    (second half) drops Scrap Rollers
## The cab is the weak point.

signal dead_at(pos: Vector3)
signal half

const BOSS_HP := 200.0
const BOOM := 10.0
var combat: Node3D
var player: CharacterBody3D
var spawn_roller: Callable
var area := Rect2()

var hp := BOSS_HP
var dead := true
var state := "off"
var st_t := 0.0
var t := 0.0
var flash := 0.0
var yaw := PI
var turn_yaw := 0.0
var pitch := 0.6
var mag := Vector3(0, 6, 0)
var lock := Vector3.ZERO
var sprays := 0
var crew_out := 0
var last_attack := ""
var half_hit := false
var landed := false

var turn := Node3D.new()
var boom := Node3D.new()
var tip := Node3D.new()
var cab: MeshInstance3D
var magnet := Node3D.new()
var cable := MeshInstance3D.new()
var warn := MeshInstance3D.new()
var warn_mat := StandardMaterial3D.new()
var eye_mat: StandardMaterial3D
var mag_mat: StandardMaterial3D
var flash_mats: Array = []
var body := StaticBody3D.new()
var hitbox := StaticBody3D.new()

func _m(c: Color, metal := 0.5, rough := 0.4) -> StandardMaterial3D:
	var m := StandardMaterial3D.new(); m.albedo_color = c; m.metallic = metal; m.roughness = rough
	m.emission_enabled = true; m.emission = Color(1, 0.9, 0.8); m.emission_energy_multiplier = 0.0
	flash_mats.append(m)
	return m

func _box(parent: Node3D, size: Vector3, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var bm := BoxMesh.new(); bm.size = size
	var mi := MeshInstance3D.new(); mi.mesh = bm; mi.material_override = mat; mi.position = pos; mi.rotation = rot
	parent.add_child(mi); return mi

func _cyl(parent: Node3D, r: float, h: float, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var cm := CylinderMesh.new(); cm.top_radius = r; cm.bottom_radius = r; cm.height = h
	var mi := MeshInstance3D.new(); mi.mesh = cm; mi.material_override = mat; mi.position = pos; mi.rotation = rot
	parent.add_child(mi); return mi

func _ready() -> void:
	add_to_group("targets"); add_to_group("boss")
	var yellow := _m(Color(0.94, 0.7, 0.12), 0.45, 0.4)
	var red := _m(Color(0.6, 0.12, 0.16), 0.5, 0.4)
	var dark := StandardMaterial3D.new(); dark.albedo_color = Color(0.17, 0.19, 0.22); dark.metallic = 0.8; dark.roughness = 0.4
	var steel := StandardMaterial3D.new(); steel.albedo_color = Color(0.72, 0.76, 0.8); steel.metallic = 0.85; steel.roughness = 0.3
	for s in [-1, 1]:
		_box(self, Vector3(0.95, 1.1, 5), dark, Vector3(1.6 * s, 0.55, 0))
		for i in range(-2, 3): _cyl(self, 0.38, 1.0, steel, Vector3(1.6 * s, 0.5, i * 0.95), Vector3(0, 0, PI / 2))
	_box(self, Vector3(2.6, 0.8, 4.2), yellow, Vector3(0, 1.2, 0))
	_box(self, Vector3(2.62, 0.18, 0.1), red, Vector3(0, 1.2, 2.12))
	turn.position.y = 1.6; add_child(turn)
	_cyl(turn, 1.55, 0.35, dark, Vector3(0, 0.1, 0))
	cab = _box(turn, Vector3(2.4, 2.1, 2.3), yellow, Vector3(0, 1.35, 0.2))
	eye_mat = StandardMaterial3D.new(); eye_mat.albedo_color = Color.BLACK; eye_mat.emission_enabled = true; eye_mat.emission = Color(1, 0.16, 0.16); eye_mat.emission_energy_multiplier = 6
	_box(turn, Vector3(1.8, 0.42, 0.12), eye_mat, Vector3(0, 1.65, 1.37))
	var el := OmniLight3D.new(); el.light_color = Color(1, 0.2, 0.15); el.light_energy = 4; el.omni_range = 6; el.position = Vector3(0, 1.65, 1.8); turn.add_child(el)
	_box(turn, Vector3(1.4, 0.4, 0.1), dark, Vector3(0, 0.95, 1.37))
	for s in [-1, 1]:
		var cm := CylinderMesh.new(); cm.top_radius = 0.0; cm.bottom_radius = 0.16; cm.height = 0.6
		var h := MeshInstance3D.new(); h.mesh = cm; h.material_override = red; h.position = Vector3(0.95 * s, 2.55, 0.5); h.rotation.z = -0.4 * s; turn.add_child(h)
	_box(turn, Vector3(2.6, 1.4, 1.2), dark, Vector3(0, 1.0, -1.7))
	_box(turn, Vector3(2.62, 0.2, 1.22), yellow, Vector3(0, 1.2, -1.7))
	boom.position = Vector3(0, 2.5, 0.8); turn.add_child(boom)
	for p in [Vector2(-0.35, -0.3), Vector2(0.35, -0.3), Vector2(-0.35, 0.3), Vector2(0.35, 0.3)]:
		_box(boom, Vector3(0.12, 0.12, BOOM), yellow, Vector3(p.x, p.y, BOOM / 2))
	for i in 10:
		var z := 0.5 + i * 0.95
		for y in [-0.3, 0.3]: _box(boom, Vector3(0.75, 0.06, 0.06), yellow, Vector3(0, y, z))
		for x in [-0.35, 0.35]: _box(boom, Vector3(0.06, 0.7, 0.06), yellow, Vector3(x, 0, z + 0.45), Vector3(0.55, 0, 0))
	tip.position = Vector3(0, -0.3, BOOM); boom.add_child(tip)
	_cyl(tip, 0.3, 0.3, dark, Vector3.ZERO, Vector3(0, 0, PI / 2))
	# magnet + cable + warning ring live in world space
	magnet.top_level = true; add_child(magnet)
	var mm := CylinderMesh.new(); mm.top_radius = 1.15; mm.bottom_radius = 1.25; mm.height = 0.5
	var mmi := MeshInstance3D.new(); mmi.mesh = mm; mmi.material_override = dark; magnet.add_child(mmi)
	mag_mat = StandardMaterial3D.new(); mag_mat.albedo_color = Color.BLACK; mag_mat.emission_enabled = true; mag_mat.emission = Color(1, 0.25, 0.19); mag_mat.emission_energy_multiplier = 3
	var tr := TorusMesh.new(); tr.inner_radius = 0.92; tr.outer_radius = 1.08
	var tri := MeshInstance3D.new(); tri.mesh = tr; tri.material_override = mag_mat; tri.position.y = -0.27; magnet.add_child(tri)
	var cm2 := CylinderMesh.new(); cm2.top_radius = 0.035; cm2.bottom_radius = 0.035; cm2.height = 1.0
	cable.mesh = cm2; cable.material_override = dark; cable.top_level = true; add_child(cable)
	var rm := TorusMesh.new(); rm.inner_radius = 1.9; rm.outer_radius = 2.3; rm.rings = 48
	warn_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; warn_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	warn_mat.albedo_color = Color(1, 0.19, 0.12, 0.7); warn_mat.no_depth_test = false
	warn.mesh = rm; warn.material_override = warn_mat; warn.top_level = true; warn.scale = Vector3(1, 0.05, 1); add_child(warn)
	# collision: the body blocks Vesk; the cab is hittable
	var cs := CollisionShape3D.new(); var sh := BoxShape3D.new(); sh.size = Vector3(4.2, 1.6, 4.4); cs.shape = sh; cs.position.y = 0.8
	body.add_child(cs); add_child(body)
	hitbox.collision_layer = 4; hitbox.collision_mask = 0
	var hcs := CollisionShape3D.new(); var hsh := BoxShape3D.new(); hsh.size = Vector3(2.6, 2.3, 2.5); hcs.shape = hsh
	hitbox.add_child(hcs); cab.add_child(hitbox)
	hitbox.add_to_group("targets_proxy")
	hitbox.set_meta("owner", self)
	_hide()

func _hide() -> void:
	visible = false; magnet.visible = false; cable.visible = false; warn.visible = false
	dead = true; state = "off"
	body.process_mode = Node.PROCESS_MODE_DISABLED; hitbox.process_mode = Node.PROCESS_MODE_DISABLED

func spawn(pos: Vector3, area_: Rect2) -> void:
	area = area_
	position = Vector3(pos.x, 14, pos.z)
	state = "intro"; st_t = 2.2; t = 0; flash = 0; yaw = PI; turn_yaw = 0; pitch = 0.6; sprays = 0; crew_out = 0; last_attack = ""
	hp = BOSS_HP; dead = false; landed = false
	visible = true; magnet.visible = true; cable.visible = true
	body.process_mode = Node.PROCESS_MODE_INHERIT; hitbox.process_mode = Node.PROCESS_MODE_INHERIT
	eye_mat.emission = Color(1, 0.16, 0.16)

func center() -> Vector3:
	return cab.global_position

func damage(amount: float, _point: Vector3, _dir: Vector3) -> bool:
	if dead or state == "intro" or state == "dying": return false
	var was_angry := hp < BOSS_HP * 0.5
	hp -= amount; flash = 1.0
	Game.boss_health.emit("CRANE BOT", maxf(0.0, hp / BOSS_HP))
	if not was_angry and hp < BOSS_HP * 0.5 and hp > 0: half_hit = true
	if hp <= 0:
		hp = 0; state = "dying"; st_t = 2.4; warn.visible = false
		return true
	return false

func crew_down() -> void:
	crew_out = maxi(0, crew_out - 1)

func _physics_process(dt: float) -> void:
	if state == "off": return
	if half_hit: half_hit = false; half.emit()
	t += dt; st_t -= dt
	flash = maxf(0.0, flash - dt * 7.0)
	for m in flash_mats: m.emission_energy_multiplier = flash * 1.5
	var angry := hp < BOSS_HP * 0.5
	var speed := 1.35 if angry else 1.0
	var hero := player.global_position
	var hero_flat := Vector3(hero.x, 0, hero.z)
	var to_hero := hero_flat - Vector3(position.x, 0, position.z)
	var hd := to_hero.length()
	if state == "intro":
		position.y = maxf(0.0, position.y - dt * 16.0)
		if position.y == 0.0 and not landed:
			landed = true; FX.explosion(position + Vector3(0, 0.3, 0), 1.4); FX.shake(1.2); Snd.at("crane_slam", position, 4)
		if st_t <= 0.0: state = "idle"; st_t = 0.8
	elif state == "dying":
		if randf() < dt * 14.0: FX.explosion(center() + Vector3(randf_range(-1.8, 1.8), randf_range(-1.5, 1.5), randf_range(-1.8, 1.8)), randf_range(0.4, 0.8))
		rotation.z = sin(t * 30.0) * 0.03
		pitch = maxf(-0.1, pitch - dt * 0.4)
		if st_t <= 0.0:
			var at := center()
			FX.explosion(at, 2.4); FX.explosion(position + Vector3(0, 1, 0), 2.0); FX.shake(2.0); Snd.at("explode_big", at, 6, 0.0)
			_hide(); dead_at.emit(at)
			return
	else:
		if state == "idle" or state == "spray":
			var want := 1.0 if hd > 11.0 else (-1.0 if hd < 7.0 else 0.0)
			if want != 0.0:
				position += to_hero.normalized() * want * 1.6 * speed * dt
				yaw += angle_difference(yaw, atan2(to_hero.x, to_hero.z) + (PI if want < 0 else 0.0)) * (1.0 - exp(-1.5 * dt))
		if area.size.x > 0:
			position.x = clampf(position.x, area.position.x + 3, area.end.x - 3)
			position.z = clampf(position.z, area.position.y + 3, area.end.y - 3)
		var aim := lock if (state == "slam" and st_t < 0.4) else hero_flat
		var want_turn := atan2(aim.x - position.x, aim.z - position.z)
		turn_yaw += angle_difference(turn_yaw, want_turn) * (1.0 - exp(-(3.5 if state == "slam" else 2.5) * speed * dt))
		if state == "idle" and st_t <= 0.0:
			var opts := ["slam", "spray"]
			if angry and crew_out < 3: opts.append("crew")
			var nxt: String = opts.pick_random()
			if nxt == last_attack and randf() < 0.6: nxt = opts[(opts.find(nxt) + 1) % opts.size()]
			last_attack = nxt; state = nxt
			if nxt == "slam": st_t = 1.85 / speed; warn.visible = true; Snd.at("crane_warn", position, 0, 0.0)
			elif nxt == "spray": st_t = 0.8; sprays = 2 if angry else 1
			else: st_t = 1.2
		if state == "slam":
			if st_t > 0.4:
				lock = hero_flat
				var off := lock - Vector3(position.x, 0, position.z)
				var l := off.length()
				var min_r := 0.8 + BOOM * cos(1.1)
				if l < min_r: lock = Vector3(position.x, 0, position.z) + (off / l if l > 0.01 else Vector3(sin(turn_yaw), 0, cos(turn_yaw))) * min_r
			var reach := clampf(Vector2(lock.x - position.x, lock.z - position.z).length(), 4.0, 10.5)
			pitch += (minf(1.1, acos(clampf((reach - 0.8) / BOOM, -1, 1))) - pitch) * (1.0 - exp(-6.0 * dt))
			warn.global_position = Vector3(lock.x, position.y + 0.05, lock.z)
			warn_mat.albedo_color.a = (0.5 + sin(t * 20.0) * 0.2) if st_t > 0.4 else 0.95
			if st_t <= 0.0: state = "drop"; st_t = 0.18
		elif state == "spray":
			pitch += (0.9 - pitch) * (1.0 - exp(-3.0 * dt))
			if st_t <= 0.0:
				var from := center() + Vector3(sin(turn_yaw) * 1.4, -0.1, cos(turn_yaw) * 1.4)
				var to := hero + Vector3(0, 0.9, 0)
				var base := atan2(to.x - from.x, to.z - from.z)
				var n := 7 if angry else 5
				var spread := 1.0 if angry else 0.8
				var dist := Vector2(to.x - from.x, to.z - from.z).length()
				for i in n:
					var a := base + (float(i) / (n - 1) - 0.5) * spread
					combat.enemy_shot(from, Vector3(from.x + sin(a) * dist, to.y, from.z + cos(a) * dist))
				sprays -= 1; st_t = 0.55; Snd.at("crane_spray", from, 2)
				if sprays <= 0: state = "idle"; st_t = randf_range(1.4, 2.0) / speed
		elif state == "crew":
			pitch += (0.5 - pitch) * (1.0 - exp(-3.0 * dt))
			if st_t <= 0.0:
				for i in 2:
					var a := randf() * TAU
					var r := randf_range(4, 7)
					var x := clampf(hero.x + sin(a) * r, area.position.x + 1.5, area.end.x - 1.5)
					var z := clampf(hero.z + cos(a) * r, area.position.y + 1.5, area.end.y - 1.5)
					spawn_roller.call(Vector3(x, position.y, z)); crew_out += 1
				state = "idle"; st_t = 1.2 / speed
		elif state == "idle":
			pitch += (0.55 - pitch) * (1.0 - exp(-2.0 * dt))
	rotation.y = yaw
	turn.rotation.y = turn_yaw - yaw
	boom.rotation.x = -pitch
	var tip_w := tip.global_position
	var mag_y: float
	if state == "drop":
		mag_y = maxf(position.y + 0.3, mag.y - dt * 60.0)
		if mag_y <= position.y + 0.3:
			var hp_ := Vector3(mag.x, position.y, mag.z)
			FX.explosion(hp_ + Vector3(0, 0.3, 0), 1.2); FX.ring(hp_ + Vector3(0, 0.06, 0), Color(1, 0.3, 0.2), 1.3); FX.shake(1.3); Snd.at("crane_slam", hp_, 4)
			if Vector2(hero.x - hp_.x, hero.z - hp_.z).length() < 2.2 and hero.y < position.y + 1.4: combat.hurt_player(2, hp_)
			state = "hold"; st_t = 0.8 / speed; warn.visible = false
	elif state == "hold":
		mag_y = position.y + 0.3
		if st_t <= 0.0: state = "idle"; st_t = randf_range(1.3, 1.9) / speed
	else:
		mag_y = mag.y + (minf(tip_w.y - 1.5, position.y + 6.0) - mag.y) * (1.0 - exp(-3.0 * dt))
	mag = Vector3(tip_w.x, mag_y, tip_w.z)
	magnet.global_position = mag
	mag_mat.emission_energy_multiplier = 8.0 if (state == "slam" or state == "drop") else 3.0
	var top := tip_w
	var bot := mag + Vector3(0, 0.6, 0)
	cable.global_position = (top + bot) * 0.5
	cable.scale = Vector3(1, maxf(0.05, top.distance_to(bot)), 1)
	eye_mat.emission_energy_multiplier = (10.0 if angry else 6.0) + sin(t * (14.0 if angry else 5.0)) * 3.0
	if angry: eye_mat.emission = Color(1, 0.35, 0.1)
