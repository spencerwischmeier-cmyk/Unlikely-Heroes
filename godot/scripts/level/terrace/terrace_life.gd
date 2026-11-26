extends Node3D
## The Market Terrace while it runs: updraft fans that lift Vesk when he holds jump in their wind,
## loose sprockets to collect in the side pockets, swaying wind chimes, spinning fan rotors, drifting sky
## lanterns, a whistling tea kettle and the area's ambience loops.

const TK := preload("res://scripts/level/terrace/tkit.gd")

## { pos: Vector3 (fan centre), r: float, top: float (lift fades out near it), vmax: float, accel: float, rotor: Node3D }
var fans: Array = []
var sprockets: Array = []      # { node: Node3D, pos: Vector3, phase: float }
var swingers: Array = []       # { node: Node3D, amp: float, speed: float, phase: float }
var gulls: Array = []          # { node: Node3D, c: Vector3, r: float, speed: float, phase: float, wings: Array }
var floaters: Array = []       # { node: Node3D, base: Vector3, phase: float, rise: float }
var kettle_pos := Vector3.ZERO
## voice lines the first time Vesk steps into a spot: { rect: Rect2, y: float, ids: Array }
var triggers: Array = []
var kettle_t := 8.0
var _t := 0.0
var _lift_snd := 0.0
var _sprocket_mat: StandardMaterial3D

func _ready() -> void:
	_sprocket_mat = StandardMaterial3D.new()
	_sprocket_mat.albedo_color = Color(1.0, 0.76, 0.24); _sprocket_mat.metallic = 1.0; _sprocket_mat.roughness = 0.25
	_sprocket_mat.emission_enabled = true; _sprocket_mat.emission = Color(1.0, 0.6, 0.15); _sprocket_mat.emission_energy_multiplier = 0.6

func add_fan(pos: Vector3, r: float, top: float, vmax: float, accel: float, rotor: Node3D) -> void:
	fans.append({ pos = pos, r = r, top = top, vmax = vmax, accel = accel, rotor = rotor })

func add_sprocket(pos: Vector3) -> void:
	var n := MeshInstance3D.new(); n.mesh = TK.sprocket_mesh(); n.material_override = _sprocket_mat
	n.scale = Vector3.ONE * 1.25
	add_child(n); n.global_position = pos
	sprockets.append({ node = n, pos = pos, phase = randf() * TAU })

func add_gull(c: Vector3, r: float, speed: float, mat_body: Material, mat_wing: Material) -> void:
	var n := Node3D.new(); add_child(n)
	var body := MeshInstance3D.new(); body.mesh = TK.sphere_mesh(); body.material_override = mat_body
	body.scale = Vector3(0.22, 0.2, 0.6); n.add_child(body)
	var wings := []
	for s in [-1, 1]:
		var piv := Node3D.new(); n.add_child(piv)
		var w := MeshInstance3D.new(); w.mesh = TK.box_mesh(); w.material_override = mat_wing
		w.scale = Vector3(0.75, 0.03, 0.3); w.position = Vector3(0.4 * s, 0, 0); piv.add_child(w)
		wings.append(piv)
	gulls.append({ node = n, c = c, r = r, speed = speed, phase = randf() * TAU, wings = wings })

func add_swinger(n: Node3D, amp := 0.12, speed := 1.3) -> void:
	swingers.append({ node = n, amp = amp, speed = speed, phase = randf() * TAU })

## a positional ambience loop
func ambience(sfx: String, pos: Vector3, db := 0.0, unit := 8.0, max_d := 45.0) -> void:
	var p := "res://audio/sfx/%s.ogg" % sfx
	if not ResourceLoader.exists(p): return
	var s: AudioStream = (load(p) as AudioStream).duplicate()
	if s is AudioStreamOggVorbis: (s as AudioStreamOggVorbis).loop = true
	var a := AudioStreamPlayer3D.new(); a.stream = s; a.volume_db = db; a.unit_size = unit; a.max_distance = max_d
	a.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	a.autoplay = true; a.position = pos
	add_child(a)

func _physics_process(dt: float) -> void:
	var p: CharacterBody3D = Game.player
	if p == null: return
	_lift_snd -= dt
	var pp := to_local(p.global_position)   # fans, triggers and the kettle are in this node's own space
	var held := Input.is_action_pressed("jump")
	for f in fans:
		var d := Vector2(pp.x - f.pos.x, pp.z - f.pos.z).length()
		if d > f.r or pp.y < f.pos.y - 0.5 or pp.y > f.top: continue
		if p.is_on_floor() or not held: continue
		var fade := clampf((f.top - pp.y) / 1.6, 0.0, 1.0)
		p.velocity.y = move_toward(p.velocity.y, f.vmax * fade, f.accel * dt)
		# riding the wind counts as the jetpack boost, so holding jump glides on out of the column
		p.set("jumps", 2); p.set("jump_cut", true)
		if _lift_snd <= 0.0:
			_lift_snd = 1.2
			Snd.at("terrace_updraft", p.global_position, -6, 0.1, 0.0)

func _process(dt: float) -> void:
	_t += dt
	for f in fans:
		if f.rotor: (f.rotor as Node3D).rotate_y(dt * 11.0)
	for s in swingers:
		var n: Node3D = s.node
		n.rotation.z = sin(_t * s.speed + s.phase) * s.amp
		n.rotation.x = sin(_t * s.speed * 0.7 + s.phase * 1.3) * s.amp * 0.6
	for g in gulls:
		var a: float = _t * g.speed + g.phase
		var n: Node3D = g.node
		n.position = g.c + Vector3(cos(a) * g.r, sin(a * 2.3) * 0.8, sin(a) * g.r)
		n.rotation.y = -a + (PI if g.speed > 0 else 0.0)
		var flap := sin(_t * 7.0 + g.phase * 4.0) * 0.6
		(g.wings[0] as Node3D).rotation.z = flap
		(g.wings[1] as Node3D).rotation.z = -flap
	for f in floaters:
		var n: Node3D = f.node
		var u := fposmod(_t * f.rise + f.phase, 1.0)
		n.position = f.base + Vector3(sin(_t * 0.3 + f.phase * 5.0) * 2.0, u * 40.0, cos(_t * 0.25 + f.phase * 3.0) * 2.0)
		n.scale = Vector3.ONE * (1.0 - u * 0.4) * (1.0 if u < 0.9 else (1.0 - u) * 10.0)
	var p: Node3D = Game.player
	var hp := p.global_position + Vector3(0, 0.9, 0) if p else Vector3(0, -999, 0)
	for i in range(sprockets.size() - 1, -1, -1):
		var s: Dictionary = sprockets[i]
		var n: Node3D = s.node
		n.rotation.y = _t * 2.6 + s.phase
		n.position.y = s.pos.y + sin(_t * 2.0 + s.phase) * 0.12
		if hp.distance_to(n.global_position) < 1.25:
			Game.add_nuts(5)
			Snd.play("nut_pickup", -6, 0.18, 0.02)
			FX.sparks(n.global_position, Color(1.0, 0.8, 0.3), 6, 3.0)
			n.queue_free(); sprockets.remove_at(i)
	if p:
		for i in range(triggers.size() - 1, -1, -1):
			var tr: Dictionary = triggers[i]
			var pp := to_local(p.global_position)
			if (tr.rect as Rect2).has_point(Vector2(pp.x, pp.z)) and absf(pp.y - tr.y) < 1.5:
				triggers.remove_at(i)
				if Game.input_locked: continue
				for id in tr.ids: Snd.voice(id)
	# the tea kettle whistles now and then when Vesk is near
	kettle_t -= dt
	if kettle_t <= 0.0:
		kettle_t = randf_range(18.0, 30.0)
		if p and to_local(p.global_position).distance_to(kettle_pos) < 26.0:
			Snd.at("terrace_kettle", to_global(kettle_pos), -4, 0.05, 0.0)
