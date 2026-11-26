extends Node3D
## Foreman Grudd for the cutscenes: a towering factory robot with a smokestack hat, a loudspeaker
## mouth and a door-sized clipboard. Uses models/chars/grudd.glb when it exists (scaled to `height`),
## otherwise builds a chunky procedural Grudd. `holo = true` renders him as a flickering orange
## broadcast hologram. Acting: `talk` (0..1, set while he speaks) bobs him, pumps the loudspeaker
## and waves his free arm; `gesture(name)` plays "point", "clipboard", "fist" or "shrug";
## `look_target` turns his head toward a node.

const M := preload("res://scripts/mats.gd")
const GLB := "res://models/chars/grudd.glb"

var height := 3.6
var holo := false
var talk := 0.0
var glitch := 0.0          # 0..1 extra hologram breakup
var look_target: Node3D
var t := randf() * 10.0
var root: Node3D           # everything visual
var head: Node3D
var mouth: Node3D
var arm_l: Node3D
var arm_r: Node3D
var stack: Node3D
var eye_mat: StandardMaterial3D
var holo_mat: ShaderMaterial
var ap: AnimationPlayer
var from_glb := false
var gest := ""
var gest_t := 0.0
var smoke_t := 0.0

const HOLO_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec4 tint : source_color = vec4(1.0, 0.55, 0.15, 1.0);
uniform float strength = 1.0;
uniform float glitch = 0.0;
uniform float base_y = 0.0;
varying vec3 wpos;
float h(float x) { return fract(sin(x * 91.7) * 43758.5); }
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float band = floor(wpos.y * 3.0 + TIME * 4.0);
	float j = step(0.93 - glitch * 0.3, h(band + floor(TIME * 12.0))) * (0.05 + glitch * 0.25);
	VERTEX.x += j * (h(band) - 0.5) * 2.0;
}
void fragment() {
	float fres = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.0);
	float scan = 0.65 + 0.35 * sin(wpos.y * 40.0 - TIME * 6.0);
	float roll = smoothstep(0.0, 0.05, fract(wpos.y * 0.15 - TIME * 0.35)) * 0.35 + 0.65;
	float flick = 0.88 + 0.12 * sin(TIME * 37.0) * sin(TIME * 13.0);
	float a = (0.18 + fres * 1.2) * scan * roll * flick * strength;
	ALBEDO = tint.rgb * a * 1.8;
	ALPHA = clamp(a, 0.0, 1.0);
}
"""

func _ready() -> void:
	root = Node3D.new(); root.name = "GruddRoot"; add_child(root)
	if ResourceLoader.exists(GLB):
		var m: Node3D = load(GLB).instantiate()
		root.add_child(m)
		from_glb = true
		var aabb := _aabb(m, Transform3D.IDENTITY)
		if aabb.size.y > 0.01:
			var s := height / aabb.size.y
			m.scale = Vector3.ONE * s
			m.position.y = -aabb.position.y * s
		ap = m.find_child("AnimationPlayer", true, false)
		if ap:
			for n in ["idle", "talk", "talk_big", "hip"]:
				if ap.has_animation(n): ap.get_animation(n).loop_mode = Animation.LOOP_LINEAR
			_glb_play("idle")
		head = m.find_child("Head", true, false) as Node3D
		stack = m.find_child("stack_top", true, false) as Node3D
		mouth = m.find_child("mouth", true, false) as Node3D
	else:
		_build()
	if holo: set_holo(true)

## Rough bounds of all meshes under `n`, in the space of n's parent.
func _aabb(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	var x := xf * (n as Node3D).transform if n is Node3D else xf
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var b: AABB = x * (n as MeshInstance3D).mesh.get_aabb()
		out = b; first = false
	for c in n.get_children():
		var cb := _aabb(c, x)
		if cb.size == Vector3.ZERO: continue
		if first: out = cb; first = false
		else: out = out.merge(cb)
	return out

func set_holo(on: bool) -> void:
	holo = on
	if on and holo_mat == null:
		holo_mat = ShaderMaterial.new()
		var sh := Shader.new(); sh.code = HOLO_SHADER; holo_mat.shader = sh
	_apply_mat(root, holo_mat if on else null)

func _apply_mat(n: Node, m: Material) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).material_override = m if m != null else (n as GeometryInstance3D).get_meta("mat", null)
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if m != null else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if n is Label3D: (n as Label3D).modulate = Color(1, 0.6, 0.25, 0.9) if m != null else Color.WHITE
	for c in n.get_children(): _apply_mat(c, m)

func set_strength(s: float) -> void:
	if holo_mat: holo_mat.set_shader_parameter("strength", s)

# ---------------------------------------------------------------- procedural Grudd
func _mi(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new(); mi.mesh = mesh; mi.material_override = mat; mi.set_meta("mat", mat)
	mi.position = pos; mi.rotation = rot; parent.add_child(mi); return mi

func _bx(parent: Node3D, size: Vector3, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new(); b.size = size; return _mi(parent, b, mat, pos, rot)

func _cy(parent: Node3D, r: float, h: float, mat: Material, pos: Vector3, rot := Vector3.ZERO, r2 := -1.0) -> MeshInstance3D:
	var c := CylinderMesh.new(); c.top_radius = r; c.bottom_radius = r if r2 < 0.0 else r2; c.height = h; c.radial_segments = 20
	return _mi(parent, c, mat, pos, rot)

func _sp(parent: Node3D, r: float, mat: Material, pos: Vector3) -> MeshInstance3D:
	var s := SphereMesh.new(); s.radius = r; s.height = r * 2.0; return _mi(parent, s, mat, pos)

func _build() -> void:
	var k := height / 3.6
	var body := Node3D.new(); body.scale = Vector3.ONE * k; root.add_child(body)
	var steel := M.std(Color(0.42, 0.45, 0.5), 0.75, 0.38)
	var dark := M.std(Color(0.14, 0.15, 0.18), 0.7, 0.45)
	var yel := M.std(Color(0.96, 0.72, 0.12), 0.35, 0.4)
	var rust := M.std(Color(0.55, 0.3, 0.18), 0.5, 0.6)
	var paper := M.std(Color(0.95, 0.93, 0.85), 0.0, 0.8)
	eye_mat = M.glow(Color(1, 0.5, 0.12), 5.0)
	# treads and hips: a squat factory base
	for s in [-1, 1]:
		_bx(body, Vector3(0.6, 0.55, 1.5), dark, Vector3(0.55 * s, 0.28, 0))
		for i in 3: _cy(body, 0.2, 0.62, steel, Vector3(0.55 * s, 0.24, -0.45 + i * 0.45), Vector3(0, 0, PI / 2))
	_bx(body, Vector3(1.0, 0.45, 0.8), steel, Vector3(0, 0.75, 0))
	# barrel chest with a hazard stripe and a FOREMAN badge
	_bx(body, Vector3(1.9, 1.35, 1.25), yel, Vector3(0, 1.55, 0))
	_bx(body, Vector3(1.95, 0.16, 1.3), dark, Vector3(0, 1.0, 0))
	_bx(body, Vector3(1.4, 0.75, 0.08), steel, Vector3(0, 1.62, 0.64))
	for i in 4: _bx(body, Vector3(0.12, 0.5, 0.02), dark, Vector3(-0.45 + i * 0.3, 1.62, 0.69), Vector3(0, 0, 0.5))
	var badge := Label3D.new(); badge.text = "FOREMAN"; badge.font_size = 64; badge.pixel_size = 0.004
	badge.position = Vector3(0, 2.1, 0.64); badge.modulate = Color(0.1, 0.1, 0.1); badge.outline_size = 0; body.add_child(badge)
	_sp(body, 0.32, rust, Vector3(-1.0, 2.05, 0)); _sp(body, 0.32, rust, Vector3(1.0, 2.05, 0))
	# middle-manager details: a big red necktie, a collar, chunky striped pauldrons, rivets, a gauge
	var tie := M.std(Color(0.75, 0.1, 0.1), 0.1, 0.5)
	_bx(body, Vector3(1.0, 0.12, 0.2), M.std(Color(0.95, 0.93, 0.88), 0.0, 0.6), Vector3(0, 2.2, 0.58))
	_bx(body, Vector3(0.22, 0.18, 0.08), tie, Vector3(0, 2.1, 0.68))
	_bx(body, Vector3(0.26, 0.7, 0.06), tie, Vector3(0, 1.7, 0.7), Vector3(0, 0, 0.05))
	_bx(body, Vector3(0.18, 0.18, 0.06), tie, Vector3(0.015, 1.33, 0.7), Vector3(0, 0, PI / 4))
	for sx in [-1, 1]:
		var pd := Node3D.new(); pd.position = Vector3(1.05 * sx, 2.25, 0); pd.rotation.z = -0.25 * sx; body.add_child(pd)
		_bx(pd, Vector3(0.75, 0.22, 0.85), yel, Vector3.ZERO)
		for i in 3: _bx(pd, Vector3(0.12, 0.23, 0.86), dark, Vector3(-0.24 + i * 0.24, 0.005, 0), Vector3(0, 0, 0.4))
		for z in [-0.3, 0.3]: _sp(body, 0.05, steel, Vector3(0.85 * sx, 1.15, 0.63 + z * 0.0))
	for i in 6: _sp(body, 0.045, steel, Vector3(-0.75 + i * 0.3, 2.15, 0.63))
	_cy(body, 0.16, 0.05, steel, Vector3(0.6, 1.25, 0.64), Vector3(PI / 2, 0, 0))
	_bx(body, Vector3(0.02, 0.12, 0.02), M.std(Color(0.8, 0.1, 0.1)), Vector3(0.62, 1.28, 0.67), Vector3(0, 0, -0.6))
	var pin := Label3D.new(); pin.text = "EMPLOYEE\nOF THE MONTH"; pin.font_size = 32; pin.pixel_size = 0.004
	pin.position = Vector3(-0.6, 1.3, 0.66); pin.modulate = Color(0.95, 0.8, 0.2); pin.outline_size = 4; body.add_child(pin)
	# head: a boxy monitor face, angry brow, loudspeaker mouth
	head = Node3D.new(); head.position = Vector3(0, 2.3, 0.05); body.add_child(head)
	_cy(head, 0.22, 0.25, dark, Vector3(0, 0.08, 0))
	_bx(head, Vector3(1.25, 0.85, 0.9), steel, Vector3(0, 0.62, 0))
	_bx(head, Vector3(1.05, 0.55, 0.05), dark, Vector3(0, 0.7, 0.46))
	for s in [-1, 1]:
		_bx(head, Vector3(0.26, 0.12, 0.03), eye_mat, Vector3(0.24 * s, 0.76, 0.49))
		_bx(head, Vector3(0.34, 0.07, 0.05), dark, Vector3(0.24 * s, 0.9, 0.5), Vector3(0, 0, -0.32 * s))
	mouth = Node3D.new(); mouth.position = Vector3(0, 0.42, 0.45); head.add_child(mouth)
	_cy(mouth, 0.22, 0.32, dark, Vector3(0, 0, 0.14), Vector3(PI / 2, 0, 0), 0.1)
	_cy(mouth, 0.2, 0.02, M.glow(Color(1, 0.35, 0.1), 1.5), Vector3(0, 0, 0.3), Vector3(PI / 2, 0, 0))
	for s in [-1, 1]: _cy(head, 0.12, 0.12, rust, Vector3(0.66 * s, 0.62, 0), Vector3(0, 0, PI / 2))
	# smokestack hat
	stack = Node3D.new(); stack.position = Vector3(0, 1.05, -0.05); head.add_child(stack)
	_cy(stack, 0.5, 0.08, dark, Vector3(0, 0, 0))
	_cy(stack, 0.26, 0.85, rust, Vector3(0, 0.45, 0), Vector3.ZERO, 0.3)
	_cy(stack, 0.31, 0.12, dark, Vector3(0, 0.88, 0))
	_cy(stack, 0.27, 0.08, yel, Vector3(0, 0.35, 0))
	# arms: the left one gestures, the right one holds the door-sized clipboard
	arm_l = Node3D.new(); arm_l.position = Vector3(1.05, 2.0, 0); body.add_child(arm_l)
	arm_r = Node3D.new(); arm_r.position = Vector3(-1.05, 2.0, 0); body.add_child(arm_r)
	for a in [arm_l, arm_r]:
		_bx(a, Vector3(0.32, 0.8, 0.32), steel, Vector3(0, -0.45, 0))
		_sp(a, 0.2, dark, Vector3(0, -0.88, 0))
		_bx(a, Vector3(0.28, 0.7, 0.28), yel, Vector3(0, -1.2, 0.12), Vector3(-0.35, 0, 0))
		_bx(a, Vector3(0.36, 0.3, 0.36), dark, Vector3(0, -1.58, 0.28))
	var board := Node3D.new(); board.position = Vector3(-0.1, -1.55, 0.5); board.rotation = Vector3(-0.25, 0.3, 0.05); arm_r.add_child(board)
	_bx(board, Vector3(0.9, 1.25, 0.06), M.std(Color(0.55, 0.38, 0.22), 0.0, 0.7), Vector3.ZERO)
	_bx(board, Vector3(0.78, 1.0, 0.02), paper, Vector3(0, -0.05, 0.04))
	_bx(board, Vector3(0.35, 0.12, 0.08), steel, Vector3(0, 0.6, 0.04))
	for i in 6: _bx(board, Vector3(0.5 - (i % 3) * 0.1, 0.03, 0.01), dark, Vector3(-0.05, 0.3 - i * 0.13, 0.055))
	arm_l.rotation.x = -0.15; arm_r.rotation.x = -0.35

const GLB_GESTURE := {"fist": "talk_big", "point": "wag", "clipboard": "hip", "shrug": "agree", "stomp": "stomp", "cheer": "cheer"}
var _glb_cur := ""

func _glb_play(n: String, blend := 0.3) -> void:
	if ap == null or not ap.has_animation(n) or n == _glb_cur: return
	_glb_cur = n; ap.play(n, blend)

func gesture(n: String) -> void:
	gest = n; gest_t = 0.0
	if from_glb and ap and ap.has_animation(GLB_GESTURE.get(n, "")):
		_glb_cur = ""; _glb_play(GLB_GESTURE[n], 0.25)

func _process(dt: float) -> void:
	t += dt; gest_t += dt
	var bob := sin(t * 1.6) * 0.03 + talk * (sin(t * 9.0) * 0.5 + 0.5) * 0.04
	root.position.y = bob * height
	if holo_mat:
		holo_mat.set_shader_parameter("glitch", glitch)
	if mouth: mouth.scale = Vector3.ONE * (1.0 + talk * (0.12 + 0.12 * sin(t * 23.0) * sin(t * 7.0)))
	if eye_mat: eye_mat.emission_energy_multiplier = 4.0 + talk * 3.0 * absf(sin(t * 11.0))
	if head:
		var yaw := 0.0
		var pitch := 0.0
		if is_instance_valid(look_target):
			var d := to_local(look_target.global_position) - head.position * (height / 3.6)
			yaw = clampf(atan2(d.x, d.z), -0.8, 0.8)
			pitch = clampf(-atan2(d.y - 0.0, Vector2(d.x, d.z).length()), -0.4, 0.4)
		pitch += talk * sin(t * 5.0) * 0.05
		if not from_glb:
			head.rotation.y = lerp_angle(head.rotation.y, yaw, 1.0 - exp(-5.0 * dt))
			head.rotation.x = lerpf(head.rotation.x, pitch, 1.0 - exp(-5.0 * dt))
	if from_glb:
		# base clip follows the talking; gesture clips run their length, then hand back
		if gest != "" and ap and ap.current_animation == GLB_GESTURE.get(gest, "") and ap.current_animation_position < ap.current_animation_length - 0.35:
			pass
		else:
			gest = ""
			_glb_play("talk" if talk > 0.5 else "idle", 0.4)
		_smoke(dt)
		return
	# arms: idle sway, talking wave, gestures
	var la := Vector3(-0.15 + sin(t * 1.3) * 0.04, 0, 0.1)
	var ra := Vector3(-0.35 + sin(t * 1.1) * 0.03, 0, -0.05)
	if talk > 0.01:
		la += Vector3(-0.6 + sin(t * 4.0) * 0.35, sin(t * 2.3) * 0.2, 0.25) * talk
	var gw := clampf(minf(gest_t / 0.25, (2.2 - gest_t) / 0.4), 0.0, 1.0)
	match gest:
		"point": la = la.lerp(Vector3(-1.45, -0.25, 0.15), gw)
		"fist": la = la.lerp(Vector3(-2.6 + sin(gest_t * 14.0) * 0.15, 0, 0.3), gw)
		"clipboard": ra = ra.lerp(Vector3(-1.5, 0.4, -0.2), gw)
		"shrug":
			la = la.lerp(Vector3(-0.5, 0, 0.9), gw); ra = ra.lerp(Vector3(-0.5, 0, -0.9), gw)
			if stack: stack.position.y = 1.05 + gw * 0.08
	if gest_t > 2.2: gest = ""
	arm_l.rotation = arm_l.rotation.lerp(la, 1.0 - exp(-8.0 * dt))
	arm_r.rotation = arm_r.rotation.lerp(ra, 1.0 - exp(-8.0 * dt))
	_smoke(dt)

## Smokestack puffs (not on the hologram).
func _smoke(dt: float) -> void:
	smoke_t -= dt
	if smoke_t <= 0.0 and stack and is_inside_tree() and not holo and visible:
		smoke_t = 0.5 + randf() * 0.4 - talk * 0.25
		var top := stack.global_position + (Vector3.ZERO if from_glb else Vector3(0, 0.95 * height / 3.6, 0))
		FX.puff(top, Color(0.35, 0.33, 0.33))
