"""Final touches on the exported site (see build.sh):

- splits index.pck into parts under 45 MB (GitHub refuses files over 100 MB, and the site is served
  from the repo). Part names carry a content hash, so a phone can never mix old and new parts.
  The loading page (shell.html) downloads the parts listed in pack.json and joins them.
- lets the service worker cache the parts, and makes a new version take over on the next launch.
- writes build.json (when, which commit, file sizes).
"""
import hashlib, json, os, re, subprocess, sys, time

out = sys.argv[1]
PART = 45 * 1024 * 1024
def split(pck, prefix):
    data = open(pck, "rb").read()
    digest = hashlib.sha256(data).hexdigest()[:10]
    parts = []
    for i in range(0, len(data), PART):
        name = f"{prefix}.{digest}.{i // PART:02d}.part"
        open(os.path.join(out, name), "wb").write(data[i:i + PART])
        parts.append({"file": name, "size": len(data[i:i + PART])})
    os.remove(pck)
    return {"version": digest, "size": len(data), "parts": parts}

# phones (ETC2/ASTC textures) and computers (S3TC textures) each get their own copy of the game data
variants = {"mobile": split(os.path.join(out, "index.pck"), "game")}
if os.path.exists(os.path.join(out, "index.desktop.pck")):
    variants["desktop"] = split(os.path.join(out, "index.desktop.pck"), "game-pc")
json.dump({"variants": variants}, open(os.path.join(out, "pack.json"), "w"))
parts = [p for v in variants.values() for p in v["parts"]]
digest = "+".join(v["version"] for v in variants.values())
data = b"x" * sum(v["size"] for v in variants.values())

sw = os.path.join(out, "index.service.worker.js")
s = open(sw).read()
cacheable = ["index.wasm", "pack.json"] + [p["file"] for p in parts]
s = re.sub(r"const CACHEABLE_FILES = \[.*?\];", "const CACHEABLE_FILES = " + json.dumps(cacheable) + ";", s)
# a new version takes over as soon as it has installed (the page reloads into it on the next launch)
s = s.replace("event.waitUntil(caches.open(CACHE_NAME).then((cache) => cache.addAll(CACHED_FILES)));",
              "event.waitUntil(caches.open(CACHE_NAME).then((cache) => cache.addAll(CACHED_FILES)).then(() => self.skipWaiting()));")
s = s.replace("return ('navigationPreload' in self.registration)", "self.clients.claim();\n\t\treturn ('navigationPreload' in self.registration)")
open(sw, "w").write(s)

sha = subprocess.run(["git", "rev-parse", "--short", "HEAD"], capture_output=True, text=True).stdout.strip()
json.dump({"built": time.strftime("%Y-%m-%d %H:%M UTC", time.gmtime()), "commit": sha, "pack": digest,
           "files": {f: os.path.getsize(os.path.join(out, f)) for f in sorted(os.listdir(out))}},
          open(os.path.join(out, "build.json"), "w"), indent=1)
print(f"[site] {len(parts)} parts, " + ", ".join(f"{k} {v['size'] / 1e6:.1f} MB" for k, v in variants.items()) + f", build {sha}")
