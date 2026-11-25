// The hero: a teal alien in an orange flight suit with a jetpack and a two-handed energy blaster.
// Same character as the look test, rebuilt with jointed legs and the blaster pointing straight ahead
// so it can run, jump and aim.
import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { V, std, glow, mesh, limb, glowSprite } from './util.js';
import { mergeByMaterial } from './models.js';

// Blender model (public/models/hero.glb, built by art/hero.py) with named pivots: hip_L/R, knee_L/R, upper, gun,
// muzzle, jet_L/R.
function buildFromModel(model) {
  const root = new THREE.Group();
  const body = new THREE.Group(); root.add(body);
  body.add(model);
  const get = n => model.getObjectByName(n);
  const legs = [['L', 1], ['R', -1]].map(([n, side]) => ({ hip: get('hip_' + n), knee: get('knee_' + n), side }));
  const upper = get('upper'), gun = get('gun'), muzzle = get('muzzle');
  const jets = ['jet_L', 'jet_R'].map(n => { const sp = glowSprite(0x50e8ff, 0.32, 0.7); get(n).add(sp); return sp; });
  // the coils get their own material so they can turn red on overheat without recolouring the jet nozzles
  const coilMat = model.getObjectByName('gun_coil_0').material.clone();
  const coils = [];
  model.traverse(o => { if (o.isMesh && o.name.startsWith('gun_coil')) { o.material = coilMat; coils.push(o); } });
  mergeByMaterial(model);
  return { root, body, upper, legs, jets, coils: coils.length ? [{ material: coilMat }] : [], gun, muzzle };
}

export function createHero(scene, model) {
  const parts = model ? buildFromModel(model) : buildBasic();
  const { root, body, upper, legs, jets, coils, gun, muzzle } = parts;
  scene.add(root);
  const flash = glowSprite(0x80f8ff, 0.9, 0); muzzle.add(flash);
  const flashCore = glowSprite(0xffffff, 0.35, 0); muzzle.add(flashCore);
  const mLight = new THREE.PointLight(0x60f0ff, 0, 5, 2); muzzle.add(mLight);
  const gunZ = gun.position.z;
  // how far the barrel sits to the hero's left, used to turn the body so the barrel points at the crosshair
  root.updateMatrixWorld(true);
  const gunSide = root.worldToLocal(muzzle.getWorldPosition(new THREE.Vector3())).x;
  return animateHero({ root, body, upper, legs, jets, coils, gun, muzzle, flash, flashCore, mLight, gunZ, gunSide });
}

// the original basic-shape hero, used if the model can't load
function buildBasic() {
  const root = new THREE.Group();                            // position + facing (yaw)
  const body = new THREE.Group(); root.add(body);            // bob / lean
  const upper = new THREE.Group(); upper.position.y = 0.72; body.add(upper); // pitches with aim

  const suitMat = new THREE.MeshPhysicalMaterial({ color: 0xff6a1a, roughness: 0.55, sheen: 0.6, sheenColor: 0xffc890, sheenRoughness: 0.6 });
  const suitDark = new THREE.MeshPhysicalMaterial({ color: 0x262b3d, roughness: 0.6, sheen: 0.5, sheenColor: 0x6a8cc0 });
  const plateMat = std(0xeef2f5, 0.55, 0.25, { envMapIntensity: 1.2 });
  const skinMat = new THREE.MeshPhysicalMaterial({ color: 0x58c9b8, roughness: 0.48, sheen: 0.8, sheenColor: 0xb8fff0, sheenRoughness: 0.4, clearcoat: 0.15 });
  const finMat = new THREE.MeshPhysicalMaterial({ color: 0x6b3fd0, roughness: 0.35, clearcoat: 0.6, sheen: 0.4, sheenColor: 0xd0a0ff });
  const bootMat = std(0x2c3038, 0.6, 0.38);
  const gloveMat = std(0x3a3f4a, 0.3, 0.55);
  const brass = std(0xd9a441, 0.9, 0.3);
  const metalBlue = std(0x5f8fb0, 0.7, 0.32);
  const metalDark = std(0x34404c, 0.75, 0.4);
  const cyanGlow = glow(0x40f0ff, 7);
  const soleMat = glow(0x3ff0ff, 2.5);

  // ---- legs: hip pivot -> thigh, knee pivot -> shin + boot ----
  const legs = [];
  for (const s of [1, -1]) {
    const hip = new THREE.Group(); hip.position.set(0.13 * s, 0.66, 0); body.add(hip);
    hip.add(limb(V(0, 0, 0), V(0, -0.28, 0.02), 0.105, suitDark));
    const knee = new THREE.Group(); knee.position.set(0, -0.28, 0.02); hip.add(knee);
    const pad = mesh(new THREE.SphereGeometry(0.085, 20, 12), plateMat); pad.position.set(0, 0, 0.05); pad.scale.set(1, 0.9, 0.7); knee.add(pad);
    knee.add(limb(V(0, 0, 0), V(0, -0.26, -0.01), 0.09, suitDark));
    knee.add(limb(V(0, -0.09, 0), V(0, -0.24, -0.01), 0.1, plateMat));
    const boot = new THREE.Group(); boot.position.set(0, -0.26, -0.01); knee.add(boot);
    const shell = mesh(new RoundedBoxGeometry(0.22, 0.2, 0.36, 4, 0.08), bootMat); shell.position.set(0, -0.03, 0.05); boot.add(shell);
    const cuff = mesh(new THREE.CylinderGeometry(0.11, 0.12, 0.1, 20), plateMat); cuff.position.y = 0.07; boot.add(cuff);
    const sole = mesh(new RoundedBoxGeometry(0.24, 0.05, 0.38, 2, 0.02), soleMat, false, false); sole.position.set(0, -0.125, 0.05); boot.add(sole);
    legs.push({ hip, knee, side: s });
  }

  // ---- torso (in `upper`, whose origin is the waist at y 0.72) ----
  const u = (x, y, z) => V(x, y - 0.72, z);
  const add = (m, p) => { m.position.copy(p); upper.add(m); return m; };
  add(mesh(new RoundedBoxGeometry(0.4, 0.2, 0.26, 4, 0.08), suitDark), u(0, 0.72, 0));
  add(mesh(new RoundedBoxGeometry(0.46, 0.42, 0.3, 5, 0.12), suitDark), u(0, 0.95, 0));
  add(mesh(new RoundedBoxGeometry(0.4, 0.27, 0.1, 4, 0.045), plateMat), u(0.01, 1.0, 0.13));
  const core = add(mesh(new THREE.CylinderGeometry(0.05, 0.05, 0.03, 6), glow(0x40f6ff, 5)), u(0.0, 1.0, 0.19)); core.rotation.x = Math.PI / 2;
  const belt = add(mesh(new THREE.TorusGeometry(0.205, 0.035, 10, 40), std(0x5a3a22, 0.1, 0.6)), u(0, 0.79, 0)); belt.rotation.x = Math.PI / 2; belt.scale.set(1.05, 0.68, 1);
  add(mesh(new RoundedBoxGeometry(0.1, 0.07, 0.03, 2, 0.01), brass), u(0.03, 0.79, 0.14));
  add(mesh(new RoundedBoxGeometry(0.1, 0.11, 0.08, 2, 0.03), std(0x5a3a22, 0.1, 0.6)), u(-0.2, 0.74, 0.06));
  const shL = u(0.27, 1.08, 0.0), shR = u(-0.26, 1.08, 0.02);
  for (const s of [shL, shR]) add(mesh(new THREE.SphereGeometry(0.12, 24, 14, 0, Math.PI * 2, 0, Math.PI / 1.7), suitMat), s.clone().add(V(0, 0.02, 0)));
  // jetpack
  add(mesh(new RoundedBoxGeometry(0.36, 0.38, 0.16, 4, 0.06), plateMat), u(0, 0.97, -0.22));
  const jets = [];
  for (const s of [-1, 1]) {
    add(mesh(new THREE.CylinderGeometry(0.07, 0.09, 0.42, 20), metalBlue), u(0.15 * s, 0.93, -0.3));
    add(mesh(new THREE.CylinderGeometry(0.075, 0.06, 0.04, 20), glow(0x4ff0ff, 6)), u(0.15 * s, 0.7, -0.3));
    const fl = add(glowSprite(0x50e8ff, 0.32, 0.7), u(0.15 * s, 0.66, -0.3)); jets.push(fl);
    const fin = add(mesh(new RoundedBoxGeometry(0.03, 0.22, 0.12, 2, 0.01), plateMat), u(0.24 * s, 1.08, -0.32)); fin.rotation.z = 0.35 * s;
  }
  // neck + head
  add(mesh(new THREE.CylinderGeometry(0.075, 0.09, 0.12, 16), skinMat), u(0, 1.17, 0));
  const collar = add(mesh(new THREE.TorusGeometry(0.11, 0.035, 10, 30), suitDark), u(0, 1.15, 0)); collar.rotation.x = Math.PI / 2;
  const head = new THREE.Group(); head.position.copy(u(0.02, 1.43, 0.03)); head.rotation.set(0.04, 0.12, 0.04); upper.add(head);
  const skull = mesh(new THREE.SphereGeometry(0.29, 48, 32), skinMat); skull.scale.set(1.0, 0.95, 0.98); head.add(skull);
  const jaw = mesh(new THREE.SphereGeometry(0.2, 32, 20), skinMat); jaw.position.set(0, -0.11, 0.08); jaw.scale.set(1.05, 0.8, 1); head.add(jaw);
  const snout = mesh(new THREE.SphereGeometry(0.09, 24, 16), skinMat); snout.position.set(0, -0.07, 0.24); snout.scale.set(1.4, 0.75, 0.9); head.add(snout);
  const nose = mesh(new THREE.SphereGeometry(0.03, 16, 10), std(0x2f6f6a, 0, 0.35)); nose.position.set(0, -0.045, 0.31); nose.scale.set(1.4, 0.8, 1); head.add(nose);
  const eyeWhite = new THREE.MeshPhysicalMaterial({ color: 0xffffff, roughness: 0.1, clearcoat: 1 });
  const irisMat = new THREE.MeshPhysicalMaterial({ color: 0xffa21a, roughness: 0.2, clearcoat: 1, emissive: 0x6a3000, emissiveIntensity: 0.6 });
  const pupilMat = std(0x0a0a10, 0, 0.2);
  for (const s of [-1, 1]) {
    const e = new THREE.Group(); e.position.set(0.105 * s, 0.035, 0.225); e.rotation.y = 0.28 * s; head.add(e);
    const ball = mesh(new THREE.SphereGeometry(0.075, 32, 20), eyeWhite); ball.scale.set(1, 1.15, 0.7); e.add(ball);
    const iris = mesh(new THREE.SphereGeometry(0.045, 24, 16), irisMat); iris.position.set(0.012 - 0.008 * s, -0.004, 0.042); iris.scale.set(1, 1.1, 0.5); e.add(iris);
    const pupil = mesh(new THREE.SphereGeometry(0.024, 16, 12), pupilMat); pupil.position.set(0.013 - 0.008 * s, -0.004, 0.058); pupil.scale.set(1, 1.15, 0.4); e.add(pupil);
    const hl = mesh(new THREE.SphereGeometry(0.009, 10, 8), glow(0xffffff, 4), false, false); hl.position.set(0.028 - 0.008 * s, 0.022, 0.066); e.add(hl);
    const lid = mesh(new THREE.SphereGeometry(0.081, 32, 16, 0, Math.PI * 2, 0, Math.PI * 0.42), skinMat); lid.scale.set(1.05, 1.2, 0.78); lid.rotation.x = -0.25; e.add(lid);
    e.add(limb(V(0.02 * s, 0.1, 0.05), V(0.105 * s, 0.11, 0.02), 0.022, std(0x2c5f6a, 0, 0.7)));
  }
  const smile = mesh(new THREE.TorusGeometry(0.06, 0.009, 8, 24, Math.PI * 0.75), std(0x1c3c3c, 0, 0.6)); smile.position.set(0.02, -0.12, 0.255); smile.rotation.set(0.25, 0.1, Math.PI + 0.55); head.add(smile);
  for (let i = 0; i < 4; i++) {
    const fin = mesh(new THREE.ConeGeometry(0.07 - i * 0.008, 0.34 - i * 0.03, 16), finMat);
    fin.position.set(0, 0.2 - i * 0.05, -0.02 - i * 0.1); fin.rotation.x = -0.75 - i * 0.28; head.add(fin);
  }
  for (const s of [-1, 1]) { const ear = mesh(new THREE.ConeGeometry(0.06, 0.24, 12), finMat); ear.position.set(0.26 * s, 0.04, -0.04); ear.rotation.set(-0.4, 0, -1.25 * s); head.add(ear); }
  const strap = mesh(new THREE.TorusGeometry(0.285, 0.02, 8, 48), std(0x3b2c22, 0.1, 0.6)); strap.rotation.x = Math.PI / 2 - 0.55; strap.position.set(0, 0.14, -0.03); head.add(strap);
  for (const s of [-1, 1]) {
    const gg = new THREE.Group(); gg.position.set(0.09 * s, 0.215, 0.16); gg.rotation.set(-0.95, 0.25 * s, 0); head.add(gg);
    gg.add(mesh(new THREE.TorusGeometry(0.06, 0.02, 10, 24), brass));
    const lens = mesh(new THREE.CircleGeometry(0.058, 24), new THREE.MeshPhysicalMaterial({ color: 0x40d0ff, metalness: 0.2, roughness: 0.02, clearcoat: 1, emissive: 0x0a4060, emissiveIntensity: 0.6 })); lens.position.z = 0.005; gg.add(lens);
  }

  // ---- blaster, held at the hip-chest pointing straight ahead (+z) ----
  const gun = new THREE.Group(); gun.position.copy(u(0.14, 1.0, 0.3)); upper.add(gun);
  gun.add(mesh(new RoundedBoxGeometry(0.17, 0.17, 0.42, 4, 0.05), std(0xf2f4f6, 0.6, 0.3)));
  const gunTop = mesh(new RoundedBoxGeometry(0.1, 0.06, 0.3, 3, 0.02), std(0xff6a1a, 0.3, 0.4)); gunTop.position.set(0, 0.1, 0.02); gun.add(gunTop);
  const barrel = mesh(new THREE.CylinderGeometry(0.045, 0.055, 0.42, 20), metalDark); barrel.rotation.x = Math.PI / 2; barrel.position.set(0, 0.02, 0.38); gun.add(barrel);
  const coils = [];
  for (let i = 0; i < 4; i++) { const coil = mesh(new THREE.TorusGeometry(0.07, 0.016, 10, 24), cyanGlow.clone()); coil.position.set(0, 0.02, 0.24 + i * 0.075); gun.add(coil); coils.push(coil); }
  for (const s of [-1, 1]) { const p = mesh(new RoundedBoxGeometry(0.04, 0.04, 0.18, 2, 0.01), brass); p.position.set(0.075 * s, 0.02, 0.6); p.rotation.y = -0.15 * s; gun.add(p); }
  const tank = mesh(new THREE.CylinderGeometry(0.05, 0.05, 0.2, 16), glow(0x40f0ff, 2.2)); tank.rotation.x = Math.PI / 2; tank.position.set(0, -0.05, -0.08); gun.add(tank);
  const grip = mesh(new RoundedBoxGeometry(0.08, 0.18, 0.09, 2, 0.03), metalDark); grip.position.set(0, -0.14, -0.1); grip.rotation.x = 0.3; gun.add(grip);
  const stock = mesh(new RoundedBoxGeometry(0.1, 0.12, 0.2, 3, 0.03), std(0xff6a1a, 0.3, 0.4)); stock.position.set(0, -0.02, -0.28); gun.add(stock);
  const muzzle = new THREE.Object3D(); muzzle.position.set(0, 0.02, 0.72); gun.add(muzzle);
  // arms reaching the grip and the barrel
  const gp = gun.position;
  const handGrip = gp.clone().add(V(0, -0.13, -0.08)), handFore = gp.clone().add(V(-0.02, -0.04, 0.2));
  const elbL = u(0.34, 0.86, 0.08), elbR = u(-0.14, 0.86, 0.2);
  upper.add(limb(shL, elbL, 0.075, suitMat), limb(elbL, handGrip, 0.068, suitMat), limb(shR, elbR, 0.075, suitMat), limb(elbR, handFore, 0.068, suitMat));
  for (const [e, h] of [[elbL, handGrip], [elbR, handFore]]) {
    upper.add(limb(e.clone().lerp(h, 0.55), e.clone().lerp(h, 0.95), 0.085, gloveMat));
    const fist = mesh(new THREE.SphereGeometry(0.08, 20, 14), gloveMat); fist.position.copy(h); fist.scale.set(1, 0.9, 1.1); upper.add(fist);
  }
  const wrist = mesh(new RoundedBoxGeometry(0.07, 0.04, 0.09, 2, 0.01), glow(0x50ff90, 2.5)); wrist.position.copy(elbR.clone().lerp(handFore, 0.78)).add(V(0, 0.07, 0)); upper.add(wrist);
  return { root, body, upper, legs, jets, coils, gun, muzzle };
}

function animateHero({ root, body, upper, legs, jets, coils, gun, muzzle, flash, flashCore, mLight, gunZ, gunSide }) {

  // collect materials so the whole hero can flash when hit
  const flashables = [];
  root.traverse(o => { if (o.isMesh && o.material && 'emissive' in o.material && o.material.emissiveIntensity < 2) flashables.push(o.material); });
  flashables.forEach(m => { m.userData.baseEmissive = m.emissive.clone(); m.userData.baseEI = m.emissiveIntensity; });

  // ---- animation state ----
  let swingT = 0;
  let phase = 0, flashT = 0, hurtT = 0, t = 0, lean = 0, pitchS = 0, airT = 0;
  const L = (a, b, k, dt) => THREE.MathUtils.lerp(a, b, 1 - Math.exp(-k * dt));
  function animate(dt, { speed, grounded, vy, aimPitch, firing, heat, jetting, turn = 0, landT = 0, aiming = true, dash = false }) {
    t += dt;
    // running cycle: stride gets longer with speed, cadence rises more slowly so it doesn't look frantic
    const run = Math.min(1, speed / 7);
    phase += dt * (3 + speed * 1.15);
    airT = grounded ? 0 : airT + dt;
    for (const Lg of legs) {
      const off = Lg.side > 0 ? 0 : Math.PI;
      const sw = Math.sin(phase + off);
      if (grounded) {
        const hipT = sw * 0.85 * run, kneeT = Math.max(0, -Math.cos(phase + off)) * 1.25 * run + 0.06 + landT * 0.6;
        Lg.hip.rotation.x = L(Lg.hip.rotation.x, hipT - landT * 0.3, 30, dt);
        Lg.knee.rotation.x = L(Lg.knee.rotation.x, kneeT, 30, dt);
      } else if (dash) {
        // long jump / dash: legs stretched out behind
        Lg.hip.rotation.x = L(Lg.hip.rotation.x, Lg.side > 0 ? 0.5 : 0.9, 14, dt);
        Lg.knee.rotation.x = L(Lg.knee.rotation.x, Lg.side > 0 ? 0.3 : 0.9, 14, dt);
      } else {
        // rising: one knee up; falling: legs reach down for the landing
        const up = vy > 0;
        Lg.hip.rotation.x = L(Lg.hip.rotation.x, up ? (Lg.side > 0 ? -0.8 : 0.35) : (Lg.side > 0 ? -0.25 : 0.1), 10, dt);
        Lg.knee.rotation.x = L(Lg.knee.rotation.x, up ? (Lg.side > 0 ? 1.3 : 0.5) : 0.35, 10, dt);
      }
    }
    // body: bob with the stride, lean forward with speed, bank into turns, squash on landing, breathe when still
    const breathe = (1 - run) * Math.sin(t * 2.2) * 0.012;
    body.position.y = grounded ? Math.abs(Math.sin(phase)) * 0.07 * run - landT * 0.12 + breathe : 0;
    const wantPitch = grounded ? run * (aiming ? 0.08 : 0.2) + landT * 0.25 : dash ? 0.5 : THREE.MathUtils.clamp(-vy * 0.02, -0.15, 0.2);
    pitchS = L(pitchS, wantPitch, 12, dt);
    body.rotation.x = pitchS;
    lean = L(lean, THREE.MathUtils.clamp(-turn * 0.09 * Math.max(run, 0.3), -0.35, 0.35), 10, dt);
    body.rotation.z = lean;
    body.scale.set(1 + landT * 0.12, 1 - landT * 0.14 + (!grounded && vy > 4 ? 0.05 : 0), 1 + landT * 0.12);
    upper.rotation.x = L(upper.rotation.x, THREE.MathUtils.clamp(-aimPitch, -0.75, 0.6) - (aiming ? 0 : pitchS * 0.5), aiming ? 30 : 10, dt);
    upper.rotation.z = grounded ? Math.sin(phase) * 0.05 * run : 0;
    upper.rotation.y = grounded && !aiming ? Math.sin(phase) * 0.12 * run : L(upper.rotation.y, 0, 10, dt);
    // melee: wind up to the right, then whip the blaster across to the left
    if (swingT > 0) {
      swingT = Math.max(0, swingT - dt); const k = 1 - swingT / 0.32;
      upper.rotation.y = k < 0.25 ? -0.9 * (k / 0.25) : -0.9 + 2.0 * Math.min(1, (k - 0.25) / 0.3);
      upper.rotation.x = -0.1;
    }
    // jetpack flames grow when hovering
    jets.forEach(j => { const s = jetting ? 0.7 + Math.random() * 0.3 : 0.3; j.scale.setScalar(s); j.material.opacity = jetting ? 1 : 0.6; });
    // muzzle flash fade
    flashT = Math.max(0, flashT - dt * 14);
    flash.material.opacity = flashT; flashCore.material.opacity = flashT;
    flash.scale.setScalar(0.6 + flashT * 0.5);
    mLight.intensity = flashT * 8;
    gun.position.z = gunZ - flashT * 0.04; // recoil
    // coils dim as the cell heats up / drains
    coils.forEach((c, i) => { c.material.emissiveIntensity = heat ? 1.5 : 7; c.material.emissive.setHex(heat ? 0xff5030 : 0x40f0ff); });
    // hurt flash
    hurtT = Math.max(0, hurtT - dt * 4);
    flashables.forEach(m => { m.emissive.copy(m.userData.baseEmissive).lerp(new THREE.Color(0xff2020), hurtT); m.emissiveIntensity = m.userData.baseEI + hurtT * 1.5; });
  }

  return {
    root, upper, muzzle, gun, animate, gunSide,
    fireFlash() { flashT = 1; },
    swing() { swingT = 0.32; },
    hurt() { hurtT = 1; },
  };
}
