extends Node
## Headless test for the weapon / crate / collectible systems. Only runs with --systems-test:
## spawns rollers in front of Vesk and fires each weapon at them through combat.try_fire, breaks
## a crate, picks up a test washer and prints a report. Add --reload-test to also reload the scene.

var on := false
var t := 0.0
var phase := -1
var log_kills := {}
var spawned := 0

func _ready() -> void:
	if OS.get_cmdline_user_args().has("--title-test"): _title_test()
	on = OS.get_cmdline_user_args().has("--systems-test")
	if not on: return
	Game.bot_killed.connect(func(b, _p, k): log_kills[Game.combat.current] = log_kills.get(Game.combat.current, 0) + 1; print("[sys-test] killed ", k, " with ", Game.combat.current))
	Game.combat.weapon_level_up.connect(func(id, lv): print("[sys-test] level up ", id, " V", lv))
	if Game.player: Game.player.process_mode = Node.PROCESS_MODE_INHERIT

func _physics_process(dt: float) -> void:
	if not on: return
	t += dt
	var c := Game.combat
	var p: Node3D = Game.player
	c.invuln = 99.0
	var f := Vector3(sin(p.face_yaw), 0, cos(p.face_yaw))
	var want := int(t / 3.0)
	if want != phase and want < 5:
		phase = want
		if phase < 4:
			var id: String = c.ORDER[phase]
			Game.data.unlocked[id] = true
			c.equip(id)
			print("[sys-test] phase ", phase, " weapon ", c.current, " ammo ", c.ammo(id), "/", c.max_ammo(id), " lv ", c.level(id))
			for i in 3:
				Game.main.spawn_bot("roller" if i < 2 else "hornet", p.global_position + f * (9.0 + i * 1.5) + Vector3(-f.z, 0, f.x) * (i - 1) * 2.0)
		else:
			var cr = get_parent().get_node_or_null("Crates")
			var crate: Node3D = cr.spawn(p.global_position + f * 3.0, true) if cr else null
			get_tree().create_timer(0.3).timeout.connect(func():
				if crate: print("[sys-test] crate hit kill=", crate.damage(5.0, crate.center(), f)))
	if phase >= 0 and phase < 4:
		var tg: Node3D = c._seek_target(p.global_position, f, 30.0, [])
		var muzzle: Vector3 = p._muzzle()
		if tg: c.try_fire(dt, true, muzzle, tg.center(), (tg.center() - muzzle).normalized())
	if t > 16.0:
		on = false
		var rep := {}
		for id in c.ORDER: rep[id] = { lv = c.level(id), xp = c.wdata[id].xp, ammo = c.ammo(id) }
		print("[sys-test] kills by weapon ", log_kills)
		print("[sys-test] weapons ", rep)
		print("[sys-test] nuts ", Game.nuts(), " pickups left ", c.pickups.size())
		print("[sys-test] held model visible: ", p.weapon_models.get(c.current).visible if p.weapon_models.has(c.current) else "lancer")
		if OS.get_cmdline_user_args().has("--reload-test") and not Game.has_meta("reloaded"):
			Game.set_meta("reloaded", true)
			print("[sys-test] reloading scene")
			get_tree().reload_current_scene()
		else:
			get_tree().quit()

## --title-test (with --title): starts a new game from the title, then pauses / unpauses and quits.
func _title_test() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().create_timer(1.0).timeout
	var m := get_parent().get_node("Menus")
	var cs := get_parent().get_node("Cutscenes")
	print("[title-test] state=", m.state, " paused=", get_tree().paused, " held=", m.held_intro, " cut playing='", cs.playing, "'")
	m._start(false)
	await get_tree().create_timer(0.5).timeout
	print("[title-test] after start: state=", m.state, " paused=", get_tree().paused, " cut playing='", cs.playing, "' locked=", Game.input_locked)
	cs._skip()
	await get_tree().create_timer(3.0).timeout
	print("[title-test] after skip: cut playing='", cs.playing, "' locked=", Game.input_locked, " objective story index=", Game.story.index)
	m.open_pause()
	print("[title-test] paused: state=", m.state, " tree paused=", get_tree().paused)
	m._open_settings(); m._set_opt("music", 40.0); m._close_settings()
	print("[title-test] music bus db=", AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")), " sfx bus of pool[0]=", Snd.pool[0].bus)
	m.close_pause()
	print("[title-test] resumed: state=", m.state, " tree paused=", get_tree().paused)
	get_tree().quit()

# ---------------------------------------------------------------- --multi-shot=<prefix>
## Saves several screenshots in one run: <prefix>_crate.png (a crate breaking, jet flames, HUD),
## _wheel.png, _pause.png, _settings.png and _title.png. Run with --no-title --no-capture --no-bots.
var shot_prefix := ""
var frame := 0
var test_crates: Array = []

func _process(_dt: float) -> void:
	if shot_prefix == "":
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--multi-shot="): shot_prefix = a.substr(13); process_mode = Node.PROCESS_MODE_ALWAYS
		if shot_prefix == "": return
	frame += 1
	var p = Game.player
	var f := Vector3(sin(p.face_yaw), 0, cos(p.face_yaw))
	var side := Vector3(-f.z, 0, f.x)
	match frame:
		40:
			var cr = get_parent().get_node_or_null("Crates")
			test_crates = [cr.spawn(p.global_position + f * 3.4 + side * 0.8, true, 0.3), cr.spawn(p.global_position + f * 3.0 - side * 1.6, false, 0.7)]
			p.force_jets = 0.85
			Game.hud.toast("LUCKY WASHER  1/3", "Lucky! Trade washers for cosmetics and cheats.", Color(1, 0.82, 0.3), 30.0)
		150:
			for c in test_crates: if is_instance_valid(c): c.damage(9.0, c.center(), f)
		156: _cap("crate")
		170:
			get_parent().get_node("Weapons").hold_debug = true
		215:
			get_parent().get_node("Weapons").point = Vector2(150, 40)
		240: _cap("wheel")
		245:
			get_parent().get_node("Weapons").hold_debug = false
		260: get_parent().get_node("Menus").open_pause()
		275: _cap("pause")
		280: get_parent().get_node("Menus")._open_settings()
		295: _cap("settings")
		300:
			var m = get_parent().get_node("Menus")
			m._close_settings(); m.close_pause(); m._show_title()
		360: _cap("title")
		365: get_tree().quit()

func _cap(n: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s_%s.png" % [shot_prefix, n])
	print("[multi-shot] saved ", n)
