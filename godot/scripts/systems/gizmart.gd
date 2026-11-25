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

var kiosks: Array = []        # { node: Node3D, spot: Dictionary, front: Vector3 }
var near := -1
var open_i := -1
var hello_cd := 0.0

var layer: CanvasLayer
var prompt: Label
var panel: PanelContainer
var title: Label
var tagline: Label
var wallet: Label
var list: VBoxContainer
var info: Label
var rows: Array = []          # { id, button: Button, price_label: Label }
var font: SystemFont
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
		var fwd := Vector3(sin(yaw), 0, cos(yaw))
		Kit.set_glow(k, "grin", Color(0.55, 1, 0.45), 3.0)
		Kit.set_glow(k, "eyes", Color(0.55, 1, 0.45), 3.0)
		var tag := Label3D.new(); tag.text = "GIZMART"; tag.font_size = 96; tag.pixel_size = 0.006
		tag.modulate = Color(0.6, 1, 0.5); tag.outline_size = 12; tag.position = Vector3(0, 3.5, 0.2)
		tag.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		k.add_child(tag)
		kiosks.append({ node = k, spot = s, front = (s.pos as Vector3) + fwd * 1.5 })

func _process(dt: float) -> void:
	hello_cd -= dt
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
	prompt.visible = near >= 0
	if near >= 0:
		var g := sin(Time.get_ticks_msec() / 1000.0 * 4.0) * 0.5 + 0.5
		prompt.modulate.a = 0.75 + 0.25 * g
		if Input.is_action_just_pressed("interact"): _open(near)

# ---------------------------------------------------------------- open / close / buy
func _open(i: int, pause := true) -> void:
	open_i = i
	prompt.visible = false
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
	if hello_cd <= 0.0: Snd.bark("gizmart", "hello"); hello_cd = 20.0
	if rows.size() > 0: rows[0].button.grab_focus()

func _close() -> void:
	if open_i < 0: return
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
		info.text = "%s added to your arsenal." % it.name
	else:
		Snd.play("shop_deny", -2)
		if not (Snd.voice_player and Snd.voice_player.playing): Snd.bark("gizmart", "poor")
		info.text = "You need %d more sprockets." % (int(it.price) - Game.nuts())
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
static func _anchor(c: Control, a: Vector2, r: Rect2) -> void:
	c.anchor_left = a.x; c.anchor_right = a.x; c.anchor_top = a.y; c.anchor_bottom = a.y
	c.offset_left = r.position.x; c.offset_top = r.position.y
	c.offset_right = r.position.x + r.size.x; c.offset_bottom = r.position.y + r.size.y

func _label(size: int, color: Color, bold := true) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font if bold else ThemeDB.fallback_font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0.04, 0.02, 0.9))
	l.add_theme_constant_override("outline_size", 6 if bold else 0)
	return l

func _style(bg: Color, border: Color, r := 14, bw := 3) -> StyleBoxFlat:
	var s := StyleBoxFlat.new(); s.bg_color = bg; s.border_color = border; s.set_border_width_all(bw); s.set_corner_radius_all(r)
	s.content_margin_left = 18; s.content_margin_right = 18; s.content_margin_top = 12; s.content_margin_bottom = 12
	return s

func _build_ui() -> void:
	font = SystemFont.new(); font.font_names = PackedStringArray(["Inter", "Segoe UI", "Arial", "sans-serif"])
	font.font_weight = 900; font.font_italic = true
	layer = CanvasLayer.new(); layer.layer = 40; add_child(layer)
	prompt = _label(26, Color(0.7, 1, 0.6))
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.visible = false
	layer.add_child(prompt)
	_anchor(prompt, Vector2(0.5, 0.5), Rect2(-250, 120, 500, 40))

	panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(Color(0.04, 0.1, 0.07, 0.94), Color(0.55, 1, 0.45), 22, 4))
	panel.custom_minimum_size = Vector2(760, 0)
	panel.visible = false
	layer.add_child(panel)
	_anchor(panel, Vector2(0.5, 0.5), Rect2(-380, -230, 760, 300))
	panel.pivot_offset = Vector2(380, 200)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 10); panel.add_child(v)
	var head := HBoxContainer.new(); v.add_child(head)
	var face := Control.new(); face.custom_minimum_size = Vector2(84, 84); face.draw.connect(_draw_face.bind(face)); head.add_child(face)
	var hv := VBoxContainer.new(); hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL; head.add_child(hv)
	title = _label(40, Color(0.65, 1, 0.5)); title.text = "GIZMART"
	hv.add_child(title)
	tagline = _label(17, Color(0.85, 1, 0.8), false)
	tagline.text = "SKYHARBOR SKY-HIGH EDITION  ·  Prices so low they float! (Prices do not float.)"
	tagline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hv.add_child(tagline)
	wallet = _label(26, Color(1, 0.85, 0.35)); wallet.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	wallet.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(wallet)
	var sep := HSeparator.new(); var line := StyleBoxLine.new(); line.color = Color(0.55, 1, 0.45, 0.45); line.thickness = 2
	sep.add_theme_stylebox_override("separator", line); v.add_child(sep)
	list = VBoxContainer.new(); list.add_theme_constant_override("separation", 8); v.add_child(list)
	info = _label(18, Color(0.85, 1, 0.8), false)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; info.custom_minimum_size = Vector2(700, 48)
	v.add_child(info)
	var hint := _label(15, Color(0.7, 0.85, 0.7), false)
	hint.text = "W/S or stick: choose    SPACE / A or click: buy    E / ESC / B: leave"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hint)

func _fill(stock: Array) -> void:
	for c in list.get_children(): c.queue_free()
	rows.clear()
	for id in stock:
		var it: Dictionary = ITEMS.get(id, {})
		if it.is_empty(): continue
		var b := Button.new()
		b.custom_minimum_size = Vector2(700, 84)
		b.focus_mode = Control.FOCUS_ALL
		b.add_theme_stylebox_override("normal", _style(Color(0.08, 0.18, 0.12, 0.9), Color(0.3, 0.6, 0.3), 12, 2))
		b.add_theme_stylebox_override("hover", _style(Color(0.12, 0.26, 0.16, 0.95), Color(0.55, 1, 0.45), 12, 2))
		b.add_theme_stylebox_override("focus", _style(Color(0.14, 0.32, 0.18, 0.95), Color(0.75, 1, 0.55), 12, 3))
		b.add_theme_stylebox_override("pressed", _style(Color(0.2, 0.4, 0.2, 0.95), Color(1, 1, 0.6), 12, 3))
		var h := HBoxContainer.new(); h.set_anchors_preset(Control.PRESET_FULL_RECT); h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.offset_left = 18; h.offset_right = -18
		b.add_child(h)
		var icon := Control.new(); icon.custom_minimum_size = Vector2(64, 64); icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.draw.connect(_draw_icon.bind(icon, id)); h.add_child(icon)
		var tv := VBoxContainer.new(); tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL; tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tv.alignment = BoxContainer.ALIGNMENT_CENTER
		h.add_child(tv)
		var n := _label(26, Color(1, 1, 1)); n.text = "  " + it.name; n.mouse_filter = Control.MOUSE_FILTER_IGNORE; tv.add_child(n)
		var d := _label(15, Color(0.75, 0.9, 0.78), false); d.text = "   " + it.desc; d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; d.custom_minimum_size = Vector2(420, 0); tv.add_child(d)
		var pl := _label(24, Color(1, 0.85, 0.35)); pl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pl.size_flags_vertical = Control.SIZE_SHRINK_CENTER; pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		pl.custom_minimum_size = Vector2(170, 0)
		h.add_child(pl)
		b.pressed.connect(_buy.bind(id))
		b.focus_entered.connect(func(): info.text = "%s  ·  %s" % [it.kind.to_upper(), it.desc])
		list.add_child(b)
		rows.append({ id = id, button = b, price_label = pl })
	_refresh()

func _refresh() -> void:
	wallet.text = "%d\nSPROCKETS" % Game.nuts()
	for r in rows:
		var it: Dictionary = ITEMS[r.id]
		if Game.has(r.id):
			r.price_label.text = "OWNED"; r.price_label.add_theme_color_override("font_color", Color(0.55, 1, 0.5))
		else:
			r.price_label.text = "%d" % it.price + "\nSPROCKETS"
			r.price_label.add_theme_color_override("font_color", Color(1, 0.85, 0.35) if Game.nuts() >= int(it.price) else Color(1, 0.45, 0.35))

## Gizmart's face: a vending machine with a light-up grin.
func _draw_face(c: Control) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	c.draw_rect(Rect2(8, 2, 68, 80), Color(0.2, 0.55, 0.3))
	c.draw_rect(Rect2(14, 8, 56, 40), Color(0.06, 0.12, 0.1))
	var g := Color(0.55, 1, 0.45)
	c.draw_circle(Vector2(30, 22), 5, g); c.draw_circle(Vector2(54, 22), 5, g)
	c.draw_arc(Vector2(42, 30), 14, 0.3, PI - 0.3, 14, g * (0.8 + 0.2 * sin(t * 6.0)), 4)
	for i in 3: c.draw_rect(Rect2(16 + i * 18, 54, 14, 10), Color(0.95, 0.75, 0.2))
	c.draw_rect(Rect2(30, 70, 24, 6), Color(0.05, 0.05, 0.05))
	c.queue_redraw()

## Simple weapon icons drawn in code (until the art lands).
func _draw_icon(c: Control, id: String) -> void:
	var o := Vector2(32, 32)
	c.draw_circle(o, 30, Color(0.03, 0.08, 0.05))
	match id:
		"scatter_bloom":
			for i in 6:
				var a := i * TAU / 6.0
				c.draw_circle(o + Vector2(cos(a), sin(a)) * 14, 9, Color(1, 0.45, 0.6))
			c.draw_circle(o, 8, Color(1, 0.85, 0.3))
		"thump_lobber":
			c.draw_arc(o + Vector2(0, 12), 22, PI + 0.4, TAU - 0.4, 16, Color(0.7, 0.9, 1), 3)
			c.draw_circle(o + Vector2(10, -6), 10, Color(0.35, 0.8, 0.4))
			c.draw_rect(Rect2(o + Vector2(6, -18), Vector2(8, 5)), Color(0.9, 0.9, 0.9))
		"seeker_hive":
			for i in 7:
				var a := i * TAU / 7.0
				var p := o + Vector2(cos(a), sin(a)) * (8 + (i % 3) * 6)
				c.draw_circle(p, 4.5, Color(1, 0.8, 0.2))
				c.draw_line(p, p + Vector2(cos(a + 1.0), sin(a + 1.0)) * 6, Color(0.6, 0.95, 1), 2)
