// Phone controls: a floating move stick on the left half of the screen, drag anywhere on the right half
// to aim, and big buttons for fire, jump and dash. Dragging your thumb on the fire button also aims.
export function createTouch({ input, isPlaying, onPause }) {
  document.body.classList.add('touch');
  const root = document.createElement('div');
  root.id = 'touch';
  root.innerHTML = `
    <div class="tzone left" id="tLeft"></div>
    <div class="tzone right" id="tRight"></div>
    <div class="stick" id="tStick"><div class="knob" id="tKnob"></div></div>
    <button class="tbtn fire" id="tFire">FIRE</button>
    <button class="tbtn jump" id="tJump">JUMP</button>
    <button class="tbtn dash" id="tDash">DASH</button>
    <button class="tpause" id="tPause" aria-label="Pause">&#10074;&#10074;</button>`;
  document.body.appendChild(root);
  const $ = id => document.getElementById(id);
  const stick = $('tStick'), knob = $('tKnob');
  const LOOK_GAIN = 1.9;   // touch drags turn faster than mouse pixels
  const STICK_R = 56;

  input.touchMove = { x: 0, z: 0 };
  input.jumpHeld = false;

  // ---- move stick (appears where the thumb lands) ----
  let moveId = null, ox = 0, oy = 0;
  $('tLeft').addEventListener('touchstart', e => {
    e.preventDefault();
    if (moveId !== null) return;
    const t = e.changedTouches[0]; moveId = t.identifier; ox = t.clientX; oy = t.clientY;
    stick.style.left = ox + 'px'; stick.style.top = oy + 'px'; stick.classList.add('on');
    knob.style.transform = 'translate(-50%,-50%)';
  }, { passive: false });
  // ---- look drags (right half, and the fire button) ----
  const lookIds = new Map(); // touch id -> last x,y
  $('tRight').addEventListener('touchstart', e => {
    e.preventDefault();
    for (const t of e.changedTouches) lookIds.set(t.identifier, [t.clientX, t.clientY]);
  }, { passive: false });

  const press = (el, down, up) => {
    el.addEventListener('touchstart', e => {
      e.preventDefault(); el.classList.add('down');
      for (const t of e.changedTouches) down(t);
    }, { passive: false });
    el.addEventListener('touchend', e => { e.preventDefault(); if (!e.touches.length || ![...e.touches].some(t => t.target === el)) el.classList.remove('down'); for (const t of e.changedTouches) up?.(t); }, { passive: false });
    el.addEventListener('touchcancel', () => { el.classList.remove('down'); up?.({}); });
  };
  let fireId = null;
  press($('tFire'), t => { fireId = t.identifier; lookIds.set(t.identifier, [t.clientX, t.clientY]); if (isPlaying()) input.fire = true; }, t => { if (t.identifier === fireId) { fireId = null; input.fire = false; } });
  press($('tJump'), () => { input.jumpPressed = true; input.jumpHeld = true; }, () => { input.jumpHeld = false; });
  press($('tDash'), () => { input.dashPressed = true; });
  $('tPause').addEventListener('touchstart', e => { e.preventDefault(); if (isPlaying()) onPause(); }, { passive: false });

  addEventListener('touchmove', e => {
    for (const t of e.changedTouches) {
      if (t.identifier === moveId) {
        let dx = t.clientX - ox, dy = t.clientY - oy;
        const d = Math.hypot(dx, dy);
        if (d > STICK_R) { dx *= STICK_R / d; dy *= STICK_R / d; }
        knob.style.transform = `translate(calc(-50% + ${dx}px), calc(-50% + ${dy}px))`;
        input.touchMove.x = dx / STICK_R; input.touchMove.z = -dy / STICK_R;
      } else if (lookIds.has(t.identifier)) {
        const [lx, ly] = lookIds.get(t.identifier);
        if (isPlaying()) { input.look.dx += (t.clientX - lx) * LOOK_GAIN; input.look.dy += (t.clientY - ly) * LOOK_GAIN; }
        lookIds.set(t.identifier, [t.clientX, t.clientY]);
      }
    }
    if (isPlaying()) e.preventDefault();
  }, { passive: false });
  const end = e => {
    for (const t of e.changedTouches) {
      if (t.identifier === moveId) { moveId = null; input.touchMove.x = input.touchMove.z = 0; stick.classList.remove('on'); }
      lookIds.delete(t.identifier);
      if (t.identifier === fireId) { fireId = null; input.fire = false; }
    }
  };
  addEventListener('touchend', end); addEventListener('touchcancel', end);

  return {
    show(on) { root.classList.toggle('on', on); },
    reset() { moveId = null; fireId = null; lookIds.clear(); input.touchMove.x = input.touchMove.z = 0; input.fire = false; input.jumpHeld = false; stick.classList.remove('on'); },
  };
}
