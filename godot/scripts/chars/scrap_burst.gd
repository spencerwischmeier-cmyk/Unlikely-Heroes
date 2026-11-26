extends Node3D
## Break-apart debris for Grudd Works bots: sprockets, bolts, nuts, springs and painted panel shards fly
## out, tumble, bounce on the ground and shrink away. Pieces of the bot's own model (a roller's head, a
## hornet's wings) can be thrown too: they are reparented here and tumble with the rest.
##   ScrapBurst.burst(parent, pos, scale, livery_mats, count, parts)
## One node per burst; all pieces are integrated here (no physics bodies).

const BITS := "res://models/chars/scrap_bits.glb"
const SMALL := ["sprocket", "sprocket", "sprocket_small", "bolt", "bolt", "nut", "nut", "spring"]
const LIFE := 1.9

static var _meshes := {}      # bit name -> [Mesh, Material]

var pieces: Array = []        # { node, vel, spin, life, s0 }
var ground := -INF
var t := 0.0

static func _load_bits() -> void:
	if not _meshes.is_empty() or not ResourceLoader.exists(BITS): return
	var root: Node = load(BITS).instantiate()
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		_meshes[String(m.name)] = [m.mesh, m.get_active_material(0)]
	root.free()

## Throw scrap from `pos`. `livery_mats` paint the panel shards (the bot's own materials look best);
## `parts` are nodes of the bot's model to rip off and throw along with the scrap; `eye` adds its glowing lens.
static func burst(parent: Node, pos: Vector3, scale := 1.0, livery_mats: Array = [], count := 10, parts: Array = [], eye := false) -> Node3D:
	if parent == null or not parent.is_inside_tree(): return null
	_load_bits()
	var b: Node3D = load("res://scripts/chars/scrap_burst.gd").new()
	b.name = "ScrapBurst"
	parent.add_child(b)
	b.global_position = pos
	b.call("_find_ground", pos)
	# paint the shards with the bot's livery, minus any hit flash or charge glow it had on
	var paint: Array = []
	for m in livery_mats:
		if m is StandardMaterial3D and (m as StandardMaterial3D).emission_enabled:
			var c := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
			c.emission_enabled = false; paint.append(c)
		elif m is Material: paint.append(m)
	livery_mats = paint
	for i in count + (1 if eye else 0):
		var mi := MeshInstance3D.new()
		var plate := i % 3 == 2 and i < count
		var key: String = ("plate" if i % 2 == 0 else "plate_bent") if plate else SMALL[i % SMALL.size()]
		if i == count: key = "eye_lens"     # the bot's eye pops out last
		var bit: Array = _meshes.get(key, [])
		if bit.is_empty():
			var bm := BoxMesh.new(); bm.size = Vector3(0.18, 0.04, 0.14); mi.mesh = bm
		else:
			mi.mesh = bit[0]; mi.material_override = bit[1]
		if plate and livery_mats.size() > 0:
			mi.material_override = livery_mats[i % livery_mats.size()]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var s := scale * randf_range(0.8, 1.35) * (1.4 if plate else 1.0)
		b.add_child(mi)
		mi.scale = Vector3.ONE * s
		mi.position = Vector3(randf_range(-0.3, 0.3), randf_range(0.0, 0.4), randf_range(-0.3, 0.3)) * scale
		mi.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		var dir := Vector3(randf_range(-1, 1), randf_range(0.6, 1.6), randf_range(-1, 1)).normalized()
		b.pieces.append({ node = mi, vel = dir * randf_range(4.0, 8.5) * sqrt(scale), spin = Vector3(randf_range(-14, 14), randf_range(-14, 14), randf_range(-14, 14)),
			life = LIFE * randf_range(0.75, 1.15), s0 = s })
	for p in parts:
		var n := p as Node3D
		if n == null or not is_instance_valid(n): continue
		var gt := n.global_transform
		n.get_parent().remove_child(n)
		b.add_child(n)
		n.global_transform = gt
		var up := Vector3(randf_range(-0.6, 0.6), 1.0, randf_range(-0.6, 0.6)).normalized()
		b.pieces.append({ node = n, vel = up * randf_range(5.0, 7.5) * sqrt(scale) + (gt.origin - pos).normalized() * 2.0,
			spin = Vector3(randf_range(-9, 9), randf_range(-6, 6), randf_range(-9, 9)), life = LIFE * 1.1, s0 = n.scale.x })
	return b

func _find_ground(pos: Vector3) -> void:
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 0.5, 0), pos + Vector3(0, -6, 0)); q.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit: ground = (hit.position as Vector3).y

func _process(dt: float) -> void:
	t += dt
	var alive := 0
	for p in pieces:
		var n: Node3D = p.node
		if not is_instance_valid(n): continue
		p.life -= dt
		if p.life <= 0.0:
			if n.visible: n.visible = false
			continue
		alive += 1
		var v: Vector3 = p.vel
		v.y -= 24.0 * dt
		var gp := n.global_position + v * dt
		if gp.y < ground + 0.04 and v.y < 0.0:
			gp.y = ground + 0.04
			v.y = -v.y * 0.38
			v.x *= 0.55; v.z *= 0.55
			p.spin = p.spin * 0.5
			if absf(v.y) < 0.8: v.y = 0.0
		p.vel = v
		n.global_position = gp
		var sp: Vector3 = p.spin
		n.rotate_x(sp.x * dt); n.rotate_y(sp.y * dt); n.rotate_z(sp.z * dt)
		if p.life < 0.3: n.scale = Vector3.ONE * p.s0 * maxf(0.01, p.life / 0.3)
	if alive == 0 and t > 0.2: queue_free()
