extends Node3D
## The Dock Plaza's moving parts: clock hands, the belfry chime, Gizmart's PA adverts from the clock tower,
## ambience loops (fountain, market crowd), spinning signs and a flock of birds round the tower.
## Built by scripts/level/areas/plaza.gd. Sounds live in audio/sfx/plaza_*.ogg and audio/voice/plaza_ad_*.ogg
## and are loaded here directly (missing files are skipped).

const PLAZA := Rect2(-24, 12, 48, 36)

var clock_hands: Array = []     # [hour_pivot, minute_pivot]
var bell: Node3D
var chime_pos := Vector3.ZERO
var pa_pos := Vector3.ZERO
var spinners: Array = []        # [node, speed]
var birds: Array = []           # { node, r, h, speed, phase, wing }
var bird_center := Vector3.ZERO
var t := 0.0
var chime_t := 25.0
var pa_t := 40.0
var pa_i := 0
var ring := 0.0
var _voice: AudioStreamPlayer3D
var _chime: AudioStreamPlayer3D
var _ads: Array = []

func _ready() -> void:
	_chime = _player(load_ogg("res://audio/sfx/plaza_chime.ogg"), 0.0, 14.0, 120.0)
	_voice = _player(null, 2.0, 16.0, 90.0)
	for i in range(1, 9):
		var s := load_ogg("res://audio/voice/plaza_ad_%d.ogg" % i)
		if s: _ads.append(s)

static func load_ogg(p: String) -> AudioStream:
	return load(p) if ResourceLoader.exists(p) else null

func _player(s: AudioStream, db: float, unit: float, maxd: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new(); p.stream = s; p.volume_db = db; p.unit_size = unit; p.max_distance = maxd
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	add_child(p)
	return p

## A looping positional ambience (fountain, crowd).
func add_loop(n: String, pos: Vector3, db: float, unit: float, maxd: float) -> void:
	var s: AudioStream = load_ogg("res://audio/sfx/%s.ogg" % n)
	if s == null: return
	s = s.duplicate()
	if s is AudioStreamOggVorbis: (s as AudioStreamOggVorbis).loop = true
	var p := _player(s, db, unit, maxd)
	p.position = pos
	p.autoplay = true
	if p.is_inside_tree(): p.play.call_deferred()

## A gentle idle: bob and turn a little (vendor bots behind the stalls).
func bob(n: Node3D) -> void:
	var m: Node3D = n.get_child(0)
	var y := m.position.y
	var tw := m.create_tween().set_loops()
	tw.tween_property(m, "position:y", y + 0.06, 0.8 + randf() * 0.4).set_trans(Tween.TRANS_SINE)
	tw.tween_property(m, "position:y", y, 0.8 + randf() * 0.4).set_trans(Tween.TRANS_SINE)
	var r := n.rotation.y
	var tw2 := n.create_tween().set_loops()
	tw2.tween_interval(randf_range(1.0, 3.0))
	tw2.tween_property(n, "rotation:y", r + 0.5, 0.6).set_trans(Tween.TRANS_SINE)
	tw2.tween_interval(randf_range(1.5, 3.0))
	tw2.tween_property(n, "rotation:y", r - 0.4, 0.8).set_trans(Tween.TRANS_SINE)
	tw2.tween_interval(randf_range(1.0, 2.0))
	tw2.tween_property(n, "rotation:y", r, 0.6).set_trans(Tween.TRANS_SINE)

func spin(n: Node3D, speed: float) -> void:
	spinners.append([n, speed])

func make_birds(center: Vector3, n: int) -> void:
	bird_center = center
	var m := StandardMaterial3D.new(); m.albedo_color = Color(0.25, 0.22, 0.24); m.roughness = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in n:
		var b := Node3D.new(); add_child(b)
		var wings: Array = []
		for s in [-1, 1]:
			var w := MeshInstance3D.new(); var q := BoxMesh.new(); q.size = Vector3(0.55, 0.03, 0.22)
			w.mesh = q; w.material_override = m; w.position.x = s * 0.27; b.add_child(w); wings.append(w)
		var body := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = Vector3(0.12, 0.1, 0.36); body.mesh = bm
		body.material_override = m; b.add_child(body)
		birds.append({ node = b, r = randf_range(7.0, 14.0), h = randf_range(-3.0, 4.0), speed = randf_range(0.25, 0.45) * (1 if i % 3 else -1),
			phase = randf() * TAU, wings = wings })

func _process(dt: float) -> void:
	t += dt
	# the clock: a quick minute hand (one turn a minute) and an hour hand twelve times slower; five minutes late
	var minutes := t / 60.0 + 55.0 / 60.0
	for h in clock_hands:
		(h[1] as Node3D).rotation.z = -fmod(minutes, 1.0) * TAU
		(h[0] as Node3D).rotation.z = -fmod((minutes + 7.0) / 12.0, 1.0) * TAU
	for s in spinners:
		(s[0] as Node3D).rotation.z += dt * s[1]
	for b in birds:
		var a: float = b.phase + t * b.speed
		var p := bird_center + Vector3(cos(a) * b.r, b.h + sin(t * 0.7 + b.phase) * 1.2, sin(a) * b.r)
		var n: Node3D = b.node
		n.position = p
		n.rotation.y = -a + (0.0 if b.speed > 0 else PI)
		var flap := sin(t * 9.0 + b.phase) * 0.6
		(b.wings[0] as Node3D).rotation.z = flap
		(b.wings[1] as Node3D).rotation.z = -flap
	# the bell swings after a chime
	if bell:
		ring = maxf(0.0, ring - dt * 0.25)
		bell.rotation.x = sin(t * 5.0) * 0.35 * ring
	var hero: Node3D = Game.player
	var near := hero != null and PLAZA.has_point(Vector2(hero.global_position.x, hero.global_position.z))
	chime_t -= dt
	if chime_t <= 0.0:
		chime_t = 75.0
		if near and _chime.stream:
			_chime.global_position = chime_pos; _chime.play(); ring = 1.0
	pa_t -= dt
	if pa_t <= 0.0:
		pa_t = randf_range(55.0, 80.0)
		if near and _ads.size() > 0 and not _chime.playing:
			_voice.global_position = pa_pos
			_voice.stream = _ads[pa_i % _ads.size()]; pa_i += 1
			_voice.play()
			var ding: AudioStream = load_ogg("res://audio/sfx/plaza_pa.ogg")
			if ding:
				_chime.stream = ding; _chime.global_position = pa_pos; _chime.play()
				_voice.stop(); get_tree().create_timer(1.6).timeout.connect(func(): if is_instance_valid(_voice): _voice.play())
				get_tree().create_timer(4.0).timeout.connect(func(): if is_instance_valid(_chime): _chime.stream = load_ogg("res://audio/sfx/plaza_chime.ogg"))
