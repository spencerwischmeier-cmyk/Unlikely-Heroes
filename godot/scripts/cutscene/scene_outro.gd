extends RefCounted
## OUTRO: after the Crane Bot. The scorecard, a radio crackling in the wreck (Grudd, outraged that his
## Employee of the Week got scrapped), Dodger's eye again, Nana Quill calls in with the coordinates,
## the old hauler drops in and lifts off with the handbrake on. Then the stinger: Grudd's office (no
## windows, many posters), "We're HIRING!", the NOW HIRING poster, and a "next time" bumper for
## Dustvein Gulch. Anchored on the arena island rect.

const Props := preload("res://scripts/cutscene/props.gd")
const OFFICE_AT := Vector3(600, 180, 600)   # out in the empty sky, far from the city
var C: Node

func run() -> void:
	var c: Vector3 = C.island_center("arena", Vector3(0, 0, -97))
	c.y = 0.0
	var mast: Vector3 = C.spot("mast_top", Vector3(14, 20, -34))
	var dish_glow: StandardMaterial3D = Game.level.get("dish_glow") if Game.level else null
	var dish_col := dish_glow.emission if dish_glow else Color.WHITE
	var vesk: Node3D = C.make_vesk(c + Vector3(0, 0, 1), PI)
	var dodger: Node3D = C.make_dodger(c + Vector3(0.85, 1.95, 1.2), PI)
	var radio: Node3D = C.actor(Props.radio(), c + Vector3(-2.5, 0, -6.5), 0.4)
	var lamp: StandardMaterial3D = radio.get_meta("lamp")
	var rlight: OmniLight3D = radio.get_meta("light")
	var horn: Node3D = radio.find_child("Horn", true, false)
	C.cast["grudd"] = horn
	var ship: Node3D = C.actor(Props.ship(), c + Vector3(0, 40, 9), PI)
	ship.visible = false
	var smoke := func(): FX.puff(radio.global_position + Vector3(randf_range(-1, 1), 1.6, randf_range(-1, 1)), Color(0.3, 0.3, 0.33))

	# 1. the Crane Yard after the fight
	C.cut(c + Vector3(17, 10, 15), c + Vector3(0, 1, -2), 50.0)
	C.move(c + Vector3(9, 6, 17), c + Vector3(0, 1, -1), 11.0)
	C.tw(C, "fade", 0.0, 2.0)
	await C.wait(1.6)
	for i in 3: C.fx(smoke)
	await C.say("outro_01", 0.8)
	# 2. the scorecard
	C.cut(c + Vector3(1.9, 1.55, -2.0), c + Vector3(0.3, 1.25, 1), 40.0)
	C.move(c + Vector3(1.5, 1.5, -1.6), c + Vector3(0.3, 1.25, 1), 9.0)
	C.focus(0.6)
	C.fx(smoke)
	dodger.emote("nod")
	await C.say("outro_02", 0.4)
	vesk.gesture("cs_shrug", 0.25, "idle")
	await C.say("outro_03", 0.3)
	dodger.emote("squint")
	await C.say("outro_04", 1.0)
	# 3. a radio crackles in the wreck
	var rp := radio.global_position + Vector3(0.9, 1.3, 1.1)
	C.cut(c + Vector3(1.5, 1.4, -0.5), rp, 46.0)
	C.focus(0.0)
	C.move(c + Vector3(-0.2, 1.2, -3.0), rp, 6.0, 38.0)
	vesk.look_target = horn; dodger.look_target = horn
	C.fx(func(): Snd.at("cutscenes_radio_crackle", rp, 2, 0.0))
	for i in 3:
		C.fx(func(): Snd.at("ui_move", rp, -6); lamp.emission_energy_multiplier = 6.0; rlight.light_energy = 3.0)
		await C.wait(0.12)
		lamp.emission_energy_multiplier = 0.5; rlight.light_energy = 0.0
		await C.wait(0.35)
	await C.say("outro_05", 0.5)
	# 4. Grudd on the radio: confused, then outraged, then back to the script
	C.live_label.text = "●  LIVE BROADCAST  ·  ALL FREQUENCIES"
	C.tw(C, "live_a", 1.0, 0.3)
	lamp.emission_energy_multiplier = 6.0; rlight.light_energy = 3.0
	if dish_glow: dish_glow.emission = Color(1, 0.45, 0.1)
	C.cut(rp + Vector3(-1.2, 0.2, 2.6), rp, 34.0)
	C.focus(0.8)
	await C.say("cs_out_grudd_1", 0.3)
	C.tw(C, "shake", 0.6, 0.1)
	C.cut(rp + Vector3(-0.6, 0.0, 1.5), rp, 30.0)
	C.setv(C, "cam_roll", -0.12)
	await C.say("cs_out_grudd_2", 0.4)
	C.setv(C, "cam_roll", 0.0)
	# Dodger's eye flickers orange through the rest of it
	C.cut(dodger.global_position + Vector3(-0.5, 0.05, -1.3), dodger.global_position, 30.0)
	C.move(dodger.global_position + Vector3(-0.35, 0.05, -0.95), dodger.global_position, 6.0)
	C.focus(1.0)
	C.tw(dodger, "orange", 1.0, 0.6)
	await C.say("sky_outro_grudd_1", 0.4)
	C.cut(Vector3(-4, 2.2, c.z + 8), mast + Vector3(0, 1, 0), 14.0)
	C.focus(0.0)
	await C.say("outro_07", 0.4)
	C.cut(rp + Vector3(-1.4, 0.4, 2.2), rp, 36.0)
	await C.say("outro_08", 0.6)
	C.tw(C, "live_a", 0.0, 0.5)
	lamp.emission_energy_multiplier = 0.5; rlight.light_energy = 0.0
	if dish_glow: dish_glow.emission = dish_col
	C.fx(func(): Snd.at("explode_small", rp, -10); FX.sparks(rp, Color(1, 0.6, 0.2), 10, 3.0))
	C.cast.erase("grudd")
	# 5. "Your eye's doing the orange thing again."
	C.cut(c + Vector3(-1.2, 1.4, -1.0), c + Vector3(0.4, 1.4, 1.1), 40.0)
	C.focus(0.6)
	vesk.look_target = dodger; dodger.look_target = vesk
	await C.say("sky_outro_eye_1", 0.3)
	C.cut(dodger.global_position + Vector3(-0.4, 0.0, -1.1), dodger.global_position, 32.0)
	C.focus(1.0)
	await C.say("sky_outro_eye_2", 0.2)
	C.tw(dodger, "orange", 0.0, 0.4)
	dodger.emote("shake")
	await C.wait(0.8)
	# 6. the chimney remark, and the road ahead
	C.cut(c + Vector3(2.2, 1.6, -2.6), c + Vector3(0.3, 1.25, 1), 42.0)
	C.focus(0.4)
	vesk.gesture("cs_talk2", 0.3, "idle")
	await C.say("cs_out_vesk_1", 0.4)
	C.tw(dodger, "global_position", dodger.global_position + Vector3(0.3, 0.4, -0.3), 0.6)
	dodger.emote("hop")
	await C.say("outro_10", 0.4)
	# 7. Nana Quill calls in with the coordinates
	C.fx(func(): Snd.play("ui_select", -4))
	await C.wait(0.35)
	C.fx(func(): Snd.play("ui_select", -4))
	C.call_text.text = "INCOMING CALL\nNANA QUILL"
	C.tw(C, "call_a", 1.0, 0.4)
	C.tw(dodger, "eye_color", Color(0.5, 1, 0.55), 0.3)
	C.cut(c + Vector3(3.6, 2.0, -3.4), c + Vector3(0.4, 1.3, 1), 44.0)
	C.focus(0.0)
	C.move(c + Vector3(-1.5, 2.1, -4.4), c + Vector3(0.4, 1.3, 1), 26.0)
	await C.wait(0.6)
	await C.say("sky_outro_nana_1", 0.3)
	vesk.gesture("cs_scratch", 0.3, "idle")
	await C.say("sky_outro_nana_2", 0.3)
	await C.say("sky_outro_nana_3", 0.3)
	C.call_text.text = "SHARD 1 DECODED\n> DUSTVEIN GULCH"
	C.fx(func(): Snd.play("checkpoint", -6))
	await C.say("sky_outro_nana_4", 0.3)
	await C.say("sky_outro_nana_5", 0.2)
	await C.say("sky_outro_nana_6", 0.6)
	C.tw(C, "call_a", 0.0, 0.5)
	C.tw(dodger, "eye_color", C.DroneActor.EYE, 0.4)
	# 8. "Back to my chair?" "Road trip!"
	C.cut(c + Vector3(-0.6, 1.1, -1.5), c + Vector3(0.1, 1.05, 1), 38.0)
	C.focus(0.8)
	await C.say("outro_11", 0.3)
	C.cut(dodger.global_position + Vector3(0.6, 0.2, -1.4), dodger.global_position, 34.0)
	C.tw(dodger, "global_position", dodger.global_position + Vector3(0, 0.6, 0), 0.3, 0.2, Tween.TRANS_BACK, Tween.EASE_OUT)
	dodger.emote("spin")
	await C.say("outro_12", 0.4)
	C.focus(0.0)
	# 9. the old hauler drops in on autopilot, Vesk climbs aboard
	ship.visible = true
	Props.ship_jets(ship, 4.0)
	var pad := c + Vector3(0, 0, 9)
	C.cut(c + Vector3(-7, 1.3, -3), pad + Vector3(0, 3, 0), 52.0)
	C.tw(ship, "global_position", pad, 4.0, 0.0, Tween.TRANS_QUAD, Tween.EASE_OUT)
	vesk.look_target = ship; dodger.look_target = ship
	C.fx(func(): Snd.at("crane_move", pad, 0))
	await C.wait(4.0)
	C.fx(func(): FX.ring(pad + Vector3(0, 0.1, 0), Color(0.6, 0.9, 1.0), 2.5); Snd.at("land", pad, 0); FX.shake(0.3))
	Props.ship_jets(ship, 0.8)
	vesk.look_target = null; dodger.look_target = null
	var w: float = C.walk(vesk, pad + Vector3(0, 0, -2.6), 4.5)
	C.tw(dodger, "global_position", pad + Vector3(1, 3.2, -1), 1.6)
	await C.wait(w)
	vesk.play("jump", 0.1)
	C.tw(vesk, "global_position", pad + Vector3(0, 2.4, -1.0), 0.45, 0.0, Tween.TRANS_QUAD, Tween.EASE_OUT)
	C.fx(func(): Snd.at("jump", vesk.global_position, -4))
	await C.wait(0.45)
	vesk.visible = false
	C.tw(dodger, "global_position", pad + Vector3(0, 2.6, 0), 0.5)
	await C.wait(0.5)
	dodger.visible = false
	await C.wait(0.6)
	# 10. liftoff... with the handbrake on
	C.cut(c + Vector3(6, 0.8, -2), pad + Vector3(0, 3, 0), 50.0)
	Props.ship_jets(ship, 6.0)
	C.fx(func(): Snd.at("crane_warn", pad, -2); FX.puff(pad, Color(0.8, 0.8, 0.85)))
	C.tw(ship, "global_position", pad + Vector3(0, 2.5, 0), 1.0, 0.0, Tween.TRANS_QUAD, Tween.EASE_OUT)
	var body: Node3D = ship.find_child("Body", true, false)
	for i in 4:
		C.tw(body, "rotation:x", 0.2 if i % 2 == 0 else -0.12, 0.25)
		C.tw(C, "shake", 0.5, 0.05)
		await C.wait(0.3)
	C.tw(body, "rotation:x", 0.0, 0.3)
	var lo: float = C.say_async("sky_outro_liftoff_1")
	C.tw(ship, "global_position", pad + Vector3(0, 3, 3), 0.4, 0.0, Tween.TRANS_QUAD, Tween.EASE_OUT)
	C.tw(ship, "global_position", pad + Vector3(0, 2.8, 0.5), 0.35, 0.45, Tween.TRANS_BACK, Tween.EASE_OUT)
	await C.wait(maxf(lo, 1.4) + 0.3)
	C.fx(func(): FX.sparks(pad + Vector3(0, 2.5, -2.5), Color(1, 0.7, 0.3), 18, 6.0); Snd.at("dash", pad, 0))
	Props.ship_jets(ship, 9.0)
	C.cut(c + Vector3(0, 1.2, -6), pad + Vector3(0, 4, 0), 50.0)
	C.look_node = ship; C.look_off = Vector3(0, 2, 0)
	C.tw(ship, "global_position", pad + Vector3(-20, 30, 90), 4.0, 0.0, Tween.TRANS_QUAD, Tween.EASE_IN)
	C.tw(ship, "rotation:x", -0.35, 1.5)
	C.tw(C, "cam_fov", 28.0, 4.0)
	await C.wait(1.5)
	await C.say("outro_13", 0.4)
	C.tw(C, "fade", 1.0, 1.2)
	await C.wait(1.3)
	C.look_node = null
	await _stinger()
	# back in the yard for a last look around
	if Game.player: Game.player.global_position = c + Vector3(0, 0.1, 1)

## Meanwhile, in an office with no windows...
func _stinger() -> void:
	var office: Node3D = C.actor(Props.office(), OFFICE_AT, 0.0)
	var desk: Vector3 = OFFICE_AT + office.get_meta("desk_pos")
	var scr: StandardMaterial3D = office.get_meta("screen_mat")
	# Grudd behind his desk, back to us at first, staring at the monitor
	var grudd: Node3D = C.make_grudd(desk + Vector3(0, 0, -1.6), PI, 3.6, false)
	C.sun_dim(true)
	await C.wait(0.2)
	await C.say("cs_tease_narr_1", 0.2)
	C.cut(OFFICE_AT + Vector3(5.5, 2.2, 5.0), desk + Vector3(0, 2.4, -1.0), 48.0)
	C.move(OFFICE_AT + Vector3(3.5, 2.4, 3.0), desk + Vector3(0, 2.6, -1.2), 9.0, 42.0)
	C.tw(C, "fade", 0.0, 0.8)
	await C.wait(1.4)
	# close on the monitor: static and a blurry orange blob that is definitely Vesk
	C.cut(desk + Vector3(1.4, 2.4, 0.9), desk + Vector3(0.4, 2.3, -0.4), 30.0)
	C.focus(0.8)
	for i in 6:
		C.tw(scr, "emission_energy_multiplier", 2.0 if i % 2 == 0 else 0.8, 0.1, i * 0.15)
	scr.emission = Color(1, 0.6, 0.25)
	var l1: float = C.say_async("cs_tease_grudd_1")
	await C.wait(l1 * 0.5)
	# he turns around, slowly
	C.focus(0.0)
	C.cut(desk + Vector3(0, 2.2, 3.2), grudd.global_position + Vector3(0, 2.9, 0), 40.0)
	C.move(desk + Vector3(0, 2.1, 2.4), grudd.global_position + Vector3(0, 2.9, 0), 6.0, 36.0)
	C.tw(grudd, "rotation:y", 0.0, 1.6, 0.0, Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	await C.wait(l1 * 0.5 + 0.4)
	grudd.gesture("clipboard")
	C.focus(0.7)
	await C.say("cs_tease_grudd_2", 0.4)
	# "Print the posters! We're HIRING!"
	C.cut(desk + Vector3(0.6, 2.4, 1.6), grudd.global_position + Vector3(0, 3.0, 0), 30.0)
	C.focus(0.0)
	grudd.gesture("fist")
	C.tw(C, "shake", 0.8, 0.05, 0.4)
	await C.say("cs_tease_grudd_3", 0.2)
	C.fx(func(): Snd.play("cutscenes_poster_slam", -2, 0.0); Snd.play("crane_slam", -12))
	C.tw(C, "poster_a", 1.0, 0.18, 0.0, Tween.TRANS_BACK, Tween.EASE_OUT)
	await C.wait(2.6)
	C.tw(C, "fade", 1.0, 0.5)
	await C.wait(0.5)
	C.sun_dim(false)
	C.setv(C, "poster_a", 0.0)
	# next time on...
	C.tw(C, "next_a", 1.0, 0.6)
	C.fx(func(): Snd.music("", 0.5); Snd.play("cutscenes_next_jingle", -4, 0.0))
	await C.wait(0.6)
	await C.say("cs_tease_narr_2", 1.2)
	C.tw(C, "next_a", 0.0, 0.6)
	await C.wait(0.7)
	# end card
	C.card_title.text = "SKYHARBOR  ·  COMPLETE"
	C.card_sub.text = "Shard 1 of the signal decoded.   Next stop: Dustvein Gulch"
	C.tw(C, "card_a", 1.0, 0.8)
	await C.wait(4.0)
	C.tw(C, "card_a", 0.0, 0.8)
	await C.wait(0.9)
