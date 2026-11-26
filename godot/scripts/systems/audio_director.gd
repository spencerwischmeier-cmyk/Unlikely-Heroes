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
		"shots": [["os_chime", -4.0], ["os_clank", -8.0], ["gull_call", -12.0], ["os_creak", -10.0], ["os_scrap_fall", -6.0]]},
	"plaza": {"combat": "combat_a", "surface": "stone", "amb_db": -8.0, "verb": 0.09,
		"shots": [["os_pigeons", -6.0], ["os_horn", -8.0], ["gull_call", -8.0], ["os_bell", -12.0], ["os_flock", -6.0], ["os_tram", -8.0], ["os_leaves", -10.0]]},
	"terrace": {"combat": "combat_b", "surface": "stone", "amb_db": -8.0, "verb": 0.1,
		"shots": [["os_bell", -6.0], ["os_pigeons", -8.0], ["os_chime", -10.0], ["os_cart", -5.0], ["os_kettle", -7.0]]},
	"gardens": {"combat": "combat_a", "surface": "grass", "amb_db": -6.0, "verb": 0.05,
		"shots": [["os_bird1", -3.0], ["os_bird2", -3.0], ["os_bird1", -6.0], ["os_pigeons", -10.0], ["os_flock", -4.0], ["os_leaves", -4.0], ["os_bees", -6.0]]},
	"docks": {"combat": "combat_b", "surface": "wood", "amb_db": -7.0, "verb": 0.07,
		"shots": [["gull_call", -4.0], ["os_creak", -4.0], ["os_horn", -6.0], ["os_gust", -8.0], ["os_winch", -5.0]]},
	"mast": {"combat": "combat_a", "surface": "metal", "amb_db": -6.0, "verb": 0.04,
		"shots": [["os_gust", -2.0], ["gull_call", -8.0], ["os_horn", -10.0], ["os_antenna", -6.0], ["os_flagsnap", -5.0]]},
	"yard": {"combat": "combat_c", "surface": "metal", "amb_db": -6.0, "verb": 0.18,
		"shots": [["os_clank", -2.0], ["os_hiss", -3.0], ["os_clank", -6.0], ["os_horn", -12.0], ["os_hammer", -3.0]]},
}
## island name (exact, then prefix, in this order) -> area
const ISLAND_AREA := [["junkyard", "junkyard"], ["junk", "junkyard"], ["causeway_2", "yard"], ["causeway", "plaza"],
	["plaza", "plaza"], ["vault", "plaza"], ["terrace", "terrace"], ["market", "terrace"], ["tier4", "gardens"], ["tier", "terrace"],
	["garden", "gardens"], ["promenade", "gardens"], ["pier", "docks"], ["dock", "docks"], ["cargo", "docks"],
	["hive", "gardens"], ["conservatory", "gardens"], ["grove", "gardens"], ["bazaar", "terrace"], ["tea", "terrace"],
	["lantern", "terrace"], ["chime", "terrace"], ["wash", "terrace"], ["depot", "docks"], ["berth", "docks"],
	["foundry", "yard"], ["gallery", "mast"], ["mast", "mast"], ["dish", "mast"], ["yard", "yard"], ["arena", "yard"], ["crane", "yard"]]
## island name prefix -> footstep surface (beats the area default)
const ISLAND_SURFACE := [["hive", "grass"], ["plaza_park", "grass"], ["park", "grass"], ["tea", "wood"], ["lantern", "wood"], ["berth", "wood"], ["junk_raft", "wood"],
	["junk_hull", "metal"], ["promenade", "wood"], ["pier", "wood"], ["tier4", "grass"], ["gallery", "metal"],
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
var prev_hook = null
var emit_t := 1.0
var turbines_done := false
var chat_t := 2.0
var lowpass := 20500.0
var fountain_done := false
var boss_phase2 := false
var cut_id := ""
var listen_pos := Vector3.ZERO
var listen_area := ""
var last_kill_t := -99.0
var last_clear_t := -99.0
var flyby: AudioStreamPlayer3D
var flyby_t := 25.0
var flyby_a := Vector3.ZERO
var flyby_b := Vector3.ZERO
var flyby_k := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Snd.director = self
	var args := OS.get_cmdline_user_args()
	debug = args.has("--audio-debug")
	Game.zone_cleared.connect(_on_zone_cleared)
	Game.item_unlocked.connect(func(_id): Snd.sting("sting_unlock", -2.0))
	Game.collectible_found.connect(func(_k, _id): Snd.sting("sting_secret", -3.0))
	Game.bot_killed.connect(_on_bot_killed)
	Game.zone_entered.connect(_on_zone_entered)
	Game.cutscene_started.connect(func(id): cut_id = id)
	Game.player_respawned.connect(func(_p): Snd.play("area_whoosh", -12.0, 0.05, 0.5))
	Game.boss_started.connect(func(_n): Snd.sting("sting_alert", 0.0, 4.0, 1.0); alert_cd = 30.0; boss_phase2 = false)
	Game.boss_health.connect(_on_boss_health)
	get_tree().node_added.connect(_on_node_added)
	for t in [0.5, 3.0]: get_tree().create_timer(t).timeout.connect(_route_all)
	if args.has("--audio-test"): _self_test.call_deferred()
	for a in args: if a.begins_with("--audio-mix="): _mix_capture.call_deferred(a.substr(12))
	for a in args: if a.begins_with("--audio-tour="): _tour.call_deferred(a.substr(13))

## Other systems' own players (area sounds, props) default to the Master bus, which skips the volume
## sliders, the reverb and the dialogue duck: route them into the mix.
func _on_node_added(n: Node) -> void:
	if n is AudioStreamPlayer3D or n is AudioStreamPlayer:
		_route.call_deferred(n)
	elif n is CharacterBody3D and n.get_script() and (n.get_script() as Script).resource_path.ends_with("enemy_hornet.gd"):
		_hornet_hum.call_deferred(n)

## a quiet buzzing hover loop on every hornet
func _hornet_hum(n: Node) -> void:
	_attach(n, "drone_hum", -14.0, 2.5, 22.0, Vector3(0, 0.5, 0))
	var p: Node = n.get_node_or_null("SndLoop")
	if p: p.pitch_scale = randf_range(1.5, 1.75)

func _route_all() -> void:
	for n in get_tree().root.find_children("*", "AudioStreamPlayer3D", true, false): _route(n)
	for n in get_tree().root.find_children("*", "AudioStreamPlayer", true, false): _route(n)

func _route(n: Node) -> void:
	if not is_instance_valid(n) or Snd.is_ancestor_of(n): return
	if n is AudioStreamPlayer3D:
		var b := (n as AudioStreamPlayer3D).bus
		if b == &"Master" or b == &"SFX": (n as AudioStreamPlayer3D).bus = &"World"   # World feeds SFX: same slider, plus the area reverb
	elif n is AudioStreamPlayer:
		var p := n as AudioStreamPlayer
		if p.bus != &"Master": return
		var path := p.stream.resource_path if p.stream else ""
		p.bus = &"Voice" if path.contains("/voice/") else &"Amb"
	if n is AudioStreamPlayer and (n as AudioStreamPlayer).bus == &"Voice" and not Snd.extra_voices.has(n):
		Snd.extra_voices = Snd.extra_voices.filter(func(v): return is_instance_valid(v))
		Snd.extra_voices.append(n)

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
	var hs: Dictionary = Game.level.heights if "heights" in Game.level else {}
	var best := ""; var best_d := INF; var best_k := INF
	var dist := {}
	for n in isl:
		var r: Rect2 = isl[n]
		var d := _rect_dist(r, p)
		var a: String = island_area.get(n, "plaza")
		dist[a] = minf(dist.get(a, INF), d)
		# among islands under the point, the deck closest below the hero wins (stacked decks)
		var h: float = hs.get(n, 0.0)
		var k := absf(pos.y - h) + (6.0 if h > pos.y + 1.0 else 0.0)
		if d < best_d - 0.5 or (d <= 0.0 and best_d <= 0.0 and k < best_k):
			best_d = d; best = n; best_k = k
	for a in AREAS:
		var d: float = dist.get(a, INF)
		weights[a] = pow(clampf(1.0 - d / 22.0, 0.0, 1.0), 1.5)
	cur_island = best if best_d < 3.0 else ""
	if best_d < 14.0: return island_area.get(best, "")
	return ""

## footstep surface under the hero
## node-name keywords of what the hero stands on -> surface (props, walkways, area pieces)
const NAME_SURFACE := [["grass", "grass"], ["lawn", "grass"], ["hedge", "grass"], ["planter", "grass"], ["garden", "grass"],
	["moss", "grass"], ["soil", "grass"], ["plank", "wood"], ["wood", "wood"], ["crate", "wood"], ["bench", "wood"],
	["barrel", "wood"], ["pier", "wood"], ["boardwalk", "wood"], ["scrap", "gravel"], ["junk", "gravel"], ["gravel", "gravel"],
	["sand", "gravel"], ["stone", "stone"], ["brick", "stone"], ["tile", "stone"], ["rock", "stone"], ["fountain", "stone"],
	["stair", "stone"], ["metal", "metal"], ["steel", "metal"], ["grate", "metal"], ["catwalk", "metal"], ["walkway", "metal"],
	["container", "metal"], ["pipe", "metal"], ["crane", "metal"], ["girder", "metal"], ["platform", "metal"]]

func _surface_by_ray() -> String:
	var pl := Game.player
	var from: Vector3 = pl.global_position + Vector3(0, 0.4, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from - Vector3(0, 1.6, 0), 1, [pl.get_rid()])
	var hit := pl.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or hit.collider == null: return ""
	var n: Node = hit.collider
	for i in 4:
		if n == null or n == Game.level: break
		var nm := String(n.name).to_lower()
		if not nm.begins_with("@"):
			for k in NAME_SURFACE:
				if nm.contains(k[0]): return k[1]
		n = n.get_parent()
	return ""

func surface() -> String:
	if not _level_ok(): return "metal"
	if Game.player.get("riding"): return "metal"
	var by_ray := _surface_by_ray()
	if by_ray != "": return by_ray
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
## the music cue for the cutscene that is starting (Snd.music("cutscene") asks)
func cut_cue() -> String:
	return "cut_" + cut_id if cut_id != "" else ""

func _shop_open() -> bool:
	var g: Node = Game.main.get_node_or_null("Gizmart") if Game.main else null
	return g != null and g.get("open_i") != null and int(g.open_i) >= 0

func _music_for() -> String:
	if _shop_open() and Snd.has_music("shop"): return "shop"
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
	if t == "shop" or Snd.track == "shop": fade = 0.8
	elif combat: fade = 0.6
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
	# a big fight pushes the combat track up a little
	if combat and Snd.tracks.has(Snd.track): Snd.tracks[Snd.track].db = move_toward(Snd.tracks[Snd.track].db, 2.5 if near >= 4 else 1.0, dt * 2.0)
	if not combat:
		combat_t = combat_t + dt if near > 0 else 0.0
		if combat_t > 0.35:
			combat = true; combat_t = 0.0
			if alert_cd <= 0.0 and Snd.adaptive:
				Snd.sting("sting_alert", -4.0, 4.0, 1.0); alert_cd = 25.0
				Snd.play("zone_alarm", -14.0, 0.0, 1.0)
	else:
		combat_t = combat_t + dt if near == 0 else 0.0
		if combat_t > 5.0:
			combat = false; combat_t = 0.0
			var now := Time.get_ticks_msec() / 1000.0
			# the fight ended because the bots got scrapped (not a zone clear, not running away): a little "phew"
			if Snd.adaptive and now - last_kill_t < 7.0 and now - last_clear_t > 10.0: Snd.sting("sting_calm", -5.0, 5.0)

func _on_zone_cleared(id: String) -> void:
	var kind := ""
	if Game.story and "zones" in Game.story:
		for z in Game.story.zones:
			if z.get("id", "") == id: kind = z.get("kind", "")
	if kind == "boss" or kind == "reach": return
	Snd.sting("sting_clear", 0.0)
	last_clear_t = Time.get_ticks_msec() / 1000.0
	combat_t = maxf(combat_t, 3.5)   # let the combat music go soon after

## the boss fight's music turns furious at half health
func _on_boss_health(_n: String, frac: float) -> void:
	if boss_phase2 or frac > 0.5 or Snd.music_name != "boss" or not Snd.has_music("boss_b"): return
	boss_phase2 = true
	Snd.sting("sting_alert", 2.0, 6.0, 1.2)
	Snd.music("boss_b", 1.2)

func _on_zone_entered(id: String) -> void:
	if Game.story and "zones" in Game.story:
		for z in Game.story.zones:
			if z.get("id", "") == id and z.has("name"): Snd.play("area_whoosh", -8.0, 0.0, 1.0)

func _on_bot_killed(_bot: Node, pos: Vector3, _kind: String) -> void:
	Snd.at("bot_die", pos, -3.0, 0.1, 0.05)
	last_kill_t = Time.get_ticks_msec() / 1000.0
	Snd.play("kill_tick", -13.0, 0.04, 0.04)

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
			p.volume_db = AREAS[a].amb_db + linear_to_db(lin) - (5.0 if _area_has_own_bed(a) else 0.0)
		elif p.playing:
			p.stop()

## area agents' own ambience loops (audio/sfx/<area>_*): ours sits under them
const OWN_BEDS := {"gardens": ["gardens_ambience"], "docks": ["docks_harbor_amb"], "terrace": ["terrace_market"],
	"plaza": ["plaza_crowd"], "yard": ["yard_smelter", "yard_conveyor"]}
var own_bed := {}
func _area_has_own_bed(a: String) -> bool:
	if not own_bed.has(a):
		own_bed[a] = false
		for n in OWN_BEDS.get(a, []): if Snd.streams.has(n): own_bed[a] = true
	return own_bed[a]

func _update_oneshots(dt: float) -> void:
	shot_t -= dt
	if shot_t > 0.0: return
	shot_t = randf_range(3.5, 8.0) * (2.0 if combat else 1.0)
	var a := listen_area if AREAS.has(listen_area) else (area if AREAS.has(area) else "")
	if a == "": return
	var s: Array = AREAS[a].shots.pick_random()
	var ang := randf() * TAU
	var r := randf_range(10.0, 26.0)
	var pos: Vector3 = listen_pos + Vector3(cos(ang) * r, randf_range(1.0, 9.0), sin(ang) * r)
	Snd.at(s[0], pos, s[1], 0.12, 0.0)

func _update_world(dt: float) -> void:
	var a := area if AREAS.has(area) else "plaza"
	verb = move_toward(verb, AREAS[a].verb, dt * 0.05)
	var rv := Snd.bus_fx("World", "AudioEffectReverb")
	if rv: rv.wet = verb
	# more wind higher up
	var y: float = Game.player.global_position.y
	Snd.loop_extra["wind_loop"] = clampf((y - 5.0) / 14.0, 0.0, 1.0) * 6.0
	Snd.loop_extra["city_loop"] = -clampf((y - 8.0) / 12.0, 0.0, 1.0) * 6.0

func _in_pause_menu() -> bool:
	var m: Node = Game.main.get_node_or_null("Menus") if Game.main else null
	if m == null or not ("state" in m): return false
	return m.state == "pause" or (m.state == "settings" and m.get("settings_from") != "title")

## bots mutter to each other during a fight
func _update_chatter(dt: float) -> void:
	chat_t -= dt
	if chat_t > 0.0: return
	chat_t = randf_range(1.6, 3.6)
	if Game.input_locked: return
	var pp: Vector3 = Game.player.global_position
	var near := []
	for b in get_tree().get_nodes_in_group("bots"):
		if b is Node3D and not b.get("dead") and (b as Node3D).global_position.distance_to(pp) < 26.0: near.append(b)
	if near.is_empty(): return
	var b: Node3D = near.pick_random()
	Snd.at("bot_chat", b.global_position + Vector3(0, 0.6, 0), -9.0, 0.15, 0.4)

## a distant airship drones across the sky now and then
func _update_flyby(dt: float) -> void:
	if not Snd.streams.has("airship_engine"): return
	if flyby == null:
		flyby = AudioStreamPlayer3D.new(); flyby.name = "Flyby"
		var s: AudioStream = Snd.streams["airship_engine"].duplicate()
		if "loop" in s: s.loop = true
		flyby.stream = s; flyby.bus = "World"; flyby.unit_size = 18.0; flyby.max_distance = 160.0
		flyby.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(flyby)
	if flyby.playing:
		flyby_k += dt / 26.0
		flyby.global_position = flyby_a.lerp(flyby_b, flyby_k)
		flyby.volume_db = -10.0 + linear_to_db(maxf(sin(clampf(flyby_k, 0.0, 1.0) * PI), 0.001))
		if flyby_k >= 1.0: flyby.stop()
		return
	flyby_t -= dt
	if flyby_t > 0.0 or combat: return
	flyby_t = randf_range(50.0, 110.0)
	var c: Vector3 = Game.player.global_position
	var ang := randf() * TAU
	var side := Vector3(cos(ang), 0, sin(ang))
	var fwd := Vector3(-side.z, 0, side.x)
	var off := side * randf_range(45.0, 70.0) + Vector3(0, randf_range(22.0, 38.0), 0)
	flyby_a = c + off - fwd * 90.0; flyby_b = c + off + fwd * 90.0; flyby_k = 0.0
	flyby.global_position = flyby_a; flyby.pitch_scale = randf_range(0.85, 1.1); flyby.play(randf() * 3.0)

## looping 3D sounds stuck to things in the level (lifts, turbines, Dodger, Gizmart, the relay)
func _attach(n: Node, sound: String, db: float, unit := 3.0, maxd := 28.0, offset := Vector3.ZERO) -> void:
	if n == null or not is_instance_valid(n) or not (n is Node3D) or n.has_node("SndLoop"): return
	if not Snd.streams.has(sound): return
	var s: AudioStream = Snd.streams[sound].duplicate()
	if "loop" in s: s.loop = true
	var p := AudioStreamPlayer3D.new(); p.name = "SndLoop"; p.stream = s; p.volume_db = db; p.bus = "World"
	p.unit_size = unit; p.max_distance = maxd; p.position = offset
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	n.add_child(p)
	p.play(randf() * maxf(s.get_length() - 0.5, 0.0))

func _update_emitters() -> void:
	for m in Game.level.get("movers") if Game.level.get("movers") != null else []:
		if m is Dictionary and m.has("body"): _attach(m.body, "lift_move", -20.0, 2.5, 18.0)
	if not turbines_done:
		turbines_done = true
		var found := 0
		for t in Game.level.find_children("*wind_turbine*", "", true, false):
			if found >= 8: break
			_attach(t, "turbine_loop", -12.0, 4.0, 34.0, Vector3(0, 6.0, 0)); found += 1
	if not fountain_done and not Snd.streams.has("plaza_fountain") and Game.level.islands.has("plaza") and (Game.level.islands.plaza as Rect2).has_point(Vector2(0, 28)):
		fountain_done = true
		var f := Node3D.new(); f.name = "FountainSnd"; Game.level.add_child(f); f.global_position = Vector3(0, 1.2, 28)
		_attach(f, "fountain", -6.0, 3.0, 26.0)
	# hidden pickups (washers, pages) glint audibly when you're close
	var col: Node = Game.main.get_node_or_null("Collectibles") if Game.main else null
	if col and col.get("items") != null:
		for it in col.items:
			if it is Dictionary and it.has("node") and is_instance_valid(it.node): _attach(it.node, "sparkle_loop", -9.0, 1.5, 11.0)
	if Game.main:
		var dg: Node = Game.main.get_node_or_null("Dodger")
		if dg and dg.get("drone") != null: _attach(dg.drone, "drone_hum", -18.0, 2.0, 16.0)
		var gz: Node = Game.main.get_node_or_null("Gizmart")
		if gz and "kiosks" in gz:
			for k in gz.kiosks:
				if k is Dictionary and k.has("node"): _attach(k.node, "vending_hum", -14.0, 2.0, 14.0, Vector3(0, 1.0, 0))
		for c in Game.main.get_children():
			if c.get_script() and (c.get_script() as Script).resource_path.ends_with("relay.gd"):
				_attach(c, "relay_hum", -6.0, 5.0, 40.0, Vector3(0, 1.5, 0))

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
	Snd.loop("rail_spark", riding and not paused, -17.0)
	var rsp: AudioStreamPlayer = Snd.loops.get("rail_spark")
	if rsp and gl: rsp.pitch_scale = gl.pitch_scale
	var gli: AudioStreamPlayer = Snd.loops.get("glide")
	Snd.loop("glide_wind", gli != null and gli.get_meta("on") and not paused, -15.0)
	# low hull: a heartbeat and the music goes muffled
	var hull: int = Game.combat.get("hull") if Game.combat and Game.combat.get("hull") != null else 8
	var low := hull > 0 and hull <= 2 and not paused
	Snd.loop("lowhp_beat", low, -12.0)
	var menu := _in_pause_menu()
	var want_lp := 700.0 if menu else (1400.0 if low else 20500.0)
	lowpass = move_toward(lowpass, want_lp, get_process_delta_time() * (40000.0 if want_lp < lowpass else 9000.0))
	Snd.menu_duck = menu
	var lp := Snd.bus_fx("Music", "AudioEffectLowPassFilter")
	if lp: lp.cutoff_hz = lowpass
	var ht = pl.get("hook_target")
	if ht != null and ht != prev_hook and pl.get("swing_hook") == null and not paused: Snd.play("hook_lock", -11.0, 0.0, 0.3)
	prev_hook = ht
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
		# in cutscenes the camera is the ear for the ambience (the music follows the hero's area)
		listen_area = ""
		var lw := {}
		var cam := get_viewport().get_camera_3d()
		if Game.input_locked and cam and cam.global_position.distance_to(Game.player.global_position) > 15.0:
			listen_pos = cam.global_position
			listen_area = _locate(listen_pos); lw = weights.duplicate()
		else:
			listen_pos = Game.player.global_position
		var a := _locate(Game.player.global_position)
		if not lw.is_empty(): weights = lw
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
	_update_chatter(dt)
	_update_flyby(dt)
	emit_t -= dt
	if emit_t <= 0.0: emit_t = 2.0; _update_emitters()
	_update_world(dt)
	_update_hero()

func _print_state() -> void:
	var w := {}
	for a in bed_w: if bed_w[a] > 0.01: w[a] = snappedf(bed_w[a], 0.01)
	print("[audio] area=%s island=%s combat=%s track=%s music=%s beds=%s verb=%.2f lp=%d" % [area, cur_island, combat, Snd.track, Snd.music_name, w, verb, lowpass])

# ------------------------------------------------------------------ self test
func _self_test() -> void:
	await get_tree().create_timer(1.5).timeout
	var ok := true
	if not _level_ok(): print("[audio-test] FAIL no level"); get_tree().quit(1); return
	Snd.music("skyharbor", 0.5)
	_map_islands()
	var by_area := {}
	for n in island_area: (by_area.get_or_add(island_area[n], []) as Array).append(n)
	for a in by_area: print("[audio-test] islands %s: %s" % [a, ", ".join(by_area[a])])
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
	# combat: a bot next to the hero should bring in the combat track, and its death let it go
	Game.player.global_position = spots.plaza[0]
	await get_tree().create_timer(1.0).timeout
	var bot: Node = Game.main.spawn_bot("roller", spots.plaza[0] + Vector3(6, 0, 0), Game.level.islands.plaza)
	await get_tree().create_timer(1.5).timeout
	var c_ok := combat and Snd.track.begins_with("combat_")
	print("[audio-test] %s combat on: combat=%s track=%s" % ["PASS" if c_ok else "FAIL", combat, Snd.track])
	ok = ok and c_ok
	if is_instance_valid(bot): bot.queue_free()
	await get_tree().create_timer(6.5).timeout
	var e_ok := not combat and Snd.track == "area_plaza"
	print("[audio-test] %s combat off: combat=%s track=%s" % ["PASS" if e_ok else "FAIL", combat, Snd.track])
	ok = ok and e_ok
	Game.boss_started.emit("TEST"); Snd.music("boss", 0.5)
	await get_tree().create_timer(0.5).timeout
	Game.boss_health.emit("TEST", 0.45)
	var b_ok := Snd.track == "boss_b"
	print("[audio-test] %s boss phase two: track=%s" % ["PASS" if b_ok else "FAIL", Snd.track])
	ok = ok and b_ok
	Game.cutscene_started.emit("broadcast"); Snd.music("cutscene", 0.5)
	var cue_ok := Snd.track == "cut_broadcast"
	print("[audio-test] %s cutscene cue: track=%s" % ["PASS" if cue_ok else "FAIL", Snd.track])
	ok = ok and cue_ok
	Game.cutscene_finished.emit("broadcast")
	Snd.music("skyharbor", 0.5)
	var gz: Node = Game.main.get_node_or_null("Gizmart")
	if gz and gz.get("kiosks") != null and gz.kiosks.size() > 0 and gz.has_method("_open"):
		gz._open(0, false)
		await get_tree().create_timer(0.6).timeout
		var s_ok := Snd.track == "shop"
		print("[audio-test] %s shop music: track=%s" % ["PASS" if s_ok else "FAIL", Snd.track])
		ok = ok and s_ok
		if gz.has_method("_close"): gz._close()
		get_tree().paused = false
	var emitters := 0
	for p in get_tree().root.find_children("SndLoop", "AudioStreamPlayer3D", true, false): emitters += 1
	print("[audio-test] emitters=%d" % emitters)
	for n in ["blaster", "step_wood", "step_grass", "bot_die", "bolt_hit", "melee_hit"]:
		var g: Array = Snd.groups.get(n, [n] if Snd.streams.has(n) else [])
		print("[audio-test] %s group %s = %d" % ["PASS" if g.size() > 0 else "FAIL", n, g.size()])
		ok = ok and g.size() > 0
	for t in ["area_junkyard", "area_plaza", "area_terrace", "area_gardens", "area_docks", "area_mast", "area_yard", "combat_a", "combat_b", "combat_c"]:
		var h := Snd.has_music(t)
		ok = ok and h
		if not h: print("[audio-test] FAIL missing music ", t)
	for a in AREAS:
		for sh in AREAS[a].shots:
			if not Snd.has_sound(sh[0]): ok = false; print("[audio-test] FAIL missing one-shot ", sh[0])
		if not Snd.streams.has("amb_" + a): ok = false; print("[audio-test] FAIL missing bed amb_", a)
	for b in ["Music", "SFX", "Voice", "Amb", "World"]:
		if AudioServer.get_bus_index(b) < 0: ok = false; print("[audio-test] FAIL missing bus ", b)
	print("[audio-test] ", "ALL PASS" if ok else "SOME FAILED")
	get_tree().quit(0 if ok else 1)

func _beds_str() -> String:
	var s := ""
	for a in weights: if weights[a] > 0.01: s += "%s:%.2f " % [a, weights[a]]
	return s

## Debug: record the Master mix of a scripted scene (explore, fight, a voice line) to a wav, for level checks.
func _mix_capture(path: String) -> void:
	await get_tree().create_timer(1.0).timeout
	var rec := AudioEffectRecord.new()
	AudioServer.add_bus_effect(0, rec)
	var spots: Dictionary = Game.level.debug_spots
	Game.player.global_position = spots.plaza[0]
	Snd.music("skyharbor", 0.5)
	rec.set_recording_active(true)
	var t0 := Time.get_ticks_msec()
	var logger := func():
		var tp: AudioStreamPlayer = Snd.tracks[Snd.track].p if Snd.tracks.has(Snd.track) else null
		print("[audio-mix] t=%.1f track=%s vol=%.1f duck=%.2f sting=%.2f voice=%s area=%s" % [(Time.get_ticks_msec() - t0) / 1000.0, Snd.track,
			tp.volume_db if tp else -99.0, Snd.duck, Snd.sting_duck, Snd.voice_player != null and Snd.voice_player.playing, area])
	var tm := Timer.new(); tm.wait_time = 1.0; tm.autostart = true; add_child(tm); tm.timeout.connect(logger)
	await get_tree().create_timer(8.0).timeout
	var pp: Vector3 = Game.player.global_position
	for i in 3: Game.main.spawn_bot("roller", pp + Vector3(5 + i * 2, 0, 4), Game.level.islands.plaza)
	await get_tree().create_timer(2.0).timeout
	for i in 24:
		Snd.play("blaster", -9, 0.07, 0.0)
		if i % 6 == 5: Snd.at("explode_small", pp + Vector3(6, 0.5, 4), 0.0)
		if i % 4 == 0: Snd.at("bolt_hit", pp + Vector3(6, 0.5, 4), -6)
		if i % 5 == 0: Snd.play("step_metal", -12, 0.12)
		await get_tree().create_timer(0.15).timeout
	Snd.at("explode_big", pp + Vector3(5, 0.5, 5), -1)
	Snd.play("hurt", -2)
	Game.say("dock_intro_1", true)
	await get_tree().create_timer(6.0).timeout
	for b in get_tree().get_nodes_in_group("bots"): if is_instance_valid(b): b.queue_free()
	await get_tree().create_timer(9.0).timeout
	rec.set_recording_active(false)
	var w := rec.get_recording()
	if w: w.save_to_wav(path); print("[audio-mix] saved ", path, " ", w.get_length())
	else: print("[audio-mix] no recording")
	get_tree().quit()

## Debug: record 8 s of the mix at each debug spot to <dir>/tour_<spot>.wav (level checks per area).
func _tour(dir: String) -> void:
	await get_tree().create_timer(1.0).timeout
	var rec := AudioEffectRecord.new()
	AudioServer.add_bus_effect(0, rec)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tour-mute="):
			for b in a.substr(12).split(","): AudioServer.set_bus_mute(AudioServer.get_bus_index(b), true)
	var spots: Dictionary = Game.level.debug_spots
	for k in ["start", "plaza", "docks", "pier_c", "terrace", "gardens", "gallery", "dish", "yard", "arena"]:
		if not spots.has(k): continue
		Game.player.global_position = spots[k][0]; Game.player.velocity = Vector3.ZERO
		await get_tree().create_timer(4.0).timeout
		rec.set_recording_active(true)
		await get_tree().create_timer(8.0).timeout
		rec.set_recording_active(false)
		var w := rec.get_recording()
		if w: w.save_to_wav("%s/tour_%s.wav" % [dir, k])
		print("[audio-tour] ", k, " area=", area, " track=", Snd.track)
	get_tree().quit()
