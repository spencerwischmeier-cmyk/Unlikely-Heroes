extends SceneTree
func _init():
	var L = load("res://scripts/level_skyharbor.gd").new()
	root.add_child(L)
	await process_frame
	for k in L.islands: print(k, " ", L.islands[k])
	quit()
