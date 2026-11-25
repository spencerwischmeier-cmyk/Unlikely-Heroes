// The setting: sky, sunlight, the floating sky-city and the arena deck the hero fights on.
// Built from the look test scene, extended so the city surrounds the arena on every side.
import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { rnd, R, V, UP, std, glow, mesh, canvasTex, glowSprite } from './util.js';

export const ARENA = { minX: -14, maxX: 14, minZ: -11, maxZ: 11 };

export function createWorld(renderer, scene, { lq = false } = {}) {
  const FOG = new THREE.Color().setRGB(0.33, 0.6, 0.76);
  scene.fog = new THREE.FogExp2(FOG, 0.0042);
  const colliders = []; // axis-aligned boxes: { min: Vector3, max: Vector3 }
  const addCollider = (cx, cy, cz, sx, sy, sz) => colliders.push({ min: V(cx - sx / 2, cy - sy / 2, cz - sz / 2), max: V(cx + sx / 2, cy + sy / 2, cz + sz / 2) });

  // ---------- sky ----------
  const SUN_DIR = V(-0.32, 0.42, -1).normalize();
  const skyMat = new THREE.ShaderMaterial({
    side: THREE.BackSide, depthWrite: false, fog: false,
    uniforms: { sunDir: { value: SUN_DIR } },
    vertexShader: `varying vec3 vDir; void main(){ vDir = normalize(position); gl_Position = projectionMatrix*modelViewMatrix*vec4(position,1.); gl_Position.z = gl_Position.w; }`,
    fragmentShader: `varying vec3 vDir; uniform vec3 sunDir;
      void main(){
        float h = clamp(vDir.y, -0.2, 1.0);
        vec3 zen = vec3(0.02,0.13,0.36), mid = vec3(0.08,0.33,0.62), hor = vec3(0.33,0.60,0.76);
        vec3 c = mix(hor, mid, smoothstep(0.0, 0.12, h));
        c = mix(c, zen, smoothstep(0.1, 0.5, h));
        float s = max(dot(normalize(vDir), sunDir), 0.0);
        c += vec3(1.0,0.92,0.75) * (pow(s, 12.0)*0.25 + pow(s, 120.0)*0.8 + pow(s, 1500.0)*5.5);
        c = mix(c, hor*1.02, smoothstep(0.02, -0.15, vDir.y));
        gl_FragColor = vec4(c,1.);
      }`
  });
  const sky = new THREE.Mesh(new THREE.SphereGeometry(2000, 48, 24), skyMat);
  sky.renderOrder = -10; sky.frustumCulled = false;
  scene.add(sky);

  const pmrem = new THREE.PMREMGenerator(renderer);
  const envScene = new THREE.Scene();
  envScene.add(new THREE.Mesh(new THREE.SphereGeometry(100, 32, 16), skyMat.clone()));
  const envGround = new THREE.Mesh(new THREE.CircleGeometry(90, 32), new THREE.MeshBasicMaterial({ color: 0x35505c }));
  envGround.rotation.x = -Math.PI / 2; envGround.position.y = -20; envScene.add(envGround);
  scene.environment = pmrem.fromScene(envScene, 0.02).texture;
  scene.environmentIntensity = 0.85;

  const cloudTex = canvasTex(512, 256, (g, w, h) => {
    for (let i = 0; i < 260; i++) {
      const x = w * 0.5 + (rnd() - 0.5) * w * 0.8 * (1 - rnd() * 0.3), y = h * 0.62 - Math.pow(rnd(), 1.6) * h * 0.45 + (rnd() - 0.5) * 20;
      const r = R(14, 52) * (1 - Math.abs(x - w / 2) / w);
      const gr = g.createRadialGradient(x, y, 0, x, y, r);
      const shade = Math.floor(R(215, 255));
      gr.addColorStop(0, `rgba(${shade},${shade},${Math.min(255, shade + 8)},.20)`); gr.addColorStop(1, 'rgba(255,255,255,0)');
      g.fillStyle = gr; g.beginPath(); g.arc(x, y, r, 0, 7); g.fill();
    }
  });
  for (let i = 0; i < 48; i++) {
    const s = new THREE.Sprite(new THREE.SpriteMaterial({ map: cloudTex, transparent: true, depthWrite: false, fog: false, opacity: R(0.55, 0.95), color: new THREE.Color().setHSL(0.55, 0.25, R(0.88, 1.0)) }));
    const ang = R(0, Math.PI * 2), dist = R(900, 1500);
    s.position.set(Math.sin(ang) * dist, R(80, 520) + dist * 0.06, -Math.cos(ang) * dist);
    s.scale.set(R(500, 900), R(180, 320), 1);
    s.renderOrder = -5; scene.add(s);
  }
  const sunSprite = glowSprite(0xfff0d0, 140, 0.35); sunSprite.position.copy(SUN_DIR).multiplyScalar(1500); sunSprite.renderOrder = -4; scene.add(sunSprite);

  // ---------- lights ----------
  scene.add(new THREE.HemisphereLight(0xbfe6ff, 0x4a5a66, 0.9));
  const sun = new THREE.DirectionalLight(0xffe2b8, 4.2);
  sun.castShadow = true; sun.shadow.mapSize.set(lq ? 1024 : 2048, lq ? 1024 : 2048);
  Object.assign(sun.shadow.camera, { left: -16, right: 16, top: 16, bottom: -16, near: 1, far: 120 });
  sun.shadow.camera.updateProjectionMatrix();
  sun.shadow.bias = -0.0003; sun.shadow.normalBias = 0.02; sun.shadow.radius = 4;
  scene.add(sun, sun.target);
  const fill = new THREE.DirectionalLight(0xa8d8ff, 1.2); fill.position.set(-3, 3, 8); scene.add(fill);
  const kick = new THREE.DirectionalLight(0xffb070, 1.0); kick.position.set(6, 2, 3); scene.add(kick);

  // ---------- building textures ----------
  function windowTex(hue) {
    return canvasTex(256, 512, (g, w, h) => {
      g.fillStyle = '#1b2a3a'; g.fillRect(0, 0, w, h);
      for (let y = 8; y < h; y += 24) for (let x = 6; x < w; x += 18) {
        if (rnd() < 0.45) continue;
        const warm = rnd() < 0.55;
        g.fillStyle = warm ? `hsl(${R(30, 45)},90%,${R(60, 78)}%)` : `hsl(${hue},85%,${R(60, 80)}%)`;
        g.globalAlpha = R(0.5, 1); g.fillRect(x, y, 11, 13);
      }
      g.globalAlpha = 1; g.fillStyle = '#9fd8ff'; for (let y = 0; y < h; y += 96) g.fillRect(0, y, w, 3);
    });
  }
  const winTexA = windowTex(190), winTexB = windowTex(170);
  [winTexA, winTexB].forEach(t => { t.wrapS = t.wrapT = THREE.RepeatWrapping; });
  const panelTex = canvasTex(512, 512, (g, w, h) => {
    g.fillStyle = '#8e9aa6'; g.fillRect(0, 0, w, h);
    for (let i = 0; i < 2500; i++) { g.fillStyle = `rgba(${rnd() < .5 ? 0 : 255},${rnd() < .5 ? 0 : 255},255,${R(0.01, 0.04)})`; g.fillRect(R(0, w), R(0, h), R(2, 40), R(1, 3)); }
    g.strokeStyle = '#4c5560'; g.lineWidth = 4;
    for (let i = 0; i <= 4; i++) { g.beginPath(); g.moveTo(i * 128, 0); g.lineTo(i * 128, h); g.stroke(); g.beginPath(); g.moveTo(0, i * 128); g.lineTo(w, i * 128); g.stroke(); }
    g.fillStyle = '#c5ced6';
    for (let i = 0; i < 4; i++) for (let j = 0; j < 4; j++) [[10, 10], [118, 10], [10, 118], [118, 118]].forEach(([a, b]) => { g.beginPath(); g.arc(i * 128 + a, j * 128 + b, 3.5, 0, 7); g.fill(); });
  });
  panelTex.wrapS = panelTex.wrapT = THREE.RepeatWrapping;
  const hazardTex = canvasTex(256, 32, (g, w, h) => {
    g.fillStyle = '#ffb21a'; g.fillRect(0, 0, w, h); g.fillStyle = '#1d1d22';
    for (let x = -h; x < w + h; x += 32) { g.beginPath(); g.moveTo(x, h); g.lineTo(x + 16, h); g.lineTo(x + 16 + h, 0); g.lineTo(x + h, 0); g.fill(); }
  });
  hazardTex.wrapS = THREE.RepeatWrapping;

  // ---------- city ----------
  const city = new THREE.Group(); scene.add(city);
  const metalWhite = std(0xdfe8ee, 0.65, 0.28);
  const metalBlue = std(0x5f8fb0, 0.7, 0.32);
  const metalTeal = std(0x3f9fa0, 0.6, 0.35);
  const metalDark = std(0x34404c, 0.75, 0.4);
  const brass = std(0xd9a441, 0.9, 0.3);
  const domeGlass = new THREE.MeshPhysicalMaterial({ color: 0x9fe3ff, metalness: 0.2, roughness: 0.05, clearcoat: 1, emissive: 0x1a6a8a, emissiveIntensity: 0.25 });
  const cyanGlow = glow(0x40f0ff, 7), warmGlow = glow(0xffa030, 6);
  const towerMats = new Map();
  function windowMat(tex, rep, base) {
    const key = `${tex.uuid}|${rep}|${base}`;
    if (towerMats.has(key)) return towerMats.get(key);
    const t = tex.clone(); t.needsUpdate = true; t.repeat.set(rep[0], rep[1]);
    const m = std(base, 0.4, 0.45, { map: t, emissiveMap: t, emissive: 0xffffff, emissiveIntensity: 1.1 });
    towerMats.set(key, m); return m;
  }
  function tower(x, z, s, bottom = -160) {
    const g = new THREE.Group(); g.position.set(x, 0, z);
    const r = R(4, 9) * s, top = R(10, 55) * s;
    const type = Math.floor(rnd() * 4);
    const h = top - bottom;
    const seg = lq ? 16 : 32;
    const shaft = mesh(new THREE.CylinderGeometry(r, r * R(1, 1.25), h, seg, 1), windowMat(rnd() < .5 ? winTexA : winTexB, [Math.round(r * 1.4), Math.round(h / 7)], [0xb8cfe0, 0x9fc4d8, 0xd6e2ea][Math.floor(rnd() * 3)]), false, false);
    shaft.position.y = bottom + h / 2; g.add(shaft);
    for (let y = top - R(4, 10); y > bottom + 20; y -= R(10, 22)) {
      const band = mesh(new THREE.CylinderGeometry(r * 1.06, r * 1.06, R(0.6, 1.8) * s, seg), rnd() < .3 ? brass : metalWhite, false, false); band.position.y = y; g.add(band);
    }
    if (type === 0) {
      const dome = mesh(new THREE.SphereGeometry(r * 1.02, 40, 20, 0, Math.PI * 2, 0, Math.PI / 2), domeGlass, false, false); dome.position.y = top; g.add(dome);
      const ring = mesh(new THREE.TorusGeometry(r * 1.7, r * 0.09, 12, 64), metalWhite, false, false); ring.rotation.x = Math.PI / 2 + R(-.15, .15); ring.position.y = top - r * 0.4; g.add(ring);
      const ringGlow = mesh(new THREE.TorusGeometry(r * 1.7, r * 0.025, 8, 64), cyanGlow, false, false); ringGlow.rotation.copy(ring.rotation); ringGlow.position.y = ring.position.y - r * 0.08; g.add(ringGlow);
    } else if (type === 1) {
      const cap = mesh(new THREE.CylinderGeometry(r * 1.5, r * 0.9, r * 0.9, 32), metalBlue, false, false); cap.position.y = top + r * 0.45; g.add(cap);
      const spire = mesh(new THREE.ConeGeometry(r * 0.35, r * R(4, 8), 16), metalWhite, false, false); spire.position.y = top + r * 0.9 + spire.geometry.parameters.height / 2; g.add(spire);
      const tip = glowSprite(0xff5040, r * 1.2, 0.8, true); tip.position.y = spire.position.y + spire.geometry.parameters.height / 2; g.add(tip);
    } else if (type === 2) {
      for (let k = 0; k < 3; k++) {
        const disc = mesh(new THREE.CylinderGeometry(r * (1.9 - k * 0.35), r * (1.6 - k * 0.35), r * 0.35, 40), k % 2 ? metalTeal : metalWhite, false, false); disc.position.y = top + k * r * 0.7; g.add(disc);
        const lip = mesh(new THREE.TorusGeometry(r * (1.75 - k * 0.35), r * 0.03, 6, 48), warmGlow, false, false); lip.rotation.x = Math.PI / 2; lip.position.y = disc.position.y - r * 0.18; g.add(lip);
      }
      const ant = mesh(new THREE.CylinderGeometry(r * 0.05, r * 0.08, r * 4, 8), metalDark, false, false); ant.position.y = top + r * 3.4; g.add(ant);
    } else {
      const bulb = mesh(new THREE.SphereGeometry(r * 1.35, 40, 24), metalWhite, false, false); bulb.position.y = top + r * 0.7; bulb.scale.y = 0.75; g.add(bulb);
      const win = mesh(new THREE.TorusGeometry(r * 1.33, r * 0.12, 8, 48), glow(0x9ff6ff, 2.2), false, false); win.rotation.x = Math.PI / 2; win.position.y = bulb.position.y; g.add(win);
      const spire = mesh(new THREE.ConeGeometry(r * 0.25, r * 3, 12), brass, false, false); spire.position.y = bulb.position.y + r * 2.2; g.add(spire);
    }
    city.add(g); return g;
  }
  // landmark observatory
  (function landmark() {
    const g = new THREE.Group(); g.position.set(-30, -6, -95); g.scale.setScalar(1.25);
    const body = mesh(new THREE.CylinderGeometry(7, 9, 140, 48), windowMat(winTexA, [10, 14], 0xcfe0ea), false, false); body.position.y = -55; g.add(body);
    const collar = mesh(new THREE.CylinderGeometry(10.5, 8, 4, 48), metalWhite, false, false); collar.position.y = 16; g.add(collar);
    for (let i = 0; i < 14; i++) { const fin = mesh(new RoundedBoxGeometry(1.6, 9, 3.2, 3, 0.4), i % 2 ? metalBlue : metalWhite, false, false); const a = i / 14 * Math.PI * 2; fin.position.set(Math.cos(a) * 9.6, 21, Math.sin(a) * 9.6); fin.rotation.y = -a; g.add(fin); }
    const drum = mesh(new THREE.CylinderGeometry(9, 9.5, 8, 48), metalTeal, false, false); drum.position.y = 22; g.add(drum);
    const dome = mesh(new THREE.SphereGeometry(9.2, 64, 32, 0, Math.PI * 2, 0, Math.PI / 2), metalWhite, false, false); dome.position.y = 26; g.add(dome);
    const slit = mesh(new RoundedBoxGeometry(2.2, 8, 10, 2, 0.5), domeGlass, false, false); slit.position.set(0, 31, 4.5); slit.rotation.x = -0.6; g.add(slit);
    const scope = mesh(new THREE.CylinderGeometry(1.2, 1.8, 18, 24), metalDark, false, false); scope.position.set(3, 36, 2); scope.rotation.z = -0.9; scope.rotation.x = 0.3; g.add(scope);
    const scopeEnd = mesh(new THREE.TorusGeometry(1.4, 0.35, 12, 24), brass, false, false); scopeEnd.position.set(10, 41, 4.6); scopeEnd.rotation.y = 0.9; scopeEnd.rotation.x = 0.6; g.add(scopeEnd);
    for (const [rad, y, tilt, m] of [[15, 19, 0.18, metalWhite], [18.5, 12, -0.12, metalBlue], [13, 28, 0.32, brass]]) {
      const ring = mesh(new THREE.TorusGeometry(rad, 0.55, 12, 96), m, false, false); ring.rotation.x = Math.PI / 2 + tilt; ring.rotation.y = tilt; ring.position.y = y; g.add(ring);
      const lg = mesh(new THREE.TorusGeometry(rad, 0.08, 8, 96), cyanGlow, false, false); lg.rotation.copy(ring.rotation); lg.position.y = y - 0.5; g.add(lg);
    }
    const balcony = mesh(new THREE.CylinderGeometry(13, 11, 1.6, 48), metalWhite, false, false); balcony.position.y = 4; g.add(balcony);
    const balGlow = mesh(new THREE.TorusGeometry(12.9, 0.18, 8, 96), warmGlow, false, false); balGlow.rotation.x = Math.PI / 2; balGlow.position.y = 3.2; g.add(balGlow);
    city.add(g);
  })();
  // towers on every side of the arena
  const spots = [];
  const towerCount = lq ? 90 : 170;
  for (let i = 0; i < towerCount; i++) {
    const ang = R(0, Math.PI * 2), dist = 60 + Math.pow(rnd(), 0.8) * 560;
    const x = Math.sin(ang) * dist, z = -Math.cos(ang) * dist;
    if (Math.hypot(x + 37, z + 118) < 32) continue; // keep the landmark clear
    spots.push([x, z, dist]);
  }
  spots.forEach(([x, z, dist]) => {
    const s = 0.7 + dist / 300 * R(0.6, 1.5);
    tower(x, z, s, -220).position.y = dist < 160 ? R(-40, -12) : R(-35, 10);
  });
  // sky bridges
  for (let i = 0; i < 30; i++) {
    const a = spots[Math.floor(rnd() * spots.length)], b = spots[Math.floor(rnd() * spots.length)];
    if (!a || !b || a === b) continue;
    const pa = V(a[0], R(0, 18), a[1]), pb = V(b[0], R(0, 18), b[1]);
    if (pa.distanceTo(pb) > 140 || pa.distanceTo(pb) < 30) continue;
    const tube = mesh(new THREE.CylinderGeometry(1, 1, pa.distanceTo(pb), 12), metalWhite, false, false);
    tube.position.copy(pa).add(pb).multiplyScalar(.5); tube.quaternion.setFromUnitVectors(UP, pb.clone().sub(pa).normalize()); city.add(tube);
  }

  // flying traffic: instanced cars that loop along lanes around the arena
  const carGeo = new THREE.CapsuleGeometry(0.6, 2.2, 4, 10); carGeo.rotateZ(Math.PI / 2);
  const N = lq ? 160 : 360;
  const cars = new THREE.InstancedMesh(carGeo, std(0xe8eef5, 0.7, 0.3), N);
  const tails = new THREE.InstancedMesh(new THREE.SphereGeometry(0.42, 8, 6), glow(0xffffff, 6), N);
  cars.frustumCulled = tails.frustumCulled = false;
  const lanes = [];
  for (let l = 0; l < 14; l++) lanes.push({ y: R(6, 60), r: R(60, 420), speed: R(0.02, 0.06) * (rnd() < .5 ? 1 : -1) });
  const carData = [];
  const col = new THREE.Color();
  for (let i = 0; i < N; i++) {
    const lane = lanes[i % lanes.length];
    carData.push({ lane, a: R(0, Math.PI * 2), dy: R(-1.5, 1.5), dr: R(-6, 6), s: R(0.8, 1.6) });
    col.setHSL(R(0, 1), 0.5, 0.75); cars.setColorAt(i, col);
    tails.setColorAt(i, col.set(rnd() < .5 ? 0xff5a3a : 0x5af6ff));
  }
  scene.add(cars, tails);
  const dummy = new THREE.Object3D();
  function updateTraffic(dt) {
    for (let i = 0; i < N; i++) {
      const c = carData[i], L = c.lane;
      c.a += L.speed * dt * (120 / L.r);
      const r = L.r + c.dr;
      const x = Math.cos(c.a) * r, z = Math.sin(c.a) * r;
      dummy.position.set(x, L.y + c.dy, z);
      // heading is the tangent of the circle
      const tx = -Math.sin(c.a) * Math.sign(L.speed), tz = Math.cos(c.a) * Math.sign(L.speed);
      dummy.rotation.set(0, Math.atan2(-tz, tx), 0);
      dummy.scale.setScalar(c.s); dummy.updateMatrix(); cars.setMatrixAt(i, dummy.matrix);
      dummy.position.x -= tx * 1.9 * c.s; dummy.position.z -= tz * 1.9 * c.s;
      dummy.updateMatrix(); tails.setMatrixAt(i, dummy.matrix);
    }
    cars.instanceMatrix.needsUpdate = true; tails.instanceMatrix.needsUpdate = true;
  }

  // grind rail looping behind the arena (scenery for now)
  const railCurve = new THREE.CatmullRomCurve3([V(-24, 1.2, -16), V(-12, 2.6, -20), V(0, 4.6, -22), V(12, 5.2, -24), V(22, 3.8, -18), V(30, 4.5, -8)]);
  scene.add(mesh(new THREE.TubeGeometry(railCurve, 200, 0.16, 12), std(0xd8e2ea, 0.95, 0.18)));
  const railGlowCurve = new THREE.CatmullRomCurve3(railCurve.points.map(p => p.clone().add(V(0, -0.22, 0))));
  scene.add(mesh(new THREE.TubeGeometry(railGlowCurve, 200, 0.04, 8), glow(0xffb43a, 2.5), false, false));
  for (let t = 0.05; t < 1; t += 0.1) {
    const p = railCurve.getPoint(t);
    const post = mesh(new THREE.CylinderGeometry(0.12, 0.2, 40, 10), metalDark); post.position.set(p.x, p.y - 20.2, p.z); scene.add(post);
    const clampM = mesh(new RoundedBoxGeometry(0.6, 0.35, 0.6, 2, 0.08), brass); clampM.position.set(p.x, p.y - 0.3, p.z); scene.add(clampM);
  }

  // ---------- arena deck ----------
  const W = ARENA.maxX - ARENA.minX + 1, D = ARENA.maxZ - ARENA.minZ + 1;
  const deckTex = panelTex.clone(); deckTex.needsUpdate = true; deckTex.repeat.set(W / 3.6, D / 3.6);
  const deck = mesh(new RoundedBoxGeometry(W, 1.2, D, 4, 0.2), std(0xffffff, 0.75, 0.38, { map: deckTex }), false, true);
  deck.position.set(0, -0.6, 0); scene.add(deck);
  const underside = mesh(new THREE.CylinderGeometry(9, 2, 16, 40), metalDark, false, false); underside.position.set(0, -9, 0); scene.add(underside);
  const coreGlow = mesh(new THREE.CylinderGeometry(2.1, 2.1, 0.6, 32), glow(0x40f0ff, 4), false, false); coreGlow.position.set(0, -17, 0); scene.add(coreGlow);
  // hazard edging and railings on all four sides
  const edge = (len, x, z, rotY) => {
    const t = hazardTex.clone(); t.needsUpdate = true; t.repeat.set(len / 2, 1);
    const hz = mesh(new THREE.BoxGeometry(len, 0.22, 0.3), std(0xffffff, 0.3, 0.5, { map: t }), false, true);
    hz.position.set(x, -0.08, z); hz.rotation.y = rotY; scene.add(hz);
    const top = mesh(new THREE.CylinderGeometry(0.06, 0.06, len, 12), metalWhite); top.rotation.z = Math.PI / 2; top.rotation.y = rotY; top.position.set(x, 1.0, z); scene.add(top);
    const light = mesh(new THREE.BoxGeometry(len, 0.03, 0.03), glow(0x40f0ff, 2.2), false, false); light.position.set(x, 0.9, z); light.rotation.y = rotY; scene.add(light);
    const n = Math.round(len / 2.4);
    for (let i = 0; i <= n; i++) {
      const u = -len / 2 + i * len / n;
      const p = mesh(new THREE.CylinderGeometry(0.05, 0.06, 1, 10), metalWhite);
      p.position.set(x + Math.cos(rotY) * u, 0.5, z - Math.sin(rotY) * u); scene.add(p);
    }
  };
  edge(W - 0.4, 0, ARENA.minZ - 0.3, 0); edge(W - 0.4, 0, ARENA.maxZ + 0.3, 0);
  edge(D - 0.4, ARENA.minX - 0.3, 0, Math.PI / 2); edge(D - 0.4, ARENA.maxX + 0.3, 0, Math.PI / 2);
  // floor light strips
  for (const z of [-6, 0, 6]) { const s = mesh(new THREE.BoxGeometry(W - 4, 0.02, 0.07), glow(0x4ff2ff, 2.5), false, false); s.position.set(0, 0.012, z); scene.add(s); }

  // raised pads the hero can jump onto
  const padMat = std(0x9fb2c2, 0.7, 0.35, { map: deckTex });
  for (const [x, z, sx, sz, h] of [[-8.5, -6, 4.2, 4.2, 1.3], [8.5, 5.5, 4.2, 4.2, 1.3], [0, -8.4, 6, 2.6, 2.2]]) {
    const p = mesh(new RoundedBoxGeometry(sx, h, sz, 3, 0.1), padMat); p.position.set(x, h / 2, z); scene.add(p);
    const lip = mesh(new THREE.BoxGeometry(sx + 0.02, 0.05, sz + 0.02), glow(0xffa030, 2.2), false, false); lip.position.set(x, h - 0.05, z); scene.add(lip);
    addCollider(x, h / 2, z, sx, h, sz);
  }
  // vents
  for (const [x, z] of [[-4.6, 3.6], [5, -3.6]]) {
    const vent = mesh(new RoundedBoxGeometry(1.6, 0.5, 1.2, 3, 0.1), metalBlue); vent.position.set(x, 0.25, z); scene.add(vent);
    const vg = mesh(new THREE.BoxGeometry(1.2, 0.04, 0.8), glow(0xff8a30, 2), false, false); vg.position.set(x, 0.51, z); scene.add(vg);
    addCollider(x, 0.25, z, 1.6, 0.5, 1.2);
  }
  // crates (cover)
  const crateMat = std(0xff8f1f, 0.35, 0.45);
  const crateEdge = std(0x3a3f47, 0.8, 0.35);
  const hexIcon = canvasTex(128, 128, (g, w) => { g.fillStyle = '#000'; g.fillRect(0, 0, w, w); g.strokeStyle = '#fff'; g.lineWidth = 10; g.beginPath(); for (let i = 0; i < 6; i++) { const a = i / 6 * Math.PI * 2 + Math.PI / 6; g.lineTo(64 + Math.cos(a) * 40, 64 + Math.sin(a) * 40); } g.closePath(); g.stroke(); g.beginPath(); g.arc(64, 64, 14, 0, 7); g.stroke(); });
  const iconMat = new THREE.MeshStandardMaterial({ color: 0x000000, emissive: 0xfff0a0, emissiveMap: hexIcon, emissiveIntensity: 1.8, transparent: true, alphaMap: hexIcon });
  function crate(x, y, z, s = 1) {
    const g = new THREE.Group(); g.position.set(x, y + s * 0.4, z);
    g.add(mesh(new RoundedBoxGeometry(0.8 * s, 0.8 * s, 0.8 * s, 3, 0.06 * s), crateMat));
    for (const [sx, sy] of [[1, 1], [1, -1], [-1, 1], [-1, -1]]) { const e = mesh(new RoundedBoxGeometry(0.12 * s, 0.84 * s, 0.12 * s, 2, 0.03), crateEdge); e.position.set(sx * 0.37 * s, 0, sy * 0.37 * s); g.add(e); }
    for (let k = 0; k < 4; k++) {
      const icon = new THREE.Mesh(new THREE.PlaneGeometry(0.5 * s, 0.5 * s), iconMat);
      icon.rotation.y = k * Math.PI / 2; icon.position.set(Math.sin(k * Math.PI / 2) * 0.405 * s, 0, Math.cos(k * Math.PI / 2) * 0.405 * s); g.add(icon);
    }
    scene.add(g); addCollider(x, y + s * 0.4, z, 0.8 * s, 0.8 * s, 0.8 * s); return g;
  }
  crate(-3.2, 0, -3.2, 1.2); crate(-2.2, 0, -3.4, 1.2); crate(-2.7, 0.96, -3.3, 1.0);
  crate(3.2, 0, 2.8, 1.3); crate(10.5, 0, -6.5, 1.3); crate(11.6, 0, -6.2, 1.1);
  crate(-10.5, 0, 6.5, 1.3); crate(-11.5, 0, 5.2, 1.1); crate(-0.5, 0, 7.5, 1.2);

  // dust motes near the arena
  const motes = [];
  for (let i = 0; i < 40; i++) { const s = glowSprite(0xfff4d8, R(0.015, 0.04), R(0.2, 0.45)); s.position.set(R(-14, 14), R(0.2, 4), R(-11, 11)); scene.add(s); motes.push(s); }

  scene.traverse(o => { const ms = o.material ? (Array.isArray(o.material) ? o.material : [o.material]) : []; ms.forEach(m => { if ('roughness' in m) m.roughness = Math.max(m.roughness, 0.12); }); });

  let t = 0;
  function update(dt, focus) {
    t += dt;
    // keep the shadow map centred on the action
    sun.position.copy(SUN_DIR).multiplyScalar(40).add(focus);
    sun.target.position.copy(focus);
    updateTraffic(dt);
    motes.forEach((m, i) => { m.position.y += Math.sin(t * 0.6 + i) * dt * 0.05; });
  }
  update(0, V(0, 0, 0));

  return { colliders, update, sun };
}
