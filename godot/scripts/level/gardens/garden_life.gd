extends Node3D
## Moving life in the Roof Gardens: butterflies, gulls circling, pollinator drones commuting between hives and
## flower beds, koi in the conservatory pond, garden bots on their rounds, floating sprocket trails you can
## collect, and the garden ambience (birdsong and water, waterfall loops). One node, one _process.

const M := preload("res://scripts/mats.gd")
const SFX := "res://audio/sfx/"

var butterflies: Array = []    # { n, wings: [MeshInstance3D, MeshInstance3D], c: Vector3, r: float, ph: float, sp: float }
var birds: Array = []          # { n, wings: [Node3D, Node3D], c: Vector3, r: float, ph: float, sp: float, h: float }
var drones: Array = []         # { n, wings: Array, route: Array[Vector3], i: int, u: float, sp: float, from: Vector3, to: Vector3, hold: float }
var koi: Array = []            # { n, tail: Node3D, c: Vector3, r: float, ph: float, sp: float }
var bots: Array = []           # { n, a: Vector3, b: Vector3, u: float, dir: int, sp: float, wait: float, bob: Node3D }
var sprockets: Array = []      # { n, pos: Vector3, ph: float }
var bobbers: Array = []        # { n, base: Vector3, amp: float, sp: float, ph: float }
var spinners: Array = []       # { n, axis: Vector3, sp: float }
var quips: Array = []          # { pos: Vector3, r: float, ids: Array, riding: bool } (each plays once)
var amb_center := Vector3.ZERO
var amb_radius := 40.0
var amb: AudioStreamPlayer
var chirp: AudioStream
var chime: AudioStream
var flock: AudioStream
var flock_t := 12.0
var t := 0.0
var rng := RandomNumberGenerator.new()

var wing_mats: Array = []
var gear_mesh: Mesh
var gear_mat: StandardMaterial3D

func _ready() -> void:
	rng.seed = 2468
	chirp = _stream("gardens_bot", false)
	chime = _stream("gardens_sprocket", false)
	flock = _stream("gardens_birds", false)
	var a := _stream("gardens_ambience", true)
	if a:
		amb = AudioStreamPlayer.new(); amb.stream = a; amb.volume_db = -60; amb.bus = "Master"; add_child(amb); amb.play()

func _stream(n: String, loop: bool) -> AudioStream:
	var p := SFX + n + ".mp3"
	if not ResourceLoader.exists(p): return null
	var s: AudioStream = load(p)
	if loop and s is AudioStreamMP3:
		s = s.duplicate(); (s as AudioStreamMP3).loop = true
	return s

## a positional looping sound (waterfall, hive hum)
func loop_at(n: String, pos: Vector3, db := 0.0, unit := 6.0, max_d := 40.0) -> void:
	var s := _stream(n, true)
	if s == null: return
	var p := AudioStreamPlayer3D.new(); p.stream = s; p.volume_db = db; p.unit_size = unit; p.max_distance = max_d
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	add_child(p); p.position = pos; p.autoplay = true
	p.play(rng.randf() * 2.0)

func _wing_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new(); m.albedo_color = c; m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.emission_enabled = true; m.emission = c; m.emission_energy_multiplier = 0.35; m.roughness = 0.5
	return m

# ------------------------------------------------------------------ spawners
func add_butterfly(c: Vector3, r := 3.0) -> void:
	if wing_mats.is_empty():
		for col in [Color(1.0, 0.55, 0.15), Color(0.4, 0.75, 1.0), Color(1.0, 0.85, 0.25), Color(0.95, 0.45, 0.85), Color(1, 1, 1)]:
			wing_mats.append(_wing_mat(col))
	var n := Node3D.new(); add_child(n)
	var mat: Material = wing_mats[rng.randi() % wing_mats.size()]
	var wings := []
	for s in [-1, 1]:
		var pivot := Node3D.new(); n.add_child(pivot)
		var q := QuadMesh.new(); q.size = Vector2(0.22, 0.18)
		var mi := MeshInstance3D.new(); mi.mesh = q; mi.material_override = mat
		mi.rotation.x = -PI / 2; mi.position = Vector3(s * 0.11, 0, 0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pivot.add_child(mi); wings.append(pivot)
	var body := MeshInstance3D.new(); var bm := CapsuleMesh.new(); bm.radius = 0.025; bm.height = 0.16; body.mesh = bm
	body.rotation.x = PI / 2; body.material_override = M.std(Color(0.15, 0.12, 0.1)); n.add_child(body)
	butterflies.append({ n = n, wings = wings, c = c, r = r, ph = rng.randf() * TAU, sp = rng.randf_range(0.35, 0.6) })

func add_bird(c: Vector3, r: float, h := 0.0) -> void:
	var n := Node3D.new(); add_child(n)
	var mat := M.std(Color(0.96, 0.96, 0.94), 0.0, 0.6)
	var dark := M.std(Color(0.3, 0.32, 0.36), 0.0, 0.6)
	var body := MeshInstance3D.new(); var cm := CapsuleMesh.new(); cm.radius = 0.16; cm.height = 0.8; body.mesh = cm
	body.rotation.x = PI / 2; body.material_override = mat; n.add_child(body)
	var beak := MeshInstance3D.new(); var bk := CylinderMesh.new(); bk.top_radius = 0.0; bk.bottom_radius = 0.06; bk.height = 0.2
	beak.mesh = bk; beak.rotation.x = -PI / 2; beak.position = Vector3(0, 0.02, -0.48); beak.material_override = M.std(Color(1, 0.7, 0.2)); n.add_child(beak)
	var wings := []
	for s in [-1, 1]:
		var pivot := Node3D.new(); pivot.position = Vector3(s * 0.12, 0.05, -0.05); n.add_child(pivot)
		var bm := BoxMesh.new(); bm.size = Vector3(0.75, 0.04, 0.3)
		var w := MeshInstance3D.new(); w.mesh = bm; w.material_override = mat; w.position = Vector3(s * 0.38, 0, 0); pivot.add_child(w)
		var tip := MeshInstance3D.new(); var tb := BoxMesh.new(); tb.size = Vector3(0.3, 0.045, 0.22); tip.mesh = tb
		tip.material_override = dark; tip.position = Vector3(s * 0.85, 0, 0.03); pivot.add_child(tip)
		wings.append(pivot)
	birds.append({ n = n, wings = wings, c = c, r = r, ph = rng.randf() * TAU, sp = rng.randf_range(0.18, 0.3) * (1 if rng.randf() < 0.5 else -1), h = h })

## a pollinator drone shuttling along route (a loop of points)
func add_drone(route: Array, buzz := false) -> void:
	var n := Node3D.new(); add_child(n)
	var body := MeshInstance3D.new(); var sm := SphereMesh.new(); sm.radius = 0.22; sm.height = 0.4
	body.mesh = sm; body.material_override = M.paint(Color(1.0, 0.78, 0.2)); body.scale = Vector3(1, 1, 1.25); n.add_child(body)
	for z in [-0.06, 0.1]:
		var tm := TorusMesh.new(); tm.inner_radius = 0.17; tm.outer_radius = 0.23; tm.rings = 12; tm.ring_segments = 6
		var band := MeshInstance3D.new(); band.mesh = tm; band.material_override = M.std(Color(0.12, 0.12, 0.14), 0.5, 0.4)
		band.rotation.x = PI / 2; band.position.z = z; n.add_child(band)
	var eye := MeshInstance3D.new(); var es := SphereMesh.new(); es.radius = 0.08; es.height = 0.16; eye.mesh = es
	eye.material_override = M.glow(Color(0.3, 0.95, 1.0), 4.0); eye.position = Vector3(0, 0.04, -0.24); n.add_child(eye)
	var wings := []
	var wm := M.glass(Color(0.85, 0.95, 1.0))
	for s in [-1, 1]:
		var pivot := Node3D.new(); pivot.position = Vector3(s * 0.12, 0.16, 0); n.add_child(pivot)
		var q := QuadMesh.new(); q.size = Vector2(0.34, 0.16)
		var w := MeshInstance3D.new(); w.mesh = q; w.material_override = wm; w.rotation.x = -PI / 2; w.position = Vector3(s * 0.17, 0, 0)
		w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pivot.add_child(w); wings.append(pivot)
	# a tiny pollen basket glow underneath
	var pb := MeshInstance3D.new(); var ps := SphereMesh.new(); ps.radius = 0.07; ps.height = 0.14; pb.mesh = ps
	pb.material_override = M.glow(Color(1.0, 0.7, 0.2), 2.5); pb.position = Vector3(0, -0.2, 0); n.add_child(pb)
	n.position = route[0]
	if buzz:
		var s := _stream("gardens_drone", true)
		if s:
			var p := AudioStreamPlayer3D.new(); p.stream = s; p.volume_db = -8; p.unit_size = 2.5; p.max_distance = 18
			n.add_child(p); p.autoplay = true; p.play(rng.randf())
	drones.append({ n = n, wings = wings, route = route, i = 0, u = 1.0, sp = rng.randf_range(0.25, 0.4), from = route[0], to = route[0], hold = rng.randf() * 2.0 })

func add_koi(c: Vector3, r: float) -> void:
	var n := Node3D.new(); add_child(n)
	var cols := [Color(1.0, 0.45, 0.12), Color(1, 1, 1), Color(1.0, 0.75, 0.2)]
	var col: Color = cols[rng.randi() % cols.size()]
	var body := MeshInstance3D.new(); var sm := SphereMesh.new(); sm.radius = 0.12; sm.height = 0.24; body.mesh = sm
	body.scale = Vector3(0.8, 0.6, 2.4); body.material_override = M.std(col, 0.1, 0.35); n.add_child(body)
	var spot := MeshInstance3D.new(); var ss := SphereMesh.new(); ss.radius = 0.07; ss.height = 0.14; spot.mesh = ss
	spot.material_override = M.std(Color(1.0, 0.3, 0.1) if col == Color(1, 1, 1) else Color(1, 1, 1), 0.1, 0.4)
	spot.position = Vector3(0, 0.05, -0.05); spot.scale = Vector3(1, 0.5, 1.4); n.add_child(spot)
	var tail := Node3D.new(); tail.position = Vector3(0, 0, 0.28); n.add_child(tail)
	var q := QuadMesh.new(); q.size = Vector2(0.22, 0.2)
	var tm := MeshInstance3D.new(); tm.mesh = q; tm.rotation.x = -PI / 2; tm.position = Vector3(0, 0, 0.09)
	var fm := M.std(col, 0.0, 0.5); fm.cull_mode = BaseMaterial3D.CULL_DISABLED; tm.material_override = fm
	tail.add_child(tm)
	koi.append({ n = n, tail = tail, c = c, r = r, ph = rng.randf() * TAU, sp = rng.randf_range(0.3, 0.55) * (1 if rng.randf() < 0.6 else -1) })

func add_bot(node: Node3D, a: Vector3, b: Vector3) -> void:
	if node == null: return
	var inner: Node3D = node.get_child(0) if node.get_child_count() > 0 else node
	bots.append({ n = node, a = a, b = b, u = rng.randf(), dir = 1, sp = 0.6 / maxf(a.distance_to(b), 0.5), wait = 0.0, bob = inner, by = inner.position.y })

func add_sprocket(pos: Vector3) -> void:
	if gear_mesh == null:
		var cm := CylinderMesh.new(); cm.top_radius = 0.26; cm.bottom_radius = 0.26; cm.height = 0.08; cm.radial_segments = 10; cm.rings = 1
		gear_mesh = cm
		gear_mat = M.std(Color(1.0, 0.78, 0.3), 1.0, 0.2); gear_mat.emission_enabled = true
		gear_mat.emission = Color(1.0, 0.6, 0.15); gear_mat.emission_energy_multiplier = 1.2
	var n := Node3D.new(); add_child(n); n.position = pos
	var g := MeshInstance3D.new(); g.mesh = gear_mesh; g.material_override = gear_mat; g.rotation.x = PI / 2; n.add_child(g)
	for k in 8:
		var tooth := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = Vector3(0.1, 0.1, 0.08); tooth.mesh = bm
		tooth.material_override = gear_mat; var a := k * TAU / 8
		tooth.position = Vector3(cos(a) * 0.3, sin(a) * 0.3, 0); tooth.rotation.z = a; n.add_child(tooth)
	var hole := MeshInstance3D.new(); var hm := CylinderMesh.new(); hm.top_radius = 0.09; hm.bottom_radius = 0.09; hm.height = 0.1
	hole.mesh = hm; hole.material_override = M.std(Color(0.25, 0.2, 0.15)); hole.rotation.x = PI / 2; n.add_child(hole)
	sprockets.append({ n = n, pos = pos, ph = rng.randf() * TAU })

## a sprocket trail along a straight line (count gears from a to b)
func sprocket_line(a: Vector3, b: Vector3, count: int) -> void:
	for i in count:
		add_sprocket(a.lerp(b, (i + 0.5) / count))

func add_bobber(n: Node3D, amp := 0.15, sp := 1.0) -> void:
	if n: bobbers.append({ n = n, base = n.position, amp = amp, sp = sp, ph = rng.randf() * TAU })

## voice lines (ids in audio/voice/script.json) the first time Vesk comes within r of pos
func add_quip(pos: Vector3, r: float, ids: Array, riding := false) -> void:
	quips.append({ pos = pos, r = r, ids = ids, riding = riding })

func add_spinner(n: Node3D, axis := Vector3.UP, sp := 1.0) -> void:
	if n: spinners.append({ n = n, axis = axis, sp = sp })

# ------------------------------------------------------------------ update
func _process(dt: float) -> void:
	t += dt
	var cam := get_viewport().get_camera_3d()
	var eye := to_local(cam.global_position) if cam else Vector3.ZERO   # in this node's (the area's original) space
	var near := eye.distance_to(amb_center) < amb_radius + 50.0
	for b in butterflies:
		if not near: break
		var ph: float = b.ph + t * b.sp
		var p: Vector3 = b.c + Vector3(sin(ph) * b.r, 0.6 + sin(ph * 2.3) * 0.5 + absf(sin(t * 3.0 + b.ph)) * 0.2, sin(ph * 1.7) * cos(ph * 0.6) * b.r)
		var d: Vector3 = p - b.n.position
		b.n.position = p
		if d.length() > 0.001: b.n.rotation.y = atan2(-d.x, -d.z)
		var f := sin(t * 18.0 + b.ph) * 0.9
		b.wings[0].rotation.z = f; b.wings[1].rotation.z = -f
	for b in birds:
		var ph: float = b.ph + t * b.sp
		var p: Vector3 = b.c + Vector3(cos(ph) * b.r, sin(ph * 2.0) * 1.2 + b.h, sin(ph) * b.r)
		var d: Vector3 = p - b.n.position
		b.n.position = p
		if d.length() > 0.001:
			b.n.rotation.y = atan2(-d.x, -d.z)
			b.n.rotation.z = -signf(b.sp) * 0.3
		var flap := sin(t * 5.0 + b.ph)
		var glide := 0.5 + 0.5 * sin(t * 0.6 + b.ph)
		var w := flap * 0.6 * (1.0 - glide * 0.8)
		b.wings[0].rotation.z = w; b.wings[1].rotation.z = -w
	for dr in drones:
		if dr.u >= 1.0:
			dr.hold -= dt
			dr.n.position = dr.to + Vector3(0, sin(t * 3.0) * 0.08, 0)
			if dr.hold <= 0.0:
				dr.i = (dr.i + 1) % dr.route.size()
				dr.from = dr.n.position; dr.to = dr.route[dr.i]; dr.u = 0.0
				dr.sp = 1.6 / maxf(dr.from.distance_to(dr.to), 0.5)
				dr.hold = rng.randf_range(1.0, 3.0)
		else:
			dr.u = minf(1.0, dr.u + dt * dr.sp)
			var e: float = dr.u * dr.u * (3.0 - 2.0 * dr.u)
			var p: Vector3 = dr.from.lerp(dr.to, e) + Vector3(0, sin(e * PI) * 1.2, 0)
			var d: Vector3 = dr.to - dr.from
			dr.n.position = p
			if Vector2(d.x, d.z).length() > 0.01: dr.n.rotation.y = lerp_angle(dr.n.rotation.y, atan2(-d.x, -d.z), 1.0 - exp(-6.0 * dt))
		if near:
			var f := sin(t * 40.0) * 0.5
			dr.wings[0].rotation.z = f; dr.wings[1].rotation.z = -f
	if near:
		for k in koi:
			var ph: float = k.ph + t * k.sp
			var rr: float = k.r * (0.75 + 0.25 * sin(ph * 0.7))
			var p: Vector3 = k.c + Vector3(cos(ph) * rr, 0, sin(ph) * rr)
			var d: Vector3 = p - k.n.position
			k.n.position = p
			if d.length() > 0.0001: k.n.rotation.y = atan2(-d.x, -d.z)
			k.tail.rotation.y = sin(t * 7.0 + k.ph) * 0.5
		for b in bots:
			if b.wait > 0.0:
				b.wait -= dt
				continue
			b.u += dt * b.sp * b.dir
			if b.u >= 1.0 or b.u <= 0.0:
				b.u = clampf(b.u, 0.0, 1.0); b.dir = -b.dir; b.wait = rng.randf_range(2.0, 4.0)
				if chirp and to_local(b.n.global_position).distance_to(eye) < 18.0: _chirp(b.n.global_position)
			var p: Vector3 = b.a.lerp(b.b, b.u)
			var d: Vector3 = (b.b - b.a) * b.dir
			b.n.position = p
			b.n.rotation.y = lerp_angle(b.n.rotation.y, atan2(d.x, d.z), 1.0 - exp(-4.0 * dt))
			b.bob.position.y = b.by + absf(sin(t * 6.0)) * 0.04
		for o in bobbers:
			o.n.position = o.base + Vector3(0, sin(t * o.sp + o.ph) * o.amp, 0)
		for s in spinners:
			s.n.rotate(s.axis, s.sp * dt)
	# sprockets: spin, and collect when Vesk touches one
	var pl: Node3D = Game.player
	var pp := to_local(pl.global_position) + Vector3(0, 0.9, 0) if pl else Vector3(0, -999, 0)
	for i in range(sprockets.size() - 1, -1, -1):
		var s: Dictionary = sprockets[i]
		s.n.rotation.y = t * 2.5 + s.ph
		s.n.position.y = s.pos.y + sin(t * 2.0 + s.ph) * 0.1
		if pp.distance_to(s.n.position) < 1.25:
			Game.add_nuts(10)
			Snd.play("nut_pickup", -6, 0.1, 0.02)
			if chime: _oneshot(chime, -10.0)
			FX.sparks(s.n.global_position, Color(1.0, 0.8, 0.35), 6, 3.0)
			s.n.queue_free(); sprockets.remove_at(i)
	if pl and not Game.input_locked and Engine.get_physics_frames() % 10 == 0:
		for i in range(quips.size() - 1, -1, -1):
			var q: Dictionary = quips[i]
			if to_local(pl.global_position).distance_to(q.pos) < q.r and (not q.riding or pl.get("riding")):
				for id in q.ids: Snd.voice(id)
				quips.remove_at(i)
	# now and then a little flock takes off from a nearby tree
	flock_t -= dt
	if flock_t <= 0.0:
		flock_t = rng.randf_range(18.0, 35.0)
		if flock and near and eye.distance_to(amb_center) < amb_radius:
			var p := AudioStreamPlayer3D.new(); p.stream = flock; p.volume_db = -8; p.unit_size = 6.0
			add_child(p); p.global_position = to_global(eye) + Vector3(rng.randf_range(-10, 10), rng.randf_range(2, 5), rng.randf_range(-10, 10))
			p.play(); p.finished.connect(p.queue_free)
	# garden ambience fades with distance from the gardens
	if amb:
		var d := eye.distance_to(amb_center)
		var want := lerpf(-6.0, -40.0, clampf((d - amb_radius * 0.5) / amb_radius, 0.0, 1.0))
		amb.volume_db = move_toward(amb.volume_db, want, dt * 20.0)

func _oneshot(s: AudioStream, db: float) -> void:
	var p := AudioStreamPlayer.new(); p.stream = s; p.volume_db = db; p.pitch_scale = randf_range(0.95, 1.1)
	add_child(p); p.play(); p.finished.connect(p.queue_free)

func _chirp(pos: Vector3) -> void:
	var p := AudioStreamPlayer3D.new(); p.stream = chirp; p.volume_db = -6; p.unit_size = 4.0; p.pitch_scale = randf_range(0.9, 1.15)
	add_child(p); p.global_position = pos; p.play(); p.finished.connect(p.queue_free)
