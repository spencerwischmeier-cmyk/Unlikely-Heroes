class_name Kit
## The Skyharbor art kit. Level code places props by name; the models live in res://models/kit/<name>.glb
## (made by art/skyharbor_kit.py in Blender, textures by art/skyharbor_textures.py). If a model is missing, a
## grey placeholder box is used so layout work never blocks on art.
##
## Every prop: origin at the base center (y = 0 sits on the floor), +Z is its front, sizes in SIZES (metres,
## the footprint used for the default box collider). Kit swaps the imported materials for the textured ones in
## mats.gd, spins rotors and fans, waves flags and lights lamps.
##
## Prop names (keep this list in sync with the Blender script):
##   crate_small, crate_large, barrel, cargo_container, lamp_post, railing_2m, railing_post, bench,
##   planter, market_stall, awning, wind_turbine, vent_stack, antenna, pipe_straight, pipe_corner,
##   sign_board, flag_pole, dish_small, generator, junk_pile, scrap_heap, workbench, porch_chair,
##   gull_nest, bank_vault_door, turbine_switch, chimney, water_tower, hanging_container, gantry
## Hero landmark pieces:
##   signal_mast_top   platform (walkable top at y 0.73, railing gap faces +Z) with the relay dish.
##                     Parts: "dish" (yaw it to align), "dish_glow" (orange rim + feed; use set_glow to pulse).
##   crane_yard_gate   8 m gate, 5.2 m wide opening. Parts: "door_L"/"door_R" (slide them along x to open, their
##                     colliders move with them), "lock_light" (red; set_glow green when unlocked).
##   junkyard_porch    Vesk's porch: floor top at y 0.45, steps toward +Z, back wall with door, sign and lamp.
##   gizmart_kiosk     vending-machine shop. Parts: "eyes", "grin" (light-up grin; use set_glow/flash).
##   sky_island_rim    4 m deck edge segment along X, +Z faces the sky. Walkable top at y 1.2: place it at
##                     y = deck_top - 1.2 on the deck edge, one every 4 m.
## Other named parts: wind_turbine "rotor", vent_stack "fan", flag_pole "flag" (animated automatically),
##   dish_small "dish", bank_vault_door "door" (hinge on its left edge) / "wheel" / "lock_light",
##   turbine_switch "lever" (rotate about x) / "status_light", gantry "trolley".
## pipe_corner ends: (0.3, 0.3, -0.3) facing -Z and (-0.3, 0.3, 0.3) facing -X; pipe_straight runs along Z, 2 m.

const M := preload("res://scripts/mats.gd")

const SIZES := {
	"crate_small": Vector3(1, 1, 1), "crate_large": Vector3(1.6, 1.6, 1.6), "barrel": Vector3(0.9, 1.2, 0.9),
	"cargo_container": Vector3(5, 2.5, 2.4), "lamp_post": Vector3(0.5, 4.2, 0.5), "railing_2m": Vector3(2, 1.1, 0.15),
	"railing_post": Vector3(0.24, 1.3, 0.24), "bench": Vector3(2.1, 0.9, 0.7), "planter": Vector3(1.6, 0.9, 1.6),
	"market_stall": Vector3(3.2, 2.8, 2.2), "awning": Vector3(3, 0.7, 1.5), "wind_turbine": Vector3(3, 8.5, 3),
	"vent_stack": Vector3(1.2, 3, 1.2), "antenna": Vector3(0.6, 5.2, 0.6), "pipe_straight": Vector3(0.6, 0.6, 2),
	"pipe_corner": Vector3(1.1, 0.6, 1.1), "sign_board": Vector3(2, 2.2, 0.3), "flag_pole": Vector3(0.5, 5.1, 0.5),
	"dish_small": Vector3(1.2, 1.5, 1.2), "generator": Vector3(2, 1.6, 1.4), "junk_pile": Vector3(3, 1.5, 3),
	"scrap_heap": Vector3(5, 2.5, 5), "workbench": Vector3(2.2, 1, 1), "porch_chair": Vector3(0.9, 1, 0.9),
	"gull_nest": Vector3(1.2, 0.5, 1.2), "bank_vault_door": Vector3(3, 3, 0.6), "turbine_switch": Vector3(0.8, 1.3, 0.6),
	"chimney": Vector3(1, 3.1, 1), "water_tower": Vector3(3, 6.4, 3), "hanging_container": Vector3(5, 3.45, 2.4),
	"gantry": Vector3(8, 6.2, 1.5),
	"signal_mast_top": Vector3(4, 4.6, 4), "crane_yard_gate": Vector3(8, 6.4, 1.6), "junkyard_porch": Vector3(6.4, 3.7, 4.6),
	"gizmart_kiosk": Vector3(2.2, 3.1, 1.4), "sky_island_rim": Vector3(4, 1.45, 1.1),
}

## Props whose collision is not one big box: [center, size] boxes, optionally a third entry naming the part
## node the box belongs to (it then moves with that part).
const COLLIDERS := {
	"lamp_post": [[Vector3(0, 2.1, 0), Vector3(0.3, 4.2, 0.3)]],
	"flag_pole": [[Vector3(0, 2.5, 0), Vector3(0.3, 5, 0.3)]],
	"antenna": [[Vector3(0, 2.5, 0), Vector3(0.5, 5, 0.5)]],
	"wind_turbine": [[Vector3(0, 3.5, 0), Vector3(1.4, 7, 1.4)]],
	"market_stall": [[Vector3(0, 0.5, 0.5), Vector3(3.1, 1.0, 0.95)], [Vector3(0, 2.62, 0.05), Vector3(3.2, 0.3, 2.2)]],
	"awning": [],
	"hanging_container": [[Vector3(0, 1.25, 0), Vector3(5, 2.5, 2.4)]],
	"gantry": [[Vector3(-3.6, 2.9, 0), Vector3(0.9, 5.8, 1.4)], [Vector3(3.6, 2.9, 0), Vector3(0.9, 5.8, 1.4)], [Vector3(0, 5.75, 0), Vector3(8, 0.75, 1.3)]],
	"water_tower": [[Vector3(0, 1.7, 0), Vector3(2.4, 3.4, 2.4)], [Vector3(0, 4.6, 0), Vector3(2.5, 2.6, 2.5)]],
	"signal_mast_top": [[Vector3(0, 0.36, 0), Vector3(3.9, 0.73, 3.9)], [Vector3(0, 1.8, 0), Vector3(0.7, 2.2, 0.7)]],
	"crane_yard_gate": [[Vector3(-3.3, 3, 0), Vector3(1.4, 6, 1.4)], [Vector3(3.3, 3, 0), Vector3(1.4, 6, 1.4)],
		[Vector3(0, 5.2, 0), Vector3(5.4, 1.0, 0.8)],
		[Vector3(0, 2.3, 0), Vector3(2.6, 4.5, 0.3), "door_L"], [Vector3(0, 2.3, 0), Vector3(2.6, 4.5, 0.3), "door_R"]],
	"junkyard_porch": [[Vector3(0, 0.225, 0), Vector3(6, 0.45, 3.4)], [Vector3(0, 0.14, 2.1), Vector3(1.6, 0.28, 0.7)],
		[Vector3(0, 1.95, -1.62), Vector3(6, 3.0, 0.24)], [Vector3(0, 3.45, 0.05), Vector3(6.4, 0.25, 4.0)],
		[Vector3(-2.85, 1.9, 1.55), Vector3(0.2, 3, 0.2)], [Vector3(2.85, 1.9, 1.55), Vector3(0.2, 3, 0.2)]],
	"sky_island_rim": [[Vector3(0, 0.6, 0), Vector3(4, 1.2, 1.0)], [Vector3(0, 1.32, 0.41), Vector3(4, 0.25, 0.18)]],
	"railing_2m": [[Vector3(0, 0.55, 0), Vector3(2, 1.1, 0.15)]],
	"scrap_heap": [[Vector3(0, 0.8, 0), Vector3(4.2, 1.6, 4.2)]],
	"junk_pile": [[Vector3(0, 0.5, 0), Vector3(2.6, 1.0, 2.6)]],
}

## Auto animation for named parts: [property, amount, seconds, mode] mode "spin" or "sway".
const ANIMS := {
	"rotor": ["rotation:z", TAU, 3.5, "spin"],
	"fan": ["rotation:y", TAU, 1.2, "spin"],
	"flag": ["rotation:y", 0.35, 1.6, "sway"],
}

## Set false before building a level to skip the small lamp lights (e.g. for low-end devices).
static var lights_enabled := true
static var _cache := {}

## Place a prop. collide adds box colliders (SIZES footprint, or the COLLIDERS boxes for that prop).
static func place(parent: Node, prop: String, pos: Vector3, rot_y := 0.0, scale := 1.0, collide := true) -> Node3D:
	var root := Node3D.new(); root.position = pos; root.rotation.y = rot_y; root.scale = Vector3.ONE * scale
	root.name = prop
	parent.add_child(root)
	var path := "res://models/kit/%s.glb" % prop
	var size: Vector3 = SIZES.get(prop, Vector3.ONE)
	if ResourceLoader.exists(path):
		var model := _instance(prop, path)
		root.add_child(model)
		_decorate(root, model)
	else:
		var bm := BoxMesh.new(); bm.size = size
		var mi := MeshInstance3D.new(); mi.mesh = bm; mi.position.y = size.y / 2
		var m := StandardMaterial3D.new(); m.albedo_color = Color(0.6, 0.6, 0.65); mi.material_override = m
		root.add_child(mi)
	if collide:
		var boxes: Array = COLLIDERS.get(prop, [[Vector3(0, size.y / 2, 0), size]])
		for b in boxes:
			var host: Node3D = root
			if b.size() > 2:
				var part := find_part(root, b[2])
				if part: host = part
			var sb := StaticBody3D.new(); var cs := CollisionShape3D.new(); var sh := BoxShape3D.new()
			sh.size = b[1]; cs.shape = sh; sb.add_child(cs)
			host.add_child(sb)
			sb.transform = _rel(root, host).affine_inverse() * Transform3D(Basis(), b[0])
	return root

## Find a named part (e.g. "dish", "door_L", "lock_light") inside a placed prop.
static func find_part(prop_root: Node, part: String) -> Node3D:
	return prop_root.find_child(part, true, false) as Node3D

## Recolor a glowing part (e.g. set_glow(gate, "lock_light", Color.GREEN)).
static func set_glow(prop_root: Node, part: String, color: Color, energy := 3.0) -> void:
	var n := find_part(prop_root, part)
	if n == null: return
	for mi in _meshes(n):
		mi.material_override = M.glow(color, energy)

## Briefly flash a glowing part brighter (e.g. the Gizmart grin when you buy something, the mast dish pulse).
static func flash(prop_root: Node, part: String, color: Color, peak := 9.0, rest := 3.0, seconds := 0.6) -> void:
	var n := find_part(prop_root, part)
	if n == null or not n.is_inside_tree(): return
	var mat := M.glow(color, peak)
	for mi in _meshes(n): mi.material_override = mat
	var tw := n.create_tween()
	tw.tween_property(mat, "emission_energy_multiplier", rest, seconds).set_trans(Tween.TRANS_SINE)

## Transform of `node` relative to its ancestor `top`.
static func _rel(top: Node, node: Node) -> Transform3D:
	var t := Transform3D()
	var n := node
	while n and n != top:
		if n is Node3D: t = (n as Node3D).transform * t
		n = n.get_parent()
	return t

static func _meshes(n: Node) -> Array:
	var out := []
	if n is MeshInstance3D: out.append(n)
	for c in n.get_children():
		if c is MeshInstance3D: out.append(c)
	return out

# ---------------------------------------------------------------- internals
static func _instance(prop: String, path: String) -> Node3D:
	if not _cache.has(prop):
		var ps: PackedScene = load(path)
		_cache[prop] = ps
		# Swap imported materials for the shared textured ones. Meshes are shared between instances, so
		# doing it once on the first instance covers every later one.
		var tmp := ps.instantiate()
		_swap_materials(tmp)
		tmp.free()
	return _cache[prop].instantiate()

static func _swap_materials(n: Node) -> void:
	if n is MeshInstance3D and n.mesh:
		var mesh: Mesh = n.mesh
		for i in mesh.get_surface_count():
			var old := mesh.surface_get_material(i)
			if old == null: continue
			var nm := M.kit(old.resource_name)
			if nm: mesh.surface_set_material(i, nm)
			elif old.resource_name.begins_with("k_sign_") and old is BaseMaterial3D:
				var sm: BaseMaterial3D = old  # signs: keep the decal, make it softly self-lit so it reads in shade
				sm.emission_enabled = true
				sm.emission_texture = sm.albedo_texture
				sm.emission = Color.WHITE
				sm.emission_energy_multiplier = 0.35
				sm.roughness = 0.45
	for c in n.get_children(): _swap_materials(c)

static func _decorate(root: Node3D, model: Node) -> void:
	for part in ANIMS:
		var n := model.find_child(part, true, false) as Node3D
		if n: _animate(n, ANIMS[part])
	if lights_enabled:
		for c in model.find_children("light_*", "", true, false):
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.78, 0.5)
			l.light_energy = 1.4
			l.omni_range = 5.0
			l.omni_attenuation = 1.4
			l.shadow_enabled = false
			l.light_specular = 0.3
			c.add_child(l)

static func _animate(n: Node3D, a: Array) -> void:
	if not n.is_inside_tree():
		n.tree_entered.connect(_animate.bind(n, a), CONNECT_ONE_SHOT)
		return
	var tw := n.create_tween().set_loops()
	var phase := fmod(absf(n.global_position.x * 0.37 + n.global_position.z * 0.21), 1.0)
	if a[3] == "spin":
		n.set_indexed(a[0], phase * TAU)
		tw.tween_property(n, a[0], a[1], a[2]).as_relative()
	else:
		tw.tween_property(n, a[0], a[1], a[2] * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(n, a[0], -a[1], a[2] * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
