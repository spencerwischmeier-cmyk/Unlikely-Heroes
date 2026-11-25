extends Node3D
## Vesk for cutscenes: models/vesk.glb with its animations (idle, run, jump, land, fall, glide...)
## and a procedural sitting pose (`sit` 0..1 folds the legs onto a chair). Holds an optional coffee mug.

const M := preload("res://scripts/mats.gd")

var ap: AnimationPlayer
var sk: Skeleton3D
var cur := ""
var sit := 0.0           # 0 standing, 1 seated
var slump := 0.0         # lean back in the chair
var head_turn := 0.0     # radians, + looks to his left
var mug: Node3D

func _ready() -> void:
	var m: Node3D = load("res://models/vesk.glb").instantiate()
	add_child(m)
	_shadows(m)
	ap = m.find_child("AnimationPlayer", true, false)
	sk = m.find_child("Skeleton3D", true, false)
	if ap:
		ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		for n in ["idle", "run", "fall", "dash", "glide", "grind", "swing"]:
			if ap.has_animation(n): ap.get_animation(n).loop_mode = Animation.LOOP_LINEAR
		play("idle")

func _shadows(n: Node) -> void:
	if n is GeometryInstance3D: (n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for c in n.get_children(): _shadows(c)

func play(n: String, blend := 0.2, spd := 1.0) -> void:
	if ap == null or not ap.has_animation(n): return
	ap.speed_scale = spd
	if n != cur:
		cur = n; ap.play(n, blend)

## A coffee mug in his hands (on the blaster grip bone).
func hold_mug(on: bool) -> void:
	if on and mug == null and sk:
		var ba := BoneAttachment3D.new(); ba.bone_name = "gun"; sk.add_child(ba)
		mug = Node3D.new(); ba.add_child(mug)
		var c := CylinderMesh.new(); c.top_radius = 0.06; c.bottom_radius = 0.055; c.height = 0.12
		var mi := MeshInstance3D.new(); mi.mesh = c; mi.material_override = M.std(Color(0.95, 0.55, 0.2), 0.0, 0.4); mug.add_child(mi)
		var h := TorusMesh.new(); h.inner_radius = 0.025; h.outer_radius = 0.045
		var hi := MeshInstance3D.new(); hi.mesh = h; hi.rotation.z = PI / 2; hi.position = Vector3(0.065, 0, 0)
		hi.material_override = mi.material_override; mug.add_child(hi)
		var top := CylinderMesh.new(); top.top_radius = 0.052; top.bottom_radius = 0.052; top.height = 0.005
		var ti := MeshInstance3D.new(); ti.mesh = top; ti.position.y = 0.05; ti.material_override = M.std(Color(0.22, 0.12, 0.06), 0.0, 0.2); mug.add_child(ti)
		mug.position = Vector3(0, 0.02, 0.02)
	if mug: mug.get_parent().visible = on

func _process(dt: float) -> void:
	if ap: ap.advance(dt)
	if sk == null: return
	if sit > 0.001: _sit_pose()
	if absf(head_turn) > 0.001: _rot_global("neck", Vector3.UP, head_turn)

## Rotate a bone about a model-space axis through its head (after the animation has posed it).
func _rot_global(bone: String, axis: Vector3, ang: float) -> void:
	var i := sk.find_bone(bone)
	if i < 0: return
	var p := sk.get_bone_parent(i)
	var pg: Basis = sk.get_bone_global_pose(p).basis if p >= 0 else Basis()
	var l := Basis(sk.get_bone_pose_rotation(i))
	sk.set_bone_pose_rotation(i, (pg.inverse() * Basis(axis, ang) * pg * l).get_rotation_quaternion())

func _sit_pose() -> void:
	var pel := sk.find_bone("pelvis")
	if pel < 0: return
	var pg: Basis = sk.get_bone_global_pose(pel).basis
	for side in [".L", ".R"]:
		var th := sk.find_bone("thigh" + side)
		var sh := sk.find_bone("shin" + side)
		if th < 0 or sh < 0: continue
		var spread := 0.12 * sit * (1.0 if side == ".L" else -1.0)
		var rt := Basis(Vector3.UP, spread) * Basis(Vector3.RIGHT, -1.5 * sit)
		var lt := Basis(sk.get_bone_pose_rotation(th))
		sk.set_bone_pose_rotation(th, (pg.inverse() * rt * pg * lt).get_rotation_quaternion())
		var tg := rt * pg * lt
		var rs := Basis(Vector3.RIGHT, 1.45 * sit)
		var ls := Basis(sk.get_bone_pose_rotation(sh))
		sk.set_bone_pose_rotation(sh, (tg.inverse() * rs * tg * ls).get_rotation_quaternion())
	if slump > 0.001: _rot_global("spine", Vector3.RIGHT, -0.22 * slump)
