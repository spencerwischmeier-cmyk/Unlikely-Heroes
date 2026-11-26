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
