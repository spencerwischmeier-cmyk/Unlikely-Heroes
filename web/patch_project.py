"""Web/phone settings for the exported copy of project.godot (the PC project is left alone)."""
import re, sys

p = sys.argv[1]
s = open(p).read()

def setting(section, key, value):
    global s
    line = f"{key}={value}"
    if re.search(rf"^{re.escape(key)}=.*$", s, flags=re.M):
        s = re.sub(rf"^{re.escape(key)}=.*$", line.replace("\\", "\\\\"), s, flags=re.M)
    elif f"[{section}]" in s:
        s = s.replace(f"[{section}]\n", f"[{section}]\n{line}\n", 1)
    else:
        s += f"\n[{section}]\n{line}\n"

s = s.replace('"Forward Plus"', '"GL Compatibility"')
setting("rendering", "renderer/rendering_method", '"gl_compatibility"')
setting("rendering", "renderer/rendering_method.mobile", '"gl_compatibility"')
setting("rendering", "textures/vram_compression/import_etc2_astc", "true")
setting("rendering", "anti_aliasing/quality/msaa_3d", "0")
setting("rendering", "anti_aliasing/quality/screen_space_aa", "0")
setting("rendering", "lights_and_shadows/directional_shadow/size", "2048")
setting("rendering", "lights_and_shadows/directional_shadow/soft_shadow_filter_quality", "1")
setting("rendering", "lights_and_shadows/positional_shadow/soft_shadow_filter_quality", "0")
setting("rendering", "lights_and_shadows/positional_shadow/atlas_size", "1024")
setting("rendering", "limits/opengl/max_lights_per_object", "4")
setting("rendering", "environment/defaults/default_clear_color", "Color(0.33, 0.6, 0.76, 1)")
# phones: 60 physics ticks instead of 120 (physics_interpolation keeps motion smooth)
setting("physics", "common/physics_ticks_per_second", "60")
setting("physics", "common/max_physics_steps_per_frame", "4")
# touch: keep taps working on menus (emulated mouse), but the game ignores emulated clicks for firing
setting("input_devices", "pointing/emulate_mouse_from_touch", "true")
setting("display", "window/handheld/orientation", "4")   # sensor landscape
setting("display", "window/energy_saving/keep_screen_on", "true")
open(p, "w").write(s)
print("[project] web settings applied")

# WebGL caps per-instance shader values at 4096 slots for the whole scene and Skyharbor has more pieces
# than that, so the web build turns them into plain uniforms. The shaders fall back to their defaults:
# painted steel uses noise-only wear (no fake bevel), ground tiles skip edge darkening and random offsets.
import glob, os
root = os.path.dirname(p)
for sh in glob.glob(os.path.join(root, "shaders", "*.gdshader")):
    t = open(sh).read()
    if "instance uniform" in t:
        open(sh, "w").write(t.replace("instance uniform", "uniform"))
        print("[project] per-instance uniforms off in", os.path.basename(sh))
# ...and the scripts that set those values would still reserve a slot each, so they store a harmless meta instead
for gd in glob.glob(os.path.join(root, "scripts", "**", "*.gd"), recursive=True):
    t = open(gd).read()
    if "_instance_shader_parameter(" in t:
        open(gd, "w").write(t.replace(".set_instance_shader_parameter(", ".set_meta(").replace(".get_instance_shader_parameter(", ".get_meta("))
