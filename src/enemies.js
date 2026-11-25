// Enemies: Rivet Hornets (flying gunships that strafe and shoot) and Scrap Rollers (spiked balls that
// roll at the hero and pop). Both are original designs built from basic shapes.
import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { V, std, glow, mesh, glowSprite, rand, clamp, UP } from './util.js';
import { ARENA, onDeck } from './world.js';
import { ownMaterials, mergeByMaterial } from './models.js';

const shellMat = std(0x2d333d, 0.85, 0.32);
const accentMat = std(0x9b1f2a, 0.5, 0.4);
const rollerMat = std(0x6a5a48, 0.8, 0.35);
const metalDark = std(0x34404c, 0.75, 0.4);
export const debrisMats = [shellMat, accentMat];

function makeHornet() {
  const g = new THREE.Group();
  const inner = new THREE.Group(); g.add(inner);
  const b = mesh(new THREE.SphereGeometry(0.6, 32, 20), shellMat.clone()); b.scale.set(1, 0.75, 1.1); inner.add(b);
  const jaw = mesh(new THREE.SphereGeometry(0.45, 24, 12, 0, Math.PI * 2, Math.PI / 2, Math.PI / 2), accentMat.clone()); jaw.position.set(0, -0.15, 0.15); inner.add(jaw);
  const eyeMat = glow(0xff2a2a, 6);
  const eye = mesh(new RoundedBoxGeometry(0.5, 0.1, 0.1, 2, 0.04), eyeMat, false, false); eye.position.set(0, 0.06, 0.62); inner.add(eye);
  const eg = glowSprite(0xff3030, 1.4, 0.8, true); eg.position.set(0, 0.06, 0.7); inner.add(eg);
  const thrusters = [];
  for (const sx of [-1, 1]) {
    const wing = mesh(new RoundedBoxGeometry(1.1, 0.06, 0.5, 2, 0.02), shellMat, false, false); wing.position.set(0.85 * sx, 0, -0.1); wing.rotation.z = 0.3 * sx; inner.add(wing);
    const gun = mesh(new THREE.CylinderGeometry(0.06, 0.06, 0.7, 10), metalDark, false, false); gun.rotation.x = Math.PI / 2; gun.position.set(0.55 * sx, -0.2, 0.4); inner.add(gun);
    const thr = glowSprite(0xff7030, 0.8, 0.8, true); thr.position.set(0.85 * sx, -0.25, -0.2); inner.add(thr); thrusters.push(thr);
  }
  for (let i = 0; i < 5; i++) { const sp = mesh(new THREE.ConeGeometry(0.06, 0.35, 8), accentMat, false, false); const a = (i / 4 - 0.5) * 1.6; sp.position.set(Math.sin(a) * 0.4, 0.48, -0.05 + Math.cos(a) * -0.1); sp.rotation.set(-0.4, 0, -a * 0.6); inner.add(sp); }
  g.traverse(o => { if (o.isMesh) o.castShadow = true; });
  return { g, inner, eyeMat, eg, thrusters, hitMats: [b.material, jaw.material] };
}

function makeRoller() {
  const g = new THREE.Group();
  const ball = new THREE.Group(); ball.position.y = 0.55; g.add(ball);
  const core = mesh(new THREE.IcosahedronGeometry(0.5, 1), rollerMat.clone()); core.material.flatShading = true; ball.add(core);
  const studGeo = new THREE.ConeGeometry(0.09, 0.32, 6);
  const ico = new THREE.IcosahedronGeometry(0.5, 0).attributes.position;
  const seen = new Set();
  for (let i = 0; i < ico.count; i++) {
    const p = V(ico.getX(i), ico.getY(i), ico.getZ(i)); const key = p.toArray().map(v => v.toFixed(2)).join();
    if (seen.has(key)) continue; seen.add(key);
    const st = mesh(studGeo, metalDark); st.position.copy(p.clone().multiplyScalar(1.05)); st.quaternion.setFromUnitVectors(UP, p.clone().normalize()); ball.add(st);
  }
  const band = mesh(new THREE.TorusGeometry(0.52, 0.05, 8, 32), accentMat); ball.add(band);
  // the eye sits on an unrotating cap so it always looks where it is going
  const cap = new THREE.Group(); cap.position.y = 0.55; g.add(cap);
  const eyeMat = glow(0xff2a2a, 5);
  const visor = mesh(new THREE.TorusGeometry(0.56, 0.06, 8, 24, Math.PI * 0.5), eyeMat, false, false); visor.rotation.set(-Math.PI / 2, Math.PI * 1.25, 0, 'YXZ'); cap.add(visor);
  const eg = glowSprite(0xff3030, 1.0, 0.7, true); eg.position.set(0, 0.05, 0.6); cap.add(eg);
  g.traverse(o => { if (o.isMesh) o.castShadow = true; });
  return { g, ball, cap, eyeMat, eg, hitMats: [core.material] };
}

// Blender versions (art/bots.py). Each bot gets its own copies of the materials that flash or glow.
function hornetFromModel(tpl) {
  const g = new THREE.Group(); const m = tpl.clone(true); g.add(m);
  const mats = ownMaterials(m, ['hornet_shell', 'hornet_accent', 'hornet_eye']);
  const eg = glowSprite(0xff3030, 1.4, 0.8, true); m.getObjectByName('hornet_eye_point').add(eg);
  const thrusters = ['hornet_jet_L', 'hornet_jet_R'].map(n => { const t = glowSprite(0xff7030, 0.8, 0.8, true); m.getObjectByName(n).add(t); return t; });
  return { g, inner: m.getObjectByName('inner'), eyeMat: mats.get('hornet_eye'), eg, thrusters, hitMats: [mats.get('hornet_shell'), mats.get('hornet_accent')] };
}
function rollerFromModel(tpl) {
  const g = new THREE.Group(); const m = tpl.clone(true); g.add(m);
  const mats = ownMaterials(m, ['roller_core', 'roller_plate', 'roller_eye']);
  const eg = glowSprite(0xff3030, 0.6, 0.6, true); m.getObjectByName('roller_eye').add(eg);
  return { g, ball: m.getObjectByName('ball'), cap: m.getObjectByName('cap'), eyeMat: mats.get('roller_eye'), eg, hitMats: [mats.get('roller_core'), mats.get('roller_plate')] };
}

export function createEnemies(scene, fx, models = {}) {
  if (models.hornet) mergeByMaterial(models.hornet);
  if (models.roller) mergeByMaterial(models.roller);
  const makeH = () => (models.hornet ? hornetFromModel(models.hornet) : makeHornet());
  const makeR = () => (models.roller ? rollerFromModel(models.roller) : makeRoller());
  const list = [];
  const chunkMats = {};
  const shots = [];
  const shotGeo = new THREE.CapsuleGeometry(0.07, 0.6, 4, 8);
  const shotMat = glow(0xff3a2a, 12);

  // opts.zone keeps a roller on its island; opts.y is the floor height it lands on
  function spawn(type, x, z, opts = {}) {
    const e = { type, dead: false, t: 0, flash: 0, vel: V(0, 0, 0), spawnT: 1.0, zone: opts.zone || null, tag: opts.tag };
    if (type === 'hornet') {
      Object.assign(e, makeH(), { hp: 4, maxHp: 4, radius: 0.85, fireT: rand(1.5, 2.8), charge: 0, orbitA: rand(0, Math.PI * 2), orbitR: rand(8, 12), height: rand(3, 5.5), nuts: 8 });
      e.pos = V(x, 14, z);
    } else {
      Object.assign(e, makeR(), { hp: 2, maxHp: 2, radius: 0.6, fuse: -1, nuts: 4, hop: 0, vy: 0 });
      e.pos = V(x, 10, z);
    }
    e.g.position.copy(e.pos);
    scene.add(e.g);
    fx.ring(V(x, 0.05, z), 0xff5040);
    list.push(e);
    return e;
  }

  function kill(e, ctx) {
    if (e.dead) return;
    e.dead = true;
    scene.remove(e.g);
    const at = e.pos.clone().add(V(0, e.type === 'roller' ? 0.55 : 0, 0));
    if (!chunkMats[e.type]) chunkMats[e.type] = [...e.hitMats.map(m => { const c = m.clone(); c.emissive?.setRGB(0, 0, 0); return c; }), ...debrisMats];
    fx.explosion(at, e.type === 'hornet' ? 1.15 : 0.95, chunkMats[e.type]);
    fx.shock(at, e.type === 'hornet' ? 0xffb040 : 0xff7040);
    ctx.onKill(e);
  }

  function damage(e, amount, hitPos, ctx) {
    if (e.dead) return;
    e.hp -= amount; e.flash = 1; e.pop = 1;
    // knock the bot back from the hit
    const push = hitPos ? e.pos.clone().sub(hitPos).setY(0) : V(rand(-1, 1), 0, rand(-1, 1));
    if (push.lengthSq() > 1e-4) push.normalize();
    const k = Math.min(2.5, 0.8 + amount * 0.6);
    if (e.type === 'hornet') e.vel.add(push.multiplyScalar(k * 2.2).add(V(rand(-1, 1), rand(0.5, 2), rand(-1, 1))));
    else if (e.fuse < 0) { e.vel.addScaledVector(push, k * 2.6); e.stun = 0.18; }
    if (e.hp <= 0) kill(e, ctx);
  }

  // closest enemy hit along a segment (for bolts)
  const tmp = V(0, 0, 0), ab = V(0, 0, 0);
  function center(e) { return tmp.copy(e.pos).add(V(0, e.type === 'roller' ? 0.55 : 0, 0)); }
  function segmentHit(a, b, pad = 0.15) {
    ab.subVectors(b, a); const len2 = ab.lengthSq();
    let best = null, bestT = Infinity;
    for (const e of list) {
      if (e.dead) continue;
      const c = center(e);
      const t = clamp(c.clone().sub(a).dot(ab) / len2, 0, 1);
      const d = a.clone().addScaledVector(ab, t).distanceTo(c);
      if (d < e.radius + pad && t < bestT) { bestT = t; best = e; }
    }
    return best ? { enemy: best, point: a.clone().addScaledVector(ab, bestT) } : null;
  }

  function fireShot(from, target) {
    const dir = target.clone().sub(from).normalize();
    const m = mesh(shotGeo, shotMat, false, false); m.position.copy(from); m.quaternion.setFromUnitVectors(UP, dir);
    const halo = glowSprite(0xff4030, 0.9, 0.7); m.add(halo);
    scene.add(m);
    shots.push({ m, vel: dir.multiplyScalar(17), life: 3 });
  }

  function update(dt, ctx) {
    const hp = ctx.heroPos;
    const heroCenter = hp.clone().add(V(0, 0.9, 0));
    for (const e of list) {
      if (e.dead) continue;
      e.t += dt;
      e.flash = Math.max(0, e.flash - dt * 8);
      e.pop = Math.max(0, (e.pop || 0) - dt * 7); e.stun = Math.max(0, (e.stun || 0) - dt);
      if (e.fuse < 0 || e.type === 'hornet') e.g.scale.setScalar(1 + e.pop * 0.22);
      e.hitMats.forEach(m => { m.emissive.setRGB(e.flash, e.flash, e.flash); m.emissiveIntensity = 2; });
      if (e.type === 'hornet') {
        // orbit the hero, slowly drifting around them
        e.orbitA += dt * 0.35;
        const want = V(hp.x + Math.cos(e.orbitA) * e.orbitR, (ctx.groundY || 0) + e.height + Math.sin(e.t * 1.3) * 0.5, hp.z + Math.sin(e.orbitA) * e.orbitR);
        want.x = clamp(want.x, ARENA.minX - 4, ARENA.maxX + 4); want.z = clamp(want.z, ARENA.minZ - 4, ARENA.maxZ + 4);
        const steer = want.sub(e.pos).multiplyScalar(e.spawnT > 0 ? 3 : 1.4);
        // keep some personal space so they never fly into the camera
        const away = e.pos.clone().sub(heroCenter); const ad = away.length();
        if (ad < 6) steer.addScaledVector(away.normalize(), (6 - ad) * 4);
        e.vel.lerp(steer, 1 - Math.exp(-2 * dt));
        e.pos.addScaledVector(e.vel, dt);
        e.spawnT -= dt;
        e.g.position.copy(e.pos);
        e.g.lookAt(heroCenter);
        e.inner.rotation.z = clamp(-e.vel.x * 0.05, -0.5, 0.5) + Math.sin(e.t * 2) * 0.08;
        // attack: charge the eye, then fire
        e.fireT -= dt;
        if (e.fireT < 0.7 && e.fireT > 0) { if (e.charge === 0) ctx.sound?.('enemyCharge', e.pos); e.charge = 1 - e.fireT / 0.7; } else e.charge = 0;
        e.eyeMat.emissiveIntensity = 6 + e.charge * 14;
        e.eg.scale.setScalar(1.4 + e.charge * 1.6);
        if (e.fireT <= 0 && ctx.alive) {
          e.fireT = rand(2.2, 3.4) / ctx.aggression;
          const lead = heroCenter.clone().addScaledVector(ctx.heroVel, 0.35 * Math.random());
          const muzzle = e.pos.clone().add(lead.clone().sub(e.pos).normalize().multiplyScalar(0.9));
          fireShot(muzzle, lead); ctx.sound?.('enemyShot', e.pos);
        }
        e.thrusters.forEach(t => t.scale.setScalar(0.6 + Math.random() * 0.4));
      } else {
        // fall in, then roll at the hero
        if (e.pos.y > 0) { e.vy -= 25 * dt; e.pos.y = Math.max(0, e.pos.y + e.vy * dt); if (e.pos.y === 0) { fx.puff(e.pos.clone().add(V(0, 0.1, 0)), 0xffb0a0); e.vy = 0; } }
        const to = V(hp.x - e.pos.x, 0, hp.z - e.pos.z); const dist = to.length();
        if (e.fuse < 0) {
          const speed = 4.2 * ctx.aggression;
          if (e.pos.y === 0 && e.stun <= 0) e.vel.lerp(to.normalize().multiplyScalar(speed), 1 - Math.exp(-2.5 * dt));
          if (dist < 1.4 && e.pos.y === 0) e.fuse = 0.55;
        } else {
          e.vel.multiplyScalar(Math.exp(-6 * dt));
          e.fuse -= dt;
          e.eyeMat.emissiveIntensity = 5 + (Math.sin(e.t * 50) > 0 ? 18 : 0);
          ctx.sound?.('fuse', e.pos);
          e.g.scale.setScalar(1 + (0.55 - e.fuse) * 0.4);
          if (e.fuse <= 0) {
            const d = V(hp.x - e.pos.x, 0, hp.z - e.pos.z).length();
            if (d < 2.2) ctx.hurtHero(1, e.pos);
            e.selfDestruct = true;
            kill(e, ctx);
            continue;
          }
        }
        e.pos.addScaledVector(e.vel, dt);
        // stay on the deck and out of solid props
        const Z = e.zone || ARENA;
        e.pos.x = clamp(e.pos.x, Z.minX + 0.5, Z.maxX - 0.5); e.pos.z = clamp(e.pos.z, Z.minZ + 0.5, Z.maxZ - 0.5);
        for (const c of ctx.colliders) pushOut(e.pos, 0.55, c);
        // separate from other rollers
        for (const o of list) if (o !== e && !o.dead && o.type === 'roller') { const d = e.pos.distanceTo(o.pos); if (d < 1.1 && d > 0.001) e.pos.add(e.pos.clone().sub(o.pos).multiplyScalar((1.1 - d) * 0.5 / d)); }
        e.g.position.copy(e.pos);
        const sp = Math.hypot(e.vel.x, e.vel.z);
        if (sp > 0.05) {
          const axis = V(e.vel.z, 0, -e.vel.x).normalize();
          e.ball.quaternion.premultiply(new THREE.Quaternion().setFromAxisAngle(axis, sp * dt / 0.55));
          e.cap.rotation.y = Math.atan2(e.vel.x, e.vel.z);
        }
      }
    }
    for (let i = list.length - 1; i >= 0; i--) if (list[i].dead) list.splice(i, 1);

    // enemy shots
    for (let i = shots.length - 1; i >= 0; i--) {
      const s = shots[i];
      const prev = s.m.position.clone();
      s.m.position.addScaledVector(s.vel, dt); s.life -= dt;
      let hit = false;
      // hero
      if (ctx.alive) {
        const ab2 = s.m.position.clone().sub(prev);
        const t = clamp(heroCenter.clone().sub(prev).dot(ab2) / ab2.lengthSq(), 0, 1);
        if (prev.clone().addScaledVector(ab2, t).distanceTo(heroCenter) < 0.6) { ctx.hurtHero(1, s.m.position); hit = true; }
      }
      // deck and props
      const p = s.m.position;
      if (!hit && p.y < 0 && onDeck(p.x, p.z)) hit = true;
      if (!hit) for (const c of ctx.colliders) if (p.x > c.min.x && p.x < c.max.x && p.y > c.min.y && p.y < c.max.y && p.z > c.min.z && p.z < c.max.z) { hit = true; break; }
      if (hit || s.life <= 0) {
        if (hit) fx.sparks(p.clone(), 0xff6040, 8, 4);
        scene.remove(s.m); shots.splice(i, 1);
      }
    }
  }

  function clear() {
    list.forEach(e => scene.remove(e.g)); list.length = 0;
    shots.forEach(s => scene.remove(s.m)); shots.length = 0;
  }

  return { list, spawn, damage, kill, segmentHit, update, clear, fireShot };
}

// push a point (on the floor plane, with radius r) out of a box
export function pushOut(p, r, c) {
  if (p.y >= c.max.y - 0.05 || p.y + 1.6 < c.min.y) return false;
  const cx = clamp(p.x, c.min.x, c.max.x), cz = clamp(p.z, c.min.z, c.max.z);
  const dx = p.x - cx, dz = p.z - cz, d2 = dx * dx + dz * dz;
  if (d2 >= r * r) return false;
  if (d2 > 1e-6) { const d = Math.sqrt(d2); p.x = cx + dx / d * r; p.z = cz + dz / d * r; return true; }
  // centre inside the box: push out along the shallowest side
  const opts = [[c.min.x - r - p.x, 0], [c.max.x + r - p.x, 0], [0, c.min.z - r - p.z], [0, c.max.z + r - p.z]];
  opts.sort((a, b) => Math.abs(a[0] + a[1]) - Math.abs(b[0] + b[1]));
  p.x += opts[0][0]; p.z += opts[0][1]; return true;
}
