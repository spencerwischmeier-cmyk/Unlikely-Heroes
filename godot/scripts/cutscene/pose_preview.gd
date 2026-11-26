extends SceneTree
## Vesk body clip contact sheet (no level): frames of one clip at given times, plus an acting beat.
##   xvfb-run -a godot --path . --rendering-driver vulkan --resolution 400x400 -s res://scripts/cutscene/pose_preview.gd -- \
##       --out=/abs/sheet.png --clip=cs_sit_drink --times=0,0.5,1,1.5 [--act=sip] [--yaw=0.5] [--mug]

const VeskActor := preload("res://scripts/cutscene/vesk_actor.gd")
var out := "/tmp/pose_sheet.png"
var clip := "cs_sit"
var act := ""
var times: Array = [0.0, 0.5, 1.0, 1.5, 2.0, 2.5]
var yaw := 0.5
var mug := false
var vesk: Node3D
var n := 0
var idx := 0
var shots: Array = []
var clock := 0.0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
		elif a.begins_with("--clip="): clip = a.substr(7)
		elif a.begins_with("--act="): act = a.substr(6)
		elif a.begins_with("--times="): times = Array(a.substr(8).split(",")).map(func(x): return float(x))
		elif a.begins_with("--yaw="): yaw = float(a.substr(6))
		elif a == "--mug": mug = true
	var r := Node3D.new(); root.add_child(r)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR; env.background_color = Color(0.3, 0.36, 0.45)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.ambient_light_color = Color(0.55, 0.65, 0.85); env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new(); we.environment = env; r.add_child(we)
	var sun := DirectionalLight3D.new(); sun.light_color = Color(1, 0.85, 0.65); sun.light_energy = 1.6; sun.shadow_enabled = true
	sun.rotation = Vector3(-0.6, -0.5, 0); r.add_child(sun)
	var fl := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(10, 10); fl.mesh = pm; r.add_child(fl)
	var box := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = Vector3(0.6, 0.5, 0.55); box.mesh = bm; box.position = Vector3(0, 0.25, -0.12); r.add_child(box)
	vesk = VeskActor.new(); r.add_child(vesk)
	var cam := Camera3D.new(); cam.fov = 38; r.add_child(cam)
	var c := Vector3(0, 0.9, 0)
	var cp := c + Vector3(sin(yaw) * 3.0, 0.5, cos(yaw) * 3.0)
	cam.transform = Transform3D(Basis.looking_at(c - cp), cp)

func _process(dt: float) -> bool:
	n += 1
	if n == 2:
		if clip.contains("@"): vesk.hold(clip.split("@")[0], float(clip.split("@")[1]), 0.0)
		else: vesk.play(clip, 0.0)
		vesk.hold_mug(mug)
		if act == "sip": print("sip len ", vesk.sip())
		elif act != "": vesk.call("act", act)
	if n < 3: return false
	clock += 1.0 / 30.0
	if idx < times.size() and clock >= float(times[idx]):
		shots.append(root.get_viewport().get_texture().get_image()); idx += 1
	if idx >= times.size():
		var s0: Image = shots[0]; var w := s0.get_width(); var h := s0.get_height()
		var cols := mini(4, shots.size()); var rows := int(ceil(shots.size() / float(cols)))
		var sheet := Image.create(w * cols, h * rows, false, s0.get_format())
		for i in shots.size(): sheet.blit_rect(shots[i], Rect2i(0, 0, w, h), Vector2i((i % cols) * w, (i / cols) * h))
		sheet.save_png(out); print("saved ", out); return true
	return false
