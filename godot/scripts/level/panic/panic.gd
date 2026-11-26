extends Node3D
## Skyharbor in a panic: since the 8:00 signal sent every bot haywire, the city is trying to get off-world.
## Built by scripts/level/areas/zz_panic.gd (after every other area, so all the floors exist).
##   crowd.gd    citizens fleeing, ducking from bots, queueing at the docks and boarding shuttles
##   traffic.gd  sky cars jamming the lanes between districts, haywire cars spiralling down, ships climbing off-world
##   evac.gd     the evacuation shuttle that keeps landing at Pier A's south edge, loading and taking off
## Plus the sound of it: sirens now and then from far-off towers, crowd panic beds around the busy areas and the Skyharbor Authority's
## evacuation announcements on the docks PA (audio/sfx/panic_*.ogg, audio/voice/panic_pa_*.ogg).
## Everything is hidden during the intro cutscene (the morning is quiet until the signal).
## Flags: --no-panic (skip all of it), --no-crowd, --no-traffic.

const S := preload("res://scripts/level/layout/spread.gd")
const Crowd := preload("res://scripts/level/panic/crowd.gd")
const Traffic := preload("res://scripts/level/panic/traffic.gd")
const Evac := preload("res://scripts/level/panic/evac.gd")

var L: Node3D
var crowd: Node3D
var traffic: Node3D
var evac: Node3D
var pa_spots: Array = []      # Vector3 speakers
var pa_t := 25.0
var pa_i := 0
var pa_player: AudioStreamPlayer3D
var chime_player: AudioStreamPlayer3D
var beds: Array = []          # AudioStreamPlayer3D
## occasional city sirens: [sound, db] picked at random (not the same twice running) from one of the towers
const SIRENS := [["panic_siren_wail", -3.0], ["panic_siren_whoop", -9.0], ["panic_siren_klaxon", -4.0],
	["panic_siren_bell", -11.0], ["panic_siren_rise", 0.0]]
const SIREN_TOWERS := [Vector3(-170, 40, 40), Vector3(190, 30, -110), Vector3(60, 50, 200)]
var siren_player: AudioStreamPlayer3D
var siren_t := 9.0
var siren_last := -1
var calm := false
var t := 0.0

func setup(level: Node3D) -> void:
	L = level
	var args := OS.get_cmdline_user_args()
	if not args.has("--no-crowd"):
		crowd = Crowd.new(); crowd.name = "Crowd"; crowd.setup(L); add_child(crowd)
		_plan_crowd()
	if not args.has("--no-traffic"):
		traffic = Traffic.new(); traffic.name = "Traffic"; traffic.setup(L); add_child(traffic)
	evac = Evac.new(); evac.name = "Evac"; evac.traffic = traffic; evac.setup(L, crowd); add_child(evac)
	_sound()

## walk layers from the level's islands (one per floor height) and who lives where
func _plan_crowd() -> void:
	var by_h := {}
	for n in L.islands:
		var h: float = snappedf(L.heights.get(n, 0.0), 0.1)
		var r: Rect2 = L.islands[n]
		by_h[h] = r.grow(3.0) if not by_h.has(h) else (by_h[h] as Rect2).merge(r.grow(3.0))
	var layer_of := {}
	for h in by_h: layer_of[h] = crowd.add_layer("h%.1f" % h, h, by_h[h])
	var lay := func(island: String) -> int: return layer_of[snappedf(L.heights.get(island, 0.0), 0.1)]
	# [island, roamers, evacuees]
	var homes := [["plaza", 12, 6], ["terrace", 6, 2], ["gardens", 5, 0], ["promenade", 2, 0], ["conservatory", 2, 0],
		["pier_a", 3, 9], ["pier_b", 2, 0], ["pier_c", 2, 0], ["pier_d", 3, 0], ["berth", 7, 0], ["causeway", 2, 0],
		["tier2", 1, 0], ["tier3", 1, 0], ["tier4", 1, 0], ["plaza_park", 2, 0]]
	for h in homes:
		if not L.islands.has(h[0]): continue
		var r: Rect2 = L.islands[h[0]]
		if h[1] > 0: crowd.add_zone(h[0], lay.call(h[0]), r, h[1], ["roam"])
		if h[2] > 0: crowd.add_zone(h[0] + "_evac", lay.call(h[0]), r, h[2], ["evac"])
	# new evacuees turn up on the far side of the plaza and the terrace
	for n in ["plaza", "terrace", "causeway"]:
		if L.islands.has(n): crowd.sources.append([lay.call(n), L.islands[n]])

func _ready() -> void:
	Game.cutscene_started.connect(func(id: String): if id == "intro": _show(false))
	Game.cutscene_finished.connect(func(id: String): if id == "intro": _show(true))
	Game.boss_defeated.connect(func(n: String): if n == "CRANE BOT": _calm())

## the Crane Bot is down: the sirens stop and people cheer instead of running (the shuttles keep going)
func _calm() -> void:
	calm = true
	if siren_player: create_tween().tween_property(siren_player, "volume_db", -60.0, 3.0)
	for b in beds:
		var p := b as AudioStreamPlayer3D
		if p.stream and String(p.stream.resource_path).contains("siren"):
			create_tween().tween_property(p, "volume_db", -60.0, 4.0)
	if crowd: crowd.calm = true
	pa_t = 1e9

func _show(on: bool) -> void:
	visible = on
	if crowd: crowd.paused = not on
	for b in beds:
		if on: (b as AudioStreamPlayer3D).play()
		else: (b as AudioStreamPlayer3D).stop()

# ------------------------------------------------------------------ sound
func _stream(n: String, loop := false) -> AudioStream:
	var p := "res://audio/sfx/%s.ogg" % n
	if not ResourceLoader.exists(p): return null
	var s: AudioStream = load(p)
	if loop and s is AudioStreamOggVorbis:
		s = s.duplicate(); (s as AudioStreamOggVorbis).loop = true
	return s

func _bed(n: String, pos: Vector3, db: float, unit: float, maxd: float, bus := "Amb") -> void:
	var s := _stream(n, true)
	if s == null: return
	var p := AudioStreamPlayer3D.new(); p.stream = s; p.volume_db = db; p.unit_size = unit; p.max_distance = maxd
	p.bus = bus; p.position = pos; p.autoplay = true
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	add_child(p); beds.append(p)
	p.play.call_deferred(randf() * 8.0)

func _sound() -> void:
	# sirens now and then from far-off towers (never one constant drone): see _siren()
	siren_player = AudioStreamPlayer3D.new(); siren_player.bus = "Amb"; siren_player.unit_size = 60.0; siren_player.max_distance = 900.0
	siren_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	add_child(siren_player)
	# crowd beds where people are
	for c in [["plaza", Vector3(0, 1.5, 30), -4.0], ["pier_a", Vector3(39, 1.5, 38), -3.0], ["berth", Vector3(122, 1.5, 30), -5.0],
			["terrace", Vector3(-36, 1.5, 36), -8.0], ["gardens", Vector3(-30, 10.3, -20), -10.0]]:
		if L.islands.has(c[0]): _bed("panic_crowd_loop" if c[2] > -6.0 else "panic_crowd_near_loop", S.at(c[1]), c[2], 12.0, 80.0)
	# the docks PA: speakers on Pier A and the berth, plus the plaza
	pa_spots = [S.at(Vector3(39, 7, 44)), S.at(Vector3(118, 7, 30)), Vector3(18, 7, 30)]
	pa_player = AudioStreamPlayer3D.new(); pa_player.bus = "World"; pa_player.unit_size = 18.0; pa_player.max_distance = 110.0
	pa_player.volume_db = 1.0; add_child(pa_player)
	chime_player = AudioStreamPlayer3D.new(); chime_player.bus = "World"; chime_player.unit_size = 18.0; chime_player.max_distance = 110.0
	chime_player.stream = _stream("panic_pa_chime"); chime_player.volume_db = -3.0; add_child(chime_player)

func _process(dt: float) -> void:
	_test(dt)
	_debug_cam()
	if not visible: return
	t += dt
	pa_t -= dt
	if pa_t <= 0.0: _announce()
	siren_t -= dt
	if siren_t <= 0.0: _siren()

func _siren() -> void:
	siren_t = randf_range(28.0, 55.0)
	if calm or siren_player == null or Game.input_locked: return
	var i := randi() % SIRENS.size()
	if i == siren_last: i = (i + 1) % SIRENS.size()
	siren_last = i
	var s := _stream(SIRENS[i][0])
	if s == null: return
	siren_player.stream = s; siren_player.volume_db = SIRENS[i][1]
	siren_player.position = SIREN_TOWERS[randi() % SIREN_TOWERS.size()]
	siren_player.pitch_scale = randf_range(0.96, 1.04)
	siren_player.play()

func _announce() -> void:
	pa_t = randf_range(38.0, 55.0)
	var pl: Node3D = Game.player
	if pl == null or Game.input_locked: return
	if Snd.get("voice_player") and Snd.voice_player and Snd.voice_player.playing:
		pa_t = 6.0; return
	var pp := pl.global_position
	var best := Vector3.ZERO; var bd := 95.0
	for s in pa_spots:
		var d: float = (s as Vector3).distance_to(pp)
		if d < bd: bd = d; best = s
	if best == Vector3.ZERO: return
	var path := "res://audio/voice/panic_pa_%d.ogg" % (pa_i % 6 + 1)
	pa_i += 1
	if not ResourceLoader.exists(path): return
	chime_player.global_position = best; pa_player.global_position = best
	chime_player.play()
	pa_player.stream = load(path)
	var id := path.get_file().get_basename()
	get_tree().create_timer(1.6).timeout.connect(func():
		if not is_inside_tree(): return
		pa_player.play()
		if bd < 60.0: Snd.line_started.emit(id, "skyharbor authority", Crowd.line_text(id)))

# ------------------------------------------------------------------ debug: --panic-test=<seconds> prints what everyone is up to, then quits
var _test_t := -1.0
var _test_next := 2.0
func _test(dt: float) -> void:
	if _test_t < 0.0:
		_test_t = 0.0
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--panic-test="): _test_t = float(a.substr(13)); set_meta("test", true)
		if not has_meta("test"): _test_t = 1e9
		return
	if not has_meta("test"): return
	_test_t -= dt; _test_next -= dt
	if _test_next <= 0.0 or _test_t <= 0.0:
		_test_next = 5.0
		var states := {}
		var boarded := 0
		if crowd:
			for p in crowd.people: states[p.state] = states.get(p.state, 0) + 1
			for q in crowd.queue: if q != null: boarded += 1
		var flying := 0
		if traffic:
			for s in traffic.ships: if s.u < 1.0: flying += 1
		var hay := 0
		if traffic:
			for c in traffic.cars: if c.mode != "lane": hay += 1
		if crowd and Game.player:
			var near := 0
			for p in crowd.people: if (p.pos as Vector3).distance_to(Game.player.global_position) < 30.0: near += 1
			print("[panic-test] visible %s crowd ready %s near Vesk %d player %s" % [is_visible_in_tree(), crowd.ready_, near, Game.player.global_position])
		print("[panic-test] t=%.0f people %s queue %d shuttle %s ships up %d cars %d (off lane %d) puffs live %d fps %d" % [t, states, boarded,
			evac.state if evac else "-", flying, traffic.cars.size() if traffic else 0, hay,
			traffic.puff_data.filter(func(x): return x.life > 0.0).size() if traffic else 0, Engine.get_frames_per_second()])
	if _test_t <= 0.0: get_tree().quit()

## debug: --panic-cam=x,y,z,tx,ty,tz looks from x,y,z at tx,ty,tz (screenshots with --shot)
var _cam: Camera3D
func _debug_cam() -> void:
	if _cam == null and not has_meta("nocam"):
		set_meta("nocam", true)
		for a in OS.get_cmdline_user_args():
			if a == "--panic-cam-ship" and evac:
				# follow the evacuation shuttle from the pier
				_cam = Camera3D.new(); _cam.fov = 55.0; _cam.far = 4000.0; add_child(_cam)
				_cam.position = S.at(Vector3(30, 4, 34)); _cam.set_meta("ship", true); _cam.set_meta("at", Vector3.ZERO)
			if a.begins_with("--panic-cam="):
				var v := a.substr(12).split_floats(",")
				_cam = Camera3D.new(); _cam.fov = 60.0; _cam.far = 4000.0; add_child(_cam)
				_cam.position = Vector3(v[0], v[1], v[2]); _cam.set_meta("at", Vector3(v[3], v[4], v[5]))
	if _cam:
		_cam.current = true
		if _cam.has_meta("ship") and evac.ship.visible: _cam.set_meta("at", evac.ship.global_position)
		if _cam.get_meta("at") != Vector3.ZERO: _cam.look_at(_cam.get_meta("at"))
