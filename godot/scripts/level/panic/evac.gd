extends Node3D
## The evacuation shuttle at Pier A's south edge. Built by panic.gd.
## A shuttle (models/panic/shuttle.glb) comes down out of the sky, holds beside the railing, swings its bridge
## over the rail onto the boarding steps and loads the queue (crowd.gd walks them up and in), then pulls the
## bridge in, roars off and climbs away; the next one is already on its way. People queue along the south
## railing with their luggage and the rest crowd round waving for a seat.
## The boarding steps are solid, with an invisible wall at the top so Vesk can't step out onto the bridge.

const M := preload("res://scripts/mats.gd")

const S := preload("res://scripts/level/layout/spread.gd")
# original Pier A positions, moved with the docks by the Spread pass
var FOOT := S.at(Vector3(44.0, 0.0, 41.3))     # bottom of the boarding steps (queue slot 0)
var TOP := S.at(Vector3(44.0, 1.45, 43.5))     # top of the steps, over the railing
var DOCK := S.at(Vector3(44.0, 0.4, 50.5))     # where the shuttle holds (bottom of its hull)
var HATCH := S.at(Vector3(44.0, 1.45, 47.6))   # the far end of the bridge, at the shuttle's door
const LENGTH := 15.0

var L: Node3D
var crowd: Node3D
var traffic: Node3D
var ship: Node3D
var glows: Array = []
var bridge: Node3D
var state := "away"
var t := 4.0
var p_from := Vector3.ZERO
var p_to := Vector3.ZERO
var puff_t := 0.0
var engine: AudioStreamPlayer3D
var oneshot: AudioStreamPlayer3D
var rng := RandomNumberGenerator.new()

func setup(level: Node3D, c: Node3D) -> void:
	L = level; crowd = c
	rng.seed = 99
	_steps()
	if crowd:
		# the queue: from the steps north up the pier, clear of the turbine switch and the forklift
		crowd.queue_slots.append(FOOT)
		for i in 11:
			crowd.queue_slots.append(Vector3(FOOT.x - 2.1 + (0.3 if i % 2 else -0.15), 0.0, 40.2 - i * 0.92))
		crowd.crowd_spot = S.rect_at(Rect2(34, 29, 7, 10), "docks")
		crowd.board_path = []

func _ready() -> void:
	_ship()
	engine = AudioStreamPlayer3D.new(); engine.bus = "World"; engine.unit_size = 10.0; engine.max_distance = 90.0; engine.volume_db = -6.0
	var s: AudioStream = _stream("panic_ship_idle_loop")
	if s is AudioStreamOggVorbis: s = s.duplicate(); (s as AudioStreamOggVorbis).loop = true
	engine.stream = s
	ship.add_child(engine)
	oneshot = AudioStreamPlayer3D.new(); oneshot.bus = "World"; oneshot.unit_size = 16.0; oneshot.max_distance = 220.0
	add_child(oneshot)
	ship.visible = false
	_bridge_out(0.0)
	if OS.get_cmdline_user_args().has("--panic-docked"):
		# debug: start with the shuttle at the steps, boarding (screenshots)
		state = "dock"; t = 0.01; ship.visible = true; ship.position = DOCK; engine.play()

func _stream(n: String) -> AudioStream:
	var p := "res://audio/sfx/%s.ogg" % n
	return load(p) if ResourceLoader.exists(p) else null

func _say(n: String, pos: Vector3, db: float) -> void:
	var s := _stream(n)
	if s == null: return
	oneshot.stream = s; oneshot.volume_db = db; oneshot.global_position = pos; oneshot.play()

## solid boarding steps against the railing, with a sign
func _steps() -> void:
	var mat := M.deck(Color(0.86, 0.8, 0.7))
	var n := 4
	for i in n:
		var h := TOP.y * (i + 1) / n
		var z0 := FOOT.z + (TOP.z - FOOT.z) * i / n + 0.3
		var depth := TOP.z - z0 + 0.2
		L.box(Vector3(FOOT.x, h / 2, z0 + depth / 2), Vector3(2.2, h, depth), mat)
	# side rails and a wall Vesk can't see at the top (the bridge beyond is only for passengers)
	L.box(Vector3(FOOT.x - 1.15, TOP.y + 0.5, (FOOT.z + TOP.z) / 2 + 0.4), Vector3(0.08, 1.0, 2.4), L.mat_brass, false)
	L.box(Vector3(FOOT.x + 1.15, TOP.y + 0.5, (FOOT.z + TOP.z) / 2 + 0.4), Vector3(0.08, 1.0, 2.4), L.mat_brass, false)
	var sb := StaticBody3D.new(); var cs := CollisionShape3D.new(); var bs := BoxShape3D.new()
	bs.size = Vector3(3.0, 4.0, 0.3); cs.shape = bs; sb.add_child(cs); sb.position = Vector3(FOOT.x, TOP.y + 2.0, TOP.z + 0.25)
	L.add_child(sb)
	var sign := Label3D.new(); sign.text = "OFF-WORLD\nBOARDING"; sign.font_size = 96; sign.pixel_size = 0.006
	sign.modulate = Color(1.0, 0.85, 0.35); sign.outline_size = 18; sign.outline_modulate = Color(0.1, 0.06, 0.04)
	sign.position = Vector3(FOOT.x - 2.6, 3.4, 43.6); sign.rotation.y = PI   # reads from the pier side
	L.add_child(sign)
	L.cyl(Vector3(FOOT.x - 2.6, 1.4, 43.7), 0.06, 0.08, 2.8, L.mat_dark, 8)
	var lamp := M.glow(Color(1.0, 0.4, 0.2), 5.0)
	var sm := SphereMesh.new(); sm.radius = 0.16; sm.height = 0.32
	var mi := MeshInstance3D.new(); mi.mesh = sm; mi.material_override = lamp; mi.position = Vector3(FOOT.x - 2.6, 4.05, 43.7); L.add_child(mi)
	set_meta("lamp", lamp)

func _ship() -> void:
	ship = Node3D.new(); ship.name = "Shuttle"; add_child(ship)
	var p := "res://models/panic/shuttle.glb"
	if ResourceLoader.exists(p):
		var m: Node3D = (load(p) as PackedScene).instantiate()
		ship.add_child(m)
		var ab := _aabb(m)
		var long_x := ab.size.x >= ab.size.z
		var s := LENGTH / maxf(ab.size.x if long_x else ab.size.z, 0.01)
		m.scale = Vector3.ONE * s
		m.position = Vector3(-ab.get_center().x * s, -ab.position.y * s, -ab.get_center().z * s)
		if not long_x:
			m.rotation.y = PI / 2; m.position = m.position.rotated(Vector3.UP, PI / 2)
		set_meta("height", ab.size.y * s)
	var glow := M.glow(Color(1.0, 0.6, 0.25), 9.0)
	for sx in [-1.0, 1.0]:
		var gs := SphereMesh.new(); gs.radius = 0.9; gs.height = 1.8
		var g := MeshInstance3D.new(); g.mesh = gs; g.material_override = glow; g.position = Vector3(sx * LENGTH * 0.25, -0.3, 0)
		ship.add_child(g); glows.append(g)
	# the bridge: a deck with rails, slid out from the ship toward the pier
	bridge = Node3D.new(); add_child(bridge)
	var span := HATCH.z - TOP.z + 0.6
	var deck := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = Vector3(1.8, 0.18, span)
	deck.mesh = bm; deck.material_override = M.deck(Color(0.78, 0.74, 0.7)); deck.position = Vector3(0, -0.09, -span / 2)
	bridge.add_child(deck)
	for sx in [-0.9, 0.9]:
		var r := MeshInstance3D.new(); var rm := BoxMesh.new(); rm.size = Vector3(0.06, 0.06, span)
		r.mesh = rm; r.material_override = L.mat_brass; r.position = Vector3(sx, 0.9, -span / 2); bridge.add_child(r)
		for k in 4:
			var post := MeshInstance3D.new(); var pm := BoxMesh.new(); pm.size = Vector3(0.05, 0.9, 0.05)
			post.mesh = pm; post.material_override = L.mat_brass; post.position = Vector3(sx, 0.45, -span * (k + 0.5) / 4); bridge.add_child(post)
	bridge.position = HATCH + Vector3(0, 0, 0.6)

func _aabb(n: Node) -> AABB:
	var out := AABB(); var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null: continue
		var ab: AABB = m.mesh.get_aabb()
		var xf := Transform3D.IDENTITY; var c: Node = m
		while c != n and c is Node3D:
			xf = (c as Node3D).transform * xf; c = c.get_parent()
		ab = xf * ab
		out = ab if first else out.merge(ab); first = false
	return out

## 0 = pulled in (hidden inside the ship), 1 = resting on the steps
func _bridge_out(u: float) -> void:
	bridge.visible = u > 0.02
	bridge.scale = Vector3(1, 1, maxf(u, 0.02))

func _process(dt: float) -> void:
	if not is_visible_in_tree(): return
	dt = minf(dt, 0.1)   # a long hitch (loading, shader compiles) must not skip the whole visit
	t -= dt
	var lamp: StandardMaterial3D = get_meta("lamp")
	match state:
		"away":
			if t <= 0.0:
				state = "arrive"; t = 8.0
				p_from = DOCK + Vector3(rng.randf_range(-60, 60), 70, 90); p_to = DOCK
				ship.visible = true; ship.position = p_from
				engine.play()
		"arrive":
			var u := 1.0 - t / 8.0
			var e := 1.0 - pow(1.0 - clampf(u, 0, 1), 3.0)
			ship.position = p_from.lerp(p_to, e) + Vector3(0, sin(u * PI) * 6.0, 0)
			ship.rotation.y = lerpf(0.4, 0.0, e)
			ship.rotation.z = sin(u * TAU) * 0.08 * (1.0 - e)
			if t <= 0.0:
				state = "dock"; t = 1.4
				_say("panic_shuttle_horn", DOCK, -2.0)
		"dock":
			ship.position = DOCK + Vector3(0, sin(Time.get_ticks_msec() * 0.0015) * 0.12, 0)
			_bridge_out(1.0 - t / 1.4)
			if t <= 0.0:
				_bridge_out(1.0)
				state = "board"; t = rng.randf_range(16.0, 22.0)
				if crowd: crowd.set_boarding(true, [FOOT, Vector3(FOOT.x, 0.5, FOOT.z + 0.9), TOP, HATCH, HATCH + Vector3(0, 0, 2.2)])
		"board":
			ship.position = DOCK + Vector3(0, sin(Time.get_ticks_msec() * 0.0015) * 0.12, 0)
			lamp.emission_energy_multiplier = 2.0 + 5.0 * float(int(Time.get_ticks_msec() / 400) % 2)
			if t <= 2.5 and crowd and crowd.boarding: crowd.set_boarding(false, [])
			if t <= 0.0:
				state = "close"; t = 1.2
		"close":
			_bridge_out(t / 1.2)
			if t <= 0.0:
				_bridge_out(0.0)
				state = "leave"; t = 9.0
				p_from = ship.position
				p_to = DOCK + Vector3(rng.randf_range(-120, 120), 260, 320)
				_say("panic_ship_takeoff", DOCK, 2.0)
				if Game.player and Game.player.global_position.distance_to(DOCK) < 25.0: FX.shake(0.15)
		"leave":
			var u := 1.0 - t / 9.0
			var e := u * u * u
			ship.position = p_from.lerp(p_to, e) + Vector3(0, 6.0 * minf(u * 4.0, 1.0), 0)
			ship.rotation.x = lerpf(0.0, -0.35, minf(u * 2.0, 1.0))
			_contrail(dt)
			if t <= 0.0:
				state = "away"; t = rng.randf_range(5.0, 9.0)
				ship.visible = false; ship.rotation = Vector3.ZERO
				engine.stop()
	for g in glows:
		var boost := 1.8 if state == "leave" else 1.0
		(g as Node3D).scale = Vector3.ONE * boost * (1.0 + 0.2 * sin(Time.get_ticks_msec() * 0.04))

func _contrail(dt: float) -> void:
	if traffic == null or not traffic.has_method("_puff"): return
	puff_t -= dt
	if puff_t > 0.0: return
	puff_t = 0.05
	for g in glows:
		var p: Vector3 = (g as Node3D).global_position
		traffic._puff(p, Vector3(0, -1.0, 0), Color(1, 1, 1, 0.6), 3.0, 5.0)
		if rng.randf() < 0.5: traffic._puff(p, Vector3.ZERO, Color(1.0, 0.7, 0.35, 0.9), 1.6, 0.35)
