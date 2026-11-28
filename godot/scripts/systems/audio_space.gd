extends Node
## Audio space pass (2026-11-28), on top of the adaptive director (audio_director.gd):
## - Route beds: the walkways between the areas get their own ambience, crossfaded by distance to the deck:
##   wind, banner flutter and rope creaks on the open viaducts, bridges and gantries (sfx/amb_route_wind),
##   far machinery and chain clanks on the freight gangways and the yard approach (sfx/amb_route_freight).
##   `--no-route-amb` turns them off.
## - Cover: rays up from the hero find roofs, awnings, arches and tunnels; under cover the ambience beds are
##   muffled (a low-pass on the Amb bus), the wind drops and the World reverb gets wetter. `--no-cover-audio`.
## - Enemy wind-ups: every attack telegraph has a sound (sfx/enemy_windup_*), so attacks can be read by ear:
##   the crew roller's riveter cocks (rivet), the hornet's eye charges (hornet), the Crane Bot's slam and sweep
##   strain (slam) and its spray charges (charge). `--no-windup-sfx`. Unused so far: enemy_windup_lunge
##   (a motor rev before a lunge) and enemy_windup_throw (a spring-arm creak before a throw).
## - Crane Bot cues (round 2), read off its state like the wind-ups: a fury roar when it rips its jib off for
##   phase two (boss_phase_roar), an alarm whoop when the red alarm lights come on and now and then after
##   (crane_alarm_whoop), the Quake Stomp's rear-up groan, ground crash and a rolling rumble with every
##   shockwave ring (crane_rearup_groan, quake_crash, quake_rumble). cranebot.gd itself plays the armour clang
##   on big hits, the JAMMED sputter and the death hiccups. All of them: `--no-boss-sfx` (snd.gd BOSS_SFX).
## `--no-audio-space` turns all of it off. `--space-debug` prints the state every 2 s; `--space-probe` visits the
## ground tour spots (scripts/level/ground/ground.gd TOUR), prints island / surface / route beds / cover there, and quits.

## bed -> [island name prefixes, dB at full weight]
const ROUTE_BEDS := {
	"amb_route_wind": [["junk_viaduct", "plaza_viaduct", "plaza_bridge", "junk_halt_gantry", "junk_works_gantry",
		"causeway", "cableway", "bridge", "viaduct"], -8.0],
	"amb_route_freight": [["pier_gangway", "yard_approach", "yard_checkpoint", "yard_liftbridge", "pier_barge", "haul"], -9.0],
}
const COVER_RAYS := [Vector3(0, 1, 0), Vector3(0.45, 1, 0), Vector3(-0.45, 1, 0), Vector3(0, 1, 0.45), Vector3(0, 1, -0.45)]
const COVER_H := 9.0

var route_on := true
var cover_on := true
var windup_on := true
var debug := false
var beds := {}            # bed name -> AudioStreamPlayer
var bed_w := {}
var bed_islands := {}     # bed name -> [island names]
var island_count := -1
var cover := 0.0
var cover_want := 0.0
var ray_t := 0.0
var prev := {}            # bot instance id -> last telegraph key
var dbg_t := 2.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	var all_off := args.has("--no-audio-space")
	route_on = not all_off and not args.has("--no-route-amb")
	cover_on = not all_off and not args.has("--no-cover-audio")
	windup_on = not all_off and not args.has("--no-windup-sfx")
	debug = args.has("--space-debug")
	if debug: print("[audio-space] route=%s cover=%s windup=%s" % [route_on, cover_on, windup_on])
	if args.has("--space-probe"): _probe.call_deferred()
	if cover_on:
		Snd._fx(AudioServer.get_bus_index("Amb"), "AudioEffectLowPassFilter", {"cutoff_hz": 20500.0, "resonance": 0.5})

func _director() -> Node:
	return Snd.director if Snd.director != null and is_instance_valid(Snd.director) else null

func _level_ok() -> bool:
	return Game.level != null and is_instance_valid(Game.level) and "islands" in Game.level \
		and Game.player != null and is_instance_valid(Game.player)

func _process(dt: float) -> void:
	if not _level_ok(): return
	if route_on: _update_routes(dt)
	if cover_on: _update_cover(dt)
	if windup_on: _update_windups()
	if windup_on: _update_boss(dt)
	if debug:
		dbg_t -= dt
		if dbg_t <= 0.0:
			dbg_t = 2.0
			if Snd.music_lift > 0.01: print("[audio-space] music lift %.2f track=%s" % [Snd.music_lift, Snd.track])
			var w := {}
			for b in bed_w: w[b] = snappedf(bed_w[b], 0.01)
			var d := _director()
			print("[audio-space] island=%s routes=%s cover=%.2f surface=%s" % [d.cur_island if d else "?", w, cover, d.surface() if d else "?"])

# ------------------------------------------------------------------ route beds
func _map() -> void:
	var isl: Dictionary = Game.level.islands
	island_count = isl.size()
	bed_islands.clear()
	for b in ROUTE_BEDS:
		var names := []
		for n in isl:
			for p in ROUTE_BEDS[b][0]:
				if String(n).begins_with(p): names.append(n); break
		bed_islands[b] = names
	if debug: print("[audio-space] route islands ", bed_islands)

func _update_routes(dt: float) -> void:
	if island_count != Game.level.islands.size(): _map()
	var pos: Vector3 = Game.player.global_position
	var cam := get_viewport().get_camera_3d()
	if Game.input_locked and cam and cam.global_position.distance_to(pos) > 15.0: pos = cam.global_position
	var p2 := Vector2(pos.x, pos.z)
	var hs: Dictionary = Game.level.heights if "heights" in Game.level else {}
	var d := _director()
	var quiet := 0.4 if d and d.combat else 0.0
	for b in ROUTE_BEDS:
		if not Snd.streams.has(b): continue
		var best := INF
		for n in bed_islands.get(b, []):
			var r: Rect2 = Game.level.islands[n]
			var dx := maxf(maxf(r.position.x - p2.x, 0.0), p2.x - r.end.x)
			var dz := maxf(maxf(r.position.y - p2.y, 0.0), p2.y - r.end.y)
			var dd := Vector2(dx, dz).length() + maxf(absf(pos.y - float(hs.get(n, 0.0))) - 4.0, 0.0)
			best = minf(best, dd)
		var want := pow(clampf(1.0 - best / 14.0, 0.0, 1.0), 1.4) * (1.0 - quiet)
		bed_w[b] = move_toward(bed_w.get(b, 0.0), want, dt * 0.5)
		var p: AudioStreamPlayer = beds.get(b)
		if bed_w[b] > 0.01:
			if p == null:
				var s: AudioStream = Snd.streams[b].duplicate()
				if "loop" in s: s.loop = true
				p = AudioStreamPlayer.new(); p.stream = s; p.bus = "Amb"; p.volume_db = -60.0; p.name = b
				add_child(p); beds[b] = p
			if not p.playing: p.play(randf() * maxf(p.stream.get_length() - 1.0, 0.0))
			p.volume_db = float(ROUTE_BEDS[b][1]) + linear_to_db(bed_w[b])
		elif p and p.playing:
			p.stop()

# ------------------------------------------------------------------ cover
func _update_cover(dt: float) -> void:
	var d := _director()
	ray_t -= dt
	if ray_t <= 0.0:
		ray_t = 0.12
		cover_want = 0.0
		var pl: Node3D = Game.player
		if not Game.input_locked and not get_tree().paused:
			var space := pl.get_world_3d().direct_space_state
			var from := pl.global_position + Vector3(0, 1.9, 0)
			var hits := 0
			for r in COVER_RAYS:
				var q := PhysicsRayQueryParameters3D.create(from, from + (r as Vector3).normalized() * COVER_H, 1, [pl.get_rid()])
				var h := space.intersect_ray(q)
				if not h.is_empty() and (h.normal as Vector3).y < -0.3: hits += 1
			cover_want = clampf((hits - 1) / 3.0, 0.0, 1.0)   # one stray beam overhead isn't a roof
	cover = move_toward(cover, cover_want, dt * (2.5 if cover_want > cover else 1.5))
	var lp := Snd.bus_fx("Amb", "AudioEffectLowPassFilter")
	# muffled beds under a roof (log-spaced from open air to about 1.6 kHz); the pause menu's own dip still applies
	if lp: lp.cutoff_hz = 20500.0 * pow(1600.0 / 20500.0, cover)
	if d:
		d.cover = cover
		d.verb_extra = 0.12 * cover

# ------------------------------------------------------------------ enemy wind-ups
func _update_windups() -> void:
	var seen := {}
	for b in get_tree().get_nodes_in_group("targets"):
		if not (b is Node3D) or b.get("dead") == true: continue
		var key := _telegraph(b)
		var id := b.get_instance_id()
		seen[id] = true
		var was: String = prev.get(id, "")
		if key != "" and key != was: _windup(b as Node3D, key)
		prev[id] = key
	for id in prev.keys():
		if not seen.has(id): prev.erase(id)

## what attack (if any) the enemy is winding up: a key into _windup
func _telegraph(b: Node) -> String:
	var sc: Script = b.get_script()
	if sc == null: return ""
	var path := sc.resource_path
	if path.ends_with("enemy_crew_roller.gd"):
		return "rivet" if float(b.get("shoot_t")) >= 0.0 else ""
	if path.ends_with("enemy_hornet.gd"):
		return "hornet" if b.get("aiming") == true else ""
	if path.ends_with("cranebot.gd"):
		match String(b.get("state")):
			"slam": return "crane_slam"
			"sweep_wind": return "crane_sweep"
			"spray": return "crane_spray"
	return ""

func _windup(b: Node3D, key: String) -> void:
	var c: Vector3 = b.center() if b.has_method("center") else b.global_position + Vector3(0, 0.8, 0)
	if debug: print("[audio-space] windup %s at %s" % [key, c.snapped(Vector3(0.1, 0.1, 0.1))])
	match key:
		"rivet": Snd.at("enemy_windup_rivet", c, -5.0, 0.1, 0.12)
		"hornet": Snd.at("enemy_windup_hornet", c, -6.0, 0.1, 0.12)
		"crane_slam": Snd.at("enemy_windup_slam", c, 2.0, 0.04, 0.3)
		"crane_sweep": Snd.at("enemy_windup_slam", c, 3.0, 0.04, 0.3)
		"crane_spray": Snd.at("enemy_windup_charge", c, 0.0, 0.04, 0.3)

# ------------------------------------------------------------------ probe
func _probe() -> void:
	await get_tree().create_timer(1.5).timeout
	if not _level_ok(): print("[audio-space] probe: no level"); get_tree().quit(1); return
	Game.input_locked = false
	# where is there cover? per island: how much of it is under a roof (same rays as in play)
	var space := Game.player.get_world_3d().direct_space_state
	for n in Game.level.islands:
		var r: Rect2 = Game.level.islands[n]
		var h: float = float(Game.level.heights.get(n, 0.0)) if "heights" in Game.level else 0.0
		var tot := 0; var cov := 0
		for x in range(int(r.position.x) + 1, int(r.end.x), 2):
			for z in range(int(r.position.y) + 1, int(r.end.y), 2):
				var from := Vector3(x, h + 1.9, z)
				var hits := 0
				for ry in COVER_RAYS:
					var hh := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + (ry as Vector3).normalized() * COVER_H, 1))
					if not hh.is_empty() and (hh.normal as Vector3).y < -0.3: hits += 1
				tot += 1; if hits >= 2: cov += 1
		if cov > 0: print("[audio-space] cover %s %d/%d" % [n, cov, tot])
	for t in preload("res://scripts/level/ground/ground.gd").TOUR:
		Game.player.global_position = t[1] + Vector3(0, 0.3, 0); Game.player.velocity = Vector3.ZERO
		await get_tree().create_timer(1.6).timeout
		Game.input_locked = false
		var d := _director()
		var w := {}
		for b in bed_w: if bed_w[b] > 0.01: w[b] = snappedf(bed_w[b], 0.01)
		print("[audio-space] probe %-16s island=%-18s surface=%-8s cover=%.2f routes=%s" % [t[0], d.cur_island if d else "?", d.surface() if d else "?", cover, w])
	get_tree().quit()

# ------------------------------------------------------------------ Crane Bot cues
var boss_state := ""
var boss_rings := 0
var boss_alarm := false
var whoop_t := 0.0
var whoops_left := 0

func _update_boss(dt: float) -> void:
	var b: Node = null
	for n in get_tree().get_nodes_in_group("boss"):
		if n.get("quake_rings") != null: b = n; break
	if b == null or not (b is Node3D): boss_state = ""; boss_alarm = false; return
	var c: Vector3 = b.center() if b.has_method("center") else (b as Node3D).global_position + Vector3(0, 2, 0)
	var base: Vector3 = (b as Node3D).global_position
	var st := String(b.get("state"))
	if st != boss_state:
		match st:
			"rip": Snd.at("boss_phase_roar", c, 5.0, 0.03, 1.0)
			"quake_wind": Snd.at("crane_rearup_groan", base + Vector3(0, 1, 0), 2.0, 0.05, 0.5)
			"quake": Snd.at("quake_crash", base + Vector3(0, 0.5, 0), 5.0, 0.05, 0.5)
		if debug: print("[audio-space] boss state ", st)
		boss_state = st
	var rings: int = (b.get("quake_rings") as Array).size()
	if rings > boss_rings:
		Snd.at("quake_rumble", base + Vector3(0, 0.5, 0), 2.0, 0.08, 0.3)
		if debug: print("[audio-space] quake ring %d" % rings)
	boss_rings = rings
	var al = b.get("alarm_lights")
	var lit: bool = al is Array and not (al as Array).is_empty() and not b.get("dead") and st != "dying"
	if lit and not boss_alarm:
		whoops_left = 2; whoop_t = 0.0
		if debug: print("[audio-space] alarm lights on")
	boss_alarm = lit
	if not lit: return
	whoop_t -= dt
	if whoop_t <= 0.0:
		if whoops_left > 0:
			whoops_left -= 1; whoop_t = 1.35
			Snd.at("crane_alarm_whoop", c + Vector3(0, 1.5, 0), 0.0, 0.0, 0.5)
		else:
			whoop_t = randf_range(10.0, 15.0)
			Snd.at("crane_alarm_whoop", c + Vector3(0, 1.5, 0), -9.0, 0.03, 0.5)
