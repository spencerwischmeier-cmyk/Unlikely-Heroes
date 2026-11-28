extends Node3D
## Builds the game: lighting and sky, the Skyharbor level, Vesk, the camera and the HUD.

const Level := preload("res://scripts/level_skyharbor.gd")
const Player := preload("res://scripts/player.gd")
const CameraRig := preload("res://scripts/camera_rig.gd")
const Combat := preload("res://scripts/combat.gd")
const Hud := preload("res://scripts/hud.gd")
const Roller := preload("res://scripts/enemy_roller.gd")
const Hornet := preload("res://scripts/enemy_hornet.gd")
const Story := preload("res://scripts/story.gd")
var story: Node
var combat: Node3D
var hud: CanvasLayer

var env: Environment
var sun: DirectionalLight3D
var level: Node3D
var player: CharacterBody3D
var cam: Node3D

func _ready() -> void:
	_build_environment()
	level = Level.new()
	level.name = "Level"
	add_child(level)
	player = Player.new()
	player.name = "Vesk"
	player.level = level
	add_child(player)
	player.global_position = level.start_pos
	player.respawn_pos = level.start_pos
	cam = CameraRig.new()
	cam.target = player
	add_child(cam)
	player.cam = cam
	combat = Combat.new(); combat.name = "Combat"; combat.player = player
	add_child(combat)
	player.combat = combat
	hud = Hud.new(); hud.combat = combat; hud.player = player
	add_child(hud)
	Game.main = self; Game.player = player; Game.cam = cam; Game.combat = combat; Game.level = level; Game.hud = hud
	Game.add_nuts(0)
	_install_systems()
	story = Story.new(); story.name = "Story"; add_child(story); Game.story = story
	if not OS.get_cmdline_user_args().has("--no-bots"): story.start()
	Snd.music("skyharbor", 3.0)
	Snd.loop("wind_loop", true, -16)
	Snd.loop("city_loop", true, -20)
	cam.yaw = level.start_yaw
	player.face_yaw = level.start_yaw
	# browsers only allow pointer lock from a click or key press (asking at boot threw an exception);
	# there the first click in the game captures the mouse (camera_rig.gd)
	if not OS.get_cmdline_user_args().has("--no-capture") and not OS.has_feature("web"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _build_environment() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/sky_skyharbor.gdshader")
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.ambient_light_sky_contribution = 0.85
	env.ambient_light_color = Color(0.62, 0.7, 0.9)
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 0.9
	env.tonemap_white = 6.0
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 2.0
	env.ssao_light_affect = 0.15
	env.ssil_enabled = true
	env.sdfgi_enabled = true
	env.sdfgi_use_occlusion = true
	env.sdfgi_energy = 1.25
	env.sdfgi_bounce_feedback = 0.6
	env.sdfgi_cascades = 4
	env.sdfgi_min_cell_size = 0.2
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.12
	env.glow_hdr_threshold = 1.0
	env.glow_strength = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.93, 0.84, 0.74)
	env.fog_sun_scatter = 0.15
	env.fog_depth_begin = 90.0
	env.fog_depth_end = 900.0
	env.fog_depth_curve = 1.6
	env.fog_aerial_perspective = 0.85
	env.fog_sky_affect = 0.0
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.0014
	env.volumetric_fog_albedo = Color(1.0, 0.92, 0.82)
	env.volumetric_fog_anisotropy = 0.7
	env.volumetric_fog_sky_affect = 0.0
	env.volumetric_fog_length = 120.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.18
	env.adjustment_contrast = 1.14
	env.adjustment_color_correction = _grade()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.84, 0.66)
	sun.light_energy = 2.6
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.shadow_normal_bias = 1.2
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_max_distance = 160.0
	sun.light_volumetric_fog_energy = 1.4
	sun.rotation_degrees = Vector3(-30, 150, 0)
	add_child(sun)
	# soft cool fill from the opposite side, standing in for sky bounce in the shadows
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.55, 0.68, 0.95)
	fill.light_energy = 0.35
	fill.shadow_enabled = false
	fill.light_specular = 0.1
	fill.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	fill.rotation_degrees = Vector3(-50, -30, 0)
	add_child(fill)

## A gentle golden-hour grade: lifted warm highlights, slightly cool shadows.
func _grade() -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.35, 0.7, 1.0])
	g.colors = PackedColorArray([Color(0.04, 0.05, 0.12), Color(0.33, 0.34, 0.4), Color(0.74, 0.7, 0.64), Color(1.0, 0.97, 0.9)])
	var t := GradientTexture1D.new(); t.gradient = g; t.width = 256
	return t

func spawn_bot(kind: String, pos: Vector3, zone := Rect2()) -> Node3D:
	if kind == "crew": return load("res://scripts/enemy_crew.gd").spawn(self, combat, player, pos, zone)
	# Plated Roller: an armoured roller (`--no-plated` spawns a plain one instead)
	var plated := kind == "plated" and not OS.get_cmdline_user_args().has("--no-plated")
	if kind == "plated": kind = "roller"
	var b: Node3D = (Roller if kind == "roller" else Hornet).new()
	b.combat = combat; b.player = player; b.zone = zone
	if plated: b.set("plated", true)
	add_child(b)
	b.global_position = pos + (Vector3(0, 6, 0) if kind == "roller" else Vector3(0, 12, 0))
	FX.ring(pos + Vector3(0, 0.05, 0), Color(1, 0.35, 0.25))
	Snd.at("bot_spawn", pos, -2)
	return b

## Every script in res://scripts/systems/ is added as a child node at start (after Game's refs are set).
## Add new gameplay systems there instead of editing this file.
func _install_systems() -> void:
	var dir := "res://scripts/systems/"
	var names := Array(DirAccess.get_files_at(dir)).filter(func(f): return f.ends_with(".gd"))
	names.sort()
	for f in names:
		var n: Node = load(dir + f).new(); n.name = f.get_basename().capitalize().replace(" ", ""); add_child(n)

## Cutscene support hook: return true once a cutscene player is installed (story waits for it).
func has_cutscenes() -> bool:
	return true

func _process(dt: float) -> void:
	# hit-stop and camera shake requested by effects
	if FX.hitstop > 0.0:
		Engine.time_scale = 0.06
		FX.hitstop -= dt / maxf(Engine.time_scale, 0.01)
		if FX.hitstop <= 0.0: Engine.time_scale = 1.0 if FX.slow_t <= 0.0 else FX.slow_scale
	elif FX.slow_t > 0.0:
		Engine.time_scale = FX.slow_scale
		FX.slow_t -= dt / maxf(Engine.time_scale, 0.01)
		if FX.slow_t <= 0.0: Engine.time_scale = 1.0
	if FX.shake_request > 0.0:
		cam.shake = maxf(cam.shake, FX.shake_request); FX.shake_request = 0.0
