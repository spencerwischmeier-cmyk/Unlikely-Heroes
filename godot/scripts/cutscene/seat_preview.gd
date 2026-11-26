extends SceneTree
## Vesk seated on the porch chair (no level): side and front views plus seat/bone heights, for fitting sit_off.
##   xvfb-run -a godot --path . --rendering-driver vulkan --resolution 480x480 -s res://scripts/cutscene/seat_preview.gd -- \
##       --out=/abs/seat --off=0,0.33,0.2 [--at=2.6] [--clip=cs_sit_drink] [--look=x,y,z]

const VeskActor := preload("res://scripts/cutscene/vesk_actor.gd")
const Kit := preload("res://scripts/kit.gd")
var out := "/tmp/seat"
var off := Vector3(0, 0.52, 0.12)
var at := 2.6
var clip := "cs_sit_drink"
var vesk: Node3D
var cam: Camera3D
var n := 0
var views := [PI * 0.5, PI, PI * 0.75]
var look := Vector3.INF
var cus := []   # close-ups: [az, dist, mm] framed from the head like scene_intro._cu

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
		elif a.begins_with("--off="):
			var p := a.substr(6).split(","); off = Vector3(float(p[0]), float(p[1]), float(p[2]))
		elif a.begins_with("--at="): at = float(a.substr(5))
		elif a.begins_with("--cu="):
			for c in a.substr(5).split(";"):
				var q := c.split(","); cus.append([float(q[0]), float(q[1]), float(q[2])])
		elif a.begins_with("--look="):
			var q := a.substr(7).split(","); look = Vector3(float(q[0]), float(q[1]), float(q[2]))
		elif a.begins_with("--clip="): clip = a.substr(7)
	var r := Node3D.new(); root.add_child(r)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR; env.background_color = Color(0.3, 0.36, 0.45)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.ambient_light_color = Color(0.6, 0.65, 0.8); env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new(); we.environment = env; r.add_child(we)
	var sun := DirectionalLight3D.new(); sun.light_energy = 1.4; sun.rotation = Vector3(-0.7, 0.4, 0); r.add_child(sun)
	var chair := Kit.place(r, "porch_chair", Vector3.ZERO, PI, 1.0, false)
	# seat top: highest chair vertex near the middle, below the backrest
	var top := -1.0
	for mi in chair.find_children("*", "MeshInstance3D", true, false):
		var xf: Transform3D = (mi as MeshInstance3D).global_transform if mi.is_inside_tree() else Transform3D()
		var m: Mesh = mi.mesh
		for s in m.get_surface_count():
			for v in m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				var w: Vector3 = xf * v
				if absf(w.x) < 0.15 and absf(w.z) < 0.15 and w.y < 0.8: top = maxf(top, w.y)
	print("[seat] chair seat top y=%.3f" % top)
	vesk = VeskActor.new(); r.add_child(vesk)
	vesk.position = off; vesk.rotation.y = PI
	cam = Camera3D.new(); cam.fov = 40; r.add_child(cam)

func _process(_dt: float) -> bool:
	n += 1
	if n == 3:
		vesk.hold(clip, at, 0.0)
		if look != Vector3.INF:
			vesk.look_point = look
			var b := MeshInstance3D.new(); var sm := SphereMesh.new(); sm.radius = 0.12; sm.height = 0.24; b.mesh = sm; b.position = look; vesk.get_parent().add_child(b)
	if n == 40:
		var sk: Skeleton3D = vesk.find_children("*", "Skeleton3D", true, false)[0]
		for i in sk.get_bone_count():
			var nm := sk.get_bone_name(i).to_lower()
			if nm.contains("hip") or nm.contains("pelvis") or nm.contains("thigh") or nm.contains("upleg") or nm.contains("head") or nm.contains("neck") or nm.contains("spine"):
				print("[seat] bone %s y=%.3f z=%.3f" % [sk.get_bone_name(i), (sk.global_transform * sk.get_bone_global_pose(i)).origin.y, (sk.global_transform * sk.get_bone_global_pose(i)).origin.z])
	var vi := n - 42
	if vi >= 0 and vi % 4 == 0:
		var k := vi / 4
		if k >= views.size() + cus.size(): quit(); return true
		if k < views.size():
			var y: float = views[k]
			cam.fov = 40
			cam.position = Vector3(sin(y) * 3.2, 0.9, cos(y) * 3.2); cam.look_at(Vector3(0, 0.75, 0))
		else:
			var c: Array = cus[k - views.size()]
			var e: Vector3 = vesk.head_node().global_position
			var f := Vector3(sin(vesk.rotation.y), 0, cos(vesk.rotation.y)).rotated(Vector3.UP, deg_to_rad(c[0]))
			cam.fov = rad_to_deg(2.0 * atan(12.0 / c[2]))
			cam.position = e + f * c[1]; cam.look_at(e + Vector3(0, -0.04, 0))
	if vi >= 0 and vi % 4 == 3:
		root.get_viewport().get_texture().get_image().save_png("%s_%d.png" % [out, vi / 4])
	return false
