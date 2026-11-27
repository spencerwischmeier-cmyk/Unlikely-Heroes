extends Node
## On-screen touch controls for phones and tablets (installed by main.gd like every system).
##
## Left side: a floating move stick (put a thumb down anywhere on the left and push).
## Right side: drag anywhere to look; buttons for JUMP (jetpack in the air, hold to glide), FIRE
## (drag while holding it to aim), DASH, MELEE, USE (swing hooks, talk to Gizmart), the weapon button
## (tap: next weapon, hold and slide: weapon wheel) and pause. A light aim assist pulls the view toward
## the bot nearest the crosshair while FIRE is held.
##
## Everything goes through the normal input actions, so the rest of the game doesn't know about touch.
## Shows on touch devices (see device.gd), or as soon as the screen is touched.

const Device := preload("res://scripts/device.gd")
const HD := preload("res://scripts/ui/hud_draw.gd")

const LOOK_SENS := 0.0058          # radians per screen unit dragged
const STICK_R := 118.0
const HOLD_WHEEL := 0.28           # seconds on the weapon button before the wheel opens
const ASSIST_CONE := 0.16          # radians off the crosshair that aim assist reaches
const ASSIST_RANGE := 70.0

var layer := CanvasLayer.new()
var pad := Control.new()
var enabled := false
var in_cutscene := false

# stick
var stick_id := -1
var stick_origin := Vector2.ZERO
var stick_vec := Vector2.ZERO
# look (a free drag, or the finger holding FIRE)
var look_ids := {}                  # touch index -> last position
# buttons: id -> { label, actions, pos (offset from a corner), corner, r, held (touch index or -1), t, hold }
var buttons := {}
var touch_btn := {}                 # touch index -> button id
var wheel_open := false
var last_size := Vector2.ZERO
var subs_ctl: Control
var subs_base := Vector2.ZERO

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer.layer = 40
	add_child(layer)
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.draw.connect(_draw_pad)
	layer.add_child(pad)
	_add("jump", "JUMP", ["jump"], Vector2(-122, -142), Vector2(1, 1), 74)
	_add("fire", "FIRE", ["fire"], Vector2(-300, -222), Vector2(1, 1), 82)
	_add("dash", "DASH", ["dash"], Vector2(-128, -328), Vector2(1, 1), 54)
	_add("melee", "HIT", ["melee"], Vector2(-462, -112), Vector2(1, 1), 52)
	_add("use", "USE", ["hook", "interact"], Vector2(-300, -400), Vector2(1, 1), 48)
	_add("weapon", "GUN", [], Vector2(-470, -300), Vector2(1, 1), 50)
	_add("pause", "II", ["pause"], Vector2(-52, 178), Vector2(1, 0), 32)
	_add("close", "BACK", ["dash"], Vector2(-120, -140), Vector2(1, 1), 60)
	Game.cutscene_started.connect(func(_id): in_cutscene = true; _release_all())
	Game.cutscene_finished.connect(func(_id): in_cutscene = false)
	if Device.touch(): _enable()
	else: pad.visible = false

func _add(id: String, label: String, actions: Array, pos: Vector2, corner: Vector2, r: float) -> void:
	buttons[id] = { label = label, actions = actions, pos = pos, corner = corner, r = r, held = -1, t = 0.0, hold = false }

func _enable() -> void:
	if enabled: return
	enabled = true
	Device.set_touch(true)
	pad.visible = true
	# taps also arrive as emulated mouse clicks (so menus work); keep those from firing or dashing
	for a in ["fire", "dash"]:
		if not InputMap.has_action(a): continue
		for ev in InputMap.action_get_events(a):
			if ev is InputEventMouseButton: InputMap.action_erase_event(a, ev)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_make_room_in_hud()

## the HUD's weapon panel sits where the right thumb goes: move it to the bottom middle
func _make_room_in_hud() -> void:
	var hud = Game.hud
	if hud == null: return
	for n in ["weapon", "wstrip"]:
		var c = hud.get(n) if n in hud else null
		if not (c is Control): continue
		var w: float = c.offset_right - c.offset_left
		c.anchor_left = 0.5; c.anchor_right = 0.5
		c.offset_left = -w * 0.5 + 20.0; c.offset_right = w * 0.5 + 20.0
	var subs = hud.get("subs") if "subs" in hud else null
	if subs is Control: subs_ctl = subs; subs_base = Vector2(subs.offset_top, subs.offset_bottom)

## during play, subtitles sit higher to clear the weapon panel; in cutscenes they go back to the bottom
func _place_subs() -> void:
	if subs_ctl == null or not is_instance_valid(subs_ctl): return
	var lift := 150.0 if _mode() == "play" else 0.0
	subs_ctl.offset_top = subs_base.x - lift; subs_ctl.offset_bottom = subs_base.y - lift

## which buttons show right now
func _mode() -> String:
	if in_cutscene or get_tree().paused: return "off"
	if Game.input_locked: return "shop"
	if Game.player == null: return "off"
	return "play"

func _visible_buttons() -> Array:
	match _mode():
		"play": return ["jump", "fire", "dash", "melee", "use", "weapon", "pause"]
		"shop": return ["close"]
	return []

func _btn_pos(b: Dictionary) -> Vector2:
	var s := pad.size
	var safe := 34.0   # keep clear of rounded corners and notches
	return Vector2(b.corner.x * s.x, b.corner.y * s.y) + b.pos + Vector2(-safe if b.corner.x > 0.5 else safe, 0)

# ------------------------------------------------------------------ input
func _input(e: InputEvent) -> void:
	if e is InputEventScreenTouch or e is InputEventScreenDrag:
		if not enabled: _enable()
	if not enabled: return
	# browsers can't lock the pointer on phones; the camera must only turn from our look drags
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if e is InputEventScreenTouch:
		var p: Vector2 = _to_pad(e.position)
		if e.pressed: _touch_down(e.index, p)
		else: _touch_up(e.index)
	elif e is InputEventScreenDrag:
		_touch_move(e.index, _to_pad(e.position))

func _to_pad(p: Vector2) -> Vector2:
	return pad.get_global_transform_with_canvas().affine_inverse() * p

func _touch_down(i: int, p: Vector2) -> void:
	var mode := _mode()
	if mode == "off": return
	for id in _visible_buttons():
		var b: Dictionary = buttons[id]
		if b.held == -1 and p.distance_to(_btn_pos(b)) < b.r * 1.22:
			b.held = i; b.t = 0.0; b.hold = false
			touch_btn[i] = id
			_press_button(id, true)
			if id == "fire": look_ids[i] = p
			get_viewport().set_input_as_handled()
			pad.queue_redraw()
			return
	if mode != "play": return
	var s := pad.size
	if p.x < s.x * 0.42 and p.y > s.y * 0.18 and stick_id == -1:
		stick_id = i; stick_origin = p; stick_vec = Vector2.ZERO
		get_viewport().set_input_as_handled()
	elif p.x >= s.x * 0.42:
		look_ids[i] = p
		get_viewport().set_input_as_handled()
	pad.queue_redraw()

func _touch_move(i: int, p: Vector2) -> void:
	if i == stick_id:
		var d := p - stick_origin
		# the stick follows a thumb that slides past its edge, so it never feels stuck
		if d.length() > STICK_R:
			stick_origin = p - d.normalized() * STICK_R
			d = p - stick_origin
		stick_vec = d / STICK_R
		_apply_stick()
		get_viewport().set_input_as_handled()
	if look_ids.has(i) and not wheel_open:
		var d: Vector2 = p - look_ids[i]
		look_ids[i] = p
		var cam = Game.cam
		if cam and "yaw" in cam:
			cam.yaw -= d.x * LOOK_SENS
			cam.pitch = clampf(cam.pitch - d.y * LOOK_SENS * 0.8 * (-1.0 if cam.invert_y else 1.0), -0.7, 0.55)
			cam.look_idle = 0.0
		get_viewport().set_input_as_handled()
	pad.queue_redraw()

func _touch_up(i: int) -> void:
	if i == stick_id:
		stick_id = -1; stick_vec = Vector2.ZERO; _apply_stick()
	look_ids.erase(i)
	if touch_btn.has(i):
		var id: String = touch_btn[i]
		touch_btn.erase(i)
		var b: Dictionary = buttons[id]
		b.held = -1
		if id == "weapon":
			if wheel_open: _action("weapon_wheel", false); wheel_open = false
			elif b.t < HOLD_WHEEL: _tap("weapon_next")
		else:
			_press_button(id, false)
	pad.queue_redraw()

func _press_button(id: String, on: bool) -> void:
	for a in buttons[id].actions: _action(a, on)

func _apply_stick() -> void:
	var v := stick_vec.limit_length(1.0)
	# a small dead zone, then full range
	var m := clampf((v.length() - 0.12) / 0.88, 0.0, 1.0)
	v = v.normalized() * m if m > 0.0 else Vector2.ZERO
	_axis("move_right", "move_left", v.x)
	_axis("move_back", "move_forward", v.y)

func _axis(pos_a: String, neg_a: String, v: float) -> void:
	if v > 0.0: Input.action_press(pos_a, v); Input.action_release(neg_a)
	elif v < 0.0: Input.action_press(neg_a, -v); Input.action_release(pos_a)
	else: Input.action_release(pos_a); Input.action_release(neg_a)

## press or release an action as a real event, so code listening in _input sees it too
func _action(a: String, on: bool) -> void:
	if not InputMap.has_action(a): return
	var ev := InputEventAction.new(); ev.action = a; ev.pressed = on; ev.strength = 1.0 if on else 0.0
	Input.parse_input_event(ev)

func _tap(a: String) -> void:
	_action(a, true)
	get_tree().create_timer(0.06, true, false, true).timeout.connect(func(): _action(a, false))

func _release_all() -> void:
	for i in touch_btn.keys(): _touch_up(i)
	stick_id = -1; stick_vec = Vector2.ZERO; _apply_stick()
	look_ids.clear()
	if wheel_open: _action("weapon_wheel", false); wheel_open = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and enabled: _release_all()

# ------------------------------------------------------------------ per frame
func _process(dt: float) -> void:
	if not enabled: return
	var mode := _mode()
	pad.visible = mode != "off"
	_place_subs()
	if mode != "play" and (stick_id != -1 or not look_ids.is_empty()):
		stick_id = -1; stick_vec = Vector2.ZERO; _apply_stick(); look_ids.clear()
	# buttons that vanished (a menu opened) let go of their actions
	var vis := _visible_buttons()
	for i in touch_btn.keys():
		if not vis.has(touch_btn[i]): _touch_up(i)
	var wb: Dictionary = buttons.weapon
	if wb.held != -1:
		wb.t += dt / maxf(Engine.time_scale, 0.05)
		if not wheel_open and wb.t >= HOLD_WHEEL:
			wheel_open = true; _action("weapon_wheel", true)
	if buttons.fire.held != -1 and mode == "play": _aim_assist(dt)
	if pad.size != last_size: last_size = pad.size
	pad.queue_redraw()

## pull the view gently toward the bot closest to the crosshair
func _aim_assist(dt: float) -> void:
	var cam = Game.cam
	if cam == null or not cam.has_method("aim_dir"): return
	var from: Vector3 = cam.camera.global_position
	var fwd: Vector3 = cam.aim_dir()
	var best: Node3D = null
	var best_a := ASSIST_CONE
	for b in get_tree().get_nodes_in_group("bots"):
		if not (b is Node3D) or b.is_in_group("dead") or not b.has_method("center"): continue
		var to: Vector3 = b.center() - from
		var dist := to.length()
		if dist > ASSIST_RANGE or dist < 1.0: continue
		var a := fwd.angle_to(to)
		if a < best_a: best_a = a; best = b
	if best == null: return
	var to2: Vector3 = (best.center() - from).normalized()
	var want_yaw := atan2(to2.x, to2.z)   # the rig looks along (sin yaw, cos yaw)
	var want_pitch := asin(clampf(to2.y, -1.0, 1.0))
	var k := 1.0 - exp(-6.0 * dt)
	cam.yaw += angle_difference(cam.yaw, want_yaw) * k
	cam.pitch = lerpf(cam.pitch, clampf(want_pitch, -0.7, 0.55), k * 0.6)

# ------------------------------------------------------------------ drawing
func _draw_pad() -> void:
	var mode := _mode()
	if mode == "off": return
	var font: Font = HD.head_font()
	if mode == "play":
		# the stick: faint where it will appear, solid while a thumb is on it
		var s := pad.size
		var base := stick_origin if stick_id != -1 else Vector2(250, s.y - 230)
		var a := 0.55 if stick_id != -1 else 0.22
		pad.draw_circle(base, STICK_R, Color(0.08, 0.1, 0.18, a * 0.6))
		pad.draw_arc(base, STICK_R, 0, TAU, 64, Color(1, 1, 1, a), 3.0, true)
		var knob := base + stick_vec.limit_length(1.0) * STICK_R
		pad.draw_circle(knob, 50, Color(1, 1, 1, a * 0.9))
	var on_ground: bool = Game.player != null and Game.player.is_on_floor()
	for id in _visible_buttons():
		var b: Dictionary = buttons[id]
		var c := _btn_pos(b)
		var held: bool = b.held != -1
		var col := Color(1.0, 0.78, 0.25) if id == "fire" else Color(1, 1, 1)
		pad.draw_circle(c, b.r, Color(0.08, 0.1, 0.18, 0.55 if held else 0.32))
		pad.draw_arc(c, b.r, 0, TAU, 48, Color(col, 0.95 if held else 0.6), 4.0 if held else 2.5, true)
		if held: pad.draw_circle(c, b.r * 0.82, Color(col, 0.22))
		var label: String = b.label
		if id == "jump" and not on_ground: label = "JET"
		if id == "weapon" and wheel_open: label = "PICK"
		var fs := int(clampf(b.r * 0.42, 18, 34))
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
		pad.draw_string(font, c + Vector2(-w * 0.5, fs * 0.36), label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, Color(col, 0.95 if held else 0.8))
