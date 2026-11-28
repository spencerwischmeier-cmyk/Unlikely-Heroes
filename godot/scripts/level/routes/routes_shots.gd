extends Node
## Screenshot + fps tour of the routes between the areas (see areas/w_routes_look.gd,
## --routes-shots=<prefix>). Positions are final world coordinates. Works with --no-routes-look too, for "before".

var prefix := ""
## [name, player position, look-at point, camera pitch]; a 5th element = a free camera at that position
const SPOTS := [
	["halt", Vector3(2.0, 0.1, 110.0), Vector3(-1, 2.5, 92), -0.05],
	["viaduct", Vector3(1.5, 0.1, 91.0), Vector3(0, 1.5, 60), -0.08],
	["viaduct_gap", Vector3(0.5, 0.1, 75.5), Vector3(0, -2, 58), -0.22],
	["viaduct_side", Vector3(0, 0.1, 80.0), Vector3(0, -4, 68), 0.0, Vector3(22, 9, 86)],
	["viaduct_plaza", Vector3(0.0, 0.1, 50.0), Vector3(0, 1, 75), -0.05],
	["lantern", Vector3(-23.5, 0.1, 33.0), Vector3(-58, 1.5, 33), -0.06],
	["lantern_side", Vector3(-40, 0.1, 33.0), Vector3(-40, 0, 33), 0.0, Vector3(-36, 8, 52)],
	["gangway", Vector3(23.5, 0.1, 30.0), Vector3(58, 1.5, 30), -0.06],
	["approach", Vector3(-6.0, 0.1, 6.0), Vector3(-6, 1.5, -20), -0.06],
	["haul_span", Vector3(-6.0, 0.1, -40.0), Vector3(-5, 1.5, -80), -0.06],
	["liftbridge", Vector3(-6.0, 0.1, -74.0), Vector3(-3, 1.5, -100), -0.06],
	["approach_side", Vector3(-6, 0.1, -50.0), Vector3(-6, -2, -45), 0.0, Vector3(-30, 10, -30)],
	["cableway", Vector3(-27.0, 6.7, -40.0), Vector3(4, 7, -53), -0.05],
	["barge", Vector3(59.0, 3.1, -34.0), Vector3(36, 3.5, -48), -0.05],
	["dish_rail", Vector3(20.0, 20.1, -48.5), Vector3(4, 3, -92), 0.0, Vector3(24, 24, -44)],
	["cable_side", Vector3(-27.0, 6.7, -40.0), Vector3(-10, 6, -47), 0.0, Vector3(-14, 13, -24)],
	["barge_side", Vector3(59.0, 3.1, -34.0), Vector3(56, 5, -36), 0.0, Vector3(74, 11, -16)],
	["barge_wide", Vector3(59.0, 3.1, -34.0), Vector3(55, 10, -36), 0.0, Vector3(84, 12, -6)],
	["cable_station", Vector3(-27.0, 6.7, -40.0), Vector3(-25, 9, -40), 0.0, Vector3(-40, 13, -50)],
	["dish_side", Vector3(20.0, 20.1, -48.5), Vector3(10, 8, -76), 0.0, Vector3(34, 15, -88)],
	["viaduct_masts", Vector3(1.5, 0.1, 91.0), Vector3(0, 3.5, 66), -0.02],
]
var only := []
var _i := -1
var _f := 0
var _ft := 0.0
var _fn := 0
var _fps := []
var _cam: Camera3D
var fast := false

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--routes-only="): only = Array(a.substr(14).split(","))
		if a == "--routes-fast": fast = true

func _process(dt: float) -> void:
	var game := get_tree().root.get_node_or_null("Game")
	if game == null or game.get("player") == null: return
	var p = game.player
	var cam = game.get("cam")
	_f += 1
	var fw := 20 if fast else 90
	var fe := 24 if fast else 110
	if _i < 0 and _f < fw: return
	if _i < 0 or _f > fe:
		_i += 1; _f = 0; _ft = 0.0; _fn = 0
		while _i < SPOTS.size() and not only.is_empty() and not only.has(SPOTS[_i][0]): _i += 1
		if _i >= SPOTS.size():
			var tot := 0.0
			for v in _fps: tot += v
			print("[routes-shots] done, mean fps %.1f" % (tot / maxf(1.0, _fps.size())))
			get_tree().quit(); return
		_place(p, cam)
		return
	_aim(cam)
	if _f > (8 if fast else 40): _ft += dt; _fn += 1
	if _f == (22 if fast else 105):
		var fps := _fn / maxf(_ft, 0.001)
		_fps.append(fps)
		print("[routes-shots] %s fps %.1f" % [SPOTS[_i][0], fps])
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s_%s.png" % [prefix, SPOTS[_i][0]])

func _place(p, cam) -> void:
	var s: Array = SPOTS[_i]
	var pos: Vector3 = s[1]
	var tgt: Vector3 = s[2]
	var yaw := atan2(tgt.x - pos.x, tgt.z - pos.z)
	p.global_position = pos; p.velocity = Vector3.ZERO; p.face_yaw = yaw
	if s.size() > 4:
		if _cam == null:
			_cam = Camera3D.new(); _cam.fov = 55; get_parent().add_child(_cam)
		_cam.current = true
		_cam.global_position = s[4]
		_cam.look_at(tgt)
	else:
		if _cam: _cam.current = false
		if cam:
			cam.yaw = yaw; cam.pitch = s[3]; cam.global_position = pos + Vector3(0, 1.55, 0); cam.cam_y = pos.y
	set_meta("yaw", yaw)

func _aim(cam) -> void:
	if cam and SPOTS[_i].size() <= 4:
		cam.yaw = get_meta("yaw"); cam.pitch = SPOTS[_i][3]
