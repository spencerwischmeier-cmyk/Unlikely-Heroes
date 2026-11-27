extends Node
## Screenshot + fps tour of the Roof Gardens (see areas/y_gardens_look.gd, --gardens-shots=<prefix>).
## Positions are final world coordinates (the gardens sit in the "west" spread group).

var prefix := ""
## [name, player position, look-at point, camera pitch]
const SPOTS := [
	["lawn", Vector3(-52.5, 8.9, -3.5), Vector3(-68, 9.5, -1), -0.12],
	["arch", Vector3(-53.0, 8.9, -17.0), Vector3(-64, 10, -6), -0.1],
	["promenade", Vector3(-53.0, 8.9, -14.5), Vector3(-53, 9.5, -38), -0.08],
	["dome", Vector3(-58.5, 8.9, -37.5), Vector3(-71.5, 10, -43), -0.08],
	["tree", Vector3(-77.0, 8.9, -41.0), Vector3(-90.8, 15, -43), 0.22],
	["crown", Vector3(-89.0, 18.9, -41.6), Vector3(-66, 10, -14), -0.22],
	["grove", Vector3(-70.0, 10.1, -57.0), Vector3(-69, 11, -67), -0.1],
	["orchard", Vector3(-60.5, 10.1, -66.5), Vector3(-57, 10.5, -59), -0.1],
	["falls", Vector3(-65.5, 8.9, -2.5), Vector3(-74, 6.0, 1.5), -0.28],
	["pond", Vector3(-68.2, 8.9, -41.6), Vector3(-71.5, 9.2, -43.4), -0.3],
	["arches", Vector3(-53.0, 8.9, -38.5), Vector3(-53, 11.0, -14), 0.05],
	["koi", Vector3(-73.6, 8.9, -45.0), Vector3(-71.5, 9.0, -43.0), -0.6],
	["channel", Vector3(-66.8, 8.9, -12.5), Vector3(-69.25, 9.0, -2.0), -0.4],
]
var only := []
var _i := -1
var _f := 0
var _ft := 0.0
var _fn := 0
var _fps := []
var fast := false

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--gardens-only="): only = Array(a.substr(15).split(","))
		if a == "--gardens-fast": fast = true

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
			print("[gardens-shots] done, mean fps %.1f" % (tot / maxf(1.0, _fps.size())))
			get_tree().quit(); return
		_place(p, cam)
		return
	_aim(cam)
	if _f > (8 if fast else 40): _ft += dt; _fn += 1
	if _f == (22 if fast else 105):
		var fps := _fn / maxf(_ft, 0.001)
		_fps.append(fps)
		print("[gardens-shots] %s fps %.1f" % [SPOTS[_i][0], fps])
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s_%s.png" % [prefix, SPOTS[_i][0]])

func _place(p, cam) -> void:
	var s: Array = SPOTS[_i]
	var pos: Vector3 = s[1]
	var tgt: Vector3 = s[2]
	var yaw := atan2(tgt.x - pos.x, tgt.z - pos.z)
	p.global_position = pos; p.velocity = Vector3.ZERO; p.face_yaw = yaw
	if cam:
		cam.yaw = yaw; cam.pitch = s[3]; cam.global_position = pos + Vector3(0, 1.55, 0); cam.cam_y = pos.y
	set_meta("yaw", yaw)

func _aim(cam) -> void:
	if cam:
		cam.yaw = get_meta("yaw"); cam.pitch = SPOTS[_i][3]
