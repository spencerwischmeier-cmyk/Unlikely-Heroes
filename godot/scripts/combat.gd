extends Node3D
## Combat: Vesk's four weapons, the bots' shots, sprocket / repair cell / ammo pickups and floating
## damage numbers. Targets are nodes in the "targets" group with `damage(amount, point, dir)`, `dead`
## and `center()`.
##
## Weapons (ids match Game.unlock / Gizmart stock):
##   arc_lancer     rapid bolts, never runs dry but overheats          V5 "ARC STORM": bolts arc to a 2nd bot
##   scatter_bloom  a fan of pellets, short range, big hits            V5 "FULL BLOOM": pellets pierce, petal ring
##   thump_lobber   arcing bomb that bounces once and thumps (splash)  V5 "THUMP CLUSTER": splits into 3 bomblets
##   seeker_hive    a swarm of homing micro-drones                     V5 "QUEEN HIVE": 6 drones that re-target
## Each weapon levels V1-V5 through kills (weapon XP). Ammo, XP and the held weapon are saved in
## Game.data.weapons / Game.data.weapon. A weapon is usable once Game.has(id).

signal nuts_changed(total: int)
signal hull_changed(hull: int, healed: bool)
signal hit_marker(kill: bool)
signal weapon_changed(id: String)
signal ammo_changed(id: String, ammo: int, max_ammo: int)
signal weapon_xp(id: String, level: int, frac: float)
signal weapon_level_up(id: String, level: int)

const MAX_HULL := 8
var player: CharacterBody3D
var nuts := 0
var hull := MAX_HULL
var invuln := 0.0
var nut_chain := 0
var nut_last := 0

const ORDER := ["arc_lancer", "scatter_bloom", "thump_lobber", "seeker_hive"]
const WEAPONS := {
	"arc_lancer": { name = "ARC LANCER", v5 = "ARC STORM", color = Color(0.45, 0.95, 1.0), ammo = [0, 0, 0, 0, 0],
		blurb = "Rapid bolts. Never runs dry, but mind the heat." },
	"scatter_bloom": { name = "SCATTER BLOOM", v5 = "FULL BLOOM", color = Color(1.0, 0.45, 0.65), ammo = [24, 28, 32, 36, 42],
		blurb = "A fan of petal shrapnel. Get close." },
	"thump_lobber": { name = "THUMP LOBBER", v5 = "THUMP CLUSTER", color = Color(0.5, 1.0, 0.45), ammo = [10, 12, 14, 16, 20],
		blurb = "Lobs bouncing thump-bombs over cover." },
	"seeker_hive": { name = "SEEKER HIVE", v5 = "QUEEN HIVE", color = Color(1.0, 0.8, 0.25), ammo = [30, 35, 40, 45, 55],
		blurb = "Homing micro-drones find the bots for you." },
}
## kills needed (in total) to reach V2, V3, V4, V5
const XP_STEPS := [5, 12, 22, 35]
const GOLD := Color(1.0, 0.82, 0.3)

var current := "arc_lancer"
var wheel_open := false          # set by the weapon wheel: no firing while it is up
var wdata := {}                  # id -> { ammo: int, xp: int }

# Arc Lancer: never runs dry but overheats
var heat := 0.0
var overheated := false
var cool := 0.0
const LANCER_INTERVAL := 0.12
const LANCER_DMG := 1.0

var bolts: Array = []       # player projectiles { node, vel, life, dmg, wpn, kind, ... }
var shots: Array = []       # enemy shots
var pickups: Array = []     # { node, vel, t, kind }

var bolt_mesh: CapsuleMesh
var pellet_mesh: SphereMesh
var bomb_mesh: SphereMesh
var drone_mesh: PrismMesh
var bolt_mat: StandardMaterial3D
var gold_mat: StandardMaterial3D
var pellet_mat: StandardMaterial3D
var bomb_mat: StandardMaterial3D
var bomb_glow: StandardMaterial3D
var drone_mat: StandardMaterial3D
var shot_mat: StandardMaterial3D
var nut_mesh: TorusMesh
var nut_mat: StandardMaterial3D
var cell_mat: StandardMaterial3D
var ammo_mesh: BoxMesh
var ammo_mat: StandardMaterial3D

func _ready() -> void:
	Game.nuts_changed.connect(_on_nuts)
	Game.item_unlocked.connect(_on_unlocked)
	# bots sometimes drop an ammo canister (only when an owned weapon is short)
	Game.bot_killed.connect(func(_b, pos, _k): if randf() < 0.25: drop_ammo(pos + Vector3(0, 0.3, 0)))
	bolt_mesh = CapsuleMesh.new(); bolt_mesh.radius = 0.05; bolt_mesh.height = 1.0
	pellet_mesh = SphereMesh.new(); pellet_mesh.radius = 0.07; pellet_mesh.height = 0.14; pellet_mesh.radial_segments = 8; pellet_mesh.rings = 4
	bomb_mesh = SphereMesh.new(); bomb_mesh.radius = 0.2; bomb_mesh.height = 0.4
	drone_mesh = PrismMesh.new(); drone_mesh.size = Vector3(0.16, 0.26, 0.08)
	bolt_mat = _glow(Color(0.6, 0.98, 1.0), 8.0)
	gold_mat = _glow(Color(1.0, 0.85, 0.45), 9.0)
	pellet_mat = _glow(Color(1.0, 0.5, 0.7), 7.0)
	bomb_mat = StandardMaterial3D.new(); bomb_mat.albedo_color = Color(0.25, 0.55, 0.3); bomb_mat.metallic = 0.6; bomb_mat.roughness = 0.35
	bomb_glow = _glow(Color(0.6, 1.0, 0.4), 6.0)
	drone_mat = _glow(Color(1.0, 0.8, 0.3), 6.0)
	shot_mat = _glow(Color(1.0, 0.25, 0.15), 8.0)
	nut_mesh = TorusMesh.new(); nut_mesh.inner_radius = 0.07; nut_mesh.outer_radius = 0.17; nut_mesh.ring_segments = 6; nut_mesh.rings = 6
	nut_mat = StandardMaterial3D.new(); nut_mat.albedo_color = Color(1.0, 0.76, 0.24); nut_mat.metallic = 1.0; nut_mat.roughness = 0.22
	nut_mat.emission_enabled = true; nut_mat.emission = Color(0.4, 0.22, 0.0); nut_mat.emission_energy_multiplier = 0.6
	cell_mat = _glow(Color(0.3, 1.0, 0.55), 3.0)
	ammo_mesh = BoxMesh.new(); ammo_mesh.size = Vector3(0.34, 0.22, 0.22)
	ammo_mat = _glow(Color(1.0, 0.55, 0.2), 2.5)
	_load_weapons()
	if OS.get_cmdline_user_args().has("--all-weapons"):
		for id in ORDER: Game.data.unlocked[id] = true
		_load_weapons()

func _glow(c: Color, e: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new(); m.albedo_color = Color.BLACK; m.emission_enabled = true; m.emission = c; m.emission_energy_multiplier = e
	return m

func _on_nuts(n: int) -> void:
	nuts = n; nuts_changed.emit(n)

# ---------- weapon state, levels and saving ----------
## Reads ammo / XP / the held weapon from Game.data (call again after loading a save).
func _load_weapons() -> void:
	var saved = Game.data.get("weapons", {})
	if not (saved is Dictionary): saved = {}
	wdata.clear()
	for id in ORDER:
		var s: Dictionary = saved.get(id, {})
		var d := { ammo = int(s.get("ammo", -1)), xp = int(s.get("xp", 0)) }
		if d.ammo < 0: d.ammo = max_ammo_of(id, d.xp)
		wdata[id] = d
	var w: String = str(Game.data.get("weapon", "arc_lancer"))
	current = w if usable(w) else "arc_lancer"
	_store()
	weapon_changed.emit(current)
	_emit_status(current)

func reload_from_save() -> void:
	_load_weapons()

func _store() -> void:
	var out := {}
	for id in wdata: out[id] = { ammo = wdata[id].ammo, xp = wdata[id].xp }
	Game.data["weapons"] = out
	Game.data["weapon"] = current

func _on_unlocked(id: String) -> void:
	if not WEAPONS.has(id): return
	wdata[id].ammo = max_ammo(id)
	_store(); Game.save()
	equip(id)

func usable(id: String) -> bool:
	return WEAPONS.has(id) and Game.has(id)

static func level_for_xp(xp: int) -> int:
	var lv := 1
	for s in XP_STEPS: if xp >= s: lv += 1
	return lv

func level(id: String) -> int:
	return level_for_xp(int(wdata.get(id, {}).get("xp", 0)))

## 0..1 progress toward the next level (1.0 at V5)
func xp_frac(id: String) -> float:
	var xp: int = wdata[id].xp
	var lv := level_for_xp(xp)
	if lv >= 5: return 1.0
	var lo: int = 0 if lv == 1 else XP_STEPS[lv - 2]
	var hi: int = XP_STEPS[lv - 1]
	return clampf(float(xp - lo) / float(hi - lo), 0.0, 1.0)

func max_ammo_of(id: String, xp: int) -> int:
	return WEAPONS[id].ammo[level_for_xp(xp) - 1]

func max_ammo(id: String) -> int:
	return max_ammo_of(id, wdata[id].xp)

func ammo(id: String) -> int:
	return wdata[id].ammo

func uses_ammo(id: String) -> bool:
	return max_ammo(id) > 0

func weapon_name(id: String) -> String:
	return WEAPONS[id].v5 if level(id) >= 5 else WEAPONS[id].name

func weapon_color(id: String) -> Color:
	return GOLD if level(id) >= 5 else WEAPONS[id].color

func owned_weapons() -> Array:
	return ORDER.filter(func(id): return usable(id))

func equip(id: String) -> bool:
	if not usable(id) or id == current: return false
	current = id; cool = maxf(cool, 0.15)
	Game.data["weapon"] = current
	Snd.play("weapon_switch", -4, 0.04)
	weapon_changed.emit(id)
	_emit_status(id)
	return true

func cycle(step: int) -> void:
	var owned := owned_weapons()
	if owned.size() < 2: return
	var i := owned.find(current)
	equip(owned[(i + step + owned.size()) % owned.size()])

func _emit_status(id: String) -> void:
	ammo_changed.emit(id, wdata[id].ammo, max_ammo(id))
	weapon_xp.emit(id, level(id), xp_frac(id))

func _add_xp(id: String, n: int) -> void:
	if not wdata.has(id): return
	var before := level(id)
	wdata[id].xp += n
	var after := level(id)
	if after > before:
		# a level up tops the weapon up to its new, bigger magazine
		if uses_ammo(id): wdata[id].ammo = max_ammo(id)
		weapon_level_up.emit(id, after)
		Snd.play("weapon_v5" if after >= 5 else "weapon_levelup", -2, 0.0)
		Snd.bark("dodger" if randf() < 0.6 else "vesk", "levelup", 1.0)
		if player: FX.ring(player.global_position + Vector3(0, 0.1, 0), weapon_color(id), 1.4)
		Game.save()
	_store()
	_emit_status(id)

## Ammo for one weapon (or the held one when id == ""). Returns rounds actually added.
func add_ammo(id: String, n: int) -> int:
	if id == "": id = current
	if not wdata.has(id) or not uses_ammo(id): return 0
	var before: int = wdata[id].ammo
	wdata[id].ammo = mini(max_ammo(id), before + n)
	_store(); _emit_status(id)
	return wdata[id].ammo - before

## Refill every owned weapon. Returns how many rounds were missing in total.
func refill_all() -> int:
	var missing := 0
	for id in owned_weapons():
		if uses_ammo(id): missing += max_ammo(id) - wdata[id].ammo; wdata[id].ammo = max_ammo(id)
	_store(); _emit_status(current)
	return missing

## Rounds missing across owned weapons (used by the Gizmart restock).
func ammo_missing() -> int:
	var m := 0
	for id in owned_weapons(): if uses_ammo(id): m += max_ammo(id) - wdata[id].ammo
	return m

## The owned ammo weapon that is emptiest (relative), preferring the held one.
func neediest_weapon() -> String:
	var best := ""
	var bf := 1.0
	for id in owned_weapons():
		if not uses_ammo(id): continue
		var f := float(wdata[id].ammo) / max_ammo(id)
		if id == current: f -= 0.15
		if f < bf: bf = f; best = id
	return best

# ---------- firing ----------
func try_fire(dt: float, want: bool, muzzle: Vector3, aim_point: Vector3, aim_dir: Vector3) -> bool:
	cool -= dt
	# the lancer cools down whatever is held
	if overheated:
		heat -= dt * 0.55
		if heat <= 0.45: overheated = false
	elif not (want and current == "arc_lancer") or cool > 0.0:
		heat = maxf(0.0, heat - dt * (0.5 if cool < -0.4 or current != "arc_lancer" else 0.1))
	if wheel_open or Game.input_locked: return false
	if not want or cool > 0.0: return false
	var dir := (aim_point - muzzle).normalized()
	if dir.dot(aim_dir) < 0.3: dir = aim_dir
	match current:
		"arc_lancer": return _fire_lancer(muzzle, dir)
		"scatter_bloom", "thump_lobber", "seeker_hive":
			if wdata[current].ammo <= 0:
				cool = 0.35; Snd.play("ammo_empty", -6, 0.0, 0.3); Snd.bark("vesk", "empty", 0.35)
				return false
			var ok := false
			match current:
				"scatter_bloom": ok = _fire_scatter(muzzle, dir)
				"thump_lobber": ok = _fire_lobber(muzzle, aim_point, dir)
				"seeker_hive": ok = _fire_seeker(muzzle, dir)
			if ok:
				wdata[current].ammo -= 1
				_store(); ammo_changed.emit(current, wdata[current].ammo, max_ammo(current))
			return ok
	return false

func _light(parent: Node3D, c: Color, e: float, r: float) -> void:
	var l := OmniLight3D.new(); l.light_color = c; l.light_energy = e; l.omni_range = r; parent.add_child(l)

func _spawn(mesh: Mesh, mat: Material, pos: Vector3, dir: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new(); mi.mesh = mesh; mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi); mi.global_position = pos
	if dir.length() > 0.01: mi.global_basis = Basis(Quaternion(Vector3.UP, dir.normalized()))
	return mi

func _fire_lancer(muzzle: Vector3, dir: Vector3) -> bool:
	if overheated: return false
	var lv := level("arc_lancer")
	cool = LANCER_INTERVAL - 0.008 * (lv - 1)
	heat += 0.03 - 0.003 * (lv - 1)
	if heat >= 1.0:
		heat = 1.0; overheated = true; Snd.play("overheat", -4, 0.0)
		Snd.bark("vesk", "overheat", 0.3)
	dir = (dir + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.008).normalized()
	var v5 := lv >= 5
	var mi := _spawn(bolt_mesh, gold_mat if v5 else bolt_mat, muzzle, dir)
	if lv >= 3: mi.scale = Vector3(1.3, 1.0, 1.3)
	_light(mi, Color(1, 0.85, 0.4) if v5 else Color(0.4, 0.95, 1), 1.5, 3.0)
	bolts.append({ node = mi, vel = dir * 75.0, life = 1.6, dmg = LANCER_DMG + 0.15 * (lv - 1) + (0.1 if v5 else 0.0),
		wpn = "arc_lancer", kind = "bolt", chain = v5 })
	FX.sparks(muzzle, Color(1, 0.85, 0.4) if v5 else Color(0.6, 0.98, 1.0), 4, 3.0)
	Snd.play("blaster", -9, 0.07, 0.0)
	return true

func _fire_scatter(muzzle: Vector3, dir: Vector3) -> bool:
	var lv := level("scatter_bloom")
	var v5 := lv >= 5
	cool = 0.72 - 0.04 * (lv - 1)
	var n := 14 if v5 else 7 + lv
	var spread := deg_to_rad(9.0 - 0.5 * (lv - 1))
	var basis := Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.98 else Vector3.FORWARD)
	for i in n:
		# a flower pattern: an inner ring and an outer ring, a little jitter
		var ring := 0.45 if i % 2 == 0 else 1.0
		var a := float(i) / n * TAU + randf_range(-0.15, 0.15)
		var off := Vector2(cos(a), sin(a)) * spread * ring
		var d := (basis * Vector3(off.x, off.y, -1.0)).normalized()
		var mi := _spawn(pellet_mesh, gold_mat if v5 else pellet_mat, muzzle, d)
		bolts.append({ node = mi, vel = d * randf_range(52.0, 60.0), life = 0.36 + 0.02 * lv, dmg = 0.6 + 0.08 * (lv - 1),
			wpn = "scatter_bloom", kind = "pellet", pierce = 1 if v5 else 0 })
	var fl := _spawn(pellet_mesh, gold_mat if v5 else pellet_mat, muzzle, Vector3.ZERO); fl.scale = Vector3.ONE * 4.0
	_light(fl, weapon_color("scatter_bloom"), 4.0, 5.0)
	var tw := fl.create_tween(); tw.tween_property(fl, "scale", Vector3.ONE * 0.1, 0.09); tw.tween_callback(fl.queue_free)
	FX.sparks(muzzle, weapon_color("scatter_bloom"), 14 if v5 else 8, 7.0)
	if v5: FX.ring(muzzle, GOLD, 0.35)
	Snd.play("scatter_fire", -4, 0.06, 0.0)
	FX.shake(0.25)
	return true

func _fire_lobber(muzzle: Vector3, aim_point: Vector3, dir: Vector3) -> bool:
	var lv := level("thump_lobber")
	cool = 0.85 - 0.04 * (lv - 1)
	var vel := _lob_velocity(muzzle, aim_point, 24.0, 22.0)
	if vel == Vector3.ZERO:
		var flat := Vector3(dir.x, 0, dir.z).normalized()
		vel = (flat * cos(0.6) + Vector3.UP * sin(0.6)) * 24.0
	_spawn_bomb(muzzle, vel, lv, false)
	FX.sparks(muzzle, weapon_color("thump_lobber"), 6, 3.0)
	FX.puff(muzzle, Color(0.8, 0.95, 0.8))
	Snd.play("lobber_fire", -3, 0.08, 0.0)
	return true

func _spawn_bomb(pos: Vector3, vel: Vector3, lv: int, small: bool) -> void:
	var mi := _spawn(bomb_mesh, bomb_mat, pos, Vector3.ZERO)
	if small: mi.scale = Vector3.ONE * 0.6
	var band := TorusMesh.new(); band.inner_radius = 0.17; band.outer_radius = 0.23
	var bm := MeshInstance3D.new(); bm.mesh = band; bm.material_override = gold_mat if lv >= 5 else bomb_glow; mi.add_child(bm)
	_light(mi, weapon_color("thump_lobber"), 1.2, 3.0)
	bolts.append({ node = mi, vel = vel, life = 0.9 if small else 1.6, dmg = (2.0 if small else 4.0 + 0.6 * (lv - 1)),
		wpn = "thump_lobber", kind = "bomb", radius = (2.2 if small else 3.2 + 0.3 * (lv - 1)), bounces = 1, lv = lv, small = small,
		spin = Vector3(randf_range(-9, 9), randf_range(-9, 9), randf_range(-9, 9)) })

## Launch velocity (speed `v`, gravity `g`) that lands on `to`; the low arc. ZERO when out of reach.
func _lob_velocity(from: Vector3, to: Vector3, v: float, g: float) -> Vector3:
	var d := to - from
	var flat := Vector2(d.x, d.z)
	var x := flat.length()
	if x < 0.5: return Vector3.ZERO
	var y := d.y
	var disc := v * v * v * v - g * (g * x * x + 2.0 * y * v * v)
	if disc < 0.0: return Vector3.ZERO
	var ang := atan((v * v - sqrt(disc)) / (g * x))
	var h := flat.normalized()
	return Vector3(h.x * cos(ang), sin(ang), h.y * cos(ang)) * v

func _fire_seeker(muzzle: Vector3, dir: Vector3) -> bool:
	var lv := level("seeker_hive")
	var v5 := lv >= 5
	cool = 0.6 - 0.03 * (lv - 1)
	var n: int = [2, 3, 3, 4, 6][lv - 1]
	var side := Vector3.UP.cross(dir).normalized()
	for i in n:
		var a := (float(i) / n - 0.5) * 1.6
		var d := (dir + side * sin(a) * 0.9 + Vector3.UP * (0.35 + 0.2 * cos(a * 3.0))).normalized()
		var mi := _spawn(drone_mesh, gold_mat if v5 else drone_mat, muzzle + d * 0.2, d)
		_light(mi, weapon_color("seeker_hive"), 0.9, 2.5)
		bolts.append({ node = mi, vel = d * 16.0, life = 3.2, dmg = 1.3 + 0.15 * (lv - 1), wpn = "seeker_hive", kind = "seeker",
			target = _seek_target(muzzle + dir * 6.0, dir, 40.0, []), t = 0.0, retarget = 1 if v5 else 0, wob = randf() * TAU })
	FX.sparks(muzzle, weapon_color("seeker_hive"), 6, 3.0)
	Snd.play("seeker_fire", -5, 0.1, 0.0)
	return true

func _seek_target(origin: Vector3, dir: Vector3, max_d: float, skip: Array) -> Node3D:
	var best: Node3D = null
	var bs := INF
	for t in get_tree().get_nodes_in_group("targets"):
		if t.dead or t in skip or t.is_in_group("crate") or t.is_in_group("switches"): continue
		var c: Vector3 = t.center()
		var d := c - origin
		var dist := d.length()
		if dist > max_d: continue
		var facing := d.normalized().dot(dir) if dist > 0.1 else 1.0
		if facing < -0.2: continue
		var s := dist * (2.0 - facing)
		if s < bs: bs = s; best = t
	return best

## Applies weapon damage to a target: hit marker, damage number and weapon XP on a kill.
func _hit(t: Node, dmg: float, point: Vector3, dir: Vector3, wpn: String) -> bool:
	if t == null or t.dead: return false
	var was_bot: bool = t.is_in_group("bots") or t.is_in_group("boss")
	var kill: bool = t.damage(dmg, point, dir)
	hit_marker.emit(kill)
	if not t.is_in_group("crate") and not t.is_in_group("switches"): damage_number(point, dmg, kill)
	if kill and was_bot: _add_xp(wpn, 10 if t.is_in_group("boss") else 1)
	return kill

func _target_of(col: Object) -> Node:
	if not (col is Node): return null
	if col.is_in_group("targets"): return col
	if col.has_meta("owner"): return col.get_meta("owner")
	var p: Node = col.get_parent()
	for i in 3:
		if p == null or p == self: return null
		if p.is_in_group("targets"): return p
		p = p.get_parent()
	return null

func _explode(pos: Vector3, radius: float, dmg: float, wpn: String, scale := 1.0) -> void:
	for t in get_tree().get_nodes_in_group("targets"):
		if t.dead: continue
		var c: Vector3 = t.center()
		var d := c.distance_to(pos)
		if t.is_in_group("boss"): d = Vector2(t.global_position.x - pos.x, t.global_position.z - pos.z).length() - 2.0
		if d < radius:
			var f := lerpf(1.0, 0.5, clampf(d / radius, 0, 1))
			_hit(t, snappedf(dmg * f, 0.1), c, (c - pos).normalized(), wpn)
	FX.explosion(pos, scale)
	if wpn == "thump_lobber": Snd.at("lobber_explode", pos, -2 if scale >= 1.0 else -7, 0.1, 0.03)
	FX.shake(0.7 * scale)
	Snd.at("explode_small" if scale < 1.0 else "explode_big", pos, -1, 0.1, 0.0)

func _arc_line(a: Vector3, b: Vector3) -> void:
	var mi := MeshInstance3D.new(); mi.mesh = bolt_mesh; mi.material_override = gold_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi); mi.global_position = (a + b) * 0.5
	mi.global_basis = Basis(Quaternion(Vector3.UP, (b - a).normalized())).scaled(Vector3(0.6, a.distance_to(b), 0.6))
	var tw := mi.create_tween(); tw.tween_interval(0.07); tw.tween_callback(mi.queue_free)

## Wrench swing. `step` is the combo step: 1 and 2 are quick swings in front, 3 is a spinning finisher
## that hits all round, a little harder and further.
func melee(origin: Vector3, facing: Vector3, step := 1) -> bool:
	var any := false
	var fin := step >= 3
	var reach := 3.2 if fin else 2.6
	for t in get_tree().get_nodes_in_group("targets"):
		if t.dead: continue
		var c: Vector3 = t.center()
		var d := c - origin
		var dy := d.y - 0.8
		d.y = 0
		if d.length() < reach and absf(dy) < 1.8 and (fin or d.length() < 0.8 or d.normalized().dot(facing) > -0.1):
			var push := facing if not fin or d.length() < 0.1 else d.normalized()
			t.damage((4.0 if fin else 3.0) if t.is_in_group("boss") else (3.0 if fin else 2.0), c, push)
			FX.sparks(c, Color(1, 0.95, 0.7), 22 if fin else 16, 7 if fin else 6)
			any = true
	if fin: FX.ring(origin + Vector3(0, 0.1, 0), Color(1, 0.85, 0.45), 0.8)
	if any:
		FX.stop(0.09 if fin else 0.05); FX.shake(0.8 if fin else 0.45)
		Snd.play("melee_hit", 0 if fin else -2, 0.08, 0.0)
	return any

## Vesk's air slam landing: everything on the ground within reach takes a knock outward.
const SLAM_R := 3.8
func slam_wave(origin: Vector3) -> bool:
	var any := false
	for t in get_tree().get_nodes_in_group("targets"):
		if t.dead: continue
		var c: Vector3 = t.center()
		var d := c - origin
		if absf(d.y - 0.6) > 1.6: continue
		d.y = 0
		var l := d.length()
		if l > SLAM_R: continue
		var out := d / l if l > 0.1 else Vector3.FORWARD
		var dmg := 2.0 if t.is_in_group("boss") else lerpf(3.0, 2.0, l / SLAM_R)
		t.damage(dmg, c, out)
		damage_number(c, dmg, t.dead)
		any = true
	FX.ring(origin + Vector3(0, 0.1, 0), Color(1, 0.8, 0.4), 1.1)
	FX.puff(origin + Vector3(0, 0.2, 0), Color(0.8, 0.75, 0.65))
	FX.sparks(origin + Vector3(0, 0.2, 0), Color(1, 0.9, 0.6), 18, 6)
	FX.shake(1.0 if any else 0.7)
	if any: FX.stop(0.07)
	Snd.play("land", 2); Snd.play("melee_hit", 0 if any else -6, 0.08, 0.0)
	Game.slam_landed.emit(any)
	return any

func nearest_target(origin: Vector3, max_d: float) -> Node3D:
	var best: Node3D = null
	var bd := max_d
	for t in get_tree().get_nodes_in_group("targets"):
		if t.dead or t.is_in_group("crate"): continue
		var c: Vector3 = t.center()
		var d := Vector2(c.x - origin.x, c.z - origin.z).length()
		if d < bd and absf(c.y - origin.y - 0.8) < 2.0: bd = d; best = t
	return best

# ---------- bots' shots ----------
func enemy_shot(from: Vector3, to: Vector3) -> void:
	var dir := (to - from).normalized()
	var mi := MeshInstance3D.new(); mi.mesh = bolt_mesh; mi.material_override = shot_mat
	mi.scale = Vector3(1.4, 0.7, 1.4)
	add_child(mi); mi.global_position = from
	mi.global_basis = Basis(Quaternion(Vector3.UP, dir)).scaled(Vector3(1.4, 0.7, 1.4))
	var l := OmniLight3D.new(); l.light_color = Color(1, 0.3, 0.2); l.light_energy = 2.0; l.omni_range = 3.5; mi.add_child(l)
	shots.append({ node = mi, vel = dir * 17.0, life = 3.0 })
	Snd.at("hornet_shot", from, -4, 0.1, 0.02)

## Sends an enemy shot back, homing on the nearest bot in front of Vesk (or straight back).
var parry_mat: StandardMaterial3D
func _parry(s: Dictionary, at: Vector3) -> void:
	s.reflected = true; s.life = 2.0
	var back: Vector3 = -(s.vel as Vector3).normalized()
	var best: Node3D = null
	var bd := 30.0
	for t in get_tree().get_nodes_in_group("targets"):
		if t.dead or t.is_in_group("crate"): continue
		var d: Vector3 = (t.center() as Vector3) - at
		var l := d.length()
		if l < bd and d.normalized().dot(back) > 0.3: bd = l; best = t
	var dir := ((best.center() as Vector3) - at).normalized() if best else back
	s.vel = dir * 30.0
	if parry_mat == null: parry_mat = _glow(Color(1.0, 0.85, 0.3), 9.0)
	s.node.material_override = parry_mat
	s.node.global_basis = Basis(Quaternion(Vector3.UP, dir)).scaled(Vector3(1.4, 0.9, 1.4))
	FX.sparks(at, Color(1, 0.95, 0.6), 16, 6); FX.ring(at, Color(1, 0.85, 0.4), 0.4)
	FX.stop(0.06); FX.shake(0.4)
	Snd.play("melee_hit", 0, 0.05, 0.0, 1.25)
	float_text(at + Vector3(0, 0.5, 0), "PARRY", Color(1.0, 0.85, 0.35), 40)
	Game.shot_parried.emit()

func _close_call() -> void:
	FX.slow(0.3, 0.35)
	player.dash_cd = 0.0
	invuln = maxf(invuln, 0.35)
	FX.ring(player.global_position + Vector3(0, 0.15, 0), Color(0.45, 0.85, 1.0), 0.7)
	float_text(player.global_position + Vector3(0, 1.6, 0), "CLOSE CALL", Color(0.55, 0.9, 1.0), 40)
	Snd.play("dash", -1, 0.0, 0.0, 0.7)
	Game.close_call.emit()

func hurt_player(n: int, from = null, force := false) -> void:
	if (invuln > 0.0 and not force) or hull <= 0: return
	hull -= n; invuln = 0.9; Snd.play("hurt", -2); Game.player_hurt.emit(hull)
	if from is Vector3: Game.player_hit_from.emit(from)
	if hull <= 2: Snd.bark("dodger", "low", 0.6)
	else: Snd.bark("vesk", "hurt", 0.35)
	FX.shake(1.0)
	hull_changed.emit(hull, false)
	if from != null and player:
		var k: Vector3 = (player.global_position - from); k.y = 0
		player.velocity += k.normalized() * 6.0
	if hull <= 0:
		hull = 0
		if Game.player_downed.get_connections().is_empty(): revive()
		else: Game.player_downed.emit()

## Back on your feet at the last checkpoint with a full hull.
func revive() -> void:
	hull = MAX_HULL; invuln = 1.5
	hull_changed.emit(hull, true)
	if player: player.respawn()

func heal(n: int) -> void:
	hull = mini(MAX_HULL, hull + n); hull_changed.emit(hull, true)

# ---------- sprockets, repair cells and ammo ----------
func drop_nuts(pos: Vector3, n: int) -> void:
	for i in n:
		var mi := MeshInstance3D.new(); mi.mesh = nut_mesh; mi.material_override = nut_mat
		add_child(mi); mi.global_position = pos
		pickups.append({ node = mi, vel = Vector3(randf_range(-3, 3), randf_range(4, 8), randf_range(-3, 3)), t = 0.0, kind = "nut", spin = Vector3(randf_range(-8, 8), randf_range(-8, 8), 0) })

func drop_cell(pos: Vector3) -> void:
	var m := PrismMesh.new(); m.size = Vector3(0.35, 0.35, 0.35)
	var mi := MeshInstance3D.new(); mi.mesh = m; mi.material_override = cell_mat
	add_child(mi); mi.global_position = pos
	pickups.append({ node = mi, vel = Vector3(randf_range(-1, 1), 5, randf_range(-1, 1)), t = 0.0, kind = "cell", spin = Vector3(0, 3, 0) })

## An ammo canister: refills part of the emptiest owned weapon. Skipped when nothing needs ammo.
func drop_ammo(pos: Vector3) -> void:
	if neediest_weapon() == "": return
	var mi := MeshInstance3D.new(); mi.mesh = ammo_mesh; mi.material_override = ammo_mat
	var cap := CylinderMesh.new(); cap.top_radius = 0.08; cap.bottom_radius = 0.08; cap.height = 0.26
	var cm := MeshInstance3D.new(); cm.mesh = cap; cm.material_override = gold_mat; cm.rotation.z = PI / 2; mi.add_child(cm)
	add_child(mi); mi.global_position = pos
	pickups.append({ node = mi, vel = Vector3(randf_range(-1.5, 1.5), 5.5, randf_range(-1.5, 1.5)), t = 0.0, kind = "ammo", spin = Vector3(0, 4, 0) })

func _collect_ammo() -> void:
	var id := neediest_weapon()
	if id == "": Game.add_nuts(5); return
	var got := add_ammo(id, maxi(2, int(ceil(max_ammo(id) * 0.3))))
	if got > 0 and Game.hud and Game.hud.has_method("toast_small"):
		Game.hud.toast_small("+%d %s AMMO" % [got, WEAPONS[id].name], weapon_color(id))

## A short word that rises and fades over a spot (same style as the damage numbers).
func float_text(pos: Vector3, text: String, color: Color, size := 44) -> void:
	var l := Label3D.new()
	l.text = text; l.billboard = BaseMaterial3D.BILLBOARD_ENABLED; l.no_depth_test = true
	l.font_size = size; l.outline_size = 12; l.modulate = color; l.pixel_size = 0.006
	add_child(l); l.global_position = pos
	var tw := create_tween().set_parallel().set_ignore_time_scale(true)
	tw.tween_property(l, "global_position", pos + Vector3(0, 0.8, 0), 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(l, "modulate:a", 0.0, 0.6).set_delay(0.35)
	tw.chain().tween_callback(l.queue_free)

func damage_number(pos: Vector3, amount: float, kill: bool) -> void:
	var l := Label3D.new()
	l.text = str(snappedf(amount, 0.1)).trim_suffix(".0")
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font_size = 64 if kill else 44
	l.outline_size = 12
	l.modulate = Color(1, 0.85, 0.3) if kill else Color(1, 1, 1)
	l.pixel_size = 0.006
	add_child(l); l.global_position = pos + Vector3(randf_range(-0.3, 0.3), 0.4, randf_range(-0.3, 0.3))
	var tw := create_tween().set_parallel()
	tw.tween_property(l, "global_position", l.global_position + Vector3(0, 1.2, 0), 0.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(l, "modulate:a", 0.0, 0.7).set_delay(0.25)
	tw.chain().tween_callback(l.queue_free)

func _physics_process(dt: float) -> void:
	invuln -= dt
	var space := get_world_3d().direct_space_state
	_step_projectiles(dt, space)
	# enemy shots
	var hero_c := player.global_position + Vector3(0, 0.9, 0) if player else Vector3.ZERO
	for i in range(shots.size() - 1, -1, -1):
		var s: Dictionary = shots[i]
		var from: Vector3 = s.node.global_position
		var to: Vector3 = from + s.vel * dt
		s.life -= dt
		var seg := to - from
		var k := clampf((hero_c - from).dot(seg) / maxf(seg.length_squared(), 1e-6), 0, 1)
		var miss_d := (from + seg * k).distance_to(hero_c) if player else INF
		var hit_hero := miss_d < 0.6
		var q := PhysicsRayQueryParameters3D.create(from, to); q.collision_mask = 1
		var hw := space.intersect_ray(q)
		if s.get("reflected", false):
			# a batted-back shot: it flies at the bots instead
			var struck: Node = null
			for t in get_tree().get_nodes_in_group("targets"):
				if not t.dead and (t.center() as Vector3).distance_to(to) < (2.2 if t.is_in_group("boss") else 1.1): struck = t; break
			if struck or hw or s.life <= 0.0:
				if struck:
					struck.damage(4.0 if struck.is_in_group("boss") else 3.0, to, s.vel.normalized())
					damage_number(to, 4.0 if struck.is_in_group("boss") else 3.0, struck.dead)
					FX.sparks(to, Color(1, 0.9, 0.5), 18, 6); Snd.at("melee_hit", to, 0)
				else: FX.sparks(to, Color(1, 0.8, 0.4), 8, 4)
				s.node.queue_free(); shots.remove_at(i); continue
			s.node.global_position = to
			continue
		# a wrench swing in front of Vesk bats the shot back at the nearest bot (a parry)
		if player and player.melee_t > 0.14 and to.distance_to(hero_c) < 2.1 \
				and (to - hero_c).normalized().dot(Vector3(sin(player.face_yaw), 0, cos(player.face_yaw))) > -0.1:
			_parry(s, to)
			continue
		# a dash through a shot is a close call: it flies past, time slows for a breath and the dash
		# is ready again, so a good read chains straight into the counter
		if miss_d < 1.4 and player.since_dash < 0.4:
			hit_hero = false
			if not s.get("dodged", false):
				s.dodged = true
				_close_call()
		if hit_hero or hw or s.life <= 0.0:
			if hit_hero: hurt_player(1, from)
			FX.sparks(to, Color(1, 0.4, 0.25), 8, 4)
			s.node.queue_free(); shots.remove_at(i); continue
		s.node.global_position = to
	# pickups
	if player:
		var target := player.global_position + Vector3(0, 0.8, 0)
		for i in range(pickups.size() - 1, -1, -1):
			var p: Dictionary = pickups[i]
			p.t += dt
			var pos: Vector3 = p.node.global_position
			var d := pos.distance_to(target)
			if p.t > 0.5 and (d < (10.0 if p.kind == "nut" else 3.5) or (p.kind == "nut" and p.t > 2.2)):
				p.vel = p.vel.lerp((target - pos).normalized() * maxf(14.0, 30.0 - d * 1.5), 1.0 - exp(-10.0 * dt))
			else:
				p.vel.y -= 20.0 * dt
			pos += p.vel * dt
			var q := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 0.3, 0), pos - Vector3(0, 0.12, 0)); q.collision_mask = 1
			var g := space.intersect_ray(q)
			if g and p.vel.y < 0:
				pos.y = g.position.y + 0.12; p.vel.y = absf(p.vel.y) * 0.4; p.vel.x *= 0.7; p.vel.z *= 0.7
			p.node.global_position = pos
			p.node.rotation += p.spin * dt
			if d < 0.75:
				match p.kind:
					"nut":
						# a run of sprockets climbs in pitch, so scooping up a big pile sounds like it
						var now := Time.get_ticks_msec()
						nut_chain = nut_chain + 1 if now - nut_last < 450 else 0
						nut_last = now
						Game.add_nuts(10); Snd.play("nut_pickup", -8, 0.03, 0.03, 1.0 + minf(nut_chain, 12) * 0.045)
					"ammo": _collect_ammo(); Snd.play("cell_pickup", -5, 0.1); Snd.play("weapon_switch", -10)
					_: heal(1); Snd.play("cell_pickup", -3)
				p.node.queue_free(); pickups.remove_at(i); continue
			if p.t > 25.0 or pos.y < -40.0: p.node.queue_free(); pickups.remove_at(i)

func _step_projectiles(dt: float, space: PhysicsDirectSpaceState3D) -> void:
	var spawn_after: Array = []
	for i in range(bolts.size() - 1, -1, -1):
		var b: Dictionary = bolts[i]
		if not is_instance_valid(b.node): bolts.remove_at(i); continue
		b.life -= dt
		var from: Vector3 = b.node.global_position
		match b.kind:
			"bomb":
				b.vel.y -= 22.0 * dt
				b.node.rotation += b.spin * dt
			"seeker":
				b.t += dt
				var tg = b.target
				if tg != null and (not is_instance_valid(tg) or tg.dead):
					tg = _seek_target(from, b.vel.normalized(), 30.0, []) if b.retarget > 0 else null
					if tg: b.retarget -= 1
					b.target = tg
				if tg == null and b.t > 0.25:
					tg = _seek_target(from, b.vel.normalized(), 30.0, []); b.target = tg
				var spd := minf(34.0, 16.0 + b.t * 30.0)
				var want: Vector3 = b.vel.normalized()
				if tg and b.t > 0.12:
					want = ((tg.center() as Vector3) - from).normalized()
				var wob := Vector3(sin(b.t * 13.0 + b.wob), cos(b.t * 11.0 + b.wob), 0) * 0.12
				b.vel = b.vel.normalized().slerp((want + wob).normalized(), 1.0 - exp(-(7.0 if b.t > 0.12 else 1.0) * dt)) * spd
				if b.node.get_child_count() > 0 and randf() < 0.4: FX.sparks(from, weapon_color("seeker_hive"), 1, 1.0)
		var to: Vector3 = from + b.vel * dt
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.collision_mask = 1 | 4
		var ex: Array = b.get("exclude", [])
		if player: ex = ex + [player.get_rid()]
		q.exclude = ex
		var hit := space.intersect_ray(q)
		if b.kind == "seeker" and not hit and b.target and is_instance_valid(b.target) and not b.target.dead:
			# proximity fuse so drones never orbit a target
			if (b.target.center() as Vector3).distance_to(to) < 0.6:
				hit = { position = to, collider = b.target, normal = -b.vel.normalized() }
		if hit:
			var t := _target_of(hit.collider)
			match b.kind:
				"bomb":
					if t == null and b.bounces > 0 and b.life > 0.25:
						b.bounces -= 1
						var nrm: Vector3 = hit.normal
						b.vel = b.vel.bounce(nrm) * 0.45
						b.node.global_position = hit.position + nrm * 0.22
						Snd.at("lobber_bounce", hit.position, -4, 0.15, 0.05)
						continue
					_bomb_burst(b, hit.position + (hit.normal as Vector3) * 0.2, spawn_after)
					b.node.queue_free(); bolts.remove_at(i); continue
				_:
					if t and not t.dead:
						var kill := _hit(t, b.dmg, hit.position, b.vel.normalized(), b.wpn)
						if b.get("chain", false): _chain_arc(t, hit.position, b.dmg * 0.7)
						if b.get("pierce", 0) > 0 and not kill:
							b.pierce -= 1
							var rid_ex: Array = b.get("exclude", [])
							rid_ex.append(hit.rid); b.exclude = rid_ex
							b.node.global_position = hit.position + b.vel.normalized() * 0.05
							FX.sparks(hit.position, GOLD, 6, 4)
							continue
						Snd.at("bolt_hit", hit.position, -6, 0.12, 0.04)
					FX.sparks(hit.position, weapon_color(b.wpn), 8 if b.kind != "pellet" else 3, 4)
					b.node.queue_free(); bolts.remove_at(i); continue
		b.node.global_position = to
		if b.life <= 0.0:
			if b.kind == "bomb": _bomb_burst(b, to, spawn_after)
			elif b.kind == "pellet" and b.wpn == "scatter_bloom" and level("scatter_bloom") >= 5: FX.sparks(to, GOLD, 2, 2)
			b.node.queue_free(); bolts.remove_at(i)
	for s in spawn_after: _spawn_bomb(s[0], s[1], s[2], true)

func _bomb_burst(b: Dictionary, pos: Vector3, spawn_after: Array) -> void:
	_explode(pos, b.radius, b.dmg, "thump_lobber", 0.6 if b.small else 1.0)
	if not b.small and b.lv >= 5:
		for k in 3:
			var a := k * TAU / 3.0 + randf() * 0.5
			spawn_after.append([pos + Vector3(0, 0.4, 0), Vector3(cos(a) * 6.0, 8.0, sin(a) * 6.0), b.lv])

func _chain_arc(from_t: Node, point: Vector3, dmg: float) -> void:
	var best: Node3D = null
	var bd := 7.0
	for t in get_tree().get_nodes_in_group("targets"):
		if t == from_t or t.dead or t.is_in_group("crate") or t.is_in_group("switches"): continue
		var d := (t.center() as Vector3).distance_to(point)
		if d < bd: bd = d; best = t
	if best:
		_arc_line(point, best.center())
		_hit(best, snappedf(dmg, 0.1), best.center(), (best.center() - point).normalized(), "arc_lancer")
		FX.sparks(best.center(), GOLD, 6, 4)
