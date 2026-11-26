extends Node
## HUD preview: draws the real HUD over a still screenshot with stand-in game state, so HUD changes
## can be checked in seconds without loading Skyharbor.
##   godot --path . res://tools/hud_preview.tscn -- --bg=<image.png> --state=explore|boss|lowhull --shot=out.png --frames=40
## Leave out --shot to look at it live.

const Hud := preload("res://scripts/hud.gd")

class MockCombat extends Node3D:
	signal nuts_changed(total: int)
	signal hull_changed(hull: int, healed: bool)
	signal hit_marker(kill: bool)
	signal weapon_changed(id: String)
	signal ammo_changed(id: String, ammo: int, max_ammo: int)
	signal weapon_xp(id: String, level: int, frac: float)
	signal weapon_level_up(id: String, level: int)
	const MAX_HULL := 8
	const WEAPONS := {
		"arc_lancer": { name = "ARC LANCER", v5 = "ARC STORM", color = Color(0.45, 0.95, 1.0) },
		"scatter_bloom": { name = "SCATTER BLOOM", v5 = "FULL BLOOM", color = Color(1.0, 0.45, 0.65) },
		"thump_lobber": { name = "THUMP LOBBER", v5 = "THUMP CLUSTER", color = Color(0.5, 1.0, 0.45) },
		"seeker_hive": { name = "SEEKER HIVE", v5 = "QUEEN HIVE", color = Color(1.0, 0.8, 0.25) },
	}
	var current := "arc_lancer"
	var hull := 8
	var heat := 0.0
	var overheated := false
	var lv := 2
	var xp := 0.4
	var am := 24
	var mx := 28
	func weapon_name(id: String) -> String: return WEAPONS[id].name
	func weapon_color(id: String) -> Color: return WEAPONS[id].color
	func level(_id: String) -> int: return lv
	func xp_frac(_id: String) -> float: return xp
	func uses_ammo(id: String) -> bool: return id != "arc_lancer"
	func ammo(_id: String) -> int: return am
	func max_ammo(_id: String) -> int: return mx

class MockPlayer extends CharacterBody3D:
	var hook_target: Node3D = null
	var using_pad := false
	var jumps := 0
	var dash_cd := 0.0

class MockLevel extends Node3D:
	var pickup_spots := [
		{ kind = "washer", id = "w1" }, { kind = "washer", id = "w2" }, { kind = "washer", id = "w3" },
		{ kind = "page", id = "p1" }, { kind = "page", id = "p2" }, { kind = "page", id = "p3" }, { kind = "page", id = "p4" }, { kind = "page", id = "p5" },
	]

var hud: CanvasLayer
var combat: MockCombat
var player: MockPlayer
var state := "explore"

func _ready() -> void:
	var bg_path := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--bg="): bg_path = a.substr(5)
		elif a.begins_with("--state="): state = a.substr(8)
	var layer := CanvasLayer.new(); layer.layer = -1; add_child(layer)
	var bg := TextureRect.new(); bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	if bg_path != "":
		var img := Image.load_from_file(bg_path)
		if img: bg.texture = ImageTexture.create_from_image(img)
	else:
		var g := GradientTexture2D.new(); g.fill_to = Vector2(0, 1)
		var gr := Gradient.new(); gr.colors = PackedColorArray([Color(0.55, 0.7, 0.95), Color(0.95, 0.75, 0.55)]); g.gradient = gr
		bg.texture = g
	layer.add_child(bg)
	combat = MockCombat.new(); add_child(combat)
	player = MockPlayer.new(); add_child(player)
	var lvl := MockLevel.new(); add_child(lvl)
	Game.level = lvl; Game.combat = combat; Game.player = player
	Game.data.collected = {"skyharbor:washer:w1": true, "skyharbor:page:p1": true, "skyharbor:page:p2": true}
	hud = Hud.new(); hud.combat = combat; hud.player = player; add_child(hud)
	Game.hud = hud
	await get_tree().process_frame
	combat.nuts_changed.emit(1240)
	match state:
		"boss":
			combat.current = "scatter_bloom"; combat.lv = 3; combat.xp = 0.65; combat.am = 6; combat.mx = 32
			combat.hull = 5; combat.hull_changed.emit(5, true)
			Game.objective_set.emit("boss", "Scrap the Crane Bot")
			Game.boss_started.emit("CRANE BOT  MK-II")
			await get_tree().create_timer(0.1).timeout
			Game.boss_health.emit("CRANE BOT  MK-II", 0.72)
			await get_tree().create_timer(0.1).timeout
			Game.boss_health.emit("CRANE BOT  MK-II", 0.58)
			player.jumps = 2; player.dash_cd = 0.3
			Snd.line_started.emit("x", "grudd", "You call that a dent? My crane's taken worse from a pigeon!")
			combat.hit_marker.emit(false)
		"lowhull":
			combat.current = "seeker_hive"; combat.lv = 5; combat.xp = 1.0; combat.am = 0; combat.mx = 55
			combat.hull = 2; combat.hull_changed.emit(2, false)
			Game.objective_set.emit("yard", "Get through the Holding Pens")
			hud.show_banner("THE YARD", "Clear the holding pens", Color(1, 0.75, 0.3))
			player.using_pad = true
			hud.show_prompt("Y   SHOP AT GIZMART")
		_:
			combat.heat = 0.55
			Game.objective_set.emit("docks", "Find Dodger on top of the scrap pile (WASD to run, Space to jump, hold it to go higher)")
			combat.nuts_changed.emit(1265)
			hud.toast("LUCKY WASHER  1/3", "Lucky! Trade washers for cosmetics and cheats.", Color(1, 0.82, 0.3))
			hud.toast_small("+12 SEEKER HIVE AMMO", Color(1.0, 0.8, 0.25))
			hud.show_prompt("E   SWING")
