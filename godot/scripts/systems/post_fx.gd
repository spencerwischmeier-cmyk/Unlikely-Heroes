extends Node
## Anti-aliasing for the rich lighting pass: temporal AA (steadier volumetric fog, smoke, thin cables and
## SDFGI, no shimmer on the bevelled scrap) instead of 2x MSAA + FXAA. `--no-taa` keeps the old setup.

func _ready() -> void:
	if OS.get_cmdline_user_args().has("--no-taa"): return
	var vp := get_viewport()
	vp.use_taa = true
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
