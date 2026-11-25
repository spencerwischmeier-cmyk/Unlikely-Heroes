extends Node3D
## Work crew: three Work-Crew Rollers (enemy_crew_roller.gd) that travel nose to tail in a line.
## When they get within range of Vesk they stop, spread out side by side and hammer up a row of
## striped barricades (crew_barricade.gd), then fire rivets over them in turn. Vesk can break the
## barricades or go around them; once the barricades are down or he gets behind the line, the crew
## charges. After a while they pack up and march on to build again (twice at most).
##
## Spawning: main.spawn_bot("crew", pos, zone) calls Crew.spawn(); it returns this crew node, which
## counts as `dead` once all three rollers are down (so story waves can wait on it) and has die().

const Member := preload("res://scripts/enemy_crew_roller.gd")
const Barricade := preload("res://scripts/crew_barricade.gd")
const SPACING := 1.6
const BUILD_T := 1.5
const MAX_BUILDS := 2

var combat: Node3D
var player: CharacterBody3D
var zone := Rect2()
var members: Array = []
var barricades: Array = []
var dead := false
var state := "march"      # march, build, hold, charge
var st_t := 1.5
var builds := 0
var heading := Vector3.FORWARD
var line_c := Vector3.ZERO
var line_n := Vector3.FORWARD
var slots: Array = []
var fire_i := 0
var fire_t := 1.2
var hammer_t := 0.0

static func spawn(main: Node, combat_: Node3D, player_: CharacterBody3D, pos: Vector3, zone_ := Rect2()) -> Node3D:
	var s: Node3D = load("res://scripts/enemy_crew.gd").new()
	s.combat = combat_; s.player = player_; s.zone = zone_
	s.name = "WorkCrew"; s.add_to_group("crews")
	main.add_child(s)
	s.global_position = pos
	s.call("_spawn_members", main, pos)
	return s

func _spawn_members(main: Node, pos: Vector3) -> void:
	var away := pos - player.global_position; away.y = 0
	away = away.normalized() if away.length() > 0.1 else Vector3.FORWARD
	heading = -away
	for i in 3:
		var m: CharacterBody3D = Member.new()
		m.combat = combat; m.player = player; m.zone = zone
		main.add_child(m)
		var p := pos + away * SPACING * i
		m.global_position = p + Vector3(0, 6 + i * 1.2, 0)
		FX.ring(p + Vector3(0, 0.05, 0), Color(1, 0.7, 0.2), 0.7)
		members.append(m)
	Snd.at("bot_spawn", pos, -2); Snd.at("crew_whistle", pos, -2, 0.1)

## Story skip / boss cleanup: destroy the whole crew.
func die(self_destruct := false) -> void:
	for m in members:
		if is_instance_valid(m) and not m.dead: m.die(self_destruct)
	_all_down()

func _all_down() -> void:
	if dead: return
	dead = true
	var bs := barricades.duplicate()
	get_tree().create_timer(1.5).timeout.connect(func():
		for b in bs: if is_instance_valid(b): b.collapse())
	get_tree().create_timer(2.0).timeout.connect(queue_free)

func _physics_process(dt: float) -> void:
	if dead: return
	members = members.filter(func(m): return is_instance_valid(m) and not m.dead)
	barricades = barricades.filter(func(b): return is_instance_valid(b) and not b.dead)
	if members.is_empty(): _all_down(); return
	if Game.input_locked or player == null: return
	st_t -= dt
	var p := player.global_position
	var lead: CharacterBody3D = members[0]
	var to := p - lead.global_position; to.y = 0
	var dist := to.length()
	match state:
		"march":
			if dist > 0.1: heading = heading.slerp(to / dist, 1.0 - exp(-2.0 * dt)).normalized()
			_line_up(lead.global_position + heading * 3.0 if dist > 2.0 else p, 1.0)
			# no barricades left to build: they fire on the move instead
			if builds >= MAX_BUILDS: _fire_turns(dt, 2.0, 15.0)
			if builds < MAX_BUILDS and st_t <= 0.0 and dist < 10.5 and dist > 4.5 and lead.is_on_floor() \
					and absf(p.y - lead.global_position.y) < 2.0:
				_start_build(lead, to / dist)
		"build":
			for i in members.size(): _hold_slot(members[i], i)
			var u := clampf(1.0 - st_t / BUILD_T, 0.0, 1.0)
			for b in barricades: b.rise = maxf(b.rise, u)
			hammer_t -= dt
			if hammer_t <= 0.0:
				hammer_t = 0.22
				var m: Node3D = members.pick_random()
				Snd.at("melee_hit", m.global_position + Vector3(0, 0.8, 0), -10, 0.2, 0.05)
				FX.sparks(m.global_position + line_n * 1.0 + Vector3(0, 0.6, 0), Color(1, 0.8, 0.4), 4, 3.0)
			if st_t <= 0.0:
				if barricades.size() > 0: Snd.at("barricade_up", line_c, -2, 0.1)
				for b in barricades: b.rise = 1.0
				state = "hold"; st_t = randf_range(7.0, 9.0); fire_t = 0.6
		"hold":
			for i in members.size(): _hold_slot(members[i], i)
			_fire_turns(dt, 1.5, 22.0)
			var behind := (p - line_c).dot(line_n) < -0.6
			if barricades.is_empty() or behind:
				state = "charge"; st_t = 3.5
				Snd.at("crane_warn", lead.global_position, -10, 0.1)
			elif st_t <= 0.0:
				state = "march"; st_t = 3.0
		"charge":
			for i in members.size():
				var m: CharacterBody3D = members[i]
				var side := Vector3(to.z, 0, -to.x).normalized() * (float(i) - 1.0) * 1.2
				m.goal = p + side; m.has_goal = true; m.speed_mul = 1.4; m.face_dir = Vector3.ZERO
			if st_t <= 0.0: state = "march"; st_t = 2.5

## The leader heads for `target`; each roller follows the one ahead, nose to tail.
func _line_up(target: Vector3, speed: float) -> void:
	for i in members.size():
		var m: CharacterBody3D = members[i]
		m.has_goal = true; m.speed_mul = speed; m.face_dir = Vector3.ZERO
		if i == 0: m.goal = target
		else:
			var ahead: Node3D = members[i - 1]
			var back := m.global_position - ahead.global_position; back.y = 0
			back = back.normalized() if back.length() > 0.1 else -heading
			m.goal = ahead.global_position + back * SPACING

func _hold_slot(m: CharacterBody3D, i: int) -> void:
	if i < slots.size(): m.goal = slots[i]
	m.has_goal = true; m.speed_mul = 1.2; m.face_dir = line_n

func _fire_turns(dt: float, gap: float, max_d: float) -> void:
	fire_t -= dt
	if fire_t > 0.0: return
	fire_t = gap
	fire_i = (fire_i + 1) % members.size()
	var m: Node3D = members[fire_i]
	if m.global_position.distance_to(player.global_position) < max_d: m.fire()

func _start_build(lead: Node3D, n: Vector3) -> void:
	builds += 1
	state = "build"; st_t = BUILD_T; hammer_t = 0.0
	Snd.at("crew_hammer", lead.global_position, -4, 0.1)
	line_n = n
	var side := Vector3(n.z, 0, -n.x)
	line_c = lead.global_position + n * 1.7
	line_c.y = lead.global_position.y
	slots.clear()
	var space := get_world_3d().direct_space_state
	for i in 3:
		var bp := line_c + side * (float(i) - 1.0) * (Barricade.W + 0.15)
		slots.append(bp - n * 1.4)
		if zone.size.x > 0.0 and not zone.grow(-0.8).has_point(Vector2(bp.x, bp.z)): continue
		var q := PhysicsRayQueryParameters3D.create(bp + Vector3(0, 1.0, 0), bp + Vector3(0, -1.5, 0)); q.collision_mask = 1
		var hit := space.intersect_ray(q)
		if hit.is_empty() or hit.normal.y < 0.8: continue
		var b: StaticBody3D = Barricade.new()
		get_parent().add_child(b)
		b.global_position = hit.position
		b.rotation.y = atan2(n.x, n.z)
		barricades.append(b)
		FX.puff(hit.position + Vector3(0, 0.2, 0), Color(1, 0.85, 0.6))
	for m in members: m.build_t = BUILD_T
	Snd.at("crane_move", line_c, -6, 0.1)
