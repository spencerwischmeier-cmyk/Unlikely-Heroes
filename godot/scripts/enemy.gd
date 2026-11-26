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
	ScrapBurst.burst(get_parent(), c, burst_scale, chunk_mats, scrap_count, parts)
	FX.shake(0.6 * burst_scale)
	Snd.at("explode_small", c, 0.0)
	FX.stop(0.045)

func tick_common(dt: float) -> void:
	t += dt
	flash = maxf(0.0, flash - dt * 8.0)
	pop = maxf(0.0, pop - dt * 7.0)
	stun = maxf(0.0, stun - dt)
	lean = lean.lerp(Vector3.ZERO, 1.0 - exp(-9.0 * dt))
	for m in flash_mats: m.emission_energy_multiplier = flash * 2.0
	if model:
		model.scale = Vector3(1.0 + pop * 0.28, 1.0 - pop * 0.18, 1.0 + pop * 0.28)
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

## Keep a ground bot inside its zone rect.
func clamp_to_zone() -> void:
	if zone.size.x > 0.0:
		global_position.x = clampf(global_position.x, zone.position.x + 0.6, zone.end.x - 0.6)
		global_position.z = clampf(global_position.z, zone.position.y + 0.6, zone.end.y - 0.6)

## Input lock (cutscenes, menus): bots hold still.
func paused() -> bool:
	return Game.input_locked or player == null
