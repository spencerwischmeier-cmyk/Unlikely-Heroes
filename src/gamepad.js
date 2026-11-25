// Gamepad support (Xbox/PlayStation/Steam Controller and others that the browser exposes as a gamepad,
// including ones paired to a phone over Bluetooth). Uses the browser's "standard" button layout:
//   left stick move, right stick aim, RT fire, LT or B dash, A jump, X/Y or RB next weapon,
//   LB hold for the weapon wheel, d-pad picks a weapon directly, Start/Select pause.
const DEAD = 0.16;
const dz = v => (Math.abs(v) < DEAD ? 0 : (v - Math.sign(v) * DEAD) / (1 - DEAD));
const BTN = { A: 0, B: 1, X: 2, Y: 3, LB: 4, RB: 5, LT: 6, RT: 7, SELECT: 8, START: 9, LS: 10, RS: 11, UP: 12, DOWN: 13, LEFT: 14, RIGHT: 15 };

export function createGamepad() {
  let prev = [];
  let active = false; // true once a pad has been used, until touch/mouse input takes over
  const state = { connected: false, active: false, name: '' };

  function pressedOf(gp, i) {
    const b = gp.buttons[i]; if (!b) return false;
    return b.pressed || b.value > 0.4;
  }

  // read the first connected pad; returns null if there is none
  function poll() {
    const pads = navigator.getGamepads ? [...navigator.getGamepads()] : [];
    const gp = pads.find(p => p && p.connected && p.buttons.length >= 4);
    state.connected = !!gp;
    if (!gp) { prev = []; return null; }
    state.name = gp.id;
    const now = gp.buttons.map((_, i) => pressedOf(gp, i)), before = prev;
    // some pads report the triggers as axes instead of buttons
    const trig = i => Math.max(gp.buttons[i]?.value ?? 0, 0);
    const out = {
      mx: dz(gp.axes[0] ?? 0), mz: -dz(gp.axes[1] ?? 0), lx: dz(gp.axes[2] ?? 0), ly: dz(gp.axes[3] ?? 0),
      fire: trig(BTN.RT) > 0.3,
      held: i => now[i], pressed: i => now[i] && !before[i],
      BTN,
    };
    const any = now.some(Boolean) || Math.abs(out.mx) + Math.abs(out.mz) + Math.abs(out.lx) + Math.abs(out.ly) > 0.3;
    if (any && !active) { active = true; document.body.classList.add('pad'); }
    prev = now;
    state.active = active;
    return out;
  }
  // touch or mouse use hands the screen back to the on-screen controls
  const release = () => { if (active) { active = false; document.body.classList.remove('pad'); } };
  addEventListener('touchstart', release, { passive: true });
  addEventListener('mousedown', release);

  addEventListener('gamepadconnected', () => { state.connected = true; });
  addEventListener('gamepaddisconnected', () => { state.connected = false; release(); });
  return { poll, state, BTN };
}
