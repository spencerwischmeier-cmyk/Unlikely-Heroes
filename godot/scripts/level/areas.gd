extends RefCounted
## Each area of Skyharbor can live in its own file in res://scripts/level/areas/<area>.gd so several people
## can work on different areas at once. An area file is a script with static functions, all optional:
##   static func build(L) -> void            # called after the base level and its zones are built
##   static func traversal_cases(moves: Dictionary) -> Dictionary   # extra --traverse cases
## Files run in name order. Keep each area's geometry inside its own region (see the README there).

const DIR := "res://scripts/level/areas/"

static func files() -> Array:
	var out := []
	for f in DirAccess.get_files_at(DIR):
		if f.ends_with(".gd"): out.append(DIR + f)
	out.sort()
	return out

static func build_all(L: Node3D) -> void:
	for f in files():
		var sc: Script = load(f)
		if sc.has_method("build"): sc.build(L)
