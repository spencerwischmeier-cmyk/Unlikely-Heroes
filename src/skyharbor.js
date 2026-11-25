// Skyharbor, the first story level: floating docks and cargo islands above the sky city, joined by grind rails.
//   Dockside (start, Gizmart) -> rail -> Cargo Yard (Gizmart) -> rail up -> Signal Mast tower top -> rail down -> Crane Yard (boss)
// Floors at height 0 are "decks" (islands); everything raised is a collider box. Miss a rail and you fall
// back to the last checkpoint.
import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { V, std, glow, mesh, glowSprite, R } from './util.js';

const rect = (cx, cz, w, d) => ({ minX: cx - w / 2, maxX: cx + w / 2, minZ: cz - d / 2, maxZ: cz + d / 2 });
export const ISLANDS = {
  dock: rect(0, 32, 22, 16),
  cargo: rect(30, -2, 20, 16),
  yard: rect(-26, -28, 24, 24),
};
export const MAST = { ...rect(28, -36, 12, 12), top: 7 };

export function buildSkyharbor(k) {
  const { G, block, crate, label, deckTex, lipMat, hazardTex, crateMat, mats, addCollider } = k;
  const { metalWhite, metalBlue, metalTeal, metalDark, brass, cyanGlow, warmGlow } = mats;
  const add = (m, x, y, z) => { m.position.set(x, y, z); G.add(m); return m; };

  // ---- islands ----
  function island(r, tint = 0xffffff) {
    const w = r.maxX - r.minX, d = r.maxZ - r.minZ, cx = (r.minX + r.maxX) / 2, cz = (r.minZ + r.maxZ) / 2;
    const t = deckTex.clone(); t.needsUpdate = true; t.repeat.set(w / 3.6, d / 3.6);
    add(mesh(new RoundedBoxGeometry(w, 1.2, d, 4, 0.2), std(tint, 0.75, 0.38, { map: t }), false, true), cx, -0.6, cz);
    // the rock-and-machinery underside, with a glowing lift core
    const rad = Math.min(w, d) * 0.48;
    const under = add(mesh(new THREE.CylinderGeometry(rad, rad * 0.22, rad * 1.7, 8), metalDark, false, false), cx, -1.2 - rad * 0.85, cz);
    under.scale.set(w / Math.min(w, d), 1, d / Math.min(w, d)); under.rotation.y = Math.PI / 8;
    add(mesh(new THREE.CylinderGeometry(rad * 0.3, rad * 0.3, 0.6, 20), glow(0x40f0ff, 4), false, false), cx, -1.2 - rad * 1.7, cz);
    for (const s of [-1, 1]) {
      const fin = add(mesh(new RoundedBoxGeometry(0.5, rad * 1.1, w * 0.5, 2, 0.15), metalBlue, false, false), cx + s * w * 0.32, -1.2 - rad * 0.5, cz);
      fin.rotation.z = s * 0.3;
    }
    // hazard edging and a glowing lip so the drop is easy to see
    const edge = (len, x, z, rotY) => {
      const ht = hazardTex.clone(); ht.needsUpdate = true; ht.repeat.set(len / 2, 1);
      const hz = add(mesh(new THREE.BoxGeometry(len, 0.22, 0.3), std(0xffffff, 0.3, 0.5, { map: ht }), false, true), x, -0.08, z); hz.rotation.y = rotY;
      const l = add(mesh(new THREE.BoxGeometry(len, 0.05, 0.05), glow(0x40f0ff, 2.5), false, false), x, -0.25, z); l.rotation.y = rotY;
    };
    edge(w, cx, r.minZ, 0); edge(w, cx, r.maxZ, 0); edge(d, r.minX, cz, Math.PI / 2); edge(d, r.maxX, cz, Math.PI / 2);
  }
  // a railing along part of an island edge: solid (you can hop over it) with a gap wherever a rail starts
  function railing(x1, z1, x2, z2) {
    const len = Math.hypot(x2 - x1, z2 - z1), cx = (x1 + x2) / 2, cz = (z1 + z2) / 2, rotY = x1 === x2 ? Math.PI / 2 : 0;
    const top = add(mesh(new THREE.CylinderGeometry(0.06, 0.06, len, 8), metalWhite, false, false), cx, 1.0, cz); top.rotation.z = Math.PI / 2; top.rotation.y = rotY;
    const lg = add(mesh(new THREE.BoxGeometry(len, 0.03, 0.03), glow(0x40f0ff, 2.2), false, false), cx, 0.9, cz); lg.rotation.y = rotY;
    const n = Math.max(1, Math.round(len / 2.4));
    for (let i = 0; i <= n; i++) { const u = i / n; add(mesh(new THREE.CylinderGeometry(0.05, 0.06, 1, 8), metalWhite, false, false), x1 + (x2 - x1) * u, 0.5, z1 + (z2 - z1) * u); }
    addCollider(cx, 0.5, cz, x1 === x2 ? 0.2 : len, 1.0, x1 === x2 ? len : 0.2);
  }
  const lamp = (x, z, c = 0xffc070) => {
    add(mesh(new THREE.CylinderGeometry(0.07, 0.1, 3.2, 8), metalDark), x, 1.6, z);
    add(mesh(new THREE.SphereGeometry(0.2, 12, 8), glow(c, 5), false, false), x, 3.25, z);
    const s = glowSprite(c, 2.2, 0.35); s.position.set(x, 3.25, z); G.add(s);
  };

  const { dock, cargo, yard } = ISLANDS;
  island(dock); island(cargo, 0xe8f0f6); island(yard, 0xd8dde2);

  // ---- Dockside: moored sky barges, bollards, cargo and lamps ----
  railing(dock.minX, dock.maxZ, dock.maxX, dock.maxZ);
  railing(dock.minX, dock.minZ, -2, dock.minZ); railing(2, dock.minZ, dock.maxX, dock.minZ); // gap for the first rail
  railing(dock.minX, dock.minZ, dock.minX, dock.maxZ); railing(dock.maxX, dock.minZ, dock.maxX, dock.maxZ);
  function barge(x, z, rotY, hull = 0xe86a2a) {
    const g = new THREE.Group(); g.position.set(x, -0.6, z); g.rotation.y = rotY; G.add(g);
    const body = mesh(new THREE.CapsuleGeometry(1.6, 7, 6, 16), std(hull, 0.4, 0.4)); body.rotation.z = Math.PI / 2; body.scale.set(1, 1, 0.8); g.add(body);
    const deck = mesh(new RoundedBoxGeometry(7.5, 0.3, 2.4, 2, 0.1), metalWhite); deck.position.y = 1.15; g.add(deck);
    const cab = mesh(new RoundedBoxGeometry(2.4, 1.6, 2, 3, 0.3), metalBlue); cab.position.set(-2, 2.1, 0); g.add(cab);
    const win = mesh(new THREE.BoxGeometry(0.05, 0.5, 1.6), glow(0x9ff6ff, 2.5), false, false); win.position.set(-0.78, 2.3, 0); g.add(win);
    for (const s of [-1, 1]) { const jet = mesh(new THREE.CylinderGeometry(0.5, 0.7, 1.4, 16), metalDark); jet.rotation.z = Math.PI / 2; jet.position.set(-4.6, -0.2, s * 0.9); g.add(jet); }
    const jg = glowSprite(0x60e8ff, 2, 0.5); jg.position.set(-5.4, -0.2, 0); g.add(jg);
  }
  barge(dock.minX - 2.6, 33, Math.PI / 2); barge(dock.maxX + 2.6, 29, -Math.PI / 2, 0x3f9fa0);
  for (const [x, z] of [[-10.4, 26], [-10.4, 38], [10.4, 26], [10.4, 38]]) { add(mesh(new THREE.CylinderGeometry(0.3, 0.38, 0.7, 12), brass), x, 0.35, z); addCollider(x, 0.35, z, 0.7, 0.7, 0.7); }
  crate(6, 0, 37, 1.2); crate(7.2, 0, 37.2, 1.1); crate(6.6, 0.96, 37.1, 1.0); crate(-4, 0, 26.5, 1.2);
  block(5.5, 28, 3, 2, 1.1, 0, metalBlue);
  lamp(-10, 31.5); lamp(10, 34.5); lamp(-3, 24.6, 0x60f0ff); lamp(3, 24.6, 0x60f0ff);
  label('SKYHARBOR DOCKS', 0, 31, 0, 11, '#ffe7a0');
  // a dock crane arm (scenery)
  add(mesh(new THREE.CylinderGeometry(0.35, 0.5, 7, 10), metalDark), 9, 3.5, 25.2);
  const arm = add(mesh(new RoundedBoxGeometry(0.5, 0.5, 8, 2, 0.1), brass), 9, 7, 28.8); arm.rotation.x = 0.15;
  addCollider(9, 3.5, 25.2, 0.9, 7, 0.9);

  // ---- Cargo Yard: container stacks to fight around ----
  railing(cargo.maxX, cargo.minZ, cargo.maxX, cargo.maxZ); railing(cargo.minX, cargo.maxZ, cargo.maxX, cargo.maxZ);
  railing(cargo.minX, cargo.minZ, 28, cargo.minZ); railing(32, cargo.minZ, cargo.maxX, cargo.minZ);
  const boxMats = [std(0xd2462e, 0.5, 0.45), std(0x2e7fd2, 0.5, 0.45), std(0xe8b22a, 0.5, 0.45), std(0x3aa57a, 0.5, 0.45)];
  const container = (x, z, rotY, y0, m) => {
    const sx = rotY ? 2.4 : 5, sz = rotY ? 5 : 2.4;
    const c = add(mesh(new RoundedBoxGeometry(sx, 2.5, sz, 2, 0.08), m), x, y0 + 1.25, z);
    for (let i = -2; i <= 2; i++) { const rib = mesh(new THREE.BoxGeometry(rotY ? sx + 0.06 : 0.12, 2.3, rotY ? 0.12 : sz + 0.06), metalDark); rib.position.set(rotY ? 0 : i * 1.1, 0, rotY ? i * 1.1 : 0); c.add(rib); }
    addCollider(x, y0 + 1.25, z, sx, 2.5, sz);
  };
  container(24, -6, 0, 0, boxMats[0]); container(24, -6, 0, 2.5, boxMats[2]);
  container(36, 1, 1, 0, boxMats[1]); container(29.5, 3.2, 0, 0, boxMats[3]);
  container(35.5, -7, 0, 0, boxMats[2]);
  crate(27, 0, -2, 1.3); crate(32.5, 0, -3.5, 1.2); crate(21.5, 0, 2.5, 1.2); crate(22.6, 0, 2.2, 1.0);
  lamp(20.6, -9.4); lamp(39.4, 5.4); lamp(28, -9.6, 0x60f0ff); lamp(32, -9.6, 0x60f0ff);
  label('CARGO YARD', 30, 4.8, 0, 8, '#bff9ff');

  // ---- Signal Mast: a tall tower; its roof is a raised platform with Grudd's signal relay on top ----
  const mw = MAST.maxX - MAST.minX, mx = (MAST.minX + MAST.maxX) / 2, mz = (MAST.minZ + MAST.maxZ) / 2;
  block(mx, mz, mw, mw, 27, MAST.top - 27, std(0x9fb2c2, 0.7, 0.35, { map: deckTex }));
  add(mesh(new THREE.CylinderGeometry(4.5, 5.5, 80, 12), metalDark, false, false), mx, MAST.top - 67, mz);
  for (const y of [-2, -9, -16]) add(mesh(new THREE.TorusGeometry(mw * 0.62, 0.25, 8, 40), warmGlow, false, false), mx, MAST.top + y, mz).rotation.x = Math.PI / 2;
  // low parapet around the roof, open on the west side where the next rail leaves and the south where you arrive
  const pm = std(0x34404c, 0.75, 0.4);
  block(mx + mw / 2 - 0.25, mz, 0.5, mw, 0.9, MAST.top, pm, false);
  block(mx + 1.5, MAST.minZ + 0.25, mw - 3, 0.5, 0.9, MAST.top, pm, false);
  // the relay itself is not merged so the story can blow it up
  const relay = new THREE.Group(); relay.position.set(mx + 1.5, MAST.top, mz - 1.5); relay.userData.dynamic = true; G.add(relay);
  const relayParts = [];
  const rp = (m, x, y, z) => { m.position.set(x, y, z); m.userData.dynamic = true; relay.add(m); relayParts.push(m); return m; };
  rp(mesh(new THREE.CylinderGeometry(0.9, 1.2, 0.8, 16), metalDark), 0, 0.4, 0);
  rp(mesh(new THREE.CylinderGeometry(0.18, 0.3, 5, 10), metalWhite), 0, 3.3, 0);
  const dish = rp(mesh(new THREE.SphereGeometry(1.3, 24, 12, 0, Math.PI * 2, 0, Math.PI / 2.5), std(0xdfe8ee, 0.6, 0.3)), 0, 4.2, 0.4); dish.rotation.x = Math.PI / 2 + 0.5; dish.material.side = THREE.DoubleSide;
  const relayEyeMat = glow(0xff2a2a, 6);
  const relayEye = rp(mesh(new THREE.SphereGeometry(0.45, 20, 12), relayEyeMat, false, false), 0, 5.9, 0);
  const relayGlow = glowSprite(0xff3030, 3.2, 0.7, true); relayGlow.position.set(0, 5.9, 0); relay.add(relayGlow);
  for (let i = 0; i < 3; i++) { const ring = rp(mesh(new THREE.TorusGeometry(0.7 + i * 0.35, 0.05, 6, 32), glow(0xff4030, 4), false, false), 0, 5.9, 0); ring.rotation.x = Math.PI / 2; }
  addCollider(mx + 1.5, MAST.top + 0.4, mz - 1.5, 2.2, 0.8, 2.2);

  // ---- Crane Yard: the boss arena ----
  railing(yard.minX, yard.minZ, yard.maxX, yard.minZ); railing(yard.minX, yard.minZ, yard.minX, yard.maxZ);
  railing(yard.minX, yard.maxZ, yard.maxX, yard.maxZ);
  railing(yard.maxX, yard.minZ, yard.maxX, -34); railing(yard.maxX, -26, yard.maxX, yard.maxZ); // gap where the rail lands
  const cyc = (yard.minX + yard.maxX) / 2, cyz = (yard.minZ + yard.maxZ) / 2;
  const ringM = add(mesh(new THREE.RingGeometry(6.6, 7, 64), glow(0xffa030, 2), false, false), cyc, 0.015, cyz); ringM.rotation.x = -Math.PI / 2;
  for (const [x, z] of [[-34, -36], [-18, -36], [-34, -20], [-18, -20]]) block(x, z, 2.4, 2.4, 1.6, 0, metalBlue);
  for (const [x, z] of [[-30, -28], [-22, -28]]) block(x, z, 1.2, 3, 1.2, 0, pm);
  crate(-36, 0, -27, 1.3); crate(-16, 0, -38, 1.2); crate(-17, 0, -37.6, 1.0);
  lamp(-37.4, -39.4, 0xff7050); lamp(-14.6, -39.4, 0xff7050); lamp(-37.4, -16.6, 0xff7050); lamp(-14.6, -16.6, 0xff7050);
  label('CRANE YARD', cyc, -17.8, 0, 8, '#ffc7d8');

  // ---- grind rails (built by rails.js); rails 0-2 start locked and open as each area is cleared ----
  const rails = [
    { pts: [[0, 0.45, 25.2], [0.5, 1.6, 18], [5, 3, 12], [13, 3.6, 8], [21, 2.6, 4.5], [25.5, 1.1, 2]], locked: true },
    { pts: [[30, 0.45, -9.2], [30.5, 2.2, -16], [29.5, 4.6, -22], [28.5, 7.1, -27.5], [28, 7.6, -31.6]], locked: true },
    { pts: [[MAST.minX + 1.2, MAST.top + 0.4, -36], [MAST.minX - 4, MAST.top + 0.6, -39], [6, 6.2, -42], [-4, 4.4, -41], [-11, 2.4, -34], [-15.5, 1.0, -30.5]], locked: true },
  ];

  // a few cargo drones parked in the air around the level for scale
  for (let i = 0; i < 10; i++) {
    const g = new THREE.Group(); g.position.set(R(-55, 55), R(-6, 14), R(-60, 55));
    if (Math.abs(g.position.x) < 45 && Math.abs(g.position.z) < 48) continue;
    g.add(mesh(new RoundedBoxGeometry(2.4, 1.2, 1.6, 2, 0.2), [metalTeal, metalWhite, brass][i % 3], false, false));
    G.add(g);
  }

  return {
    bounds: { minX: -42, maxX: 44, minZ: -48, maxZ: 44 },
    decks: [dock, cargo, yard],
    start: { pos: V(0, 0, 35), yaw: Math.PI },
    rails,
    relay: { group: relay, eyeMat: relayEyeMat, glow: relayGlow, eye: relayEye, pos: V(mx + 1.5, MAST.top + 5.9, mz - 1.5), parts: relayParts },
    gizmarts: [{ pos: V(-7.5, 0, 36.5), yaw: Math.PI / 2 }, { pos: V(37.5, 0, -4.5), yaw: -Math.PI / 2 }],
    bossPos: V(cyc, 0, cyz - 1),
  };
}
