extends RefCounted
## The Crane Bot arena look pass (late file: runs after the per-area floors, in final coordinates).
## Pushes the boss stage toward the high-end Junkyard look target: smoky golden-hour grade, weathered
## paint-over-steel materials, real smoke columns and fire, scrap dressing around the stage.
##   --no-arena-look     keep the arena as it was (for before/after shots)
##   --arena-shots=<p>   visit a few arena viewpoints, save <p>_<spot>.png with the fps, then quit
##                       (--arena-only=a,b to pick spots)

const Look := preload("res://scripts/level/yard/arena_look.gd")
const Shots := preload("res://scripts/level/yard/arena_shots.gd")

static func build(L) -> void:
	if not L.islands.has("arena"): return
	var args := OS.get_cmdline_user_args()
	if not args.has("--no-arena-look"):
		Look.build(L)
	for a in args:
		if a.begins_with("--arena-shots="):
			var s: Node = Shots.new(); s.prefix = a.substr(14); s.name = "ArenaShots"
			L.add_child(s)
