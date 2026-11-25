// The sidekick: a one-eyed floating drone that trails the hero and zaps nearby enemies.
import * as THREE from 'three';
import { V, std, glow, mesh, glowSprite } from './util.js';

export function createDrone(scene) {
  const bot = new THREE.Group(); scene.add(bot);
  const shellMat = std(0xe9edf1, 0.6, 0.22);
  const metalDark = std(0x34404c, 0.75, 0.4);
  bot.add(mesh(new THREE.SphereGeometry(0.26, 48, 32), shellMat));
  bot.add(mesh(new THREE.TorusGeometry(0.262, 0.03, 12, 48), std(0xff6a1a, 0.3, 0.4)));
  const eyeRing = mesh(new THREE.TorusGeometry(0.12, 0.03, 16, 40), metalDark); eyeRing.position.z = 0.22; bot.add(eyeRing);
  const eyeGlass = mesh(new THREE.SphereGeometry(0.115, 32, 20), new THREE.MeshPhysicalMaterial({ color: 0x062028, metalness: 0.1, roughness: 0.05, clearcoat: 1 })); eyeGlass.position.z = 0.2; eyeGlass.scale.z = 0.5; bot.add(eyeGlass);
  const pupilMat = glow(0x3ff6ff, 2.5);
  const pupil = mesh(new THREE.CircleGeometry(0.055, 32), pupilMat, false, false); pupil.position.set(0, 0, 0.262); bot.add(pupil);
  const pr = mesh(new THREE.RingGeometry(0.07, 0.085, 32), glow(0x3ff6ff, 3), false, false); pr.position.set(0, 0, 0.26); bot.add(pr);
  const jets = [];
  for (const s of [-1, 1]) {
    const arm = mesh(new THREE.CylinderGeometry(0.025, 0.025, 0.22, 10), metalDark); arm.rotation.z = Math.PI / 2; arm.position.set(0.32 * s, 0, -0.02); bot.add(arm);
    const pod = mesh(new THREE.CylinderGeometry(0.09, 0.07, 0.08, 24), shellMat); pod.position.set(0.44 * s, 0, -0.02); bot.add(pod);
    const ring = mesh(new THREE.TorusGeometry(0.1, 0.012, 8, 32), glow(0x40f0ff, 7)); ring.rotation.x = Math.PI / 2; ring.position.set(0.44 * s, -0.04, -0.02); bot.add(ring);
    const jet = glowSprite(0x60e8ff, 0.35, 0.65); jet.position.set(0.44 * s, -0.1, -0.02); bot.add(jet); jets.push(jet);
  }
  const antenna = mesh(new THREE.CylinderGeometry(0.008, 0.012, 0.2, 8), metalDark); antenna.position.set(0.06, 0.32, -0.04); antenna.rotation.z = -0.25; bot.add(antenna);
  const antTip = mesh(new THREE.SphereGeometry(0.025, 12, 8), glow(0xffa030, 5)); antTip.position.set(0.085, 0.42, -0.04); bot.add(antTip);
  const botLight = new THREE.PointLight(0x50e8ff, 1.5, 2.5, 2); botLight.position.set(0, 0, 0.5); bot.add(botLight);

  // zap beam
  const beamMat = new THREE.MeshBasicMaterial({ color: 0x8ffcff, transparent: true, opacity: 0, blending: THREE.AdditiveBlending, depthWrite: false });
  const beam = new THREE.Mesh(new THREE.CylinderGeometry(0.03, 0.03, 1, 6, 1, true), beamMat); beam.frustumCulled = false; scene.add(beam);

  let t = 0, cooldown = 1.5, beamT = 0;
  const pos = V(0, 2, 0), vel = V(0, 0, 0), look = new THREE.Quaternion(), m4 = new THREE.Matrix4();
  bot.position.copy(pos);

  function update(dt, heroPos, heroYaw, enemies, onZap) {
    t += dt;
    // hover behind the hero's left shoulder
    const side = V(Math.cos(heroYaw), 0, -Math.sin(heroYaw));
    const back = V(-Math.sin(heroYaw), 0, -Math.cos(heroYaw));
    const target = heroPos.clone().addScaledVector(side, -0.9).addScaledVector(back, -0.2).add(V(0, 2.25 + Math.sin(t * 2.2) * 0.12, 0));
    vel.lerp(target.clone().sub(bot.position).multiplyScalar(5), 1 - Math.exp(-6 * dt));
    bot.position.addScaledVector(vel, dt);

    // pick the nearest enemy in range
    let best = null, bestD = 13;
    for (const e of enemies) { if (e.dead) continue; const d = e.pos.distanceTo(bot.position); if (d < bestD) { bestD = d; best = e; } }
    const lookAt = best ? best.pos : bot.position.clone().add(back.clone().multiplyScalar(-3));
    m4.lookAt(lookAt, bot.position, V(0, 1, 0)); look.setFromRotationMatrix(m4);
    bot.quaternion.slerp(look, 1 - Math.exp(-8 * dt));
    bot.rotation.z += Math.sin(t * 1.7) * 0.002;

    cooldown -= dt;
    if (best && cooldown <= 0) {
      cooldown = 1.8;
      beamT = 1;
      const a = bot.position.clone(), b = best.pos.clone();
      beam.position.copy(a).lerp(b, 0.5);
      beam.scale.set(1, a.distanceTo(b), 1);
      beam.quaternion.setFromUnitVectors(V(0, 1, 0), b.clone().sub(a).normalize());
      onZap(best);
    }
    beamT = Math.max(0, beamT - dt * 6);
    beamMat.opacity = beamT;
    pupilMat.emissiveIntensity = 2.5 + beamT * 6;
    jets.forEach(j => j.scale.setScalar(0.3 + Math.random() * 0.08));
  }
  return { bot, update };
}
