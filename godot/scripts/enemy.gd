extends CharacterBody3D
## Shared bot behaviour: health, a white hit flash, a squash "pop", a lean away from the hit, knockback,
## a short stagger, and a death burst with sprockets when destroyed.
## Subclasses override _death_fx() for a custom death (the hornet falls in flames first) and may
## override center(), knock() and damage().
##
## Dying: die() marks the bot dead at once (the story counts it), takes it out of the "targets" and
## "bots" groups, drops sprockets and emits `died` and Game.bot_killed, then plays _death_fx().

signal died(bot)

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

## Keep a ground bot inside its zone rect.
func clamp_to_zone() -> void:
	if zone.size.x > 0.0:
		global_position.x = clampf(global_position.x, zone.position.x + 0.6, zone.end.x - 0.6)
		global_position.z = clampf(global_position.z, zone.position.y + 0.6, zone.end.y - 0.6)

## Input lock (cutscenes, menus): bots hold still.
func paused() -> bool:
	return Game.input_locked or player == null
