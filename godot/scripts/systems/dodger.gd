extends Node
## Dodger, the drone sidekick. Starts crashed on the junkyard scrap pile (level.dodger_crash_pos) and becomes
## Vesk's shoulder follower when the "dodger_launch" zone is cleared. Runs the combo meter (kills chained
## within 3 s, bonus sprockets when a chain of 3+ ends), rates great shots out of ten (air kills, long shots,
## multi-kills) and barks: taunts, falls, grinds, Vesk's kills and overheats. His eye flickers orange
## when Shard 1 is read off the relay dish.
## Debug: --combo-demo fakes a chain of kills a second after the start (for screenshots).

const DroneActor := preload("res://scripts/cutscene/drone_actor.gd")
const COMBO_TIME := 3.0
const RATE_SCORES := [3, 5, 6, 7, 8, 9, 10]   # dodger_rate_1..7

var drone: Node3D
var state := "crashed"      # crashed | launch | follow
var crash_pos := Vector3(-12.5, 2.4, 74.5)
var vel := Vector3.ZERO
var t := 0.0
var spark_t := 2.0

# combo + ratings
var combo := 0
var combo_t := 0.0
var combo_peak := 0
var pending: Array = []      # kills waiting to be rated together (multi-kills)
var pending_t := 0.0
var rate_cd := 0.0
var bark_cd := 0.0
var taunt_t := 25.0
var grind_cd := 0.0
var was_riding := false
var was_hot := false
var orange_t := 0.0
var demo := false

# UI
var layer: CanvasLayer
var meter: Control
var meter_a := 0.0
var pop_label: Label
var pop_sub: Label
var pop_t := 0.0
var bonus_label: Label
var bonus_t := 0.0
var font: Font

func _ready() -> void:
	var v = Game.level.get("dodger_crash_pos") if Game.level else null
	if v is Vector3: crash_pos = v
	drone = DroneActor.new(); drone.name = "DodgerDrone"; drone.scale = Vector3.ONE * 0.75
	Game.main.add_child.call_deferred(drone)
	var args := OS.get_cmdline_user_args()
	var at_other := false
	for a in args: if a.begins_with("--at=") and a != "--at=start": at_other = true
	if args.has("--no-bots") or at_other or Game.is_complete("dodger_launch"):
		state = "follow"
	_place_start.call_deferred()
	Game.zone_cleared.connect(_on_zone_cleared)
	Game.zone_entered.connect(_on_zone_entered)
	Game.bot_killed.connect(_on_kill)
	Game.player_fell.connect(func(): if state == "follow": _bark("dodger", "fall", 0.8); _emote("surprised", 1.4))
	Game.player_hurt.connect(func(h):
		if state != "follow": return
		_emote("surprised" if h > 2 else "sad", 1.2)
		if h <= 2: Snd.at("chars_dodger_worried", drone.global_position, -8, 0.05, 4.0)
		if h > 2: _bark.call_deferred("dodger", "hurt", 0.2))
	Game.item_unlocked.connect(func(id): if id == "shard_1": orange_t = 7.0; _emote("angry", 6.0))
	Game.cutscene_started.connect(func(_id): if drone: drone.visible = false)
	Game.cutscene_finished.connect(func(_id): if drone: drone.visible = true)
	_build_ui()
	if args.has("--combo-demo"): _combo_demo()

func _place_start() -> void:
	if state == "crashed":
		drone.global_position = crash_pos + Vector3(0, 0.25, 0)
		drone.tilt = Vector3(0.9, 0.4, 1.2); drone.hover = 0.0; drone.dim = 0.6
	elif Game.player:
		drone.global_position = _target()

func _on_zone_entered(id: String) -> void:
	if id == "junk_crash" and state == "crashed":
		# perks up when Vesk climbs over
		drone.dim = 0.2
		_emote("surprised", 1.2)
		var tw := drone.create_tween()
		tw.tween_property(drone, "tilt", Vector3(0.5, 0.2, 0.6), 0.25).set_trans(Tween.TRANS_BACK)
		tw.tween_property(drone, "tilt", Vector3(0.9, 0.4, 1.2), 0.4)

func _on_zone_cleared(id: String) -> void:
	if id == "dodger_launch" and state == "crashed": _launch()

func _launch() -> void:
	state = "launch"
	var p := drone.global_position
	_emote("happy", 2.5)
	Snd.at("chars_dodger_happy", p, -4, 0.0)
	FX.sparks(p + Vector3(0, 0.3, 0), Color(1, 0.75, 0.3), 16, 5.0)
	FX.ring(p, Color(0.4, 0.9, 1.0), 1.2)
	Snd.at("double_jump", p, -2)
	var tw := drone.create_tween().set_parallel()
	tw.tween_property(drone, "tilt", Vector3.ZERO, 0.6).set_trans(Tween.TRANS_BACK)
	tw.tween_property(drone, "global_position", p + Vector3(0, 3.0, 0), 0.9).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(drone, "hover", 1.0, 0.8)
	tw.tween_property(drone, "dim", 0.0, 0.4)
	tw.tween_property(drone, "rotation:y", drone.rotation.y + TAU * 2.0, 1.0).set_trans(Tween.TRANS_QUAD)
	tw.chain().tween_callback(func(): state = "follow"; vel = Vector3.ZERO)

func _target() -> Vector3:
	var pl := Game.player
	var yaw: float = pl.get("face_yaw") if pl.get("face_yaw") != null else 0.0
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	var right := Vector3(-cos(yaw), 0, sin(yaw))
	return pl.global_position + Vector3(0, 1.9 + sin(t * 1.1) * 0.08, 0) + right * -0.85 - fwd * 0.2

func _process(dt: float) -> void:
	t += dt
	if Game.player == null or drone == null or not drone.is_inside_tree(): return
	bark_cd -= dt; rate_cd -= dt; grind_cd -= dt
	match state:
		"crashed":
			spark_t -= dt
			if spark_t <= 0.0:
				spark_t = randf_range(2.0, 4.5)
				FX.sparks(drone.global_position + Vector3(0, 0.2, 0), Color(1, 0.75, 0.3), 5, 2.5)
		"follow":
			_follow(dt)
			_poll_barks(dt)
	# orange flicker after reading the shard
	if orange_t > 0.0:
		orange_t -= dt
		drone.orange = clampf(orange_t / 1.5, 0.0, 1.0)
	elif drone.orange > 0.0 and not Game.input_locked:
		drone.orange = 0.0
	_tick_combo(dt)
	_tick_ui(dt)

func _follow(dt: float) -> void:
	var goal := _target()
	var p := drone.global_position
	if p.distance_to(goal) > 16.0:
		FX.puff(goal, Color(0.6, 0.9, 1.0)); drone.global_position = goal; vel = Vector3.ZERO; return
	# critically damped spring toward the shoulder spot
	var k := 38.0
	var acc := (goal - p) * k - vel * 2.0 * sqrt(k)
	vel += acc * dt
	drone.global_position = p + vel * dt
	# look at the nearest bot in a fight, else the way Vesk faces
	var look_yaw: float = Game.player.get("face_yaw") if Game.player.get("face_yaw") != null else drone.rotation.y
	var b := _nearest_bot(22.0)
	if b:
		var d: Vector3 = b.global_position - drone.global_position
		look_yaw = atan2(d.x, d.z)
	drone.rotation.y = lerp_angle(drone.rotation.y, look_yaw, 1.0 - exp(-6.0 * dt))
	var side := vel.dot(Vector3(cos(drone.rotation.y), 0, -sin(drone.rotation.y)))
	var ahead := vel.dot(Vector3(sin(drone.rotation.y), 0, cos(drone.rotation.y)))
	drone.tilt = drone.tilt.lerp(Vector3(clampf(ahead * 0.06, -0.4, 0.4), 0, clampf(side * 0.08, -0.5, 0.5)), 1.0 - exp(-8.0 * dt))

func _nearest_bot(r: float) -> Node3D:
	var best: Node3D = null
	var bd := r
	for b in get_tree().get_nodes_in_group("bots"):
		if not is_instance_valid(b) or b.get("dead"): continue
		var d: float = (b as Node3D).global_position.distance_to(Game.player.global_position)
		if d < bd: bd = d; best = b
	return best

func _poll_barks(dt: float) -> void:
	if Game.input_locked: return
	var pl := Game.player
	var riding: bool = pl.get("riding") == true
	if riding and not was_riding and grind_cd <= 0.0:
		grind_cd = 25.0; _bark("dodger", "grind", 0.5)
	was_riding = riding
	var hot: bool = Game.combat != null and Game.combat.get("overheated") == true
	if hot and not was_hot: _bark("vesk", "overheat", 0.6); _emote("smug", 1.5)
	was_hot = hot
	taunt_t -= dt
	if taunt_t <= 0.0:
		taunt_t = randf_range(20.0, 35.0)
		if _nearest_bot(25.0): _bark("dodger", "taunt", 0.6); _emote("smug", 2.0)

## Dodger's eye pulls a face (scripts/cutscene/drone_actor.gd emote()).
func _emote(m: String, secs: float) -> void:
	if drone and drone.has_method("emote"): drone.emote(m, secs)

func _bark(who: String, kind: String, chance: float) -> void:
	if bark_cd > 0.0 and who == "dodger": return
	if Snd.voice_player and Snd.voice_player.playing: return
	if randf() > chance: return
	Snd.bark(who, kind)
	if who == "dodger": bark_cd = 4.0

# ---------------------------------------------------------------- combo meter and shot ratings
func _on_kill(_bot: Node, pos: Vector3, _kind: String) -> void:
	if state != "follow" or Game.player == null: return
	combo = combo + 1 if combo_t > 0.0 else 1
	combo_t = COMBO_TIME
	combo_peak = maxi(combo_peak, combo)
	if combo >= 2: Snd.play("combo_up", -8, 0.0)
	_emote("happy", 0.9 + minf(combo, 6) * 0.2)
	if combo in [3, 6, 10]: Snd.at("chars_dodger_happy", drone.global_position, -8, 0.05, 1.0)
	meter.set_meta("pop", 1.0)
	if combo in [3, 6, 10]: _bark("dodger", "combo", 0.8)
	var pl := Game.player
	var air: bool = not pl.is_on_floor() and pl.get("riding") != true
	pending.append({ air = air, dist = pl.global_position.distance_to(pos) })
	pending_t = 0.35

func _tick_combo(dt: float) -> void:
	if pending_t > 0.0:
		pending_t -= dt
		if pending_t <= 0.0: _rate(pending); pending = []
	if demo: combo_t = maxf(combo_t, 2.1); pop_t = maxf(pop_t, 1.0)
	if combo_t > 0.0:
		combo_t -= dt
		if combo_t <= 0.0: _combo_end()

func _combo_end() -> void:
	if combo >= 3:
		var bonus := combo * 5
		Game.add_nuts(bonus)
		bonus_label.text = "CHAIN OF %d   +%d SPROCKETS" % [combo, bonus]
		bonus_t = 2.5
		_bark("dodger", "comboEnd", 0.7)
	combo = 0

func _rate(kills: Array) -> void:
	if kills.is_empty(): return
	var n := kills.size()
	var air := false
	var dist := 0.0
	for k in kills:
		air = air or k.air
		dist = maxf(dist, k.dist)
	var far := dist > 18.0
	if not (air or far or n >= 2): return
	var score := 4.0
	if air: score += 2.0
	if far: score += 1.0 + minf(2.0, (dist - 18.0) / 8.0)
	if n >= 2: score += 1.0 + n
	if combo >= 5: score += 1.0
	var s := clampi(int(round(score)), 3, 10)
	var tags := []
	if n >= 2: tags.append("%s KILL" % ["DOUBLE", "TRIPLE", "QUAD"][mini(n - 2, 2)] if n <= 4 else "MULTI KILL")
	if air: tags.append("AIR SHOT")
	if far: tags.append("LONG SHOT  %d m" % int(dist))
	pop_label.text = "%d/10" % s
	pop_sub.text = "  ·  ".join(tags)
	pop_t = 2.2
	pop_label.pivot_offset = pop_label.size * 0.5
	pop_label.scale = Vector2(1.6, 1.6)
	# Dodger's verdict: a rating line for big scores, otherwise a bark for the kind of shot
	if s >= 7 and rate_cd <= 0.0 and not (Snd.voice_player and Snd.voice_player.playing):
		var idx := 0
		for i in RATE_SCORES.size(): if RATE_SCORES[i] <= s: idx = i
		Snd.voice("dodger_rate_%d" % (idx + 1)); rate_cd = 10.0; bark_cd = 4.0
	elif n >= 2: _bark("dodger", "multi", 0.8)
	elif air: _bark("dodger", "air", 0.6)
	elif far: _bark("dodger", "far", 0.6)
	elif randf() < 0.15: _bark("vesk", "kill", 1.0)

# ---------------------------------------------------------------- UI
func _build_ui() -> void:
	font = preload("res://scripts/ui/hud_draw.gd").head_font()
	layer = CanvasLayer.new(); layer.layer = 5; add_child(layer)
	meter = Control.new(); meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meter.draw.connect(_draw_meter); meter.set_meta("pop", 0.0)
	layer.add_child(meter)
	_anchor(meter, Vector2(1, 0.5), Rect2(-190, -150, 160, 160))
	pop_label = _label(54, Color(1, 0.85, 0.3)); pop_sub = _label(20, Color(0.6, 0.95, 1))
	for l in [pop_label, pop_sub]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; l.modulate.a = 0.0; layer.add_child(l)
	_anchor(pop_label, Vector2(1, 0.5), Rect2(-270, 20, 320, 62))
	_anchor(pop_sub, Vector2(1, 0.5), Rect2(-330, 82, 440, 30))
	bonus_label = _label(22, Color(1, 0.85, 0.35))
	bonus_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; bonus_label.modulate.a = 0.0
	layer.add_child(bonus_label)
	_anchor(bonus_label, Vector2(1, 0.5), Rect2(-470, 116, 440, 30))

## Pin a control to a screen anchor point (0..1 on each axis) with a rect offset from it.
static func _anchor(c: Control, a: Vector2, r: Rect2) -> void:
	c.anchor_left = a.x; c.anchor_right = a.x; c.anchor_top = a.y; c.anchor_bottom = a.y
	c.offset_left = r.position.x; c.offset_top = r.position.y
	c.offset_right = r.position.x + r.size.x; c.offset_bottom = r.position.y + r.size.y

func _label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0.05, 0.1, 0.9))
	l.add_theme_constant_override("outline_size", 10)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _tick_ui(dt: float) -> void:
	var show := combo >= 2 and not Game.input_locked
	meter_a = move_toward(meter_a, 1.0 if show else 0.0, dt * (6.0 if show else 2.0))
	meter.modulate.a = meter_a
	meter.set_meta("pop", maxf(0.0, float(meter.get_meta("pop")) - dt * 5.0))
	meter.queue_redraw()
	pop_t -= dt
	var pa := clampf(pop_t / 0.5, 0.0, 1.0) if not Game.input_locked else 0.0
	pop_label.modulate.a = pa; pop_sub.modulate.a = pa
	pop_label.scale = pop_label.scale.lerp(Vector2.ONE, 1.0 - exp(-14.0 * dt))
	bonus_t -= dt
	bonus_label.modulate.a = clampf(bonus_t / 0.5, 0.0, 1.0)

func _draw_meter() -> void:
	var c := meter.size * 0.5
	var pop := float(meter.get_meta("pop"))
	var r := 58.0 + pop * 8.0
	var frac := clampf(combo_t / COMBO_TIME, 0.0, 1.0)
	var hot := Color(1, 0.55, 0.2).lerp(Color(1, 0.25, 0.3), clampf((combo - 2) / 8.0, 0, 1))
	meter.draw_circle(c, r + 6, Color(0, 0.05, 0.1, 0.55))
	meter.draw_arc(c, r, 0, TAU, 48, Color(1, 1, 1, 0.15), 8)
	meter.draw_arc(c, r, -PI / 2, -PI / 2 + TAU * frac, 48, hot, 8, true)
	# little Dodger eye in the middle top
	meter.draw_circle(c + Vector2(0, -r + 0.5), 7, Color(0.35, 0.95, 1))
	var txt := "x%d" % combo
	var fs := 46 + int(pop * 10)
	var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	meter.draw_string_outline(font, c + Vector2(-w / 2, 14), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 8, Color(0, 0.05, 0.1, 0.9))
	meter.draw_string(font, c + Vector2(-w / 2, 14), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.92, 0.6))
	var lw := font.get_string_size("COMBO", HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	meter.draw_string(font, c + Vector2(-lw / 2, 38), "COMBO", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.6, 0.95, 1))

# ---------------------------------------------------------------- debug
func _combo_demo() -> void:
	state = "follow"
	await get_tree().create_timer(1.0).timeout
	var p: Vector3 = Game.player.global_position
	for i in 3:
		_on_kill(null, p + Vector3(3, 0, -4), "roller")
		await get_tree().create_timer(0.6).timeout
	_on_kill(null, p + Vector3(6, 0, -26), "hornet")
	_on_kill(null, p + Vector3(-5, 0, -27), "roller")
	demo = true
