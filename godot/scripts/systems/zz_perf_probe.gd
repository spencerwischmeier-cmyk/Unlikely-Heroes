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

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--perf-probe": on = true
		elif a.begins_with("--perf-probe="): on = true; secs = float(a.substr(13))
	set_process(on)

func _process(dt: float) -> void:
	t += dt; acc_t += dt; frames += 1
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
	}
	rows.append(r)
	print("[perf] t=%.0f fps %.0f proc %.1fms phys %.1fms draws %d objs %d prims %dk nodes %d bots %d at %s" % [t, r.fps, r.proc, r.phys, r.draws, r.objs, r.prims / 1000, r.nodes,
		get_tree().get_nodes_in_group("bots").size(), Game.player.global_position.snapped(Vector3.ONE) if Game.player else Vector3.ZERO])
	if t >= secs:
		var avg := func(k): return rows.reduce(func(a, x): return a + float(x[k]), 0.0) / rows.size()
		print("[perf] AVG fps %.1f min %.0f proc %.1fms phys %.1fms draws %.0f prims %.0fk" % [avg.call("fps"), rows.map(func(x): return x.fps).min(), avg.call("proc"), avg.call("phys"), avg.call("draws"), avg.call("prims") / 1000.0])
		get_tree().quit()
