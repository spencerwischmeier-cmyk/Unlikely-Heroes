extends Node
## Debug: `-- --draw-audit[=radius]` (with --at=<spot>) counts what could draw around Vesk: every visible
## mesh/multimesh within its visibility range and `radius` (default 200 m), grouped by where it lives in the
## scene, by repeated mesh (MultiMesh candidates) and by shadow casting. Prints a report and quits.

func _ready() -> void:
	var on := false
	var radius := 200.0
	for a in OS.get_cmdline_user_args():
		if a == "--draw-audit": on = true
		elif a.begins_with("--draw-audit="): on = true; radius = float(a.substr(13))
	if not on: return
	await get_tree().create_timer(3.0).timeout
	# wait for the static batcher to finish so the counts match what the player sees
	for n in get_parent().get_children():
		if n.get_script() and String(n.get_script().resource_path).ends_with("zzz_batcher.gd"):
			var w := 0.0
			while not n.done and w < 60.0:
				await get_tree().create_timer(0.25).timeout; w += 0.25
	await get_tree().create_timer(0.5).timeout
	_audit(radius)
	get_tree().quit()

func _vis(n: Node3D) -> bool:
	while n:
		if not n.visible: return false
		var p := n.get_parent()
		n = p as Node3D
	return true

func _audit(radius: float) -> void:
	var cam: Vector3 = Game.player.global_position + Vector3(0, 1.6, 0)
	var by_area := {}
	var by_mesh := {}
	var total := 0
	var shadow := 0
	var objects := 0
	var mm_inst := 0
	for g in get_tree().root.find_children("*", "GeometryInstance3D", true, false):
		var gi := g as GeometryInstance3D
		if not (gi is MeshInstance3D or gi is MultiMeshInstance3D): continue
		if not _vis(gi): continue
		var ab := gi.global_transform * gi.get_aabb()
		var d := ab.get_center().distance_to(cam) - ab.size.length() * 0.5
		if d > radius: continue
		if gi.visibility_range_end > 0.0 and d > gi.visibility_range_end: continue
		var mesh: Mesh = (gi as MeshInstance3D).mesh if gi is MeshInstance3D else ((gi as MultiMeshInstance3D).multimesh.mesh if (gi as MultiMeshInstance3D).multimesh else null)
		if mesh == null: continue
		var surf := mesh.get_surface_count()
		objects += 1; total += surf
		if gi is MultiMeshInstance3D: mm_inst += (gi as MultiMeshInstance3D).multimesh.visible_instance_count if (gi as MultiMeshInstance3D).multimesh.visible_instance_count >= 0 else (gi as MultiMeshInstance3D).multimesh.instance_count
		if gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF: shadow += surf
		var path := String(gi.get_path())
		var parts := path.split("/")
		var key := "/".join(parts.slice(2, mini(6, parts.size() - 1)))
		by_area[key] = by_area.get(key, 0) + surf
		var mk := "%s %s" % [mesh.resource_path.get_file() if mesh.resource_path != "" else mesh.get_class(), str(mesh.get_instance_id()) if mesh.resource_path == "" else ""]
		if gi is MeshInstance3D: by_mesh[mk] = by_mesh.get(mk, 0) + 1
	# lights that can light this spot (within range + distance fade), and how many cast shadows
	var lights := 0
	var lshadow := 0
	for l in get_tree().root.find_children("*", "Light3D", true, false):
		if l is DirectionalLight3D or not _vis(l) or (l as Light3D).light_energy <= 0.0: continue
		var ld := (l as Node3D).global_position.distance_to(cam)
		var lim: float = (l as Light3D).distance_fade_begin + (l as Light3D).distance_fade_length if (l as Light3D).distance_fade_enabled else radius
		if ld > minf(lim, radius): continue
		lights += 1
		if (l as Light3D).shadow_enabled: lshadow += 1
	# shadow casters the sun's shadow map actually draws (within its max distance)
	var sun_d := 100.0
	for l in get_tree().root.find_children("*", "DirectionalLight3D", true, false): if (l as Light3D).shadow_enabled: sun_d = (l as DirectionalLight3D).directional_shadow_max_distance
	var near_shadow := 0
	for g in get_tree().root.find_children("*", "GeometryInstance3D", true, false):
		var gi := g as GeometryInstance3D
		if not (gi is MeshInstance3D or gi is MultiMeshInstance3D) or gi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF or not _vis(gi): continue
		var ab2 := gi.global_transform * gi.get_aabb()
		var d2 := ab2.get_center().distance_to(cam) - ab2.size.length() * 0.5
		if d2 > sun_d: continue
		if gi.visibility_range_end > 0.0 and d2 > gi.visibility_range_end: continue
		near_shadow += 1
	var parts_n := 0
	for g in get_tree().root.find_children("*", "GPUParticles3D", true, false) + get_tree().root.find_children("*", "CPUParticles3D", true, false):
		if _vis(g) and (g as Node3D).global_position.distance_to(cam) < radius: parts_n += 1
	print("[audit] lights %d (shadowed %d), sun-shadow casters within %.0f m: %d, particle systems %d" % [lights, lshadow, sun_d, near_shadow, parts_n])
	print("[audit] objects %d, surfaces %d (shadow-casting %d), multimesh instances %d, radius %.0f" % [objects, total, shadow, mm_inst, radius])
	var ak := by_area.keys(); ak.sort_custom(func(a, b): return by_area[a] > by_area[b])
	for k in ak.slice(0, 30): print("[audit] area %5d  %s" % [by_area[k], k])
	var mk2 := by_mesh.keys(); mk2.sort_custom(func(a, b): return by_mesh[a] > by_mesh[b])
	for k in mk2.slice(0, 25): print("[audit] repeated mesh x%-5d %s" % [by_mesh[k], k])
	# how many distinct meshes are used only a few times vs many
	var uniq := 0
	for k in by_mesh: if by_mesh[k] == 1: uniq += 1
	print("[audit] mesh instances using a unique mesh: %d of %d" % [uniq, by_mesh.values().reduce(func(a, b): return a + b, 0)])
