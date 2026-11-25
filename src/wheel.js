// Weapon wheel: four slots around the crosshair. Time slows while it is open.
//   Desktop: hold Q, move the mouse toward a weapon, release Q (also: mouse wheel, keys 1-4)
//   Controller: hold LB, push the right stick toward a weapon, release LB
//   Touch: tap the weapon button, then tap a weapon (or slide from the button toward one and let go)
import { ICONS } from './weapons.js';

const DIRS = [[0, -1], [1, 0], [0, 1], [-1, 0]]; // slot 0 top, 1 right, 2 bottom, 3 left

export function createWheel(weapons, onPick) {
  const el = document.createElement('div'); el.id = 'wheel';
  el.innerHTML = `<div class="wcenter"><b id="wName"></b><small id="wBlurb"></small></div>` + weapons.map((w, i) =>
    `<div class="wslot" data-i="${i}" style="--c:${w.color};--x:${DIRS[i][0]};--y:${DIRS[i][1]}"><svg viewBox="0 0 60 60">${ICONS[w.id]}</svg><span class="wn">${w.name}</span><span class="wa"></span><i class="wk">${i + 1}</i></div>`).join('');
  document.body.append(el);
  const slots = [...el.querySelectorAll('.wslot')];
  let open = false, hi = -1, vx = 0, vy = 0;

  function highlight(i) {
    hi = i;
    slots.forEach((s, k) => s.classList.toggle('hi', k === i));
    const w = weapons[i >= 0 ? i : 0];
    el.querySelector('#wName').textContent = i >= 0 ? w.name : 'CHOOSE A WEAPON';
    el.querySelector('#wBlurb').textContent = i >= 0 ? w.blurb : '';
  }
  function refresh(state, cur) {
    slots.forEach((s, k) => {
      const w = state[k];
      s.querySelector('.wa').textContent = w.regen ? `V${w.level}` : `${Math.floor(w.ammo)}/${w.max} · V${w.level}`;
      s.classList.toggle('sel', k === cur);
    });
  }
  // direction from the centre (screen space, y down) picks the closest slot
  function point(dx, dy, absolute = false) {
    if (absolute) { vx = dx; vy = dy; } else { vx += dx; vy += dy; const l = Math.hypot(vx, vy); if (l > 120) { vx *= 120 / l; vy *= 120 / l; } }
    if (Math.hypot(vx, vy) < (absolute ? 0.35 : 30)) return;
    let best = -1, bd = -2;
    DIRS.forEach(([x, y], i) => { const d = (x * vx + y * vy) / Math.hypot(vx, vy); if (d > bd) { bd = d; best = i; } });
    highlight(best);
  }
  slots.forEach((s, i) => {
    const pick = e => { e.preventDefault(); e.stopPropagation(); highlight(i); close(true); };
    s.addEventListener('touchend', pick); s.addEventListener('click', pick);
  });
  el.addEventListener('touchend', e => { if (e.target === el && open) { e.preventDefault(); close(false); } });

  function show(state, cur) {
    if (open) return; open = true; vx = vy = 0;
    refresh(state, cur); highlight(-1);
    el.classList.add('on'); document.body.classList.add('wheel-open');
  }
  function close(commit = true) {
    if (!open) return; open = false;
    el.classList.remove('on'); document.body.classList.remove('wheel-open');
    if (commit && hi >= 0) onPick(hi);
  }
  return { show, close, point, highlight, get open() { return open; }, refresh };
}
