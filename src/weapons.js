// The hero's four blasters, their projectiles and their upgrades.
//   Arc Lancer    rapid energy bolts; never runs dry but overheats if held too long
//   Scatter Bloom close-range burst of petal pellets
//   Thump Lobber  bouncing bombs that blast everything nearby
//   Seeker Hive   volleys of mini-rockets that home in on the bot under (or near) the crosshair
// Every weapon levels up V1-V5 from the bots it wrecks: more damage and faster fire.
import * as THREE from 'three';
import { V, UP, glow, mesh, glowSprite, rand, clamp } from './util.js';
import { onDeck } from './world.js';
import { mergeByMaterial } from './models.js';
import { sfx } from './audio.js';

export const LEVELS = [0, 120, 300, 560, 900]; // xp needed for V1..V5

export const WEAPONS = [
  { id: 'lancer', name: 'ARC LANCER', color: '#5ff2ff', hex: 0x5ff2ff, max: 60, regen: true, interval: 0.13, dmg: 1,
    blurb: 'Rapid bolts. Overheats if you hold it too long.' },
  { id: 'scatter', name: 'SCATTER BLOOM', color: '#ff6ab0', hex: 0xff6ab0, max: 24, interval: 0.75, dmg: 0.55, pellets: 9,
    blurb: 'A close-range burst of petals.' },
  { id: 'lobber', name: 'THUMP LOBBER', color: '#9dff5a', hex: 0x9dff5a, max: 12, interval: 0.85, dmg: 5, radius: 3.3,
    blurb: 'Bouncing bombs that blast a whole area.' },
  { id: 'seeker', name: 'SEEKER HIVE', color: '#ffd040', hex: 0xffd040, max: 40, interval: 1.0, dmg: 1.3, volley: 4,
    blurb: 'Homing rockets. Point near a bot and fire.' },
];

// small HUD icons (60x60 viewBox), shared by the weapon panel and the weapon wheel
export const ICONS = {
  lancer: '<path d="M6 34h30l6-6h10v8h-6l-4 4H20l-4 8H8l3-8H6z" fill="currentColor"/><path d="M22 24h18" stroke="currentColor" stroke-width="3"/>',
  scatter: '<path d="M6 32h24l4-6h8v14h-8l-4-4H16l-3 8H6l3-8H6z" fill="currentColor"/><circle cx="48" cy="22" r="3" fill="currentColor"/><circle cx="54" cy="33" r="3" fill="currentColor"/><circle cx="48" cy="44" r="3" fill="currentColor"/>',
  lobber: '<path d="M6 36h18v-8h14l8-4 4 8-6 6v8H24l-4 6H10l3-6H6z" fill="currentColor"/><circle cx="50" cy="14" r="6" fill="currentColor"/>',
  seeker: '<path d="M6 36h16l2-10h22v18H24l-2-2h-4l-3 8H8l3-8H6z" fill="currentColor"/><path d="M50 22l8-4M50 30h9M50 38l8 4" stroke="currentColor" stroke-width="3"/>',
};

export function createArsenal({ scene, fx, hero, models, colliders, floorAt, hits, deal, onEmpty, onLevel }) {
  const near = p => 1 / (1 + p.distanceTo(hero.root.position) / 14); // quieter when far away
  // ---- weapon models in the hero's hands ----
  const lancerMeshes = hero.gun.children.filter(c => c.isMesh);
  const held = { lancer: { meshes: lancerMeshes, muzzle: hero.muzzle } };
  for (const w of WEAPONS.slice(1)) {
    const m = models['wpn_' + w.id];
    if (m) {
      mergeByMaterial(m);
      hero.gun.add(m); m.visible = false;
      held[w.id] = { group: m, muzzle: m.getObjectByName('muzzle_' + w.id) || hero.muzzle };
    } else held[w.id] = { muzzle: hero.muzzle }; // no model: keep showing the lancer
  }
  // the muzzle flash rides on whichever muzzle is active
  const flashParts = hero.muzzle.children.slice();

  const state = WEAPONS.map(w => ({ ...w, ammo: w.max, level: 1, xp: 0, cool: 0, hot: false, sinceShot: 9 }));
  let cur = 0, infinite = false;
  const projectiles = [];
  const burst = []; // queued seeker launches

  function select(i) {
    if (i === cur || i < 0 || i >= state.length) return false;
    cur = i;
    const id = state[i].id;
    held.lancer.meshes.forEach(m => { m.visible = id === 'lancer' || !held[id].group; });
    for (const w of WEAPONS.slice(1)) if (held[w.id].group) held[w.id].group.visible = w.id === id;
    const mz = held[id].muzzle; flashParts.forEach(p => mz.add(p));
    state[i].cool = Math.max(state[i].cool, 0.25);
    return true;
  }

  // ---- projectile assets ----
  const boltGeo = new THREE.CapsuleGeometry(0.05, 0.9, 4, 10), boltMat = glow(0x9ffcff, 10);
  const pelletGeo = new THREE.SphereGeometry(0.07, 8, 6), pelletMat = glow(0xff8ac4, 8);
  const bombGeo = new THREE.SphereGeometry(0.16, 16, 12), bombMat = glow(0x9dff5a, 5);
  const rocketGeo = new THREE.CapsuleGeometry(0.06, 0.28, 4, 8), rocketMat = glow(0xffe08a, 7);

  const dmgMul = w => 1 + (w.level - 1) * 0.35;
  const interval = w => w.interval * Math.pow(0.9, w.level - 1);

  function spawn(kind, geo, mat, pos, vel, extra = {}) {
    const m = mesh(geo, mat, false, false); m.position.copy(pos);
    if (vel.lengthSq() > 0) m.quaternion.setFromUnitVectors(UP, vel.clone().normalize());
    scene.add(m);
    const p = { kind, m, vel, life: 2, ...extra };
    projectiles.push(p); return p;
  }

  function fire(w, muzzle, aimPoint, aimDir) {
    let dir = aimPoint.clone().sub(muzzle).normalize();
    if (dir.dot(aimDir) < 0.3) dir.copy(aimDir); // never shoot back into the camera when the target is very close
    const d = dmgMul(w) * w.dmg;
    if (w.id === 'lancer') {
      dir.add(V(rand(-1, 1), rand(-1, 1), rand(-1, 1)).multiplyScalar(0.008)).normalize();
      const p = spawn('bolt', boltGeo, boltMat, muzzle, dir.multiplyScalar(75), { life: 1.6, dmg: d, wid: w.id });
      p.m.add(glowSprite(0x40e8ff, 0.8, 0.75));
    } else if (w.id === 'scatter') {
      const side = new THREE.Vector3().crossVectors(dir, UP).normalize(), up = new THREE.Vector3().crossVectors(side, dir);
      for (let i = 0; i < w.pellets; i++) {
        const a = (i / w.pellets) * Math.PI * 2 + rand(-0.3, 0.3), r = i === 0 ? 0 : rand(0.03, 0.085);
        const pd = dir.clone().addScaledVector(side, Math.cos(a) * r).addScaledVector(up, Math.sin(a) * r).normalize();
        const p = spawn('pellet', pelletGeo, pelletMat, muzzle, pd.multiplyScalar(rand(52, 60)), { life: 0.4, dmg: d, wid: w.id });
        p.m.add(glowSprite(0xff6ab0, 0.45, 0.8));
      }
      fx.sparks(muzzle.clone(), 0xff8ac4, 8, 4);
    } else if (w.id === 'lobber') {
      // arc the bomb so it lands on the aim point (or flies flat-ish toward far aim points)
      const to = aimPoint.clone().sub(muzzle); const flat = Math.hypot(to.x, to.z);
      const T = clamp(flat / 17, 0.35, 1.15), g = 22;
      const vel = new THREE.Vector3(to.x / T, (to.y + 0.5 * g * T * T) / T, to.z / T);
      if (flat > 26) vel.copy(dir).multiplyScalar(24).add(V(0, 5, 0));
      const p = spawn('bomb', bombGeo, bombMat, muzzle, vel, { life: 2.4, dmg: d, wid: w.id, bounces: 0, radius: w.radius });
      p.m.add(glowSprite(0x9dff5a, 0.9, 0.8));
    } else if (w.id === 'seeker') {
      const target = hits.lock(muzzle, aimDir, aimPoint);
      for (let i = 0; i < w.volley; i++) burst.push({ t: i * 0.07, target, dmg: d, wid: w.id, i });
    }
  }

  function launchRocket(b, aimPoint, aimDir) {
    const muzzle = held.seeker.muzzle.getWorldPosition(V(0, 0, 0));
    const spread = V(Math.cos(b.i * 1.7), Math.sin(b.i * 1.7) * 0.6 + 0.4, 0).multiplyScalar(0.35);
    const dir = aimDir.clone().add(spread).normalize();
    const p = spawn('rocket', rocketGeo, rocketMat, muzzle, dir.multiplyScalar(14), { life: 3, dmg: b.dmg, wid: b.wid, target: b.target, goal: aimPoint.clone(), age: 0 });
    p.m.add(glowSprite(0xffb040, 0.6, 0.9));
    hero.fireFlash(); sfx.rocket();
  }

  function explode(pos, p) {
    fx.explosion(pos, 0.9); sfx.explosion(near(pos), 1);
    fx.ring(pos.clone().setY(Math.max(0.05, pos.y)), 0x9dff5a);
    for (const { t, c } of hits.inRadius(pos, p.radius)) {
      const k = 1 - 0.5 * clamp(c.distanceTo(pos) / p.radius, 0, 1);
      deal(t, p.dmg * k, c.clone(), p.wid);
    }
    hits.onBlast?.(pos);
  }

  function solid(p) {
    if (p.y < 0 && onDeck(p.x, p.z)) return true;
    for (const c of colliders) if (p.x > c.min.x && p.x < c.max.x && p.y > c.min.y && p.y < c.max.y && p.z > c.min.z && p.z < c.max.z) return true;
    return false;
  }

  function update(dt, { wantFire, aimPoint, aimDir, canFire }) {
    // ammo: the lancer recharges (and overheats); the others refill slowly while holstered
    for (const w of state) {
      w.cool -= dt; w.sinceShot += dt;
      if (w.regen) {
        if (w.hot) { w.ammo += 26 * dt; if (w.ammo >= w.max * 0.5) w.hot = false; }
        else if (w.sinceShot > 0.45) w.ammo += 22 * dt;
      } else if (infinite) w.ammo = w.max;
      else if (state[cur] !== w || w.sinceShot > 3) w.ammo += dt * w.max / 60; // full refill in a minute
      w.ammo = Math.min(w.max, w.ammo);
    }
    const w = state[cur];
    let fired = false;
    if (wantFire && canFire && w.cool <= 0 && !w.hot) {
      if (w.ammo >= 1) {
        fire(w, held[w.id].muzzle.getWorldPosition(V(0, 0, 0)), aimPoint, aimDir);
        if (!infinite || w.regen) w.ammo -= 1;
        w.cool = interval(w); w.sinceShot = 0; fired = true;
        if (w.id !== 'seeker') { hero.fireFlash(); sfx[w.id](); }
        if (w.regen && w.ammo <= 0) { w.ammo = 0; w.hot = true; onEmpty?.(w, true); }
      } else if (w.cool <= 0) { w.cool = 0.4; onEmpty?.(w, false); }
    }
    for (let i = burst.length - 1; i >= 0; i--) { burst[i].t -= dt; if (burst[i].t <= 0) { launchRocket(burst[i], aimPoint, aimDir); burst.splice(i, 1); } }

    for (let i = projectiles.length - 1; i >= 0; i--) {
      const p = projectiles[i];
      const a = p.m.position.clone();
      let done = false;
      if (p.kind === 'bomb') p.vel.y -= 22 * dt;
      if (p.kind === 'rocket') {
        p.age += dt;
        const tgt = p.target && !p.target.dead ? hits.center(p.target) : p.goal;
        const want = tgt.clone().sub(a).normalize();
        const turn = p.age < 0.15 ? 0 : 7;
        const v = p.vel.clone().normalize().lerp(want, 1 - Math.exp(-turn * dt)).normalize();
        p.vel.copy(v.multiplyScalar(Math.min(38, p.vel.length() + 60 * dt)));
        p.m.quaternion.setFromUnitVectors(UP, v.clone().normalize());
        if (Math.random() < 0.7) fx.smokeTrail(a.clone());
        if (!p.target && a.distanceTo(p.goal) < 0.6) { done = true; fx.sparks(a, 0xffd040, 8, 4); }
      }
      const n = a.clone().addScaledVector(p.vel, dt);
      const hit = hits.segment(a, n, p.kind === 'bomb' ? 0.2 : p.kind === 'pellet' ? 0.12 : 0.15);
      if (hit && !done) {
        if (p.kind === 'bomb') explode(hit.point, p);
        else { deal(hit.t, p.dmg, hit.point, p.wid); fx.sparks(hit.point, p.kind === 'rocket' ? 0xffd040 : p.kind === 'pellet' ? 0xff8ac4 : 0xaefaff, p.kind === 'pellet' ? 4 : 8, 5); if (p.kind === 'rocket') { fx.explosion(hit.point, 0.35); sfx.explosion(near(hit.point) * 0.5, 0.5); } }
        done = true;
      } else if (!done) {
        p.m.position.copy(n);
        if (p.kind === 'bomb') {
          const f = floorAt(n) + 0.16;
          if (n.y < f && onDeck(n.x, n.z)) {
            p.m.position.y = f; p.vel.y = Math.abs(p.vel.y) * 0.45; p.vel.x *= 0.6; p.vel.z *= 0.6; p.bounces++;
            fx.puff(n.clone(), 0xc8ffb0); sfx.bounce(near(n));
            if (p.bounces >= 3) { explode(p.m.position.clone(), p); done = true; }
          } else if (solid(n)) { p.vel.x *= -0.5; p.vel.z *= -0.5; p.m.position.copy(a); }
          p.m.scale.setScalar(1 + Math.sin(p.life * 30) * 0.08);
          if (!done && p.life - dt <= 0) { explode(p.m.position.clone(), p); done = true; }
        } else if (solid(n)) {
          fx.sparks(n.clone(), p.kind === 'rocket' ? 0xffd040 : 0xaefaff, 6, 3);
          if (p.kind === 'rocket') { fx.explosion(n.clone(), 0.35); sfx.explosion(near(n) * 0.5, 0.5); }
          done = true;
        }
      }
      p.life -= dt;
      if (done || p.life <= 0 || n.y < -40) { scene.remove(p.m); projectiles.splice(i, 1); }
    }
    return fired;
  }

  function addXp(wid, n) {
    const w = state.find(x => x.id === wid); if (!w) return;
    w.xp += n;
    const next = LEVELS[w.level];
    if (next !== undefined && w.xp >= next) { w.level++; onLevel?.(w); }
  }

  function reset() {
    projectiles.forEach(p => scene.remove(p.m)); projectiles.length = 0; burst.length = 0;
    state.forEach(w => Object.assign(w, { ammo: w.max, level: 1, xp: 0, cool: 0, hot: false, sinceShot: 9 }));
    select(0);
  }

  return {
    state, select, update, addXp, reset,
    get current() { return state[cur]; }, get index() { return cur; },
    set infinite(v) { infinite = v; },
    refill(frac) { for (const w of state) if (!w.regen) w.ammo = Math.min(w.max, w.ammo + w.max * frac); },
  };
}
