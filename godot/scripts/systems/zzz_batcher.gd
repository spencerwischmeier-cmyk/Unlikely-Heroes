extends Node
## Static batching: the level is built from thousands of separate little meshes (boxes, cylinders, props),
## and each one costs the renderer a draw call per pass (colour, depth and up to four shadow cascades).
## Once the level is up, this merges the pieces that never move into one mesh per material, per 32 m
## cell, per shadow/draw-distance setting, and removes the originals. Collision is untouched (it lives
## on separate bodies).
##
## A piece is only merged when nothing can move, hide or restyle it later:
##  - it is a plain MeshInstance3D (no script, no children) with StandardMaterial3D materials only
##    (shader materials may use per-instance values), not transparent, not skinned
##  - neither it nor any parent up to the level has a script, is a moving body (Animatable, Rigid,
##    Character), is a gate/mover/hook/bouncer, or is referenced from any script's variables
##  - it did not move or change visibility while the level was watched for a moment
## `--no-batch` turns it off; `--batch-log` prints what it did.

const CELL := 64.0
const WATCH_T := 1.2
const SLICE_US := 4000
var done := false

var log_on := false
var refs := {}
var cands: Array = []           # [MeshInstance3D, Transform3D, visible]

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--no-batch") or Game.level == null: done = true; return
	log_on = args.has("--batch-log")
	await get_tree().process_frame
	await get_tree().process_frame
	var t0 := Time.get_ticks_msec()
	var referenced := _referenced_nodes()
	refs = referenced
	_collect(Game.level, referenced, false)
	if log_on: print("[batch] %d candidates (%d referenced nodes excluded) in %d ms" % [cands.size(), referenced.size(), Time.get_ticks_msec() - t0])
	await get_tree().create_timer(WATCH_T, true).timeout
	await _merge()
	await get_tree().process_frame
	if args.has("--batch-why"): _why()

## debug: why the meshes that are still separate weren't merged, by area
func _why() -> void:
	var out := {}
	for mi in Game.level.find_children("*", "MeshInstance3D", true, false):
		if mi.get_parent().name == "StaticBatches" or not mi.is_visible_in_tree(): continue
		var r := "?"
		if mi.get_script() != null: r = "script"
		elif mi.get_child_count() > 0: r = "children"
		elif not _mergeable(mi):
			r = "material"
			var m = mi.get_active_material(0)
			if m is ShaderMaterial: r = "shader"
			elif m is StandardMaterial3D and m.transparency != 0: r = "transparent"
		else:
			var a: Node = mi.get_parent()
			while a != Game.level and a != null:
				if a.get_script() != null: r = "scripted parent " + String(a.name); break
				a = a.get_parent()
			if r == "?":
				a = mi
				while a != Game.level and a != null:
					if refs.has(a): r = "referenced " + a.get_class(); break
					if a.get_meta_list().size() > 0: r = "meta"; break
					var nm := String(a.name).to_lower()
					for k in SKIP_NAMES: if nm.contains(k): r = "name " + k; break
					if r != "?": break
					if a is CollisionObject3D: r = "body " + a.get_class(); break
					a = a.get_parent()
			if r == "?": r = "single in group"
		var path := str(mi.get_path()).split("/")
		var k := (path[4] if path.size() > 5 else "-") + " : " + r
		out[k] = int(out.get(k, 0)) + 1
	var ks := out.keys(); ks.sort_custom(func(a, b): return out[a] > out[b])
	for k in ks.slice(0, 40): print("[why] %5d  %s" % [out[k], k])

## Every node held in some script's variables (directly, or inside arrays and dictionaries).
func _referenced_nodes() -> Dictionary:
	var out := {}
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		var sc: Script = n.get_script()
		if sc == null or n == self: continue
		for prop in n.get_property_list():
			if not (prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE): continue
			_scan_value(n.get(prop.name), out, 0)
	return out

func _scan_value(v, out: Dictionary, depth: int) -> void:
	if depth > 4: return
	if typeof(v) == TYPE_OBJECT:
		if is_instance_valid(v) and (v is Node or v is Material): out[v] = true
	elif v is Array:
		for x in v: _scan_value(x, out, depth + 1)
	elif v is Dictionary:
		for k in v: _scan_value(v[k], out, depth + 1); _scan_value(k, out, depth + 1)

const SKIP_NAMES := ["skyworld", "chaos", "panic", "crowd", "porch_chair", "arenabridge", "door", "gate",
	"bridge", "rotor", "blade", "turbine", "dish", "lift", "fan", "flag", "beacon", "vesk", "dodger"]

func _collect(n: Node, referenced: Dictionary, _unused: bool) -> void:
	for c in n.get_children():
		if referenced.has(c) or c.get_script() != null or c.get_meta_list().size() > 0: continue
		if c is AnimatableBody3D or c is RigidBody3D or c is CharacterBody3D or c is Skeleton3D: continue
		if c is CanvasItem or c is AnimationMixer or c is GPUParticles3D or c is CPUParticles3D: continue
		var nm := String(c.name).to_lower()
		var skip := false
		for k in SKIP_NAMES: if nm.contains(k): skip = true; break
		if skip: continue
		if c is Node3D and not (c as Node3D).visible: continue
		if c is MeshInstance3D and _mergeable(c as MeshInstance3D): cands.append([c, (c as Node3D).global_transform])
		if c.get_child_count() > 0: _collect(c, referenced, false)

func _mergeable(mi: MeshInstance3D) -> bool:
	if mi.mesh == null or not mi.visible or mi.skin != null: return false
	if not (mi.mesh is ArrayMesh or mi.mesh is PrimitiveMesh): return false
	if mi.mesh is ArrayMesh and (mi.mesh as ArrayMesh).get_blend_shape_count() > 0: return false
	if mi.material_overlay != null or mi.visibility_range_begin > 0.0: return false
	for s in mi.mesh.get_surface_count():
		var m := mi.get_active_material(s)
		if not (m is StandardMaterial3D): return false
		var sm := m as StandardMaterial3D
		if sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or sm.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED: return false
		if sm.next_pass != null: return false
		if mi.mesh is ArrayMesh and (mi.mesh as ArrayMesh).surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES: return false
	return true

## Materials are often made fresh for every piece, so pieces that look identical rarely share one.
## Identical materials (same settings and textures) share a key; one a script holds keeps its own,
## since the script may change it later.
var _mkeys := {}
var _sig_props: Array = []
func _mat_key(m: Material) -> String:
	var id := m.get_instance_id()
	if _mkeys.has(id): return _mkeys[id]
	var k := ""
	if refs.has(m): k = "id%d" % id
	else:
		if _sig_props.is_empty():
			for pr in m.get_property_list():
				if pr.usage & PROPERTY_USAGE_STORAGE and pr.name != "resource_name" and pr.name != "resource_local_to_scene" and pr.name != "script":
					_sig_props.append(pr.name)
		var parts := PackedStringArray()
		for pn in _sig_props:
			var v = m.get(pn)
			parts.append(("r%d" % v.get_instance_id()) if v is Resource else str(v))
		k = "|".join(parts).md5_text()
	_mkeys[id] = k
	return k

## Object-space triplanar mapping would slide once the vertices move into the batch's space, so a
## batch of such pieces maps in world space instead (same texture and density, only the offset moves).
var _world_mats := {}
func _batch_mat(key: String, m: StandardMaterial3D) -> StandardMaterial3D:
	var local1 := m.uv1_triplanar and not m.uv1_world_triplanar
	var local2 := m.uv2_triplanar and not m.uv2_world_triplanar
	if not (local1 or local2): return m
	if _world_mats.has(key): return _world_mats[key]
	var w := m.duplicate() as StandardMaterial3D
	if local1: w.uv1_world_triplanar = true
	if local2: w.uv2_world_triplanar = true
	_world_mats[key] = w
	return w

var _jobs: Array = []
var _arr_cache := {}

## A surface's vertex data, fetched once per mesh. Primitive meshes (boxes, cylinders) generate it on
## the CPU; reading an imported mesh back from the graphics card is slow, so each is read only once.
func _arrays(m: Mesh, s: int) -> Array:
	var key := "%d:%d" % [m.get_instance_id(), s]
	if _arr_cache.has(key): return _arr_cache[key]
	var a: Array = (m as PrimitiveMesh).get_mesh_arrays() if m is PrimitiveMesh else m.surface_get_arrays(s)
	_arr_cache[key] = a
	return a

## Worker: one batch's arrays (positions, normals, uvs, optional tangents/colours, indices).
func _build_job(i: int) -> void:
	var job: Dictionary = _jobs[i]
	var V := PackedVector3Array(); var N := PackedVector3Array(); var UV := PackedVector2Array()
	var T := PackedFloat32Array(); var C := PackedColorArray(); var I := PackedInt32Array()
	var want_t: bool = job.want_t
	var want_c: bool = job.want_c
	for p in job.parts:
		var a: Array = p[0]
		var xf: Transform3D = p[1]
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var n := vs.size()
		if n == 0: continue
		var base := V.size()
		V.append_array(xf * vs)
		var sc := xf.basis.get_scale()
		var uniform := absf(sc.x - sc.y) < 1e-3 and absf(sc.y - sc.z) < 1e-3
		var flip := xf.basis.determinant() < 0.0
		var ns = a[Mesh.ARRAY_NORMAL]
		if ns != null and (ns as PackedVector3Array).size() == n:
			if uniform:
				N.append_array(Transform3D(xf.basis.orthonormalized() if not flip else xf.basis.inverse().transposed().orthonormalized(), Vector3.ZERO) * (ns as PackedVector3Array))
			else:
				var nb := xf.basis.inverse().transposed()
				for v in (ns as PackedVector3Array): N.append((nb * v).normalized())
		else:
			for k in n: N.append(Vector3.UP)
		var uvs = a[Mesh.ARRAY_TEX_UV]
		if uvs != null and (uvs as PackedVector2Array).size() == n: UV.append_array(uvs)
		else:
			UV.resize(UV.size() + n)
		if want_t:
			var ts = a[Mesh.ARRAY_TANGENT]
			if ts != null and (ts as PackedFloat32Array).size() == n * 4:
				var tsa: PackedFloat32Array = ts
				for k in n:
					var tv: Vector3 = (xf.basis * Vector3(tsa[k * 4], tsa[k * 4 + 1], tsa[k * 4 + 2])).normalized()
					T.append(tv.x); T.append(tv.y); T.append(tv.z); T.append(-tsa[k * 4 + 3] if flip else tsa[k * 4 + 3])
			else:
				for k in n: T.append(1.0); T.append(0.0); T.append(0.0); T.append(1.0)
		if want_c:
			var cs = a[Mesh.ARRAY_COLOR]
			if cs != null and (cs as PackedColorArray).size() == n: C.append_array(cs)
			else:
				for k in n: C.append(Color.WHITE)
		var idx = a[Mesh.ARRAY_INDEX]
		var ii: PackedInt32Array = idx if idx != null else PackedInt32Array()
		if ii.is_empty():
			ii.resize(n)
			for k in n: ii[k] = k
		var m := ii.size() - ii.size() % 3
		var start := I.size()
		I.resize(start + m)
		if flip:
			for k in range(0, m, 3):
				I[start + k] = base + ii[k]; I[start + k + 1] = base + ii[k + 2]; I[start + k + 2] = base + ii[k + 1]
		else:
			for k in m: I[start + k] = base + ii[k]
	if V.is_empty(): return
	var arr := []; arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = V; arr[Mesh.ARRAY_NORMAL] = N; arr[Mesh.ARRAY_TEX_UV] = UV
	if want_t: arr[Mesh.ARRAY_TANGENT] = T
	if want_c: arr[Mesh.ARRAY_COLOR] = C
	arr[Mesh.ARRAY_INDEX] = I
	job.out = arr

func _merge() -> void:
	var t0 := Time.get_ticks_msec()
	var groups := {}
	var moved := 0
	for c in cands:
		if not is_instance_valid(c[0]): moved += 1; continue
		var mi: MeshInstance3D = c[0]
		if not mi.is_inside_tree() or not mi.is_visible_in_tree(): moved += 1; continue
		if not mi.global_transform.is_equal_approx(c[1]): moved += 1; continue
		var xf := mi.global_transform
		# pieces with a draw distance batch in smaller cells, so a batch fades as its pieces would
		var cs := CELL if mi.visibility_range_end <= 0.0 else clampf(mi.visibility_range_end * 0.25, 8.0, CELL)
		var cell := Vector3i(floori(xf.origin.x / cs), floori(xf.origin.y / cs), floori(xf.origin.z / cs))
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s)
			var mk := _mat_key(mat)
			var ks := "%s|%d|%s|%d|%d|%d" % [cell, int(cs), mk, mi.cast_shadow, int(mi.visibility_range_end), mi.layers]
			if not groups.has(ks): groups[ks] = { mat = mat, mk = mk, src = mi, parts = [] }
			groups[ks].parts.append([mi, s])
	# a group is built when it merges two or more pieces, or holds a surface of a multi-surface piece
	# (so that piece can go entirely); single-surface pieces alone in their group stay as they are.
	var jobs: Array = []
	var t_group := Time.get_ticks_msec() - t0
	for ks in groups:
		var g: Dictionary = groups[ks]
		var build: bool = g.parts.size() >= 2
		if not build:
			for p in g.parts: if (p[0] as MeshInstance3D).mesh.get_surface_count() > 1: build = true
		if not build: continue
		var src: MeshInstance3D = g.src
		var origin: Vector3 = src.global_position
		var mat: StandardMaterial3D = g.mat
		var job := { g = g, origin = origin, parts = [], out = null,
			want_t = mat.normal_enabled and not mat.uv1_triplanar,
			want_c = mat.vertex_color_use_as_albedo }
		for p in g.parts:
			var mi: MeshInstance3D = p[0]
			job.parts.append([_arrays(mi.mesh, p[1]), Transform3D(Basis(), -origin) * mi.global_transform])
		jobs.append(job)
	var t_fetch := Time.get_ticks_msec() - t0 - t_group
	# the heavy part (moving every vertex into the batch's space) runs on worker threads where the
	# platform has them, otherwise a few ms per frame
	_jobs = jobs
	if OS.has_feature("threads") and not OS.get_cmdline_user_args().has("--batch-no-threads"):
		var tid := WorkerThreadPool.add_group_task(_build_job, jobs.size(), -1, true, "batcher")
		while not WorkerThreadPool.is_group_task_completed(tid): await get_tree().process_frame
		WorkerThreadPool.wait_for_group_task_completion(tid)
	else:
		var st0 := Time.get_ticks_usec()
		for i in jobs.size():
			_build_job(i)
			if Time.get_ticks_usec() - st0 > SLICE_US: await get_tree().process_frame; st0 = Time.get_ticks_usec()
	var t_build := Time.get_ticks_msec() - t0 - t_group - t_fetch
	# hand the meshes to the renderer and retire the originals, a slice per frame
	var root := Node3D.new(); root.name = "StaticBatches"
	Game.level.add_child(root)
	var made := 0
	var dropped := 0
	var gone := {}
	var slice_t := Time.get_ticks_usec()
	for job in jobs:
		if Time.get_ticks_usec() - slice_t > SLICE_US:
			await get_tree().process_frame
			slice_t = Time.get_ticks_usec()
		var g: Dictionary = job.g
		var ok := job.out != null
		for p in g.parts: if not is_instance_valid(p[0]) or not (p[0] as Node).is_inside_tree(): ok = false
		if not ok: continue
		var src: MeshInstance3D = g.src
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, job.out)
		am.surface_set_material(0, _batch_mat(g.mk, g.mat))
		job.out = null; job.parts = []
		var out := MeshInstance3D.new(); out.mesh = am; out.name = "Batch%d" % made
		out.cast_shadow = src.cast_shadow; out.layers = src.layers; out.gi_mode = src.gi_mode
		out.visibility_range_end = src.visibility_range_end
		out.visibility_range_end_margin = src.visibility_range_end_margin
		out.visibility_range_fade_mode = src.visibility_range_fade_mode
		out.position = job.origin
		root.add_child(out)
		made += 1
		for p in g.parts:
			var mi: MeshInstance3D = p[0]
			gone[mi] = int(gone.get(mi, 0)) + 1
			if gone[mi] == mi.mesh.get_surface_count():
				dropped += 1
				# a piece that holds other nodes (its collision, child pieces) stays as an empty holder
				if mi.get_child_count() > 0: mi.mesh = null
				else: mi.queue_free()
	_jobs = []; _arr_cache.clear()
	if log_on: print("[batch] timings: group %d ms, fetch %d ms, build %d ms, upload %d ms" % [t_group, t_fetch, t_build, Time.get_ticks_msec() - t0 - t_group - t_fetch - t_build])
	if log_on: print("[batch] %d batches replace %d of %d pieces (%d moved/hidden, skipped) in %d ms" % [made, dropped, cands.size(), moved, Time.get_ticks_msec() - t0])
	done = true
