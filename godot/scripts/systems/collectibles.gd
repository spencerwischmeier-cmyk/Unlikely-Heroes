extends Node
## Collectibles at Game.level.pickup_spots: Lucky Washers (spinning gold washers with a sparkle) and
## Pink Slip Pages. Walk into one to collect it (Game.collect(kind, id), saved). Also tracks the
## Gripe "Return to Sender": knock 10 Scrap Rollers back into other bots with the wrench.
## A toast on the HUD shows each find. Debug: --collect-test drops a washer in front of Vesk.

const GRIPE_GOAL := 10
const GRIPES := {
	"return_to_sender": { name = "RETURN TO SENDER", desc = "Wrench %d Scrap Rollers back into other bots" % GRIPE_GOAL },
}
const RADIUS := 1.3

var items: Array = []          # { node: Node3D, kind, id, pos, spin: Node3D, t }
var washer_mat: StandardMaterial3D
var page_mat: StandardMaterial3D

func _ready() -> void:
	washer_mat = StandardMaterial3D.new(); washer_mat.albedo_color = Color(1.0, 0.78, 0.25); washer_mat.metallic = 1.0
	washer_mat.roughness = 0.18; washer_mat.emission_enabled = true; washer_mat.emission = Color(1.0, 0.6, 0.12)
	washer_mat.emission_energy_multiplier = 1.4
	page_mat = StandardMaterial3D.new(); page_mat.albedo_color = Color(1.0, 0.62, 0.78); page_mat.roughness = 0.7
	page_mat.emission_enabled = true; page_mat.emission = Color(1.0, 0.4, 0.65); page_mat.emission_energy_multiplier = 1.2
	page_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	Game.bot_killed.connect(_on_bot_killed)
	_place.call_deferred()
	if OS.get_cmdline_user_args().has("--collect-test"):
		get_tree().create_timer(0.8).timeout.connect(func():
			var p: Node3D = Game.player
			var f := Vector3(sin(p.face_yaw), 0, cos(p.face_yaw))
			_spawn("washer", "test", p.global_position + f * 3.0 + Vector3(0, 1.0, 0)))

func _place() -> void:
	if Game.level == null: return
	var spots = Game.level.get("pickup_spots")
	if not (spots is Array): return
	for s in spots:
		if Game.is_collected(s.kind, s.id): continue
		_spawn(s.kind, s.id, s.pos)

func _spawn(kind: String, id: String, pos: Vector3) -> void:
	var root := Node3D.new(); root.name = "%s_%s" % [kind, id]
	Game.level.add_child(root); root.global_position = pos
	var spin := Node3D.new(); root.add_child(spin)
	var light := OmniLight3D.new(); light.omni_range = 3.5; light.light_energy = 1.6
	match kind:
		"washer":
			var tm := TorusMesh.new(); tm.inner_radius = 0.16; tm.outer_radius = 0.42; tm.rings = 32; tm.ring_segments = 12
			var mi := MeshInstance3D.new(); mi.mesh = tm; mi.material_override = washer_mat; mi.rotation.x = PI / 2
			mi.scale = Vector3(1, 0.45, 1)
			spin.add_child(mi)
			light.light_color = Color(1, 0.8, 0.35)
		"page":
			var q := QuadMesh.new(); q.size = Vector2(0.55, 0.75)
			var mi := MeshInstance3D.new(); mi.mesh = q; mi.material_override = page_mat
			spin.add_child(mi)
			# a few printed lines on the page
			var lm := M_lines()
			for k in 4:
				var lmi := MeshInstance3D.new(); var b := BoxMesh.new(); b.size = Vector3(0.38 - (0.12 if k == 3 else 0.0), 0.03, 0.005)
				lmi.mesh = b; lmi.material_override = lm; lmi.position = Vector3(-0.03 if k == 3 else 0.0, 0.2 - k * 0.12, 0.004)
				spin.add_child(lmi)
			light.light_color = Color(1, 0.45, 0.7)
	root.add_child(light)
	var sp := CPUParticles3D.new()
	var sq := QuadMesh.new(); sq.size = Vector2(0.08, 0.08); sp.mesh = sq
	var sm := StandardMaterial3D.new(); sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES; sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD; sm.vertex_color_use_as_albedo = true
	sm.albedo_color = Color(2.5, 2.0, 1.0) if kind == "washer" else Color(2.5, 1.2, 1.8)
	sp.material_override = sm
	sp.amount = 10; sp.lifetime = 1.1; sp.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE; sp.emission_sphere_radius = 0.5
	sp.direction = Vector3.UP; sp.spread = 180; sp.initial_velocity_min = 0.1; sp.initial_velocity_max = 0.5; sp.gravity = Vector3(0, 0.4, 0)
	var cr := Curve.new(); cr.add_point(Vector2(0, 0)); cr.add_point(Vector2(0.3, 1)); cr.add_point(Vector2(1, 0)); sp.scale_amount_curve = cr
	root.add_child(sp)
	items.append({ node = root, kind = kind, id = id, pos = pos, spin = spin, t = randf() * TAU })

func M_lines() -> StandardMaterial3D:
	var m := StandardMaterial3D.new(); m.albedo_color = Color(0.5, 0.15, 0.3); m.roughness = 0.9
	return m

func _process(dt: float) -> void:
	var p: Node3D = Game.player
	for i in range(items.size() - 1, -1, -1):
		var it: Dictionary = items[i]
		if not is_instance_valid(it.node): items.remove_at(i); continue
		it.t += dt
		var spin: Node3D = it.spin
		spin.rotation.y += dt * (2.6 if it.kind == "washer" else 1.2)
		spin.position.y = sin(it.t * 2.0) * 0.12
		if it.kind == "page": spin.rotation.z = sin(it.t * 1.3) * 0.2
		if p and not Game.input_locked and (p.global_position + Vector3(0, 0.8, 0)).distance_to(it.node.global_position) < RADIUS:
			_pickup(it)
			items.remove_at(i)

func _pickup(it: Dictionary) -> void:
	var pos: Vector3 = it.node.global_position
	it.node.queue_free()
	FX.sparks(pos, Color(1, 0.85, 0.4) if it.kind == "washer" else Color(1, 0.5, 0.75), 24, 5.0)
	FX.ring(pos, Color(1, 0.8, 0.3) if it.kind == "washer" else Color(1, 0.45, 0.7), 0.6)
	Snd.play("washer_pickup" if it.kind == "washer" else "page_pickup", -2, 0.0, 0.0)
	Snd.bark("dodger", "washer" if it.kind == "washer" else "page", 1.0)
	if it.id != "test": Game.collect(it.kind, it.id)
	_toast_for(it.kind)

## Drops pickups that are already collected (after a save is loaded).
func refresh() -> void:
	for i in range(items.size() - 1, -1, -1):
		var it: Dictionary = items[i]
		if Game.is_collected(it.kind, it.id):
			if is_instance_valid(it.node): it.node.queue_free()
			items.remove_at(i)

func _count(kind: String) -> Vector2i:
	var total := 0
	var found := 0
	var spots = Game.level.get("pickup_spots") if Game.level else null
	if spots is Array:
		for s in spots:
			if s.kind != kind: continue
			total += 1
			if Game.is_collected(kind, s.id): found += 1
	return Vector2i(found, total)

func _toast_for(kind: String) -> void:
	if Game.hud == null or not Game.hud.has_method("toast"): return
	var c := _count(kind)
	match kind:
		"washer": Game.hud.toast("LUCKY WASHER  %d/%d" % [c.x, c.y], "Lucky! Trade washers for cosmetics and cheats.", Color(1, 0.82, 0.3))
		"page": Game.hud.toast("PINK SLIP PAGE", "A page of something big. Collect them all.", Color(1, 0.5, 0.75))
		_: Game.hud.toast(kind.to_upper(), "", Color.WHITE)

# ---------------------------------------------------------------- gripe: Return to Sender
func gripe_count(id: String) -> int:
	var g = Game.data.get("gripes", {})
	return int(g.get(id, 0)) if g is Dictionary else 0

func _on_bot_killed(bot: Node, _pos: Vector3, kind: String) -> void:
	if not (kind in ["roller", "crew_roller"]): return
	if bot == null or not bot.get_meta("returned_to_sender", false): return
	var id := "return_to_sender"
	if Game.is_collected("gripe", id): return
	var g = Game.data.get("gripes", {})
	if not (g is Dictionary): g = {}
	var n := int(g.get(id, 0)) + 1
	g[id] = n; Game.data["gripes"] = g
	if n >= GRIPE_GOAL:
		Game.collect("gripe", id)
		if Game.hud and Game.hud.has_method("toast"):
			Game.hud.toast("GRIPE: %s" % GRIPES[id].name, "Complete! %d rollers returned, no postage paid." % GRIPE_GOAL, Color(0.6, 1, 0.5), 5.0)
		Snd.play("checkpoint", -2, 0.0, 0.0)
	elif Game.hud and Game.hud.has_method("toast_small"):
		Game.hud.toast_small("RETURN TO SENDER  %d/%d" % [n, GRIPE_GOAL], Color(0.6, 1, 0.5))
