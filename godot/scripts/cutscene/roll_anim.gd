extends Node
## Makes a cutscene roller (models/roller.glb under a plain actor node) move like the gameplay one:
## the ball spins with the distance travelled, the cap turns to face where it's going, leans into
## starts and stops, bobs while rolling and wobbles a little when idle. Add it as a child of the actor;
## then just tween the actor's position and the roll follows.

var ball: Node3D
var cap: Node3D
var cap_y := 0.55
var last := Vector3.INF
var vel := Vector3.ZERO
var heading := 0.0
var lean := 0.0
var t := randf() * 10.0
var steer := true            # cap faces the travel direction (turn off for scripted head turns)

func _ready() -> void:
	var a: Node3D = get_parent()
	ball = a.find_child("ball", true, false)
	cap = a.find_child("cap", true, false)
	if cap: cap_y = cap.position.y; heading = cap.rotation.y

func _process(dt: float) -> void:
	var a: Node3D = get_parent()
	if dt <= 0.0 or a == null: return
	t += dt
	var p := a.global_position
	if last == Vector3.INF: last = p
	var v := (p - last) / dt
	last = p
	v.y = 0.0
	var prev := vel
	vel = vel.lerp(v, 1.0 - exp(-14.0 * dt))
	var sp := vel.length()
	# local-space velocity (the actor itself may be yawed)
	var lv := a.global_transform.basis.inverse() * vel
	if sp > 0.05 and ball:
		var axis := Vector3(lv.z, 0, -lv.x).normalized()
		ball.rotate(axis, sp * dt / 0.55)
	if cap:
		if steer and sp > 0.3: heading = lerp_angle(heading, atan2(lv.x, lv.z), 1.0 - exp(-7.0 * dt))
		cap.rotation.y = heading
		# lean into acceleration, rock back when braking, then settle with a little overshoot
		var acc := (vel.length() - prev.length()) / dt
		var want := clampf(sp * 0.045 + acc * 0.03, -0.2, 0.3)
		lean = lerpf(lean, want, 1.0 - exp(-5.0 * dt))
		var idle := (1.0 - minf(1.0, sp / 0.5))
		cap.rotation.x = lean + sin(t * 1.7) * 0.025 * idle
		cap.rotation.z = sin(t * 1.3) * 0.03 * idle + sin(t * sp * 1.1) * 0.02 * minf(1.0, sp / 3.0)
		cap.position.y = cap_y + absf(sin(t * maxf(sp, 0.01) * 2.2)) * 0.03 * minf(1.0, sp / 3.0) + sin(t * 2.1) * 0.008 * idle
