extends Node3D
## Dodger's body: the drone model with a hover bob, a glowing eye (cyan, flickers orange during
## Grudd's broadcasts) and jet glows. Shared by the Dodger follower (systems/dodger.gd) and the cutscenes.

const M := preload("res://scripts/mats.gd")
const EYE := Color(0.35, 0.95, 1.0)
const ORANGE := Color(1.0, 0.42, 0.06)

var model: Node3D
var eye_mat: StandardMaterial3D
var eye_light: OmniLight3D
var eye_color := EYE
var orange := 0.0          # 0..1, eye flickers toward orange (the broadcast's inspector code)
var hover := 1.0           # bob amount (0 while crashed)
var tilt := Vector3.ZERO   # extra body tilt in radians (banking, lying crashed)
var dim := 0.0             # 0..1, eye fades out (crashed)
var t := randf() * 10.0
var _flick := 0.0
var _flick_on := false
var jet_mats: Array = []

func _ready() -> void:
	model = load("res://models/drone.glb").instantiate()
	add_child(model)
	eye_mat = M.glow(EYE, 4.0)
	var glass := model.find_child("drone_eye_glass", true, false) as MeshInstance3D
	if glass: glass.material_override = eye_mat
	var eye := model.find_child("drone_eye", true, false) as Node3D
	eye_light = OmniLight3D.new(); eye_light.light_color = EYE; eye_light.light_energy = 0.8; eye_light.omni_range = 2.2
	eye_light.shadow_enabled = false
	(eye if eye else model).add_child(eye_light)
	eye_light.position = Vector3(0, 0, 0.15) if eye else Vector3(0, 0, 0.45)
	for j in ["drone_jet_L", "drone_jet_R"]:
		var jn := model.find_child(j, true, false) as Node3D
		if jn == null: continue
		var s := SphereMesh.new(); s.radius = 0.05; s.height = 0.14
		var mi := MeshInstance3D.new(); mi.mesh = s
		var jm := M.glow(Color(0.4, 0.9, 1.0), 3.0); mi.material_override = jm; jet_mats.append(jm)
		mi.position = Vector3(0, -0.05, 0); jn.add_child(mi)
	_shadows(model)

func _shadows(n: Node) -> void:
	if n is GeometryInstance3D: (n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for c in n.get_children(): _shadows(c)

func _process(dt: float) -> void:
	t += dt
	model.position.y = sin(t * 2.3) * 0.07 * hover
	model.rotation = Vector3(sin(t * 1.3) * 0.05 * hover + tilt.x, tilt.y, sin(t * 1.7) * 0.08 * hover + tilt.z)
	var c := eye_color
	if orange > 0.01:
		_flick -= dt
		if _flick <= 0.0:
			_flick = randf_range(0.03, 0.16); _flick_on = randf() < 0.75
		c = eye_color.lerp(ORANGE, orange * (1.0 if _flick_on else 0.25))
	var e := (1.0 - dim) * (4.0 if not (orange > 0.01 and not _flick_on) else 1.5)
	eye_mat.albedo_color = c * 0.2; eye_mat.emission = c; eye_mat.emission_energy_multiplier = e
	eye_light.light_color = c; eye_light.light_energy = 0.8 * (1.0 - dim)
	for jm in jet_mats: jm.emission_energy_multiplier = (2.0 + randf()) * hover
