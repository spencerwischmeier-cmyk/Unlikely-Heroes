// Gizmart: a cheerful vending-machine robot that sells weapons, ammo and repairs for hex nuts.
// Step onto the glowing mat in front of it to open the shop.
import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { V, std, glow, mesh, canvasTex, glowSprite } from './util.js';

const signTex = canvasTex(512, 128, (g, w, h) => {
  g.fillStyle = '#1a0f2e'; g.fillRect(0, 0, w, h);
  g.font = 'italic 900 84px system-ui,sans-serif'; g.textAlign = 'center'; g.textBaseline = 'middle';
  g.shadowColor = '#ff5ab0'; g.shadowBlur = 18; g.fillStyle = '#ffe36a'; g.fillText('GIZMART', w / 2, h / 2 + 4);
});
const matTex = canvasTex(256, 256, (g, w) => {
  g.strokeStyle = '#fff'; g.lineWidth = 12; g.beginPath(); g.arc(w / 2, w / 2, w / 2 - 10, 0, 7); g.stroke();
  g.font = '900 italic 60px system-ui,sans-serif'; g.fillStyle = '#fff'; g.textAlign = 'center'; g.textBaseline = 'middle'; g.fillText('SHOP', w / 2, w / 2 + 4);
});

const at = (m, p, r) => { m.position.copy(p); if (r) m.rotation.copy(r); return m; };

export function createGizmart(group, pos, yaw) {
  const g = new THREE.Group(); g.position.copy(pos); g.rotation.y = yaw; group.add(g);
  const body = std(0xff5a4a, 0.35, 0.35), trim = std(0xf4f6f8, 0.5, 0.3), dark = std(0x23262e, 0.7, 0.4);
  const tilt = new THREE.Group(); g.add(tilt); // the whole machine bobs and leans as it "talks"
  tilt.add(at(mesh(new RoundedBoxGeometry(1.4, 2.1, 0.95, 4, 0.16), body), V(0, 1.35, 0)));
  tilt.add(at(mesh(new RoundedBoxGeometry(1.5, 0.16, 1.05, 2, 0.06), trim), V(0, 2.42, 0)));
  // glass front with rows of goodies
  const glass = new THREE.MeshPhysicalMaterial({ color: 0x9fe3ff, metalness: 0, roughness: 0.05, transmission: 0, transparent: true, opacity: 0.35, clearcoat: 1 });
  tilt.add(at(mesh(new THREE.BoxGeometry(0.95, 1.05, 0.04), glass, false, false), V(-0.12, 1.25, 0.49)));
  const goods = [0x5ff2ff, 0xff6ab0, 0x9dff5a, 0xffd040];
  for (let r = 0; r < 3; r++) for (let c = 0; c < 3; c++) {
    const it = mesh(new RoundedBoxGeometry(0.2, 0.22, 0.2, 2, 0.05), glow(goods[(r + c) % 4], 1.6), false, false);
    it.position.set(-0.42 + c * 0.3, 0.92 + r * 0.33, 0.36); tilt.add(it);
  }
  // coin slot and keypad on the right
  tilt.add(at(mesh(new RoundedBoxGeometry(0.26, 0.7, 0.06, 2, 0.03), dark), V(0.5, 1.3, 0.49)));
  for (let i = 0; i < 6; i++) tilt.add(at(mesh(new THREE.CylinderGeometry(0.03, 0.03, 0.03, 10), glow(0xffe36a, 2), false, false), V(0.46 + (i % 2) * 0.08, 1.45 - Math.floor(i / 2) * 0.1, 0.53), new THREE.Euler(Math.PI / 2, 0, 0)));
  tilt.add(at(mesh(new RoundedBoxGeometry(0.9, 0.22, 0.1, 2, 0.04), dark), V(-0.12, 0.52, 0.47))); // prize drawer
  // the face: a little screen on top with blinking eyes and a smile
  const head = new THREE.Group(); head.position.set(0, 2.85, 0); tilt.add(head);
  head.add(mesh(new RoundedBoxGeometry(1.1, 0.7, 0.7, 4, 0.18), trim));
  head.add(at(mesh(new RoundedBoxGeometry(0.9, 0.5, 0.05, 2, 0.08), dark, false, false), V(0, 0, 0.34)));
  const faceMat = glow(0x5ff2ff, 4);
  const eyes = [-0.2, 0.2].map(x => { const e = mesh(new THREE.SphereGeometry(0.07, 14, 10), faceMat, false, false); e.scale.set(1, 1.4, 0.4); e.position.set(x, 0.06, 0.38); head.add(e); return e; });
  const smile = mesh(new THREE.TorusGeometry(0.14, 0.025, 6, 20, Math.PI), faceMat, false, false); smile.rotation.z = Math.PI; smile.position.set(0, -0.06, 0.38); head.add(smile);
  const ant = mesh(new THREE.CylinderGeometry(0.02, 0.02, 0.35, 6), dark); ant.position.set(0.3, 0.5, 0); head.add(ant);
  const antTip = mesh(new THREE.SphereGeometry(0.06, 10, 8), glow(0xff5ab0, 5), false, false); antTip.position.set(0.3, 0.7, 0); head.add(antTip);
  // sign
  const sign = new THREE.Mesh(new THREE.PlaneGeometry(1.5, 0.375), new THREE.MeshBasicMaterial({ map: signTex, toneMapped: false }));
  sign.position.set(0, 3.55, 0.05); tilt.add(sign);
  // stubby arms
  const arms = [-1, 1].map(s => {
    const a = new THREE.Group(); a.position.set(0.76 * s, 1.7, 0); tilt.add(a);
    const up = mesh(new THREE.CylinderGeometry(0.06, 0.06, 0.55, 8), dark); up.position.y = -0.27; a.add(up);
    const hand = mesh(new THREE.SphereGeometry(0.11, 12, 8), trim); hand.position.y = -0.58; a.add(hand);
    a.rotation.z = 0.25 * s; return a;
  });
  // hover base
  g.add(at(mesh(new THREE.CylinderGeometry(0.62, 0.75, 0.28, 24), dark), V(0, 0.2, 0)));
  const hover = mesh(new THREE.TorusGeometry(0.66, 0.05, 8, 32), glow(0xff5ab0, 4), false, false); hover.rotation.x = Math.PI / 2; hover.position.y = 0.08; g.add(hover);
  // shop mat
  const matPos = V(0, 0, 1.7).applyAxisAngle(V(0, 1, 0), yaw).add(pos);
  const matMat = new THREE.MeshBasicMaterial({ map: matTex, color: 0xffe36a, transparent: true, depthWrite: false, toneMapped: false });
  const mat = new THREE.Mesh(new THREE.CircleGeometry(0.95, 32), matMat); mat.rotation.x = -Math.PI / 2; mat.position.copy(matPos).setY(0.03); group.add(mat);
  const matGlow = glowSprite(0xffe36a, 2.2, 0.3); matGlow.position.copy(matPos).setY(0.3); group.add(matGlow);
  g.traverse(o => { o.userData.dynamic = true; });
  mat.userData.dynamic = true;

  let t = Math.random() * 10, blink = 2, talk = 0, inside = false;
  return {
    pos, matPos, group: g,
    talk() { talk = 1.2; },
    // returns true the moment the hero steps onto the mat
    update(dt, heroPos, heroGrounded) {
      t += dt; blink -= dt; talk = Math.max(0, talk - dt);
      const sq = blink < 0.12 ? 0.15 : 1.4; eyes.forEach(e => (e.scale.y = sq)); if (blink < 0) blink = 2 + Math.random() * 3;
      tilt.position.y = Math.sin(t * 2) * 0.05 + (talk > 0 ? Math.abs(Math.sin(t * 14)) * 0.06 : 0);
      tilt.rotation.z = Math.sin(t * 1.3) * 0.03;
      arms.forEach((a, i) => { a.rotation.x = talk > 0 ? Math.sin(t * 10 + i * 3) * 0.8 : Math.sin(t * 1.6 + i) * 0.1; });
      head.rotation.y = Math.sin(t * 0.7) * 0.15;
      const d = Math.hypot(heroPos.x - matPos.x, heroPos.z - matPos.z);
      const on = d < 1.0 && heroGrounded && Math.abs(heroPos.y) < 0.3;
      matMat.color.setHex(on ? 0xffffff : 0xffe36a); matGlow.material.opacity = 0.25 + Math.sin(t * 4) * 0.08;
      const entered = on && !inside; inside = d < 1.6 ? inside || on : false;
      return entered;
    },
  };
}

// what Gizmart sells; `have` tells the shop what the hero already owns
export const SHOP = [
  { id: 'scatter', kind: 'weapon', name: 'Scatter Bloom', price: 200, blurb: 'A close-range burst of petals.' },
  { id: 'lobber', kind: 'weapon', name: 'Thump Lobber', price: 400, blurb: 'Bouncing bombs that blast a whole area.' },
  { id: 'seeker', kind: 'weapon', name: 'Seeker Hive', price: 650, blurb: 'Homing rockets. Point near a bot and fire.' },
  { id: 'ammo', kind: 'ammo', name: 'Ammo refill', price: 60, blurb: 'Tops up every weapon.' },
  { id: 'repair', kind: 'repair', name: 'Hull patch', price: 80, blurb: 'Repairs 4 hull cells.' },
];
export const GIZ_LINES = {
  hello: ['Welcome to Gizmart! Everything must go, mostly because bots keep stealing it!', 'Hi hi hi! Customer! A real one! Do not run!', 'Gizmart! Open 25 hours a day!', 'You look like someone who needs a bigger blaster!'],
  buy: ['Pleasure doing business!', 'No refunds! Also no returns! Also no complaints!', 'Ka-ching! That sound never gets old!', 'Excellent choice! I say that to everyone, but this time I mean it!'],
  broke: ['Ooh, so close. By "close" I mean not close at all.', 'Come back with more nuts!', 'Gizmart accepts hex nuts, hex nuts, and hex nuts.'],
  bye: ['Come back soon! Please! It gets lonely!', 'Bye! Don\'t get scrapped!'],
};
