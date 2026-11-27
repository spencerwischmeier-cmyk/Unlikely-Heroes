"""After the first import: make every 3D texture VRAM-compressed (ETC2/ASTC on phones).

Godot only switches a texture to VRAM compression after the editor sees it used in 3D, which never
happens in a headless build, so they would stay lossless and use 4 bytes per pixel of GPU memory.
Phones can't spare that. Normal maps get the normal-map flag so they compress correctly.
"""
import os, re, sys
root = sys.argv[1]
n = 0
for d, _, fs in os.walk(root):
    if "/.godot" in d:
        continue
    for f in fs:
        if not f.endswith(".import"):
            continue
        p = os.path.join(d, f)
        s = open(p).read()
        if 'importer="texture"' not in s or ("/textures/" not in p and "/models/" not in p):
            continue
        t = re.sub(r"^compress/mode=\d+", "compress/mode=2", s, flags=re.M)
        if "normal" in f.lower():
            t = re.sub(r"^compress/normal_map=\d+", "compress/normal_map=1", t, flags=re.M)
        t = re.sub(r"^mipmaps/generate=\w+", "mipmaps/generate=true", t, flags=re.M)
        if t != s:
            open(p, "w").write(t); n += 1
print(f"[imports] {n} textures set to VRAM compression")
