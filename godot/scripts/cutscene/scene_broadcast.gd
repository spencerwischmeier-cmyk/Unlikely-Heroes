extends RefCounted
## BROADCAST: the relay dish locks on and the hidden signal resolves into a towering hologram of
## Foreman Grudd over the Signal Mast: his first message to Skyharbor. Dodger's eye flickers orange
## for the first time (and he says something in a voice that isn't his), Vesk goes quiet when asked
## if he knows the guy. Staged around the player's spot on the dish deck and the level's dish pivot.

const Props := preload("res://scripts/cutscene/props.gd")
var C: Node
var dish_glow: StandardMaterial3D
var dish_col := Color(0.3, 0.95, 1.0)

func run() -> void:
	var mast: Vector3 = C.spot("mast_top", Vector3(14, 20, -34))
	var dish := mast + Vector3(0, 1.5, -0.5)
	var dp = Game.level.get("dish_pivot") if Game.level else null
	if dp is Node3D: dish = (dp as Node3D).global_position
	dish_glow = Game.level.get("dish_glow") if Game.level else null
	if dish_glow: dish_col = dish_glow.emission
	var p: Vector3 = Game.player.global_position if Game.player else mast + Vector3(3, 0.1, 3)
	if p.distance_to(mast) > 12.0: p = mast + Vector3(3, 0.1, 3)
	var deck_y := p.y
	# Vesk stands where the player is, facing the dish; Dodger hovers off his shoulder
	var to_dish := Vector3(dish.x - p.x, 0, dish.z - p.z).normalized()
	if to_dish.length() < 0.1: to_dish = Vector3(0, 0, -1)
	var side := to_dish.cross(Vector3.UP).normalized()
	var stand := p - to_dish * 0.6
	var vesk: Node3D = C.make_vesk(stand, atan2(to_dish.x, to_dish.z))
	var dodger: Node3D = C.make_dodger(stand + side * 1.0 + Vector3(0, 1.75, 0) - to_dish * 0.3, atan2(to_dish.x, to_dish.z))
	# the hologram: Grudd, seven metres tall, above the dish, facing Vesk
	var holo_base := Vector3(mast.x, dish.y + 4.0, mast.z)
	var to_v := Vector3(stand.x - holo_base.x, 0, stand.z - holo_base.z)
	var grudd: Node3D = C.make_grudd(holo_base, atan2(to_v.x, to_v.z), 7.0, true)
	grudd.set_strength(0.0); grudd.glitch = 1.0
	grudd.look_target = vesk
	var beam: Node3D = C.actor(Props.holo_beam(holo_base.y - dish.y, 2.6), dish, 0.0)
	beam.scale = Vector3(1, 0.001, 1)
	var holo_eye := grudd.global_position + Vector3(0, 7.0 * 0.78, 0)

	# 1. the dish swings home and flares orange
	C.cut(stand + side * 2.5 + Vector3(0, 0.6, 0) - to_dish * 1.5, dish + Vector3(0, 0.6, 0), 42.0)
	C.move(stand + side * 3.2 + Vector3(0, 0.4, 0) - to_dish * 0.5, dish + Vector3(0, 1.2, 0), 3.0, 36.0)
	C.tw(C, "fade", 0.0, 0.6)
	vesk.look_target = null; vesk.look_point = dish
	dodger.look_target = null
	if dish_glow:
		dish_glow.emission = Color(1, 0.45, 0.1)
		C.tw(dish_glow, "emission_energy_multiplier", 12.0, 0.8)
	C.fx(func(): Snd.at("checkpoint", dish, -2); FX.ring(dish, Color(1, 0.5, 0.15), 3.0))
	await C.wait(1.2)
	await C.say("sky_shard_1", 0.2)
	# 2. the beam rises, the hologram stutters on. Wide: two tiny heroes, one enormous foreman
	C.fx(func(): Snd.play("cutscenes_holo_on", -2, 0.0); Snd.at("bot_spawn", holo_base, -6))
	C.tw(beam, "scale", Vector3.ONE, 0.8, 0.0, Tween.TRANS_EXPO, Tween.EASE_OUT)
	C.tw(grudd, "glitch", 0.08, 1.6, 0.4)
	C.tw(C, "white", 0.35, 0.08, 0.3); C.tw(C, "white", 0.0, 0.5, 0.4)
	for i in 4:
		C.tw(grudd, "holo_mat:shader_parameter/strength", 0.9 if i % 2 == 0 else 0.15, 0.08, 0.3 + i * 0.12)
	C.tw(grudd, "holo_mat:shader_parameter/strength", 1.0, 0.3, 0.8)
	var wide := stand - to_dish * 8.0 - side * 2.0 + Vector3(0, 0.9, 0)
	C.cut(wide, holo_base + Vector3(0, 1.6, 0), 58.0)
	C.move(wide - to_dish * 1.5 + Vector3(0, -0.5, 0), holo_base + Vector3(0, 2.2, 0), 7.0, 56.0)
	await C.wait(1.0)
	C.live_label.text = "●  LIVE BROADCAST  ·  ALL FREQUENCIES"
	C.tw(C, "live_a", 1.0, 0.3)
	vesk.look_point = Vector3.INF; vesk.look_target = grudd
	dodger.look_target = grudd
	dodger.act("shock")
	await C.say("cs_bc_dodger_1", 0.3)
	# 3. "Good morning, Skyharbor!" low hero angle, slow push in
	var low := stand + to_dish * 1.0 + side * 1.6 + Vector3(0, 0.3, 0)
	C.cut(low, holo_eye, 52.0)
	C.move(low + to_dish * 0.8, holo_eye, 9.0, 44.0)
	C.cast["grudd"] = grudd
	grudd.gesture("fist")
	await C.say("cs_bc_grudd_1", 0.3)
	grudd.gesture("clipboard")
	C.tw(dodger, "orange", 1.0, 0.8)
	await C.say("cs_bc_grudd_2", 0.3)
	# 4. reaction: Vesk, close and shallow, the hologram glowing behind him
	C.cut(vesk.global_position + to_dish * 1.3 + side * 0.4 + Vector3(0, 1.55, 0), vesk.global_position + Vector3(0, 1.45, 0), 34.0)
	C.focus(1.0)
	var l3: float = C.say_async("cs_bc_grudd_3")
	await C.wait(l3 * 0.55)
	# cut back up for the punchline
	C.focus(0.0)
	C.cut(stand - to_dish * 3.0 + side * 1.2 + Vector3(0, 0.4, 0), holo_eye + Vector3(0, -1.0, 0), 38.0)
	grudd.gesture("shrug")
	await C.wait(l3 * 0.45 + 0.3)
	# 5. TEAMWORK. Dutch angle on the giant face.
	C.cut(holo_base + Vector3(0, 4.2, 0) + Vector3(to_v.x, 0, to_v.z).normalized() * 7.0 + side * 2.0, holo_eye, 40.0)
	C.setv(C, "cam_roll", 0.14)
	C.move(holo_base + Vector3(0, 4.6, 0) + Vector3(to_v.x, 0, to_v.z).normalized() * 6.0 + side * 1.5, holo_eye, 6.0, 34.0)
	grudd.gesture("point")
	await C.say("cs_bc_grudd_4", 0.3)
	C.setv(C, "cam_roll", 0.0)
	# 6. sign-off, then the hologram breaks up
	C.cut(wide + Vector3(0, -0.6, 0) + to_dish * 1.0, holo_base + Vector3(0, 2.0, 0), 56.0)
	grudd.gesture("fist")
	await C.say("cs_bc_grudd_5", 0.2)
	C.fx(func(): Snd.play("cutscenes_holo_off", -3, 0.0))
	C.tw(grudd, "glitch", 1.0, 0.4)
	C.tw(grudd, "holo_mat:shader_parameter/strength", 0.0, 0.5, 0.3)
	C.tw(grudd, "scale", Vector3(1.0, 0.02, 1.0), 0.35, 0.5, Tween.TRANS_EXPO, Tween.EASE_IN)
	C.tw(beam, "scale", Vector3(1, 0.001, 1), 0.4, 0.6)
	C.tw(C, "live_a", 0.0, 0.5, 0.5)
	await C.wait(1.1)
	C.cast.erase("grudd")
	# 7. Dodger, still orange, speaks in someone else's voice
	var dpos: Vector3 = dodger.global_position
	C.cut(dpos + to_dish * 1.1 - side * 0.3 + Vector3(0, 0.05, 0), dpos, 30.0)
	C.focus(1.0)
	C.move(dpos + to_dish * 0.85 - side * 0.2, dpos, 5.0, 28.0)
	dodger.look_target = null
	C.tw(dodger, "tilt", Vector3(0.0, 0, 0), 0.3)
	await C.say("cs_bc_dodger_2", 0.2)
	C.tw(dodger, "orange", 0.0, 0.2)
	dodger.act("shake")
	await C.wait(0.4)
	# 8. "Your eye just went orange." two-shot, then singles
	C.cut(stand + side * 2.6 + to_dish * 1.6 + Vector3(0, 1.4, 0), stand + side * 0.5 + Vector3(0, 1.5, 0), 40.0)
	C.focus(0.4)
	vesk.look_target = dodger; dodger.look_target = vesk
	C.turn_to(vesk, dodger.global_position, 0.5)
	await C.say("sky_shard_3", 0.3)
	dodger.act("squint")
	await C.say("sky_shard_4", 0.3)
	# 9. "You know him?" ... a long look at where the hologram was.
	C.cut(dpos + to_dish * 1.0 + side * 0.4, dpos, 32.0)
	C.focus(1.0)
	await C.say("cs_bc_dodger_3", 0.6)
	C.cut(vesk.global_position + to_dish * 1.2 - side * 0.5 + Vector3(0, 1.55, 0), vesk.global_position + Vector3(0, 1.5, 0), 30.0)
	C.move(vesk.global_position + to_dish * 1.0 - side * 0.4 + Vector3(0, 1.55, 0), vesk.global_position + Vector3(0, 1.5, 0), 5.0, 27.0)
	C.auto_look = false
	vesk.look_target = null; vesk.look_point = holo_base + Vector3(0, 4, 0)
	await C.wait(0.9)
	await C.say("cs_bc_vesk_1", 0.8)
	C.auto_look = true
	# 10. back to business: the shard, and the rail to the Crane Yard
	C.cut(stand + side * 2.8 + to_dish * 2.0 + Vector3(0, 1.2, 0), stand + side * 0.5 + Vector3(0, 1.4, 0), 42.0)
	C.focus(0.3)
	vesk.look_point = Vector3.INF; vesk.look_target = dodger
	dodger.act("spin")
	await C.say("cs_bc_dodger_4", 0.3)
	vesk.gesture("cs_beckon", 0.3, "idle")
	await C.say("cs_bc_vesk_2", 0.6)
	if dish_glow: dish_glow.emission = dish_col; dish_glow.emission_energy_multiplier = 6.0
	vesk.look_target = null
	C.setv(vesk, "global_position", p)

func cleanup() -> void:
	if dish_glow: dish_glow.emission = dish_col; dish_glow.emission_energy_multiplier = 6.0
