"""Shrinks loose textures and re-encodes audio in the web copy of the project (see build.sh).

Textures only ever get smaller. Signs and painted text keep more width so they stay readable.
Music stays stereo at ~80 kbps; effects and voices go mono, which is all a phone speaker plays anyway.
"""
import os, subprocess, sys
from concurrent.futures import ThreadPoolExecutor
from PIL import Image

root = sys.argv[1]
TEX_DEFAULT = int(os.environ.get("TEX_MAX", 512))
TEX_SHARP = 1024   # signs, painted text, decals, Vesk


CHARS = ("/chars/", "/citizens/")


def looks_like_normal_map(im):
    """Tangent-space normal maps are mostly (128, 128, 255): blue-violet."""
    px = list(im.convert("RGB").resize((32, 32)).getdata())
    r = sum(p[0] for p in px) / len(px); g = sum(p[1] for p in px) / len(px); b = sum(p[2] for p in px) / len(px)
    return b > 190 and abs(r - 128) < 35 and abs(g - 128) < 35


def tex_limit(path, im=None):
    n = os.path.basename(path)
    if n.startswith("sign_") or "_sign_" in n or "_text" in n or "/decals/" in path or n.startswith("vesk_"):
        return TEX_SHARP
    prop = "/models/" in path and not any(c in path for c in CHARS) and not n.startswith(("vesk", "hornet", "roller", "crew_roller", "drone"))
    if prop and ("normal" in n.lower() or (im is not None and looks_like_normal_map(im))):
        return TEX_DEFAULT // 2   # prop normal maps: fine detail nobody sees on a phone screen
    return TEX_DEFAULT


def shrink(path):
    im = Image.open(path)
    lim = tex_limit(path, im)
    w, h = im.size
    changed = False
    # an alpha channel that is fully opaque doubles the GPU-compressed size (ETC2 RGBA vs RGB)
    if im.mode in ("RGBA", "LA") and im.getchannel("A").getextrema()[0] == 255:
        im = im.convert("RGB" if im.mode == "RGBA" else "L"); changed = True
    if max(w, h) > lim:
        s = lim / max(w, h)
        im = im.resize((max(1, round(w * s)), max(1, round(h * s))), Image.LANCZOS); changed = True
    if not changed:
        return 0
    if path.lower().endswith((".jpg", ".jpeg")):
        im.convert("RGB").save(path, quality=88)
    else:
        im.save(path, optimize=True)
    return 1


def audio(path):
    tmp = path + ".tmp" + os.path.splitext(path)[1]
    music = "/audio/music/" in path
    if path.endswith(".ogg"):
        args = ["-c:a", "libvorbis", "-q:a", "0" if music else "-1"]
    else:
        args = ["-c:a", "libmp3lame", "-b:a", "96k" if music else "56k"]
    ch = ["-ac", "2"] if music else ["-ac", "1"]
    r = subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", path, *ch, "-ar", "44100", *args, "-map_metadata", "-1", tmp])
    if r.returncode == 0 and os.path.getsize(tmp) < os.path.getsize(path):
        os.replace(tmp, path)
    elif os.path.exists(tmp):
        os.remove(tmp)


imgs, snds = [], []
for d, _, fs in os.walk(root):
    if "/.godot" in d:
        continue
    for f in fs:
        p = os.path.join(d, f)
        lf = f.lower()
        if lf.endswith((".png", ".jpg", ".jpeg")) and ("/textures/" in p or "/models/" in p):
            imgs.append(p)
        elif lf.endswith((".ogg", ".mp3")):
            snds.append(p)

def size(ps): return sum(os.path.getsize(p) for p in ps) / 1e6
b_i, b_s = size(imgs), size(snds)
n = sum(map(shrink, imgs))
if "--textures-only" not in sys.argv:
    with ThreadPoolExecutor(os.cpu_count() or 4) as ex:
        list(ex.map(audio, snds))
print(f"[tex] {n}/{len(imgs)} shrunk, {b_i:.1f} -> {size(imgs):.1f} MB")
print(f"[audio] {len(snds)} files, {b_s:.1f} -> {size(snds):.1f} MB")
