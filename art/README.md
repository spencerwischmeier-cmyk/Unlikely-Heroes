# Character models

The game's characters are built by Python scripts that run in Blender 5.3 and export to `public/models/*.glb`.

- `blib.py`: helpers. Parts are authored in game coordinates (Y up, +Z forward) and stored so the glTF export
  lines up with the game. Named empties become the pivots the game animates (`hip_L`, `knee_L`, `upper`, `gun`,
  `muzzle`, `jet_L`, ...).
- `hero.py`: the hero. `bots.py`: the sidekick drone, Scrap Roller and Rivet Hornet.

Run them with Blender's Python (the `bpy` module from PyPI works too):
```
blender --background --python art/hero.py
blender --background --python art/bots.py
```
Edit the paths at the bottom of each script if you are not on Linux; they write to `/tmp/claude-0/art/`. Add
`--preview` to also render preview images.
