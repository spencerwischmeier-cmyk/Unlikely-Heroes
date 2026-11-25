extends Node
## Animated in-engine cutscenes for Skyharbor (planet 1): camera moves, Vesk and Dodger actors, props,
## letterbox bars and subtitles, all on one cutscene clock so they can be skipped or fast-forwarded.
##   intro: Vesk's porch at dawn, the 8:00:00 signal, the coffee maker clocks in, a roller eats his
##          chair, Dodger zooms off and crashes on the scrap pile (where the level picks him up).
##   outro: after the Crane Bot. Grudd's first radio broadcast (Dodger's eye flickers orange),
##          Nana Quill radios the coordinates, liftoff.
## Story emits Game.cutscene_started(id) and waits for Game.cutscene_finished(id).
## Skip: Jump or Esc. Debug: --cut=intro|outro plays one at start (pair with --no-bots),
##   --cut-t=<seconds> fast-forwards into it, --cut-hold freezes it there (screenshots),
##   --no-cutscenes finishes them at once.

const M := preload("res://scripts/mats.gd")
const VeskActor := preload("res://scripts/cutscene/vesk_actor.gd")
const DroneActor := preload("res://scripts/cutscene/drone_actor.gd")

const SPEAKER_NAMES := {"vesk": "VESK", "dodger": "DODGER", "grudd": "FOREMAN GRUDD", "gizmart": "GIZMART", "nana": "NANA QUILL", "narrator": ""}
const SPEAKER_COLORS := {"vesk": Color(1, 0.62, 0.25), "dodger": Color(0.5, 0.9, 1), "grudd": Color(1, 0.35, 0.3),
	"gizmart": Color(0.6, 1, 0.5), "nana": Color(0.75, 1, 0.7), "narrator": Color(1, 1, 1)}

var playing := ""
var ct := 0.0            # cutscene clock (seconds)
var seek := 0.0          # seconds still to fast-forward
var skipping := false
var tracks: Array = []
var actors: Array = []   # nodes freed when the cutscene ends
var keep_props: Array = []

# camera state (tracked)
var cam: Camera3D
var cam_pos := Vector3.ZERO
var cam_look := Vector3.ZERO
var cam_fov := 50.0
var sway := 1.0
var shake := 0.0
var look_node: Node3D   # when set, the camera looks at this node (plus look_off)
var look_off := Vector3.ZERO

# overlay state (tracked)
var fade := 0.0
var bars := 0.0
var clock_a := 0.0
var live_a := 0.0
var call_a := 0.0
var card_a := 0.0

var layer: CanvasLayer
var bar_top: ColorRect
var bar_bot: ColorRect
var black: ColorRect
var sub: Label
var sub_t := 0.0
var skip_hint: Label
var clock_label: Label
var live_label: Label
var call_box: Control
var call_text: Label
var card_title: Label
var card_sub: Label
var font: SystemFont
var hud_was := true

var vesk: Node3D
var dodger: Node3D
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
	if start_args.has("no-cutscenes") or not (id in ["intro", "outro"]):
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

## Play a voice line (not while fast-forwarding) and wait for it plus a gap.
func say(id: String, gap := 0.45) -> void:
	var l := line_len(id)
	if not ffwd(): Snd.voice(id, true)
	elif start_args.has("cut-hold") and Snd.subtitle(id) != "":
		_on_line(id, Snd.script_lines[id][0], Snd.subtitle(id)); sub_t = 999.0
	await wait(l + gap)

func fx(f: Callable) -> void:
	if not ffwd(): f.call()

func cut(pos: Vector3, look: Vector3, fov := -1.0) -> void:
	setv(self, "cam_pos", pos); setv(self, "cam_look", look)
	if fov > 0.0: setv(self, "cam_fov", fov)
	look_node = null

func move(pos: Vector3, look: Vector3, dur: float, fov := -1.0, trans := Tween.TRANS_SINE) -> void:
	tw(self, "cam_pos", pos, dur, 0.0, trans); tw(self, "cam_look", look, dur, 0.0, trans)
	if fov > 0.0: tw(self, "cam_fov", fov, dur, 0.0, trans)

func _process(dt: float) -> void:
	sub_t -= dt
	if sub_t <= 0.0: sub.modulate.a = maxf(0.0, sub.modulate.a - dt * 3.0)
	if playing == "": return
	if seek <= 0.0 and not (start_args.has("cut-hold") and start_args.get("cut", "") == playing):
		ct += dt
		_eval()
	_apply(dt)

func _input(e: InputEvent) -> void:
	if playing == "" or skipping or ct < 0.8 or e.is_echo(): return
	if e.is_action_pressed("jump") or e.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		_skip()

func _apply(dt: float) -> void:
	if cam:
		var look := cam_look
		if is_instance_valid(look_node): look = look_node.global_position + look_off
		shake = maxf(0.0, shake - dt * 2.0)
		var tt := ct
		var off := Vector3(sin(tt * 0.7) * 0.03 + sin(tt * 1.9) * 0.012, sin(tt * 0.9) * 0.025, 0) * sway
		off += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * shake * 0.08
		cam.global_position = cam_pos + off
		if not cam_pos.is_equal_approx(look):
			var up := Vector3.UP if absf((look - cam_pos).normalized().y) < 0.98 else Vector3.FORWARD
			cam.look_at(look + off * 0.5, up)
		cam.fov = cam_fov
	black.color.a = fade
	var h := 92.0 * bars
	bar_top.size = Vector2(bar_top.get_viewport_rect().size.x, h)
	bar_bot.size = Vector2(bar_top.size.x, h); bar_bot.position.y = bar_bot.get_viewport_rect().size.y - h
	clock_label.modulate.a = clock_a; live_label.modulate.a = live_a * (0.6 + 0.4 * sin(ct * 6.0))
	call_box.modulate.a = call_a; call_box.queue_redraw()
	card_title.modulate.a = card_a; card_sub.modulate.a = card_a
	skip_hint.modulate.a = clampf(bars, 0, 1) * 0.55

func _skip() -> void:
	skipping = true
	Snd.voice_queue.clear()
	if Snd.voice_player: Snd.voice_player.stop()
	sub.modulate.a = 0.0
	var t := create_tween(); t.tween_property(self, "fade", 1.0, 0.25)
	await t.finished
	seek = 1e6

# ---------------------------------------------------------------- start / end
func _run(id: String) -> void:
	playing = id; ct = 0.0; skipping = false; tracks.clear()
	seek = float(start_args.get("cut-t", 0.0)) if start_args.get("cut", "") == id else 0.0
	Game.input_locked = true
	await get_tree().process_frame   # story is still between emitting cutscene_started and awaiting the finish
	if id == "outro" and seek <= 0.0:
		# dip to black from gameplay before the scene is set up
		fade = 0.0; bars = 0.0
		var ft := create_tween().set_parallel()
		ft.tween_property(self, "fade", 1.0, 0.9); ft.tween_property(self, "bars", 1.0, 0.9)
		while ft.is_running():
			_apply_overlay_only(); await get_tree().process_frame
	if Game.hud: hud_was = Game.hud.visible; Game.hud.visible = false
	if Game.player:
		Game.player.process_mode = Node.PROCESS_MODE_DISABLED
		Game.player.visible = false
	cam = Camera3D.new(); cam.name = "CutsceneCam"; cam.far = 2500; Game.main.add_child(cam)
	cam.current = true
	cam_fov = 50.0; sway = 1.0; fade = 1.0; bars = 1.0
	_apply(0.0)
	Snd.music("cutscene", 2.0)
	if id == "intro": await _intro()
	else: await _outro()
	await _finish(id)

func _finish(id: String) -> void:
	var was_skip := skipping
	print("[cutscene] %s finished at t=%.1f%s" % [id, ct, " (skipped)" if was_skip else ""])
	seek = 0.0; skipping = false
	tracks.clear()
	for a in actors: if is_instance_valid(a): a.queue_free()
	actors.clear(); vesk = null; dodger = null
	clock_a = 0; live_a = 0; call_a = 0; card_a = 0
	if Game.player:
		Game.player.visible = true
		Game.player.process_mode = Node.PROCESS_MODE_INHERIT
		Game.player.velocity = Vector3.ZERO
	if Game.hud: Game.hud.visible = hud_was
	Game.input_locked = false
	Snd.music("skyharbor", 2.5)
	Snd.loop("wind_loop", true, -16)
	playing = ""
	Game.cutscene_finished.emit(id)
	# ease from the cutscene camera into the gameplay camera, open the letterbox, fade in
	var game_cam: Camera3D = Game.cam.camera if Game.cam and "camera" in Game.cam else null
	var from := cam.global_transform
	var from_fov := cam.fov
	var t := 0.0
	var dur := 0.4 if was_skip else 1.3
	while t < dur:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		t += dt
		var u := smoothstep(0.0, 1.0, t / dur)
		if game_cam:
			cam.global_transform = from.interpolate_with(game_cam.global_transform, u)
			cam.fov = lerpf(from_fov, game_cam.fov, u)
		fade = move_toward(fade, 0.0, dt * 2.5)
		bars = 1.0 - u
		_apply_overlay_only()
	bars = 0.0; fade = 0.0; _apply_overlay_only()
	if game_cam: game_cam.current = true
	cam.queue_free(); cam = null

func _apply_overlay_only() -> void:
	black.color.a = fade
	var h := 92.0 * bars
	bar_top.size.y = h; bar_bot.size.y = h; bar_bot.position.y = bar_bot.get_viewport_rect().size.y - h
	skip_hint.modulate.a = 0.0
	clock_label.modulate.a = 0; live_label.modulate.a = 0; call_box.modulate.a = 0; card_title.modulate.a = 0; card_sub.modulate.a = 0

# ---------------------------------------------------------------- helpers for the scenes
func _spot(name_: String, def: Vector3) -> Vector3:
	var v = Game.level.get(name_) if Game.level else null
	return v if v is Vector3 else def

func _actor(n: Node3D, pos: Vector3, yaw := 0.0, keep := false) -> Node3D:
	Game.main.add_child(n); n.global_position = pos; n.rotation.y = yaw
	if keep: keep_props.append(n)
	else: actors.append(n)
	return n

func _mesh(parent: Node3D, m: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new(); mi.mesh = m; mi.material_override = mat; mi.position = pos; mi.rotation = rot
	parent.add_child(mi); return mi

func _box(parent: Node3D, size: Vector3, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new(); b.size = size; return _mesh(parent, b, mat, pos, rot)

func _cyl(parent: Node3D, r: float, h: float, mat: Material, pos: Vector3, rot := Vector3.ZERO, r2 := -1.0) -> MeshInstance3D:
	var c := CylinderMesh.new(); c.top_radius = r; c.bottom_radius = r if r2 < 0.0 else r2; c.height = h
	return _mesh(parent, c, mat, pos, rot)

func _sphere(parent: Node3D, r: float, mat: Material, pos: Vector3, hemi := false) -> MeshInstance3D:
	var s := SphereMesh.new(); s.radius = r; s.height = r * (1.0 if hemi else 2.0); s.is_hemisphere = hemi
	return _mesh(parent, s, mat, pos)

func _model(path: String) -> Node3D:
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

func _face_to(a: Node3D, target: Vector3) -> float:
	var d := target - a.global_position
	return atan2(d.x, d.z)

# ---------------------------------------------------------------- props built for the cutscenes
func _make_coffee_maker() -> Node3D:
	var n := Node3D.new(); n.name = "CoffeeMaker"
	var body := M.std(Color(0.2, 0.42, 0.45), 0.6, 0.35)
	var dark := M.std(Color(0.12, 0.13, 0.15), 0.5, 0.5)
	_box(n, Vector3(0.26, 0.06, 0.22), dark, Vector3(0, 0.03, 0))
	_box(n, Vector3(0.26, 0.34, 0.09), body, Vector3(0, 0.2, -0.07))
	_box(n, Vector3(0.26, 0.07, 0.22), body, Vector3(0, 0.36, 0))
	var glass := M.std(Color(0.5, 0.6, 0.65), 0.1, 0.05); glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; glass.albedo_color.a = 0.45
	_cyl(n, 0.075, 0.15, glass, Vector3(0, 0.14, 0.04))
	_cyl(n, 0.07, 0.07, M.std(Color(0.22, 0.12, 0.06), 0, 0.3), Vector3(0, 0.1, 0.04))
	var eye := M.glow(Color(0.35, 0.9, 1.0), 2.5)
	n.set_meta("eye", eye)
	_sphere(n, 0.025, eye, Vector3(-0.06, 0.3, -0.02))
	_sphere(n, 0.025, eye, Vector3(0.06, 0.3, -0.02))
	# time-card slot and card
	var card := _box(n, Vector3(0.11, 0.15, 0.004), M.std(Color(0.96, 0.93, 0.82), 0, 0.8), Vector3(0, 0.33, -0.07))
	card.name = "Card"
	var stamp := Node3D.new(); stamp.name = "Stamp"; stamp.position = Vector3(0, 0.46, 0.0); n.add_child(stamp)
	_box(stamp, Vector3(0.05, 0.08, 0.05), dark, Vector3(0, 0, 0))
	# tiny hard hat (pops on when it clocks in)
	var hat := Node3D.new(); hat.name = "Hat"; hat.position = Vector3(0, 0.4, 0); hat.scale = Vector3.ONE * 0.001; n.add_child(hat)
	var yel := M.std(Color(1, 0.78, 0.1), 0.1, 0.35)
	_sphere(hat, 0.1, yel, Vector3.ZERO, true)
	_cyl(hat, 0.13, 0.012, yel, Vector3(0, 0.005, 0.02))
	return n

func _make_toaster() -> Node3D:
	var n := Node3D.new(); n.name = "Toaster"
	var chrome := M.std(Color(0.8, 0.82, 0.85), 0.95, 0.2)
	_box(n, Vector3(0.28, 0.18, 0.16), chrome, Vector3(0, 0.09, 0))
	_box(n, Vector3(0.02, 0.04, 0.04), M.std(Color(0.1, 0.1, 0.1), 0, 0.5), Vector3(0.15, 0.12, 0))
	var toast := Node3D.new(); toast.name = "Toast"; n.add_child(toast)
	for x in [-0.05, 0.05]:
		_box(toast, Vector3(0.02, 0.12, 0.11), M.std(Color(0.72, 0.45, 0.2), 0, 0.9), Vector3(x, 0.14, 0))
	var eye := M.glow(Color(1, 0.2, 0.1), 0.0)
	n.set_meta("eye", eye)
	_box(n, Vector3(0.2, 0.02, 0.005), eye, Vector3(0, 0.1, 0.081))
	return n

func _make_radio() -> Node3D:
	var n := Node3D.new(); n.name = "WreckRadio"
	var rust := M.std(Color(0.5, 0.33, 0.22), 0.6, 0.6)
	var dark := M.std(Color(0.16, 0.17, 0.2), 0.7, 0.4)
	var yel := M.std(Color(0.95, 0.7, 0.15), 0.5, 0.4)
	# a chunk of crane cab, tipped over, with its loudspeaker horn still working
	_box(n, Vector3(2.4, 1.6, 2.0), yel, Vector3(0, 0.6, 0), Vector3(0.15, 0.3, 0.35))
	_box(n, Vector3(1.6, 0.9, 0.08), M.std(Color(0.3, 0.4, 0.5), 0.1, 0.1), Vector3(0.1, 0.9, 1.0), Vector3(0.15, 0.3, 0.35))
	_box(n, Vector3(3.5, 0.35, 0.35), rust, Vector3(-1.6, 0.25, 1.2), Vector3(0, 0.7, 0.1))
	var horn := Node3D.new(); horn.name = "Horn"; horn.position = Vector3(0.9, 1.25, 1.1); horn.rotation = Vector3(-0.3, 0.4, 0); n.add_child(horn)
	_cyl(horn, 0.32, 0.55, dark, Vector3(0, 0, 0.25), Vector3(PI / 2, 0, 0), 0.08)
	var lamp := M.glow(Color(1, 0.15, 0.1), 0.5)
	n.set_meta("lamp", lamp)
	_sphere(n, 0.12, lamp, Vector3(0.4, 1.55, 0.8))
	var l := OmniLight3D.new(); l.light_color = Color(1, 0.2, 0.1); l.light_energy = 0.0; l.omni_range = 5; l.position = Vector3(0.4, 1.8, 1.0)
	n.add_child(l); n.set_meta("light", l)
	return n

func _make_ship() -> Node3D:
	# Vesk's old hauler: stubby, patched and loud
	var n := Node3D.new(); n.name = "Hauler"
	var hull := M.std(Color(0.93, 0.5, 0.18), 0.5, 0.4)
	var teal := M.std(Color(0.2, 0.55, 0.58), 0.6, 0.35)
	var dark := M.std(Color(0.18, 0.2, 0.24), 0.7, 0.4)
	var glass := M.std(Color(0.4, 0.75, 0.95), 0.2, 0.05)
	var body := Node3D.new(); body.name = "Body"; n.add_child(body)
	var cap := CapsuleMesh.new(); cap.radius = 1.3; cap.height = 6.5
	_mesh(body, cap, hull, Vector3(0, 2.0, 0), Vector3(PI / 2, 0, 0))
	_sphere(body, 0.95, glass, Vector3(0, 2.75, 1.9))
	_box(body, Vector3(7.2, 0.25, 2.0), teal, Vector3(0, 1.8, -0.6), Vector3(0, 0, 0))
	_box(body, Vector3(0.25, 1.6, 1.4), teal, Vector3(0, 3.6, -2.4), Vector3(-0.3, 0, 0))
	_box(body, Vector3(1.2, 0.8, 0.9), M.std(Color(0.7, 0.72, 0.75), 0.8, 0.3), Vector3(0.9, 2.9, -0.8))  # patch
	for x in [-2.6, 2.6]:
		_cyl(body, 0.45, 1.8, dark, Vector3(x, 1.8, -1.0), Vector3(PI / 2, 0, 0))
		var g := M.glow(Color(0.4, 0.9, 1.0), 0.0)
		_cyl(body, 0.36, 0.05, g, Vector3(x, 1.8, -1.92), Vector3(PI / 2, 0, 0))
		n.set_meta("jet%d" % (0 if x < 0 else 1), g)
	for p in [Vector3(-1.1, 0.5, 1.6), Vector3(1.1, 0.5, 1.6), Vector3(0, 0.5, -2.2)]:
		_cyl(body, 0.08, 1.0, dark, p)
		_cyl(body, 0.25, 0.08, dark, p - Vector3(0, 0.5, 0))
	var l := OmniLight3D.new(); l.light_color = Color(0.4, 0.9, 1.0); l.light_energy = 0.0; l.omni_range = 8; l.position = Vector3(0, 1.6, -2.5)
	body.add_child(l); n.set_meta("light", l)
	return n

func _ship_jets(ship: Node3D, e: float) -> void:
	for k in ["jet0", "jet1"]: (ship.get_meta(k) as StandardMaterial3D).emission_energy_multiplier = e
	(ship.get_meta("light") as OmniLight3D).light_energy = e * 0.8

# ---------------------------------------------------------------- INTRO
func _intro() -> void:
	var chair_pos := _spot("porch_chair_pos", Vector3(-2.5, 0.4, 93.5))
	var porch_y := 0.4
	var bench := _spot("gear_pos", Vector3(3.6, 1.45, 94))
	var crash := _spot("dodger_crash_pos", Vector3(-12.5, 2.4, 74.5))
	var mast := _spot("mast_top", Vector3(14, 20, -34))
	var start: Vector3 = Game.level.start_pos if Game.level else Vector3(0, 0.5, 91)
	var chair: Node3D = Game.level.find_child("porch_chair", false, false) if Game.level else null
	if chair: chair_pos = chair.global_position
	var bench_top := bench.y - 0.05
	# actors
	vesk = _actor(VeskActor.new(), chair_pos + Vector3(0, 0.27, 0.06), PI)
	vesk.sit = 1.0; vesk.slump = 1.0
	vesk.hold_mug(true)
	dodger = _actor(DroneActor.new(), Vector3(-30, 9, 70), PI * 0.5)
	var coffee := _actor(_make_coffee_maker(), Vector3(bench.x + 0.95, bench_top, bench.z + 0.05), PI + 0.25, true)
	var toaster := _actor(_make_toaster(), Vector3(bench.x - 0.75, bench_top, bench.z + 0.1), PI - 0.2, true)
	var roller := _actor(_model("res://models/roller.glb"), Vector3(-14, 0.0, 86), 0.0)
	var roller2 := _actor(_model("res://models/roller.glb"), Vector3(15, 0.0, 76), 0.0)
	var hornet := _actor(_model("res://models/hornet.glb"), Vector3(-30, 7, 80), PI * 0.5)

	# 1. the sky city, from far out
	Snd.loop("wind_loop", true, -12)
	cut(Vector3(34, 46, 175), Vector3(4, 4, 30), 48.0)
	move(Vector3(22, 30, 138), Vector3(0, 2, 40), 15.0, 44.0)
	tw(self, "fade", 0.0, 3.0)
	await wait(2.6)
	await say("intro_01", 0.6)
	# 2. over the docks and gardens, out to the junkyard
	cut(Vector3(-66, 24, 34), Vector3(-10, 3, 44), 50.0)
	move(Vector3(-30, 12, 70), Vector3(-2, 1.5, 86), 9.5)
	await say("intro_02", 1.0)
	# 3. the porch: start on the brass gear on the workbench, drift over to Vesk in his chair
	cut(bench + Vector3(-0.35, 0.3, -1.1), bench + Vector3(0, 0.02, 0), 38.0)
	sway = 0.5
	move(chair_pos + Vector3(1.6, 1.15, -3.4), chair_pos + Vector3(0, 0.85, 0), 8.0, 42.0)
	await wait(1.4)
	await say("intro_03", 1.4)
	# 4. "Finally. Nothing left to fix."
	cut(chair_pos + Vector3(0.55, 1.0, -1.55), chair_pos + Vector3(0, 0.95, 0.1), 40.0)
	move(chair_pos + Vector3(0.45, 1.0, -1.3), chair_pos + Vector3(0, 0.95, 0.1), 5.0)
	tw(vesk, "head_turn", -0.15, 1.0)
	await say("intro_04", 1.6)
	# 5. Dodger swoops in from the yard
	cut(chair_pos + Vector3(3.2, 1.4, -4.6), chair_pos + Vector3(0.8, 0.9, 0), 46.0)
	setv(dodger, "global_position", chair_pos + Vector3(-9, 5, -14))
	tw(dodger, "global_position", chair_pos + Vector3(4, 3.0, -6), 1.2, 0.0, Tween.TRANS_SINE, Tween.EASE_OUT)
	tw(dodger, "global_position", chair_pos + Vector3(1.25, 1.55, -0.3), 1.1, 1.2, Tween.TRANS_BACK, Tween.EASE_OUT)
	tw(dodger, "rotation:y", PI + 0.6, 0.8, 1.2)
	fx(func(): Snd.at("dash", dodger.global_position, -6))
	await wait(2.4)
	tw(vesk, "head_turn", -0.5, 0.6)
	await say("intro_05", 0.5)
	# 6. "Dodger. It's my day off."
	cut(chair_pos + Vector3(-0.6, 1.05, -1.6), chair_pos + Vector3(0.3, 1.0, 0), 40.0)
	await say("intro_06", 2.2)
	# 7. 7:59:57 ... 8:00:00, the relay dish on the Signal Mast pulses
	tw(vesk, "head_turn", 0.0, 1.0)
	cut(chair_pos + Vector3(2.4, 1.3, -3.6), chair_pos + Vector3(0.5, 0.9, 0), 46.0)
	clock_label.text = "SKYHARBOR   7:59:57 AM"
	tw(self, "clock_a", 1.0, 0.6)
	for s in ["58", "59"]:
		await wait(1.0)
		clock_label.text = "SKYHARBOR   7:59:%s AM" % s
	await wait(1.0)
	clock_label.text = "SKYHARBOR   8:00:00 AM"
	fx(func(): Snd.play("crane_warn", -6); Snd.play("checkpoint", -4))
	cut(Vector3(-3, 3.2, 73), mast + Vector3(0, 0.5, 0), 16.0)
	move(Vector3(-2.6, 3.4, 72), mast + Vector3(0, 1.2, 0), 7.0, 11.0)
	tw(self, "clock_a", 0.0, 1.0, 1.2)
	for i in 4:
		fx(func(): FX.ring(mast + Vector3(0, 1.5, 0), Color(1, 0.5, 0.15), 3.0 + i))
		await wait(0.5)
	await say("intro_07", 0.6)
	# 8. the coffee maker clocks in
	var cm_eye: StandardMaterial3D = coffee.get_meta("eye")
	var card: Node3D = coffee.find_child("Card", true, false)
	var stamp: Node3D = coffee.find_child("Stamp", true, false)
	var hat: Node3D = coffee.find_child("Hat", true, false)
	var cpos := coffee.global_position
	cut(cpos + Vector3(-0.55, 0.42, -0.95), cpos + Vector3(0, 0.25, 0), 34.0)
	await wait(0.8)
	cm_eye.emission = Color(1, 0.3, 0.1)
	fx(func(): Snd.at("ui_select", cpos, -4))
	tw(card, "position:y", 0.52, 0.25, 0.0, Tween.TRANS_BACK, Tween.EASE_OUT)
	await wait(0.6)
	tw(stamp, "position:y", 0.39, 0.08, 0.0, Tween.TRANS_EXPO, Tween.EASE_IN)
	await wait(0.1)
	fx(func(): Snd.at("melee_hit", cpos, -6); FX.sparks(cpos + Vector3(0, 0.45, 0), Color(1, 0.8, 0.4), 6, 2.0))
	tw(stamp, "position:y", 0.46, 0.2, 0.05)
	tw(card, "position:y", 0.33, 0.3, 0.4)
	await wait(0.5)
	tw(hat, "scale", Vector3.ONE, 0.3, 0.0, Tween.TRANS_BACK, Tween.EASE_OUT)
	tw(hat, "position:y", 0.45, 0.3, 0.0, Tween.TRANS_BACK, Tween.EASE_OUT)
	fx(func(): Snd.at("cell_pickup", cpos, -8))
	await wait(0.6)
	await say("sky_intro_coffee_1", 0.3)
	cut(chair_pos + Vector3(0.5, 1.05, -1.45), chair_pos + Vector3(0, 1.0, 0.1), 38.0)
	tw(vesk, "head_turn", 0.55, 0.5)
	await say("sky_intro_coffee_2", 0.4)
	cut(cpos + Vector3(-0.35, 0.32, -0.6), cpos + Vector3(0, 0.38, 0), 30.0)
	await say("sky_intro_coffee_3", 0.6)
	# 9. the toaster growls
	var tpos := toaster.global_position
	var t_eye: StandardMaterial3D = toaster.get_meta("eye")
	cut(tpos + Vector3(0.5, 0.35, -0.8), tpos + Vector3(0, 0.12, 0), 34.0)
	tw(t_eye, "emission_energy_multiplier", 4.0, 0.5)
	for i in 6:
		tw(toaster, "rotation:z", 0.08 if i % 2 == 0 else -0.08, 0.08)
		await wait(0.1)
	setv(toaster, "rotation:z", 0.0)
	fx(func(): Snd.at("roller_fuse", tpos, -8))
	await say("intro_08", 0.4)
	var toast: Node3D = toaster.find_child("Toast", true, false)
	tw(toast, "position:y", 0.35, 0.25, 0.0, Tween.TRANS_QUAD, Tween.EASE_OUT)
	tw(toast, "position:y", 0.0, 0.3, 0.3, Tween.TRANS_QUAD, Tween.EASE_IN)
	await wait(0.8)
	# 10. every bot goes haywire: rollers in the yard, a hornet over the wall, sparks from the generator
	cut(Vector3(3, 5.5, 98.5), Vector3(-3, 0.5, 79), 52.0)
	move(Vector3(1, 6.5, 99.5), Vector3(-4, 0.5, 77), 7.0)
	tw(roller, "global_position", Vector3(-6, 0, 80), 5.0, 0.0, Tween.TRANS_LINEAR)
	tw(roller, "rotation:y", 2.4, 5.0)
	tw(roller2, "global_position", Vector3(4, 0, 79), 4.0, 0.3, Tween.TRANS_LINEAR)
	tw(hornet, "global_position", Vector3(12, 5, 74), 6.0, 0.0, Tween.TRANS_LINEAR)
	fx(func(): FX.sparks(Vector3(10, 1.4, 94.5), Color(1, 0.7, 0.3), 16, 5.0); Snd.at("bot_spawn", Vector3(-6, 0, 80), -4))
	await wait(0.5)
	await say("intro_09", 0.5)
	fx(func(): FX.sparks(Vector3(10, 1.4, 94.5), Color(1, 0.7, 0.3), 10, 4.0))
	# 11. Dodger picks up the signal, looking north to the mast
	cut(dodger.global_position + Vector3(0.5, 0.35, 1.4), mast, 30.0)
	tw(dodger, "rotation:y", PI, 0.6)
	dodger.orange = 0.0
	await say("intro_10", 0.4)
	# 12. "Somebody else's problem."
	cut(chair_pos + Vector3(0.5, 1.05, -1.45), chair_pos + Vector3(0, 1.0, 0.1), 38.0)
	tw(vesk, "head_turn", 0.0, 0.5)
	await say("intro_11", 0.6)
	# 13. a roller trundles up the porch steps and eats the chair
	cut(chair_pos + Vector3(4.0, 1.7, -4.2), chair_pos + Vector3(-0.3, 0.6, 0), 46.0)
	setv(roller, "global_position", chair_pos + Vector3(-5, porch_y - 0.4, -4))
	tw(roller, "global_position", chair_pos + Vector3(-1.4, porch_y, -0.9), 1.6, 0.0, Tween.TRANS_LINEAR)
	tw(roller, "rotation:y", 0.9, 1.6)
	fx(func(): Snd.at("roller_roll", chair_pos, -2))
	await wait(1.0)
	# Vesk hops out of the chair
	vesk.play("jump", 0.1)
	tw(vesk, "sit", 0.0, 0.3); tw(vesk, "slump", 0.0, 0.3)
	tw(vesk, "global_position", chair_pos + Vector3(1.6, porch_y - 0.4 + 0.02, -0.9), 0.55, 0.0, Tween.TRANS_QUAD, Tween.EASE_OUT)
	await wait(0.55)
	vesk.play("land", 0.05)
	fx(func(): Snd.at("land", vesk.global_position, -4))
	await wait(0.35)
	vesk.play("idle", 0.3)
	setv(vesk, "rotation:y", _face_to(vesk, chair_pos))
	tw(roller, "global_position", chair_pos + Vector3(-0.2, porch_y, -0.3), 0.5)
	await wait(0.5)
	fx(func(): Snd.at("crate_break", chair_pos, -2); FX.puff(chair_pos + Vector3(0, 0.6, 0), Color(0.6, 0.5, 0.4)); FX.shake(0.3))
	if chair:
		tw(chair, "rotation:z", 1.45, 0.35, 0.0, Tween.TRANS_BOUNCE, Tween.EASE_OUT)
		tw(chair, "position", chair.position + Vector3(0.35, -0.05, -0.2), 0.35)
		tw(chair, "scale", Vector3(1, 0.75, 1), 0.3)
	await wait(0.6)
	await say("intro_12", 0.5)
	# 14. "...Fine. Let's go unplug it."
	cut(vesk.global_position + Vector3(-1.2, 1.15, -1.6), vesk.global_position + Vector3(0, 1.0, 0), 40.0)
	setv(vesk, "rotation:y", _face_to(vesk, vesk.global_position + Vector3(-1, 0, -2)))
	tw(roller, "global_position", Vector3(-8, 0.0, 79), 2.4, 0.4, Tween.TRANS_QUAD, Tween.EASE_IN)
	await say("intro_13", 0.3)
	vesk.hold_mug(false)
	# 15. Dodger cheers, zooms off for the scrap pile... and crashes
	var dp: Vector3 = dodger.global_position
	cut(dp + Vector3(1.8, 0.4, 2.2), dp, 44.0)
	tw(dodger, "rotation:y", _face_to(dodger, crash), 0.4)
	await say("intro_14", 0.1)
	var fly := line_len("sky_intro_crash_1")
	if not ffwd(): Snd.voice("sky_intro_crash_1", true)
	cut(Vector3(1.5, 2.6, 93.5), dp, 46.0)
	look_node = dodger
	tw(dodger, "global_position", dp + Vector3(-1, 2.5, -3), 0.7, 0.0, Tween.TRANS_SINE, Tween.EASE_OUT)
	tw(dodger, "global_position", crash + Vector3(0.4, 1.8, 2.5), fly * 0.55, 0.7, Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	tw(dodger, "tilt", Vector3(0.4, 0, 0.3), 0.6, 0.7)
	tw(self, "cam_fov", 34.0, fly * 0.7)
	fx(func(): Snd.at("dash", dp, -4))
	await wait(0.7 + fly * 0.55)
	tw(dodger, "global_position", crash + Vector3(0, 0.25, 0), 0.25, 0.0, Tween.TRANS_QUAD, Tween.EASE_IN)
	await wait(0.25)
	fx(func(): Snd.at("explode_small", crash, -4); FX.sparks(crash + Vector3(0, 0.3, 0), Color(1, 0.7, 0.3), 18, 5.0); FX.puff(crash + Vector3(0, 0.4, 0), Color(0.5, 0.45, 0.4)); FX.shake(0.4))
	setv(dodger, "tilt", Vector3(0.9, 0.4, 1.2)); dodger.hover = 0.0; dodger.dim = 0.6
	await wait(maxf(0.4, fly * 0.45 - 0.25) + 1.0)
	# 16. hand over: Vesk on the porch steps, looking out at the yard
	look_node = null
	setv(vesk, "global_position", start + Vector3(0, -0.1, 0.9))
	setv(vesk, "rotation:y", PI)
	vesk.play("idle")
	cut(start + Vector3(0.7, 2.0, 4.6), start + Vector3(0, 1.2, -3.0), 50.0)
	walk(vesk, start + Vector3(0, -0.1, 0), 2.0)
	await wait(0.6)
	vesk.play("idle", 0.3)
	await wait(0.4)
	if chair:  # the chewed chair stays knocked over
		chair.rotation.z = 1.45; chair.scale = Vector3(1, 0.75, 1)

# ---------------------------------------------------------------- OUTRO
func _outro() -> void:
	var c := Vector3(0, 0, -97)
	if Game.level and "islands" in Game.level and Game.level.islands.has("arena"):
		var r: Rect2 = Game.level.islands.arena
		c = Vector3(r.get_center().x, 0, r.get_center().y)
	var mast := _spot("mast_top", Vector3(14, 20, -34))
	var dish_glow: StandardMaterial3D = Game.level.get("dish_glow") if Game.level else null
	var dish_col := dish_glow.emission if dish_glow else Color.WHITE
	# actors
	vesk = _actor(VeskActor.new(), c + Vector3(0, 0, 1), PI)
	dodger = _actor(DroneActor.new(), c + Vector3(0.85, 1.95, 1.2), PI)
	var radio := _actor(_make_radio(), c + Vector3(-2.5, 0, -6.5), 0.4)
	var lamp: StandardMaterial3D = radio.get_meta("lamp")
	var rlight: OmniLight3D = radio.get_meta("light")
	var ship := _actor(_make_ship(), c + Vector3(0, 40, 9), PI)
	ship.visible = false
	var smoke := func(): FX.puff(radio.global_position + Vector3(randf_range(-1, 1), 1.6, randf_range(-1, 1)), Color(0.3, 0.3, 0.33))

	# 1. the Crane Yard after the fight
	cut(c + Vector3(17, 10, 15), c + Vector3(0, 1, -2), 50.0)
	move(c + Vector3(9, 6, 17), c + Vector3(0, 1, -1), 11.0)
	tw(self, "fade", 0.0, 2.0)
	await wait(1.6)
	for i in 3: fx(smoke)
	await say("outro_01", 0.8)
	# 2. the scorecard
	cut(c + Vector3(1.9, 1.55, -2.0), c + Vector3(0.3, 1.25, 1), 40.0)
	move(c + Vector3(1.5, 1.5, -1.6), c + Vector3(0.3, 1.25, 1), 9.0)
	fx(smoke)
	await say("outro_02", 0.4)
	setv(vesk, "head_turn", 0.0); tw(vesk, "head_turn", -0.5, 0.4)
	await say("outro_03", 0.3)
	await say("outro_04", 1.0)
	# 3. a radio crackles in the wreck
	var rp := radio.global_position + Vector3(0.9, 1.3, 1.1)
	cut(c + Vector3(1.5, 1.4, -0.5), rp, 46.0)
	move(c + Vector3(-0.2, 1.2, -3.0), rp, 6.0, 38.0)
	tw(vesk, "head_turn", 0.0, 0.6)
	for i in 3:
		fx(func(): Snd.at("ui_move", rp, -2); lamp.emission_energy_multiplier = 6.0; rlight.light_energy = 3.0)
		await wait(0.12)
		lamp.emission_energy_multiplier = 0.5; rlight.light_energy = 0.0
		await wait(0.35)
	await say("outro_05", 0.5)
	# 4. Grudd's first broadcast: the relay dish flares orange, Dodger's eye flickers
	live_label.text = "●  LIVE BROADCAST  ·  ALL FREQUENCIES"
	tw(self, "live_a", 1.0, 0.3)
	lamp.emission_energy_multiplier = 6.0; rlight.light_energy = 3.0
	if dish_glow: dish_glow.emission = Color(1, 0.45, 0.1)
	cut(rp + Vector3(-1.2, 0.2, 2.6), rp, 34.0)
	tw(self, "shake", 0.6, 0.1)
	await say("sky_outro_grudd_1", 0.5)
	# Dodger's eye flickers orange for the whole broadcast
	cut(dodger.global_position + Vector3(-0.5, 0.05, -1.3), dodger.global_position, 30.0)
	move(dodger.global_position + Vector3(-0.35, 0.05, -0.95), dodger.global_position, 6.0)
	tw(dodger, "orange", 1.0, 0.6)
	await say("outro_06", 0.4)
	cut(Vector3(-4, 2.2, c.z + 8), mast + Vector3(0, 1, 0), 14.0)
	await say("outro_07", 0.4)
	cut(rp + Vector3(-1.4, 0.4, 2.2), rp, 36.0)
	await say("outro_08", 0.6)
	tw(self, "live_a", 0.0, 0.5)
	lamp.emission_energy_multiplier = 0.5; rlight.light_energy = 0.0
	if dish_glow: dish_glow.emission = dish_col
	fx(func(): Snd.at("explode_small", rp, -10); FX.sparks(rp, Color(1, 0.6, 0.2), 10, 3.0))
	# 5. "Your eye's doing the orange thing again."
	cut(c + Vector3(-1.2, 1.4, -1.0), c + Vector3(0.4, 1.4, 1.1), 40.0)
	tw(vesk, "head_turn", -0.6, 0.5)
	await say("sky_outro_eye_1", 0.3)
	cut(dodger.global_position + Vector3(-0.4, 0.0, -1.1), dodger.global_position, 32.0)
	await say("sky_outro_eye_2", 0.2)
	tw(dodger, "orange", 0.0, 0.4)
	await wait(0.8)
	# 6. a giant robot foreman, of course
	cut(c + Vector3(2.2, 1.6, -2.6), c + Vector3(0.3, 1.25, 1), 42.0)
	tw(vesk, "head_turn", 0.0, 0.6)
	await say("outro_09", 0.4)
	tw(dodger, "global_position", dodger.global_position + Vector3(0.3, 0.4, -0.3), 0.6)
	await say("outro_10", 0.4)
	# 7. Nana Quill calls in with the coordinates
	fx(func(): Snd.play("ui_select", -4))
	await wait(0.35)
	fx(func(): Snd.play("ui_select", -4))
	call_text.text = "INCOMING CALL\nNANA QUILL"
	tw(self, "call_a", 1.0, 0.4)
	tw(dodger, "eye_color", Color(0.5, 1, 0.55), 0.3)
	cut(c + Vector3(3.6, 2.0, -3.4), c + Vector3(0.4, 1.3, 1), 44.0)
	move(c + Vector3(-1.5, 2.1, -4.4), c + Vector3(0.4, 1.3, 1), 26.0)
	await wait(0.6)
	await say("sky_outro_nana_1", 0.3)
	await say("sky_outro_nana_2", 0.3)
	await say("sky_outro_nana_3", 0.3)
	call_text.text = "SHARD 1 DECODED\n> DUSTVEIN GULCH"
	fx(func(): Snd.play("checkpoint", -6))
	await say("sky_outro_nana_4", 0.3)
	await say("sky_outro_nana_5", 0.2)
	await say("sky_outro_nana_6", 0.6)
	tw(self, "call_a", 0.0, 0.5)
	tw(dodger, "eye_color", DroneActor.EYE, 0.4)
	# 8. "Back to my chair?" "Road trip!"
	cut(c + Vector3(-0.6, 1.1, -1.5), c + Vector3(0.1, 1.05, 1), 38.0)
	await say("outro_11", 0.3)
	cut(dodger.global_position + Vector3(0.6, 0.2, -1.4), dodger.global_position, 34.0)
	tw(dodger, "global_position", dodger.global_position + Vector3(0, 0.6, 0), 0.3, 0.2, Tween.TRANS_BACK, Tween.EASE_OUT)
	await say("outro_12", 0.4)
	# 9. the old hauler drops in on autopilot, Vesk climbs aboard
	ship.visible = true
	_ship_jets(ship, 4.0)
	var pad := c + Vector3(0, 0, 9)
	cut(c + Vector3(-7, 1.3, -3), pad + Vector3(0, 3, 0), 52.0)
	tw(ship, "global_position", pad, 4.0, 0.0, Tween.TRANS_QUAD, Tween.EASE_OUT)
	fx(func(): Snd.at("crane_move", pad, 0))
	await wait(4.0)
	fx(func(): FX.ring(pad + Vector3(0, 0.1, 0), Color(0.6, 0.9, 1.0), 2.5); Snd.at("land", pad, 0); FX.shake(0.3))
	_ship_jets(ship, 0.8)
	var w := walk(vesk, pad + Vector3(0, 0, -2.6), 4.5)
	tw(dodger, "global_position", pad + Vector3(1, 3.2, -1), 1.6)
	await wait(w)
	vesk.play("jump", 0.1)
	tw(vesk, "global_position", pad + Vector3(0, 2.4, -1.0), 0.45, 0.0, Tween.TRANS_QUAD, Tween.EASE_OUT)
	fx(func(): Snd.at("jump", vesk.global_position, -4))
	await wait(0.45)
	vesk.visible = false
	tw(dodger, "global_position", pad + Vector3(0, 2.6, 0), 0.5)
	await wait(0.5)
	dodger.visible = false
	await wait(0.6)
	# 10. liftoff... with the handbrake on
	cut(c + Vector3(6, 0.8, -2), pad + Vector3(0, 3, 0), 50.0)
	_ship_jets(ship, 6.0)
	fx(func(): Snd.at("crane_warn", pad, -2); FX.puff(pad, Color(0.8, 0.8, 0.85)))
	tw(ship, "global_position", pad + Vector3(0, 2.5, 0), 1.0, 0.0, Tween.TRANS_QUAD, Tween.EASE_OUT)
	var body: Node3D = ship.find_child("Body", true, false)
	for i in 4:
		tw(body, "rotation:x", 0.2 if i % 2 == 0 else -0.12, 0.25)
		tw(self, "shake", 0.5, 0.05)
		await wait(0.3)
	tw(body, "rotation:x", 0.0, 0.3)
	var lo := line_len("sky_outro_liftoff_1")
	if not ffwd(): Snd.voice("sky_outro_liftoff_1", true)
	# lurch forward, snap back on the brake, then off for real
	tw(ship, "global_position", pad + Vector3(0, 3, 3), 0.4, 0.0, Tween.TRANS_QUAD, Tween.EASE_OUT)
	tw(ship, "global_position", pad + Vector3(0, 2.8, 0.5), 0.35, 0.45, Tween.TRANS_BACK, Tween.EASE_OUT)
	await wait(maxf(lo, 1.4) + 0.3)
	fx(func(): FX.sparks(pad + Vector3(0, 2.5, -2.5), Color(1, 0.7, 0.3), 18, 6.0); Snd.at("dash", pad, 0))
	_ship_jets(ship, 9.0)
	cut(c + Vector3(0, 1.2, -6), pad + Vector3(0, 4, 0), 50.0)
	look_node = ship; look_off = Vector3(0, 2, 0)
	tw(ship, "global_position", pad + Vector3(-20, 30, 90), 4.0, 0.0, Tween.TRANS_QUAD, Tween.EASE_IN)
	tw(ship, "rotation:x", -0.35, 1.5)
	tw(self, "cam_fov", 28.0, 4.0)
	await wait(1.5)
	await say("outro_13", 0.4)
	# 11. end card
	tw(self, "fade", 1.0, 1.4)
	await wait(1.6)
	look_node = null
	card_title.text = "SKYHARBOR  ·  COMPLETE"
	card_sub.text = "Shard 1 of the signal decoded.   Next stop: Dustvein Gulch"
	tw(self, "card_a", 1.0, 0.8)
	await wait(4.0)
	tw(self, "card_a", 0.0, 0.8)
	await wait(0.9)
	# back in the yard for a last look around
	if Game.player: Game.player.global_position = c + Vector3(0, 0.1, 1)

# ---------------------------------------------------------------- UI
func _on_line(_id: String, sp: String, text: String) -> void:
	if playing == "": return
	var who: String = SPEAKER_NAMES.get(sp, sp.to_upper())
	sub.text = (who + ":  " if who != "" else "") + text
	sub.add_theme_color_override("font_color", SPEAKER_COLORS.get(sp, Color.WHITE))
	sub.modulate.a = 1.0; sub_t = maxf(1.5, line_len(_id) + 0.2)

func _label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 8)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _build_ui() -> void:
	font = SystemFont.new(); font.font_names = PackedStringArray(["Inter", "Segoe UI", "Arial", "sans-serif"]); font.font_weight = 700
	layer = CanvasLayer.new(); layer.layer = 60; add_child(layer)
	var root := Control.new(); root.set_anchors_preset(Control.PRESET_FULL_RECT); root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	black = ColorRect.new(); black.color = Color(0, 0, 0, 0); black.set_anchors_preset(Control.PRESET_FULL_RECT); black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_top = ColorRect.new(); bar_top.color = Color.BLACK; bar_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_bot = ColorRect.new(); bar_bot.color = Color.BLACK; bar_bot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar_top); root.add_child(bar_bot)
	sub = _label(27, Color.WHITE)
	sub.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size = Vector2(1000, 80); sub.position = Vector2(-500, -88); sub.size = Vector2(1000, 80)
	sub.modulate.a = 0.0
	root.add_child(sub)
	skip_hint = _label(16, Color(1, 1, 1))
	skip_hint.text = "JUMP / ESC  skip"
	skip_hint.set_anchors_preset(Control.PRESET_TOP_RIGHT); skip_hint.position = Vector2(-210, 34); skip_hint.size = Vector2(190, 24)
	skip_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; skip_hint.modulate.a = 0.0
	root.add_child(skip_hint)
	clock_label = _label(22, Color(1, 0.85, 0.5))
	clock_label.position = Vector2(40, 32); clock_label.modulate.a = 0.0
	root.add_child(clock_label)
	live_label = _label(20, Color(1, 0.3, 0.25))
	live_label.position = Vector2(40, 32); live_label.modulate.a = 0.0
	root.add_child(live_label)
	call_box = Control.new(); call_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	call_box.position = Vector2(-380, 112); call_box.size = Vector2(350, 110); call_box.modulate.a = 0.0
	call_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	call_box.draw.connect(_draw_call)
	root.add_child(call_box)
	call_text = _label(20, Color(0.8, 1, 0.75))
	call_text.position = Vector2(118, 22); call_text.size = Vector2(220, 70)
	call_box.add_child(call_text)
	card_title = _label(58, Color(1, 0.85, 0.35)); card_sub = _label(24, Color(1, 1, 1))
	root.add_child(black)
	for l in [card_title, card_sub]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; l.modulate.a = 0.0; root.add_child(l)
		l.anchor_left = 0.5; l.anchor_right = 0.5; l.anchor_top = 0.5; l.anchor_bottom = 0.5
		l.offset_left = -600; l.offset_right = 600
	card_title.offset_top = -70; card_title.offset_bottom = 10
	card_sub.offset_top = 10; card_sub.offset_bottom = 50

## Nana Quill's call card: a little portrait (antenna-covered shell, round glasses) and the text.
func _draw_call() -> void:
	var b := call_box
	var panel := StyleBoxFlat.new(); panel.bg_color = Color(0.03, 0.08, 0.06, 0.82); panel.set_corner_radius_all(10)
	panel.border_color = Color(0.5, 1, 0.55, 0.8); panel.set_border_width_all(2)
	b.draw_style_box(panel, Rect2(Vector2.ZERO, b.size))
	var o := Vector2(56, 58)
	var green := Color(0.45, 0.75, 0.4)
	# antennas on the shell
	for i in 5:
		var a := -PI * 0.85 + i * PI * 0.17
		var p := o + Vector2(cos(a), sin(a)) * 30
		var tip := o + Vector2(cos(a), sin(a)) * (44 + (i % 2) * 6)
		b.draw_line(p, tip, Color(0.8, 0.8, 0.7), 2)
		b.draw_circle(tip, 3, Color(1, 0.45, 0.2) if int(ct * 3 + i) % 2 == 0 else Color(0.6, 1, 0.5))
	b.draw_circle(o + Vector2(0, 4), 32, green)
	for i in 3: b.draw_arc(o + Vector2(0, 4), 12 + i * 9, PI, TAU, 16, Color(0.3, 0.55, 0.3), 2)
	# face, glasses, smile
	var f := o + Vector2(0, 14)
	b.draw_circle(f, 19, Color(0.78, 0.8, 0.6))
	for sx in [-8, 8]:
		b.draw_arc(f + Vector2(sx, -3), 6, 0, TAU, 16, Color(0.2, 0.2, 0.2), 2)
		b.draw_circle(f + Vector2(sx, -3), 2, Color(0.15, 0.15, 0.15))
	b.draw_line(f + Vector2(-2, -3), f + Vector2(2, -3), Color(0.2, 0.2, 0.2), 2)
	b.draw_arc(f + Vector2(0, 6), 6, 0.3, PI - 0.3, 10, Color(0.35, 0.2, 0.15), 2)
	# signal bars
	for i in 4:
		var h := 6.0 + i * 5.0
		var on := (int(ct * 4.0) % 5) > i
		b.draw_rect(Rect2(Vector2(300 + i * 9, 96 - h), Vector2(6, h)), Color(0.5, 1, 0.55, 0.9 if on else 0.25))
