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

var settings := { look = 100.0, invert_y = false, master = 100.0, music = 80.0, sfx = 100.0, voice = 100.0, subtitles = true }

var layer: CanvasLayer
var font: SystemFont
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
	if Game.hud and "subtitles" in Game.hud: Game.hud.subtitles = settings.subtitles
	_route_snd()

func _process(dt: float) -> void:
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
			"": if _can_pause(): open_pause(); get_viewport().set_input_as_handled()
			"pause": close_pause(); get_viewport().set_input_as_handled()
			"settings": _close_settings(); get_viewport().set_input_as_handled()
	elif e.is_action_pressed("ui_cancel") and not (e is InputEventKey):
		# pad B backs out (Esc already handled as "pause")
		match state:
			"pause": close_pause(); get_viewport().set_input_as_handled()
			"settings": _close_settings(); get_viewport().set_input_as_handled()

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
	else:
		Game.reset_save()
		Game.data.nuts = 0; Game.data.unlocked = {"arc_lancer": true}; Game.data.collected = {}; Game.data.completed = {}
		Game.data.checkpoint = -1; Game.data.erase("weapons"); Game.data.erase("weapon"); Game.data.erase("gripes")
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
	pause_root.create_tween().tween_property(pause_root, "modulate:a", 1.0, 0.12)
	pause_buttons.get_child(0).grab_focus()
	Snd.play("ui_select", -6)

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
	if bold: l.add_theme_font_override("font", font)
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

func _button(text: String, cb: Callable) -> Button:
	var b := Button.new(); b.text = text
	b.custom_minimum_size = Vector2(380, 58)
	b.add_theme_font_override("font", font); b.add_theme_font_size_override("font_size", 28)
	b.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	b.add_theme_color_override("font_focus_color", Color(0.05, 0.08, 0.12))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_color_override("font_disabled_color", Color(0.5, 0.55, 0.6, 0.6))
	b.add_theme_stylebox_override("normal", _box(Color(0.04, 0.09, 0.15, 0.82), Color(0.37, 0.95, 1.0, 0.4), 12, 2))
	b.add_theme_stylebox_override("hover", _box(Color(0.08, 0.16, 0.25, 0.9), Color(0.37, 0.95, 1.0, 0.9), 12, 2))
	b.add_theme_stylebox_override("focus", _box(Color(1, 0.72, 0.25, 0.98), Color(1, 0.95, 0.75), 12, 3))
	b.add_theme_stylebox_override("pressed", _box(Color(1, 0.85, 0.4, 1.0), Color(1, 1, 1), 12, 3))
	b.add_theme_stylebox_override("disabled", _box(Color(0.04, 0.07, 0.1, 0.6), Color(0.3, 0.35, 0.4, 0.4), 12, 2))
	b.pressed.connect(cb)
	b.focus_entered.connect(func(): if state != "": Snd.play("ui_move", -10, 0.0, 0.0))
	b.mouse_entered.connect(func(): if not b.disabled: b.grab_focus())
	return b

static func _full(c: Control) -> void:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)

static func _center(c: Control, size: Vector2, off := Vector2.ZERO) -> void:
	c.anchor_left = 0.5; c.anchor_right = 0.5; c.anchor_top = 0.5; c.anchor_bottom = 0.5
	c.offset_left = -size.x / 2 + off.x; c.offset_right = size.x / 2 + off.x
	c.offset_top = -size.y / 2 + off.y; c.offset_bottom = size.y / 2 + off.y

func _build_ui() -> void:
	font = SystemFont.new(); font.font_names = PackedStringArray(["Inter", "Segoe UI", "Arial", "sans-serif"])
	font.font_weight = 900; font.font_italic = true
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
	continue_btn = _button("CONTINUE", func(): _start(true))
	title_buttons.add_child(continue_btn)
	title_buttons.add_child(_button("NEW GAME", func(): _start(false)))
	title_buttons.add_child(_button("SETTINGS", _open_settings))
	title_buttons.add_child(_button("QUIT", func(): get_tree().quit()))
	var hint := _label(16, Color(0.8, 0.88, 0.95, 0.7), false)
	hint.text = "Arrows / stick to choose    Enter / A to select"
	hint.anchor_left = 0.06; hint.anchor_top = 0.93; hint.anchor_right = 0.6; hint.anchor_bottom = 0.98
	title_root.add_child(hint)
	# ---- pause ----
	pause_root = Control.new(); _full(pause_root); pause_root.visible = false; layer.add_child(pause_root)
	var dim := ColorRect.new(); dim.color = Color(0.0, 0.02, 0.05, 0.6); _full(dim); dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_root.add_child(dim)
	var pp := PanelContainer.new(); pp.add_theme_stylebox_override("panel", _panel_box())
	_center(pp, Vector2(560, 400)); pause_root.add_child(pp)
	var pv := VBoxContainer.new(); pv.add_theme_constant_override("separation", 12); pp.add_child(pv)
	var pt := _label(54, Color(1, 0.72, 0.25)); pt.text = "PAUSED"; pt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; pv.add_child(pt)
	pause_buttons = VBoxContainer.new(); pause_buttons.add_theme_constant_override("separation", 12)
	pause_buttons.alignment = BoxContainer.ALIGNMENT_CENTER; pv.add_child(pause_buttons)
	pause_buttons.add_child(_button("RESUME", close_pause))
	pause_buttons.add_child(_button("SETTINGS", _open_settings))
	pause_buttons.add_child(_button("RESTART FROM CHECKPOINT", _restart_checkpoint))
	pause_buttons.add_child(_button("QUIT TO TITLE", _quit_to_title))
	for b in pause_buttons.get_children(): (b as Control).size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# ---- settings ----
	settings_root = Control.new(); _full(settings_root); settings_root.visible = false; layer.add_child(settings_root)
	var dim2 := ColorRect.new(); dim2.color = Color(0.0, 0.02, 0.05, 0.65); _full(dim2); dim2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	settings_root.add_child(dim2)
	var sp := PanelContainer.new(); sp.add_theme_stylebox_override("panel", _panel_box())
	_center(sp, Vector2(760, 560)); settings_root.add_child(sp)
	var sv := VBoxContainer.new(); sv.add_theme_constant_override("separation", 10); sp.add_child(sv)
	var st := _label(44, Color(1, 0.72, 0.25)); st.text = "SETTINGS"; st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; sv.add_child(st)
	_slider_row(sv, "look", "LOOK SENSITIVITY", 20, 250)
	_check_row(sv, "invert_y", "INVERT LOOK Y")
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

func _panel_box() -> StyleBoxFlat:
	var s := StyleBoxFlat.new(); s.bg_color = Color(0.02, 0.06, 0.11, 0.94); s.border_color = Color(0.37, 0.95, 1.0, 0.8)
	s.set_border_width_all(3); s.set_corner_radius_all(22)
	s.content_margin_left = 34; s.content_margin_right = 34; s.content_margin_top = 22; s.content_margin_bottom = 24
	return s

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
