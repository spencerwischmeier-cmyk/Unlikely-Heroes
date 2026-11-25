// Skyharbor, the first story level: floating islands above the sky city, joined by stepping pads, moving
// platforms, swing hooks and grind rails.
//   Dockside (start, Gizmart) -> sky steps (pads + a moving platform) -> Market Terrace (fight) -> bounce pad up
//   to the lookout -> two swing hooks across the gap -> Cargo Yard (fight, Gizmart) -> rail up -> Signal Mast
//   (relay) -> rail down -> Fan Gardens (fight) -> moving platform -> swing hook -> Crane Yard (boss)
// Floors at height 0 are "decks" (islands); everything raised is a collider box. Fall and you go back to the
// last checkpoint.
import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { V, std, glow, mesh, glowSprite, R } from './util.js';

const rect = (cx, cz, w, d) => ({ minX: cx - w / 2, maxX: cx + w / 2, minZ: cz - d / 2, maxZ: cz + d / 2 });
export const ISLANDS = {
  dock: rect(0, 62, 34, 24),
  terrace: rect(0, 4, 30, 24),
  cargo: rect(12, -56, 32, 24),
  gardens: rect(-30, -96, 22, 20),
  yard: rect(-58, -130, 30, 30),
};
export const MAST = { ...rect(12, -96, 14, 14), top: 8 };

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

  const { dock, terrace, cargo, gardens, yard } = ISLANDS;
  island(dock); island(terrace, 0xf4ecdf); island(cargo, 0xe8f0f6); island(gardens, 0xdcefe4); island(yard, 0xd8dde2);

  // ---- Dockside: moored sky barges, bollards, cargo and lamps ----
  railing(dock.minX, dock.maxZ, dock.maxX, dock.maxZ);
  railing(dock.minX, dock.minZ, -2.5, dock.minZ); railing(2.5, dock.minZ, dock.maxX, dock.minZ); // gap for the sky steps
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
  barge(dock.minX - 2.6, 66, Math.PI / 2); barge(dock.maxX + 2.6, 58, -Math.PI / 2, 0x3f9fa0); barge(dock.minX - 2.6, 54, Math.PI / 2, 0x8a5ad0);
  for (const [x, z] of [[-16.4, 52], [-16.4, 72], [16.4, 52], [16.4, 72]]) { add(mesh(new THREE.CylinderGeometry(0.3, 0.38, 0.7, 12), brass), x, 0.35, z); addCollider(x, 0.35, z, 0.7, 0.7, 0.7); }
  crate(10, 0, 71, 1.2); crate(11.2, 0, 71.2, 1.1); crate(10.6, 0.96, 71.1, 1.0); crate(-6, 0, 53.5, 1.2);
  block(8.5, 57, 3, 2, 1.1, 0, metalBlue);
  block(-9, 60, 5, 3, 1.4, 0, metalBlue); block(-9, 60, 3, 3, 1.2, 1.4, metalTeal); // a two-step stack to hop up
  lamp(-16, 63); lamp(16, 63); lamp(-3.5, 50.6, 0x60f0ff); lamp(3.5, 50.6, 0x60f0ff);
  label('SKYHARBOR DOCKS', 0, 64, 0, 12, '#ffe7a0');
  // a dock crane arm (scenery)
  add(mesh(new THREE.CylinderGeometry(0.35, 0.5, 7, 10), metalDark), 14, 3.5, 66);
  const arm = add(mesh(new RoundedBoxGeometry(0.5, 0.5, 8, 2, 0.1), brass), 14, 7, 62.4); arm.rotation.x = -0.15;
  addCollider(14, 3.5, 66, 0.9, 7, 0.9);

  // ---- Sky steps: floating pads (tops at deck height) and one moving platform ----
  const padTop = std(0xbcd0dc, 0.7, 0.35, { map: deckTex });
  const skyPad = (x, z, w, d) => {
    block(x, z, w, d, 0.6, -0.6, padTop);
    add(mesh(new THREE.ConeGeometry(Math.min(w, d) * 0.45, 2.2, 6), metalDark, false, false), x, -1.7, z).rotation.x = Math.PI;
    add(mesh(new THREE.SphereGeometry(0.3, 12, 8), glow(0x40f0ff, 4), false, false), x, -2.9, z);
  };
  skyPad(0, 45.5, 4.5, 4.5); skyPad(3, 39.2, 4.5, 4.5); skyPad(2, 19.3, 5, 3.4);
  label('SKY STEPS', 0, 45.5, 0, 3.6, '#bff9ff');

  // ---- Market Terrace: stalls and awnings, plenty of crates to smash ----
  railing(terrace.minX, terrace.minZ, terrace.minX, terrace.maxZ); railing(terrace.maxX, terrace.minZ, terrace.maxX, terrace.maxZ);
  railing(terrace.minX, terrace.maxZ, -1, terrace.maxZ); railing(5, terrace.maxZ, terrace.maxX, terrace.maxZ);
  railing(terrace.minX, terrace.minZ, 5, terrace.minZ);
  const awnings = [0xff6a4a, 0x4ab0ff, 0xffc040, 0x7ad06a];
  const stall = (x, z, rotY, c) => {
    const g = new THREE.Group(); g.position.set(x, 0, z); g.rotation.y = rotY; G.add(g);
    const counter = mesh(new RoundedBoxGeometry(3.2, 1.1, 1.2, 2, 0.1), metalWhite); counter.position.y = 0.55; g.add(counter);
    for (const s of [-1, 1]) { const pole = mesh(new THREE.CylinderGeometry(0.06, 0.06, 2.6, 8), metalDark); pole.position.set(1.5 * s, 1.3, -0.5); g.add(pole); }
    const aw = mesh(new RoundedBoxGeometry(3.6, 0.15, 1.8, 2, 0.06), std(c, 0.2, 0.5)); aw.position.set(0, 2.6, 0.1); aw.rotation.x = 0.25; g.add(aw);
    for (let i = 0; i < 3; i++) { const gd = mesh(new THREE.SphereGeometry(0.18, 10, 8), glow(awnings[(i + 1) % 4], 1.4), false, false); gd.position.set(-0.9 + i * 0.9, 1.25, 0); g.add(gd); }
    const sx = Math.abs(Math.cos(rotY)) > 0.5 ? 3.2 : 1.2, sz = Math.abs(Math.cos(rotY)) > 0.5 ? 1.2 : 3.2;
    addCollider(x, 0.55, z, sx, 1.1, sz);
  };
  stall(-10, 12, 0, awnings[0]); stall(-10, 2, Math.PI / 2, awnings[1]); stall(-4, -4, 0, awnings[2]); stall(11, 10, Math.PI, awnings[3]);
  add(mesh(new THREE.CylinderGeometry(2, 2.3, 0.8, 24), metalTeal), 1, 0.4, 5); addCollider(1, 0.4, 5, 3.6, 0.8, 3.6); // fountain
  const fountain = add(mesh(new THREE.CylinderGeometry(1.7, 1.7, 0.1, 24), glow(0x60e0ff, 1.5), false, false), 1, 0.82, 5);
  lamp(-14, -7, 0xffd080); lamp(14, -7, 0xffd080); lamp(-14, 15, 0xffd080); lamp(14, 15, 0xffd080);
  label('MARKET TERRACE', 0, -2, 0, 9, '#ffe7a0');
  // the lookout: a tall block at the north edge, reached by the bounce pad
  block(10, -11, 6, 6, 6, 0, std(0x9fb2c2, 0.7, 0.35, { map: deckTex }));
  add(mesh(new THREE.CylinderGeometry(0.08, 0.08, 3, 8), metalWhite), 12.4, 7.5, -13.4);
  add(mesh(new THREE.PlaneGeometry(1.2, 0.7), new THREE.MeshStandardMaterial({ color: 0x40e0ff, side: THREE.DoubleSide, emissive: 0x0a4050 })), 13.0, 8.6, -13.4);

  // ---- Cargo Yard: container stacks to fight around ----
  railing(cargo.maxX, cargo.minZ, cargo.maxX, cargo.maxZ); railing(cargo.minX, cargo.minZ, cargo.minX, cargo.maxZ);
  railing(cargo.minX, cargo.minZ, 10, cargo.minZ); railing(14, cargo.minZ, cargo.maxX, cargo.minZ);
  const boxMats = [std(0xd2462e, 0.5, 0.45), std(0x2e7fd2, 0.5, 0.45), std(0xe8b22a, 0.5, 0.45), std(0x3aa57a, 0.5, 0.45)];
  const container = (x, z, rotY, y0, m) => {
    const sx = rotY ? 2.4 : 5, sz = rotY ? 5 : 2.4;
    const c = add(mesh(new RoundedBoxGeometry(sx, 2.5, sz, 2, 0.08), m), x, y0 + 1.25, z);
    for (let i = -2; i <= 2; i++) { const rib = mesh(new THREE.BoxGeometry(rotY ? sx + 0.06 : 0.12, 2.3, rotY ? 0.12 : sz + 0.06), metalDark); rib.position.set(rotY ? 0 : i * 1.1, 0, rotY ? i * 1.1 : 0); c.add(rib); }
    addCollider(x, y0 + 1.25, z, sx, 2.5, sz);
  };
  container(2, -60, 0, 0, boxMats[0]); container(2, -60, 0, 2.5, boxMats[2]);
  container(22, -52, 1, 0, boxMats[1]); container(9, -50, 0, 0, boxMats[3]);
  container(20, -63, 0, 0, boxMats[2]); container(20, -63, 0, 2.5, boxMats[1]); container(-1, -48, 1, 0, boxMats[3]);
  lamp(-3.4, -67.4); lamp(27.4, -45); lamp(10, -67.6, 0x60f0ff); lamp(14, -67.6, 0x60f0ff);
  label('CARGO YARD', 12, -46.5, 0, 9, '#bff9ff');

  // ---- Signal Mast: a tall tower; its roof is a raised platform with Grudd's signal relay on top ----
  const mw = MAST.maxX - MAST.minX, mx = (MAST.minX + MAST.maxX) / 2, mz = (MAST.minZ + MAST.maxZ) / 2;
  block(mx, mz, mw, mw, 28, MAST.top - 28, std(0x9fb2c2, 0.7, 0.35, { map: deckTex }));
  add(mesh(new THREE.CylinderGeometry(4.5, 5.5, 80, 12), metalDark, false, false), mx, MAST.top - 68, mz);
  for (const y of [-2, -9, -16]) add(mesh(new THREE.TorusGeometry(mw * 0.62, 0.25, 8, 40), warmGlow, false, false), mx, MAST.top + y, mz).rotation.x = Math.PI / 2;
  // low parapet on the east side
  const pm = std(0x34404c, 0.75, 0.4);
  block(MAST.maxX - 0.25, mz, 0.5, mw, 0.9, MAST.top, pm, false);
  block(mx + 2, MAST.minZ + 0.25, mw - 4, 0.5, 0.9, MAST.top, pm, false);
  // the relay itself is not merged so the story can blow it up
  const relay = new THREE.Group(); relay.position.set(mx + 2, MAST.top, mz - 2); relay.userData.dynamic = true; G.add(relay);
  const relayParts = [];
  const rp = (m, x, y, z) => { m.position.set(x, y, z); m.userData.dynamic = true; relay.add(m); relayParts.push(m); return m; };
  rp(mesh(new THREE.CylinderGeometry(0.9, 1.2, 0.8, 16), metalDark), 0, 0.4, 0);
  rp(mesh(new THREE.CylinderGeometry(0.18, 0.3, 5, 10), metalWhite), 0, 3.3, 0);
  const dish = rp(mesh(new THREE.SphereGeometry(1.3, 24, 12, 0, Math.PI * 2, 0, Math.PI / 2.5), std(0xdfe8ee, 0.6, 0.3)), 0, 4.2, 0.4); dish.rotation.x = Math.PI / 2 + 0.5; dish.material.side = THREE.DoubleSide;
  const relayEyeMat = glow(0xff2a2a, 6);
  const relayEye = rp(mesh(new THREE.SphereGeometry(0.45, 20, 12), relayEyeMat, false, false), 0, 5.9, 0);
  const relayGlow = glowSprite(0xff3030, 3.2, 0.7, true); relayGlow.position.set(0, 5.9, 0); relay.add(relayGlow);
  for (let i = 0; i < 3; i++) { const ring = rp(mesh(new THREE.TorusGeometry(0.7 + i * 0.35, 0.05, 6, 32), glow(0xff4030, 4), false, false), 0, 5.9, 0); ring.rotation.x = Math.PI / 2; }
  addCollider(mx + 2, MAST.top + 0.4, mz - 2, 2.2, 0.8, 2.2);

  // ---- Fan Gardens: planters and big turbine fans ----
  railing(gardens.minX, gardens.maxZ, gardens.maxX, gardens.maxZ); railing(gardens.minX, gardens.minZ, gardens.maxX, gardens.minZ);
  railing(gardens.maxX, gardens.minZ, gardens.maxX, -98); railing(gardens.maxX, -94, gardens.maxX, gardens.maxZ); // gap where the rail lands
  railing(gardens.minX, gardens.minZ, gardens.minX, -98.5); railing(gardens.minX, -93.5, gardens.minX, gardens.maxZ); // gap to the moving platform
  const leaf = std(0x4fb86a, 0, 0.7), leaf2 = std(0x7ad06a, 0, 0.7), soil = std(0x6a4a30, 0, 0.9);
  const planter = (x, z, w, d) => {
    block(x, z, w, d, 0.8, 0, metalWhite, false);
    add(mesh(new THREE.BoxGeometry(w - 0.3, 0.1, d - 0.3), soil, false, false), x, 0.82, z);
    for (let i = 0; i < Math.round(w * d / 2); i++) {
      const b = add(mesh(new THREE.IcosahedronGeometry(R(0.35, 0.7), 0), i % 2 ? leaf : leaf2), x + R(-w / 2 + 0.5, w / 2 - 0.5), 1.05, z + R(-d / 2 + 0.5, d / 2 - 0.5)); b.scale.y = R(0.8, 1.4);
    }
  };
  planter(-35, -90, 4, 2.4); planter(-25, -102, 4, 2.4); planter(-36, -102, 2.4, 4); planter(-23, -89, 2.4, 3);
  const fans = [];
  const fan = (x, z, r) => {
    add(mesh(new THREE.CylinderGeometry(r * 0.2, r * 0.3, 9, 10), metalDark, false, false), x, -1, z);
    const hub = new THREE.Group(); hub.position.set(x, 3.6, z); hub.userData.dynamic = true; G.add(hub);
    for (let i = 0; i < 3; i++) { const bl = mesh(new RoundedBoxGeometry(r, 0.12, r * 0.28, 2, 0.05), metalWhite, false, false); bl.position.x = r * 0.5; const piv = new THREE.Group(); piv.rotation.y = i * Math.PI * 2 / 3; piv.add(bl); bl.rotation.x = 0.35; hub.add(piv); }
    hub.add(mesh(new THREE.SphereGeometry(r * 0.16, 12, 8), brass, false, false));
    hub.traverse(o => { o.userData.dynamic = true; });
    fans.push(hub); addCollider(x, 1.5, z, r * 0.45, 3, r * 0.45);
  };
  fan(-30, -96, 4.5);
  lamp(-40.4, -105.4, 0x9dff9a); lamp(-19.6, -105.4, 0x9dff9a); lamp(-40.4, -86.6, 0x9dff9a); lamp(-19.6, -86.6, 0x9dff9a);
  label('FAN GARDENS', -30, -88.5, 0, 7, '#c8ffd0');
  skyPad(-58, -97, 6, 6);

  // ---- Crane Yard: the boss arena ----
  railing(yard.minX, yard.minZ, yard.maxX, yard.minZ); railing(yard.minX, yard.minZ, yard.minX, yard.maxZ);
  railing(yard.maxX, yard.minZ, yard.maxX, yard.maxZ);
  const cyc = (yard.minX + yard.maxX) / 2, cyz = (yard.minZ + yard.maxZ) / 2;
  const ringM = add(mesh(new THREE.RingGeometry(6.6, 7, 64), glow(0xffa030, 2), false, false), cyc, 0.015, cyz); ringM.rotation.x = -Math.PI / 2;
  for (const [dx, dz] of [[-9, -9], [9, -9], [-9, 9], [9, 9]]) block(cyc + dx, cyz + dz, 2.4, 2.4, 1.6, 0, metalBlue);
  for (const dx of [-5, 5]) block(cyc + dx, cyz, 1.2, 3, 1.2, 0, pm);
  crate(cyc - 12, 0, cyz + 1, 1.3); crate(cyc + 11, 0, cyz - 11, 1.2); crate(cyc + 12, 0, cyz - 10.6, 1.0);
  for (const [dx, dz] of [[-1, -1], [1, -1], [-1, 1], [1, 1]]) lamp(cyc + dx * 14.6, cyz + dz * 14.6, 0xff7050);
  label('CRANE YARD', cyc, yard.maxZ - 2.5, 0, 8, '#ffc7d8');

  // ---- grind rails (built by rails.js); they start locked and open as each area is cleared ----
  const rails = [
    { pts: [[12, 0.45, -67.6], [12.5, 2.2, -73], [11.5, 4.6, -79], [12.5, 7.4, -85], [12, 8.6, -88.6]], locked: true },
    { pts: [[MAST.minX + 1.2, MAST.top + 0.4, -96], [MAST.minX - 4, MAST.top + 0.6, -99], [-4, 6.6, -101], [-12, 4, -97], [-17, 1.8, -95.5], [-19.6, 1.0, -96]], locked: true },
  ];

  // moving platforms: { size, from, to, period (s) }; swing hooks: points you can grab with the hook
  const movers = [
    { size: [4.5, 0.6, 4.5], from: V(3, -0.3, 33), to: V(3, -0.3, 25.5), period: 5.5 },
    { size: [4.5, 0.6, 4.5], from: V(-45, -0.3, -96), to: V(-52.5, -0.3, -96), period: 5 },
  ];
  const hooks = [V(10, 12.5, -21), V(10, 12.5, -35), V(-58, 11, -107)];
  const bouncers = [{ pos: V(10, 0, -4), power: 19 }];
  // nut crates you can smash (pos is the floor under them)
  const nutCrates = [
    V(-12, 0, 68), V(-12.9, 0, 68.4), V(5, 0, 52), V(0, 0, 45.5),
    V(-12, 0, -6), V(-11, 0, -6.4), V(13, 0, 2), V(-2, 0, 14), V(10, 6, -9.5),
    V(26, 0, -66), V(25, 0, -66.3), V(-2, 0, -66), V(2, 5, -60),
    V(-38, 0, -88), V(-21.5, 0, -104), V(-58, 0, -97),
    V(cyc - 13, 0, cyz + 12), V(cyc + 13, 0, cyz + 12),
  ];
  // touch these to set where you come back after a fall
  const checkpoints = [
    { pos: V(0, 0, 45.5), r: 2.4 }, { pos: V(10, 6, -11), r: 3 }, { pos: V(-58, 0, -97), r: 3 },
  ];

  // a few cargo drones parked in the air around the level for scale
  for (let i = 0; i < 16; i++) {
    const g = new THREE.Group(); g.position.set(R(-90, 60), R(-6, 14), R(-160, 90));
    if (g.position.x > -80 && g.position.x < 45 && g.position.z > -150 && g.position.z < 80) continue;
    g.add(mesh(new RoundedBoxGeometry(2.4, 1.2, 1.6, 2, 0.2), [metalTeal, metalWhite, brass][i % 3], false, false));
    G.add(g);
  }

  return {
    bounds: { minX: -78, maxX: 46, minZ: -152, maxZ: 80 },
    decks: [dock, terrace, cargo, gardens, yard],
    start: { pos: V(0, 0, 70), yaw: Math.PI },
    rails, movers, hooks, bouncers, nutCrates, checkpoints, fans, fountain,
    relay: { group: relay, eyeMat: relayEyeMat, glow: relayGlow, eye: relayEye, pos: V(mx + 2, MAST.top + 5.9, mz - 2), parts: relayParts },
    gizmarts: [{ pos: V(-12, 0, 64.5), yaw: Math.PI / 2 }, { pos: V(26.5, 0, -50), yaw: -Math.PI / 2 }],
    bossPos: V(cyc, 0, cyz - 1),
  };
}
