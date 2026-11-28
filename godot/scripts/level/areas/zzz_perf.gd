extends RefCounted
## Draw-distance pass: with the areas spread out, most of the level is far away at any moment. Small pieces
## (props, rails' bolts, railings, clutter) stop drawing past a distance that depends on their size, so the
## GPU only spends time on what Vesk can actually make out. Big things (islands, buildings, the sky city)
## are untouched. Named zzz_ so it runs last, after the panic and the ground pass. `--no-cull` turns it off.

static func build(L) -> void:
	if OS.get_cmdline_user_args().has("--no-cull"): return
	var n := 0
	for g in L.find_children("*", "GeometryInstance3D", true, false):
		var gi := g as GeometryInstance3D
		if gi.visibility_range_end > 0.0: continue
		if gi is GPUParticles3D or gi is CPUParticles3D or gi is Label3D: continue
		if _in_sky(gi, L): continue
		var ab := gi.get_aabb()
		var big := maxf(ab.size.x * gi.global_transform.basis.get_scale().x, maxf(ab.size.y * gi.global_transform.basis.get_scale().y, ab.size.z * gi.global_transform.basis.get_scale().z))
		var end := 0.0
		if big < 0.8: end = 55.0
		elif big < 2.5: end = 90.0
		elif big < 6.0: end = 150.0
		else: continue
		gi.visibility_range_end = end
		gi.visibility_range_end_margin = 6.0
		n += 1
	if OS.get_cmdline_user_args().has("--scatter-log"): print("[perf] draw distance set on %d pieces" % n)
	_particles(L)

## Smoke, sparks, embers and dust far off: each system is still a draw (and a GPU update pass). Small ones
## stop drawing past 140 m, mid-sized ones past 260 m; tall plumes (12 m and up) are landmarks and stay.
## `--no-particle-cull` turns it off. (The web/phone builds shorten these further in systems/mobile_quality.gd.)
static func _particles(L) -> void:
	if OS.get_cmdline_user_args().has("--no-particle-cull"): return
	for g in L.find_children("*", "GeometryInstance3D", true, false):
		if not (g is GPUParticles3D or g is CPUParticles3D): continue
		var gi := g as GeometryInstance3D
		if gi.visibility_range_end > 0.0 or _in_sky(gi, L): continue
		var ab := gi.get_aabb()
		var sc := gi.global_transform.basis.get_scale()
		var big := maxf(ab.size.x * sc.x, maxf(ab.size.y * sc.y, ab.size.z * sc.z))
		if big >= 12.0: continue
		gi.visibility_range_end = 140.0 if big < 5.0 else 260.0
		gi.visibility_range_end_margin = 8.0

static func _in_sky(n: Node, L: Node) -> bool:
	var p := n.get_parent()
	while p and p != L:
		if p.name == "SkyWorld": return true
		p = p.get_parent()
	return false
