extends RefCounted
## The Roof Gardens look pass (late file: runs after the layout spread, in final coordinates).
## Pushes the gardens toward the high-end look-target renders: leaf-card foliage, grass, weathered wood,
## stone and bark, waterfall mist, pollen in the light shafts, and the city's panic (smoke columns, ash,
## a downed sky car, a burning hedge). See scripts/level/gardens/gardens_look.gd.
##   --no-gardens-look     keep the gardens as they were (for before/after shots)
##   --gardens-shots=<p>   visit a few garden viewpoints, save <p>_<spot>.png with the fps, then quit
##                         (--gardens-only=a,b to pick spots, --gardens-fast for slow renderers)

const Look := preload("res://scripts/level/gardens/gardens_look.gd")
const Shots := preload("res://scripts/level/gardens/gardens_shots.gd")

static func build(L) -> void:
	if not L.has_meta("garden_kit"): return
	var args := OS.get_cmdline_user_args()
	if Look.on():
		Look.build(L)
	for a in args:
		if a.begins_with("--gardens-shots="):
			var s: Node = Shots.new(); s.prefix = a.substr(16); s.name = "GardensShots"
			L.add_child(s)
