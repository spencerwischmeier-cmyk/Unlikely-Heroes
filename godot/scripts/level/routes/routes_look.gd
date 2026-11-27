extends RefCounted

static func on() -> bool:
	return not OS.get_cmdline_user_args().has("--no-routes-look")

static func build(L: Node3D) -> void:
	pass
