extends Node3D
## Vesk for cutscenes: models/vesk.glb with its gameplay clips (idle, run, jump, land...) plus the
## cutscene acting clips merged in by art/meshy/build_vesk.py (cs_sit, cs_sit_drink, cs_sit_stand,
## cs_sit_arms, cs_talk, cs_talk2, cs_talk_angry, cs_shrug, cs_facepalm, cs_scratch, cs_wave,
## cs_beckon, cs_listen, cs_stomp, cs_drink, cs_nod, cs_look_around).
##   play(name)      loop / hold a clip
##   gesture(name)   a one-shot clip, then back to the base clip (falls back quietly if missing)
##   look_target     head and neck turn smoothly toward a node (clamped), head_turn adds a fixed offset
##   talk            0..1 while he speaks: small head nods
## A procedural sitting pose (`sit` 0..1) is used when the cs_sit clips are missing.

const M := preload("res://scripts/mats.gd")
const CS_ANIMS := "res://models/vesk_cs_anims.glb"
static var cs_lib: AnimationLibrary
const LOOPS := ["idle", "run", "fall", "dash", "glide", "grind", "swing", "cs_sit", "cs_sit_drink", "cs_sit_arms", "cs_listen", "cs_talk", "cs_talk2"]

var ap: AnimationPlayer
var sk: Skeleton3D
var cur := ""
var base := "idle"
var one_shot := false
var sit := 0.0           # 0 standing, 1 seated (procedural fallback)
var slump := 0.0         # lean back in the chair
var head_turn := 0.0     # radians, + looks to his left
var look_target: Node3D
var look_point := Vector3.INF
var talk := 0.0
var mug: Node3D
var t := 0.0
var _yaw := 0.0
var _pitch := 0.0

func _ready() -> void:
	var m: Node3D = load("res://models/vesk.glb").instantiate()
	add_child(m)
	_shadows(m)
	ap = m.find_child("AnimationPlayer", true, false)
	sk = m.find_child("Skeleton3D", true, false)
	if ap:
		ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		_add_cs_clips()
		for n in LOOPS:
			if has(n): ap.get_animation(_res(n)).loop_mode = Animation.LOOP_LINEAR
		play("idle")

## The acting clips live in their own animation-only GLB (same armature and bone names as vesk.glb).
func _add_cs_clips() -> void:
	if cs_lib == null and ResourceLoader.exists(CS_ANIMS):
		var s: Node = load(CS_ANIMS).instantiate()
		var src := s.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if src:
			cs_lib = AnimationLibrary.new()
			for n in src.get_animation_list(): cs_lib.add_animation(n, src.get_animation(n).duplicate())
		s.free()
	if cs_lib and not ap.has_animation_library("cs"): ap.add_animation_library("cs", cs_lib)

func _res(n: String) -> String:
	if ap.has_animation(n): return n
	return "cs/" + n

func _shadows(n: Node) -> void:
	if n is GeometryInstance3D: (n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for c in n.get_children(): _shadows(c)

func has(n: String) -> bool:
	return ap != null and (ap.has_animation(n) or ap.has_animation("cs/" + n))

## Seated with real clips when they exist (no procedural fold needed).
func can_sit() -> bool:
	return has("cs_sit")

func play(n: String, blend := 0.2, spd := 1.0) -> void:
	if not has(n): return
	ap.speed_scale = spd
	base = n; one_shot = false
	if n != cur:
		cur = n; ap.play(_res(n), blend)

## One-shot acting clip; returns its length (0 if missing). `then` sets the clip to return to.
func gesture(n: String, blend := 0.25, then := "", spd := 1.0) -> float:
	if not has(n): return 0.0
	if then != "": base = then
	ap.speed_scale = spd
	cur = n; one_shot = true
	ap.play(_res(n), blend)
	ap.seek(0.0, false)
	return ap.get_animation(_res(n)).length / spd

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
	t += dt
	if ap:
		if one_shot and ap.current_animation == _res(cur) and ap.current_animation_position >= ap.current_animation_length - 0.3:
			one_shot = false; cur = base; ap.speed_scale = 1.0; ap.play(_res(base), 0.3)
		ap.advance(dt)
	if sk == null: return
	if sit > 0.001: _sit_pose()
	# head look (neck 40%, head 60%), plus talking nods
	var want_y := 0.0
	var want_p := 0.0
	var tp := look_point
	if is_instance_valid(look_target): tp = look_target.global_position
	var hb := sk.find_bone("head")
	if tp != Vector3.INF and hb >= 0:
		var hp := sk.global_transform * sk.get_bone_global_pose(hb).origin
		var d := sk.global_transform.basis.inverse() * (tp - hp)
		want_y = clampf(atan2(d.x, d.z), -1.15, 1.15)
		want_p = clampf(atan2(d.y, Vector2(d.x, d.z).length()), -0.5, 0.45)
	var k := 1.0 - exp(-6.0 * dt)
	_yaw = lerpf(_yaw, want_y + head_turn, k)
	_pitch = lerpf(_pitch, want_p, k)
	var nod := talk * (sin(t * 6.5) * 0.045 + sin(t * 2.7) * 0.03)
	if absf(_yaw) > 0.001 or absf(_pitch) > 0.001 or absf(nod) > 0.001:
		_rot_global("neck", Vector3.UP, _yaw * 0.4)
		_rot_global("head", Vector3.UP, _yaw * 0.6)
		_rot_global("neck", Vector3.RIGHT, -_pitch * 0.4)
		_rot_global("head", Vector3.RIGHT, -_pitch * 0.6 + nod)

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
