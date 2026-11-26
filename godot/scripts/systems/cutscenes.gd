extends Node
## Animated in-engine cutscenes for Skyharbor (planet 1). This node is the player: one cutscene
## clock that drives camera moves, actor tweens, letterbox, subtitles and overlays, so everything can
## be skipped or fast-forwarded. The scenes themselves live in scripts/cutscene/scene_*.gd:
##   intro        the sky city, Vesk's quiet morning, the 8:00:00 signal, bots go haywire, Dodger crashes
##   broadcast    after the relay dish is aligned: Foreman Grudd's hologram broadcast over the mast
##   crane_intro  entering the Crane Yard: the Crane Bot drops in (the real boss), Grudd on the PA
##   outro        after the Crane Bot: Grudd's radio rant, Nana Quill, liftoff, Grudd's office, next time
## Story emits Game.cutscene_started(id) and waits for Game.cutscene_finished(id).
## Camera language helpers: cut / move (eased dolly or crane) / orbit / follow, look_node tracking,
## dutch roll, handheld sway, shake, depth of field (dof 0..1, focus_d metres or auto on the look point).
## Acting: speakers are looked at automatically (Vesk's head, Dodger's body, Grudd's head) and the
## speaking actor gets `talk` (nods, eye pulse, loudspeaker pump).
## Skip: hold Jump / Esc / Enter (a press shows the prompt). Debug: --cut=<id> plays one at start
##   (pair with --no-bots), --cut-t=<seconds> fast-forwards into it, --cut-hold freezes it there
##   (screenshots), --no-cutscenes finishes them at once.

const M := preload("res://scripts/mats.gd")
const VeskActor := preload("res://scripts/cutscene/vesk_actor.gd")
const DroneActor := preload("res://scripts/cutscene/drone_actor.gd")
const CutsceneDodger := preload("res://scripts/cutscene/cutscene_dodger.gd")
const GruddActor := preload("res://scripts/cutscene/grudd_actor.gd")
const Props := preload("res://scripts/cutscene/props.gd")
const SCENES := {
	"intro": "res://scripts/cutscene/scene_intro.gd",
	"broadcast": "res://scripts/cutscene/scene_broadcast.gd",
	"crane_intro": "res://scripts/cutscene/scene_crane.gd",
	"outro": "res://scripts/cutscene/scene_outro.gd",
}

const SPEAKER_NAMES := {"vesk": "VESK", "dodger": "DODGER", "grudd": "FOREMAN GRUDD", "gizmart": "GIZMART", "nana": "NANA QUILL", "narrator": ""}
const SPEAKER_COLORS := {"vesk": Color(1, 0.62, 0.25), "dodger": Color(0.5, 0.9, 1), "grudd": Color(1, 0.42, 0.3),
	"gizmart": Color(0.6, 1, 0.5), "nana": Color(0.75, 1, 0.7), "narrator": Color(0.92, 0.92, 0.88)}
const SKIP_HOLD := 0.7

var playing := ""
var ct := 0.0            # cutscene clock (seconds)
var seek := 0.0          # seconds still to fast-forward
var skipping := false
var tracks: Array = []
var actors: Array = []   # nodes freed when the cutscene ends
var keep_props: Array = []
var scene: RefCounted
var cast := {}           # speaker id -> Node3D (for auto look-at and talk)
var auto_look := true
var speaking := ""
var speak_t := 0.0

# camera state (tracked)
var cam: Camera3D
var attrs: CameraAttributesPractical
var cam_pos := Vector3.ZERO
var cam_look := Vector3.ZERO
var cam_fov := 50.0
var cam_roll := 0.0
var sway := 1.0
var shake := 0.0
var look_node: Node3D   # when set, the camera looks at this node (plus look_off)
var look_off := Vector3.ZERO
var follow_node: Node3D # when set, the camera rides along at follow_node + follow_off
var follow_off := Vector3.ZERO
var orbit_on := false
var orbit_c := Vector3.ZERO
var orbit_r := 5.0
var orbit_h := 2.0
var orbit_a := 0.0
var dof := 0.0          # 0..1 depth of field strength
var focus_d := -1.0     # focus distance; <= 0 focuses on the look point
var focus_node: Node3D  # when set, focus follows this node (+ focus_off); rack() blends from the old subject
var focus_off := Vector3.ZERO
var focus_prev_d := -1.0
var focus_k := 1.0      # 0..1 rack blend (old subject -> focus_node)
var hand := 0.0         # handheld rotation shake amount (0 calm .. 1 run-and-gun)
var mblur := 0.0        # camera motion blur strength (shutter)
var _hn := FastNoiseLite.new()
var _prev_vp := Projection.IDENTITY
var _post: MeshInstance3D
var _post_mat: ShaderMaterial
# per-shot lighting rig (see light())
var rig_subject: Node3D
var rig_h := 1.4
var rig_side := 1.0
var rig_lights: Array = []   # key, rim, fill
var rig_preset := ""
var env_saved := {}
var grade_name := ""

# overlay state (tracked)
var fade := 0.0
var white := 0.0
var bars := 0.0
var clock_a := 0.0
var live_a := 0.0
var call_a := 0.0
var card_a := 0.0
var loc_a := 0.0
var boss_a := 0.0
var poster_a := 0.0
var next_a := 0.0
var hint_a := 0.0
var skip_hold := 0.0

var layer: CanvasLayer
var root_ui: Control
var bar_top: ColorRect
var bar_bot: ColorRect
var black: ColorRect
var flash: ColorRect
var vignette: ColorRect
var sub: Control        # subtitle box (menus.gd hides it when subtitles are off)
var sub_rt: RichTextLabel
var sub_t := 0.0
var skip_hint: Label
var skip_bar: ColorRect
var clock_label: Label
var live_label: Label
var call_box: Control
var call_text: Label
var card_title: Label
var card_sub: Label
var loc_box: Control
var loc_title: Label
var loc_sub: Label
var boss_box: Control
var boss_title: Label
var boss_sub: Label
var poster: Control
var next_box: Control
var font: SystemFont
var font_heavy: SystemFont
var hud_was := true
var sun: DirectionalLight3D
var sun_energy := -1.0

var vesk: Node3D
var dodger: Node3D
var grudd: Node3D
var start_args := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="): start_args[a.substr(2, a.find("=") - 2)] = a.substr(a.find("=") + 1)
		elif a.begins_with("--"): start_args[a.substr(2)] = true
	Game.cutscene_started.connect(_on_started)
	Snd.line_started.connect(_on_line)
	_build_ui()
	if start_args.has("cut") and OS.get_cmdline_user_args().has("--no-bots"):
		var id: String = start_args.cut
		get_tree().create_timer(0.05).timeout.connect(func(): Game.cutscene_started.emit(id))

func _on_started(id: String) -> void:
	if playing != "": return
	if start_args.has("no-cutscenes") or not SCENES.has(id):
		_emit_finished.call_deferred(id); return
	_run(id)

func _emit_finished(id: String) -> void:
	Game.cutscene_finished.emit(id)

# ---------------------------------------------------------------- clock, tracks and waits
func tw(obj: Object, prop: String, to, dur: float, delay := 0.0, trans := Tween.TRANS_SINE, ease_ := Tween.EASE_IN_OUT) -> void:
	tracks.append({o = obj, p = prop, a = null, b = to, t0 = ct + delay, d = maxf(dur, 0.001), tr = trans, e = ease_})

func setv(obj: Object, prop: String, v) -> void:
	# cancel running tracks on that property, then set it
	tracks = tracks.filter(func(k): return not (k.o == obj and k.p == prop))
	obj.set_indexed(prop, v)

func _eval() -> void:
	var keep := []
	for k in tracks:
		if not is_instance_valid(k.o): continue
		if ct < k.t0: keep.append(k); continue
		if k.a == null: k.a = k.o.get_indexed(k.p)
		var el := minf(ct - k.t0, k.d)
		if k.a is float and k.b is int: k.b = float(k.b)
		k.o.set_indexed(k.p, Tween.interpolate_value(k.a, k.b - k.a, el, k.d, k.tr, k.e))
		if ct - k.t0 < k.d: keep.append(k)
	tracks = keep

func ffwd() -> bool:
	return seek > 0.0 or skipping

func wait(t: float) -> void:
	var end := ct + t
	while ct < end - 0.0001 and playing != "":
		if seek > 0.0:
			var d := minf(seek, end - ct); ct += d; seek -= d; _eval()
		else:
			await get_tree().process_frame

func line_len(id: String) -> float:
	var path := "res://audio/voice/%s.ogg" % id
	if ResourceLoader.exists(path): return (load(path) as AudioStream).get_length()
	return 0.8 + Snd.subtitle(id).length() * 0.065

## Start a voice line without waiting (not while fast-forwarding); returns its length.
func say_async(id: String) -> float:
	var l := line_len(id)
	if not ffwd(): Snd.voice(id, true)
	elif start_args.has("cut-hold") and Snd.subtitle(id) != "":
		_on_line(id, Snd.script_lines[id][0], Snd.subtitle(id)); sub_t = 999.0
	return l

## Play a voice line and wait for it plus a gap.
func say(id: String, gap := 0.45) -> void:
	var l := say_async(id)
	await wait(l + gap)

func fx(f: Callable) -> void:
	if not ffwd(): f.call()

# ---------------------------------------------------------------- camera language
func cut(pos: Vector3, look: Vector3, fov := -1.0) -> void:
	if start_args.has("cut-log"): print("[cut] %s t=%.1f" % [playing, ct])
	for p in ["cam_pos", "cam_look", "cam_roll", "orbit_a"]: setv(self, p, get(p))
	cam_pos = pos; cam_look = look; cam_roll = 0.0
	if fov > 0.0: setv(self, "cam_fov", fov)
	look_node = null; follow_node = null; orbit_on = false
	focus_node = null; setv(self, "focus_k", 1.0)
	_prev_vp = Projection.IDENTITY   # no motion blur smear across a cut

## Eased dolly / crane / push-in from the current framing.
func move(pos: Vector3, look: Vector3, dur: float, fov := -1.0, trans := Tween.TRANS_SINE, ease_ := Tween.EASE_IN_OUT) -> void:
	tw(self, "cam_pos", pos, dur, 0.0, trans, ease_); tw(self, "cam_look", look, dur, 0.0, trans, ease_)
	if fov > 0.0: tw(self, "cam_fov", fov, dur, 0.0, trans, ease_)

## Orbit around `c` (radius r, height h above c) from angle a0 to a1 (radians, 0 = +Z side).
func orbit(c: Vector3, r: float, h: float, a0: float, a1: float, dur: float, fov := -1.0, look_h := 0.0) -> void:
	cut(c + Vector3(sin(a0) * r, h, cos(a0) * r), c + Vector3(0, look_h, 0), fov)
	orbit_on = true; orbit_c = c; orbit_r = r; orbit_h = h; orbit_a = a0
	tw(self, "orbit_a", a1, dur, 0.0, Tween.TRANS_SINE, Tween.EASE_IN_OUT)

## Close-up focus: depth of field on, focused on the look point (or `d` metres).
func focus(amount := 1.0, d := -1.0, dur := 0.0) -> void:
	focus_d = d
	if dur <= 0.0: setv(self, "dof", amount)
	else: tw(self, "dof", amount, dur)

## Over-the-shoulder framing: camera behind `who`'s shoulder, looking at `at`.
func ots(who: Node3D, at: Vector3, side := 1.0, fov := 40.0, back := 1.5, up := 1.65) -> void:
	var p := who.global_position
	var d := (at - p); d.y = 0; d = d.normalized()
	var right := d.cross(Vector3.UP).normalized()
	cut(p - d * back + right * side * 0.55 + Vector3(0, up, 0), at, fov)

## Lens in millimetres (full-frame, vertical): 18 wide .. 35 normal .. 85 portrait .. 200 long.
func lens(mm: float, dur := 0.0) -> void:
	var f := rad_to_deg(2.0 * atan(12.0 / mm))
	if dur <= 0.0: setv(self, "cam_fov", f)
	else: tw(self, "cam_fov", f, dur)

## Keep focus on a node (+ offset); with dur > 0 it racks over from whatever was in focus.
func focus_on(n: Node3D, off := Vector3.ZERO, dur := 0.0, amount := -1.0) -> void:
	var cur_d := -1.0
	if cam and attrs and attrs.dof_blur_far_enabled: cur_d = attrs.dof_blur_far_distance - maxf(0.5, (attrs.dof_blur_far_distance) * 0.23)
	if cam and is_instance_valid(focus_node): cur_d = cam.global_position.distance_to(focus_node.global_position + focus_off)
	focus_node = n; focus_off = off; focus_prev_d = cur_d
	if amount >= 0.0: setv(self, "dof", amount)
	if dur > 0.0 and cur_d > 0.0:
		setv(self, "focus_k", 0.0); tw(self, "focus_k", 1.0, dur, 0.0, Tween.TRANS_CUBIC, Tween.EASE_IN_OUT)
	else:
		setv(self, "focus_k", 1.0)

## A head (or any point on an actor) as a focus / lighting target.
func head_of(a: Node3D) -> Node3D:
	if a and a.has_method("head_node"): return a.head_node()
	return a

## Scene score: cues from audio/music/intro/<cue>.ogg (crossfaded; "" fades the score out).
var score_players: Array = []
var score_cue := ""
func score(cue: String, fade := 1.0) -> void:
	if cue == score_cue: return
	score_cue = cue
	for p in score_players:
		if is_instance_valid(p):
			var tw_ := create_tween(); tw_.tween_property(p, "volume_db", -60.0, maxf(fade, 0.05)); tw_.tween_callback(p.queue_free)
	score_players = []
	if cue == "": return
	var path := "res://audio/music/%s/%s.ogg" % [playing, cue]
	if not ResourceLoader.exists(path): return
	Snd.set_track("", maxf(fade, 0.3))
	var p := AudioStreamPlayer.new(); p.bus = "Music"; p.stream = load(path); p.volume_db = -60.0 if fade > 0.0 else SCORE_DB
	add_child(p); p.play()
	if fade > 0.0: create_tween().tween_property(p, "volume_db", SCORE_DB, fade)
	score_players.append(p)
const SCORE_DB := -4.0

## Foley: audio/sfx/foley_<name>.ogg at a point (skipped when missing or fast-forwarding).
func foley(n: String, at: Vector3, db := 0.0) -> void:
	if ffwd(): return
	if ResourceLoader.exists("res://audio/sfx/foley_%s.ogg" % n): Snd.at("foley_" + n, at, db)

## Room tone: a looping bed (audio/sfx/foley_<name>.ogg) under the scene; "" fades it out.
var tone_player: AudioStreamPlayer
func room_tone(n: String, db := -14.0, fade := 1.5) -> void:
	if is_instance_valid(tone_player):
		var old := tone_player; var tw_ := create_tween(); tw_.tween_property(old, "volume_db", -60.0, fade); tw_.tween_callback(old.queue_free)
		tone_player = null
	var path := "res://audio/sfx/foley_%s.ogg" % n
	if n == "" or not ResourceLoader.exists(path): return
	var st: AudioStream = (load(path) as AudioStream).duplicate()
	if "loop" in st: st.loop = true
	tone_player = AudioStreamPlayer.new(); tone_player.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	tone_player.stream = st; tone_player.volume_db = -60.0; add_child(tone_player); tone_player.play()
	create_tween().tween_property(tone_player, "volume_db", db, fade)

## Mark a beat in the log (--cut-log): music and foley are timed from these.
func mark(n: String) -> void:
	if start_args.has("cut-log"): print("[mark] %s %.2f" % [n, ct])

func _process(dt: float) -> void:
	sub_t -= dt
	if sub_t <= 0.0: sub.modulate.a = maxf(0.0, sub.modulate.a - dt * 3.0)
	if playing == "": return
	if seek <= 0.0 and not (start_args.has("cut-hold") and start_args.get("cut", "") == playing):
		ct += dt
		_eval()
	_skip_input(dt)
	_acting(dt)
	_apply(dt)

func _skip_input(dt: float) -> void:
	if skipping or ct < 0.5: return
	var held := Input.is_action_pressed("jump") or Input.is_action_pressed("pause") or Input.is_action_pressed("ui_accept") \
		or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if held:
		skip_hold += dt; hint_a = 1.0
		if skip_hold >= SKIP_HOLD: _skip()
	else:
		skip_hold = maxf(0.0, skip_hold - dt * 2.0)
		hint_a = maxf(0.0, hint_a - dt * 0.35)

func _input(e: InputEvent) -> void:
	if playing == "" or e.is_echo(): return
	if e.is_action("jump") or e.is_action("pause") or e.is_action("ui_accept") or e is InputEventMouseButton:
		if e.is_pressed(): hint_a = 1.0
		get_viewport().set_input_as_handled()

## Speaker look-at and talk amounts.
func _acting(dt: float) -> void:
	var talking := Snd.voice_player != null and Snd.voice_player.playing and speaking != ""
	for who in cast:
		var a: Node3D = cast[who]
		if not is_instance_valid(a) or not ("talk" in a): continue
		var want := 1.0 if (talking and who == speaking) else 0.0
		a.talk = move_toward(a.talk, want, dt * 5.0)

func _apply(dt: float) -> void:
	if cam:
		var look := cam_look
		if is_instance_valid(look_node): look = look_node.global_position + look_off
		var pos := cam_pos
		if orbit_on: pos = orbit_c + Vector3(sin(orbit_a) * orbit_r, orbit_h, cos(orbit_a) * orbit_r)
		if is_instance_valid(follow_node): pos = follow_node.global_position + follow_off
		shake = maxf(0.0, shake - dt * 2.0)
		var tt := ct
		var off := Vector3(sin(tt * 0.7) * 0.03 + sin(tt * 1.9) * 0.012, sin(tt * 0.9) * 0.025, 0) * sway
		off += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * shake * 0.08
		cam.global_position = pos + off
		if not pos.is_equal_approx(look):
			var up := Vector3.UP if absf((look - pos).normalized().y) < 0.98 else Vector3.FORWARD
			cam.look_at(look + off * 0.5, up)
			if absf(cam_roll) > 0.0001: cam.rotate_object_local(Vector3(0, 0, 1), cam_roll)
			if hand > 0.001:   # handheld: slow drift plus a little operator jitter, in rotation
				var ht := ct * 1.0
				cam.rotate_object_local(Vector3.RIGHT, (_hn.get_noise_2d(ht * 40.0, 1.0) * 0.012 + _hn.get_noise_2d(ht * 160.0, 5.0) * 0.003) * hand)
				cam.rotate_object_local(Vector3.UP, (_hn.get_noise_2d(ht * 40.0, 9.0) * 0.014 + _hn.get_noise_2d(ht * 160.0, 13.0) * 0.003) * hand)
				cam.rotate_object_local(Vector3.BACK, _hn.get_noise_2d(ht * 30.0, 17.0) * 0.008 * hand)
		cam.fov = cam_fov
		_post_fx()
		_rig_update()
		if attrs:
			var fd := focus_d if focus_d > 0.0 else pos.distance_to(look)
			if is_instance_valid(focus_node):
				var nd := cam.global_position.distance_to(focus_node.global_position + focus_off)
				fd = lerpf(focus_prev_d, nd, focus_k) if focus_prev_d > 0.0 else nd
			var on := dof > 0.01
			attrs.dof_blur_far_enabled = on
			attrs.dof_blur_near_enabled = on and fd < 8.0
			attrs.dof_blur_far_distance = fd + maxf(0.5, fd * 0.3)
			attrs.dof_blur_far_transition = maxf(1.0, fd * 0.9)
			attrs.dof_blur_near_distance = fd * 0.55
			attrs.dof_blur_near_transition = fd * 0.4
			attrs.dof_blur_amount = 0.11 * dof
	_overlays()

func _overlays() -> void:
	black.color.a = fade
	(vignette.material as ShaderMaterial).set_shader_parameter("amount", 0.55 * clampf(bars, 0, 1))
	flash.color.a = white
	var vs := root_ui.size
	var h := vs.y * 0.105 * bars
	bar_top.position = Vector2.ZERO; bar_top.size = Vector2(vs.x, h)
	bar_bot.size = Vector2(vs.x, h); bar_bot.position = Vector2(0, vs.y - h)
	clock_label.modulate.a = clock_a; live_label.modulate.a = live_a * (0.6 + 0.4 * sin(ct * 6.0))
	call_box.modulate.a = call_a; call_box.queue_redraw()
	card_title.modulate.a = card_a; card_sub.modulate.a = card_a
	loc_box.modulate.a = loc_a; loc_box.position.x = 54 - (1.0 - loc_a) * 40.0
	boss_box.modulate.a = boss_a; boss_box.scale = Vector2.ONE * (1.0 + maxf(0.0, 1.0 - boss_a) * 0.4)
	boss_box.pivot_offset = boss_box.size * 0.5
	poster.modulate.a = poster_a; poster.scale = Vector2.ONE * (0.85 + poster_a * 0.15); poster.pivot_offset = poster.size * 0.5
	next_box.modulate.a = next_a; next_box.queue_redraw()
	if poster_a > 0.01: poster.queue_redraw()
	skip_hint.modulate.a = clampf(bars, 0, 1) * (0.35 + 0.65 * hint_a) if playing != "" and not skipping else 0.0
	skip_bar.size.x = 150.0 * clampf(skip_hold / SKIP_HOLD, 0, 1); skip_bar.modulate.a = skip_hint.modulate.a

func _skip() -> void:
	if skipping: return
	skipping = true
	Snd.voice_queue.clear()
	if Snd.voice_player: Snd.voice_player.stop()
	sub.modulate.a = 0.0
	var t := create_tween(); t.tween_property(self, "fade", 1.0, 0.25)
	await t.finished
	seek = 1e6

# ---------------------------------------------------------------- start / end
func _run(id: String) -> void:
	playing = id; ct = 0.0; skipping = false; tracks.clear(); skip_hold = 0.0; hint_a = 0.0
	seek = float(start_args.get("cut-t", 0.0)) if start_args.get("cut", "") == id else 0.0
	if start_args.has("cut-fast"): seek = 1e6   # flow tests: run every scene instantly
	Game.input_locked = true
	await get_tree().process_frame   # story is still between emitting cutscene_started and awaiting the finish
	if id != "intro" and seek <= 0.0:
		# letterbox in and dip to black from gameplay before the scene is set up
		fade = 0.0; bars = 0.0
		var ft := create_tween().set_parallel()
		ft.tween_property(self, "fade", 1.0, 0.7); ft.tween_property(self, "bars", 1.0, 0.7)
		while ft.is_running():
			_overlays_only(); await get_tree().process_frame
	if Game.hud: hud_was = Game.hud.visible; Game.hud.visible = false
	if Game.player:
		Game.player.process_mode = Node.PROCESS_MODE_DISABLED
		Game.player.visible = false
	cam = Camera3D.new(); cam.name = "CutsceneCam"; cam.far = 2500; cam.near = 0.05
	attrs = _make_attrs()
	cam.attributes = attrs
	Game.main.add_child(cam)
	cam.current = true
	_hn.seed = 7; _hn.frequency = 0.01; _hn.fractal_octaves = 2
	hand = 0.0; mblur = 0.6; focus_node = null; focus_k = 1.0
	_add_post()
	cam_fov = 50.0; sway = 1.0; fade = 1.0; bars = 1.0; dof = 0.0; focus_d = -1.0; cam_roll = 0.0
	orbit_on = false; look_node = null; follow_node = null; auto_look = true; cast.clear(); speaking = ""
	_apply(0.0)
	Snd.music("cutscene", 2.0)
	scene = load(SCENES[id]).new()
	scene.C = self
	await scene.run()
	await _finish(id)

## Camera attributes for the cutscene camera: keep the world's exposure settings, add depth of field.
func _make_attrs() -> CameraAttributesPractical:
	var a := CameraAttributesPractical.new()
	var we := Game.main.find_child("WorldEnvironment", true, false) as WorldEnvironment
	if we == null:
		for c in Game.main.get_children(): if c is WorldEnvironment: we = c
	if we and we.camera_attributes is CameraAttributesPractical:
		a = (we.camera_attributes as CameraAttributesPractical).duplicate()
	var gc: Camera3D = Game.cam.camera if Game.cam and "camera" in Game.cam else null
	if gc and gc.attributes is CameraAttributesPractical: a = (gc.attributes as CameraAttributesPractical).duplicate()
	a.dof_blur_far_enabled = false; a.dof_blur_near_enabled = false
	return a

func _finish(id: String) -> void:
	var was_skip := skipping
	print("[cutscene] %s finished at t=%.1f%s" % [id, ct, " (skipped)" if was_skip else ""])
	seek = 0.0; skipping = false
	tracks.clear()
	if scene and scene.has_method("cleanup"): scene.cleanup()
	scene = null
	for a in actors: if is_instance_valid(a): a.queue_free()
	actors.clear(); vesk = null; dodger = null; grudd = null; cast.clear()
	light_off(); grade(""); score("", 1.5); room_tone("")
	if is_instance_valid(_post): _post.queue_free()
	_post = null
	clock_a = 0; live_a = 0; call_a = 0; card_a = 0; loc_a = 0; boss_a = 0; poster_a = 0; next_a = 0; white = 0
	if sun and sun_energy >= 0.0: sun.light_energy = sun_energy
	sun_energy = -1.0
	if Game.player:
		Game.player.visible = true
		Game.player.process_mode = Node.PROCESS_MODE_INHERIT
		Game.player.velocity = Vector3.ZERO
	if Game.hud: Game.hud.visible = hud_was
	Game.input_locked = false
	if id != "crane_intro": Snd.music("skyharbor", 2.5)
	Snd.loop("wind_loop", true, -16)
	playing = ""
	Game.cutscene_finished.emit(id)
	if start_args.has("cut-quit") and start_args.get("cut", "") == id:   # preview renders (Movie Maker) stop here
		get_tree().create_timer(2.0).timeout.connect(get_tree().quit)
	# ease from the cutscene camera into the gameplay camera, open the letterbox, fade in
	var game_cam: Camera3D = Game.cam.camera if Game.cam and "camera" in Game.cam else null
	var oc := cam
	var oa := attrs
	var from := oc.global_transform
	var from_fov := oc.fov
	var from_dof := dof
	var t := 0.0
	var dur := 0.4 if was_skip else 1.3
	while t < dur and playing == "":
		await get_tree().process_frame
		var dt := get_process_delta_time()
		t += dt
		var u := smoothstep(0.0, 1.0, t / dur)
		if game_cam:
			oc.global_transform = from.interpolate_with(game_cam.global_transform, u)
			oc.fov = lerpf(from_fov, game_cam.fov, u)
		if oa: oa.dof_blur_amount = 0.11 * from_dof * (1.0 - u)
		fade = move_toward(fade, 0.0, dt * 2.5)
		bars = 1.0 - u
		_overlays_only()
	if playing == "":
		bars = 0.0; fade = 0.0; _overlays_only()
		if game_cam: game_cam.current = true
	oc.queue_free()
	if cam == oc: cam = null; attrs = null

func _overlays_only() -> void:
	black.color.a = fade
	(vignette.material as ShaderMaterial).set_shader_parameter("amount", 0.55 * clampf(bars, 0, 1))
	flash.color.a = 0.0
	var vs := root_ui.size
	var h := vs.y * 0.105 * bars
	bar_top.size = Vector2(vs.x, h); bar_bot.size = Vector2(vs.x, h); bar_bot.position.y = vs.y - h
	skip_hint.modulate.a = 0.0; skip_bar.modulate.a = 0.0
	for c in [clock_label, live_label, call_box, card_title, card_sub, loc_box, boss_box, poster, next_box]: c.modulate.a = 0.0

# ---------------------------------------------------------------- helpers for the scenes
func spot(name_: String, def: Vector3) -> Vector3:
	var v = Game.level.get(name_) if Game.level else null
	return v if v is Vector3 else def

func island_center(name_: String, def: Vector3) -> Vector3:
	if Game.level and "islands" in Game.level and Game.level.islands.has(name_):
		var r: Rect2 = Game.level.islands[name_]
		var y: float = Game.level.heights.get(name_, def.y) if "heights" in Game.level else def.y
		return Vector3(r.get_center().x, y, r.get_center().y)
	return def

func island_rect(name_: String, def: Rect2) -> Rect2:
	if Game.level and "islands" in Game.level and Game.level.islands.has(name_): return Game.level.islands[name_]
	return def

func actor(n: Node3D, pos: Vector3, yaw := 0.0, keep := false) -> Node3D:
	Game.main.add_child(n); n.global_position = pos; n.rotation.y = yaw
	if keep: keep_props.append(n)
	else: actors.append(n)
	return n

func make_vesk(pos: Vector3, yaw := PI) -> Node3D:
	vesk = actor(VeskActor.new(), pos, yaw); cast["vesk"] = vesk; return vesk

func make_dodger(pos: Vector3, yaw := PI) -> Node3D:
	dodger = actor(CutsceneDodger.new(), pos, yaw); cast["dodger"] = dodger; return dodger

func make_grudd(pos: Vector3, yaw := 0.0, height := 3.6, holo := false) -> Node3D:
	var g := GruddActor.new(); g.height = height; g.holo = holo
	grudd = actor(g, pos, yaw); cast["grudd"] = grudd; return grudd

func model(path: String) -> Node3D:
	var n := Node3D.new()
	if ResourceLoader.exists(path): n.add_child(load(path).instantiate())
	return n

## Walk an actor to a spot (run anim, facing the way it goes), then idle.
func walk(a: Node3D, to: Vector3, speed := 3.2, anim := "run") -> float:
	var from := a.global_position
	var d := Vector2(to.x - from.x, to.z - from.z)
	var dur := maxf(0.2, from.distance_to(to) / speed)
	if d.length() > 0.05: setv(a, "rotation:y", atan2(d.x, d.y))
	if a.has_method("play"): a.play(anim, 0.2, clampf(speed / 6.0, 0.5, 1.4))
	tw(a, "global_position", to, dur, 0.0, Tween.TRANS_LINEAR)
	return dur

func face_to(a: Node3D, target: Vector3) -> float:
	var d := target - a.global_position
	return atan2(d.x, d.z)

## Turn an actor to face a point over `dur` seconds (shortest way round).
func turn_to(a: Node3D, target: Vector3, dur := 0.4) -> void:
	var y := face_to(a, target)
	var cur := a.rotation.y
	tw(a, "rotation:y", cur + angle_difference(cur, y), dur)

## Who looks at whom: every cast member looks at `who` (except `who`, who looks at `at` if given).
func all_look(who: String, at: Node3D = null) -> void:
	for k in cast:
		var a: Node3D = cast[k]
		if not is_instance_valid(a) or not ("look_target" in a): continue
		if k == who: a.look_target = at
		elif cast.has(who): a.look_target = cast[who]

## Dim the sun for the indoor stinger (restored when the cutscene ends).
func sun_dim(on: bool) -> void:
	if sun == null:
		for c in Game.main.find_children("*", "DirectionalLight3D", true, false): sun = c; break
	if sun == null: return
	if on:
		if sun_energy < 0.0: sun_energy = sun.light_energy
		sun.light_energy = 0.0
	elif sun_energy >= 0.0:
		sun.light_energy = sun_energy

# ---------------------------------------------------------------- UI
func _on_line(id: String, sp: String, text: String) -> void:
	if playing == "": return
	speaking = sp
	if cast.has(sp) and is_instance_valid(cast[sp]) and cast[sp].has_method("lip"): cast[sp].lip(id)
	if auto_look and cast.has(sp): all_look(sp, cast[sp].look_target if "look_target" in cast[sp] else null)
	var who: String = SPEAKER_NAMES.get(sp, sp.to_upper())
	var col: Color = SPEAKER_COLORS.get(sp, Color.WHITE)
	var body := text.replace("[", "(").replace("]", ")")
	if who != "": sub_rt.text = "[color=#%s]%s[/color]   %s" % [col.to_html(false), who, body]
	else: sub_rt.text = "[i]%s[/i]" % body
	sub.modulate.a = 1.0; sub_t = maxf(1.5, line_len(id) + 0.2)

func _label(size: int, color: Color, heavy := false) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font_heavy if heavy else font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 8)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _ctl() -> Control:
	var c := Control.new(); c.mouse_filter = Control.MOUSE_FILTER_IGNORE; return c

func _build_ui() -> void:
	font = SystemFont.new(); font.font_names = PackedStringArray(["Inter", "Segoe UI", "Arial", "sans-serif"]); font.font_weight = 600
	font_heavy = SystemFont.new(); font_heavy.font_names = PackedStringArray(["Impact", "Arial Black", "Segoe UI Black", "Inter", "sans-serif"]); font_heavy.font_weight = 900
	layer = CanvasLayer.new(); layer.layer = 60; add_child(layer)
	root_ui = _ctl(); root_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root_ui)
	black = ColorRect.new(); black.color = Color(0, 0, 0, 0); black.set_anchors_preset(Control.PRESET_FULL_RECT); black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash = ColorRect.new(); flash.color = Color(1, 0.95, 0.85, 0); flash.set_anchors_preset(Control.PRESET_FULL_RECT); flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_top = ColorRect.new(); bar_top.color = Color.BLACK; bar_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_bot = ColorRect.new(); bar_bot.color = Color.BLACK; bar_bot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# soft cinematic vignette while the letterbox is up
	vignette = ColorRect.new(); vignette.set_anchors_preset(Control.PRESET_FULL_RECT); vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vs := Shader.new()
	vs.code = "shader_type canvas_item;\nuniform float amount = 0.0;\nvoid fragment() {\n\tvec2 d = (UV - 0.5) * vec2(1.25, 1.0);\n\tfloat v = smoothstep(0.35, 0.95, length(d));\n\tCOLOR = vec4(0.02, 0.01, 0.03, v * amount);\n}\n"
	var vm := ShaderMaterial.new(); vm.shader = vs; vignette.material = vm
	root_ui.add_child(vignette)
	root_ui.add_child(flash)
	root_ui.add_child(bar_top); root_ui.add_child(bar_bot)
	# subtitles: centred in the lower letterbox bar, speaker name in their colour
	sub = _ctl()
	sub.anchor_left = 0.5; sub.anchor_right = 0.5; sub.anchor_top = 1.0; sub.anchor_bottom = 1.0
	sub.offset_left = -620; sub.offset_right = 620; sub.offset_top = -92; sub.offset_bottom = -8
	sub.modulate.a = 0.0
	root_ui.add_child(sub)
	sub_rt = RichTextLabel.new(); sub_rt.bbcode_enabled = true; sub_rt.scroll_active = false; sub_rt.fit_content = false
	sub_rt.set_anchors_preset(Control.PRESET_FULL_RECT); sub_rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub_rt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; sub_rt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sub_rt.add_theme_font_override("normal_font", font)
	var fi := SystemFont.new(); fi.font_names = font.font_names; fi.font_weight = 500; fi.font_italic = true
	sub_rt.add_theme_font_override("italics_font", fi)
	sub_rt.add_theme_font_size_override("normal_font_size", 27); sub_rt.add_theme_font_size_override("italics_font_size", 27)
	sub_rt.add_theme_color_override("default_color", Color(0.96, 0.95, 0.9))
	sub_rt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95)); sub_rt.add_theme_constant_override("outline_size", 6)
	sub.add_child(sub_rt)
	# skip prompt + hold bar
	skip_hint = _label(16, Color(1, 1, 1))
	skip_hint.text = "HOLD  JUMP / ESC / CLICK  TO SKIP"
	skip_hint.set_anchors_preset(Control.PRESET_TOP_RIGHT); skip_hint.position = Vector2(-300, 30); skip_hint.size = Vector2(270, 24)
	skip_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; skip_hint.modulate.a = 0.0
	root_ui.add_child(skip_hint)
	skip_bar = ColorRect.new(); skip_bar.color = Color(1, 0.75, 0.3); skip_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	skip_bar.set_anchors_preset(Control.PRESET_TOP_RIGHT); skip_bar.position = Vector2(-180, 58); skip_bar.size = Vector2(0, 4)
	root_ui.add_child(skip_bar)
	clock_label = _label(24, Color(1, 0.85, 0.5))
	clock_label.position = Vector2(54, 30); clock_label.modulate.a = 0.0
	root_ui.add_child(clock_label)
	live_label = _label(20, Color(1, 0.3, 0.25))
	live_label.position = Vector2(54, 30); live_label.modulate.a = 0.0
	root_ui.add_child(live_label)
	call_box = _ctl(); call_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	call_box.position = Vector2(-380, 120); call_box.size = Vector2(350, 110); call_box.modulate.a = 0.0
	call_box.draw.connect(_draw_call)
	root_ui.add_child(call_box)
	call_text = _label(20, Color(0.8, 1, 0.75))
	call_text.position = Vector2(118, 22); call_text.size = Vector2(220, 70)
	call_box.add_child(call_text)
	# location card (lower left, above the bar)
	loc_box = _ctl(); loc_box.anchor_top = 1.0; loc_box.anchor_bottom = 1.0
	loc_box.position = Vector2(54, -230); loc_box.size = Vector2(700, 110); loc_box.modulate.a = 0.0
	loc_box.draw.connect(func(): loc_box.draw_rect(Rect2(0, 8, 6, 84), Color(1, 0.7, 0.3)))
	root_ui.add_child(loc_box)
	loc_title = _label(64, Color(1, 0.9, 0.7), true); loc_title.position = Vector2(22, -4); loc_box.add_child(loc_title)
	loc_sub = _label(22, Color(1, 1, 1, 0.9)); loc_sub.position = Vector2(26, 70); loc_box.add_child(loc_sub)
	# boss name card (centre-left, slams in)
	boss_box = _ctl(); boss_box.anchor_top = 0.5; boss_box.anchor_bottom = 0.5
	boss_box.position = Vector2(90, -60); boss_box.size = Vector2(900, 150); boss_box.modulate.a = 0.0
	boss_box.draw.connect(_draw_boss)
	root_ui.add_child(boss_box)
	boss_title = _label(96, Color(1, 0.82, 0.2), true); boss_title.position = Vector2(20, -10); boss_box.add_child(boss_title)
	boss_sub = _label(24, Color(1, 1, 1)); boss_sub.position = Vector2(26, 108); boss_box.add_child(boss_sub)
	# "NOW HIRING" poster and the next-time bumper are drawn
	poster = _ctl(); poster.set_anchors_preset(Control.PRESET_CENTER); poster.position = Vector2(-260, -340); poster.size = Vector2(520, 680)
	poster.modulate.a = 0.0; poster.draw.connect(_draw_poster); root_ui.add_child(poster)
	next_box = _ctl(); next_box.set_anchors_preset(Control.PRESET_FULL_RECT); next_box.modulate.a = 0.0
	next_box.draw.connect(_draw_next); root_ui.add_child(next_box)
	card_title = _label(58, Color(1, 0.85, 0.35), true); card_sub = _label(24, Color(1, 1, 1))
	root_ui.add_child(black)
	for l in [card_title, card_sub]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; l.modulate.a = 0.0; root_ui.add_child(l)
		l.anchor_left = 0.5; l.anchor_right = 0.5; l.anchor_top = 0.5; l.anchor_bottom = 0.5
		l.offset_left = -700; l.offset_right = 700
	card_title.offset_top = -70; card_title.offset_bottom = 10
	card_sub.offset_top = 10; card_sub.offset_bottom = 50
	# the bumper sits above the black so it can play over a blacked-out frame
	next_box.move_to_front(); poster.move_to_front(); card_title.move_to_front(); card_sub.move_to_front()
	sub.move_to_front(); skip_hint.move_to_front(); skip_bar.move_to_front()

func show_location(title: String, subtitle: String, hold := 4.0) -> void:
	loc_title.text = title; loc_sub.text = subtitle
	tw(self, "loc_a", 1.0, 0.8, 0.0, Tween.TRANS_CUBIC, Tween.EASE_OUT)
	tw(self, "loc_a", 0.0, 0.8, hold)

func show_boss(title: String, subtitle: String, hold := 3.2) -> void:
	boss_title.text = title; boss_sub.text = subtitle
	tw(self, "boss_a", 1.0, 0.18, 0.0, Tween.TRANS_QUAD, Tween.EASE_OUT)
	tw(self, "boss_a", 0.0, 0.6, hold)

func _draw_boss() -> void:
	var b := boss_box
	var w := 640.0 * clampf(boss_a * 1.4, 0, 1)
	b.draw_rect(Rect2(0, 96, w, 6), Color(1, 0.82, 0.2))
	for i in 8: b.draw_rect(Rect2(w - 20 - i * 26, 104, 14, 4), Color(0.1, 0.1, 0.1, 0.8))

func _draw_poster() -> void:
	var p := poster
	var s := p.size
	p.draw_rect(Rect2(Vector2(8, 10), s), Color(0, 0, 0, 0.4))
	p.draw_rect(Rect2(Vector2.ZERO, s), Color(0.96, 0.9, 0.72))
	p.draw_rect(Rect2(Vector2(14, 14), s - Vector2(28, 28)), Color(0.75, 0.2, 0.12), false, 6)
	p.draw_rect(Rect2(28, 28, s.x - 56, 120), Color(0.75, 0.2, 0.12))
	var f := font_heavy
	p.draw_string(f, Vector2(28, 118), "NOW HIRING", HORIZONTAL_ALIGNMENT_CENTER, s.x - 56, 86, Color(0.98, 0.92, 0.75))
	# a silhouette: a stocky mechanic with a big question mark
	var c := Vector2(s.x * 0.5, 330)
	p.draw_circle(c + Vector2(0, -60), 54, Color(0.2, 0.18, 0.2))
	p.draw_rect(Rect2(c.x - 90, c.y - 10, 180, 150), Color(0.2, 0.18, 0.2))
	p.draw_string(f, Vector2(0, c.y - 30), "?", HORIZONTAL_ALIGNMENT_CENTER, s.x, 120, Color(1, 0.8, 0.3))
	p.draw_string(f, Vector2(28, 540), "ONE MECHANIC", HORIZONTAL_ALIGNMENT_CENTER, s.x - 56, 52, Color(0.2, 0.15, 0.12))
	p.draw_string(font, Vector2(28, 590), "You know who you are.", HORIZONTAL_ALIGNMENT_CENTER, s.x - 56, 30, Color(0.3, 0.22, 0.18))
	p.draw_string(font, Vector2(28, 636), "Apply at the Great Works. Hard hat required.", HORIZONTAL_ALIGNMENT_CENTER, s.x - 56, 18, Color(0.35, 0.25, 0.2))

## "Next time" bumper: a starfield and a turning desert planet, drawn.
func _draw_next() -> void:
	if next_a <= 0.01: return
	var b := next_box
	var s := b.size
	b.draw_rect(Rect2(Vector2.ZERO, s), Color(0.03, 0.02, 0.07))
	var rng := RandomNumberGenerator.new(); rng.seed = 7
	for i in 160:
		var p := Vector2(rng.randf() * s.x, rng.randf() * s.y)
		p.x = fposmod(p.x - ct * (6.0 + rng.randf() * 18.0), s.x)
		b.draw_circle(p, rng.randf_range(0.8, 2.2), Color(1, 0.95, 0.85, rng.randf_range(0.3, 0.9)))
	var c := Vector2(s.x * 0.66, s.y * 0.5)
	var r := s.y * 0.3
	b.draw_circle(c, r * 1.12, Color(1, 0.6, 0.25, 0.12))
	b.draw_circle(c, r * 1.05, Color(1, 0.65, 0.3, 0.18))
	b.draw_circle(c, r, Color(0.86, 0.55, 0.28))
	# canyon bands that slide across as it turns
	for i in 9:
		var y := -r + (i + 0.5) * (2.0 * r / 9.0)
		var half := sqrt(maxf(0.0, r * r - y * y))
		var col := Color(0.7, 0.4, 0.2) if i % 2 == 0 else Color(0.94, 0.68, 0.38)
		var off := fposmod(ct * 18.0 + i * 37.0, half * 2.0 + 1.0)
		b.draw_line(c + Vector2(-half + off * 0.3, y), c + Vector2(minf(half, -half + off), y), col, 2.0 * r / 9.0 * 0.45)
	for k in 5:
		var a := k * 1.3 + ct * 0.15
		var p := c + Vector2(cos(a) * r * 0.55, sin(a * 1.7) * r * 0.45)
		if p.distance_to(c) < r * 0.9: b.draw_circle(p, r * 0.06, Color(0.55, 0.3, 0.15))
	# terminator shadow
	for i in 18: b.draw_arc(c + Vector2(r * 0.25, 0), r * (0.95 - i * 0.012) + i * 0.3, -PI * 0.5, PI * 0.5, 48, Color(0.02, 0.01, 0.05, 0.05), r * 0.12)
	var f := font_heavy
	b.draw_string(f, Vector2(s.x * 0.08, s.y * 0.38), "NEXT TIME", HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color(1, 0.8, 0.4))
	b.draw_string(f, Vector2(s.x * 0.08, s.y * 0.5), "DUSTVEIN GULCH", HORIZONTAL_ALIGNMENT_LEFT, -1, 84, Color(1, 0.93, 0.8))
	b.draw_string(font, Vector2(s.x * 0.08, s.y * 0.57), "Sand. Scrap pirates. Absolutely no retirement.", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(1, 1, 1, 0.85))

## Nana Quill's call card: a little portrait (antenna-covered shell, round glasses) and the text.
func _draw_call() -> void:
	var b := call_box
	var panel := StyleBoxFlat.new(); panel.bg_color = Color(0.03, 0.08, 0.06, 0.82); panel.set_corner_radius_all(10)
	panel.border_color = Color(0.5, 1, 0.55, 0.8); panel.set_border_width_all(2)
	b.draw_style_box(panel, Rect2(Vector2.ZERO, b.size))
	var o := Vector2(56, 58)
	var green := Color(0.45, 0.75, 0.4)
	for i in 5:
		var a := -PI * 0.85 + i * PI * 0.17
		var p := o + Vector2(cos(a), sin(a)) * 30
		var tip := o + Vector2(cos(a), sin(a)) * (44 + (i % 2) * 6)
		b.draw_line(p, tip, Color(0.8, 0.8, 0.7), 2)
		b.draw_circle(tip, 3, Color(1, 0.45, 0.2) if int(ct * 3 + i) % 2 == 0 else Color(0.6, 1, 0.5))
	b.draw_circle(o + Vector2(0, 4), 32, green)
	for i in 3: b.draw_arc(o + Vector2(0, 4), 12 + i * 9, PI, TAU, 16, Color(0.3, 0.55, 0.3), 2)
	var f := o + Vector2(0, 14)
	b.draw_circle(f, 19, Color(0.78, 0.8, 0.6))
	for sx in [-8, 8]:
		b.draw_arc(f + Vector2(sx, -3), 6, 0, TAU, 16, Color(0.2, 0.2, 0.2), 2)
		b.draw_circle(f + Vector2(sx, -3), 2, Color(0.15, 0.15, 0.15))
	b.draw_line(f + Vector2(-2, -3), f + Vector2(2, -3), Color(0.2, 0.2, 0.2), 2)
	var talking := speaking == "nana" and Snd.voice_player != null and Snd.voice_player.playing
	var mo := 3.0 + (absf(sin(ct * 14.0)) * 4.0 if talking else 0.0)
	b.draw_arc(f + Vector2(0, 6), 6, 0.3, PI - 0.3, 10, Color(0.35, 0.2, 0.15), 2)
	if talking: b.draw_circle(f + Vector2(0, 9), mo * 0.5, Color(0.35, 0.15, 0.12))
	for i in 4:
		var h := 6.0 + i * 5.0
		var on := (int(ct * 4.0) % 5) > i
		b.draw_rect(Rect2(Vector2(300 + i * 9, 96 - h), Vector2(6, h)), Color(0.5, 1, 0.55, 0.9 if on else 0.25))

# ---------------------------------------------------------------- lens post, lighting rig, grade
func _add_post() -> void:
	_post = MeshInstance3D.new(); _post.name = "CutscenePost"
	var q := QuadMesh.new(); q.size = Vector2(1, 1); _post.mesh = q
	_post_mat = ShaderMaterial.new(); _post_mat.shader = load("res://shaders/cutscene_post.gdshader")
	_post.material_override = _post_mat
	_post.extra_cull_margin = 16384.0; _post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_post.position = Vector3(0, 0, -0.2)
	cam.add_child(_post)
	_prev_vp = Projection.IDENTITY

func _post_fx() -> void:
	if not is_instance_valid(_post) or _post_mat == null: return
	var cur := Projection(cam.global_transform.affine_inverse())
	var valid := _prev_vp != Projection.IDENTITY and not ffwd()
	_post_mat.set_shader_parameter("prev_view", _prev_vp if valid else cur)
	_post_mat.set_shader_parameter("blur", mblur if valid else 0.0)
	_prev_vp = cur

const RIGS := {
	# key (warm sun side), rim (back light), fill (sky side); energies for SpotLight3D / OmniLight3D
	"golden": {"key": Color(1.0, 0.8, 0.58), "key_e": 3.0, "rim": Color(1.0, 0.68, 0.38), "rim_e": 9.0, "fill": Color(0.55, 0.66, 0.9), "fill_e": 0.6, "elev": 0.45},
	"soft": {"key": Color(1.0, 0.86, 0.7), "key_e": 2.0, "rim": Color(1.0, 0.75, 0.5), "rim_e": 5.0, "fill": Color(0.6, 0.7, 0.9), "fill_e": 0.8, "elev": 0.35},
	"tension": {"key": Color(0.85, 0.85, 1.0), "key_e": 1.8, "rim": Color(1.0, 0.45, 0.12), "rim_e": 12.0, "fill": Color(0.4, 0.5, 0.8), "fill_e": 0.4, "elev": 0.6},
	"angry": {"key": Color(1.0, 0.72, 0.5), "key_e": 2.6, "rim": Color(1.0, 0.35, 0.1), "rim_e": 16.0, "fill": Color(0.45, 0.5, 0.75), "fill_e": 0.3, "elev": -0.15},
	"hero": {"key": Color(1.0, 0.82, 0.6), "key_e": 3.4, "rim": Color(1.0, 0.6, 0.25), "rim_e": 18.0, "fill": Color(0.5, 0.65, 1.0), "fill_e": 0.7, "elev": 0.2},
}

## Per-shot three-point light on a subject (placed from the camera each frame, like a set crew would):
## key from the `side` (+1 camera right), rim from behind on the other side, cool fill from the front.
func light(subject: Node3D, preset := "golden", side := 1.0, h := 1.45) -> void:
	rig_subject = subject; rig_side = side; rig_h = h; rig_preset = preset
	if rig_lights.is_empty():
		var key := SpotLight3D.new(); key.name = "CsKey"; key.shadow_enabled = true; key.spot_range = 7.0; key.spot_angle = 32.0
		key.spot_angle_attenuation = 0.8; key.shadow_blur = 2.0; key.light_size = 0.25
		var rim := SpotLight3D.new(); rim.name = "CsRim"; rim.shadow_enabled = false; rim.spot_range = 6.0; rim.spot_angle = 28.0; rim.light_specular = 1.0
		var fill := OmniLight3D.new(); fill.name = "CsFill"; fill.shadow_enabled = false; fill.omni_range = 5.0; fill.light_specular = 0.15
		for l in [key, rim, fill]: l.light_volumetric_fog_energy = 0.0; Game.main.add_child(l)
		rig_lights = [key, rim, fill]
	var r: Dictionary = RIGS.get(preset, RIGS.golden)
	var key: SpotLight3D = rig_lights[0]; var rim: SpotLight3D = rig_lights[1]; var fill: OmniLight3D = rig_lights[2]
	key.light_color = r.key; rim.light_color = r.rim; fill.light_color = r.fill
	tw(key, "light_energy", r.key_e, 0.4); tw(rim, "light_energy", r.rim_e, 0.4); tw(fill, "light_energy", r.fill_e, 0.4)
	for l in rig_lights: l.visible = true
	_rig_update()

func light_off() -> void:
	for l in rig_lights: if is_instance_valid(l): l.queue_free()
	rig_lights = []; rig_subject = null

func _rig_update() -> void:
	if rig_lights.is_empty() or not is_instance_valid(rig_subject) or cam == null: return
	var c: Vector3 = rig_subject.global_position + (Vector3.ZERO if rig_subject.name == "Eyes" else Vector3(0, rig_h, 0))
	var to_cam := cam.global_position - c; to_cam.y = 0
	if to_cam.length() < 0.01: to_cam = Vector3.BACK
	to_cam = to_cam.normalized()
	var r: Dictionary = RIGS.get(rig_preset, RIGS.golden)
	var kd := to_cam.rotated(Vector3.UP, deg_to_rad(55.0) * rig_side) + Vector3(0, r.elev, 0)
	var rd := (-to_cam).rotated(Vector3.UP, -deg_to_rad(40.0) * rig_side) + Vector3(0, 0.55, 0)
	var fd := to_cam.rotated(Vector3.UP, -deg_to_rad(35.0) * rig_side) + Vector3(0, 0.1, 0)
	var key: SpotLight3D = rig_lights[0]; var rim: SpotLight3D = rig_lights[1]; var fill: OmniLight3D = rig_lights[2]
	key.global_position = c + kd.normalized() * 2.6; key.look_at(c, Vector3.UP)
	rim.global_position = c + rd.normalized() * 2.2; rim.look_at(c, Vector3.UP)
	fill.global_position = c + fd.normalized() * 1.8

const GRADES := {
	"golden": {"adjustment_saturation": 1.24, "adjustment_contrast": 1.12, "tonemap_exposure": 0.95, "volumetric_fog_density": 0.006, "glow_intensity": 0.95},
	"porch": {"adjustment_saturation": 1.2, "adjustment_contrast": 1.1, "tonemap_exposure": 0.92, "volumetric_fog_density": 0.012, "glow_intensity": 1.0},
	"tension": {"adjustment_saturation": 0.88, "adjustment_contrast": 1.22, "tonemap_exposure": 0.82, "volumetric_fog_density": 0.014, "glow_intensity": 1.1},
	"chaos": {"adjustment_saturation": 1.32, "adjustment_contrast": 1.24, "tonemap_exposure": 0.92, "volumetric_fog_density": 0.01, "glow_intensity": 1.2},
	"hero": {"adjustment_saturation": 1.28, "adjustment_contrast": 1.18, "tonemap_exposure": 0.98, "volumetric_fog_density": 0.009, "glow_intensity": 1.15},
}

## Scene colour grade and atmosphere (the world Environment, put back when the cutscene ends).
func grade(n: String, dur := 1.2) -> void:
	var env: Environment = Game.main.get("env") if Game.main else null
	if env == null: return
	if n == "":
		for k in env_saved: env.set(k, env_saved[k])
		env_saved = {}; grade_name = ""; return
	var g: Dictionary = GRADES.get(n, {})
	for k in g:
		if not env_saved.has(k): env_saved[k] = env.get(k)
		if dur <= 0.0 or ffwd(): setv(env, k, g[k])
		else: tw(env, k, g[k], dur)
	grade_name = n
