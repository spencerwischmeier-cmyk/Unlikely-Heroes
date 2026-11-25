class_name Kit
## The Skyharbor art kit. Level code places props by name; the models live in res://models/kit/<name>.glb
## (made by art/skyharbor_kit.py in Blender). If a model is missing, a grey placeholder box is used so
## layout work never blocks on art.
##
## Prop names (keep this list in sync with the Blender script):
##   crate_small, crate_large, barrel, cargo_container, lamp_post, railing_2m, railing_post, bench,
##   planter, market_stall, awning, wind_turbine, vent_stack, antenna, pipe_straight, pipe_corner,
##   sign_board, flag_pole, dish_small, generator, junk_pile, scrap_heap, workbench, porch_chair,
##   gull_nest, bank_vault_door, turbine_switch, chimney, water_tower, hanging_container, gantry

const SIZES := {
	"crate_small": Vector3(1, 1, 1), "crate_large": Vector3(1.6, 1.6, 1.6), "barrel": Vector3(0.9, 1.2, 0.9),
	"cargo_container": Vector3(5, 2.5, 2.4), "lamp_post": Vector3(0.4, 4, 0.4), "railing_2m": Vector3(2, 1.1, 0.15),
	"bench": Vector3(2, 0.9, 0.7), "planter": Vector3(1.6, 0.9, 1.6), "market_stall": Vector3(3.2, 2.8, 2.0),
	"wind_turbine": Vector3(3, 8, 3), "vent_stack": Vector3(1.2, 3, 1.2), "antenna": Vector3(0.6, 5, 0.6),
	"generator": Vector3(2, 1.6, 1.4), "junk_pile": Vector3(3, 1.5, 3), "scrap_heap": Vector3(5, 2.5, 5),
	"workbench": Vector3(2.2, 1, 1), "porch_chair": Vector3(0.9, 1, 0.9), "bank_vault_door": Vector3(3, 3, 0.6),
	"turbine_switch": Vector3(0.8, 1.3, 0.6), "water_tower": Vector3(3, 6, 3), "hanging_container": Vector3(5, 2.5, 2.4),
	"gantry": Vector3(8, 6, 1.5),
}

static var _cache := {}

## Place a prop. collide adds a box collider from the prop's size (good enough for gameplay).
static func place(parent: Node, prop: String, pos: Vector3, rot_y := 0.0, scale := 1.0, collide := true) -> Node3D:
	var root := Node3D.new(); root.position = pos; root.rotation.y = rot_y; root.scale = Vector3.ONE * scale
	parent.add_child(root)
	var path := "res://models/kit/%s.glb" % prop
	var size: Vector3 = SIZES.get(prop, Vector3.ONE)
	if ResourceLoader.exists(path):
		if not _cache.has(prop): _cache[prop] = load(path)
		root.add_child(_cache[prop].instantiate())
	else:
		var bm := BoxMesh.new(); bm.size = size
		var mi := MeshInstance3D.new(); mi.mesh = bm; mi.position.y = size.y / 2
		var m := StandardMaterial3D.new(); m.albedo_color = Color(0.6, 0.6, 0.65); mi.material_override = m
		root.add_child(mi)
	if collide:
		var sb := StaticBody3D.new(); var cs := CollisionShape3D.new(); var sh := BoxShape3D.new()
		sh.size = size; cs.shape = sh; cs.position.y = size.y / 2; sb.add_child(cs); root.add_child(sb)
	return root
