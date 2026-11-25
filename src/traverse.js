// Getting around Skyharbor: moving platforms, bounce pads, swing hooks and nut crates you can smash.
import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { V, std, glow, mesh, glowSprite, clamp } from './util.js';

const HOOK_RANGE = 15, SWING_T = 1.05, RELEASE = 0.8;

export function createTraverse(group, data, { colliders, fx, sfx }) {
  const metal = std(0xbcd0dc, 0.7, 0.35), dark = std(0x34404c, 0.75, 0.4);

  // ---- moving platforms: a collider box that slides back and forth; whatever stands on it rides along ----
  const movers = data.movers.map(m => {
    const g = new THREE.Group(); group.add(g);
    g.add(mesh(new RoundedBoxGeometry(m.size[0], m.size[1], m.size[2], 2, 0.1), metal));
    const lip = mesh(new THREE.BoxGeometry(m.size[0] + 0.02, 0.05, m.size[2] + 0.02), glow(0x5ff2ff, 2.5), false, false); lip.position.y = m.size[1] / 2 - 0.04; g.add(lip);
    for (const s of [-1, 1]) { const jet = mesh(new THREE.CylinderGeometry(0.35, 0.5, 0.6, 12), dark); jet.position.set(s * m.size[0] * 0.3, -0.55, 0); g.add(jet); const fl = glowSprite(0x60e8ff, 1.2, 0.8); fl.position.set(s * m.size[0] * 0.3, -1, 0); g.add(fl); }
    g.traverse(o => { o.userData.dynamic = true; });
    const col = { min: V(0, 0, 0), max: V(0, 0, 0), mover: true };
    const half = V(m.size[0] / 2, m.size[1] / 2, m.size[2] / 2);
    return { ...m, g, col, half, pos: m.from.clone(), delta: V(0, 0, 0) };
  });
  // ---- bounce pads ----
  const bouncers = data.bouncers.map(b => {
    const g = new THREE.Group(); g.position.copy(b.pos); group.add(g);
    g.add(mesh(new THREE.CylinderGeometry(1.1, 1.25, 0.25, 24), dark));
    const top = mesh(new THREE.CylinderGeometry(0.95, 0.95, 0.1, 24), glow(0x7dff9a, 2.5), false, false); top.position.y = 0.17; g.add(top);
    const ring = mesh(new THREE.TorusGeometry(1.0, 0.06, 8, 32), glow(0xffffff, 3), false, false); ring.rotation.x = Math.PI / 2; ring.position.y = 0.24; g.add(ring);
    const arrow = glowSprite(0x7dff9a, 1.6, 0.35); arrow.position.y = 0.8; g.add(arrow);
    g.traverse(o => { o.userData.dynamic = true; });
    return { ...b, g, top, squash: 0 };
  });
  // ---- swing hooks: a glowing ring you grab with the hook and swing from ----
  const hooks = data.hooks.map(p => {
    const g = new THREE.Group(); g.position.copy(p); group.add(g);
    const ring = mesh(new THREE.TorusGeometry(0.55, 0.12, 10, 28), std(0xffc040, 0.9, 0.25)); g.add(ring);
    const core = mesh(new THREE.SphereGeometry(0.22, 14, 10), glow(0xffd060, 4), false, false); g.add(core);
    const halo = glowSprite(0xffc040, 2.4, 0.45); g.add(halo);
    const drone = mesh(new RoundedBoxGeometry(1.2, 0.5, 1.2, 2, 0.15), dark); drone.position.y = 0.9; g.add(drone);
    for (const s of [-1, 1]) { const prop = mesh(new THREE.CylinderGeometry(0.5, 0.5, 0.04, 16), std(0xffffff, 0.3, 0.4, { transparent: true, opacity: 0.5 }), false, false); prop.position.set(s * 0.8, 1.2, 0); g.add(prop); }
    g.traverse(o => { o.userData.dynamic = true; });
    return { pos: p, g, ring, halo, t: Math.random() * 6 };
  });
  const rope = new THREE.Mesh(new THREE.CylinderGeometry(0.035, 0.035, 1, 6), glow(0xffd060, 3)); rope.visible = false; group.add(rope);

  // ---- nut crates ----
  const crateMat = std(0xffb43a, 0.35, 0.45), crateEdge = std(0x3a3f47, 0.8, 0.35), crateIcon = glow(0xfff0a0, 1.6);
  const boxGeo = new RoundedBoxGeometry(0.85, 0.85, 0.85, 2, 0.06), edgeGeo = new THREE.BoxGeometry(0.9, 0.12, 0.12), nutGeo = new THREE.TorusGeometry(0.17, 0.06, 6, 6);
  const crates = data.nutCrates.map(p => {
    const g = new THREE.Group(); g.position.copy(p).add(V(0, 0.425, 0)); group.add(g);
    g.add(mesh(boxGeo, crateMat));
    for (const [y, r] of [[0.38, 0], [-0.38, 0], [0.38, Math.PI / 2], [-0.38, Math.PI / 2]]) { const e = mesh(edgeGeo, crateEdge); e.position.y = y; e.rotation.y = r; g.add(e); }
    for (let k = 0; k < 4; k++) { const n = mesh(nutGeo, crateIcon, false, false); const a = k * Math.PI / 2; n.position.set(Math.sin(a) * 0.43, 0, Math.cos(a) * 0.43); n.rotation.y = a; g.add(n); }
    g.traverse(o => { o.userData.dynamic = true; });
    const col = { min: g.position.clone().subScalar(0.42), max: g.position.clone().addScalar(0.42) };
    return { type: 'crate', pos: g.position.clone(), g, col, radius: 0.55, hp: 1, maxHp: 1, dead: false };
  });

  const swing = { hook: null, t: 0, L: 0, A: 0, dir: V(0, 0, 1), vel: V(0, 0, 0) };
  let time = 0;

  function reset() {
    for (const c of crates) { c.dead = false; c.g.visible = true; c.hp = 1; }
    swing.hook = null; rope.visible = false;
    time = 0;
  }
  // the colliders this module owns (call after the level's colliders are loaded)
  function addColliders() {
    for (const m of movers) colliders.push(m.col);
    for (const c of crates) if (!c.dead) colliders.push(c.col);
  }
  function smash(c, onNuts) {
    if (c.dead) return;
    c.dead = true; c.g.visible = false;
    const i = colliders.indexOf(c.col); if (i >= 0) colliders.splice(i, 1);
    fx.explosion(c.pos.clone(), 0.45, [crateMat, crateEdge]);
    sfx.crate?.();
    onNuts(c.pos.clone(), 4);
  }

  // the hook the hero would grab right now (in range, above, and roughly where they're facing or looking)
  function hookTarget(pos, lookDir) {
    let best = null, bs = Infinity;
    for (const h of hooks) {
      const d = h.pos.clone().sub(pos); const dist = d.length();
      if (dist > HOOK_RANGE || dist < 4 || d.y < 1.5) continue;
      const flat = V(d.x, 0, d.z).normalize();
      const facing = flat.dot(V(lookDir.x, 0, lookDir.z).normalize());
      if (facing < 0.2) continue;
      const s = dist * (1.6 - facing);
      if (s < bs) { bs = s; best = h; }
    }
    return best;
  }
  function startSwing(h, pos) {
    const d = h.pos.clone().sub(pos);
    swing.hook = h; swing.t = 0; swing.L = d.length();
    swing.dir.set(d.x, 0, d.z).normalize();
    swing.A = Math.atan2(Math.hypot(d.x, d.z), d.y); // start angle from straight down
    sfx.hook?.();
    fx.sparks(h.pos.clone(), 0xffd060, 10, 3);
  }
  // swing: position follows a pendulum arc under the hook; returns 'swing', 'release' or null
  function stepSwing(dt, pos, vel, letGo) {
    if (!swing.hook) return null;
    swing.t += dt;
    const T = SWING_T, k = Math.min(swing.t / T, RELEASE);
    const th = -swing.A * Math.cos(Math.PI * k);
    const N = swing.hook.pos;
    pos.copy(N).addScaledVector(swing.dir, swing.L * Math.sin(th)).add(V(0, -swing.L * Math.cos(th), 0));
    const w = swing.A * Math.PI / T * Math.sin(Math.PI * k); // angular speed
    const sp = Math.min(16, swing.L * w);
    vel.copy(swing.dir).multiplyScalar(Math.cos(th) * sp).add(V(0, Math.sin(th) * sp, 0));
    // rope from the hero's hand to the hook
    const hand = pos.clone().add(V(0, 1.2, 0)), mid = hand.clone().add(N).multiplyScalar(0.5);
    rope.visible = true; rope.position.copy(mid); rope.scale.set(1, hand.distanceTo(N), 1);
    rope.quaternion.setFromUnitVectors(V(0, 1, 0), N.clone().sub(hand).normalize());
    if (k >= RELEASE || (letGo && swing.t > 0.25)) {
      swing.hook = null; rope.visible = false;
      vel.y += 4; vel.addScaledVector(V(vel.x, 0, vel.z).normalize(), 2);
      return 'release';
    }
    return 'swing';
  }

  // called every frame; returns { carry: Vector3 | null, bounce: number | null }
  function update(dt, hero) {
    time += dt;
    let carry = null, bounce = null;
    for (const m of movers) {
      const u = 0.5 - 0.5 * Math.cos(time / m.period * Math.PI * 2);
      const np = m.from.clone().lerp(m.to, u);
      m.delta.subVectors(np, m.pos); m.pos.copy(np);
      m.g.position.copy(np);
      m.col.min.copy(np).sub(m.half); m.col.max.copy(np).add(m.half);
      if (hero.grounded && Math.abs(hero.pos.y - m.col.max.y) < 0.08 && hero.pos.x > m.col.min.x - 0.3 && hero.pos.x < m.col.max.x + 0.3 && hero.pos.z > m.col.min.z - 0.3 && hero.pos.z < m.col.max.z + 0.3) carry = m.delta.clone();
    }
    for (const b of bouncers) {
      b.squash = Math.max(0, b.squash - dt * 5);
      b.top.scale.y = 1 - b.squash * 0.6; b.g.scale.set(1 + b.squash * 0.15, 1 - b.squash * 0.3, 1 + b.squash * 0.15);
      if (hero.grounded && Math.hypot(hero.pos.x - b.pos.x, hero.pos.z - b.pos.z) < 1.15 && Math.abs(hero.pos.y - b.pos.y) < 0.4) {
        bounce = b.power; b.squash = 1; fx.ring(b.pos.clone().add(V(0, 0.3, 0)), 0x7dff9a); sfx.pad?.();
      }
    }
    const target = hero.lookDir ? hookTarget(hero.pos, hero.lookDir) : null;
    for (const h of hooks) {
      h.t += dt; h.g.position.y = h.pos.y + Math.sin(h.t * 1.5) * 0.08;
      const on = h === target && !swing.hook;
      h.ring.rotation.y += dt * (on ? 4 : 1);
      h.halo.material.opacity = on ? 0.9 + Math.sin(h.t * 10) * 0.1 : 0.35;
      h.halo.scale.setScalar(on ? 3.2 : 2.4);
    }
    return { carry, bounce, hook: target };
  }

  return {
    movers, bouncers, hooks, crates, swing, reset, addColliders, smash, startSwing, stepSwing, update, hookTarget,
    get swinging() { return !!swing.hook; },
  };
}
