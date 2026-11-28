extends CanvasLayer
## Hit chain: landing hits in quick succession (shots, wrench, stomps, slams) builds a chain shown in a
## small chip in the top-left HUD cluster, beside the jet/dash strip. The chain breaks after CHAIN_T without a hit, or when Vesk is hurt.
## Every 10 links pays out bonus sprockets, so fluid, aggressive play is rewarded without any enemy
## health bars. Hits landing on the same frame (a scatter blast) count once.

const HD := preload("res://scripts/ui/hud_draw.gd")
const CHAIN_T := 2.6
const MIN_SHOW := 3
const COLORS := [Color(1.0, 0.82, 0.3), Color(1.0, 0.6, 0.25), Color(1.0, 0.4, 0.5), Color(0.6, 0.7, 1.0)]

var chain := 0
var best := 0
var left := 0.0          # seconds until the chain breaks
var pop := 0.0
var fade := 0.0          # after a break: the last count fades out
var shown := 0
var bonus_t := 0.0
var bonus := 0
var last_frame := -1
var head: Font
var body: Font
var chip: Control

func _ready() -> void:
	layer = 6
	process_mode = Node.PROCESS_MODE_ALWAYS   # so the chip can hide while the game is paused
	head = HD.head_font(); body = HD.body_font()
	chip = Control.new(); chip.set_anchors_preset(Control.PRESET_FULL_RECT)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.draw.connect(_draw_chip)
	add_child(chip)
	Game.bot_hit.connect(_on_hit)
	Game.player_hurt.connect(func(_h): _break())
	Game.player_respawned.connect(func(_p): _break())

func _on_hit(_bot: Node, _amount: float) -> void:
	var f := Engine.get_physics_frames()
	if f == last_frame: return
	last_frame = f
	chain += 1; left = CHAIN_T; pop = 1.0; fade = 0.0; shown = chain
	best = maxi(best, chain)
	if chain % 10 == 0:
		bonus = mini(10 + chain, 60)
		Game.add_nuts(bonus); bonus_t = 1.6
		Snd.play("nut_pickup", -2, 0.0, 0.0, 1.0 + minf(chain / 100.0, 0.4))
		if Game.player: FX.ring(Game.player.global_position + Vector3(0, 0.1, 0), COLORS[mini(chain / 10 - 1, 3)], 0.6)

func _break() -> void:
	if chain >= MIN_SHOW: fade = 0.6
	if chain > 0 and OS.get_cmdline_user_args().has("--chain-log"): print("[chain] broke at ", chain, " (best ", best, ")")
	chain = 0; left = 0.0

func _process(dt: float) -> void:
	if get_tree().paused or Game.get("input_locked"):
		chip.queue_redraw(); return
	if chain > 0:
		left -= dt
		if left <= 0.0: _break()
	pop = maxf(0.0, pop - dt * 5.0)
	fade = maxf(0.0, fade - dt)
	bonus_t = maxf(0.0, bonus_t - dt)
	chip.queue_redraw()

func _draw_chip() -> void:
	if get_tree().paused or Game.get("input_locked"): return
	var on := chain >= MIN_SHOW
	if not on and fade <= 0.0: return
	var a := 1.0 if on else fade / 0.6
	var tier := mini(shown / 10, 3)
	var col: Color = COLORS[tier]
	var s := 1.0 + pop * 0.25
	# top left, tucked beside the jet/dash strip of the vitals cluster (kept clear of the crosshair)
	var r := Rect2(462, 96 - 22 * (s - 1.0), 128 * s, 44 * s)
	HD.panel(chip, r, col, 12, 0.12, a * 0.95)
	HD.text(chip, head, Vector2(r.position.x + 14, r.position.y + 33 * s), "x%d" % shown, int(28 * s), col.lerp(Color.WHITE, 0.35), 0, 6, a)
	HD.text(chip, body, Vector2(r.end.x - 12, r.position.y + 28 * s), "CHAIN", int(14 * s), Color(0.9, 0.92, 1.0), 2, 4, a)
	if on:
		# time left before the chain breaks
		var w := (r.size.x - 24) * clampf(left / CHAIN_T, 0.0, 1.0)
		chip.draw_rect(Rect2(r.position.x + 12, r.end.y - 9, r.size.x - 24, 5), Color(0, 0, 0, 0.35 * a))
		chip.draw_rect(Rect2(r.position.x + 12, r.end.y - 9, w, 5), Color(col, 0.95 * a))
	if bonus_t > 0.0:
		var ba := clampf(bonus_t / 0.4, 0.0, 1.0)
		var y := r.end.y + 24 - (1.6 - bonus_t) * 14.0
		HD.text(chip, head, Vector2(r.position.x + 14, y), "+%d BONUS" % bonus, 20, Color(1.0, 0.9, 0.4), 0, 5, ba)
