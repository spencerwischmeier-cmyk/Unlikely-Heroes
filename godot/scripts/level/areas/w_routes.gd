extends RefCounted
## The routes between Skyharbor's areas, built after the Spread pass pushed the areas apart (final world
## coordinates; see scripts/level/layout/spread.gd). Each one is a deliberate set piece instead of a few loose
## pads, hooks and short rails, and each one shows the city caught off guard (scripts/level/layout/chaos.gd).
##   Scrapline (south)        Junkyard gate -> Scrapline Halt (tram stop) -> the tram viaduct with its collapsed
##                            span and a long overhead-cable grind -> the plaza. The halt's west side opens onto
##                            the Sorting Works, the junkyard's new scrap-sorting yard (built here too).
##   Lantern Bridge (west)    plaza -> Market Terrace; the Gardens Express rail sweeps over it back to the plaza
##   Freight Gangway (east)   plaza -> Pier A; the cargo lift flies from Pier C to the plaza's east landing
##   Freight Approach (north) plaza -> Grudd's abandoned checkpoint -> the causeway; the lift bridge on to the
##                            Crane Yard gate; the long dish rail from the mast drops onto the gate island
##   Skyline Cableway         Roof Gardens promenade -> two hooks -> cable car station -> cable grind -> mast
##   Balloon Line             Pier C -> two hooks -> the balloon barge -> tether grind -> mast landing

const M := preload("res://scripts/mats.gd")
const Chaos := preload("res://scripts/level/layout/chaos.gd")
const JK := preload("res://scripts/level/junkyard/junk_kit.gd")
const Junk := preload("res://scripts/level/areas/junkyard.gd")
const YK := preload("res://scripts/level/yard/yard_kit.gd")
const DD := preload("res://scripts/level/docks_dressing.gd")
const S := preload("res://scripts/level/layout/spread.gd")

static var steel: Material
static var yellow: Material
static var teal: Material
static var cable_m: Material

static func build(L) -> void:
	if not S.on(): return
	steel = M.std(Color(0.55, 0.6, 0.66), 0.85, 0.35)
	yellow = M.paint(Color(0.93, 0.7, 0.18))
	teal = M.paint(Color(0.18, 0.58, 0.56))
	cable_m = M.std(Color(0.16, 0.17, 0.19), 0.6, 0.5)
	var rng := RandomNumberGenerator.new(); rng.seed = 90210
	_scrapline(L, rng)
	_sorting_works(L, rng)
	_lantern_bridge(L, rng)
	_gangway(L, rng)
	_approach(L, rng)
	_cableway(L, rng)
	_balloon_line(L, rng)
	_dish_rail(L)
	# zones that unlock the rebuilt rails
	for z in L.zones:
		if z.id == "gardens": z.unlock_rails = [L.R_CHUTE]
		elif z.id == "mast": z.unlock_rails = [L.R_YARD]
	L.debug_spots["halt"] = [Vector3(0, 0.1, 106), PI]
	L.debug_spots["viaduct"] = [Vector3(1.5, 0.1, 76), PI]
	L.debug_spots["works"] = [Vector3(-22, 0.1, 102), -PI / 2]
	L.debug_spots["lantern"] = [Vector3(-26, 0.1, 33), -PI / 2]
	L.debug_spots["gangway"] = [Vector3(27, 0.1, 30), PI / 2]
	L.debug_spots["approach"] = [Vector3(-6, 0.1, 6), PI]
	L.debug_spots["liftbridge"] = [Vector3(-6, 0.1, -76), PI]
	L.debug_spots["cableway"] = [Vector3(-27, 6.7, -40), PI / 2]
	L.debug_spots["barge"] = [Vector3(58, 3.1, -34), -PI / 2]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--at=") and L.debug_spots.has(a.substr(5)):
			L.start_pos = L.debug_spots[a.substr(5)][0]; L.start_yaw = L.debug_spots[a.substr(5)][1]

# ------------------------------------------------------------------ building blocks
## a rail without support poles standing on islands or decks (they would poke through floors and walkways)
static func _rail(L, pts: Array, locked: bool, poles := true) -> int:
	var n0: int = L.get_child_count()
	var i: int = L.rail(pts, locked)
	for k in range(L.get_child_count() - 1, n0, -1):
		var c: Node = L.get_child(k)
		if not (c is MeshInstance3D): continue
		var p: Vector3 = (c as Node3D).position
		var over := not poles
		for n in L.islands:
			if (L.islands[n] as Rect2).grow(2.0).has_point(Vector2(p.x, p.z)): over = true; break
		if over: c.queue_free()
	return i

## a bridge deck: walkable slab, trusses under it, glowing trim; registered as an island so the ground pass,
## the crowd and the audio know about it
static func _deck(L, name_: String, r: Rect2, y: float, tint: Color, along_z: bool, keel := true) -> void:
	L.islands[name_] = r; L.heights[name_] = y
	var c := r.get_center()
	L.box(Vector3(c.x, y - 0.3, c.y), Vector3(r.size.x, 0.6, r.size.y), M.deck(tint))
	var len: float = r.size.y if along_z else r.size.x
	var wid: float = r.size.x if along_z else r.size.y
	for s in [-1, 1]:
		var off: float = (wid / 2 - 0.5) * s
		var bp := Vector3(c.x + (off if along_z else 0.0), y - 1.05, c.y + (0.0 if along_z else off))
		L.box(bp, Vector3(0.35, 0.9, len) if along_z else Vector3(len, 0.9, 0.35), steel, false)
		var tp := Vector3(c.x + ((wid / 2 - 0.05) * s if along_z else 0.0), y - 0.08, c.y + (0.0 if along_z else (wid / 2 - 0.05) * s))
		L.box(tp, Vector3(0.12, 0.1, len) if along_z else Vector3(len, 0.1, 0.12), L.glow_cyan, false)
	var n := int(len / 4.0)
	for k in n + 1:
		var u := -len / 2 + len * k / maxf(1, n)
		var p := Vector3(c.x + (0.0 if along_z else u), y - 0.75, c.y + (u if along_z else 0.0))
		L.box(p, Vector3(wid - 0.8, 0.25, 0.25) if along_z else Vector3(0.25, 0.25, wid - 0.8), steel, false)
		if keel and k % 2 == 1:
			# a V of struts down to a glowing keel lamp, like the islands' undersides
			var kp := p + Vector3(0, -2.6, 0)
			for s in [-1, 1]:
				var a := p + (Vector3(s * (wid / 2 - 0.5), 0, 0) if along_z else Vector3(0, 0, s * (wid / 2 - 0.5)))
				YK.beam(L, a, kp, 0.18, "dark")
			L.cyl(kp, 0.25, 0.25, 0.3, L.glow_cyan)

static func _sign(L, text: String, pos: Vector3, yaw: float) -> void:
	L.hint_sign(text, pos, yaw)

## a mast for an overhead cable: a pole beside the path with an arm reaching over it
static func _cable_mast(L, foot: Vector3, top_y: float, arm_to: Vector3) -> void:
	L.cyl(foot + Vector3(0, top_y / 2, 0), 0.14, 0.2, top_y, steel, 10, true)
	L.box(foot + Vector3(0, 0.15, 0), Vector3(0.8, 0.3, 0.8), L.mat_dark)
	var top := foot + Vector3(0, top_y, 0)
	YK.beam(L, top, Vector3(arm_to.x, top_y, arm_to.z), 0.16, "dark")
	YK.beam(L, top + Vector3(0, -1.2, 0), Vector3(lerpf(top.x, arm_to.x, 0.6), top_y, lerpf(top.z, arm_to.z, 0.6)), 0.1, "dark")
	var lamp := MeshInstance3D.new(); var sm := SphereMesh.new(); sm.radius = 0.16; sm.height = 0.32; lamp.mesh = sm
	lamp.material_override = L.glow_warm; lamp.position = top + Vector3(0, 0.25, 0); L.add_child(lamp)

## a ramp you can walk up: a tilted slab from `lo` (bottom centre) to `hi` (top centre)
static func _ramp(L, lo: Vector3, hi: Vector3, width: float, mat: Material) -> void:
	var d := hi - lo
	var flat := Vector2(d.x, d.z).length()
	var len := d.length()
	var mid := (lo + hi) / 2
	var mi: MeshInstance3D = L.box(mid + Vector3(0, -0.15, 0), Vector3(width, 0.3, len), mat)
	mi.rotation = Vector3(atan2(d.y, flat), atan2(-d.x, -d.z), 0)
	# step strips on top (visual)
	var n := int(len / 0.5)
	for k in n:
		var u := (k + 0.5) / n
		var s: MeshInstance3D = L.box(lo.lerp(hi, u) + Vector3(0, 0.02, 0), Vector3(width - 0.1, 0.04, 0.08), L.mat_dark, false)
		s.rotation = mi.rotation

# ------------------------------------------------------------------ Scrapline: Junkyard -> Plaza
static func _scrapline(L, rng: RandomNumberGenerator) -> void:
	var C: Node3D = Chaos.make(L, "scrapline")
	# Scrapline Halt: the tram stop right outside Vesk's gate
	var halt := Rect2(-15, 93, 30, 20)
	L.island("junk_halt", halt, 0.0, Color(0.9, 0.86, 0.8))
	L.fence(halt, 0.0, [["n", -4, 4], ["w", 98, 106]], "nwe")
	L.checkpoints.append({ pos = Vector3(0, 0.1, 106), r = 3.0 })
	L.label("SCRAPLINE HALT", Vector3(4, 0, 106), 4.0, Color(0.85, 1, 0.95))
	# the track: two rails from the halt all the way to the plaza (decor)
	for x in [-0.75, 0.75]:
		L.box(Vector3(x, 0.05, 79.5), Vector3(0.12, 0.1, 27), steel, false)
		L.box(Vector3(x, 0.05, 56), Vector3(0.12, 0.1, 20), steel, false)
		L.box(Vector3(x, 0.05, 103), Vector3(0.12, 0.1, 20), steel, false)
	for z in range(48, 112, 2):
		if z > 66 and z < 72: continue
		L.box(Vector3(0, 0.03, z), Vector3(2.2, 0.06, 0.3), M.wood(Color(0.5, 0.38, 0.28)), false)
	# the siding with the last tram, stalled and dark
	for x in [8.25, 9.75]: L.box(Vector3(x, 0.05, 103), Vector3(0.12, 0.1, 18), steel, false)
	C.prop("tram_car", Vector3(9, 0, 102), 0.0)
	C.box_collider(Vector3(9, 1.5, 102), Vector3(2.6, 3.0, 8.0))
	C.broken_sign("ALL SERVICES CANCELLED", Vector3(-7.5, 3.6, 95.5), 0.0, Color(1.0, 0.45, 0.3), 0.12)
	L.cyl(Vector3(-11.6, 1.8, 95.5), 0.08, 0.1, 3.6, L.mat_dark, 8); L.cyl(Vector3(-3.4, 1.8, 95.5), 0.08, 0.1, 3.6, L.mat_dark, 8)
	# shelter on the east platform edge
	for z in [108.5, 112.0]:
		L.cyl(Vector3(13.2, 1.4, z), 0.08, 0.08, 2.8, steel, 8)
	L.box(Vector3(13.4, 2.9, 110.2), Vector3(2.6, 0.12, 4.4), M.paint(Color(0.2, 0.55, 0.55)), false)
	L.box(Vector3(14.4, 1.4, 110.2), Vector3(0.08, 2.6, 4.2), M.glass(), false)
	# panic: luggage everywhere, carts shoved aside, a skycar that came down on the platform, a bin fire
	C.luggage(Vector3(2.5, 0, 103.5), 4.0, 12, rng)
	C.luggage(Vector3(5, 0, 96), 3.0, 7, rng)
	C.prop("luggage_cart", Vector3(-9, 0, 104.5), 0.6, 1.0, Vector2(0, PI / 2 - 0.1), true)
	C.prop("luggage_cart", Vector3(4.5, 0, 108), -0.3, 1.0, Vector2.ZERO, true)
	C.prop("luggage_cart", Vector3(-12, 0, 110.5), 1.9, 1.0, Vector2.ZERO, true)
	C.crashed_skycar(Vector3(10.5, 0, 95.5), 2.4, rng)
	C.prop("kit/barrel", Vector3(-12.5, 0, 101), 0.0)
	C.fire(Vector3(-12.5, 1.1, 101), 0.6)
	C.prop("sign_bent", Vector3(-13.5, 0, 97), 1.2)
	_sign(L, "OVERHEAD LINE: QUICKEST WAY TO THE PLAZA", Vector3(-7.6, 0, 111.2), PI)
	# the gantry the overhead cable starts from, and its stair
	var gy := 6.0
	L.box(Vector3(-2.5, gy - 0.2, 95.2), Vector3(11, 0.4, 4.4), M.deck(Color(0.8, 0.8, 0.82)))
	L.islands["junk_halt_gantry"] = Rect2(-8, 93, 11, 4.4); L.heights["junk_halt_gantry"] = gy
	for p in [Vector3(-7.6, 0, 93.4), Vector3(-7.6, 0, 97.0), Vector3(2.6, 0, 93.4), Vector3(2.6, 0, 97.0)]:
		L.cyl(p + Vector3(0, gy / 2, 0), 0.16, 0.2, gy, yellow, 10, true)
	L.railing(-8, 93, 3, 93, gy); L.railing(-8, 97.4, -6, 97.4, gy); L.railing(-4.2, 97.4, 3, 97.4, gy)
	_ramp(L, Vector3(-5.1, 0.0, 109.8), Vector3(-5.1, gy, 97.4), 2.0, M.deck(Color(0.78, 0.78, 0.8)))
	L.checkpoints.append({ pos = Vector3(-3, gy + 0.1, 95.5), r = 2.0 })
	# the viaduct: two spans with a collapsed gap between them
	_deck(L, "junk_viaduct", Rect2(-4, 72, 8, 21), 0.0, Color(0.82, 0.8, 0.78), true)
	_deck(L, "plaza_viaduct", Rect2(-4, 46, 8, 21), 0.0, Color(0.85, 0.82, 0.78), true)
	for s in [-1, 1]:
		L.railing(s * 4.0, 73, s * 4.0, 92.5, 0.0)
		L.railing(s * 4.0, 47, s * 4.0, 66.5, 0.0)
	_sign(L, "LINE DOWN. JUMP THE GAP OR RIDE THE CABLE", Vector3(3.2, 0, 74.2), PI)
	L.checkpoints.append({ pos = Vector3(1.5, 0.1, 76), r = 2.4 })
	# broken ends: jagged slabs and dangling track over the drop
	for e in [[72.0, -1.0], [67.0, 1.0]]:
		var z0: float = e[0]
		for k in 4:
			var x := -3.2 + k * 2.1 + rng.randf_range(-0.3, 0.3)
			var chunk: MeshInstance3D = L.box(Vector3(x, -0.35, z0 + e[1] * rng.randf_range(0.2, 0.7)), Vector3(1.8, 0.5, rng.randf_range(0.6, 1.4)), M.deck(Color(0.8, 0.78, 0.76)), false)
			chunk.rotation = Vector3(rng.randf_range(-0.4, 0.4), rng.randf_range(-0.3, 0.3), rng.randf_range(-0.2, 0.2))
		for x in [-0.75, 0.75]:
			var dangle: MeshInstance3D = L.box(Vector3(x, -1.1, z0 - e[1] * 0.9), Vector3(0.12, 0.1, 2.6), steel, false)
			dangle.rotation.x = e[1] * 0.9
	var fallen: MeshInstance3D = L.box(Vector3(-1.5, -5.5, 69.5), Vector3(7, 0.6, 5), M.deck(Color(0.78, 0.76, 0.74)), false)
	fallen.rotation = Vector3(0.7, 0.2, 0.25)
	# the derailed tram, on its side across half the north span, burning
	C.prop("tram_car", Vector3(-1.0, 1.3, 83), 0.1, 1.0, Vector2(0, PI / 2))
	C.box_collider(Vector3(-2.5, 1.3, 83), Vector3(3.0, 2.6, 8.0), 0.1)
	C.fire(Vector3(-2.0, 2.6, 80.5), 1.0)
	C.smoke(Vector3(-2.0, 3.2, 81), 1.3, true)
	C.luggage(Vector3(2.0, 0, 87), 1.8, 6, rng)
	C.prop("rubble", Vector3(2.4, 0, 79), 1.0, 0.8)
	C.luggage(Vector3(-1.5, 0, 60), 2.2, 6, rng)
	C.prop("luggage_cart", Vector3(2.4, 0, 56), 2.8, 1.0, Vector2(0, -PI / 2 + 0.1))
	C.barricade(Vector3(-3.8, 0, 50.5), Vector3(3.8, 0, 50.5), rng, 0.5, 2.6)
	# the overhead cable: masts along the viaduct, and the grind itself
	var pts := [Vector3(0, gy + 0.45, 94.6), Vector3(0, 6.2, 88), Vector3(0, 5.6, 80), Vector3(0, 4.9, 72.5), Vector3(0, 4.3, 66.5),
		Vector3(0, 3.4, 60), Vector3(0, 2.2, 54), Vector3(0, 1.15, 50), Vector3(0, 0.6, 47.2)]
	L.set_meta("rail_scrapline", _rail(L, pts, false, false))
	for m in [[88.0, -1], [78.0, 1], [73.5, -1], [65.5, 1], [57.0, -1]]:
		var z: float = m[0]; var s: int = m[1]
		var y := 0.0
		for i in pts.size() - 1:
			if z <= pts[i].z and z >= pts[i + 1].z:
				y = lerpf(pts[i].y, pts[i + 1].y, (pts[i].z - z) / (pts[i].z - pts[i + 1].z)); break
		_cable_mast(L, Vector3(s * 4.7, 0 if absf(z - 69.5) > 3.5 else -0.6, z), y + 0.7, Vector3(0, 0, z))
	C.flush()

# ------------------------------------------------------------------ the Sorting Works (junkyard expansion)
static func _sorting_works(L, rng: RandomNumberGenerator) -> void:
	var C: Node3D = Chaos.make(L, "works")
	var B := JK.Batch.new()
	var r := Rect2(-50, 86, 32, 24)
	JK.slab(L, "junk_works", r, 0.0, Color(0.86, 0.76, 0.62))
	L.fence(r, 0.0, [["e", 98, 106], ["s", -40, -33]], "nwes")
	JK.plank_bridge(L, Vector3(-18, 0, 102), Vector3(-15, 0, 102), 4.0, rng)
	JK.plank_bridge(L, Vector3(-36.5, 0, 110), Vector3(-36.5, 0, 113.2), 3.5, rng)
	L.label("SORTING WORKS", Vector3(-26, 0, 104), 4.0, Color(1, 0.8, 0.55))
	L.checkpoints.append({ pos = Vector3(-22, 0.1, 102), r = 2.4 })
	_sign(L, "SORTING WORKS. KEEP HANDS OUT OF THE CRUSHER", Vector3(-20, 0, 98.5), -PI / 2)
	# the sorting line: a long belt west to east, scrap riding on it, into the crusher
	var belt_y := 1.1
	L.box(Vector3(-36, belt_y - 0.15, 91), Vector3(22, 0.3, 2.4), M.rubber(), true)
	for x in range(-46, -25, 3):
		for s in [-1, 1]: L.box(Vector3(x, belt_y / 2 - 0.15, 91 + s * 1.0), Vector3(0.25, belt_y - 0.3, 0.25), L.mat_dark, false)
	for s in [-1, 1]: L.box(Vector3(-36, belt_y + 0.1, 91 + s * 1.25), Vector3(22, 0.35, 0.12), yellow, false)
	for i in 16:
		var p := Vector3(rng.randf_range(-46, -27), belt_y + 0.1, 91 + rng.randf_range(-0.7, 0.7))
		B.add(["plate", "drum", "gear", "block"][i % 4], "scrap", JK.xform(p, Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * TAU, 0), Vector3.ONE * rng.randf_range(0.5, 0.9)), JK.PALETTE[i % JK.PALETTE.size()])
	# the crusher: a press frame over the belt's east end, its ram stuck half down, sparking
	var cx := -23.5
	for s in [-1, 1]: L.box(Vector3(cx, 3.0, 91 + s * 1.8), Vector3(1.0, 6.0, 0.8), yellow, true)
	L.box(Vector3(cx, 6.2, 91), Vector3(1.6, 0.8, 4.4), yellow)
	L.box(Vector3(cx, 3.2, 91), Vector3(2.0, 1.6, 2.6), L.mat_dark)
	L.box(Vector3(cx, 2.35, 91), Vector3(2.1, 0.1, 2.7), M.hazard(), false)
	YK.sparks(L, Vector3(cx, 2.3, 92.4), Color(1, 0.7, 0.25), 18, 4.0).emitting = true
	C.broken_sign("SHIFT CANCELLED", Vector3(cx, 7.1, 91), PI / 2, Color(1, 0.6, 0.25), -0.18, 0.01)
	# bales of crushed scrap: climbable stacks up to the sorting gantry
	var bale_cols := [Color(0.62, 0.42, 0.3), Color(0.5, 0.55, 0.6), Color(0.72, 0.6, 0.38), Color(0.45, 0.5, 0.42)]
	for st in [[Vector2(-43.6, 96.7), 3], [Vector2(-43.6, 94.4), 3], [Vector2(-43.6, 99), 2], [Vector2(-41.2, 99), 1], [Vector2(-46, 99), 3], [Vector2(-46, 101.4), 2], [Vector2(-46, 103.8), 1],
			[Vector2(-30, 106), 2], [Vector2(-27.6, 106), 1], [Vector2(-32.4, 106), 1]]:
		var p: Vector2 = st[0]
		for k in st[1]:
			var col: Color = bale_cols[(k + int(p.x)) % bale_cols.size()]
			L.box(Vector3(p.x, 0.6 + k * 1.2, p.y), Vector3(2.3, 1.2, 2.3), JK.paint(col))
			for q in 3:
				B.add("plate", "scrap", JK.xform(Vector3(p.x + rng.randf_range(-0.9, 0.9), 0.6 + k * 1.2 + rng.randf_range(-0.5, 0.5), p.y + 1.16), Vector3(PI / 2, 0, rng.randf() * TAU), Vector3(rng.randf_range(0.3, 0.6), 1, rng.randf_range(0.3, 0.6))), col.darkened(0.2))
	# the sorting gantry along the north wall (3.6): bale steps up, a sprocket stash at the far end
	L.box(Vector3(-36, 3.4, 88.35), Vector3(22, 0.4, 4.5), M.deck(Color(0.75, 0.75, 0.78)))
	L.islands["junk_works_gantry"] = Rect2(-47, 86.1, 22, 4.5); L.heights["junk_works_gantry"] = 3.6
	for x in range(-46, -25, 5): L.cyl(Vector3(x, 1.7, 87.4), 0.12, 0.14, 3.4, yellow, 8)
	L.railing(-47, 90.55, -45.0, 90.55, 3.6); L.railing(-42.2, 90.55, -25, 90.55, 3.6)
	var life: Node = L.find_child("JunkLife", true, false)
	# a magnet crane over the bale yard, still swinging a car it grabbed when the bots went haywire
	if life: Junk._crane(L, B, life, Vector3(-36, 0, 103))
	for p in [Vector3(-28, 4.3, 87.4), Vector3(-30, 4.3, 87.4), Vector3(-32, 4.3, 87.4)]: L.crate_spots.append(p - Vector3(0, 0.7, 0))
	# scrap piles and litter
	JK.pile(B, rng, Vector3(-48.0, 0, 95.5), 1.8, 2.0, 30)
	JK.pile(B, rng, Vector3(-21, 0, 108), 2.0, 1.6, 28)
	JK.litter(B, rng, Rect2(-49, 94, 30, 15), 0.0, 70, [Rect2(-37.5, 101.5, 3, 3)])
	B.flush(L, JK)
	# what the workers left: a toppled forklift, the lunch table, a fire in a scrap bin, cones
	C.model("res://models/docks/forklift.glb", Vector3(-32, 0.6, 96.5), 0.8, 1.0, Vector2(0.1, 1.45))
	C.box_collider(Vector3(-32, 0.8, 96.5), Vector3(2.2, 1.6, 3.0), 0.8)
	C.prop("kit/barrel", Vector3(-24, 0, 97), 0.0, 1.1)
	C.fire(Vector3(-24, 1.2, 97), 0.7)
	C.smoke(Vector3(-24, 2.0, 97), 0.9, true)
	C.fire(Vector3(-48, 2.2, 95.5), 0.8)
	C.smoke(Vector3(-48, 3.0, 95.5), 1.2, true)
	C.prop("cone", Vector3(-28, 0, 100), 0.0); C.prop("cone", Vector3(-27, 0, 99), 0.0, 1.0, Vector2(0, 1.5))
	C.prop("rubble", Vector3(-38, 0, 96.5), 0.4, 0.9)
	C.flush()
	L.debug_spots["works_gantry"] = [Vector3(-44, 3.7, 87.4), PI / 2]

# ------------------------------------------------------------------ Lantern Bridge: plaza -> Market Terrace
static func _lantern_bridge(L, rng: RandomNumberGenerator) -> void:
	var C: Node3D = Chaos.make(L, "lantern_bridge")
	var r := Rect2(-58, 29, 36, 8)
	_deck(L, "plaza_bridge_west", r, 0.0, Color(0.96, 0.88, 0.78), false)
	L.railing(-57.5, 29, -22.5, 29, 0.0)
	L.railing(-57.5, 37, -22.5, 37, 0.0)
	L.label("LANTERN BRIDGE", Vector3(-40, 0, 33), 4.0, Color(1, 0.85, 0.6))
	# two lantern arches with strings of paper lanterns between them
	var red := M.paint(Color(0.78, 0.22, 0.16))
	for x in [-31.0, -49.0]:
		for z in [29.3, 36.7]: L.cyl(Vector3(x, 2.6, z), 0.22, 0.26, 5.2, red, 10, true)
		L.box(Vector3(x, 5.3, 33), Vector3(0.6, 0.5, 8.6), red, false)
		L.box(Vector3(x, 5.65, 33), Vector3(1.0, 0.2, 9.4), L.mat_dark, false)
	var lan := [M.glow(Color(1.0, 0.55, 0.25), 2.5), M.glow(Color(1.0, 0.8, 0.35), 2.5)]
	for z in [29.6, 36.4]:
		for k in 15:
			var x := -49.0 + k * 18.0 / 14.0
			var sag := sin(k / 14.0 * PI) * 1.2
			var s := SphereMesh.new(); s.radius = 0.22; s.height = 0.5
			var mi := MeshInstance3D.new(); mi.mesh = s; mi.material_override = lan[k % 2]; mi.position = Vector3(x, 5.0 - sag, z); L.add_child(mi)
	for x in [-31.0, -49.0]:
		var l := OmniLight3D.new(); l.light_color = Color(1, 0.65, 0.35); l.light_energy = 1.6; l.omni_range = 9.0; l.position = Vector3(x, 4.2, 33); L.add_child(l)
	# chaos: a stall that was being wheeled to market, flattened; a sky car into the south rail; bags, a cart
	C.prop("stall_wreck", Vector3(-35.5, 0, 35.2), PI + 0.15, 1.0, Vector2.ZERO, false)
	C.box_collider(Vector3(-35.5, 0.6, 35.0), Vector3(2.6, 1.2, 2.2), 0.15)
	C.crashed_skycar(Vector3(-44, 0, 30.2), PI * 0.6, rng)
	C.prop("rubble", Vector3(-41.5, 0, 29.8), 0.0, 0.7)
	C.luggage(Vector3(-27, 0, 32), 2.4, 7, rng)
	C.luggage(Vector3(-52, 0, 34), 2.0, 5, rng)
	C.prop("luggage_cart", Vector3(-39, 0.1, 35.0), 1.2, 1.0, Vector2(0, PI / 2 - 0.15))
	C.prop("kit/crate_small", Vector3(-33, 0, 35.8), 0.4); C.prop("kit/crate_small", Vector3(-32.4, 0, 30.5), 1.1, 1.0, Vector2(0.4, 0))
	C.broken_sign("MARKET TERRACE  >>>", Vector3(-49, 4.5, 29.4), 0.0, Color(1.0, 0.78, 0.35), 0.35, 0.009)
	C.barricade(Vector3(-55.5, 0, 29.6), Vector3(-55.5, 0, 36.4), rng, 0.55, 2.8)
	# the Gardens Express: from the gardens' east edge, over the bridge and down into the plaza
	L.R_CHUTE = _rail(L, [Vector3(-51.2, 9.25, -1.0), Vector3(-48.5, 9.0, 2.5), Vector3(-44, 8.2, 6.5), Vector3(-38, 6.8, 10.5),
		Vector3(-31.5, 5.0, 14.0), Vector3(-26, 3.2, 16.5), Vector3(-21, 1.6, 18.0), Vector3(-17.5, 0.55, 18.5)], true)
	L.hint_sign("GARDENS EXPRESS TO THE PLAZA", Vector3(-52.5, 8.8, 1.5), PI)
	C.flush()

# ------------------------------------------------------------------ Freight Gangway: plaza -> Pier A
static func _gangway(L, rng: RandomNumberGenerator) -> void:
	var C: Node3D = Chaos.make(L, "gangway")
	var r := Rect2(22, 26, 36, 8)
	_deck(L, "pier_gangway", r, 0.0, Color(0.9, 0.9, 0.92), false)
	# yellow truss sides with flood lights
	for s in [26.0, 34.0]:
		L.railing(22.5, s, 57.5, s, 0.0)
		for x in range(24, 58, 6):
			L.box(Vector3(x, 1.8, s), Vector3(0.25, 3.6, 0.25), yellow, false)
		L.box(Vector3(40, 3.7, s), Vector3(36, 0.3, 0.3), yellow, false)
		for k in 6:
			var b := YK.beam(L, Vector3(24 + k * 6, 3.6, s), Vector3(27 + k * 6, 0.9, s), 0.12, "yellow")
	L.label("FREIGHT GANGWAY", Vector3(40, 0, 30), 4.0, Color(0.75, 0.98, 1))
	C.broken_sign("ALL FLIGHTS BOARDING AT PIER A", Vector3(40, 4.6, 34.0), 0.0, Color(0.5, 0.95, 1.0), -0.08, 0.009)
	# a cargo pod torn loose and spilled across the walk, crates everywhere
	C.prop("docks/container", Vector3(46, 0, 32.4), 1.35, 1.0, Vector2(0, 0.12))
	C.box_collider(Vector3(46, 1.2, 32.4), Vector3(3.0, 2.4, 6.2), 1.35)
	for i in 7:
		C.prop("kit/crate_small", Vector3(rng.randf_range(42, 50), 0, rng.randf_range(27, 33)), rng.randf() * TAU, 1.0, Vector2(rng.randf_range(-0.3, 0.3), 0))
	C.crashed_skycar(Vector3(30.5, 0, 33.0), -0.4, rng)
	C.luggage(Vector3(36, 0, 28.5), 2.4, 9, rng)
	C.luggage(Vector3(53, 0, 29), 2.0, 6, rng)
	for p in [[Vector3(25, 0, 28), 0.3, false], [Vector3(55.5, 0, 32.5), 2.0, true], [Vector3(38.5, 0, 32.8), 1.4, false]]:
		C.prop("luggage_cart", p[0], p[1], 1.0, Vector2(0, PI / 2 - 0.1) if p[2] else Vector2.ZERO, true)
	C.barricade(Vector3(56.5, 0, 26.5), Vector3(56.5, 0, 33.5), rng, 0.45, 2.8)
	# the cargo lift's plaza landing pad and its flight from Pier C
	L.box(Vector3(25, -0.65, 16), Vector3(5.6, 0.3, 5.6), L.mat_dark, false)
	L.label("CARGO LIFT", Vector3(25, 0.1, 16), 1.8, Color(0.75, 0.98, 1))
	L.moving_platform(Vector3(87.5, 5.7, -38), Vector3(25, -0.3, 16), 30.0, Vector3(5, 0.6, 5), "cargo_lift", false)
	C.flush()

# ------------------------------------------------------------------ Freight Approach: plaza -> causeway -> Crane Yard
static func _approach(L, rng: RandomNumberGenerator) -> void:
	var C: Node3D = Chaos.make(L, "approach")
	_deck(L, "yard_approach", Rect2(-10, -6, 8, 15), 0.0, Color(0.86, 0.86, 0.88), true)
	_deck(L, "yard_approach_n", Rect2(-10, -31, 8, 11), 0.0, Color(0.86, 0.86, 0.88), true)
	# Grudd's checkpoint halfway: a wider deck, a booth, boom gates (one snapped), abandoned in a hurry
	var cp := Rect2(-17, -20, 22, 14)
	_deck(L, "yard_checkpoint", cp, 0.0, Color(0.84, 0.84, 0.86), false, false)
	L.fence(cp, 0.0, [["n", -10, -2], ["s", -10, -2]], "nswe")
	for s in [-1, 1]:
		L.railing(-6 + s * 4, 9, -6 + s * 4, -6, 0.0)
		L.railing(-6 + s * 4, -20, -6 + s * 4, -30.5, 0.0)
	YK.bx(L, Vector3(-13, 1.4, -13), Vector3(3.0, 2.8, 3.0), "yellow", true)
	YK.bx(L, Vector3(-13, 2.9, -13), Vector3(3.6, 0.3, 3.6), "dark")
	YK.bx(L, Vector3(-11.45, 1.7, -13), Vector3(0.06, 1.0, 2.2), "glass")
	YK.poster(L, Vector3(-11.4, 0, -10.8), PI / 2, "CHECKPOINT 7", "res://textures/yard/poster_fist.png", Vector2(2.2, 1.6), "SHOW YOUR BADGE")
	for z in [-8.5, -17.5]:
		YK.bx(L, Vector3(-10.6, 0.6, z), Vector3(0.5, 1.2, 0.5), "dark", true)
		var arm := YK.node(L, Vector3(-10.6, 1.1, z))
		YK.bx(arm, Vector3(3.2, 0, 0), Vector3(6.4, 0.18, 0.18), "hazard")
		if z < -10: arm.rotation.z = 1.25            # snapped up
		else: arm.rotation = Vector3(0, -0.35, -0.12)  # knocked aside
	YK.work_light(L, Vector3(3.5, 0, -7), -PI * 0.8)
	YK.loudspeaker(L, Vector3(-16, 0, -19), 0.6)
	# a hauler jackknifed across the checkpoint, its containers spilled
	YK.container(L, Vector3(-1.0, 0, -15.5), false, Color(0.82, 0.3, 0.2))
	var tilt := YK.container(L, Vector3(2.0, 0, -10.0), true, Color(0.2, 0.5, 0.8))
	tilt.rotation = Vector3(0.0, 0.6, 0.12)
	C.prop("rubble", Vector3(-3, 0, -18), 0.3, 1.0)
	C.fire(Vector3(-0.8, 2.6, -15.5), 0.9)
	C.smoke(Vector3(-0.8, 3.2, -15.5), 1.4, true)
	for p in [Vector3(-8, 0, -9), Vector3(-4.5, 0, -12), Vector3(-15, 0, -8), Vector3(-7, 0, 2), Vector3(-3.5, 0, -25)]:
		C.prop("cone", p, rng.randf() * TAU, 1.0, Vector2(0, 1.5) if rng.randf() < 0.5 else Vector2.ZERO)
	C.prop("sawhorse", Vector3(-8.2, 0, -21.5), 0.1, 1.0, Vector2.ZERO, true)
	C.prop("sawhorse", Vector3(-3.6, 0, -22.0), -0.3, 1.0, Vector2(0, 1.4))
	C.prop("sandbags", Vector3(-15, 0, -16.5), PI / 2, 1.0, Vector2.ZERO, true)
	C.luggage(Vector3(-6, 0, 0), 2.0, 4, rng)
	L.label("FREIGHT APPROACH", Vector3(-6, 0, -26), 3.0, Color(1, 0.78, 0.85))
	# the long haul span between the old causeway and the gate: a queue of freight carts left where they stopped
	_deck(L, "yard_approach_span", Rect2(-10, -66, 8, 25), 0.0, Color(0.84, 0.84, 0.86), true)
	for s in [-1, 1]: L.railing(-6 + s * 4, -41, -6 + s * 4, -66, 0.0)
	for z in [-45.5, -53.0, -61.0]:
		C.prop("luggage_cart", Vector3(-8.4, 0, z), rng.randf_range(-0.3, 0.3), 1.0, Vector2.ZERO, true)
		C.luggage(Vector3(-3.4, 0, z + 2.0), 1.2, 3, rng)
	C.crashed_skycar(Vector3(-2.6, 0, -57.0), 0.4, rng, true)
	C.barricade(Vector3(-10, 0, -64.5), Vector3(-2, 0, -64.5), rng, 0.45, 2.6)
	C.broken_sign("GATE CLOSED", Vector3(-9.6, 2.6, -49.0), PI / 2, Color(1, 0.3, 0.25), 0.25)
	L.checkpoints.append({ pos = Vector3(-6, 0.1, -13), r = 3.0 })
	# lift bridge: causeway_2 -> the gate island, the lifting leaf stuck half up beside it
	# (the gate island's south fence only opens at x -3..3, so the bridge widens east to meet it)
	_deck(L, "yard_liftbridge_s", Rect2(-10, -80, 8, 6), 0.0, Color(0.84, 0.84, 0.86), true, false)
	_deck(L, "yard_liftbridge", Rect2(-10, -97, 14, 17), 0.0, Color(0.84, 0.84, 0.86), true)
	L.railing(-10, -74.5, -10, -96.5, 0.0); L.railing(-2, -74.5, -2, -80, 0.0)
	L.railing(4, -80, 4, -96.5, 0.0); L.railing(-2, -80, 4, -80, 0.0)
	for s in [-1, 1]:
		YK.lattice(L, Vector3(-6 + s * 5.6, 0, -78), 1.6, 12.0, "yellow", true)
	YK.girder(L, Vector3(-11.6, 12, -78), Vector3(-0.4, 12, -78), 1.0, "yellow")
	var leaf := YK.node(L, Vector3(6.0, 0, -88))
	YK.bx(leaf, Vector3(0, 4.0, 0), Vector3(0.6, 8.0, 7.0), "steel")
	YK.bx(leaf, Vector3(-0.32, 4.0, 0), Vector3(0.05, 7.6, 6.6), "hazard")
	leaf.rotation.z = -0.35
	C.prop("rubble", Vector3(-4.2, 0, -88), 0.6, 0.8)
	C.prop("cone", Vector3(-8.4, 0, -83), 0.0); C.prop("sandbags", Vector3(-8.3, 0, -93), PI / 2, 1.0, Vector2.ZERO, true)
	C.flush()

# ------------------------------------------------------------------ Skyline Cableway: gardens -> mast
static func _cableway(L, rng: RandomNumberGenerator) -> void:
	var C: Node3D = Chaos.make(L, "cableway")
	L.hook(Vector3(-44, 15.3, -40)); L.hook(Vector3(-34, 15.3, -40))
	var st := Rect2(-31, -44, 8, 8)
	L.island("mast_cable_station", st, 6.6, Color(0.86, 0.86, 0.9), 0.8)
	L.fence(st, 6.6, [["w", -42, -38], ["e", -42, -39]], "nsew")
	L.checkpoints.append({ pos = Vector3(-27, 6.7, -40), r = 2.4 })
	L.label("CABLEWAY", Vector3(-27, 6.6, -42.5), 2.4, Color(1, 0.85, 0.6))
	# the station's A-frame and the haul rope beside the grind cable
	for s in [-1, 1]: YK.beam(L, Vector3(-24.5, 6.6, -40 + s * 3.0), Vector3(-24.5, 12.0, -40), 0.25, "yellow")
	L.box(Vector3(-24.5, 12.1, -40), Vector3(0.8, 0.5, 4.0), L.mat_dark, false)
	var cable := [Vector3(-23.4, 7.05, -40.5), Vector3(-15, 6.0, -43.0), Vector3(-6, 5.5, -47.0), Vector3(1.0, 6.0, -50.5), Vector3(5.6, 7.2, -53.0)]
	_rail(L, cable, false, false)
	# the stalled car on the haul rope, swinging a little; a suitcase dangling from its door
	var haul_a := Vector3(-24.5, 11.5, -42.0); var haul_b := Vector3(4.5, 11.0, -55.0)
	YK.beam(L, haul_a, haul_b, 0.06, "dark")
	var g: Node3D = C.model("res://models/chaos/gondola.glb", haul_a.lerp(haul_b, 0.45) - Vector3(0, 4.7, 0), atan2(haul_b.x - haul_a.x, haul_b.z - haul_a.z), 1.0, Vector2(0.06, 0.1))
	C.fire(haul_a.lerp(haul_b, 0.45) - Vector3(0, 3.2, 0), 0.5, false)
	C.smoke(haul_a.lerp(haul_b, 0.45) - Vector3(0, 2.6, 0), 0.8, true)
	# the mast end: a terminal deck west of the catch ledge
	var tm := Rect2(0, -57, 6, 7)
	L.island("mast_terminal", tm, 6.6, Color(0.82, 0.84, 0.88), 0.8)
	L.fence(tm, 6.6, [["w", -54, -50], ["e", -57, -50]], "nsw")
	for s in [-1, 1]: YK.beam(L, Vector3(3.0, 6.6, -53.5 + s * 3.0), Vector3(3.0, 11.6, -53.5), 0.25, "yellow")
	C.luggage(Vector3(-27, 6.6, -38.5), 1.6, 5, rng)
	C.prop("luggage_cart", Vector3(-29, 6.6, -42), 0.5, 1.0, Vector2.ZERO, true)
	C.broken_sign("CABLEWAY CLOSED", Vector3(-24.6, 10.2, -40), PI / 2, Color(1.0, 0.45, 0.3), 0.2, 0.01)
	_sign(L, "CABLE LINE TO THE SIGNAL MAST", Vector3(-30.2, 6.6, -36.6), PI)
	C.flush()

# ------------------------------------------------------------------ Balloon Line: Pier C -> mast landing
static func _balloon_line(L, rng: RandomNumberGenerator) -> void:
	var C: Node3D = Chaos.make(L, "balloon_line")
	L.hook(Vector3(85, 12.5, -36)); L.hook(Vector3(75, 12.5, -36))
	var bg := Rect2(54, -40, 8, 12)
	L.islands["pier_barge"] = bg; L.heights["pier_barge"] = 3.0
	L.box(Vector3(58, 2.7, -34), Vector3(8, 0.6, 12), M.worn("deck", Color(0.85, 0.8, 0.72), 0.14, 0.45, 0.6, 0.55))
	L.box(Vector3(58, 1.9, -34), Vector3(7.2, 1.0, 11.2), M.paint(Color(0.2, 0.5, 0.82)), false)
	L.box(Vector3(58, 1.35, -34), Vector3(6.4, 0.2, 10.4), L.glow_cyan, false)
	L.fence(bg, 3.0, [["e", -38, -33], ["w", -36, -32]], "nsew")
	L.checkpoints.append({ pos = Vector3(58, 3.1, -34), r = 2.4 })
	L.label("BALLOON BARGE", Vector3(58, 3.0, -31), 2.0, Color(0.75, 0.98, 1))
	for p in [Vector3(55.5, 3.0, -38.5), Vector3(60.5, 3.0, -29.5)]:
		var ring: Vector3 = p + Vector3(0, 9.0, 0)
		YK.beam(L, p + Vector3(0, 0.1, 0), ring, 0.05, "dark")
		DD.balloon(L, ring, 0.4, M.std(Color(0.85, 0.3, 0.2), 0.3, 0.5))
	# the tether the barge was moored by: grind it down to the mast landing
	var tether := [Vector3(54.6, 3.45, -34.5), Vector3(49, 2.9, -38.5), Vector3(44, 3.05, -42.5), Vector3(39.5, 3.6, -46.0), Vector3(36.4, 3.85, -48.2)]
	L.set_meta("rail_balloon", _rail(L, tether, false, false))
	L.box(Vector3(54.6, 3.4, -34.5), Vector3(0.6, 0.8, 0.6), L.mat_brass, false)
	C.luggage(Vector3(59, 3.0, -36), 2.0, 6, rng)
	C.prop("sandbags", Vector3(56, 3.0, -30), 0.0)
	C.prop("kit/crate_large", Vector3(60.5, 3.0, -38.5), 0.3)
	C.broken_sign("LAST BARGE: GONE", Vector3(61.8, 5.0, -34), -PI / 2, Color(1.0, 0.5, 0.3), 0.2, 0.01)
	C.flush()

# ------------------------------------------------------------------ the dish rail down to the Crane Yard
static func _dish_rail(L) -> void:
	L.R_YARD = _rail(L, [Vector3(20, 20.45, -50.6), Vector3(19, 19.4, -55), Vector3(16.5, 16.6, -62), Vector3(12.5, 12.6, -71),
		Vector3(7.5, 8.2, -81), Vector3(4.0, 4.4, -90), Vector3(1.8, 1.8, -97.5), Vector3(1.0, 1.0, -101.5)], true)

# ------------------------------------------------------------------ traversal cases (final coordinates)
static func traversal_cases(moves: Dictionary) -> Dictionary:
	var run: Array = moves.run
	var walk := [[0.0, "move_forward", true], [2.6, "move_forward", false]]
	return {
		# the overhead cable from the halt's gantry all the way to the plaza
		rail_scrapline = [Vector3(0, 6.1, 96.2), PI, run, 0.0, Rect2(-22, 14, 44, 33), true, 10.0],
		# the stair up to the gantry
		halt_ramp = [Vector3(-5.1, 0.1, 111.5), PI, [[0.0, "move_forward", true], [2.8, "move_forward", false]], 6.0, Rect2(-8, 93, 11, 4.4), true, 4.5],
		# jump the collapsed span (double jump)
		viaduct_gap = [Vector3(1.6, 0.1, 74.5), PI, moves.dj, 0.0, Rect2(-4, 46, 8, 21), true],
		# the halt into the Sorting Works over the plank bridge
		works_bridge = [Vector3(-12.5, 0.1, 102), -PI / 2, walk, 0.0, Rect2(-50, 86, 32, 24), true],
		# bale steps up to the sorting gantry
		works_bale1 = [Vector3(-39.0, 0.1, 99), -PI / 2, moves.sj, 1.2, Rect2(-42.35, 97.85, 2.3, 2.3), true],
		works_bale2 = [Vector3(-41.2, 1.3, 99), -PI / 2, moves.sj, 2.4, Rect2(-44.75, 97.85, 2.3, 2.3), true],
		works_bale3 = [Vector3(-43.6, 2.5, 99), PI, moves.sj, 3.6, Rect2(-44.75, 93.25, 2.3, 4.6), true],
		works_gantry = [Vector3(-43.6, 3.7, 94.4), PI, moves.sj, 3.6, Rect2(-47, 86.1, 22, 4.5), true],
		# walk the lantern bridge and the gangway end to end
		lantern_walk = [Vector3(-23.5, 0.1, 32.6), -PI / 2, [[0.0, "move_forward", true], [5.5, "move_forward", false]], 0.0, Rect2(-112, 10, 54, 50), true, 7.0],
		gangway_walk = [Vector3(23.5, 0.1, 29.5), PI / 2, [[0.0, "move_forward", true], [5.5, "move_forward", false]], 0.0, Rect2(58, 10, 60, 40), true, 7.0],
		# Gardens Express down to the plaza
		rail_chute = [Vector3(-51.4, 8.9, -3.6), 0.0, run, 0.0, Rect2(-22, 14, 44, 32), true, 9.0],
		# promenade -> two hooks -> cable car station, then the cable to the mast
		# (holding forward after the swing runs straight onto the cableway, so the case ends at the mast terminal)
		hooks_gardens = [Vector3(-50.6, 8.9, -40), PI / 2, moves.hooks2, 6.6, Rect2(0, -57, 11, 7), true, 14.0],
		rail_cableway = [Vector3(-25.0, 6.7, -40.3), PI / 2, run, 6.6, Rect2(0, -57, 11, 7), true, 8.0],
		# Pier C -> two hooks -> balloon barge, then the tether to the mast landing
		hooks_docks = [Vector3(90.4, 6.1, -36), -PI / 2, moves.hooks2, 3.0, Rect2(54, -40, 8, 12), true],
		rail_balloon = [Vector3(56.2, 3.1, -33.6), -PI / 2 - 0.5, run, 3.0, Rect2(30, -54, 8, 12), true, 8.0],
		# the long dish rail to the Crane Yard gate
		rail_yard = [Vector3(20, 20.1, -48.5), PI, run, 0.0, Rect2(-18, -111, 36, 14), true, 10.0],
		# walk the freight approach through the checkpoint to the causeway
		approach_walk = [Vector3(-6, 0.1, 8), PI, [[0.0, "move_forward", true], [9.6, "move_forward", false]], 0.0, Rect2(-10, -80, 8, 14), true, 12.0],
	}
