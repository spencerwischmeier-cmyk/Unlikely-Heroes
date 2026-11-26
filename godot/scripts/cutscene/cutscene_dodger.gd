extends "res://scripts/cutscene/drone_actor.gd"
## Dodger for the cutscenes: the shared drone body (drone_actor.gd, also used by the follower) plus
## acting on top of it, kept in this file so the body script stays free for the character work:
##   look_target  turns him (model yaw/pitch) toward a node and aims his pupil when he has one
##   talk         0..1 while he speaks: eye pulse, chatter bob
##   act(name)    body beats "spin", "hop", "shock", "squint", "sad", "nod", "shake"; also pulls a
##                matching eye face through drone_actor's emote() when that exists

const FACE_FOR := {"spin": "happy", "hop": "happy", "shock": "surprised", "squint": "smug", "sad": "sad",
	"nod": "happy", "shake": "angry"}

var look_target: Node3D
var talk := 0.0
var _look := Vector2.ZERO
var act_name := ""
var act_t := 9.0

func act(n: String) -> void:
	act_name = n; act_t = 0.0
	if has_method("emote") and FACE_FOR.has(n): call("emote", FACE_FOR[n], 1.8)

func _process(dt: float) -> void:
	super(dt)
	act_t += dt
	var want := Vector2.ZERO
	if is_instance_valid(look_target):
		var d := to_local(look_target.global_position)
		want = Vector2(clampf(atan2(d.x, d.z), -1.4, 1.4), clampf(-atan2(d.y, Vector2(d.x, d.z).length()), -0.6, 0.6))
	_look = _look.lerp(want, 1.0 - exp(-5.0 * dt))
	if "look_dir" in self and is_instance_valid(look_target): set("look_dir", Vector2(0.02, clampf(want.y * -1.5, -1.0, 1.0)))
	var r := Vector3(_look.y, _look.x, 0)
	var p := Vector3.ZERO
	var u := act_t
	match act_name:
		"spin": if u < 0.6: r.y += smoothstep(0.0, 0.6, u) * TAU
		"hop": if u < 0.45: p.y = sin(u / 0.45 * PI) * 0.3
		"shock":
			if u < 1.6:
				var k := clampf(minf(u / 0.08, (1.6 - u) / 0.4), 0.0, 1.0)
				p.z = -0.15 * k; r.x -= 0.35 * k
		"squint":
			if u < 2.4: r.z += 0.15 * clampf(minf(u / 0.15, (2.4 - u) / 0.3), 0.0, 1.0)
		"sad":
			if u < 3.0:
				var k := clampf(minf(u / 0.4, (3.0 - u) / 0.5), 0.0, 1.0)
				r.x += 0.4 * k; p.y -= 0.12 * k
		"nod": if u < 0.9: r.x += sin(u / 0.9 * TAU * 2.0) * 0.25
		"shake": if u < 0.9: r.y += sin(u / 0.9 * TAU * 2.0) * 0.35
	var tk := talk * (0.5 + 0.5 * sin(t * 17.0) * sin(t * 5.3))
	r.x += tk * 0.06; p.y += tk * 0.03
	model.position += p
	model.rotation += r
	eye_mat.emission_energy_multiplier *= 1.0 + tk * 0.8
	eye_light.light_energy *= 1.0 + tk
