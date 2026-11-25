extends Node3D
## Art kit lineup for checking the props. Run:
##   godot --path . res://scenes/kit_test.tscn -- --kit-out=/tmp/kit [--kit-group=2] [--kit-only=barrel,bench]
## It lays every prop out in groups, frames each group with the camera and saves <kit-out>_<n>.png, then quits.
## Without --kit-out it just shows group 0 (or --kit-group) so you can look at it in a normal run.

const M := preload("res://scripts/mats.gd")
const GROUPS := [
	["crate_small", "crate_large", "barrel", "railing_post", "railing_2m", "bench", "porch_chair", "planter", "gull_nest", "turbine_switch"],
	["generator", "workbench", "pipe_straight", "pipe_corner", "dish_small", "sign_board", "chimney", "vent_stack", "awning", "lamp_post"],
	["cargo_container", "hanging_container", "market_stall", "junk_pile", "gizmart_kiosk", "scrap_heap"],
	["wind_turbine", "antenna", "flag_pole", "water_tower", "bank_vault_door", "gantry"],
	["signal_mast_top", "crane_yard_gate", "junkyard_porch", "sky_island_rim", "sky_island_rim"],
]

var out := ""
var only: Array = []
var group_sel := -1
var cam: Camera3D
var frames := []   # [center, width, height]

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--kit-out="): out = a.substr(10)
		elif a.begins_with("--kit-only="): only = Array(a.substr(11).split(","))
		elif a.begins_with("--kit-group="): group_sel = int(a.substr(12))
	_env()
	var groups: Array = [only] if only.size() > 0 else GROUPS
	for gi in groups.size():
		var g: Array = groups[gi]
		var z := -gi * 40.0
		var w := 0.0
		for p in g: w += Kit.SIZES.get(p, Vector3.ONE).x + 1.2
		var x := -w / 2
		var h := 0.0
		for p in g:
			var s: Vector3 = Kit.SIZES.get(p, Vector3.ONE)
			x += s.x / 2 + 0.6
			Kit.place(self, p, Vector3(x, 0, z), 0.0)
			x += s.x / 2 + 0.6
			h = maxf(h, s.y)
		var fl := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = Vector3(w + 12, 1, 14)
		fl.mesh = bm; fl.material_override = M.deck(Color(0.78, 0.86, 0.92)); fl.position = Vector3(0, -0.5, z)
		add_child(fl)
		frames.append([Vector3(0, 0, z), w, h])
	cam = Camera3D.new(); cam.fov = 38; add_child(cam)
	_frame(maxi(group_sel, 0))
	if out != "": _capture()

func _frame(i: int) -> void:
	var c: Vector3 = frames[i][0]; var w: float = frames[i][1]; var h: float = frames[i][2]
	var aspect := 16.0 / 9.0
	var half_v := deg_to_rad(cam.fov) / 2
	var dist := maxf((w * 0.5 + 0.5) / (tan(half_v) * aspect), (h * 0.6 + 0.5) / tan(half_v)) + 2.0
	var look := c + Vector3(0, h * 0.42, 0)
	cam.global_position = look + Vector3(-0.12, 0.32, 1).normalized() * dist
	cam.look_at(look)
	cam.current = true

func _capture() -> void:
	for i in frames.size():
		if group_sel >= 0 and i != group_sel: continue
		_frame(i)
		for k in 45: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := "%s_%d.png" % [out, i]
		get_viewport().get_texture().get_image().save_png(path)
		print("saved ", path)
	get_tree().quit()

func _env() -> void:
	var we := WorldEnvironment.new(); var env := Environment.new(); var sky := Sky.new(); var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.08, 0.3, 0.72); sm.sky_horizon_color = Color(0.55, 0.76, 0.92); sm.sky_curve = 0.12
	sm.ground_horizon_color = Color(0.62, 0.80, 0.93); sm.ground_bottom_color = Color(0.25, 0.42, 0.58)
	sky.sky_material = sm; env.background_mode = Environment.BG_SKY; env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY; env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX; env.tonemap_exposure = 0.92; env.tonemap_white = 6.0
	env.ssao_enabled = true; env.ssao_radius = 1.2; env.ssao_intensity = 1.6; env.ssil_enabled = true
	env.sdfgi_enabled = true; env.sdfgi_use_occlusion = true; env.sdfgi_min_cell_size = 0.2
	env.glow_enabled = true; env.glow_intensity = 0.7; env.glow_bloom = 0.08; env.glow_hdr_threshold = 1.2
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.adjustment_enabled = true; env.adjustment_saturation = 1.2; env.adjustment_contrast = 1.05
	we.environment = env; add_child(we)
	var sun := DirectionalLight3D.new(); sun.light_color = Color(1.0, 0.9, 0.76); sun.light_energy = 2.2
	sun.shadow_enabled = true; sun.shadow_blur = 1.5; sun.directional_shadow_max_distance = 120.0
	sun.rotation_degrees = Vector3(-35, -50, 0)
	add_child(sun)
