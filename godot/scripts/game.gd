extends Node
## Autoloaded as Game. The shared hub every system talks through, so parts of the game stay
## independent: gameplay emits events here, and the story, HUD, Dodger, shop and save system listen.
##
## Rules for new code: don't reach into another system's script; emit or listen on Game instead.
## References to the live scene (player, combat, level, hud, story) are filled in by main.gd.

# ---- events ----
signal bot_killed(bot: Node, pos: Vector3, kind: String)   # any enemy destroyed
signal player_hurt(hull: int)
signal player_hit_from(pos: Vector3)                       # where a hit came from (HUD damage arrows)
signal player_fell
signal player_respawned(pos: Vector3)
signal player_downed                                       # hull ran out (systems/knockout.gd fades out and revives)
signal close_call          # a dash through an enemy shot (combat._close_call)
signal zone_entered(id: String)
signal zone_cleared(id: String)
signal objective_set(id: String, text: String)           # the current main objective
signal objective_done(id: String)
signal checkpoint_reached(pos: Vector3)
signal progress_restored(zone_ids: Array)                 # Continue: these zones were already done in the save
signal boss_started(boss_name: String)
signal boss_health(boss_name: String, frac: float)
signal boss_defeated(boss_name: String)
signal nuts_changed(total: int)
signal item_unlocked(id: String)                           # weapon, gadget or upgrade id
signal collectible_found(kind: String, id: String)       # "washer", "page", "gripe" ...
signal cutscene_started(id: String)
signal cutscene_finished(id: String)
signal level_complete(level_id: String)

# ---- live scene references (set by main.gd) ----
var main: Node3D
var player: CharacterBody3D
var cam: Node3D
var combat: Node3D
var level: Node3D
var hud: CanvasLayer
var story: Node

## True while a cutscene or menu owns the screen: player input and bot AI should pause.
var input_locked := false

# ---- progress that is saved ----
var data := {
	"nuts": 0,
	"unlocked": {"arc_lancer": true},   # weapons / gadgets / upgrades owned
	"collected": {},                       # "<level>:<kind>:<id>": true
	"completed": {},                       # "<level>:<objective id>": true
	"level": "skyharbor",
	"checkpoint": -1,
}
const SAVE_PATH := "user://save.json"

func add_nuts(n: int) -> void:
	data.nuts = maxi(0, int(data.nuts) + n); nuts_changed.emit(data.nuts)

func spend_nuts(n: int) -> bool:
	if int(data.nuts) < n: return false
	add_nuts(-n); return true

func nuts() -> int:
	return int(data.nuts)

func unlock(id: String) -> void:
	if data.unlocked.get(id, false): return
	data.unlocked[id] = true; item_unlocked.emit(id); save()

func has(id: String) -> bool:
	return data.unlocked.get(id, false)

func collect(kind: String, id: String) -> bool:
	var key := "%s:%s:%s" % [data.level, kind, id]
	if data.collected.get(key, false): return false
	data.collected[key] = true; collectible_found.emit(kind, id); save(); return true

func is_collected(kind: String, id: String) -> bool:
	return data.collected.get("%s:%s:%s" % [data.level, kind, id], false)

func complete(objective_id: String) -> void:
	data.completed["%s:%s" % [data.level, objective_id]] = true
	objective_done.emit(objective_id)

func is_complete(objective_id: String) -> bool:
	return data.completed.get("%s:%s" % [data.level, objective_id], false)

func say(id: String, interrupt := false) -> float:
	return Snd.voice(id, interrupt)

func save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(data, "\t"))

func load_save() -> bool:
	if not FileAccess.file_exists(SAVE_PATH): return false
	var d = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if d is Dictionary:
		for k in d: data[k] = d[k]
		return true
	return false

func reset_save() -> void:
	if FileAccess.file_exists(SAVE_PATH): DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
