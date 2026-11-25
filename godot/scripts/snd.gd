extends Node
## Sound effects (made with ElevenLabs, in audio/sfx). Snd.play("name") for UI and the hero,
## Snd.at("name", pos) for sounds out in the world, Snd.loop("name", on) for held loops.

const DIR := "res://audio/sfx/"
var streams := {}
var pool: Array[AudioStreamPlayer] = []
var pool3: Array[AudioStreamPlayer3D] = []
var loops := {}
var last := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for f in DirAccess.get_files_at(DIR):
		var n := f.trim_suffix(".import")
		if n.ends_with(".ogg") and not streams.has(n.get_basename()):
			streams[n.get_basename()] = load(DIR + n)
	for i in 16:
		var p := AudioStreamPlayer.new(); p.bus = "Master"; add_child(p); pool.append(p)
	for i in 24:
		var p := AudioStreamPlayer3D.new(); p.unit_size = 8.0; p.max_distance = 90.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE; add_child(p); pool3.append(p)

func _ok(n: String, gap: float) -> bool:
	if not streams.has(n): return false
	var now := Time.get_ticks_msec() / 1000.0
	if now - last.get(n, -9.0) < gap: return false
	last[n] = now; return true

func play(n: String, db := 0.0, pitch_var := 0.06, gap := 0.03) -> void:
	if not _ok(n, gap): return
	for p in pool:
		if not p.playing:
			p.stream = streams[n]; p.volume_db = db; p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var); p.play(); return

func at(n: String, pos: Vector3, db := 0.0, pitch_var := 0.08, gap := 0.03) -> void:
	if not _ok(n, gap): return
	for p in pool3:
		if not p.playing:
			p.stream = streams[n]; p.volume_db = db; p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
			p.global_position = pos; p.play(); return

## A held loop (grind, glide, ambience). Fades in and out.
func loop(n: String, on: bool, db := 0.0) -> void:
	if not streams.has(n): return
	var p: AudioStreamPlayer = loops.get(n)
	if p == null:
		if not on: return
		var s: AudioStream = streams[n].duplicate()
		if s is AudioStreamOggVorbis: s.loop = true
		p = AudioStreamPlayer.new(); p.stream = s; p.volume_db = -40; add_child(p); loops[n] = p
		p.set_meta("want", db)
	p.set_meta("on", on); p.set_meta("want", db)
	if on and not p.playing: p.play()

func _process(dt: float) -> void:
	for n in loops:
		var p: AudioStreamPlayer = loops[n]
		var target: float = p.get_meta("want") if p.get_meta("on") else -40.0
		p.volume_db = move_toward(p.volume_db, target, dt * 60.0)
		if not p.get_meta("on") and p.volume_db <= -39.5 and p.playing: p.stop()

# ---------- music (crossfades between tracks in audio/music) ----------
var music_players: Array[AudioStreamPlayer] = []
var music_cur := -1
var music_name := ""
var music_db := -6.0

func music(n: String, fade := 1.5) -> void:
	if n == music_name: return
	music_name = n
	if music_players.is_empty():
		for i in 2:
			var p := AudioStreamPlayer.new(); p.volume_db = -60; add_child(p); music_players.append(p)
	var old := music_cur
	music_cur = 0 if music_cur != 0 else 1
	var p := music_players[music_cur]
	if n != "":
		var s: AudioStream = load("res://audio/music/%s.ogg" % n)
		if s is AudioStreamOggVorbis: s = s.duplicate(); s.loop = true
		p.stream = s; p.volume_db = -60; p.play()
		create_tween().tween_property(p, "volume_db", music_db, fade)
	if old >= 0:
		var q := music_players[old]
		var tw := create_tween(); tw.tween_property(q, "volume_db", -60.0, fade); tw.tween_callback(q.stop)

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
		voice_player = AudioStreamPlayer.new(); add_child(voice_player)
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
