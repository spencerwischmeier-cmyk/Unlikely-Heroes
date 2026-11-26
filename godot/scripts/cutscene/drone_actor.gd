extends Node3D
## Dodger's body: the drone model with a hover bob, a glowing eye (cyan, flickers orange during
## Grudd's broadcasts) and jet glows. Shared by the Dodger follower (systems/dodger.gd) and the cutscenes.
## The eye emotes: two shell lids (top and bottom) close, slant and squint, a pair of brow flaps tilt,
## and the pupil darts around and grows or shrinks.
##   emote("happy" | "angry" | "surprised" | "sad" | "smug" | "sleepy" | "neutral", seconds)
##   look_dir: set a direction (-1..1 on x/y) to aim the pupil; it wanders on its own otherwise.

const M := preload("res://scripts/mats.gd")
const EYE := Color(0.35, 0.95, 1.0)
const ORANGE := Color(1.0, 0.42, 0.06)
const BODY_OFFSET := Vector3(0, 0.015, -0.04)

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
var rotors: Array = []     # spinning prop pivots on the side pods (Meshy shell only)
var spin := 1.0            # 0..1 rotor speed; follows hover so a crashed Dodger's props wind down
const HUBS := [Vector3(-0.427, -0.03, 0.004), Vector3(0.423, -0.03, 0.006)]
static var _stripped: Mesh

# eye emotes: top lid close, bottom lid close, lid slant, brow tilt, brow lift, pupil size
const FACES := {
	"neutral": [0.08, 0.0, 0.0, 0.0, 0.0, 1.0],
	"happy": [0.0, 0.55, 0.0, -0.25, 0.02, 1.15],
	"angry": [0.42, 0.1, 0.45, 0.55, -0.025, 0.85],
	"surprised": [0.0, 0.0, 0.0, -0.15, 0.04, 0.6],
	"sad": [0.35, 0.0, -0.35, -0.5, 0.0, 1.1],
	"smug": [0.45, 0.3, 0.12, 0.25, -0.01, 0.95],
	"sleepy": [0.75, 0.25, 0.0, -0.2, -0.02, 0.9],
}
var face := "neutral"
var face_t := 0.0
var cur: Array = (FACES.neutral as Array).duplicate()
var lid_top: MeshInstance3D
var lid_bot: MeshInstance3D
var brows: Array = []
var pupil: Node3D
var pupil_ring: Node3D
var look_dir := Vector2.ZERO
var _wander := Vector2.ZERO
var _wander_t := 1.0
var _blink := 2.5

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
	_reskin()
	_shadows(model)
	_build_lids()

## The Meshy shell (models/chars/dodger_body.glb) replaces the primitive body; the eye parts stay and sit
## in its socket.
func _reskin() -> void:
	if not ResourceLoader.exists("res://models/chars/dodger_body.glb"): return
	const KEEP := ["drone_eye_glass", "drone_eye_ring", "drone_pupil", "drone_pupil_ring"]
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		if not (String(mi.name) in KEEP) and not jet_mats.has((mi as MeshInstance3D).material_override): (mi as MeshInstance3D).visible = false
	var body: Node3D = load("res://models/chars/dodger_body.glb").instantiate()
	body.name = "DodgerBody"; body.position = BODY_OFFSET
	model.add_child(body)
	# the Meshy shell has its prop blades baked in; strip them and add real ones that spin
	var shell := body.find_child("*", true, false) as MeshInstance3D
	if body is MeshInstance3D: shell = body as MeshInstance3D
	if shell == null:
		for c in body.find_children("*", "MeshInstance3D", true, false): shell = c; break
	if shell and shell.mesh:
		if _stripped == null: _stripped = _strip_blades(shell.mesh)
		shell.mesh = _stripped
		for i in 2: rotors.append(_rotor(shell, HUBS[i], 1.0 if i == 0 else -1.0))

## Drops the baked prop blades. models/chars/dodger_blades.json lists their triangle centres on a 2.5 mm grid
## (found offline as the thin connected pieces fanning out from each pod hub), so the hub caps stay.
static func _strip_blades(src: Mesh) -> Mesh:
	var keys := {}
	var raw = JSON.parse_string(FileAccess.get_file_as_string("res://models/chars/dodger_blades.json"))
	if raw is Array:
		for k in raw: keys[k] = true
	if keys.is_empty(): return src
	var out := ArrayMesh.new()
	for si in src.get_surface_count():
		var a: Array = src.surface_get_arrays(si)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		if idx.is_empty():
			idx = PackedInt32Array(); for k in v.size(): idx.append(k)
		var keep := PackedInt32Array()
		for k in range(0, idx.size(), 3):
			var c := (v[idx[k]] + v[idx[k + 1]] + v[idx[k + 2]]) / 3.0
			if absf(c.x) > 0.28 and c.y > -0.065 and c.y < 0.0:
				var q := (c / 0.0025).round()
				if keys.has("%d,%d,%d" % [int(q.x), int(q.y), int(q.z)]): continue
			keep.append(idx[k]); keep.append(idx[k + 1]); keep.append(idx[k + 2])
		a[Mesh.ARRAY_INDEX] = keep
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		out.surface_set_material(si, src.surface_get_material(si))
	return out

## A two-blade prop plus a faint motion-blur disc, spinning about its hub's up axis.
func _rotor(parent: Node3D, hub: Vector3, dir: float) -> Node3D:
	var piv := Node3D.new(); piv.position = hub; piv.set_meta("dir", dir); parent.add_child(piv)
	var bm := StandardMaterial3D.new(); bm.albedo_color = Color(0.92, 0.93, 0.95); bm.roughness = 0.35; bm.metallic = 0.2
	for k in 2:
		var b := MeshInstance3D.new(); var bx := BoxMesh.new(); bx.size = Vector3(0.115, 0.006, 0.034)
		b.mesh = bx; b.material_override = bm
		b.position = Vector3(0.068 if k == 0 else -0.068, 0, 0); b.rotation.x = 0.22 * (1.0 if k == 0 else -1.0)
		piv.add_child(b)
	var disc := MeshInstance3D.new(); var cm := CylinderMesh.new()
	cm.top_radius = 0.13; cm.bottom_radius = 0.13; cm.height = 0.003; cm.radial_segments = 32
	var dm := StandardMaterial3D.new(); dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; dm.albedo_color = Color(0.9, 0.95, 1.0, 0.0)
	disc.mesh = cm; disc.material_override = dm; disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	piv.add_child(disc); piv.set_meta("disc", dm)
	return piv

func _build_lids() -> void:
	var shell := StandardMaterial3D.new(); shell.albedo_color = Color(0.17, 0.19, 0.23); shell.metallic = 0.55; shell.roughness = 0.38
	var rim := StandardMaterial3D.new(); rim.albedo_color = Color(1.0, 0.45, 0.12); rim.roughness = 0.4
	var band := StandardMaterial3D.new(); band.albedo_color = Color(1.0, 0.42, 0.1); band.roughness = 0.4
	for top in [true, false]:
		var hm := SphereMesh.new(); hm.radius = 0.132; hm.height = 0.132; hm.is_hemisphere = true; hm.radial_segments = 24; hm.rings = 8
		var piv := Node3D.new(); piv.position = Vector3(0, 0, 0.2); piv.scale = Vector3(1, 1, 0.85); model.add_child(piv)
		var mi := MeshInstance3D.new(); mi.mesh = hm; mi.material_override = shell
		piv.add_child(mi)
		var tm := TorusMesh.new(); tm.inner_radius = 0.124; tm.outer_radius = 0.142; tm.rings = 24; tm.ring_segments = 6
		var edge := MeshInstance3D.new(); edge.mesh = tm; edge.material_override = rim; mi.add_child(edge)
		if top: lid_top = mi
		else: lid_bot = mi
	for sx in [-1.0, 1.0]:
		var bm := BoxMesh.new(); bm.size = Vector3(0.1, 0.026, 0.04)
		var b := MeshInstance3D.new(); b.mesh = bm; b.material_override = band
		b.position = Vector3(0.055 * sx, 0.172, 0.215); b.rotation.x = -0.35
		model.add_child(b); brows.append(b)
	pupil = model.find_child("drone_pupil", true, false) as Node3D
	if pupil is MeshInstance3D:
		var pm := StandardMaterial3D.new(); pm.albedo_color = Color(0.01, 0.04, 0.06); pm.roughness = 0.1; pm.metallic = 0.2
		(pupil as MeshInstance3D).material_override = pm
	pupil_ring = model.find_child("drone_pupil_ring", true, false) as Node3D

## Pull a face for `secs` seconds (then back to neutral). See FACES for the names.
func emote(name_: String, secs := 1.5) -> void:
	if not FACES.has(name_): return
	face = name_; face_t = secs

func _tick_face(dt: float) -> void:
	face_t -= dt
	if face_t <= 0.0 and face != "neutral": face = "neutral"
	var want: Array = FACES.get("sleepy" if dim > 0.45 else face, FACES.neutral)
	var k := 1.0 - exp(-14.0 * dt)
	for i in cur.size(): cur[i] = lerpf(cur[i], want[i], k)
	# blinks, sometimes a double blink
	_blink -= dt
	var bl := 0.0
	if _blink < 0.13: bl = 1.0 - absf(_blink - 0.065) / 0.065
	if _blink <= 0.0: _blink = randf_range(2.0, 5.0) if randf() > 0.2 else 0.25
	var top_c := clampf(maxf(cur[0], bl), 0.0, 1.0)
	var bot_c := clampf(maxf(cur[1], bl * 0.6), 0.0, 1.0)
	# lids: the hemispheres swing from tucked back (open) to over the eye (closed); slant tilts them
	(lid_top.get_parent() as Node3D).rotation = Vector3(lerpf(-PI * 0.5, PI * 0.47, top_c), 0, 0)
	lid_top.rotation = Vector3(0, 0, cur[2])
	(lid_bot.get_parent() as Node3D).rotation = Vector3(lerpf(PI * 0.5, -PI * 0.47, bot_c), 0, 0)
	lid_bot.rotation = Vector3(0, 0, PI - cur[2] * 0.5)
	lid_top.visible = top_c > 0.02; lid_bot.visible = bot_c > 0.02
	for i in brows.size():
		var b: MeshInstance3D = brows[i]
		var sx := -1.0 if i == 0 else 1.0
		b.rotation.z = -cur[3] * sx
		b.position.y = 0.172 + cur[4] - absf(cur[3]) * 0.01
	# pupil: wanders (saccades) unless told where to look, grows/shrinks with the mood
	_wander_t -= dt
	if _wander_t <= 0.0:
		_wander_t = randf_range(0.4, 1.8)
		_wander = Vector2(randf_range(-1, 1), randf_range(-0.6, 0.6)) if randf() < 0.6 else Vector2.ZERO
	var aim := look_dir if look_dir.length() > 0.01 else _wander
	var off := Vector3(aim.x * 0.03, aim.y * 0.025, 0)
	if pupil:
		pupil.position = pupil.position.lerp(Vector3(0, 0, 0.262) + off, 1.0 - exp(-25.0 * dt))
		pupil.scale = Vector3.ONE * float(cur[5])
	if pupil_ring:
		pupil_ring.position = pupil_ring.position.lerp(Vector3(0, 0, 0.26) + off, 1.0 - exp(-25.0 * dt))
		pupil_ring.scale = Vector3.ONE * float(cur[5])

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
	spin = move_toward(spin, clampf(hover, 0.0, 1.0), dt * 0.6)
	for r in rotors:
		r.rotation.y += dt * 38.0 * spin * float(r.get_meta("dir"))
		(r.get_meta("disc") as StandardMaterial3D).albedo_color.a = 0.14 * spin
	if lid_top: _tick_face(dt)
