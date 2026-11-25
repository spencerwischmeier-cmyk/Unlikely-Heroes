// Test-range props: practice targets in the target range (some slide on rails) and the "call bots" pad.
// Targets use the same fields the weapons look at on enemies (pos, radius, dead, type) so every weapon can hit them.
import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { V, std, glow, mesh, canvasTex, glowSprite } from './util.js';

const boardTex = canvasTex(256, 256, (g, w) => {
  const rings = ['#ff7a1a', '#ffffff', '#ff7a1a', '#ffffff', '#2fe3ff'];
  rings.forEach((c, i) => { g.fillStyle = c; g.beginPath(); g.arc(w / 2, w / 2, w / 2 - i * 24 - 2, 0, 7); g.fill(); });
  g.strokeStyle = '#1d2a36'; g.lineWidth = 6; g.beginPath(); g.arc(w / 2, w / 2, w / 2 - 4, 0, 7); g.stroke();
});

export function createRange(scene, fx) {
  const targets = [];
  const postMat = std(0x34404c, 0.75, 0.4), baseMat = std(0xdfe8ee, 0.65, 0.28), railMat = std(0x5f8fb0, 0.7, 0.32);
  const postGeo = new THREE.CylinderGeometry(0.06, 0.06, 1.0, 10), baseGeo = new RoundedBoxGeometry(0.8, 0.25, 0.5, 2, 0.06);
  const boardGeo = new THREE.CylinderGeometry(0.55, 0.55, 0.08, 32);
  // distance from the firing line (z = -15) and sideways position; `slide` = how far it moves side to side
  const layout = [[5, -6], [5, 0], [5, 6], [10, -9, 0], [10, 3, 3], [20, -6], [20, 6, 5], [20, 0, 0]];
  for (const [d, x, slide = 0] of layout) {
    const z = -15 - d;
    const g = new THREE.Group(); g.position.set(x, 0, z); scene.add(g);
    g.add(mesh(baseGeo, baseMat)); const post = mesh(postGeo, postMat); post.position.y = 0.6; g.add(post);
    const hinge = new THREE.Group(); hinge.position.y = 1.1; g.add(hinge);  // the board flips back on this when knocked down
    const mat = new THREE.MeshStandardMaterial({ map: boardTex, roughness: 0.5, emissive: 0xffffff, emissiveIntensity: 0 });
    const board = mesh(boardGeo, [std(0xdfe8ee, 0.6, 0.3), mat, mat]); board.rotation.x = Math.PI / 2; board.position.y = 0.55; hinge.add(board);
    if (slide) {
      const rail = mesh(new THREE.BoxGeometry(slide * 2 + 1, 0.08, 0.3), railMat); rail.position.set(x, 0.04, z); scene.add(rail);
    }
    targets.push({ type: 'dummy', g, hinge, mat, x0: x, slide, pos: V(x, 1.65, z), radius: 0.6, hp: 10, maxHp: 10, dead: false, downT: 0, flash: 0, t: Math.random() * 6 });
  }

  // "call bots" pad on the south side of the test area
  const padPos = V(0, 0, 16);
  const ringTex = canvasTex(256, 256, (g, w) => {
    g.strokeStyle = '#fff'; g.lineWidth = 14; g.beginPath(); g.arc(w / 2, w / 2, w / 2 - 12, 0, 7); g.stroke();
    g.font = '900 italic 46px system-ui,sans-serif'; g.fillStyle = '#fff'; g.textAlign = 'center'; g.textBaseline = 'middle';
    g.fillText('CALL', w / 2, w / 2 - 24); g.fillText('BOTS', w / 2, w / 2 + 28);
  });
  const padMat = new THREE.MeshBasicMaterial({ map: ringTex, color: 0xff5040, transparent: true, depthWrite: false, toneMapped: false });
  const pad = new THREE.Mesh(new THREE.CircleGeometry(1.4, 40), padMat); pad.rotation.x = -Math.PI / 2; pad.position.copy(padPos).setY(0.03); scene.add(pad);
  const padBase = mesh(new THREE.CylinderGeometry(1.55, 1.65, 0.06, 40), std(0x34404c, 0.75, 0.4), false, true); padBase.position.copy(padPos).setY(0.01); scene.add(padBase);
  const padGlow = glowSprite(0xff5040, 3, 0.35); padGlow.position.copy(padPos).setY(0.4); scene.add(padGlow);
  let padCd = 0;

  function damage(t, amount) {
    if (t.dead) return false;
    t.hp -= amount; t.flash = 1;
    if (t.hp <= 0) { t.dead = true; t.downT = 2.2; fx.sparks(t.pos.clone(), 0xffc23d, 14, 5); return true; }
    return false;
  }

  function update(dt, { heroPos, active, onCall }) {
    for (const t of targets) {
      t.t += dt;
      if (t.slide) { t.g.position.x = t.x0 + Math.sin(t.t * 0.9) * t.slide; t.pos.x = t.g.position.x; }
      t.flash = Math.max(0, t.flash - dt * 6); t.mat.emissiveIntensity = t.flash * 0.8;
      if (t.dead) {
        t.downT -= dt;
        t.hinge.rotation.x = Math.max(-1.5, t.hinge.rotation.x - dt * 12);
        if (t.downT <= 0) { t.dead = false; t.hp = t.maxHp; }
      } else t.hinge.rotation.x = Math.min(0, t.hinge.rotation.x + dt * 6);
    }
    // call-bots pad: only works in the test range
    padCd -= dt;
    pad.visible = padBase.visible = padGlow.visible = active;
    const on = active && Math.hypot(heroPos.x - padPos.x, heroPos.z - padPos.z) < 1.4 && heroPos.y < 0.2;
    padMat.color.setHex(padCd > 0 ? 0x666a70 : on ? 0xffffff : 0xff5040);
    padGlow.material.opacity = padCd > 0 ? 0.1 : 0.3 + Math.sin(t0 += dt * 4) * 0.1;
    if (on && padCd <= 0) { padCd = 4; onCall(); }
  }
  let t0 = 0;

  return { targets, damage, update, padPos };
}
