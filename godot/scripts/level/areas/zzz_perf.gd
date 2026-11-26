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

static func _in_sky(n: Node, L: Node) -> bool:
	var p := n.get_parent()
	while p and p != L:
		if p.name == "SkyWorld": return true
		p = p.get_parent()
	return false
