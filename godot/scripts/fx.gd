extends Node3D
## Particle effects: sparks, explosions with flying scrap, dust puffs, shock rings, muzzle flashes.
## Autoloaded as FX. Everything is pooled-light: short-lived CPUParticles3D that free themselves.

var shake_request := 0.0
var hitstop := 0.0
var _spark_mesh: Mesh
var _fire_mesh: Mesh
var _smoke_mesh: Mesh
var _chunk_mesh: Mesh

func _ready() -> void:
	var q := QuadMesh.new(); q.size = Vector2(0.12, 0.12)
	_spark_mesh = q
	var f := QuadMesh.new(); f.size = Vector2(1, 1)
	_fire_mesh = f
	_smoke_mesh = f
	var c := BoxMesh.new(); c.size = Vector3(0.18, 0.12, 0.22)
	_chunk_mesh = c

func _bill(color: Color, energy: float, tex := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = color * energy
	m.albedo_color.a = 1.0
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft_tex()
	return m

var _soft: GradientTexture2D
func _soft_tex() -> GradientTexture2D:
	if _soft: return _soft
	_soft = GradientTexture2D.new()
	_soft.fill = GradientTexture2D.FILL_RADIAL
	_soft.fill_from = Vector2(0.5, 0.5); _soft.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1)); g.set_color(1, Color(1, 1, 1, 0))
	_soft.gradient = g
	_soft.width = 64; _soft.height = 64
	return _soft

func _emit(pos: Vector3, mesh: Mesh, mat: Material, amount: int, life: float, speed: Vector2, gravity: Vector3, scale: Vector2, spread := 180.0, dir := Vector3.UP, fade := true) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.mesh = mesh
	p.material_override = mat
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 0.95
	p.direction = dir
	p.spread = spread
	p.initial_velocity_min = speed.x; p.initial_velocity_max = speed.y
	p.gravity = gravity
	p.scale_amount_min = scale.x; p.scale_amount_max = scale.y
	p.damping_min = 1.0; p.damping_max = 3.0
	if fade:
		var cr := Curve.new(); cr.add_point(Vector2(0, 1)); cr.add_point(Vector2(1, 0))
		p.scale_amount_curve = cr
	p.local_coords = false
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(life + 0.2).timeout.connect(p.queue_free)
	return p

func sparks(pos: Vector3, color := Color(0.7, 0.98, 1.0), n := 12, speed := 6.0) -> void:
	_emit(pos, _spark_mesh, _bill(color, 3.0), n, 0.35, Vector2(speed * 0.3, speed), Vector3(0, -12, 0), Vector2(0.6, 1.4))
	_emit(pos, _fire_mesh, _bill(color, 2.0), 1, 0.12, Vector2.ZERO, Vector3.ZERO, Vector2(0.6, 0.6))

func puff(pos: Vector3, color := Color(0.85, 0.9, 1.0)) -> void:
	var m := _bill(color, 0.6); m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	_emit(pos, _smoke_mesh, m, 8, 0.6, Vector2(0.5, 2.0), Vector3(0, 0.5, 0), Vector2(0.3, 0.7), 80, Vector3.UP)

func explosion(pos: Vector3, scale := 1.0, chunk_mats: Array = []) -> void:
	_emit(pos, _fire_mesh, _bill(Color(1.0, 0.6, 0.2), 3.0), 14, 0.55, Vector2(1, 4) * scale, Vector3(0, 1.5, 0), Vector2(1.2, 2.6) * scale)
	_emit(pos, _fire_mesh, _bill(Color(1.0, 0.95, 0.8), 4.0), 3, 0.18, Vector2(0, 1), Vector3.ZERO, Vector2(2.5, 3.5) * scale)
	var sm := _bill(Color(0.42, 0.44, 0.5), 1.0); sm.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	sm.albedo_color.a = 0.55
	_emit(pos, _smoke_mesh, sm, 10, 1.6, Vector2(0.5, 2) * scale, Vector3(0, 1.2, 0), Vector2(1.2, 3.0) * scale)
	_emit(pos, _spark_mesh, _bill(Color(1, 0.7, 0.25), 3.0), 24, 0.6, Vector2(4, 12) * scale, Vector3(0, -9, 0), Vector2(0.6, 1.6))
	# scrap chunks with real lighting that tumble and bounce
	var chunk_mat: Material = chunk_mats[0] if chunk_mats.size() > 0 else load_chunk_mat()
	var c := _emit(pos, _chunk_mesh, chunk_mat, 12, 1.4, Vector2(4, 9) * scale, Vector3(0, -18, 0), Vector2(0.6, 1.8) * scale, 70, Vector3.UP, false)
	c.angular_velocity_min = -720; c.angular_velocity_max = 720
	c.particle_flag_rotate_y = true
	var light := OmniLight3D.new(); light.light_color = Color(1, 0.6, 0.25); light.light_energy = 8.0 * scale; light.omni_range = 9 * scale
	add_child(light); light.global_position = pos
	var tw := create_tween(); tw.tween_property(light, "light_energy", 0.0, 0.35); tw.tween_callback(light.queue_free)
	ring(pos, Color(1, 0.7, 0.3), scale)

var _chunk_default: StandardMaterial3D
func load_chunk_mat() -> StandardMaterial3D:
	if not _chunk_default:
		_chunk_default = StandardMaterial3D.new(); _chunk_default.albedo_color = Color(0.3, 0.33, 0.38); _chunk_default.metallic = 0.8; _chunk_default.roughness = 0.4
	return _chunk_default

func ring(pos: Vector3, color: Color, scale := 1.0) -> void:
	var t := TorusMesh.new(); t.inner_radius = 0.9; t.outer_radius = 1.0; t.rings = 32
	var mi := MeshInstance3D.new(); mi.mesh = t
	var m := StandardMaterial3D.new(); m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD; m.albedo_color = color * 2.0
	mi.material_override = m
	add_child(mi); mi.global_position = pos; mi.scale = Vector3.ONE * 0.4
	var tw := create_tween().set_parallel()
	tw.tween_property(mi, "scale", Vector3(4, 1, 4) * scale, 0.35)
	tw.tween_property(m, "albedo_color", Color(0, 0, 0, 0), 0.35)
	tw.chain().tween_callback(mi.queue_free)

func shake(n: float) -> void:
	shake_request = maxf(shake_request, n)

func stop(t: float) -> void:
	hitstop = maxf(hitstop, t)
