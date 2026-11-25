extends Node3D
## Combat: Vesk's blaster bolts, the bots' shots, hex nut pickups and floating damage numbers.
## Targets are nodes in the "targets" group with `damage(amount, point, dir)`, `dead` and `center()`.

signal nuts_changed(total: int)
signal hull_changed(hull: int, healed: bool)
signal hit_marker(kill: bool)

const MAX_HULL := 8
var player: CharacterBody3D
var nuts := 0
var hull := MAX_HULL
var invuln := 0.0

# Arc Lancer: rapid bolts, never runs dry but overheats
var heat := 0.0
var overheated := false
var cool := 0.0
const LANCER_INTERVAL := 0.12
const LANCER_DMG := 1.0

var bolts: Array = []       # { node, vel, life, dmg }
var shots: Array = []       # enemy shots
var pickups: Array = []     # { node, vel, t, kind }

var bolt_mesh: CapsuleMesh
var bolt_mat: StandardMaterial3D
var shot_mat: StandardMaterial3D
var nut_mesh: TorusMesh
var nut_mat: StandardMaterial3D
var cell_mat: StandardMaterial3D

func _ready() -> void:
	bolt_mesh = CapsuleMesh.new(); bolt_mesh.radius = 0.05; bolt_mesh.height = 1.0
	bolt_mat = _glow(Color(0.6, 0.98, 1.0), 8.0)
	shot_mat = _glow(Color(1.0, 0.25, 0.15), 8.0)
	nut_mesh = TorusMesh.new(); nut_mesh.inner_radius = 0.07; nut_mesh.outer_radius = 0.17; nut_mesh.ring_segments = 6; nut_mesh.rings = 6
	nut_mat = StandardMaterial3D.new(); nut_mat.albedo_color = Color(1.0, 0.76, 0.24); nut_mat.metallic = 1.0; nut_mat.roughness = 0.22
	nut_mat.emission_enabled = true; nut_mat.emission = Color(0.4, 0.22, 0.0); nut_mat.emission_energy_multiplier = 0.6
	cell_mat = _glow(Color(0.3, 1.0, 0.55), 3.0)

func _glow(c: Color, e: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new(); m.albedo_color = Color.BLACK; m.emission_enabled = true; m.emission = c; m.emission_energy_multiplier = e
	return m

# ---------- Vesk's blaster ----------
func try_fire(dt: float, want: bool, muzzle: Vector3, aim_point: Vector3, aim_dir: Vector3) -> bool:
	cool -= dt
	if overheated:
		heat -= dt * 0.55
		if heat <= 0.45: overheated = false
	elif not want or cool > 0.0:
		heat = maxf(0.0, heat - dt * (0.5 if cool < -0.4 else 0.1))
	if not want or overheated or cool > 0.0: return false
	cool = LANCER_INTERVAL
	heat += 0.03
	if heat >= 1.0: heat = 1.0; overheated = true
	var dir := (aim_point - muzzle).normalized()
	if dir.dot(aim_dir) < 0.3: dir = aim_dir
	dir = (dir + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.008).normalized()
	var mi := MeshInstance3D.new(); mi.mesh = bolt_mesh; mi.material_override = bolt_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi); mi.global_position = muzzle
	mi.global_basis = Basis(Quaternion(Vector3.UP, dir))
	var l := OmniLight3D.new(); l.light_color = Color(0.4, 0.95, 1); l.light_energy = 1.5; l.omni_range = 3.0; mi.add_child(l)
	bolts.append({ node = mi, vel = dir * 75.0, life = 1.6, dmg = LANCER_DMG })
	FX.sparks(muzzle, Color(0.6, 0.98, 1.0), 4, 3.0)
	return true

func melee(origin: Vector3, facing: Vector3) -> bool:
	var any := false
	for t in get_tree().get_nodes_in_group("targets"):
		if t.dead: continue
		var c: Vector3 = t.center()
		var d := c - origin
		var dy := d.y - 0.8
		d.y = 0
		if d.length() < 2.6 and absf(dy) < 1.8 and (d.length() < 0.8 or d.normalized().dot(facing) > -0.1):
			t.damage(3.0 if t.is_in_group("boss") else 2.0, c, facing)
			FX.sparks(c, Color(1, 0.95, 0.7), 16, 6)
			any = true
	if any: FX.stop(0.06); FX.shake(0.5)
	return any

func nearest_target(origin: Vector3, max_d: float) -> Node3D:
	var best: Node3D = null
	var bd := max_d
	for t in get_tree().get_nodes_in_group("targets"):
		if t.dead or t.is_in_group("crate"): continue
		var c: Vector3 = t.center()
		var d := Vector2(c.x - origin.x, c.z - origin.z).length()
		if d < bd and absf(c.y - origin.y - 0.8) < 2.0: bd = d; best = t
	return best

# ---------- bots' shots ----------
func enemy_shot(from: Vector3, to: Vector3) -> void:
	var dir := (to - from).normalized()
	var mi := MeshInstance3D.new(); mi.mesh = bolt_mesh; mi.material_override = shot_mat
	mi.scale = Vector3(1.4, 0.7, 1.4)
	add_child(mi); mi.global_position = from
	mi.global_basis = Basis(Quaternion(Vector3.UP, dir)).scaled(Vector3(1.4, 0.7, 1.4))
	var l := OmniLight3D.new(); l.light_color = Color(1, 0.3, 0.2); l.light_energy = 2.0; l.omni_range = 3.5; mi.add_child(l)
	shots.append({ node = mi, vel = dir * 17.0, life = 3.0 })

func hurt_player(n: int, from = null, force := false) -> void:
	if (invuln > 0.0 and not force) or hull <= 0: return
	hull -= n; invuln = 0.9
	FX.shake(1.0)
	hull_changed.emit(hull, false)
	if from != null and player:
		var k: Vector3 = (player.global_position - from); k.y = 0
		player.velocity += k.normalized() * 6.0
	if hull <= 0:
		hull = MAX_HULL
		hull_changed.emit(hull, true)
		if player: player.respawn()

func heal(n: int) -> void:
	hull = mini(MAX_HULL, hull + n); hull_changed.emit(hull, true)

# ---------- hex nuts and repair cells ----------
func drop_nuts(pos: Vector3, n: int) -> void:
	for i in n:
		var mi := MeshInstance3D.new(); mi.mesh = nut_mesh; mi.material_override = nut_mat
		add_child(mi); mi.global_position = pos
		pickups.append({ node = mi, vel = Vector3(randf_range(-3, 3), randf_range(4, 8), randf_range(-3, 3)), t = 0.0, kind = "nut", spin = Vector3(randf_range(-8, 8), randf_range(-8, 8), 0) })

func drop_cell(pos: Vector3) -> void:
	var m := PrismMesh.new(); m.size = Vector3(0.35, 0.35, 0.35)
	var mi := MeshInstance3D.new(); mi.mesh = m; mi.material_override = cell_mat
	add_child(mi); mi.global_position = pos
	pickups.append({ node = mi, vel = Vector3(randf_range(-1, 1), 5, randf_range(-1, 1)), t = 0.0, kind = "cell", spin = Vector3(0, 3, 0) })

func damage_number(pos: Vector3, amount: float, kill: bool) -> void:
	var l := Label3D.new()
	l.text = str(snappedf(amount, 0.1)).trim_suffix(".0")
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font_size = 64 if kill else 44
	l.outline_size = 12
	l.modulate = Color(1, 0.85, 0.3) if kill else Color(1, 1, 1)
	l.pixel_size = 0.006
	add_child(l); l.global_position = pos + Vector3(randf_range(-0.3, 0.3), 0.4, randf_range(-0.3, 0.3))
	var tw := create_tween().set_parallel()
	tw.tween_property(l, "global_position", l.global_position + Vector3(0, 1.2, 0), 0.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(l, "modulate:a", 0.0, 0.7).set_delay(0.25)
	tw.chain().tween_callback(l.queue_free)

func _physics_process(dt: float) -> void:
	invuln -= dt
	var space := get_world_3d().direct_space_state
	# player bolts: sweep a ray each step so fast bolts never skip through a bot
	for i in range(bolts.size() - 1, -1, -1):
		var b: Dictionary = bolts[i]
		var from: Vector3 = b.node.global_position
		var to: Vector3 = from + b.vel * dt
		b.life -= dt
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.collision_mask = 1 | 4
		if player: q.exclude = [player.get_rid()]
		var hit := space.intersect_ray(q)
		if hit:
			var col: Object = hit.collider
			var t: Node = col if (col is Node and col.is_in_group("targets")) else (col.get_parent() if col is Node and col.get_parent() and col.get_parent().is_in_group("targets") else null)
			if t and not t.dead:
				var kill: bool = t.damage(b.dmg, hit.position, b.vel.normalized())
				hit_marker.emit(kill)
				if not t.is_in_group("crate"): damage_number(hit.position, b.dmg, kill)
			FX.sparks(hit.position, Color(0.6, 0.98, 1.0), 8, 4)
			b.node.queue_free(); bolts.remove_at(i); continue
		b.node.global_position = to
		if b.life <= 0.0: b.node.queue_free(); bolts.remove_at(i)
	# enemy shots
	var hero_c := player.global_position + Vector3(0, 0.9, 0) if player else Vector3.ZERO
	for i in range(shots.size() - 1, -1, -1):
		var s: Dictionary = shots[i]
		var from: Vector3 = s.node.global_position
		var to: Vector3 = from + s.vel * dt
		s.life -= dt
		var seg := to - from
		var k := clampf((hero_c - from).dot(seg) / maxf(seg.length_squared(), 1e-6), 0, 1)
		var hit_hero := player and (from + seg * k).distance_to(hero_c) < 0.6
		var q := PhysicsRayQueryParameters3D.create(from, to); q.collision_mask = 1
		var hw := space.intersect_ray(q)
		if hit_hero or hw or s.life <= 0.0:
			if hit_hero: hurt_player(1, from)
			FX.sparks(to, Color(1, 0.4, 0.25), 8, 4)
			s.node.queue_free(); shots.remove_at(i); continue
		s.node.global_position = to
	# pickups
	if player:
		var target := player.global_position + Vector3(0, 0.8, 0)
		for i in range(pickups.size() - 1, -1, -1):
			var p: Dictionary = pickups[i]
			p.t += dt
			var pos: Vector3 = p.node.global_position
			var d := pos.distance_to(target)
			if p.t > 0.5 and (d < (10.0 if p.kind == "nut" else 3.0) or (p.kind == "nut" and p.t > 2.2)):
				p.vel = p.vel.lerp((target - pos).normalized() * maxf(14.0, 30.0 - d * 1.5), 1.0 - exp(-10.0 * dt))
			else:
				p.vel.y -= 20.0 * dt
			pos += p.vel * dt
			var q := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 0.3, 0), pos - Vector3(0, 0.12, 0)); q.collision_mask = 1
			var g := space.intersect_ray(q)
			if g and p.vel.y < 0:
				pos.y = g.position.y + 0.12; p.vel.y = absf(p.vel.y) * 0.4; p.vel.x *= 0.7; p.vel.z *= 0.7
			p.node.global_position = pos
			p.node.rotation += p.spin * dt
			if d < 0.75:
				if p.kind == "nut": nuts += 10; nuts_changed.emit(nuts)
				else: heal(1)
				p.node.queue_free(); pickups.remove_at(i); continue
			if p.t > 25.0 or pos.y < -40.0: p.node.queue_free(); pickups.remove_at(i)
