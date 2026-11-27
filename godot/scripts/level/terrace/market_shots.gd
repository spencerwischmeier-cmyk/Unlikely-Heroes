extends Node
## Screenshot + fps tour of the Market Terrace and the Spice Bazaar (see areas/w_market.gd,
## --market-shots=<prefix>). Positions are final world coordinates. Works with --no-market too, for "before".

var prefix := ""
## [name, player position, look-at point, camera pitch]; a 5th element = a free camera at that position
const SPOTS := [
	["entrance", Vector3(-55.5, 0.1, 33.0), Vector3(-90, 0, 37), -0.08],
	["houses", Vector3(-70.5, 0.1, 33.0), Vector3(-68, 3.0, 22), 0.14],
	["lane", Vector3(-60.0, 0.1, 46.0), Vector3(-80, 0, 44), -0.08],
	["bazaar", Vector3(-80.5, 0.1, 37.0), Vector3(-104, 0, 46), -0.1],
	["bazaar_south", Vector3(-106.0, 0.1, 49.0), Vector3(-84, 0, 40), -0.1],
	["over", Vector3(-70.0, 0.1, 34.0), Vector3(-84, 0, 38), 0.0, Vector3(-48, 24, 66)],
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
		if a.begins_with("--market-only="): only = Array(a.substr(14).split(","))
		if a == "--market-fast": fast = true

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
			print("[market-shots] done, mean fps %.1f" % (tot / maxf(1.0, _fps.size())))
			get_tree().quit(); return
		_place(p, cam)
		return
	_aim(cam)
	if _f > (8 if fast else 40): _ft += dt; _fn += 1
	if _f == (22 if fast else 105):
		var fps := _fn / maxf(_ft, 0.001)
		_fps.append(fps)
		print("[market-shots] %s fps %.1f" % [SPOTS[_i][0], fps])
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
