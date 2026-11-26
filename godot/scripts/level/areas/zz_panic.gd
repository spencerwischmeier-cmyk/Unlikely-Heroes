extends RefCounted
## The city in a panic (citizens, air traffic, the docks evacuation): see scripts/level/panic/panic.gd.
## Named zz_ so it runs after every other area file and can read all their islands.

const Panic := preload("res://scripts/level/panic/panic.gd")

static func build(L) -> void:
	if OS.get_cmdline_user_args().has("--no-panic"): return
	var p: Node3D = Panic.new()
	p.name = "Panic"
	p.setup(L)
	L.add_child(p)
