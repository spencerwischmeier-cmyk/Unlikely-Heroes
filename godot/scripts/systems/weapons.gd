extends Node
## Weapon switching: number keys 1-4, mouse wheel / D-pad left-right to cycle, and the weapon wheel
## (hold Q or pad LB): time slows down while it is open, point with the mouse or a stick and let go
## to equip. Weapons you don't own yet show as locked. Combat (combat.gd) owns the weapons themselves.
## Input actions are added at runtime when the project doesn't define them.
## Debug: --all-weapons unlocks every weapon (combat.gd), --wheel holds the wheel open (screenshots),
## --weapon=<id> starts with that weapon, --wpn-level=<1-5> sets every weapon's level.

const SLOW := 0.2
const R := 170.0

var layer: CanvasLayer
var wheel: Control
var center_label: Label
var sub_label: Label
var font: SystemFont
var open := false
var sel := -1
var point := Vector2.ZERO
var hold_debug := false
var t := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_actions()
	_build_ui()
	var args := OS.get_cmdline_user_args()
	hold_debug = args.has("--wheel")
	for a in args:
		if a.begins_with("--weapon="): _equip_later.call_deferred(a.substr(9))
		if a.begins_with("--wpn-level="): _level_later.call_deferred(clampi(int(a.substr(12)), 1, 5))

func _equip_later(id: String) -> void:
	if Game.combat: Game.combat.equip(id)

func _level_later(lv: int) -> void:
	var c := Game.combat
	if c == null: return
	for id in c.ORDER:
		c.wdata[id].xp = 0 if lv <= 1 else c.XP_STEPS[lv - 2]
		if c.uses_ammo(id): c.wdata[id].ammo = c.max_ammo(id)
	c._store(); c._emit_status(c.current)

static func _key(action: String, key: Key) -> void:
	var k := InputEventKey.new(); k.physical_keycode = key; InputMap.action_add_event(action, k)

static func _pad(action: String, b: JoyButton) -> void:
	var j := InputEventJoypadButton.new(); j.button_index = b; InputMap.action_add_event(action, j)

func _actions() -> void:
	if not InputMap.has_action("weapon_wheel"):
		InputMap.add_action("weapon_wheel", 0.5); _key("weapon_wheel", KEY_Q); _pad("weapon_wheel", JOY_BUTTON_LEFT_SHOULDER)
	var keys := [KEY_1, KEY_2, KEY_3, KEY_4]
	for i in 4:
		var a := "weapon_%d" % (i + 1)
		if not InputMap.has_action(a): InputMap.add_action(a, 0.5); _key(a, keys[i])
	if not InputMap.has_action("weapon_next"):
		InputMap.add_action("weapon_next", 0.5); _pad("weapon_next", JOY_BUTTON_DPAD_RIGHT)
		var m := InputEventMouseButton.new(); m.button_index = MOUSE_BUTTON_WHEEL_DOWN; InputMap.action_add_event("weapon_next", m)
	if not InputMap.has_action("weapon_prev"):
		InputMap.add_action("weapon_prev", 0.5); _pad("weapon_prev", JOY_BUTTON_DPAD_LEFT)
		var m := InputEventMouseButton.new(); m.button_index = MOUSE_BUTTON_WHEEL_UP; InputMap.action_add_event("weapon_prev", m)

func _blocked() -> bool:
	return Game.input_locked or get_tree().paused or Game.combat == null or Game.player == null \
		or Game.player.process_mode == Node.PROCESS_MODE_DISABLED

## Gizmart restocks ammo when you open the shop: a few sprockets per round (whatever you can afford).
const AMMO_PRICE := { scatter_bloom = 2, thump_lobber = 8, seeker_hive = 2 }
var shop_was_open := false
var gizmart: Node

func _restock() -> void:
	var c := Game.combat
	var spent := 0
	var rounds := 0
	for id in c.owned_weapons():
		if not c.uses_ammo(id): continue
		var price: int = AMMO_PRICE.get(id, 3)
		var missing: int = c.max_ammo(id) - c.ammo(id)
		var n := mini(missing, Game.nuts() / price)
		if n <= 0: continue
		if Game.spend_nuts(n * price):
			c.add_ammo(id, n); spent += n * price; rounds += n
	if rounds > 0 and Game.hud and Game.hud.has_method("toast"):
		Game.hud.toast("AMMO RESTOCKED", "%d rounds for %d sprockets. Gizmart thanks you for your business." % [rounds, spent], Color(0.6, 1, 0.5))

func _process(dt: float) -> void:
	t += dt
	if gizmart == null: gizmart = get_parent().get_node_or_null("Gizmart")
	if gizmart and "open_i" in gizmart and Game.combat:
		var shop_open: bool = gizmart.open_i >= 0
		if shop_open and not shop_was_open: _restock()
		shop_was_open = shop_open
	if _blocked():
		if open: _close(false)
		return
	var c := Game.combat
	for i in 4:
		if Input.is_action_just_pressed("weapon_%d" % (i + 1)):
			var id: String = c.ORDER[i]
			if c.usable(id): c.equip(id)
			elif Game.hud and Game.hud.has_method("toast_small"): Game.hud.toast_small("%s: NOT OWNED YET" % c.WEAPONS[id].name, Color(0.7, 0.75, 0.8))
	if not open:
		if Input.is_action_just_pressed("weapon_next"): c.cycle(1)
		if Input.is_action_just_pressed("weapon_prev"): c.cycle(-1)
	var want := Input.is_action_pressed("weapon_wheel") or hold_debug
	if want and not open: _open()
	elif open and not want: _close(true)
	if open:
		Engine.time_scale = SLOW
		# sticks point at a slot too
		var st := Input.get_vector("look_left", "look_right", "look_up", "look_down")
		var ls := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		if ls.length() > st.length(): st = ls
		if st.length() > 0.5: point = st * R
		var new_sel := sel
		if point.length() > 40.0:
			var a := fposmod(atan2(point.x, -point.y) + PI / 4.0, TAU)
			new_sel = int(a / (PI / 2.0)) % 4
		if new_sel != sel:
			sel = new_sel; Snd.play("ui_move", -10, 0.0, 0.0)
		_label_sel()
		wheel.queue_redraw()

func _input(e: InputEvent) -> void:
	if not open: return
	if e is InputEventMouseMotion:
		point = (point + e.relative * 1.2).limit_length(R)
		get_viewport().set_input_as_handled()
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		_close(true)
		get_viewport().set_input_as_handled()

func _open() -> void:
	open = true
	Game.combat.wheel_open = true
	sel = Game.combat.ORDER.find(Game.combat.current)
	var a := sel * PI / 2.0
	point = Vector2(sin(a), -cos(a)) * R * 0.6
	wheel.visible = true
	wheel.modulate.a = 0.0; wheel.scale = Vector2(0.85, 0.85)
	var tw := wheel.create_tween().set_parallel().set_ignore_time_scale(true)
	tw.tween_property(wheel, "modulate:a", 1.0, 0.1); tw.tween_property(wheel, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK)
	Snd.play("ui_select", -8, 0.0, 0.0)

func _close(apply: bool) -> void:
	open = false
	wheel.visible = false
	Engine.time_scale = 1.0
	if Game.combat:
		Game.combat.wheel_open = false
		if apply and sel >= 0:
			var id: String = Game.combat.ORDER[sel]
			if Game.combat.usable(id): Game.combat.equip(id)
			else: Snd.play("shop_deny", -8, 0.0, 0.0)

func _label_sel() -> void:
	var c := Game.combat
	if sel < 0: center_label.text = ""; sub_label.text = ""; return
	var id: String = c.ORDER[sel]
	if c.usable(id):
		center_label.text = c.weapon_name(id)
		center_label.add_theme_color_override("font_color", c.weapon_color(id))
		var lv: int = c.level(id)
		var am := "unlimited (heat)" if not c.uses_ammo(id) else "%d / %d" % [c.ammo(id), c.max_ammo(id)]
		sub_label.text = "V%d   ·   %s\n%s" % [lv, am, c.WEAPONS[id].blurb]
	else:
		center_label.text = "LOCKED"
		center_label.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7))
		sub_label.text = "%s\nSold at Gizmart." % c.WEAPONS[id].name

# ---------------------------------------------------------------- UI
func _build_ui() -> void:
	font = SystemFont.new(); font.font_names = PackedStringArray(["Inter", "Segoe UI", "Arial", "sans-serif"])
	font.font_weight = 900; font.font_italic = true
	layer = CanvasLayer.new(); layer.layer = 30; add_child(layer)
	wheel = Control.new()
	wheel.anchor_left = 0.5; wheel.anchor_right = 0.5; wheel.anchor_top = 0.5; wheel.anchor_bottom = 0.5
	wheel.offset_left = -260; wheel.offset_right = 260; wheel.offset_top = -260; wheel.offset_bottom = 260
	wheel.pivot_offset = Vector2(260, 260)
	wheel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wheel.visible = false
	wheel.draw.connect(_draw_wheel)
	layer.add_child(wheel)
	center_label = _label(28); center_label.position = Vector2(110, 210); center_label.size = Vector2(300, 40)
	wheel.add_child(center_label)
	sub_label = _label(15); sub_label.position = Vector2(130, 250); sub_label.size = Vector2(260, 80)
	sub_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub_label.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	wheel.add_child(sub_label)

func _label(size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color(0, 0.04, 0.1, 0.9))
	l.add_theme_constant_override("outline_size", 8)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _draw_wheel() -> void:
	var c := Game.combat
	if c == null: return
	var o := Vector2(260, 260)
	wheel.draw_circle(o, 250, Color(0.02, 0.05, 0.09, 0.55))
	wheel.draw_arc(o, 250, 0, TAU, 96, Color(0.45, 0.95, 1.0, 0.35), 3, true)
	wheel.draw_circle(o, 112, Color(0.02, 0.05, 0.09, 0.8))
	for i in 4:
		var id: String = c.ORDER[i]
		var a0 := i * PI / 2.0 - PI / 4.0 - PI / 2.0
		var owned: bool = c.usable(id)
		var col: Color = c.weapon_color(id) if owned else Color(0.45, 0.5, 0.55)
		var is_sel := i == sel
		var pts := PackedVector2Array()
		var r0 := 120.0
		var r1 := 244.0 if is_sel else 232.0
		for k in 17:
			var a := a0 + 0.04 + (PI / 2.0 - 0.08) * k / 16.0
			pts.append(o + Vector2(cos(a), sin(a)) * r1)
		for k in range(16, -1, -1):
			var a := a0 + 0.06 + (PI / 2.0 - 0.12) * k / 16.0
			pts.append(o + Vector2(cos(a), sin(a)) * r0)
		var fill := Color(col.r, col.g, col.b, 0.42 if is_sel else 0.14)
		wheel.draw_colored_polygon(pts, fill)
		pts.append(pts[0])
		wheel.draw_polyline(pts, Color(col.r, col.g, col.b, 0.95 if is_sel else 0.45), 3.0 if is_sel else 1.5, true)
		var mid := a0 + PI / 4.0
		var ic := o + Vector2(cos(mid), sin(mid)) * 176.0
		_icon(ic, id, col, owned, 1.25 if is_sel else 1.0)
		# key number and level
		wheel.draw_string(font, ic + Vector2(-48, -34), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.7))
		if owned:
			var lv: int = c.level(id)
			wheel.draw_string(font, ic + Vector2(22, -34), "V%d" % lv, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 0.82, 0.3) if lv >= 5 else Color(1, 1, 1, 0.85))
			if c.uses_ammo(id):
				var f := float(c.ammo(id)) / maxf(1.0, c.max_ammo(id))
				wheel.draw_rect(Rect2(ic + Vector2(-30, 40), Vector2(60, 5)), Color(0, 0, 0, 0.5))
				wheel.draw_rect(Rect2(ic + Vector2(-30, 40), Vector2(60 * f, 5)), col)
	# pointer
	if point.length() > 10.0:
		var pd := point.normalized()
		wheel.draw_line(o + pd * 96.0, o + pd * 112.0, Color(1, 1, 1, 0.9), 4.0, true)
	var title_c := Color(1, 1, 1, 0.55)
	wheel.draw_string(font, o + Vector2(-60, -70), "WEAPONS", HORIZONTAL_ALIGNMENT_CENTER, 120, 16, title_c)

## Small weapon icons drawn in code.
func _icon(p: Vector2, id: String, col: Color, owned: bool, s: float) -> void:
	var dim := 1.0 if owned else 0.5
	var c := Color(col.r, col.g, col.b, dim)
	wheel.draw_circle(p, 30 * s, Color(0.02, 0.05, 0.08, 0.85))
	match id:
		"arc_lancer":
			wheel.draw_rect(Rect2(p + Vector2(-22, -6) * s, Vector2(30, 12) * s), Color(0.95, 0.96, 0.98, dim))
			wheel.draw_rect(Rect2(p + Vector2(8, -3) * s, Vector2(16, 6) * s), Color(0.2, 0.25, 0.3, dim))
			for k in 3: wheel.draw_arc(p + Vector2(-12 + k * 8, 0) * s, 7 * s, 0, TAU, 12, c, 2)
			wheel.draw_line(p + Vector2(24, 0) * s, p + Vector2(30, -6) * s, c, 2)
			wheel.draw_line(p + Vector2(30, -6) * s, p + Vector2(26, 4) * s, c, 2)
		"scatter_bloom":
			for k in 6:
				var a := k * TAU / 6.0
				wheel.draw_circle(p + Vector2(cos(a), sin(a)) * 13 * s, 8 * s, c)
			wheel.draw_circle(p, 7 * s, Color(1, 0.85, 0.3, dim))
		"thump_lobber":
			wheel.draw_arc(p + Vector2(0, 14) * s, 22 * s, PI + 0.4, TAU - 0.4, 16, Color(0.7, 0.9, 1, dim), 3)
			wheel.draw_circle(p + Vector2(9, -5) * s, 10 * s, c)
			wheel.draw_rect(Rect2(p + Vector2(5, -18) * s, Vector2(8, 5) * s), Color(0.9, 0.9, 0.9, dim))
		"seeker_hive":
			for k in 7:
				var a := k * TAU / 7.0
				var q := p + Vector2(cos(a), sin(a)) * (7 + (k % 3) * 6) * s
				wheel.draw_circle(q, 4.5 * s, c)
				wheel.draw_line(q, q + Vector2(cos(a + 1.0), sin(a + 1.0)) * 6 * s, Color(0.6, 0.95, 1, dim), 2)
	if not owned:
		wheel.draw_rect(Rect2(p + Vector2(-9, -2) * s, Vector2(18, 14) * s), Color(0.75, 0.78, 0.82))
		wheel.draw_arc(p + Vector2(0, -2) * s, 7 * s, PI, TAU, 10, Color(0.75, 0.78, 0.82), 3)
