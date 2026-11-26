extends RefCounted
## INTRO: "Clocking In". The sky city from far out, the docks waking up, out to the junkyard where
## Vesk enjoys his coffee and ignores customers. 7:59:57... 8:00:00: a distant voice says "clock in",
## the coffee maker punches a time card, bots all over town put on hard hats and go haywire, a roller
## eats Vesk's chair, and Dodger zooms off to find the signal and crashes on the scrap pile (where the
## level picks him up). Anchors: porch chair, workbench gear, Dodger crash spot, mast top, start_pos,
## and the plaza / pier_a island rects.

const Props := preload("res://scripts/cutscene/props.gd")
var C: Node

func run() -> void:
	var chair_pos: Vector3 = C.spot("porch_chair_pos", Vector3(-2.5, 0.4, 93.5))
	var porch_y := 0.4
	var bench: Vector3 = C.spot("gear_pos", Vector3(3.6, 1.45, 94))
	var crash: Vector3 = C.spot("dodger_crash_pos", Vector3(-12.5, 2.4, 74.5))
	var mast: Vector3 = C.spot("mast_top", Vector3(14, 20, -34))
	var start: Vector3 = Game.level.start_pos if Game.level else Vector3(0, 0.5, 91)
	var plaza: Vector3 = C.island_center("plaza", Vector3(0, 0, 30))
	var pier: Vector3 = C.island_center("pier_a", Vector3(38, 0, 26))
	var chair: Node3D = Game.level.find_child("porch_chair", false, false) if Game.level else null
	if chair: chair_pos = chair.global_position
	var bench_top := bench.y - 0.05
	# actors: seated with the real chair clip when it exists, else the procedural fold
	var vesk: Node3D = C.make_vesk(chair_pos, PI)
	var sit_off := Vector3(0, 0.52, 0.12) if vesk.can_sit() else Vector3(0, 0.27, 0.06)
	vesk.global_position = chair_pos + sit_off
	if vesk.can_sit():
		vesk.play("cs_sit_drink", 0.0)
	else:
		vesk.sit = 1.0; vesk.slump = 1.0
	vesk.hold_mug(true)
	var dodger: Node3D = C.make_dodger(Vector3(-30, 9, 70), PI * 0.5)
	var coffee: Node3D = C.actor(Props.coffee_maker(), Vector3(bench.x + 0.95, bench_top, bench.z + 0.05), PI + 0.25, true)
	var toaster: Node3D = C.actor(Props.toaster(), Vector3(bench.x - 0.75, bench_top, bench.z + 0.1), PI - 0.2, true)
	var roller: Node3D = C.actor(C.model("res://models/roller.glb"), Vector3(-14, 0.0, 86), 0.0)
	var roller2: Node3D = C.actor(C.model("res://models/roller.glb"), Vector3(15, 0.0, 76), 0.0)
	var hornet: Node3D = C.actor(C.model("res://models/hornet.glb"), Vector3(-30, 7, 80), PI * 0.5)
	# town bots for the montage: a dock worker and a mail hornet, hats ready to pop on
	var dock_bot: Node3D = C.actor(C.model("res://models/roller.glb"), pier + Vector3(-3, 0, 2), 1.2)
	var mail_bot: Node3D = C.actor(C.model("res://models/hornet.glb"), plaza + Vector3(4, 3.2, 6), -0.6)
	var hats := []
	for b in [dock_bot, mail_bot, roller]:
		var h: Node3D = Props.hard_hat(0.28 if b != mail_bot else 0.22)
		h.position = Vector3(0, 1.05 if b != mail_bot else 0.55, 0); h.scale = Vector3.ONE * 0.001
		b.add_child(h); hats.append(h)

	# 1. the sky city, from far out
	Snd.loop("wind_loop", true, -12)
	C.cut(Vector3(34, 46, 175), Vector3(4, 4, 30), 48.0)
	C.move(Vector3(22, 30, 138), Vector3(0, 2, 40), 15.0, 44.0)
	C.tw(C, "fade", 0.0, 3.0)
	C.show_location("SKYHARBOR", "Planet 1  ·  The sky city  ·  Golden hour", 5.0)
	await C.wait(2.6)
	await C.say("intro_01", 0.6)
	# 2. low over the docks: airship moorings, cranes, a bot hauling crates (still a nice bot, for now)
	C.cut(pier + Vector3(-22, 7, 18), pier + Vector3(0, 1.5, 0), 46.0)
	C.move(pier + Vector3(-6, 4.5, 16), pier + Vector3(4, 1.0, -2), 9.0, 42.0)
	C.tw(dock_bot, "global_position", pier + Vector3(5, 0, 1), 9.0, 0.0, Tween.TRANS_LINEAR)
	await C.say("cs_intro_city", 0.6)
	# 3. over the gardens and out to the junkyard
	C.cut(Vector3(-66, 24, 34), Vector3(-10, 3, 44), 50.0)
	C.move(Vector3(-30, 12, 70), Vector3(-2, 1.5, 86), 9.5)
	await C.say("intro_02", 1.0)
	# 4. the porch: start on the brass gear on the workbench (shallow focus), drift over to Vesk
	C.cut(bench + Vector3(-0.35, 0.3, -1.1), bench + Vector3(0, 0.02, 0), 34.0)
	C.focus(1.0)
	C.sway = 0.5
	C.move(chair_pos + Vector3(1.6, 1.15, -3.4), chair_pos + Vector3(0, 0.85, 0), 8.0, 40.0)
	C.tw(C, "dof", 0.35, 3.0, 2.0)
	await C.wait(1.4)
	await C.say("intro_03", 1.4)
	# 5. "Finally. Nothing left to fix." A long sip.
	C.cut(chair_pos + Vector3(0.55, 1.0, -1.55), chair_pos + Vector3(0, 0.95, 0.1), 38.0)
	C.focus(0.8)
	C.move(chair_pos + Vector3(0.45, 1.0, -1.3), chair_pos + Vector3(0, 0.95, 0.1), 9.0)
	vesk.look_point = chair_pos + Vector3(3, 1.6, -8)
	await C.say("intro_04", 0.8)
	await C.say("cs_intro_sip", 1.0)
	# 6. Dodger swoops in from the yard
	C.cut(chair_pos + Vector3(3.2, 1.4, -4.6), chair_pos + Vector3(0.8, 0.9, 0), 46.0)
	C.focus(0.0)
	C.setv(dodger, "global_position", chair_pos + Vector3(-9, 5, -14))
	C.tw(dodger, "global_position", chair_pos + Vector3(4, 3.0, -6), 1.2, 0.0, Tween.TRANS_SINE, Tween.EASE_OUT)
	C.tw(dodger, "global_position", chair_pos + Vector3(1.25, 1.55, -0.3), 1.1, 1.2, Tween.TRANS_BACK, Tween.EASE_OUT)
	C.tw(dodger, "rotation:y", PI + 0.6, 0.8, 1.2)
	C.fx(func(): Snd.at("dash", dodger.global_position, -6))
	await C.wait(2.4)
	dodger.look_target = vesk
	dodger.emote("spin")
	await C.say("intro_05", 0.5)
	# 7. "Dodger. It's my day off." (he doesn't even look)
	C.cut(chair_pos + Vector3(-0.6, 1.05, -1.6), chair_pos + Vector3(0.3, 1.0, 0), 40.0)
	C.focus(0.8)
	C.auto_look = false
	vesk.look_point = chair_pos + Vector3(2, 1.4, -8)
	await C.say("intro_06", 1.2)
	# 8. the customer at the gate
	C.cut(chair_pos + Vector3(2.6, 1.7, -2.6), chair_pos + Vector3(0.6, 1.2, 0), 44.0)
	C.move(chair_pos + Vector3(2.2, 1.6, -2.2), chair_pos + Vector3(0.6, 1.2, 0), 10.0)
	C.focus(0.5)
	dodger.emote("hop")
	await C.say("cs_intro_gate_1", 0.3)
	await C.say("cs_intro_gate_2", 0.3)
	dodger.emote("squint")
	await C.say("cs_intro_gate_3", 0.3)
	await C.say("cs_intro_gate_4", 1.2)
	C.auto_look = true
	# 9. 7:59:57 ... 8:00:00, the relay dish on the Signal Mast pulses, a voice on the wind
	C.cut(chair_pos + Vector3(2.4, 1.3, -3.6), chair_pos + Vector3(0.5, 0.9, 0), 46.0)
	C.focus(0.0)
	C.clock_label.text = "SKYHARBOR   7:59:57 AM"
	C.tw(C, "clock_a", 1.0, 0.6)
	for s in ["58", "59"]:
		await C.wait(1.0)
		C.clock_label.text = "SKYHARBOR   7:59:%s AM" % s
	await C.wait(1.0)
	C.clock_label.text = "SKYHARBOR   8:00:00 AM"
	C.fx(func(): Snd.play("crane_warn", -6); Snd.play("checkpoint", -4))
	C.cut(Vector3(-3, 3.2, 73), mast + Vector3(0, 0.5, 0), 16.0)
	C.move(Vector3(-2.6, 3.4, 72), mast + Vector3(0, 1.2, 0), 7.0, 11.0)
	C.tw(C, "clock_a", 0.0, 1.0, 1.2)
	for i in 4:
		C.fx(func(): FX.ring(mast + Vector3(0, 1.5, 0), Color(1, 0.5, 0.15), 3.0 + i))
		await C.wait(0.5)
	var cl: float = C.say_async("cs_intro_clock")
	await C.wait(cl + 0.4)
	vesk.look_point = mast
	dodger.look_target = null
	C.tw(dodger, "rotation:y", C.face_to(dodger, mast), 0.6)
	await C.say("intro_07", 0.6)
	# 10. the coffee maker clocks in
	var cm_eye: StandardMaterial3D = coffee.get_meta("eye")
	var card: Node3D = coffee.find_child("Card", true, false)
	var stamp: Node3D = coffee.find_child("Stamp", true, false)
	var hat: Node3D = coffee.find_child("Hat", true, false)
	var cpos := coffee.global_position
	C.cut(cpos + Vector3(-0.55, 0.42, -0.95), cpos + Vector3(0, 0.25, 0), 34.0)
	C.focus(1.0)
	await C.wait(0.8)
	cm_eye.emission = Color(1, 0.3, 0.1)
	C.fx(func(): Snd.at("ui_select", cpos, -4))
	C.tw(card, "position:y", 0.52, 0.25, 0.0, Tween.TRANS_BACK, Tween.EASE_OUT)
	await C.wait(0.6)
	C.tw(stamp, "position:y", 0.39, 0.08, 0.0, Tween.TRANS_EXPO, Tween.EASE_IN)
	await C.wait(0.1)
	C.fx(func(): Snd.at("melee_hit", cpos, -6); FX.sparks(cpos + Vector3(0, 0.45, 0), Color(1, 0.8, 0.4), 6, 2.0))
	C.tw(stamp, "position:y", 0.46, 0.2, 0.05)
	C.tw(card, "position:y", 0.33, 0.3, 0.4)
	await C.wait(0.5)
	C.tw(hat, "scale", Vector3.ONE, 0.3, 0.0, Tween.TRANS_BACK, Tween.EASE_OUT)
	C.tw(hat, "position:y", 0.45, 0.3, 0.0, Tween.TRANS_BACK, Tween.EASE_OUT)
	C.fx(func(): Snd.at("cell_pickup", cpos, -8))
	await C.wait(0.6)
	vesk.look_target = coffee; dodger.look_target = coffee
	dodger.emote("shock")
	await C.say("sky_intro_coffee_1", 0.3)
	C.cut(chair_pos + Vector3(0.5, 1.05, -1.45), chair_pos + Vector3(0, 1.0, 0.1), 38.0)
	C.focus(0.8)
	await C.say("sky_intro_coffee_2", 0.4)
	C.cut(cpos + Vector3(-0.35, 0.32, -0.6), cpos + Vector3(0, 0.38, 0), 30.0)
	C.focus(1.0)
	await C.say("sky_intro_coffee_3", 0.6)
	# 11. the toaster growls
	var tpos := toaster.global_position
	var t_eye: StandardMaterial3D = toaster.get_meta("eye")
	C.cut(tpos + Vector3(0.5, 0.35, -0.8), tpos + Vector3(0, 0.12, 0), 34.0)
	C.tw(t_eye, "emission_energy_multiplier", 4.0, 0.5)
	for i in 6:
		C.tw(toaster, "rotation:z", 0.08 if i % 2 == 0 else -0.08, 0.08)
		await C.wait(0.1)
	C.setv(toaster, "rotation:z", 0.0)
	C.fx(func(): Snd.at("roller_fuse", tpos, -8))
	await C.say("intro_08", 0.4)
	var toast: Node3D = toaster.find_child("Toast", true, false)
	C.tw(toast, "position:y", 0.35, 0.25, 0.0, Tween.TRANS_QUAD, Tween.EASE_OUT)
	C.tw(toast, "position:y", 0.0, 0.3, 0.3, Tween.TRANS_QUAD, Tween.EASE_IN)
	await C.wait(0.8)
	C.focus(0.0)
	# 12. montage: all over town, bots put on hard hats. The dock worker...
	C.cut(dock_bot.global_position + Vector3(2.2, 1.4, 3.0), dock_bot.global_position + Vector3(0, 0.8, 0), 40.0)
	C.move(dock_bot.global_position + Vector3(1.6, 1.2, 2.2), dock_bot.global_position + Vector3(0, 0.9, 0), 2.6, 34.0)
	await C.wait(0.5)
	C.tw(hats[0], "scale", Vector3.ONE, 0.25, 0.0, Tween.TRANS_BACK, Tween.EASE_OUT)
	C.fx(func(): Snd.at("cell_pickup", dock_bot.global_position, -6); FX.sparks(dock_bot.global_position + Vector3(0, 1, 0), Color(1, 0.8, 0.3), 6, 2.0))
	C.tw(dock_bot, "rotation:y", dock_bot.rotation.y + PI, 0.5, 0.4, Tween.TRANS_BACK, Tween.EASE_OUT)
	await C.wait(1.4)
	# ...and the mail hornet over the plaza
	var mp: Vector3 = mail_bot.global_position
	C.cut(mp + Vector3(-2.5, 0.2, 3.5), mp, 40.0)
	C.tw(mail_bot, "global_position", mp + Vector3(-2, 0.4, -1), 3.5, 0.0, Tween.TRANS_SINE)
	C.look_node = mail_bot
	await C.wait(0.4)
	C.tw(hats[1], "scale", Vector3.ONE, 0.25, 0.0, Tween.TRANS_BACK, Tween.EASE_OUT)
	C.fx(func(): Snd.at("cell_pickup", mp, -6))
	await C.say("cs_intro_mail", 0.2)
	C.look_node = null
	# 13. every bot goes haywire: rollers in the yard, a hornet over the wall, sparks from the generator
	C.cut(Vector3(3, 5.5, 98.5), Vector3(-3, 0.5, 79), 52.0)
	C.move(Vector3(1, 6.5, 99.5), Vector3(-4, 0.5, 77), 7.0)
	C.tw(hats[2], "scale", Vector3.ONE, 0.2)
	C.tw(roller, "global_position", Vector3(-6, 0, 80), 5.0, 0.0, Tween.TRANS_LINEAR)
	C.tw(roller, "rotation:y", 2.4, 5.0)
	C.tw(roller2, "global_position", Vector3(4, 0, 79), 4.0, 0.3, Tween.TRANS_LINEAR)
	C.tw(hornet, "global_position", Vector3(12, 5, 74), 6.0, 0.0, Tween.TRANS_LINEAR)
	C.fx(func(): FX.sparks(Vector3(10, 1.4, 94.5), Color(1, 0.7, 0.3), 16, 5.0); Snd.at("bot_spawn", Vector3(-6, 0, 80), -4))
	await C.wait(0.5)
	await C.say("intro_09", 0.5)
	C.fx(func(): FX.sparks(Vector3(10, 1.4, 94.5), Color(1, 0.7, 0.3), 10, 4.0))
	# 14. Dodger picks up the signal, looking north to the mast
	C.cut(dodger.global_position + Vector3(0.5, 0.35, 1.4), mast, 30.0)
	C.tw(dodger, "rotation:y", PI, 0.6)
	dodger.look_target = null
	dodger.emote("hop")
	await C.say("intro_10", 0.4)
	# 15. "Somebody else's problem." (back to the coffee)
	C.cut(chair_pos + Vector3(0.5, 1.05, -1.45), chair_pos + Vector3(0, 1.0, 0.1), 38.0)
	C.focus(0.8)
	vesk.look_target = null; vesk.look_point = chair_pos + Vector3(2, 1.2, -8)
	await C.say("intro_11", 0.6)
	# 16. a roller (in a hard hat) trundles up the porch steps and eats the chair
	C.cut(chair_pos + Vector3(4.0, 1.7, -4.2), chair_pos + Vector3(-0.3, 0.6, 0), 46.0)
	C.focus(0.0)
	C.setv(roller, "global_position", chair_pos + Vector3(-5, porch_y - 0.4, -4))
	C.tw(roller, "global_position", chair_pos + Vector3(-1.4, porch_y, -0.9), 1.6, 0.0, Tween.TRANS_LINEAR)
	C.tw(roller, "rotation:y", 0.9, 1.6)
	C.fx(func(): Snd.at("roller_roll", chair_pos, -2))
	await C.wait(1.0)
	# Vesk hops out of the chair
	vesk.look_target = roller
	vesk.play("jump", 0.1)
	C.tw(vesk, "sit", 0.0, 0.3); C.tw(vesk, "slump", 0.0, 0.3)
	C.tw(vesk, "global_position", chair_pos + Vector3(1.6, porch_y - 0.4 + 0.02, -0.9), 0.55, 0.0, Tween.TRANS_QUAD, Tween.EASE_OUT)
	await C.wait(0.55)
	vesk.play("land", 0.05)
	C.fx(func(): Snd.at("land", vesk.global_position, -4))
	await C.wait(0.35)
	vesk.play("idle", 0.3)
	C.setv(vesk, "rotation:y", C.face_to(vesk, chair_pos))
	C.tw(roller, "global_position", chair_pos + Vector3(-0.2, porch_y, -0.3), 0.5)
	await C.wait(0.5)
	C.fx(func(): Snd.at("crate_break", chair_pos, -2); FX.puff(chair_pos + Vector3(0, 0.6, 0), Color(0.6, 0.5, 0.4)); FX.shake(0.3))
	if chair:
		C.tw(chair, "rotation:z", 1.45, 0.35, 0.0, Tween.TRANS_BOUNCE, Tween.EASE_OUT)
		C.tw(chair, "position", chair.position + Vector3(0.35, -0.05, -0.2), 0.35)
		C.tw(chair, "scale", Vector3(1, 0.75, 1), 0.3)
	await C.wait(0.6)
	dodger.look_target = vesk
	await C.say("intro_12", 0.4)
	# 17. "...That was a good chair." Then the long-suffering decision.
	C.cut(vesk.global_position + Vector3(0.9, 1.25, -1.5), vesk.global_position + Vector3(0, 1.3, 0), 36.0)
	C.focus(1.0)
	vesk.look_target = null; vesk.look_point = chair_pos
	await C.wait(0.4)
	await C.say("cs_intro_chair", 0.5)
	var fp: float = vesk.gesture("cs_facepalm", 0.25, "idle")
	await C.wait(minf(fp, 2.2) if fp > 0.0 else 0.6)
	C.cut(vesk.global_position + Vector3(-1.2, 1.15, -1.6), vesk.global_position + Vector3(0, 1.0, 0), 40.0)
	C.setv(vesk, "rotation:y", C.face_to(vesk, vesk.global_position + Vector3(-1, 0, -2)))
	vesk.look_point = Vector3.INF
	vesk.look_target = dodger
	C.tw(roller, "global_position", Vector3(-8, 0.0, 79), 2.4, 0.4, Tween.TRANS_QUAD, Tween.EASE_IN)
	vesk.gesture("cs_talk2", 0.3, "idle")
	await C.say("intro_13", 0.3)
	vesk.hold_mug(false)
	# 18. Dodger cheers, zooms off for the scrap pile... and crashes
	var dp: Vector3 = dodger.global_position
	C.cut(dp + Vector3(1.8, 0.4, 2.2), dp, 44.0)
	C.focus(0.6)
	dodger.look_target = null
	dodger.emote("spin")
	C.tw(dodger, "rotation:y", C.face_to(dodger, crash), 0.4)
	await C.say("intro_14", 0.1)
	C.focus(0.0)
	var fly: float = C.line_len("sky_intro_crash_1")
	if not C.ffwd(): Snd.voice("sky_intro_crash_1", true)
	C.cut(Vector3(1.5, 2.6, 93.5), dp, 46.0)
	C.look_node = dodger
	C.tw(dodger, "global_position", dp + Vector3(-1, 2.5, -3), 0.7, 0.0, Tween.TRANS_SINE, Tween.EASE_OUT)
	C.tw(dodger, "global_position", crash + Vector3(0.4, 1.8, 2.5), fly * 0.55, 0.7, Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	C.tw(dodger, "tilt", Vector3(0.4, 0, 0.3), 0.6, 0.7)
	C.tw(C, "cam_fov", 34.0, fly * 0.7)
	C.fx(func(): Snd.at("dash", dp, -4))
	await C.wait(0.7 + fly * 0.55)
	C.tw(dodger, "global_position", crash + Vector3(0, 0.25, 0), 0.25, 0.0, Tween.TRANS_QUAD, Tween.EASE_IN)
	await C.wait(0.25)
	C.fx(func(): Snd.at("explode_small", crash, -4); FX.sparks(crash + Vector3(0, 0.3, 0), Color(1, 0.7, 0.3), 18, 5.0); FX.puff(crash + Vector3(0, 0.4, 0), Color(0.5, 0.45, 0.4)); FX.shake(0.4))
	C.setv(dodger, "tilt", Vector3(0.9, 0.4, 1.2)); dodger.hover = 0.0; dodger.dim = 0.6
	await C.wait(maxf(0.4, fly * 0.45 - 0.25) + 1.0)
	# 19. hand over: Vesk on the porch steps, looking out at the yard
	C.look_node = null
	vesk.look_target = null
	C.setv(vesk, "global_position", start + Vector3(0, -0.1, 0.9))
	C.setv(vesk, "rotation:y", PI)
	vesk.play("idle")
	C.cut(start + Vector3(0.7, 2.0, 4.6), start + Vector3(0, 1.2, -3.0), 50.0)
	C.walk(vesk, start + Vector3(0, -0.1, 0), 2.0)
	await C.wait(0.6)
	vesk.play("idle", 0.3)
	await C.wait(0.4)
	if chair:  # the chewed chair stays knocked over
		chair.rotation.z = 1.45; chair.scale = Vector3(1, 0.75, 1)
