extends Node
## Debug: `-- --perf-probe[=secs]` prints a line every second: fps, frame/process/physics ms, draw calls,
## objects, primitives, bots and where Vesk is; the camera turns slowly so each spot is sampled all round.
## Quits after `secs` (default 20) with averages. Use with --at=<spot> --no-title.

var on := false
var secs := 20.0
var t := 0.0
var acc_t := 0.0
var frames := 0
var rows: Array = []

# --perf-bisect: switches each big part of the scene off for a moment and reports how much main-thread
# time it was costing (finds what makes the game CPU-bound)
var bisect := false
var cands: Array = []
var ci := -1
var phase_t := 0.0
var samp := 0.0
var samp_n := 0
var base_ms := 0.0
var costs: Array = []

class Mark extends Node:
	var probe
	var first := true
	func _process(_dt: float) -> void:
		if first: probe.t0 = Time.get_ticks_usec()
		else: probe.script_us = Time.get_ticks_usec() - probe.t0
	func _physics_process(_dt: float) -> void:
		if first: probe.p0 = Time.get_ticks_usec()
		else: probe.phys_us += Time.get_ticks_usec() - probe.p0

var t0 := 0
var p0 := 0
var script_us := 0      # time spent in every _process callback this frame
var phys_us := 0        # time spent in _physics_process callbacks since the last frame

func _add_marks() -> void:
	for f in [true, false]:
		var m := Mark.new(); m.probe = self; m.first = f
		m.process_priority = -100000 if f else 100000
		m.process_physics_priority = -100000 if f else 100000
		get_tree().root.add_child.call_deferred(m)

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--perf-bisect": bisect = true; on = true; secs = 9999.0
		if a == "--perf-probe": on = true
		elif a.begins_with("--perf-probe="): on = true; secs = float(a.substr(13))
	set_process(on)
	if on:
		_add_marks()
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)

func _process(dt: float) -> void:
	if bisect: _bisect(dt); return
	t += dt; acc_t += dt; frames += 1
	_spike(dt)
	if Game.cam and t > 2.0: Game.cam.yaw += dt * 0.35
	if acc_t < 1.0: return
	var fps := frames / acc_t
	acc_t = 0.0; frames = 0
	if t < 3.0: return   # skip the load hitch
	var r := {
		fps = fps,
		proc = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		phys = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		draws = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		objs = Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		prims = Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		nodes = Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		scr = script_us / 1000.0,
	}
	rows.append(r)
	print("[perf] t=%.0f scripts %.1fms fps %.0f frame %.1fms phys %.1fms draws %d objs %d prims %dk nodes %d bots %d at %s" % [t, r.scr, r.fps, r.proc, r.phys, r.draws, r.objs, r.prims / 1000, r.nodes,
		get_tree().get_nodes_in_group("bots").size(), Game.player.global_position.snapped(Vector3.ONE) if Game.player else Vector3.ZERO])
	if t >= secs:
		var avg := func(k): return rows.reduce(func(a, x): return a + float(x[k]), 0.0) / rows.size()
		print("[perf] AVG fps %.1f min %.0f proc %.1fms phys %.1fms draws %.0f prims %.0fk" % [avg.call("fps"), rows.map(func(x): return x.fps).min(), avg.call("proc"), avg.call("phys"), avg.call("draws"), avg.call("prims") / 1000.0])
		get_tree().quit()

## A frame over 30 ms prints what it was made of: our scripts, physics (and how many physics steps
## it had to catch up), the renderer's CPU and GPU time for the last frame, node count change, draws.
var _last_nodes := 0
var _last_pf := 0
var _last_phys_us := 0
func _spike(dt: float) -> void:
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var pf := Engine.get_physics_frames()
	var ph_us := phys_us - _last_phys_us
	if t > 3.0 and dt > 0.030:
		var vp := get_viewport().get_viewport_rid()
		print("[spike] t=%.2f frame %.1fms scripts %.1fms physics %.1fms (%d steps) render cpu %.1fms gpu %.1fms setup %.1fms nodes %+d draws %d" % [t, dt * 1000.0,
			script_us / 1000.0, ph_us / 1000.0, pf - _last_pf,
			RenderingServer.viewport_get_measured_render_time_cpu(vp), RenderingServer.viewport_get_measured_render_time_gpu(vp),
			RenderingServer.get_frame_setup_time_cpu(), nodes - _last_nodes, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
	_last_nodes = nodes; _last_pf = pf; _last_phys_us = phys_us

## Candidates are groups: every node running a given script's _process/_physics_process, plus all
## AnimationPlayers / AnimationTrees, all CPU particles, all Skeleton3Ds.
func _collect() -> void:
	var by := {}
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n == self: continue
		var key := ""
		var sc: Script = n.get_script()
		if sc and (n.is_processing() or n.is_physics_processing()): key = sc.resource_path.get_file()
		elif n is AnimationMixer: key = "<AnimationMixer>"
		elif n is CPUParticles3D or n is GPUParticles3D: key = "<Particles>"
		elif n is Skeleton3D: key = "<Skeleton3D>"
		if key == "": continue
		if not by.has(key): by[key] = []
		by[key].append(n)
	for k in by: cands.append([k, by[k]])
	print("[bisect] %d groups" % cands.size())

func _set_on(group: Array, on_: bool) -> void:
	for n in group:
		if not is_instance_valid(n): continue
		if n is AnimationMixer: (n as AnimationMixer).active = on_
		elif n is CPUParticles3D or n is GPUParticles3D: n.process_mode = Node.PROCESS_MODE_INHERIT if on_ else Node.PROCESS_MODE_DISABLED
		elif n is Skeleton3D: n.process_mode = Node.PROCESS_MODE_INHERIT if on_ else Node.PROCESS_MODE_DISABLED
		else:
			if not on_:
				n.set_meta("pp", [n.is_processing(), n.is_physics_processing()])
				n.set_process(false); n.set_physics_process(false)
			else:
				var w: Array = n.get_meta("pp", [true, true]); n.set_process(w[0]); n.set_physics_process(w[1])

## script time of the last frame (process callbacks + physics callbacks), not the whole frame
func _ms() -> float:
	var v := (script_us + phys_us) / 1000.0
	phys_us = 0
	return v

var sub := 0          # 0 = measuring with the group on, 1 = with it off
var on_ms := 0.0
var win: Array = []
func _bisect(dt: float) -> void:
	t += dt; phase_t += dt
	if t < 5.0: return
	if cands.is_empty() and ci == -1:
		_collect(); ci = 0; sub = 0; phase_t = 0.0; samp = 0.0; samp_n = 0
		return
	if phase_t > 0.4: win.append(_ms())   # skip the switch-over frames
	if phase_t < 2.5: return
	win.sort()
	var avg: float = win[win.size() / 2] if not win.is_empty() else 0.0   # median: ignores the periodic spikes
	win.clear(); phase_t = 0.0
	var g: Array = cands[ci]
	if sub == 0:
		on_ms = avg; sub = 1; _set_on(g[1], false); return
	_set_on(g[1], true); sub = 0
	costs.append([on_ms - avg, g[0], g[1].size()])
	print("[bisect] %-40s x%-4d on %.1f ms  off %.1f ms  saves %.1f" % [g[0], g[1].size(), on_ms, avg, on_ms - avg])
	ci += 1
	if ci >= cands.size():
		costs.sort_custom(func(a, b): return a[0] > b[0])
		print("[bisect] TOP:")
		for k in mini(15, costs.size()): print("[bisect]   %.1f ms  %s (x%d)" % costs[k])
		get_tree().quit()
