extends Node
## Menus: the title screen, the pause menu and settings. Keyboard, mouse and gamepad all work
## (arrows / WASD / D-pad / left stick to move, Enter / Space / A to pick, Esc / B to go back).
##
## Title screen ("UNLIKELY HEROES": Continue / New Game / Settings / Quit, plays Snd.music("title"))
##   shows on normal runs only. It holds the story's opening cutscene until a game is started:
##   New Game wipes the save and plays the intro, Continue loads the save and skips it.
## Pause menu (Esc / pad Start): Resume, Settings, Restart from checkpoint, Quit to title.
## Settings: look sensitivity, invert Y, master / music / sfx / voice volume, subtitles. Saved in
##   user://settings.cfg. Audio buses "Music", "SFX" and "Voice" are created at runtime if missing
##   and Snd's players are routed onto them.
## Debug: the title is skipped with --shot / --no-title / --at= / --story-auto / --cut=; --title
##   forces it, --pause-menu and --settings open those after a moment (for screenshots).

const SETTINGS_PATH := "user://settings.cfg"
const BUSES := ["Music", "SFX", "Voice"]
const HD := preload("res://scripts/ui/hud_draw.gd")
const CYAN := Color(0.45, 0.95, 1.0)
const GOLD := Color(1.0, 0.82, 0.3)
const PAUSE_SIZE := Vector2(1160, 640)

var settings := { look = 100.0, invert_y = false, aim_assist = true, master = 100.0, music = 80.0, sfx = 100.0, voice = 100.0, subtitles = true }

var layer: CanvasLayer
var font: Font
var body: Font
var pause_art: Control
var all_buttons: Array = []
var ui_t := 0.0
var title_root: Control
var pause_root: Control
var settings_root: Control
var title_buttons: VBoxContainer
var pause_buttons: VBoxContainer
var continue_btn: Button
var setting_rows := {}      # key -> { slider/check, value label }
var state := ""             # "", "title", "pause", "settings"
var settings_from := ""
var title_cam: Camera3D
var cam_t := 0.0
var held_intro := false
var cutscenes: Node
var route_t := 0.0
var prev_mouse := Input.MOUSE_MODE_CAPTURED
var hud_was := true

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	_load_settings()
	_build_ui()
	_apply_settings.call_deferred()
	Game.checkpoint_reached.connect(func(_p): Game.save())
	var args := OS.get_cmdline_user_args()
	var test := false
	for a in args:
		if a.begins_with("--shot") or a == "--no-title" or a.begins_with("--at=") or a == "--story-auto" or a.begins_with("--cut") or a == "--no-bots":
			test = true
	if args.has("--title") or not test:
		_hold_intro()
		_show_title.call_deferred()
	if args.has("--auto-continue"): get_tree().create_timer(1.0, true).timeout.connect(func(): _start(true))
	if args.has("--pause-menu"): get_tree().create_timer(1.2).timeout.connect(open_pause)
	if args.has("--settings"): get_tree().create_timer(1.2).timeout.connect(func(): open_pause(); _open_settings())

# ---------------------------------------------------------------- audio buses + settings
func _ensure_buses() -> void:
	for b in BUSES:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus(AudioServer.bus_count)
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b); AudioServer.set_bus_send(i, "Master")

func _route_snd() -> void:
	for c in Snd.get_children():
		var bus := "SFX"
		if c is AudioStreamPlayer and Snd.music_players.has(c): bus = "Music"
		elif c == Snd.voice_player: bus = "Voice"
		if c is AudioStreamPlayer and (c as AudioStreamPlayer).bus != bus: (c as AudioStreamPlayer).bus = bus
		elif c is AudioStreamPlayer3D and (c as AudioStreamPlayer3D).bus != bus: (c as AudioStreamPlayer3D).bus = bus

func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK: return
	for k in settings: settings[k] = cf.get_value("settings", k, settings[k])

func _save_settings() -> void:
	var cf := ConfigFile.new()
	for k in settings: cf.set_value("settings", k, settings[k])
	cf.save(SETTINGS_PATH)

static func _db(pct: float) -> float:
	return linear_to_db(maxf(pct, 0.001) / 100.0)

func _apply_settings() -> void:
	AudioServer.set_bus_volume_db(0, _db(settings.master))
	AudioServer.set_bus_mute(0, settings.master <= 0.5)
	for pair in [["Music", "music"], ["SFX", "sfx"], ["Voice", "voice"]]:
		var i := AudioServer.get_bus_index(pair[0])
		if i >= 0:
			AudioServer.set_bus_volume_db(i, _db(settings[pair[1]])); AudioServer.set_bus_mute(i, settings[pair[1]] <= 0.5)
	if Game.cam:
		Game.cam.mouse_sens = 0.0024 * settings.look / 100.0
		Game.cam.pad_sens = settings.look / 100.0
		Game.cam.invert_y = settings.invert_y
		if "aim_assist" in Game.cam: Game.cam.aim_assist = settings.get("aim_assist", true)
	if Game.hud and "subtitles" in Game.hud: Game.hud.subtitles = settings.subtitles
	_route_snd()

func _process(dt: float) -> void:
	ui_t += dt
	for b in all_buttons:
		var bb := b as Button
		if not bb.is_visible_in_tree(): continue
		bb.set_meta("f", move_toward(float(bb.get_meta("f")), 1.0 if bb.has_focus() else 0.0, dt * 8.0))
		bb.queue_redraw()
	if state == "pause" and pause_art: pause_art.queue_redraw()
	route_t -= dt
	if route_t <= 0.0: route_t = 0.5; _route_snd()
	# the cutscene player has its own subtitle label: hide it when subtitles are off
	if not settings.subtitles:
		if cutscenes == null: cutscenes = get_parent().get_node_or_null("Cutscenes")
		if cutscenes and "sub" in cutscenes and cutscenes.sub: cutscenes.sub.visible = false
	elif cutscenes and "sub" in cutscenes and cutscenes.sub: cutscenes.sub.visible = true
	if state == "title" and title_cam:
		cam_t += dt
		var a := cam_t * 0.05 + 2.4
		title_cam.global_position = Vector3(sin(a) * 52.0, 24.0 + sin(cam_t * 0.2) * 2.0, 34.0 + cos(a) * 52.0)
		title_cam.look_at(Vector3(4, 8, 6))

func _input(e: InputEvent) -> void:
	if e.is_echo(): return
	if e.is_action_pressed("pause"):
		match state:
			"":
				if _can_pause(): open_pause(); get_viewport().set_input_as_handled()
				else: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE   # never trap the mouse (cutscenes etc.); a click recaptures it
			"pause": close_pause(); get_viewport().set_input_as_handled()
			"settings": _close_settings(); get_viewport().set_input_as_handled()
	elif e.is_action_pressed("ui_cancel") and not (e is InputEventKey):
		# pad B backs out (Esc already handled as "pause")
		match state:
			"pause": close_pause(); get_viewport().set_input_as_handled()
			"settings": _close_settings(); get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	# alt-tab / clicking another window always frees the mouse
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _can_pause() -> bool:
	return not Game.input_locked and not get_tree().paused and Game.player != null

# ---------------------------------------------------------------- title
func _hold_intro() -> void:
	# keep the opening cutscene from starting until the player picks a game
	cutscenes = get_parent().get_node_or_null("Cutscenes")
	if cutscenes and cutscenes.has_method("_on_started") and Game.cutscene_started.is_connected(cutscenes._on_started):
		Game.cutscene_started.disconnect(cutscenes._on_started)
	Game.cutscene_started.connect(_on_cutscene_started)

func _on_cutscene_started(id: String) -> void:
	if id == "intro": held_intro = true

func _release_intro(play: bool) -> void:
	if Game.cutscene_started.is_connected(_on_cutscene_started): Game.cutscene_started.disconnect(_on_cutscene_started)
	if cutscenes and cutscenes.has_method("_on_started") and not Game.cutscene_started.is_connected(cutscenes._on_started):
		Game.cutscene_started.connect(cutscenes._on_started)
	if held_intro:
		held_intro = false
		if play and cutscenes and cutscenes.has_method("_on_started"): cutscenes._on_started("intro")
		else: Game.cutscene_finished.emit("intro")

func _show_title() -> void:
	state = "title"
	get_tree().paused = true
	Game.input_locked = true
	if Game.hud: hud_was = Game.hud.visible; Game.hud.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	title_cam = Camera3D.new(); title_cam.fov = 60; title_cam.far = 2500; title_cam.process_mode = Node.PROCESS_MODE_ALWAYS
	Game.main.add_child(title_cam); title_cam.current = true
	_process(0.0)
	Snd.music("title", 1.0)
	continue_btn.disabled = not FileAccess.file_exists(Game.SAVE_PATH)
	continue_btn.focus_mode = Control.FOCUS_NONE if continue_btn.disabled else Control.FOCUS_ALL
	title_root.visible = true
	title_root.modulate.a = 0.0
	title_root.create_tween().tween_property(title_root, "modulate:a", 1.0, 0.6)
	(continue_btn if not continue_btn.disabled else title_buttons.get_child(1)).grab_focus()

func _start(continue_game: bool) -> void:
	Snd.play("ui_select", -4)
	if continue_game:
		Game.load_save()
		_place_at_checkpoint()
	else:
		Game.reset_save()
		Game.data.nuts = 0; Game.data.unlocked = {"arc_lancer": true}; Game.data.collected = {}; Game.data.completed = {}
		Game.data.checkpoint = -1; Game.data.erase("weapons"); Game.data.erase("weapon"); Game.data.erase("gripes")
		Game.data.erase("checkpoint_pos"); Game.data.erase("checkpoint_yaw")
	if Game.combat and Game.combat.has_method("reload_from_save"): Game.combat.reload_from_save()
	Game.add_nuts(0)
	var col := get_parent().get_node_or_null("Collectibles")
	if col and col.has_method("refresh"): col.refresh()
	Game.save()
	var tw := title_root.create_tween(); tw.tween_property(title_root, "modulate:a", 0.0, 0.3)
	tw.tween_callback(func(): title_root.visible = false)
	state = ""
	get_tree().paused = false
	Game.input_locked = false
	if Game.hud: Game.hud.visible = hud_was
	if Game.cam and "camera" in Game.cam: Game.cam.camera.current = true
	if title_cam: title_cam.queue_free(); title_cam = null
	if not OS.get_cmdline_user_args().has("--no-capture"): Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Snd.music("skyharbor", 2.0)
	_release_intro(not continue_game)

## Continue: put Vesk back on the last checkpoint he touched (saves from before this existed start at the beginning).
func _place_at_checkpoint() -> void:
	var cp = Game.data.get("checkpoint_pos")
	if not (cp is Array and cp.size() == 3) or Game.player == null: return
	var p := Vector3(float(cp[0]), float(cp[1]), float(cp[2]))
	Game.player.respawn_pos = p
	Game.player.respawn_yaw = float(Game.data.get("checkpoint_yaw", Game.cam.yaw))
	Game.player.respawn()
	print("[menus] continue at checkpoint ", p)

# ---------------------------------------------------------------- pause
func open_pause() -> void:
	if state != "": return
	state = "pause"
	get_tree().paused = true
	Game.input_locked = true
	Engine.time_scale = 1.0
	prev_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	pause_root.visible = true
	pause_root.modulate.a = 0.0
	pause_art.scale = Vector2(0.94, 0.94)
	var tw := pause_root.create_tween().set_parallel()
	tw.tween_property(pause_root, "modulate:a", 1.0, 0.12)
	tw.tween_property(pause_art, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pause_buttons.get_child(0).grab_focus()
	Snd.play("pause_in", -4)

func close_pause() -> void:
	if state != "pause": return
	state = ""
	pause_root.visible = false
	get_tree().paused = false
	Game.input_locked = false
	Input.mouse_mode = prev_mouse if not OS.get_cmdline_user_args().has("--no-capture") else Input.MOUSE_MODE_VISIBLE
	Snd.play("ui_back", -6)

func _restart_checkpoint() -> void:
	close_pause()
	if Game.player: Game.player.respawn()
	if Game.combat: Game.combat.heal(Game.combat.MAX_HULL)

func _quit_to_title() -> void:
	Game.save()
	state = ""
	get_tree().paused = false
	Game.input_locked = false
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()

# ---------------------------------------------------------------- settings
func _open_settings() -> void:
	settings_from = state
	if state == "title": title_root.visible = false
	elif state == "pause": pause_root.visible = false
	state = "settings"
	settings_root.visible = true
	_sync_rows()
	(setting_rows.look.ctl as Control).grab_focus()
	Snd.play("ui_select", -6)

func _close_settings() -> void:
	_save_settings()
	settings_root.visible = false
	state = settings_from
	if state == "title":
		title_root.visible = true; title_buttons.get_child(2).grab_focus()
	else:
		state = "pause"; pause_root.visible = true; pause_buttons.get_child(1).grab_focus()
	Snd.play("ui_back", -6)

func _sync_rows() -> void:
	for k in setting_rows:
		var r: Dictionary = setting_rows[k]
		if r.ctl is HSlider: (r.ctl as HSlider).set_value_no_signal(settings[k]); r.val.text = "%d%%" % int(settings[k])
		else: (r.ctl as CheckButton).set_pressed_no_signal(settings[k]); r.val.text = "ON" if settings[k] else "OFF"

func _set_opt(k: String, v) -> void:
	settings[k] = v
	_sync_rows()
	_apply_settings()
	if k in ["sfx", "master"]: Snd.play("ui_move", -4, 0.0, 0.08)
	elif k == "voice": Snd.bark("dodger", "rate", 1.0)

# ---------------------------------------------------------------- UI
func _label(size: int, color: Color, bold := true) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font if bold else body)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0.04, 0.1, 0.9))
	l.add_theme_constant_override("outline_size", 10 if bold else 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _box(bg: Color, border: Color, r := 14, bw := 3) -> StyleBoxFlat:
	var s := StyleBoxFlat.new(); s.bg_color = bg; s.border_color = border; s.set_border_width_all(bw); s.set_corner_radius_all(r)
	s.content_margin_left = 22; s.content_margin_right = 22; s.content_margin_top = 10; s.content_margin_bottom = 10
	s.skew = Vector2(-0.12, 0)
	return s

func _button(text: String, cb: Callable, icon := "") -> Button:
	var b := Button.new(); b.text = text
	b.custom_minimum_size = Vector2(400, 62)
	b.add_theme_font_override("font", font); b.add_theme_font_size_override("font_size", 26)
	# the button is drawn by _draw_button in the HUD style; its own text and boxes stay invisible
	for k in ["font_color", "font_focus_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_disabled_color"]:
		b.add_theme_color_override(k, Color(0, 0, 0, 0))
	var e := StyleBoxEmpty.new()
	for k in ["normal", "hover", "focus", "pressed", "disabled", "hover_pressed"]: b.add_theme_stylebox_override(k, e)
	b.set_meta("icon", icon); b.set_meta("f", 0.0)
	b.draw.connect(_draw_button.bind(b))
	b.pressed.connect(cb)
	b.focus_entered.connect(func(): if state != "": Snd.play("ui_move", -10, 0.0, 0.0))
	b.mouse_entered.connect(func(): if not b.disabled: b.grab_focus())
	all_buttons.append(b)
	return b

## A menu button: a glossy slanted plate with an icon badge. The focused one slides right, warms to
## gold and gets a light sweep and a chevron.
func _draw_button(b: Button) -> void:
	var f: float = b.get_meta("f")
	var foc := b.has_focus()
	var a := 0.45 if b.disabled else 1.0
	var acc := CYAN.lerp(GOLD, f)
	var r := Rect2(Vector2(10 + 14.0 * f, 6), b.size - Vector2(34, 12))
	HD.panel(b, r, acc, 12, 0.12, a, HD.PANEL_TOP.lerp(Color(0.6, 0.4, 0.1, 0.97), f), HD.PANEL_BOT.lerp(Color(0.3, 0.17, 0.03, 0.97), f))
	var cy := r.get_center().y
	if foc:
		var sw := fposmod(ui_t * 0.7, 1.5)
		if sw < 1.0:
			var x := r.position.x + 40 + (r.size.x - 80) * sw
			b.draw_colored_polygon(PackedVector2Array([Vector2(x - 10, r.end.y - 3), Vector2(x + 14, r.end.y - 3), Vector2(x + 24, r.position.y + 3), Vector2(x, r.position.y + 3)]), Color(1, 1, 1, 0.16 * sin(sw * PI)))
	var tx := r.position.x + 26
	var ic: String = b.get_meta("icon")
	if ic != "":
		var bc := Vector2(r.position.x + 26, cy)
		HD.badge(b, bc, 18, acc, a)
		HD.icon(b, ic, bc, 10.5, acc.lightened(0.2), a)
		tx = r.position.x + 58
	HD.text(b, font, Vector2(tx, cy + 9), b.text, 25, Color(0.86, 0.95, 1.0).lerp(Color(1, 0.97, 0.88), f), 0, 6, a)
	if f > 0.05:
		var bob := sin(ui_t * 6.0) * 3.0
		HD.icon(b, "dash", Vector2(r.end.x - 26 + bob, cy), 9, GOLD, f * a)

static func _full(c: Control) -> void:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)

static func _center(c: Control, size: Vector2, off := Vector2.ZERO) -> void:
	c.anchor_left = 0.5; c.anchor_right = 0.5; c.anchor_top = 0.5; c.anchor_bottom = 0.5
	c.offset_left = -size.x / 2 + off.x; c.offset_right = size.x / 2 + off.x
	c.offset_top = -size.y / 2 + off.y; c.offset_bottom = size.y / 2 + off.y

func _build_ui() -> void:
	font = HD.head_font()
	body = HD.body_font()
	layer = CanvasLayer.new(); layer.layer = 90; add_child(layer)
	# ---- title ----
	title_root = Control.new(); _full(title_root); title_root.visible = false; layer.add_child(title_root)
	var grad := GradientTexture2D.new(); grad.fill_from = Vector2(0, 0); grad.fill_to = Vector2(1, 0); grad.width = 64; grad.height = 4
	var gg := Gradient.new(); gg.set_color(0, Color(0.01, 0.03, 0.08, 0.88)); gg.set_color(1, Color(0.01, 0.03, 0.08, 0.0)); grad.gradient = gg
	var shade := TextureRect.new(); shade.texture = grad; _full(shade); shade.anchor_right = 0.62
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_root.add_child(shade)
	var tv := VBoxContainer.new(); tv.add_theme_constant_override("separation", 0)
	tv.anchor_left = 0.06; tv.anchor_top = 0.12; tv.anchor_right = 0.6; tv.anchor_bottom = 0.95
	title_root.add_child(tv)
	var l1 := _label(56, Color(0.37, 0.95, 1.0)); l1.text = "UNLIKELY"
	var l2 := _label(104, Color(1, 0.72, 0.25)); l2.text = "HEROES"
	l2.add_theme_constant_override("outline_size", 18)
	var l3 := _label(22, Color(0.9, 0.95, 1.0), false); l3.text = "Episode 1  ·  SKYHARBOR"
	for l in [l1, l2, l3]: tv.add_child(l)
	var gap := Control.new(); gap.custom_minimum_size = Vector2(0, 46); tv.add_child(gap)
	title_buttons = VBoxContainer.new(); title_buttons.add_theme_constant_override("separation", 12); tv.add_child(title_buttons)
	continue_btn = _button("CONTINUE", func(): _start(true), "play")
	title_buttons.add_child(continue_btn)
	title_buttons.add_child(_button("NEW GAME", func(): _start(false), "star"))
	title_buttons.add_child(_button("SETTINGS", _open_settings, "sliders"))
	title_buttons.add_child(_button("QUIT", func(): get_tree().quit(), "power"))
	for b in title_buttons.get_children(): (b as Control).size_flags_horizontal = Control.SIZE_SHRINK_BEGIN; (b as Control).custom_minimum_size = Vector2(460, 62)
	var hint := _label(16, Color(0.8, 0.88, 0.95, 0.7), false)
	hint.text = "Arrows / stick to choose    Enter / A to select"
	hint.anchor_left = 0.06; hint.anchor_top = 0.93; hint.anchor_right = 0.6; hint.anchor_bottom = 0.98
	title_root.add_child(hint)
	# ---- pause ----
	pause_root = Control.new(); _full(pause_root); pause_root.visible = false; layer.add_child(pause_root)
	var dim := ColorRect.new(); dim.color = Color(0.0, 0.02, 0.05, 0.6); _full(dim); dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_root.add_child(dim)
	pause_art = Control.new(); _center(pause_art, PAUSE_SIZE); pause_art.pivot_offset = PAUSE_SIZE * 0.5
	pause_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_art.draw.connect(_draw_pause)
	pause_root.add_child(pause_art)
	pause_buttons = VBoxContainer.new(); pause_buttons.add_theme_constant_override("separation", 10)
	pause_buttons.position = Vector2(14, 128); pause_buttons.size = Vector2(440, 380)
	pause_art.add_child(pause_buttons)
	pause_buttons.add_child(_button("RESUME", close_pause, "play"))
	pause_buttons.add_child(_button("SETTINGS", _open_settings, "sliders"))
	pause_buttons.add_child(_button("RESTART FROM CHECKPOINT", _restart_checkpoint, "restart"))
	pause_buttons.add_child(_button("QUIT TO TITLE", _quit_to_title, "home"))
	pause_buttons.add_child(_button("QUIT GAME", func(): Game.save(); get_tree().quit(), "power"))
	for b in pause_buttons.get_children(): (b as Control).custom_minimum_size = Vector2(440, 62)
	# ---- settings ----
	settings_root = Control.new(); _full(settings_root); settings_root.visible = false; layer.add_child(settings_root)
	var dim2 := ColorRect.new(); dim2.color = Color(0.0, 0.02, 0.05, 0.65); _full(dim2); dim2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	settings_root.add_child(dim2)
	var sp := PanelContainer.new(); sp.add_theme_stylebox_override("panel", _panel_box())
	_center(sp, Vector2(780, 650)); settings_root.add_child(sp)
	sp.draw.connect(_draw_card.bind(sp))
	var sv := VBoxContainer.new(); sv.add_theme_constant_override("separation", 10); sp.add_child(sv)
	var st := _label(44, Color(1, 0.72, 0.25)); st.text = "SETTINGS"; st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; sv.add_child(st)
	_slider_row(sv, "look", "LOOK SENSITIVITY", 20, 250)
	_check_row(sv, "invert_y", "INVERT LOOK Y")
	_check_row(sv, "aim_assist", "CONTROLLER AIM ASSIST")
	_slider_row(sv, "master", "MASTER VOLUME", 0, 100)
	_slider_row(sv, "music", "MUSIC VOLUME", 0, 100)
	_slider_row(sv, "sfx", "EFFECTS VOLUME", 0, 100)
	_slider_row(sv, "voice", "VOICE VOLUME", 0, 100)
	_check_row(sv, "subtitles", "SUBTITLES")
	var back := _button("BACK", _close_settings); back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	sv.add_child(back)
	var sh := _label(15, Color(0.8, 0.88, 0.95, 0.7), false)
	sh.text = "Up / down to choose    left / right to change    Esc / B to go back"
	sh.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; sv.add_child(sh)

## Settings card: an empty box for the margins, with a HUD-style panel drawn behind its rows.
func _panel_box() -> StyleBox:
	var s := StyleBoxEmpty.new()
	s.content_margin_left = 40; s.content_margin_right = 40; s.content_margin_top = 26; s.content_margin_bottom = 28
	return s

func _draw_card(c: Control) -> void:
	HD.panel(c, Rect2(Vector2(8, 8), c.size - Vector2(16, 16)), CYAN, 20)

func _row(parent: Control, text: String) -> HBoxContainer:
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 18); parent.add_child(h)
	var l := _label(22, Color(0.88, 0.95, 1.0)); l.text = text; l.custom_minimum_size = Vector2(290, 0); h.add_child(l)
	return h

func _focus_box() -> StyleBoxFlat:
	var s := StyleBoxFlat.new(); s.bg_color = Color(0, 0, 0, 0); s.border_color = Color(1, 0.72, 0.25); s.set_border_width_all(3)
	s.set_corner_radius_all(8); s.expand_margin_left = 6; s.expand_margin_right = 6; s.expand_margin_top = 4; s.expand_margin_bottom = 4
	return s

func _slider_row(parent: Control, key: String, text: String, lo: float, hi: float) -> void:
	var h := _row(parent, text)
	var s := HSlider.new(); s.min_value = lo; s.max_value = hi; s.step = 5; s.custom_minimum_size = Vector2(260, 34)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_ALL
	var track := StyleBoxFlat.new(); track.bg_color = Color(0.1, 0.18, 0.26); track.set_corner_radius_all(5)
	track.content_margin_top = 5; track.content_margin_bottom = 5
	var fill := StyleBoxFlat.new(); fill.bg_color = Color(0.37, 0.95, 1.0); fill.set_corner_radius_all(5)
	fill.content_margin_top = 5; fill.content_margin_bottom = 5
	s.add_theme_stylebox_override("slider", track); s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill); s.add_theme_stylebox_override("focus", _focus_box())
	h.add_child(s)
	var v := _label(22, Color(1, 0.85, 0.4)); v.custom_minimum_size = Vector2(80, 0); v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(v)
	s.value_changed.connect(func(x): _set_opt(key, x))
	s.mouse_entered.connect(func(): s.grab_focus())
	setting_rows[key] = { ctl = s, val = v }

func _check_row(parent: Control, key: String, text: String) -> void:
	var h := _row(parent, text)
	var c := CheckButton.new(); c.focus_mode = Control.FOCUS_ALL; c.custom_minimum_size = Vector2(260, 34)
	c.add_theme_stylebox_override("focus", _focus_box())
	h.add_child(c)
	var v := _label(22, Color(1, 0.85, 0.4)); v.custom_minimum_size = Vector2(80, 0); v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(v)
	c.toggled.connect(func(on): _set_opt(key, on))
	c.mouse_entered.connect(func(): c.grab_focus())
	setting_rows[key] = { ctl = c, val = v }

# ---------------------------------------------------------------- pause screen art
## The pause screen: a header plate, the buttons on the left and a status card on the right with
## the current objective, sprockets, collectibles and the weapons you own (emblem, level, ammo).
func _draw_pause() -> void:
	var ci := pause_art
	var W := PAUSE_SIZE.x
	# header
	var hr := Rect2(6, 6, W - 12, 80)
	HD.panel(ci, hr, GOLD, 18, 0.0)
	var vb := Vector2(56, 46 + sin(ui_t * 2.2) * 2.0)
	HD.badge(ci, vb, 28, GOLD)
	HD.icon(ci, "vesk", vb, 22, Color(0.95, 0.62, 0.3))
	HD.text(ci, font, Vector2(102, 66), "PAUSED", 50, Color(1, 0.88, 0.5), 0, 8)
	HD.text(ci, font, Vector2(W - 34, 44), "SKYHARBOR", 28, CYAN, 2, 6)
	HD.text(ci, body, Vector2(W - 34, 68), "EPISODE 1", 15, Color(0.8, 0.88, 1.0), 2, 4)
	# left column backing (buttons sit on it)
	HD.panel(ci, Rect2(6, 112, 460, 406), CYAN, 18, 0.0, 0.9)
	# right status card
	var cr := Rect2(492, 112, W - 498, 406)
	HD.panel(ci, cr, CYAN, 18, 0.0)
	var x0 := cr.position.x + 26
	HD.icon(ci, "flag", Vector2(x0 + 12, cr.position.y + 34), 14, GOLD)
	HD.text(ci, font, Vector2(x0 + 36, cr.position.y + 42), "CURRENT JOB", 20, GOLD, 0, 5)
	var obj := ""
	if Game.hud and "obj_text" in Game.hud: obj = Game.hud.obj_text
	if obj == "": obj = "Explore Skyharbor."
	ci.draw_multiline_string_outline(body, Vector2(x0, cr.position.y + 76), obj, HORIZONTAL_ALIGNMENT_LEFT, cr.size.x - 52, 20, 2, 5, HD.INK)
	ci.draw_multiline_string(body, Vector2(x0, cr.position.y + 76), obj, HORIZONTAL_ALIGNMENT_LEFT, cr.size.x - 52, 20, 2, Color(0.92, 0.97, 1.0))
	ci.draw_line(Vector2(x0, cr.position.y + 124), Vector2(cr.end.x - 26, cr.position.y + 124), Color(CYAN, 0.35), 2.0)
	# three stat tiles
	var tiles := [["sprocket", GOLD, _thousands(Game.nuts()), "SPROCKETS"]]
	var counts: Array = Game.hud.collect_counts if Game.hud and "collect_counts" in Game.hud else []
	for k in counts:
		tiles.append([k[0], k[1], "%d/%d" % [k[2], k[3]], "LUCKY WASHERS" if k[0] == "washer" else ("PAGES" if k[0] == "page" else str(k[0]).to_upper())])
	var tw := (cr.size.x - 52 - 16.0 * (tiles.size() - 1)) / maxf(1.0, tiles.size())
	for i in tiles.size():
		var tl: Array = tiles[i]
		var r := Rect2(x0 + i * (tw + 16), cr.position.y + 142, tw, 84)
		HD.panel(ci, r, tl[1], 12, 0.0, 0.95)
		var bc := Vector2(r.position.x + 38, r.get_center().y)
		HD.badge(ci, bc, 22, tl[1])
		HD.icon(ci, tl[0], bc, 14, tl[1], 1.0, ui_t * 0.8 if tl[0] == "sprocket" else 0.0)
		HD.text(ci, font, Vector2(r.position.x + 72, r.position.y + 44), tl[2], 30, Color.WHITE, 0, 6)
		HD.text(ci, body, Vector2(r.position.x + 72, r.position.y + 66), tl[3], 13, Color(0.8, 0.88, 1.0), 0, 4)
	# arsenal
	HD.icon(ci, "ammo", Vector2(x0 + 10, cr.position.y + 262), 12, CYAN)
	HD.text(ci, font, Vector2(x0 + 32, cr.position.y + 270), "ARSENAL", 20, CYAN, 0, 5)
	var c := Game.combat
	if c == null or not "ORDER" in c: return
	var n: int = c.ORDER.size()
	var sw := (cr.size.x - 52 - 12.0 * (n - 1)) / n
	for i in n:
		var id: String = c.ORDER[i]
		var owned: bool = c.usable(id)
		var col: Color = c.weapon_color(id) if owned else Color(0.5, 0.55, 0.62)
		var r := Rect2(x0 + i * (sw + 12), cr.position.y + 286, sw, 100)
		HD.panel(ci, r, col, 12, 0.0, 0.95 if owned else 0.6)
		var nm: String = c.weapon_name(id) if owned else "LOCKED"
		var ns := 16
		while ns > 11 and font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, ns).x > sw - 22: ns -= 1
		HD.text(ci, font, Vector2(r.position.x + 12, r.position.y + 26), nm, ns, col.lightened(0.2) if owned else Color(0.65, 0.7, 0.78), 0, 5)
		var bc := Vector2(r.position.x + 32, r.position.y + 64)
		HD.badge(ci, bc, 18, col, 1.0 if owned else 0.7)
		HD.icon(ci, HD.weapon_icon(id) if owned else "lock", bc, 11, col if owned else Color(0.72, 0.76, 0.82), 1.0 if owned else 0.8)
		var tx := r.position.x + 62
		if owned:
			var lv: int = c.level(id)
			HD.text(ci, font, Vector2(tx, r.position.y + 64), "V%d" % lv, 19, GOLD if lv >= 5 else Color.WHITE, 0, 5)
			var am := "HEAT" if not c.uses_ammo(id) else "%d/%d" % [c.ammo(id), c.max_ammo(id)]
			HD.text(ci, body, Vector2(r.end.x - 12, r.position.y + 63), am, 13, Color(0.8, 0.88, 1.0), 2, 4)
			var f := 1.0 if not c.uses_ammo(id) else clampf(float(c.ammo(id)) / maxf(1.0, c.max_ammo(id)), 0.0, 1.0)
			var br := Rect2(tx, r.position.y + 74, r.end.x - 12 - tx, 7)
			ci.draw_colored_polygon(HD.rrect(br.grow(1.5), 4), HD.INK)
			ci.draw_colored_polygon(HD.rrect(br, 3), HD.SLOT)
			if f > 0.01: ci.draw_colored_polygon(HD.rrect(Rect2(br.position, Vector2(br.size.x * f, br.size.y)), 3), col)
		else:
			HD.text(ci, body, Vector2(tx, r.position.y + 60), "At Gizmart", 13, Color(0.7, 0.75, 0.82), 0, 4)
	# controls hint under the card
	var pad: bool = Game.player != null and "using_pad" in Game.player and Game.player.using_pad
	var hy := PAUSE_SIZE.y - 70
	var x := 24.0
	for pair in [["A" if pad else "Enter", "SELECT"], ["B" if pad else "Esc", "RESUME"]]:
		var kw := 36.0 if pad else maxf(34.0, font.get_string_size(pair[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 18.0)
		HD.keycap(ci, Vector2(x + kw * 0.5, hy), pair[0], pad)
		x += kw + 10
		x += HD.text(ci, font, Vector2(x, hy + 7), pair[1], 18, Color(0.9, 0.96, 1.0), 0, 5) + 30

static func _thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out
