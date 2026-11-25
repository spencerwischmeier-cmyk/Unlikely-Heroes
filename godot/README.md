# Unlikely Heroes (Godot 4)

The Godot version of the game, built for Windows first (Forward+ renderer) with an iPhone build planned later.
Open this `godot/` folder in **Godot 4.7** (Project Manager > Import > pick `project.godot`) and press F5.

## Controls

| Control | Keyboard and mouse | Gamepad |
| --- | --- | --- |
| Move | WASD | left stick |
| Aim | mouse | right stick |
| Jump (hold for higher), jetpack boost in the air, hold to glide | Space | A |
| Dash (jump right after for a long jump) | Shift or right click | B |
| Swing from a hook | E | Y |
| Melee | F | X |
| Fire | left click | RT |

## Layout

- `scripts/main.gd` builds the scene: sky, lighting, the level, Vesk and the camera.
- `scripts/player.gd` movement, rails, swing hooks, bounce pads and procedural animation.
- `scripts/camera_rig.gd` the third-person camera.
- `scripts/level_skyharbor.gd` Skyharbor, built from code (islands, sky steps, moving platforms, rails, hooks).
- `scripts/mats.gd` shared materials and procedural textures.
- `scripts/shot.gd` test helper: `godot --path . -- --shot=out.png --frames=60 --no-capture` saves a screenshot.
- `models/` the Blender models from `../art/`.
