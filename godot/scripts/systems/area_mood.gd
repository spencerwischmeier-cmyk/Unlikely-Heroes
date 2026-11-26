extends Node
## Per-area lighting mood. While Vesk is inside an area's region the world environment and the sun's colour
## ease toward that area's look (and back to main.gd's defaults outside it). Starts with the Junkyard: a
## deeper golden-hour grade, warm smoky haze, stronger contact shadows and richer colour, so the junk reads
## like the look target (art/lookdev/junkyard_look.py). Pauses during cutscenes, which grade the shot
## themselves. `--no-mood` turns it off.

## region (final coordinates, xz) -> parameter overrides
const MOODS := {
	"junkyard": {
		"rect": Rect2(-54, 84, 108, 124),
		"fade": 10.0,   # metres of blend at the edge of the region
		"env": {
			"tonemap_exposure": 0.8,
			"adjustment_contrast": 1.18,
			"adjustment_saturation": 1.12,
			"volumetric_fog_density": 0.0034,
			"volumetric_fog_albedo": Color(1.0, 0.85, 0.72),
			"volumetric_fog_anisotropy": 0.78,
			"fog_light_color": Color(0.95, 0.7, 0.5),
			"fog_sun_scatter": 0.35,
			"ssao_intensity": 2.8,
			"ssil_intensity": 1.3,
			"glow_intensity": 1.0,
			"glow_bloom": 0.16,
		},
		"sun_color": Color(1.0, 0.76, 0.54),
		"ssr": true,                    # oil puddles and wet patches reflect (on while the mood is mostly in)
		"fill_energy": 0.22,
	},
	# the Crane Bot arena and the foundry behind it: darker, smokier, redder; the floodlight beams and the
	# molten glow cut through the haze (scripts/level/yard/arena_look.gd dresses the stage to match)
	"arena": {
		"rect": Rect2(-30, -190, 60, 74),
		"fade": 12.0,
		"env": {
			"tonemap_exposure": 0.74,
			"adjustment_contrast": 1.22,
			"adjustment_saturation": 1.1,
			"volumetric_fog_density": 0.0048,
			"volumetric_fog_albedo": Color(1.0, 0.8, 0.66),
			"volumetric_fog_anisotropy": 0.72,
			"fog_light_color": Color(0.9, 0.56, 0.38),
			"fog_sun_scatter": 0.45,
			"ssao_intensity": 2.8,
			"ssil_intensity": 1.4,
			"glow_intensity": 1.15,
			"glow_bloom": 0.2,
		},
		"sun_color": Color(1.0, 0.68, 0.46),
		"ssr": true,
		"fill_energy": 0.18,
	},
}

var env: Environment
var sun: DirectionalLight3D
var fill: DirectionalLight3D
var base := {}            # parameter -> value from main.gd
var base_sun := Color.WHITE
var base_fill := 0.35
var weight := {}          # mood -> current 0..1
var off := false
var last_p := Vector3.INF

func _ready() -> void:
	off = OS.get_cmdline_user_args().has("--no-mood")
	for k in MOODS: weight[k] = 0.0

func _grab() -> bool:
	if env and sun: return true
	var m: Node = Game.main
	if m == null: return false
	env = m.get("env")
	sun = m.get("sun")
	if env == null or sun == null: return false
	for c in m.get_children():
		if c is DirectionalLight3D and c != sun: fill = c
	for k in MOODS:
		for p in MOODS[k].env: if not base.has(p): base[p] = env.get(p)
	base_sun = sun.light_color
	if fill: base_fill = fill.light_energy
	return true

func _cutscene_on() -> bool:
	var cs: Node = get_parent().get_node_or_null("Cutscenes")
	return cs != null and String(cs.get("playing")) != ""

func _process(dt: float) -> void:
	if off or not _grab() or Game.player == null or _cutscene_on(): return
	var p: Vector3 = Game.player.global_position
	var q := Vector2(p.x, p.z)
	var snap := last_p == Vector3.INF or p.distance_to(last_p) > 20.0   # teleports (respawn, debug spots) don't fade
	last_p = p
	for k in MOODS:
		var md: Dictionary = MOODS[k]
		var r: Rect2 = md.rect
		# 1 inside, fading to 0 over `fade` metres outside the rect
		var dx := maxf(maxf(r.position.x - q.x, q.x - r.end.x), 0.0)
		var dz := maxf(maxf(r.position.y - q.y, q.y - r.end.y), 0.0)
		var target := 1.0 - clampf(Vector2(dx, dz).length() / float(md.fade), 0.0, 1.0)
		weight[k] = target if snap else move_toward(weight[k], target, dt * 0.6)
	_apply()

func _apply() -> void:
	# start from the defaults, then blend each mood in by its weight
	var vals := base.duplicate()
	var sc := base_sun
	var fe := base_fill
	for k in MOODS:
		var w: float = weight[k]
		if w <= 0.0: continue
		var md: Dictionary = MOODS[k]
		for p in md.env:
			var a = vals[p]; var b = md.env[p]
			vals[p] = a.lerp(b, w) if a is Color else lerpf(a, b, w)
		sc = sc.lerp(md.sun_color, w)
		fe = lerpf(fe, md.fill_energy, w)
	for p in vals: env.set(p, vals[p])
	var ssr := false
	for k in MOODS: if MOODS[k].get("ssr", false) and weight[k] > 0.5: ssr = true
	if env.ssr_enabled != ssr:
		env.ssr_enabled = ssr
		env.ssr_max_steps = 48; env.ssr_fade_in = 0.15; env.ssr_fade_out = 2.0; env.ssr_depth_tolerance = 0.3
	sun.light_color = sc
	if fill: fill.light_energy = fe
