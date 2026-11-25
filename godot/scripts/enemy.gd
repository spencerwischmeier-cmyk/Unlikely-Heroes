extends CharacterBody3D
## Shared bot behaviour: health, white hit flash, knockback, a little pop when hit and a big
## scrap explosion with hex nuts when destroyed.

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

## returns true if this hit destroyed the bot
func damage(amount: float, point: Vector3, dir: Vector3) -> bool:
	if dead: return false
	hp -= amount; flash = 1.0; pop = 1.0
	var push := dir; push.y = 0
	if push.length() < 0.01: push = (global_position - point); push.y = 0
	knock(push.normalized() * minf(2.5, 0.8 + amount * 0.6))
	if hp <= 0.0:
		die()
		return true
	return false

func knock(v: Vector3) -> void:
	velocity += v * 2.6
	stun = 0.18

func die(self_destruct := false) -> void:
	if dead: return
	dead = true
	var c := center()
	FX.explosion(c, 1.0, chunk_mats)
	FX.shake(0.6)
	Snd.at("explode_small", c, 0.0)
	FX.stop(0.045)
	if not self_destruct and combat:
		combat.drop_nuts(c, nuts)
		if randf() < 0.15: combat.drop_cell(c + Vector3(0, 0.3, 0))
	died.emit(self)
	Game.bot_killed.emit(self, c, get_script().resource_path.get_file().get_basename().trim_prefix("enemy_"))
	queue_free()

func tick_common(dt: float) -> void:
	t += dt
	flash = maxf(0.0, flash - dt * 8.0)
	pop = maxf(0.0, pop - dt * 7.0)
	stun = maxf(0.0, stun - dt)
	for m in flash_mats: m.emission_energy_multiplier = flash * 2.0
	if model: model.scale = Vector3.ONE * (1.0 + pop * 0.22)
