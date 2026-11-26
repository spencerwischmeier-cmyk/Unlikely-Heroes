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
## Face (models/vesk_face.glb, built by art/face/build_vesk_face.py; falls back to vesk.glb without it):
##   mood(name)      brows / lids / mouth set: neutral content smug annoyed angry furious shocked sad tired
##                   skeptical; blends over `secs`
##   lip(id)         lip sync for a voice line from audio/voice/lipsync.json, locked to the voice player
## Acting (hand-keyed beats on top of the clips, see ACTS):
##   hold(clip, at)  freeze a clip at one moment (a resting pose) with breathing and weight shifts on top
##   sip()           mug up to the mouth and back down (seated, cs_sit_drink), then back to the hold
##   act(name)       keyed body beat: sigh, content_sigh, lean_in, flinch, shrug_small, head_shake, settle,
##                   nod_small, slump, puff_up
##   breathing, and small head accents on stressed syllables while he talks, run on their own.
##   blinks, eye darts (saccades) and the real right eyeball aiming at look_target / look_point run on
##   their own; `blink()` forces one (on a cut, a head turn).

const M := preload("res://scripts/mats.gd")
const CS_ANIMS := "res://models/vesk_cs_anims.glb"
const FACE_GLB := "res://models/vesk_face.glb"
const LIPSYNC := "res://audio/voice/lipsync.json"
static var lip_data := {}
# Rhubarb mouth shapes -> jaw degrees and mouth keys
const VISEMES := {
	"X": {"jaw": 0.0, "press": 0.55},
	"A": {"jaw": 0.0, "press": 1.0},
	"B": {"jaw": 2.5, "wide": 0.35},
	"C": {"jaw": 6.0, "wide": 0.45},
	"D": {"jaw": 11.0, "wide": 0.25},
	"E": {"jaw": 6.0, "pucker": 0.45},
	"F": {"jaw": 2.0, "pucker": 1.0},
	"G": {"jaw": 2.0, "press": 0.35, "sneer": 0.45},
	"H": {"jaw": 7.0, "wide": 0.1},
}
const MOODS := {
	"neutral": {},
	"content": {"smile": 0.55, "lids_half": 0.35, "brow_up_L": 0.12, "brow_up_R": 0.12},
	"smug": {"smile": 0.6, "brow_up_R": 0.75, "lids_half": 0.3},
	"annoyed": {"brow_down": 0.5, "frown": 0.3, "lids_half": 0.4},
	"angry": {"brow_down": 1.0, "sneer": 0.45, "frown": 0.35},
	"furious": {"brow_down": 1.0, "sneer": 1.0, "frown": 0.5, "clench": 1.0},
	"shocked": {"brow_up_L": 1.0, "brow_up_R": 1.0, "jaw": 5.0},
	"sad": {"brow_sad": 1.0, "frown": 0.6, "lids_half": 0.2},
	"tired": {"lids_half": 0.6, "brow_sad": 0.2, "frown": 0.2},
	"skeptical": {"brow_up_L": 0.85, "brow_down": 0.35, "frown": 0.2},
	"stunned": {"brow_up_L": 0.6, "brow_up_R": 0.6, "lids_half": 0.0, "jaw": 2.0},
}
const FACE_KEYS := ["blink", "lids_half", "brow_up_L", "brow_up_R", "brow_down", "brow_sad", "smile", "frown", "wide", "pucker", "press", "sneer"]
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
# face state
var face_mi: MeshInstance3D
var bs := {}                  # blend shape name -> index
var jaw_i := -1
var eye_i := -1
var mood_name := "neutral"
var mood_want := {}
var mood_cur := {}
var mood_k := 4.0
var lip_cues: Array = []
var lip_id := ""
var lip_clock := -1.0
var vis_cur := {"jaw": 0.0, "wide": 0.0, "pucker": 0.0, "press": 0.0, "sneer": 0.0}
var blink_in := 2.0
var blink_t := -1.0
var blink_double := false
var sacc := Vector2.ZERO      # eye dart offset (radians)
var sacc_in := 0.6
var eye_aim := Vector2.ZERO
var force_viseme := ""        # previews: hold one mouth shape
# acting layer
var held := false
var hold_at := 0.0
var seq: Array = []           # [[clip time to reach, speed after]] for sip() and friends
var act_name := ""
var act_t := 0.0
var breath := 1.0             # breathing amount
var accent := 0.0             # head accent on stressed syllables (decays)
var _last_shape := "X"
# keyed beats: channel -> [[t, value]...] (radians; channels are bone:axis, applied in model space)
const ACTS := {
	"sigh": {"len": 2.2, "chest:x": [[0, 0], [0.55, -0.1], [1.0, -0.08], [1.7, 0.08], [2.2, 0]],
		"head:x": [[0, 0], [0.55, -0.12], [1.1, -0.1], [1.8, 0.1], [2.2, 0]],
		"shoulders:z": [[0, 0], [0.5, 0.09], [1.0, 0.08], [1.6, -0.05], [2.2, 0]]},
	"content_sigh": {"len": 3.0, "chest:x": [[0, 0], [0.8, -0.12], [1.6, -0.1], [3.0, 0.02]],
		"head:x": [[0, 0], [0.9, -0.22], [1.8, -0.2], [3.0, 0]], "head:z": [[0, 0], [1.0, 0.08], [3.0, 0]],
		"shoulders:z": [[0, 0], [0.8, 0.1], [1.7, 0.08], [3.0, -0.03]]},
	"lean_in": {"len": 2.4, "spine:x": [[0, 0], [0.35, 0.16], [1.9, 0.14], [2.4, 0]],
		"head:x": [[0, 0], [0.35, -0.1], [1.9, -0.08], [2.4, 0]]},
	"flinch": {"len": 1.2, "chest:x": [[0, 0], [0.08, -0.14], [0.5, -0.1], [1.2, 0]],
		"shoulders:z": [[0, 0], [0.08, 0.16], [0.6, 0.1], [1.2, 0]], "head:x": [[0, 0], [0.08, -0.15], [1.2, 0]]},
	"shrug_small": {"len": 1.3, "shoulders:z": [[0, 0], [0.3, 0.14], [0.8, 0.12], [1.3, 0]],
		"head:z": [[0, 0], [0.35, 0.12], [0.9, 0.1], [1.3, 0]]},
	"head_shake": {"len": 1.1, "head:y": [[0, 0], [0.18, 0.13], [0.42, -0.13], [0.66, 0.1], [0.9, -0.05], [1.1, 0]]},
	"nod_small": {"len": 0.8, "head:x": [[0, 0], [0.2, 0.12], [0.45, -0.02], [0.8, 0]]},
	"settle": {"len": 1.6, "spine:x": [[0, 0], [0.5, -0.05], [1.6, 0]], "chest:z": [[0, 0], [0.6, 0.05], [1.6, 0]]},
	"slump": {"len": 2.0, "spine:x": [[0, 0], [0.7, 0.12], [2.0, 0.1]], "head:x": [[0, 0], [0.8, 0.14], [2.0, 0.12]],
		"shoulders:z": [[0, 0], [0.8, -0.06], [2.0, -0.05]], "hold": true},
	"puff_up": {"len": 1.6, "chest:x": [[0, 0], [0.4, -0.12], [1.2, -0.1], [1.6, -0.06]],
		"shoulders:z": [[0, 0], [0.4, 0.1], [1.6, 0.04]], "spine:x": [[0, 0], [0.4, -0.06], [1.6, -0.03]], "hold": true},
}

func _ready() -> void:
	var m: Node3D = load(FACE_GLB if ResourceLoader.exists(FACE_GLB) else "res://models/vesk.glb").instantiate()
	add_child(m)
	_shadows(m)
	ap = m.find_child("AnimationPlayer", true, false)
	sk = m.find_child("Skeleton3D", true, false)
	_setup_face(m)
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
	base = n; one_shot = false; held = false; seq = []
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
		mug.add_child(_steam())
	if mug: mug.get_parent().visible = on

## A soft wisp of steam off the coffee (world-space, so it trails when the mug moves).
func _steam() -> CPUParticles3D:
	var p := CPUParticles3D.new(); p.name = "Steam"
	p.amount = 16; p.lifetime = 2.4; p.local_coords = false; p.position.y = 0.06
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE; p.emission_sphere_radius = 0.025
	p.direction = Vector3.UP; p.spread = 12.0
	p.initial_velocity_min = 0.03; p.initial_velocity_max = 0.07
	p.gravity = Vector3(0.015, 0.09, 0.0)
	p.damping_min = 0.02; p.damping_max = 0.05
	p.angle_min = -180.0; p.angle_max = 180.0
	p.scale_amount_min = 0.7; p.scale_amount_max = 1.2
	var sc := Curve.new(); sc.add_point(Vector2(0, 0.35)); sc.add_point(Vector2(1, 1.6)); p.scale_amount_curve = sc
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 0.98, 0.95, 0.32), Color(1, 1, 1, 0.0)])
	p.color_ramp = g
	var q := QuadMesh.new(); q.size = Vector2(0.07, 0.07)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES; m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var rg := Gradient.new(); rg.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var tex := GradientTexture2D.new(); tex.gradient = rg; tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5); tex.fill_to = Vector2(1.0, 0.5); tex.width = 64; tex.height = 64
	m.albedo_texture = tex
	q.material = m; p.mesh = q
	return p

# ---------------------------------------------------------------- acting
## Freeze `n` at `at` seconds: a resting pose that breathing and the keyed beats play over.
func hold(n: String, at: float, blend := 0.3) -> void:
	if not has(n): return
	if cur != n: ap.play(_res(n), blend)
	cur = n; base = n; one_shot = false
	ap.seek(at, true); ap.speed_scale = 0.0
	held = true; hold_at = at; seq = []

## Mug up for a sip and back down to the seated hold (cs_sit_drink: lap 2.6 s, at the mouth 4.2-5.4 s).
func sip(drink_secs := 1.0) -> float:
	if not has("cs_sit_drink"): return 0.0
	if cur != "cs_sit_drink": hold("cs_sit_drink", 2.6, 0.2)
	ap.seek(3.0, true)
	seq = [[4.4 + drink_secs, 1.15], [2.6, -1.35], [2.6, 0.0]]
	ap.speed_scale = 1.15; held = true
	return (4.4 + drink_secs - 3.0) / 1.15 + (4.4 + drink_secs - 2.6) / 1.35

var _held_key := ""
var _held_rot: Array = []
var _held_pos: Array = []
func _held_pose() -> void:
	var key := "%s@%.3f" % [ap.current_animation, ap.current_animation_position]
	if key != _held_key:
		ap.seek(ap.current_animation_position, true)
		ap.advance(0.0)
		_held_key = key; _held_rot = []; _held_pos = []
		for i in sk.get_bone_count():
			_held_rot.append(sk.get_bone_pose_rotation(i)); _held_pos.append(sk.get_bone_pose_position(i))
	else:
		for i in sk.get_bone_count():
			sk.set_bone_pose_rotation(i, _held_rot[i]); sk.set_bone_pose_position(i, _held_pos[i])

func act(n: String) -> void:
	if ACTS.has(n): act_name = n; act_t = 0.0

func _seq_step() -> void:
	if seq.is_empty() or not ap.is_playing(): return
	var p := ap.current_animation_position
	var tgt: float = seq[0][0]
	var spd := ap.speed_scale
	if (spd > 0.0 and p >= tgt) or (spd < 0.0 and p <= tgt) or spd == 0.0:
		var nxt: Array = seq.pop_front()
		ap.speed_scale = float(nxt[1])
		if ap.speed_scale == 0.0: ap.seek(tgt, true); hold_at = tgt

func _curve(k: Array, u: float) -> float:
	if u <= float(k[0][0]): return float(k[0][1])
	for i in range(1, k.size()):
		if u <= float(k[i][0]):
			var a: Array = k[i - 1]; var b: Array = k[i]
			var f := (u - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.001)
			return lerpf(float(a[1]), float(b[1]), f * f * (3.0 - 2.0 * f))
	return float(k[-1][1])

## Breathing, the keyed beat, and stressed-syllable accents, on top of whatever the clip did.
func _acting(dt: float) -> void:
	var ch := {}
	if act_name != "":
		act_t += dt
		var a: Dictionary = ACTS[act_name]
		var u: float = minf(act_t, a.len)
		for k in a:
			if k in ["len", "hold"]: continue
			ch[k] = _curve(a[k], u)
		if act_t > a.len and not a.get("hold", false): act_name = ""
	# breathing: slow chest rise, a little in the shoulders
	var b := sin(t * 1.65) * breath
	ch["chest:x"] = ch.get("chest:x", 0.0) - b * 0.018
	ch["shoulders:z"] = ch.get("shoulders:z", 0.0) + (b * 0.5 + 0.5) * 0.02 * breath
	# head accents: a small dip when the mouth snaps open on a stressed vowel
	var shp := _lip_shape() if (has_face() and not lip_cues.is_empty()) else "X"
	if shp != _last_shape and shp in ["C", "D"] and _last_shape in ["A", "B", "X", "F", "G"]: accent = 1.0
	_last_shape = shp
	accent = maxf(0.0, accent - dt * 3.5)
	ch["head:x"] = ch.get("head:x", 0.0) + sin(accent * PI) * 0.05
	for k in ch:
		var v: float = ch[k]
		if absf(v) < 0.0001: continue
		var parts: PackedStringArray = (k as String).split(":")
		var ax: Vector3 = {"x": Vector3.RIGHT, "y": Vector3.UP, "z": Vector3.BACK}[parts[1]]
		if parts[0] == "shoulders":
			_rot_global("mixamorig:LeftShoulder", Vector3.BACK, v)
			_rot_global("mixamorig:RightShoulder", Vector3.BACK, -v)
		else:
			_rot_global(parts[0], ax, v)

# ---------------------------------------------------------------- face
func _setup_face(m: Node3D) -> void:
	face_mi = m.find_child("VeskFace", true, false) as MeshInstance3D
	if face_mi and face_mi.mesh:
		for i in face_mi.mesh.get_blend_shape_count(): bs[String(face_mi.mesh.get_blend_shape_name(i))] = i
	if sk:
		jaw_i = sk.find_bone("jaw"); eye_i = sk.find_bone("eye.R")
	for k in FACE_KEYS: mood_cur[k] = 0.0
	mood_cur["jaw"] = 0.0; mood_cur["clench"] = 0.0
	var lens := m.find_child("LensGlass", true, false) as MeshInstance3D
	if lens:
		var gm := StandardMaterial3D.new()
		gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; gm.albedo_color = Color(0.75, 0.9, 0.85, 0.12)
		gm.roughness = 0.03; gm.metallic_specular = 1.0; gm.clearcoat_enabled = true; gm.clearcoat = 1.0
		lens.material_override = gm; lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var eye := m.find_child("EyeR", true, false) as MeshInstance3D
	if eye and eye.get_active_material(0) is StandardMaterial3D:
		var em := (eye.get_active_material(0) as StandardMaterial3D).duplicate() as StandardMaterial3D
		em.roughness = 0.06; em.clearcoat_enabled = true; em.clearcoat = 1.0; em.clearcoat_roughness = 0.02
		em.rim_enabled = false
		eye.material_override = em; eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fur(m)
	for n in ["MouthBag", "Tongue", "TeethTop", "TeethBot"]:
		var mi := m.find_child(n, true, false) as GeometryInstance3D
		if mi: mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

var _head_ba: BoneAttachment3D
## A node riding his head bone (eyes height), for focus pulls and the lighting rig.
func head_node() -> Node3D:
	if _head_ba == null and sk:
		_head_ba = BoneAttachment3D.new(); _head_ba.bone_name = "head"; sk.add_child(_head_ba)
		var eyes := Node3D.new(); eyes.name = "Eyes"; eyes.position = Vector3(0, 0.13, 0.12); _head_ba.add_child(eyes)
	return _head_ba.get_node("Eyes") if _head_ba else self

const FUR_SHELLS := 14
## Shell fur on the body and face (shaders/fur_shell.gdshader), masked off armour and skin.
func _fur(m: Node3D) -> void:
	if not ResourceLoader.exists("res://textures/vesk_fur_mask.png"): return
	var mask: Texture2D = load("res://textures/vesk_fur_mask.png")
	var sh: Shader = load("res://shaders/fur_shell.gdshader")
	for n in ["Mesh_0", "VeskFace"]:
		var mi := m.find_child(n, true, false) as MeshInstance3D
		if mi == null or not (mi.get_active_material(0) is BaseMaterial3D): continue
		var base := (mi.get_active_material(0) as BaseMaterial3D).duplicate() as BaseMaterial3D
		var prev: Material = base
		for i in FUR_SHELLS:
			var sm := ShaderMaterial.new(); sm.shader = sh
			sm.set_shader_parameter("albedo_tex", base.albedo_texture)
			sm.set_shader_parameter("mask_tex", mask)
			sm.set_shader_parameter("shell", float(i + 1) / FUR_SHELLS)
			prev.next_pass = sm; prev = sm
		mi.set_surface_override_material(0, base)

func has_face() -> bool:
	return face_mi != null and not bs.is_empty()

## Brows, lids and mouth set; see MOODS.
func mood(n: String, secs := 0.35) -> void:
	if not MOODS.has(n): return
	mood_name = n; mood_want = MOODS[n]; mood_k = 3.0 / maxf(secs, 0.05)

## Lip sync for a voice line (cues from audio/voice/lipsync.json), locked to the voice player clock.
func lip(id: String) -> void:
	if lip_data.is_empty() and FileAccess.file_exists(LIPSYNC):
		var d = JSON.parse_string(FileAccess.get_file_as_string(LIPSYNC))
		if d is Dictionary: lip_data = d
	lip_cues = lip_data.get(id, [])
	lip_id = id; lip_clock = 0.0

func blink() -> void:
	if blink_t < 0.0: blink_t = 0.0

func _lip_shape() -> String:
	if force_viseme != "": return force_viseme
	if lip_cues.is_empty() or lip_clock < 0.0: return "X"
	var tt := lip_clock
	var snd := get_node_or_null("/root/Snd")
	var vp: AudioStreamPlayer = snd.get("voice_player") if snd else null
	if vp and vp.playing and vp.stream and vp.stream.resource_path.ends_with("/%s.ogg" % lip_id):
		tt = vp.get_playback_position() + 0.03   # a hair early reads as in sync
	var shape := "X"
	for c in lip_cues:
		if float(c[0]) <= tt: shape = String(c[1])
		else: break
	if tt > float(lip_cues[-1][0]) + 0.2: lip_cues = []; lip_clock = -1.0
	return shape

func _face(dt: float) -> void:
	if lip_clock >= 0.0: lip_clock += dt
	# mood keys ease toward the set
	var mk := 1.0 - exp(-mood_k * dt)
	for k in mood_cur: mood_cur[k] = lerpf(mood_cur[k], float(mood_want.get(k, 0.0)), mk)
	# visemes: fast attack, co-articulated
	var v: Dictionary = VISEMES.get(_lip_shape(), VISEMES.X)
	var vk := 1.0 - exp(-24.0 * dt)
	var clench: float = mood_cur.clench
	for k in vis_cur: vis_cur[k] = lerpf(vis_cur[k], float(v.get(k, 0.0)), vk)
	# blinks (sometimes a double), plus one when the head whips round
	blink_in -= dt
	if blink_in <= 0.0 and blink_t < 0.0:
		blink_t = 0.0; blink_double = randf() < 0.18
		blink_in = randf_range(2.2, 5.5)
	var bl := 0.0
	if blink_t >= 0.0:
		blink_t += dt
		bl = clampf(blink_t / 0.055, 0.0, 1.0) if blink_t < 0.055 else clampf(1.0 - (blink_t - 0.075) / 0.1, 0.0, 1.0)
		if blink_t > 0.175:
			blink_t = 0.0 if blink_double else -1.0; blink_double = false
	var look_down := clampf(-_pitch * 1.2, 0.0, 0.5)
	var lids: float = clampf(mood_cur.lids_half + look_down, 0.0, 1.0) * (1.0 - bl)
	var w := {}
	for k in FACE_KEYS: w[k] = mood_cur[k]
	w.blink = bl; w.lids_half = lids
	w.wide = w.wide + vis_cur.wide * (1.0 - clench * 0.5)
	w.pucker = w.pucker + vis_cur.pucker
	w.press = w.press + vis_cur.press
	w.sneer = w.sneer + vis_cur.sneer
	if face_mi:
		for k in w:
			if bs.has(k): face_mi.set_blend_shape_value(bs[k], clampf(w[k], 0.0, 1.2))
	if jaw_i >= 0:
		var jaw_deg: float = mood_cur.jaw + vis_cur.jaw * (1.0 - clench * 0.75) + talk * 0.4 * sin(t * 9.0) * float(lip_cues.is_empty())
		sk.set_bone_pose_rotation(jaw_i, sk.get_bone_rest(jaw_i).basis.get_rotation_quaternion() * Quaternion(Vector3.RIGHT, deg_to_rad(maxf(jaw_deg, 0.0))))

## Real right eyeball: aim at the look target (clamped), plus small darts.
func _eyes(dt: float, tp: Vector3) -> void:
	if eye_i < 0: return
	sacc_in -= dt
	if sacc_in <= 0.0:
		sacc_in = randf_range(0.35, 1.6)
		sacc = Vector2(randf_range(-0.09, 0.09), randf_range(-0.05, 0.05)) if randf() < 0.7 else Vector2.ZERO
	var rest_g := sk.get_bone_global_pose(sk.get_bone_parent(eye_i)) * sk.get_bone_rest(eye_i)
	var want := Vector2.ZERO
	if tp != Vector3.INF:
		var d := rest_g.basis.inverse() * ((sk.global_transform.affine_inverse() * tp) - rest_g.origin)
		# bone +Y is the pupil direction; x/z are its sides
		want = Vector2(clampf(atan2(d.x, d.y), -0.4, 0.4), clampf(atan2(d.z, d.y), -0.3, 0.3))
	eye_aim = eye_aim.lerp(want + sacc, 1.0 - exp(-30.0 * dt))
	var q := Quaternion(Vector3(0, 0, 1), -eye_aim.x) * Quaternion(Vector3(1, 0, 0), eye_aim.y)
	sk.set_bone_pose_rotation(eye_i, sk.get_bone_rest(eye_i).basis.get_rotation_quaternion() * q)

func _process(dt: float) -> void:
	t += dt
	if ap:
		if one_shot and ap.current_animation == _res(cur) and ap.current_animation_position >= ap.current_animation_length - 0.3:
			one_shot = false; cur = base; ap.speed_scale = 1.0; ap.play(_res(base), 0.3)
		if ap.speed_scale == 0.0 and sk: _held_pose()   # a frozen clip: restore it (the additive layers write on top)
		else: _held_key = ""; ap.advance(dt)
		_seq_step()
	if sk == null: return
	_rg_restore()
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
		var raw := atan2(d.x, d.z)
		# a target behind him would flip the turn between left and right every frame: stay on the current side
		if absf(raw) > 2.2: raw = (1.0 if _yaw >= 0.0 else -1.0) * 1.0
		want_y = clampf(raw, -1.0, 1.0)
		want_p = clampf(atan2(d.y, Vector2(d.x, d.z).length()), -0.45, 0.28)
	var k := 1.0 - exp(-6.0 * dt)
	_yaw = lerpf(_yaw, want_y + head_turn, k)
	_pitch = lerpf(_pitch, want_p, k)
	var nod := talk * (sin(t * 6.5) * 0.045 + sin(t * 2.7) * 0.03)
	if absf(_yaw) > 0.001 or absf(_pitch) > 0.001 or absf(nod) > 0.001:
		# share the turn down the spine so the head never twists into the shoulder armour
		_rot_global("spine", Vector3.UP, _yaw * 0.3)
		_rot_global("neck", Vector3.UP, _yaw * 0.3)
		_rot_global("head", Vector3.UP, _yaw * 0.4)
		_rot_global("neck", Vector3.RIGHT, -_pitch * 0.4)
		_rot_global("head", Vector3.RIGHT, -_pitch * 0.6 + nod)
	_acting(dt)
	if has_face():
		if absf(want_y - _yaw) > 0.6 and randf() < dt * 8.0: blink()
		_face(dt)
		_eyes(dt, tp)

## Rotate a bone about a model-space axis through its head (after the animation has posed it).
func _rot_global(bone: String, axis: Vector3, ang: float) -> void:
	var i := sk.find_bone(bone)
	if i < 0: return
	var p := sk.get_bone_parent(i)
	var pg: Basis = sk.get_bone_global_pose(p).basis if p >= 0 else Basis()
	var q0: Quaternion = sk.get_bone_pose_rotation(i)
	var q := (pg.inverse() * Basis(axis, ang) * pg * Basis(q0)).get_rotation_quaternion()
	if not _rg.has(i): _rg[i] = [q0, q]
	else: _rg[i][1] = q
	sk.set_bone_pose_rotation(i, q)

## Procedural offsets are layered on the animated pose each frame. When the clip doesn't rewrite a bone
## (a finished one-shot, a held pose, a clip without that track), last frame's offset would still be there
## and the next one would stack on it, so the upper body keeps turning. Undo whatever wasn't overwritten.
var _rg := {}   # bone index -> [pose before our offsets, pose after them]
func _rg_restore() -> void:
	for i in _rg:
		if sk.get_bone_pose_rotation(i).is_equal_approx(_rg[i][1]): sk.set_bone_pose_rotation(i, _rg[i][0])
	_rg.clear()

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
