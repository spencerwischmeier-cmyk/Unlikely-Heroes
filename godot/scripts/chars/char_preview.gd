extends SceneTree
## Character turntable shots in the game renderer, without loading the level (fast).
##   xvfb-run -a godot --path . --rendering-driver vulkan --resolution 960x540 -s res://scripts/chars/char_preview.gd -- \
##       --out=/abs/shot.png --set=bots|gizmart|dodger|grudd|crane [--frames=40]
## Lights the set like Skyharbor at golden hour (warm low sun, blue sky fill).

var out := "/tmp/char_preview.png"
var which := "bots"
var frames := 40
var n := 0
var root3: Node3D
var actors: Array = []

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
		elif a.begins_with("--set="): which = a.substr(6)
		elif a.begins_with("--frames="): frames = int(a.substr(9))
	root3 = Node3D.new(); root.add_child(root3)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR; env.background_color = Color(0.55, 0.68, 0.82)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.ambient_light_color = Color(0.6, 0.7, 0.85); env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_AGX; env.glow_enabled = true
	var we := WorldEnvironment.new(); we.environment = env; root3.add_child(we)
	var sun := DirectionalLight3D.new(); sun.light_color = Color(1, 0.84, 0.62); sun.light_energy = 1.6; sun.shadow_enabled = true
	sun.rotation = Vector3(-0.6, 0.7, 0); root3.add_child(sun)
	var floor_ := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(40, 40); floor_.mesh = pm
	var fm := StandardMaterial3D.new(); fm.albedo_color = Color(0.62, 0.58, 0.52); floor_.material_override = fm; root3.add_child(floor_)
	var cam := Camera3D.new(); cam.fov = 40; root3.add_child(cam)
	match which:
		"bots":
			_add_model("res://models/roller.glb", Vector3(-2.4, 0, 0))
			_add_model("res://models/crew_roller.glb", Vector3(-0.8, 0, 0))
			_add_model("res://models/hornet.glb", Vector3(0.9, 1.3, 0))
			_add_model("res://models/crew_barricade.glb", Vector3(2.9, 0, -0.4))
			_aim(cam, Vector3(0.2, 1.7, 7.2), Vector3(0.2, 0.8, 0))
		"gizmart":
			var g: Node3D = load("res://scripts/chars/gizmart_actor.gd").new(); root3.add_child(g)
			g.rotation.y = 0.35
			actors.append(g)
			_aim(cam, Vector3(0.3, 2.2, 4.6), Vector3(0.1, 1.7, 0))
		"dodger":
			for i in 3:
				var d: Node3D = load("res://scripts/cutscene/drone_actor.gd").new(); root3.add_child(d)
				d.position = Vector3((i - 1) * 0.9, 1.0, 0); d.rotation.y = 0.25
				actors.append(d)
			_aim(cam, Vector3(0, 1.15, 2.0), Vector3(0, 1.0, 0))
		"grudd":
			var m := _add_model("res://models/chars/grudd.glb", Vector3.ZERO)
			var ap := m.find_child("AnimationPlayer", true, false) as AnimationPlayer
			if ap and ap.has_animation("talk"): ap.play("talk")
			_aim(cam, Vector3(1.5, 2.6, 7.5), Vector3(0, 2.0, 0))
		"crane":
			var c: Node3D = load("res://scripts/cranebot.gd").new(); root3.add_child(c)
			actors.append(c)
			_aim(cam, Vector3(7, 5, 11), Vector3(0, 2.5, 0))

func _aim(cam: Camera3D, pos: Vector3, at: Vector3) -> void:
	cam.transform = Transform3D(Basis.looking_at(at - pos), pos)

func _add_model(path: String, pos: Vector3) -> Node3D:
	var m: Node3D = load(path).instantiate(); root3.add_child(m); m.position = pos
	return m

func _process(_dt: float) -> bool:
	n += 1
	if which == "dodger" and n == 5:
		var moods := ["happy", "angry", "sad"]
		for i in actors.size(): if actors[i].has_method("emote"): actors[i].emote(moods[i], 99.0)
	if which == "crane" and n == 3:
		var c: Node3D = actors[0]
		c.visible = true; c.magnet.visible = true
		c.boom.rotation.x = -0.5; c.turn.rotation.y = 0.5
		c.magnet.global_position = c.tip.global_position + Vector3(0, -1.6, 0)
	if which == "gizmart" and n == 5 and actors.size() > 0: actors[0].mood("hello", 99.0)
	if n == frames:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(out)
		print("saved ", out)
		return true
	return false
