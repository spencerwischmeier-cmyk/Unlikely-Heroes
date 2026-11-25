// Phone controls: a move stick on the left (it rests in the corner and jumps to wherever your thumb lands),
// drag anywhere on the right to aim, and buttons for fire, jump, dash and the weapon wheel.
// Dragging your thumb on the fire button also aims, so you can shoot and steer with one thumb.
import { settings, onSettings } from './settings.js';

const ICON = {
  fire: '<svg viewBox="0 0 40 40"><circle cx="20" cy="20" r="11" fill="none" stroke="currentColor" stroke-width="3"/><path d="M20 3v9M20 28v9M3 20h9M28 20h9" stroke="currentColor" stroke-width="3" stroke-linecap="round"/></svg>',
  jump: '<svg viewBox="0 0 40 40"><path d="M20 8l11 12h-7v11h-8V20H9z" fill="currentColor"/></svg>',
  melee: '<svg viewBox="0 0 40 40"><path d="M8 30C12 14 22 8 34 8" fill="none" stroke="currentColor" stroke-width="4" stroke-linecap="round"/><path d="M6 24c4-2 8-2 10 2" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round"/></svg>',
  dash: '<svg viewBox="0 0 40 40"><path d="M6 12h14M3 20h17M6 28h14" stroke="currentColor" stroke-width="3" stroke-linecap="round"/><path d="M22 9l13 11-13 11z" fill="currentColor"/></svg>',
};

export function createTouch({ input, isPlaying, onPause, onWheelOpen, onWheelDrag, onWheelRelease }) {
  document.body.classList.add('touch');
  const root = document.createElement('div');
  root.id = 'touch';
  root.innerHTML = `
    <div class="tzone left" id="tLeft"></div>
    <div class="tzone right" id="tRight"></div>
    <div class="stick rest" id="tStick"><div class="knob" id="tKnob"></div></div>
    <button class="tbtn fire" id="tFire">${ICON.fire}<span>FIRE</span></button>
    <button class="tbtn jump" id="tJump">${ICON.jump}<span>JUMP</span></button>
    <button class="tbtn dash" id="tDash"><i class="cd" id="tDashCd"></i>${ICON.dash}<span>DASH</span></button>
    <button class="tbtn melee" id="tMelee">${ICON.melee}<span>BASH</span></button>
    <button class="tbtn wsel" id="tWpn"><svg viewBox="0 0 60 60" id="tWpnIcon"></svg></button>
    <button class="tpause" id="tPause" aria-label="Pause">&#10074;&#10074;</button>`;
  document.body.appendChild(root);
  const $ = id => document.getElementById(id);
  const stick = $('tStick'), knob = $('tKnob');
  const STICK_R = 56;
  const applyScale = () => root.style.setProperty('--bs', settings.btnScale);
  applyScale(); onSettings(applyScale);

  input.touchMove = { x: 0, z: 0 };
  input.jumpHeld = false;

  // ---- move stick ----
  let moveId = null, ox = 0, oy = 0;
  const restStick = () => { stick.classList.add('rest'); stick.style.left = ''; stick.style.top = ''; knob.style.transform = 'translate(-50%,-50%)'; };
  $('tLeft').addEventListener('touchstart', e => {
    e.preventDefault();
    if (moveId !== null) return;
    const t = e.changedTouches[0]; moveId = t.identifier; ox = t.clientX; oy = t.clientY;
    stick.classList.remove('rest'); stick.style.left = ox + 'px'; stick.style.top = oy + 'px';
    knob.style.transform = 'translate(-50%,-50%)';
  }, { passive: false });

  // ---- look drags (right side, and the fire button) ----
  const lookIds = new Map(); // touch id -> [x, y]
  $('tRight').addEventListener('touchstart', e => {
    e.preventDefault();
    for (const t of e.changedTouches) lookIds.set(t.identifier, [t.clientX, t.clientY]);
  }, { passive: false });

  const press = (el, down, up) => {
    el.addEventListener('touchstart', e => {
      e.preventDefault(); e.stopPropagation(); el.classList.add('down');
      for (const t of e.changedTouches) down(t);
    }, { passive: false });
    el.addEventListener('touchend', e => { e.preventDefault(); if (![...e.touches].some(t => t.target === el)) el.classList.remove('down'); for (const t of e.changedTouches) up?.(t); }, { passive: false });
    el.addEventListener('touchcancel', () => { el.classList.remove('down'); up?.({}); });
  };
  let fireId = null, wheelId = null, wx = 0, wy = 0;
  press($('tFire'), t => { fireId = t.identifier; lookIds.set(t.identifier, [t.clientX, t.clientY]); if (isPlaying()) input.fire = true; }, t => { if (t.identifier === fireId) { fireId = null; input.fire = false; } });
  press($('tJump'), () => { input.jumpPressed = true; input.jumpHeld = true; }, () => { input.jumpHeld = false; });
  press($('tDash'), () => { input.dashPressed = true; });
  press($('tMelee'), () => { input.meleePressed = true; });
  press($('tWpn'), t => { if (!isPlaying()) return; wheelId = t.identifier; wx = t.clientX; wy = t.clientY; onWheelOpen(); },
    t => { if (t.identifier === wheelId) { wheelId = null; onWheelRelease(Math.hypot(t.clientX - wx, t.clientY - wy) > 40); } });
  $('tPause').addEventListener('touchstart', e => { e.preventDefault(); if (isPlaying()) onPause(); }, { passive: false });

  addEventListener('touchmove', e => {
    for (const t of e.changedTouches) {
      if (t.identifier === moveId) {
        let dx = t.clientX - ox, dy = t.clientY - oy;
        const d = Math.hypot(dx, dy);
        if (d > STICK_R) { dx *= STICK_R / d; dy *= STICK_R / d; }
        knob.style.transform = `translate(calc(-50% + ${dx}px), calc(-50% + ${dy}px))`;
        input.touchMove.x = dx / STICK_R; input.touchMove.z = -dy / STICK_R;
      } else if (t.identifier === wheelId) {
        onWheelDrag(t.clientX - wx, t.clientY - wy);
      } else if (lookIds.has(t.identifier)) {
        const [lx, ly] = lookIds.get(t.identifier);
        if (isPlaying()) {
          // a little acceleration: slow drags are precise, fast flicks turn quickly
          const dx = t.clientX - lx, dy = t.clientY - ly, sp = Math.hypot(dx, dy);
          const gain = 1.5 * settings.sens * (1 + Math.min(1.2, sp / 40));
          input.look.dx += dx * gain; input.look.dy += dy * gain;
        }
        lookIds.set(t.identifier, [t.clientX, t.clientY]);
      }
    }
    if (isPlaying()) e.preventDefault();
  }, { passive: false });
  const end = e => {
    for (const t of e.changedTouches) {
      if (t.identifier === moveId) { moveId = null; input.touchMove.x = input.touchMove.z = 0; restStick(); }
      lookIds.delete(t.identifier);
      if (t.identifier === fireId) { fireId = null; input.fire = false; }
    }
  };
  addEventListener('touchend', end); addEventListener('touchcancel', end);

  return {
    show(on) { root.classList.toggle('on', on); },
    reset() { moveId = null; fireId = null; wheelId = null; lookIds.clear(); input.touchMove.x = input.touchMove.z = 0; input.fire = false; input.jumpHeld = false; restStick(); },
    setDash(frac) { $('tDashCd').style.setProperty('--p', `${Math.round(frac * 100)}%`); $('tDash').classList.toggle('cool', frac > 0); },
    setWeapon(iconSvg, color) { const ic = $('tWpnIcon'); if (ic.dataset.k !== iconSvg) { ic.innerHTML = iconSvg; ic.dataset.k = iconSvg; } $('tWpn').style.setProperty('--c', color); },
    get fireHeld() { return fireId !== null; },
  };
}

export function buzz(ms) { if (settings.vibrate && navigator.vibrate) try { navigator.vibrate(ms); } catch { /* not allowed */ } }
