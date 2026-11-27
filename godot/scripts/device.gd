extends RefCounted
## What the game is running on, and how much it should draw. Static helpers, no autoload needed:
##   const Device := preload("res://scripts/device.gd")
##   if Device.phone(): ...      Device.scale(30) -> fewer of something on phones
##
## Tiers: "pc" (the Windows build, everything on), "web" (a browser on a laptop/desktop: WebGL 2,
## lighter effects), "phone" (a phone or tablet browser: lighter still, touch controls).
## Override for testing: command line `--quality=phone|web|pc` or `--touch`, or in the browser
## add `?quality=phone` or `?touch=1` to the address.

static var _tier := ""
static var _touch := -1

static func tier() -> String:
	if _tier != "": return _tier
	var forced := _arg("quality")
	if forced in ["phone", "web", "pc"]:
		_tier = forced
	elif OS.has_feature("web_android") or OS.has_feature("web_ios") or OS.has_feature("android") or OS.has_feature("ios"):
		_tier = "phone"
	elif OS.has_feature("web"):
		_tier = "phone" if _js_bool("matchMedia('(pointer: coarse)').matches && Math.min(screen.width, screen.height) < 900") else "web"
	else:
		_tier = "pc"
	return _tier

static func phone() -> bool:
	return tier() == "phone"

## the WebGL / phone builds (anything that isn't the full PC renderer)
static func lite() -> bool:
	return tier() != "pc" or RenderingServer.get_current_rendering_method() == "gl_compatibility"

## true when on-screen touch controls should show from the start
static func touch() -> bool:
	if _touch == -1:
		var f := _arg("touch")
		if f != "": _touch = 1 if f in ["1", "true", "yes", "on"] else 0
		else: _touch = 1 if (phone() or DisplayServer.is_touchscreen_available() and OS.has_feature("web") and _js_bool("matchMedia('(pointer: coarse)').matches")) else 0
	return _touch == 1

static func set_touch(on: bool) -> void:
	_touch = 1 if on else 0

## scale a count (citizens, cars, particles) for this device; never below `min_n`
static func scale(n: int, min_n := 1) -> int:
	var f := {"pc": 1.0, "web": 0.7, "phone": 0.45}[tier()] as float
	return maxi(mini(n, min_n), int(round(n * f)))

## a float multiplier for draw distances etc.
static func reach() -> float:
	return {"pc": 1.0, "web": 0.8, "phone": 0.6}[tier()]

static func _arg(key: String) -> String:
	for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if a == "--" + key: return "1"
		if a.begins_with("--" + key + "="): return a.substr(key.length() + 3)
	if OS.has_feature("web"):
		var v = JavaScriptBridge.eval("new URLSearchParams(location.search).get('%s') || ''" % key, true)
		if v is String: return v
	return ""

static func _js_bool(expr: String) -> bool:
	if not OS.has_feature("web"): return false
	return bool(JavaScriptBridge.eval("!!(%s)" % expr, true))
