extends Node
## Test helper. Run with `-- --shot=out.png --frames=90` to save a screenshot after N frames and quit.
## `--script=name` runs a scripted input scenario from scripts/test_scenarios.gd.

var path := ""
var frames := 0
var scenario := ""
var _n := 0
var side_cam := false
var _dbg: Camera3D

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="): path = a.substr(7)
		elif a.begins_with("--frames="): frames = int(a.substr(9))
		elif a.begins_with("--scenario="): scenario = a.substr(11)
		elif a == "--side": side_cam = true
	process_priority = 1000
	process_mode = Node.PROCESS_MODE_ALWAYS   # keeps counting frames while the game is paused (pause menu shots)

func _process(_dt: float) -> void:
	if path == "" and scenario == "": return
	_n += 1
	match scenario:
		"run":
			if _n == 10: Input.action_press("move_forward")
		"turn":
			if _n == 10: Input.action_press("move_forward")
			if _n == 40: Input.action_press("move_right")
		"jump":
			if _n == 10: Input.action_press("move_forward")
			if _n == 30: Input.action_press("jump")
		"aim":
			if _n == 10: Input.action_press("fire")
	if side_cam and _n >= frames - 2:
		var pl = get_tree().current_scene.get_node_or_null("Vesk")
		if pl:
			if _dbg == null:
				_dbg = Camera3D.new(); _dbg.fov = 35; get_tree().current_scene.add_child(_dbg)
			var f := Vector3(sin(pl.face_yaw), 0, cos(pl.face_yaw))
			var r := Vector3(-f.z, 0, f.x)
			_dbg.global_position = pl.global_position + r * 3.2 + f * 0.6 + Vector3(0, 1.0, 0)
			_dbg.look_at(pl.global_position + Vector3(0, 0.8, 0))
			_dbg.current = true
	if path != "" and _n == frames:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(path)
		print("saved ", path)
		get_tree().quit()
