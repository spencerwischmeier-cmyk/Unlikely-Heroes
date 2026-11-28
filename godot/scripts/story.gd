extends Node
## Runs a level's story from data. The level script defines `zones` (in play order); this script
## walks through them: entering a zone starts it, finishing it applies its effects (unlock rails,
## open gates, power movers), plays Dodger/Vesk lines and sets the next objective.
##
## Zone kinds (key "kind"):
##   ""         (default) a fight: waves of bots; cleared when every wave is down
##   "reach"    cleared as soon as the player gets inside the zone
##   "activate" hit every switch in `switches` (wrench or bolt); optional `guards` spawn at the start
##   "relay"    a shootable relay target must be destroyed
##   "boss"     the Crane Bot fight; beating it completes the level
##
## Zone dictionary keys (all optional except id/rect):
##   id, name, rect (Rect2 on XZ), y (floor height, default 0), objective (shown while heading there),
##   enter_lines / clear_lines (voice ids), waves (Array of {roller:int, plated:int, hornet:int, crew:int}),
##   unlock_rails (Array of rail indexes), open_gates (Array of gate ids, calls level.open_gate),
##   power (Array of mover ids, calls level.power), grants (Array of item ids, Game.unlock),
##   relay_pos (Vector3), boss_pos (Vector3),
##   switches (Array of {pos: Vector3, yaw: float, label: String}) for "activate",
##   guards (Array of {rect: Rect2, y: float, roller: int, hornet: int}) bots spawned when an
##     "activate" zone starts, progress_text (objective text while switching, "%d/%d" is filled in),
##   skippable (bool) this zone may be skipped if the player reaches a later `skip_to` zone first,
##   skip_to (bool) entering this zone early skips the skippable zones before it,
##   banner (String) clear banner, default "AREA CLEAR" ("" for none; reach zones default to none),
##   y_range (float) vertical tolerance for being inside (default 6).
## The level may define on_switch(zone_id, index, done, total) and on_zone_cleared(zone_id).
##
## Cutscenes inside the level (systems/cutscenes.gd): CUT_AFTER plays one when a zone is cleared
## (instead of its clear_lines), and the "boss" zone opens with the "crane_intro" cutscene, which
## calls drop_boss() at its dramatic moment (story drops it itself if the cutscene was skipped).

const CraneBot := preload("res://scripts/cranebot.gd")
const Relay := preload("res://scripts/relay.gd")
const Switch := preload("res://scripts/level/switch_target.gd")

var zones: Array = []
var index := -1          # zone currently being fought / headed to
var active := false      # a fight is running in zones[index]
var wave := 0
var alive: Array = []
var wave_delay := 0.0
var wave_age := 0.0
var wave_size := 0
var no_overlap := OS.get_cmdline_user_args().has("--no-wave-overlap")
var no_pacing := OS.get_cmdline_user_args().has("--no-wave-pacing")
var boss: Node3D
var relay: Node3D
var switches: Array = []
var switched := 0
var finished := false
var debug_auto := false  # --story-auto: throws switches / clears fights by itself (flow test)
var debug_t := 0.0
var boss_pos := Vector3.ZERO
var boss_dropped := false
var boss_zone: Dictionary = {}

const CUT_AFTER := {"mast": "broadcast"}

func _cuts_on() -> bool:
	return Game.main.has_method("has_cutscenes") and Game.main.has_cutscenes() and not OS.get_cmdline_user_args().has("--no-cutscenes")

## Play a cutscene and wait for it to finish.
func play_cutscene(id: String) -> void:
	if not _cuts_on(): return
	var cs: Node = Game.main.get_node_or_null("Cutscenes")
	while cs and cs.get("playing") != "":
		await Game.cutscene_finished
	Game.cutscene_started.emit(id)
	while true:
		var done: String = await Game.cutscene_finished
		if done == id: break

func start() -> void:
	zones = Game.level.zones
	debug_auto = OS.get_cmdline_user_args().has("--story-auto")
	Game.cutscene_started.emit("intro")
	if Game.main.has_method("has_cutscenes") and Game.main.has_cutscenes():
		await Game.cutscene_finished
	_resume()
	_advance()

## Continue: zones already finished in the save are passed over silently (their rails, gates and
## power come back on) so the story picks up where the player left off. The boss is never skipped.
func _resume() -> void:
	var done: Array = []
	while index + 1 < zones.size():
		var z: Dictionary = zones[index + 1]
		if z.get("kind", "") == "boss" or not Game.is_complete(z.id): break
		index += 1
		_apply_effects(z, true); done.append(z.id)
	if not done.is_empty(): Game.progress_restored.emit(done)
	if index >= 0: print("[story] resumed after zone %d (%s)" % [index, zones[index].id])

func current_id() -> String:
	return zones[index].id if index >= 0 and index < zones.size() else ""

func _advance() -> void:
	index += 1; active = false; wave = 0
	if index >= zones.size(): return
	var z: Dictionary = zones[index]
	Game.objective_set.emit(z.id, z.get("objective", "Explore"))

func _inside(z: Dictionary, p: Vector3) -> bool:
	var r: Rect2 = z.rect
	return r.has_point(Vector2(p.x, p.z)) and absf(p.y - z.get("y", 0.0)) < z.get("y_range", 6.0)

func _physics_process(dt: float) -> void:
	if finished or index < 0 or index >= zones.size() or Game.player == null: return
	var z: Dictionary = zones[index]
	var p: Vector3 = Game.player.global_position
	if debug_auto: _debug_step(dt, z)
	_check_skip(p)
	z = zones[index] if index < zones.size() else {}
	if z.is_empty(): return
	if not active:
		if _inside(z, p): _begin(z)
		return
	# fight in progress
	alive = alive.filter(func(b): return is_instance_valid(b) and not b.dead)
	var kind: String = z.get("kind", "")
	if kind == "relay" or kind == "boss" or kind == "activate": return
	var waves: Array = z.get("waves", [])
	wave_age += dt
	# the next wave rolls in while the last straggler of a big wave is still up, so a fight flows
	# instead of stopping dead between waves (never for the final clear, which needs everyone down)
	var straggler := alive.size() == 1 and wave < waves.size() and wave_age > 4.0 and wave_size >= 3 and not no_overlap
	if alive.is_empty() or straggler:
		wave_delay -= dt
		if wave_delay > 0.0: return
		if wave < waves.size():
			_spawn_wave(z, waves[wave]); wave += 1; wave_age = 0.0
			var w: Dictionary = waves[wave - 1]
			wave_size = int(w.get("roller", 0)) + int(w.get("plated", 0)) + int(w.get("hornet", 0)) + int(w.get("crew", 0)) * 3
			# pacing: a big wave earns a longer breather before the next one (a small one keeps the pressure on)
			wave_delay = 1.2 if no_pacing else clampf(0.7 + 0.3 * wave_size, 0.9, 2.4)
		elif alive.is_empty():
			_clear(z)

## Reaching a later `skip_to` zone early skips the skippable zones in between (alternate routes).
func _check_skip(p: Vector3) -> void:
	for j in range(index + 1, zones.size()):
		var zj: Dictionary = zones[j]
		if not zj.get("skip_to", false) or not _inside(zj, p): continue
		for k in range(index, j):
			if not zones[k].get("skippable", false): return
		for k in range(index, j):
			_apply_effects(zones[k]); Game.complete(zones[k].id)
		for b in alive: if is_instance_valid(b) and not b.dead: b.die(true)
		alive.clear()
		index = j - 1
		_advance()
		return

func _begin(z: Dictionary) -> void:
	active = true; wave_delay = 0.6; wave_age = 0.0; wave_size = 0
	Game.zone_entered.emit(z.id)
	var cut_lines: bool = z.get("kind", "") == "boss" and _cuts_on()
	if not cut_lines:
		for l in z.get("enter_lines", []): Game.say(l)
	if z.has("name") and not cut_lines: Game.hud.show_banner(z.name, z.get("objective", ""))
	match z.get("kind", ""):
		"reach":
			_clear(z)
		"activate":
			switches.clear(); switched = 0
			var list: Array = z.get("switches", [])
			for i in list.size():
				var s: Dictionary = list[i]
				var sw: Node3D = Switch.new(); sw.label_text = s.get("label", "")
				Game.main.add_child(sw); sw.global_position = s.pos; sw.rotation.y = s.get("yaw", 0.0)
				sw.set_meta("index", i)
				sw.activated.connect(func(n): _switched(z, n))
				switches.append(sw)
			for g in z.get("guards", []):
				_spawn_in(g.rect, g.get("y", 0.0), g)
			_progress(z)
			if list.is_empty(): _clear(z)
		"relay":
			relay = Relay.new(); Game.main.add_child(relay); relay.global_position = z.relay_pos
			relay.destroyed.connect(func(): _clear(z))
			Game.boss_started.emit("SIGNAL RELAY")
		"boss":
			boss = CraneBot.new(); boss.combat = Game.combat; boss.player = Game.player
			boss.spawn_roller = func(p: Vector3): alive.append(Game.main.spawn_bot("roller", p, z.rect))
			Game.main.add_child(boss)
			boss_pos = z.boss_pos; boss_zone = z; boss_dropped = false
			boss.half.connect(func(): Game.say("boss_half", true))
			boss.dead_at.connect(func(p: Vector3): _boss_down(z, p))
			_boss_intro(z)

## The Crane Bot intro cutscene (it drops the boss in itself), then the fight.
func _boss_intro(z: Dictionary) -> void:
	if _cuts_on():
		Snd.music("cutscene", 1.0)
		await play_cutscene("crane_intro")
	drop_boss()
	if z.has("name"): Game.hud.show_banner(z.name, z.get("objective", ""))
	Game.boss_started.emit("CRANE BOT")
	Snd.music("boss", 1.0)

## Spawn the Crane Bot onto its mark (it falls out of the sky). Safe to call twice.
func drop_boss() -> void:
	if boss_dropped or not is_instance_valid(boss): return
	boss_dropped = true
	boss.spawn(boss_pos, boss_zone.rect)

func _progress(z: Dictionary) -> void:
	var total: int = z.get("switches", []).size()
	if total <= 1: return
	var txt: String = z.get("progress_text", z.get("objective", "") + " (%d/%d)")
	Game.objective_set.emit(z.id, txt % [switched, total])

func _switched(z: Dictionary, sw: Node3D) -> void:
	if not active or zones[index] != z: return
	switched += 1
	var total: int = z.get("switches", []).size()
	if Game.level.has_method("on_switch"): Game.level.on_switch(z.id, int(sw.get_meta("index")), switched, total)
	_progress(z)
	if switched >= total: _clear(z)

func _spawn_in(r: Rect2, y: float, w: Dictionary) -> void:
	var n := 0
	var base := randf() * TAU
	for kind in ["roller", "plated", "hornet", "crew"]:
		for i in int(w.get(kind, 0)):
			alive.append(Game.main.spawn_bot(kind, _spawn_spot(r, y, base + TAU * float(n) / 5.0), r)); n += 1

## A drop-in spot in the zone: never right on top of Vesk, and where possible somewhere he is facing,
## so bots arrive in view instead of behind him.
func _spawn_spot(r: Rect2, y: float, a: float) -> Vector3:
	var rad := minf(r.size.x, r.size.y) * 0.3
	var c := r.get_center() + Vector2(cos(a), sin(a)) * rad
	var p: Node3D = Game.player
	if p == null or Game.cam == null: return Vector3(c.x, y, c.y)
	var pp := Vector2(p.global_position.x, p.global_position.z)
	var fwd: Vector3 = Game.cam.forward()
	var best := c
	var best_s := -INF
	for k in 8:
		var aa := a + randf_range(-0.9, 0.9) if k > 0 else a
		var rr := rad * (randf_range(0.6, 1.2) if k > 0 else 1.0)
		var q := r.get_center() + Vector2(cos(aa), sin(aa)) * rr
		q = q.clamp(r.position + Vector2(1.5, 1.5), r.end - Vector2(1.5, 1.5))
		var d := q - pp
		var dist := d.length()
		var s := -absf(dist - 11.0) * 0.3 + (d.normalized().dot(Vector2(fwd.x, fwd.z)) * 2.0 if dist > 0.1 else -9.0)
		if dist < 6.0: s -= 10.0
		if k > 0 and not _floor_at(Vector3(q.x, y, q.y)): continue
		if s > best_s: best_s = s; best = q
	return Vector3(best.x, y, best.y)

## True when there is open floor at about height `p.y` under `p` (not a roof, a pit or a wall).
func _floor_at(p: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 7.0, 0), p - Vector3(0, 1.5, 0)); q.collision_mask = 1
	var hit := Game.main.get_world_3d().direct_space_state.intersect_ray(q)
	return not hit.is_empty() and absf(hit.position.y - p.y) < 0.8 and hit.normal.y > 0.8

func _spawn_wave(z: Dictionary, w: Dictionary) -> void:
	_spawn_in(z.rect, z.get("y", 0.0), w)
	if wave == 0 and randf() < 0.6: Snd.bark("dodger", "spawn")

## Unlocks, gates, power and grants of a zone (also applied when a zone is skipped).
func _apply_effects(z: Dictionary, quiet := false) -> void:
	for i in z.get("unlock_rails", []):
		Game.level.set_rail_locked(i, false)
		if not quiet: Snd.play("rail_unlock", -2)
	for g in z.get("open_gates", []): if Game.level.has_method("open_gate"): Game.level.open_gate(g)
	for m in z.get("power", []): if Game.level.has_method("power"): Game.level.power(m)
	for it in z.get("grants", []): Game.unlock(it)
	if Game.level.has_method("on_zone_cleared"): Game.level.on_zone_cleared(z.id)

func _clear(z: Dictionary) -> void:
	if not active: return
	active = false
	switches.clear()
	Game.complete(z.id); Game.zone_cleared.emit(z.id)
	_apply_effects(z)
	if CUT_AFTER.has(z.id) and _cuts_on():
		play_cutscene(CUT_AFTER[z.id])
	else:
		for l in z.get("clear_lines", []): Game.say(l)
	if z.get("kind", "") == "relay": Game.boss_defeated.emit("SIGNAL RELAY")
	var banner: String = z.get("banner", "" if z.get("kind", "") == "reach" else "AREA CLEAR")
	if banner != "": Game.hud.show_banner(banner, z.get("name", ""), Color(0.5, 1, 0.6))
	Game.save()
	_advance()

func _boss_down(z: Dictionary, p: Vector3) -> void:
	Game.boss_defeated.emit("CRANE BOT")
	Game.combat.drop_nuts(p, 30); Game.combat.drop_cell(p)
	for b in alive: if is_instance_valid(b) and not b.dead: b.die(true)
	Snd.music("skyharbor", 2.0); Snd.play("victory_sting", 0, 0.0, 0.0)
	Game.hud.show_banner("CRANE BOT SCRAPPED", "", Color(1, 0.85, 0.3))
	active = false; finished = true
	Game.complete(z.id); Game.zone_cleared.emit(z.id)
	await get_tree().create_timer(4.0).timeout
	Game.level_complete.emit(Game.data.level)
	Game.cutscene_started.emit("outro")

## Flow test (--story-auto): teleports the player into each zone, then throws its switches or
## destroys its bots, printing each step. Stops at the boss.
func _debug_step(dt: float, z: Dictionary) -> void:
	debug_t -= dt
	if debug_t > 0.0: return
	debug_t = 0.5
	var kind: String = z.get("kind", "")
	if not active:
		var c: Vector2 = z.rect.get_center()
		print("[story-auto] zone %d %s (%s): %s" % [index, z.id, kind if kind != "" else "fight", z.get("objective", "")])
		if kind == "boss": debug_auto = false; print("[story-auto] teleporting into the boss arena, auto off")
		Game.player.global_position = Vector3(c.x, z.get("y", 0.0) + 0.3, c.y); Game.player.velocity = Vector3.ZERO
		return
	match kind:
		"activate":
			for sw in switches: if is_instance_valid(sw) and not sw.dead: sw.damage(1.0, sw.center(), Vector3.ZERO); return
		"":
			for b in alive: if is_instance_valid(b) and not b.dead: b.die(true)
