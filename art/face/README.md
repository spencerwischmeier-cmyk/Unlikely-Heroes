# Vesk's cutscene face (opening cutscene polish, 2026-11-26)

- `build_vesk_face.py` (pip bpy 5.3): godot/models/vesk.glb -> godot/models/vesk_face.glb. Subdivides the face, cuts a mouth
  slit along the painted lip line, adds a mouth bag, tongue and teeth, a `jaw` bone, a real right eyeball on an `eye.R`
  bone, a glass dome on the eyepiece, and 12 shape keys (blink, lids_half, brow_up_L/R, brow_down, brow_sad, smile,
  frown, wide, pucker, press, sneer). The face is split off as `VeskFace` so only it carries morph targets.
  Gameplay still uses vesk.glb; only the cutscene actor (scripts/cutscene/vesk_actor.gd) loads vesk_face.glb.
- `fur_mask.py`: godot/textures/vesk_fur_mask.png for the shell fur (shaders/fur_shell.gdshader).
- Lip sync: Rhubarb Lip Sync 1.14 (https://github.com/DanielSWolf/rhubarb-lip-sync) on each voice line, with the
  subtitle text as the dialog hint, `--extendedShapes GHX`; cues are merged into godot/audio/voice/lipsync.json
  (`lipsync_run_example.sh` shows the per-line commands). vesk_actor.gd maps shapes A-H/X to the jaw and mouth keys.
- Quick looks without the level: scripts/cutscene/face_preview.gd (moods x mouth shapes) and pose_preview.gd (body clips
  and acting beats), see their headers.
