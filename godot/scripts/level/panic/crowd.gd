extends Node3D
## Skyharbor's citizens, in a panic since the signal sent every bot haywire. Built by panic.gd.
## - Walkable ground comes from the level itself: once physics is up, each layer (a floor height and a
##   rect) is scanned with downward rays on a 1 m grid. A cell is walkable when the first thing under
##   head height is floor at that height, so props, fences and walls are avoided without hand-made paths.
##   Cells next to anything blocked cost more, so people keep off fences and walls where they can.
## - People: four species (models/citizens/cit_*.glb, Meshy rigs with clips idle, run, run2, wave, carry,
##   look, cower, hop, shout, sneak) with tints and sizes. They run between random spots of their home
##   area, stop to look around, wave, shout or hop, duck and flee when a bot gets close, and step aside
##   for Vesk. Evacuees walk to the docks with luggage, queue at the shuttle gangway and board it
##   (evac.gd opens and closes boarding); boarded people come back later as new evacuees out of sight.
## - Barks (audio/voice/panic_<species>_<n>.ogg) from people near Vesk, one at a time, positional.
## - Cheap at a distance: people more than ACTIVE_D from Vesk freeze (no animation), past SHOW_D they hide.
## Debug: `-- --panic-map=out.png` writes the walk grids as an image and quits.

const Device := preload("res://scripts/device.gd")
const SPECIES := ["cit_frog", "cit_bird", "cit_mole", "cit_goat"]
const BARK := {"cit_frog": "frog", "cit_bird": "bird", "cit_mole": "mole", "cit_goat": "goat"}
const WHO := {"frog": "dockhand", "bird": "traveller", "mole": "shopkeeper", "goat": "tourist"}

## the words of every panic line (audio/voice/panic_lines.json, written by art/voice_panic.py), for subtitles
static func line_text(id: String) -> String:
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://audio/voice/panic_lines.json")) if FileAccess.file_exists("res://audio/voice/panic_lines.json") else null
	return d.get(id, "") if d is Dictionary else ""
const TINTS := [Color(1, 1, 1), Color(1.0, 0.92, 0.86), Color(0.88, 0.95, 1.0), Color(0.95, 1.0, 0.9), Color(1.0, 0.95, 1.0)]
const ACTIVE_D := 70.0
const SHOW_D := 105.0
const CELL := 1.0
const SCAN_PER_FRAME := 6000

var L: Node3D
var layers: Array = []        # { name, y, rect: Rect2, w, h, hgt: PackedFloat32Array, walk: PackedByteArray, astar, scan: int }
var people: Array = []        # see _spawn()
var zones: Array = []         # { name, layer, rect, count, roles }
var scenes := {}
var mats := {}                # "<species>:<tint>:<surface>" -> Material (shared by everyone with that look)
var ready_ := false
var paused := false
var calm := false              # after the boss: no more fleeing, cheering instead
var t := 0.0
var bots: Array = []          # bot positions, refreshed a few times a second
var bot_t := 0.0
var bark_t := 6.0
var bark_player: AudioStreamPlayer3D
var heard := {}               # lines already played recently
var special_done := {}
var rng := RandomNumberGenerator.new()
var ray := PhysicsRayQueryParameters3D.new()
var path_budget := 0

# queue and boarding (driven by evac.gd)
var queue_slots: Array = []   # Vector3, slot 0 at the gangway foot
var queue: Array = []         # people, by slot
var board_path: Array = []    # Vector3 points from the gangway foot to the hatch
var boarding := false
var board_t := 0.0
var sources: Array = []       # [layer index, Rect2] where new evacuees appear (out of sight)
var crowd_spot := Rect2()     # where evacuees mill about when the queue is full
var evacuees_wanted := 14

func setup(level: Node3D) -> void:
	L = level
	rng.seed = 2611
	ray.collision_mask = 1
	ray.hit_from_inside = true   # a ray starting inside something tall (a container) counts as blocked
	for s in SPECIES:
		var p := "res://models/citizens/%s.glb" % s
		if ResourceLoader.exists(p): scenes[s] = load(p)

## a walk layer: everything at floor height y inside r
func add_layer(name_: String, y: float, r: Rect2) -> int:
	var w := int(ceil(r.size.x / CELL)); var h := int(ceil(r.size.y / CELL))
	var hg := PackedFloat32Array(); hg.resize(w * h)
	var wk := PackedByteArray(); wk.resize(w * h)
	layers.append({ name = name_, y = y, rect = r, w = w, h = h, hgt = hg, walk = wk, astar = null, scan = 0 })
	return layers.size() - 1

## a home area: `count` people of the given roles ("roam", "evac") start in it
func add_zone(name_: String, layer: int, r: Rect2, count: int, roles := ["roam"]) -> void:
	count = Device.scale(count)   # fewer people on phones and in browsers
	zones.append({ name = name_, layer = layer, rect = r, count = count, roles = roles })

func _ready() -> void:
	bark_player = AudioStreamPlayer3D.new(); bark_player.bus = "World"; bark_player.unit_size = 7.0
	bark_player.max_distance = 45.0; bark_player.volume_db = -2.0
	add_child(bark_player)

# ------------------------------------------------------------------ the walk grid
func _scan(dt: float) -> bool:
	var space := get_world_3d().direct_space_state
	var budget := SCAN_PER_FRAME
	for ly in layers:
		var n: int = ly.w * ly.h
		while ly.scan < n and budget > 0:
			var i: int = ly.scan
			var cx := i % int(ly.w); var cz := i / int(ly.w)
			var x: float = ly.rect.position.x + (cx + 0.5) * CELL
			var z: float = ly.rect.position.y + (cz + 0.5) * CELL
			ray.from = Vector3(x, ly.y + 2.2, z); ray.to = Vector3(x, ly.y - 0.8, z)
			var hit := space.intersect_ray(ray)
			var ok := false
			if hit and hit.normal.y > 0.85 and absf(hit.position.y - ly.y) < 0.45: ok = true
			ly.walk[i] = 1 if ok else 0
			ly.hgt[i] = hit.position.y if ok else ly.y
			ly.scan += 1; budget -= 1
		if ly.scan < n: return false
	for ly in layers:
		if ly.astar == null: _finish_layer(ly)
	return true

func _finish_layer(ly: Dictionary) -> void:
	var w: int = ly.w; var h: int = ly.h
	var edge := PackedByteArray(); edge.resize(w * h)
	for i in w * h:
		if ly.walk[i] == 0: continue
		var cx := i % w; var cz := i / w
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = cx + d.x; var nz: int = cz + d.y
			if nx < 0 or nz < 0 or nx >= w or nz >= h or ly.walk[nz * w + nx] == 0:
				edge[i] = 1; break
	for i in w * h: if edge[i]: ly.walk[i] = 2
	var a := AStarGrid2D.new()
	a.region = Rect2i(0, 0, w, h); a.cell_size = Vector2(1, 1)
	a.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	a.update()
	for i in w * h:
		var c := Vector2i(i % w, i / w)
		if ly.walk[i] == 0: a.set_point_solid(c, true)
		elif ly.walk[i] == 2: a.set_point_weight_scale(c, 4.0)
	ly.astar = a

func _cell(ly: Dictionary, p: Vector3) -> Vector2i:
	return Vector2i(int(floor((p.x - ly.rect.position.x) / CELL)), int(floor((p.z - ly.rect.position.y) / CELL)))

func _walk_at(ly: Dictionary, c: Vector2i) -> int:
	if c.x < 0 or c.y < 0 or c.x >= ly.w or c.y >= ly.h: return 0
	return ly.walk[c.y * ly.w + c.x]

func _world(ly: Dictionary, c: Vector2i) -> Vector3:
	var i: int = c.y * ly.w + c.x
	return Vector3(ly.rect.position.x + (c.x + 0.5) * CELL, ly.hgt[i], ly.rect.position.y + (c.y + 0.5) * CELL)

func _floor_y(ly: Dictionary, p: Vector3) -> float:
	var c := _cell(ly, p)
	if _walk_at(ly, c) == 0: return p.y
	return ly.hgt[c.y * ly.w + c.x]

## a random open (non-edge) cell inside r, or the zero cell (-1, -1) when there is none
func _random_cell(ly: Dictionary, r: Rect2, tries := 24) -> Vector2i:
	for k in tries:
		var p := Vector3(rng.randf_range(r.position.x, r.end.x), 0, rng.randf_range(r.position.y, r.end.y))
		var c := _cell(ly, p)
		if _walk_at(ly, c) == 1: return c
	return Vector2i(-1, -1)

func _nearest_walk(ly: Dictionary, p: Vector3) -> Vector2i:
	var c := _cell(ly, p)
	if _walk_at(ly, c) != 0: return c
	for r in range(1, 6):
		for dx in range(-r, r + 1):
			for dz in [-r, r]:
				if _walk_at(ly, c + Vector2i(dx, dz)) != 0: return c + Vector2i(dx, dz)
				if _walk_at(ly, c + Vector2i(dz, dx)) != 0: return c + Vector2i(dz, dx)
	return Vector2i(-1, -1)

## a path of world points from p to cell `to` (thinned: points kept only where the direction changes)
func _path(ly: Dictionary, p: Vector3, to: Vector2i) -> PackedVector3Array:
	var out := PackedVector3Array()
	var from := _nearest_walk(ly, p)
	if from.x < 0 or to.x < 0: return out
	var ids: Array[Vector2i] = ly.astar.get_id_path(from, to, true)
	var last_d := Vector2i.ZERO
	for k in range(1, ids.size()):
		var d: Vector2i = ids[k] - ids[k - 1]
		if d != last_d and k > 1: out.append(_world(ly, ids[k - 1]))
		last_d = d
	if ids.size() > 0: out.append(_world(ly, ids[ids.size() - 1]))
	# jitter so a crowd heading the same way doesn't walk in single file
	for k in range(out.size() - 1):
		var q := out[k] + Vector3(rng.randf_range(-0.35, 0.35), 0, rng.randf_range(-0.35, 0.35))
		if _walk_at(ly, _cell(ly, q)) != 0: out[k] = q
	return out

# ------------------------------------------------------------------ people
func _material_for(species: String, tint: int, si: int, base: Material) -> Material:
	var key := "%s:%d:%d" % [species, tint, si]
	if mats.has(key): return mats[key]
	var m: Material = base
	if tint > 0 and base is StandardMaterial3D:
		m = base.duplicate(); (m as StandardMaterial3D).albedo_color = (base as StandardMaterial3D).albedo_color * TINTS[tint]
	mats[key] = m
	return m

func _make_body(species: String, tint: int) -> Node3D:
	var holder := Node3D.new()
	var sc: PackedScene = scenes.get(species)
	if sc == null:
		# placeholder: a capsule with a head (only if the models are missing)
		var cm := CapsuleMesh.new(); cm.radius = 0.3; cm.height = 1.5
		var mi := MeshInstance3D.new(); mi.mesh = cm; mi.position.y = 0.75; holder.add_child(mi)
		return holder
	var m: Node3D = sc.instantiate()
	holder.add_child(m)
	if not has_meta("looped_" + species):
		# the clips come in from glTF without looping: every one of them loops here (shared by all instances)
		set_meta("looped_" + species, true)
		var ap: AnimationPlayer = m.find_child("AnimationPlayer", true, false)
		if ap:
			for n in ap.get_animation_list(): ap.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		var mm := mi as MeshInstance3D
		mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if tint > 0 and mm.mesh:
			for si in mm.mesh.get_surface_count():
				var base := mm.mesh.surface_get_material(si)
				if base: mm.set_surface_override_material(si, _material_for(species, tint, si, base))
	return holder

func _luggage(holder: Node3D, h: float) -> Node3D:
	var b := Node3D.new(); holder.add_child(b)
	var cols := [Color(0.62, 0.3, 0.2), Color(0.2, 0.42, 0.6), Color(0.75, 0.6, 0.25), Color(0.5, 0.25, 0.45)]
	var mat := StandardMaterial3D.new(); mat.albedo_color = cols[rng.randi() % cols.size()]; mat.roughness = 0.6
	var bm := BoxMesh.new(); bm.size = Vector3(0.62, 0.42, 0.26) * (h / 1.7)
	var mi := MeshInstance3D.new(); mi.mesh = bm; mi.material_override = mat; b.add_child(mi)
	var strap := StandardMaterial3D.new(); strap.albedo_color = Color(0.25, 0.18, 0.12)
	var sm := BoxMesh.new(); sm.size = Vector3(0.64, 0.06, 0.28) * (h / 1.7)
	var si := MeshInstance3D.new(); si.mesh = sm; si.material_override = strap; b.add_child(si)
	b.position = Vector3(0, 0.95 * h / 1.7, 0.42 * h / 1.7)
	return b

func _spawn(zone: Dictionary, role: String) -> void:
	var ly: Dictionary = layers[zone.layer]
	var c := _random_cell(ly, zone.rect, 60)
	if c.x < 0: return
	var species: String = SPECIES[people.size() % SPECIES.size()]
	var tint := rng.randi() % TINTS.size()
	var node := _make_body(species, tint)
	add_child(node)
	var s := rng.randf_range(0.9, 1.08)
	node.scale = Vector3.ONE * s
	var pos := _world(ly, c)
	node.position = pos
	var ap: AnimationPlayer = node.find_child("AnimationPlayer", true, false)
	var p := { node = node, ap = ap, species = species, layer = zone.layer, home = zone.rect, pos = pos,
		yaw = rng.randf() * TAU, state = "react", t = rng.randf_range(0.2, 2.0), path = PackedVector3Array(), pi = 0,
		speed = 5.0, anim = "", role = role, active = true, luggage = null, slot = -1, flee_from = Vector3.ZERO,
		run_clip = "run" if rng.randf() < 0.6 else "run2", rate = rng.randf_range(0.9, 1.12), threat_t = rng.randf(), want_path = false,
		dest = Vector2i(-1, -1), react = "look",
		meshes = node.find_children("*", "MeshInstance3D", true, false), near = true, shad = true, adt = 0.0, phase = people.size() % 3 }
	if role == "evac":
		p.luggage = _luggage(node, 1.7)
		p.luggage.visible = false
	people.append(p)
	_react(p, ["look", "idle", "wave"].pick_random(), rng.randf_range(0.3, 2.5))

func _play(p: Dictionary, clip: String, blend := 0.25, speed := 1.0) -> void:
	if p.ap == null: return
	p.ap.speed_scale = speed * p.rate
	if p.anim == clip: return
	p.anim = clip
	var c := clip if p.ap.has_animation(clip) else "idle"
	if p.ap.has_animation(c): p.ap.play(c, blend)

func _react(p: Dictionary, what: String, dur: float) -> void:
	p.state = "react"; p.t = dur; p.react = what
	_play(p, what)

## head off somewhere: evacuees to the queue (or the crowd by it), everyone else to a random spot of home
func _go(p: Dictionary, run := true) -> void:
	var ly: Dictionary = layers[p.layer]
	var to := Vector2i(-1, -1)
	if p.role == "evac" and p.state != "flee":
		var free := _free_slot()
		if free >= 0:
			queue[free] = p; p.slot = free
			to = _nearest_walk(ly, queue_slots[free])
		else:
			to = _random_cell(ly, crowd_spot)
	if to.x < 0:
		var area: Rect2 = p.home
		if p.flee_from != Vector3.ZERO:
			# pick the far one of a few candidates around, away from the threat
			var best := -1.0
			for k in 6:
				var r := Rect2(p.pos.x - 14, p.pos.z - 14, 28, 28).intersection(area.grow(6))
				var c := _random_cell(ly, r, 8)
				if c.x < 0: continue
				var d := _world(ly, c).distance_to(p.flee_from)
				if d > best: best = d; to = c
		if to.x < 0: to = _random_cell(ly, area)
	if to.x < 0:
		_react(p, "look", 2.0); return
	p.dest = to; p.want_path = true
	p.state = "walk"
	var carrying: bool = p.role == "evac" and p.slot >= 0 and p.flee_from == Vector3.ZERO
	if p.luggage: p.luggage.visible = carrying
	if carrying: p.speed = rng.randf_range(2.3, 2.8); _play(p, "carry", 0.25, 1.3)
	elif run and not calm: p.speed = rng.randf_range(4.2, 5.6); _play(p, p.run_clip, 0.2, p.speed / 5.0)
	elif calm: p.speed = 3.0; _play(p, "run2", 0.25, 0.62)
	else: p.speed = 1.5; _play(p, "sneak")

func _free_slot() -> int:
	for i in queue.size():
		if queue[i] == null: return i
	return -1

# ------------------------------------------------------------------ per frame
func _physics_process(dt: float) -> void:
	if not ready_:
		if L == null or not L.is_inside_tree(): return
		t += dt
		if t < 0.2: return        # let the level's bodies register first
		if _scan(dt):
			ready_ = true
			queue.resize(queue_slots.size()); queue.fill(null)
			for z in zones:
				for k in z.count: _spawn(z, z.roles[k % z.roles.size()])
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--panic-map="): _dump_map(a.substr(12))

## People move once per drawn frame, not per physics step: they have no bodies, and at 120 Hz physics a
## slow frame ran the whole crowd (and its O(n^2) separation) four or five times over.
func _process(dt: float) -> void:
	if not ready_ or paused: return
	dt = minf(dt, 0.05)
	t += dt
	var pl: Node3D = Game.player
	var pp: Vector3 = pl.global_position if pl else Vector3(1e6, 0, 1e6)
	bot_t -= dt
	if bot_t <= 0.0:
		bot_t = 0.3
		bots.clear()
		for b in get_tree().get_nodes_in_group("bots"):
			if b is Node3D and b.is_inside_tree() and not b.is_in_group("dead"): bots.append((b as Node3D).global_position)
	path_budget = 3
	for p in people: _step(p, dt, pp)
	_separate(pp)
	_boarding(dt)
	_barks(dt, pp)

## Level of detail for people: past SHADOW_D they stop casting shadows, past NEAR_D their animation
## updates every other frame (staggered, with the time saved up so they don't slow down).
const NEAR_D := 24.0
const SHADOW_D := 36.0
func _lod(p: Dictionary, d: float, dt: float) -> void:
	var shad := d < SHADOW_D
	if shad != p.shad:
		p.shad = shad
		for mi in p.meshes:
			if is_instance_valid(mi): (mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shad else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if p.ap == null: return
	var near := d < NEAR_D
	if near != p.near:
		p.near = near
		p.ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE if near else AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		p.adt = 0.0
	if not near and p.active:
		p.adt += dt
		if Engine.get_process_frames() % 2 == p.phase % 2:
			p.ap.advance(p.adt); p.adt = 0.0

func _step(p: Dictionary, dt: float, pp: Vector3) -> void:
	if p.state == "gone":
		p.t -= dt
		if p.t <= 0.0: _respawn(p, pp)
		return
	var d := Vector2(p.pos.x - pp.x, p.pos.z - pp.z).length()
	var act := d < ACTIVE_D and absf(p.pos.y - pp.y) < 30.0
	if act != p.active:
		p.active = act
		if p.ap: p.ap.active = act
	p.node.visible = d < SHOW_D
	_lod(p, d, dt)
	# far away people stand still, except those on their way somewhere (evacuees must still reach the queue)
	if not act and p.state != "walk": return
	# threats: a bot close by makes people duck and run (queuers just flinch)
	p.threat_t -= dt
	if p.threat_t <= 0.0:
		p.threat_t = 0.35
		var near := Vector3.ZERO; var nd := 8.0
		for b in bots:
			var bd: float = (b as Vector3).distance_to(p.pos)
			if bd < nd: nd = bd; near = b
		if near != Vector3.ZERO and not calm:
			if p.state == "queue" or p.state == "board":
				if p.anim != "cower" and rng.randf() < 0.3: _play(p, "cower")
			elif p.state != "cower" and p.flee_from.distance_to(near) > 3.0:
				p.flee_from = near
				_leave_queue(p)
				p.state = "cower"; p.t = rng.randf_range(0.5, 0.9); _play(p, "cower", 0.12)
				if rng.randf() < 0.5: _scream(p)
		elif p.flee_from != Vector3.ZERO and p.flee_from.distance_to(p.pos) > 16.0:
			p.flee_from = Vector3.ZERO
	match p.state:
		"react", "cower":
			p.t -= dt
			_face(p, (pp - p.pos) if d < 9.0 and p.state == "react" else Vector3.ZERO, dt, 3.0)
			if p.t <= 0.0: _go(p, true)
		"walk":
			if p.want_path:
				if path_budget <= 0: return
				path_budget -= 1
				p.want_path = false
				p.path = _path(layers[p.layer], p.pos, p.dest); p.pi = 0
				if p.path.is_empty():
					_leave_queue(p); _react(p, "look", 1.5); return
			_follow(p, dt)
		"queue":
			p.t -= dt
			var slot: Vector3 = queue_slots[p.slot]
			var to: Vector3 = slot - p.pos; to.y = 0
			if to.length() > 0.15:
				p.pos += to.normalized() * minf(to.length(), 1.6 * dt)
				_play(p, "carry" if to.length() > 0.4 else p.anim)
			if p.t <= 0.0:
				p.t = rng.randf_range(2.5, 6.0)
				_play(p, ["idle", "look", "wave", "shout", "hop", "idle", "wave"].pick_random())
			_face(p, (board_path[0] - p.pos) if board_path.size() > 0 else Vector3.ZERO, dt, 4.0)
			p.pos.y = _floor_y(layers[p.layer], p.pos)
		"board":
			if p.pi >= p.path.size():
				p.state = "gone"; p.t = rng.randf_range(10.0, 22.0); p.node.visible = false; return
			var tgt: Vector3 = p.path[p.pi]
			var v: Vector3 = tgt - p.pos
			if v.length() < 0.2: p.pi += 1; return
			p.pos += v.normalized() * minf(v.length(), 2.4 * dt)
			_face(p, v, dt, 8.0)
	p.node.position = p.pos
	p.node.rotation.y = p.yaw

func _follow(p: Dictionary, dt: float) -> void:
	if p.pi >= p.path.size():
		if p.role == "evac" and p.slot >= 0 and p.flee_from == Vector3.ZERO:
			p.state = "queue"; p.t = rng.randf_range(0.5, 2.0)
			if p.luggage: p.luggage.visible = false
			_play(p, "idle")
			return
		var acts := ["look", "look", "shout", "hop", "wave", "cower", "idle"]
		if p.role == "evac": acts = ["wave", "wave", "shout", "hop", "look"]
		if calm: acts = ["hop", "wave", "hop", "idle"]
		_react(p, acts.pick_random(), rng.randf_range(1.2, 3.5))
		return
	var tgt: Vector3 = p.path[p.pi]
	var v: Vector3 = tgt - p.pos; v.y = 0
	if v.length() < 0.45:
		p.pi += 1; return
	var step: Vector3 = v.normalized() * p.speed * dt
	var np: Vector3 = p.pos + step
	var ly: Dictionary = layers[p.layer]
	if _walk_at(ly, _cell(ly, np)) == 0:
		# something moved in the way (or the path cut a corner): ask for a new one
		p.want_path = true; return
	p.pos = np
	p.pos.y = lerpf(p.pos.y, _floor_y(ly, np), 1.0 - exp(-12.0 * dt))
	_face(p, v, dt, 10.0)

func _face(p: Dictionary, dir: Vector3, dt: float, rate: float) -> void:
	if dir.length_squared() < 0.01: return
	p.yaw = lerp_angle(p.yaw, atan2(dir.x, dir.z), 1.0 - exp(-rate * dt))

## keep people out of each other and out of Vesk's way
func _separate(pp: Vector3) -> void:
	var n := people.size()
	for i in n:
		var a: Dictionary = people[i]
		if not a.active or a.state == "gone" or a.state == "board": continue
		var ly: Dictionary = layers[a.layer]
		var push := Vector3.ZERO
		var dp: Vector3 = a.pos - pp; dp.y = 0
		var pd := dp.length()
		if pd < 1.1 and absf(a.pos.y - pp.y) < 2.0:
			push += (dp / maxf(pd, 0.05)) * (1.1 - pd) * 0.6
			if a.state == "react" or a.state == "queue":
				if a.anim != "cower" and a.anim != "hop": _play(a, "hop")
		for j in range(i + 1, n):
			var b: Dictionary = people[j]
			if not b.active or b.layer != a.layer or b.state == "gone" or b.state == "board": continue
			var dv: Vector3 = a.pos - b.pos; dv.y = 0
			var dd := dv.length()
			if dd < 0.75 and dd > 0.001:
				var k := dv / dd * (0.75 - dd) * 0.5
				if a.state != "queue": push += k
				if b.state != "queue":
					var nb: Vector3 = b.pos - k
					if _walk_at(ly, _cell(ly, nb)) != 0: b.pos = nb
		if push != Vector3.ZERO:
			var na: Vector3 = a.pos + push
			if _walk_at(ly, _cell(ly, na)) != 0: a.pos = na

# ------------------------------------------------------------------ the queue and boarding (evac.gd)
func _leave_queue(p: Dictionary) -> void:
	if p.slot >= 0 and p.slot < queue.size() and is_same(queue[p.slot], p): queue[p.slot] = null
	p.slot = -1
	if p.luggage: p.luggage.visible = false

## evac.gd: open or close the gangway. `path` runs from the gangway foot to inside the hatch.
func set_boarding(open: bool, path: Array) -> void:
	boarding = open; board_path = path; board_t = 0.8

func _boarding(dt: float) -> void:
	# shuffle forward: anyone in a later slot moves up into a free earlier one
	for i in queue.size():
		if queue[i] != null: continue
		for j in range(i + 1, queue.size()):
			var q = queue[j]
			if q != null and q.state == "queue":
				queue[j] = null; queue[i] = q; q.slot = i; break
	if not boarding or board_path.is_empty() or queue.is_empty(): return
	board_t -= dt
	if board_t > 0.0: return
	var p = queue[0]
	if p == null or p.state != "queue" or p.pos.distance_to(queue_slots[0]) > 1.0: return
	board_t = rng.randf_range(0.7, 1.2)
	queue[0] = null; p.slot = -1
	p.state = "board"; p.path = PackedVector3Array(board_path); p.pi = 0
	if p.luggage: p.luggage.visible = true
	_play(p, "carry", 0.2, 1.3)

func _respawn(p: Dictionary, pp: Vector3) -> void:
	# come back as a new evacuee somewhere in a source area, out of Vesk's sight
	for k in 6:
		if sources.is_empty(): break
		var s: Array = sources[rng.randi() % sources.size()]
		var ly: Dictionary = layers[s[0]]
		var c := _random_cell(ly, s[1], 12)
		if c.x < 0: continue
		var pos := _world(ly, c)
		if pos.distance_to(pp) < 26.0: continue
		p.layer = s[0]; p.pos = pos; p.flee_from = Vector3.ZERO
		p.node.position = p.pos; p.node.visible = true
		p.home = s[1]
		_go(p, false)
		return
	p.t = 3.0

# ------------------------------------------------------------------ voices
func _barks(dt: float, pp: Vector3) -> void:
	bark_t -= dt
	if bark_t > 0.0 or bark_player.playing: return
	if Game.input_locked: return
	# a story line is playing: stay quiet under it
	if Snd.get("voice_player") and Snd.voice_player and Snd.voice_player.playing:
		bark_t = 1.5; return
	var cands: Array = []
	for p in people:
		if not p.active or p.state == "gone": continue
		var d: float = p.pos.distance_to(pp)
		if d > 3.0 and d < 16.0: cands.append(p)
	bark_t = rng.randf_range(3.0, 6.5)
	if cands.is_empty(): return
	var p: Dictionary = cands.pick_random()
	var who: String = BARK[p.species]
	var close: bool = p.pos.distance_to(pp) < 6.0
	var n := rng.randi_range(1, 4)
	# lines 5 are about Vesk: only when he's close, and each one once in a while
	if close and not special_done.has(who): n = 5; special_done[who] = true
	elif n == 1 and p.role == "evac": n = 2
	var id := "panic_%s_%d" % [who, n]
	if heard.get(id, -100.0) > t - 40.0: return
	heard[id] = t
	_say(p, id)

func _scream(p: Dictionary) -> void:
	if bark_player.playing: return
	_say(p, "panic_%s_6" % BARK[p.species])

func _say(p: Dictionary, id: String) -> void:
	var path := "res://audio/voice/%s.ogg" % id
	if not ResourceLoader.exists(path): return
	bark_player.stream = load(path)
	bark_player.pitch_scale = rng.randf_range(0.96, 1.05)
	bark_player.global_position = p.pos + Vector3(0, 1.5, 0)
	bark_player.play()
	# subtitles for the full lines (not the screams), when they're close enough to hear the words
	if not id.ends_with("_6") and p.pos.distance_to(Game.player.global_position if Game.player else p.pos) < 12.0:
		var who: String = id.split("_")[1]
		Snd.line_started.emit(id, WHO.get(who, "citizen"), line_text(id))
	if p.state == "react" or p.state == "queue": _play(p, "shout" if rng.randf() < 0.5 else "wave")

# ------------------------------------------------------------------ debug
func _dump_map(path: String) -> void:
	var r := Rect2()
	for ly in layers: r = ly.rect if r.size == Vector2.ZERO else r.merge(ly.rect)
	var s := 4
	var img := Image.create(int(r.size.x) * s, int(r.size.y) * s, false, Image.FORMAT_RGB8)
	img.fill(Color(0.1, 0.1, 0.14))
	var cols := [Color(0.85, 0.85, 0.8), Color(0.5, 0.8, 1.0), Color(0.6, 1.0, 0.6), Color(1.0, 0.8, 0.5), Color(1.0, 0.6, 0.9), Color(0.8, 0.7, 1.0)]
	for li in layers.size():
		var ly: Dictionary = layers[li]
		for i in ly.w * ly.h:
			if ly.walk[i] == 0: continue
			var x: int = int((ly.rect.position.x - r.position.x) / CELL) + i % int(ly.w)
			var z: int = int((ly.rect.position.y - r.position.y) / CELL) + i / int(ly.w)
			var c: Color = cols[li % cols.size()] * (1.0 if ly.walk[i] == 1 else 0.6)
			img.fill_rect(Rect2i(x * s, z * s, s, s), c)
	for z in zones:
		var zr: Rect2 = z.rect
		_rect_outline(img, Rect2i(int((zr.position.x - r.position.x) * s), int((zr.position.y - r.position.y) * s), int(zr.size.x * s), int(zr.size.y * s)), Color(1, 0.3, 0.2))
	for q in queue_slots:
		img.fill_rect(Rect2i(int((q.x - r.position.x) * s) - 2, int((q.z - r.position.y) * s) - 2, 4, 4), Color(1, 0, 1))
	for p in people:
		img.fill_rect(Rect2i(int((p.pos.x - r.position.x) * s) - 1, int((p.pos.z - r.position.y) * s) - 1, 3, 3), Color(1, 0.1, 0.1))
	# grid lines every 10 m, labelled by position in the console
	for gx in range(int(ceil(r.position.x / 10.0)) * 10, int(r.end.x), 10):
		for zz in range(0, img.get_height(), 3): img.set_pixel(int((gx - r.position.x) * s), zz, Color(0.3, 0.3, 0.4) if gx != 0 else Color(0.9, 0.2, 0.2))
	for gz in range(int(ceil(r.position.y / 10.0)) * 10, int(r.end.y), 10):
		for xx in range(0, img.get_width(), 3): img.set_pixel(xx, int((gz - r.position.y) * s), Color(0.3, 0.3, 0.4) if gz != 0 else Color(0.9, 0.2, 0.2))
	img.save_png(path)
	print("[panic] map ", path, " origin ", r.position, " size ", r.size, " px/m ", s, " people ", people.size())
	get_tree().quit()

func _rect_outline(img: Image, r: Rect2i, c: Color) -> void:
	img.fill_rect(Rect2i(r.position.x, r.position.y, r.size.x, 1), c)
	img.fill_rect(Rect2i(r.position.x, r.end.y - 1, r.size.x, 1), c)
	img.fill_rect(Rect2i(r.position.x, r.position.y, 1, r.size.y), c)
	img.fill_rect(Rect2i(r.end.x - 1, r.position.y, 1, r.size.y), c)
