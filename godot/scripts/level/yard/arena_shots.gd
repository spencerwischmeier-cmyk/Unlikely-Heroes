extends Node
## Screenshot + fps tour of the Crane Bot arena (see areas/yz_arena.gd, --arena-shots=<prefix>).
## Positions are offsets from the arena's centre (x, z), so they follow the layout spread.

var prefix := ""
## [name, player offset (x, z), look-at offset (x, y, z), camera pitch]; "free" spots use a fixed camera
const SPOTS := [
	["wide", Vector2(-13, 13), Vector3(3, 0, -30), -0.16],
	["stands", Vector2(-10, -3), Vector3(28, 0, 0), -0.18],
	["gate", Vector2(13, -2), Vector3(-24, 0, 1), -0.16],
	["foundry", Vector2(2, -13), Vector3(0, 0, -40), -0.1],
	["over", Vector2(0, 14), Vector3(0, 0, -6), 0.0, true],
]
var only := []
var _i := -1
var _f := 0
var _ft := 0.0
var _fn := 0
var _fps := []
var _cam: Camera3D
var fast := false        # --arena-fast: fewer frames per spot (slow software renders in the cloud)

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--arena-only="): only = Array(a.substr(13).split(","))
		if a == "--arena-fast": fast = true

func _center() -> Vector3:
	var L = get_parent()
	var r: Rect2 = L.islands.get("arena", Rect2(-18, -152, 36, 30))
	var c := r.get_center()
	return Vector3(c.x, 0, c.y)

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
			print("[arena-shots] done, mean fps %.1f" % (tot / maxf(1.0, _fps.size())))
			get_tree().quit(); return
		_place(p, cam)
		return
	_aim(cam)
	if _f > (8 if fast else 40): _ft += dt; _fn += 1
	if _f == (22 if fast else 105):
		var fps := _fn / maxf(_ft, 0.001)
		_fps.append(fps)
		print("[arena-shots] %s fps %.1f" % [SPOTS[_i][0], fps])
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s_%s.png" % [prefix, SPOTS[_i][0]])

func _place(p, cam) -> void:
	var s: Array = SPOTS[_i]
	var c := _center()
	var pos := c + Vector3(s[1].x, 0.1, s[1].y)
	var tgt: Vector3 = c + s[2]
	var yaw := atan2(tgt.x - pos.x, tgt.z - pos.z)
	p.global_position = pos; p.velocity = Vector3.ZERO; p.face_yaw = yaw
	if s.size() > 4:
		if _cam == null:
			_cam = Camera3D.new(); _cam.fov = 60; get_parent().add_child(_cam)
		_cam.current = true
		_cam.global_position = c + Vector3(24, 15, 26)
		_cam.look_at(c + Vector3(0, 2, -6))
	else:
		if _cam: _cam.current = false
		if cam:
			cam.yaw = yaw; cam.pitch = s[3]; cam.global_position = pos + Vector3(0, 1.55, 0); cam.cam_y = pos.y
	set_meta("yaw", yaw)

func _aim(cam) -> void:
	if cam and SPOTS[_i].size() <= 4:
		cam.yaw = get_meta("yaw"); cam.pitch = SPOTS[_i][3]
