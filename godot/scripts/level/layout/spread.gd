extends RefCounted
## Spread: pushes each Skyharbor area out from the Dock Plaza so they stop crowding each other, leaving room
## for real transition pieces between them (scripts/level/areas/w_routes.gd).
##
## The areas are still built at their original coordinates (thousands of hand-placed numbers across
## level_skyharbor.gd and the area files). While building, the level tags every node and every list entry
## each area adds; `apply()` then moves the area's nodes under a "Spread_<group>" node offset by the group's
## shift, and shifts the level's world-space lists (islands, checkpoints, bounce pads, zones, spots).
## Code that keeps its own world positions (life nodes, cutscenes, panic, the ground tour) converts them
## with `at()`, which classifies an ORIGINAL position by area. `--no-spread` turns it all off.
##
## Groups (offset):  junk (south)   west: Terrace + Roof Gardens   docks (east)   mast (north-east)
##                   yard: Crane Yard and its causeway (north)      plaza: stays put

const OFF := {
	junk = Vector3(0, 0, 45),
	west = Vector3(-30, 0, 0),
	docks = Vector3(30, 0, 0),
	mast = Vector3(6, 0, -14),
	yard = Vector3(0, 0, -40),
}

static var enabled := true
static var _checked := false

static func on() -> bool:
	if not _checked:
		_checked = true
		enabled = not OS.get_cmdline_user_args().has("--no-spread")
	return enabled

static func offset(group: String) -> Vector3:
	if not on(): return Vector3.ZERO
	return OFF.get(group, Vector3.ZERO)

## which area group an ORIGINAL (pre-spread) position belongs to
static func group_at(p: Vector3) -> String:
	var x := p.x; var z := p.z
	# the causeway north of the plaza belongs to the Crane Yard now
	if x > -15.0 and x < 3.0 and z < 8.5 and z > -56.0: return "yard"
	# Signal Mast: gallery, landings, catch ledge, relay pylon
	if x >= -1.0 and x <= 34.0 and z >= -56.0 and z <= -20.0: return "mast"
	if x > 34.0 and x <= 54.0 and z >= -62.0 and z < -44.0 and p.y > 2.5: return "mast"
	# hive grove above Container Row
	if x > -52.0 and x < -24.0 and z > -72.0 and z < -54.0 and p.y > 6.0: return "west"
	if z < -55.0: return "yard"
	if z > 60.5 and x > -48.0: return "junk"
	if x >= 24.0 and z > -50.0: return "docks"
	if x <= -19.5 and z < 13.5: return "west"
	if x <= -22.5 and z <= 60.5: return "west"
	return "plaza"

## where an ORIGINAL position ends up
static func at(p: Vector3) -> Vector3:
	if not on(): return p
	return p + offset(group_at(p))

static func rect_at(r: Rect2, group := "") -> Rect2:
	if not on(): return r
	var g := group if group != "" else group_at(Vector3(r.get_center().x, 0, r.get_center().y))
	var o := offset(g)
	return Rect2(r.position + Vector2(o.x, o.z), r.size)

static func shift_rect(r: Rect2, o: Vector3) -> Rect2:
	return Rect2(r.position + Vector2(o.x, o.z), r.size)

# ------------------------------------------------------------------ build-time tagging
## The level calls begin(L, group) before building a piece and end(L) after it.
class Rec:
	var group := ""
	var kids0 := 0
	var arrays := {}
	var island_keys := {}

static var _open: Rec = null
static var _records: Array = []

const LISTS := ["rails", "hooks", "bouncers", "movers", "checkpoints"]

static func reset() -> void:
	_records.clear(); _open = null

static func begin(L: Node3D, group: String) -> void:
	var r := Rec.new()
	r.group = group; r.kids0 = L.get_child_count()
	for k in LISTS: r.arrays[k] = (L.get(k) as Array).size()
	for k in L.islands: r.island_keys[k] = true
	_open = r

static func end(L: Node3D) -> void:
	var r := _open
	if r == null: return
	_open = null
	var rec := { group = r.group, kids = [], lists = {}, islands = [] }
	for i in range(r.kids0, L.get_child_count()): rec.kids.append(L.get_child(i))
	for k in LISTS:
		var arr: Array = L.get(k)
		rec.lists[k] = arr.slice(r.arrays[k])
	for k in L.islands:
		if not r.island_keys.has(k): rec.islands.append(k)
	_records.append(rec)

## move every tagged area into place and shift the level's world-space data
static func apply(L: Node3D) -> void:
	if not on():
		_records.clear(); return
	var holders := {}
	for rec in _records:
		var g: String = rec.group
		var o := offset(g)
		if o == Vector3.ZERO: continue
		if not holders.has(g):
			var h := Node3D.new(); h.name = "Spread_" + g; h.position = o
			L.add_child(h); holders[g] = h
		var h: Node3D = holders[g]
		for n in rec.kids:
			if not is_instance_valid(n) or n.get_parent() != L: continue
			if n.name == "SkyWorld": continue          # the distant city stays where it is
			n.reparent(h, false)
		for k in rec.islands:
			L.islands[k] = shift_rect(L.islands[k], o)
		for b in rec.lists.bouncers: b.pos += o
		for c in rec.lists.checkpoints: c.pos += o
		# movers' a/b are in their body's parent space (the body moved with its area); rails are sampled
		# through path.to_global; hooks are nodes: nothing else to do for those
	_records.clear()
	# world-space lists the level filled from hard-coded positions
	L.start_pos = at(L.start_pos)
	for i in L.crate_spots.size(): L.crate_spots[i] = at(L.crate_spots[i])
	for p in L.pickup_spots: p.pos = at(p.pos)
	for s in L.shop_spots: s.pos = at(s.pos)
	for k in L.debug_spots.keys():
		var s: Array = L.debug_spots[k]
		L.debug_spots[k] = [at(s[0]), s[1]]
	L.vault_door.pos = at(L.vault_door.pos)
	L.mast_top = at(L.mast_top)
	for k in ["dodger_crash_pos", "porch_chair_pos", "gear_pos"]: L.set(k, at(L.get(k)))
	for z in L.zones: _shift_zone(z)

const ZONE_GROUP := {
	junk_crash = "junk", junkyard = "junk", dodger_launch = "junk",
	docks = "docks", turbines = "docks",
	terrace = "west", gardens = "west",
	mast_climb = "mast", mast_pylon = "mast", mast = "mast",
	yard_gate = "yard", yard_row = "yard", yard = "yard",
}

static func _shift_zone(z: Dictionary) -> void:
	var g: String = ZONE_GROUP.get(z.id, "")
	if g == "" and z.has("rect"):
		var c: Vector2 = (z.rect as Rect2).get_center()
		g = group_at(Vector3(c.x, z.get("y", 0.0), c.y))
	var o := offset(g)
	if o == Vector3.ZERO: return
	if z.has("rect"): z.rect = shift_rect(z.rect, o)
	if z.has("boss_pos"): z.boss_pos += o
	for s in z.get("switches", []): s.pos += o
	for gd in z.get("guards", []): gd.rect = shift_rect(gd.rect, o)
