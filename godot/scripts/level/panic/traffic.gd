extends Node3D
## Air traffic over Skyharbor in a panic. Built by panic.gd; nothing here collides.
## - Sky cars (models/panic/skycar.glb, one MultiMesh, hue varied per car in the shader) bunch up on loops:
##   rings weaving between the city towers, two high loops crossing right over the islands and a low ring under
##   them. The tower and district positions are recomputed from scripts/level/docks/sky.gd's seeds, so the lanes
##   bend round them (keep TOWER_SEED / DISTRICTS in step with sky.gd if that changes).
## - Every so often a car goes haywire: it honks, spins and spirals down trailing smoke, and somewhere far
##   below there's a crash. It rejoins its lane later.
## - The exodus: shuttles (models/panic/shuttle.glb), airships and the odd big freighter lift off from the
##   districts and tower tops and climb away off-world, each leaving a contrail of puffs.
## Sounds: panic_skycar_zoom_* when a car passes close, panic_skycar_honk_*, panic_far_crash, panic_ship_takeoff.

const M := preload("res://scripts/mats.gd")
const TOWER_SEED := 7
const DISTRICTS := [[Vector3(205, -6, 10), 26.0], [Vector3(170, 4, -120), 20.0], [Vector3(60, -12, 175), 22.0],
	[Vector3(-150, 0, -150), 24.0], [Vector3(-190, -10, 60), 20.0], [Vector3(110, 14, -210), 28.0],
	[Vector3(260, -24, 120), 30.0], [Vector3(-60, 8, -230), 22.0]]
const CAR_LEN := 3.6
const MAX_PUFFS := 700

const CAR_SHADER := """
shader_type spatial;
render_mode cull_back;
uniform sampler2D tex : source_color, filter_linear_mipmap;
varying float hue;
varying float glow;
void vertex() { hue = INSTANCE_CUSTOM.r; glow = INSTANCE_CUSTOM.g; }
vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
}
vec3 hsv2rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * clamp(p - 1.0, 0.0, 1.0);
}
void fragment() {
	vec3 c = texture(tex, UV).rgb;
	vec3 h = rgb2hsv(c);
	// only the painted body (strongly coloured) changes colour; chrome, glass and lights keep theirs
	if (h.y > 0.45) { h.x = fract(h.x + hue); c = hsv2rgb(h); }
	ALBEDO = c;
	ROUGHNESS = 0.35;
	METALLIC = 0.25;
	EMISSION = c * glow * 2.0;
}
"""

const PUFF_SHADER := """
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, blend_mix;
varying vec4 col;
void vertex() {
	col = COLOR;
	// face the camera
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0, 0, 0), vec4(0, length(MODEL_MATRIX[1].xyz), 0, 0), vec4(0, 0, 1, 0), vec4(0, 0, 0, 1));
}
void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float a = smoothstep(1.0, 0.25, d);
	ALBEDO = col.rgb;
	ALPHA = a * col.a;
}
"""

var L: Node3D
var rng := RandomNumberGenerator.new()
var towers: Array = []        # [Vector2 xz, radius, top y]
var lanes: Array = []         # { curve: Curve3D, len: float }
var cars: Array = []          # { lane, d, speed, side, up, hue, mode: "lane"|"haywire"|"down", t, pos, vel, spin, yaw_off }
var car_mm: MultiMesh
var ships: Array = []         # { node, glow: MeshInstance3D, p0, p1, p2, dur, u, puff_t, scale, big }
var puffs: MultiMesh
var puff_data: Array = []     # { pos: Vector3, vel: Vector3, age: float, life: float, size: float, col: Color }
var puff_next := 0
var haywire_t := 9.0
var ship_t := 1.0
var zoom_t := 0.0
var honk_t := 4.0
var t := 0.0
var car_fwd_yaw := 0.0        # turns the model so its nose points along +Z
var sfx: AudioStreamPlayer3D
var far_sfx: AudioStreamPlayer3D

func setup(level: Node3D) -> void:
	L = level
	rng.seed = 4711

func _ready() -> void:
	_rebuild_towers()
	_build_lanes()
	_build_cars()
	_build_puffs()
	_build_ships()
	sfx = AudioStreamPlayer3D.new(); sfx.bus = "World"; sfx.unit_size = 14.0; sfx.max_distance = 160.0; add_child(sfx)
	far_sfx = AudioStreamPlayer3D.new(); far_sfx.bus = "World"; far_sfx.unit_size = 60.0; far_sfx.max_distance = 900.0; add_child(far_sfx)

# ------------------------------------------------------------------ obstacles (mirrors sky.gd)
func _rebuild_towers() -> void:
	var r := RandomNumberGenerator.new(); r.seed = TOWER_SEED
	for i in 150:
		var ang := r.randf() * TAU
		var dist := 190.0 + pow(r.randf(), 0.8) * 620.0
		var p := Vector2(sin(ang) * dist, -cos(ang) * dist - 10)
		var rad := r.randf_range(5, 12) * (0.8 + dist / 400.0)
		var top := r.randf_range(-30, 45) + dist * 0.045
		var tiers := r.randi_range(1, 3)
		for k in tiers: r.randf_range(2, 6)
		var extra := rad * 0.9
		if r.randf() < 0.45: extra = rad * 0.4 + rad * r.randf_range(1.5, 3.0)
		towers.append([p, rad, top + extra])
	for d in DISTRICTS:
		var c: Vector3 = d[0]
		towers.append([Vector2(c.x, c.z), d[1] + 4.0, c.y + 66.0])

## push the points of a loop out of every tower they pass through at their height
func _avoid(pts: Array) -> Array:
	for it in 6:
		for i in pts.size():
			var p: Vector3 = pts[i]
			for tw in towers:
				if p.y > tw[2] + 6.0: continue
				var c: Vector2 = tw[0]
				var dv := Vector2(p.x, p.z) - c
				var need: float = tw[1] + 9.0
				if dv.length() < need:
					var n := dv.normalized() if dv.length() > 0.01 else Vector2(1, 0)
					var q := c + n * need
					p.x = q.x; p.z = q.y
			pts[i] = p
		# smooth so the pushes don't leave kinks
		var sm := []
		for i in pts.size():
			var a: Vector3 = pts[(i - 1 + pts.size()) % pts.size()]; var b: Vector3 = pts[(i + 1) % pts.size()]
			sm.append((pts[i] as Vector3) * 0.5 + (a + b) * 0.25)
		pts = sm
	return pts

func _curve(pts: Array) -> Curve3D:
	var c := Curve3D.new(); c.bake_interval = 2.0
	var n := pts.size()
	for i in n + 1:
		var p: Vector3 = pts[i % n]
		var tg: Vector3 = ((pts[(i + 1) % n] as Vector3) - (pts[(i - 1 + n) % n] as Vector3)) * 0.2
		c.add_point(p, -tg, tg)
	return c

func _build_lanes() -> void:
	var hub := Vector3(30, 0, -15)
	# rings through the tower city: [radius, height, wobble]
	for ring in [[215.0, 24.0, 18.0], [255.0, 42.0, 22.0], [300.0, 16.0, 26.0], [345.0, 58.0, 30.0], [185.0, 64.0, 10.0]]:
		var pts := []
		var n := 40
		var ph := rng.randf() * TAU
		for i in n:
			var a := TAU * i / n
			var rr: float = ring[0] + sin(a * 3.0 + ph) * ring[2]
			pts.append(Vector3(hub.x + cos(a) * rr, ring[1] + sin(a * 2.0 + ph) * 6.0, hub.z + sin(a) * rr))
		_add_lane(_avoid(pts))
	# two high loops crossing over the islands (elongated, tilted), and a low ring under them
	for k in 2:
		var pts := []
		var rot := 0.6 + k * 1.7
		for i in 32:
			var a := TAU * i / 32
			var v := Vector3(cos(a) * 230.0, 0, sin(a) * 70.0).rotated(Vector3.UP, rot)
			pts.append(hub + v + Vector3(0, 78.0 + k * 14.0 + sin(a * 2.0) * 8.0, 0))
		_add_lane(_avoid(pts))
	var low := []
	for i in 36:
		var a := TAU * i / 36
		low.append(hub + Vector3(cos(a) * 160.0, -46.0 + sin(a * 3.0) * 5.0, sin(a) * 170.0))
	_add_lane(_avoid(low))

func _add_lane(pts: Array) -> void:
	var c := _curve(pts)
	lanes.append({ curve = c, len = c.get_baked_length() })

# ------------------------------------------------------------------ cars
func _car_mesh() -> Array:
	var p := "res://models/panic/skycar.glb"
	if not ResourceLoader.exists(p): return []
	var n: Node3D = (load(p) as PackedScene).instantiate()
	var mi: MeshInstance3D = n.find_children("*", "MeshInstance3D", true, false)[0]
	var mesh: Mesh = mi.mesh
	var tex: Texture2D = null
	var mat := mesh.surface_get_material(0)
	if mat is StandardMaterial3D: tex = (mat as StandardMaterial3D).albedo_texture
	# normalise: centre it, scale to CAR_LEN along its longest horizontal axis
	var ab := mesh.get_aabb()
	var long_x := ab.size.x >= ab.size.z
	var s := CAR_LEN / maxf(ab.size.x if long_x else ab.size.z, 0.01)
	n.free()
	return [mesh, tex, s, ab, long_x]

func _build_cars() -> void:
	var cm := _car_mesh()
	var mesh: Mesh
	var sm := ShaderMaterial.new(); var sh := Shader.new(); sh.code = CAR_SHADER; sm.shader = sh
	var base := Transform3D.IDENTITY
	if cm.is_empty():
		var bm := CapsuleMesh.new(); bm.radius = 0.8; bm.height = CAR_LEN
		mesh = bm; base = Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3.ZERO)
	else:
		mesh = cm[0]
		if cm[1]: sm.set_shader_parameter("tex", cm[1])
		var ab: AABB = cm[3]
		var s: float = cm[2]
		# the model's nose: along -X when it is long in x (Meshy side view faces left), along +Z otherwise
		var b := Basis.IDENTITY.scaled(Vector3.ONE * s)
		if cm[4]: b = Basis(Vector3.UP, -PI / 2) * b
		base = Transform3D(b, b * -ab.get_center())
	car_mm = MultiMesh.new()
	car_mm.transform_format = MultiMesh.TRANSFORM_3D
	car_mm.use_custom_data = true
	car_mm.mesh = mesh
	var per_lane := [16, 14, 14, 12, 8, 9, 9, 10]
	var total := 0
	for i in lanes.size(): total += per_lane[i % per_lane.size()]
	car_mm.instance_count = total
	var mmi := MultiMeshInstance3D.new(); mmi.multimesh = car_mm; mmi.material_override = sm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	set_meta("car_base", base)
	for li in lanes.size():
		var ln: Dictionary = lanes[li]
		var n: int = per_lane[li % per_lane.size()]
		# platoons: cars bunch up in jams with gaps between
		var d: float = rng.randf() * ln.len
		for k in n:
			d += rng.randf_range(9.0, 16.0) if rng.randf() < 0.75 else rng.randf_range(60.0, 140.0)
			var dir := 1.0 if li % 2 == 0 else -1.0
			cars.append({ lane = li, d = fposmod(d, ln.len), speed = dir * rng.randf_range(16.0, 26.0), side = rng.randf_range(-3.0, 3.0),
				up = rng.randf_range(-2.0, 2.0), hue = rng.randf(), mode = "lane", t = 0.0, pos = Vector3.ZERO, vel = Vector3.ZERO,
				spin = 0.0, yaw = 0.0, glow = 0.0 })
	for i in cars.size(): car_mm.set_instance_custom_data(i, Color(cars[i].hue, 0, 0, 0))

func _lane_xf(c: Dictionary) -> Transform3D:
	var ln: Dictionary = lanes[c.lane]
	var cv: Curve3D = ln.curve
	var d: float = fposmod(c.d, ln.len)
	var p := cv.sample_baked(d, true)
	var q := cv.sample_baked(fposmod(d + signf(c.speed) * 4.0, ln.len), true)
	var fw := (q - p).normalized()
	if fw.length_squared() < 0.5: fw = Vector3.FORWARD
	var right := fw.cross(Vector3.UP).normalized()
	p += right * c.side + Vector3.UP * (c.up + sin(t * 1.3 + c.hue * 20.0) * 0.4)
	# bank into the turn
	var q2 := cv.sample_baked(fposmod(d + signf(c.speed) * 12.0, ln.len), true)
	var turn := right.dot((q2 - q).normalized())
	var b := Basis.looking_at(fw, Vector3.UP, true)
	b = b * Basis(Vector3.FORWARD, clampf(turn * 1.6, -0.6, 0.6))
	return Transform3D(b, p)

func _cars(dt: float, pp: Vector3) -> void:
	var base: Transform3D = get_meta("car_base")
	var near_d := 1e9
	for i in cars.size():
		var c: Dictionary = cars[i]
		var xf: Transform3D
		match c.mode:
			"lane":
				c.d += c.speed * dt
				xf = _lane_xf(c)
				c.pos = xf.origin
				c.vel = -xf.basis.z * absf(c.speed)
			"haywire":
				c.t += dt
				c.vel += Vector3(0, -9.0, 0) * dt
				c.vel = c.vel.rotated(Vector3.UP, dt * 1.4)
				c.pos += c.vel * dt
				c.spin += dt * (4.0 + c.t * 2.0)
				var fw: Vector3 = c.vel.normalized()
				var b := Basis.looking_at(fw, Vector3.UP, true) * Basis(Vector3.FORWARD, c.spin) * Basis(Vector3.RIGHT, sin(c.t * 7.0) * 0.4)
				xf = Transform3D(b, c.pos)
				if rng.randf() < dt * 22.0: _puff(c.pos, Vector3(0, 1.5, 0), Color(0.22, 0.2, 0.2, 0.75), 2.2, 3.5)
				if rng.randf() < dt * 6.0: _puff(c.pos, Vector3(0, 2, 0), Color(1.0, 0.55, 0.15, 0.9), 1.2, 0.5)
				if c.pos.y < -150.0:
					c.mode = "down"; c.t = rng.randf_range(12.0, 25.0)
					if c.pos.distance_to(pp) < 650.0: _sound(far_sfx, "panic_far_crash", c.pos, 0.0)
			"down":
				c.t -= dt
				xf = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.001), Vector3(0, -2000, 0))
				if c.t <= 0.0: c.mode = "lane"
		car_mm.set_instance_transform(i, xf * base)
		if c.mode == "lane":
			var dd: float = (c.pos as Vector3).distance_to(pp)
			if dd < near_d: near_d = dd
	# a whoosh when one zips past close
	zoom_t -= dt
	if near_d < 26.0 and zoom_t <= 0.0:
		zoom_t = 2.5
		for c in cars:
			if c.mode == "lane" and (c.pos as Vector3).distance_to(pp) < 26.0:
				_sound(sfx, "panic_skycar_zoom_%d" % rng.randi_range(1, 2), c.pos, -2.0); break
	# honks from the jams within earshot
	honk_t -= dt
	if honk_t <= 0.0:
		honk_t = rng.randf_range(2.5, 6.0)
		var cands := []
		for c in cars:
			if c.mode == "lane" and (c.pos as Vector3).distance_to(pp) < 140.0: cands.append(c)
		if not cands.is_empty():
			var c: Dictionary = cands.pick_random()
			Snd.at("panic_skycar_honk_%d" % rng.randi_range(1, 2), c.pos, -4.0)
	# haywire: a car within sight but not too close loses it
	haywire_t -= dt
	if haywire_t <= 0.0:
		haywire_t = rng.randf_range(9.0, 18.0)
		var cands := []
		for c in cars:
			if c.mode != "lane": continue
			var dd: float = (c.pos as Vector3).distance_to(pp)
			if dd > 50.0 and dd < 260.0 and c.pos.y > pp.y + 5.0: cands.append(c)
		if not cands.is_empty():
			var c: Dictionary = cands.pick_random()
			c.mode = "haywire"; c.t = 0.0; c.spin = 0.0
			c.vel = c.vel * 0.7 + Vector3(rng.randf_range(-4, 4), 4.0, rng.randf_range(-4, 4))
			Snd.at("panic_skycar_honk_%d" % rng.randi_range(1, 2), c.pos, 0.0)
			_puff(c.pos, Vector3.ZERO, Color(1.0, 0.8, 0.3, 1.0), 3.0, 0.35)

func _sound(p: AudioStreamPlayer3D, n: String, pos: Vector3, db: float) -> void:
	var path := "res://audio/sfx/%s.ogg" % n
	if not ResourceLoader.exists(path): return
	p.stream = load(path); p.volume_db = db; p.global_position = pos; p.pitch_scale = rng.randf_range(0.92, 1.08); p.play()

# ------------------------------------------------------------------ contrails and smoke
func _build_puffs() -> void:
	var q := QuadMesh.new(); q.size = Vector2(1, 1)
	var sm := ShaderMaterial.new(); var sh := Shader.new(); sh.code = PUFF_SHADER; sm.shader = sh
	puffs = MultiMesh.new(); puffs.transform_format = MultiMesh.TRANSFORM_3D; puffs.use_colors = true; puffs.mesh = q
	puffs.instance_count = MAX_PUFFS
	var mmi := MultiMeshInstance3D.new(); mmi.multimesh = puffs; mmi.material_override = sm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-3000, -2000, -3000), Vector3(6000, 4000, 6000))
	add_child(mmi)
	puff_data.resize(MAX_PUFFS)
	for i in MAX_PUFFS:
		puff_data[i] = { pos = Vector3.ZERO, vel = Vector3.ZERO, age = 1.0, life = 0.0, size = 0.0, col = Color(1, 1, 1, 0) }
		puffs.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.001), Vector3(0, -3000, 0)))

func _puff(pos: Vector3, vel: Vector3, col: Color, size: float, life: float) -> void:
	var p: Dictionary = puff_data[puff_next]
	puff_next = (puff_next + 1) % MAX_PUFFS
	p.pos = pos; p.vel = vel; p.age = 0.0; p.life = life; p.size = size; p.col = col

func _puffs(dt: float) -> void:
	for i in MAX_PUFFS:
		var p: Dictionary = puff_data[i]
		if p.life <= 0.0: continue
		p.age += dt
		var u: float = p.age / p.life
		if u >= 1.0:
			p.life = 0.0
			puffs.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.001), Vector3(0, -3000, 0)))
			continue
		p.pos += p.vel * dt
		var s: float = p.size * (0.6 + u * 1.8)
		puffs.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3(s, s, s)), p.pos))
		var c: Color = p.col
		puffs.set_instance_color(i, Color(c.r, c.g, c.b, c.a * (1.0 - u) * minf(1.0, u * 8.0 + 0.2)))

# ------------------------------------------------------------------ the exodus
func _ship_model(kind: String) -> Node3D:
	var paths := { shuttle = "res://models/panic/shuttle.glb", airship = "res://models/docks/airship.glb", freighter = "res://models/docks/freighter.glb" }
	var p: String = paths[kind]
	if not ResourceLoader.exists(p): return null
	return (load(p) as PackedScene).instantiate()

func _build_ships() -> void:
	var glow := M.glow(Color(1.0, 0.6, 0.25), 9.0)
	for k in 9:
		var kind := "shuttle" if k < 6 else ("airship" if k < 8 else "freighter")
		var holder := Node3D.new(); add_child(holder)
		var m := _ship_model(kind)
		var length: float = {"shuttle": 13.0, "airship": 16.0, "freighter": 34.0}[kind]
		if m:
			holder.add_child(m)
			var ab := _aabb(m)
			var long_x := ab.size.x >= ab.size.z
			var s := length / maxf(ab.size.x if long_x else ab.size.z, 0.01)
			m.scale = Vector3.ONE * s
			m.position = -ab.get_center() * s
			if long_x: m.rotation.y = -PI / 2; m.position = m.position.rotated(Vector3.UP, -PI / 2)
		# thruster glow at the tail (+Z is the tail: ships fly toward -Z)
		var gs := SphereMesh.new(); gs.radius = length * 0.07; gs.height = length * 0.14
		var g := MeshInstance3D.new(); g.mesh = gs; g.material_override = glow; g.position = Vector3(0, -length * 0.05, length * 0.5)
		holder.add_child(g)
		holder.visible = false
		ships.append({ node = holder, glow = g, kind = kind, len = length, p0 = Vector3.ZERO, p1 = Vector3.ZERO, p2 = Vector3.ZERO,
			dur = 1.0, u = 2.0, puff_t = 0.0, last = Vector3.ZERO, wait = rng.randf_range(0.0, 20.0) })
	# some start already on the way up, so the sky is busy from the first second
	for s in ships:
		if rng.randf() < 0.6: _launch(s, rng.randf_range(0.1, 0.7))

func _aabb(n: Node) -> AABB:
	var out := AABB(); var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null: continue
		var ab: AABB = m.mesh.get_aabb()
		var xf := Transform3D.IDENTITY; var c: Node = m
		while c != n and c is Node3D:
			xf = (c as Node3D).transform * xf; c = c.get_parent()
		ab = xf * ab
		out = ab if first else out.merge(ab); first = false
	return out

func _launch(s: Dictionary, u0 := 0.0) -> void:
	# from a district deck or a tower top, straight up, then pitching over and climbing away from the islands
	var from: Vector3
	if rng.randf() < 0.55:
		var d: Array = DISTRICTS[rng.randi() % DISTRICTS.size()]
		var a := rng.randf() * TAU
		from = (d[0] as Vector3) + Vector3(cos(a), 0, sin(a)) * (d[1] as float) * 0.5 + Vector3(0, 2, 0)
	else:
		var tw: Array = towers[rng.randi() % 150]
		var c: Vector2 = tw[0]
		from = Vector3(c.x, (tw[2] as float) + 4.0, c.y)
	var out := Vector3(from.x - 30, 0, from.z + 15).normalized()
	out = out.rotated(Vector3.UP, rng.randf_range(-0.6, 0.6))
	s.p0 = from
	s.p1 = from + Vector3(0, rng.randf_range(50, 80), 0)
	s.p2 = from + out * rng.randf_range(400, 700) + Vector3(0, rng.randf_range(550, 800), 0)
	s.dur = rng.randf_range(26.0, 38.0) * (1.6 if s.kind == "freighter" else 1.0)
	s.u = u0; s.last = _bez(s, u0)
	s.node.visible = true

func _bez(s: Dictionary, u: float) -> Vector3:
	var e := u * u * (1.6 - 0.6 * u)          # slow lift-off, then speeding up
	var a: Vector3 = (s.p0 as Vector3).lerp(s.p1, e); var b: Vector3 = (s.p1 as Vector3).lerp(s.p2, e)
	return a.lerp(b, e)

func _ships(dt: float, pp: Vector3) -> void:
	ship_t -= dt
	for s in ships:
		if s.u >= 1.0:
			s.node.visible = false
			s.wait -= dt
			if s.wait <= 0.0 and ship_t <= 0.0:
				ship_t = rng.randf_range(2.5, 5.0)
				s.wait = rng.randf_range(4.0, 14.0)
				_launch(s)
				if s.p0.distance_to(pp) < 420.0: _sound(far_sfx, "panic_ship_takeoff", s.p0, 2.0 if s.kind == "freighter" else -2.0)
			continue
		s.u += dt / s.dur
		var p := _bez(s, minf(s.u, 1.0))
		var v: Vector3 = (p - (s.last as Vector3)) / maxf(dt, 0.001)
		s.last = p
		var n: Node3D = s.node
		n.position = p
		if v.length() > 0.5:
			var fw := v.normalized()
			# nose up while climbing, but never fully vertical
			var flat := Vector3(fw.x, 0, fw.z)
			if flat.length() < 0.2: flat = (s.p2 - s.p0) * Vector3(1, 0, 1)
			var look := (flat.normalized() + Vector3(0, clampf(fw.y, -0.2, 0.9), 0)).normalized()
			n.basis = n.basis.slerp(Basis.looking_at(look, Vector3.UP), 1.0 - exp(-2.0 * dt)) if n.basis.is_conformal() else Basis.looking_at(look, Vector3.UP)
		var g: MeshInstance3D = s.glow
		g.scale = Vector3.ONE * (1.0 + 0.25 * sin(t * 40.0 + s.len))
		# contrail
		s.puff_t -= dt
		if s.puff_t <= 0.0:
			s.puff_t = 0.07 if s.kind != "freighter" else 0.05
			var tail: Vector3 = n.global_transform * Vector3(0, 0, s.len * 0.55)
			var size: float = s.len * 0.32
			_puff(tail, Vector3(rng.randf_range(-0.5, 0.5), 0.6, rng.randf_range(-0.5, 0.5)), Color(1, 1, 1, 0.55), size, 7.0)
			if rng.randf() < 0.35: _puff(tail, Vector3.ZERO, Color(1.0, 0.7, 0.35, 0.8), size * 0.5, 0.4)

func _process(dt: float) -> void:
	if not is_visible_in_tree(): return
	t += dt
	var pl: Node3D = Game.player
	var pp: Vector3 = pl.global_position if pl else Vector3.ZERO
	_cars(dt, pp)
	_ships(dt, pp)
	_puffs(dt)
