// Grind rails: walk or jump onto one and you slide along it (shooting still works), jump to hop off.
// A locked rail glows red and can't be ridden until the story opens it.
import * as THREE from 'three';
import { V, std, mesh, clamp } from './util.js';

const OPEN = new THREE.Color(0xffb43a), LOCKED = new THREE.Color(0xff3030);

export function createRails(group, defs) {
  const steel = std(0xd8e2ea, 0.95, 0.18), postMat = std(0x34404c, 0.75, 0.4);
  const rails = defs.map(d => {
    const curve = new THREE.CatmullRomCurve3(d.pts.map(p => V(...p)));
    const len = curve.getLength();
    const tube = mesh(new THREE.TubeGeometry(curve, Math.ceil(len * 4), 0.13, 10), steel);
    const glowMat = new THREE.MeshStandardMaterial({ color: 0x000000, emissive: d.locked ? LOCKED : OPEN, emissiveIntensity: 2.5 });
    const glowLine = mesh(new THREE.TubeGeometry(new THREE.CatmullRomCurve3(d.pts.map(p => V(p[0], p[1] - 0.17, p[2]))), Math.ceil(len * 3), 0.04, 6), glowMat, false, false);
    tube.userData.dynamic = glowLine.userData.dynamic = true;
    group.add(tube, glowLine);
    // support posts hanging down into the sky
    for (let u = 0.08; u < 0.95; u += 10 / len) {
      const p = curve.getPointAt(u);
      const post = mesh(new THREE.CylinderGeometry(0.1, 0.16, 30, 8), postMat); post.position.set(p.x, p.y - 15.15, p.z); group.add(post);
    }
    // samples for finding the nearest point quickly
    const n = Math.ceil(len / 0.25), samples = [];
    for (let i = 0; i <= n; i++) samples.push(curve.getPointAt(i / n));
    return { curve, len, samples, locked: !!d.locked, glowMat };
  });

  const ride = { rail: null, u: 0, dir: 1, speed: 0, cooldown: 0 };
  const tan = V(0, 0, 0);

  function setLocked(i, v) { const r = rails[i]; if (!r) return; r.locked = v; r.glowMat.emissive.copy(v ? LOCKED : OPEN); }

  // look for a rail under the hero's feet
  function tryAttach(pos, vel, dt) {
    ride.cooldown -= dt;
    if (ride.cooldown > 0) return false;
    for (const r of rails) {
      if (r.locked) continue;
      let best = -1, bd = 1.0;
      for (let i = 0; i < r.samples.length; i++) {
        const s = r.samples[i];
        const dy = pos.y - s.y; if (dy < -0.55 || dy > 0.7) continue;
        const d = Math.hypot(pos.x - s.x, pos.z - s.z); if (d < bd) { bd = d; best = i; }
      }
      if (best < 0) continue;
      if (vel.y > 2 && pos.y < r.samples[best].y) continue; // still rising up past it
      ride.rail = r; ride.u = best / (r.samples.length - 1);
      r.curve.getTangentAt(ride.u, tan);
      const along = vel.x * tan.x + vel.y * tan.y + vel.z * tan.z;
      // ride in the direction you were moving; from a standstill, toward the far end
      ride.dir = Math.abs(along) > 1 ? Math.sign(along) : ride.u < 0.5 ? 1 : -1;
      ride.speed = Math.max(12, Math.abs(along));
      return true;
    }
    return false;
  }

  // move along the rail; returns 'ride', 'end' (ran off the end) or null when not riding
  function step(dt, pos, vel) {
    const r = ride.rail; if (!r) return null;
    r.curve.getTangentAt(clamp(ride.u, 0, 1), tan);
    // downhill speeds you up, uphill slows you a little
    ride.speed = clamp(ride.speed - tan.y * ride.dir * 14 * dt, 10, 22);
    ride.u += ride.dir * ride.speed * dt / r.len;
    const done = ride.u <= 0 || ride.u >= 1;
    const p = r.curve.getPointAt(clamp(ride.u, 0, 1));
    pos.set(p.x, p.y + 0.13, p.z);
    vel.copy(tan).multiplyScalar(ride.dir * ride.speed);
    if (done) { detach(); vel.y += 3; return 'end'; }
    return 'ride';
  }
  function detach(cool = 0.45) { ride.rail = null; ride.cooldown = cool; }

  return { rails, ride, tryAttach, step, detach, setLocked, get riding() { return !!ride.rail; } };
}
