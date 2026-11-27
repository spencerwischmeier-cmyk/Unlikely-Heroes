extends Node
## Debug: `-- --floor-top=<prefix>` renders the level straight down in 80 m tiles (orthographic) and saves
## <prefix>_<col>_<row>.png, then quits; for checking every floor's surface and the seams between areas.
## Run with --no-title --no-cutscenes and a square window (--resolution 1024x1024).

var prefix := ""
var tiles: Array = []
var _i := 0
var _f := 0
var cam: Camera3D

func _ready() -> void:
	for cz in range(130, -210, -80):
		for cx in range(-120, 121, 80):
			tiles.append(Vector2(cx + 40, cz - 40))
	cam = Camera3D.new(); cam.projection = Camera3D.PROJECTION_ORTHOGONAL; cam.size = 80.0
	cam.far = 400.0; add_child(cam)

func _process(_dt: float) -> void:
	_f += 1
	if _f % 20 == 0: print("[floor-top] frame %d tile %d" % [_f, _i])
	if _f < 60: return
	for c in get_tree().root.find_children("*", "CanvasLayer", true, false): (c as CanvasLayer).visible = false
	if _i >= tiles.size(): get_tree().quit(); return
	var t: Vector2 = tiles[_i]
	cam.current = true
	cam.global_transform = Transform3D(Basis.from_euler(Vector3(-PI / 2, 0, 0)), Vector3(t.x, 150, t.y))
	if _f % 6 == 0:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s_%02d.png" % [prefix, _i])
		_i += 1
