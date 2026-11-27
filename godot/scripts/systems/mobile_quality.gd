extends Node
## Lighter graphics for the browser and phone builds (installed by main.gd like every system).
## Does nothing on the PC build. Tiers come from device.gd ("web" or "phone").
##
## - effects WebGL can't do (SDFGI, SSAO, SSIL, volumetric fog) are switched off cleanly; phones also drop glow
## - sun shadows cover less distance with 2 cascades; small props stop casting shadows on phones
## - small and medium pieces stop drawing sooner; lamps fade out with distance and lose their shadows
## - particle effects (smoke, sparks, dust) spawn fewer particles
## - the 3D view renders at a lower resolution that adapts to keep the frame rate up (the HUD stays sharp)
## Citizens and sky traffic are thinned where they spawn (level/panic/crowd.gd, traffic.gd use Device.scale).

const Device := preload("res://scripts/device.gd")

var tier := ""
var scale_3d := 1.0
var min_scale := 0.5
var max_scale := 1.0
var fps_t := 0.0
var fps_frames := 0
var slow_for := 0.0
var fast_for := 0.0

func _ready() -> void:
	if not Device.lite(): queue_free(); return
	tier = Device.tier()
	if tier == "pc": tier = "web"   # compatibility renderer forced on a PC: treat like a desktop browser
	_environment()
	_view()
	await get_tree().process_frame
	_sweep(Game.level if Game.level else get_parent())
	# things built after the level (cutscene sets, bosses, effects) get the same treatment
	get_tree().node_added.connect(_on_node_added)
	print("[quality] %s tier, 3D scale %.2f" % [tier, scale_3d])

func _environment() -> void:
	var m = Game.main
	if m == null: return
	var env: Environment = m.get("env")
	if env:
		env.sdfgi_enabled = false
		env.ssao_enabled = false
		env.ssil_enabled = false
		env.ssr_enabled = false
		env.volumetric_fog_enabled = false
		# the volumetric fog gave the distance its warm haze; plain depth fog starts a little closer instead
		env.fog_depth_begin = 70.0 if tier == "phone" else 80.0
		if tier == "phone":
			env.glow_enabled = false
		else:
			env.glow_intensity = 0.6
	var sun: DirectionalLight3D = m.get("sun")
	if sun:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		sun.directional_shadow_max_distance = 55.0 if tier == "phone" else 90.0
		sun.shadow_blur = 1.0

func _view() -> void:
	var vp := get_viewport()
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	if tier == "phone":
		# phone screens are dense (2-3x); rendering 3D near CSS resolution is plenty
		var dpr := 1.0
		if OS.has_feature("web"):
			var v = JavaScriptBridge.eval("window.devicePixelRatio || 1", true)
			if v != null: dpr = float(v)
		max_scale = clampf(1.6 / maxf(dpr, 1.0), 0.45, 1.0)
		min_scale = 0.4
		scale_3d = max_scale
		vp.msaa_3d = Viewport.MSAA_DISABLED
	else:
		max_scale = 1.0; min_scale = 0.6; scale_3d = 1.0
		vp.msaa_3d = Viewport.MSAA_2X
	vp.scaling_3d_scale = scale_3d
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED

func _on_node_added(n: Node) -> void:
	if n is GeometryInstance3D or n is Light3D:
		# wait until it is placed in the world (sizes and positions are known then)
		(func(): if is_instance_valid(n) and n.is_inside_tree(): _tune(n)).call_deferred()

func _sweep(root: Node) -> void:
	if root == null: return
	for n in root.find_children("*", "Node3D", true, false):
		if n is GeometryInstance3D or n is Light3D: _tune(n)

func _tune(n: Node) -> void:
	if n.has_meta("_q"): return
	n.set_meta("_q", true)
	var phone := tier == "phone"
	var reach := Device.reach()
	if n is OmniLight3D or n is SpotLight3D:
		var l := n as Light3D
		if phone: l.shadow_enabled = false
		elif l.shadow_enabled and l is OmniLight3D: (l as OmniLight3D).omni_shadow_mode = OmniLight3D.SHADOW_DUAL_PARABOLOID
		l.distance_fade_enabled = true
		var far := 34.0 if phone else 55.0
		if l.distance_fade_begin <= 0.0 or l.distance_fade_begin > far: l.distance_fade_begin = far
		l.distance_fade_length = 10.0
		l.distance_fade_shadow = minf(l.distance_fade_begin, 22.0)
		return
	if n is GPUParticles3D:
		(n as GPUParticles3D).amount_ratio = 0.45 if phone else 0.7
		return
	if n is CPUParticles3D:
		var cp := n as CPUParticles3D
		var want := maxi(1, int(cp.amount * (0.45 if phone else 0.7)))
		if want < cp.amount: cp.amount = want
		return
	if n is Label3D: return
	var gi := n as GeometryInstance3D
	if _in_sky(gi): return
	var ab := gi.get_aabb()
	var sc := gi.global_transform.basis.get_scale()
	var big := maxf(ab.size.x * sc.x, maxf(ab.size.y * sc.y, ab.size.z * sc.z))
	if gi is MultiMeshInstance3D:
		big = 6.0   # instanced crowds / clutter: judge by the batch, not one piece
	if gi.visibility_range_end > 0.0:
		gi.visibility_range_end *= reach
	elif big < 15.0 and not (gi is MultiMeshInstance3D):
		gi.visibility_range_end = (230.0 if big >= 6.0 else 150.0) * reach
		gi.visibility_range_end_margin = 8.0
	if phone and big < 2.5 and gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _in_sky(n: Node) -> bool:
	var p := n.get_parent()
	while p:
		if p.name == "SkyWorld": return true
		p = p.get_parent()
	return false

## adaptive 3D resolution: drop when the frame rate sags, creep back up when there's headroom
func _process(dt: float) -> void:
	if get_tree().paused: return
	fps_t += dt; fps_frames += 1
	if fps_t < 1.0: return
	var fps := fps_frames / fps_t
	fps_t = 0.0; fps_frames = 0
	if fps < 27.0: slow_for += 1.0; fast_for = 0.0
	elif fps > 50.0: fast_for += 1.0; slow_for = 0.0
	else: slow_for = 0.0; fast_for = 0.0
	if slow_for >= 2.0 and scale_3d > min_scale:
		scale_3d = maxf(min_scale, scale_3d - 0.1); slow_for = 0.0
		get_viewport().scaling_3d_scale = scale_3d
	elif fast_for >= 6.0 and scale_3d < max_scale:
		scale_3d = minf(max_scale, scale_3d + 0.05); fast_for = 0.0
		get_viewport().scaling_3d_scale = scale_3d
