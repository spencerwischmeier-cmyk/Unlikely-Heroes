extends CharacterBody3D
## Shared bot behaviour: health, a white hit flash, a squash "pop", a lean away from the hit, knockback,
## a short stagger, and a death burst with sprockets when destroyed.
## Subclasses override _death_fx() for a custom death (the hornet falls in flames first) and may
## override center(), knock() and damage().
##
## Dying: die() marks the bot dead at once (the story counts it), takes it out of the "targets" and
## "bots" groups, drops sprockets and emits `died` and Game.bot_killed, then plays _death_fx().

signal died(bot)

const ScrapBurst := preload("res://scripts/chars/scrap_burst.gd")

var combat: Node3D
var player: CharacterBody3D
var hp := 2.0
var max_hp := 2.0
var nuts := 4
var dead := false
var flash := 0.0
var pop := 0.0
var stun := 0.0
var t := 0.0
var zone: Rect2 = Rect2()
var model: Node3D
var flash_mats: Array = []
var chunk_mats: Array = []
var lean := Vector3.ZERO          # hit lean (model rotation, eases back to zero)
var stagger_time := 0.22          # how long a hit stops the bot's steering
var burst_color := Color(1, 0.55, 0.2)
var burst_scale := 1.0
var eyes: Array = []              # glowing eye overlays: { node, mat, color, energy } (blink, flare, flash)
var eye_open := 1.0               # 0..1, squashes the eyes shut (blinks, waking up)
var blink_t := 2.0
var break_parts: Array = []       # model nodes ripped off and thrown when the bot breaks apart
var scrap_count := 9
var lean_v := Vector3.ZERO        # the lean is a spring: it overshoots and wobbles back after a hit
var model_scale := 1.0            # base size of the model (variants are a little bigger or smaller)
var variant := 0                  # 0 = standard paint, 1 = second paint job + accessory (set by apply_variant)
var cable: Node3D                 # drop-in hook and cable while the bot is lowered in
var cable_on := false             # subclasses set this in _ready to arrive on a crane cable
var ticks := 0

## True for roughly `chance` of spawns. Previews force it with Engine meta "bot_variant" (0 or 1).
func roll_variant(chance := 0.4) -> bool:
	if Engine.has_meta("bot_variant"): return int(Engine.get_meta("bot_variant")) == 1
	return randf() < chance

func _init() -> void:
	collision_layer = 4
	collision_mask = 1
	add_to_group("targets")
	add_to_group("bots")

func setup_model(path: String) -> void:
	model = load(path).instantiate()
	add_child(model)
	_collect(model)

func _collect(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for s in mi.mesh.get_surface_count():
			var m := mi.get_active_material(s)
			if m is StandardMaterial3D and not (m as StandardMaterial3D).emission_enabled:
				var c := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
				c.emission_enabled = true; c.emission = Color.WHITE; c.emission_energy_multiplier = 0.0
				mi.set_surface_override_material(s, c)
				flash_mats.append(c)
				if chunk_mats.size() < 3: chunk_mats.append(m)
	for c in n.get_children(): _collect(c)

## A glowing eye overlay (a flattened emissive sphere facing +Z) on `parent` at `pos`. Blinks and flashes
## with the bot; returns its material so subclasses can flare it as a telegraph.
func add_eye(parent: Node3D, pos: Vector3, r: float, color: Color, energy := 4.0, flat := 0.45) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color * 0.3; m.emission_enabled = true; m.emission = color; m.emission_energy_multiplier = energy
	m.roughness = 0.2
	var sm := SphereMesh.new(); sm.radius = r; sm.height = r * 2.0; sm.radial_segments = 16; sm.rings = 8
	var mi := MeshInstance3D.new(); mi.mesh = sm; mi.material_override = m; mi.position = pos
	mi.scale = Vector3(1, 1, flat); mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	eyes.append({ node = mi, mat = m, color = color, energy = energy })
	blink_t = randf_range(1.0, 4.0)
	return m

func center() -> Vector3:
	return global_position + Vector3(0, 0.55, 0)

## The kind name reported in Game.bot_killed: "roller", "hornet", "crew_roller"...
func kind() -> String:
	return get_script().resource_path.get_file().get_basename().trim_prefix("enemy_")

## returns true if this hit destroyed the bot
func damage(amount: float, point: Vector3, dir: Vector3) -> bool:
	if dead: return false
	hp -= amount; flash = 1.0; pop = 1.0
	var push := dir; push.y = 0
	if push.length() < 0.01: push = (global_position - point); push.y = 0
	push = push.normalized()
	knock(push * minf(2.5, 0.8 + amount * 0.6))
	# lean away from the hit: rotate about the axis perpendicular to the push
	lean = Vector3(push.z, 0, -push.x) * minf(0.6, 0.25 + amount * 0.12)
	lean_v = lean * 6.0
	FX.hit_sparks(point, dir if dir.length() > 0.01 else -push, burst_color.lerp(Color.WHITE, 0.4), 6 + int(amount * 3))
	if hp <= 0.0:
		die()
		return true
	return false

func knock(v: Vector3) -> void:
	velocity += v * 2.6
	stun = maxf(stun, stagger_time)

func die(self_destruct := false) -> void:
	if dead: return
	dead = true
	remove_from_group("targets"); remove_from_group("bots")
	collision_layer = 0
	if cable: _cable_release()
	var c := center()
	if not self_destruct and combat:
		combat.drop_nuts(c, nuts)
		if randf() < 0.15: combat.drop_cell(c + Vector3(0, 0.3, 0))
	died.emit(self)
	Game.bot_killed.emit(self, c, kind())
	_death_fx(self_destruct)

## Default death: burst on the spot and vanish. Override for a custom death.
func _death_fx(_self_destruct: bool) -> void:
	_burst()
	queue_free()

func _burst() -> void:
	var c := center()
	FX.death_burst(c, burst_scale, chunk_mats, burst_color)
	# break apart: the head pops off, bolts, sprockets and panels fly
	var parts := break_parts.filter(func(n): return is_instance_valid(n))
	for e in eyes: if is_instance_valid(e.node): (e.mat as StandardMaterial3D).emission_energy_multiplier = 0.4
	ScrapBurst.burst(get_parent(), c, burst_scale, chunk_mats, scrap_count, parts, true)
	Snd.at("chars_bot_break", c, -3, 0.12, 0.05)
	FX.shake(0.6 * burst_scale)
	Snd.at("explode_small", c, 0.0)
	FX.stop(0.045)

func tick_common(dt: float) -> void:
	t += dt
	ticks += 1
	if ticks == 1 and cable_on and not is_on_floor(): _cable_attach()
	if cable and is_on_floor(): _cable_release()
	_cable_tick()
	flash = maxf(0.0, flash - dt * 8.0)
	pop = maxf(0.0, pop - dt * 7.0)
	stun = maxf(0.0, stun - dt)
	# springy lean: a hit knocks the bot back and it wobbles upright again (overshoots once or twice)
	lean_v += (-lean * 170.0 - lean_v * 11.0) * dt
	lean += lean_v * dt
	for m in flash_mats: m.emission_energy_multiplier = flash * 2.0
	if model:
		model.scale = Vector3(1.0 + pop * 0.28, 1.0 - pop * 0.18, 1.0 + pop * 0.28) * model_scale
		model.rotation = lean
	_tick_eyes(dt)

## Eyes: blink now and then, squint shut while staggered, flash white when hit.
func _tick_eyes(dt: float) -> void:
	if eyes.is_empty(): return
	blink_t -= dt
	var open := eye_open
	if blink_t < 0.12: open *= absf(blink_t - 0.06) / 0.06
	if blink_t <= 0.0: blink_t = randf_range(1.8, 4.5)
	if stun > 0.0: open *= 0.25
	for e in eyes:
		var n: MeshInstance3D = e.node
		if not is_instance_valid(n): continue
		n.scale.y = maxf(0.08, open)
		var m: StandardMaterial3D = e.mat
		m.emission = (e.color as Color).lerp(Color.WHITE, flash)

## Second paint job: tints every livery material (Grudd Works runs two crews: the mustard regulars and
## the rust-orange night shift) and scales the model. Accessories are added by the subclass.
func apply_variant(tint: Color, size := 1.0) -> void:
	variant = 1; model_scale = size
	for m in flash_mats: (m as StandardMaterial3D).albedo_color = (m as StandardMaterial3D).albedo_color * tint
	var tinted: Array = []
	for m in chunk_mats:
		var c := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
		c.albedo_color = c.albedo_color * tint; tinted.append(c)
	chunk_mats = tinted

## A small accessory (antenna, toolbox...) on `parent`, in a plain material that flashes with the bot.
func add_prop(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3, rot := Vector3.ZERO, metal := 0.4, glow := 0.0) -> MeshInstance3D:
	var m := StandardMaterial3D.new(); m.albedo_color = color; m.metallic = metal; m.roughness = 0.45
	m.emission_enabled = true; m.emission = Color.WHITE if glow <= 0.0 else color; m.emission_energy_multiplier = glow
	if glow <= 0.0: flash_mats.append(m)
	var mi := MeshInstance3D.new(); mi.mesh = mesh; mi.material_override = m; mi.position = pos; mi.rotation = rot
	parent.add_child(mi)
	return mi

static func cyl(r: float, h: float, r2 := -1.0) -> CylinderMesh:
	var c := CylinderMesh.new(); c.top_radius = r; c.bottom_radius = r if r2 < 0.0 else r2; c.height = h; c.radial_segments = 10
	return c

static func ball_mesh(r: float) -> SphereMesh:
	var sm := SphereMesh.new(); sm.radius = r; sm.height = r * 2.0; sm.radial_segments = 12; sm.rings = 6
	return sm

static func box(sz: Vector3) -> BoxMesh:
	var b := BoxMesh.new(); b.size = sz
	return b

## Drop-in on a crane cable: a livery hook block on a long cable rides down with the bot, lets go when
## it lands and reels back up into the sky. Purely visual.
func _cable_attach() -> void:
	var top := center().y - global_position.y + 0.75
	cable = Node3D.new(); cable.name = "DropCable"; cable.top_level = true
	add_child(cable); cable.global_position = global_position + Vector3(0, top, 0)
	var steel := StandardMaterial3D.new(); steel.albedo_color = Color(0.22, 0.23, 0.25); steel.metallic = 0.8; steel.roughness = 0.4
	var yellow := StandardMaterial3D.new(); yellow.albedo_color = Color(0.85, 0.6, 0.13); yellow.metallic = 0.3; yellow.roughness = 0.5
	var black := StandardMaterial3D.new(); black.albedo_color = Color(0.08, 0.08, 0.09); black.roughness = 0.6
	var line := CylinderMesh.new(); line.top_radius = 0.025; line.bottom_radius = 0.025; line.height = 30.0; line.radial_segments = 6
	_cable_part(line, steel, Vector3(0, 15.55, 0), Vector3.ZERO)
	var blk := BoxMesh.new(); blk.size = Vector3(0.36, 0.3, 0.2)
	_cable_part(blk, yellow, Vector3(0, 0.45, 0), Vector3.ZERO)
	var stripe := BoxMesh.new(); stripe.size = Vector3(0.37, 0.07, 0.21)
	_cable_part(stripe, black, Vector3(0, 0.45, 0), Vector3.ZERO)
	var hook := TorusMesh.new(); hook.inner_radius = 0.09; hook.outer_radius = 0.14; hook.rings = 16; hook.ring_segments = 8
	_cable_part(hook, steel, Vector3(0, 0.17, 0), Vector3(0, 0, PI / 2))

func _cable_part(mesh: Mesh, m: Material, at: Vector3, rot: Vector3) -> void:
	var mi := MeshInstance3D.new(); mi.mesh = mesh; mi.material_override = m; mi.position = at; mi.rotation = rot
	cable.add_child(mi)

func _cable_tick() -> void:
	if cable and is_instance_valid(cable) and not cable.has_meta("free"):
		var top := center().y - global_position.y + 0.75
		cable.global_position = global_position + Vector3(0, top, 0)
		cable.rotation.z = sin(t * 5.0) * 0.04

func _cable_release() -> void:
	var c := cable; cable = null
	if not is_instance_valid(c): return
	c.set_meta("free", true)
	var gp := c.global_position
	if get_parent(): c.reparent(get_parent()); c.top_level = false; c.global_position = gp
	Snd.at("chars_roller_hop", c.global_position, -14, 0.1, 0.25)
	var tw := c.create_tween().set_parallel(true)
	tw.tween_property(c, "global_position:y", c.global_position.y + 0.35, 0.12)
	tw.tween_property(c, "rotation:z", 0.25, 0.3)
	tw.chain().tween_property(c, "global_position:y", c.global_position.y + 26.0, 0.9).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.chain().tween_callback(c.queue_free)

## Keep a ground bot inside its zone rect.
func clamp_to_zone() -> void:
	if zone.size.x > 0.0:
		global_position.x = clampf(global_position.x, zone.position.x + 0.6, zone.end.x - 0.6)
		global_position.z = clampf(global_position.z, zone.position.y + 0.6, zone.end.y - 0.6)

## Input lock (cutscenes, menus): bots hold still.
func paused() -> bool:
	return Game.input_locked or player == null
