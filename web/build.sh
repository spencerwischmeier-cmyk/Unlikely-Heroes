#!/usr/bin/env bash
# Builds the phone/web version of the game into ../site (what the website serves).
#
#   web/build.sh            full build (needs: godot 4.7.2 on PATH or $GODOT, web export templates,
#                           node, ffmpeg, python3 with Pillow)
#
# It never changes godot/: it copies the project to build/web-src, shrinks that copy for phones
# (textures, audio), switches the copy to the Compatibility (WebGL 2) renderer, and exports it.
# The PC build keeps its full-size assets and the Forward+ renderer.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
SRC="$REPO/build/web-src"
OUT="$REPO/site"
GODOT="${GODOT:-godot}"

echo "== copy the project"
rm -rf "$SRC"; mkdir -p "$SRC"
tar -C "$REPO/godot" --exclude=.godot --exclude=export --exclude='*.import' -cf - . | tar -C "$SRC" -xf -
rm -f "$SRC/models/vesk_old.glb"

echo "== shrink textures inside the models"
(cd "$HERE" && [ -d node_modules ] || npm ci --silent)
node "$HERE/optimize_glb.mjs" "$SRC/models"

echo "== shrink loose textures and re-encode audio"
python3 "$HERE/optimize_assets.py" "$SRC"

echo "== web settings"
python3 "$HERE/patch_project.py" "$SRC/project.godot"
cp "$HERE/export_presets.cfg" "$SRC/export_presets.cfg"
cp "$HERE/shell.html" "$SRC/web_shell.html"

echo "== import"
"$GODOT" --headless --path "$SRC" --import > "$REPO/build/import.log" 2>&1 || true
python3 "$HERE/optimize_assets.py" "$SRC" --textures-only   # images the import just extracted from models
python3 "$HERE/fix_imports.py" "$SRC"
"$GODOT" --headless --path "$SRC" --import >> "$REPO/build/import.log" 2>&1 || true
echo "== export"
rm -rf "$OUT"; mkdir -p "$OUT"
"$GODOT" --headless --path "$SRC" --export-release Web "$OUT/index.html" > "$REPO/build/export.log" 2>&1
test -s "$OUT/index.pck" || { tail -40 "$REPO/build/export.log"; echo "export failed"; exit 1; }
# computer browsers can't read the phone texture formats (ETC2/ASTC), so they get their own game data (S3TC)
rm -rf "$REPO/build/desktop"; mkdir -p "$REPO/build/desktop"
"$GODOT" --headless --path "$SRC" --export-release WebDesktop "$REPO/build/desktop/index.html" >> "$REPO/build/export.log" 2>&1
test -s "$REPO/build/desktop/index.pck" || { tail -40 "$REPO/build/export.log"; echo "desktop export failed"; exit 1; }
mv "$REPO/build/desktop/index.pck" "$OUT/index.desktop.pck"

echo "== site extras"
cp "$HERE/site_extra/"* "$OUT/"
python3 "$HERE/finish_site.py" "$OUT"
du -sh "$OUT"; ls -la "$OUT" | awk '{print $5, $9}' | sort -rn | head -5
