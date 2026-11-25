// Game loop: input (mouse/keyboard, touch, gamepad), hero movement and camera, weapons, waves,
// the test range, pickups, menus and HUD.
import * as THREE from 'three';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js';
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';
import { ShaderPass } from 'three/addons/postprocessing/ShaderPass.js';
import { V, std, glow, mesh, glowSprite, rand, clamp, damp, angleDiff } from './util.js';
import { createWorld, ARENA, onDeck } from './world.js';
import { createHero } from './hero.js';
import { createDrone } from './drone.js';
import { createEnemies, pushOut } from './enemies.js';
import { createFx } from './fx.js';
import { createTouch, buzz } from './touch.js';
import { loadModels } from './models.js';
import { createArsenal, WEAPONS, ICONS } from './weapons.js';
import { createRange } from './range.js';
import { createWheel } from './wheel.js';
import { createHud } from './hud.js';
import { createMenu } from './menu.js';
import { createGamepad } from './gamepad.js';
import { settings } from './settings.js';
import { sfx, music, audioState } from './audio.js';
import { createRails } from './rails.js';
import { createGizmart, SHOP, GIZ_LINES } from './gizmart.js';
import { createDodger } from './dodger.js';
import { createCraneBot } from './cranebot.js';
import { createStory } from './story.js';
import { playComic, comicPad, INTRO, OUTRO } from './comic.js';

const params = new URLSearchParams(location.search);
// phones and tablets get touch controls and the lighter graphics mode by default
const TOUCH = params.get('touch') === '1' || (params.get('touch') !== '0' && matchMedia('(pointer: coarse)').matches);
const LQ = params.has('lq') ? params.get('lq') === '1' : settings.quality === 'auto' ? TOUCH : settings.quality === 'low';
const $ = id => document.getElementById(id);
if (!TOUCH) document.body.classList.add('desktop');

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
// character and weapon models from Blender; ?basic=1 uses the original basic shapes instead
$('go').textContent = 'Loading…';
document.querySelectorAll('#mainMenu .mbtn').forEach(b => (b.disabled = true));
const models = params.get('basic') === '1' ? {} : await loadModels(p => { $('go').textContent = `Loading… ${Math.round(p * 100)}%`; });
$('go').textContent = '';
document.querySelectorAll('#mainMenu .mbtn').forEach(b => (b.disabled = false));
const hero = createHero(scene, models.hero);
const drone = createDrone(scene, models.drone);
const enemies = createEnemies(scene, fx, models);
const range = createRange(world.arenaG, fx);
const sky1 = world.levels.skyharbor.data;
const rails = createRails(world.skyG, sky1.rails);
const gizmarts = sky1.gizmarts.map(g => createGizmart(world.skyG, g.pos, g.yaw));
const boss = createCraneBot(scene, fx);
const extraTargets = []; // story targets: the signal relay and the boss

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
  camera.aspect = innerWidth / innerHeight;
  // keep a sensible view on very wide phone screens
  camera.fov = camera.aspect > 1.9 ? 50 : 55;
  camera.updateProjectionMatrix();
  renderer.setSize(innerWidth, innerHeight); composer.setSize(innerWidth, innerHeight);
}
addEventListener('resize', resize); resize();

// ---------- game state ----------
let state = 'title', mode = 'waves';
const MAX_HULL = 8;
const player = {
  pos: V(0, 0, 4), vel: V(0, 0, 0), yaw: Math.PI, pitch: -0.05, grounded: true, jumps: 0, coyote: 0,
  hull: MAX_HULL, invuln: 0, dashT: 0, dashCd: 0, jetT: 0, regenT: 0, groundY: 0, sparkT: 0,
  meleeCd: 0, meleeHit: 0, jumpBuf: 0, jumpAge: 0, jumpCut: false, longJump: false, sinceDash: 9, aimHold: 0, lookIdle: 9, landT: 0, faceYaw: Math.PI, turnRate: 0,
};
const stats = { nuts: 0, kills: 0, wave: 0, shots: 0, hits: 0 };
let waveState = { toSpawn: [], spawnT: 0, clearT: -1 };
const pickups = [];
let timeScale = 1, lastWid = 'lancer';

const near = p => 1 / (1 + p.distanceTo(player.pos) / 14); // sounds get quieter with distance

// ---------- targets (bots + practice targets) shared by every weapon ----------
const centerOf = t => (t.type === 'roller' ? t.pos.clone().add(V(0, 0.55, 0)) : t.pos.clone());
const liveTargets = () => {
  const out = [];
  for (const e of enemies.list) if (!e.dead) out.push(e);
  if (mode !== 'story') for (const t of range.targets) if (!t.dead) out.push(t);
  for (const t of extraTargets) if (!t.dead) out.push(t);
  return out;
};
const hits = {
  center: centerOf,
  segment(a, b, pad = 0.15) {
    const ab = b.clone().sub(a), len2 = Math.max(1e-6, ab.lengthSq());
    let best = null, bestT = Infinity;
    for (const t of liveTargets()) {
      const c = centerOf(t);
      const k = clamp(c.clone().sub(a).dot(ab) / len2, 0, 1);
      if (a.clone().addScaledVector(ab, k).distanceTo(c) < t.radius + pad && k < bestT) { bestT = k; best = t; }
    }
    return best ? { t: best, point: a.clone().addScaledVector(ab, bestT) } : null;
  },
  inRadius(p, r) { return liveTargets().map(t => ({ t, c: centerOf(t) })).filter(({ t, c }) => c.distanceTo(p) < r + t.radius); },
  // the bot nearest the crosshair direction (within ~20 degrees), preferring real bots over practice targets
  lock(from, dir) {
    let best = null, score = Infinity;
    for (const t of liveTargets()) {
      const d = centerOf(t).sub(camPivot); const dist = d.length(); if (dist > 55) continue;
      const a = d.normalize().angleTo(dir); if (a > 0.36) continue;
      const s = a + dist * 0.002 + (t.type === 'dummy' ? 0.2 : 0);
      if (s < score) { score = s; best = t; }
    }
    return best;
  },
};
function deal(t, amount, point, wid) {
  if (t.dead) return;
  lastWid = wid;
  stats.hits++;
  let kill;
  if (t.type === 'dummy') kill = range.damage(t, amount);
  else if (t.type === 'relay') kill = story.damageRelay(amount);
  else if (t.type === 'boss') kill = boss.damage(amount);
  else { enemies.damage(t, amount, point, ctx); kill = t.dead; }
  hud.hit(kill);
  if (t.type === 'dummy') { if (kill) sfx.targetDown(); else sfx.targetHit(); } else if (!kill) sfx.hit(near(point));
  hud.damageNumber(point, amount, kill, WEAPONS.find(w => w.id === wid)?.color);
}

// ---------- HUD, weapons, wheel, menus ----------
const hud = createHud({ maxHull: MAX_HULL, weapons: WEAPONS });
const arsenal = createArsenal({
  scene, fx, hero, models, colliders: world.colliders, floorAt, hits, deal,
  onEmpty(w, overheated) { if (overheated) { hud.toast('Overheated'); sfx.overheat(); } else { hud.toast(`${w.name}: out of ammo`); sfx.empty(); } },
  onLevel(w) { hud.banner(`${w.name} V${w.level}`, 'Weapon upgraded: more damage, faster fire', w.color); fx.ring(player.pos.clone().add(V(0, 1, 0)), 0xffc23d); buzz(30); sfx.levelUp(); },
});
function selectWeapon(i) {
  if (arsenal.state[i] && arsenal.state[i].owned === false) { hud.toast(`${WEAPONS[i].name}: buy it at Gizmart`); sfx.empty(); return; }
  if (arsenal.select(i)) { hud.toast(WEAPONS[i].name); buzz(12); sfx.switchWeapon(); }
}
// next/previous weapon you own
function cycleWeapon(dir) {
  for (let k = 1; k < WEAPONS.length; k++) {
    const i = (arsenal.index + dir * k + WEAPONS.length * 2) % WEAPONS.length;
    if (arsenal.state[i].owned !== false) { selectWeapon(i); return; }
  }
}
const wheel = createWheel(WEAPONS, i => selectWeapon(i));
const openWheel = () => { if (state === 'playing' && !wheel.open) { wheel.show(arsenal.state, arsenal.index); input.fire = false; sfx.wheelOpen(); } };
const menu = createMenu(a => {
  if (a === 'story') { mode = 'story'; reset(); startStory(); }
  else if (a === 'waves' || a === 'range') { mode = a; reset(); begin(); }
  else if (a === 'resume' || a === 'leave') { if (a === 'leave') dodger.say(pick(GIZ_LINES.bye), 1, 'giz'); begin(); }
  else if (a.startsWith('buy:')) buy(a.slice(4));
  else if (a === 'restart' || a === 'again') { reset(); begin(); }
  else if (a === 'quit') { reset(); state = 'title'; touch?.show(false); menu.show('title'); music.intensity = 0.3; }
});

// ---------- story mode: Dodger, Gizmart, the Skyharbor script ----------
const pick = a => a[Math.floor(Math.random() * a.length)];
const dodger = createDodger({ isPlaying: () => state === 'playing' });
dodger.onComboEnd = n => { const b = n * 15; stats.nuts += b; hud.nuts(stats.nuts); hud.toast(`Combo x${n}: +${b} nuts`); sfx.cell(); };
// a random open spot inside an area, away from the hero and from props on the floor
function spawnIn(r, minDist = 6) {
  for (let k = 0; k < 50; k++) {
    const x = rand(r.minX + 1.5, r.maxX - 1.5), z = rand(r.minZ + 1.5, r.maxZ - 1.5);
    if (Math.hypot(x - player.pos.x, z - player.pos.z) < minDist) continue;
    if (world.colliders.some(c => c.min.y > -0.5 && c.max.y < 5 && x > c.min.x - 0.8 && x < c.max.x + 0.8 && z > c.min.z - 0.8 && z < c.max.z + 0.8)) continue;
    return [x, z];
  }
  return [(r.minX + r.maxX) / 2, (r.minZ + r.maxZ) / 2];
}
const story = createStory({
  player, enemies, rails, dodger, hud, sfx, fx, boss, gizmarts, relay: sky1.relay, extraTargets, spawnIn, start: sky1.start, bossPos: sky1.bossPos,
  hurtHero: (n, from, force) => ctx.hurtHero(n, from, force),
  heal: n => { player.hull = Math.min(MAX_HULL, player.hull + n); hud.hull(player.hull, true); },
  dropNuts: (p, n) => dropNuts(p, n), shake: n => { shake = Math.max(shake, n); },
  openShop, onComplete: storyComplete,
});
function startStory() {
  state = 'comic'; menu.hide(); music.start(); music.intensity = 0.3;
  playComic(INTRO, () => { state = 'title'; begin(); });
}
function storyComplete() {
  state = 'comic'; input.fire = false; touch?.show(false); wheel.close(false);
  if (document.pointerLockElement) document.exitPointerLock();
  music.intensity = 0.3;
  playComic(OUTRO, () => {
    const t = Math.round(story.time), mm = Math.floor(t / 60), ss = String(t % 60).padStart(2, '0');
    const acc = stats.shots ? Math.round(100 * Math.min(1, stats.hits / stats.shots)) : 0;
    $('doneStats').innerHTML = `<tr><td>Time</td><td>${mm}:${ss}</td></tr><tr><td>Bots wrecked</td><td>${stats.kills}</td></tr>
      <tr><td>Hex nuts</td><td>${stats.nuts.toLocaleString()}</td></tr><tr><td>Falls</td><td>${story.deaths}</td></tr>
      <tr><td>Hit rate</td><td>${acc}%</td></tr><tr><td>Dodger's best rating</td><td>${dodger.best || '-'}/10</td></tr>`;
    state = 'dead'; menu.show('done');
  });
}
// Gizmart's shop screen
let shopGiz = null;
function renderShop() {
  $('shopNuts').textContent = stats.nuts.toLocaleString();
  $('shopList').innerHTML = SHOP.map(it => {
    const w = it.kind === 'weapon' ? arsenal.state.find(x => x.id === it.id) : null;
    const owned = w?.owned, full = (it.kind === 'repair' && player.hull >= MAX_HULL) || (it.kind === 'ammo' && arsenal.state.every(x => !x.owned || x.regen || x.ammo >= x.max));
    const cant = !owned && !full && stats.nuts < it.price;
    const c = w ? WEAPONS.find(x => x.id === it.id).color : it.kind === 'repair' ? '#7dff9a' : '#d070ff';
    return `<button class="mbtn shop ${owned || full ? 'owned' : ''} ${cant ? 'poor' : ''}" data-act="buy:${it.id}" style="--c:${c}">
      ${w ? `<svg viewBox="0 0 60 60">${ICONS[it.id]}</svg>` : `<span class="sico">${it.kind === 'repair' ? '+' : '&#8801;'}</span>`}
      <span class="sname">${it.name}<small>${it.blurb}</small></span><span class="sprice">${owned ? 'OWNED' : full ? 'FULL' : it.price}</span></button>`;
  }).join('') + '<button class="mbtn primary" data-act="leave">Leave shop</button>';
  menu.refresh();
}
function openShop(g) {
  if (state !== 'playing') return;
  shopGiz = g; state = 'paused'; input.fire = false; wheel.close(false); touch?.show(false);
  if (document.pointerLockElement) document.exitPointerLock();
  $('shopLine').textContent = pick(GIZ_LINES.hello);
  menu.show('shopMenu'); renderShop();
}
function buy(id) {
  const it = SHOP.find(x => x.id === id); if (!it) return;
  const w = it.kind === 'weapon' ? arsenal.state.find(x => x.id === id) : null;
  if (w?.owned) return;
  if ((it.kind === 'repair' && player.hull >= MAX_HULL)) { $('shopLine').textContent = 'You look fine to me! Shiny, even!'; return; }
  if (stats.nuts < it.price) { $('shopLine').textContent = pick(GIZ_LINES.broke); sfx.empty(); return; }
  stats.nuts -= it.price; hud.nuts(stats.nuts); sfx.levelUp(); shopGiz?.talk();
  if (w) { w.owned = true; w.ammo = w.max; arsenal.select(arsenal.state.indexOf(w)); $('shopLine').textContent = `${it.name}! ` + pick(GIZ_LINES.buy); }
  else if (it.kind === 'ammo') { arsenal.refill(1); $('shopLine').textContent = pick(GIZ_LINES.buy); }
  else { player.hull = Math.min(MAX_HULL, player.hull + 4); hud.hull(player.hull, true); $('shopLine').textContent = pick(GIZ_LINES.buy); }
  renderShop();
}

// ---------- input ----------
const keys = new Set();
const input = { fire: false, look: { dx: 0, dy: 0 }, jumpPressed: false, dashPressed: false, meleePressed: false };
addEventListener('keydown', e => {
  if (e.repeat) return;
  keys.add(e.code);
  if (state !== 'playing') return;
  if (e.code === 'Space') { input.jumpPressed = true; e.preventDefault(); }
  if (e.code === 'ShiftLeft' || e.code === 'ShiftRight') input.dashPressed = true;
  if (e.code === 'KeyF' || e.code === 'KeyV') input.meleePressed = true;
  if (e.code === 'KeyQ' || e.code === 'Tab') { openWheel(); e.preventDefault(); }
  if (/^Digit[1-4]$/.test(e.code)) selectWeapon(+e.code.slice(5) - 1);
  if (e.code === 'KeyP' || (e.code === 'Escape' && !document.pointerLockElement)) pause();
  if (e.code === 'Enter' || e.code === 'NumpadEnter') input.jumpPressed = true; // controllers in keyboard mode send Enter for A
});
addEventListener('keyup', e => {
  keys.delete(e.code);
  if ((e.code === 'KeyQ' || e.code === 'Tab') && wheel.open) wheel.close(true);
});
addEventListener('blur', () => { keys.clear(); input.fire = false; });
const realMouse = e => (e.pointerType ? e.pointerType === 'mouse' : true) && !e.sourceCapabilities?.firesTouchEvents;
addEventListener('mousedown', e => {
  if (!realMouse(e) || state !== 'playing' || wheel.open) return;
  if (e.button === 0) input.fire = true;
  if (e.button === 2) input.dashPressed = true;
  if (e.button === 1) { input.meleePressed = true; e.preventDefault(); }
});
addEventListener('mouseup', e => { if (realMouse(e) && e.button === 0) input.fire = false; });
addEventListener('wheel', e => { if (state === 'playing' && !wheel.open) cycleWeapon(e.deltaY > 0 ? 1 : -1); }, { passive: true });
let ignoreMouseUntil = 0;
addEventListener('pointermove', e => {
  if (!realMouse(e)) return;
  // browsers can report one huge jump when the pointer gets locked; skip it
  if (state !== 'playing' || performance.now() < ignoreMouseUntil) return;
  if (Math.abs(e.movementX) > 250 || Math.abs(e.movementY) > 250) return;
  if (wheel.open) { wheel.point(e.movementX, e.movementY); return; }
  input.look.dx += e.movementX * settings.sens; input.look.dy += e.movementY * settings.sens;
});
addEventListener('contextmenu', e => e.preventDefault());
const canvas = renderer.domElement;
const lock = () => { try { const p = canvas.requestPointerLock?.(); p?.catch?.(() => {}); } catch { /* no pointer lock (e.g. headless) */ } };
let hadLock = false;
document.addEventListener('pointerlockchange', () => {
  if (document.pointerLockElement) { hadLock = true; ignoreMouseUntil = performance.now() + 150; }
  else if (hadLock && state === 'playing' && !pad.state.active) pause();
});
// clicking the game while playing (e.g. after the pointer was released) grabs the mouse again
canvas.addEventListener('click', () => { if (state === 'playing' && !TOUCH && !document.pointerLockElement) lock(); });

const pad = createGamepad();
let padWheel = false;
const touch = TOUCH ? createTouch({
  input, isPlaying: () => state === 'playing', onPause: () => pause(),
  onWheelOpen: openWheel,
  onWheelDrag: (dx, dy) => wheel.point(dx / 60, dy / 60, true),
  onWheelRelease: dragged => { if (dragged) wheel.close(true); },
}) : null;

function reset() {
  world.setLevel(mode === 'story' ? 'skyharbor' : 'arena');
  if (mode === 'story') world.colliders.push(boss.collider);
  enemies.clear(); arsenal.reset(); rails.detach(0); boss.hide(); extraTargets.length = 0; hud.boss(null); dodger.reset(); callQueue.length = 0;
  arsenal.state.forEach((w, i) => { w.owned = mode !== 'story' || i === 0; });
  pickups.forEach(p => scene.remove(p.m)); pickups.length = 0;
  Object.assign(player, { hull: MAX_HULL, invuln: 0, dashT: 0, dashCd: 0, jumps: 0 });
  player.pos.set(0, 0, 4); player.vel.set(0, 0, 0); player.yaw = Math.PI; player.pitch = -0.05;
  Object.assign(stats, { nuts: 0, kills: 0, wave: 0, shots: 0, hits: 0 });
  waveState = { toSpawn: [], spawnT: 0, clearT: mode === 'waves' ? 1.2 : -1 };
  arsenal.infinite = mode === 'range';
  if (mode === 'range') player.pos.set(5.5, 0, -12.5);
  if (mode === 'story') { player.pos.copy(sky1.start.pos); player.yaw = sky1.start.yaw; stats.nuts = 100; story.reset(); } else story.stop();
  player.groundY = player.pos.y; camPivot.copy(player.pos); camY = player.pos.y; player.faceYaw = player.yaw; player.aimHold = 0; player.longJump = false;
  hud.hull(player.hull); hud.nuts(stats.nuts); hud.weapon(arsenal.state, arsenal.index);
}
function begin() {
  music.start(); music.intensity = 1;
  if (touch) {
    // go full screen and sideways where the browser allows it
    const de = document.documentElement;
    if (!document.fullscreenElement && de.requestFullscreen) de.requestFullscreen({ navigationUI: 'hide' }).then(() => screen.orientation?.lock?.('landscape').catch(() => {})).catch(() => {});
    touch.reset(); touch.show(true);
  } else if (!pad.state.active) lock();
  menu.hide();
  if (mode === 'range' && state !== 'paused') hud.banner('TEST RANGE', 'Targets north, jump course east, cover yard west. Step on CALL BOTS to fight.', '#ffd040');
  state = 'playing';
  input.fire = false;
}
function pause() {
  if (state !== 'playing') return;
  music.intensity = 0.3;
  state = 'paused'; input.fire = false; wheel.close(false);
  touch?.show(false);
  if (document.pointerLockElement) document.exitPointerLock();
  menu.show('pauseMenu');
}
function gameOver() {
  state = 'dead'; input.fire = false; touch?.show(false); wheel.close(false); sfx.gameOver(); music.intensity = 0.3;
  if (document.pointerLockElement) document.exitPointerLock();
  $('summary').innerHTML = mode === 'story'
    ? `Wrecked <b>${stats.kills}</b> bots before the hull gave out. Dodger says: "I believe in you. Mostly."`
    : `You reached wave <b>${stats.wave}</b>, wrecked <b>${stats.kills}</b> bots and banked <b>${stats.nuts.toLocaleString()}</b> hex nuts.`;
  story.stop();
  setTimeout(() => { if (state === 'dead') menu.show('over'); }, 1200);
}

// ---------- waves ----------
function startWave(n) {
  stats.wave = n;
  const rollers = 2 + n, hornets = Math.floor((n + 1) / 2);
  const list = [];
  for (let i = 0; i < Math.max(rollers, hornets); i++) { if (i < rollers) list.push('roller'); if (i < hornets) list.push('hornet'); }
  waveState.toSpawn = list; waveState.spawnT = 0.6;
  hud.banner(`WAVE ${n}`, n === 1 ? 'Clear the deck' : `${list.length} bots incoming`); sfx.waveStart();
}
const aggression = () => (mode === 'range' ? 1 : 1 + (stats.wave - 1) * 0.08);
// somewhere on open deck 8-22 m from the hero
function spawnPoint() {
  for (let k = 0; k < 40; k++) {
    const a = rand(0, Math.PI * 2), r = rand(8, 22);
    const x = player.pos.x + Math.sin(a) * r, z = player.pos.z + Math.cos(a) * r;
    if (x < ARENA.minX + 1.5 || x > ARENA.maxX - 1.5 || z < ARENA.minZ + 1.5 || z > ARENA.maxZ - 1.5) continue;
    if (world.colliders.some(c => x > c.min.x - 0.8 && x < c.max.x + 0.8 && z > c.min.z - 0.8 && z < c.max.z + 0.8)) continue;
    return [x, z];
  }
  return [clamp(player.pos.x + 10, ARENA.minX + 2, ARENA.maxX - 2), clamp(player.pos.z, ARENA.minZ + 2, ARENA.maxZ - 2)];
}
function updateWaves(dt) {
  if (mode !== 'waves') return;
  if (waveState.clearT >= 0) {
    waveState.clearT -= dt;
    if (waveState.clearT < 0) startWave(stats.wave + 1);
    return;
  }
  if (waveState.toSpawn.length) {
    waveState.spawnT -= dt;
    if (waveState.spawnT <= 0) {
      const [x, z] = spawnPoint();
      enemies.spawn(waveState.toSpawn.shift(), x, z); sfx.spawn(near(V(x, 0, z)));
      waveState.spawnT = rand(0.5, 1.1);
    }
  } else if (enemies.list.length === 0 && state === 'playing') {
    hud.banner('WAVE CLEAR', `+${50 * stats.wave} bonus nuts`); sfx.waveClear();
    stats.nuts += 50 * stats.wave; hud.nuts(stats.nuts);
    if (player.hull < MAX_HULL) { player.hull = Math.min(MAX_HULL, player.hull + 2); hud.hull(player.hull); }
    waveState.clearT = 3.2;
  }
}
const callQueue = [];
function callBots() {
  if (enemies.list.length >= 8) { hud.toast('Plenty of bots out already'); return; }
  hud.banner('BOTS INCOMING', '3 Scrap Rollers and 2 Rivet Hornets', '#ff5040');
  ['roller', 'hornet', 'roller', 'hornet', 'roller'].forEach((type, i) => callQueue.push({ type, t: 0.3 + i * 0.45 }));
}
function updateCalls(dt) {
  for (let i = callQueue.length - 1; i >= 0; i--) {
    const c = callQueue[i]; c.t -= dt;
    if (c.t <= 0) { const [x, z] = spawnPoint(); enemies.spawn(c.type, x, z); sfx.spawn(near(V(x, 0, z))); callQueue.splice(i, 1); }
  }
}

// ---------- hero physics ----------
const GRAV = 28, RUN = 8.4, JUMP = 9.4, BOOST = 8.2, RADIUS = 0.38, LONG_SPEED = 15.5, LONG_UP = 8;
function floorAt(p) {
  let f = onDeck(p.x, p.z, 0.15) ? 0 : -Infinity; // open sky between Skyharbor's islands
  for (const c of world.colliders) {
    if (p.x > c.min.x - RADIUS * 0.6 && p.x < c.max.x + RADIUS * 0.6 && p.z > c.min.z - RADIUS * 0.6 && p.z < c.max.z + RADIUS * 0.6 && p.y >= c.max.y - 0.3) f = Math.max(f, c.max.y);
  }
  return f;
}
function updatePlayer(dt, p) {
  // look: mouse/touch deltas plus the right stick (with a curve so small pushes are precise)
  const sens = 0.0024, inv = settings.invertY ? -1 : 1;
  player.yaw -= input.look.dx * sens; player.pitch -= input.look.dy * sens * inv;
  const looked = Math.abs(input.look.dx) + Math.abs(input.look.dy) > 0.5 || (p && Math.abs(p.lx) + Math.abs(p.ly) > 0.12);
  player.lookIdle = looked ? 0 : player.lookIdle + dt;
  input.look.dx = input.look.dy = 0;
  if (p && !padWheel) {
    const curve = v => Math.sign(v) * Math.pow(Math.abs(v), 1.8);
    player.yaw -= curve(p.lx) * 3.4 * settings.padSens * dt; player.pitch -= curve(p.ly) * 2.4 * settings.padSens * dt * inv;
  }
  // aim assist on touch and controller: while firing, drift gently toward the bot nearest the crosshair
  const assisted = settings.aimAssist && (touch || pad.state.active) && (input.fire || p?.fire);
  if (assisted) {
    let best = null, bestA = 0.16;
    for (const t of liveTargets()) {
      const d = centerOf(t).sub(camPivot);
      const a = d.clone().normalize().angleTo(aimDir);
      if (a < bestA && d.length() < 35) { bestA = a; best = d; }
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
  if (p) { mx += p.mx; mz += p.mz; }
  if (input.touchMove) { mx += input.touchMove.x; mz += input.touchMove.z; }
  const ml = Math.hypot(mx, mz); if (ml > 1) { mx /= ml; mz /= ml; }
  const fwd = V(Math.sin(player.yaw), 0, Math.cos(player.yaw));
  const right = V(-Math.cos(player.yaw), 0, Math.sin(player.yaw));
  const wish = fwd.multiplyScalar(mz).addScaledVector(right, mx).multiplyScalar(RUN);

  // riding a grind rail: the rail moves you; jump hops off with the rail's momentum
  if (rails.riding) {
    if (input.jumpPressed) {
      input.jumpPressed = false; player.jumpCut = true; player.longJump = false;
      rails.detach(); player.vel.y = Math.max(player.vel.y, 0) + JUMP; player.grounded = false; player.jumps = 1; sfx.jump();
    } else {
      rails.step(dt, player.pos, player.vel);
      player.grounded = !rails.riding ? false : true; player.jumps = rails.riding ? 0 : 1;
      player.sparkT -= dt;
      if (rails.riding && player.sparkT <= 0) { player.sparkT = 0.05; fx.sparks(player.pos.clone(), 0xffc060, 3, 2.5); sfx.grind(); }
      input.jumpPressed = input.dashPressed = false;
      if (rails.riding) {
        // gently turn the view to look along the rail
        if (Math.hypot(player.vel.x, player.vel.z) > 2) player.yaw += angleDiff(player.yaw, Math.atan2(player.vel.x, player.vel.z)) * (1 - Math.exp(-1.1 * dt));
        player.coyote = 0.12; return;
      }
    }
  }

  // melee bash: hits everything in a wide arc in front, with a small lunge toward the nearest bot
  player.meleeCd -= dt;
  if (input.meleePressed && player.meleeCd <= 0) {
    player.meleeCd = 0.42; player.meleeHit = 0.09;
    let near = null, nd = 3.2;
    for (const t of liveTargets()) { const c = centerOf(t); const d = Math.hypot(c.x - player.pos.x, c.z - player.pos.z); if (d < nd && Math.abs(c.y - player.pos.y - 0.8) < 2) { nd = d; near = c; } }
    if (near) player.faceYaw = Math.atan2(near.x - player.pos.x, near.z - player.pos.z);
    const f = V(Math.sin(player.faceYaw), 0, Math.cos(player.faceYaw));
    player.vel.x += f.x * 5; player.vel.z += f.z * 5;
    hero.swing(); sfx.swing();
    fx.swipe(player.pos.clone().add(V(0, 0.95, 0)), player.faceYaw);
  }
  input.meleePressed = false;
  if (player.meleeHit > 0) {
    player.meleeHit -= dt;
    if (player.meleeHit <= 0) {
      const f = V(Math.sin(player.faceYaw), 0, Math.cos(player.faceYaw));
      let any = false;
      for (const t of liveTargets()) {
        const c = centerOf(t), d = c.clone().sub(player.pos); const dy = d.y - 0.8; d.y = 0;
        const reach = 2.4 + (t.radius || 0.5) * 0.6;
        if (d.length() < reach && Math.abs(dy) < 1.8 && (d.length() < 0.8 || d.normalize().dot(f) > -0.1)) {
          deal(t, t.type === 'boss' ? 3 : 2, c, 'melee'); any = true;
          fx.sparks(c, 0xfff0b0, 14, 6);
        }
      }
      if (any) { sfx.bash(); hitStop = Math.max(hitStop, 0.06); shake = Math.max(shake, 0.5); }
    }
  }

  const jumpHeld = keys.has('Space') || p?.held(p.BTN.A) || input.jumpHeld;
  // a jump pressed a moment before landing still counts
  if (input.jumpPressed) player.jumpBuf = 0.14;
  input.jumpPressed = false;
  player.jumpBuf -= dt;

  player.dashCd -= dt; player.sinceDash += dt;
  if (input.dashPressed && player.dashCd <= 0) {
    const dir = ml > 0.1 ? wish.clone().normalize() : V(Math.sin(player.faceYaw), 0, Math.cos(player.faceYaw));
    player.vel.x = dir.x * 18; player.vel.z = dir.z * 18;
    player.dashT = 0.16; player.dashCd = 0.6; player.sinceDash = 0; player.invuln = Math.max(player.invuln, 0.2); sfx.dash();
    fx.puff(player.pos.clone().add(V(0, 0.3, 0)));
  }
  input.dashPressed = false;
  const hs = Math.hypot(player.vel.x, player.vel.z);
  if (player.dashT > 0) player.dashT -= dt;
  else if (player.grounded) {
    // on the ground: turn the run direction smoothly instead of sliding through a stop, and get up to speed fast
    const want = Math.hypot(wish.x, wish.z);
    if (want > 0.3) {
      const cur = hs > 0.5 ? Math.atan2(player.vel.x, player.vel.z) : Math.atan2(wish.x, wish.z);
      const tgt = Math.atan2(wish.x, wish.z), diff = angleDiff(cur, tgt);
      // a sharp reversal skids (loses speed); gentle turns keep it
      const turned = cur + clamp(diff, -16 * dt, 16 * dt);
      let speed = Math.abs(diff) > 2.3 ? hs * Math.exp(-14 * dt) : hs;
      speed = speed < want ? Math.min(want, speed + 55 * dt) : damp(speed, want, 7, dt);
      player.vel.x = Math.sin(turned) * speed; player.vel.z = Math.cos(turned) * speed;
    } else {
      // stop quickly but not instantly
      const k = Math.exp(-16 * dt); player.vel.x *= k; player.vel.z *= k;
    }
  } else {
    // in the air: steer, but keep momentum (long jumps and rail hops carry you)
    const cap = Math.max(RUN, hs);
    player.vel.x += wish.x * 2.2 * dt * (player.longJump ? 0.4 : 1); player.vel.z += wish.z * 2.2 * dt * (player.longJump ? 0.4 : 1);
    if (!player.longJump) { player.vel.x = damp(player.vel.x, Math.max(-cap, Math.min(cap, wish.x)), 2.5, dt); player.vel.z = damp(player.vel.z, Math.max(-cap, Math.min(cap, wish.z)), 2.5, dt); }
    const nh = Math.hypot(player.vel.x, player.vel.z); if (nh > cap) { player.vel.x *= cap / nh; player.vel.z *= cap / nh; }
  }

  // jump / long jump / jet boost
  player.coyote -= dt;
  if (player.jumpBuf > 0) {
    if (player.grounded || player.coyote > 0) {
      player.jumpBuf = 0; player.grounded = false; player.coyote = 0; player.jumps = 1; player.jumpCut = false; player.jumpAge = 0;
      if (player.sinceDash < 0.28 && hs > 9) {
        // jumping out of a dash: a long, low leap
        const d = V(player.vel.x, 0, player.vel.z).normalize();
        player.vel.x = d.x * LONG_SPEED; player.vel.z = d.z * LONG_SPEED; player.vel.y = LONG_UP; player.longJump = true; player.dashT = 0;
        fx.sparks(player.pos.clone().add(V(0, 0.5, 0)), 0x60e8ff, 10, 3); sfx.boost();
      } else { player.vel.y = JUMP; player.longJump = false; sfx.jump(); }
      fx.puff(player.pos.clone().add(V(0, 0.1, 0)));
    } else if (player.jumps < 2) {
      player.jumpBuf = 0; player.vel.y = BOOST; player.jumps = 2; player.jetT = 0.35; player.jumpCut = true; player.longJump = false;
      fx.sparks(player.pos.clone().add(V(0, 0.6, 0)), 0x60e8ff, 12, 3); sfx.boost();
    }
  }
  // let go of jump early for a short hop
  player.jumpAge += dt;
  if (!jumpHeld && !player.jumpCut && player.jumpAge > 0.09 && !player.grounded && player.vel.y > 0 && player.jumps === 1 && !player.longJump) { player.vel.y *= 0.55; player.jumpCut = true; }
  player.jetT -= dt;
  // holding jump while falling glides a little
  const gliding = !player.grounded && player.vel.y < 0 && jumpHeld && player.jumps === 2;
  // a floatier top of the jump arc, faster fall afterwards
  const g = gliding ? 0.35 : Math.abs(player.vel.y) < 2.5 ? 0.7 : player.vel.y < 0 ? 1.25 : 1;
  player.vel.y -= GRAV * dt * g;
  if (gliding) player.vel.y = Math.max(player.vel.y, -3);
  player.vel.y = Math.max(player.vel.y, -30);

  // integrate and collide
  const pp = player.pos;
  pp.x += player.vel.x * dt; pp.z += player.vel.z * dt;
  for (const c of world.colliders) pushOut(pp, RADIUS, c);
  pp.x = clamp(pp.x, ARENA.minX + RADIUS, ARENA.maxX - RADIUS); pp.z = clamp(pp.z, ARENA.minZ + RADIUS, ARENA.maxZ - RADIUS);
  pp.y += player.vel.y * dt;
  const f = floorAt(pp);
  if (pp.y <= f) {
    if (!player.grounded && player.vel.y < -6) { fx.puff(pp.clone().add(V(0, 0.05, 0))); sfx.land(); player.landT = clamp(-player.vel.y / 20, 0.3, 1); }
    if (!player.grounded) player.longJump = false;
    pp.y = f; player.vel.y = 0; player.grounded = true; player.jumps = 0; player.coyote = 0.12; player.groundY = f;
  } else if (player.grounded && pp.y > f) {
    player.grounded = false; player.jumps = 1; // walked off a ledge
  }
  // land on (or walk into) a grind rail
  if (mode === 'story' && rails.tryAttach(pp, player.vel, dt)) { player.grounded = true; player.jumps = 0; dodger.line('grind'); sfx.land(); }
  player.invuln -= dt;
  // test range: the hull slowly repairs itself
  if (mode === 'range' && player.hull < MAX_HULL) { player.regenT += dt; if (player.regenT > 2) { player.regenT = 0; player.hull++; hud.hull(player.hull, true); } }
}

// ---------- camera + aim ----------
const camPivot = V(0, 0, 0), aimDir = V(0, 0, 1), aimPoint = V(0, 0, 0);
const camRay = new THREE.Ray(), camBox = new THREE.Box3(), camHit = V(0, 0, 0), aimRay = new THREE.Ray(), aimBox = new THREE.Box3(), aimHit = V(0, 0, 0);
let camSmooth = 4.0, camY = 0, shoulder = 0.95, fovKick = 0, hitStop = 0;
let shake = 0;
function updateCamera(dt) {
  // controller and touch players: while running and not steering the view, the camera slowly swings in behind
  if (state === 'playing' && (touch || pad.state.active) && player.lookIdle > 0.7 && player.aimHold <= 0 && !rails.riding) {
    const hs = Math.hypot(player.vel.x, player.vel.z);
    if (hs > 3) player.yaw += angleDiff(player.yaw, Math.atan2(player.vel.x, player.vel.z)) * (1 - Math.exp(-0.9 * dt)) * Math.min(1, (hs - 3) / 4);
  }
  const cp = Math.cos(player.pitch);
  aimDir.set(Math.sin(player.yaw) * cp, Math.sin(player.pitch), Math.cos(player.yaw) * cp);
  const right = V(-Math.cos(player.yaw), 0, Math.sin(player.yaw));
  // over the left shoulder, on the side the blaster is held
  shoulder = damp(shoulder, player.aimHold > 0 ? 0.95 : 0.6, 5, dt);
  // follow height smoothly: jumps don't yank the view, but falls and big drops are tracked
  const footY = player.grounded || rails.riding ? player.pos.y : Math.min(Math.max(camY, player.pos.y - 1.5), player.pos.y);
  camY = damp(camY, footY, player.grounded || rails.riding ? 10 : player.pos.y < camY ? 12 : 3, dt);
  const target = V(player.pos.x, camY + 1.55, player.pos.z).addScaledVector(right, -shoulder);
  // a little lag sideways and forwards makes motion read better
  camPivot.x = damp(camPivot.x, target.x, 13, dt); camPivot.z = damp(camPivot.z, target.z, 13, dt); camPivot.y = damp(camPivot.y, target.y, 16, dt);
  const speedFov = clamp((Math.hypot(player.vel.x, player.vel.z) - 9) / 8, 0, 1) * 7;
  fovKick = damp(fovKick, speedFov, 4, dt);
  const fov = 55 + fovKick; if (Math.abs(camera.fov - fov) > 0.01) { camera.fov = fov; camera.updateProjectionMatrix(); }
  const dist = 4.3 - Math.max(0, player.pitch) * 2.4; // pull in when looking up so the camera stays off the floor
  // pull the camera in front of any crate or wall that would block the view
  let camDist = dist;
  camRay.set(camPivot, aimDir.clone().negate());
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

  // what is under the crosshair? bots and targets first, then props/deck, else far away
  const from = camPivot;
  let best = 150, onTarget = false;
  for (const t of liveTargets()) {
    const c = centerOf(t);
    const k = c.clone().sub(from).dot(aimDir);
    if (k < 0 || k > best) continue;
    if (from.clone().addScaledVector(aimDir, k).distanceTo(c) < t.radius + 0.25) { best = k; onTarget = true; }
  }
  if (aimDir.y < -0.01) { const k = -from.y / aimDir.y; if (k > 0 && k < best && onDeck(from.x + aimDir.x * k, from.z + aimDir.z * k, 0)) { best = k; onTarget = false; } }
  aimRay.set(from, aimDir);
  for (const c of world.colliders) {
    aimBox.min.copy(c.min); aimBox.max.copy(c.max);
    if (aimBox.containsPoint(from)) continue;
    const hit = aimRay.intersectBox(aimBox, aimHit);
    if (hit) { const k = hit.distanceTo(from); if (k < best) { best = k; onTarget = false; } }
  }
  aimPoint.copy(from).addScaledVector(aimDir, best);
  return onTarget;
}

// ---------- pickups ----------
const nutGeo = new THREE.TorusGeometry(0.1, 0.055, 6, 6);
const nutMat = std(0xffc23d, 1.0, 0.22, { emissive: 0x5a3500, emissiveIntensity: 0.6 });
const cellGeo = new THREE.OctahedronGeometry(0.22), cellMat = glow(0x50ff90, 3);
const ammoGeo = new THREE.CapsuleGeometry(0.12, 0.22, 4, 8), ammoMat = glow(0xd070ff, 3);
function dropNuts(pos, n) {
  for (let i = 0; i < n; i++) {
    const m = mesh(nutGeo, nutMat); m.position.copy(pos); m.scale.setScalar(1.6);
    scene.add(m);
    pickups.push({ kind: 'nut', m, vel: V(rand(-3, 3), rand(3, 7), rand(-3, 3)), t: 0, spin: V(rand(-8, 8), rand(-8, 8), 0) });
  }
}
function dropItem(kind, pos) {
  const m = mesh(kind === 'cell' ? cellGeo : ammoGeo, kind === 'cell' ? cellMat : ammoMat, false, false); m.position.copy(pos);
  m.add(glowSprite(kind === 'cell' ? 0x50ff90 : 0xd070ff, 1.0, 0.6)); scene.add(m);
  pickups.push({ kind, m, vel: V(rand(-1, 1), 5, rand(-1, 1)), t: 0, spin: V(kind === 'ammo' ? 2 : 0, 3, 0) });
}
function updatePickups(dt) {
  const target = player.pos.clone().add(V(0, 0.8, 0));
  for (let i = pickups.length - 1; i >= 0; i--) {
    const p = pickups[i]; p.t += dt;
    const d = p.m.position.distanceTo(target);
    // nuts home in when close, or from anywhere once they have settled; cells and ammo need you to walk close
    if (p.t > 0.5 && (d < (p.kind === 'nut' ? 10 : 3) || (p.kind === 'nut' && p.t > 2.2)) && state === 'playing') {
      p.vel.lerp(target.clone().sub(p.m.position).normalize().multiplyScalar(Math.max(14, 30 - d * 1.5)), 1 - Math.exp(-10 * dt));
    } else p.vel.y -= 20 * dt;
    p.m.position.addScaledVector(p.vel, dt);
    const fl = floorAt(p.m.position) + 0.12;
    if (onDeck(p.m.position.x, p.m.position.z, 0) && p.m.position.y < fl) { p.m.position.y = fl; p.vel.y = Math.abs(p.vel.y) * 0.4; p.vel.x *= 0.7; p.vel.z *= 0.7; }
    p.m.rotation.x += p.spin.x * dt; p.m.rotation.y += p.spin.y * dt;
    if (d < 0.7 && state === 'playing') {
      if (p.kind === 'nut') { stats.nuts += 10; hud.nuts(stats.nuts); sfx.nut(); }
      else if (p.kind === 'cell') { player.hull = Math.min(MAX_HULL, player.hull + 1); hud.hull(player.hull, true); sfx.cell(); }
      else { arsenal.refill(0.35); hud.toast('Ammo +35%'); sfx.ammo(); }
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
  get groundY() { return player.groundY; },
  hurtHero(n, from, force = false) {
    if ((player.invuln > 0 && !force) || player.hull <= 0) return;
    player.hull -= n; player.invuln = 0.9; shake = 1;
    hero.hurt(); hud.hurt(); hud.hull(player.hull); buzz(60); sfx.hurt();
    if (player.hull > 0) dodger.line(player.hull <= 2 ? 'low' : 'hurt');
    if (from) { const k = player.pos.clone().sub(from).setY(0).normalize().multiplyScalar(6); player.vel.x += k.x; player.vel.z += k.z; }
    if (player.hull <= 0) {
      if (mode === 'range') { player.hull = MAX_HULL; hud.hull(player.hull); hud.toast('Hull restored (test range)'); }
      else gameOver();
    }
  },
  sound(name, pos) { sfx[name]?.(pos ? near(pos) : 1); },
  onKill(e) {
    sfx.explosion(near(e.pos), e.type === 'hornet' ? 1.2 : 0.9);
    if (e.tag === 'boss') boss.crewDown();
    if (e.selfDestruct) return; // a roller that blew itself up earns nothing
    stats.kills++;
    dodger.kill({ airborne: !player.grounded, grinding: rails.riding, dist: e.pos.distanceTo(player.pos) });
    dropNuts(e.pos.clone().add(V(0, 0.6, 0)), e.nuts);
    if (Math.random() < (player.hull <= 3 ? 0.35 : 0.12)) dropItem('cell', e.pos.clone().add(V(0, 0.8, 0)));
    else if (mode === 'waves' && Math.random() < 0.3) dropItem('ammo', e.pos.clone().add(V(0, 0.8, 0)));
    if (lastWid !== 'melee') arsenal.addXp(lastWid, e.type === 'hornet' ? 40 : 20);
    const kd = e.pos.distanceTo(player.pos);
    shake = Math.max(shake, kd < 20 ? 0.75 - kd * 0.02 : 0.3);
    hitStop = Math.max(hitStop, 0.045);
  },
};

// the boss uses the same hero, shots and rollers as the regular bots
const bossCtx = {
  get heroPos() { return player.pos; }, get alive() { return state === 'playing' && player.hull > 0; },
  hurtHero: (n, from) => ctx.hurtHero(n, from),
  fireShot: (from, to) => enemies.fireShot(from, to),
  spawnRoller: (x, z) => { enemies.spawn('roller', x, z, { zone: world.levels.skyharbor.data.decks[2], tag: 'boss' }); sfx.spawn(0.8); },
  sound: (name, pos) => ctx.sound(name, pos),
  shake: n => { shake = Math.max(shake, n); },
  onDead: at => story.bossDead(at),
  // halfway: the cab spits out two repair cells and gets angry
  onHalf: at => { dropItem('cell', at.clone()); dropItem('cell', at.clone()); dodger.story('dodger', 'It dropped repair cells! Grab them! Also, it looks angrier.'); },
};

// ---------- main loop ----------
const timer = new THREE.Timer();
let simTime = 0;
function readPad(dt) {
  const p = pad.poll();
  if (!p) { if (padWheel) { padWheel = false; wheel.close(false); } return null; }
  const B = p.BTN;
  if (state === 'playing') {
    if (p.pressed(B.A)) input.jumpPressed = true;
    if (p.pressed(B.B) || p.pressed(B.LT)) input.dashPressed = true;
    if (p.pressed(B.START) || p.pressed(B.SELECT)) pause();
    if (p.pressed(B.X)) input.meleePressed = true;
    if (p.pressed(B.RB) || p.pressed(B.Y)) cycleWeapon(1);
    [B.UP, B.RIGHT, B.DOWN, B.LEFT].forEach((b, i) => { if (p.pressed(b)) selectWeapon(i); });
    if (p.held(B.LB)) {
      if (!padWheel) { padWheel = true; openWheel(); }
      // either stick picks a slot (screen space: right = +x, down = +y)
      const sx = Math.abs(p.lx) + Math.abs(p.ly) > 0.3 ? p.lx : p.mx, sy = Math.abs(p.lx) + Math.abs(p.ly) > 0.3 ? p.ly : -p.mz;
      wheel.point(sx, sy, true);
    } else if (padWheel) { padWheel = false; wheel.close(true); }
  } else if (state === 'comic') comicPad(p);
  else menu.pad(p, dt);
  return p;
}
function frame(dtRaw, render = true) {
  const p = readPad(Math.min(dtRaw, 0.1));
  timeScale = damp(timeScale, wheel.open ? 0.25 : 1, 12, Math.min(dtRaw, 0.1));
  // hit-stop: the game freezes for a few hundredths of a second when something big lands
  const stopped = hitStop > 0; hitStop = Math.max(0, hitStop - Math.min(dtRaw, 0.1));
  const dt = Math.min(dtRaw, 1 / 30) * timeScale * (stopped ? 0.06 : 1);
  simTime += dt;
  const playing = state === 'playing';
  if (playing) {
    updatePlayer(dt, padWheel ? { ...p, lx: 0, ly: 0, mx: 0, mz: 0 } : p);
    updateWaves(dt); updateCalls(dt);
    if (mode === 'story') story.update(dt);
  } else {
    input.jumpPressed = input.dashPressed = input.meleePressed = false; input.look.dx = input.look.dy = 0;
    if (state === 'title') player.yaw += dt * 0.08; // slow orbit behind the title card
  }
  const onTarget = updateCamera(dt);
  if (state !== 'paused') {
    const wantFire = !wheel.open && (input.fire || (p && p.fire) || (touch && settings.autoFire && onTarget));
    if (arsenal.update(dt, { wantFire, aimPoint, aimDir, canFire: playing })) stats.shots++;
    player.aimHold = wantFire && playing ? 0.9 : player.aimHold - dt;
    player.landT = Math.max(0, player.landT - dt * 4);
    enemies.update(dt, ctx);
    boss.update(dt, bossCtx);
    dodger.update(dt);
    range.update(dt, { heroPos: player.pos, active: mode === 'range' && playing, onCall: callBots });
    updatePickups(dt);
    drone.update(dt, player.pos, player.yaw, liveTargets().filter(t => t.type !== 'dummy'), e => { deal(e, 0.75, centerOf(e), arsenal.current.id); fx.sparks(centerOf(e), 0x8ffcff, 6, 3); sfx.zap(); });
    fx.update(dt);
  }

  // hero pose: turn the body so the shouldered blaster lines up with whatever is under the crosshair
  hero.root.position.copy(player.pos);
  // shooting: turn so the shouldered blaster lines up with the crosshair (strafing). Otherwise face where you run.
  const ad = aimPoint.clone().sub(player.pos), aDist = Math.hypot(ad.x, ad.z);
  const aiming = player.aimHold > 0 || player.hull <= 0;
  const hsp = Math.hypot(player.vel.x, player.vel.z);
  let targetYaw = player.faceYaw;
  if (aiming) targetYaw = aDist > 0.8 ? Math.atan2(ad.x, ad.z) - Math.asin(clamp(hero.gunSide / aDist, -0.6, 0.6)) : player.yaw;
  else if (hsp > 0.8) targetYaw = Math.atan2(player.vel.x, player.vel.z);
  const gunPitch = aiming ? Math.atan2(aimPoint.y - (player.pos.y + 1.2), Math.max(aDist, 0.5)) : -0.45;
  const prevFace = player.faceYaw;
  player.faceYaw += angleDiff(player.faceYaw, targetYaw) * (1 - Math.exp(-(aiming ? 20 : 13) * dt));
  player.turnRate = damp(player.turnRate, dt > 0 ? angleDiff(prevFace, player.faceYaw) / dt : 0, 10, dt);
  hero.root.rotation.y = player.faceYaw;
  hero.root.visible = !(player.invuln > 0 && player.hull > 0 && Math.floor(simTime * 20) % 2 === 0 && player.dashT <= 0);
  if (player.hull <= 0) { hero.root.rotation.x = damp(hero.root.rotation.x, -1.4, 4, dt); }
  else hero.root.rotation.x = 0;
  const w = arsenal.current;
  hero.animate(dt, {
    speed: rails.riding ? 0 : Math.hypot(player.vel.x, player.vel.z), grounded: player.grounded, vy: player.vel.y,
    aimPitch: gunPitch, heat: w.hot, turn: aiming ? 0 : player.turnRate, landT: player.landT, aiming, dash: player.dashT > 0 || player.longJump, jetting: player.jetT > 0 || (!player.grounded && player.jumps === 2 && player.vel.y > -3),
  });

  world.update(dt, player.pos);
  hud.weapon(arsenal.state, arsenal.index);
  const left = enemies.list.length + waveState.toSpawn.length, out = enemies.list.length;
  hud.frame(dt, {
    camera, onTarget, targets: liveTargets(),
    waveText: mode === 'story' ? 'SKYHARBOR' : mode === 'range' ? 'TEST RANGE' : stats.wave ? `WAVE ${stats.wave}` : '',
    leftText: mode === 'story' ? story.goal : mode === 'range' ? (out ? `${out} bot${out === 1 ? '' : 's'} out` : '') : stats.wave && waveState.clearT < 0 ? `${left} bot${left === 1 ? '' : 's'} left` : '',
  });
  if (wheel.open) wheel.refresh(arsenal.state, arsenal.index);
  if (touch) { touch.setDash(Math.max(0, player.dashCd) / 0.75); touch.setWeapon(ICONS[w.id], w.color); }
  if (render) composer.render();
}
let autoLoop = true;
function loop(ts) {
  timer.update(ts);
  if (autoLoop) frame(timer.getDelta());
  requestAnimationFrame(loop);
}
reset();
menu.show('title');
loop();
// title music starts with the first tap, click or key press (browsers block sound before that)
for (const ev of ['pointerdown', 'keydown']) addEventListener(ev, () => { music.start(); if (state !== 'playing') music.intensity = 0.3; }, { once: true });

// hooks for automated play tests
window.__game = {
  get state() { return state; }, get mode() { return mode; }, aimPoint, player, stats, enemies, keys, input, hero, arsenal, range, wheel, hits, menu,
  merged: world.merged, info() { renderer.info.autoReset = false; renderer.info.reset(); composer.render(); const r = { calls: renderer.info.render.calls, tris: renderer.info.render.triangles }; renderer.info.autoReset = true; return r; },
  begin(m) { if (m) { mode = m; reset(); } begin(); }, reset, frame, render: () => composer.render(), set autoLoop(v) { autoLoop = v; },
  look(yaw, pitch) { player.yaw = yaw; player.pitch = pitch; },
  selectWeapon, callBots, openWheel, audioState, story, rails, boss, dodger, gizmarts, world, extraTargets, buy, openShop,
  aimAt(p) { const d = p.clone().sub(camPivot); player.yaw = Math.atan2(d.x, d.z); player.pitch = Math.atan2(d.y, Math.hypot(d.x, d.z)); },
  aimAtNearest() {
    const e = enemies.list.find(x => !x.dead); if (!e) return false;
    const d = centerOf(e).sub(camPivot);
    player.yaw = Math.atan2(d.x, d.z); player.pitch = Math.atan2(d.y, Math.hypot(d.x, d.z));
    return true;
  },
};

// offline / home-screen support (only in the built game, so the dev server always serves fresh code)
if (import.meta.env.PROD && 'serviceWorker' in navigator) {
  addEventListener('load', () => navigator.serviceWorker.register('./sw.js').catch(() => {}));
}
