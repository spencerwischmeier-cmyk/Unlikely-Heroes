extends CanvasLayer
## On-screen display. Every readout sits in its own glossy panel with an icon, so it's clear at a glance:
##   top left     HULL (shield + cells), JET / DASH readiness, the current OBJECTIVE
##   top right    SPROCKETS (gear + count), collectibles found here (washers, pages), toast cards
##   top centre   the boss panel (only bosses get a health bar)
##   bottom right the weapon panel: emblem medallion, name, V-level, ammo or heat, weapon XP
##   centre       crosshair with hit markers, button prompts (key caps on keyboard, face buttons on pad)
##   plus the area banner, subtitles and the damage vignette.
## Panels are anchored to the screen corners, so the layout holds on any aspect ratio.
##
## Other systems can call: show_prompt(text) / hide_prompt(), toast(title, sub, color, seconds, icon),
## toast_small(text, color), show_banner(title, sub, color). `subtitles` turns subtitles on/off.
## Prompt text starts with the key: "E   OPEN THE VAULT" (pad letters A/B/X/Y draw as face buttons).

const HD := preload("res://scripts/ui/hud_draw.gd")

const HULL_COL := Color(0.3, 0.95, 0.78)
const LOW_COL := Color(1.0, 0.3, 0.25)
const JET_COL := Color(1.0, 0.62, 0.22)
const GOLD := Color(1.0, 0.82, 0.3)
const OBJ_COL := Color(1.0, 0.86, 0.35)
const BOSS_COL := Color(1.0, 0.34, 0.26)
const SPEAKER_NAMES := {"vesk": "VESK", "dodger": "DODGER", "grudd": "FOREMAN GRUDD", "gizmart": "GIZMART", "narrator": ""}
const SPEAKER_COLORS := {"vesk": Color(1, 0.62, 0.25), "dodger": Color(0.5, 0.9, 1), "grudd": Color(1, 0.35, 0.3), "gizmart": Color(0.6, 1, 0.5), "narrator": Color(1, 1, 1)}
const COLLECT_KINDS := [["washer", Color(0.95, 0.8, 0.4)], ["page", Color(1.0, 0.55, 0.78)]]

var combat: Node3D
var player: Node3D
var subtitles := true

var head: Font
var body: Font
var root := Control.new()
var vignette := TextureRect.new()
var vitals := Control.new()
var objective := Control.new()
var wallet := Control.new()
var collect := Control.new()
var weapon := Control.new()
var boss := Control.new()
var cross := Control.new()
var prompt := Control.new()
var banner := Control.new()
var subs := Control.new()
var toast_box := VBoxContainer.new()

# state
var hull := 8
var hull_max := 8
var cell_flash: Array = []
var hull_pop := 0.0
var low_t := 0.0
var vig_a := 0.0
var hit_t := 0.0
var hit_kill := false
var nuts := 0
var nut_shown := 0.0
var nut_last := -1
var nut_gain_n := 0
var nut_gain_t := 0.0
var gear_rot := 0.0
var gear_spin := 0.0
var wallet_pop := 0.0
var collect_counts: Array = []       # [kind, colour, found, total]
var collect_pop := 0.0
var obj_text := ""
var obj_t := 0.0                      # time since the objective changed
var wpn_pop := 0.0
var lvl_pop := 0.0
var ammo_pop := 0.0
var heat_shown := 0.0
var boss_name := ""
var boss_frac := 1.0
var boss_trail := 1.0
var boss_a := 0.0
var boss_hit := 0.0
var ext_prompt := ""
var prompt_a := 0.0
var prompt_text := ""
var banner_title := ""
var banner_sub := ""
var banner_col := GOLD
var banner_t := 0.0
var sub_who := ""
var sub_text := ""
var sub_col := Color.WHITE
var sub_t := 0.0
var sub_a := 0.0
var t := 0.0

## Kept for callers that still poke at the old label (e.g. tests).
var obj_label: Label = Label.new()

# ---------------------------------------------------------------- build
func _ready() -> void:
	head = HD.head_font(); body = HD.body_font()
	root.set_anchors_preset(Control.PRESET_FULL_RECT); root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_vignette()
	_place(vitals, Vector2(0, 0), Rect2(18, 14, 420, 104), _draw_vitals)
	_place(objective, Vector2(0, 0), Rect2(18, 122, 640, 104), _draw_objective)
	_place(wallet, Vector2(1, 0), Rect2(-300, 14, 282, 76), _draw_wallet)
	_place(collect, Vector2(1, 0), Rect2(-300, 92, 282, 46), _draw_collect)
	_place(boss, Vector2(0.5, 0), Rect2(-340, 10, 680, 84), _draw_boss)
	_place(weapon, Vector2(1, 1), Rect2(-470, -156, 452, 140), _draw_weapon)
	_place(cross, Vector2(0.5, 0.5), Rect2(-40, -40, 80, 80), _draw_cross)
	_place(prompt, Vector2(0.5, 0.5), Rect2(-320, 70, 640, 60), _draw_prompt)
	_place(banner, Vector2(0.5, 0), Rect2(-640, 150, 1280, 150), _draw_banner)
	_place(subs, Vector2(0.5, 1), Rect2(-520, -190, 1040, 170), _draw_subs)
	toast_box.anchor_left = 1; toast_box.anchor_right = 1
	toast_box.offset_left = -440; toast_box.offset_right = -18; toast_box.offset_top = 146; toast_box.offset_bottom = 560
	toast_box.add_theme_constant_override("separation", 10); toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toast_box)
	for i in (combat.MAX_HULL if combat and "MAX_HULL" in combat else 8): cell_flash.append(0.0)
	hull_max = cell_flash.size(); hull = hull_max
	# events
	Snd.line_started.connect(_subtitle)
	Game.boss_started.connect(func(n): set_boss(n, 1.0))
	Game.boss_health.connect(func(n, f): set_boss(n, f))
	Game.boss_defeated.connect(func(_n): set_boss("", 0.0))
	Game.objective_set.connect(func(_id, text): _set_objective(text))
	Game.collectible_found.connect(func(_k, _id): _refresh_collect(); collect_pop = 1.0)
	Game.player_hurt.connect(func(_h): vig_a = 0.75)
	combat.nuts_changed.connect(_nuts)
	combat.hull_changed.connect(_hull)
	combat.hit_marker.connect(func(k): hit_t = 0.18; hit_kill = k)
	combat.weapon_changed.connect(func(_id): wpn_pop = 1.0)
	combat.ammo_changed.connect(func(_id, _a, _m): ammo_pop = 1.0)
	combat.weapon_level_up.connect(_level_up)
	if "hull" in combat: hull = combat.hull
	_refresh_collect.call_deferred()
	if OS.get_cmdline_user_args().has("--hud-demo"): _demo()

## Debug (--hud-demo): show every panel at once for screenshots: a toast, sprockets pouring in and a boss bar.
func _demo() -> void:
	await get_tree().create_timer(2.0).timeout
	Game.add_nuts(1240)
	toast("LUCKY WASHER  1/3", "Lucky! Trade washers for cosmetics and cheats.", GOLD)
	await get_tree().create_timer(1.0).timeout
	toast_small("+12 SEEKER HIVE AMMO", Color(1.0, 0.8, 0.25))
	Game.add_nuts(25)
	set_boss("CRANE BOT", 0.8)
	await get_tree().create_timer(0.2).timeout
	set_boss("CRANE BOT", 0.62)
	show_prompt("E   SHOP AT GIZMART")

func _place(c: Control, anchor: Vector2, r: Rect2, fn: Callable) -> void:
	c.anchor_left = anchor.x; c.anchor_right = anchor.x; c.anchor_top = anchor.y; c.anchor_bottom = anchor.y
	c.offset_left = r.position.x; c.offset_top = r.position.y
	c.offset_right = r.end.x; c.offset_bottom = r.end.y
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(fn)
	root.add_child(c)

func _build_vignette() -> void:
	# red edges that flash when Vesk is hit and pulse while the hull is low
	var vg := GradientTexture2D.new(); vg.fill = GradientTexture2D.FILL_RADIAL
	vg.fill_from = Vector2(0.5, 0.5); vg.fill_to = Vector2(1.05, 0.5); vg.width = 256; vg.height = 256
	var g := Gradient.new(); g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	g.colors = PackedColorArray([Color(1, 0.1, 0.05, 0), Color(1, 0.1, 0.05, 0.05), Color(0.9, 0.05, 0.02, 0.85)])
	vg.gradient = g
	vignette.texture = vg; vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE; vignette.modulate.a = 0.0
	root.add_child(vignette)

# ---------------------------------------------------------------- events
func _subtitle(_id: String, sp: String, text: String) -> void:
	sub_who = SPEAKER_NAMES.get(sp, sp.to_upper())
	sub_col = SPEAKER_COLORS.get(sp, Color.WHITE)
	sub_text = text
	sub_t = 1.2 + text.length() * 0.06

func _set_objective(text: String) -> void:
	if text == obj_text: return
	obj_text = text; obj_t = 0.0; obj_label.text = "> " + text

func _nuts(n: int) -> void:
	nuts = n
	if nut_last >= 0 and n > nut_last:
		nut_gain_n += n - nut_last; nut_gain_t = 1.6; gear_spin = 1.0; wallet_pop = 1.0
	elif nut_last < 0:
		nut_shown = n
	nut_last = n

func _hull(h: int, healed: bool) -> void:
	for i in cell_flash.size():
		if (i < hull) != (i < h): cell_flash[i] = 1.0
	hull = h
	if not healed: hull_pop = 1.0

func _level_up(id: String, lv: int) -> void:
	lvl_pop = 1.0
	if lv >= 5:
		show_banner("%s V5" % combat.WEAPONS[id].name, "EVOLVED INTO THE %s!" % combat.WEAPONS[id].v5, GOLD)
	else:
		toast("%s  V%d" % [combat.WEAPONS[id].name, lv], "Weapon level up! Bigger magazine, harder hits.", combat.weapon_color(id), 3.6, "up")

func _refresh_collect() -> void:
	collect_counts.clear()
	var spots = Game.level.get("pickup_spots") if Game.level else null
	if not spots is Array: return
	for k in COLLECT_KINDS:
		var found := 0
		var total := 0
		for s in spots:
			if s.kind != k[0]: continue
			total += 1
			if Game.is_collected(k[0], s.id): found += 1
		if total > 0: collect_counts.append([k[0], k[1], found, total])

# ---------------------------------------------------------------- public API
## A prompt under the crosshair, e.g. show_prompt("E   OPEN THE VAULT"). hide_prompt() clears it.
func show_prompt(text: String) -> void:
	ext_prompt = text

func hide_prompt() -> void:
	ext_prompt = ""

## A toast card on the right: an icon, a bold title and an optional line under it. Fades after a few seconds.
## icon: any HUD icon name ("ammo", "washer", "page", "gripe", "up", "lock", "star"...). Guessed from the title if empty.
func toast(title: String, sub := "", color := GOLD, seconds := 3.6, icon := "") -> void:
	if icon == "": icon = _guess_icon(title)
	var card := Control.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var w := 422.0
	var sub_h := 0.0
	if sub != "": sub_h = body.get_multiline_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, w - 96, 17).y
	card.custom_minimum_size = Vector2(w, maxf(62.0, 44.0 + sub_h + 10.0))
	card.set_meta("d", {title = title, sub = sub, color = color, icon = icon, born = t})
	card.draw.connect(_draw_toast.bind(card))
	toast_box.add_child(card)
	while toast_box.get_child_count() > 4:
		var old := toast_box.get_child(0); toast_box.remove_child(old); old.queue_free()
	card.modulate.a = 0.0
	var tw := card.create_tween()
	tw.tween_property(card, "modulate:a", 1.0, 0.18)
	tw.tween_interval(seconds)
	tw.tween_property(card, "modulate:a", 0.0, 0.5)
	tw.tween_callback(card.queue_free)

## A one-line toast (ammo pickups, progress ticks).
func toast_small(text: String, color := Color(1, 1, 1)) -> void:
	toast(text, "", color, 1.4)

func show_banner(title: String, sub := "", color := GOLD) -> void:
	banner_title = title; banner_sub = sub; banner_col = color; banner_t = 3.2

func set_boss(name_: String, frac: float) -> void:
	if name_ == "":
		boss_name = ""; return
	if name_ != boss_name: boss_trail = frac; boss_frac = frac
	if frac < boss_frac - 0.0001: boss_hit = 1.0
	boss_name = name_; boss_frac = frac

func _guess_icon(title: String) -> String:
	var u := title.to_upper()
	if u.contains("AMMO"): return "ammo"
	if u.contains("WASHER"): return "washer"
	if u.contains("PAGE"): return "page"
	if u.contains("GRIPE") or u.contains("RETURN TO SENDER"): return "gripe"
	if u.contains("NOT OWNED") or u.contains("LOCKED"): return "lock"
	if u.contains("SPROCKET"): return "sprocket"
	return "star"

# ---------------------------------------------------------------- per frame
func _process(dt: float) -> void:
	t += dt
	hit_t -= dt
	hull_pop = maxf(0.0, hull_pop - dt * 4.0)
	for i in cell_flash.size(): cell_flash[i] = maxf(0.0, cell_flash[i] - dt * 2.5)
	wallet_pop = maxf(0.0, wallet_pop - dt * 5.0)
	wpn_pop = maxf(0.0, wpn_pop - dt * 4.0)
	lvl_pop = maxf(0.0, lvl_pop - dt * 2.0)
	ammo_pop = maxf(0.0, ammo_pop - dt * 6.0)
	collect_pop = maxf(0.0, collect_pop - dt * 1.5)
	boss_hit = maxf(0.0, boss_hit - dt * 4.0)
	obj_t += dt
	# sprocket counter rolls up, the gear spins on pickups
	nut_shown = move_toward(nut_shown, nuts, maxf(1.0, absf(nuts - nut_shown) * 8.0) * dt)
	gear_spin = maxf(0.0, gear_spin - dt * 1.5)
	gear_rot += dt * (0.15 + gear_spin * 9.0)
	nut_gain_t -= dt
	if nut_gain_t <= -0.4: nut_gain_n = 0
	if combat: heat_shown = lerpf(heat_shown, combat.heat, 1.0 - exp(-18.0 * dt))
	# boss bar: the damage trail drains after a short delay
	boss_a = move_toward(boss_a, 1.0 if boss_name != "" else 0.0, dt * 3.0)
	if boss_hit <= 0.0: boss_trail = move_toward(boss_trail, boss_frac, dt * 0.6)
	# prompt (hook swing or a system's prompt)
	var want := ext_prompt
	if player and player.get("hook_target"):
		want = ("Y" if player.get("using_pad") else "E") + "   SWING"
	if want != "": prompt_text = want
	prompt_a = move_toward(prompt_a, 1.0 if want != "" else 0.0, dt * 8.0)
	# damage vignette: flash on hits, slow pulse when the hull is nearly empty
	vig_a = maxf(0.0, vig_a - dt * 1.6)
	var low := 0.0
	if hull <= 2:
		low_t += dt; low = 0.22 + 0.12 * sin(low_t * 5.0)
	vignette.modulate.a = maxf(vig_a, low)
	banner_t -= dt
	sub_t -= dt
	sub_a = move_toward(sub_a, 1.0 if sub_t > 0.0 and subtitles and sub_text != "" else 0.0, dt * (8.0 if sub_t > 0.0 else 3.0))
	for c in [vitals, objective, wallet, collect, weapon, boss, cross, prompt, banner, subs]: c.queue_redraw()
	for c in toast_box.get_children(): c.queue_redraw()

func _pad() -> bool:
	return player != null and player.get("using_pad") == true

func _pop_scale(p: float) -> float:
	return 1.0 + 0.18 * sin(p * PI) * p

# ---------------------------------------------------------------- draw: vitals (hull + jet)
func _draw_vitals() -> void:
	var ci := vitals
	var low := hull <= 2
	var pulse := 0.5 + 0.5 * sin(t * 7.0)
	var acc := HULL_COL.lerp(LOW_COL, pulse if low else 0.0) if low else HULL_COL
	var shake := Vector2(sin(t * 60.0), cos(t * 47.0)) * 3.0 * hull_pop
	ci.draw_set_transform(shake)
	# hull panel
	var pr := Rect2(52, 10, 352, 54)
	HD.panel(ci, pr, acc, 14, -0.2)
	HD.text(ci, head, Vector2(92, 31), "HULL", 17, acc, 0, 5)
	var hp := "%d/%d" % [hull, hull_max]
	HD.text(ci, body, Vector2(384, 31), hp, 15, Color(0.85, 0.9, 1.0), 2, 4)
	var n := cell_flash.size()
	var cw := 30.0
	var gap := 5.0
	for i in n:
		var r := Rect2(88 + i * (cw + gap), 37, cw, 17)
		var full := i < hull
		var pts := HD.rrect(r, 5, -0.35)
		ci.draw_colored_polygon(HD.rrect(r.grow(2), 6, -0.35), HD.INK)
		if full:
			var col := LOW_COL.lerp(Color(1, 0.6, 0.5), pulse * 0.5) if low else HULL_COL
			var cols := PackedColorArray()
			for p in pts: cols.append(col.lightened(0.4).lerp(col.darkened(0.1), clampf((p.y - r.position.y) / r.size.y, 0, 1)))
			ci.draw_polygon(pts, cols)
			ci.draw_line(Vector2(r.position.x + 5, r.position.y + 4), Vector2(r.end.x - 7, r.position.y + 4), Color(1, 1, 1, 0.55), 2.0, true)
		else:
			ci.draw_colored_polygon(pts, HD.SLOT)
		if cell_flash[i] > 0.0:
			ci.draw_colored_polygon(pts, Color(1, 1, 1, cell_flash[i] * 0.9))
	# shield badge over the left end
	var bc := Vector2(44, 38)
	var bs := 1.0 + 0.15 * hull_pop
	HD.badge(ci, bc, 33 * bs, acc)
	HD.icon(ci, "hull", bc, 19 * bs, acc)
	ci.draw_set_transform(Vector2.ZERO)
	# jetpack + dash strip, tucked under the hull panel
	var jr := Rect2(78, 70, 246, 32)
	HD.panel(ci, jr, JET_COL, 10, -0.2, 1.0)
	var jets := 0
	var gliding := false
	var dash_frac := 1.0
	if player:
		jets = int(player.get("jumps")) if player.get("jumps") != null else 0
		var vy: float = player.velocity.y if "velocity" in player else 0.0
		gliding = jets >= 2 and vy < 0.0 and Input.is_action_pressed("jump") and not player.is_on_floor()
		var dcd = player.get("dash_cd")
		if dcd != null: dash_frac = clampf(1.0 - float(dcd) / 0.6, 0.0, 1.0)
	var jet_ready := jets < 2
	var jc := JET_COL if jet_ready else Color(0.45, 0.48, 0.58)
	HD.icon(ci, "jet", Vector2(102, 86), 13, jc)
	var jl := "GLIDE" if gliding else ("JET READY" if jet_ready else "JET USED")
	HD.text(ci, head, Vector2(120, 93), jl, 15, jc.lightened(0.2) if jet_ready or gliding else jc, 0, 4)
	var dc := Color(0.45, 0.85, 1.0) if dash_frac >= 1.0 else Color(0.45, 0.48, 0.58)
	HD.icon(ci, "dash", Vector2(228, 86), 10, dc)
	HD.text(ci, head, Vector2(242, 93), "DASH", 15, dc, 0, 4)
	var bx := 284.0
	ci.draw_colored_polygon(HD.rrect(Rect2(bx, 81, 28, 10), 4, -0.3), HD.SLOT)
	if dash_frac > 0.01:
		ci.draw_colored_polygon(HD.rrect(Rect2(bx, 81, 28 * dash_frac, 10), 4, -0.3), dc)

# ---------------------------------------------------------------- draw: objective
func _draw_objective() -> void:
	if obj_text == "": return
	var ci := objective
	var a := clampf(obj_t / 0.35, 0.0, 1.0)
	var slide := (1.0 - a) * (1.0 - a) * -50.0
	var fresh := clampf(1.0 - (obj_t - 0.35) / 2.5, 0.0, 1.0)     # glow while the objective is new
	var fs := 21
	var tw := body.get_string_size(obj_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var two := tw > 540.0          # long objectives wrap onto a second line instead of being cut off
	if two: fs = 19
	var wrap := 540.0
	var w := clampf((wrap if two else tw) + 92.0, 260.0, 640.0)
	var h := 76.0 if two else 54.0
	var r := Rect2(30 + slide, 14, w, h)
	HD.panel(ci, r, OBJ_COL.lerp(Color.WHITE, fresh * 0.5 * (0.5 + 0.5 * sin(t * 10.0))), 12, -0.12, a)
	HD.badge(ci, Vector2(32 + slide, 14 + h * 0.5), 24, OBJ_COL, a)
	HD.icon(ci, "flag", Vector2(34 + slide, 14 + h * 0.5), 13, OBJ_COL, a)
	HD.text(ci, head, Vector2(66 + slide, 34), "OBJECTIVE", 15, OBJ_COL, 0, 4, a)
	if fresh > 0.0:
		HD.text(ci, head, Vector2(150 + slide, 34), "NEW", 15, Color(1, 1, 1, fresh), 0, 4, a)
	if two:
		var pos := Vector2(66 + slide, 57)
		ci.draw_multiline_string_outline(body, pos, obj_text, HORIZONTAL_ALIGNMENT_LEFT, wrap, fs, 2, 5, Color(HD.INK, a))
		ci.draw_multiline_string(body, pos, obj_text, HORIZONTAL_ALIGNMENT_LEFT, wrap, fs, 2, Color(1, 1, 1, a))
	else:
		HD.text(ci, body, Vector2(66 + slide, 58), obj_text, fs, Color(1, 1, 1), 0, 5, a)

# ---------------------------------------------------------------- draw: sprockets + collectibles
func _draw_wallet() -> void:
	var ci := wallet
	var s := _pop_scale(wallet_pop)
	ci.draw_set_transform(Vector2(282, 38) * (1.0 - s), 0.0, Vector2(s, s))
	var r := Rect2(48, 10, 222, 56)
	HD.panel(ci, r, GOLD, 14, 0.2)
	HD.text(ci, head, Vector2(86, 32), "SPROCKETS", 14, GOLD, 0, 4)
	HD.text(ci, head, Vector2(254, 60), _thousands(int(round(nut_shown))), 34, Color(1, 0.95, 0.8), 2, 7)
	var bc := Vector2(50, 38)
	HD.badge(ci, bc, 33, GOLD)
	HD.icon(ci, "sprocket", bc, 22, GOLD, 1.0, gear_rot)
	ci.draw_set_transform(Vector2.ZERO)
	# "+N" chip to the left while sprockets pour in
	var ga := clampf(nut_gain_t / 0.4, 0.0, 1.0)
	if nut_gain_n > 0 and ga > 0.0:
		var txt := "+%d" % nut_gain_n
		var w := head.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x + 22
		var gr := Rect2(8 - w, 22, w, 34)
		HD.panel(ci, gr, GOLD, 10, 0.2, ga, Color(0.55, 0.4, 0.1, 0.95), Color(0.3, 0.2, 0.05, 0.95))
		HD.text(ci, head, Vector2(gr.get_center().x, 48), txt, 24, Color(1, 0.95, 0.6), 1, 5, ga)

func _thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out; s = s.substr(0, s.length() - 3)
	return s + out

func _draw_collect() -> void:
	if collect_counts.is_empty(): return
	var ci := collect
	var item_w := 96.0
	var w := 24.0 + item_w * collect_counts.size()
	var r := Rect2(270 - w, 6, w, 34)
	var acc := Color(0.75, 0.8, 0.95).lerp(GOLD, collect_pop)
	HD.panel(ci, r, acc, 10, 0.2, 0.92)
	var x := r.position.x + 22
	for c in collect_counts:
		var done: bool = c[2] >= c[3]
		HD.icon(ci, c[0], Vector2(x, 23), 11, c[1])
		HD.text(ci, head, Vector2(x + 18, 31), "%d/%d" % [c[2], c[3]], 19, GOLD if done else Color(1, 1, 1), 0, 5)
		x += item_w

# ---------------------------------------------------------------- draw: weapon
func _draw_weapon() -> void:
	if combat == null or not combat.has_method("weapon_name"): return
	var ci := weapon
	var id: String = combat.current
	var wc: Color = combat.weapon_color(id)
	var lv: int = combat.level(id)
	var maxed := lv >= 5
	var s := _pop_scale(wpn_pop)
	ci.draw_set_transform(Vector2(400, 80) * (1.0 - s), 0.0, Vector2(s, s))
	var r := Rect2(16, 26, 368, 100)
	HD.panel(ci, r, wc, 16, 0.12)
	# name
	HD.text(ci, head, Vector2(332, 60), combat.weapon_name(id), 27, wc.lightened(0.15), 2, 7)
	var lancer: bool = not combat.uses_ammo(id)
	if lancer:
		# heat gauge: ten segments, cyan to orange to red
		var hot: bool = combat.overheated
		var hc := Color(1, 0.3, 0.2) if hot else Color(0.45, 0.95, 1.0).lerp(Color(1, 0.55, 0.2), clampf(heat_shown * 1.4 - 0.3, 0, 1))
		HD.icon(ci, "heat", Vector2(70, 84), 12, hc if heat_shown > 0.05 else Color(0.55, 0.6, 0.7))
		var segs := 10
		for i in segs:
			var sr := Rect2(92 + i * 24, 75, 20, 16)
			var on := heat_shown * segs > i + 0.15
			ci.draw_colored_polygon(HD.rrect(sr.grow(1.5), 4, 0.25), HD.INK)
			var cc := (Color(1, 0.3, 0.2) if hot else Color(0.45, 0.95, 1.0).lerp(Color(1, 0.4, 0.15), float(i) / segs)) if on else HD.SLOT
			if hot and on: cc = cc.lerp(Color.WHITE, 0.35 * (0.5 + 0.5 * sin(t * 18.0)))
			ci.draw_colored_polygon(HD.rrect(sr, 4, 0.25), cc)
		if hot: HD.text(ci, head, Vector2(48, 60), "OVERHEAT!", 18, Color(1, 0.45, 0.35).lerp(Color.WHITE, 0.5 + 0.5 * sin(t * 18.0)), 0, 5)
	else:
		var a: int = combat.ammo(id)
		var m: int = combat.max_ammo(id)
		var ac := Color(1, 0.4, 0.3) if a <= 0 else (Color(1, 0.8, 0.4) if a * 4 <= m else Color(1, 1, 1))
		var as_ := 1.0 + 0.12 * ammo_pop
		HD.icon(ci, "ammo", Vector2(70, 86), 13, wc)
		var mw := HD.text(ci, head, Vector2(332, 100), " / %d" % m, 19, Color(0.7, 0.76, 0.9), 2, 5)
		ci.draw_set_transform(Vector2(400, 80) * (1.0 - s) + Vector2(332 - mw, 100) * (1.0 - as_) * s, 0.0, Vector2(s * as_, s * as_))
		HD.text(ci, head, Vector2(332 - mw, 100), str(a), 36, ac, 2, 7)
		ci.draw_set_transform(Vector2(400, 80) * (1.0 - s), 0.0, Vector2(s, s))
		HD.text(ci, body, Vector2(92, 92), "EMPTY" if a <= 0 else "AMMO", 13, ac if a <= 0 else Color(0.75, 0.82, 0.95), 0, 4)
	# weapon XP bar along the bottom
	var xr := Rect2(56, 114, 278, 6)
	ci.draw_colored_polygon(HD.rrect(xr.grow(1.5), 4, 0.12), HD.INK)
	ci.draw_colored_polygon(HD.rrect(xr, 3, 0.12), HD.SLOT)
	var xf: float = 1.0 if maxed else combat.xp_frac(id)
	if xf > 0.01: ci.draw_colored_polygon(HD.rrect(Rect2(xr.position, Vector2(xr.size.x * xf, xr.size.y)), 3, 0.12), GOLD if maxed else wc)
	HD.text(ci, head, Vector2(24, 122), "XP", 13, GOLD, 0, 4)
	# emblem medallion + level chip
	var mc := Vector2(396, 74)
	HD.badge(ci, mc, 50, wc)
	HD.icon(ci, HD.weapon_icon(id), mc, 28, wc)
	var ls := 1.0 + 0.3 * sin(lvl_pop * PI)
	var lr := Rect2(mc.x - 30 * ls, mc.y + 36, 60 * ls, 28 * ls)
	HD.panel(ci, lr, GOLD if maxed else Color.WHITE, 9, 0.0, 1.0, Color(0.55, 0.4, 0.08, 0.97) if maxed else HD.PANEL_TOP, Color(0.3, 0.2, 0.04, 0.97) if maxed else HD.PANEL_BOT)
	HD.text(ci, head, Vector2(mc.x, lr.position.y + 22 * ls), "V%d" % lv, int(20 * ls), GOLD if maxed else Color.WHITE, 1, 5)
	ci.draw_set_transform(Vector2.ZERO)

# ---------------------------------------------------------------- draw: boss
func _draw_boss() -> void:
	if boss_a <= 0.0: return
	var ci := boss
	var a := boss_a
	var drop := (1.0 - a) * -40.0
	var shake := Vector2(sin(t * 70.0), cos(t * 53.0)) * 4.0 * boss_hit
	ci.draw_set_transform(Vector2(0, drop) + shake)
	var r := Rect2(50, 12, 620, 62)
	HD.panel(ci, r, BOSS_COL, 14, 0.0, a, Color(0.3, 0.09, 0.1, 0.92), Color(0.1, 0.03, 0.05, 0.92))
	HD.text(ci, head, Vector2(98, 37), boss_name if boss_name != "" else "", 21, Color(1, 0.85, 0.8), 0, 5, a)
	HD.text(ci, body, Vector2(650, 37), "%d%%" % int(ceil(boss_frac * 100.0)), 15, Color(1, 0.75, 0.7), 2, 4, a)
	var br := Rect2(98, 45, 552, 18)
	ci.draw_colored_polygon(HD.rrect(br.grow(2.5), 9), Color(HD.INK, a))
	ci.draw_colored_polygon(HD.rrect(br, 8), Color(0.12, 0.04, 0.06, a))
	if boss_trail > boss_frac:
		ci.draw_colored_polygon(HD.rrect(Rect2(br.position, Vector2(br.size.x * boss_trail, br.size.y)), 8), Color(1, 0.92, 0.75, 0.85 * a))
	if boss_frac > 0.005:
		var fr := Rect2(br.position, Vector2(maxf(16.0, br.size.x * boss_frac), br.size.y))
		var pts := HD.rrect(fr, 8)
		var cols := PackedColorArray()
		for p in pts: cols.append(Color(1, 0.55, 0.4, a).lerp(Color(0.85, 0.12, 0.1, a), clampf((p.y - fr.position.y) / fr.size.y, 0, 1)))
		ci.draw_polygon(pts, cols)
		ci.draw_line(fr.position + Vector2(8, 4), Vector2(fr.end.x - 8, fr.position.y + 4), Color(1, 1, 1, 0.45 * a), 2.0, true)
		if boss_hit > 0.0: ci.draw_colored_polygon(pts, Color(1, 1, 1, boss_hit * 0.6 * a))
	for i in range(1, 10):
		var x := br.position.x + br.size.x * i / 10.0
		ci.draw_line(Vector2(x, br.position.y + 2), Vector2(x, br.end.y - 2), Color(0, 0, 0, 0.35 * a), 2.0)
	HD.badge(ci, Vector2(56, 42), 36, BOSS_COL, a)
	HD.icon(ci, "boss", Vector2(56, 44), 21, BOSS_COL, a)
	ci.draw_set_transform(Vector2.ZERO)

# ---------------------------------------------------------------- draw: crosshair + prompt
func _draw_cross() -> void:
	var c := cross.size * 0.5
	var col := Color(1, 1, 1, 0.92)
	var gap := 7.0 + (6.0 if hit_t > 0.0 else 0.0)
	for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		cross.draw_line(c + d * gap, c + d * (gap + 10.0), Color(HD.INK, 0.7), 5.0, true)
		cross.draw_line(c + d * gap, c + d * (gap + 10.0), col, 2.5, true)
	cross.draw_circle(c, 3.2, Color(HD.INK, 0.7), true, -1, true)
	cross.draw_circle(c, 2.0, col, true, -1, true)
	if hit_t > 0.0:
		var hc := Color(1, 0.4, 0.3) if hit_kill else Color(1, 1, 1)
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			cross.draw_line(c + d.normalized() * 10.0, c + d.normalized() * 19.0, Color(HD.INK, 0.7), 6.0, true)
			cross.draw_line(c + d.normalized() * 10.0, c + d.normalized() * 19.0, hc, 3.0, true)

func _draw_prompt() -> void:
	if prompt_a <= 0.0 or prompt_text == "": return
	var ci := prompt
	var key := ""
	var label := prompt_text.strip_edges()
	var sp := label.find("  ")
	if sp > 0 and sp <= 6:
		key = label.substr(0, sp); label = label.substr(sp).strip_edges()
	var fs := 22
	var lw := head.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var kw := 40.0 if key != "" else 0.0
	var w := lw + kw + 44.0
	var bob := sin(t * 4.0) * 2.0
	var r := Rect2(320 - w * 0.5, 8 + bob, w, 44)
	var a := prompt_a
	HD.panel(ci, r, Color(1, 0.9, 0.55), 22, 0.0, a)
	var x := r.position.x + 22
	if key != "":
		HD.keycap(ci, Vector2(x + 14, r.get_center().y), key, _pad(), a)
		x += kw
	HD.text(ci, head, Vector2(x, r.position.y + 30), label, fs, Color(1, 0.95, 0.75), 0, 5, a)

# ---------------------------------------------------------------- draw: banner + subtitles
func _draw_banner() -> void:
	if banner_t <= 0.0 or banner_title == "": return
	var ci := banner
	var a := clampf(banner_t, 0.0, 1.0) * clampf((3.2 - banner_t) / 0.2, 0.0, 1.0)
	var grow := 0.85 + 0.15 * clampf((3.2 - banner_t) / 0.25, 0.0, 1.0)
	var cx := 640.0
	var tw := head.get_string_size(banner_title, HORIZONTAL_ALIGNMENT_LEFT, -1, 56).x
	var sw := body.get_string_size(banner_sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x if banner_sub != "" else 0.0
	var w := (maxf(tw, sw) + 120.0) * grow
	var h := 116.0 if banner_sub != "" else 84.0
	var r := Rect2(cx - w * 0.5, 10, w, h)
	# side wings
	for sgn in [-1.0, 1.0]:
		var x0: float = cx + sgn * (w * 0.5 + 14)
		ci.draw_line(Vector2(x0, 10 + h * 0.5), Vector2(x0 + sgn * 120 * grow, 10 + h * 0.5), Color(banner_col, 0.8 * a), 3.0, true)
		var d := Vector2(x0 + sgn * 130 * grow, 10 + h * 0.5)
		ci.draw_colored_polygon(PackedVector2Array([d + Vector2(0, -8), d + Vector2(8, 0), d + Vector2(0, 8), d + Vector2(-8, 0)]), Color(banner_col, a))
	HD.panel(ci, r, banner_col, 18, 0.0, a * 0.95)
	HD.text(ci, head, Vector2(cx, r.position.y + 62), banner_title, 56, banner_col, 1, 10, a)
	if banner_sub != "":
		HD.text(ci, body, Vector2(cx, r.position.y + 98), banner_sub, 22, Color(1, 1, 1), 1, 5, a)

func _draw_subs() -> void:
	if sub_a <= 0.0: return
	var ci := subs
	var fs := 25
	var wrap := 620.0
	var sz := body.get_multiline_string_size(sub_text, HORIZONTAL_ALIGNMENT_CENTER, wrap, fs)
	var w := minf(wrap, sz.x) + 56.0
	var h := sz.y + 28.0
	var r := Rect2(520 - w * 0.5, 160 - h, w, h)
	ci.draw_colored_polygon(HD.rrect(r.grow(2), 16), Color(HD.INK, 0.6 * sub_a))
	ci.draw_colored_polygon(HD.rrect(r, 14), Color(0.03, 0.05, 0.11, 0.72 * sub_a))
	ci.draw_multiline_string_outline(body, Vector2(r.position.x + 28, r.position.y + 14 + body.get_ascent(fs)), sub_text, HORIZONTAL_ALIGNMENT_CENTER, w - 56, fs, -1, 6, Color(HD.INK, sub_a))
	ci.draw_multiline_string(body, Vector2(r.position.x + 28, r.position.y + 14 + body.get_ascent(fs)), sub_text, HORIZONTAL_ALIGNMENT_CENTER, w - 56, fs, -1, Color(1, 1, 1, sub_a))
	if sub_who != "":
		var nw := head.get_string_size(sub_who, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 28
		var nr := Rect2(r.position.x + 18, r.position.y - 16, nw, 28)
		HD.panel(ci, nr, sub_col, 10, -0.15, sub_a, sub_col.darkened(0.45), sub_col.darkened(0.7))
		HD.text(ci, head, Vector2(nr.get_center().x, nr.position.y + 21), sub_who, 18, Color(1, 1, 1), 1, 4, sub_a)

# ---------------------------------------------------------------- draw: toast cards
func _draw_toast(card: Control) -> void:
	var d: Dictionary = card.get_meta("d")
	var age: float = t - float(d.born)
	var slide := maxf(0.0, 1.0 - age / 0.25)
	var ox := slide * slide * 60.0
	var col: Color = d.color
	var r := Rect2(30 + ox, 2, card.size.x - 32, card.size.y - 4)
	HD.panel(card, r, col, 12, 0.0)
	var bc := Vector2(30 + ox, minf(31.0, card.size.y * 0.5))
	HD.badge(card, bc, 26, col)
	HD.icon(card, d.icon, bc, 15, col)
	HD.text(card, head, Vector2(66 + ox, 32), d.title, 22, col.lightened(0.1), 0, 5)
	if d.sub != "":
		card.draw_multiline_string(body, Vector2(66 + ox, 42 + body.get_ascent(17)), d.sub, HORIZONTAL_ALIGNMENT_LEFT, card.size.x - 96, 17, -1, Color(0.9, 0.94, 1.0))
