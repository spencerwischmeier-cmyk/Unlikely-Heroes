extends Node
## Runs a level's story from data. The level script defines `zones` (in play order); this script
## walks through them: entering a zone starts its fight (waves of bots), clearing it opens the way
## on (unlocks rails), plays Dodger/Vesk lines and sets the next objective. Special zone kinds:
##   "relay"  a shootable relay target must be destroyed
##   "boss"   the Crane Bot fight; beating it completes the level
##
## Zone dictionary keys (all optional except id/rect):
##   id, name, rect (Rect2 on XZ), y (floor height, default 0), objective (shown while heading there),
##   enter_lines / clear_lines (voice ids), waves (Array of {roller:int, hornet:int}),
##   unlock_rails (Array of rail indexes), relay_pos (Vector3), boss_pos (Vector3)

const CraneBot := preload("res://scripts/cranebot.gd")
const Relay := preload("res://scripts/relay.gd")

var zones: Array = []
var index := -1          # zone currently being fought / headed to
var active := false      # a fight is running in zones[index]
var wave := 0
var alive: Array = []
var wave_delay := 0.0
var boss: Node3D
var relay: Node3D
var finished := false

func start() -> void:
	zones = Game.level.zones
	Game.cutscene_started.emit("intro")
	if Game.main.has_method("has_cutscenes") and Game.main.has_cutscenes():
		await Game.cutscene_finished
	_advance()

func _advance() -> void:
	index += 1; active = false; wave = 0
	if index >= zones.size(): return
	var z: Dictionary = zones[index]
	Game.objective_set.emit(z.id, z.get("objective", "Explore"))

func _inside(z: Dictionary, p: Vector3) -> bool:
	var r: Rect2 = z.rect
	return r.has_point(Vector2(p.x, p.z)) and absf(p.y - z.get("y", 0.0)) < 6.0

func _physics_process(dt: float) -> void:
	if finished or index < 0 or index >= zones.size() or Game.player == null: return
	var z: Dictionary = zones[index]
	if not active:
		if _inside(z, Game.player.global_position): _begin(z)
		return
	# fight in progress
	alive = alive.filter(func(b): return is_instance_valid(b) and not b.dead)
	if z.get("kind", "") == "relay" or z.get("kind", "") == "boss": return
	if alive.is_empty():
		wave_delay -= dt
		if wave_delay > 0.0: return
		var waves: Array = z.get("waves", [])
		if wave < waves.size():
			_spawn_wave(z, waves[wave]); wave += 1; wave_delay = 1.2
		else:
			_clear(z)

func _begin(z: Dictionary) -> void:
	active = true; wave_delay = 0.6
	Game.zone_entered.emit(z.id)
	for l in z.get("enter_lines", []): Game.say(l)
	if z.has("name"): Game.hud.show_banner(z.name, z.get("objective", ""))
	match z.get("kind", ""):
		"relay":
			relay = Relay.new(); Game.main.add_child(relay); relay.global_position = z.relay_pos
			relay.destroyed.connect(func(): _clear(z))
			Game.boss_started.emit("SIGNAL RELAY")
		"boss":
			boss = CraneBot.new(); boss.combat = Game.combat; boss.player = Game.player
			boss.spawn_roller = func(p: Vector3): alive.append(Game.main.spawn_bot("roller", p, z.rect))
			Game.main.add_child(boss)
			boss.spawn(z.boss_pos, z.rect)
			boss.half.connect(func(): Game.say("boss_half", true))
			boss.dead_at.connect(func(p: Vector3): _boss_down(z, p))
			Game.boss_started.emit("CRANE BOT")
			Snd.music("boss", 1.0)

func _spawn_wave(z: Dictionary, w: Dictionary) -> void:
	var r: Rect2 = z.rect
	var y: float = z.get("y", 0.0)
	var n := 0
	for kind in ["roller", "hornet"]:
		for i in int(w.get(kind, 0)):
			var a := TAU * float(n) / 5.0 + randf() * 0.6
			var c := r.get_center() + Vector2(cos(a), sin(a)) * minf(r.size.x, r.size.y) * 0.3
			alive.append(Game.main.spawn_bot(kind, Vector3(c.x, y, c.y), r)); n += 1
	if wave == 0 and randf() < 0.6: Snd.bark("dodger", "spawn")

func _clear(z: Dictionary) -> void:
	if not active: return
	active = false
	Game.complete(z.id); Game.zone_cleared.emit(z.id)
	for i in z.get("unlock_rails", []): Game.level.set_rail_locked(i, false); Snd.play("rail_unlock", -2)
	for l in z.get("clear_lines", []): Game.say(l)
	if z.get("kind", "") == "relay": Game.boss_defeated.emit("SIGNAL RELAY")
	Game.hud.show_banner("AREA CLEAR", z.get("name", ""), Color(0.5, 1, 0.6))
	Game.save()
	_advance()

func _boss_down(z: Dictionary, p: Vector3) -> void:
	Game.boss_defeated.emit("CRANE BOT")
	Game.combat.drop_nuts(p, 30); Game.combat.drop_cell(p)
	for b in alive: if is_instance_valid(b) and not b.dead: b.die(true)
	Snd.music("skyharbor", 2.0)
	Game.hud.show_banner("CRANE BOT SCRAPPED", "", Color(1, 0.85, 0.3))
	active = false; finished = true
	Game.complete(z.id); Game.zone_cleared.emit(z.id)
	await get_tree().create_timer(4.0).timeout
	Game.level_complete.emit(Game.data.level)
	Game.cutscene_started.emit("outro")
