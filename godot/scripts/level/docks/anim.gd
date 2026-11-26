extends Node3D
## Runs everything that moves in the Cargo Docks and the sky around them: conveyors and the crates riding
## them, swinging jib cranes, forklifts and dock bots on loops, blinking signal lights, the loading-bay doors,
## the floor buttons, loose sprockets on container tops, airship traffic lanes and bird flocks.
## Built by depot.gd / sky.gd, which fill the arrays below.

var belts: Array = []      # { body: StaticBody3D, dir: Vector3, speed: float, mat: StandardMaterial3D, scroll: float, id }
var riders: Array = []     # { body: AnimatableBody3D, a: Vector3, b: Vector3, belt: Dictionary, u: float }
var cranes: Array = []     # { node: Node3D, base: float, amp: float, w: float, ph: float, hang: Node3D, last_dir: float }
var loopers: Array = []    # { node: Node3D, pts: PackedVector3Array, len: float, speed: float, d: float, beep: bool }
var blinkers: Array = []   # { mat: StandardMaterial3D, on: float, period: float, ph: float, color: Color }
var doors: Array = []      # { node: Node3D, open_y: float, closed_y: float, trigger: AABB or null, id, open: bool }
var buttons: Array = []    # { pos: Vector3, r: float, y: float, cap: Node3D, fn: Callable, done: bool, once: bool }
var sprockets: Array = []  # { node: Node3D, pos: Vector3, taken: bool }
var lanes: Array = []      # { node: Node3D, a: Vector3, b: Vector3, speed: float, u: float, bob: float }
var flocks: Array = []     # { node: Node3D, c: Vector3, r: Vector2, h: float, w: float, ph: float }
var spinners: Array = []   # { node: Node3D, axis: Vector3, speed: float }
var bobbers: Array = []    # { node: Node3D, base: Vector3, amp: float, w: float, ph: float, roll: float }
var triggers: Array = []   # { box: AABB, fn: Callable, done: bool } one-shot (voice lines on entering a spot)
var horns: Array = []      # { player: AudioStreamPlayer3D, every: float, t: float }
var t := 0.0

func _physics_process(dt: float) -> void:
	t += dt
	var p: Node3D = Game.player if Game.player else null
	var pp: Vector3 = p.global_position if p else Vector3(1e6, 1e6, 1e6)
	for b in belts:
		b.scroll = fmod(b.scroll + b.speed * dt * 0.5, 1.0)
		if b.mat: b.mat.uv1_offset.x = -b.scroll
	for r in riders:
		var bl: Dictionary = r.belt
		var len: float = (r.b - r.a).length()
		r.u += bl.speed * dt / maxf(len, 0.1)
		if r.u > 1.0 or r.u < 0.0:
			r.u = fposmod(r.u, 1.0)
			r.body.sync_to_physics = false
			r.body.position = r.a.lerp(r.b, r.u)
			r.body.sync_to_physics = true
		else:
			r.body.position = r.a.lerp(r.b, r.u)
	for c in cranes:
		var s := sin(t * c.w + c.ph)
		c.node.rotation.y = c.base + c.amp * s
		if c.hang:
			c.hang.rotation.z = cos(t * c.w + c.ph) * 0.08
			c.hang.rotation.x = sin(t * 1.3 + c.ph) * 0.03
		var dirn := signf(cos(t * c.w + c.ph))
		if dirn != c.last_dir:
			c.last_dir = dirn
			if c.node.global_position.distance_to(pp) < 45.0: Snd3.at(self, "docks_crane_whir", c.node.global_position + Vector3(0, 10, 0), -6.0)
	for l in loopers:
		l.d = fposmod(l.d + l.speed * dt, l.len)
		var q := _along(l.pts, l.d)
		var q2 := _along(l.pts, fposmod(l.d + 0.6, l.len))
		var n: Node3D = l.node
		n.position = q
		var fw := q2 - q
		if fw.length_squared() > 1e-4:
			n.rotation.y = lerp_angle(n.rotation.y, atan2(fw.x, fw.z) + l.get("yaw_off", 0.0), 1.0 - exp(-6.0 * dt))
	for bk in blinkers:
		var ph: float = fposmod(t / bk.period + bk.ph, 1.0)
		bk.mat.emission_energy_multiplier = bk.peak if ph < bk.on else bk.low
	for tg in triggers:
		if not tg.done and (tg.box as AABB).has_point(pp):
			tg.done = true; tg.fn.call()
	for d in doors:
		if d.trigger != null and not d.open and (d.trigger as AABB).has_point(pp): open_door(d)
	for bt in buttons:
		if bt.done and bt.once: continue
		var hit: bool = absf(pp.y - bt.y) < 0.6 and Vector2(pp.x - bt.pos.x, pp.z - bt.pos.z).length() < bt.r
		if hit and not bt.down:
			bt.down = true
			if not bt.done or not bt.once:
				bt.done = true
				bt.fn.call()
			var tw := create_tween(); tw.tween_property(bt.cap, "position:y", -0.12, 0.12)
		elif not hit and bt.down:
			bt.down = false
			if not bt.once:
				var tw2 := create_tween(); tw2.tween_property(bt.cap, "position:y", 0.0, 0.2)
	for s in sprockets:
		if s.taken: continue
		var n: Node3D = s.node
		n.rotation.y = t * 2.4 + s.pos.x
		n.position.y = s.pos.y + sin(t * 2.0 + s.pos.z) * 0.12
		if pp.distance_to(s.pos + Vector3(0, -0.4, 0)) < 1.3:
			s.taken = true
			Game.add_nuts(s.value)
			Snd.play("nut_pickup", -6, 0.15, 0.03)
			var tw := create_tween().set_parallel()
			tw.tween_property(n, "position:y", n.position.y + 1.2, 0.25)
			tw.tween_property(n, "scale", Vector3.ONE * 0.05, 0.25)
			tw.chain().tween_callback(n.queue_free)
	for ln in lanes:
		ln.u = fposmod(ln.u + ln.speed * dt / ln.len, 1.0)
		var pos: Vector3 = ln.a.lerp(ln.b, ln.u)
		pos.y += sin(t * 0.4 + ln.bob) * 1.5
		ln.node.position = pos
	for f in flocks:
		var a: float = t * f.w + f.ph
		var c: Vector3 = f.c + Vector3(cos(a) * f.r.x, sin(a * 2.0) * f.h, sin(a) * f.r.y)
		var a2: float = a + 0.05
		var c2: Vector3 = f.c + Vector3(cos(a2) * f.r.x, sin(a2 * 2.0) * f.h, sin(a2) * f.r.y)
		f.node.position = c
		var fw := c2 - c
		f.node.rotation.y = atan2(fw.x, fw.z)
	for sp in spinners:
		sp.node.rotate_object_local(sp.axis, sp.speed * dt)
	for bb in bobbers:
		bb.node.position = bb.base + Vector3(0, sin(t * bb.w + bb.ph) * bb.amp, 0)
		bb.node.rotation.z = sin(t * bb.w * 0.7 + bb.ph) * bb.roll
	for h in horns:
		h.t -= dt
		if h.t <= 0.0:
			h.t = h.every + randf() * h.every * 0.5
			if h.node.global_position.distance_to(pp) < h.get("near", 140.0): Snd3.at(self, h.sound, h.node.global_position, h.db, 200.0)

func say(ids: Array) -> void:
	for id in ids: Game.say(id)

func _along(pts: PackedVector3Array, d: float) -> Vector3:
	var acc := 0.0
	var n := pts.size()
	for i in n:
		var a := pts[i]; var b := pts[(i + 1) % n]
		var l := a.distance_to(b)
		if acc + l >= d: return a.lerp(b, (d - acc) / maxf(l, 0.001))
		acc += l
	return pts[0]

static func loop_len(pts: PackedVector3Array) -> float:
	var s := 0.0
	for i in pts.size(): s += pts[i].distance_to(pts[(i + 1) % pts.size()])
	return s

func open_door(d: Dictionary) -> void:
	if d.open: return
	d.open = true
	var n: Node3D = d.node
	Snd3.at(self, "docks_door_roll", n.global_position + Vector3(0, 2, 0), 0.0)
	var tw := create_tween()
	tw.tween_property(n, "position:y", d.open_y, 2.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func open_door_id(id: String) -> void:
	for d in doors:
		if d.id == id: open_door(d)

func set_belt(id: String, speed: float) -> void:
	for b in belts:
		if b.id == id:
			b.speed = speed
			(b.body as StaticBody3D).constant_linear_velocity = b.dir * speed

## Tiny positional one-shot player for the docks' own sounds (mp3s in audio/sfx/docks_*; Snd only loads oggs).
class Snd3:
	static var _cache := {}
	static func at(host: Node, name: String, pos: Vector3, db := 0.0, max_d := 90.0) -> void:
		var path := "res://audio/sfx/%s.mp3" % name
		if not _cache.has(name):
			_cache[name] = load(path) if ResourceLoader.exists(path) else null
		var s: AudioStream = _cache[name]
		if s == null: return
		var p := AudioStreamPlayer3D.new()
		p.stream = s; p.volume_db = db; p.unit_size = 10.0; p.max_distance = max_d
		p.pitch_scale = randf_range(0.95, 1.05)
		host.add_child(p); p.global_position = pos
		p.finished.connect(p.queue_free)
		p.play()

	## A looping ambient emitter (the conveyors, the harbor bed).
	static func loop(host: Node, name: String, pos: Vector3, db := 0.0, unit := 10.0, max_d := 60.0) -> AudioStreamPlayer3D:
		var path := "res://audio/sfx/%s.mp3" % name
		if not ResourceLoader.exists(path): return null
		var s: AudioStream = load(path).duplicate()
		if s is AudioStreamMP3: (s as AudioStreamMP3).loop = true
		var p := AudioStreamPlayer3D.new()
		p.stream = s; p.volume_db = db; p.unit_size = unit; p.max_distance = max_d; p.autoplay = true
		host.add_child(p); p.global_position = pos
		return p
