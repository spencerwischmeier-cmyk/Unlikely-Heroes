# Vesk from Meshy

How the 2026-11 Vesk was made (Meshy API, network secret on api.meshy.ai; downloads from assets.meshy.ai):
1. `t2i.py`: four concept images (text-to-image, nano-banana-2, A-pose). Spencer picked the furry bruiser.
2. Image-to-image restyle to a cartoon look (3 versions); Spencer picked B -> `vesk_concept.png`.
3. Image-to-3D from that task (meshy latest, PBR, 2k textures, ~45k polys, A-pose).
4. Rigging (mixamo skeleton, 1.6 m) and two animation batches (`anim.py`, library action ids in the file).
5. `build_vesk.py` (pip bpy): merges the clips, renames them to the game's names (idle, run, jump, land, fall,
   dash, glide, grind, swing, melee, hurt...), strips root motion, renames the spine/leg bones to the old names
   (pelvis, spine, chest, neck, head, thigh/shin/foot.L/R), adds a `gun` bone in the right hand, exports
   godot/models/vesk.glb. The old model is kept as godot/models/vesk_old.glb.
The Arc Lancer is now its own model (art/weapons.py `lancer`, godot/models/wpn_lancer.glb).

# Characters and enemies (sprint/characters)

Same pipeline, scripted in `chars.py` (concept text-to-image -> image-to-3d -> rigging -> animations) and
`build_chars.py` / `build_grudd.py` (pip bpy: scale, ground, face +Z, 1k PNG textures). Every Grudd Works bot uses
one livery: mustard yellow and charcoal grey, brick-red trim, hazard stripes, a white gear stencil.
- `roller.glb`, `crew_roller.glb`: split into "ball" (rolls; rebuilt from its lower half mirrored, so it is a whole
  sphere) and "cap" (the head, turns to face travel). Eyes, the hat lamp and the riveter arm are added in code.
- `hornet.glb`: Hornet/inner/mesh. Glowing eyes added in code.
- `chars/crane_base.glb`, `chars/crane_cab.glb`, `chars/crane_magnet.glb`: the Crane Bot skin (cranebot.gd `_skin()`).
- `chars/gizmart.glb`: the vending-machine body; `scripts/chars/gizmart_actor.gd` adds the live screen face.
- `chars/grudd.glb`: Foreman Grudd, 4 m, Meshy rig (Hips, Spine.., Head, Left/RightArm..), clips idle, talk,
  talk_big, wag, stomp, walk (in place), hip, cheer, defeat, agree; nodes "stack_top" (smoke) and "mouth" on Head.
- `chars/scrap_bits.glb` (art/scrap_bits.py): sprockets, bolts, nuts, springs and plates for break-apart deaths
  (`scripts/chars/scrap_burst.gd`).
Quick looks without the level: `scripts/chars/char_preview.gd` (see its header), or `sheet.py` in Blender.

# Dodger J1 (2026-11-27)
Spencer picked concept J1 (side jet pods instead of rotors) with eye K1 (one glowing lens, no pupil, no brows).
Concept: Meshy image-to-image (nano-banana-pro) from a render of the old Dodger -> `dodger_concept.png` (clean, jets off)
-> image-to-3d (`chars.py i23d dodger_j1`) -> `build_chars.py -- dodger` (eye-glass centre on the origin, old shell size).
The lens, eyelids, jet flames and moods are code (godot/scripts/cutscene/drone_actor.gd). Old shell: chars/dodger_body_old.glb.
Quick look: char_preview.gd `--set=dodger_moods|dodger_turn|dodger_close`.
