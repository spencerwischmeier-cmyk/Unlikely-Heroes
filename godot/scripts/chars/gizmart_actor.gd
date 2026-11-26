extends Node3D
## Gizmart's body: the Meshy vending-machine robot (models/chars/gizmart.glb) with a live screen face.
## The face is made of glowing pieces so it can emote: "eyes" (two pills that blink, squint into happy
## arcs or go wide) and "grin" (a row of segments bent into a smile, a big open grin or a wobbly frown).
## Kit.set_glow / Kit.flash find "eyes" and "grin" by name, so the shop code can recolor and flash them.
##   mood("happy" | "excited" | "sad" | "hello", seconds)  pull a face for a while, then back to "idle"
## Idle: a bouncy salesman bob, a little sway, and leaning toward Vesk when he is close.

const SEG := 9
const SCREEN := Vector3(0.12, 2.14, 0.42)   # screen centre on the model (metres, model space)

var model: Node3D
var eyes: Node3D
var grin: Node3D
var eye_l: MeshInstance3D
var eye_r: MeshInstance3D
var segs: Array = []
var t := randf() * 10.0
var blink := 2.0
var face := "idle"
var face_t := 0.0
var curve := 1.0          # grin curvature: 1 smile, -1 frown
var open := 0.0           # grin opening (excited)
var eye_h := 1.0          # eye height (1 open, ~0.2 happy squint, 1.4 wide)
var hop := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	model = load("res://models/chars/gizmart.glb").instantiate()
	add_child(model)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var green := _glow(Color(0.55, 1, 0.45), 3.0)
	# a dark glass screen over the painted face
	var scr := MeshInstance3D.new(); var sb := BoxMesh.new(); sb.size = Vector3(0.9, 0.5, 0.02); scr.mesh = sb
	var sm := StandardMaterial3D.new(); sm.albedo_color = Color(0.02, 0.05, 0.05); sm.roughness = 0.15; sm.metallic = 0.3
	sm.emission_enabled = true; sm.emission = Color(0.1, 0.35, 0.25); sm.emission_energy_multiplier = 0.25
	scr.material_override = sm; scr.position = SCREEN; scr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.add_child(scr)
	eyes = Node3D.new(); eyes.name = "eyes"; eyes.position = SCREEN + Vector3(0, 0.11, 0.02); model.add_child(eyes)
	for sx in [-1.0, 1.0]:
		var e := MeshInstance3D.new(); var cm := CapsuleMesh.new(); cm.radius = 0.042; cm.height = 0.12; cm.radial_segments = 12; cm.rings = 3
		e.mesh = cm; e.material_override = green; e.position = Vector3(0.17 * sx, 0, 0); e.scale = Vector3(1, 1, 0.3)
		e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		eyes.add_child(e)
		if sx < 0: eye_l = e
		else: eye_r = e
	grin = Node3D.new(); grin.name = "grin"; grin.position = SCREEN + Vector3(0, -0.12, 0.02); model.add_child(grin)
	for i in SEG:
		var g := MeshInstance3D.new(); var cm := CapsuleMesh.new(); cm.radius = 0.022; cm.height = 0.085; cm.radial_segments = 8; cm.rings = 2
		g.mesh = cm; g.material_override = green; g.scale = Vector3(1, 1, 0.3)
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		grin.add_child(g); segs.append(g)

func _glow(c: Color, e: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new(); m.albedo_color = c; m.emission_enabled = true; m.emission = c; m.emission_energy_multiplier = e
	return m

## Pull a face for `secs` seconds: "happy", "excited", "sad", "hello".
func mood(m: String, secs := 1.5) -> void:
	face = m; face_t = secs
	if m in ["excited", "hello"]: hop = 1.0

func _process(dt: float) -> void:
	t += dt
	face_t -= dt
	if face_t <= 0.0: face = "idle"
	var want_curve := 1.0; var want_open := 0.0; var want_eye := 1.0
	match face:
		"happy": want_curve = 1.3; want_eye = 0.35
		"excited": want_curve = 1.5; want_open = 1.0; want_eye = 0.3
		"hello": want_curve = 1.4; want_open = 0.6; want_eye = 1.3
		"sad": want_curve = -0.8; want_eye = 0.75
	var k := 1.0 - exp(-12.0 * dt)
	curve = lerpf(curve, want_curve, k); open = lerpf(open, want_open, k); eye_h = lerpf(eye_h, want_eye, k)
	# blink
	blink -= dt
	var b := 1.0
	if blink < 0.12: b = absf(blink - 0.06) / 0.06
	if blink <= 0.0: blink = randf_range(2.0, 4.5)
	for e in [eye_l, eye_r]:
		(e as MeshInstance3D).scale.y = maxf(0.12, eye_h * b)
		(e as MeshInstance3D).position.y = -0.03 if eye_h < 0.5 else 0.0
	# grin: segments along a parabola; "open" adds a lower lip
	var wob := sin(t * 18.0) * 0.012 if face == "sad" else 0.0
	for i in SEG:
		var u := float(i) / (SEG - 1) * 2.0 - 1.0          # -1..1
		var g: MeshInstance3D = segs[i]
		var y := curve * (u * u - 1.0) * -0.05 * -1.0      # smile: ends up, middle down
		y = curve * (u * u) * 0.06 - curve * 0.03 + wob * sin(u * 6.0)
		if open > 0.05 and i % 2 == 1: y -= open * 0.06 * (1.0 - u * u)
		g.position = Vector3(u * 0.16 * (1.0 + open * 0.15), y, 0)
		var slope := curve * 2.0 * u * 0.06 / 0.16
		g.rotation = Vector3(0, 0, PI / 2 + atan(slope))
	# body: salesman bob, sway, hops when excited
	hop = maxf(0.0, hop - dt * 2.5)
	var bob := absf(sin(t * 2.2)) * 0.03 + sin(hop * PI) * 0.25
	model.position.y = bob
	var squash := 1.0 + sin(t * 4.4) * 0.012 - sin(hop * PI) * 0.04
	model.scale = Vector3(1.0 / sqrt(squash), squash, 1.0 / sqrt(squash))
	var lean := 0.0
	if Game.player and is_inside_tree():
		var d := to_local(Game.player.global_position)
		if d.length() < 6.0 and d.z > 0.0: lean = clampf(-d.x * 0.03, -0.08, 0.08)
	model.rotation.z = lerpf(model.rotation.z, sin(t * 1.3) * 0.025 + lean, 1.0 - exp(-4.0 * dt))
	model.rotation.x = lerpf(model.rotation.x, 0.04 if lean != 0.0 else 0.0, 1.0 - exp(-4.0 * dt))
