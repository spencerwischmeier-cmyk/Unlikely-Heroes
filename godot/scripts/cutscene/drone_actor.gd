extends Node3D
## Dodger's body (design J1 + eye K1, 2026-11-27): the Meshy egg shell with side jet pods
## (models/chars/dodger_body.glb, eye-glass centre on the origin), one smooth glowing lens with no pupil,
## two eyelid shutters, and jet flames under the pods. No brows, and moods never change the eye colour
## (blue -> orange is a story beat): he emotes with the lids, the lens shape (size, squash, raise), body
## language (bounce, rattle, droop, sway, head turn) and the jets (bursts, sputter, roar).
## Shared by the Dodger follower (systems/dodger.gd) and the cutscenes (cutscene_dodger.gd).
##   emote("happy" | "angry" | "surprised" | "sad" | "smug" | "sleepy" | "neutral", seconds)
##   look_dir: a direction (-1..1 on x/y); he turns his whole head toward it (he wanders on his own otherwise).
##   eye_color, orange (0..1, Grudd's broadcast flicker), hover (bob), tilt (extra body tilt), dim (0..1 eye fade)
## The old shell is kept as models/chars/dodger_body_old.glb.

const M := preload("res://scripts/mats.gd")
const EYE := Color(0.08, 0.85, 1.0)
const ORANGE := Color(1.0, 0.42, 0.06)
const LENS_Z := 0.255         # lens/lid centre, in front of the origin (the shell's glass front is at ~0.287)
const LENS_R := 0.106
const LID_R := 0.113
const NOZZLES := [Vector3(0.483, -0.277, -0.01), Vector3(-0.483, -0.277, -0.01)]

var model: Node3D
var eye_mat: StandardMaterial3D
var eye_light: OmniLight3D
var eye_color := EYE
var orange := 0.0
var hover := 1.0
var tilt := Vector3.ZERO
var dim := 0.0
var glow_gain := 1.0       # overall lens brightness
var t := randf() * 10.0
var _flick := 0.0
var _flick_on := false
var jet_mats: Array = []
var jets: Array = []          # flame nodes (scaled for length)

# Moods never change the eye colour: blue -> orange is reserved for the story (Grudd's broadcast).
# Columns: 0 top lid close, 1 bottom lid close, 2 lid slant, 3 lens size, 4 lens width, 5 lens height,
# 6 lens raise, 7 body pitch (+ = nose down), 8 body roll, 9 jet power, 10 bob amount, 11 bob speed,
# 12 rattle (fast shake), 13 sink (drops lower), 14 head turn x, 15 head turn y, 16 sway (side wiggle), 17 glow
const FACES := {
	"neutral":   [0.1, 0.0, 0.0, 1.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0],
	"happy":     [0.0, 0.42, 0.0, 1.05, 1.08, 0.8, 0.012, -0.12, 0.0, 1.3, 1.5, 2.2, 0.0, -0.04, 0.0, 0.25, 0.10, 1.0],
	"angry":     [0.5, 0.15, 0.45, 0.88, 1.1, 0.75, -0.005, 0.2, 0.0, 1.5, 0.3, 1.0, 1.0, 0.0, 0.0, -0.15, 0.0, 1.0],
	"surprised": [0.0, 0.0, 0.0, 1.22, 1.0, 1.08, 0.0, -0.2, 0.0, 1.8, 0.6, 1.4, 0.0, -0.06, 0.0, 0.2, 0.0, 1.15],
	"sad":       [0.42, 0.0, -0.38, 0.85, 0.95, 0.95, -0.012, 0.38, 0.0, 0.45, 0.6, 0.45, 0.0, 0.14, 0.0, -0.6, 0.0, 0.9],
	"smug":      [0.48, 0.3, 0.12, 0.95, 1.05, 0.9, 0.0, -0.05, 0.22, 1.0, 0.8, 0.8, 0.0, 0.0, 0.7, 0.1, 0.0, 1.0],
	"sleepy":    [0.74, 0.28, 0.0, 0.95, 1.0, 1.0, 0.0, 0.18, 0.0, 0.6, 0.7, 0.35, 0.0, 0.08, 0.0, -0.3, 0.06, 0.75],
}
var face := "neutral"
var face_t := 0.0
var cur: Array = (FACES.neutral as Array).duplicate()
var lens: MeshInstance3D
var lid_top: MeshInstance3D
var lid_bot: MeshInstance3D
var look_dir := Vector2.ZERO
var _head_look := Vector2.ZERO
var _wander := Vector2.ZERO
var _wander_t := 1.0
var _blink := 2.5
var _bob_t := randf() * 10.0
var _burst := 0.0             # jet burst on a new face (decays)

func _ready() -> void:
	model = Node3D.new(); model.name = "DodgerModel"; add_child(model)
	if ResourceLoader.exists("res://models/chars/dodger_body.glb"):
		var body: Node3D = load("res://models/chars/dodger_body.glb").instantiate()
		body.name = "DodgerBody"; model.add_child(body)
	eye_mat = M.glow(EYE, 1.5); eye_mat.roughness = 1.0; eye_mat.metallic_specular = 0.0
	# soft radial falloff: the lens sphere is turned so its pole faces forward, so the texture's v runs from the
	# lens centre (bright) out to its rim (deeper colour); no pupil
	var g := Gradient.new(); g.offsets = PackedFloat32Array([0.0, 0.22, 0.42, 0.5]); g.colors = PackedColorArray([
		Color(1, 1, 1), Color(0.85, 0.85, 0.85), Color(0.5, 0.5, 0.5), Color(0.28, 0.28, 0.28)])
	var gt := GradientTexture2D.new(); gt.gradient = g; gt.width = 4; gt.height = 128
	gt.fill_from = Vector2(0, 0); gt.fill_to = Vector2(0, 1)
	eye_mat.emission_texture = gt; eye_mat.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	var sm := SphereMesh.new(); sm.radius = LENS_R; sm.height = LENS_R * 2.0; sm.radial_segments = 32; sm.rings = 16
	lens = MeshInstance3D.new(); lens.name = "Lens"; lens.mesh = sm; lens.material_override = eye_mat
	lens.position = Vector3(0, 0, LENS_Z); lens.rotation.x = PI * 0.5; lens.scale = Vector3(1, 0.45, 1)
	lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.add_child(lens)
	eye_light = OmniLight3D.new(); eye_light.light_color = EYE; eye_light.light_energy = 0.8; eye_light.omni_range = 2.2
	eye_light.shadow_enabled = false; eye_light.position = Vector3(0, 0, LENS_Z + 0.12)
	model.add_child(eye_light)
	_build_jets()
	_shadows(model)
	_build_lids()

## A glowing flame cone under each jet pod (points down; length follows the jet power).
func _build_jets() -> void:
	for p in NOZZLES:
		var holder := Node3D.new(); holder.position = p; model.add_child(holder)
		for layer in 2:
			var c := CylinderMesh.new(); c.top_radius = 0.05 if layer == 0 else 0.026; c.bottom_radius = 0.004
			c.height = 0.15 if layer == 0 else 0.08; c.radial_segments = 12; c.rings = 1
			var mi := MeshInstance3D.new(); mi.mesh = c
			var m := StandardMaterial3D.new(); m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD; m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_color = Color(0.1, 0.45, 1.0, 0.55) if layer == 0 else Color(0.45, 0.9, 1.0, 0.85)
			m.no_depth_test = false; m.cull_mode = BaseMaterial3D.CULL_DISABLED
			mi.material_override = m; mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var f := Node3D.new(); holder.add_child(f); f.add_child(mi)
			mi.position = Vector3(0, -c.height * 0.5, 0)
			jet_mats.append(m); jets.append(f)

## Lids: two shell-coloured half-shells (orange edge) inside the socket that swing over the lens (open = tucked back).
## The outer node flattens them like the lens; the pivot swings; the mesh slants.
func _build_lids() -> void:
	var shell := M.std(Color(0.86, 0.83, 0.76), 0.1, 0.5)   # shell-coloured lids read as eyelids, never as a dark pupil
	var edge_m := M.std(Color(0.95, 0.42, 0.1), 0.2, 0.45)
	for top in [true, false]:
		var flat := Node3D.new(); flat.position = Vector3(0, 0, LENS_Z); flat.scale = Vector3(1, 1, 0.5); model.add_child(flat)
		var piv := Node3D.new(); flat.add_child(piv)
		var hm := SphereMesh.new(); hm.radius = LID_R; hm.height = LID_R; hm.is_hemisphere = true; hm.radial_segments = 32; hm.rings = 8
		var mi := MeshInstance3D.new(); mi.mesh = hm; mi.material_override = shell
		piv.add_child(mi)
		var tm := TorusMesh.new(); tm.inner_radius = LID_R - 0.007; tm.outer_radius = LID_R + 0.004; tm.rings = 32; tm.ring_segments = 6
		var e := MeshInstance3D.new(); e.mesh = tm; e.material_override = edge_m; mi.add_child(e)
		if top: lid_top = mi
		else: lid_bot = mi

## Pull a face for `secs` seconds (then back to neutral). See FACES for the names.
func emote(name_: String, secs := 1.5) -> void:
	if not FACES.has(name_): return
	if name_ != face and (name_ == "happy" or name_ == "surprised" or name_ == "angry"): _burst = 1.0
	face = name_; face_t = secs

func _tick_face(dt: float) -> void:
	face_t -= dt
	if face_t <= 0.0 and face != "neutral": face = "neutral"
	var fname := "sleepy" if dim > 0.45 else face
	var want: Array = FACES.get(fname, FACES.neutral)
	var k := 1.0 - exp(-14.0 * dt)
	for i in cur.size(): cur[i] = lerpf(cur[i], want[i], k)
	# blinks, sometimes a double blink
	_blink -= dt
	var bl := 0.0
	if _blink < 0.13: bl = 1.0 - absf(_blink - 0.065) / 0.065
	if _blink <= 0.0: _blink = randf_range(2.0, 5.0) if randf() > 0.2 else 0.25
	var top_c := clampf(maxf(cur[0], bl), 0.0, 1.0)
	var bot_c := clampf(maxf(cur[1], bl * 0.6), 0.0, 1.0)
	(lid_top.get_parent() as Node3D).rotation = Vector3(lerpf(-PI * 0.5, PI * 0.47, top_c), 0, 0)
	lid_top.rotation = Vector3(0, 0, cur[2])
	(lid_bot.get_parent() as Node3D).rotation = Vector3(lerpf(PI * 0.5, -PI * 0.47, bot_c), 0, 0)
	lid_bot.rotation = Vector3(0, 0, PI - cur[2] * 0.5)
	lid_top.visible = top_c > 0.02; lid_bot.visible = bot_c > 0.02
	# lens shape: size, squash (wide and flat = squint/grin, tall = startled) and a small raise/drop
	var s: float = cur[3]
	lens.scale = Vector3(s * cur[4], 0.45, s * cur[5])
	lens.position.y = cur[6]
	# no pupil: he glances by turning his whole head (small saccades unless told where to look)
	_wander_t -= dt
	if _wander_t <= 0.0:
		_wander_t = randf_range(0.6, 2.2)
		_wander = Vector2(randf_range(-1, 1), randf_range(-0.6, 0.6)) if randf() < 0.5 else Vector2.ZERO
	var aim := look_dir if look_dir.length() > 0.01 else _wander * 0.5 + Vector2(cur[14], cur[15])
	_head_look = _head_look.lerp(aim, 1.0 - exp(-7.0 * dt))

func _shadows(n: Node) -> void:
	if n is GeometryInstance3D and n != lens: (n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for c in n.get_children(): _shadows(c)

func _process(dt: float) -> void:
	t += dt
	_tick_face(dt)
	_burst = maxf(0.0, _burst - dt * 2.2)
	# body language: bob size/speed, rattle, sinking, side sway, head pose
	_bob_t += dt * float(cur[11])
	var bob: float = sin(_bob_t * 2.3) * 0.07 * float(cur[10])
	if face == "happy": bob = absf(sin(_bob_t * 2.3)) * 0.09 * float(cur[10]) - 0.03   # bouncy hops
	var rat: float = cur[12]
	var shake := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * 0.012 * rat
	model.position = (Vector3(sin(_bob_t * 1.6) * float(cur[16]), bob - float(cur[13]), 0) + shake) * hover \
		+ Vector3(0, _burst * 0.06 * hover, 0)
	model.rotation = Vector3(sin(t * 1.3) * 0.05 * hover + tilt.x + cur[7] - _head_look.y * 0.22 + randf_range(-0.04, 0.04) * rat,
		tilt.y + _head_look.x * 0.3, sin(_bob_t * 1.7) * 0.08 * hover + tilt.z + cur[8] + sin(_bob_t * 1.6) * float(cur[16]) * 2.5)
	var c := eye_color
	if orange > 0.01:
		_flick -= dt
		if _flick <= 0.0:
			_flick = randf_range(0.03, 0.16); _flick_on = randf() < 0.75
		c = c.lerp(ORANGE, orange * (1.0 if _flick_on else 0.25))
	var glow: float = cur[17]
	var e := (1.0 - dim) * glow * glow_gain * (1.1 if not (orange > 0.01 and not _flick_on) else 0.45)
	eye_mat.albedo_color = Color.BLACK; eye_mat.emission = c; eye_mat.emission_energy_multiplier = e
	eye_light.light_color = c; eye_light.light_energy = 0.8 * (1.0 - dim) * glow
	# jets: flicker, follow the mood's power and bursts; die out when he's down (hover 0)
	var pw: float = (cur[9] + _burst * 1.4) * hover
	if face == "sad" and fmod(t, 1.7) < 0.12: pw *= 0.15        # sad: the jets sputter
	if face == "angry": pw *= 0.8 + 0.5 * absf(sin(t * 23.0))    # angry: the jets roar in hard pulses
	for f in jets:
		(f as Node3D).scale = Vector3(1.0, maxf(0.001, pw * randf_range(0.8, 1.15)), 1.0)
		(f as Node3D).visible = pw > 0.02
	for jm in jet_mats: (jm as StandardMaterial3D).albedo_color.a = clampf(pw, 0.0, 1.0) * randf_range(0.45, 0.85)
