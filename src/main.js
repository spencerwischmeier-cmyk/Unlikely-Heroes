// Game loop: input, hero movement and camera, the Arc Lancer blaster, waves, pickups and HUD.
import * as THREE from 'three';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js';
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';
import { ShaderPass } from 'three/addons/postprocessing/ShaderPass.js';
import { V, std, glow, mesh, glowSprite, rand, clamp, damp, angleDiff, UP } from './util.js';
import { createWorld, ARENA } from './world.js';
import { createHero } from './hero.js';
import { createDrone } from './drone.js';
import { createEnemies, pushOut } from './enemies.js';
import { createFx } from './fx.js';
import { createTouch } from './touch.js';
import { loadModels } from './models.js';

const params = new URLSearchParams(location.search);
// phones and tablets get touch controls and the lighter graphics mode by default
const TOUCH = params.get('touch') === '1' || (params.get('touch') !== '0' && matchMedia('(pointer: coarse)').matches);
const LQ = params.has('lq') ? params.get('lq') === '1' : TOUCH;
const $ = id => document.getElementById(id);

// ---------- renderer ----------
const renderer = new THREE.WebGLRenderer({ antialias: !LQ, powerPreference: 'high-performance' });
renderer.setPixelRatio(Math.min(devicePixelRatio, LQ ? 1 : 1.5));
renderer.setSize(innerWidth, innerHeight);
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 0.95;
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFShadowMap;
document.body.prepend(renderer.domElement);

const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(55, innerWidth / innerHeight, 0.1, 3000);
const world = createWorld(renderer, scene, { lq: LQ });
const fx = createFx(scene);
// character models from Blender; ?basic=1 uses the original basic shapes instead
$('go').textContent = 'Loading…';
const models = params.get('basic') === '1' ? {} : await loadModels(p => { $('go').textContent = `Loading… ${Math.round(p * 100)}%`; });
$('go').textContent = 'Click to play';
const hero = createHero(scene, models.hero);
const drone = createDrone(scene, models.drone);
const enemies = createEnemies(scene, fx, models);

// ---------- post ----------
const composer = new EffectComposer(renderer, new THREE.WebGLRenderTarget(1, 1, { type: THREE.HalfFloatType, samples: LQ ? 0 : 4 }));
composer.addPass(new RenderPass(scene, camera));
const bloom = new UnrealBloomPass(new THREE.Vector2(innerWidth, innerHeight), 0.7, 0.4, +(params.get('th') || 14));
if (params.get('bloom') !== '0') composer.addPass(bloom);
composer.addPass(new OutputPass());
composer.addPass(new ShaderPass({
  uniforms: { tDiffuse: { value: null }, hurt: { value: 0 } },
  vertexShader: `varying vec2 vUv; void main(){ vUv=uv; gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.); }`,
  fragmentShader: `uniform sampler2D tDiffuse; uniform float hurt; varying vec2 vUv;
    void main(){ vec4 c = texture2D(tDiffuse, vUv);
      vec2 d = vUv-0.5; float v = smoothstep(0.85, 0.3, length(d*vec2(1.0,0.85)));
      float l = dot(c.rgb, vec3(0.299,0.587,0.114));
      c.rgb += mix(vec3(-0.012,0.006,0.03), vec3(0.03,0.01,-0.02), smoothstep(0.2,0.8,l));
      c.rgb = mix(vec3(l), c.rgb, 1.1);
      c.rgb *= mix(0.72, 1.0, v);
      gl_FragColor = c; }`
}));
function resize() {
  camera.aspect = innerWidth / innerHeight; camera.updateProjectionMatrix();
  renderer.setSize(innerWidth, innerHeight); composer.setSize(innerWidth, innerHeight);
}
addEventListener('resize', resize); resize();

// ---------- input ----------
const keys = new Set();
const input = { fire: false, look: { dx: 0, dy: 0 }, jumpPressed: false, dashPressed: false };
addEventListener('keydown', e => {
  if (e.repeat) return;
  keys.add(e.code);
  if (e.code === 'Space') { input.jumpPressed = true; e.preventDefault(); }
  if (e.code === 'ShiftLeft' || e.code === 'ShiftRight') input.dashPressed = true;
});
addEventListener('keyup', e => keys.delete(e.code));
addEventListener('blur', () => { keys.clear(); input.fire = false; });
addEventListener('mousedown', e => { if (e.button === 0 && state === 'playing') input.fire = true; });
addEventListener('mouseup', e => { if (e.button === 0) input.fire = false; });
let ignoreMouseUntil = 0;
addEventListener('mousemove', e => {
  // browsers can report one huge jump when the pointer gets locked; skip it
  if (state !== 'playing' || performance.now() < ignoreMouseUntil) return;
  if (Math.abs(e.movementX) > 250 || Math.abs(e.movementY) > 250) return;
  input.look.dx += e.movementX; input.look.dy += e.movementY;
});
addEventListener('contextmenu', e => e.preventDefault());
const canvas = renderer.domElement;
const lock = () => { try { const p = canvas.requestPointerLock?.(); p?.catch?.(() => {}); } catch { /* no pointer lock (e.g. headless) */ } };
let hadLock = false;
document.addEventListener('pointerlockchange', () => {
  if (document.pointerLockElement) { hadLock = true; ignoreMouseUntil = performance.now() + 150; }
  else if (hadLock && state === 'playing') pause();
});
$('title').addEventListener('click', () => { if (state === 'title' || state === 'paused') begin(); });
$('over').addEventListener('click', () => { if (state === 'dead') { reset(); begin(); } });

function readGamepad() {
  const pads = navigator.getGamepads ? navigator.getGamepads() : [];
  const gp = [...pads].find(p => p && p.connected);
  if (!gp) return null;
  const dz = v => (Math.abs(v) < 0.15 ? 0 : v);
  return {
    mx: dz(gp.axes[0]), mz: -dz(gp.axes[1]), lx: dz(gp.axes[2] ?? 0), ly: dz(gp.axes[3] ?? 0),
    fire: (gp.buttons[7]?.value ?? 0) > 0.3, jump: gp.buttons[0]?.pressed, dash: gp.buttons[1]?.pressed, start: gp.buttons[9]?.pressed,
  };
}
let padPrev = {};
const touch = TOUCH ? createTouch({ input, isPlaying: () => state === 'playing', onPause: () => pause() }) : null;
if (TOUCH) { $('go').textContent = 'Tap to play'; document.querySelector('#over .go').textContent = 'Tap to try again'; }

// ---------- game state ----------
let state = 'title';
const MAX_HULL = 8;
const player = {
  pos: V(0, 0, 4), vel: V(0, 0, 0), yaw: Math.PI, pitch: -0.05, grounded: true, jumps: 0, coyote: 0,
  hull: MAX_HULL, invuln: 0, dashT: 0, dashCd: 0, jetT: 0,
};
const gun = { energy: 60, max: 60, cool: 0, sinceShot: 9, hot: false, level: 1, xp: 0 };
const LEVELS = [0, 120, 300, 560, 900]; // xp needed for V1..V5
const stats = { nuts: 0, kills: 0, wave: 0, shots: 0, hits: 0 };
let waveState = { toSpawn: [], spawnT: 0, clearT: -1 };
const bolts = [];
const pickups = [];

const boltGeo = new THREE.CapsuleGeometry(0.05, 0.9, 4, 10);
const boltMat = glow(0x9ffcff, 10);
const nutGeo = new THREE.TorusGeometry(0.1, 0.055, 6, 6);
const nutMat = std(0xffc23d, 1.0, 0.22, { emissive: 0x5a3500, emissiveIntensity: 0.6 });
const cellGeo = new THREE.OctahedronGeometry(0.22);
const cellMat = glow(0x50ff90, 3);

function reset() {
  enemies.clear();
  bolts.forEach(b => scene.remove(b.m)); bolts.length = 0;
  pickups.forEach(p => scene.remove(p.m)); pickups.length = 0;
  Object.assign(player, { hull: MAX_HULL, invuln: 0, dashT: 0, dashCd: 0, jumps: 0 });
  player.pos.set(0, 0, 4); player.vel.set(0, 0, 0); player.yaw = Math.PI; player.pitch = -0.05;
  Object.assign(gun, { energy: 60, cool: 0, sinceShot: 9, hot: false, level: 1, xp: 0 });
  Object.assign(stats, { nuts: 0, kills: 0, wave: 0, shots: 0, hits: 0 });
  waveState = { toSpawn: [], spawnT: 0, clearT: 1.2 };
  hud.full();
}
function begin() {
  if (touch) {
    // go full screen and sideways where the browser allows it
    const de = document.documentElement;
    if (!document.fullscreenElement && de.requestFullscreen) de.requestFullscreen({ navigationUI: 'hide' }).then(() => screen.orientation?.lock?.('landscape').catch(() => {})).catch(() => {});
    touch.reset(); touch.show(true);
  } else lock();
  $('title').classList.add('hidden'); $('over').classList.add('hidden');
  if (stats.wave === 0 && waveState.clearT < 0) waveState.clearT = 1.2;
  state = 'playing';
  input.fire = false;
}
function pause() {
  state = 'paused'; input.fire = false;
  touch?.show(false);
  $('title').classList.remove('hidden'); $('go').textContent = touch ? 'Paused: tap to resume' : 'Paused: click to resume';
}
function gameOver() {
  state = 'dead'; input.fire = false; touch?.show(false);
  if (document.pointerLockElement) document.exitPointerLock();
  $('summary').innerHTML = `You reached wave <b>${stats.wave}</b>, wrecked <b>${stats.kills}</b> bots and banked <b>${stats.nuts.toLocaleString()}</b> hex nuts.`;
  setTimeout(() => $('over').classList.remove('hidden'), 1200);
}

// ---------- waves ----------
function startWave(n) {
  stats.wave = n;
  const rollers = 2 + n, hornets = Math.floor((n + 1) / 2);
  const list = [];
  for (let i = 0; i < Math.max(rollers, hornets); i++) { if (i < rollers) list.push('roller'); if (i < hornets) list.push('hornet'); }
  waveState.toSpawn = list; waveState.spawnT = 0.6;
  hud.banner(`WAVE ${n}`, n === 1 ? 'Clear the deck' : `${list.length} bots incoming`);
}
const aggression = () => 1 + (stats.wave - 1) * 0.08;
function spawnPoint() {
  for (let k = 0; k < 30; k++) {
    const x = rand(ARENA.minX + 1.5, ARENA.maxX - 1.5), z = rand(ARENA.minZ + 1.5, ARENA.maxZ - 1.5);
    if (Math.hypot(x - player.pos.x, z - player.pos.z) < 7) continue;
    if (world.colliders.some(c => x > c.min.x - 0.8 && x < c.max.x + 0.8 && z > c.min.z - 0.8 && z < c.max.z + 0.8)) continue;
    return [x, z];
  }
  return [ARENA.minX + 2, ARENA.minZ + 2];
}
function updateWaves(dt) {
  if (waveState.clearT >= 0) {
    waveState.clearT -= dt;
    if (waveState.clearT < 0) startWave(stats.wave + 1);
    return;
  }
  if (waveState.toSpawn.length) {
    waveState.spawnT -= dt;
    if (waveState.spawnT <= 0) {
      const [x, z] = spawnPoint();
      enemies.spawn(waveState.toSpawn.shift(), x, z);
      waveState.spawnT = rand(0.5, 1.1);
    }
  } else if (enemies.list.length === 0 && state === 'playing') {
    hud.banner('WAVE CLEAR', `+${50 * stats.wave} bonus nuts`);
    stats.nuts += 50 * stats.wave; hud.nuts();
    if (player.hull < MAX_HULL) { player.hull = Math.min(MAX_HULL, player.hull + 2); hud.hull(); }
    waveState.clearT = 3.2;
  }
}

// ---------- hero physics ----------
const GRAV = 26, RUN = 6.8, JUMP = 8.6, BOOST = 7.8, RADIUS = 0.38;
function floorAt(p) {
  let f = 0;
  for (const c of world.colliders) {
    if (p.x > c.min.x - RADIUS * 0.6 && p.x < c.max.x + RADIUS * 0.6 && p.z > c.min.z - RADIUS * 0.6 && p.z < c.max.z + RADIUS * 0.6 && p.y >= c.max.y - 0.3) f = Math.max(f, c.max.y);
  }
  return f;
}
function updatePlayer(dt, pad) {
  // look
  const sens = 0.0024;
  player.yaw -= input.look.dx * sens; player.pitch -= input.look.dy * sens;
  input.look.dx = input.look.dy = 0;
  if (pad) { player.yaw -= pad.lx * 3.2 * dt; player.pitch -= pad.ly * 2.2 * dt; }
  // gentle aim assist on touch screens: while firing, drift toward the bot nearest the crosshair
  if (touch && input.fire) {
    let best = null, bestA = 0.16;
    for (const e of enemies.list) {
      const d = e.pos.clone().add(V(0, e.type === 'roller' ? 0.55 : 0, 0)).sub(camPivot);
      const a = d.clone().normalize().angleTo(aimDir);
      if (a < bestA && d.length() < 30) { bestA = a; best = d; }
    }
    if (best) {
      const k = 1 - Math.exp(-5 * dt);
      player.yaw += angleDiff(player.yaw, Math.atan2(best.x, best.z)) * k;
      player.pitch += (Math.atan2(best.y, Math.hypot(best.x, best.z)) - player.pitch) * k;
    }
  }
  player.pitch = clamp(player.pitch, -0.65, 0.5);

  // move relative to the camera
  let mx = 0, mz = 0;
  if (keys.has('KeyW') || keys.has('ArrowUp')) mz += 1;
  if (keys.has('KeyS') || keys.has('ArrowDown')) mz -= 1;
  if (keys.has('KeyD') || keys.has('ArrowRight')) mx += 1;
  if (keys.has('KeyA') || keys.has('ArrowLeft')) mx -= 1;
  if (pad) { mx += pad.mx; mz += pad.mz; }
  if (input.touchMove) { mx += input.touchMove.x; mz += input.touchMove.z; }
  const ml = Math.hypot(mx, mz); if (ml > 1) { mx /= ml; mz /= ml; }
  const fwd = V(Math.sin(player.yaw), 0, Math.cos(player.yaw));
  const right = V(-Math.cos(player.yaw), 0, Math.sin(player.yaw));
  const wish = fwd.multiplyScalar(mz).addScaledVector(right, mx).multiplyScalar(RUN);

  player.dashCd -= dt;
  if (input.dashPressed && player.dashCd <= 0) {
    const dir = ml > 0.1 ? wish.clone().normalize() : V(Math.sin(player.yaw), 0, Math.cos(player.yaw));
    player.vel.x = dir.x * 17; player.vel.z = dir.z * 17;
    player.dashT = 0.17; player.dashCd = 0.75; player.invuln = Math.max(player.invuln, 0.2);
    fx.puff(player.pos.clone().add(V(0, 0.3, 0)));
  }
  input.dashPressed = false;
  if (player.dashT > 0) player.dashT -= dt;
  else {
    const accel = player.grounded ? 14 : 5;
    player.vel.x = damp(player.vel.x, wish.x, accel, dt);
    player.vel.z = damp(player.vel.z, wish.z, accel, dt);
  }

  // jump / jet boost
  player.coyote -= dt;
  if (input.jumpPressed) {
    if (player.grounded || player.coyote > 0) { player.vel.y = JUMP; player.grounded = false; player.coyote = 0; player.jumps = 1; fx.puff(player.pos.clone().add(V(0, 0.1, 0))); }
    else if (player.jumps < 2) { player.vel.y = BOOST; player.jumps = 2; player.jetT = 0.35; fx.sparks(player.pos.clone().add(V(0, 0.6, 0)), 0x60e8ff, 12, 3); }
  }
  input.jumpPressed = false;
  player.jetT -= dt;
  // holding jump while falling glides a little
  const gliding = !player.grounded && player.vel.y < 0 && (keys.has('Space') || pad?.jump || input.jumpHeld) && player.jumps === 2;
  player.vel.y -= GRAV * dt * (gliding ? 0.35 : 1);
  if (gliding) player.vel.y = Math.max(player.vel.y, -3);

  // integrate and collide
  const p = player.pos;
  p.x += player.vel.x * dt; p.z += player.vel.z * dt;
  for (const c of world.colliders) pushOut(p, RADIUS, c);
  p.x = clamp(p.x, ARENA.minX + RADIUS, ARENA.maxX - RADIUS); p.z = clamp(p.z, ARENA.minZ + RADIUS, ARENA.maxZ - RADIUS);
  p.y += player.vel.y * dt;
  const f = floorAt(p);
  if (p.y <= f) {
    if (!player.grounded && player.vel.y < -6) fx.puff(p.clone().add(V(0, 0.05, 0)));
    p.y = f; player.vel.y = 0; player.grounded = true; player.jumps = 0; player.coyote = 0.1;
  } else if (player.grounded && p.y > f) {
    player.grounded = false; player.jumps = 1; // walked off a ledge
  }
  player.invuln -= dt;
}

// ---------- camera + aim ----------
const camPivot = V(0, 0, 0), aimDir = V(0, 0, 1), aimPoint = V(0, 0, 0);
const raycaster = new THREE.Raycaster();
const camRay = new THREE.Ray(), camBox = new THREE.Box3(), camHit = V(0, 0, 0);
let camSmooth = 4.4;
let shake = 0;
function updateCamera(dt) {
  const cp = Math.cos(player.pitch);
  aimDir.set(Math.sin(player.yaw) * cp, Math.sin(player.pitch), Math.cos(player.yaw) * cp);
  const right = V(-Math.cos(player.yaw), 0, Math.sin(player.yaw));
  const target = player.pos.clone().add(V(0, 1.7, 0)).addScaledVector(right, -1.0);
  camPivot.lerp(target, 1 - Math.exp(-18 * dt));
  const dist = 4.4 - Math.max(0, player.pitch) * 2.4; // pull in when looking up so the camera stays off the floor
  // pull the camera in front of any crate or pad that would block the view
  let camDist = dist;
  const back = aimDir.clone().negate();
  camRay.set(camPivot, back);
  for (const c of world.colliders) {
    camBox.min.copy(c.min).subScalar(0.25); camBox.max.copy(c.max).addScalar(0.25);
    if (camBox.containsPoint(camPivot)) continue;
    const hit = camRay.intersectBox(camBox, camHit);
    if (hit) camDist = Math.min(camDist, Math.max(0.6, hit.distanceTo(camPivot)));
  }
  camSmooth = camDist < camSmooth ? camDist : damp(camSmooth, camDist, 6, dt);
  camera.position.copy(camPivot).addScaledVector(aimDir, -camSmooth);
  camera.position.y = Math.max(camera.position.y, 0.35);
  camera.lookAt(camera.position.clone().add(aimDir));
  if (shake > 0) { camera.position.add(V(rand(-1, 1), rand(-1, 1), rand(-1, 1)).multiplyScalar(shake * 0.08)); shake = Math.max(0, shake - dt * 4); }

  // what is under the crosshair? enemies first, then props/deck, else far away
  const from = camPivot.clone();
  let best = 120;
  for (const e of enemies.list) {
    const c = e.pos.clone().add(V(0, e.type === 'roller' ? 0.55 : 0, 0));
    const t = c.clone().sub(from).dot(aimDir);
    if (t < 0 || t > best) continue;
    if (from.clone().addScaledVector(aimDir, t).distanceTo(c) < e.radius + 0.25) best = t;
  }
  raycaster.set(from, aimDir); raycaster.far = best;
  if (aimDir.y < -0.01) { const t = -from.y / aimDir.y; if (t > 0 && t < best && Math.abs(from.x + aimDir.x * t) < 15 && Math.abs(from.z + aimDir.z * t) < 12) best = t; }
  for (const c of world.colliders) {
    const box = new THREE.Box3(c.min, c.max); const hit = raycaster.ray.intersectBox(box, new THREE.Vector3());
    if (hit) { const t = hit.distanceTo(from); if (t < best) best = t; }
  }
  aimPoint.copy(from).addScaledVector(aimDir, best);
  return best;
}

// ---------- blaster ----------
function fireBolt() {
  const muzzle = hero.muzzle.getWorldPosition(V(0, 0, 0));
  const dir = aimPoint.clone().sub(muzzle).normalize();
  // never shoot backwards into the camera when the aim point is very close
  if (dir.dot(aimDir) < 0.3) dir.copy(aimDir);
  dir.add(V(rand(-1, 1), rand(-1, 1), rand(-1, 1)).multiplyScalar(0.008)).normalize();
  const m = mesh(boltGeo, boltMat, false, false); m.position.copy(muzzle); m.quaternion.setFromUnitVectors(UP, dir);
  m.add(glowSprite(0x40e8ff, 0.8, 0.75));
  scene.add(m);
  bolts.push({ m, vel: dir.multiplyScalar(75), life: 1.6 });
  hero.fireFlash();
  stats.shots++;
}
const dmg = () => 1 + (gun.level - 1) * 0.35;
const fireInterval = () => 0.13 * Math.pow(0.9, gun.level - 1);
function updateGun(dt, wantFire) {
  gun.cool -= dt; gun.sinceShot += dt;
  if (gun.hot) { gun.energy += 26 * dt; if (gun.energy >= gun.max * 0.5) gun.hot = false; }
  else if (gun.sinceShot > 0.45) gun.energy += 22 * dt;
  gun.energy = Math.min(gun.max, gun.energy);
  if (wantFire && !gun.hot && gun.cool <= 0 && state === 'playing') {
    fireBolt();
    gun.energy -= 1; gun.cool = fireInterval(); gun.sinceShot = 0;
    if (gun.energy <= 0) { gun.energy = 0; gun.hot = true; hud.banner('', 'Overheated'); }
  }
}
function updateBolts(dt) {
  for (let i = bolts.length - 1; i >= 0; i--) {
    const b = bolts[i];
    const a = b.m.position.clone();
    const n = a.clone().addScaledVector(b.vel, dt);
    let end = false;
    const hit = enemies.segmentHit(a, n);
    if (hit) {
      enemies.damage(hit.enemy, dmg(), hit.point, ctx);
      fx.sparks(hit.point, 0xaefaff, 8, 5);
      hud.hit(); stats.hits++;
      end = true;
    } else {
      b.m.position.copy(n);
      const p = b.m.position;
      if (p.y < 0 && Math.abs(p.x) < 14.5 && Math.abs(p.z) < 11.5) end = true;
      for (const c of world.colliders) if (p.x > c.min.x && p.x < c.max.x && p.y > c.min.y && p.y < c.max.y && p.z > c.min.z && p.z < c.max.z) { end = true; break; }
      if (end) fx.sparks(p.clone(), 0xaefaff, 6, 3);
    }
    b.life -= dt;
    if (end || b.life <= 0) { scene.remove(b.m); bolts.splice(i, 1); }
  }
}
function addXp(n) {
  gun.xp += n;
  const next = LEVELS[gun.level];
  if (next !== undefined && gun.xp >= next) {
    gun.level++;
    hud.banner(`ARC LANCER V${gun.level}`, 'Weapon upgraded: more damage, faster fire');
    fx.ring(player.pos.clone().add(V(0, 1, 0)), 0xffc23d);
  }
  hud.weapon();
}

// ---------- pickups ----------
function dropNuts(pos, n) {
  for (let i = 0; i < n; i++) {
    const m = mesh(nutGeo, nutMat); m.position.copy(pos); m.scale.setScalar(1.6);
    scene.add(m);
    pickups.push({ kind: 'nut', m, vel: V(rand(-3, 3), rand(3, 7), rand(-3, 3)), t: 0, spin: V(rand(-8, 8), rand(-8, 8), 0) });
  }
}
function dropCell(pos) {
  const m = mesh(cellGeo, cellMat, false, false); m.position.copy(pos);
  m.add(glowSprite(0x50ff90, 1.0, 0.6)); scene.add(m);
  pickups.push({ kind: 'cell', m, vel: V(rand(-1, 1), 5, rand(-1, 1)), t: 0, spin: V(0, 3, 0) });
}
function updatePickups(dt) {
  const target = player.pos.clone().add(V(0, 0.8, 0));
  for (let i = pickups.length - 1; i >= 0; i--) {
    const p = pickups[i]; p.t += dt;
    const d = p.m.position.distanceTo(target);
    // nuts home in when close, or from anywhere once they have settled; repair cells need you to walk over
    if (p.t > 0.5 && (d < (p.kind === 'nut' ? 7 : 2.5) || (p.kind === 'nut' && p.t > 2.2)) && state === 'playing') {
      // magnet
      p.vel.lerp(target.clone().sub(p.m.position).normalize().multiplyScalar(16), 1 - Math.exp(-8 * dt));
    } else {
      p.vel.y -= 20 * dt;
    }
    p.m.position.addScaledVector(p.vel, dt);
    const fl = floorAt(p.m.position) + 0.12;
    const onDeck = Math.abs(p.m.position.x) < 14.5 && Math.abs(p.m.position.z) < 11.5;
    if (onDeck && p.m.position.y < fl) { p.m.position.y = fl; p.vel.y = Math.abs(p.vel.y) * 0.4; p.vel.x *= 0.7; p.vel.z *= 0.7; }
    p.m.rotation.x += p.spin.x * dt; p.m.rotation.y += p.spin.y * dt;
    if (d < 0.7 && state === 'playing') {
      if (p.kind === 'nut') { stats.nuts += 10; hud.nuts(); }
      else { player.hull = Math.min(MAX_HULL, player.hull + 1); hud.hull(true); }
      scene.remove(p.m); pickups.splice(i, 1); continue;
    }
    if (p.t > 25 || p.m.position.y < -30) { scene.remove(p.m); pickups.splice(i, 1); }
  }
}

// ---------- shared context for enemies ----------
const ctx = {
  heroPos: player.pos, heroVel: player.vel, colliders: world.colliders,
  get alive() { return state === 'playing' && player.hull > 0; },
  get aggression() { return aggression(); },
  hurtHero(n, from) {
    if (player.invuln > 0 || player.hull <= 0) return;
    player.hull -= n; player.invuln = 0.9; shake = 1;
    hero.hurt(); hud.hurt(); hud.hull();
    if (from) { const k = player.pos.clone().sub(from).setY(0).normalize().multiplyScalar(6); player.vel.x += k.x; player.vel.z += k.z; }
    if (player.hull <= 0) gameOver();
  },
  onKill(e) {
    if (e.selfDestruct) return; // a roller that blew itself up earns nothing
    stats.kills++;
    dropNuts(e.pos.clone().add(V(0, 0.6, 0)), e.nuts);
    if (Math.random() < (player.hull <= 3 ? 0.35 : 0.12)) dropCell(e.pos.clone().add(V(0, 0.8, 0)));
    addXp(e.type === 'hornet' ? 40 : 20);
    shake = Math.max(shake, 0.5);
  },
};

// ---------- HUD ----------
const hud = (() => {
  const hullEl = $('hull');
  for (let i = 0; i < MAX_HULL; i++) hullEl.insertBefore(document.createElement('i'), hullEl.querySelector('b'));
  const cells = [...hullEl.querySelectorAll('i')];
  let bannerTimer = 0, hitT = 0, hurtT = 0;
  const api = {
    hull(pop) {
      cells.forEach((c, i) => { c.className = i < player.hull ? (player.hull <= 2 ? 'low' : '') : 'off'; });
      if (pop && player.hull > 0) { const c = cells[player.hull - 1]; c.classList.add('pop'); setTimeout(() => c.classList.remove('pop'), 200); }
    },
    nuts() { $('nuts').textContent = stats.nuts.toLocaleString(); const c = document.querySelector('.cur'); c.classList.add('pop'); clearTimeout(api._np); api._np = setTimeout(() => c.classList.remove('pop'), 90); },
    weapon() {
      $('lvl').textContent = 'V' + gun.level;
      const lo = LEVELS[gun.level - 1], hi = LEVELS[gun.level];
      $('xp').style.width = hi === undefined ? '100%' : `${(100 * (gun.xp - lo) / (hi - lo)).toFixed(1)}%`;
    },
    banner(title, sub) { const b = $('banner'); b.innerHTML = `${title}${sub ? `<small>${sub}</small>` : ''}`; b.classList.add('on'); bannerTimer = 2.2; },
    hit() { hitT = 0.12; },
    hurt() { hurtT = 1; },
    full() { api.hull(); $('nuts').textContent = stats.nuts.toLocaleString(); api.weapon(); },
    frame(dt, onEnemy) {
      $('ammo').textContent = Math.floor(gun.energy);
      $('ammo').parentElement.classList.toggle('hot', gun.hot);
      $('ring').classList.toggle('hot', gun.hot);
      $('wave').textContent = stats.wave ? `WAVE ${stats.wave}` : '';
      const left = enemies.list.length + waveState.toSpawn.length;
      $('left').textContent = stats.wave && waveState.clearT < 0 ? `${left} bot${left === 1 ? '' : 's'} left` : '';
      $('cross').classList.toggle('on', onEnemy);
      bannerTimer -= dt; if (bannerTimer <= 0) $('banner').classList.remove('on');
      hitT -= dt; $('hitmark').classList.toggle('on', hitT > 0);
      hurtT = Math.max(0, hurtT - dt * 2.5); $('hurt').style.opacity = hurtT * 0.8;
    },
  };
  return api;
})();
hud.full();

// ---------- main loop ----------
const timer = new THREE.Timer();
let simTime = 0;
function frame(dtRaw, render = true) {
  const dt = Math.min(dtRaw, 1 / 30);
  simTime += dt;
  const pad = readGamepad();
  if (pad) {
    if (pad.jump && !padPrev.jump) input.jumpPressed = true;
    if (pad.dash && !padPrev.dash) input.dashPressed = true;
    if (pad.start && !padPrev.start) { if (state === 'title' || state === 'paused') begin(); else if (state === 'dead') { reset(); begin(); } }
    padPrev = pad;
  }
  const playing = state === 'playing';
  if (playing) {
    updatePlayer(dt, pad);
    updateWaves(dt);
  } else {
    input.jumpPressed = input.dashPressed = false; input.look.dx = input.look.dy = 0;
    if (state === 'title') player.yaw += dt * 0.08; // slow orbit behind the title card
  }
  const aimDist = updateCamera(dt);
  const onEnemy = enemies.list.some(e => aimPoint.distanceTo(e.pos.clone().add(V(0, e.type === 'roller' ? 0.55 : 0, 0))) < e.radius + 0.4);
  if (state !== 'paused') {
    updateGun(dt, input.fire || (pad && pad.fire));
    updateBolts(dt);
    enemies.update(dt, ctx);
    updatePickups(dt);
    drone.update(dt, player.pos, player.yaw, enemies.list, e => { enemies.damage(e, 0.75, e.pos, ctx); fx.sparks(e.pos.clone().add(V(0, e.type === 'roller' ? 0.55 : 0, 0)), 0x8ffcff, 6, 3); });
    fx.update(dt);
  }

  // hero pose
  hero.root.position.copy(player.pos);
  const targetYaw = player.yaw;
  hero.root.rotation.y += angleDiff(hero.root.rotation.y, targetYaw) * (1 - Math.exp(-20 * dt));
  hero.root.visible = !(player.invuln > 0 && player.hull > 0 && Math.floor(simTime * 20) % 2 === 0 && player.dashT <= 0);
  if (player.hull <= 0) { hero.root.rotation.x = damp(hero.root.rotation.x, -1.4, 4, dt); }
  else hero.root.rotation.x = 0;
  hero.animate(dt, {
    speed: Math.hypot(player.vel.x, player.vel.z), grounded: player.grounded, vy: player.vel.y,
    aimPitch: player.pitch, heat: gun.hot, jetting: player.jetT > 0 || (!player.grounded && player.jumps === 2 && player.vel.y > -3),
  });

  world.update(dt, player.pos);
  hud.frame(dt, onEnemy);
  if (render) composer.render();
}
let autoLoop = true;
function loop(ts) {
  timer.update(ts);
  if (autoLoop) frame(timer.getDelta());
  requestAnimationFrame(loop);
}
reset();
waveState.clearT = -1; // first wave starts when the player clicks in
loop();

// hooks for automated play tests
window.__game = {
  get state() { return state; }, player, gun, stats, enemies, keys, input, hero,
  info: () => ({ calls: renderer.info.render.calls, tris: renderer.info.render.triangles }),
  begin, reset, frame, render: () => composer.render(), set autoLoop(v) { autoLoop = v; },
  look(yaw, pitch) { player.yaw = yaw; player.pitch = pitch; },
  aimAtNearest() {
    const e = enemies.list.find(x => !x.dead); if (!e) return false;
    const c = e.pos.clone().add(V(0, e.type === 'roller' ? 0.55 : 0, 0));
    const d = c.sub(camPivot);
    player.yaw = Math.atan2(d.x, d.z); player.pitch = Math.atan2(d.y, Math.hypot(d.x, d.z));
    return true;
  },
};

// offline / home-screen support (only in the built game, so the dev server always serves fresh code)
if (import.meta.env.PROD && 'serviceWorker' in navigator) {
  addEventListener('load', () => navigator.serviceWorker.register('./sw.js').catch(() => {}));
}
