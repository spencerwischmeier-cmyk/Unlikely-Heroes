// Pooled particle effects: sparks, explosions, smoke and debris.
import * as THREE from 'three';
import { softDot, canvasTex, rand, V } from './util.js';
import { onDeck } from './world.js';

const fireTex = canvasTex(128, 128, (g, w) => { const gr = g.createRadialGradient(w / 2, w / 2, 0, w / 2, w / 2, w / 2); gr.addColorStop(0, 'rgba(255,250,220,1)'); gr.addColorStop(0.25, 'rgba(255,190,60,.95)'); gr.addColorStop(0.6, 'rgba(255,80,10,.5)'); gr.addColorStop(1, 'rgba(120,20,0,0)'); g.fillStyle = gr; g.fillRect(0, 0, w, w); });
const smokeTex = canvasTex(128, 128, (g) => { for (let i = 0; i < 40; i++) { const x = 30 + Math.random() * 68, y = 30 + Math.random() * 68, r = 14 + Math.random() * 20; const gr = g.createRadialGradient(x, y, 0, x, y, r); gr.addColorStop(0, 'rgba(60,62,70,.35)'); gr.addColorStop(1, 'rgba(60,62,70,0)'); g.fillStyle = gr; g.beginPath(); g.arc(x, y, r, 0, 7); g.fill(); } });

export function createFx(scene) {
  const pool = [];
  const live = [];
  function sprite(kind) {
    let s = pool.find(p => !p.visible && p.userData.kind === kind);
    if (!s) {
      const map = kind === 'fire' ? fireTex : kind === 'smoke' ? smokeTex : softDot;
      s = new THREE.Sprite(new THREE.SpriteMaterial({ map, transparent: true, depthWrite: false, blending: kind === 'smoke' ? THREE.NormalBlending : THREE.AdditiveBlending }));
      s.userData.kind = kind; pool.push(s); scene.add(s);
    }
    s.visible = true; return s;
  }
  // one particle: position, velocity, life, size curve, colour
  function emit(kind, pos, vel, life, size0, size1, color = 0xffffff, opacity = 1, gravity = 0, drag = 0) {
    const s = sprite(kind);
    s.position.copy(pos); s.material.color.set(color); s.material.opacity = opacity;
    s.userData.p = { vel: vel.clone(), life, t: 0, size0, size1, opacity, gravity, drag };
    s.scale.setScalar(size0);
    live.push(s);
  }

  const debrisGeo = new THREE.TetrahedronGeometry(0.12);
  const debrisPool = [];
  function debris(pos, mat, big = 1) {
    let d = debrisPool.find(x => !x.visible);
    if (!d) { d = new THREE.Mesh(debrisGeo, mat); d.castShadow = true; debrisPool.push(d); scene.add(d); }
    d.material = mat; d.visible = true; d.position.copy(pos);
    d.userData = { vel: V(rand(-1, 1), rand(0.3, 1.4), rand(-1, 1)).multiplyScalar(rand(4, 9)), spin: V(rand(-9, 9), rand(-9, 9), rand(-9, 9)), t: 0, life: rand(1, 1.8) };
    d.scale.setScalar(rand(0.6, 1.8) * big);
  }

  const shockGeo = new THREE.RingGeometry(0.85, 1, 40), shockPool = [];
  const swipeGeo = new THREE.RingGeometry(1.1, 2.1, 24, 1, 0, 2.4), swipePool = [];
  const lights = [];
  for (let i = 0; i < 4; i++) { const l = new THREE.PointLight(0xff8a30, 0, 14, 2); scene.add(l); lights.push({ l, t: 0, peak: 0 }); }
  function flashLight(pos, color, peak) {
    const L = lights.reduce((a, b) => (a.t <= b.t ? a : b));
    L.l.position.copy(pos); L.l.color.set(color); L.peak = peak; L.t = 1;
  }

  return {
    sparks(pos, color = 0xaefaff, n = 10, speed = 5) {
      for (let i = 0; i < n; i++) emit('dot', pos, V(rand(-1, 1), rand(-0.5, 1.2), rand(-1, 1)).normalize().multiplyScalar(rand(0.3, 1) * speed), rand(0.15, 0.4), rand(0.06, 0.14), 0.01, color, 1, -12, 2);
      emit('dot', pos, V(0, 0, 0), 0.12, 0.6, 0.1, color, 0.9);
    },
    explosion(pos, scale = 1, debrisMat) {
      for (let i = 0; i < 10; i++) emit('fire', pos.clone().add(V(rand(-.4, .4), rand(-.3, .4), rand(-.4, .4)).multiplyScalar(scale)), V(rand(-1, 1), rand(0, 1.5), rand(-1, 1)).multiplyScalar(1.6 * scale), rand(0.35, 0.7), rand(0.6, 1.2) * scale, rand(1.6, 2.6) * scale, 0xffffff, 1, 0, 2);
      for (let i = 0; i < 8; i++) emit('smoke', pos.clone().add(V(rand(-.5, .5), rand(0, .6), rand(-.5, .5)).multiplyScalar(scale)), V(rand(-.5, .5), rand(0.6, 1.6), rand(-.5, .5)), rand(1.2, 2.0), rand(0.8, 1.2) * scale, rand(2.2, 3.4) * scale, 0x9aa3b0, 0.45, 0, 1);
      for (let i = 0; i < 16; i++) emit('dot', pos, V(rand(-1, 1), rand(-0.3, 1.3), rand(-1, 1)).normalize().multiplyScalar(rand(4, 11) * scale), rand(0.3, 0.7), rand(0.08, 0.16), 0.02, 0xffb040, 1, -9, 1.5);
      if (debrisMat) for (let i = 0; i < 14; i++) debris(pos, debrisMat[i % debrisMat.length], i < 5 ? 2.2 : 1);
      flashLight(pos, 0xff8a30, 60 * scale);
    },
    // a quick expanding shock ring for explosions
    shock(pos, color = 0xffb040) {
      const r = shockPool.find(x => !x.visible) || (() => { const m = new THREE.Mesh(shockGeo, new THREE.MeshBasicMaterial({ color, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, side: THREE.DoubleSide })); shockPool.push(m); scene.add(m); return m; })();
      r.visible = true; r.position.copy(pos); r.material.color.set(color); r.userData.t = 0; r.lookAt(pos.clone().add(V(0, 1, 0)));
    },
    // the arc of a melee swing
    swipe(pos, yaw, color = 0x9ff8ff) {
      const r = swipePool.find(x => !x.visible) || (() => { const m = new THREE.Mesh(swipeGeo, new THREE.MeshBasicMaterial({ color, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, side: THREE.DoubleSide })); swipePool.push(m); scene.add(m); return m; })();
      r.visible = true; r.position.copy(pos); r.rotation.set(-Math.PI / 2, 0, yaw + Math.PI / 2 - 1.2); r.userData.t = 0; r.scale.setScalar(0.7);
    },
    ring(pos, color = 0x40f0ff) {
      for (let i = 0; i < 18; i++) { const a = i / 18 * Math.PI * 2; emit('dot', pos, V(Math.cos(a), 0, Math.sin(a)).multiplyScalar(5), 0.35, 0.18, 0.02, color, 1, 0, 3); }
    },
    trail(pos, color = 0xffd040, size = 0.25, life = 0.35) { emit('dot', pos, V(rand(-.3, .3), rand(-.3, .3), rand(-.3, .3)), life, size, 0.02, color, 0.8, 0, 1); },
    smokeTrail(pos) { emit('smoke', pos, V(rand(-.2, .2), rand(0.2, 0.5), rand(-.2, .2)), 0.6, 0.15, 0.6, 0x9aa3b0, 0.35, 0, 1); },
    puff(pos, color = 0xcfe8ff) {
      for (let i = 0; i < 6; i++) emit('smoke', pos.clone().add(V(rand(-.2, .2), 0, rand(-.2, .2))), V(rand(-1.5, 1.5), rand(0.1, 0.5), rand(-1.5, 1.5)), rand(0.4, 0.7), 0.3, 0.9, color, 0.5, 0, 3);
    },
    update(dt) {
      for (let i = live.length - 1; i >= 0; i--) {
        const s = live[i], p = s.userData.p;
        p.t += dt;
        const k = p.t / p.life;
        if (k >= 1) { s.visible = false; live.splice(i, 1); continue; }
        p.vel.y += p.gravity * dt;
        p.vel.multiplyScalar(Math.exp(-p.drag * dt));
        s.position.addScaledVector(p.vel, dt);
        s.scale.setScalar(p.size0 + (p.size1 - p.size0) * k);
        s.material.opacity = p.opacity * (1 - k * k);
      }
      for (const d of debrisPool) {
        if (!d.visible) continue;
        const u = d.userData; u.t += dt;
        u.vel.y -= 18 * dt; d.position.addScaledVector(u.vel, dt);
        if (d.position.y < 0.05 && onDeck(d.position.x, d.position.z, 0)) { d.position.y = 0.05; u.vel.y *= -0.35; u.vel.x *= 0.6; u.vel.z *= 0.6; }
        d.rotation.x += u.spin.x * dt; d.rotation.y += u.spin.y * dt;
        if (u.t > u.life) d.scale.multiplyScalar(Math.exp(-8 * dt));
        if (u.t > u.life + 0.6) d.visible = false;
      }
      for (const r of shockPool) { if (!r.visible) continue; const u = r.userData; u.t += dt; const k = u.t / 0.35; if (k >= 1) { r.visible = false; continue; } r.scale.setScalar(0.4 + k * 3.6); r.material.opacity = (1 - k) * 0.9; }
      for (const r of swipePool) { if (!r.visible) continue; const u = r.userData; u.t += dt; const k = u.t / 0.2; if (k >= 1) { r.visible = false; continue; } r.scale.setScalar(0.7 + k * 0.35); r.material.opacity = (1 - k) * 0.85; }
      for (const L of lights) { L.t = Math.max(0, L.t - dt * 4); L.l.intensity = L.peak * L.t * L.t; }
    },
  };
}
