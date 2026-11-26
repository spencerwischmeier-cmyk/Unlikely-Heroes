extends Node
## Sound (made with ElevenLabs, in audio/sfx and audio/music). Autoloaded as Snd.
##   Snd.play("name")          a sound for UI and the hero (2D, dry)
##   Snd.at("name", pos)       a sound out in the world (3D, through the World bus reverb)
##   Snd.loop("name", on)      a held loop (grind, glide, ambience); fades in and out
##   Snd.music("track")        crossfade to audio/music/<track>; "skyharbor" hands the music to the
##                             adaptive director (per-area themes and a combat layer, see audio_director.gd)
##   Snd.sting("name")         a short musical stinger over the music (the music dips under it)
##   Snd.voice(id) / bark()    voice lines; music and ambience duck under them
##
## Variants: files named <name>_<n> (step_wood_1, bolt_hit_2 ...) are picked at random when "<name>" is
## played, never the same one twice in a row. Layers (LAYERS) add extra punch to some sounds.
## Files: .ogg and .mp3 both load (area agents' <area>_*.mp3 included).
##
## Buses (also in default_bus_layout.tres): Master (limiter) <- Music (duck), SFX (glue compressor)
## <- Amb (duck), World (reverb, duck) ; Voice (high-pass + compressor).

const DIR := "res://audio/sfx/"
const MUSIC_DIR := "res://audio/music/"

## extra layers played with a sound: name -> [[layer, db offset, delay seconds], ...]
const LAYERS := {
	"blaster": [["blaster_tail", -7.0, 0.0]],
	"explode_big": [["explode_sub", -1.0, 0.0], ["debris", -5.0, 0.14]],
	"explode_small": [["debris", -11.0, 0.08]],
	"lobber_explode": [["explode_sub", -6.0, 0.0]],
	"relay_destroy": [["explode_sub", 0.0, 0.0], ["debris", -2.0, 0.2]],
	"crane_slam": [["explode_sub", -5.0, 0.0]],
	"boss_defeat": [["explode_sub", 0.0, 0.0], ["debris", 0.0, 0.3]],
	"hurt": [["hurt_armor", -3.0, 0.0]],
	"dash": [["dash_whoosh", -4.0, 0.0]],
	"double_jump": [["jet_ignite", -5.0, 0.0]],
	"sprocket_burst": [["coin_burst", -3.0, 0.05]],
	"hook_fire": [["rope_swing", -7.0, 0.06]],
	"crate_break": [["debris", -12.0, 0.06]],
}
## how many copies of one sound may ring at once (the oldest is cut)
const MAX_INST := {"step": 2, "blaster": 3, "bolt_hit": 3, "nut_pickup": 3, "melee_hit": 3, "debris": 2,
	"explode_sub": 2, "hornet_buzz": 2, "roller_roll": 2, "crane_move": 2}

var streams := {}
var groups := {}          # name -> [variant names]
var last_pick := {}
var pool: Array[AudioStreamPlayer] = []
var pool3: Array[AudioStreamPlayer3D] = []
var loops := {}
var loop_extra := {}      # name -> extra db the director adds on top of a loop's wanted level
var last := {}
var director: Node        # systems/audio_director.gd registers itself here

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()
	for f in DirAccess.get_files_at(DIR):
		var n := f.trim_suffix(".import").trim_suffix(".remap")
		if (n.ends_with(".ogg") or n.ends_with(".mp3")) and not streams.has(n.get_basename()):
			var s = load(DIR + n)
			if s: streams[n.get_basename()] = s
	_build_groups()
	for i in 20:
		var p := AudioStreamPlayer.new(); p.bus = "SFX"; add_child(p); pool.append(p)
	var world := Node.new(); world.name = "World3D"; add_child(world)
	for i in 32:
		var p := AudioStreamPlayer3D.new(); p.unit_size = 8.0; p.max_distance = 90.0; p.bus = "World"
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.attenuation_filter_cutoff_hz = 9000.0; p.attenuation_filter_db = -18.0
		world.add_child(p); pool3.append(p)
	_load_loop_points()

func _build_groups() -> void:
	var re := RegEx.create_from_string("^(.+)_(\\d+)$")
	for n in streams:
		var m := re.search(n)
		if m: (groups.get_or_add(m.get_string(1), []) as Array).append(n)
	for n in streams:
		if groups.has(n) and not (groups[n] as Array).has(n): groups[n].append(n)

## the name actually played for n: a random variant (not the last one), or n itself
func pick(n: String) -> String:
	var g: Array = groups.get(n, [])
	if g.size() <= 1: return n if streams.has(n) else (g[0] if g.size() == 1 else "")
	var c: String = g.pick_random()
	if c == last_pick.get(n, ""): c = g[(g.find(c) + 1) % g.size()]
	last_pick[n] = c
	return c

func _dir() -> bool:
	return director != null and is_instance_valid(director)

func has_sound(n: String) -> bool:
	return streams.has(n) or groups.has(n)

func _ok(n: String, gap: float) -> bool:
	if not has_sound(n): return false
	var now := Time.get_ticks_msec() / 1000.0
	if now - last.get(n, -9.0) < gap: return false
	last[n] = now; return true

func _cap(n: String) -> int:
	for k in MAX_INST:
		if n.begins_with(k): return MAX_INST[k]
	return 5

## a free player from a pool (or the one to cut: the oldest copy of this sound, else the oldest of all)
func _free_player(arr: Array, n: String):
	var same := []; var oldest = null; var oldest_t := -1.0
	for p in arr:
		if not p.playing: return p
		if p.get_meta("n", "") == n: same.append(p)
		var t: float = p.get_playback_position()
		if t > oldest_t: oldest_t = t; oldest = p
	if same.size() >= _cap(n):
		var o = same[0]
		for p in same: if p.get_playback_position() > o.get_playback_position(): o = p
		return o
	return oldest

func play(n: String, db := 0.0, pitch_var := 0.06, gap := 0.03) -> void:
	if n == "step_metal" and _dir(): n = "step_" + director.surface()
	if n == "land" and _dir(): director.landed(db)
	if not _ok(n, gap): return
	var pitch := 1.0 + randf_range(-pitch_var, pitch_var)
	_play2(pick(n), db, pitch, n)
	_layers(n, db, pitch, null)

func _play2(c: String, db: float, pitch: float, key: String) -> void:
	if c == "" or not streams.has(c): return
	var p: AudioStreamPlayer = _free_player(pool, key)
	p.stream = streams[c]; p.volume_db = db; p.pitch_scale = pitch; p.set_meta("n", key); p.play()

func at(n: String, pos: Vector3, db := 0.0, pitch_var := 0.08, gap := 0.03) -> void:
	if not _ok(n, gap): return
	var pitch := 1.0 + randf_range(-pitch_var, pitch_var)
	_play3(pick(n), pos, db, pitch, n)
	_layers(n, db, pitch, pos)

func _play3(c: String, pos: Vector3, db: float, pitch: float, key: String) -> void:
	if c == "" or not streams.has(c): return
	var p: AudioStreamPlayer3D = _free_player(pool3, key)
	p.stream = streams[c]; p.volume_db = db; p.pitch_scale = pitch; p.set_meta("n", key)
	p.global_position = pos; p.play()

func _layers(n: String, db: float, pitch: float, pos) -> void:
	for l in LAYERS.get(n, []):
		var ln: String = l[0]
		if not has_sound(ln): continue
		var c := pick(ln)
		if l[2] <= 0.0: _layer_now(c, db + l[1], pitch, ln, pos)
		else: get_tree().create_timer(l[2], true, false, true).timeout.connect(_layer_now.bind(c, db + l[1], pitch, ln, pos))

func _layer_now(c: String, db: float, pitch: float, key: String, pos) -> void:
	if pos == null: _play2(c, db, pitch, key)
	else: _play3(c, pos, db, pitch, key)

## A held loop (grind, glide, ambience). Fades in and out.
func loop(n: String, on: bool, db := 0.0) -> void:
	if not streams.has(n): return
	var p: AudioStreamPlayer = loops.get(n)
	if p == null:
		if not on: return
		var s: AudioStream = streams[n].duplicate()
		if "loop" in s: s.loop = true
		p = AudioStreamPlayer.new(); p.stream = s; p.volume_db = -40; p.bus = "SFX"; add_child(p); loops[n] = p
		p.set_meta("want", db)
	p.set_meta("on", on); p.set_meta("want", db)
	if on and not p.playing: p.play()

func _process(dt: float) -> void:
	for n in loops:
		var p: AudioStreamPlayer = loops[n]
		var target: float = (p.get_meta("want") + loop_extra.get(n, 0.0)) if p.get_meta("on") else -40.0
		p.volume_db = move_toward(p.volume_db, target, dt * 60.0)
		if not p.get_meta("on") and p.volume_db <= -39.5 and p.playing: p.stop()
	_music_process(dt)
	_duck_process(dt)

# ---------- buses ----------
func _bus(name_: String, send: String) -> int:
	var i := AudioServer.get_bus_index(name_)
	if i < 0:
		AudioServer.add_bus(AudioServer.bus_count); i = AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, name_)
	AudioServer.set_bus_send(i, send)
	return i

func _fx(bus: int, cls: String, props: Dictionary) -> AudioEffect:
	var e: AudioEffect = null
	for k in AudioServer.get_bus_effect_count(bus):
		if AudioServer.get_bus_effect(bus, k).get_class() == cls: e = AudioServer.get_bus_effect(bus, k)
	if e == null:
		e = ClassDB.instantiate(cls); AudioServer.add_bus_effect(bus, e)
	for k in props: e.set(k, props[k])
	return e

func _setup_buses() -> void:
	_fx(0, "AudioEffectHardLimiter", {"ceiling_db": -0.8, "pre_gain_db": 2.5, "release": 0.12})
	var mu := _bus("Music", "Master")
	_fx(mu, "AudioEffectAmplify", {"volume_db": 0.0})
	_fx(mu, "AudioEffectLowPassFilter", {"cutoff_hz": 20500.0})
	var sfx := _bus("SFX", "Master")
	_fx(sfx, "AudioEffectCompressor", {"threshold": -14.0, "ratio": 2.5, "attack_us": 4000.0, "release_ms": 140.0, "gain": 0.0})
	var vo := _bus("Voice", "Master")
	_fx(vo, "AudioEffectHighPassFilter", {"cutoff_hz": 95.0})
	_fx(vo, "AudioEffectCompressor", {"threshold": -20.0, "ratio": 3.0, "attack_us": 2500.0, "release_ms": 160.0, "gain": 2.5})
	var amb := _bus("Amb", "SFX")
	_fx(amb, "AudioEffectAmplify", {"volume_db": 0.0})
	var w := _bus("World", "SFX")
	_fx(w, "AudioEffectAmplify", {"volume_db": 0.0})
	_fx(w, "AudioEffectReverb", {"room_size": 0.45, "damping": 0.6, "spread": 0.9, "hipass": 0.25, "dry": 1.0, "wet": 0.08,
		"predelay_msec": 45.0, "predelay_feedback": 0.25})

func bus_fx(bus: String, cls: String) -> AudioEffect:
	var i := AudioServer.get_bus_index(bus)
	if i < 0: return null
	for k in AudioServer.get_bus_effect_count(i):
		var e := AudioServer.get_bus_effect(i, k)
		if e.get_class() == cls: return e
	return null

## ducking: music and ambience dip under dialogue
var duck := 0.0
func _duck_process(dt: float) -> void:
	var talking := voice_player != null and voice_player.playing
	duck = move_toward(duck, 1.0 if talking else 0.0, dt * (4.0 if talking else 1.2))
	var m := bus_fx("Music", "AudioEffectAmplify"); if m: m.volume_db = -6.5 * duck
	var a := bus_fx("Amb", "AudioEffectAmplify"); if a: a.volume_db = -6.0 * duck
	var w := bus_fx("World", "AudioEffectAmplify"); if w: w.volume_db = -2.5 * duck

# ---------- music (crossfades between tracks in audio/music) ----------
var music_players: Array[AudioStreamPlayer] = []   # every music player (menus routes these to the Music bus)
var music_name := ""          # what was asked for ("skyharbor" = adaptive)
var music_db := -6.0
var adaptive := false         # the director picks the track (area themes / combat)
var track := ""               # the track playing now
var tracks := {}              # track -> {p, fade, rate, pos}
var loop_points := {}
var sting_player: AudioStreamPlayer
var sting_duck := 0.0
var sting_t := 0.0
var sting_depth := 9.0

func _load_loop_points() -> void:
	if FileAccess.file_exists(MUSIC_DIR + "loops.json"):
		var d = JSON.parse_string(FileAccess.get_file_as_string(MUSIC_DIR + "loops.json"))
		if d is Dictionary: loop_points = d

func has_music(t: String) -> bool:
	return ResourceLoader.exists(MUSIC_DIR + t + ".ogg") or ResourceLoader.exists(MUSIC_DIR + t + ".mp3")

func music(n: String, fade := 1.5) -> void:
	if n == music_name: return
	music_name = n
	adaptive = n == "skyharbor" and has_music("area_plaza")
	if adaptive and _dir(): director.pick_track(fade)
	else: set_track(n, fade)   # (adaptive without a director yet: the plain theme until it takes over)

## crossfade to a track (fade seconds); area and combat themes resume where they left off
func set_track(t: String, fade := 1.5, db := 0.0) -> void:
	if t == track: return
	track = t
	for k in tracks: tracks[k].rate = 1.0 / maxf(fade, 0.05)
	if t == "": return
	var tr: Dictionary = tracks.get(t, {})
	if tr.is_empty():
		var path := MUSIC_DIR + t + (".ogg" if ResourceLoader.exists(MUSIC_DIR + t + ".ogg") else ".mp3")
		if not ResourceLoader.exists(path): return
		var s: AudioStream = (load(path) as AudioStream).duplicate()
		if "loop" in s: s.loop = true
		if "loop_offset" in s and loop_points.has(t): s.loop_offset = float(loop_points[t])
		var p := AudioStreamPlayer.new(); p.stream = s; p.volume_db = -60; p.bus = "Music"; add_child(p)
		music_players.append(p)
		tr = {p = p, fade = 0.0, rate = 1.0, pos = 0.0, db = db}
		tracks[t] = tr
	tr.rate = 1.0 / maxf(fade, 0.05); tr.db = db
	if not tr.p.playing:
		var resume: bool = t.begins_with("area_") or t.begins_with("combat_")
		tr.p.play(tr.pos if resume else 0.0)

func _music_process(dt: float) -> void:
	if sting_t > 0.0: sting_t -= dt
	sting_duck = move_toward(sting_duck, 1.0 if sting_t > 0.0 else 0.0, dt * (5.0 if sting_t > 0.0 else 0.8))
	for k in tracks:
		var tr: Dictionary = tracks[k]
		var want := 1.0 if k == track else 0.0
		tr.fade = move_toward(tr.fade, want, dt * tr.rate)
		var p: AudioStreamPlayer = tr.p
		p.volume_db = music_db + tr.db + linear_to_db(maxf(tr.fade, 0.001)) - sting_depth * sting_duck
		if tr.fade <= 0.0 and p.playing:
			tr.pos = p.get_playback_position(); p.stop()

## a short musical stinger over the music
func sting(n: String, db := 0.0, duck_db := 9.0, duck_time := -1.0) -> void:
	var path := MUSIC_DIR + n + ".ogg"
	if not ResourceLoader.exists(path): return
	if sting_player == null:
		sting_player = AudioStreamPlayer.new(); sting_player.bus = "Music"; add_child(sting_player)
		music_players.append(sting_player)
	sting_player.stream = load(path); sting_player.volume_db = music_db + 3.0 + db; sting_player.play()
	sting_t = duck_time if duck_time >= 0.0 else maxf(0.5, sting_player.stream.get_length() - 1.2)
	sting_depth = duck_db

# ---------- voice lines (audio/voice, text in audio/voice/script.json) ----------
signal line_started(id: String, speaker: String, text: String)
var voice_player: AudioStreamPlayer
var voice_queue: Array = []
var script_lines := {}

func _load_script() -> void:
	if not script_lines.is_empty(): return
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://audio/voice/script.json"))
	if d == null: return
	for k in d:
		if k.begins_with("_"): continue
		if d[k] is Array:
			for r in d[k]: script_lines[r[0]] = [r[1], r[2]]
		else:
			for kk in d[k]:
				var arr: Array = d[k][kk]
				for j in arr.size(): script_lines["%s_%s_%d" % [k, kk, j + 1]] = [k, arr[j]]

## Text with the [delivery tags] stripped, for subtitles.
func subtitle(id: String) -> String:
	_load_script()
	if not script_lines.has(id): return ""
	var re := RegEx.create_from_string("\\[[^\\]]*\\]\\s*")
	return re.sub(script_lines[id][1], "", true).strip_edges()

## Play a voice line now (interrupt = true) or after the current one.
func voice(id: String, interrupt := false) -> float:
	_load_script()
	var path := "res://audio/voice/%s.ogg" % id
	if not ResourceLoader.exists(path): return 0.0
	if voice_player == null:
		voice_player = AudioStreamPlayer.new(); voice_player.bus = "Voice"; add_child(voice_player)
		voice_player.finished.connect(func(): if not voice_queue.is_empty(): _voice_now(voice_queue.pop_front()))
	if interrupt or not voice_player.playing: _voice_now(id)
	else: voice_queue.append(id)
	return (load(path) as AudioStream).get_length()

## A random line from a bark set like ("dodger", "spawn").
func bark(who: String, kind: String, chance := 1.0) -> void:
	if randf() > chance or (voice_player and voice_player.playing): return
	_load_script()
	var ids := []
	var pre := "%s_%s_" % [who, kind]
	for k in script_lines: if k.begins_with(pre): ids.append(k)
	if ids.size() > 0: voice(ids.pick_random())

func _voice_now(id: String) -> void:
	voice_player.stream = load("res://audio/voice/%s.ogg" % id); voice_player.play()
	var sp: String = script_lines.get(id, ["", ""])[0]
	line_started.emit(id, sp, subtitle(id))
