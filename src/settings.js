// Player settings, saved on this device. The settings screen is built from the SPEC list below.
const KEY = 'uh-settings-v1';
const SPEC = [
  { key: 'volume', label: 'Master volume', type: 'range', min: 0, max: 1, step: 0.05, def: 0.8 },
  { key: 'sfxVolume', label: 'Sound effects', type: 'range', min: 0, max: 1, step: 0.05, def: 0.9 },
  { key: 'musicVolume', label: 'Music', type: 'range', min: 0, max: 1, step: 0.05, def: 0.6 },
  { key: 'sens', label: 'Look sensitivity', type: 'range', min: 0.3, max: 2.5, step: 0.1, def: 1 },
  { key: 'padSens', label: 'Controller aim speed', type: 'range', min: 0.3, max: 2.5, step: 0.1, def: 1 },
  { key: 'invertY', label: 'Invert look up/down', type: 'toggle', def: false },
  { key: 'aimAssist', label: 'Aim assist (touch and controller)', type: 'toggle', def: true },
  { key: 'autoFire', label: 'Auto-fire when on target (touch)', type: 'toggle', def: false },
  { key: 'btnScale', label: 'Touch button size', type: 'range', min: 0.8, max: 1.4, step: 0.05, def: 1 },
  { key: 'vibrate', label: 'Vibration', type: 'toggle', def: true },
  { key: 'quality', label: 'Graphics', type: 'choice', options: [['auto', 'Auto'], ['high', 'High'], ['low', 'Light (faster)']], def: 'auto', reload: true },
];

export const settings = Object.fromEntries(SPEC.map(s => [s.key, s.def]));
try { Object.assign(settings, JSON.parse(localStorage.getItem(KEY) || '{}')); } catch { /* ignore broken saves */ }
const listeners = [];
export const onSettings = fn => listeners.push(fn);
function save() { try { localStorage.setItem(KEY, JSON.stringify(settings)); } catch { /* private mode */ } listeners.forEach(f => f(settings)); }

// Builds the rows of the settings screen into `el`. Each row is focusable for controller navigation and
// reacts to left/right (adjust) and A (toggle).
export function buildSettings(el) {
  el.innerHTML = '';
  for (const s of SPEC) {
    const row = document.createElement('div'); row.className = 'srow'; row.tabIndex = 0; row.dataset.key = s.key;
    const label = document.createElement('label'); label.textContent = s.label; row.append(label);
    const ctl = document.createElement('div'); ctl.className = 'sctl'; row.append(ctl);
    const render = () => {
      const v = settings[s.key];
      if (s.type === 'range') ctl.innerHTML = `<input type="range" min="${s.min}" max="${s.max}" step="${s.step}" value="${v}"><span>${(+v).toFixed(s.step < 0.1 ? 2 : 1)}</span>`;
      else if (s.type === 'toggle') ctl.innerHTML = `<button class="tog ${v ? 'on' : ''}">${v ? 'On' : 'Off'}</button>`;
      else ctl.innerHTML = `<button class="tog on">${s.options.find(o => o[0] === v)?.[1] ?? v}</button>`;
      const inp = ctl.querySelector('input');
      if (inp) inp.addEventListener('input', () => { settings[s.key] = +inp.value; ctl.querySelector('span').textContent = (+inp.value).toFixed(s.step < 0.1 ? 2 : 1); save(); });
      ctl.querySelector('button')?.addEventListener('click', e => { e.stopPropagation(); row.adjust(1); });
    };
    row.adjust = dir => {
      if (s.type === 'range') settings[s.key] = Math.round(Math.min(s.max, Math.max(s.min, settings[s.key] + dir * s.step)) * 100) / 100;
      else if (s.type === 'toggle') settings[s.key] = !settings[s.key];
      else { const i = s.options.findIndex(o => o[0] === settings[s.key]); settings[s.key] = s.options[(i + dir + s.options.length) % s.options.length][0]; }
      save(); render();
      if (s.reload) row.querySelector('label').textContent = `${s.label} (applies after reload)`;
    };
    row.activate = () => row.adjust(1);
    render(); el.append(row);
  }
}
