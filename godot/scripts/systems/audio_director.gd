extends Node
## Adaptive audio for Skyharbor (installed by main.gd like every system; registers itself as Snd.director).
## - Works out which area the hero is in from Game.level.islands (island name -> area, unknown islands
##   take the area of the nearest known one), with a short hysteresis so borders don't flap.
## - Music: while Snd.music("skyharbor") is asked for, plays the area's theme (audio/music/area_<area>)
##   and crossfades between themes as the hero moves; when live bots are close it swaps to the area's
##   combat track with an alert stinger, and back a few seconds after the fight.
## - Ambience: one looping bed per area (audio/sfx/amb_<area>), each faded by distance to that area's
##   islands, plus random positional one-shots (birds, gulls, horns, clanks), more wind up high, and
##   per-area reverb on the World bus.
## - Hero feel: jetpack thruster loop from the flames, air rush when falling fast, grind pitch from rail
##   speed, footstep surface per area/island, heavy landing layers.
## - Events: zone clear / unlock / secret stingers, bot death variety.
## Debug: `-- --audio-debug` prints the state every 2 s; `-- --audio-test` runs a quick check and quits.

const AREAS := {
	"junkyard": {"combat": "combat_b", "surface": "gravel", "amb_db": -7.0, "verb": 0.14,
		"shots": [["os_chime", -4.0], ["os_clank", -8.0], ["gull_call", -12.0], ["os_creak", -10.0]]},
	"plaza": {"combat": "combat_a", "surface": "stone", "amb_db": -8.0, "verb": 0.09,
		"shots": [["os_pigeons", -6.0], ["os_horn", -8.0], ["gull_call", -8.0], ["os_bell", -12.0]]},
	"terrace": {"combat": "combat_b", "surface": "stone", "amb_db": -8.0, "verb": 0.1,
		"shots": [["os_bell", -6.0], ["os_pigeons", -8.0], ["os_chime", -10.0]]},
	"gardens": {"combat": "combat_a", "surface": "grass", "amb_db": -6.0, "verb": 0.05,
		"shots": [["os_bird1", -3.0], ["os_bird2", -3.0], ["os_bird1", -6.0], ["os_pigeons", -10.0]]},
	"docks": {"combat": "combat_b", "surface": "wood", "amb_db": -7.0, "verb": 0.07,
		"shots": [["gull_call", -4.0], ["os_creak", -4.0], ["os_horn", -6.0], ["os_gust", -8.0]]},
	"mast": {"combat": "combat_a", "surface": "metal", "amb_db": -6.0, "verb": 0.04,
		"shots": [["os_gust", -2.0], ["gull_call", -8.0], ["os_horn", -10.0]]},
	"yard": {"combat": "combat_a", "surface": "metal", "amb_db": -6.0, "verb": 0.18,
		"shots": [["os_clank", -2.0], ["os_hiss", -3.0], ["os_clank", -6.0], ["os_horn", -12.0]]},
}
## island name (exact, then prefix, in this order) -> area
const ISLAND_AREA := [["junkyard", "junkyard"], ["junk", "junkyard"], ["causeway_2", "yard"], ["causeway", "plaza"],
	["plaza", "plaza"], ["vault", "plaza"], ["terrace", "terrace"], ["market", "terrace"], ["tier4", "gardens"], ["tier", "terrace"],
	["garden", "gardens"], ["promenade", "gardens"], ["pier", "docks"], ["dock", "docks"], ["cargo", "docks"],
	["gallery", "mast"], ["mast", "mast"], ["dish", "mast"], ["yard", "yard"], ["arena", "yard"], ["crane", "yard"]]
## island name prefix -> footstep surface (beats the area default)
const ISLAND_SURFACE := [["promenade", "wood"], ["pier", "wood"], ["tier4", "grass"], ["gallery", "metal"],
	["dish", "metal"], ["mast", "metal"], ["causeway", "metal"]]

var island_area := {}       # island name -> area
var island_count := -1
var area := ""              # settled area (music follows this)
var cand := ""
var cand_t := 0.0
var combat := false
var combat_t := 0.0         # seconds with / without bots near (towards switching)
var alert_cd := 0.0
var beds := {}              # area -> AudioStreamPlayer
var bed_w := {}
var shot_t := 3.0
var tick := 0.0
var cur_island := ""
var weights := {}
var debug := false
var verb := 0.08
var prev_swing := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Snd.director = self
	var args := OS.get_cmdline_user_args()
	debug = args.has("--audio-debug")
	Game.zone_cleared.connect(_on_zone_cleared)
	Game.item_unlocked.connect(func(_id): Snd.sting("sting_unlock", -2.0))
	Game.collectible_found.connect(func(_k, _id): Snd.sting("sting_secret", -3.0))
	Game.bot_killed.connect(_on_bot_killed)
	Game.boss_started.connect(func(_n): Snd.sting("sting_alert", 0.0); alert_cd = 30.0)
	if args.has("--audio-test"): _self_test.call_deferred()

func _level_ok() -> bool:
	return Game.level != null and is_instance_valid(Game.level) and "islands" in Game.level \
		and Game.player != null and is_instance_valid(Game.player)

# ------------------------------------------------------------------ areas
func _map_islands() -> void:
	var isl: Dictionary = Game.level.islands
	island_count = isl.size()
	island_area.clear()
	var unknown := []
	for n in isl:
		var a := _area_by_name(n)
		if a == "": unknown.append(n)
		else: island_area[n] = a
	for n in unknown:
		var c: Vector2 = (isl[n] as Rect2).get_center()
		var best := INF; var ba := "plaza"
		for k in island_area:
			var d := c.distance_to((isl[k] as Rect2).get_center())
			if d < best: best = d; ba = island_area[k]
		island_area[n] = ba

static func _area_by_name(n: String) -> String:
	for p in ISLAND_AREA:
		if n == p[0]: return p[1]
	for p in ISLAND_AREA:
		if n.begins_with(p[0]): return p[1]
	return ""

static func _rect_dist(r: Rect2, p: Vector2) -> float:
	var dx := maxf(maxf(r.position.x - p.x, 0.0), p.x - r.end.x)
	var dz := maxf(maxf(r.position.y - p.y, 0.0), p.y - r.end.y)
	return Vector2(dx, dz).length()

## the island under (or nearest to) a point, and per-area distance weights
func _locate(pos: Vector3) -> String:
	var isl: Dictionary = Game.level.islands
	var p := Vector2(pos.x, pos.z)
	var best := ""; var best_d := INF; var best_area := INF
	var dist := {}
	for n in isl:
		var r: Rect2 = isl[n]
		var d := _rect_dist(r, p)
		var a: String = island_area.get(n, "plaza")
		dist[a] = minf(dist.get(a, INF), d)
		var sz := r.get_area()
		if d < best_d - 0.5 or (d <= 0.0 and best_d <= 0.0 and sz < best_area):
			best_d = d; best = n; best_area = sz
	for a in AREAS:
		var d: float = dist.get(a, INF)
		weights[a] = pow(clampf(1.0 - d / 22.0, 0.0, 1.0), 1.5)
	cur_island = best if best_d < 3.0 else ""
	if best_d < 14.0: return island_area.get(best, "")
	return ""

## footstep surface under the hero
func surface() -> String:
	if not _level_ok(): return "metal"
	if Game.player.get("riding"): return "metal"
	if cur_island == "": return "metal"
	var h: float = Game.level.heights.get(cur_island, 0.0) if "heights" in Game.level else 0.0
	if absf(Game.player.global_position.y - h) > 2.5: return "metal"
	for p in ISLAND_SURFACE:
		if cur_island.begins_with(p[0]): return p[1]
	var a: String = island_area.get(cur_island, "")
	return AREAS[a].surface if AREAS.has(a) else "metal"

## a landing: a footstep of the surface on top, and a heavy thump for big drops
func landed(db: float) -> void:
	Snd.play("step_" + surface(), db + 3.0, 0.08, 0.0)
	if db > -5.0: Snd.play("land_heavy", db - 1.0, 0.06, 0.1)
	if db > -2.0: Snd.play("debris", db - 12.0, 0.1, 0.3)

# ------------------------------------------------------------------ music
func _music_for() -> String:
	var a := area if AREAS.has(area) else "plaza"
	if combat: return AREAS[a].combat
	return "area_" + a

func pick_track(fade := 2.0) -> void:
	if _level_ok():
		if island_count != Game.level.islands.size(): _map_islands()
		var a := _locate(Game.player.global_position)
		if a != "": area = a; cand = a
	Snd.set_track(_music_for(), fade, 0.0)

func _update_music() -> void:
	if not Snd.adaptive: return
	var t := _music_for()
	if t == Snd.track: return
	var fade := 2.5
	if combat: fade = 0.6
	elif Snd.track.begins_with("combat_"): fade = 3.5
	Snd.set_track(t, fade, 1.0 if combat else 0.0)

func _bots_near(pos: Vector3) -> int:
	var n := 0
	for b in get_tree().get_nodes_in_group("bots"):
		if not (b is Node3D) or b.get("dead"): continue
		var d: Vector3 = (b as Node3D).global_position - pos
		if absf(d.y) < 14.0 and Vector2(d.x, d.z).length() < 30.0: n += 1
	return n

func _update_combat(dt: float) -> void:
	var near := 0 if Game.input_locked else _bots_near(Game.player.global_position)
	if not combat:
		combat_t = combat_t + dt if near > 0 else 0.0
		if combat_t > 0.35:
			combat = true; combat_t = 0.0
			if alert_cd <= 0.0 and Snd.adaptive:
				Snd.sting("sting_alert", -4.0); alert_cd = 25.0
				Snd.play("zone_alarm", -14.0, 0.0, 1.0)
	else:
		combat_t = combat_t + dt if near == 0 else 0.0
		if combat_t > 5.0: combat = false; combat_t = 0.0

func _on_zone_cleared(id: String) -> void:
	var kind := ""
	if Game.story and "zones" in Game.story:
		for z in Game.story.zones:
			if z.get("id", "") == id: kind = z.get("kind", "")
	if kind == "boss" or kind == "reach": return
	Snd.sting("sting_clear", 0.0)
	combat_t = maxf(combat_t, 3.5)   # let the combat music go soon after

func _on_bot_killed(_bot: Node, pos: Vector3, _kind: String) -> void:
	Snd.at("bot_die", pos, -3.0, 0.1, 0.05)

# ------------------------------------------------------------------ ambience
func _ensure_beds() -> void:
	if not beds.is_empty(): return
	var holder := Node.new(); holder.name = "Beds"; add_child(holder)
	for a in AREAS:
		var n: String = "amb_" + a
		if not Snd.streams.has(n): continue
		var s: AudioStream = Snd.streams[n].duplicate()
		if "loop" in s: s.loop = true
		var p := AudioStreamPlayer.new(); p.stream = s; p.bus = "Amb"; p.volume_db = -60.0
		holder.add_child(p); beds[a] = p; bed_w[a] = 0.0

func _update_beds(dt: float) -> void:
	_ensure_beds()
	var quiet := 0.35 if combat else 0.0     # beds sit back during fights
	for a in beds:
		var p: AudioStreamPlayer = beds[a]
		var w: float = weights.get(a, 0.0)
		bed_w[a] = move_toward(bed_w[a], w, dt * 0.6)
		var lin: float = bed_w[a] * (1.0 - quiet)
		if lin > 0.01:
			if not p.playing: p.play(randf() * maxf(p.stream.get_length() - 1.0, 0.0))
			p.volume_db = AREAS[a].amb_db + linear_to_db(lin)
		elif p.playing:
			p.stop()

func _update_oneshots(dt: float) -> void:
	shot_t -= dt
	if shot_t > 0.0: return
	shot_t = randf_range(3.5, 8.0) * (2.0 if combat else 1.0)
	var a := area if AREAS.has(area) else ""
	if a == "": return
	var s: Array = AREAS[a].shots.pick_random()
	var ang := randf() * TAU
	var r := randf_range(10.0, 26.0)
	var pos: Vector3 = Game.player.global_position + Vector3(cos(ang) * r, randf_range(1.0, 9.0), sin(ang) * r)
	Snd.at(s[0], pos, s[1], 0.12, 0.0)

func _update_world(dt: float) -> void:
	var a := area if AREAS.has(area) else "plaza"
	verb = move_toward(verb, AREAS[a].verb, dt * 0.05)
	var rv := Snd.bus_fx("World", "AudioEffectReverb")
	if rv: rv.wet = verb
	# more wind higher up
	var y: float = Game.player.global_position.y
	Snd.loop_extra["wind_loop"] = clampf((y - 5.0) / 14.0, 0.0, 1.0) * 9.0
	Snd.loop_extra["city_loop"] = -clampf((y - 8.0) / 12.0, 0.0, 1.0) * 6.0

# ------------------------------------------------------------------ hero
func _update_hero() -> void:
	var pl := Game.player
	var paused := get_tree().paused or Game.input_locked
	var grounded: bool = pl.get("grounded") == true
	var riding: bool = pl.get("riding") == true
	var jp: float = pl.get("jet_power") if pl.get("jet_power") != null else 0.0
	var jet_on := not paused and jp > 0.12 and not grounded
	Snd.loop("jet_loop", jet_on, lerpf(-24.0, -10.0, clampf(jp, 0.0, 1.0)))
	var jl: AudioStreamPlayer = Snd.loops.get("jet_loop")
	if jl: jl.pitch_scale = 0.85 + 0.3 * clampf(jp, 0.0, 1.0)
	var v: Vector3 = pl.velocity
	var spd := v.length()
	var rush_on := not paused and not grounded and not riding and spd > 11.0
	Snd.loop("air_rush", rush_on, lerpf(-28.0, -12.0, clampf((spd - 11.0) / 17.0, 0.0, 1.0)))
	var gl: AudioStreamPlayer = Snd.loops.get("grind_loop")
	if gl and riding:
		var rs: float = absf(pl.get("rail_speed")) if pl.get("rail_speed") != null else 10.0
		gl.pitch_scale = clampf(0.85 + rs / 45.0, 0.85, 1.35)
	var swinging: bool = pl.get("swing_hook") != null
	if swinging and not prev_swing: Snd.play("rope_swing", -10.0, 0.08, 0.3)
	prev_swing = swinging

# ------------------------------------------------------------------ main loop
func _process(dt: float) -> void:
	if not _level_ok(): return
	alert_cd -= dt
	tick -= dt
	if tick <= 0.0:
		tick = 0.2
		if island_count != Game.level.islands.size(): _map_islands()
		var a := _locate(Game.player.global_position)
		if a != "" and a != area:
			if a == cand: cand_t += 0.2
			else: cand = a; cand_t = 0.0
			if cand_t >= 0.8 or area == "": area = a
		else: cand = area; cand_t = 0.0
		_update_combat(0.2)
		_update_music()
		if debug and Engine.get_process_frames() % 120 < 12: _print_state()
	_update_beds(dt)
	_update_oneshots(dt)
	_update_world(dt)
	_update_hero()

func _print_state() -> void:
	var w := {}
	for a in bed_w: if bed_w[a] > 0.01: w[a] = snappedf(bed_w[a], 0.01)
	print("[audio] area=%s island=%s combat=%s track=%s music=%s beds=%s verb=%.2f" % [area, cur_island, combat, Snd.track, Snd.music_name, w, verb])

# ------------------------------------------------------------------ self test
func _self_test() -> void:
	await get_tree().create_timer(1.5).timeout
	var ok := true
	if not _level_ok(): print("[audio-test] FAIL no level"); get_tree().quit(1); return
	Snd.music("skyharbor", 0.5)
	var spots: Dictionary = Game.level.debug_spots
	var expect := {"start": "junkyard", "plaza": "plaza", "docks": "docks", "pier_c": "docks", "terrace": "terrace",
		"glide": "terrace", "gardens": "gardens", "gallery": "mast", "dish": "mast", "yard": "yard", "arena": "yard"}
	for k in expect:
		if not spots.has(k): continue
		Game.player.global_position = spots[k][0]; Game.player.velocity = Vector3.ZERO
		for i in 30: await get_tree().process_frame
		await get_tree().create_timer(1.3).timeout
		var good: bool = area == expect[k]
		ok = ok and good
		print("[audio-test] %s spot=%s area=%s island=%s surface=%s track=%s %s" % ["PASS" if good else "FAIL", k, area, cur_island, surface(), Snd.track, _beds_str()])
	for n in ["blaster", "step_wood", "step_grass", "bot_die", "bolt_hit", "melee_hit"]:
		var g: Array = Snd.groups.get(n, [n] if Snd.streams.has(n) else [])
		print("[audio-test] %s group %s = %d" % ["PASS" if g.size() > 0 else "FAIL", n, g.size()])
		ok = ok and g.size() > 0
	for t in ["area_junkyard", "area_plaza", "area_terrace", "area_gardens", "area_docks", "area_mast", "area_yard", "combat_a", "combat_b"]:
		var h := Snd.has_music(t)
		ok = ok and h
		if not h: print("[audio-test] FAIL missing music ", t)
	for b in ["Music", "SFX", "Voice", "Amb", "World"]:
		if AudioServer.get_bus_index(b) < 0: ok = false; print("[audio-test] FAIL missing bus ", b)
	print("[audio-test] ", "ALL PASS" if ok else "SOME FAILED")
	get_tree().quit(0 if ok else 1)

func _beds_str() -> String:
	var s := ""
	for a in weights: if weights[a] > 0.01: s += "%s:%.2f " % [a, weights[a]]
	return s
