// Heads-up display: hull, hex nuts, wave, the weapon panel and slots, crosshair with heat ring,
// floating damage numbers, a boss health bar and arrows pointing at bots off screen.
import * as THREE from 'three';
import { ICONS, LEVELS } from './weapons.js';

const $ = id => document.getElementById(id);

export function createHud({ maxHull, weapons }) {
  const hud = $('hud');
  const hullEl = $('hull');
  for (let i = 0; i < maxHull; i++) hullEl.insertBefore(document.createElement('i'), hullEl.querySelector('b'));
  const cells = [...hullEl.querySelectorAll('i')];

  // weapon slot strip under the weapon panel
  const slotsEl = $('slots');
  slotsEl.innerHTML = weapons.map((w, i) => `<div class="slot" style="--c:${w.color}"><svg viewBox="0 0 60 60">${ICONS[w.id]}</svg><i></i><b>${i + 1}</b></div>`).join('');
  const slots = [...slotsEl.children];

  // pools for floating numbers, health bars and off-screen arrows
  const pool = (cls, n) => Array.from({ length: n }, () => { const d = document.createElement('div'); d.className = cls; hud.append(d); return d; });
  const nums = pool('dmg', 28).map(el => ({ el, t: 0, pos: new THREE.Vector3(), vy: 0 }));
  // boss (and objective target) health bar at the top of the screen; regular bots show no health
  const bossEl = document.createElement('div'); bossEl.id = 'bossbar'; bossEl.innerHTML = '<b></b><div><i></i><u></u></div>'; hud.append(bossEl);
  let bossShown = -1;
  const arrows = pool('offarrow', 12);
  const v = new THREE.Vector3();

  let bannerTimer = 0, hitT = 0, hurtT = 0, killT = 0, lastWeapon = -1;
  const api = {
    hull(hull, pop) {
      cells.forEach((c, i) => { c.className = i < hull ? (hull <= 2 ? 'low' : '') : 'off'; });
      if (pop && hull > 0) { const c = cells[hull - 1]; c.classList.add('pop'); setTimeout(() => c.classList.remove('pop'), 200); }
      hud.classList.toggle('lowhull', hull > 0 && hull <= 2);
    },
    nuts(n) { $('nuts').textContent = n.toLocaleString(); const c = document.querySelector('.cur'); c.classList.add('pop'); clearTimeout(api._np); api._np = setTimeout(() => c.classList.remove('pop'), 90); },
    banner(title, sub, color) {
      const b = $('banner'); b.innerHTML = `${title}${sub ? `<small>${sub}</small>` : ''}`; b.style.setProperty('--c', color || '#3ef');
      b.classList.remove('on'); void b.offsetWidth; b.classList.add('on'); bannerTimer = 2.2;
    },
    toast(text) { const t = $('toast'); t.textContent = text; t.classList.remove('on'); void t.offsetWidth; t.classList.add('on'); clearTimeout(api._tt); api._tt = setTimeout(() => t.classList.remove('on'), 1400); },
    hit(kill) { hitT = 0.12; if (kill) killT = 0.3; },
    hurt() { hurtT = 1; },
    boss(name, frac = 1) {
      if (!name) { bossEl.classList.remove('on'); hud.classList.remove('bossfight'); bossShown = -1; return; }
      bossEl.classList.add('on'); hud.classList.add('bossfight'); bossEl.querySelector('b').textContent = name;
      const f = Math.max(0, Math.min(1, frac));
      bossEl.querySelector('i').style.width = `${(f * 100).toFixed(1)}%`;
      // the trailing bar shows the chunk you just knocked off
      if (bossShown < 0 || f > bossShown) bossShown = f; else bossShown += (f - bossShown) * 0.05;
      bossEl.querySelector('u').style.width = `${(bossShown * 100).toFixed(1)}%`;
    },
    weapon(state, cur) {
      const w = state[cur];
      if (cur !== lastWeapon) {
        lastWeapon = cur;
        $('ringIcon').innerHTML = ICONS[w.id];
        $('wpnPanel').style.setProperty('--c', w.color);
        $('wname').textContent = w.name;
        $('wpnPanel').classList.remove('swap'); void $('wpnPanel').offsetWidth; $('wpnPanel').classList.add('swap');
      }
      $('lvl').textContent = 'V' + w.level;
      const lo = LEVELS[w.level - 1], hi = LEVELS[w.level];
      $('xp').style.width = hi === undefined ? '100%' : `${(100 * (w.xp - lo) / (hi - lo)).toFixed(1)}%`;
      $('ammo').textContent = Math.floor(w.ammo); $('ammoMax').textContent = `/ ${w.max}`;
      $('ammo').parentElement.classList.toggle('hot', w.hot || w.ammo < 1);
      $('ring').classList.toggle('hot', w.hot);
      slots.forEach((s, i) => {
        s.classList.toggle('sel', i === cur);
        s.classList.toggle('locked', state[i].owned === false);
        s.querySelector('i').style.width = `${(100 * state[i].ammo / state[i].max).toFixed(0)}%`;
      });
      // heat ring around the crosshair: shows the lancer's charge, or the reload of the slower weapons
      const frac = w.regen ? w.ammo / w.max : Math.max(0, 1 - Math.max(0, w.cool) / (w.interval * Math.pow(0.9, w.level - 1)));
      $('heat').style.setProperty('--p', `${(frac * 100).toFixed(0)}%`);
      $('heat').classList.toggle('hot', w.hot);
      $('heat').classList.toggle('show', w.regen ? frac < 0.98 : frac < 0.99);
    },
    damageNumber(pos, amount, kill, color = '#fff') {
      const n = nums.reduce((a, b) => (a.t <= b.t ? a : b));
      n.t = 0.8; n.pos.copy(pos); n.vy = 1.6;
      n.el.textContent = Math.max(1, Math.round(amount * 10));
      n.el.className = 'dmg on' + (kill ? ' kill' : '');
      n.el.style.color = kill ? '#ffd040' : color;
      n.x = (Math.random() - 0.5) * 30;
    },
    frame(dt, { camera, onTarget, waveText, leftText, targets }) {
      $('wave').textContent = waveText; $('left').textContent = leftText;
      $('cross').classList.toggle('on', onTarget);
      bannerTimer -= dt; if (bannerTimer <= 0) $('banner').classList.remove('on');
      hitT -= dt; $('hitmark').classList.toggle('on', hitT > 0);
      killT -= dt; $('hitmark').classList.toggle('kill', killT > 0);
      hurtT = Math.max(0, hurtT - dt * 2.5); $('hurt').style.opacity = hurtT * 0.8;
      const W = innerWidth, H = innerHeight;
      // floating damage numbers
      for (const n of nums) {
        if (n.t <= 0) continue;
        n.t -= dt; n.pos.y += n.vy * dt; n.vy *= Math.exp(-3 * dt);
        v.copy(n.pos).project(camera);
        if (n.t <= 0 || v.z > 1) { n.el.className = 'dmg'; continue; }
        n.el.style.transform = `translate(${((v.x + 1) / 2 * W + n.x).toFixed(1)}px, ${((1 - v.y) / 2 * H).toFixed(1)}px) translate(-50%,-50%) scale(${(0.8 + Math.min(n.t, 0.6)).toFixed(2)})`;
        n.el.style.opacity = Math.min(1, n.t * 3).toFixed(2);
      }
      // edge arrows for bots you cannot see
      let ai = 0;
      for (const t of targets) {
        if (t.dead) continue;
        const c = v.copy(t.pos); if (t.type === 'roller') c.y += 1.35; else c.y += t.type === 'dummy' ? 0.85 : 1.1;
        c.project(camera);
        const onScreen = c.z < 1 && Math.abs(c.x) < 1 && Math.abs(c.y) < 1;
        if (!onScreen && t.type !== 'dummy' && t.type !== 'relay' && ai < arrows.length) {
          // point from the screen centre toward the bot, pinned to an ellipse inside the screen edge
          let x = c.x, y = c.y; if (c.z > 1) { x = -x; y = -y; }
          const a = Math.atan2(y, x);
          const ax = W / 2 + Math.cos(a) * (W / 2 - 46), ay = H / 2 - Math.sin(a) * (H / 2 - 46);
          const el = arrows[ai++]; el.style.display = 'block';
          el.style.transform = `translate(${ax.toFixed(1)}px, ${ay.toFixed(1)}px) translate(-50%,-50%) rotate(${(-a).toFixed(3)}rad)`;
          el.classList.toggle('air', t.type === 'hornet'); el.classList.toggle('big', t.type === 'boss');
        }
      }
      for (; ai < arrows.length; ai++) arrows[ai].style.display = 'none';
    },
  };
  return api;
}
