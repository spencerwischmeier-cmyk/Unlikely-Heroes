extends RefCounted
## Each area of Skyharbor can live in its own file in res://scripts/level/areas/<area>.gd so several people
## can work on different areas at once. An area file is a script with static functions, all optional:
##   static func build(L) -> void            # called after the base level and its zones are built
##   static func traversal_cases(moves: Dictionary) -> Dictionary   # extra --traverse cases
## Files run in name order. Keep each area's geometry inside its own region (see the README there).
##
## Area files named after an area (docks, gardens, junkyard, mast, plaza, terrace, yard) build at the area's
## original coordinates and are moved into place by the Spread pass (scripts/level/layout/spread.gd).
## Files starting with w_, x_, y_ or zz_ run after that, in final world coordinates.

const DIR := "res://scripts/level/areas/"
const Spread := preload("res://scripts/level/layout/spread.gd")
const GROUP := { docks = "docks", gardens = "west", junkyard = "junk", mast = "mast", plaza = "plaza", terrace = "west", yard = "yard" }
const LATE := ["w_", "x_", "y_", "zz_", "zzz_"]

static func files() -> Array:
	var out := []
	for f in DirAccess.get_files_at(DIR):
		if f.ends_with(".gd"): out.append(DIR + f)
	out.sort()
	return out

static func is_late(f: String) -> bool:
	var n := f.get_file()
	for p in LATE:
		if n.begins_with(p): return true
	return false

static func build_all(L: Node3D) -> void:
	for f in files():
		if is_late(f): continue
		var sc: Script = load(f)
		if not sc.has_method("build"): continue
		Spread.begin(L, GROUP.get(f.get_file().get_basename(), "plaza"))
		sc.build(L)
		Spread.end(L)
	Spread.apply(L)
	for f in files():
		if not is_late(f): continue
		var sc: Script = load(f)
		if sc.has_method("build"): sc.build(L)
