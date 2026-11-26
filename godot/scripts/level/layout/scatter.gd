extends Node3D
## Scatter: drops the panic's leftovers (luggage, carts, toppled stalls, crashed sky cars, fires, broken signs)
## inside the areas themselves, where hand-placing every prop around thousands of existing pieces would be
## fragile. Each cluster lists what to drop and roughly where; a couple of physics frames after the level
## loads, every prop is checked against the real geometry: it must land on its area's floor (raycast down,
## the floor height must match) with solid floor under its whole footprint and nothing already standing there
## (box query). Anything that does not fit is skipped, so moving a stall or a wall later never buries a prop.
## Props are decoration only (no collision), so they can never block a route. Everything goes into one
## Chaos node per cluster group (batched MultiMeshes, see chaos.gd).

const Chaos := preload("res://scripts/level/layout/chaos.gd")

const FOOT := {
	suitcase_teal = 0.8, suitcase_coral = 0.8, suitcase_mustard = 0.8, duffel = 0.8, luggage = 0.8,
	luggage_cart = 2.2, stall_wreck = 3.4, rubble = 1.6, cone = 0.5, sawhorse = 1.6, sandbags = 1.4,
	sign_bent = 1.0, skycar = 4.4, fire = 1.2,
}

var L: Node3D
var plan: Array = []          # { area, c: Vector3 (final coords, y = floor), r, items: [[kind, count]] }
var _frames := 0
var rng := RandomNumberGenerator.new()
var placed := 0
var skipped := 0

func setup(level: Node3D, p: Array) -> void:
	L = level; plan = p
	rng.seed = 4242

func _physics_process(_dt: float) -> void:
	_frames += 1
	if _frames < 3: return
	set_physics_process(false)
	var t0 := Time.get_ticks_usec()
	var by_area := {}
	for cl in plan:
		var a: String = cl.area
		if not by_area.has(a): by_area[a] = Chaos.make(L, "scatter_" + a)
		_cluster(by_area[a], cl)
	for a in by_area: by_area[a].flush()
	if OS.get_cmdline_user_args().has("--scatter-log"):
		print("[scatter] placed %d, skipped %d in %.1f ms" % [placed, skipped, (Time.get_ticks_usec() - t0) / 1000.0])

func _cluster(C: Node3D, cl: Dictionary) -> void:
	var c: Vector3 = cl.c; var r: float = cl.r
	for it in cl.items:
		var kind: String = it[0]
		for i in int(it[1]):
			var ok := false
			for attempt in 10:
				var a := rng.randf() * TAU; var d := sqrt(rng.randf()) * r
				var p := c + Vector3(cos(a) * d, 0, sin(a) * d)
				var f: float = FOOT.get(kind, 1.0)
				var hit := _floor(p, c.y)
				if hit == INF: continue
				p.y = hit
				if not _clear(p, f): continue
				_put(C, kind, p)
				ok = true; placed += 1
				break
			if not ok: skipped += 1

## the floor height under p if it is this cluster's floor (within 0.45 m), else INF
func _floor(p: Vector3, want_y: float) -> float:
	var ss := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 4.0, 0), p + Vector3(0, -3.0, 0))
	var h := ss.intersect_ray(q)
	if h.is_empty(): return INF
	if absf(h.position.y - want_y) > 0.45 or h.normal.y < 0.9: return INF
	return h.position.y

## floor all round the footprint and nothing standing in it
func _clear(p: Vector3, f: float) -> bool:
	var half := f * 0.5 + 0.2
	for o in [Vector3(half, 0, half), Vector3(-half, 0, half), Vector3(half, 0, -half), Vector3(-half, 0, -half)]:
		if absf(_floor(p + o, p.y) - p.y) > 0.2: return false
	var ss := get_world_3d().direct_space_state
	var sh := BoxShape3D.new(); sh.size = Vector3(f + 0.3, 1.6, f + 0.3)
	var q := PhysicsShapeQueryParameters3D.new(); q.shape = sh
	q.transform = Transform3D(Basis(), p + Vector3(0, 0.95, 0))
	q.collide_with_areas = false
	return ss.intersect_shape(q, 1).is_empty()

func _put(C: Node3D, kind: String, p: Vector3) -> void:
	var yaw := rng.randf() * TAU
	match kind:
		"luggage":
			C.luggage(p, 0.6, 1, rng)
		"skycar":
			var car: Node3D = C.model("res://models/panic/skycar.glb", p + Vector3(0, 0.55, 0), yaw, 1.0, Vector2(rng.randf_range(0.18, 0.32), rng.randf_range(-0.35, 0.35)))
			if car: Chaos._fit(car, 4.2)
			C.prop("rubble", p + Vector3(cos(yaw) * 1.8, 0, -sin(yaw) * 1.8), rng.randf() * TAU, 0.8)
			C.fire(p + Vector3(0, 1.2, 0), 1.0)
			C.smoke(p + Vector3(0, 1.8, 0), 1.2, true)
		"fire":
			C.prop("rubble", p, yaw, 0.7)
			C.fire(p + Vector3(0, 0.5, 0), 0.8, rng.randf() < 0.6)
			C.smoke(p + Vector3(0, 1.2, 0), 1.0, true)
		"cone":
			C.prop("cone", p, yaw, 1.0, Vector2(0, 1.5) if rng.randf() < 0.45 else Vector2.ZERO)
		"luggage_cart":
			C.prop("luggage_cart", p, yaw, 1.0, Vector2(0, 1.4) if rng.randf() < 0.3 else Vector2.ZERO)
			C.luggage(p + Vector3(1.4, 0, 0.6), 0.8, 2, rng)
		"stall_wreck":
			C.prop("stall_wreck", p, yaw, 1.0)
		"sign_bent":
			C.prop("sign_bent", p, yaw, 1.0, Vector2(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.3, 0.3)))
		_:
			C.prop(kind, p, yaw, 1.0)
