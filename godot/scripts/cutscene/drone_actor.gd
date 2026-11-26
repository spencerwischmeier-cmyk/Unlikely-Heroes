extends Node3D
## Dodger's body: the drone model with a hover bob, a glowing eye (cyan, flickers orange during
## Grudd's broadcasts) and jet glows. Shared by the Dodger follower (systems/dodger.gd) and the cutscenes.
## Uses models/chars/dodger.glb when it exists (scaled to the old drone's size), else models/drone.glb.
## Acting (cutscenes): `look_target` turns him toward a node, `talk` (0..1) pulses his eye and bob
## while he speaks, `emote(name)`: "spin", "hop", "shock", "squint", "sad", "nod", "shake".

const M := preload("res://scripts/mats.gd")
const EYE := Color(0.35, 0.95, 1.0)
const ORANGE := Color(1.0, 0.42, 0.06)
const NEW_GLB := "res://models/chars/dodger.glb"
const SIZE := 0.62          # rough width of the old drone model, for scaling a new one

var model: Node3D
var eye_mat: StandardMaterial3D
var eye_light: OmniLight3D
var eye_node: Node3D
var eye_rest := Vector3.ONE
var eye_color := EYE
var orange := 0.0          # 0..1, eye flickers toward orange (the broadcast's inspector code)
var hover := 1.0           # bob amount (0 while crashed)
var tilt := Vector3.ZERO   # extra body tilt in radians (banking, lying crashed)
var dim := 0.0             # 0..1, eye fades out (crashed)
var look_target: Node3D
var talk := 0.0
var t := randf() * 10.0
var _flick := 0.0
var _flick_on := false
var _look := Vector2.ZERO
var emo := ""
var emo_t := 9.0
var jet_mats: Array = []

func _ready() -> void:
	var path := NEW_GLB if ResourceLoader.exists(NEW_GLB) else "res://models/drone.glb"
	var inner: Node3D = load(path).instantiate()
	if path == NEW_GLB:
		model = Node3D.new(); model.add_child(inner)
		var b := _aabb(inner, Transform3D.IDENTITY)
		var s := SIZE / maxf(0.01, maxf(b.size.x, b.size.z))
		inner.scale = Vector3.ONE * s
		inner.position = -b.get_center() * s
		var ap := inner.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap and ap.get_animation_list().size() > 0:
			var a: String = ap.get_animation_list()[0]
			for n in ap.get_animation_list(): if n.to_lower().contains("idle") or n.to_lower().contains("hover"): a = n
			ap.get_animation(a).loop_mode = Animation.LOOP_LINEAR; ap.play(a)
	else:
		model = inner
	add_child(model)
	eye_mat = M.glow(EYE, 4.0)
	var glass := _find_eye_mesh(model)
	if glass: glass.material_override = eye_mat
	eye_node = model.find_child("drone_eye", true, false) as Node3D
	if eye_node == null and glass: eye_node = glass
	if glass == null:
		# no eye mesh found on a new model: add a glowing lens at the front
		var s := SphereMesh.new(); s.radius = 0.09; s.height = 0.18
		var mi := MeshInstance3D.new(); mi.mesh = s; mi.material_override = eye_mat; mi.position = Vector3(0, 0.02, SIZE * 0.42)
		model.add_child(mi); eye_node = mi
	if eye_node: eye_rest = eye_node.scale
	eye_light = OmniLight3D.new(); eye_light.light_color = EYE; eye_light.light_energy = 0.8; eye_light.omni_range = 2.2
	eye_light.shadow_enabled = false
	(eye_node if eye_node else model).add_child(eye_light)
	eye_light.position = Vector3(0, 0, 0.15) if eye_node else Vector3(0, 0, 0.45)
	for j in ["drone_jet_L", "drone_jet_R"]:
		var jn := model.find_child(j, true, false) as Node3D
		if jn == null: continue
		var s := SphereMesh.new(); s.radius = 0.05; s.height = 0.14
		var mi := MeshInstance3D.new(); mi.mesh = s
		var jm := M.glow(Color(0.4, 0.9, 1.0), 3.0); mi.material_override = jm; jet_mats.append(jm)
		mi.position = Vector3(0, -0.05, 0); jn.add_child(mi)
	_shadows(model)

func _find_eye_mesh(n: Node) -> MeshInstance3D:
	var g := n.find_child("drone_eye_glass", true, false) as MeshInstance3D
	if g: return g
	for c in n.find_children("*", "MeshInstance3D", true, false):
		var nm := String(c.name).to_lower()
		if nm.contains("eye") or nm.contains("lens"): return c
	return null

func _aabb(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	var x := xf * (n as Node3D).transform if n is Node3D else xf
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		out = x * (n as MeshInstance3D).mesh.get_aabb(); first = false
	for c in n.get_children():
		var cb := _aabb(c, x)
		if cb.size == Vector3.ZERO: continue
		if first: out = cb; first = false
		else: out = out.merge(cb)
	return out

func _shadows(n: Node) -> void:
	if n is GeometryInstance3D: (n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for c in n.get_children(): _shadows(c)

func emote(n: String) -> void:
	emo = n; emo_t = 0.0

func _process(dt: float) -> void:
	t += dt; emo_t += dt
	# look toward a node: yaw/pitch on the model only, so tweens on the node itself still work
	var want := Vector2.ZERO
	if is_instance_valid(look_target):
		var d := to_local(look_target.global_position)
		want = Vector2(clampf(atan2(d.x, d.z), -1.4, 1.4), clampf(-atan2(d.y, Vector2(d.x, d.z).length()), -0.6, 0.6))
	_look = _look.lerp(want, 1.0 - exp(-5.0 * dt))
	var e_rot := Vector3.ZERO
	var e_pos := Vector3.ZERO
	var eye_s := Vector3.ONE
	var u := emo_t
	match emo:
		"spin": if u < 0.6: e_rot.y = smoothstep(0.0, 0.6, u) * TAU
		"hop": if u < 0.45: e_pos.y = sin(u / 0.45 * PI) * 0.3
		"shock":
			if u < 1.6:
				var k := clampf(minf(u / 0.08, (1.6 - u) / 0.4), 0.0, 1.0)
				e_pos.z = -0.15 * k; e_rot.x = -0.35 * k; eye_s = Vector3.ONE * (1.0 + 0.4 * k)
		"squint":
			if u < 2.4:
				var k := clampf(minf(u / 0.15, (2.4 - u) / 0.3), 0.0, 1.0)
				eye_s = Vector3(1.0 + 0.1 * k, 1.0 - 0.6 * k, 1.0); e_rot.z = 0.15 * k
		"sad":
			if u < 3.0:
				var k := clampf(minf(u / 0.4, (3.0 - u) / 0.5), 0.0, 1.0)
				e_rot.x = 0.4 * k; e_pos.y = -0.12 * k; eye_s = Vector3(1, 1.0 - 0.3 * k, 1)
		"nod": if u < 0.9: e_rot.x = sin(u / 0.9 * TAU * 2.0) * 0.25
		"shake": if u < 0.9: e_rot.y = sin(u / 0.9 * TAU * 2.0) * 0.35
	var tk := talk * (0.5 + 0.5 * sin(t * 17.0) * sin(t * 5.3))
	model.position = Vector3(0, sin(t * 2.3) * 0.07 * hover + tk * 0.03, 0) + e_pos
	model.rotation = Vector3(sin(t * 1.3) * 0.05 * hover + tilt.x + _look.y + tk * 0.06, tilt.y + _look.x, sin(t * 1.7) * 0.08 * hover + tilt.z) + e_rot
	if eye_node: eye_node.scale = eye_rest * eye_s
	var c := eye_color
	if orange > 0.01:
		_flick -= dt
		if _flick <= 0.0:
			_flick = randf_range(0.03, 0.16); _flick_on = randf() < 0.75
		c = eye_color.lerp(ORANGE, orange * (1.0 if _flick_on else 0.25))
	var e := (1.0 - dim) * (4.0 if not (orange > 0.01 and not _flick_on) else 1.5) * (1.0 + tk * 0.8)
	eye_mat.albedo_color = c * 0.2; eye_mat.emission = c; eye_mat.emission_energy_multiplier = e
	eye_light.light_color = c; eye_light.light_energy = 0.8 * (1.0 - dim) * (1.0 + tk)
	for jm in jet_mats: jm.emission_energy_multiplier = (2.0 + randf()) * hover
