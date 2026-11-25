extends Node3D
## Third-person camera: over Vesk's shoulder, trails a little behind his movement, pulls in
## in front of walls, and eases in behind him while you run with a controller.

var target: Node3D
var yaw := PI
var pitch := -0.08
var shoulder := 0.6
var cam_y := 0.0
var fov_kick := 0.0
var shake := 0.0
var look_idle := 9.0
var mouse_sens := 0.0024
var pad_sens := 1.0
var invert_y := false

var pitch_node := Node3D.new()
var arm := SpringArm3D.new()
var camera := Camera3D.new()

func _ready() -> void:
	top_level = true
	add_child(pitch_node)
	pitch_node.add_child(arm)
	arm.add_child(camera)
	arm.spring_length = 4.3
	arm.margin = 0.25
	var sh := SphereShape3D.new(); sh.radius = 0.25
	arm.shape = sh
	camera.fov = 58
	camera.current = true
	camera.far = 2500
	if target:
		global_position = target.global_position + Vector3(0, 1.55, 0)
		cam_y = target.global_position.y
		arm.add_excluded_object(target.get_rid())

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= e.relative.x * mouse_sens
		pitch -= e.relative.y * mouse_sens * (-1.0 if invert_y else 1.0)
		if e.relative.length() > 0.5: look_idle = 0.0
	elif e is InputEventMouseButton and e.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func forward() -> Vector3:
	return Vector3(sin(yaw), 0, cos(yaw))

func aim_dir() -> Vector3:
	return -camera.global_transform.basis.z

func pivot() -> Vector3:
	return global_position

func update(dt: float, p) -> void:
	# controller look, with a curve so small pushes aim precisely
	var lx := Input.get_axis("look_left", "look_right")
	var ly := Input.get_axis("look_up", "look_down")
	if absf(lx) + absf(ly) > 0.05:
		look_idle = 0.0
		yaw -= signf(lx) * pow(absf(lx), 1.8) * 3.4 * pad_sens * dt
		pitch -= signf(ly) * pow(absf(ly), 1.8) * 2.4 * pad_sens * dt * (-1.0 if invert_y else 1.0)
	else:
		look_idle += dt
	# while running with a controller and not steering the view, swing in behind the run
	var hv := Vector2(p.velocity.x, p.velocity.z)
	if p.using_pad and look_idle > 0.7 and p.aim_hold <= 0.0 and not p.riding and hv.length() > 3.0:
		yaw += angle_difference(yaw, atan2(hv.x, hv.y)) * (1.0 - exp(-0.9 * dt)) * minf(1.0, (hv.length() - 3.0) / 4.0)
	pitch = clampf(pitch, -0.7, 0.55)

	shoulder = lerpf(shoulder, 0.95 if p.aim_hold > 0.0 else 0.55, 1.0 - exp(-5.0 * dt))
	var pos: Vector3 = p.global_position
	var foot := pos.y
	if not (p.grounded or p.riding):
		foot = minf(maxf(cam_y, pos.y - 1.5), pos.y)
	var rate := 10.0 if (p.grounded or p.riding) else (12.0 if pos.y < cam_y else 3.0)
	cam_y = lerpf(cam_y, foot, 1.0 - exp(-rate * dt))
	var right := Vector3(-cos(yaw), 0, sin(yaw))
	var tgt := Vector3(pos.x, cam_y + 1.55, pos.z) + right * -shoulder
	var g := global_position
	g.x = lerpf(g.x, tgt.x, 1.0 - exp(-13.0 * dt))
	g.z = lerpf(g.z, tgt.z, 1.0 - exp(-13.0 * dt))
	g.y = lerpf(g.y, tgt.y, 1.0 - exp(-16.0 * dt))
	global_position = g
	rotation = Vector3(0, yaw + PI, 0)
	pitch_node.rotation = Vector3(pitch, 0, 0)
	arm.spring_length = 4.3 - maxf(0.0, pitch) * 2.4
	var speed_fov := clampf((hv.length() - 9.0) / 8.0, 0.0, 1.0) * 8.0
	fov_kick = lerpf(fov_kick, speed_fov, 1.0 - exp(-4.0 * dt))
	camera.fov = 58.0 + fov_kick
	if shake > 0.0:
		camera.position = Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * shake * 0.08
		shake = maxf(0.0, shake - dt * 4.0)
	else:
		camera.position = Vector3.ZERO
