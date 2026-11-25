extends CanvasLayer
## On-screen display: hull cells, sprocket counter, crosshair with hit markers, the weapon panel
## (name, level, ammo or heat, weapon XP), interact prompts, toasts, area banners, the damage
## vignette, subtitles and the boss health bar.
##
## Other systems can call: show_prompt(text) / hide_prompt(), toast(title, sub, color),
## toast_small(text, color), show_banner(title, sub, color). `subtitles` turns subtitles on/off.

var combat: Node3D
var player: Node3D
var root := Control.new()
var hull_box := HBoxContainer.new()
var cells: Array = []
var nut_label := Label.new()
var cross := Control.new()
var heat_bar := ProgressBar.new()
var weapon_label := Label.new()
var prompt := Label.new()
var banner := Label.new()
var banner_sub := Label.new()
var boss_box := VBoxContainer.new()
var boss_name := Label.new()
var boss_bar := ProgressBar.new()
var hit_t := 0.0
var hit_kill := false
var banner_t := 0.0
var font: Font
var nut_caption := Label.new()
var nut_gain := Label.new()
var nut_gain_n := 0
var nut_gain_t := 0.0
var nut_last := -1
var wpn_level := Label.new()
var ammo_label := Label.new()
var xp_bar := ProgressBar.new()
var vignette := TextureRect.new()
var vig_a := 0.0
var low_t := 0.0
var toast_box := VBoxContainer.new()
var ext_prompt := ""
var subtitles := true

var sub_label: Label
var obj_label := Label.new()
var sub_t := 0.0
const SPEAKER_NAMES := {"vesk": "VESK", "dodger": "DODGER", "grudd": "FOREMAN GRUDD", "gizmart": "GIZMART", "narrator": ""}
const SPEAKER_COLORS := {"vesk": Color(1, 0.62, 0.25), "dodger": Color(0.5, 0.9, 1), "grudd": Color(1, 0.35, 0.3), "gizmart": Color(0.6, 1, 0.5), "narrator": Color(1, 1, 1)}

func _subtitle(_id: String, sp: String, text: String) -> void:
	var who: String = SPEAKER_NAMES.get(sp, sp.to_upper())
	sub_label.text = (who + ":  " if who != "" else "") + text
	sub_label.add_theme_color_override("font_color", SPEAKER_COLORS.get(sp, Color.WHITE))
	sub_label.modulate.a = 1.0 if subtitles else 0.0; sub_t = 1.2 + text.length() * 0.06

func _ready() -> void:
	sub_label = Label.new(); sub_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; sub_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub_label.custom_minimum_size = Vector2(900, 0); sub_label.position = Vector2(-450, -150)
	sub_label.add_theme_font_size_override("font_size", 26)
	sub_label.add_theme_constant_override("outline_size", 8); sub_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	add_child(sub_label); sub_label.modulate.a = 0.0
	Snd.line_started.connect(_subtitle)
	Game.boss_started.connect(func(n): set_boss(n, 1.0))
	Game.boss_health.connect(func(n, f): set_boss(n, f))
	Game.boss_defeated.connect(func(_n): set_boss("", 0.0))
	obj_label.position = Vector2(28, 66); obj_label.add_theme_font_size_override("font_size", 20)
	obj_label.add_theme_constant_override("outline_size", 6); obj_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	obj_label.add_theme_color_override("font_color", Color(1, 0.92, 0.6))
	add_child(obj_label)
	Game.objective_set.connect(func(_id, text): obj_label.text = "> " + text; _pop(obj_label))
	font = SystemFont.new()
	(font as SystemFont).font_names = PackedStringArray(["Inter", "Segoe UI", "Arial", "sans-serif"])
	(font as SystemFont).font_weight = 900
	(font as SystemFont).font_italic = true
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	# damage vignette: red edges that flash when Vesk is hit and pulse while hull is low
	var vg := GradientTexture2D.new(); vg.fill = GradientTexture2D.FILL_RADIAL
	vg.fill_from = Vector2(0.5, 0.5); vg.fill_to = Vector2(1.05, 0.5); vg.width = 256; vg.height = 256
	var vgr := Gradient.new(); vgr.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	vgr.colors = PackedColorArray([Color(1, 0.1, 0.05, 0), Color(1, 0.1, 0.05, 0.05), Color(0.9, 0.05, 0.02, 0.85)])
	vg.gradient = vgr
	vignette.texture = vg; vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE; vignette.modulate.a = 0.0
	root.add_child(vignette)
	# hull cells, top left
	hull_box.position = Vector2(28, 24)
	hull_box.add_theme_constant_override("separation", 6)
	root.add_child(hull_box)
	for i in 8:
		var c := Panel.new(); c.custom_minimum_size = Vector2(26, 30)
		var sb := StyleBoxFlat.new(); sb.bg_color = Color(0.37, 0.95, 1.0); sb.set_corner_radius_all(8); sb.skew = Vector2(-0.15, 0)
		sb.border_color = Color(1, 1, 1, 0.8); sb.set_border_width_all(2)
		c.add_theme_stylebox_override("panel", sb)
		hull_box.add_child(c); cells.append(sb)
	# nuts, top right
	nut_label.text = "0"
	_style(nut_label, 44, Color(1, 0.85, 0.35))
	nut_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	nut_label.position = Vector2(-260, 16); nut_label.size = Vector2(230, 60)
	nut_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(nut_label)
	_style(nut_caption, 16, Color(1, 0.85, 0.35, 0.85)); nut_caption.text = "SPROCKETS"
	nut_caption.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	nut_caption.position = Vector2(-260, 70); nut_caption.size = Vector2(230, 22)
	nut_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(nut_caption)
	_style(nut_gain, 26, Color(1, 0.95, 0.6))
	nut_gain.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	nut_gain.position = Vector2(-260, 92); nut_gain.size = Vector2(230, 34)
	nut_gain.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; nut_gain.modulate.a = 0.0
	root.add_child(nut_gain)
	# toasts (collectibles, ammo), right side under the counter
	toast_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	toast_box.position = Vector2(-440, 140); toast_box.size = Vector2(410, 300)
	toast_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	toast_box.add_theme_constant_override("separation", 8)
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toast_box)
	# crosshair
	cross.set_anchors_preset(Control.PRESET_CENTER)
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cross.draw.connect(_draw_cross)
	root.add_child(cross)
	# weapon + heat, bottom right
	weapon_label.text = "ARC LANCER"
	_style(weapon_label, 30, Color(0.6, 0.97, 1.0))
	weapon_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	weapon_label.position = Vector2(-420, -124); weapon_label.size = Vector2(330, 40)
	weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(weapon_label)
	_style(wpn_level, 30, Color(1, 1, 1))
	wpn_level.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	wpn_level.position = Vector2(-86, -124); wpn_level.size = Vector2(60, 40)
	wpn_level.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(wpn_level)
	_style(ammo_label, 26, Color(1, 1, 1))
	ammo_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ammo_label.position = Vector2(-330, -86); ammo_label.size = Vector2(300, 32)
	ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(ammo_label)
	xp_bar.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	xp_bar.position = Vector2(-330, -40); xp_bar.size = Vector2(300, 6)
	xp_bar.show_percentage = false; xp_bar.max_value = 1.0
	var xbg := StyleBoxFlat.new(); xbg.bg_color = Color(0, 0, 0, 0.45); xbg.set_corner_radius_all(3)
	var xfg := StyleBoxFlat.new(); xfg.bg_color = Color(1, 0.85, 0.35); xfg.set_corner_radius_all(3)
	xp_bar.add_theme_stylebox_override("background", xbg); xp_bar.add_theme_stylebox_override("fill", xfg)
	root.add_child(xp_bar)
	heat_bar.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	heat_bar.position = Vector2(-330, -62); heat_bar.size = Vector2(300, 14)
	heat_bar.show_percentage = false; heat_bar.max_value = 1.0
	var bg := StyleBoxFlat.new(); bg.bg_color = Color(0, 0, 0, 0.45); bg.set_corner_radius_all(7)
	var fg := StyleBoxFlat.new(); fg.bg_color = Color(0.37, 0.95, 1.0); fg.set_corner_radius_all(7)
	heat_bar.add_theme_stylebox_override("background", bg); heat_bar.add_theme_stylebox_override("fill", fg)
	root.add_child(heat_bar)
	# swing prompt
	_style(prompt, 26, Color(1, 0.9, 0.6))
	prompt.set_anchors_preset(Control.PRESET_CENTER)
	prompt.position = Vector2(-200, 90); prompt.size = Vector2(400, 40)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(prompt)
	# banner
	_style(banner, 64, Color(1, 0.85, 0.3))
	banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner.position = Vector2(-600, 150); banner.size = Vector2(1200, 80)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(banner)
	_style(banner_sub, 26, Color(1, 1, 1))
	banner_sub.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner_sub.position = Vector2(-600, 230); banner_sub.size = Vector2(1200, 40)
	banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(banner_sub)
	# boss bar
	boss_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	boss_box.position = Vector2(-360, 22); boss_box.size = Vector2(720, 60)
	_style(boss_name, 24, Color(1, 0.55, 0.4)); boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_box.add_child(boss_name)
	boss_bar.custom_minimum_size = Vector2(720, 18); boss_bar.show_percentage = false; boss_bar.max_value = 1.0
	var bfg := StyleBoxFlat.new(); bfg.bg_color = Color(1, 0.35, 0.25); bfg.set_corner_radius_all(9)
	boss_bar.add_theme_stylebox_override("background", bg); boss_bar.add_theme_stylebox_override("fill", bfg)
	boss_box.add_child(boss_bar)
	boss_box.visible = false
	root.add_child(boss_box)
	combat.nuts_changed.connect(_nuts)
	combat.hull_changed.connect(_hull)
	combat.hit_marker.connect(func(k): hit_t = 0.18; hit_kill = k)
	combat.weapon_changed.connect(func(_id): _refresh_weapon(); _pop(weapon_label))
	combat.ammo_changed.connect(func(_id, _a, _m): _refresh_weapon())
	combat.weapon_xp.connect(func(_id, _l, _f): _refresh_weapon())
	combat.weapon_level_up.connect(_level_up)
	Game.player_hurt.connect(func(_h): vig_a = 0.75)
	_refresh_weapon()

func _style(l: Label, size: int, color: Color) -> void:
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0.05, 0.1, 0.85))
	l.add_theme_constant_override("outline_size", 10)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _pop(c: Control) -> void:
	c.pivot_offset = c.size * Vector2(1, 0.5)
	var tw := create_tween(); c.scale = Vector2(1.15, 1.15); tw.tween_property(c, "scale", Vector2.ONE, 0.12)

func _nuts(n: int) -> void:
	nut_label.text = str(n); _pop(nut_label)
	if nut_last >= 0 and n > nut_last:
		nut_gain_n += n - nut_last; nut_gain_t = 1.4
		nut_gain.text = "+%d" % nut_gain_n; nut_gain.modulate.a = 1.0; _pop(nut_gain)
	nut_last = n

func _refresh_weapon() -> void:
	if combat == null or not combat.has_method("weapon_name"): return
	var id: String = combat.current
	var c: Color = combat.weapon_color(id)
	weapon_label.text = combat.weapon_name(id)
	weapon_label.add_theme_color_override("font_color", c)
	var lv: int = combat.level(id)
	wpn_level.text = "V%d" % lv
	wpn_level.add_theme_color_override("font_color", Color(1, 0.82, 0.3) if lv >= 5 else Color(1, 1, 1))
	xp_bar.value = combat.xp_frac(id)
	(xp_bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = Color(1, 0.82, 0.3) if lv >= 5 else c
	var lancer: bool = not combat.uses_ammo(id)
	heat_bar.visible = lancer
	ammo_label.visible = not lancer
	if not lancer:
		var a: int = combat.ammo(id)
		ammo_label.text = "%d / %d" % [a, combat.max_ammo(id)]
		ammo_label.add_theme_color_override("font_color", Color(1, 0.4, 0.3) if a <= 0 else (Color(1, 0.8, 0.4) if a * 4 <= combat.max_ammo(id) else Color(1, 1, 1)))

func _level_up(id: String, lv: int) -> void:
	_refresh_weapon(); _pop(wpn_level)
	if lv >= 5:
		show_banner("%s V5" % combat.WEAPONS[id].name, "EVOLVED INTO THE %s!" % combat.WEAPONS[id].v5, Color(1, 0.82, 0.3))
	else:
		toast("%s  V%d" % [combat.WEAPONS[id].name, lv], "Weapon level up! Bigger magazine, harder hits.", combat.weapon_color(id))

## A prompt under the crosshair, e.g. show_prompt("E   OPEN THE VAULT"). hide_prompt() clears it.
func show_prompt(text: String) -> void:
	ext_prompt = text

func hide_prompt() -> void:
	ext_prompt = ""

## A toast card on the right: a bold title and an optional line under it. Fades after a few seconds.
func toast(title: String, sub := "", color := Color(1, 0.85, 0.3), seconds := 3.6) -> void:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new(); sb.bg_color = Color(0.03, 0.06, 0.1, 0.82); sb.border_color = color
	sb.border_width_left = 6; sb.set_corner_radius_all(10)
	sb.content_margin_left = 16; sb.content_margin_right = 16; sb.content_margin_top = 8; sb.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", sb); card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 0); card.add_child(v)
	var t := Label.new(); _style(t, 26, color); t.text = title; v.add_child(t)
	if sub != "":
		var s2 := Label.new(); _style(s2, 17, Color(0.92, 0.95, 1)); s2.text = sub
		s2.add_theme_constant_override("outline_size", 4)
		s2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; s2.custom_minimum_size = Vector2(370, 0); v.add_child(s2)
	toast_box.add_child(card)
	while toast_box.get_child_count() > 4: toast_box.get_child(0).queue_free(); toast_box.remove_child(toast_box.get_child(0))
	card.modulate.a = 0.0
	var tw := card.create_tween()
	tw.tween_property(card, "modulate:a", 1.0, 0.18)
	tw.tween_interval(seconds)
	tw.tween_property(card, "modulate:a", 0.0, 0.5)
	tw.tween_callback(card.queue_free)

## A one-line toast (ammo pickups, progress ticks).
func toast_small(text: String, color := Color(1, 1, 1)) -> void:
	toast(text, "", color, 1.4)

func _hull(h: int, healed: bool) -> void:
	for i in cells.size():
		var sb: StyleBoxFlat = cells[i]
		sb.bg_color = Color(0.37, 0.95, 1.0) if i < h else Color(0.1, 0.15, 0.2, 0.6)
	if not healed: _pop(hull_box)

func show_banner(title: String, sub := "", color := Color(1, 0.85, 0.3)) -> void:
	banner.text = title; banner_sub.text = sub
	banner.add_theme_color_override("font_color", color)
	banner_t = 3.0

func set_boss(name_: String, frac: float) -> void:
	boss_box.visible = name_ != ""
	boss_name.text = name_
	boss_bar.value = lerpf(boss_bar.value, frac, 0.3)

func _draw_cross() -> void:
	var c := Vector2.ZERO
	var col := Color(1, 1, 1, 0.9)
	var gap := 7.0 + (6.0 if hit_t > 0.0 else 0.0)
	for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		cross.draw_line(c + d * gap, c + d * (gap + 9.0), col, 2.5)
	cross.draw_circle(c, 2.0, col)
	if hit_t > 0.0:
		var hc := Color(1, 0.4, 0.3) if hit_kill else Color(1, 1, 1)
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			cross.draw_line(c + d.normalized() * 10.0, c + d.normalized() * 18.0, hc, 3.0)

func _process(dt: float) -> void:
	sub_t -= dt
	if sub_t <= 0.0: sub_label.modulate.a = maxf(0.0, sub_label.modulate.a - dt * 3.0)
	hit_t -= dt
	cross.queue_redraw()
	heat_bar.value = combat.heat
	(heat_bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = Color(1, 0.35, 0.2) if combat.overheated else Color(0.37, 0.95, 1.0)
	prompt.text = ext_prompt
	if player and player.hook_target:
		prompt.text = ("Y" if player.using_pad else "E") + "   SWING"
	heat_bar.value = combat.heat
	# damage vignette: flash on hits, slow pulse when the hull is nearly empty
	vig_a = maxf(0.0, vig_a - dt * 1.6)
	var low := 0.0
	if combat.hull <= 2:
		low_t += dt; low = 0.22 + 0.12 * sin(low_t * 5.0)
	vignette.modulate.a = maxf(vig_a, low)
	nut_gain_t -= dt
	if nut_gain_t <= 0.0:
		nut_gain.modulate.a = maxf(0.0, nut_gain.modulate.a - dt * 3.0)
		if nut_gain.modulate.a <= 0.0: nut_gain_n = 0
	banner_t -= dt
	var a := clampf(banner_t, 0.0, 1.0)
	banner.modulate.a = a; banner_sub.modulate.a = a
