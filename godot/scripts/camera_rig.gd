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
var aim_assist := true            # controller only: the view slows over a bot and leans onto it while firing
var shake_t := 0.0                # runs the smooth shake noise
var lead := Vector3.ZERO          # the framing drifts a little ahead of a run so you see where you're going
var dip := 0.0                    # camera dips on hard landings

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
	# the arm itself never collides: update() casts for walls and eases the length (in fast, out slow),
	# so the camera doesn't snap in and out behind railings and posts
	arm.collision_mask = 0
	_probe.radius = 0.16
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

## Jump straight to the target (after a respawn or teleport) instead of sweeping across the level.
var _probe := SphereShape3D.new()
var _boom_len := 4.3
var _occl_t := 0.0
var _boom_q := PhysicsShapeQueryParameters3D.new()
## Camera distance after walls: pulls in at once when something is in the way, eases back out over
## about half a second once it clears.
func _boom(dt: float, want: float) -> float:
	var from := pitch_node.global_position
	var dir := pitch_node.global_basis.z
	_boom_q.shape = _probe
	_boom_q.transform = Transform3D(Basis(), from)
	_boom_q.motion = dir * want
	_boom_q.collision_mask = 1
	if target: _boom_q.exclude = [target.get_rid()]
	var r := get_world_3d().direct_space_state.cast_motion(_boom_q)
	var free := want * (r[0] if r.size() > 0 else 1.0)
	free = maxf(free - 0.1, 0.3)
	# something thin (an upright, a railing) between where the lens wants to be and Vesk for more than
	# a moment: stay in front of it (checked at the wanted spot, so easing out never slides back behind it)
	var want_len := free
	if target:
		var chest := target.global_position + Vector3(0, 1.0, 0)
		var at := from + dir * free
		var rq := PhysicsRayQueryParameters3D.create(chest, at); rq.collision_mask = 1; rq.exclude = [target.get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(rq)
		if hit:
			_occl_t += dt
			if _occl_t > 0.12:
				var f := chest.distance_to(hit.position) / maxf(chest.distance_to(at), 0.01)
				want_len = maxf(free * f - 0.35, 0.6)
		else:
			_occl_t = 0.0
	if free < _boom_len: _boom_len = free                                   # a wall: at once
	elif want_len < _boom_len: _boom_len = lerpf(_boom_len, want_len, 1.0 - exp(-9.0 * dt))
	else: _boom_len = lerpf(_boom_len, want_len, 1.0 - exp(-4.0 * dt))
	return _boom_len

func snap(p: Node3D) -> void:
	cam_y = p.global_position.y
	var right := Vector3(-cos(yaw), 0, sin(yaw))
	global_position = p.global_position + Vector3(0, 1.55, 0) + right * -shoulder
	rotation = Vector3(0, yaw + PI, 0)

func update(dt: float, p) -> void:
	# controller look, with a curve so small pushes aim precisely
	var lx := Input.get_axis("look_left", "look_right")
	var ly := Input.get_axis("look_up", "look_down")
	var friction := 1.0
	var assist_bot: Node3D = null
	if p.using_pad and aim_assist:
		assist_bot = _assist_target(0.14, 60.0)
		if assist_bot: friction = 0.55
	if absf(lx) + absf(ly) > 0.05:
		look_idle = 0.0
		yaw -= signf(lx) * pow(absf(lx), 1.8) * 3.4 * pad_sens * dt * friction
		pitch -= signf(ly) * pow(absf(ly), 1.8) * 2.4 * pad_sens * dt * (-1.0 if invert_y else 1.0) * friction
	else:
		look_idle += dt
	# controller aim assist: while firing, ease the crosshair onto the bot nearest to it
	if assist_bot and p.aim_hold > 0.5:
		var to2: Vector3 = (assist_bot.center() - camera.global_position).normalized()
		var k := 1.0 - exp(-4.5 * dt)
		yaw += angle_difference(yaw, atan2(to2.x, to2.z)) * k
		pitch = lerpf(pitch, clampf(asin(clampf(to2.y, -1.0, 1.0)), -0.7, 0.55), k * 0.5)
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
	# lead: drift a little ahead of a run (not while aiming, grinding or swinging, which have their own framing)
	var lead_to := Vector3.ZERO
	if p.aim_hold <= 0.0 and hv.length() > 2.0:
		lead_to = Vector3(hv.x, 0, hv.y) * 0.05
		lead_to = lead_to.limit_length(0.7)
	lead = lead.lerp(lead_to, 1.0 - exp(-2.5 * dt))
	dip = lerpf(dip, float(p.land_t) * 0.22, 1.0 - exp(-(30.0 if p.land_t > dip else 6.0) * dt))
	var tgt := Vector3(pos.x, cam_y + 1.55 - dip, pos.z) + right * -shoulder + lead
	var g := global_position
	g.x = lerpf(g.x, tgt.x, 1.0 - exp(-13.0 * dt))
	g.z = lerpf(g.z, tgt.z, 1.0 - exp(-13.0 * dt))
	g.y = lerpf(g.y, tgt.y, 1.0 - exp(-16.0 * dt))
	global_position = g
	rotation = Vector3(0, yaw + PI, 0)
	pitch_node.rotation = Vector3(pitch, 0, 0)
	arm.spring_length = _boom(dt, 4.3 - maxf(0.0, pitch) * 2.4)
	var speed_fov := clampf((hv.length() - 9.0) / 8.0, 0.0, 1.0) * 8.0
	fov_kick = lerpf(fov_kick, speed_fov, 1.0 - exp(-4.0 * dt))
	camera.fov = 58.0 + fov_kick
	# shake: smooth layered noise scaled by trauma squared (a jolt that settles, not a random jitter)
	if shake > 0.0:
		shake_t += dt
		var tr := minf(shake, 1.5); tr = tr * tr
		var n := Vector3(sin(shake_t * 37.0) + sin(shake_t * 23.0 + 1.7) * 0.6, sin(shake_t * 31.0 + 0.6) + sin(shake_t * 19.0 + 2.9) * 0.6, 0)
		camera.position = n * tr * 0.06
		camera.rotation = Vector3(0, 0, (sin(shake_t * 27.0 + 4.1) + sin(shake_t * 13.0) * 0.5) * tr * 0.012)
		shake = maxf(0.0, shake - dt * 3.0)
	else:
		camera.position = Vector3.ZERO; camera.rotation = Vector3.ZERO

## The bot closest to the crosshair within `cone` radians (and in sight), for controller aim assist.
func _assist_target(cone: float, rng: float) -> Node3D:
	var from: Vector3 = camera.global_position
	var fwd := aim_dir()
	var best: Node3D = null
	var best_a := cone
	for b in get_tree().get_nodes_in_group("bots"):
		if not (b is Node3D) or b.get("dead") or not b.has_method("center"): continue
		var to: Vector3 = b.center() - from
		var dist := to.length()
		if dist > rng or dist < 1.5: continue
		var a := fwd.angle_to(to) * clampf(dist / 12.0, 0.6, 1.0)   # close bots are wide on screen: a bit more cone
		if a < best_a: best_a = a; best = b
	if best:
		var q := PhysicsRayQueryParameters3D.create(from, best.center()); q.collision_mask = 1
		if get_world_3d().direct_space_state.intersect_ray(q): return null
	return best
