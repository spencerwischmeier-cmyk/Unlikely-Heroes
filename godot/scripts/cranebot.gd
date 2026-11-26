extends Node3D
## Crane Bot: Foreman Grudd's heavy lifter and Skyharbor's boss. A tracked crane with a magnet on a jib.
##
## Phase 1 (100-50%)
##   Magnet slam  the magnet tracks Vesk while a red ring marks where it will land, then it drops.
##                The magnet drags the arena's steel crates toward the impact (they glow and rattle
##                while it charges); a sliding crate knocks Vesk over.
##   Rivet fan    a fan of hot rivets from the cab (the cab lights up and the boom dips first)
##   Work crew    (below 75%) drops Scrap Rollers. Wrench them back into the crane for big damage.
## Phase change (50%)
##   It drives to the middle, rips its jib off the turret and slams down outriggers. A grind rail
##   lights up along its track, running up to the cab.
## Phase 2 (50-0%)
##   Jib sweep    it lowers the jib (a ring shows its reach) and spins it like a sweeper: double jump
##                over it (or stand on the tracks)
##   Rivet fan, Work crew as before
##   Cab strike   grinding the track rail all the way up rams the cab: big bonus damage, the crane is
##                stunned for a few seconds (and takes extra damage), and the rail cools down
## The cab is the weak point. Intro: it drops out of the sky onto a warning ring. Death: it shakes
## itself apart, tips over and bursts.
##
## API used by story.gd: combat, player, spawn_roller (Callable(pos)), spawn(pos, area), signals
## half and dead_at(pos); also center()/damage()/dead for the "targets" group. Emits Game.boss_health.

signal dead_at(pos: Vector3)
signal half

const MagnetCrate := preload("res://scripts/magnet_crate.gd")
const NAME := "CRANE BOT"
const BOSS_HP := 200.0
const BOOM := 10.0
const JIB_Z := 1.4             # where the ripped-off jib sits on the turret (it reaches JIB_Z + BOOM)
const JIB_UP := 3.4            # jib height while idle in phase 2 (harmless, Vesk runs under it)
const JIB_DOWN := 1.15         # jib height while sweeping
const SWEEP_HIT_Y := 1.55      # Vesk's feet must be above this to clear the sweeping jib
const CAB_STRIKE := 24.0
const PULL_R := 12.0           # magnet reach for crates

var combat: Node3D
var player: CharacterBody3D
var spawn_roller: Callable
var area := Rect2()

var hp := BOSS_HP
var dead := true
var state := "off"
var st_t := 0.0
var t := 0.0
var flash := 0.0
var yaw := PI
var turn_yaw := 0.0
var pitch := 0.6
var mag := Vector3(0, 6, 0)
var lock := Vector3.ZERO
var sprays := 0
var last_attack := ""
var landed := false
var phase := 1
var pending_rip := false
var rip_from := Vector3.ZERO
var rip_stage := 0
var jib_h := JIB_UP
var sweep_dir := 1.0
var spin_v := 0.0
var swept := 0.0
var sweep_goal := TAU
var stun_t := 0.0
var rail_cd := 0.0
var restock_cd := 6.0
var said_slam := false
var force_next := ""           # debug: the next attack to pick
var intro_warn: Node3D

var turn := Node3D.new()
var boom := Node3D.new()
var tip := Node3D.new()
var cab: MeshInstance3D
var magnet := Node3D.new()
var cable := MeshInstance3D.new()
var warn := MeshInstance3D.new()
var warn_mat := StandardMaterial3D.new()
var eye_mat: StandardMaterial3D
var mag_mat: StandardMaterial3D
var cab_glow: StandardMaterial3D
var flash_mats: Array = []
var body := StaticBody3D.new()
var hitbox := StaticBody3D.new()
var stub := Node3D.new()       # the torn jib mount (smokes in phase 2)
var outriggers: Array = []
var rail: Dictionary = {}
var rail_path: Path3D
var rail_glow: StandardMaterial3D
var crates: Array = []
# Meshy skin (models/chars/crane_*.glb) over the old primitive build, which stays for hitboxes and pivots
const ScrapBurst := preload("res://scripts/chars/scrap_burst.gd")
var base_model: Node3D
var cab_model: Node3D
var mag_model: Node3D
var stacks: Array = []         # exhaust stack tops (smoke when damaged)
var skin_mats: Array = []      # livery materials for the scrap when it breaks
var cab_squash := 0.0
var smoke_t := 0.0

func _m(c: Color, metal := 0.5, rough := 0.4) -> StandardMaterial3D:
	var m := StandardMaterial3D.new(); m.albedo_color = c; m.metallic = metal; m.roughness = rough
	m.emission_enabled = true; m.emission = Color(1, 0.9, 0.8); m.emission_energy_multiplier = 0.0
	flash_mats.append(m)
	return m

func _box(parent: Node3D, size: Vector3, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var bm := BoxMesh.new(); bm.size = size
	var mi := MeshInstance3D.new(); mi.mesh = bm; mi.material_override = mat; mi.position = pos; mi.rotation = rot
	parent.add_child(mi); return mi

func _cyl(parent: Node3D, r: float, h: float, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var cm := CylinderMesh.new(); cm.top_radius = r; cm.bottom_radius = r; cm.height = h
	var mi := MeshInstance3D.new(); mi.mesh = cm; mi.material_override = mat; mi.position = pos; mi.rotation = rot
	parent.add_child(mi); return mi

func _ready() -> void:
	add_to_group("targets"); add_to_group("boss")
	var yellow := _m(Color(0.94, 0.7, 0.12), 0.45, 0.4)
	var red := _m(Color(0.6, 0.12, 0.16), 0.5, 0.4)
	var dark := StandardMaterial3D.new(); dark.albedo_color = Color(0.17, 0.19, 0.22); dark.metallic = 0.8; dark.roughness = 0.4
	var steel := StandardMaterial3D.new(); steel.albedo_color = Color(0.72, 0.76, 0.8); steel.metallic = 0.85; steel.roughness = 0.3
	var stripe := StandardMaterial3D.new(); stripe.albedo_color = Color(0.08, 0.08, 0.09); stripe.roughness = 0.6
	for s in [-1, 1]:
		_box(self, Vector3(0.95, 1.1, 5), dark, Vector3(1.6 * s, 0.55, 0))
		for i in range(-2, 3): _cyl(self, 0.38, 1.0, steel, Vector3(1.6 * s, 0.5, i * 0.95), Vector3(0, 0, PI / 2))
	_box(self, Vector3(2.6, 0.8, 4.2), yellow, Vector3(0, 1.2, 0))
	_box(self, Vector3(2.62, 0.18, 0.1), red, Vector3(0, 1.2, 2.12))
	for i in 4: _box(self, Vector3(0.3, 0.6, 0.02), stripe, Vector3(-0.9 + i * 0.6, 1.2, 2.13), Vector3(0, 0, 0.6))
	# outriggers (dropped in phase 2)
	for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var o := Node3D.new(); o.position = Vector3(c.x * 2.5, 0, c.y * 1.9); add_child(o)
		_box(o, Vector3(0.35, 1.0, 0.35), yellow, Vector3(0, 0.7, 0))
		_box(o, Vector3(1.0, 0.18, 1.0), dark, Vector3(0, 0.1, 0))
		_box(o, Vector3(1.2, 0.25, 0.3), dark, Vector3(-c.x * 0.6, 1.1, 0))
		o.visible = false; outriggers.append(o)
	turn.position.y = 1.6; add_child(turn)
	_cyl(turn, 1.55, 0.35, dark, Vector3(0, 0.1, 0))
	cab = _box(turn, Vector3(2.4, 2.1, 2.3), yellow, Vector3(0, 1.35, 0.2))
	eye_mat = StandardMaterial3D.new(); eye_mat.albedo_color = Color.BLACK; eye_mat.emission_enabled = true; eye_mat.emission = Color(1, 0.16, 0.16); eye_mat.emission_energy_multiplier = 6
	_box(turn, Vector3(1.8, 0.42, 0.12), eye_mat, Vector3(0, 1.65, 1.37))
	var el := OmniLight3D.new(); el.light_color = Color(1, 0.2, 0.15); el.light_energy = 4; el.omni_range = 6; el.position = Vector3(0, 1.65, 1.8); turn.add_child(el)
	cab_glow = StandardMaterial3D.new(); cab_glow.albedo_color = Color.BLACK; cab_glow.emission_enabled = true; cab_glow.emission = Color(1, 0.5, 0.15); cab_glow.emission_energy_multiplier = 0.5
	_box(turn, Vector3(1.4, 0.4, 0.1), cab_glow, Vector3(0, 0.95, 1.37))   # rivet port: glows before the fan
	for s in [-1, 1]:
		var cm := CylinderMesh.new(); cm.top_radius = 0.0; cm.bottom_radius = 0.16; cm.height = 0.6
		var h := MeshInstance3D.new(); h.mesh = cm; h.material_override = red; h.position = Vector3(0.95 * s, 2.55, 0.5); h.rotation.z = -0.4 * s; turn.add_child(h)
	_box(turn, Vector3(2.6, 1.4, 1.2), dark, Vector3(0, 1.0, -1.7))
	_box(turn, Vector3(2.62, 0.2, 1.22), yellow, Vector3(0, 1.2, -1.7))
	# jib mount and the stub left when the jib is ripped off
	stub.position = Vector3(0, 2.5, 0.8); turn.add_child(stub)
	_box(stub, Vector3(1.0, 0.5, 0.5), dark, Vector3.ZERO)
	boom.position = Vector3(0, 2.5, 0.8); turn.add_child(boom)
	for p in [Vector2(-0.35, -0.3), Vector2(0.35, -0.3), Vector2(-0.35, 0.3), Vector2(0.35, 0.3)]:
		_box(boom, Vector3(0.12, 0.12, BOOM), yellow, Vector3(p.x, p.y, BOOM / 2))
	for i in 10:
		var z := 0.5 + i * 0.95
		for y in [-0.3, 0.3]: _box(boom, Vector3(0.75, 0.06, 0.06), yellow, Vector3(0, y, z))
		for x in [-0.35, 0.35]: _box(boom, Vector3(0.06, 0.7, 0.06), yellow, Vector3(x, 0, z + 0.45), Vector3(0.55, 0, 0))
	tip.position = Vector3(0, -0.3, BOOM); boom.add_child(tip)
	_cyl(tip, 0.3, 0.3, dark, Vector3.ZERO, Vector3(0, 0, PI / 2))
	# magnet + cable + warning ring live in world space
	magnet.top_level = true; add_child(magnet)
	var mm := CylinderMesh.new(); mm.top_radius = 1.15; mm.bottom_radius = 1.25; mm.height = 0.5
	var mmi := MeshInstance3D.new(); mmi.mesh = mm; mmi.material_override = dark; magnet.add_child(mmi)
	mag_mat = StandardMaterial3D.new(); mag_mat.albedo_color = Color.BLACK; mag_mat.emission_enabled = true; mag_mat.emission = Color(1, 0.25, 0.19); mag_mat.emission_energy_multiplier = 3
	var tr := TorusMesh.new(); tr.inner_radius = 0.92; tr.outer_radius = 1.08
	var tri := MeshInstance3D.new(); tri.mesh = tr; tri.material_override = mag_mat; tri.position.y = -0.27; magnet.add_child(tri)
	var cm2 := CylinderMesh.new(); cm2.top_radius = 0.035; cm2.bottom_radius = 0.035; cm2.height = 1.0
	cable.mesh = cm2; cable.material_override = dark; cable.top_level = true; add_child(cable)
	var rm := TorusMesh.new(); rm.inner_radius = 1.9; rm.outer_radius = 2.3; rm.rings = 48
	warn_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; warn_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	warn_mat.albedo_color = Color(1, 0.19, 0.12, 0.7); warn_mat.no_depth_test = false
	warn.mesh = rm; warn.material_override = warn_mat; warn.top_level = true; warn.scale = Vector3(1, 0.05, 1); add_child(warn)
	# collision: the body blocks Vesk; the cab is hittable
	var cs := CollisionShape3D.new(); var sh := BoxShape3D.new(); sh.size = Vector3(4.2, 1.6, 4.4); cs.shape = sh; cs.position.y = 0.8
	body.add_child(cs); add_child(body)
	hitbox.collision_layer = 4; hitbox.collision_mask = 0
	var hcs := CollisionShape3D.new(); var hsh := BoxShape3D.new(); hsh.size = Vector3(2.6, 2.3, 2.5); hcs.shape = hsh
	hitbox.add_child(hcs); cab.add_child(hitbox)
	hitbox.add_to_group("targets_proxy")
	hitbox.set_meta("owner", self)
	_build_rail(steel)
	_skin()
	_hide()

## Swap the primitive body, cab and magnet for the Meshy models. The old meshes stay as hidden pivots
## (the cab box still carries the hitbox and center()); the eye and the rivet port keep their materials.
func _skin() -> void:
	if not ResourceLoader.exists("res://models/chars/crane_cab.glb"): return
	for n in get_children():
		if n is MeshInstance3D and n != cable and n != warn: (n as MeshInstance3D).visible = false
	for n in turn.get_children():
		if n is MeshInstance3D: (n as MeshInstance3D).visible = false
	for n in magnet.get_children():
		if n is MeshInstance3D and (n as MeshInstance3D).material_override != mag_mat: (n as MeshInstance3D).visible = false
	base_model = _skin_model("res://models/chars/crane_base.glb", self, Vector3.ZERO, Vector3(1.15, 0.7, 0.9))
	cab_model = _skin_model("res://models/chars/crane_cab.glb", turn, Vector3(0, -0.02, -0.25), Vector3.ONE * 1.25)
	mag_model = _skin_model("res://models/chars/crane_magnet.glb", magnet, Vector3(0, 0.72, 0), Vector3.ONE * 1.0)
	# the angry visor (eye_mat) and the rivet port (cab_glow) as overlays on the new cab
	for sx in [-1.0, 1.0]:
		var e := _box(turn, Vector3(0.62, 0.2, 0.08), eye_mat, Vector3(0.31 * sx, 1.93, 1.4), Vector3(0, 0, 0.2 * sx))
		e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var port := _box(turn, Vector3(1.0, 0.22, 0.06), cab_glow, Vector3(0, 1.28, 1.44))
	port.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for sx in [-1.0, 1.0]:
		var st := Node3D.new(); st.position = Vector3(0.41 * sx, 3.15, -1.1); turn.add_child(st); stacks.append(st)

func _skin_model(path: String, parent: Node3D, pos: Vector3, scl: Vector3) -> Node3D:
	var m: Node3D = load(path).instantiate()
	parent.add_child(m); m.position = pos; m.scale = scl
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		var g := mi as MeshInstance3D
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for i in g.mesh.get_surface_count():
			var src := g.get_active_material(i)
			if src is StandardMaterial3D:
				if skin_mats.size() < 4: skin_mats.append(src)
				var c := (src as StandardMaterial3D).duplicate() as StandardMaterial3D
				c.emission_enabled = true; c.emission = Color(1, 0.9, 0.8); c.emission_energy_multiplier = 0.0
				g.set_surface_override_material(i, c); flash_mats.append(c)
	return m

## Damage states: the stacks smoke below 2/3 health, the cab sparks and both stacks belch below 1/3,
## and it catches fire when nearly done. Also the cab "inhales" before a rivet fan.
func _damage_fx(dt: float) -> void:
	if cab_model:
		cab_squash = lerpf(cab_squash, 1.0 if (state == "spray" and st_t > 0.0 and st_t < 0.8) else 0.0, 1.0 - exp(-10.0 * dt))
		var k := cab_squash * (0.5 + 0.5 * sin(t * 30.0))
		cab_model.scale = Vector3.ONE * 1.25 * Vector3(1.0 + k * 0.05, 1.0 - k * 0.04, 1.0 + k * 0.05)
	if state in ["off", "intro"] or stacks.is_empty(): return
	# slam tell: the magnet crackles and its coil arcs while it charges over Vesk
	if state == "slam" and randf() < dt * (14.0 if st_t < 0.6 else 6.0):
		var a := randf() * TAU
		FX.sparks(magnet.global_position + Vector3(cos(a) * 1.2, -0.3, sin(a) * 1.2), Color(1, 0.45, 0.3), 5, 3.5)
	var f := hp / BOSS_HP
	smoke_t -= dt
	if f < 0.66 and smoke_t <= 0.0:
		smoke_t = 0.35 if f > 0.33 else 0.16
		var st: Node3D = stacks[0] if f > 0.33 else stacks.pick_random()
		FX.smoke_trail(st.global_position, 1.0 if f > 0.33 else 1.5)
		if f < 0.33 and randf() < 0.4:
			FX.sparks(center() + Vector3(randf_range(-1, 1), randf_range(-0.3, 0.8), randf_range(-1, 1)), Color(1, 0.75, 0.35), 6, 4.0)
		if f < 0.15 and randf() < 0.5:
			FX.explosion(center() + Vector3(randf_range(-1, 1), 0.6, randf_range(-1, 1)), 0.25)

## The track rail: from the ground behind the crane, along the right-hand track and up to the cab roof.
func _build_rail(steel: Material) -> void:
	rail_path = Path3D.new(); add_child(rail_path)
	var curve := Curve3D.new(); curve.bake_interval = 0.2
	var pts := [Vector3(2.1, 0.32, -7.2), Vector3(2.0, 0.6, -5.2), Vector3(1.75, 1.35, -3.1), Vector3(1.4, 2.3, -1.7),
		Vector3(0.8, 3.4, -0.7), Vector3(0.0, 4.25, 0.15)]
	for p in pts: curve.add_point(p)
	for i in curve.point_count:
		var prev: Vector3 = curve.get_point_position(maxi(i - 1, 0))
		var nxt: Vector3 = curve.get_point_position(mini(i + 1, curve.point_count - 1))
		curve.set_point_in(i, -(nxt - prev) / 6.0); curve.set_point_out(i, (nxt - prev) / 6.0)
	rail_path.curve = curve
	var tube := CSGPolygon3D.new(); tube.mode = CSGPolygon3D.MODE_PATH; tube.path_node = NodePath("..")
	var poly := PackedVector2Array()
	for k in 10: poly.append(Vector2(cos(k * TAU / 10), sin(k * TAU / 10)) * 0.13)
	tube.polygon = poly; tube.path_interval_type = CSGPolygon3D.PATH_INTERVAL_DISTANCE; tube.path_interval = 0.4
	tube.path_rotation = CSGPolygon3D.PATH_ROTATION_PATH_FOLLOW; tube.smooth_faces = true; tube.material = steel; tube.path_local = true
	rail_path.add_child(tube)
	rail_glow = StandardMaterial3D.new(); rail_glow.albedo_color = Color.BLACK; rail_glow.emission_enabled = true
	rail_glow.emission = Color(1.0, 0.19, 0.19); rail_glow.emission_energy_multiplier = 3.0
	var gt := CSGPolygon3D.new(); gt.mode = CSGPolygon3D.MODE_PATH; gt.path_node = NodePath("..")
	var gp := PackedVector2Array()
	for k in 6: gp.append(Vector2(cos(k * TAU / 6), sin(k * TAU / 6)) * 0.07 + Vector2(0, -0.17))
	gt.polygon = gp; gt.path_interval_type = CSGPolygon3D.PATH_INTERVAL_DISTANCE; gt.path_interval = 0.4
	gt.path_rotation = CSGPolygon3D.PATH_ROTATION_PATH_FOLLOW; gt.material = rail_glow; gt.path_local = true
	rail_path.add_child(gt)
	# struts holding the rail onto the track
	for u in [0.2, 0.42, 0.62]:
		var p := curve.sample_baked(curve.get_baked_length() * u)
		_box(rail_path, Vector3(0.12, maxf(0.2, p.y - 0.3), 0.12), steel, Vector3(p.x, p.y * 0.5 - 0.1, p.z))
	rail = { curve = curve, path = rail_path, locked = true, glow = rail_glow, length = curve.get_baked_length(), boss_rail = true }

func _rail_on(on: bool) -> void:
	var lv: Node = Game.level
	if lv == null or not ("rails" in lv): return
	var has: bool = lv.rails.has(rail)
	if on and not has: lv.rails.append(rail)
	elif not on and has:
		if player and player.get("riding") and player.get("rail") == rail: player.riding = false
		lv.rails.erase(rail)

func _rail_lock(locked: bool) -> void:
	rail.locked = locked
	rail_glow.emission = Color(1.0, 0.19, 0.19) if locked else Color(1.0, 0.7, 0.23)
	rail_glow.emission_energy_multiplier = 3.0 if locked else 7.0

func _hide() -> void:
	visible = false; magnet.visible = false; cable.visible = false; warn.visible = false
	dead = true; state = "off"
	body.process_mode = Node.PROCESS_MODE_DISABLED; hitbox.process_mode = Node.PROCESS_MODE_DISABLED
	_rail_on(false)

func spawn(pos: Vector3, area_: Rect2) -> void:
	area = area_
	position = Vector3(pos.x, 24, pos.z)
	state = "intro"; st_t = 4.2; t = 0; flash = 0; yaw = PI; turn_yaw = PI; pitch = 0.2; sprays = 0; last_attack = ""
	hp = BOSS_HP; dead = false; landed = false; phase = 1; pending_rip = false; stun_t = 0.0; jib_h = JIB_UP
	visible = true; magnet.visible = true; cable.visible = true
	boom.position = Vector3(0, 2.5, 0.8); boom.scale = Vector3.ONE; boom.rotation = Vector3.ZERO
	for o in outriggers: o.visible = false
	rotation = Vector3(0, yaw, 0)
	rail_path.visible = false; _rail_lock(true)
	body.process_mode = Node.PROCESS_MODE_INHERIT; hitbox.process_mode = Node.PROCESS_MODE_INHERIT
	eye_mat.emission = Color(1, 0.16, 0.16)
	intro_warn = FX.warn_ring(Vector3(pos.x, 0, pos.z), 3.6, 1.9, Color(1, 0.3, 0.15))
	Snd.at("crane_warn", Vector3(pos.x, 2, pos.z), 2, 0.0)
	_spawn_crates()

func _spawn_crates() -> void:
	for c in crates: if is_instance_valid(c): c.queue_free()
	crates.clear()
	if area.size.x <= 0.0: return
	var c := area.get_center()
	for o in [Vector2(-6, 3), Vector2(6, 3), Vector2(-13, -2), Vector2(13, -2), Vector2(-5, 9), Vector2(5, 9)]:
		_add_crate(Vector3(c.x + o.x, position.y if position.y < 5 else 0.0, c.y + o.y), false)

func _add_crate(p: Vector3, drop: bool) -> void:
	var k: AnimatableBody3D = MagnetCrate.new()
	k.player = player; k.combat = combat
	get_parent().add_child(k)
	k.global_position = p
	if drop: k.drop_in(p)
	crates.append(k)

func center() -> Vector3:
	return cab.global_position

func damage(amount: float, _point: Vector3, _dir: Vector3) -> bool:
	if dead or state in ["off", "intro", "rip", "dying"]: return false
	return _hurt(amount * (1.5 if stun_t > 0.0 else 1.0))

func _hurt(amount: float) -> bool:
	hp -= amount; flash = 1.0
	if amount >= 3.0: Snd.at("chars_crane_hurt", center(), 0, 0.1, 0.8)
	if phase == 1 and hp <= BOSS_HP * 0.5:
		hp = BOSS_HP * 0.5; pending_rip = true     # phase 2 always plays
	Game.boss_health.emit(NAME, maxf(0.0, hp / BOSS_HP))
	if hp <= 0.0:
		hp = 0.0; _start_dying()
		return true
	return false

## Kept for older callers.
func crew_down() -> void:
	pass

func _bots_in_arena() -> int:
	var n := 0
	for b in get_tree().get_nodes_in_group("bots"):
		if not b.dead and (area.size.x <= 0.0 or area.has_point(Vector2(b.global_position.x, b.global_position.z))): n += 1
	return n

func _physics_process(dt: float) -> void:
	if state == "off": return
	t += dt; st_t -= dt
	flash = maxf(0.0, flash - dt * 7.0)
	stun_t = maxf(0.0, stun_t - dt)
	for m in flash_mats: m.emission_energy_multiplier = flash * 1.5 + (0.12 + sin(t * 25.0) * 0.1 if stun_t > 0.0 else 0.0)
	crates = crates.filter(func(c): return is_instance_valid(c) and not c.dead)
	var hero := player.global_position
	var hero_flat := Vector3(hero.x, 0, hero.z)
	var to_hero := hero_flat - Vector3(position.x, 0, position.z)
	var hd := to_hero.length()
	var angry := hp < BOSS_HP * 0.25
	var speed := 1.35 if phase == 2 else 1.0
	if pending_rip and state not in ["intro", "rip", "dying"]: _start_rip()
	match state:
		"intro": _intro(dt, to_hero)
		"dying":
			if _dying(dt): return
		"rip": _rip(dt, to_hero)
		_:
			if Game.input_locked: return
			_fight(dt, hero, hero_flat, to_hero, hd, speed, angry)
	_damage_fx(dt)
	_pose(dt, hero)

# ---------- intro: drop out of the sky, roar ----------
func _intro(dt: float, to_hero: Vector3) -> void:
	if st_t > 3.0:
		pitch = 0.2
	elif not landed:
		position.y = maxf(0.0, position.y - dt * 34.0)
		if position.y == 0.0:
			landed = true
			FX.explosion(position + Vector3(0, 0.3, 0), 1.6); FX.ring(position + Vector3(0, 0.1, 0), Color(1, 0.6, 0.3), 2.2)
			FX.shake(1.6); Snd.at("crane_slam", position, 6)
			var d := player.global_position - position
			if Vector2(d.x, d.z).length() < 4.6 and d.y < 2.0: combat.hurt_player(1, position)
			Game.boss_health.emit(NAME, 1.0)
	else:
		# roar: boom up, eye flare, horn
		var k := clampf((3.0 - st_t) / 3.0, 0, 1)
		pitch = 0.2 + sin(k * PI) * 0.9
		turn_yaw += angle_difference(turn_yaw, atan2(to_hero.x, to_hero.z)) * (1.0 - exp(-2.0 * dt))
		if st_t < 2.2 and st_t + dt >= 2.2: Snd.at("crane_warn", center(), 4, 0.0); FX.shake(0.5); Snd.at("chars_crane_roar", center(), 4, 0.0)
		if st_t < 1.6 and st_t + dt >= 1.6: Snd.at("crane_move", position, 0)
		eye_mat.emission_energy_multiplier = 6.0 + sin(k * PI) * 14.0
	if st_t <= 0.0:
		state = "idle"; st_t = 0.8

# ---------- the fight ----------
func _fight(dt: float, hero: Vector3, hero_flat: Vector3, to_hero: Vector3, hd: float, speed: float, angry: bool) -> void:
	rail_cd -= dt
	if phase == 2 and rail.locked and rail_cd <= 0.0 and state != "stunned":
		_rail_lock(false); Snd.at("rail_unlock", position, -2)
	# phase 1: drive to keep a comfortable distance
	if phase == 1 and (state == "idle" or state == "spray"):
		var want := 1.0 if hd > 11.0 else (-1.0 if hd < 7.0 else 0.0)
		if want != 0.0:
			position += to_hero.normalized() * want * 1.6 * speed * dt
			yaw += angle_difference(yaw, atan2(to_hero.x, to_hero.z) + (PI if want < 0 else 0.0)) * (1.0 - exp(-1.5 * dt))
			if randf() < dt * 2.0: Snd.at("crane_move", position, -8, 0.1, 0.8)
	if area.size.x > 0:
		position.x = clampf(position.x, area.position.x + 3, area.end.x - 3)
		position.z = clampf(position.z, area.position.y + 3, area.end.y - 3)
	if state not in ["sweep_wind", "sweep", "sweep_end", "stunned"]:
		var aim := lock if (state == "slam" and st_t < 0.4) else hero_flat
		var want_turn := atan2(aim.x - position.x, aim.z - position.z)
		turn_yaw += angle_difference(turn_yaw, want_turn) * (1.0 - exp(-(3.5 if state == "slam" else 2.5) * speed * dt))
	# cab strike: Vesk grinds the track rail all the way up
	if phase == 2 and not rail.locked and player.get("riding") and player.get("rail") == rail:
		if float(player.get("rail_off")) >= float(rail.length) - 0.9: _cab_strike()
	if state == "idle" and st_t <= 0.0: _pick_attack(speed, angry)
	match state:
		"slam":
			if st_t > 0.4:
				lock = hero_flat
				var off := lock - Vector3(position.x, 0, position.z)
				var l := off.length()
				var min_r := 0.8 + BOOM * cos(1.1)
				if l < min_r: lock = Vector3(position.x, 0, position.z) + (off / l if l > 0.01 else Vector3(sin(turn_yaw), 0, cos(turn_yaw))) * min_r
			var reach := clampf(Vector2(lock.x - position.x, lock.z - position.z).length(), 4.0, 10.5)
			pitch += (minf(1.1, acos(clampf((reach - 0.8) / BOOM, -1, 1))) - pitch) * (1.0 - exp(-6.0 * dt))
			warn.global_position = Vector3(lock.x, position.y + 0.05, lock.z)
			warn_mat.albedo_color.a = (0.5 + sin(t * 20.0) * 0.2) if st_t > 0.4 else 0.95
			for c in crates: c.charge = 1.0 if _in_pull(c, lock) else 0.0
			if st_t <= 0.0: state = "drop"; st_t = 0.18
		"spray":
			pitch += (0.9 - pitch) * (1.0 - exp(-3.0 * dt))
			cab_glow.emission_energy_multiplier = 0.5 + clampf(1.0 - st_t / 0.8, 0, 1) * 10.0 * (0.7 + 0.3 * sin(t * 40.0))
			if st_t <= 0.0:
				var from := center() + Vector3(sin(turn_yaw) * 1.4, -0.1, cos(turn_yaw) * 1.4)
				var to := hero + Vector3(0, 0.9, 0)
				var base := atan2(to.x - from.x, to.z - from.z)
				var n := 7 if (phase == 2) else 5
				var spread := 1.0 if (phase == 2) else 0.8
				var dist := Vector2(to.x - from.x, to.z - from.z).length()
				for i in n:
					var a := base + (float(i) / (n - 1) - 0.5) * spread
					combat.enemy_shot(from, Vector3(from.x + sin(a) * dist, to.y, from.z + cos(a) * dist))
				sprays -= 1; st_t = 0.55; Snd.at("crane_spray", from, 2)
				FX.sparks(from, Color(1, 0.6, 0.3), 12, 5.0)
				cab_glow.emission_energy_multiplier = 0.5
				if sprays <= 0: state = "idle"; st_t = randf_range(1.4, 2.0) / speed
		"crew":
			if phase == 1: pitch += (0.5 - pitch) * (1.0 - exp(-3.0 * dt))
			if st_t <= 0.0:
				for i in (3 if angry else 2):
					var a := randf() * TAU
					var r := randf_range(4, 7)
					var x := clampf(hero.x + sin(a) * r, area.position.x + 1.5, area.end.x - 1.5)
					var z := clampf(hero.z + cos(a) * r, area.position.y + 1.5, area.end.y - 1.5)
					if spawn_roller.is_valid(): spawn_roller.call(Vector3(x, position.y, z))
				Snd.at("crane_warn", center(), -2, 0.15)
				state = "idle"; st_t = 1.2 / speed
		"sweep_wind":
			jib_h += (JIB_DOWN - jib_h) * (1.0 - exp(-6.0 * dt))
			turn_yaw -= sweep_dir * 0.45 * dt     # pull back before swinging
			if randf() < 0.4: FX.sparks(magnet.global_position, Color(1, 0.7, 0.3), 3, 3.0)
			if st_t <= 0.0: state = "sweep"; spin_v = 0.0; swept = 0.0; Snd.at("crane_move", position, 4, 0.0)
		"sweep":
			jib_h = JIB_DOWN
			spin_v = minf(spin_v + 5.0 * dt, 3.1 if not angry else 3.5)
			var prev := turn_yaw
			turn_yaw += sweep_dir * spin_v * dt
			swept += spin_v * dt
			_sweep_hit(prev, turn_yaw)
			_sweep_crates(prev, turn_yaw)
			if randf() < 0.8: FX.sparks(magnet.global_position + Vector3(0, -0.2, 0), Color(1, 0.75, 0.35), 4, 4.0)
			if randf() < dt * 3.0: Snd.at("crane_move", magnet.global_position, -2, 0.15, 0.3)
			if swept >= sweep_goal: state = "sweep_end"; st_t = 0.9
		"sweep_end":
			spin_v = maxf(0.0, spin_v - 6.0 * dt)
			var prev := turn_yaw
			turn_yaw += sweep_dir * spin_v * dt
			_sweep_hit(prev, turn_yaw)
			if st_t < 0.5: jib_h += (JIB_UP - jib_h) * (1.0 - exp(-4.0 * dt))
			if st_t <= 0.0: state = "idle"; st_t = randf_range(1.3, 1.8) / speed
		"stunned":
			jib_h += (0.45 - jib_h) * (1.0 - exp(-8.0 * dt))
			if randf() < dt * 10.0: FX.sparks(center() + Vector3(randf_range(-1, 1), randf_range(-0.5, 1), randf_range(-1, 1)), Color(1, 0.8, 0.4), 8, 5.0)
			if randf() < dt * 6.0: FX.smoke_trail(center() + Vector3(0, 1.2, 0), 1.5)
			if stun_t <= 0.0: state = "idle"; st_t = 0.6; Snd.at("crane_warn", center(), 0, 0.0)
		"idle":
			if phase == 1: pitch += (0.55 - pitch) * (1.0 - exp(-2.0 * dt))
			else: jib_h += (JIB_UP - jib_h) * (1.0 - exp(-3.0 * dt))
			# phase 1: restock the crates the magnet drags around
			restock_cd -= dt
			if phase == 1 and restock_cd <= 0.0 and crates.size() < 3 and area.size.x > 0.0:
				restock_cd = 9.0
				for i in 2:
					var c := area.get_center() + Vector2(randf_range(-12, 12), randf_range(-9, 9))
					var p := Vector3(c.x, 0, c.y)
					if p.distance_to(hero_flat) > 3.5 and p.distance_to(Vector3(position.x, 0, position.z)) > 4.0: _add_crate(p, true)
	# the slam lands
	if state == "drop" or state == "hold": _magnet_slam(dt, hero, speed)

func _pick_attack(speed: float, angry: bool) -> void:
	var opts: Array
	if phase == 1:
		opts = ["slam", "slam", "spray"]
		if hp < BOSS_HP * 0.75 and _bots_in_arena() < 3: opts.append("crew")
	else:
		opts = ["sweep", "sweep", "spray"]
		if _bots_in_arena() < 3: opts.append("crew")
	var nxt: String = opts.pick_random()
	if nxt == last_attack and randf() < 0.7:
		var others := opts.filter(func(o): return o != nxt)
		if not others.is_empty(): nxt = others.pick_random()
	if force_next != "" and not (force_next == "sweep" and phase == 1) and not (force_next == "slam" and phase == 2): nxt = force_next
	last_attack = nxt; state = nxt
	match nxt:
		"slam":
			st_t = 1.85 / speed; warn.visible = true; Snd.at("crane_warn", position, 0, 0.0)
			if not said_slam: said_slam = true; Game.say("boss_slam")
		"spray": st_t = 0.8; sprays = 2 if (phase == 2 or angry) else 1
		"crew": st_t = 1.2
		"sweep":
			state = "sweep_wind"; st_t = 1.4
			sweep_dir = 1.0 if randf() < 0.5 else -1.0
			sweep_goal = TAU * (1.5 if angry else 1.0)
			FX.warn_ring(Vector3(position.x, position.y, position.z), JIB_Z + BOOM + 1.2, 1.4, Color(1, 0.25, 0.12))
			Snd.at("crane_warn", center(), 3, 0.0)

func _in_pull(c: Node3D, at: Vector3) -> bool:
	return Vector2(c.global_position.x - at.x, c.global_position.z - at.z).length() < PULL_R

## The magnet drops, lands, holds, and lifts again. On landing it drags the crates in.
func _magnet_slam(dt: float, hero: Vector3, speed: float) -> void:
	if state == "drop":
		if mag.y <= position.y + 0.35:
			var hp_ := Vector3(mag.x, position.y, mag.z)
			FX.explosion(hp_ + Vector3(0, 0.3, 0), 1.2); FX.ring(hp_ + Vector3(0, 0.06, 0), Color(1, 0.3, 0.2), 1.3); FX.shake(1.3); Snd.at("crane_slam", hp_, 4)
			if Vector2(hero.x - hp_.x, hero.z - hp_.z).length() < 2.2 and hero.y < position.y + 1.4: combat.hurt_player(2, hp_)
			state = "hold"; st_t = 1.0 / speed; warn.visible = false
			_pull_crates(hp_)
	elif state == "hold":
		if st_t <= 0.0:
			state = "idle"; st_t = randf_range(1.3, 1.9) / speed
			for c in crates: c.charge = 0.0

## Drag every crate in reach toward the magnet: they stop in a ring around it.
func _pull_crates(at: Vector3) -> void:
	var any := false
	for c in crates:
		c.charge = 0.6
		if not _in_pull(c, at): continue
		var d: Vector3 = c.global_position - at; d.y = 0
		var stop := at + (d.normalized() if d.length() > 0.1 else Vector3.FORWARD) * 2.1
		c.pull(stop); any = true
	# other systems' crates (group "crate") get dragged too, without the knockdown
	for c in get_tree().get_nodes_in_group("crate"):
		if c.is_in_group("magnet_crate") or not (c is Node3D) or c.get("dead"): continue
		var d: Vector3 = (c as Node3D).global_position - at; d.y = 0
		if d.length() > PULL_R or d.length() < 2.2: continue
		var tw := (c as Node3D).create_tween()
		tw.tween_property(c, "global_position", (c as Node3D).global_position - d.normalized() * (d.length() - 2.1), 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		any = true
	if any: Snd.at("hook_latch", at, 2, 0.1)

## Crates in the jib's path get smashed (sprockets fly).
func _sweep_crates(a0: float, a1: float) -> void:
	for c in crates:
		var d := Vector2(c.global_position.x - position.x, c.global_position.z - position.z)
		var r := d.length()
		if r < 2.0 or r > JIB_Z + BOOM + 1.3: continue
		var ap := atan2(d.x, d.y)
		var da0 := angle_difference(a0, ap)
		var da1 := angle_difference(a1, ap)
		if (signf(da0) != signf(da1) and absf(da0) < 1.5) or absf(da1) * r < 0.9: c.smash()

## The jib swept from angle a0 to a1 this frame: hit Vesk if he's in its path and not above it.
func _sweep_hit(a0: float, a1: float) -> void:
	var p := player.global_position
	var d := Vector2(p.x - position.x, p.z - position.z)
	var r := d.length()
	if r < 2.0 or r > JIB_Z + BOOM + 1.3: return
	if p.y - position.y > SWEEP_HIT_Y or combat.invuln > 0.0: return
	var ap := atan2(d.x, d.y)
	var da0 := angle_difference(a0, ap)
	var da1 := angle_difference(a1, ap)
	var crossed := signf(da0) != signf(da1) and absf(da0) < 1.5
	if crossed or absf(da1) * r < 0.55:
		combat.hurt_player(2, position)
		var out := Vector3(d.x, 0, d.y).normalized()
		var tang := Vector3(cos(a1), 0, -sin(a1)) * sweep_dir
		player.velocity += out * 5.0 + tang * 6.0 + Vector3(0, 7.0, 0)
		FX.sparks(p + Vector3(0, 0.9, 0), Color(1, 0.8, 0.5), 16, 7.0); FX.shake(1.0)
		Snd.at("melee_hit", p, 2)

func _cab_strike() -> void:
	_hurt(CAB_STRIKE)
	if combat: combat.damage_number(center() + Vector3(0, 1.2, 0), CAB_STRIKE, hp <= 0.0)
	FX.explosion(center() + Vector3(0, 1.0, 0), 1.3, flash_mats.slice(0, 1)); FX.stop(0.12); FX.shake(1.6)
	Snd.at("explode_big", center(), 2, 0.05); Snd.at("melee_hit", center(), 4)
	# bounce Vesk off the cab and lock the rail for a while
	player.riding = false; player.rail_cool = 0.8
	var out := player.global_position - position; out.y = 0
	out = out.normalized() if out.length() > 0.1 else Vector3(sin(yaw), 0, cos(yaw))
	player.velocity = out * 7.0 + Vector3(0, 11.0, 0)
	player.jumps = 1
	_rail_lock(true); rail_cd = 8.0
	if hp > 0.0:
		state = "stunned"; stun_t = 3.0; warn.visible = false
		Snd.at("crane_slam", position, 0); Snd.at("crane_stun", position, 2)

# ---------- phase change ----------
func _start_rip() -> void:
	pending_rip = false
	state = "rip"; st_t = 4.0; rip_stage = 0; rip_from = position
	warn.visible = false
	for c in crates: c.charge = 0.0
	half.emit()
	Snd.at("crane_warn", center(), 4, 0.0)
	eye_mat.emission = Color(1, 0.4, 0.08)

func _rip(dt: float, to_hero: Vector3) -> void:
	var k := 4.0 - st_t   # time since the rip started
	var c := area.get_center() if area.size.x > 0 else Vector2(position.x, position.z)
	if k < 1.3:
		# drive to the middle, shaking
		var u := clampf(k / 1.2, 0, 1)
		position = Vector3(lerpf(rip_from.x, c.x, u * u * (3 - 2 * u)), position.y, lerpf(rip_from.z, c.y, u * u * (3 - 2 * u)))
		rotation.z = sin(t * 35.0) * 0.02
		pitch += (1.0 - pitch) * (1.0 - exp(-3.0 * dt))
		turn_yaw += angle_difference(turn_yaw, atan2(to_hero.x, to_hero.z)) * (1.0 - exp(-3.0 * dt))
		if randf() < dt * 12.0: FX.sparks(stub.global_position, Color(1, 0.7, 0.3), 6, 4.0)
		if randf() < dt * 3.0: Snd.at("crane_move", position, -2, 0.1, 0.2)
	elif rip_stage == 0:
		rip_stage = 1
		FX.explosion(stub.global_position, 1.2); FX.shake(1.4); FX.stop(0.08)
		Snd.at("crane_rip", stub.global_position, 4); Snd.at("explode_small", stub.global_position, 2)
	elif k < 2.3:
		# the jib tears free, flips up, then swings down into the cab's grip
		var u := clampf((k - 1.3) / 1.0, 0, 1)
		pitch = lerpf(1.0, 1.5, sin(u * PI)) if u < 0.5 else lerpf(1.5, 0.0, (u - 0.5) * 2.0)
		boom.position = Vector3(0, 2.5, 0.8).lerp(Vector3(0, JIB_UP - 1.6, JIB_Z), u)
		boom.scale = Vector3(1, lerpf(1.0, 1.6, u), 1)
		rotation.z = sin(t * 35.0) * 0.015
	elif rip_stage == 1:
		rip_stage = 2; pitch = 0.0; rotation.z = 0.0
		boom.position = Vector3(0, JIB_UP - 1.6, JIB_Z); boom.scale = Vector3(1, 1.6, 1)
		jib_h = JIB_UP
		for o in outriggers: o.visible = true; o.position.y = 1.2
		Snd.at("crane_move", position, 2)
	elif k < 2.8:
		for o in outriggers: o.position.y = maxf(0.0, o.position.y - dt * 6.0)
	elif rip_stage == 2:
		rip_stage = 3
		for o in outriggers:
			o.position.y = 0.0
			FX.puff(o.global_position + Vector3(0, 0.2, 0)); FX.ring(o.global_position + Vector3(0, 0.05, 0), Color(1, 0.7, 0.4), 0.5)
		FX.shake(1.2); Snd.at("crane_slam", position, 4)
		phase = 2
		rail_path.visible = true; _rail_lock(false); _rail_on(true); rail_cd = 0.0
		Snd.at("rail_unlock", position, 2)
		if Game.hud and Game.hud.has_method("show_banner"): Game.hud.show_banner("GRIND THE TRACK RAIL", "Ride it up and ram the cab. Double jump the jib!", Color(1, 0.75, 0.3))
	if st_t <= 0.0:
		state = "idle"; st_t = 1.0
		last_attack = "spray"   # open phase 2 with a sweep more often than not

# ---------- death ----------
func _start_dying() -> void:
	state = "dying"; st_t = 3.4; warn.visible = false
	_rail_on(false); rail_path.visible = false
	for c in crates: c.charge = 0.0
	Snd.at("crane_warn", center(), 4, 0.0); Snd.at("boss_defeat", center(), 6, 0.0)
	FX.stop(0.15); FX.shake(1.5)
	Game.boss_health.emit(NAME, 0.0)

## Returns true once the crane is gone.
func _dying(dt: float) -> bool:
	if randf() < dt * 14.0: FX.explosion(center() + Vector3(randf_range(-1.8, 1.8), randf_range(-1.5, 1.5), randf_range(-1.8, 1.8)), randf_range(0.4, 0.8))
	if randf() < dt * 10.0: FX.smoke_trail(position + Vector3(randf_range(-2, 2), 2.5, randf_range(-2, 2)), 2.0)
	if randf() < dt * 4.0: Snd.at("explode_small", center(), 0, 0.2, 0.1)
	var k := 3.4 - st_t
	rotation.z = sin(t * 30.0) * 0.03 + (0.0 if k < 2.2 else (k - 2.2) * 0.22)
	turn_yaw += dt * (0.5 + k * 0.8)
	if phase == 1: pitch = maxf(-0.25, pitch - dt * 0.5)
	else: jib_h = maxf(0.4, jib_h - dt * 2.0)
	eye_mat.emission_energy_multiplier = 8.0 if sin(t * 22.0) > 0.3 - k * 0.3 else 0.0
	_pose(dt, player.global_position)
	if st_t <= 0.0:
		var at := center()
		FX.death_burst(at, 2.6, flash_mats.slice(0, 2), Color(1, 0.75, 0.3)); FX.explosion(position + Vector3(0, 1, 0), 2.0)
		FX.shake(2.2); Snd.at("explode_big", at, 6, 0.0)
		ScrapBurst.burst(get_parent(), at, 2.4, skin_mats, 26)
		for c in crates: if is_instance_valid(c): c.smash(true)
		crates.clear()
		rotation.z = 0.0
		_hide(); dead_at.emit(at)
		return true
	return false

# ---------- pose: turret, jib, magnet, cable ----------
func _pose(dt: float, _hero: Vector3) -> void:
	rotation.y = yaw
	turn.rotation.y = turn_yaw - yaw
	if phase == 1 or state == "rip":
		boom.rotation.x = -pitch
	else:
		boom.rotation.x = 0.0
		boom.position.y = jib_h - 1.6
	var tip_w := tip.global_position
	var mag_y: float
	if phase == 1 and state != "rip":
		if state == "drop":
			mag_y = maxf(position.y + 0.3, mag.y - dt * 60.0)
		elif state == "hold":
			mag_y = position.y + 0.3
		else:
			mag_y = mag.y + (minf(tip_w.y - 1.5, position.y + 6.0) - mag.y) * (1.0 - exp(-3.0 * dt))
		mag = Vector3(tip_w.x, mag_y, tip_w.z)
	else:
		# hanging off the jib tip, dragging along the ground when the jib is low
		mag_y = maxf(position.y + 0.3, tip_w.y - 1.4)
		mag = Vector3(tip_w.x, mag.y + (mag_y - mag.y) * (1.0 - exp(-10.0 * dt)), tip_w.z)
	magnet.global_position = mag
	magnet.rotation.y = turn_yaw
	mag_mat.emission_energy_multiplier = 8.0 if (state in ["slam", "drop", "sweep_wind", "sweep"]) else 3.0
	var top := tip_w
	var bot := mag + Vector3(0, 1.5 if mag_model else 0.6, 0)
	cable.global_position = (top + bot) * 0.5
	cable.scale = Vector3(1, maxf(0.05, top.distance_to(bot)), 1)
	if state != "dying":
		var hot := phase == 2
		eye_mat.emission_energy_multiplier = (10.0 if hot else 6.0) + sin(t * (14.0 if hot else 5.0)) * 3.0
		if stun_t > 0.0: eye_mat.emission_energy_multiplier = 2.0 if sin(t * 18.0) > 0.0 else 0.0
	if phase == 2 and state != "dying" and randf() < dt * 4.0: FX.smoke_trail(stub.global_position + Vector3(0, 0.3, 0), 1.0)
	if intro_warn and not is_instance_valid(intro_warn): intro_warn = null
