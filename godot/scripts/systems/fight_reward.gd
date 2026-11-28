extends CanvasLayer
## The reward loop after a fight.
##   Style bonus   flashy kills pay extra sprockets on the spot (a gold "STYLE" word and a nut burst):
##                 a Plated Roller's shell cracked by a wrench/stomp/slam, a kill within 2 s of a
##                 close-call dodge, a Return to Sender kill, and the final blow of a fight.
##   Fight clear   when a fight zone is cleared, a "FIGHT CLEAR" stamp slaps onto the lower screen with
##                 the fight's best hit chain, the sprockets it earned and the style count. It is only
##                 a picture: it never blocks input or movement.
## `--no-fight-reward` turns both off. `--reward-log` prints each bonus and the stamp figures.

const HD := preload("res://scripts/ui/hud_draw.gd")
const STAMP_T := 3.4
const BONUS := {"plated_smash": 3, "close_call_kill": 3, "sender_kill": 2, "final_blow": 4}   # extra nuts (x10 sprockets)
const WORDS := {"plated_smash": "SHELL SMASH!", "close_call_kill": "CLOSE CALL KILL!", "sender_kill": "RETURN TO SENDER!", "final_blow": "FINISHER!"}

var off := OS.get_cmdline_user_args().has("--no-fight-reward")
var log_on := OS.get_cmdline_user_args().has("--reward-log")
var in_fight := false
var fight_best := 0
var fight_nuts := 0
var fight_style := 0
var last_total := -1
var count_t := 0.0          # sprockets still count toward the fight for a moment after the clear
var close_t := -10.0
var stamp_t := 0.0
var stamp := {}
var head: Font
var body: Font
var card: Control

func _ready() -> void:
	if off: return
	layer = 6
	head = HD.head_font(); body = HD.body_font()
	card = Control.new(); card.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.draw.connect(_draw_stamp)
	add_child(card)
	Game.zone_entered.connect(_on_zone_entered)
	Game.zone_cleared.connect(_on_zone_cleared)
	Game.nuts_changed.connect(_on_nuts)
	Game.close_call.connect(func(): close_t = _now())
	Game.bot_killed.connect(_on_kill)
	Game.combat_event.connect(_on_event)

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _fight_zone(id: String) -> bool:
	var s: Node = Game.story
	if s == null: return false
	for z in s.get("zones"):
		if z.get("id", "") == id: return z.get("kind", "") == ""
	return false

func _on_zone_entered(id: String) -> void:
	if not _fight_zone(id): return
	in_fight = true; fight_best = 0; fight_nuts = 0; fight_style = 0; count_t = 0.0

func _on_zone_cleared(id: String) -> void:
	if not in_fight or not _fight_zone(id): return
	in_fight = false; count_t = 2.6     # the last sprockets still flying in count too
	stamp = { best = fight_best, nuts = fight_nuts, style = fight_style }
	get_tree().create_timer(1.3).timeout.connect(_show_stamp)

func _on_nuts(total: int) -> void:
	if last_total >= 0 and total > last_total:
		if in_fight: fight_nuts += total - last_total
		elif count_t > 0.0 and not stamp.is_empty(): stamp.nuts = int(stamp.nuts) + total - last_total
	last_total = total

func _on_kill(bot: Node, pos: Vector3, _kind: String) -> void:
	if bot and bot.get_meta("returned_to_sender", false): _bonus("sender_kill", pos)
	elif _now() - close_t < 2.0: _bonus("close_call_kill", pos); close_t = -10.0

func _on_event(kind: String, at: Vector3) -> void:
	if BONUS.has(kind): _bonus(kind, at)

func _bonus(kind: String, at: Vector3) -> void:
	var c: Node = Game.combat
	if c == null: return
	var n: int = BONUS[kind]
	if in_fight: fight_style += 1
	elif count_t > 0.0 and not stamp.is_empty(): stamp.style = int(stamp.style) + 1   # the final blow lands just after the clear
	c.drop_nuts(at + Vector3(0, 0.6, 0), n)
	c.float_text(at + Vector3(0, 1.6, 0), "%s +%d" % [WORDS[kind], n * 10], Color(1, 0.85, 0.3), 46)
	FX.sparks(at + Vector3(0, 0.8, 0), Color(1, 0.85, 0.35), 14, 5.0)
	Snd.play("coin_burst" if Snd.has_sound("coin_burst") else "nut_pickup", -6, 0.05, 0.05)
	if log_on: print("[reward] ", kind, " +", n * 10)

func _show_stamp() -> void:
	if stamp.is_empty(): return
	stamp_t = STAMP_T
	Snd.play("cutscenes_poster_slam" if Snd.has_sound("cutscenes_poster_slam") else "land_heavy", -8, 0.03, 0.0)
	if log_on: print("[reward] fight clear: best chain x%d, +%d sprockets so far, style %d" % [stamp.best, stamp.nuts, stamp.style])

func _process(dt: float) -> void:
	if off: return
	if in_fight:
		var hc: Node = Game.main.get_node_or_null("HitChain") if Game.main else null
		if hc: fight_best = maxi(fight_best, int(hc.get("chain")))
	count_t = maxf(0.0, count_t - dt)
	if stamp_t > 0.0:
		stamp_t -= dt
		card.queue_redraw()
	elif card.visible:
		card.queue_redraw()

func _draw_stamp() -> void:
	if stamp_t <= 0.0 or stamp.is_empty() or get_tree().paused: return
	var age := STAMP_T - stamp_t
	var a := clampf(stamp_t / 0.5, 0.0, 1.0)
	# slams in big and tilted, settles with a little bounce
	var k := clampf(age / 0.22, 0.0, 1.0)
	var s := lerpf(1.7, 1.0, k * k) + (sin(clampf((age - 0.22) / 0.3, 0.0, 1.0) * PI) * 0.06 if age > 0.22 else 0.0)
	var vp := card.get_viewport_rect().size
	var c := Vector2(vp.x * 0.5, vp.y * 0.74)
	card.draw_set_transform(c, -0.05, Vector2(s, s))
	var w := 420.0; var h := 96.0
	var r := Rect2(-w * 0.5, -h * 0.5, w, h)
	var gold := Color(1.0, 0.82, 0.3)
	HD.panel(card, r, gold, 14, 0.1, a * 0.95)
	HD.text(card, head, Vector2(0, -6), "FIGHT CLEAR", 38, gold.lerp(Color.WHITE, 0.3), 1, 7, a)
	var line := "BEST CHAIN x%d    +%d SPROCKETS" % [int(stamp.best), int(stamp.nuts)]
	if int(stamp.style) > 0: line += "    STYLE x%d" % int(stamp.style)
	HD.text(card, body, Vector2(0, 30), line, 17, Color(0.92, 0.94, 1.0), 1, 4, a)
	card.draw_set_transform(Vector2.ZERO)
