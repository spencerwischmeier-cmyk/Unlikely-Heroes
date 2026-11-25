extends Node3D
## A switch for "activate" story zones: a lever box (Kit prop "turbine_switch") you hit once with the
## wrench or a bolt. Red light = off, green = on. It is in the "targets" group so combat can hit it.

signal activated(sw: Node3D)

var dead := false          # true once thrown (combat skips dead targets)
var label_text := ""
var lamp_mat := StandardMaterial3D.new()
var light := OmniLight3D.new()
var lever := Node3D.new()
var pulse := 0.0

func _ready() -> void:
	add_to_group("targets"); add_to_group("switches")
	Kit.place(self, "turbine_switch", Vector3.ZERO, 0.0, 1.0, true)
	lamp_mat.albedo_color = Color.BLACK; lamp_mat.emission_enabled = true
	lamp_mat.emission = Color(1, 0.2, 0.15); lamp_mat.emission_energy_multiplier = 5.0
	var s := SphereMesh.new(); s.radius = 0.16; s.height = 0.32
	var lm := MeshInstance3D.new(); lm.mesh = s; lm.material_override = lamp_mat; lm.position = Vector3(0, 1.5, 0); add_child(lm)
	lever.position = Vector3(0, 1.0, 0.32); add_child(lever)
	var bm := BoxMesh.new(); bm.size = Vector3(0.12, 0.7, 0.12)
	var lv := MeshInstance3D.new(); lv.mesh = bm; lv.position.y = 0.35
	var m := StandardMaterial3D.new(); m.albedo_color = Color(0.95, 0.75, 0.2); m.metallic = 0.8; m.roughness = 0.3
	lv.material_override = m; lever.add_child(lv)
	lever.rotation.x = -0.7
	light.light_color = Color(1, 0.25, 0.2); light.light_energy = 2.0; light.omni_range = 5.0; light.position = Vector3(0, 1.8, 0)
	add_child(light)
	# hitbox on the enemy layer so bolts register it (combat reads the "owner" meta)
	var sb := StaticBody3D.new(); sb.collision_layer = 4; sb.collision_mask = 0
	var cs := CollisionShape3D.new(); var sh := BoxShape3D.new(); sh.size = Vector3(1.2, 1.9, 1.0)
	cs.shape = sh; cs.position.y = 0.95; sb.add_child(cs); add_child(sb); sb.set_meta("owner", self)
	if label_text != "":
		var l := Label3D.new(); l.text = label_text; l.font_size = 64; l.pixel_size = 0.006
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED; l.position = Vector3(0, 2.4, 0)
		l.modulate = Color(1, 0.85, 0.5); l.outline_size = 12; add_child(l)

func center() -> Vector3:
	return global_position + Vector3(0, 1.0, 0)

func damage(_amount: float, _p: Vector3, _d: Vector3) -> bool:
	if dead: return false
	dead = true
	lamp_mat.emission = Color(0.3, 1, 0.45); light.light_color = Color(0.3, 1, 0.45)
	var tw := create_tween(); tw.tween_property(lever, "rotation:x", 0.7, 0.18).set_trans(Tween.TRANS_BACK)
	FX.sparks(center(), Color(1, 0.9, 0.5), 18, 6)
	Snd.at("rail_unlock", center(), -2)
	activated.emit(self)
	return true

func _process(dt: float) -> void:
	if dead: return
	pulse += dt
	lamp_mat.emission_energy_multiplier = 4.0 + sin(pulse * 6.0) * 2.5
