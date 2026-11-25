// Menu screens (title, pause, settings, game over). Works with mouse, touch, keyboard and controller:
// up/down move between buttons, left/right change a setting, A/Enter selects, B/Esc goes back.
import { buildSettings } from './settings.js';
import { sfx, music } from './audio.js';

const $ = id => document.getElementById(id);
const SCREENS = ['title', 'pauseMenu', 'settingsMenu', 'over'];

export function createMenu(onAction) {
  let current = 'title', back = 'title', focus = 0;
  buildSettings($('setList'));
  const items = () => [...$(current).querySelectorAll('.mbtn, .srow')].filter(e => e.offsetParent !== null);
  function setFocus(i) {
    const list = items(); if (!list.length) return;
    focus = (i + list.length) % list.length;
    list.forEach((e, k) => e.classList.toggle('focus', k === focus));
    list[focus].scrollIntoView?.({ block: 'nearest' });
  }
  function show(name) {
    SCREENS.forEach(s => $(s).classList.toggle('hidden', s !== name));
    if (name === 'settingsMenu' && current !== 'settingsMenu') back = current;
    current = name;
    document.body.classList.add('menu-open');
    if (name) setFocus(0);
  }
  function hide() { SCREENS.forEach(s => $(s).classList.add('hidden')); current = null; document.body.classList.remove('menu-open'); }
  for (const s of SCREENS) $(s).addEventListener('click', e => {
    const b = e.target.closest('[data-act]'); if (!b || b.disabled) return;
    act(b.dataset.act);
  });
  function act(a) {
    sfx.uiSelect(); music.start();
    if (a === 'settings') return show('settingsMenu');
    if (a === 'back') return show(back);
    onAction(a);
  }
  function nav(dir) { if (current) { setFocus(focus + dir); sfx.ui(); } }
  function adjust(dir) { const e = items()[focus]; if (e?.adjust) { e.adjust(dir); sfx.ui(); } }
  function select() { const e = items()[focus]; if (!e) return; if (e.activate) e.activate(); else if (e.dataset.act) act(e.dataset.act); }
  function cancel() {
    if (current === 'settingsMenu') show(back);
    else if (current === 'pauseMenu') onAction('resume');
  }
  addEventListener('keydown', e => {
    if (!current) return;
    if (e.code === 'ArrowDown' || e.code === 'KeyS') nav(1);
    else if (e.code === 'ArrowUp' || e.code === 'KeyW') nav(-1);
    else if (e.code === 'ArrowLeft' || e.code === 'KeyA') adjust(-1);
    else if (e.code === 'ArrowRight' || e.code === 'KeyD') adjust(1);
    else if (e.code === 'Enter') select();
    else if (e.code === 'Escape' || e.code === 'Backspace') cancel();
    else return;
    e.preventDefault();
  });
  // controller: called every frame with the polled pad while a menu is open
  let repeatT = 0, lastDir = 0;
  function pad(p, dt) {
    if (!current || !p) return;
    const B = p.BTN;
    const v = p.held(B.DOWN) || p.mz < -0.6 ? 1 : p.held(B.UP) || p.mz > 0.6 ? -1 : 0;
    const h = p.held(B.RIGHT) || p.mx > 0.6 ? 1 : p.held(B.LEFT) || p.mx < -0.6 ? -1 : 0;
    const dir = v * 10 + h;
    repeatT -= dt;
    if (dir !== lastDir || (dir && repeatT <= 0)) {
      if (v) nav(v); else if (h) adjust(h);
      repeatT = dir === lastDir ? 0.12 : 0.35;
    }
    lastDir = dir;
    if (p.pressed(B.A)) select();
    if (p.pressed(B.B)) cancel();
    if (p.pressed(B.START) && current === 'pauseMenu') onAction('resume');
  }
  return { show, hide, pad, get current() { return current; } };
}
