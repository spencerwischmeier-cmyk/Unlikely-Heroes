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
var veil: Control
var font: Font
var body_font: Font
var open_rt := 0.0          # real time the wheel opened (the game runs slowed while it is open)
var sel_rt := 0.0           # real time the selection last changed
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
			sel = new_sel; sel_rt = _rt(); Snd.play("ui_move", -10, 0.0, 0.0)
		wheel.queue_redraw()
		veil.queue_redraw()

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
	open_rt = _rt(); sel_rt = open_rt
	wheel.visible = true; veil.visible = true
	wheel.modulate.a = 0.0; wheel.scale = Vector2(0.8, 0.8); veil.modulate.a = 0.0
	var tw := wheel.create_tween().set_parallel().set_ignore_time_scale(true)
	tw.tween_property(wheel, "modulate:a", 1.0, 0.1); tw.tween_property(wheel, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK)
	tw.tween_property(veil, "modulate:a", 1.0, 0.18)
	Snd.play("wheel_open", -6, 0.0, 0.0)

func _close(apply: bool) -> void:
	open = false
	wheel.visible = false; veil.visible = false
	Engine.time_scale = 1.0
	Snd.play("wheel_close", -8, 0.0, 0.0)
	if Game.combat:
		Game.combat.wheel_open = false
		if apply and sel >= 0:
			var id: String = Game.combat.ORDER[sel]
			if Game.combat.usable(id): Game.combat.equip(id)
			else: Snd.play("shop_deny", -8, 0.0, 0.0)

static func _rt() -> float:
	return Time.get_ticks_msec() / 1000.0

# ---------------------------------------------------------------- UI
## The wheel is drawn in the HUD's style (hud_draw.gd): a brushed-metal ring split into four glossy
## slices, each with the weapon's emblem badge, slot key, V-level chip and an ammo arc. The picked
## slice springs outwards and the hub shows its name, ammo and a short blurb. A dark veil with a
## slow-motion ring sits behind it while time is slowed.
const HD := preload("res://scripts/ui/hud_draw.gd")
const W := 640.0
const O := Vector2(320, 330)
const R_IN := 116.0
const R_OUT := 224.0

func _build_ui() -> void:
	font = HD.head_font()
	body_font = HD.body_font()
	layer = CanvasLayer.new(); layer.layer = 30; add_child(layer)
	veil = Control.new(); veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE; veil.visible = false
	veil.draw.connect(_draw_veil)
	layer.add_child(veil)
	wheel = Control.new()
	wheel.anchor_left = 0.5; wheel.anchor_right = 0.5; wheel.anchor_top = 0.5; wheel.anchor_bottom = 0.5
	wheel.offset_left = -W / 2; wheel.offset_right = W / 2; wheel.offset_top = -O.y; wheel.offset_bottom = W - O.y + 40
	wheel.pivot_offset = O
	wheel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wheel.visible = false
	wheel.draw.connect(_draw_wheel)
	layer.add_child(wheel)

func _draw_veil() -> void:
	var sz := veil.size
	var c := sz * 0.5
	veil.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.0, 0.02, 0.06, 0.38))
	# darker towards the corners
	var rmax := c.length()
	for i in 10:
		var f := float(i) / 10.0
		veil.draw_arc(c, lerpf(rmax * 0.55, rmax * 1.05, f), 0, TAU, 72, Color(0.0, 0.01, 0.04, 0.07), rmax * 0.06, true)
	# slow-motion rings drifting outwards
	var rt := _rt()
	for k in 3:
		var ph := fposmod(rt * 0.35 + k / 3.0, 1.0)
		veil.draw_arc(c, lerpf(260.0, rmax, ph), 0, TAU, 96, Color(0.45, 0.95, 1.0, 0.12 * (1.0 - ph)), 3.0, true)
	# "time slowed" tag up top
	var tag := Rect2(c.x - 92, 26, 184, 34)
	HD.panel(veil, tag, Color(0.45, 0.95, 1.0), 10, 0.12, 0.95)
	HD.icon(veil, "dash", Vector2(tag.position.x + 24, tag.get_center().y), 10, Color(0.45, 0.95, 1.0))
	HD.text(veil, font, Vector2(c.x + 12, tag.position.y + 25), "TIME SLOWED", 19, Color(0.85, 0.97, 1.0), 1, 5)

func _slice(a0: float, a1: float, r0: float, r1: float, off: Vector2, steps := 18) -> PackedVector2Array:
	var p := PackedVector2Array()
	for k in steps + 1:
		var a := lerpf(a0, a1, float(k) / steps); p.append(O + off + Vector2(cos(a), sin(a)) * r1)
	for k in range(steps, -1, -1):
		var a := lerpf(a0, a1, float(k) / steps); p.append(O + off + Vector2(cos(a), sin(a)) * r0)
	return p

func _draw_wheel() -> void:
	var c := Game.combat
	if c == null: return
	var ci := wheel
	var rt := _rt()
	var since_open := rt - open_rt
	var pad: bool = Game.player != null and "using_pad" in Game.player and Game.player.using_pad
	# ---- header plate
	var hr := Rect2(O.x - 110, 2, 220, 44)
	HD.panel(ci, hr, Color(1.0, 0.82, 0.3), 12, 0.12)
	HD.icon(ci, "ammo", Vector2(hr.position.x + 30, hr.get_center().y), 12, Color(1.0, 0.82, 0.3))
	HD.text(ci, font, Vector2(O.x + 14, hr.position.y + 33), "WEAPONS", 27, Color(1, 0.92, 0.6), 1, 6)
	# ---- outer ring: shadow, ink, brushed metal, ink seam
	ci.draw_circle(O + Vector2(2, 7), R_OUT + 22, Color(0, 0, 0, 0.35), true, -1, true)
	ci.draw_circle(O, R_OUT + 20, HD.INK, true, -1, true)
	var ring := PackedVector2Array(HD._circle_pts(96, R_OUT + 17, O))
	ci.draw_polygon(ring, HD._metal_cols(ring, Rect2(O - Vector2.ONE * (R_OUT + 17), Vector2.ONE * (R_OUT + 17) * 2.0), 1.0))
	ci.draw_circle(O, R_OUT + 9, HD.INK, true, -1, true)
	ci.draw_circle(O, R_OUT + 6, Color(0.03, 0.05, 0.11, 0.96), true, -1, true)
	# bolts on the metal ring, and a slowly turning tick ring inside it
	for k in 8:
		var a := TAU * k / 8.0 + PI / 8.0
		var bp := O + Vector2(cos(a), sin(a)) * (R_OUT + 13)
		ci.draw_circle(bp, 4.2, HD.INK, true, -1, true)
		ci.draw_circle(bp, 3.0, Color(0.75, 0.8, 0.9), true, -1, true)
	var spin := rt * 0.25
	for k in 60:
		var a := spin + TAU * k / 60.0
		var long := k % 5 == 0
		ci.draw_line(O + Vector2(cos(a), sin(a)) * (R_OUT + 1), O + Vector2(cos(a), sin(a)) * (R_OUT - (7 if long else 3)), Color(0.45, 0.95, 1.0, 0.45 if long else 0.2), 2.0, true)
	# ---- the four slices (0 top, 1 right, 2 bottom, 3 left)
	var order := [0, 1, 2, 3]
	if sel >= 0: order.erase(sel); order.append(sel)        # picked slice drawn last, on top
	for i in order:
		var id: String = c.ORDER[i]
		var owned: bool = c.usable(id)
		var is_sel: bool = i == sel
		var col: Color = c.weapon_color(id) if owned else Color(0.5, 0.55, 0.62)
		var mid: float = i * PI / 2.0 - PI / 2.0
		var dir := Vector2(cos(mid), sin(mid))
		# stagger-in on open, spring out when picked
		var appear := clampf((since_open - float(i) * 0.04) / 0.16, 0.0, 1.0)
		var sp := 0.0
		if is_sel:
			var p := clampf(1.0 - (rt - sel_rt) / 0.35, 0.0, 1.0)
			sp = 14.0 * (1.0 + 0.35 * p * cos((1.0 - p) * 13.0))
		var off := dir * (sp - (1.0 - appear) * 40.0)
		var a0 := mid - PI / 4.0 + 0.035
		var a1 := mid + PI / 4.0 - 0.035
		var r1 := R_OUT - 8.0 + (6.0 if is_sel else 0.0)
		ci.draw_colored_polygon(_slice(a0 - 0.012, a1 + 0.012, R_IN - 4, r1 + 4, off + Vector2(1.5, 5)), Color(0, 0, 0, 0.35 * appear))
		ci.draw_colored_polygon(_slice(a0 - 0.015, a1 + 0.015, R_IN - 4, r1 + 4, off), HD._fade(HD.INK, appear))
		var body := _slice(a0, a1, R_IN, r1, off)
		var cols := PackedColorArray()
		var top := HD.PANEL_TOP.lerp(col.darkened(0.35), 0.55 if is_sel else (0.22 if owned else 0.0))
		var bot := HD.PANEL_BOT.lerp(col.darkened(0.7), 0.4 if is_sel else 0.1)
		for q in body:
			var u := clampf(((q - O - off).length() - R_IN) / (r1 - R_IN), 0.0, 1.0)
			cols.append(HD._fade(bot.lerp(top, u), appear))
		ci.draw_polygon(body, cols)
		# sheen along the outer edge, light sweep across the picked slice
		ci.draw_colored_polygon(_slice(a0 + 0.02, a1 - 0.02, r1 - 22, r1 - 3, off, 14), Color(1, 1, 1, (0.14 if is_sel else 0.07) * appear))
		if is_sel:
			var sw := fposmod((rt - sel_rt) * 0.9, 1.6)
			if sw < 1.0:
				var sa := lerpf(a0, a1, sw)
				ci.draw_colored_polygon(_slice(maxf(a0, sa - 0.09), minf(a1, sa + 0.09), R_IN + 3, r1 - 3, off, 4), Color(1, 1, 1, 0.16 * sin(sw * PI)))
		var edge := HD._closed(body)
		ci.draw_polyline(edge, HD._fade(col.lightened(0.2) if is_sel else HD._fade(col, 0.55), appear), 3.5 if is_sel else 1.6, true)
		if is_sel:
			ci.draw_polyline(edge, Color(col.r, col.g, col.b, 0.25 * (0.6 + 0.4 * sin(rt * 6.0))), 9.0, true)
		# ammo arc hugging the inner edge of the outer rim
		var ar := r1 - 10.0
		var aa0 := a0 + 0.1
		var aa1 := a1 - 0.1
		ci.draw_arc(O + off, ar, aa0, aa1, 24, HD._fade(HD.INK, appear), 8, true)
		ci.draw_arc(O + off, ar, aa0, aa1, 24, HD._fade(HD.SLOT, appear), 5, true)
		if owned:
			var f := 1.0
			var fc := col
			if c.uses_ammo(id):
				f = clampf(float(c.ammo(id)) / maxf(1.0, c.max_ammo(id)), 0.0, 1.0)
				if f <= 0.25: fc = Color(1, 0.45, 0.3)
			else:
				f = 1.0 - clampf(float(c.heat) if "heat" in c else 0.0, 0.0, 1.0)
			if f > 0.01: ci.draw_arc(O + off, ar, aa0, lerpf(aa0, aa1, f), maxi(4, int(24 * f)), HD._fade(fc, appear), 5, true)
		# emblem badge
		var bc := O + off + dir * 166.0
		var bs := 32.0 if is_sel else 27.0
		HD.badge(ci, bc, bs, col, appear)
		if owned:
			HD.icon(ci, HD.weapon_icon(id), bc, bs * 0.6, col, appear)
		else:
			HD.icon(ci, "lock", bc, bs * 0.52, Color(0.72, 0.76, 0.82), appear)
		# slot key (keyboard) beside the badge, level chip under it
		var side := Vector2(-dir.y, dir.x)
		if not pad: HD.keycap(ci, bc + side * -(bs + 30) + dir * 4.0, str(i + 1), false, 0.9 * appear)
		if owned:
			var lv: int = c.level(id)
			var maxed := lv >= 5
			var lr := Rect2(bc + side * (bs + 24) - Vector2(23, 13), Vector2(46, 26))
			HD.panel(ci, lr, Color(1.0, 0.82, 0.3) if maxed else Color.WHITE, 8, 0.0, appear,
				Color(0.55, 0.4, 0.08, 0.97) if maxed else HD.PANEL_TOP, Color(0.3, 0.2, 0.04, 0.97) if maxed else HD.PANEL_BOT)
			HD.text(ci, font, lr.get_center() + Vector2(0, 7), "V%d" % lv, 18, Color(1.0, 0.82, 0.3) if maxed else Color.WHITE, 1, 4, appear)
	# ---- hub: metal bezel, dark glass, picked weapon's details
	ci.draw_circle(O + Vector2(1.5, 5), R_IN - 6, Color(0, 0, 0, 0.35), true, -1, true)
	ci.draw_circle(O, R_IN - 6, HD.INK, true, -1, true)
	var hub := PackedVector2Array(HD._circle_pts(64, R_IN - 8, O))
	ci.draw_polygon(hub, HD._metal_cols(hub, Rect2(O - Vector2.ONE * (R_IN - 8), Vector2.ONE * (R_IN - 8) * 2.0), 1.0))
	ci.draw_circle(O, R_IN - 14, HD.INK, true, -1, true)
	ci.draw_circle(O, R_IN - 16, HD.PANEL_BOT, true, -1, true)
	for k in 6:
		var f := k / 6.0
		ci.draw_circle(O - Vector2(0, (R_IN - 16) * 0.25 * f), (R_IN - 16) * (1.0 - f * 0.3), Color(HD.PANEL_TOP, 0.25), true, -1, true)
	ci.draw_arc(O, R_IN - 22, PI * 1.1, PI * 1.6, 16, Color(1, 1, 1, 0.3), 3, true)
	# pointer: an arrow on the hub rim towards the mouse / stick
	if point.length() > 10.0:
		var pd := point.normalized()
		var pc: Color = c.weapon_color(c.ORDER[sel]) if sel >= 0 and c.usable(c.ORDER[sel]) else Color(0.85, 0.9, 1.0)
		var tip := O + pd * (R_IN + 4)
		var bl := O + pd * (R_IN - 14) + Vector2(-pd.y, pd.x) * 11
		var br := O + pd * (R_IN - 14) - Vector2(-pd.y, pd.x) * 11
		ci.draw_colored_polygon(PackedVector2Array([tip + pd * 2.5, bl - pd * 2 + Vector2(-pd.y, pd.x) * 2.5, br - pd * 2 - Vector2(-pd.y, pd.x) * 2.5]), HD.INK)
		ci.draw_colored_polygon(PackedVector2Array([tip, bl, br]), pc)
	if sel >= 0:
		var id: String = c.ORDER[sel]
		var owned: bool = c.usable(id)
		var col: Color = c.weapon_color(id) if owned else Color(0.65, 0.7, 0.78)
		var nm: String = c.weapon_name(id) if owned else "LOCKED"
		var ns := 24
		while ns > 16 and font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, ns).x > 176: ns -= 1
		HD.text(ci, font, O + Vector2(0, -38), nm, ns, col.lightened(0.15), 1, 6)
		ci.draw_line(O + Vector2(-60, -28), O + Vector2(60, -28), Color(col, 0.6), 2.0, true)
		var info := ""
		if owned:
			if c.uses_ammo(id):
				var am: int = c.ammo(id)
				var mx: int = c.max_ammo(id)
				HD.text(ci, font, O + Vector2(0, 2), "%d" % am, 30, Color(1, 0.45, 0.35) if am <= 0 else Color.WHITE, 2, 6)
				HD.text(ci, font, O + Vector2(4, 2), "/ %d" % mx, 18, Color(0.7, 0.78, 0.92), 0, 5)
			else:
				HD.text(ci, font, O + Vector2(0, 2), "NO AMMO NEEDED", 16, Color(0.6, 0.95, 1.0), 1, 5)
			info = c.WEAPONS[id].blurb
		else:
			HD.text(ci, font, O + Vector2(0, 0), c.WEAPONS[id].name, 17, Color(0.85, 0.88, 0.95), 1, 5)
			info = "Sold at Gizmart."
		ci.draw_multiline_string_outline(body_font, O + Vector2(-82, 22), info, HORIZONTAL_ALIGNMENT_CENTER, 164, 13, 3, 4, HD.INK)
		ci.draw_multiline_string(body_font, O + Vector2(-82, 22), info, HORIZONTAL_ALIGNMENT_CENTER, 164, 13, 3, Color(0.85, 0.92, 1.0))
	# ---- hint under the wheel
	var hy := O.y + R_OUT + 52
	var hint := "RELEASE TO EQUIP"
	var hw := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	var kw := 36.0
	var hr2 := Rect2(O.x - (hw + kw + 40) / 2, hy - 20, hw + kw + 40, 40)
	HD.panel(ci, hr2, Color(0.45, 0.95, 1.0), 12, 0.12, 0.95)
	HD.keycap(ci, Vector2(hr2.position.x + 12 + kw / 2, hy), "LB" if pad else "Q", false)
	HD.text(ci, font, Vector2(hr2.position.x + 24 + kw, hy + 7), hint, 18, Color(0.9, 0.97, 1.0), 0, 5)
