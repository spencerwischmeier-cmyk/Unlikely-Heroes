extends RefCounted
const S := preload("res://scripts/level/layout/spread.gd")   # original positions -> spread-out level
## INTRO: "Clocking In". The sky city from far out, the docks waking up, out to the junkyard where
## Vesk enjoys his coffee and ignores customers. 7:59:57... 8:00:00: a distant voice says "clock in",
## the coffee maker punches a time card, bots all over town put on hard hats and go haywire, a roller
## eats Vesk's chair, and Dodger zooms off to find the signal and crashes on the scrap pile (where the
## level picks him up). Anchors: porch chair, workbench gear, Dodger crash spot, mast top, start_pos,
## and the plaza / pier_a island rects.

const Props := preload("res://scripts/cutscene/props.gd")
var C: Node

func run() -> void:
	var chair_pos: Vector3 = C.spot("porch_chair_pos", S.at(Vector3(-2.5, 0.4, 93.5)))
	var porch_y := 0.4
	var bench: Vector3 = C.spot("gear_pos", S.at(Vector3(3.6, 1.45, 94)))
	var crash: Vector3 = C.spot("dodger_crash_pos", S.at(Vector3(-12.5, 2.4, 74.5)))
	var mast: Vector3 = C.spot("mast_top", S.at(Vector3(14, 20, -34)))
	var start: Vector3 = Game.level.start_pos if Game.level else S.at(Vector3(0, 0.5, 91))
	var plaza: Vector3 = C.island_center("plaza", S.at(Vector3(0, 0, 30)))
	var pier: Vector3 = C.island_center("pier_a", S.at(Vector3(38, 0, 26)))
	var chair: Node3D = Game.level.find_child("porch_chair", false, false) if Game.level else null
	if chair: chair_pos = chair.global_position
	var bench_top := bench.y - 0.05
	# actors: seated with the real chair clip when it exists, else the procedural fold
	var vesk: Node3D = C.make_vesk(chair_pos, PI)
	var sit_off := Vector3(0, 0.33, 0.2) if vesk.can_sit() else Vector3(0, 0.27, 0.06)
	vesk.global_position = chair_pos + sit_off
	if vesk.can_sit():
		vesk.play("cs_sit_drink", 0.0)
	else:
		vesk.sit = 1.0; vesk.slump = 1.0
	vesk.hold_mug(true)
	# camera heights for the seated shots (the real sitting clip sits him up on the chair)
	var seat: Vector3 = chair_pos + Vector3(0, 0.31 if vesk.can_sit() else 0.0, 0)
	# where Dodger hovers while he pesters Vesk: in front and to his left, a little above eye line
	var dspot: Vector3 = seat + Vector3(0.8, 1.42, -0.9)
	var dodger: Node3D = C.make_dodger(S.at(Vector3(-30, 9, 70)), PI * 0.5)
	var coffee: Node3D = C.actor(Props.coffee_maker(), Vector3(bench.x + 0.95, bench_top, bench.z + 0.05), PI + 0.25, true)
	var toaster: Node3D = C.actor(Props.toaster(), Vector3(bench.x - 0.75, bench_top, bench.z + 0.1), PI - 0.2, true)
	var roller: Node3D = C.actor(C.model("res://models/roller.glb"), S.at(Vector3(-14, 0.0, 86)), 0.0)
	var roller2: Node3D = C.actor(C.model("res://models/roller.glb"), S.at(Vector3(15, 0.0, 76)), 0.0)
	var hornet: Node3D = C.actor(C.model("res://models/hornet.glb"), S.at(Vector3(-30, 7, 80)), PI * 0.5)
	# town bots for the montage: a dock worker and a mail hornet, hats ready to pop on
	var dock_bot: Node3D = C.actor(C.model("res://models/roller.glb"), pier + Vector3(-3, 0, 2), 1.2)
	var mail_bot: Node3D = C.actor(C.model("res://models/hornet.glb"), plaza + Vector3(4, 3.2, 6), -0.6)
	var RollAnim := load("res://scripts/cutscene/roll_anim.gd")
	for r in [roller, roller2, dock_bot]: r.add_child(RollAnim.new())
	# the dock bot hauls a crate on its back
	var cargo: Node3D = C.model("res://models/kit/crate_small.glb")
	_ride(dock_bot, cargo, Vector3(0, 0.98, -0.05), 0.45)
	var hats := []
	for b in [dock_bot, mail_bot, roller]:
		var h: Node3D = Props.hard_hat(0.28 if b != mail_bot else 0.22)
		_ride(b, h, Vector3(0, 1.05 if b != mail_bot else 0.55, 0), 0.001)
		hats.append(h)

	var seated: bool = vesk.has_method("hold") and vesk.has("cs_sit_drink")
	if seated: vesk.hold("cs_sit_drink", 2.6, 0.0)
	_vesk = vesk
	_dodger = dodger
	var vh: Node3D = C.head_of(vesk)            # his eyes, for focus pulls and the light rig
	var dh: Node3D = dodger
	C.score("open", 0.0)
	C.grade("vista", 0.0)
	C.mblur = 0.55

	# 1. the sky city, from far out: a slow crane down through the haze
	C.mark("city")
	Snd.loop("wind_loop", true, -12)
	C.cut(S.at(Vector3(40, 58, 190)), S.at(Vector3(4, 6, 30))); C.lens(24.0)
	C.move(S.at(Vector3(22, 30, 138)), S.at(Vector3(0, 2, 40)), 16.0, -1.0, Tween.TRANS_CUBIC, Tween.EASE_OUT)
	C.lens(28.0, 16.0)
	C.tw(C, "fade", 0.0, 3.5)
	C.show_location("SKYHARBOR", "Planet 1  ·  The sky city  ·  Golden hour", 5.0)
	await C.wait(2.6)
	await C.say("intro_01", 0.6)
	# 2. low along the docks, tracking the dock bot as it hauls crates (still a nice bot, for now)
	C.mark("docks")
	C.grade("golden", 0.0)
	var dbp: Vector3 = dock_bot.global_position
	C.cut(dbp + Vector3(-3.5, 1.1, 4.2), dbp + Vector3(0, 0.9, 0)); C.lens(35.0)
	# roll, ease to a stop to let a gull pass, then carry on (eased, so the roll reads as weight)
	var dmid: Vector3 = dbp.lerp(pier + Vector3(5, 0, 1), 0.45)
	C.tw(dock_bot, "global_position", dmid, 3.8, 0.3, Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	C.tw(dock_bot, "global_position", pier + Vector3(5, 0, 1), 4.6, 4.6, Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	C.follow_node = dock_bot; C.follow_off = Vector3(-3.2, 1.2, 4.4)
	C.look_node = dock_bot; C.look_off = Vector3(1.5, 0.9, 0)
	C.focus_on(dock_bot, Vector3(0, 0.8, 0), 0.0, 0.5)
	await C.say("cs_intro_city", 0.6)
	# 3. over the gardens and out to the junkyard: a long glide, the porch light catching the sun
	C.mark("glide")
	C.cut(S.at(Vector3(-66, 24, 34)), S.at(Vector3(-10, 3, 44))); C.lens(30.0)
	C.move(S.at(Vector3(-30, 12, 70)), S.at(Vector3(-2, 1.5, 86)), 9.5, -1.0, Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	C.lens(40.0, 9.5)
	await C.say("intro_02", 1.0)
	# 4. the porch. Macro on the brass gear on the workbench, then rack focus to Vesk in his chair
	C.mark("porch")
	C.grade("porch", 2.0)
	C.score("porch", 2.5)
	C.room_tone("porch_tone", -16.0, 3.0)
	C.light(vh, "golden", 1.0)
	C.cut(bench + Vector3(-0.32, 0.16, -0.75), seat + Vector3(0, 0.95, 0)); C.lens(85.0)
	var gear_mark: Node3D = C.actor(Node3D.new(), bench + Vector3(0, 0.05, 0))
	C.focus_on(gear_mark, Vector3.ZERO, 0.0, 1.0)
	C.move(bench + Vector3(-0.5, 0.2, -0.95), seat + Vector3(0, 0.95, 0), 9.0)
	C.sway = 0.4
	vesk.mood("content", 0.1)
	vesk.look_point = chair_pos + Vector3(3, 1.4, -8)
	await C.wait(1.6)
	C.focus_on(vh, Vector3.ZERO, 2.2, 1.0)          # rack: gear soft, Vesk sharp
	await C.say("intro_03", 0.9)
	# 5. "Ahhh. Finally. Nothing left to fix." Eyes shut, the long happy sigh, then the sip
	C.mark("sigh")
	_cu(-30.0, 1.45, 65.0, -0.02)
	C.focus_on(vh, Vector3.ZERO, 0.0, 0.8)
	C.light(vh, "golden", -1.0)
	_push(-30.0, 1.2, 12.0)   # slow push-in
	vesk.mood("content", 0.6)
	vesk.act("content_sigh")
	C.fx(func(): C.foley("chair_creak", chair_pos, -10))
	await C.say("intro_04", 0.5)
	# the sip: cut wider, front three-quarter from his body so the face stays in view
	_cub(-30.0, 2.3, 50.0, -0.08)
	C.focus_on(vh, Vector3.ZERO, 0.0, 0.7)
	if seated: C.fx(func(): C.foley("mug_sip", seat + Vector3(0, 1.0, 0), -6)); vesk.sip(1.4)
	await C.wait(0.6)
	await C.say("cs_intro_sip", 0.9)
	# 6. Dodger swoops in over the yard: wide from behind the chair, whip-panning with him
	C.mark("dodger_in")
	C.cut(seat + Vector3(-1.4, 1.5, 1.6), seat + Vector3(-6, 3.0, -10)); C.lens(24.0)
	C.focus(0.0)
	C.light(vh, "soft", 1.0)
	C.setv(dodger, "global_position", chair_pos + Vector3(-9, 5, -14))
	C.tw(dodger, "global_position", chair_pos + Vector3(4, 3.0, -6), 1.2, 0.0, Tween.TRANS_SINE, Tween.EASE_OUT)
	C.tw(dodger, "global_position", dspot, 1.1, 1.2, Tween.TRANS_BACK, Tween.EASE_OUT)
	C.tw(dodger, "rotation:y", PI + 0.6, 0.8, 1.2)
	C.look_node = dodger; C.look_off = Vector3(0, -0.3, 0)
	C.fx(func(): Snd.play("cutscenes_whoosh", -6); Snd.at("dash", dodger.global_position, -8))
	vesk.mood("tired", 0.8)                              # he doesn't even look
	await C.wait(2.4)
	C.look_node = null
	dodger.look_target = vesk
	dodger.act("spin")
	# Dodger, close: Vesk soft over his shoulder
	C.cut(seat + Vector3(-0.8, 1.55, 0.9), dspot); C.lens(50.0)   # over Vesk's shoulder, far enough back that his head is a soft edge, not a wall
	C.focus_on(dodger, Vector3.ZERO, 0.0, 0.9)
	C.light(dodger, "soft", -1.0, 0.0)
	await C.say("intro_05", 0.4)
	# 7. "Dodger. It's my day off." Close on Vesk, Dodger a soft blur at the frame edge
	C.mark("day_off")
	C.auto_look = false
	vesk.look_target = null; vesk.look_point = chair_pos + Vector3(2, 1.4, -8)
	_cu(28.0, 1.5, 75.0, -0.03)
	C.focus_on(vh, Vector3.ZERO, 0.0, 1.0)
	C.light(vh, "golden", 1.0)
	_push(28.0, 1.3, 10.0)
	vesk.mood("annoyed", 0.4)
	vesk.act("sigh")
	var l6: float = C.say_async("intro_06")
	await C.wait(1.6)
	vesk.look_target = dodger                            # turns to him for the explanation
	vesk.mood("skeptical", 0.5)
	await C.wait(3.2)
	vesk.act("nod_small")
	await C.wait(maxf(0.5, l6 - 4.8) - 1.6)
	vesk.look_target = null; vesk.look_point = chair_pos + Vector3(2, 1.4, -8)
	vesk.mood("tired", 0.6); vesk.act("settle")
	await C.wait(1.6 + 1.0)
	# 8. the customer at the gate: shot / reverse shot
	C.mark("gate")
	# a two-shot that sees Dodger's face: from Vesk's side of him, swung off the line between them
	var hv: Vector3 = C.head_of(vesk).global_position
	var to_vk := ((hv - dspot) * Vector3(1, 0, 1)).normalized()
	var gcands := []
	for a in [0.55, -0.55, 0.75, -0.75, 1.0, -1.0]:
		gcands.append(dspot + to_vk.rotated(Vector3.UP, a) * 2.4 + Vector3(0, 0.35, 0))
	var gcam: Vector3 = _clear(dspot, gcands)
	var gmid := dspot.lerp(hv, 0.35)
	C.cut(gcam, gmid); C.lens(32.0)
	C.focus_on(dodger, Vector3.ZERO, 0.0, 0.5)
	C.light(dodger, "soft", 1.0, 0.0)
	C.move(gcam + (gmid - gcam).normalized() * 0.4, gmid, 6.0)
	dodger.act("hop")
	await C.say("cs_intro_gate_1", 0.25)
	_cu(-28.0, 1.45, 70.0, 0.0)
	C.focus_on(vh, Vector3.ZERO, 0.0, 1.0)
	C.light(vh, "golden", -1.0)
	vesk.mood("tired", 0.3)
	await C.say("cs_intro_gate_2", 0.3)
	C.cut(seat + Vector3(-0.8, 1.55, 0.9), dspot); C.lens(60.0)
	C.focus_on(dodger, Vector3.ZERO, 0.0, 1.0)
	C.light(dodger, "soft", -1.0, 0.0)
	dodger.act("squint")
	await C.say("cs_intro_gate_3", 0.3)
	C.setv(dodger, "global_position", dspot + Vector3(0.5, 0.45, -0.5))   # off-camera: drift him clear of the lens line
	_cub(-50.0, 2.2, 40.0, 0.05)    # front three-quarter medium, wide enough that the slurp stays in frame
	C.focus_on(vh, Vector3.ZERO, 0.0, 1.0)
	C.light(vh, "golden", -1.0)
	var sp4 := 0.0
	if seated: sp4 = vesk.sip(0.6)
	C.fx(func(): C.foley("mug_slurp", seat + Vector3(0, 1.0, 0), -4))
	await C.wait(1.2)
	vesk.mood("smug", 0.3)
	await C.say("cs_intro_gate_4", 0.2)
	await C.wait(maxf(0.0, sp4 - 3.2))
	dodger.act("sad")
	await C.wait(0.9)
	C.setv(dodger, "global_position", dspot)
	C.auto_look = true
	# 9. 7:59:57 ... 8:00:00. The relay dish on the Signal Mast pulses; a voice on the wind
	C.mark("clock")
	C.score("tension", 1.5)
	C.grade("tension", 3.0)
	# from his other side, so Dodger (hovering front-right of him) sits beside him instead of over his face
	var kc: Vector3 = _clear(seat + Vector3(0.3, 0.9, 0), [seat + Vector3(-2.2, 1.3, -3.6), seat + Vector3(-1.2, 1.4, -3.9), seat + Vector3(2.4, 1.3, -3.6)])
	C.cut(kc, seat + Vector3(0.3, 0.9, 0)); C.lens(40.0)
	C.move(kc.lerp(seat + Vector3(0.3, 0.9, 0), 0.15), seat + Vector3(0.3, 0.95, 0), 3.4)
	C.focus(0.0)
	C.light(vh, "tension", 1.0)
	C.clock_label.text = "SKYHARBOR   7:59:57 AM"
	C.tw(C, "clock_a", 1.0, 0.6)
	for s in ["58", "59"]:
		await C.wait(1.0)
		C.fx(func(): C.foley("clock_tick", seat, -8))
		C.clock_label.text = "SKYHARBOR   7:59:%s AM" % s
	await C.wait(1.0)
	C.clock_label.text = "SKYHARBOR   8:00:00 AM"
	C.fx(func(): Snd.play("cutscenes_factory_whistle", -2, 0.0); Snd.play("checkpoint", -6))
	# long lens on the mast: heat haze, the dish pulsing
	var mto: Vector3 = (mast - seat) * Vector3(1, 0, 1)
	var mdir := mto.normalized()
	var mcands := []
	for k in [0.0, 0.15, 0.3, 0.45]:      # from the porch out along the line to the mast, rising
		for up in [10.0, 14.0, 18.0, 7.0]:
			mcands.append(seat + mto * k + Vector3(0, up, 0) - mdir * 2.0)
	var mcam := _clear(mast + Vector3(0, 0.5, 0), mcands)
	C.grade("vista", 0.0)              # thin the haze for the long lens; back to tension after
	C.cut(mcam, mast + Vector3(0, 0.5, 0)); C.lens(180.0)
	C.move(mcam + Vector3(0, 0.3, 0) + mdir * 0.5, mast + Vector3(0, 1.2, 0), 7.0)
	C.lens(240.0, 7.0)
	C.hand = 0.5
	C.tw(C, "clock_a", 0.0, 1.0, 1.2)
	for i in 4:
		C.fx(func(): FX.ring(mast + Vector3(0, 1.5, 0), Color(1, 0.5, 0.15), 3.0 + i))
		await C.wait(0.5)
	var cl: float = C.say_async("cs_intro_clock")
	await C.wait(cl + 0.4)
	C.hand = 0.0
	C.grade("tension", 0.0)
	vesk.look_point = mast
	dodger.look_target = null
	C.tw(dodger, "rotation:y", C.face_to(dodger, mast), 0.6)
	# both of them turn to the mast, framed small against it
	C.cut(_clear(mast, [seat + Vector3(-1.5, 1.75, 2.7), seat + Vector3(1.2, 1.75, 2.7), seat + Vector3(-1.5, 2.6, 3.4)]), mast); C.lens(35.0)
	C.focus(0.0)
	vesk.mood("skeptical", 0.4)
	await C.say("intro_07", 0.6)
	# 10. the coffee maker clocks in (macro, low; Vesk racks into focus behind it)
	C.mark("coffee")
	var cm_eye: StandardMaterial3D = coffee.get_meta("eye")
	var card: Node3D = coffee.find_child("Card", true, false)
	var stamp: Node3D = coffee.find_child("Stamp", true, false)
	var hat: Node3D = coffee.find_child("Hat", true, false)
	var cpos := coffee.global_position
	C.cut(cpos + Vector3(-0.5, 0.2, -0.82), cpos + Vector3(0, 0.3, 0)); C.lens(50.0)
	C.focus_on(coffee, Vector3(0, 0.3, 0), 0.0, 1.0)
	C.light(coffee, "tension", 1.0, 0.3)
	vesk.look_point = Vector3.INF; vesk.look_target = coffee
	await C.wait(0.8)
	cm_eye.emission = Color(1, 0.3, 0.1)
	C.fx(func(): Snd.at("ui_select", cpos, -4))
	C.tw(card, "position:y", 0.52, 0.25, 0.0, Tween.TRANS_BACK, Tween.EASE_OUT)
	await C.wait(0.6)
	C.tw(stamp, "position:y", 0.39, 0.08, 0.0, Tween.TRANS_EXPO, Tween.EASE_IN)
	await C.wait(0.1)
	C.fx(func(): Snd.at("melee_hit", cpos, -6); C.foley("punch_clock", cpos, -2); FX.sparks(cpos + Vector3(0, 0.45, 0), Color(1, 0.8, 0.4), 6, 2.0); C.shake = 0.25)
	C.tw(stamp, "position:y", 0.46, 0.2, 0.05)
	C.tw(card, "position:y", 0.33, 0.3, 0.4)
	await C.wait(0.5)
	C.tw(hat, "scale", Vector3.ONE, 0.3, 0.0, Tween.TRANS_BACK, Tween.EASE_OUT)
	C.tw(hat, "position:y", 0.45, 0.3, 0.0, Tween.TRANS_BACK, Tween.EASE_OUT)
	C.fx(func(): Snd.at("cell_pickup", cpos, -8))
	await C.wait(0.6)
	dodger.look_target = coffee
	dodger.act("shock")
	vesk.mood("shocked", 0.15); vesk.act("flinch")
	C.focus_on(vh, Vector3.ZERO, 0.6)                  # rack to Vesk's face over the hat
	await C.say("sky_intro_coffee_1", 0.3)
	_cu(-25.0, 1.4, 65.0, 0.0)
	C.focus_on(vh, Vector3.ZERO, 0.0, 1.0)
	C.light(vh, "tension", -1.0)
	vesk.mood("annoyed", 0.25); vesk.act("lean_in")
	await C.say("sky_intro_coffee_2", 0.4)
	C.cut(cpos + Vector3(-0.6, 0.5, -1.05), cpos + Vector3(0, 0.36, 0)); C.lens(45.0)
	C.focus_on(coffee, Vector3(0, 0.4, 0), 0.0, 1.0)
	await C.say("sky_intro_coffee_3", 0.6)
	# 11. the toaster growls (dutch angle)
	var tpos := toaster.global_position
	var t_eye: StandardMaterial3D = toaster.get_meta("eye")
	C.cut(tpos + Vector3(0.48, 0.24, -0.72), tpos + Vector3(0, 0.12, 0)); C.lens(40.0)
	C.cam_roll = -0.18
	C.focus_on(toaster, Vector3(0, 0.12, 0), 0.0, 1.0)
	C.light(toaster, "angry", 1.0, 0.15)
	C.tw(t_eye, "emission_energy_multiplier", 4.0, 0.5)
	C.fx(func(): C.foley("toaster_growl", tpos, -4))
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
	C.light_off()
	# 12. montage: all over town, bots put on hard hats. Whip-pans between them
	C.mark("montage")
	C.score("haywire", 0.4)
	C.grade("chaos", 1.0)
	C.mblur = 0.9
	var dbm: Vector3 = dock_bot.global_position + Vector3(0, 0.8, 0)
	var dcam := _clear(dbm, _ring(dbm, 3.4, 0.6, deg_to_rad(55.0)))   # first angle with nothing in the way
	C.cut(dcam, dbm); C.lens(35.0)
	C.move(dbm + (dcam - dbm) * 0.72, dbm + Vector3(0, 0.1, 0), 2.6)
	C.lens(45.0, 2.6)
	await C.wait(0.5)
	C.tw(hats[0], "scale", Vector3.ONE, 0.25, 0.0, Tween.TRANS_BACK, Tween.EASE_OUT)
	C.fx(func(): Snd.at("cell_pickup", dock_bot.global_position, -6); FX.sparks(dock_bot.global_position + Vector3(0, 1, 0), Color(1, 0.8, 0.3), 6, 2.0))
	C.tw(dock_bot, "rotation:y", dock_bot.rotation.y + PI, 0.5, 0.4, Tween.TRANS_BACK, Tween.EASE_OUT)
	await C.wait(1.2)
	C.tw(C, "cam_look", C.cam_look + Vector3(8, 0, -6), 0.22, 0.0, Tween.TRANS_QUAD, Tween.EASE_IN)   # whip out
	C.fx(func(): Snd.play("cutscenes_whoosh", -10))
	await C.wait(0.22)
	# ...and the mail hornet over the plaza
	var mp: Vector3 = mail_bot.global_position
	C.cut(mp + Vector3(-2.5, 0.2, 3.5), mp + Vector3(3, 0, -2)); C.lens(40.0)
	C.tw(C, "cam_look", mp, 0.25, 0.0, Tween.TRANS_QUAD, Tween.EASE_OUT)   # whip in
	C.tw(mail_bot, "global_position", mp + Vector3(-2, 0.4, -1), 3.5, 0.0, Tween.TRANS_SINE)
	await C.wait(0.25)
	C.look_node = mail_bot
	await C.wait(0.2)
	C.tw(hats[1], "scale", Vector3.ONE, 0.25, 0.0, Tween.TRANS_BACK, Tween.EASE_OUT)
	C.fx(func(): Snd.at("cell_pickup", mp, -6))
	await C.say("cs_intro_mail", 0.2)
	C.look_node = null
	# ...and one bot that does NOT clock in: Gizmart, at his plaza kiosk
	var giz := _gizmart_spot()
	if giz.size() > 0:
		var gp: Vector3 = giz[0]; var gf: Vector3 = giz[1]
		var gside := gf.cross(Vector3.UP)
		C.cut(gp + gf * 3.6 + gside * 1.2 + Vector3(0, 1.5, 0), gp + Vector3(0, 1.5, 0)); C.lens(40.0)
		C.move(gp + gf * 2.8 + gside * 0.8 + Vector3(0, 1.5, 0), gp + Vector3(0, 1.6, 0), 9.0)
		C.lens(50.0, 9.0)
		C.fx(func(): Snd.at("gizmart_chime", gp, -2))
		await C.say("cs_intro_gizmart", 0.2)
		await C.say("cs_intro_gizmart_2", 0.4)
	# 13. every bot goes haywire: handheld, rollers in the yard, a hornet over the wall, the generator sparking
	C.mark("haywire")
	C.cut(S.at(Vector3(3, 5.5, 98.5)), S.at(Vector3(-3, 0.5, 79))); C.lens(24.0)
	C.move(S.at(Vector3(1, 6.5, 99.5)), S.at(Vector3(-4, 0.5, 77)), 7.0)
	C.hand = 1.0
	C.tw(hats[2], "scale", Vector3.ONE, 0.2)
	C.tw(roller, "global_position", S.at(Vector3(-6, 0, 80)), 5.0, 0.0, Tween.TRANS_LINEAR)
	C.tw(roller, "rotation:y", 2.4, 5.0)
	C.tw(roller2, "global_position", S.at(Vector3(4, 0, 79)), 4.0, 0.3, Tween.TRANS_LINEAR)
	C.tw(hornet, "global_position", S.at(Vector3(12, 5, 74)), 6.0, 0.0, Tween.TRANS_LINEAR)
	C.fx(func(): FX.sparks(S.at(Vector3(10, 1.4, 94.5)), Color(1, 0.7, 0.3), 16, 5.0); Snd.at("bot_spawn", S.at(Vector3(-6, 0, 80)), -4))
	await C.wait(0.5)
	await C.say("intro_09", 0.5)
	C.fx(func(): FX.sparks(S.at(Vector3(10, 1.4, 94.5)), Color(1, 0.7, 0.3), 10, 4.0))
	C.hand = 0.0
	C.mblur = 0.55
	# 14. Dodger picks up the signal, looking north to the mast
	# his line plays over the mast: long lens, the dish pulsing, a slow push
	var scam := _clear(mast + Vector3(0, 0.8, 0), mcands)
	C.grade("vista", 0.0)
	C.cut(scam, mast + Vector3(0, 0.8, 0)); C.lens(140.0)
	C.move(scam + mdir * 0.6 + Vector3(0, 0.2, 0), mast + Vector3(0, 1.0, 0), 6.0)
	C.lens(200.0, 6.0)
	C.fx(func(): FX.ring(mast + Vector3(0, 1.5, 0), Color(1, 0.5, 0.15), 4.0))
	C.light(dodger, "tension", 1.0, 0.0)
	C.tw(dodger, "rotation:y", PI, 0.6)
	dodger.look_target = null
	dodger.act("hop")
	await C.say("intro_10", 0.4)
	# 15. "Somebody else's problem." Back to the coffee, the sky going orange behind him
	C.mark("not_my_problem")
	C.grade("porch", 1.5)
	C.score("porch_b", 1.5)
	_cu(-32.0, 1.4, 70.0, 0.0)
	C.focus_on(vh, Vector3.ZERO, 0.0, 1.0)
	C.light(vh, "golden", 1.0)
	vesk.look_target = null; vesk.look_point = chair_pos + Vector3(2, 1.2, -8)
	vesk.mood("smug", 0.4)
	await C.say("intro_11", 0.2)
	var sp11 := 0.0
	if seated: sp11 = vesk.sip(1.2)
	await C.wait(0.9)
	# 16. a roller (in a hard hat) trundles up the porch steps and eats the chair
	C.mark("chair")
	C.score("sting", 0.2)
	C.grade("chaos", 0.6)
	C.cut(chair_pos + Vector3(4.0, 1.7, -4.2), chair_pos + Vector3(-0.3, 0.6, 0)); C.lens(28.0)
	C.focus(0.0)
	C.light(vh, "soft", 1.0)
	C.setv(roller, "global_position", chair_pos + Vector3(-5, porch_y - 0.4, -4))
	C.tw(roller, "global_position", chair_pos + Vector3(-1.4, porch_y, -0.9), 1.6, 0.0, Tween.TRANS_LINEAR)
	C.tw(roller, "rotation:y", 0.9, 1.6)
	C.fx(func(): Snd.at("roller_roll", chair_pos, -2))
	await C.wait(1.0)
	# Vesk hops out of the chair, mug still in hand
	vesk.look_target = roller
	vesk.mood("shocked", 0.1)
	vesk.play("jump", 0.1)
	C.tw(vesk, "sit", 0.0, 0.3); C.tw(vesk, "slump", 0.0, 0.3)
	C.tw(vesk, "global_position", chair_pos + Vector3(1.6, porch_y - 0.4 + 0.02, -0.9), 0.55, 0.0, Tween.TRANS_QUAD, Tween.EASE_OUT)
	await C.wait(0.55)
	vesk.play("land", 0.05)
	C.fx(func(): Snd.at("land", vesk.global_position, -4); C.foley("boot_land", vesk.global_position, -4))
	await C.wait(0.35)
	vesk.play("idle", 0.3)
	C.setv(vesk, "rotation:y", C.face_to(vesk, chair_pos))
	C.tw(roller, "global_position", chair_pos + Vector3(-0.2, porch_y, -0.3), 0.5)
	await C.wait(0.5)
	C.fx(func(): Snd.at("crate_break", chair_pos, -2); C.foley("chair_crunch", chair_pos, 0); FX.puff(chair_pos + Vector3(0, 0.6, 0), Color(0.6, 0.5, 0.4)); FX.shake(0.3); C.shake = 0.6)
	if chair:
		C.tw(chair, "rotation:z", 1.45, 0.35, 0.0, Tween.TRANS_BOUNCE, Tween.EASE_OUT)
		C.tw(chair, "position", chair.position + Vector3(0.35, -0.05, -0.2), 0.35)
		C.tw(chair, "scale", Vector3(1, 0.75, 1), 0.3)
	await C.wait(0.6)
	dodger.look_target = vesk
	# Dodger, wide-eyed, the wrecked chair soft behind him
	var dpp: Vector3 = dodger.global_position
	var to_v := ((vesk.global_position - dpp) * Vector3(1, 0, 1)).normalized()   # he's facing Vesk
	var dcands := []
	for a in [0.5, -0.5, 0.9, -0.9]:
		dcands.append(dpp + to_v.rotated(Vector3.UP, a) * 1.6 + Vector3(0, -0.1, 0))
	C.cut(_clear(dpp, dcands), dpp); C.lens(45.0)
	C.look_node = dodger; C.look_off = Vector3(0, 0.05, 0)
	C.focus_on(dodger, Vector3.ZERO, 0.0, 0.8)
	C.light(dodger, "soft", 1.0, 0.0)
	await C.say("intro_12", 0.4)
	# 17. "...That was a good chair." A slow push-in that widens the background (dolly zoom), then the facepalm
	C.mark("good_chair")
	C.score("", 1.0)                                    # the music drops out for the line
	C.grade("tension", 2.0)
	var vp: Vector3 = vesk.global_position
	var fwd := Vector3(sin(vesk.rotation.y), 0, cos(vesk.rotation.y))
	var side := fwd.cross(Vector3.UP)
	vesk.look_target = null; vesk.look_point = chair_pos
	C.tw(dodger, "global_position", dodger.global_position + Vector3(0, 1.1, 0), 0.8)   # he backs off, out of the shot
	_cu(-50.0, 2.4, 50.0, 0.0)          # off to the side, so the roller isn't between us and him
	_push(-50.0, 1.5, 4.0)
	C.lens(35.0, 4.0)
	C.focus_on(vh, Vector3.ZERO, 0.0, 1.0)
	C.light(vh, "angry", 1.0)
	vesk.mood("stunned", 0.4)
	await C.wait(0.6)
	var lc: float = C.say_async("cs_intro_chair")
	await C.wait(lc * 0.45)
	vesk.mood("furious", 0.5)
	await C.wait(lc * 0.55 + 0.5)
	var fp: float = vesk.gesture("cs_facepalm", 0.25, "idle")
	await C.wait(minf(fp, 2.2) if fp > 0.0 else 0.6)
	# 18. "Fine. Let's go unplug it." Low angle, hard rim light, the hero shot
	C.mark("fine")
	C.score("hero", 0.3)
	C.grade("hero", 1.0)
	C.setv(vesk, "rotation:y", C.face_to(vesk, vesk.global_position + Vector3(-1, 0, -2)))
	vp = vesk.global_position
	fwd = Vector3(sin(vesk.rotation.y), 0, cos(vesk.rotation.y)); side = fwd.cross(Vector3.UP)
	C.cut(vp + fwd * 2.3 - side * 1.1 + Vector3(0, 0.8, 0), vp + Vector3(0, 1.5, 0)); C.lens(28.0)
	C.move(vp + fwd * 2.0 - side * 0.95 + Vector3(0, 0.75, 0), vp + Vector3(0, 1.5, 0), 4.0)
	C.focus_on(vh, Vector3.ZERO, 0.0, 0.6)
	C.light(vh, "hero", -1.0)
	vesk.look_point = Vector3.INF
	vesk.look_target = dodger
	C.tw(roller, "global_position", S.at(Vector3(-8, 0.0, 79)), 2.4, 0.4, Tween.TRANS_QUAD, Tween.EASE_IN)
	vesk.mood("furious", 0.2)
	vesk.act("puff_up")
	await C.wait(0.3)
	vesk.gesture("cs_talk2", 0.3, "idle")
	await C.say("intro_13", 0.3)
	vesk.mood("annoyed", 0.6)
	vesk.hold_mug(false)
	# 19. Dodger cheers, zooms off for the scrap pile... and crashes
	C.mark("crash")
	var dp: Vector3 = dodger.global_position
	C.cut(dp + Vector3(1.8, 0.4, 2.2), dp); C.lens(40.0)
	C.focus_on(dodger, Vector3.ZERO, 0.0, 0.6)
	C.light(dodger, "hero", 1.0, 0.0)
	dodger.look_target = null
	dodger.act("spin")
	C.tw(dodger, "rotation:y", C.face_to(dodger, crash), 0.4)
	await C.say("intro_14", 0.1)
	C.focus(0.0)
	C.light_off()
	C.mblur = 0.9
	var fly: float = C.line_len("sky_intro_crash_1")
	if not C.ffwd(): Snd.voice("sky_intro_crash_1", true)
	C.cut(S.at(Vector3(1.5, 2.6, 93.5)), dp); C.lens(28.0)
	C.look_node = dodger
	C.tw(dodger, "global_position", dp + Vector3(-1, 2.5, -3), 0.7, 0.0, Tween.TRANS_SINE, Tween.EASE_OUT)
	C.tw(dodger, "global_position", crash + Vector3(0.4, 1.8, 2.5), fly * 0.55, 0.7, Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	C.tw(dodger, "tilt", Vector3(0.4, 0, 0.3), 0.6, 0.7)
	C.lens(55.0, fly * 0.7)
	C.fx(func(): Snd.at("dash", dp, -4); Snd.play("cutscenes_whoosh", -8))
	await C.wait(0.7 + fly * 0.55)
	C.tw(dodger, "global_position", crash + Vector3(0, 0.25, 0), 0.25, 0.0, Tween.TRANS_QUAD, Tween.EASE_IN)
	await C.wait(0.25)
	C.fx(func(): Snd.at("explode_small", crash, -4); C.foley("scrap_crash", crash, 0); FX.sparks(crash + Vector3(0, 0.3, 0), Color(1, 0.7, 0.3), 18, 5.0); FX.puff(crash + Vector3(0, 0.4, 0), Color(0.5, 0.45, 0.4)); FX.shake(0.4); C.shake = 0.5)
	C.setv(dodger, "tilt", Vector3(0.9, 0.4, 1.2)); dodger.hover = 0.0; dodger.dim = 0.6
	await C.wait(0.4)
	# the aftermath, close: Dodger upside down in the scrap, props winding down, smoke drifting
	var cpt: Vector3 = crash + Vector3(0, 0.3, 0)
	var to_c := ((S.at(Vector3(1.5, 2.6, 93.5)) - crash) * Vector3(1, 0, 1)).normalized()
	var ccands := []
	for a in [0.0, 0.5, -0.5, 1.0, -1.0, 1.6, -1.6]:
		ccands.append(crash + to_c.rotated(Vector3.UP, a) * 2.2 + Vector3(0, 0.9, 0))
	C.look_node = null
	C.cut(_clear(cpt, ccands), cpt); C.lens(35.0)
	C.focus_on(dodger, Vector3.ZERO, 0.0, 0.6)
	await C.wait(maxf(0.4, fly * 0.45 - 0.25) + 0.6)
	# 20. hand over: crane down behind Vesk on the porch steps, settling into the gameplay camera
	C.mark("handover")
	C.mblur = 0.55
	C.look_node = null
	vesk.look_target = null
	vesk.mood("annoyed", 0.3)
	C.setv(vesk, "global_position", start + Vector3(0, -0.1, 0.9))
	C.setv(vesk, "rotation:y", PI)
	vesk.play("idle")
	C.cut(start + Vector3(0.9, 2.15, 6.2), start + Vector3(0, 1.0, -3.0)); C.lens(35.0)   # under the string lights, not through them
	C.move(start + Vector3(0.6, 2.0, 4.4), start + Vector3(0, 1.2, -3.0), 2.6, -1.0, Tween.TRANS_SINE, Tween.EASE_OUT)
	C.walk(vesk, start + Vector3(0, -0.1, 0), 2.0)
	await C.wait(0.6)
	vesk.play("idle", 0.3)
	await C.wait(0.9)
	if chair:  # the chewed chair stays knocked over
		chair.rotation.z = 1.45; chair.scale = Vector3(1, 0.75, 1)

var _vesk: Node3D
## Close-up on Vesk's face: camera `dist` metres out at `az` degrees from where he faces (+ = his left).
## Parent `n` to the bot's head ("cap") so it leans and bobs with it, at `off` from the bot's origin.
func _ride(bot: Node3D, n: Node3D, off: Vector3, sc: float) -> void:
	var cap: Node3D = bot.find_child("cap", true, false)
	if cap == null:
		bot.add_child(n); n.position = off; n.scale = Vector3.ONE * sc; return
	cap.add_child(n)
	n.global_position = bot.global_transform * off
	n.global_basis = bot.global_basis.orthonormalized().scaled(Vector3.ONE * sc)

## Close-up on Vesk's face. `az` is degrees off his gaze (where his head will be turned to: the look
## target or look point, clamped to how far his head can turn), so the camera always sees his face.
func _cu(az: float, dist: float, mm: float, dy := 0.0) -> void:
	var e: Vector3 = C.head_of(_vesk).global_position
	az = _dodge_az(az, dist, dy, false)
	C.cut(e + _gaze_dir(az) * dist + Vector3(0, dy, 0), e + Vector3(0, -0.08, 0)); C.lens(mm)

## Slow push-in to `dist` along the same angle (shifted the same way _cu shifted it).
func _push(az: float, dist: float, dur: float) -> void:
	var e: Vector3 = C.head_of(_vesk).global_position
	C.move(e + _gaze_dir(az + _az_shift) * dist, e + Vector3(0, -0.08, 0), dur)

var _dodger: Node3D
var _az_shift := 0.0
## Swings the camera angle (up to 70 degrees either way) until Dodger isn't between the lens and Vesk's
## face, and the lens isn't inside him. `body` frames from his body facing (_cub) instead of his gaze.
func _dodge_az(az: float, dist: float, dy: float, body: bool) -> float:
	_az_shift = 0.0
	if not is_instance_valid(_dodger) or not _dodger.visible: return az
	var e: Vector3 = C.head_of(_vesk).global_position
	var dp := _dodger.global_position
	for off in [0.0, 12.0, -12.0, 24.0, -24.0, 36.0, -36.0, 50.0, -50.0, 70.0, -70.0]:
		var d: Vector3 = _body_dir(az + off) if body else _gaze_dir(az + off)
		var cam := e + d * dist + Vector3(0, dy, 0)
		# Dodger's distance to the sight line, and to the lens
		var seg := Geometry3D.get_closest_point_to_segment(dp, cam, e)
		if seg.distance_to(dp) > 0.55 and cam.distance_to(dp) > 0.8:
			_az_shift = off
			if off != 0.0 and C.start_args.has("cut-log"): print("[cam] swung %+d deg to clear Dodger at t=%.1f" % [int(off), C.ct])
			return az + off
	return az

func _body_dir(az: float) -> Vector3:
	var r: float = _vesk.rotation.y
	return Vector3(sin(r), 0, cos(r)).rotated(Vector3.UP, deg_to_rad(az))

## Candidate camera spots on a ring around `c` (radius r, height h above c), starting at angle a0.
func _ring(c: Vector3, r: float, h: float, a0 := 0.0, n := 10) -> Array:
	var out := []
	for i in n:
		var a := a0 + TAU * float(i) / float(n)
		out.append(c + Vector3(sin(a) * r, h, cos(a) * r))
	return out

## First candidate with a clear line of sight to `target` (nothing solid in between), else the first.
func _clear(target: Vector3, cands: Array) -> Vector3:
	var space := (C as Node).get_viewport().world_3d.direct_space_state
	for p in cands:
		var pq := PhysicsPointQueryParameters3D.new(); pq.position = p
		if not space.intersect_point(pq, 1).is_empty(): continue      # camera inside something
		var q := PhysicsRayQueryParameters3D.create(p, target)
		q.hit_from_inside = true
		var hit := space.intersect_ray(q)
		if hit.is_empty() or (hit.position as Vector3).distance_to(target) < 1.0:
			return p
	return cands[0]

## Like _cu, but the angle is taken from the way his body faces, not his gaze (for shots where he looks at Dodger).
func _cub(az: float, dist: float, mm: float, dy := 0.0) -> void:
	var e: Vector3 = C.head_of(_vesk).global_position
	az = _dodge_az(az, dist, dy, true)
	var d := _body_dir(az)
	C.cut(e + d * dist + Vector3(0, dy, 0), e + Vector3(0, -0.08, 0)); C.lens(mm)

func _gaze_dir(az: float) -> Vector3:
	var e: Vector3 = C.head_of(_vesk).global_position
	var r: float = _vesk.rotation.y
	var tp: Vector3 = _vesk.look_point
	if is_instance_valid(_vesk.look_target): tp = _vesk.look_target.global_position
	var rel := 0.0
	if tp != Vector3.INF:
		var d := tp - e
		rel = clampf(wrapf(atan2(d.x, d.z) - r, -PI, PI), -0.8, 0.8)
	return Vector3(sin(r + rel), 0, cos(r + rel)).rotated(Vector3.UP, deg_to_rad(az))

## The first Gizmart kiosk (position, front direction), from the Gizmart system or the level's shop spots.
func _gizmart_spot() -> Array:
	var g: Node = Game.main.get_node_or_null("Gizmart")
	if g and "kiosks" in g and g.kiosks.size() > 0 and is_instance_valid(g.kiosks[0].node):
		var k: Dictionary = g.kiosks[0]
		var pos: Vector3 = (k.node as Node3D).global_position
		var f: Vector3 = k.get("front", pos) - pos   # "front" is a point 1.5 m in front of the kiosk
		f.y = 0.0
		if f.length() > 0.01: return [pos, f.normalized()]
	var spots = Game.level.get("shop_spots") if Game.level else null
	if spots is Array and spots.size() > 0:
		var s: Dictionary = spots[0]
		var yaw: float = s.get("yaw", 0.0)
		return [s.pos, Vector3(sin(yaw), 0, cos(yaw))]
	return []
