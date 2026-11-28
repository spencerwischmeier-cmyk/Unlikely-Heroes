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
			"tonemap_exposure": 0.7,
			"adjustment_contrast": 1.26,
			"adjustment_saturation": 1.06,
			"volumetric_fog_density": 0.0045,
			"volumetric_fog_albedo": Color(1.0, 0.86, 0.7),
			"volumetric_fog_anisotropy": 0.74,
			"fog_light_color": Color(0.86, 0.64, 0.44),
			"fog_sun_scatter": 0.4,
			"ssao_intensity": 3.0,
			"ssil_intensity": 1.4,
			"glow_intensity": 1.15,
			"glow_bloom": 0.2,
		},
		"sun_color": Color(1.0, 0.74, 0.46),
		"ssr": false,                   # the stage is big; SSR there cost more than it showed
		"fill_energy": 0.16,
	},
	# the Market Terrace and the Spice Bazaar: warm late-afternoon light through drifting smoke, rich colour,
	# deeper contact shadows under the stalls and awnings (scripts/level/terrace/market_look.gd dresses it)
	"market": {
		"rect": Rect2(-111, 20, 54, 35),
		"fade": 9.0,
		"off_flag": "--no-market",
		"env": {
			"tonemap_exposure": 0.86,
			"adjustment_contrast": 1.14,
			"adjustment_saturation": 1.14,
			"volumetric_fog_density": 0.0028,
			"volumetric_fog_albedo": Color(1.0, 0.88, 0.74),
			"volumetric_fog_anisotropy": 0.76,
			"fog_light_color": Color(0.98, 0.76, 0.56),
			"fog_sun_scatter": 0.32,
			"ssao_intensity": 2.6,
			"ssil_intensity": 1.3,
			"glow_intensity": 1.0,
			"glow_bloom": 0.14,
		},
		"sun_color": Color(1.0, 0.8, 0.58),
		"ssr": false,
		"fill_energy": 0.24,
	},
	# the Roof Gardens: warm, bright golden hour; more haze so the sun cuts shafts through the canopies, a soft
	# bloom on the lanterns and glow-pods, richer greens (scripts/level/gardens/gardens_look.gd dresses it)
	"gardens": {
		"rect": Rect2(-96, -74, 52, 80),
		"fade": 8.0,
		"env": {
			"tonemap_exposure": 0.82,
			"adjustment_contrast": 1.2,
			"adjustment_saturation": 1.2,
			"volumetric_fog_density": 0.0021,
			"volumetric_fog_albedo": Color(1.0, 0.92, 0.78),
			"volumetric_fog_anisotropy": 0.84,
			"fog_light_color": Color(1.0, 0.84, 0.62),
			"fog_sun_scatter": 0.32,
			"ssao_intensity": 3.0,
			"ssil_intensity": 1.3,
			"glow_intensity": 0.95,
			"glow_bloom": 0.14,
		},
		"sun_color": Color(1.0, 0.8, 0.56),
		"ssr": false,
		"fill_energy": 0.26,
	},
	# the routes between the areas (scripts/level/routes/routes_look.gd): the tram viaduct catches the same
	# dusty gold as the junkyard it leaves, warming toward the plaza; the Lantern Bridge glows like the market
	# ahead of it; the freight routes are cooler and harder, steel and floodlight
	"viaduct": {
		"rect": Rect2(-7, 46, 14, 47),
		"fade": 8.0,
		"off_flag": "--no-routes-look",
		"env": {
			"tonemap_exposure": 0.84,
			"adjustment_contrast": 1.15,
			"adjustment_saturation": 1.14,
			"volumetric_fog_density": 0.0026,
			"volumetric_fog_albedo": Color(1.0, 0.88, 0.74),
			"volumetric_fog_anisotropy": 0.8,
			"fog_light_color": Color(0.98, 0.78, 0.58),
			"fog_sun_scatter": 0.34,
			"ssao_intensity": 2.6,
			"ssil_intensity": 1.25,
			"glow_intensity": 0.95,
			"glow_bloom": 0.14,
		},
		"sun_color": Color(1.0, 0.8, 0.6),
		"ssr": false,
		"fill_energy": 0.24,
	},
	"lantern_bridge": {
		"rect": Rect2(-58, 28, 34, 10),
		"fade": 7.0,
		"off_flag": "--no-routes-look",
		"env": {
			"tonemap_exposure": 0.84,
			"adjustment_contrast": 1.14,
			"adjustment_saturation": 1.18,
			"volumetric_fog_density": 0.0026,
			"volumetric_fog_albedo": Color(1.0, 0.86, 0.76),
			"volumetric_fog_anisotropy": 0.78,
			"fog_light_color": Color(1.0, 0.74, 0.58),
			"fog_sun_scatter": 0.34,
			"ssao_intensity": 2.6,
			"ssil_intensity": 1.3,
			"glow_intensity": 1.05,
			"glow_bloom": 0.16,
		},
		"sun_color": Color(1.0, 0.78, 0.6),
		"ssr": false,
		"fill_energy": 0.24,
	},
	"freight_gangway": FREIGHT_GANGWAY,
	"freight_approach": FREIGHT_APPROACH,
	# the sky routes: the Skyline Cableway is high, airy and bright, a clean blue haze with the gardens' gold;
	# the balloon barge is festive, warm and rosy; the dish rail down to the Crane Yard is crisp steel-blue
	# with the signal lamps glowing through it
	"cableway": {
		"rect": Rect2(-31, -57, 37, 21),
		"fade": 6.0,
		"off_flag": ["--no-routes-look", "--no-routes-sky"],
		"env": {
			"tonemap_exposure": 0.88,
			"adjustment_contrast": 1.12,
			"adjustment_saturation": 1.16,
			"volumetric_fog_density": 0.0022,
			"volumetric_fog_albedo": Color(0.9, 0.95, 1.0),
			"volumetric_fog_anisotropy": 0.7,
			"fog_light_color": Color(0.82, 0.9, 0.98),
			"fog_sun_scatter": 0.3,
			"ssao_intensity": 2.4,
			"ssil_intensity": 1.2,
			"glow_intensity": 1.0,
			"glow_bloom": 0.14,
		},
		"sun_color": Color(1.0, 0.9, 0.72),
		"ssr": false,
		"fill_energy": 0.32,
	},
	"balloon_line": {
		"rect": Rect2(35, -49, 28, 22),
		"fade": 6.0,
		"off_flag": ["--no-routes-look", "--no-routes-sky"],
		"env": {
			"tonemap_exposure": 0.85,
			"adjustment_contrast": 1.13,
			"adjustment_saturation": 1.2,
			"volumetric_fog_density": 0.0026,
			"volumetric_fog_albedo": Color(1.0, 0.88, 0.84),
			"volumetric_fog_anisotropy": 0.76,
			"fog_light_color": Color(1.0, 0.78, 0.7),
			"fog_sun_scatter": 0.34,
			"ssao_intensity": 2.5,
			"ssil_intensity": 1.25,
			"glow_intensity": 1.05,
			"glow_bloom": 0.16,
		},
		"sun_color": Color(1.0, 0.8, 0.66),
		"ssr": false,
		"fill_energy": 0.26,
	},
	"dish_rail": {
		"rect": Rect2(2, -97, 17, 40),
		"fade": 6.0,
		"off_flag": ["--no-routes-look", "--no-routes-sky"],
		"env": {
			"tonemap_exposure": 0.86,
			"adjustment_contrast": 1.16,
			"adjustment_saturation": 1.08,
			"volumetric_fog_density": 0.0025,
			"volumetric_fog_albedo": Color(0.86, 0.9, 1.0),
			"volumetric_fog_anisotropy": 0.72,
			"fog_light_color": Color(0.74, 0.82, 0.96),
			"fog_sun_scatter": 0.3,
			"ssao_intensity": 2.6,
			"ssil_intensity": 1.2,
			"glow_intensity": 1.08,
			"glow_bloom": 0.15,
		},
		"sun_color": Color(1.0, 0.86, 0.72),
		"ssr": false,
		"fill_energy": 0.3,
	},
}

const FREIGHT_ENV := {
	"tonemap_exposure": 0.86,
	"adjustment_contrast": 1.17,
	"adjustment_saturation": 1.06,
	"volumetric_fog_density": 0.0024,
	"volumetric_fog_albedo": Color(0.9, 0.93, 1.0),
	"volumetric_fog_anisotropy": 0.72,
	"fog_light_color": Color(0.78, 0.84, 0.95),
	"fog_sun_scatter": 0.28,
	"ssao_intensity": 2.7,
	"ssil_intensity": 1.2,
	"glow_intensity": 1.0,
	"glow_bloom": 0.13,
}
const FREIGHT_GANGWAY := { "rect": Rect2(23, 25, 34, 10), "fade": 7.0, "off_flag": "--no-routes-look", "env": FREIGHT_ENV,
	"sun_color": Color(1.0, 0.9, 0.78), "ssr": false, "fill_energy": 0.3 }
const FREIGHT_APPROACH := { "rect": Rect2(-11, -97, 10, 105), "fade": 7.0, "off_flag": "--no-routes-look", "env": FREIGHT_ENV,
	"sun_color": Color(1.0, 0.9, 0.78), "ssr": false, "fill_energy": 0.3 }

var env: Environment
var sun: DirectionalLight3D
var fill: DirectionalLight3D
var base := {}            # parameter -> value from main.gd
var base_sun := Color.WHITE
var base_fill := 0.35
var weight := {}          # mood -> current 0..1
var disabled := {}        # moods turned off by their off_flag
var off := false
var last_p := Vector3.INF

func _ready() -> void:
	off = OS.get_cmdline_user_args().has("--no-mood")
	for k in MOODS: weight[k] = 0.0
	for k in MOODS.keys():   # a mood can be switched off with its area's own flag (before/after shots)
		if MOODS[k].has("off_flag"):
			var fl = MOODS[k].off_flag   # one flag or a list of them
			for f in (fl if fl is Array else [fl]):
				if OS.get_cmdline_user_args().has(f): disabled[k] = true

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
		if disabled.has(k): target = 0.0
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
