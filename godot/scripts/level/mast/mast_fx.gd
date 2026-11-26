extends Node3D
## Runtime life of the Signal Mast (built by mast_build.gd): blinking beacons, wind gusts that shove Vesk
## about on the exposed catwalks, windsocks and flags that whip with the wind, sprocket pickups on the risky
## perches, sparking cables, the control-room screens, and the relay dish powering up when it is aligned.

var level: Node3D
var t := 0.0
var traversing := false

# ---- beacons: { mat: StandardMaterial3D, light: OmniLight3D or null, phase: float, base: float }
var beacons: Array = []
# ---- wind: { rect: Rect2, y0: float, y1: float, dir: Vector3, power: float, period: float, offset: float,
#              shelters: Array[Rect2], parts: CPUParticles3D, snd: Vector3, amount: float, was: float }
var gusts: Array = []
var socks: Array = []          # { pivot: Node3D, sock: Node3D, dir: Vector3, gust: int (index or -1) }
var flag_mats: Array = []      # ShaderMaterial (uniform "gust")
var flag_gust := 0.0
# ---- sprockets: { node: Node3D, id: String, pos: Vector3 }
var sprockets: Array = []
# ---- sparks along the lattice
var spark_spots: Array = []    # Vector3
var spark_t := 2.0
# ---- control room screens: bars (MeshInstance3D) that bounce, labels that scroll
var bars: Array = []
var screen_labels: Array = []
var screen_t := 0.0
# ---- power rings on the lattice and the dish beam
var power_rings: Array = []    # StandardMaterial3D, bottom to top
var beam: Node3D
var beam_mats: Array = []      # ShaderMaterial (uniform "power")
var beam_rings: Array = []     # MeshInstance3D sliding up the beam
var powered := false
var power_t := -1.0
var last_target := Vector2.ZERO
var crank_count := 0
# ---- sound
var players: Array = []        # AudioStreamPlayer3D pool for one-shots
var hum: AudioStreamPlayer3D
var streams := {}

func _ready() -> void:
	for a in OS.get_cmdline_user_args(): if a.begins_with("--traverse"): traversing = true
	for i in 4:
		var p := AudioStreamPlayer3D.new(); p.unit_size = 10.0; p.max_distance = 110.0; p.bus = "SFX"
		add_child(p); players.append(p)
	if level: last_target = level.dish_target

func stream(n: String, loop := false) -> AudioStream:
	var key := n + ("_loop" if loop else "")
	if streams.has(key): return streams[key]
	var path := "res://audio/sfx/%s.mp3" % n
	if not ResourceLoader.exists(path): streams[key] = null; return null
	var s: AudioStream = load(path)
	if loop:
		s = s.duplicate()
		if s is AudioStreamMP3: (s as AudioStreamMP3).loop = true
	streams[key] = s
	return s

func play_at(n: String, pos: Vector3, db := 0.0, pitch_var := 0.06) -> void:
	var s := stream(n)
	if s == null: return
	for p: AudioStreamPlayer3D in players:
		if not p.playing:
			p.stream = s; p.volume_db = db; p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
			p.global_position = pos; p.play(); return

## a looping positional sound (ambience); returns the player
func loop_at(n: String, pos: Vector3, db := -6.0, unit := 6.0, max_d := 45.0) -> AudioStreamPlayer3D:
	var s := stream(n, true)
	if s == null: return null
	var p := AudioStreamPlayer3D.new(); p.stream = s; p.volume_db = db; p.unit_size = unit; p.max_distance = max_d
	p.bus = "SFX"; p.autoplay = true; p.position = pos
	add_child(p)
	return p

# ---------------------------------------------------------------- wind
func gust_amount(g: Dictionary) -> float:
	var ph := fmod(t + g.offset, g.period)
	var calm: float = g.period - 3.4
	if ph < calm: return 0.0
	ph -= calm
	if ph < 0.9: return ph / 0.9 * 0.3          # building: streaks and a whistle, barely a push
	if ph < 2.8: return 1.0
	return clampf(1.0 - (ph - 2.8) / 0.6, 0.0, 1.0)

func _wind(dt: float) -> void:
	var p: CharacterBody3D = Game.player
	flag_gust = 0.0
	for g in gusts:
		var a := gust_amount(g)
		g.amount = a
		flag_gust = maxf(flag_gust, a)
		if g.parts: g.parts.emitting = a > 0.05
		if a > 0.05 and g.was <= 0.05: play_at("mast_wind_gust", g.snd, -2.0)
		g.was = a
		if traversing or p == null or a < 0.31: continue
		if p.get("riding") or p.get("swing_hook") != null: continue
		var pp := p.global_position
		if pp.y < g.y0 or pp.y > g.y1 or not (g.rect as Rect2).has_point(Vector2(pp.x, pp.z)): continue
		var sheltered := false
		for s: Rect2 in g.shelters:
			if s.has_point(Vector2(pp.x, pp.z)): sheltered = true; break
		if sheltered: continue
		p.move_and_collide(g.dir * g.power * a * dt)
	for m: ShaderMaterial in flag_mats: m.set_shader_parameter("gust", flag_gust)
	for s in socks:
		var a: float = 0.35
		if s.gust >= 0 and s.gust < gusts.size(): a = maxf(a, gusts[s.gust].amount)
		else: a = maxf(a, flag_gust * 0.7)
		var piv: Node3D = s.pivot
		var want := atan2(s.dir.x, s.dir.z)
		piv.rotation.y = lerp_angle(piv.rotation.y, want + sin(t * 1.7 + s.phase) * 0.25 * (1.2 - a), 1.0 - exp(-3.0 * dt))
		var sock: Node3D = s.sock
		var droop := lerpf(1.1, 0.08, a) + sin(t * (5.0 + a * 9.0) + s.phase) * (0.05 + 0.1 * a)
		sock.rotation.x = lerpf(sock.rotation.x, droop, 1.0 - exp(-6.0 * dt))

# ---------------------------------------------------------------- sprockets
func _sprockets(dt: float) -> void:
	var p: Node3D = Game.player
	for i in range(sprockets.size() - 1, -1, -1):
		var s: Dictionary = sprockets[i]
		var n: Node3D = s.node
		n.rotation.y += dt * 2.6
		n.position.y = s.pos.y + sin(t * 2.4 + s.pos.x) * 0.12
		if p == null: continue
		if p.global_position.distance_to(n.global_position - Vector3(0, 0.6, 0)) < 1.25:
			Game.collect("mast_sprocket", s.id)
			Game.add_nuts(10)
			Snd.play("nut_pickup", -6, 0.15, 0.04)
			FX.sparks(n.global_position, Color(1, 0.8, 0.35), 10, 4.0)
			n.queue_free(); sprockets.remove_at(i)

# ---------------------------------------------------------------- the dish
func _dish(dt: float) -> void:
	if level == null or level.dish_pivot == null: return
	var dp: Node3D = level.dish_pivot
	# each crank swings the dish a step: grind, sparks and a shudder
	if level.dish_target.distance_to(last_target) > 0.01:
		last_target = level.dish_target
		crank_count += 1
		play_at("mast_crank", dp.global_position, 2.0)
		for k in 3:
			get_tree().create_timer(0.15 * k).timeout.connect(func():
				FX.sparks(dp.global_position + Vector3(randf_range(-1.5, 1.5), randf_range(-2.0, -0.5), randf_range(-1.5, 1.5)), Color(1, 0.7, 0.3), 14, 5.0))
	var aligned: bool = level.dish_glow != null and level.dish_glow.emission.b > 0.8 and level.dish_glow.emission.r < 0.5
	if aligned and not powered:
		powered = true; power_t = 0.0
		play_at("mast_dish_powerup", dp.global_position, 4.0, 0.0)
		FX.shake(0.3)
	if powered:
		power_t += dt
		# the power climbs the lattice ring by ring, then the dish fires its beam into the sky
		for i in power_rings.size():
			var m: StandardMaterial3D = power_rings[i]
			var on := power_t > 0.25 + i * 0.3
			m.emission = Color(0.3, 0.95, 1.0) if on else Color(1.0, 0.63, 0.19)
			var flash := clampf(1.0 - (power_t - (0.25 + i * 0.3)) * 2.0, 0.0, 1.0) if on else 0.0
			m.emission_energy_multiplier = 3.0 + 9.0 * flash + (1.0 + sin(t * 3.0 - i * 0.8)) * (1.0 if on else 0.0)
			if on and flash > 0.95 and i < spark_spots.size(): pass
		if power_t > 0.25 and power_t - dt <= 0.25 + power_rings.size() * 0.3 and fmod(power_t, 0.3) < dt:
			var sp: Vector3 = spark_spots.pick_random() if spark_spots.size() > 0 else dp.global_position
			FX.sparks(sp, Color(0.4, 0.95, 1.0), 16, 6.0)
		var fire := clampf((power_t - 1.9) / 0.5, 0.0, 1.0)
		if power_t >= 1.9 and power_t - dt < 1.9:
			FX.shake(0.8)
			for k in 3:
				get_tree().create_timer(0.18 * k).timeout.connect(func(): FX.ring(dp.global_position, Color(0.3, 0.95, 1.0), 2.5 + k * 1.5))
			FX.sparks(dp.global_position, Color(0.5, 1.0, 1.0), 30, 9.0)
			if hum == null:
				hum = loop_at("mast_dish_hum", Vector3.ZERO, -4.0, 9.0, 90.0)
				if hum:
					remove_child(hum); dp.add_child(hum); hum.position = Vector3.ZERO
		if beam:
			beam.visible = fire > 0.0
			beam.scale = Vector3(lerpf(0.2, 1.0, fire), lerpf(0.2, 1.0, fire), fire)
			var pulse := 0.85 + 0.15 * sin(t * 5.0) + 0.6 * clampf(1.0 - (power_t - 1.9) * 1.5, 0.0, 1.0)
			for m: ShaderMaterial in beam_mats: m.set_shader_parameter("power", fire * pulse)
			for i in beam_rings.size():
				var r: MeshInstance3D = beam_rings[i]
				var u := fmod(t * 0.35 + i / float(beam_rings.size()), 1.0)
				r.position.z = 2.0 + u * 46.0
				var s := lerpf(0.9, 3.2, u)
				r.scale = Vector3(s, s, s) * fire
		if level.dish_light: level.dish_light.light_energy = 6.0 + 3.0 * sin(t * 5.0) * fire

# ---------------------------------------------------------------- sparks, beacons, screens
func _ambient(dt: float) -> void:
	for b in beacons:
		var ph := fmod(t * b.rate + b.phase, 1.0)
		var on := ph < 0.18
		var e: float = b.base * (1.0 if on else 0.06) * (1.0 if not b.has("soft") else (0.5 + 0.5 * sin(t * 3.0 + b.phase * 6.0)))
		(b.mat as StandardMaterial3D).emission_energy_multiplier = e
		if b.light: (b.light as OmniLight3D).light_energy = 2.2 if on else 0.0
	var p: Node3D = Game.player
	if p and p.global_position.distance_to(Vector3(20, 14, -40)) < 45.0 and spark_spots.size() > 0:
		spark_t -= dt
		if spark_t <= 0.0:
			spark_t = randf_range(1.6, 4.2)
			var sp: Vector3 = spark_spots.pick_random()
			FX.sparks(sp, Color(0.45, 0.95, 1.0) if powered else Color(1, 0.65, 0.25), 8, 3.5)
			play_at("mast_spark", sp, -10.0, 0.15)
	screen_t -= dt
	for i in bars.size():
		var b: MeshInstance3D = bars[i]
		var h := 0.25 + 0.75 * absf(sin(t * (1.3 + i * 0.37) + i * 1.7)) * (1.0 if powered else 0.55 + 0.45 * float(int(t * 4.0 + i) % 3 == 0))
		b.scale.y = lerpf(b.scale.y, h, 1.0 - exp(-8.0 * dt))
		b.position.y = b.get_meta("y0") + b.scale.y * 0.5 * b.get_meta("h")
	if screen_t <= 0.0:
		screen_t = 0.45
		for l: Label3D in screen_labels:
			var kind: String = l.get_meta("kind")
			match kind:
				"signal":
					l.text = ("SIGNAL LOCKED\nRELAY ONLINE" if powered else "SIGNAL: ???\nDISH OFF-AXIS")
					l.modulate = Color(0.45, 1, 0.9) if powered else (Color(1, 0.55, 0.2) if int(t * 2.0) % 2 == 0 else Color(1, 0.3, 0.2))
				"freq":
					l.text = "FREQ %d.%02d\nGAIN %d%%" % [118 + int(t) % 7, randi() % 100, (96 + randi() % 4) if powered else (12 + randi() % 30)]
				"wind":
					var g: float = gusts[0].amount if gusts.size() > 0 else 0.0
					l.text = "WIND %d KN\n%s" % [int(14 + g * 38 + randf() * 3), "GUST!" if g > 0.3 else "STEADY"]
					l.modulate = Color(1, 0.4, 0.3) if g > 0.3 else Color(0.6, 0.95, 1)

func _physics_process(dt: float) -> void:
	t += dt
	_wind(dt)
	_sprockets(dt)

func _process(dt: float) -> void:
	_dish(dt)
	_ambient(dt)
