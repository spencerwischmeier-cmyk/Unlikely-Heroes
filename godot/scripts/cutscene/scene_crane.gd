extends RefCounted
## CRANE INTRO: Vesk and Dodger step into the Crane Yard. A big empty yard with one big empty spot.
## A warning horn, a shadow, and the real Crane Bot (story.gd's boss) drops out of the sky onto its
## mark, roars, and gets its orders from Grudd over the yard loudspeakers. Boss title card, then
## straight into the fight. Anchored on the arena island rect and the player's entry point.

var C: Node

func run() -> void:
	var r: Rect2 = C.island_rect("arena", Rect2(-18, -112, 36, 30))
	var c := Vector3(r.get_center().x, 0, r.get_center().y)
	var story: Node = Game.story
	var boss_pos := Vector3(0, 0, -102)
	if story and story.get("boss_pos") is Vector3: boss_pos = story.boss_pos
	var p: Vector3 = Game.player.global_position if Game.player else Vector3(c.x, 0.1, r.end.y - 2)
	if not r.grow(2.0).has_point(Vector2(p.x, p.z)): p = Vector3(c.x, 0.1, r.end.y - 2)
	var fwd := Vector3(boss_pos.x - p.x, 0, boss_pos.z - p.z).normalized()
	var side := fwd.cross(Vector3.UP).normalized()
	# a few steps in from where the player stopped, so the drop has room
	var stand := p + fwd * 1.5
	var vesk: Node3D = C.make_vesk(stand - fwd * 2.5, atan2(fwd.x, fwd.z))
	var dodger: Node3D = C.make_dodger(stand + side * 1.1 + Vector3(0, 1.8, 0) - fwd * 2.8, atan2(fwd.x, fwd.z))
	var boss: Node3D = story.boss if story and is_instance_valid(story.get("boss")) else null
	var preview: Node3D = null
	if boss == null and C.start_args.has("cut"):
		# --cut=crane_intro preview (no story running): a stand-in Crane Bot
		preview = load("res://scripts/cranebot.gd").new(); preview.combat = Game.combat; preview.player = Game.player
		C.actor(preview, Vector3.ZERO); boss = preview

	# 1. establishing: high over the yard, craning down toward the heroes walking in
	C.cut(c + Vector3(-14, 16, 10), c + Vector3(0, 0, 4), 50.0)
	C.move(stand - fwd * 6 + side * 4 + Vector3(0, 3.2, 0), boss_pos + Vector3(0, 0.5, 0), 7.5, 46.0, Tween.TRANS_CUBIC)
	C.tw(C, "fade", 0.0, 0.8)
	C.walk(vesk, stand, 1.6)
	C.tw(dodger, "global_position", stand + side * 1.1 + Vector3(0, 1.8, 0), 2.5)
	C.fx(func(): Snd.loop("wind_loop", true, -10))
	await C.wait(1.0)
	await C.say("cs_ci_dodger_1", 0.3)
	vesk.play("idle", 0.3)
	# 2. over the shoulder: the empty spot, in focus far away
	C.ots(vesk, boss_pos + Vector3(0, 0.6, 0), 1.0, 38.0, 1.6, 1.7)
	C.focus(0.8, stand.distance_to(boss_pos))
	vesk.look_point = boss_pos
	await C.say("cs_ci_vesk_1", 0.4)
	# 3. the horn. A shadow ring on the ground. Look up.
	C.focus(0.0)
	if story and story.has_method("drop_boss") and preview == null: story.drop_boss()
	elif preview: preview.spawn(boss_pos, r)
	var low := boss_pos + (stand - boss_pos).normalized() * 7.0 + side * 3.0 + Vector3(0, 0.4, 0)
	C.cut(low, boss_pos + Vector3(0, 2.0, 0), 56.0)
	vesk.look_point = boss_pos + Vector3(0, 8, 0)
	dodger.look_target = null
	dodger.act("shock")
	C.fx(func(): Snd.play("cutscenes_drop_whoosh", -2, 0.0))
	await C.wait(0.9)
	if boss:
		C.look_node = boss; C.look_off = Vector3(0, 2.0, 0)
	C.tw(C, "cam_fov", 62.0, 0.8)
	await C.wait(1.0)
	# it lands
	C.tw(C, "shake", 1.4, 0.05)
	C.tw(C, "white", 0.4, 0.05); C.tw(C, "white", 0.0, 0.4, 0.06)
	await C.wait(0.6)
	# 4. dust settles: low hero angle, slow push in on the cab while it roars
	C.look_node = null
	var cab := boss_pos + Vector3(0, 3.2, 0)
	if boss and boss.has_method("center"): cab = boss.center()
	var hero := boss_pos + (stand - boss_pos).normalized() * 9.0 - side * 2.0 + Vector3(0, 0.5, 0)
	C.cut(hero, cab + Vector3(0, 0.6, 0), 44.0)
	C.move(hero + (boss_pos - hero).normalized() * 2.2, cab + Vector3(0, 0.8, 0), 3.2, 36.0, Tween.TRANS_CUBIC, Tween.EASE_OUT)
	C.focus(0.5)
	await C.wait(0.9)
	C.show_boss("CRANE BOT", "Heavy lifter. Unit Seven. Hates weekends.", 2.6)
	C.fx(func(): Snd.play("cutscenes_boss_sting", -3, 0.0))
	await C.wait(2.6)
	C.focus(0.0)
	# 5. "That crane is looking at us."
	var dpos: Vector3 = dodger.global_position
	C.cut(dpos + fwd * 1.2 - side * 0.3, dpos, 32.0)
	C.focus(1.0)
	vesk.look_point = Vector3.INF
	await C.say("yard_intro_1", 0.2)
	C.cut(stand + fwd * 1.4 + side * 0.4 + Vector3(0, 1.55, 0), stand + Vector3(0, 1.45, 0), 34.0)
	vesk.look_target = dodger
	await C.say("yard_intro_2", 0.2)
	C.cut(stand - fwd * 2.2 - side * 1.2 + Vector3(0, 1.9, 0), cab, 44.0)
	C.focus(0.0)
	dodger.act("shock")
	vesk.look_target = null; vesk.look_point = cab
	await C.say("yard_intro_3", 0.3)
	# 6. Grudd on the yard loudspeakers. Dodger's eye flickers again.
	C.live_label.text = "●  YARD PA  ·  FOREMAN'S OFFICE"
	C.tw(C, "live_a", 1.0, 0.3)
	C.cut(stand + fwd * 2.5 + side * 2.6 + Vector3(0, 1.2, 0), stand + side * 0.5 + Vector3(0, 1.5, 0), 40.0)
	C.move(stand + fwd * 2.2 + side * 2.2 + Vector3(0, 1.3, 0), stand + side * 0.5 + Vector3(0, 1.5, 0), 7.0)
	C.focus(0.4)
	C.auto_look = false
	vesk.look_point = boss_pos + Vector3(0, 6, 0); dodger.look_target = null
	C.tw(dodger, "orange", 0.8, 0.4)
	await C.say("cs_ci_grudd_1", 0.3)
	C.tw(dodger, "orange", 0.0, 0.3)
	C.tw(C, "live_a", 0.0, 0.4)
	C.auto_look = true
	dodger.act("shake")
	vesk.look_point = Vector3.INF
	await C.say("cs_ci_dodger_2", 0.3)
	# 7. "I'm retired, you know."
	C.cut(stand + fwd * 1.3 - side * 0.5 + Vector3(0, 1.5, 0), stand + Vector3(0, 1.4, 0), 32.0)
	C.focus(1.0)
	vesk.look_target = null; vesk.look_point = cab
	vesk.gesture("cs_stomp", 0.25, "idle")
	await C.say("cs_ci_vesk_2", 0.3)
	dodger.act("spin")
	C.cut(stand - fwd * 3.0 + side * 1.8 + Vector3(0, 2.0, 0), boss_pos + Vector3(0, 1.5, 0), 48.0)
	C.focus(0.0)
	await C.say("cs_ci_dodger_3", 0.2)
	# 8. hand over: behind Vesk, the crane in frame
	vesk.look_point = Vector3.INF
	if Game.player:
		Game.player.global_position = stand + Vector3(0, 0.05, 0)
		Game.player.rotation.y = atan2(fwd.x, fwd.z)
	C.cut(stand - fwd * 4.5 + Vector3(0, 2.4, 0), boss_pos + Vector3(0, 1.5, 0), 55.0)
	await C.wait(0.3)
