extends Node
## Gizmart, the vending-machine shop. Places a kiosk at every Game.level.shop_spots entry (Kit prop
## "gizmart_kiosk"), shows a prompt when Vesk walks up, and opens the shop on "interact" (E / pad Y,
## added at runtime when the project has no such action). Buying spends sprockets (Game.spend_nuts)
## and unlocks the item (Game.unlock). The game pauses while the shop is open.
## Debug: --shop-open opens the first shop right away without pausing (for screenshots), --rich adds 2000 sprockets.

const ITEMS := {
	"scatter_bloom": { name = "SCATTER BLOOM", price = 300, kind = "Weapon",
		desc = "Fires a fan of petal-shaped shrapnel. Close range, big bloom. Pollen not included." },
	"thump_lobber": { name = "THUMP LOBBER", price = 600, kind = "Weapon",
		desc = "Lobs bouncing thump-bombs over cover. Arcs, bounces, thumps. Mostly in that order." },
	"seeker_hive": { name = "SEEKER HIVE", price = 900, kind = "Weapon",
		desc = "Releases a swarm of homing micro-drones. They find the bots so you don't have to." },
}
const RANGE := 2.8
const GizmartActor := preload("res://scripts/chars/gizmart_actor.gd")

var kiosks: Array = []        # { node: Node3D, spot: Dictionary, front: Vector3 }
var near := -1
var open_i := -1
var hello_cd := 0.0

var layer: CanvasLayer
var prompt: Label
var hud_prompt := false
var panel: Control
var list: VBoxContainer
var rows: Array = []          # { id, button: Button }
var font: Font
var prev_mouse := Input.MOUSE_MODE_CAPTURED

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not InputMap.has_action("interact"):
		InputMap.add_action("interact", 0.5)
		var k := InputEventKey.new(); k.physical_keycode = KEY_E; InputMap.action_add_event("interact", k)
		var j := InputEventJoypadButton.new(); j.button_index = JOY_BUTTON_Y; InputMap.action_add_event("interact", j)
	_build_ui()
	_place_kiosks.call_deferred()
	if OS.get_cmdline_user_args().has("--rich"): Game.add_nuts.call_deferred(2000)
	if OS.get_cmdline_user_args().has("--shop-open"):
		get_tree().create_timer(0.5).timeout.connect(func(): if kiosks.size() > 0: _open(0, false))

func _place_kiosks() -> void:
	if Game.level == null: return
	var spots = Game.level.get("shop_spots")
	if not (spots is Array): return
	for s in spots:
		var yaw: float = s.get("yaw", 0.0)
		var k := Kit.place(Game.level, "gizmart_kiosk", s.pos, yaw, 1.0, true)
		k.name = "Gizmart%d" % kiosks.size()
		# the kiosk keeps its collision; its body is the animated Gizmart (live screen face, bob and lean)
		var actor: Node3D = null
		if ResourceLoader.exists("res://models/chars/gizmart.glb"):
			for c in k.get_children():
				if not (c is StaticBody3D): c.queue_free(); k.remove_child(c)
			actor = GizmartActor.new(); actor.name = "GizmartActor"; k.add_child(actor)
		var fwd := Vector3(sin(yaw), 0, cos(yaw))
		Kit.set_glow(k, "grin", Color(0.55, 1, 0.45), 3.0)
		Kit.set_glow(k, "eyes", Color(0.55, 1, 0.45), 3.0)
		var tag := Label3D.new(); tag.text = "GIZMART"; tag.font_size = 96; tag.pixel_size = 0.006
		tag.modulate = Color(0.6, 1, 0.5); tag.outline_size = 12; tag.position = Vector3(0, 3.5, 0.2)
		tag.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		k.add_child(tag)
		kiosks.append({ node = k, spot = s, front = (s.pos as Vector3) + fwd * 1.5, actor = actor })

func _process(dt: float) -> void:
	hello_cd -= dt
	_tick_ui(dt)
	if open_i >= 0:
		_shop_input()
		return
	near = -1
	if Game.player and not Game.input_locked and not get_tree().paused:
		var p: Vector3 = Game.player.global_position
		for i in kiosks.size():
			var f: Vector3 = kiosks[i].front
			if Vector2(p.x - f.x, p.z - f.z).length() < RANGE and absf(p.y - f.y) < 2.0: near = i
	var pad: bool = Game.player != null and Game.player.get("using_pad") == true
	prompt.text = ("Y" if pad else "E") + "   SHOP AT GIZMART"
	# the HUD draws the prompt (key cap or pad button in a panel); fall back to our own label without it
	var hud_ok: bool = Game.hud != null and Game.hud.has_method("show_prompt")
	prompt.visible = near >= 0 and not hud_ok
	if hud_ok:
		if near >= 0: Game.hud.show_prompt(prompt.text); hud_prompt = true
		elif hud_prompt: Game.hud.hide_prompt(); hud_prompt = false
	if near >= 0:
		var g := sin(Time.get_ticks_msec() / 1000.0 * 4.0) * 0.5 + 0.5
		prompt.modulate.a = 0.75 + 0.25 * g
		if Input.is_action_just_pressed("interact"): _open(near)

# ---------------------------------------------------------------- open / close / buy
func _open(i: int, pause := true) -> void:
	open_i = i
	prompt.visible = false
	if hud_prompt: Game.hud.hide_prompt(); hud_prompt = false
	Game.input_locked = true
	get_tree().paused = pause
	prev_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var stock: Array = kiosks[i].spot.get("stock", [])
	_fill(stock)
	panel.visible = true
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.92, 0.92)
	var tw := panel.create_tween().set_parallel()
	tw.tween_property(panel, "modulate:a", 1.0, 0.15); tw.tween_property(panel, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK)
	Snd.play("ui_select", -4)
	Kit.flash(kiosks[i].node, "grin", Color(0.55, 1, 0.45), 9.0, 3.0, 0.5)
	_mood(i, "hello", 1.6)
	Snd.play("gizmart_chime", -6, 0.0, 0.0)
	if hello_cd <= 0.0: Snd.bark("gizmart", "hello"); hello_cd = 20.0
	if rows.size() > 0: rows[0].button.grab_focus()

## Gizmart pulls a face on his screen (see scripts/chars/gizmart_actor.gd).
func _mood(i: int, m: String, secs: float) -> void:
	if i < 0 or i >= kiosks.size(): return
	var a = kiosks[i].get("actor")
	if a and is_instance_valid(a): a.mood(m, secs)

func _close() -> void:
	if open_i < 0: return
	_mood(open_i, "happy", 1.5)
	open_i = -1
	panel.visible = false
	get_tree().paused = false
	Game.input_locked = false
	Input.mouse_mode = prev_mouse
	Snd.play("ui_back", -4)
	if not (Snd.voice_player and Snd.voice_player.playing): Snd.bark("gizmart", "bye")

func _buy(id: String) -> void:
	var it: Dictionary = ITEMS.get(id, {})
	if it.is_empty() or Game.has(id): return
	if Game.spend_nuts(int(it.price)):
		Game.unlock(id)
		Snd.play("shop_buy", -2)
		Snd.voice_queue.clear()
		if Snd.voice_player: Snd.voice_player.stop()
		Snd.bark("gizmart", "buy")
		_vesk_buy_line()
		Kit.flash(kiosks[open_i].node, "grin", Color(1, 0.9, 0.3), 12.0, 3.0, 0.8)
		_mood(open_i, "excited", 2.0)
		info_text = "%s added to your arsenal." % it.name
		_fx_buy(id)
	else:
		Snd.play("shop_deny", -2)
		if not (Snd.voice_player and Snd.voice_player.playing): Snd.bark("gizmart", "poor")
		_mood(open_i, "sad", 1.6)
		info_text = "Not enough sprockets! You need %d more." % (int(it.price) - Game.nuts())
		_fx_deny(id)
	_refresh()

func _vesk_buy_line() -> void:
	# Vesk grumbles once Gizmart's pitch is done (queued behind it)
	if randf() < 0.6:
		var ids := ["vesk_buy_1", "vesk_buy_2"]
		Snd.voice(ids.pick_random())

func _shop_input() -> void:
	if Input.is_action_just_pressed("pause") or Input.is_action_just_pressed("dash") or Input.is_action_just_pressed("interact"):
		_close(); return
	var f := panel.get_viewport().gui_get_focus_owner()
	if Input.is_action_just_pressed("move_forward") or Input.is_action_just_pressed("move_back"):
		var idx := -1
		for i in rows.size(): if rows[i].button == f: idx = i
		var step := -1 if Input.is_action_just_pressed("move_forward") else 1
		if rows.size() > 0:
			idx = clampi(idx + step, 0, rows.size() - 1); rows[idx].button.grab_focus(); Snd.play("ui_move", -8)
	if Input.is_action_just_pressed("jump"):
		for r in rows: if r.button == f: _buy(r.id)

# ---------------------------------------------------------------- UI
## The shop window is drawn in code in the HUD's style (scripts/ui/hud_draw.gd): an animated
## Gizmart screen face, a scrolling LED ticker, a wallet chip, item rows with emblem medallions,
## a light sweep on the selected row, coin confetti on a purchase and a shake when you're short.
const HD := preload("res://scripts/ui/hud_draw.gd")
const GREEN := Color(0.55, 1.0, 0.45)
const GOLD := Color(1.0, 0.82, 0.3)
const TICKER := "SKYHARBOR SKY-HIGH EDITION   +++   PRICES SO LOW THEY FLOAT! (PRICES DO NOT FLOAT.)   +++   NO REFUNDS, NO RETURNS, NO QUESTIONS   +++   NOW WITH 12% MORE BLAST   +++   "
const W := 840.0
const ROW_H := 104.0
const ROW_GAP := 12.0
const ROWS_Y := 138.0

var info_text := ""
var marquee: Control
var fx: Control
var open_t := 0.0                # seconds since the shop opened (row stagger)
var face_mood := "hello"
var face_mood_t := 0.0
var confetti: Array = []         # { p, v, rot, spin, col, life }
var shake := {}                  # row id -> seconds left
var wallet_shown := 0.0
var wallet_pop := 0.0
var last_tick := 0.0

static func _anchor(c: Control, a: Vector2, r: Rect2) -> void:
	c.anchor_left = a.x; c.anchor_right = a.x; c.anchor_top = a.y; c.anchor_bottom = a.y
	c.offset_left = r.position.x; c.offset_top = r.position.y
	c.offset_right = r.position.x + r.size.x; c.offset_bottom = r.position.y + r.size.y

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _build_ui() -> void:
	font = HD.head_font()
	layer = CanvasLayer.new(); layer.layer = 40; add_child(layer)
	prompt = _label(26, GREEN)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.visible = false
	layer.add_child(prompt)
	_anchor(prompt, Vector2(0.5, 0.5), Rect2(-250, 120, 500, 40))
	panel = Control.new()
	panel.visible = false
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(panel)
	_anchor(panel, Vector2(0.5, 0.5), Rect2(-W * 0.5, -280, W, 560))
	panel.draw.connect(_draw_panel)
	marquee = Control.new(); marquee.clip_contents = true; marquee.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marquee.position = Vector2(198, 80); marquee.size = Vector2(420, 30)
	marquee.draw.connect(_draw_marquee)
	panel.add_child(marquee)
	list = VBoxContainer.new(); list.add_theme_constant_override("separation", int(ROW_GAP))
	list.position = Vector2(20, ROWS_Y); list.size = Vector2(W - 40, 10)
	panel.add_child(list)
	fx = Control.new(); fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	fx.draw.connect(_draw_fx)
	fx.z_index = 10
	panel.add_child(fx)

func _label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0.04, 0.02, 0.9))
	l.add_theme_constant_override("outline_size", 6)
	return l

func _fill(stock: Array) -> void:
	for c in list.get_children(): list.remove_child(c); c.queue_free()
	rows.clear()
	open_t = 0.0
	var empty := StyleBoxEmpty.new()
	for id in stock:
		var it: Dictionary = ITEMS.get(id, {})
		if it.is_empty(): continue
		var b := Button.new()
		b.custom_minimum_size = Vector2(W - 40, ROW_H)
		b.focus_mode = Control.FOCUS_ALL
		for s in ["normal", "hover", "focus", "pressed", "disabled", "hover_pressed"]: b.add_theme_stylebox_override(s, empty)
		b.draw.connect(_draw_row.bind(b, id))
		b.pressed.connect(_buy.bind(id))
		b.mouse_entered.connect(func(): if not b.has_focus(): b.grab_focus(); Snd.play("ui_move", -10))
		b.focus_entered.connect(func(): info_text = _status(id))
		list.add_child(b)
		rows.append({ id = id, button = b })
	var h := ROWS_Y + rows.size() * (ROW_H + ROW_GAP) + 92.0
	_anchor(panel, Vector2(0.5, 0.5), Rect2(-W * 0.5, -h * 0.5, W, h))
	panel.pivot_offset = Vector2(W * 0.5, h * 0.5)
	wallet_shown = Game.nuts()
	info_text = ""
	face_mood = "hello"; face_mood_t = 1.6
	_refresh()

func _status(id: String) -> String:
	var it: Dictionary = ITEMS[id]
	if Game.has(id): return "%s is already yours. Gizmart remembers every customer." % it.name
	if Game.nuts() >= int(it.price): return "%s costs %d sprockets. Press buy and it's yours." % [it.name, it.price]
	return "You need %d more sprockets for the %s." % [int(it.price) - Game.nuts(), it.name]

func _refresh() -> void:
	wallet_pop = 1.0
	for r in rows: r.button.queue_redraw()

## Called by _buy: coins burst from the price tag / the row shakes.
func _fx_buy(id: String) -> void:
	var b: Button = _row_button(id)
	if b == null: return
	var o := b.position + list.position + Vector2(b.size.x - 90, b.size.y * 0.5)
	for i in 56:
		var a := randf_range(-PI * 0.95, -PI * 0.05)
		var sp := randf_range(220.0, 620.0)
		confetti.append({ p = o, v = Vector2(cos(a), sin(a)) * sp, rot = randf() * TAU, spin = randf_range(-12, 12),
			col = [GOLD, GREEN, Color(1, 0.55, 0.75), Color(0.5, 0.9, 1)][i % 4], life = randf_range(0.8, 1.4), coin = i % 3 == 0 })
	face_mood = "excited"; face_mood_t = 2.0

func _fx_deny(id: String) -> void:
	shake[id] = 0.4
	face_mood = "sad"; face_mood_t = 1.6

func _row_button(id: String) -> Button:
	for r in rows: if r.id == id: return r.button
	return null

func _tick_ui(dt: float) -> void:
	if not panel.visible: return
	open_t += dt
	face_mood_t -= dt
	if face_mood_t <= 0.0: face_mood = "idle"
	wallet_pop = maxf(0.0, wallet_pop - dt * 4.0)
	wallet_shown = move_toward(wallet_shown, Game.nuts(), maxf(1.0, absf(Game.nuts() - wallet_shown) * 8.0) * dt)
	for k in shake.keys():
		shake[k] -= dt
		if shake[k] <= 0.0: shake.erase(k)
	for c in confetti:
		c.v.y += 900.0 * dt; c.v *= 1.0 - 1.2 * dt
		c.p += c.v * dt; c.rot += c.spin * dt; c.life -= dt
	confetti = confetti.filter(func(c): return c.life > 0.0)
	panel.queue_redraw(); marquee.queue_redraw(); fx.queue_redraw()
	for r in rows: r.button.queue_redraw()

func _draw_panel() -> void:
	var ci := panel
	var t := _now()
	var r := Rect2(Vector2.ZERO, panel.size)
	HD.panel(ci, r, GREEN, 24, 0.0, 1.0, Color(0.09, 0.2, 0.14, 0.96), Color(0.02, 0.07, 0.05, 0.96))
	# corner rivets
	for p in [Vector2(14, 14), Vector2(r.size.x - 14, 14), Vector2(14, r.size.y - 14), Vector2(r.size.x - 14, r.size.y - 14)]:
		ci.draw_circle(p, 4.5, HD.INK, true, -1, true); ci.draw_circle(p, 3, Color(0.5, 0.75, 0.55), true, -1, true)
	_draw_face(ci, Rect2(22, 16, 160, 110), t)
	# title with a little letter bounce
	var x := 198.0
	var title_s := "GIZMART"
	for i in title_s.length():
		var ch := title_s[i]
		var bob := sin(t * 3.0 - i * 0.6) * 3.0
		x += HD.text(ci, font, Vector2(x, 66 + bob), ch, 50, GREEN.lightened(0.1), 0, 9)
	HD.text(ci, HD.body_font(), Vector2(x + 12, 64), "vending + armaments", 16, Color(0.75, 0.95, 0.75), 0, 4)
	# LED strip frame behind the marquee
	var mr := Rect2(marquee.position - Vector2(4, 3), marquee.size + Vector2(8, 6))
	ci.draw_colored_polygon(HD.rrect(mr.grow(2), 8), HD.INK)
	ci.draw_colored_polygon(HD.rrect(mr, 7), Color(0.01, 0.04, 0.02))
	# wallet chip
	var s := 1.0 + 0.12 * sin(wallet_pop * PI)
	var wr := Rect2(r.size.x - 200, 30, 178, 66)
	ci.draw_set_transform(wr.get_center() * (1.0 - s), 0.0, Vector2(s, s))
	HD.panel(ci, wr, GOLD, 14, 0.0)
	HD.text(ci, font, Vector2(wr.end.x - 16, wr.position.y + 26), "YOUR SPROCKETS", 13, GOLD, 2, 4)
	HD.text(ci, font, Vector2(wr.end.x - 16, wr.position.y + 56), str(int(round(wallet_shown))), 30, Color(1, 0.95, 0.8), 2, 6)
	HD.badge(ci, Vector2(wr.position.x + 4, wr.get_center().y), 26, GOLD)
	HD.icon(ci, "sprocket", Vector2(wr.position.x + 4, wr.get_center().y), 17, GOLD, 1.0, t * 0.6)
	ci.draw_set_transform(Vector2.ZERO)
	# info line + controls
	var iy := ROWS_Y + rows.size() * (ROW_H + ROW_GAP) + 8.0
	var info_col := Color(0.88, 1, 0.88)
	if info_text.begins_with("You need") or info_text.begins_with("Not enough"): info_col = Color(1, 0.6, 0.5)
	elif info_text.ends_with("arsenal."): info_col = GOLD
	ci.draw_multiline_string(HD.body_font(), Vector2(34, iy + 20), info_text, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 68, 17, 2, info_col)
	var pad: bool = Game.player != null and Game.player.get("using_pad") == true
	var hx := 34.0
	var hy := r.size.y - 26.0
	for h in ([["L", "CHOOSE"], ["A", "BUY"], ["B", "LEAVE"]] if pad else [["W/S", "CHOOSE"], ["SPACE", "BUY"], ["E", "LEAVE"]]):
		var key: String = h[0]
		var kw := maxf(34.0, font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 18.0)
		HD.keycap(ci, Vector2(hx + kw * 0.5, hy), key, pad and key != "L")
		hx += kw + 10.0
		hx += HD.text(ci, font, Vector2(hx, hy + 7), h[1], 17, Color(0.8, 0.95, 0.8), 0, 4) + 26.0

## Gizmart's screen face: blinks, glances around and pulls a face for buys and empty wallets.
func _draw_face(ci: CanvasItem, r: Rect2, t: float) -> void:
	ci.draw_colored_polygon(HD.rrect(Rect2(r.position + Vector2(2, 5), r.size), 16), Color(0, 0, 0, 0.35))
	ci.draw_colored_polygon(HD.rrect(r.grow(3), 18), HD.INK)
	ci.draw_colored_polygon(HD.rrect(r, 16), Color(0.2, 0.55, 0.3))
	var sr := r.grow(-10)
	ci.draw_colored_polygon(HD.rrect(sr, 10), Color(0.02, 0.07, 0.04))
	# scanlines
	for y in range(int(sr.position.y) + 3, int(sr.end.y) - 2, 4):
		ci.draw_line(Vector2(sr.position.x + 4, y), Vector2(sr.end.x - 4, y), Color(0.3, 1, 0.4, 0.05), 1.0)
	var g := GREEN * Color(1, 1, 1, 0.85 + 0.15 * sin(t * 9.0))
	var c := sr.get_center()
	var look := Vector2(sin(t * 0.7) * 6.0, 0)
	var blink := fmod(t, 3.3) < 0.12
	var el := c + Vector2(-22, -10) + look
	var er := c + Vector2(22, -10) + look
	match face_mood:
		"excited":
			HD.icon(ci, "star", el, 13, GOLD, 1.0, t * 3.0); HD.icon(ci, "star", er, 13, GOLD, 1.0, -t * 3.0)
			ci.draw_arc(c + Vector2(0, 6), 24, 0.15, PI - 0.15, 18, g, 6, true)
			ci.draw_line(c + Vector2(-23, 9), c + Vector2(23, 9), g, 4, true)
		"sad":
			ci.draw_line(el + Vector2(-9, -2), el + Vector2(9, 3), g, 5, true)
			ci.draw_line(er + Vector2(-9, 3), er + Vector2(9, -2), g, 5, true)
			ci.draw_arc(c + Vector2(0, 30), 16, PI + 0.4, TAU - 0.4, 14, g, 5, true)
			ci.draw_circle(er + Vector2(8, 12 + fmod(t * 30.0, 18.0)), 3, Color(0.5, 0.9, 1), true, -1, true)
		_:
			for e in [el, er]:
				if blink: ci.draw_line(e + Vector2(-8, 0), e + Vector2(8, 0), g, 4, true)
				else: ci.draw_circle(e, 8, g, true, -1, true)
			ci.draw_arc(c + Vector2(0, 8), 20, 0.3, PI - 0.3, 16, g, 5, true)

func _draw_marquee() -> void:
	var f := HD.head_font()
	var size := 18
	var w := f.get_string_size(TICKER, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var off := fmod(_now() * 70.0, w)
	for k in 2:
		var x := -off + k * w
		marquee.draw_string(f, Vector2(x, 22), TICKER, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0.55, 1, 0.45, 0.95))
	# LED dot mask
	for y in range(0, int(marquee.size.y), 3):
		marquee.draw_line(Vector2(0, y), Vector2(marquee.size.x, y), Color(0.01, 0.04, 0.02, 0.45), 1.0)

func _draw_row(b: Button, id: String) -> void:
	var it: Dictionary = ITEMS[id]
	var t := _now()
	var idx := 0
	for i in rows.size(): if rows[i].id == id: idx = i
	var appear := clampf((open_t - 0.05 - idx * 0.07) / 0.22, 0.0, 1.0)
	var ease := 1.0 - pow(1.0 - appear, 3.0)
	var sel := b.has_focus()
	var owned: bool = Game.has(id)
	var afford: bool = Game.nuts() >= int(it.price)
	var wc: Color = Game.combat.weapon_color(id) if Game.combat and Game.combat.has_method("weapon_color") else GREEN
	var sh: float = shake.get(id, 0.0)
	var ox := (1.0 - ease) * 60.0 + (10.0 if sel else 0.0) + sin(t * 60.0) * 10.0 * sh
	var a := ease
	var r := Rect2(ox, 4, b.size.x - 24, b.size.y - 8)
	var acc := wc if sel else Color(0.35, 0.6, 0.4)
	if sel: acc = acc.lerp(Color.WHITE, 0.25 + 0.15 * sin(t * 5.0))
	HD.panel(b, r, acc, 16, 0.0, a, Color(0.16, 0.3, 0.22, 0.96) if sel else Color(0.1, 0.2, 0.15, 0.93), Color(0.03, 0.1, 0.06, 0.96))
	if sel:
		# a light sweep across the selected row
		var sx := fmod(t * 520.0, r.size.x + 400.0) - 200.0
		var band := PackedVector2Array([Vector2(r.position.x + sx, r.position.y + 3), Vector2(r.position.x + sx + 60, r.position.y + 3),
			Vector2(r.position.x + sx + 20, r.end.y - 3), Vector2(r.position.x + sx - 40, r.end.y - 3)])
		var keep := PackedVector2Array()
		for p in band: keep.append(Vector2(clampf(p.x, r.position.x + 14, r.end.x - 14), p.y))
		b.draw_colored_polygon(keep, Color(1, 1, 1, 0.07 * a))
	# emblem
	var ec := Vector2(r.position.x + 52, r.get_center().y)
	var es := 1.0 + (0.06 * sin(t * 4.0) if sel else 0.0)
	HD.badge(b, ec, 38 * es, wc, a)
	HD.icon(b, HD.weapon_icon(id), ec, 22 * es, wc, a)
	# name + kind + blurb
	var bf := HD.body_font()
	var nx := r.position.x + 106
	var nw := HD.text(b, font, Vector2(nx, r.position.y + 38), it.name, 28, wc.lightened(0.2) if sel else Color(0.92, 1, 0.92), 0, 6, a)
	var tag: String = String(it.kind).to_upper()
	var tw := font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 16
	var tr := Rect2(nx + nw + 12, r.position.y + 20, tw, 22)
	b.draw_colored_polygon(HD.rrect(tr, 8), Color(wc.darkened(0.55), 0.9 * a))
	HD.text(b, font, Vector2(tr.get_center().x, tr.position.y + 16), tag, 13, wc.lightened(0.3), 1, 0, a)
	b.draw_multiline_string(bf, Vector2(nx, r.position.y + 62), it.desc, HORIZONTAL_ALIGNMENT_LEFT, 470, 16, 2, Color(0.78, 0.92, 0.82, a))
	# price tag / owned stamp
	var pc := Vector2(r.end.x - 92, r.get_center().y)
	if owned:
		b.draw_set_transform(pc, -0.12, Vector2.ONE)
		var stamp := Rect2(-70, -22, 140, 44)
		b.draw_polyline(PackedVector2Array([stamp.position, Vector2(stamp.end.x, stamp.position.y), stamp.end, Vector2(stamp.position.x, stamp.end.y), stamp.position]), Color(0.55, 1, 0.5, 0.9 * a), 3.5, true)
		HD.text(b, font, Vector2(0, 11), "OWNED", 28, Color(0.6, 1, 0.55), 1, 6, a)
		b.draw_set_transform(Vector2.ZERO)
	else:
		var bob := sin(t * 3.0 + idx) * 2.0 if sel else 0.0
		var col := GOLD if afford else Color(1, 0.42, 0.35)
		if sh > 0.0: col = col.lerp(Color(1, 0.2, 0.15), 0.6)
		var pr := Rect2(pc.x - 74, pc.y - 26 + bob, 148, 52)
		HD.panel(b, pr, col, 14, 0.0, a, Color(0.45, 0.32, 0.08, 0.96) if afford else Color(0.38, 0.1, 0.08, 0.96), Color(0.2, 0.13, 0.03, 0.96) if afford else Color(0.18, 0.04, 0.03, 0.96))
		HD.icon(b, "sprocket", Vector2(pr.position.x + 26, pr.get_center().y), 14, GOLD, a, t * (1.5 if sel else 0.3))
		HD.text(b, font, Vector2(pr.end.x - 14, pr.get_center().y + 11), str(it.price), 30, col.lightened(0.3), 2, 6, a)
		if sel and not afford:
			HD.text(b, HD.body_font(), Vector2(pr.get_center().x, pr.end.y + 14), "NEED %d MORE" % (int(it.price) - Game.nuts()), 12, Color(1, 0.6, 0.5), 1, 4, a)

func _draw_fx() -> void:
	for c in confetti:
		var al := clampf(c.life / 0.4, 0.0, 1.0)
		if c.coin:
			HD.icon(fx, "sprocket", c.p, 12, GOLD, al, c.rot)
		else:
			fx.draw_set_transform(c.p, c.rot, Vector2.ONE)
			fx.draw_rect(Rect2(-7, -4, 14, 8), Color(c.col, al))
			fx.draw_set_transform(Vector2.ZERO)
