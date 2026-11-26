extends SceneTree
## Vesk face rig contact sheet in the game renderer (no level):
##   xvfb-run -a godot --path . --rendering-driver vulkan --resolution 640x640 -s res://scripts/cutscene/face_preview.gd -- \
##       --out=/abs/sheet.png --poses="neutral:X;angry:D;smug:B;content:A" [--yaw=0.3] [--look=1,0.2]
## Each pose is mood:mouth-shape (Rhubarb A-H, X). Golden-hour key, blue fill, warm rim.

const VeskActor := preload("res://scripts/cutscene/vesk_actor.gd")
var out := "/tmp/face_sheet.png"
var poses: Array = ["neutral:X", "content:X", "angry:D", "smug:B"]
var yaw := 0.35
var look := Vector2(0.6, 0.0)
var vesk: Node3D
var cam: Camera3D
var n := 0
var idx := 0
var shots: Array = []

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
		elif a.begins_with("--poses="): poses = a.substr(8).split(";")
		elif a.begins_with("--yaw="): yaw = float(a.substr(6))
		elif a.begins_with("--look="):
			var p := a.substr(7).split(","); look = Vector2(float(p[0]), float(p[1]))
	var r := Node3D.new(); root.add_child(r)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR; env.background_color = Color(0.3, 0.36, 0.45)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.ambient_light_color = Color(0.55, 0.65, 0.85); env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_AGX; env.glow_enabled = true
	var we := WorldEnvironment.new(); we.environment = env; r.add_child(we)
	var sun := DirectionalLight3D.new(); sun.light_color = Color(1, 0.82, 0.6); sun.light_energy = 1.7; sun.shadow_enabled = true
	sun.rotation = Vector3(-0.5, -0.6, 0); r.add_child(sun)
	var rim := DirectionalLight3D.new(); rim.light_color = Color(1.0, 0.7, 0.45); rim.light_energy = 1.4
	rim.rotation = Vector3(-0.3, 2.6, 0); r.add_child(rim)
	vesk = VeskActor.new(); r.add_child(vesk)
	cam = Camera3D.new(); cam.fov = 22; r.add_child(cam)
	var face := Vector3(0, 1.42, 0.25) if not OS.get_cmdline_user_args().has("--wide") else Vector3(0, 1.0, 0.1)
	var dir := Vector3(sin(PI + yaw), 0.05, cos(PI + yaw)) * -1.0
	var dist := 1.0 if not OS.get_cmdline_user_args().has("--wide") else 4.5
	var cp := face + Vector3(sin(yaw) * dist, 0.04, dist * cos(yaw))
	cam.transform = Transform3D(Basis.looking_at(face - cp), cp)
	var tgt := Node3D.new(); r.add_child(tgt)
	tgt.position = cam.position + cam.transform.basis.x * look.x + cam.transform.basis.y * look.y
	vesk.look_target = tgt

func _set_pose(p: String) -> void:
	var parts := p.split(":")
	vesk.mood(parts[0], 0.01)
	vesk.force_viseme = parts[1] if parts.size() > 1 else "X"
	vesk.blink_in = 99.0
	if parts.size() > 2 and parts[2] == "blink": vesk.blink_t = 0.06; vesk.blink_in = 99.0

func _process(_dt: float) -> bool:
	n += 1
	if n == 2:
		vesk.play("idle"); _set_pose(poses[0])
		print("face keys ", vesk.bs, " jaw ", vesk.jaw_i, " eye ", vesk.eye_i, " face mi ", vesk.face_mi)
		for mi in vesk.find_children("*", "MeshInstance3D", true, false): print("  mesh ", mi.name, " skin ", mi.skin != null, " surfaces ", mi.mesh.get_surface_count())
	if n > 2 and (n - 2) % 25 == 0:
		if poses[idx].ends_with(":blink"): vesk.blink_t = 0.065
		shots.append(root.get_viewport().get_texture().get_image())
		idx += 1
		if idx >= poses.size():
			var s0: Image = shots[0]; var w := s0.get_width(); var h := s0.get_height()
			var cols := mini(3, shots.size()); var rows := int(ceil(shots.size() / float(cols)))
			var sheet := Image.create(w * cols, h * rows, false, s0.get_format())
			for i in shots.size(): sheet.blit_rect(shots[i], Rect2i(0, 0, w, h), Vector2i((i % cols) * w, (i / cols) * h))
			sheet.save_png(out); print("saved ", out)
			quit()
			return true
		_set_pose(poses[idx])
	return false
