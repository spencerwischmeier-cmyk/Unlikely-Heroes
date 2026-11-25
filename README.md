# Blaster game (working title)

An original 3D action-platformer shooter for the browser and phone: a hero with a big arsenal of weapons, a robot
sidekick drone, and planets to explore. Built with Three.js.

This folder now holds a **first playable prototype** (`index.html`) and the original still **look test** (`look.html`).

![Playable prototype](docs/play.jpg)

## Run it
```
npm install
npm run dev
```
Then open the address Vite prints (usually http://localhost:5173). The look test is at `/look.html`.

`npm run build` makes a deployable copy of both pages in `dist/`.

### Play on your phone
1. Run `npm run phone` instead of `npm run dev`. It shares the game on your home Wi-Fi and prints a `Network:`
   address such as `http://192.168.1.20:5173`. On Windows, click **Allow** if a firewall prompt appears.
2. On a phone connected to the same Wi-Fi, open that address in Chrome or Safari and turn the phone sideways.
3. Tap to play. Phones get touch controls and a lighter graphics mode automatically.

## How to play
Fight off waves of bots on a floating deck above the sky city.

| Control | Keyboard and mouse | Gamepad |
| --- | --- | --- |
| Move | WASD | left stick |
| Aim | mouse | right stick |
| Fire (hold) | left click | RT |
| Jump, then jet-boost in the air | Space (hold to glide) | A |
| Dash | Shift | B |
| Pause | Esc | |

On a phone or tablet: drag your left thumb to move (the stick appears where you touch), drag on the right half to
aim, hold **FIRE** to shoot (slide your thumb on it to aim too), and tap **JUMP** and **DASH**. There is a little aim
assist on touch screens. Add `?touch=1` to force touch controls, or `?touch=0` to turn them off.

- **Arc Lancer blaster:** fires energy bolts from a 60-shot cell that recharges when you stop firing. Empty it and it
  overheats until half full. Kills give weapon XP, which upgrades it from V1 to V5 (more damage, faster fire).
- **Enemies:** *Scrap Rollers* are spiked balls that roll at you and pop when they get close. *Rivet Hornets* are
  flying gunships that circle you, charge their red visor, then fire a laser bolt.
- **Sidekick drone:** follows you and zaps the nearest bot every couple of seconds.
- **Pickups:** wrecked bots drop hex nuts (currency) that fly to you. Green repair cells restore one hull segment.
- **Waves:** each wave adds more bots and makes them a little more aggressive. Clearing a wave pays bonus nuts and
  repairs two hull segments. Lose all eight hull segments and it is game over.

URL switches: `?lq=1` for a lighter mode on slow machines, `?bloom=0` to turn off glow.

## Code layout
- `src/main.js`: game loop, input, hero movement and camera, blaster, waves, pickups, HUD.
- `src/world.js`: sky, lights, the sky city and the arena deck with its crates and pads.
- `src/hero.js`, `src/drone.js`, `src/enemies.js`: characters, built from basic shapes for now.
- `src/touch.js`: phone controls.
- `src/fx.js`: sparks, explosions, smoke and debris.
- `src/hud.css`: HUD and menu styles.

## Next steps
Real models from Blender to replace the basic-shape characters, more weapons and a weapon wheel, sound, and then traversal (grind rails, grapple) and the first full planet.
