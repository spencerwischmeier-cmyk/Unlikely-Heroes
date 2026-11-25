extends Node
## Test helper. Run with `-- --shot=out.png --frames=90` to save a screenshot after N frames and quit.
## `--script=name` runs a scripted input scenario from scripts/test_scenarios.gd.

var path := ""
var frames := 0
var scenario := ""
var _n := 0

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="): path = a.substr(7)
		elif a.begins_with("--frames="): frames = int(a.substr(9))
		elif a.begins_with("--scenario="): scenario = a.substr(11)
	process_priority = 1000

func _process(_dt: float) -> void:
	if path == "" and scenario == "": return
	_n += 1
	if path != "" and _n == frames:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(path)
		print("saved ", path)
		get_tree().quit()
