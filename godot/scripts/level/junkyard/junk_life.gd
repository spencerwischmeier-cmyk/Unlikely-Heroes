extends Node3D
## Keeps Vesk's Junkyard moving: swaying chimes, chains and hanging tools, the magnet crane swinging its
## load over the hull dock, the scrap windmill, welding sparks at the half-built hull, smoke puffs, and the
## area's own positional sounds (audio/sfx/junkyard_*.mp3: chimes, the shack radio, creaks, crane clanks).
## Everything sleeps while Vesk is far away.
## All stored positions are in this node's own space (the Junkyard's original coordinates; the Spread pass
## moves the whole area), so the player's position is converted with to_local before comparing.

const SFX := "res://audio/sfx/"

var swingers: Array = []   # { node, base: Vector3, amp: Vector3, speed, phase }
var spinners: Array = []   # { node, axis: Vector3, speed }
var cranes: Array = []     # { jib: Node3D, base, amp, speed, hook: Node3D, hook_y, last_dir }
var welders: Array = []    # { pos, t }
var creaks: Array = []     # Vector3 spots a creak may come from
var bobbers: Array = []    # { node, base_y, amp, speed, phase }
var talks: Array = []      # { rect: Rect2, y0, y1, ids: Array, done: bool }
var dodger_up := false     # Dodger only chats once he's been dug out of the scrap pile
var talk_t := 0.0
var center := Vector3(0, 0, 95)
var t := 0.0
var creak_t := 4.0
var _streams := {}
var _one_shots: Array[AudioStreamPlayer3D] = []

func _ready() -> void:
	var g := get_node_or_null("/root/Game")
	if g and g.has_signal("zone_cleared"):
		g.zone_cleared.connect(func(id: String): if id == "junk_crash" or id == "dodger_launch": dodger_up = true)
		if g.has_signal("progress_restored"):
			g.progress_restored.connect(func(ids: Array): if ids.has("dodger_launch"): dodger_up = true)

## Lines that play the first time Vesk walks into `rect` (between heights y0 and y1).
func talk(rect: Rect2, y0: float, y1: float, ids: Array) -> void:
	talks.append({ rect = rect, y0 = y0, y1 = y1, ids = ids, done = false })

func _talks(pp: Vector3, dt: float) -> void:
	talk_t -= dt
	if talk_t > 0.0: return
	talk_t = 0.25
	if not dodger_up:
		var g := get_node_or_null("/root/Game")
		var st: Node = g.story if g and g.get("story") else null
		if st and st.has_method("current_id") and not (st.current_id() in ["", "junk_crash"]): dodger_up = true
		else: return
	var snd := get_node_or_null("/root/Snd")
	if snd == null: return
	if snd.get("voice_player") and snd.voice_player.playing: return
	for tk in talks:
		if tk.done: continue
		if tk.rect.has_point(Vector2(pp.x, pp.z)) and pp.y > tk.y0 and pp.y < tk.y1:
			tk.done = true
			for id in tk.ids: snd.voice(id)
			talk_t = 6.0
			return

func swing(n: Node3D, amp: Vector3, speed: float, phase := 0.0) -> void:
	swingers.append({ node = n, base = n.rotation, amp = amp, speed = speed, phase = phase })

func spin(n: Node3D, axis: Vector3, speed: float) -> void:
	spinners.append({ node = n, axis = axis, speed = speed })

func bob(n: Node3D, amp: float, speed: float, phase := 0.0) -> void:
	bobbers.append({ node = n, base_y = n.position.y, amp = amp, speed = speed, phase = phase })

func crane(jib: Node3D, amp: float, speed: float, hook: Node3D) -> void:
	cranes.append({ jib = jib, base = jib.rotation.y, amp = amp, speed = speed, hook = hook, hook_y = hook.position.y if hook else 0.0, last_dir = 1.0 })

func welder(pos: Vector3) -> void:
	welders.append({ pos = pos, t = randf() * 3.0 })

func stream(name: String, loop := false) -> AudioStream:
	var key := name + ("_loop" if loop else "")
	if _streams.has(key): return _streams[key]
	var p := SFX + name + ".mp3"
	if not ResourceLoader.exists(p): return null
	var s: AudioStream = load(p)
	if loop:
		s = s.duplicate()
		if s is AudioStreamMP3: (s as AudioStreamMP3).loop = true
	_streams[key] = s
	return s

## A looping positional sound (chimes, radio). unit_size sets how far it carries.
func ambient(name: String, pos: Vector3, db: float, unit := 4.0, max_dist := 40.0) -> void:
	var s := stream(name, true)
	if s == null: return
	var p := AudioStreamPlayer3D.new(); p.stream = s; p.volume_db = db; p.unit_size = unit; p.max_distance = max_dist
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.position = pos; p.autoplay = true; add_child(p)

func one_shot(name: String, pos: Vector3, db: float, pitch := 1.0) -> void:
	var s := stream(name)
	if s == null: return
	var p: AudioStreamPlayer3D = null
	for q in _one_shots:
		if not q.playing: p = q; break
	if p == null:
		if _one_shots.size() >= 4: return
		p = AudioStreamPlayer3D.new(); p.unit_size = 7.0; p.max_distance = 60.0; add_child(p); _one_shots.append(p)
	p.stream = s; p.volume_db = db; p.pitch_scale = pitch; p.global_position = to_global(pos); p.play()

func _player_pos() -> Vector3:
	var g := get_node_or_null("/root/Game")
	if g and g.get("player") and is_instance_valid(g.player): return to_local(g.player.global_position)
	return center

func _process(dt: float) -> void:
	var pp := _player_pos()
	if pp.distance_to(center) > 120.0: return
	t += dt
	_talks(pp, dt)
	for s in swingers:
		var n: Node3D = s.node
		var w: float = t * s.speed + s.phase
		n.rotation = s.base + Vector3(s.amp.x * sin(w), s.amp.y * sin(w * 0.7 + 1.0), s.amp.z * sin(w * 1.3 + 2.0))
	for s in spinners:
		(s.node as Node3D).rotate_object_local(s.axis, s.speed * dt)
	for b in bobbers:
		(b.node as Node3D).position.y = b.base_y + b.amp * sin(t * b.speed + b.phase)
	for c in cranes:
		var w: float = t * c.speed
		(c.jib as Node3D).rotation.y = c.base + c.amp * sin(w)
		var dir := signf(cos(w))
		if dir != c.last_dir:
			c.last_dir = dir
			# the load settles at each end of the swing: clank, and the hook dips
			if dir < 0.0: one_shot("junkyard_clank", to_local((c.jib as Node3D).global_position), -10.0, randf_range(0.9, 1.05))
		if c.hook:
			(c.hook as Node3D).position.y = c.hook_y - 0.6 * pow(absf(sin(w)), 6.0) + 0.08 * sin(t * 2.1)
	for wd in welders:
		wd.t -= dt
		if wd.t <= 0.0:
			wd.t = randf_range(0.15, 0.4) if randf() < 0.75 else randf_range(1.8, 3.5)
			var fx := get_node_or_null("/root/FX")
			if fx and pp.distance_to(wd.pos) < 45.0: fx.sparks(to_global(wd.pos), Color(1.0, 0.75, 0.35), 5, 3.5)
	creak_t -= dt
	if creak_t <= 0.0 and creaks.size() > 0:
		creak_t = randf_range(7.0, 15.0)
		var best: Vector3 = creaks[randi() % creaks.size()]
		if pp.distance_to(best) < 35.0: one_shot("junkyard_creak", best, -9.0, randf_range(0.85, 1.1))
