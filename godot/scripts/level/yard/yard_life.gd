extends Node3D
## Everything that moves in the Crane Yard: the conveyor belt, crane trolleys, the chain conveyor, welding
## sparks, the foundry ladle, spinning beacons, Grudd's loudspeaker announcements (with subtitles), the
## holding-pen release, the arena doors and the crowd, and crates dropping from the arena crane during the boss.

const K := preload("res://scripts/level/yard/yard_kit.gd")

var level: Node3D
var belt_mat: StandardMaterial3D
var trolleys: Array = []     # { node, body, cables: Array, w }
var chains: Array = []       # { hooks: Array of Node3D, a, b, u: Array }
var sliders: Array = []      # { node, a, b, period, t }
var welders: Array = []      # { p: CPUParticles3D, t: float, light }
var sparkers: Array = []     # { p, t }
var beacons: Array = []
var speakers: Array = []     # Node3D
var fans: Array = []         # { node, base: float, phase: float }
var doors: Array = []        # { gate: Node3D, id: String, open: float }
var alarms: Array = []       # work-light Node3D (head lights turn red and flash)
var searchlights: Array = [] # { node, target }
var swayers: Array = []      # { node, phase }
var patrols: Array = []      # { node, pts: Array, speed, d, total }
var loops: Array = []        # AudioStreamPlayer3D
var pen_cages: Array = []
var pen_bots: Array = []
var pen_open := false
var counter: Label3D
var arena_bridge: Node3D
var arena_trolley: Node3D
var arena_hook: Node3D
var arena_center := Vector3(0, 0, -97)
var ladle: Node3D
var pour: MeshInstance3D
var pour_sparks: CPUParticles3D

var t := 0.0
var pa_t := 25.0
var pa_order: Array = []
var pa_player: AudioStreamPlayer3D
var chime_player: AudioStreamPlayer3D
var sfx_players: Array = []
var boss_on := false
var boss_seen := false
var drop_t := 9.0
var drops: Array = []        # { node, vel, target, ring, landed, life }
var incidents := 0
var said := {}
var pen_rect := Rect2(28, -85, 24, 22)
var pen_guarded := false

func _ready() -> void:
	pa_player = AudioStreamPlayer3D.new(); pa_player.unit_size = 22.0; pa_player.max_distance = 140.0; pa_player.volume_db = 4.0
	add_child(pa_player)
	chime_player = AudioStreamPlayer3D.new(); chime_player.unit_size = 22.0; chime_player.max_distance = 140.0
	add_child(chime_player)
	for i in 4:
		var p := AudioStreamPlayer3D.new(); p.unit_size = 10.0; p.max_distance = 80.0; add_child(p); sfx_players.append(p)
	pa_order = ["yard_pa_1", "yard_pa_2", "yard_pa_3", "yard_pa_4", "yard_pa_5", "yard_pa_6"]
	pa_order.shuffle()
	if Engine.has_singleton("Game") or get_node_or_null("/root/Game"):
		var g := get_node("/root/Game")
		g.zone_cleared.connect(_on_zone_cleared)
		g.zone_entered.connect(_on_zone_entered)
		g.boss_started.connect(func(n): if n == "CRANE BOT": _boss_start())
		g.boss_defeated.connect(func(n): if n == "CRANE BOT": _boss_end())
		g.bot_killed.connect(func(_b, p, _k): _bot_killed(p))
	if OS.get_cmdline_user_args().has("--yard-selftest"): _selftest()

## Debug: `-- --yard-selftest` releases the pen, opens the arena doors and runs the boss-time crate drops.
func _selftest() -> void:
	await get_tree().create_timer(1.0).timeout
	release_pen(); print("[yard] pen released, bots ", pen_bots.size())
	if level: level.open_gate("arena_gate")
	_boss_start(); drop_t = 0.1
	await get_tree().create_timer(6.0).timeout
	print("[yard] doors ", doors.map(func(d): return snappedf(d.open, 0.01)), " drops ", drops.size(), " pa ", pa_player.playing)
	boss_on = false
	await get_tree().create_timer(1.0).timeout
	print("[yard] selftest done, drops left ", drops.size())

# ---------------------------------------------------------------- registration (called by areas/yard.gd)
func belt_material() -> StandardMaterial3D:
	if belt_mat: return belt_mat
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.13, 0.13, 0.15))
	for y in 64:
		for x in 64:
			# chevrons pointing -x (the belt runs west), plus slat seams
			var u := (x - absi(y - 32) + 64) % 32
			if u < 7 and absi(y - 32) < 22: img.set_pixel(x, y, Color(0.95, 0.66, 0.12))
			elif x % 16 == 0: img.set_pixel(x, y, Color(0.07, 0.07, 0.08))
	img.generate_mipmaps()
	belt_mat = StandardMaterial3D.new(); belt_mat.albedo_texture = ImageTexture.create_from_image(img)
	belt_mat.roughness = 0.8; belt_mat.metallic = 0.1
	belt_mat.uv1_triplanar = true; belt_mat.uv1_scale = Vector3.ONE * 0.25
	return belt_mat

func add_trolley(pos: Vector3, body: Node3D, w: float, drop: float) -> void:
	var n := K.node(self, pos, 0.0, "Trolley")
	K.bx(n, Vector3(0, -0.1, 0), Vector3(2.0, 0.8, 1.6), "dark")
	K.bx(n, Vector3(0, 0.36, 0), Vector3(2.1, 0.14, 1.7), "hazard")
	K.cy(n, Vector3(0, -0.2, 0.82), 0.22, 0.12, "glow_amber", Vector3(PI / 2, 0, 0))
	var cables := []
	for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var cb := K.cy(self, Vector3.ZERO, 0.035, 1.0, "cable")
		cables.append([cb, Vector3(c.x * w * 0.42, 0.3, c.y * w * 0.42)])
	trolleys.append({ node = n, body = body, cables = cables, base = pos })

func add_speaker(n: Node3D) -> void:
	speakers.append(n)
	var b := n.get_node_or_null("beacon")
	if b: beacons.append(b)

func add_chain(a: Vector3, b: Vector3, count: int) -> void:
	var hooks := []
	var cols := [Color(0.72, 0.32, 0.2), Color(0.22, 0.52, 0.55), Color(0.9, 0.65, 0.18), Color(0.85, 0.82, 0.72)]
	for i in count:
		var h := K.node(self, a)
		K.cy(h, Vector3(0, -0.6, 0), 0.03, 1.2, "cable")
		K.bx(h, Vector3(0, -1.25, 0), Vector3(1.3, 0.12, 1.3), "dark")
		var crate := K.bx(h, Vector3(0, -1.9, 0), Vector3(1.2, 1.1, 1.2), "steel")
		crate.material_override = K.M.paint(cols[i % 4])
		hooks.append(h)
	chains.append({ hooks = hooks, a = a, b = b })

func add_slider(n: Node3D, a: Vector3, b: Vector3, period: float) -> void:
	sliders.append({ node = n, a = a, b = b, period = period })

func add_welder(arm: Node3D, tip: Vector3) -> void:
	var p := K.sparks(self, tip, Color(0.6, 0.9, 1.0), 26, 4.5)
	p.emitting = false
	var l := K.omni(self, tip, Color(0.6, 0.85, 1.0), 0.0, 6.0)
	welders.append({ p = p, t = randf() * 3.0, light = l, arm = arm, yaw = arm.rotation.y, on = false })

func add_sparks(p: CPUParticles3D, phase: float) -> void:
	sparkers.append({ p = p, t = phase + randf() * 2.0 })

func add_fan(n: Node3D) -> void:
	fans.append({ node = n, base = n.position.y, phase = randf() * TAU, yaw = n.rotation.y })

func add_doors(g: Node3D, id: String) -> void:
	if g == null: return
	var dl: Node3D = Kit.find_part(g, "door_L"); var dr: Node3D = Kit.find_part(g, "door_R")
	if dl == null or dr == null: return
	doors.append({ gate = g, id = id, l = dl, r = dr, l0 = dl.position, r0 = dr.position, open = 0.0 })
	var lock_ := Kit.find_part(g, "lock_light")
	if lock_: doors[-1].lock = lock_

func add_sway(n: Node3D) -> void:
	swayers.append({ node = n, phase = randf() * TAU, rot = n.rotation })

## A prop that drives back and forth along a list of points (background work crews).
func add_patrol(n: Node3D, pts: Array, speed := 1.6) -> void:
	if n == null: return
	var total := 0.0
	for i in pts.size() - 1: total += (pts[i + 1] - pts[i]).length()
	patrols.append({ node = n, pts = pts, speed = speed, d = randf() * total, total = total })

func add_alarm(wl: Node3D) -> void:
	alarms.append(wl)

func add_searchlight(n: Node3D, target: Vector3) -> void:
	searchlights.append({ node = n, target = target })

func add_pour(l: Node3D, p: MeshInstance3D, ps: CPUParticles3D) -> void:
	ladle = l; pour = p; pour_sparks = ps

func add_loop(sfx: String, pos: Vector3, db: float) -> void:
	var path := "res://audio/sfx/%s.mp3" % sfx
	if not ResourceLoader.exists(path): return
	var s: AudioStream = load(path)
	if s is AudioStreamMP3: s = s.duplicate(); s.loop = true
	var p := AudioStreamPlayer3D.new(); p.stream = s; p.volume_db = db; p.unit_size = 6.0; p.max_distance = 40.0
	p.position = pos; p.autoplay = true
	add_child(p); loops.append(p)

# ---------------------------------------------------------------- sound helpers
func _sfx(n: String, pos: Vector3, db := 0.0) -> void:
	var path := "res://audio/sfx/%s.mp3" % n
	if not ResourceLoader.exists(path): return
	for p in sfx_players:
		if not p.playing:
			p.stream = load(path); p.global_position = pos; p.volume_db = db; p.pitch_scale = randf_range(0.94, 1.06); p.play(); return

func _player() -> Node3D:
	var g := get_node_or_null("/root/Game")
	return g.player if g and g.player and is_instance_valid(g.player) else null

func _in_yard(p: Vector3) -> bool:
	return p.z < -20.0 and p.x > -62.0 and p.x < 62.0 and p.z > -150.0 and absf(p.y) < 30.0

## Grudd over the loudspeakers: chime, then the line from the speaker nearest Vesk, with a subtitle.
func announce(id: String, force := false) -> bool:
	var path := "res://audio/voice/%s.mp3" % id
	if not ResourceLoader.exists(path): return false
	if pa_player.playing and not force: return false
	var snd := get_node_or_null("/root/Snd")
	if not force and snd and snd.voice_player and snd.voice_player.playing: return false
	var pl := _player()
	var at := Vector3(0, 4, -64)
	if pl:
		var best := INF
		for s in speakers:
			var d: float = s.global_position.distance_to(pl.global_position)
			if d < best: best = d; at = s.global_position + Vector3(0, 5, 0)
	pa_player.global_position = at; chime_player.global_position = at
	if ResourceLoader.exists("res://audio/sfx/yard_pa_chime.mp3"):
		chime_player.stream = load("res://audio/sfx/yard_pa_chime.mp3"); chime_player.play()
	var tw := create_tween(); tw.tween_interval(1.2)
	tw.tween_callback(func():
		pa_player.stream = load(path); pa_player.play()
		if snd: snd.line_started.emit(id, "grudd", LINES.get(id, "")))
	return true

const LINES := {
	"yard_pa_1": "Attention, workers. Morale is mandatory. Anyone caught without morale will be issued some.",
	"yard_pa_2": "Reminder: lunch break has been rescheduled to never. Thank you for your cooperation.",
	"yard_pa_3": "Employee of the month: the Crane Bot. Again. Try harder, everybody else.",
	"yard_pa_4": "Workers are reminded that the smelter is not a hot tub. I am looking at you, Unit Forty-Two.",
	"yard_pa_5": "Safety tip: if you are on fire, please be on fire more quietly.",
	"yard_pa_6": "The suggestion box has been moved. It is now inside the smelter.",
	"yard_row_1": "Container Row crews! We have an intruder. Whoever scraps him gets a five-minute break!",
	"yard_gate_1": "Stop that hero! And somebody update the sign. Days without an incident: zero. Again.",
	"yard_pen_1": "Who opened the holding pen?! That is coming out of somebody's paycheck! Nobody gets a paycheck. That is coming out of SOMEBODY!",
	"yard_arena_1": "Ladies, gentlemen, and assorted appliances! Put your clamps together for the pride of Grudd Industries... the CRANE BOT!",
}

# ---------------------------------------------------------------- story hooks
func _on_zone_entered(id: String) -> void:
	match id:
		"yard_row":
			_once("row", func(): announce("yard_row_1", true))

func _on_zone_cleared(id: String) -> void:
	match id:
		"yard_gate":
			_once("gate", func(): get_tree().create_timer(5.0).timeout.connect(func(): announce("yard_gate_1")))
		"yard_row":
			_sfx("yard_siren", Vector3(-23, 4, -96), 2.0)
			get_tree().create_timer(3.5).timeout.connect(func(): announce("yard_arena_1", true))

func _once(key: String, f: Callable) -> void:
	if said.has(key): return
	said[key] = true; f.call()

func _bot_killed(p: Vector3) -> void:
	if not _in_yard(p): return
	incidents += 1
	if counter:
		counter.text = "0"
		var tw := counter.create_tween()
		tw.tween_property(counter, "modulate", Color(1, 1, 0.4), 0.05); tw.tween_property(counter, "modulate", Color(1, 0.3, 0.2), 0.4)

func _boss_start() -> void:
	boss_on = true; boss_seen = true; drop_t = 8.0
	_sfx("yard_siren", arena_center + Vector3(0, 6, 0), 2.0)
	_sfx("yard_cheer", Vector3(28, 2, -97), 3.0)
	for f in fans: f.phase = randf() * TAU

func _boss_end() -> void:
	boss_on = false
	_sfx("yard_cheer", Vector3(28, 2, -97), 0.0)
	for f in fans: f.node.rotation.y = f.yaw + PI   # the crowd turns its back on the scrapped champion

## The holding pen lever: doors lift, the captives hop out, sprockets for everyone.
func release_pen() -> void:
	if pen_open: return
	pen_open = true
	var g := get_node_or_null("/root/Game")
	for c in pen_cages:
		var door: Node3D = c.door
		if is_instance_valid(c.collider): c.collider.queue_free()
		var tw := door.create_tween(); tw.tween_property(door, "position:y", 2.7, 0.9).set_trans(Tween.TRANS_BACK)
		c.lock.material_override = K.mat("glow_green")
		FX.sparks(c.node.global_position + Vector3(0, 1.4, 1.6), Color(0.5, 1, 0.6), 14, 5.0)
		if g and g.combat: g.combat.drop_nuts(c.node.global_position + Vector3(0, 1.0, 2.2), 6)
	var i := 0
	for b in pen_bots:
		var n: Node3D = b
		var out := n.global_position + Vector3(randf_range(-2, 2), 0, 0) + (Vector3(40, 0, -74) - n.global_position).normalized() * 3.5
		out.y = 0.0
		var tw := n.create_tween(); tw.tween_interval(0.5 + i * 0.15)
		tw.tween_property(n, "position", out + Vector3(0, 1.2, 0), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(n, "position", out, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(func(): fans.append({ node = n, base = 0.0, phase = randf() * TAU, yaw = n.rotation.y, free = true }))
		i += 1
	_sfx("yard_cheer", Vector3(40, 1.5, -80), 2.0)
	get_tree().create_timer(2.5).timeout.connect(func(): announce("yard_pen_1", true))

# ---------------------------------------------------------------- per frame
func _process(dt: float) -> void:
	t += dt
	if belt_mat: belt_mat.uv1_offset.x = fmod(belt_mat.uv1_offset.x + dt * 1.8 * 0.25, 1.0)
	for tr in trolleys:
		var b: Node3D = tr.body
		if not is_instance_valid(b): continue
		var n: Node3D = tr.node
		if tr.base.z == -66.0: n.position = Vector3(b.position.x, tr.base.y, tr.base.z)
		else: n.position = Vector3(tr.base.x, tr.base.y, b.position.z)
		for cc in tr.cables:
			var cb: MeshInstance3D = cc[0]; var off: Vector3 = cc[1]
			var top := n.position + Vector3(off.x * 0.3, -0.4, off.z * 0.3)
			var bot: Vector3 = b.position + off
			cb.look_at_from_position((top + bot) * 0.5, top, Vector3.RIGHT)
			cb.rotate_object_local(Vector3.RIGHT, PI / 2)
			cb.scale = Vector3(1, top.distance_to(bot), 1)
	for ch in chains:
		var k: int = ch.hooks.size()
		for i in k:
			var u := fmod(t / 26.0 + float(i) / k, 1.0)
			var h: Node3D = ch.hooks[i]
			h.position = ch.a.lerp(ch.b, u)
			h.rotation.z = sin(t * 1.3 + i) * 0.04
			h.visible = u > 0.02 and u < 0.98
	for s in sliders:
		var u := 0.5 - 0.5 * cos(t / s.period * TAU)
		s.node.position = s.a.lerp(s.b, u)
	for b in beacons: b.rotation.y += dt * 4.0
	for sw in swayers:
		sw.node.rotation = sw.rot + Vector3(sin(t * 1.1 + sw.phase) * 0.06, 0, sin(t * 0.7 + sw.phase) * 0.03)
	for pa in patrols:
		pa.d = fmod(pa.d + dt * pa.speed, pa.total * 2.0)
		var back: bool = pa.d >= pa.total
		var dd: float = pa.total * 2.0 - pa.d if back else pa.d
		var pts: Array = pa.pts
		for i in pts.size() - 1:
			var seg: float = (pts[i + 1] - pts[i]).length()
			if dd <= seg or i == pts.size() - 2:
				var dir: Vector3 = (pts[i + 1] - pts[i]) * (-1.0 if back else 1.0)
				pa.node.position = pts[i].lerp(pts[i + 1], clampf(dd / seg, 0.0, 1.0))
				pa.node.rotation.y = atan2(dir.x, dir.z)
				break
			dd -= seg
	for w in welders:
		w.t -= dt
		if w.t <= 0.0:
			w.on = not w.on
			w.t = randf_range(0.6, 1.6) if w.on else randf_range(1.0, 2.6)
			w.p.emitting = w.on
			if w.on and is_instance_valid(w.arm): _sfx("yard_weld", w.p.global_position, -8.0)
		w.light.light_energy = (1.5 + randf() * 2.5) if w.on else 0.0
		if is_instance_valid(w.arm): w.arm.rotation.y = w.yaw + sin(t * 0.7 + w.yaw * 3.0) * 0.25
	for s in sparkers:
		s.t -= dt
		if s.t <= 0.0:
			s.p.emitting = not s.p.emitting
			s.t = randf_range(0.4, 1.0) if s.p.emitting else randf_range(0.8, 2.8)
	if ladle:
		var tilt := clampf(sin(t * 0.35) * 1.4, 0.0, 1.0)
		ladle.rotation.z = -tilt * 0.75
		pour.visible = tilt > 0.6
		pour_sparks.emitting = pour.visible
	for f in fans:
		var n: Node3D = f.node
		if not is_instance_valid(n): continue
		var amp := 0.35 if boss_on else 0.06
		var spd := 9.0 if boss_on else 2.0
		if f.get("free", false): amp = 0.3; spd = 7.0
		n.position.y = f.base + maxf(0.0, sin(t * spd + f.phase)) * amp
		if f.get("free", false): n.rotation.y += dt * 1.5
	for d in doors:
		var want := 0.0 if level and level.gates.has(d.id) else 1.0
		if want > d.open:
			if d.open == 0.0: _sfx("yard_siren", d.gate.global_position + Vector3(0, 3, 0), 0.0)
			d.open = minf(1.0, d.open + dt * 0.4)
			d.l.position = d.l0 + Vector3(-2.6 * d.open, 0, 0)
			d.r.position = d.r0 + Vector3(2.6 * d.open, 0, 0)
			if d.has("lock"): Kit.set_glow(d.gate, "lock_light", Color(0.4, 1, 0.45), 4.0)
	var alarm_on := boss_on or doors.any(func(d): return d.open > 0.0 and d.open < 1.0)
	for a in alarms:
		var l: OmniLight3D = a.get_child(a.get_child_count() - 1) if a.get_child_count() > 0 else null
		if l is OmniLight3D:
			l.light_color = Color(1, 0.2, 0.1) if alarm_on else Color(1, 0.4, 0.25)
			l.light_energy = (2.0 + 2.0 * maxf(0.0, sin(t * 8.0))) if alarm_on else 2.0
	for sl in searchlights:
		var n: Node3D = sl.node
		var target: Vector3 = sl.target + Vector3(sin(t * 0.4) * 9.0, 0, cos(t * 0.31) * 7.0)
		if pen_open: target = sl.target + Vector3(sin(t * 3.0) * 10.0, 0, cos(t * 2.3) * 8.0)
		n.look_at(target, Vector3.UP)
		n.rotate_object_local(Vector3.UP, PI)
	if arena_bridge:
		var u := 0.5 - 0.5 * cos(t / 34.0 * TAU)
		arena_bridge.position.z = lerpf(-108.0, -86.0, u)
		arena_trolley.position.x = sin(t * TAU / 21.0) * 14.0
		arena_hook.position.y = -5.2 + sin(t * 0.8) * 0.4
	# ambient announcements while Vesk is in the yard
	var pl := _player()
	if pl and _in_yard(pl.global_position) and not boss_on:
		pa_t -= dt
		if pa_t <= 0.0:
			if announce(pa_order[0]):
				pa_order.push_back(pa_order.pop_front())
				pa_t = randf_range(38.0, 55.0)
			else:
				pa_t = 6.0
	if boss_on: _step_drops(dt, pl)
	# the pen's guards jump out the first time Vesk lands in it
	if pl and not pen_guarded and pen_rect.has_point(Vector2(pl.global_position.x, pl.global_position.z)) and absf(pl.global_position.y) < 3.0:
		pen_guarded = true
		var g := get_node_or_null("/root/Game")
		if g and g.main and g.main.has_method("spawn_bot") and not OS.get_cmdline_user_args().has("--no-bots"):
			for k in [["roller", Vector3(38, 0, -70)], ["roller", Vector3(44, 0, -76)], ["crew", Vector3(41, 0, -80)]]:
				g.main.spawn_bot(k[0], k[1], pen_rect)
			_sfx("yard_siren", Vector3(30.6, 6, -75), -2.0)
	_update_drops(dt, pl)

## During the boss fight a crate slips off the overhead crane now and then: a red ring marks where it lands.
func _step_drops(dt: float, pl: Node3D) -> void:
	drop_t -= dt
	if drop_t > 0.0 or arena_trolley == null: return
	drop_t = randf_range(9.0, 15.0)
	var src := arena_hook.global_position + Vector3(0, -1.0, 0)
	var target := Vector3(clampf(src.x, -19.0, 19.0), 0.0, clampf(src.z, -111.0, -83.0))
	if pl and randf() < 0.5:   # sometimes it slips right over Vesk
		target = Vector3(clampf(pl.global_position.x + randf_range(-2, 2), -19, 19), 0, clampf(pl.global_position.z + randf_range(-2, 2), -111, -83))
	if Vector2(target.x, target.z + 102).length() < 4.5: return   # never onto the boss
	var n := K.node(self, Vector3(target.x, 16.0, target.z))
	var c := K.bx(n, Vector3.ZERO, Vector3(1.3, 1.3, 1.3), "steel")
	c.material_override = K.M.paint(Color(0.9, 0.65, 0.18))
	K.bx(n, Vector3(0, 0, 0.66), Vector3(1.0, 0.25, 0.02), "hazard")
	var ring: Node3D = FX.warn_ring(target, 1.6, 1.6, Color(1, 0.3, 0.15)) if FX.has_method("warn_ring") else null
	drops.append({ node = n, vel = 0.0, target = target, landed = false, life = 1.4, ring = ring })

func _update_drops(dt: float, pl: Node3D) -> void:
	for d in drops.duplicate():
		var n: Node3D = d.node
		if not d.landed:
			d.life -= dt
			if d.life > 0.0: n.position.y = 16.0 - (1.4 - d.life) * 0.4   # wobbles loose
			else:
				d.vel += 30.0 * dt
				n.position.y -= d.vel * dt
				n.rotation.x += dt * 1.5
				if n.position.y <= 0.65:
					n.position.y = 0.65; n.rotation = Vector3(0, randf() * TAU, 0); d.landed = true; d.life = 5.0
					FX.shake(0.5); FX.sparks(d.target + Vector3(0, 0.2, 0), Color(1, 0.75, 0.3), 16, 7.0); FX.puff(d.target + Vector3(0, 0.3, 0))
					_sfx("yard_crate_land", d.target, 2.0)
					var g := get_node_or_null("/root/Game")
					if pl and g and g.combat and Vector2(pl.global_position.x - d.target.x, pl.global_position.z - d.target.z).length() < 1.6 and pl.global_position.y < 2.5:
						g.combat.hurt_player(1, d.target)
		else:
			d.life -= dt
			if d.life <= 0.0 or not boss_on:
				FX.explosion(n.global_position, 0.6)
				if randf() < 0.5:
					var g := get_node_or_null("/root/Game")
					if g and g.combat: g.combat.drop_nuts(n.global_position, 3)
				n.queue_free(); drops.erase(d)
