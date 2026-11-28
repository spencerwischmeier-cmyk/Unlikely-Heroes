extends Node
## First-use hitches: the first spark burst, explosion, scrap burst, shockwave ring or telegraph of a run
## used to load files, build meshes and (on the web/phone renderer, which compiles shaders when something
## is first drawn) compile shaders in the middle of a fight. Shortly after the level loads this fires each
## effect once out of sight, then draws a tiny copy of every effect mesh/material for a few frames hidden
## inside Vesk's body (in view, so the renderer really draws and compiles them, but nothing shows).
## `--no-prewarm` turns it off; `--prewarm-log` prints what each effect cost the first and second time.

const ScrapBurst := preload("res://scripts/chars/scrap_burst.gd")
const CraneBot := preload("res://scripts/cranebot.gd")
const FAR := Vector3(0, -4000, 0)
const HOLD_FRAMES := 4

var log_on := false
var held: Array = []      # proxies drawn inside Vesk for a few frames
var frames := 0

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--no-prewarm"): set_process(false); return
	log_on = args.has("--prewarm-log")
	set_process(false)
	await get_tree().create_timer(0.6).timeout
	if Game.player == null or Game.level == null: return
	_run()

func _time(label: String, f: Callable) -> void:
	var t0 := Time.get_ticks_usec()
	f.call()
	var t1 := Time.get_ticks_usec()
	if log_on:
		f.call()
		print("[prewarm] %-14s first %6.2f ms, again %6.2f ms" % [label, (t1 - t0) / 1000.0, (Time.get_ticks_usec() - t1) / 1000.0])

func _run() -> void:
	var before := {}
	for c in FX.get_children(): before[c] = true
	var t0 := Time.get_ticks_usec()
	_time("sparks", func(): FX.sparks(FAR))
	_time("hit_sparks", func(): FX.hit_sparks(FAR, Vector3.FORWARD))
	_time("puff", func(): FX.puff(FAR))
	_time("dust", func(): FX.dust(FAR))
	_time("wisp", func(): FX.wisp(FAR))
	_time("smoke_trail", func(): FX.smoke_trail(FAR))
	_time("ring", func(): FX.ring(FAR, Color(1, 0.6, 0.3)))
	_time("warn_ring", func(): FX.warn_ring(FAR, 3.0, 0.5))
	_time("explosion", func(): FX.explosion(FAR, 0.3))
	_time("scrap_bits", func(): ScrapBurst._load_bits())
	_time("scrap_burst", func(): ScrapBurst.burst(FX, FAR, 0.5, [FX.load_chunk_mat()], 6))
	_time("quake_ring", func(): CraneBot.quake_ring_res())
	# draw a speck of every effect mesh + material, hidden inside Vesk's chest
	var seen := {}
	for c in FX.get_children():
		if before.has(c): continue
		_proxies(c, seen)
	var q: Array = CraneBot.quake_ring_res()
	_hold(q[0], q[1], false, seen)
	for k in ScrapBurst._meshes:
		var mm: Array = ScrapBurst._meshes[k]
		_hold(mm[0], mm[1], false, seen)
	if log_on: print("[prewarm] %d effects fired, %d specks drawn, %.1f ms" % [12, held.size(), (Time.get_ticks_usec() - t0) / 1000.0])
	frames = 0
	set_process(true)

func _proxies(n: Node, seen: Dictionary) -> void:
	if n is CPUParticles3D:
		var p := n as CPUParticles3D
		_hold(p.mesh, p.material_override, true, seen)
	elif n is MeshInstance3D:
		var mi := n as MeshInstance3D
		_hold(mi.mesh, mi.material_override if mi.material_override else mi.get_active_material(0), false, seen)
	for c in n.get_children(): _proxies(c, seen)

## A speck of `mesh` with `mat` (as a one-particle system when `particles`, which draws through the
## particle/instancing path) parked inside Vesk for HOLD_FRAMES frames.
func _hold(mesh: Mesh, mat: Material, particles: bool, seen: Dictionary) -> void:
	if mesh == null or mat == null: return
	var key := "%d|%d|%s" % [mesh.get_instance_id(), mat.get_instance_id(), particles]
	if seen.has(key): return
	seen[key] = true
	var n: GeometryInstance3D
	if particles:
		var p := CPUParticles3D.new(); p.mesh = mesh; p.amount = 1; p.lifetime = 1.0
		p.initial_velocity_min = 0.0; p.initial_velocity_max = 0.0; p.gravity = Vector3.ZERO
		p.scale_amount_min = 0.02; p.scale_amount_max = 0.02; p.local_coords = true; p.explosiveness = 1.0
		p.material_override = mat
		n = p
	else:
		var mi := MeshInstance3D.new(); mi.mesh = mesh; mi.material_override = mat; mi.scale = Vector3.ONE * 0.02
		n = mi
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.set_meta("_prewarm", true)
	Game.player.add_child(n)
	n.position = Vector3(0, 1.0, 0)
	held.append(n)

func _process(_dt: float) -> void:
	frames += 1
	if frames < HOLD_FRAMES: return
	for n in held: if is_instance_valid(n): n.queue_free()
	held.clear()
	set_process(false)
