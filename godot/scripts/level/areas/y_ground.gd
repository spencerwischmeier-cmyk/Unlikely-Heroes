extends RefCounted
## Per-area ground surfaces, edging, clutter and decals: see scripts/level/ground/ground.gd.
## Named y_ so it runs after every area file has built its floors (and before zz_panic).

const Ground := preload("res://scripts/level/ground/ground.gd")

static func build(L) -> void:
	var g: Node3D = Ground.new()
	g.name = "Ground"
	L.add_child(g)
	g.setup(L)
