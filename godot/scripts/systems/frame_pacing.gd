extends Node
## Frame pacing. With plain vsync a frame that runs a little past the screen's refresh waits for the
## next one, so a 20 ms frame shows as a 33 ms hitch. `--vsync=adaptive|mailbox|off|on` picks the mode
## for testing; `--max-fps=N` caps the rate (handy with vsync off). The web build keeps the browser's own pacing.

func _ready() -> void:
	if OS.has_feature("web"): return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--vsync="):
			var m: String = a.get_slice("=", 1)
			var mode: int = { "off": DisplayServer.VSYNC_DISABLED, "on": DisplayServer.VSYNC_ENABLED,
				"adaptive": DisplayServer.VSYNC_ADAPTIVE, "mailbox": DisplayServer.VSYNC_MAILBOX }.get(m, DisplayServer.VSYNC_ENABLED)
			DisplayServer.window_set_vsync_mode(mode)
			print("[pacing] vsync ", m, " -> ", DisplayServer.window_get_vsync_mode(), "  screen ", DisplayServer.screen_get_refresh_rate(), " Hz")
		elif a.begins_with("--max-fps="):
			Engine.max_fps = int(a.get_slice("=", 1))
