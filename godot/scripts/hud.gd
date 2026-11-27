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
var wstrip := Control.new()
var flyer_layer := Control.new()
var flyers: Array = []                 # sprockets flying into the counter: { from, t, delay }
var strip_t := 0.0

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
var dmg_arrows: Array = []              # { pos: Vector3, t } recent hits, drawn as arrows round the crosshair
var kill_t := 0.0
var heal_t := 0.0
var swap_t := 0.0
var prev_wpn := ""
var shown_wpn := ""
var waves := Control.new()
var waypoint := Control.new()
var threats := Control.new()
var saved := Control.new()
var save_t := 0.0                      # checkpoint "saved" chip
var boss_intro := 0.0                  # time since the boss bar appeared (name types in, bar fills)
var boss_dead_t := 0.0                 # SCRAPPED! stamp after a boss goes down
var boss_dead_name := ""
var boss_shards: Array = []            # { p, v, t } chips knocked off the bar
var boss_phase2 := false
var lvup := Control.new()
var lv_t := 0.0                        # level-up card: counts down from LV_TIME
var lv_id := ""
var lv_level := 1
const LV_TIME := 3.6
var results := Control.new()
var res_t := 0.0                       # area results card: counts down from RES_TIME
var res := {}                          # name, kills, nuts, secs, hits
var zone_run := {}                     # stats of the fight in progress
const RES_TIME := 7.0
var wp_a := 0.0                        # objective marker fade
var wp_pos := Vector2(-1, -1)          # smoothed screen spot of the marker
var wp_dist := 0.0
var wp_edge := false
var wp_dir := Vector2.UP
var wave_pop := 0.0
var wave_last := -1
var wallet_idle := 0.0                  # sprockets + collectibles tuck away after a while with no change
var wallet_slide := 0.0
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
	_place(vitals, Vector2(0, 0), Rect2(14, 8, 440, 170), _draw_vitals)
	_place(objective, Vector2(0, 0), Rect2(18, 178, 640, 104), _draw_objective)
	_place(wallet, Vector2(1, 0), Rect2(-300, 14, 282, 76), _draw_wallet)
	_place(collect, Vector2(1, 0), Rect2(-300, 92, 282, 46), _draw_collect)
	_place(boss, Vector2(0.5, 0), Rect2(-340, 10, 680, 84), _draw_boss)
	_place(weapon, Vector2(1, 1), Rect2(-470, -156, 452, 140), _draw_weapon)
	_place(wstrip, Vector2(1, 1), Rect2(-470, -206, 452, 50), _draw_wstrip)
	_place(waves, Vector2(0.5, 0), Rect2(-200, 96, 400, 50), _draw_waves)
	waypoint.set_anchors_preset(Control.PRESET_FULL_RECT); waypoint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	waypoint.draw.connect(_draw_waypoint); root.add_child(waypoint)
	_place(lvup, Vector2(1, 1), Rect2(-574, -392, 560, 170), _draw_lvup)
	_place(results, Vector2(0, 0), Rect2(0, 292, 420, 280), _draw_results)
	threats.set_anchors_preset(Control.PRESET_FULL_RECT); threats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	threats.draw.connect(_draw_threats); root.add_child(threats)
	_place(saved, Vector2(0, 1), Rect2(14, -96, 340, 80), _draw_saved)
	_place(cross, Vector2(0.5, 0.5), Rect2(-160, -160, 320, 320), _draw_cross)
	_place(prompt, Vector2(0.5, 0.5), Rect2(-320, 70, 640, 60), _draw_prompt)
	_place(banner, Vector2(0.5, 0), Rect2(-640, 286, 1280, 150), _draw_banner)
	_place(subs, Vector2(0.5, 1), Rect2(-520, -190, 1040, 170), _draw_subs)
	flyer_layer.set_anchors_preset(Control.PRESET_FULL_RECT); flyer_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flyer_layer.draw.connect(_draw_flyers); root.add_child(flyer_layer)
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
	Game.boss_defeated.connect(func(n): boss_dead_name = n if boss_name == "" else boss_name; boss_dead_t = 2.2; set_boss("", 0.0))
	Game.checkpoint_reached.connect(func(_p): save_t = 2.6)
	Game.objective_set.connect(func(_id, text): _set_objective(text))
	Game.collectible_found.connect(func(_k, _id): _refresh_collect(); collect_pop = 1.0; wallet_idle = 0.0)
	Game.player_hurt.connect(func(_h): vig_a = 0.75)
	if Game.has_signal("player_hit_from"): Game.player_hit_from.connect(func(p): dmg_arrows.append({ pos = p, t = 0.0 }))
	Game.zone_entered.connect(_zone_started)
	Game.zone_cleared.connect(_zone_done)
	Game.bot_killed.connect(func(_b, _p, _k): if not zone_run.is_empty(): zone_run.kills += 1)
	Game.player_hurt.connect(func(_h): if not zone_run.is_empty(): zone_run.hits += 1)
	combat.nuts_changed.connect(_nuts)
	combat.hull_changed.connect(_hull)
	combat.hit_marker.connect(func(k): hit_t = 0.18; hit_kill = k; if k: kill_t = 1.0)
	combat.weapon_changed.connect(func(id): wpn_pop = 1.0; strip_t = 2.5; prev_wpn = shown_wpn; swap_t = 1.0; shown_wpn = id)
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
	# keep the combat feedback going so any screenshot frame catches it
	while is_inside_tree():
		var cam := get_viewport().get_camera_3d()
		if cam and player:
			var b := cam.global_transform.basis
			Game.player_hit_from.emit(player.global_position + b.x * 6.0 - b.z * 3.0)
			Game.player_hit_from.emit(player.global_position - b.x * 5.0 + b.z * 4.0)
		combat.hit_marker.emit(true)
		await get_tree().create_timer(0.9).timeout

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
		nut_gain_n += n - nut_last; nut_gain_t = 1.6; gear_spin = 1.0; wallet_pop = 1.0; wallet_idle = 0.0
		_spawn_flyers(n - nut_last)
	elif nut_last < 0:
		nut_shown = n
	nut_last = n

func _hull(h: int, healed: bool) -> void:
	for i in cell_flash.size():
		if (i < hull) != (i < h): cell_flash[i] = 1.0
	hull = h
	if not healed: hull_pop = 1.0
	elif h > 0: heal_t = 1.0

func _level_up(id: String, lv: int) -> void:
	lvl_pop = 1.0
	lv_id = id; lv_level = lv; lv_t = LV_TIME

func _zone_started(_id: String) -> void:
	var nm := ""
	var st = Game.story
	if st and "zones" in st and st.index >= 0 and st.index < st.zones.size(): nm = str(st.zones[st.index].get("name", ""))
	zone_run = { name = nm, kills = 0, hits = 0, start = Time.get_ticks_msec(), nuts = nuts }

func _zone_done(_id: String) -> void:
	if zone_run.is_empty(): return
	if zone_run.kills > 0:
		res = zone_run.duplicate()
		res.secs = (Time.get_ticks_msec() - zone_run.start) / 1000.0
		res.nuts = maxi(0, nuts - int(zone_run.nuts))
		res_t = RES_TIME
	zone_run = {}

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
	if name_ != boss_name:
		boss_trail = frac; boss_frac = frac; boss_intro = 0.0; boss_phase2 = frac <= 0.5; boss_shards.clear()
	if frac < boss_frac - 0.0001:
		boss_hit = 1.0
		# knock a few chips off the end of the bar
		for k in 4: boss_shards.append({ f = frac, v = Vector2(randf_range(-60, 160), randf_range(-220, -80)), t = 0.0, s = randf_range(3.0, 6.0) })
	if frac <= 0.5 and not boss_phase2 and boss_name == name_:
		boss_phase2 = true
		show_banner("PHASE 2", "%s is furious!" % name_.capitalize(), BOSS_COL)
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
	hull_pop = maxf(0.0, hull_pop - dt * 2.2)
	for i in cell_flash.size(): cell_flash[i] = maxf(0.0, cell_flash[i] - dt * 2.5)
	wallet_pop = maxf(0.0, wallet_pop - dt * 2.5)
	wallet_idle += dt
	wallet_slide = move_toward(wallet_slide, 1.0 if wallet_idle > 7.0 else 0.0, dt * (1.6 if wallet_idle > 7.0 else 5.0))
	wpn_pop = maxf(0.0, wpn_pop - dt * 2.5)
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
	kill_t = maxf(0.0, kill_t - dt * 2.5)
	heal_t = maxf(0.0, heal_t - dt * 1.4)
	swap_t = maxf(0.0, swap_t - dt * 3.0)
	wave_pop = maxf(0.0, wave_pop - dt * 2.0)
	for d in dmg_arrows: d.t += dt
	dmg_arrows = dmg_arrows.filter(func(d): return d.t < 1.4)
	if shown_wpn == "" and combat: shown_wpn = combat.current
	_update_waypoint(dt)
	lv_t = maxf(0.0, lv_t - dt)
	save_t = maxf(0.0, save_t - dt)
	boss_intro += dt
	boss_dead_t = maxf(0.0, boss_dead_t - dt)
	for sh in boss_shards:
		sh.t += dt; sh.v.y += 600.0 * dt
	boss_shards = boss_shards.filter(func(sh): return sh.t < 0.8)
	threats.queue_redraw(); saved.queue_redraw()
	res_t = maxf(0.0, res_t - dt)
	for c in [vitals, objective, wallet, collect, weapon, boss, cross, prompt, banner, subs, waves, waypoint, lvup, results]: c.queue_redraw()
	for c in toast_box.get_children(): c.queue_redraw()
	strip_t = maxf(0.0, strip_t - dt)
	wstrip.queue_redraw()
	for f in flyers: f.t += dt
	flyers = flyers.filter(func(f): return f.t < f.delay + 0.55)
	flyer_layer.queue_redraw()

func _pad() -> bool:
	return player != null and player.get("using_pad") == true

func _pop_scale(p: float) -> float:
	return _spring(p)

# ---------------------------------------------------------------- draw: vitals (hull + jet)
func _draw_vitals() -> void:
	var ci := vitals
	var low := hull <= 2
	var pulse := 0.5 + 0.5 * sin(t * 7.0)
	var acc := HULL_COL.lerp(LOW_COL, pulse) if low else HULL_COL
	var shake := Vector2(sin(t * 60.0), cos(t * 47.0)) * 3.0 * hull_pop
	ci.draw_set_transform(shake)
	var c := Vector2(84, 84)
	# name plate: HULL and the count
	var pr := Rect2(166, 32, 222, 44)
	HD.panel(ci, pr, acc, 12, -0.2)
	HD.text(ci, head, Vector2(186, 62), "HULL", 22, acc, 0, 6)
	var hs := _spring(hull_pop)
	ci.draw_set_transform(shake + Vector2(368, 56) * (1.0 - hs), 0.0, Vector2(hs, hs))
	HD.text(ci, head, Vector2(368, 64), "%d/%d" % [hull, hull_max], 24, Color(1, 0.75, 0.7) if low else Color(1, 1, 1), 2, 6)
	ci.draw_set_transform(shake)
	# hull cells in a ring around the portrait (270 degrees, open at the bottom)
	var n := cell_flash.size()
	var a0 := PI * 0.75
	var span := PI * 1.5
	var seg := span / n
	for i in n:
		var full := i < hull
		var s0 := a0 + i * seg + 0.035
		var s1 := a0 + (i + 1) * seg - 0.035
		var grow: float = 1.0 + (0.08 * pulse if full and low else 0.0) + float(cell_flash[i]) * 0.12
		var r1 := 58.0
		var r2: float = 58.0 + 16.0 * grow
		ci.draw_colored_polygon(_arc_poly(c, r1 - 2.5, r2 + 2.5, s0 - 0.02, s1 + 0.02), HD.INK)
		var pts := _arc_poly(c, r1, r2, s0, s1)
		if full:
			var col := LOW_COL.lerp(Color(1, 0.65, 0.55), pulse * 0.5) if low else HULL_COL
			var cols := PackedColorArray()
			for p in pts:
				var k := clampf(((p - c).length() - r1) / (r2 - r1), 0.0, 1.0)
				cols.append(col.darkened(0.2).lerp(col.lightened(0.45), k))
			ci.draw_polygon(pts, cols)
			ci.draw_arc(c, r2 - 3.0, s0 + 0.04, s1 - 0.04, 6, Color(1, 1, 1, 0.5), 2.0, true)
		else:
			ci.draw_colored_polygon(pts, HD.SLOT)
		if cell_flash[i] > 0.0:
			ci.draw_colored_polygon(pts, Color(1, 1, 1, cell_flash[i] * 0.9))
	if heal_t > 0.0:
		var sweep := a0 + span * (1.0 - heal_t)
		ci.draw_arc(c, 66, a0, sweep, 32, Color(0.6, 1, 0.75, 0.55 * heal_t), 18, true)
		ci.draw_circle(c + Vector2(cos(sweep), sin(sweep)) * 66, 9 * heal_t + 3, Color(0.85, 1, 0.9, heal_t), true, -1, true)
	# Vesk's portrait in the middle
	var bs := _spring(hull_pop)
	HD.badge(ci, c, 46 * bs, acc)
	HD.icon(ci, "vesk", c + Vector2(0, 4), 31 * bs, acc)
	ci.draw_set_transform(Vector2.ZERO)
	# jetpack + dash strip
	var jr := Rect2(176, 92, 232, 32)
	HD.panel(ci, jr, JET_COL, 10, -0.2, 1.0)
	if low:
		var la := 0.55 + 0.45 * sin(t * 8.0)
		var lr := Rect2(110, 136, 92, 28)
		HD.panel(ci, lr, LOW_COL, 9, 0.0, la, Color(0.45, 0.06, 0.05, 0.95), Color(0.25, 0.02, 0.02, 0.95))
		HD.text(ci, head, Vector2(lr.get_center().x, lr.position.y + 21), "REPAIR!", 17, Color(1, 0.9, 0.85), 1, 4, la)
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
	HD.icon(ci, "jet", Vector2(198, 108), 13, jc)
	var jl := "GLIDE" if gliding else ("JET READY" if jet_ready else "JET USED")
	HD.text(ci, head, Vector2(216, 115), jl, 15, jc.lightened(0.2) if jet_ready or gliding else jc, 0, 4)
	var dc := Color(0.45, 0.85, 1.0) if dash_frac >= 1.0 else Color(0.45, 0.48, 0.58)
	HD.icon(ci, "dash", Vector2(318, 108), 10, dc)
	HD.text(ci, head, Vector2(332, 115), "DASH", 15, dc, 0, 4)
	var bx := 372.0
	ci.draw_colored_polygon(HD.rrect(Rect2(bx, 103, 26, 10), 4, -0.3), HD.SLOT)
	if dash_frac > 0.01:
		ci.draw_colored_polygon(HD.rrect(Rect2(bx, 103, 26 * dash_frac, 10), 4, -0.3), dc)

## A ring segment polygon between radii r1 and r2 from angle a0 to a1.
func _arc_poly(c: Vector2, r1: float, r2: float, a0: float, a1: float, steps := 6) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in steps + 1:
		var a := lerpf(a0, a1, float(i) / steps); p.append(c + Vector2(cos(a), sin(a)) * r2)
	for i in steps + 1:
		var a := lerpf(a1, a0, float(i) / steps); p.append(c + Vector2(cos(a), sin(a)) * r1)
	return p

## Springy scale for pops: overshoots, then wobbles back to 1 as p falls from 1 to 0.
func _spring(p: float) -> float:
	return 1.0 + 0.22 * p * cos((1.0 - p) * 13.0)

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
	if two: fs = 18
	var wrap := 540.0
	var w := clampf((wrap if two else tw) + 92.0, 260.0, 640.0)
	var h := 82.0 if two else 54.0
	var r := Rect2(30 + slide, 14, w, h)
	HD.panel(ci, r, OBJ_COL.lerp(Color.WHITE, fresh * 0.5 * (0.5 + 0.5 * sin(t * 10.0))), 12, -0.12, a)
	HD.badge(ci, Vector2(32 + slide, 14 + h * 0.5), 24, OBJ_COL, a)
	HD.icon(ci, "flag", Vector2(34 + slide, 14 + h * 0.5), 13, OBJ_COL, a)
	HD.text(ci, head, Vector2(66 + slide, 34), "OBJECTIVE", 15, OBJ_COL, 0, 4, a)
	if fresh > 0.0:
		HD.text(ci, head, Vector2(150 + slide, 34), "NEW", 15, Color(1, 1, 1, fresh), 0, 4, a)
	if two:
		var pos := Vector2(66 + slide, 56)
		ci.draw_multiline_string_outline(body, pos, obj_text, HORIZONTAL_ALIGNMENT_LEFT, wrap, fs, 2, 5, Color(HD.INK, a))
		ci.draw_multiline_string(body, pos, obj_text, HORIZONTAL_ALIGNMENT_LEFT, wrap, fs, 2, Color(1, 1, 1, a))
	else:
		HD.text(ci, body, Vector2(66 + slide, 58), obj_text, fs, Color(1, 1, 1), 0, 5, a)

# ---------------------------------------------------------------- draw: sprockets + collectibles
func _draw_wallet() -> void:
	var ci := wallet
	var s := _pop_scale(wallet_pop)
	var ox := _slide_x()
	ci.draw_set_transform(Vector2(282, 38) * (1.0 - s) + Vector2(ox, 0), 0.0, Vector2(s, s))
	var r := Rect2(48, 10, 222, 56)
	HD.panel(ci, r, GOLD, 14, 0.2)
	HD.text(ci, head, Vector2(86, 32), "SPROCKETS", 14, GOLD, 0, 4)
	HD.text(ci, head, Vector2(254, 60), _thousands(int(round(nut_shown))), 34, Color(1, 0.95, 0.8), 2, 7)
	var bc := Vector2(50, 38)
	HD.badge(ci, bc, 33, GOLD)
	HD.icon(ci, "sprocket", bc, 22, GOLD, 1.0, gear_rot)
	ci.draw_set_transform(Vector2.ZERO)
	# "+N" chip to the left while sprockets pour in
	ci.draw_set_transform(Vector2(ox, 0))
	var ga := clampf(nut_gain_t / 0.4, 0.0, 1.0)
	if nut_gain_n > 0 and ga > 0.0:
		var txt := "+%d" % nut_gain_n
		var w := head.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x + 22
		var gr := Rect2(8 - w, 22, w, 34)
		HD.panel(ci, gr, GOLD, 10, 0.2, ga, Color(0.55, 0.4, 0.1, 0.95), Color(0.3, 0.2, 0.05, 0.95))
		HD.text(ci, head, Vector2(gr.get_center().x, 48), txt, 24, Color(1, 0.95, 0.6), 1, 5, ga)

## How far the sprocket/collectible panels have tucked off the right edge.
func _slide_x() -> float:
	var e := wallet_slide * wallet_slide * (3.0 - 2.0 * wallet_slide)
	return e * 330.0

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
	ci.draw_set_transform(Vector2(_slide_x() * 1.1, 0))
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
	HD.text(ci, head, Vector2(312, 60), combat.weapon_name(id), 27, wc.lightened(0.15), 2, 7)
	var lancer: bool = not combat.uses_ammo(id)
	if lancer:
		# heat gauge: ten segments, cyan to orange to red
		var hot: bool = combat.overheated
		var hc := Color(1, 0.3, 0.2) if hot else Color(0.45, 0.95, 1.0).lerp(Color(1, 0.55, 0.2), clampf(heat_shown * 1.4 - 0.3, 0, 1))
		HD.icon(ci, "heat", Vector2(70, 84), 12, hc if heat_shown > 0.05 else Color(0.55, 0.6, 0.7))
		var segs := 10
		for i in segs:
			var sr := Rect2(92 + i * 22, 75, 18, 16)
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
		var mw := HD.text(ci, head, Vector2(312, 100), " / %d" % m, 19, Color(0.7, 0.76, 0.9), 2, 5)
		ci.draw_set_transform(Vector2(400, 80) * (1.0 - s) + Vector2(312 - mw, 100) * (1.0 - as_) * s, 0.0, Vector2(s * as_, s * as_))
		HD.text(ci, head, Vector2(312 - mw, 100), str(a), 36, ac, 2, 7)
		ci.draw_set_transform(Vector2(400, 80) * (1.0 - s), 0.0, Vector2(s, s))
		HD.text(ci, body, Vector2(92, 92), "EMPTY" if a <= 0 else "AMMO", 13, ac if a <= 0 else Color(0.75, 0.82, 0.95), 0, 4)
	# weapon XP bar along the bottom
	var xr := Rect2(56, 114, 254, 6)
	ci.draw_colored_polygon(HD.rrect(xr.grow(1.5), 4, 0.12), HD.INK)
	ci.draw_colored_polygon(HD.rrect(xr, 3, 0.12), HD.SLOT)
	var xf: float = 1.0 if maxed else combat.xp_frac(id)
	if xf > 0.01: ci.draw_colored_polygon(HD.rrect(Rect2(xr.position, Vector2(xr.size.x * xf, xr.size.y)), 3, 0.12), GOLD if maxed else wc)
	HD.text(ci, head, Vector2(24, 122), "XP", 13, GOLD, 0, 4)
	# emblem medallion + level chip
	var mc := Vector2(392, 74)
	# ammo (or heat) ring around the medallion, filling clockwise from the top
	var rf := heat_shown if not combat.uses_ammo(id) else float(combat.ammo(id)) / maxf(1.0, combat.max_ammo(id))
	var rc := wc
	if not combat.uses_ammo(id):
		rc = Color(1, 0.3, 0.2) if combat.overheated else Color(0.45, 0.95, 1.0).lerp(Color(1, 0.45, 0.15), clampf(heat_shown * 1.3 - 0.2, 0, 1))
	elif rf <= 0.25: rc = Color(1, 0.45, 0.3).lerp(Color.WHITE, 0.3 * (0.5 + 0.5 * sin(t * 10.0)))
	ci.draw_arc(mc, 63, 0, TAU, 64, HD.INK, 13, true)
	ci.draw_arc(mc, 63, 0, TAU, 64, HD.SLOT, 8, true)
	if rf > 0.005:
		ci.draw_arc(mc, 63, -PI / 2, -PI / 2 + TAU * clampf(rf, 0, 1), maxi(8, int(64 * rf)), rc, 8, true)
		ci.draw_arc(mc, 65, -PI / 2, -PI / 2 + TAU * clampf(rf, 0, 1), maxi(8, int(64 * rf)), Color(1, 1, 1, 0.35), 2, true)
	for i in 12:
		var a := -PI / 2 + TAU * i / 12.0
		ci.draw_line(mc + Vector2(cos(a), sin(a)) * 58.5, mc + Vector2(cos(a), sin(a)) * 67.5, Color(HD.INK, 0.7), 2.0)
	# swap: the medallion flips over, showing the old emblem until it is edge-on
	var flip := absf(cos(swap_t * PI)) if swap_t > 0.0 else 1.0
	var show_id := prev_wpn if swap_t > 0.5 and prev_wpn != "" else id
	var sc: Color = combat.weapon_color(show_id)
	ci.draw_set_transform(Vector2(400, 80) * (1.0 - s) + mc * s * (1.0 - flip) * Vector2(1, 0), 0.0, Vector2(s * maxf(0.05, flip), s))
	HD.badge(ci, mc, 46, sc)
	HD.icon(ci, HD.weapon_icon(show_id), mc, 27, sc)
	ci.draw_set_transform(Vector2(400, 80) * (1.0 - s), 0.0, Vector2(s, s))
	var ls := 1.0 + 0.3 * sin(lvl_pop * PI)
	var lr := Rect2(mc.x - 30 * ls, mc.y + 36, 60 * ls, 28 * ls)
	HD.panel(ci, lr, GOLD if maxed else Color.WHITE, 9, 0.0, 1.0, Color(0.55, 0.4, 0.08, 0.97) if maxed else HD.PANEL_TOP, Color(0.3, 0.2, 0.04, 0.97) if maxed else HD.PANEL_BOT)
	HD.text(ci, head, Vector2(mc.x, lr.position.y + 22 * ls), "V%d" % lv, int(20 * ls), GOLD if maxed else Color.WHITE, 1, 5)
	ci.draw_set_transform(Vector2.ZERO)

# ---------------------------------------------------------------- draw: boss
## Boss bar: a red plate with the boss badge. The name types in and the bar fills up when the fight
## starts; the bar has moving hazard stripes, a white damage trail, chips that fly off on hits, a
## notch at half health where phase 2 starts (then an ENRAGED tag), and a SCRAPPED! stamp at the end.
func _draw_boss() -> void:
	var ci := boss
	if boss_dead_t > 0.0 and boss_a < 1.0:
		_draw_boss_scrapped(); return
	if boss_a <= 0.0: return
	var a := boss_a
	var drop := (1.0 - a) * -40.0
	var shake := Vector2(sin(t * 70.0), cos(t * 53.0)) * 4.0 * boss_hit
	ci.draw_set_transform(Vector2(0, drop) + shake)
	var r := Rect2(50, 12, 620, 62)
	var rage := boss_frac <= 0.5
	var pulse := 0.5 + 0.5 * sin(t * (9.0 if boss_frac <= 0.25 else 5.0))
	HD.panel(ci, r, BOSS_COL.lerp(Color(1, 0.6, 0.3), pulse * 0.5) if rage else BOSS_COL, 14, 0.0, a, Color(0.3, 0.09, 0.1, 0.92), Color(0.1, 0.03, 0.05, 0.92))
	var nm := boss_name
	var shown := clampi(int(boss_intro * 28.0), 0, nm.length())
	HD.text(ci, head, Vector2(98, 37), nm.substr(0, shown), 21, Color(1, 0.85, 0.8), 0, 5, a)
	var fill_in := clampf((boss_intro - 0.2) / 0.8, 0.0, 1.0)
	var f := boss_frac * fill_in
	if rage:
		var tag := "ENRAGED"
		var tw := head.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		var tr := Rect2(590 - tw - 20, 20, tw + 18, 20)
		HD.panel(ci, tr, Color(1, 0.6, 0.3), 6, 0.12, a, Color(0.6, 0.12, 0.08, 0.95), Color(0.35, 0.05, 0.03, 0.95))
		HD.text(ci, head, Vector2(tr.get_center().x, tr.position.y + 16), tag, 14, Color(1, 0.9, 0.7).lerp(Color.WHITE, pulse * 0.5), 1, 3, a)
	HD.text(ci, body, Vector2(650, 37), "%d%%" % int(ceil(f * 100.0)), 15, Color(1, 0.75, 0.7), 2, 4, a)
	var br := Rect2(98, 45, 552, 18)
	ci.draw_colored_polygon(HD.rrect(br.grow(2.5), 9), Color(HD.INK, a))
	ci.draw_colored_polygon(HD.rrect(br, 8), Color(0.12, 0.04, 0.06, a))
	if boss_trail > f and fill_in >= 1.0:
		ci.draw_colored_polygon(HD.rrect(Rect2(br.position, Vector2(br.size.x * boss_trail, br.size.y)), 8), Color(1, 0.92, 0.75, 0.85 * a))
	if f > 0.005:
		var fr := Rect2(br.position, Vector2(maxf(16.0, br.size.x * f), br.size.y))
		var pts := HD.rrect(fr, 8)
		var cols := PackedColorArray()
		var hi := Color(1, 0.55, 0.4, a) if not rage else Color(1, 0.7, 0.3, a)
		for p in pts: cols.append(hi.lerp(Color(0.85, 0.12, 0.1, a), clampf((p.y - fr.position.y) / fr.size.y, 0, 1)))
		ci.draw_polygon(pts, cols)
		# moving hazard stripes inside the fill
		var off := fposmod(t * (60.0 if rage else 30.0), 22.0)
		var x := fr.position.x - 22.0 + off
		while x < fr.end.x - 4.0:
			var x0 := maxf(x, fr.position.x + 4.0)
			var x1 := minf(x + 9.0, fr.end.x - 4.0)
			if x1 > x0 + 1.0:
				ci.draw_colored_polygon(PackedVector2Array([Vector2(x0 + 4, fr.position.y + 3), Vector2(x1 + 4, fr.position.y + 3), Vector2(x1 - 2, fr.end.y - 3), Vector2(x0 - 2, fr.end.y - 3)]), Color(1, 1, 1, 0.1 * a))
			x += 22.0
		ci.draw_line(fr.position + Vector2(8, 4), Vector2(fr.end.x - 8, fr.position.y + 4), Color(1, 1, 1, 0.45 * a), 2.0, true)
		if boss_hit > 0.0: ci.draw_colored_polygon(pts, Color(1, 1, 1, boss_hit * 0.6 * a))
		if boss_frac <= 0.25: ci.draw_colored_polygon(pts, Color(1, 0.9, 0.6, 0.18 * pulse * a))
	for i in range(1, 10):
		if i == 5: continue
		var xx := br.position.x + br.size.x * i / 10.0
		ci.draw_line(Vector2(xx, br.position.y + 2), Vector2(xx, br.end.y - 2), Color(0, 0, 0, 0.35 * a), 2.0)
	# phase notch at half health
	var nx := br.position.x + br.size.x * 0.5
	ci.draw_line(Vector2(nx, br.position.y - 4), Vector2(nx, br.end.y + 4), Color(HD.INK, a), 5.0)
	ci.draw_line(Vector2(nx, br.position.y - 2), Vector2(nx, br.end.y + 2), Color(1, 0.85, 0.5, a), 2.0)
	var dm := Vector2(nx, br.end.y + 9)
	ci.draw_colored_polygon(PackedVector2Array([dm + Vector2(0, -8), dm + Vector2(8, 0), dm + Vector2(0, 8), dm + Vector2(-8, 0)]), Color(HD.INK, a))
	ci.draw_colored_polygon(PackedVector2Array([dm + Vector2(0, -6), dm + Vector2(6, 0), dm + Vector2(0, 6), dm + Vector2(-6, 0)]), Color(1, 0.6, 0.3, a) if rage else Color(0.55, 0.3, 0.3, a))
	# flying chips
	for sh in boss_shards:
		var sp: Vector2 = Vector2(br.position.x + br.size.x * float(sh.f), br.get_center().y) + sh.v * float(sh.t)
		var sa := (1.0 - float(sh.t) / 0.8) * a
		var ss: float = sh.s
		ci.draw_colored_polygon(PackedVector2Array([sp + Vector2(-ss, -ss * 0.4).rotated(sh.t * 9.0), sp + Vector2(ss, -ss * 0.6).rotated(sh.t * 9.0), sp + Vector2(ss * 0.3, ss).rotated(sh.t * 9.0)]), Color(1, 0.5, 0.35, sa))
	HD.badge(ci, Vector2(56, 42), 36, BOSS_COL, a)
	HD.icon(ci, "boss", Vector2(56, 44), 21, BOSS_COL.lerp(Color(1, 0.7, 0.3), pulse * 0.6) if rage else BOSS_COL, a)
	ci.draw_set_transform(Vector2.ZERO)

func _draw_boss_scrapped() -> void:
	var ci := boss
	var el := 2.2 - boss_dead_t
	var a := clampf(boss_dead_t / 0.4, 0.0, 1.0)
	var q := clampf(el / 0.25, 0.0, 1.0)
	var r := Rect2(50, 12, 620, 62)
	HD.panel(ci, r, GOLD, 14, 0.0, a, Color(0.45, 0.32, 0.08, 0.95), Color(0.2, 0.12, 0.03, 0.95))
	HD.badge(ci, Vector2(56, 42), 36, GOLD, a)
	HD.icon(ci, "star", Vector2(56, 42), 20, GOLD, a, el * 2.0)
	HD.text(ci, body, Vector2(98, 36), boss_dead_name, 17, Color(1, 0.9, 0.7), 0, 4, a)
	var ss := 1.0 + 1.5 * (1.0 - q) * (1.0 - q)
	var c := Vector2(380, 62)
	ci.draw_set_transform(c * (1.0 - ss), -0.06, Vector2(ss, ss))
	HD.text(ci, head, c, "SCRAPPED!", 34, GOLD.lightened(0.2), 1, 8, a * q)
	ci.draw_set_transform(Vector2.ZERO)

# ---------------------------------------------------------------- off-screen threats
## Bots in the current fight that are off-screen show as small red chevrons on an oval round the
## crosshair, pointing at them (closer = bigger and brighter). Up to eight.
func _draw_threats() -> void:
	var st = Game.story if "story" in Game else null
	var cam := get_viewport().get_camera_3d()
	if st == null or not is_instance_valid(st) or not "alive" in st or cam == null or player == null: return
	var vs := threats.size
	var ctr := vs * 0.5
	var shown := 0
	for b in st.alive:
		if shown >= 8: break
		if not is_instance_valid(b) or not (b is Node3D) or b.get("dead") == true: continue
		var wp: Vector3 = (b as Node3D).global_position + Vector3(0, 1, 0)
		var dist := player.global_position.distance_to(wp)
		if dist > 40.0: continue
		var behind := cam.is_position_behind(wp)
		var sp := cam.unproject_position(wp)
		if not behind and Rect2(Vector2.ZERO, vs).grow(-40).has_point(sp): continue
		var loc: Vector3 = cam.global_transform.basis.inverse() * (wp - cam.global_position)
		var d := Vector2(loc.x, -loc.y)
		if behind: d = Vector2(loc.x, maxf(-loc.y, 0.2 * absf(loc.x)))
		if d.length() < 0.001: continue
		d = d.normalized()
		var rx := vs.x * 0.2
		var ry := vs.y * 0.24
		var k := 1.0 / sqrt((d.x * d.x) / (rx * rx) + (d.y * d.y) / (ry * ry))
		var p := ctr + d * k
		var near := clampf(1.0 - dist / 40.0, 0.0, 1.0)
		var sz := 11.0 + 7.0 * near
		var al := 0.45 + 0.5 * near
		var sd := Vector2(-d.y, d.x)
		var pts := PackedVector2Array([p + d * sz, p - d * sz * 0.4 + sd * sz, p - d * sz * 0.1, p - d * sz * 0.4 - sd * sz])
		var po := PackedVector2Array([p + d * (sz + 3), p - d * (sz * 0.4 + 2) + sd * (sz + 3), p - d * (sz * 0.1 - 1), p - d * (sz * 0.4 + 2) - sd * (sz + 3)])
		threats.draw_colored_polygon(po, Color(HD.INK, al))
		threats.draw_colored_polygon(pts, Color(1, 0.3, 0.22, al).lerp(Color(1, 0.75, 0.5, al), 0.3 * (0.5 + 0.5 * sin(t * 8.0))))
		shown += 1

# ---------------------------------------------------------------- checkpoint chip
func _draw_saved() -> void:
	if save_t <= 0.0: return
	var ci := saved
	var a := clampf(save_t / 0.4, 0.0, 1.0) * clampf((2.6 - save_t) / 0.2, 0.0, 1.0)
	var x := (1.0 - clampf((2.6 - save_t) / 0.3, 0.0, 1.0)) * -60.0
	var r := Rect2(54 + x, 22, 236, 40)
	HD.panel(ci, r, Color(0.45, 0.95, 1.0), 12, 0.12, a)
	HD.text(ci, head, Vector2(r.position.x + 30, r.position.y + 28), "CHECKPOINT", 19, Color(0.85, 0.97, 1.0), 0, 5, a)
	HD.text(ci, body, Vector2(r.end.x - 14, r.position.y + 27), "SAVED", 14, Color(0.6, 1, 0.65), 2, 4, a)
	var bc := Vector2(34 + x, 42)
	HD.badge(ci, bc, 20, Color(0.45, 0.95, 1.0), a)
	HD.icon(ci, "sprocket", bc, 13, Color(0.45, 0.95, 1.0), a, t * 4.0)

# ---------------------------------------------------------------- draw: crosshair + prompt
## Each weapon has its own reticle (tinted with its colour): Arc Lancer a tight cross with a heat arc,
## Scatter Bloom a wide petal ring showing its spread, Thump Lobber a bracket with drop dots for the
## arc, Seeker Hive four lock-on corners that slowly turn. It springs in on weapon swap and warns
## when the ammo runs low or the Lancer overheats.
func _draw_cross() -> void:
	var c := cross.size * 0.5
	var id: String = combat.current if combat and "current" in combat else "arc_lancer"
	var wc: Color = combat.weapon_color(id) if combat and combat.has_method("weapon_color") else Color.WHITE
	var col := Color(1, 1, 1, 0.92)
	var tint := Color(1, 1, 1).lerp(wc, 0.45)
	var sw := 1.0 + 0.5 * swap_t * swap_t
	var hit := hit_t > 0.0
	var ink := Color(HD.INK, 0.7)
	var ammo_f := 1.0
	var uses_ammo: bool = combat != null and combat.has_method("uses_ammo") and combat.uses_ammo(id)
	if uses_ammo: ammo_f = clampf(float(combat.ammo(id)) / maxf(1.0, combat.max_ammo(id)), 0.0, 1.0)
	match id:
		"scatter_bloom":
			var r := (30.0 + (5.0 if hit else 0.0)) * sw
			for i in 6:
				var a := -PI / 2 + TAU * i / 6.0
				var d := Vector2(cos(a), sin(a))
				var q := c + d * r
				cross.draw_colored_polygon(PackedVector2Array([q + d * 9, q + Vector2(-d.y, d.x) * 5.5, q - d * 3, q - Vector2(-d.y, d.x) * 5.5]), ink)
				cross.draw_colored_polygon(PackedVector2Array([q + d * 7, q + Vector2(-d.y, d.x) * 3.5, q - d * 1.5, q - Vector2(-d.y, d.x) * 3.5]), tint)
			cross.draw_arc(c, r - 9, 0, TAU, 40, Color(tint, 0.35), 1.5, true)
		"thump_lobber":
			var w := 22.0 * sw
			cross.draw_polyline(PackedVector2Array([c + Vector2(-w, -10), c + Vector2(-w, 6), c + Vector2(-w + 8, 12)]), ink, 5.0, true)
			cross.draw_polyline(PackedVector2Array([c + Vector2(w, -10), c + Vector2(w, 6), c + Vector2(w - 8, 12)]), ink, 5.0, true)
			cross.draw_polyline(PackedVector2Array([c + Vector2(-w, -10), c + Vector2(-w, 6), c + Vector2(-w + 8, 12)]), tint, 2.5, true)
			cross.draw_polyline(PackedVector2Array([c + Vector2(w, -10), c + Vector2(w, 6), c + Vector2(w - 8, 12)]), tint, 2.5, true)
			for k in 4:
				var y := 22.0 + k * 13.0 + k * k * 2.0
				var rr := 3.6 - k * 0.5
				cross.draw_circle(c + Vector2(0, y), rr + 1.5, ink, true, -1, true)
				cross.draw_circle(c + Vector2(0, y), rr, Color(tint, 1.0 - k * 0.18), true, -1, true)
		"seeker_hive":
			var r := 26.0 * sw + (4.0 if hit else 0.0)
			var rot := t * 0.8
			for i in 4:
				var a := rot + PI / 4 + i * PI / 2
				var d := Vector2(cos(a), sin(a))
				var sd := Vector2(-d.y, d.x)
				var q := c + d * r
				var pts := PackedVector2Array([q + sd * 9 - d * 4, q, q - sd * 9 - d * 4])
				cross.draw_polyline(pts, ink, 6.0, true)
				cross.draw_polyline(pts, tint, 3.0, true)
			cross.draw_arc(c, 9, 0, TAU, 24, ink, 4.0, true)
			cross.draw_arc(c, 9, 0, TAU, 24, Color(tint, 0.8), 2.0, true)
		_:   # arc_lancer and anything new: tight cross with a heat arc on the right
			var gap := (7.0 + (6.0 if hit else 0.0)) * sw
			for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
				cross.draw_line(c + d * gap, c + d * (gap + 10.0), ink, 5.0, true)
				cross.draw_line(c + d * gap, c + d * (gap + 10.0), col, 2.5, true)
			if heat_shown > 0.04:
				var hot: bool = combat.overheated if combat and "overheated" in combat else false
				var hc := Color(1, 0.3, 0.2) if hot else Color(0.45, 0.95, 1.0).lerp(Color(1, 0.45, 0.15), clampf(heat_shown * 1.3 - 0.2, 0, 1))
				var a1 := PI * 0.32
				var a0 := -PI * 0.32
				cross.draw_arc(c, 30, a0, a1, 16, ink, 7.0, true)
				cross.draw_arc(c, 30, a1 - (a1 - a0) * clampf(heat_shown, 0, 1), a1, 16, hc, 3.5, true)
	cross.draw_circle(c, 3.2, ink, true, -1, true)
	cross.draw_circle(c, 2.0, col, true, -1, true)
	# ammo arc on the left for ammo weapons; flashes when low
	if uses_ammo:
		var low := ammo_f <= 0.25
		var ac := wc if not low else Color(1, 0.4, 0.3).lerp(Color.WHITE, 0.4 * (0.5 + 0.5 * sin(t * 12.0)))
		var b0 := PI * 0.68
		var b1 := PI * 1.32
		cross.draw_arc(c, 44, b0, b1, 16, Color(HD.INK, 0.55), 7.0, true)
		if ammo_f > 0.005: cross.draw_arc(c, 44, b1 - (b1 - b0) * ammo_f, b1, 16, Color(ac, 0.9), 3.5, true)
	# warnings under the reticle
	var warn := ""
	if uses_ammo and combat.ammo(id) <= 0: warn = "EMPTY! RESTOCK AT GIZMART"
	elif uses_ammo and ammo_f <= 0.25: warn = "LOW AMMO"
	elif id == "arc_lancer" and combat and "overheated" in combat and combat.overheated: warn = "OVERHEAT!"
	if warn != "":
		var fl := 0.5 + 0.5 * sin(t * 10.0)
		var ww := head.get_string_size(warn, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		var wr := Rect2(c + Vector2(-ww * 0.5 - 14, 62), Vector2(ww + 28, 28))
		HD.panel(cross, wr, Color(1, 0.4, 0.3), 9, 0.12, 0.9, Color(0.45, 0.1, 0.06, 0.95), Color(0.22, 0.04, 0.03, 0.95))
		HD.text(cross, head, Vector2(c.x, wr.position.y + 21), warn, 18, Color(1, 0.75, 0.6).lerp(Color.WHITE, 0.5 * fl), 1, 4)
	if hit:
		var hc := Color(1, 0.4, 0.3) if hit_kill else Color(1, 1, 1)
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			cross.draw_line(c + d.normalized() * 10.0, c + d.normalized() * 19.0, Color(HD.INK, 0.7), 6.0, true)
			cross.draw_line(c + d.normalized() * 10.0, c + d.normalized() * 19.0, hc, 3.0, true)
	# kill burst: an expanding ring and four shards
	if kill_t > 0.0:
		var k := 1.0 - kill_t
		var rr := 14.0 + k * 34.0
		cross.draw_arc(c, rr, 0, TAU, 32, Color(1, 0.45, 0.3, kill_t), 3.0 + 3.0 * kill_t, true)
		for i in 4:
			var a := PI / 4 + i * PI / 2
			var d := Vector2(cos(a), sin(a))
			cross.draw_line(c + d * (rr + 4), c + d * (rr + 14), Color(1, 0.85, 0.4, kill_t), 3.0, true)
	# damage arrows: a red wedge pointing toward whoever hit Vesk
	var cam := get_viewport().get_camera_3d()
	if cam and player:
		for dm in dmg_arrows:
			var to: Vector3 = dm.pos - player.global_position
			var loc: Vector3 = cam.global_transform.basis.inverse() * to
			var ang := atan2(loc.x, -loc.z)          # 0 = straight ahead = up on screen
			var al: float = clampf(1.0 - (dm.t - 0.6) / 0.8, 0.0, 1.0) * clampf(dm.t / 0.08, 0.0, 1.0)
			var dir := Vector2(sin(ang), -cos(ang))
			var side := Vector2(-dir.y, dir.x)
			var r0 := 92.0 + 8.0 * sin(dm.t * 12.0)
			var tip := c + dir * (r0 + 34)
			var pts := PackedVector2Array([tip, c + dir * r0 + side * 26, c + dir * (r0 + 8), c + dir * r0 - side * 26])
			cross.draw_colored_polygon(PackedVector2Array([tip + dir * 4, c + dir * (r0 - 3) + side * 31, c + dir * (r0 + 6), c + dir * (r0 - 3) - side * 31]), Color(HD.INK, 0.8 * al))
			cross.draw_colored_polygon(pts, Color(1, 0.25, 0.18, 0.9 * al))
			cross.draw_line(c + dir * (r0 + 6) + side * 16, tip - dir * 6, Color(1, 0.75, 0.65, 0.8 * al), 2.0, true)


# ---------------------------------------------------------------- objective marker
## Where the current objective is in the world: the next story zone's centre while you travel to it.
## Hidden during fights, cutscenes and once you are standing in the zone.
func _objective_world() -> Variant:
	var st = Game.story if "story" in Game else null
	if st == null or not is_instance_valid(st) or not "zones" in st: return null
	if st.active: return null
	var i: int = st.index
	if i < 0 or i >= st.zones.size(): return null
	var z: Dictionary = st.zones[i]
	if not z.has("rect"): return null
	var r: Rect2 = z.rect
	return Vector3(r.get_center().x, float(z.get("y", 0.0)) + 2.0, r.get_center().y)

func _update_waypoint(dt: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var w = _objective_world()
	var show := w != null and cam != null and player != null and not Game.input_locked
	if show:
		var wp: Vector3 = w
		wp_dist = player.global_position.distance_to(wp)
		if wp_dist < 9.0: show = false
	wp_a = move_toward(wp_a, 1.0 if show else 0.0, dt * 3.0)
	if not show: return
	var wpos: Vector3 = w
	var vs := waypoint.size
	var m := Vector2(vs.x * 0.2, vs.y * 0.17)
	var behind := cam.is_position_behind(wpos)
	var sp := cam.unproject_position(wpos)
	var ctr := vs * 0.5
	var inside := not behind and Rect2(m, vs - m * 2.0).has_point(sp)
	wp_edge = not inside
	if not inside:
		# pin it to the screen edge in the direction of the target
		var loc: Vector3 = cam.global_transform.basis.inverse() * (wpos - cam.global_position)
		var d := Vector2(loc.x, -loc.y)
		if d.length() < 0.001: d = Vector2(0, 1)
		d = d.normalized()
		if behind and absf(d.y) < 0.3: d.y = 0.3
		# ride an oval round the crosshair, clear of the corner panels
		var rx := vs.x * 0.3
		var ry := vs.y * 0.33
		var k := 1.0 / sqrt((d.x * d.x) / (rx * rx) + (d.y * d.y) / (ry * ry))
		sp = ctr + d * k
		wp_dir = d
	if wp_pos.x < 0.0: wp_pos = sp
	wp_pos = wp_pos.lerp(sp, 1.0 - exp(-14.0 * dt))

func _draw_waypoint() -> void:
	if wp_a <= 0.01: return
	var ci := waypoint
	var a := wp_a
	var bob := sin(t * 3.0) * 4.0
	var p := wp_pos + Vector2(0, bob if not wp_edge else 0.0)
	# a diamond pin with the objective flag, a beam below it and the distance chip
	if not wp_edge:
		for k in 6:
			ci.draw_circle(p + Vector2(0, 30 + k * 7), 2.2 - k * 0.25, Color(OBJ_COL, (0.7 - k * 0.11) * a), true, -1, true)
	var pulse := fposmod(t * 0.9, 1.0)
	ci.draw_arc(p, 22 + pulse * 18, 0, TAU, 32, Color(OBJ_COL, 0.5 * (1.0 - pulse) * a), 2.5, true)
	var dia := PackedVector2Array([p + Vector2(0, -26), p + Vector2(22, 0), p + Vector2(0, 26), p + Vector2(-22, 0)])
	var dia_o := PackedVector2Array([p + Vector2(0, -32), p + Vector2(28, 0), p + Vector2(0, 32), p + Vector2(-28, 0)])
	ci.draw_colored_polygon(PackedVector2Array([dia_o[0] + Vector2(1.5, 4), dia_o[1] + Vector2(1.5, 4), dia_o[2] + Vector2(1.5, 4), dia_o[3] + Vector2(1.5, 4)]), Color(0, 0, 0, 0.3 * a))
	ci.draw_colored_polygon(dia_o, Color(HD.INK, a))
	var rim := PackedVector2Array([p + Vector2(0, -29.5), p + Vector2(25.5, 0), p + Vector2(0, 29.5), p + Vector2(-25.5, 0)])
	ci.draw_polygon(rim, HD._metal_cols(rim, Rect2(p - Vector2(26, 30), Vector2(52, 60)), a))
	ci.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -25), p + Vector2(21, 0), p + Vector2(0, 25), p + Vector2(-21, 0)]), Color(HD.INK, a))
	var body := PackedVector2Array([p + Vector2(0, -23), p + Vector2(19, 0), p + Vector2(0, 23), p + Vector2(-19, 0)])
	ci.draw_polygon(body, PackedColorArray([Color(0.55, 0.4, 0.08, a), Color(0.35, 0.24, 0.05, a), Color(0.2, 0.13, 0.03, a), Color(0.4, 0.28, 0.06, a)]))
	HD.icon(ci, "flag", p, 11, OBJ_COL, a)
	# arrow pointing off-screen when pinned to the edge
	if wp_edge:
		var d := wp_dir
		var sd := Vector2(-d.y, d.x)
		var tip := p + d * (44 + sin(t * 6.0) * 3.0)
		ci.draw_colored_polygon(PackedVector2Array([tip + d * 4, p + d * 30 + sd * 15, p + d * 30 - sd * 15]), Color(HD.INK, a))
		ci.draw_colored_polygon(PackedVector2Array([tip, p + d * 32 + sd * 11, p + d * 32 - sd * 11]), Color(OBJ_COL, a))
	# distance chip
	var txt := "%d m" % int(round(wp_dist))
	var tw := head.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	var cp := p + (Vector2(0, -56) if wp_edge and wp_dir.y > 0.5 else Vector2(0, 52 if wp_edge else 78))
	var r := Rect2(cp - Vector2(tw * 0.5 + 12, 13), Vector2(tw + 24, 26))
	HD.panel(ci, r, OBJ_COL, 9, 0.12, a)
	HD.text(ci, head, Vector2(cp.x, cp.y + 7), txt, 17, Color(1, 0.95, 0.75), 1, 4, a)

# ---------------------------------------------------------------- level-up card
## A weapon level-up gets its own card just above the weapon panel: the emblem spins in over turning rays,
## "V2 > V3" chips, five level pips with the new one popping, and a ribbon tab. V5 turns it gold
## and names the evolved weapon.
func _draw_lvup() -> void:
	if lv_t <= 0.0 or combat == null or lv_id == "": return
	var ci := lvup
	var el := LV_TIME - lv_t
	var a := clampf(el / 0.15, 0.0, 1.0) * clampf(lv_t / 0.35, 0.0, 1.0)
	var maxed := lv_level >= 5
	var wc: Color = GOLD if maxed else combat.weapon_color(lv_id)
	var p_in := clampf(el / 0.45, 0.0, 1.0)
	var drop := (1.0 - (1.0 + 0.2 * sin(p_in * PI * 1.5) * (1.0 - p_in)) * p_in) * -60.0 + (1.0 - clampf(lv_t / 0.35, 0.0, 1.0)) * -30.0
	var r := Rect2(30, 38 + drop, 500, 104)
	# ribbon tab on top
	var tab := Rect2(r.position.x + 150, r.position.y - 40, 200, 34)
	HD.panel(ci, tab, wc, 10, 0.12, a, Color(0.6, 0.42, 0.08, 0.97) if maxed else wc.darkened(0.45), Color(0.3, 0.18, 0.03, 0.97) if maxed else wc.darkened(0.75))
	HD.text(ci, head, Vector2(tab.get_center().x, tab.position.y + 25), "EVOLVED!" if maxed else "LEVEL UP!", 22, Color(1, 0.97, 0.85), 1, 5, a)
	HD.panel(ci, r, wc, 18, 0.0, a)
	# rays + emblem
	var bc := Vector2(r.position.x + 62, r.get_center().y)
	for k in 12:
		var ang := el * 0.9 + TAU * k / 12.0
		var d := Vector2(cos(ang), sin(ang))
		var sd := Vector2(-d.y, d.x)
		ci.draw_colored_polygon(PackedVector2Array([bc + d * 30 + sd * 3, bc + d * 64 + sd * 9, bc + d * 64 - sd * 9, bc + d * 30 - sd * 3]), Color(wc, 0.22 * a))
	var spin := clampf(el / 0.6, 0.0, 1.0)
	var flip := absf(cos(spin * PI * 2.0)) if spin < 1.0 else 1.0
	ci.draw_set_transform(Vector2(bc.x * (1.0 - flip), 0), 0.0, Vector2(maxf(0.06, flip), 1))
	HD.badge(ci, bc, 36, wc, a)
	HD.icon(ci, HD.weapon_icon(lv_id), bc, 21, wc, a)
	ci.draw_set_transform(Vector2.ZERO)
	# name, level chips, pips
	var x := r.position.x + 120
	var nm: String = (combat.WEAPONS[lv_id].v5 if maxed and "v5" in combat.WEAPONS[lv_id] else combat.weapon_name(lv_id))
	HD.text(ci, head, Vector2(x, r.position.y + 38), nm, 28, wc.lightened(0.2), 0, 6, a)
	for k in 2:
		var cr := Rect2(x + k * 86, r.position.y + 52, 54, 28)
		var lvn := lv_level - 1 + k
		var on := k == 1
		var pop := 1.0 + (0.25 * sin(clampf((el - 0.5) / 0.3, 0, 1) * PI) if on else 0.0)
		var crs := Rect2(cr.get_center() - cr.size * 0.5 * pop, cr.size * pop)
		HD.panel(ci, crs, GOLD if on else Color(0.7, 0.75, 0.85), 8, 0.0, a * (1.0 if on else 0.7), Color(0.55, 0.4, 0.08, 0.97) if on else HD.PANEL_TOP, Color(0.3, 0.2, 0.04, 0.97) if on else HD.PANEL_BOT)
		HD.text(ci, head, Vector2(crs.get_center().x, crs.position.y + 21 * pop), "V%d" % lvn, int(20 * pop), GOLD if on else Color(0.8, 0.85, 0.95), 1, 4, a)
	HD.icon(ci, "dash", Vector2(x + 70, r.position.y + 66), 9, GOLD, a)
	for k in 5:
		var pc := Vector2(x + 210 + k * 32, r.position.y + 66)
		var filled := k < lv_level
		var is_new := k == lv_level - 1
		var ps := 11.0
		if is_new:
			var q := clampf((el - 0.55) / 0.35, 0.0, 1.0)
			filled = q > 0.0
			ps = 11.0 * (1.0 + 0.6 * sin(q * PI))
		if filled: HD.icon(ci, "star", pc, ps, GOLD, a)
		else:
			ci.draw_circle(pc, 7, Color(HD.INK, a), true, -1, true)
			ci.draw_circle(pc, 5, Color(HD.SLOT, a), true, -1, true)
	var sub := "Evolved into its final form!" if maxed else "Bigger magazine, harder hits."
	HD.text(ci, body, Vector2(x, r.position.y + 96), sub, 15, Color(0.85, 0.92, 1.0), 0, 4, a)

# ---------------------------------------------------------------- area results
## After a fight zone is cleared: a tally card slides in on the left. Rows count up one after
## another (bots scrapped, sprockets earned, time, hits taken) and a medal stamps down at the end:
## gold for no hits, silver for 1-2, bronze otherwise.
func _draw_results() -> void:
	if res_t <= 0.0 or res.is_empty(): return
	var ci := results
	var el := RES_TIME - res_t
	var p_in := clampf(el / 0.4, 0.0, 1.0)
	var slide := (1.0 - p_in) * (1.0 - p_in) * -420.0 + (1.0 - clampf(res_t / 0.5, 0.0, 1.0)) * -420.0
	ci.draw_set_transform(Vector2(slide, 0))
	var r := Rect2(24, 18, 370, 236)
	var acc := Color(0.5, 1, 0.6)
	HD.panel(ci, r, acc, 16, 0.08)
	HD.icon(ci, "flag", Vector2(r.position.x + 28, r.position.y + 30), 13, acc)
	HD.text(ci, head, Vector2(r.position.x + 50, r.position.y + 40), "AREA REPORT", 24, acc.lightened(0.2), 0, 5)
	if str(res.get("name", "")) != "":
		HD.text(ci, body, Vector2(r.end.x - 20, r.position.y + 38), str(res.name), 14, Color(0.8, 0.88, 1.0), 2, 4)
	ci.draw_line(Vector2(r.position.x + 18, r.position.y + 54), Vector2(r.end.x - 18, r.position.y + 54), Color(acc, 0.35), 2.0)
	var secs: float = res.secs
	var rows := [
		["boss", Color(1, 0.45, 0.35), "BOTS SCRAPPED", float(res.kills), "%d"],
		["sprocket", GOLD, "SPROCKETS", float(res.nuts), "+%d"],
		["dash", Color(0.45, 0.95, 1.0), "TIME", secs, "time"],
		["hull", HULL_COL, "HITS TAKEN", float(res.hits), "%d"],
	]
	for i in rows.size():
		var row: Array = rows[i]
		var t0 := 0.35 + i * 0.35
		var ra := clampf((el - t0) / 0.2, 0.0, 1.0)
		if ra <= 0.0: continue
		var y := r.position.y + 84 + i * 38
		var cnt := clampf((el - t0) / 0.5, 0.0, 1.0)
		var v: float = row[3] * cnt
		var txt := ""
		if row[4] == "time": txt = "%d:%02d" % [int(v) / 60, int(v) % 60]
		else: txt = row[4] % int(round(v))
		HD.icon(ci, row[0], Vector2(r.position.x + 34, y - 7), 11, row[1], ra)
		HD.text(ci, body, Vector2(r.position.x + 56, y), row[2], 17, Color(0.88, 0.95, 1.0), 0, 4, ra)
		HD.text(ci, head, Vector2(r.end.x - (120 if i >= 2 else 24), y + 2), txt, 24, Color.WHITE, 2, 5, ra)
	# medal
	var mt := 0.35 + rows.size() * 0.35 + 0.3
	if el > mt:
		var q := clampf((el - mt) / 0.3, 0.0, 1.0)
		var hits: int = res.hits
		var mcol := GOLD if hits == 0 else (Color(0.82, 0.86, 0.95) if hits <= 2 else Color(0.85, 0.55, 0.3))
		var label := "NO-HIT!" if hits == 0 else ("SILVER" if hits <= 2 else "BRONZE")
		var ms := 1.0 + 1.2 * (1.0 - q) * (1.0 - q)
		var mc := Vector2(r.end.x - 60, r.end.y - 62)
		ci.draw_set_transform(Vector2(slide, 0) + mc * (1.0 - ms), -0.25 * (1.0 - q), Vector2(ms, ms))
		HD.badge(ci, mc, 30, mcol, q)
		HD.icon(ci, "star", mc, 18, mcol, q, sin(el * 2.0) * 0.15)
		HD.text(ci, head, mc + Vector2(0, 52), label, 16, mcol.lightened(0.2), 1, 4, q)
	ci.draw_set_transform(Vector2.ZERO)

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

# ---------------------------------------------------------------- draw: owned-weapon strip
## Small emblems for every owned weapon above the weapon card, the current one raised and ringed.
## Bright for a moment after a swap, then it settles back to a dim strip.
func _draw_wstrip() -> void:
	if combat == null or not ("WEAPONS" in combat): return
	var owned: Array = []
	for id in combat.WEAPONS:
		if id == "arc_lancer" or Game.has(id): owned.append(id)
	if owned.size() < 2: return
	var ci := wstrip
	var a := 0.85 + 0.15 * clampf(strip_t / 0.4, 0.0, 1.0)
	var pad := _pad()
	var x := 392.0 - (owned.size() - 1) * 52.0
	for i in owned.size():
		var id: String = owned[i]
		var cur: bool = id == combat.current
		var wc: Color = combat.weapon_color(id)
		var c := Vector2(x + i * 52.0, 24.0 - (3.0 if cur else 0.0))
		HD.badge(ci, c, 20.0 if cur else 16.0, wc if cur else wc.darkened(0.3), a)
		HD.icon(ci, HD.weapon_icon(id), c, 12.0 if cur else 9.5, wc if cur else wc.darkened(0.1), a)
		if not pad:
			var k := c + Vector2(-16, 13)
			ci.draw_circle(k, 9, Color(HD.INK, a), true, -1, true)
			ci.draw_circle(k, 7, Color(0.9, 0.93, 1.0, a) if cur else Color(0.55, 0.6, 0.7, a), true, -1, true)
			HD.text(ci, head, k + Vector2(0, 5), str(i + 1), 13, Color(0.08, 0.1, 0.18), 1, 0, a)
	if pad:
		HD.text(ci, head, Vector2(x - 40, 30), "LB", 16, Color(0.85, 0.9, 1), 1, 5, a)

# ---------------------------------------------------------------- sprocket flyers
func _spawn_flyers(gain: int) -> void:
	var vp := root.size
	var from := Vector2(vp.x * 0.5, vp.y * 0.62)
	for i in mini(8, maxi(1, gain / 5)):
		flyers.append({ from = from + Vector2(randf_range(-60, 60), randf_range(-40, 30)), t = 0.0, delay = i * 0.05, side = randf_range(-1, 1) })

func _draw_flyers() -> void:
	if flyers.is_empty(): return
	var to := Vector2(root.size.x - 300 + 50, 52)
	for f in flyers:
		var k: float = clampf((f.t - f.delay) / 0.55, 0.0, 1.0)
		if k <= 0.0: continue
		var e := k * k * (3.0 - 2.0 * k)
		var mid: Vector2 = (f.from + to) * 0.5 + Vector2(f.side * 160.0, -140.0)
		var p: Vector2 = (f.from.lerp(mid, e)).lerp(mid.lerp(to, e), e)
		HD.icon(flyer_layer, "sprocket", p, lerpf(13.0, 8.0, e), GOLD, 1.0 - maxf(0.0, (k - 0.85) / 0.15), t * 8.0 + f.side)

# ---------------------------------------------------------------- draw: wave tracker
## During a fight: "WAVE 2/3" and how many bots are still up. Hidden for bosses and outside fights.
func _draw_waves() -> void:
	var st = Game.story
	if st == null or not st.get("active"): return
	var zs = st.get("zones")
	var idx: int = int(st.get("index"))
	if not (zs is Array) or idx < 0 or idx >= zs.size(): return
	var z: Dictionary = zs[idx]
	if z.get("kind", "") != "": return
	var total: int = (z.get("waves", []) as Array).size()
	var left := 0
	for b in st.get("alive"):
		if is_instance_valid(b) and not b.get("dead"): left += 1
	var wv: int = clampi(int(st.get("wave")), 1, maxi(1, total))
	if wv != wave_last: wave_pop = 1.0; wave_last = wv
	var ci := waves
	var s := _spring(wave_pop)
	ci.draw_set_transform(Vector2(200, 25) * (1.0 - s), 0.0, Vector2(s, s))
	var r := Rect2(70, 6, 260, 38)
	HD.panel(ci, r, BOSS_COL.lerp(GOLD, 0.4), 12, 0.0, 0.95)
	HD.text(ci, head, Vector2(r.position.x + 20, 33), "WAVE %d/%d" % [wv, total], 20, Color(1, 0.88, 0.6), 0, 5)
	HD.icon(ci, "boss", Vector2(r.end.x - 92, 25), 11, Color(1, 0.55, 0.45))
	var lt := "%d LEFT" % left
	if left == 0: lt = "INCOMING!" if wv < total else "CLEAR!"
	var lc := Color(1, 1, 1) if left > 0 else (Color(1, 0.75, 0.4).lerp(Color.WHITE, 0.5 + 0.5 * sin(t * 9.0)) if wv < total else Color(0.6, 1, 0.6))
	HD.text(ci, head, Vector2(r.end.x - 18, 33), lt, 20, lc, 2, 5)
	ci.draw_set_transform(Vector2.ZERO)
