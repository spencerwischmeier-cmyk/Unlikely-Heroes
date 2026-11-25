// All sound is made in code with the Web Audio API (no audio files): weapon shots, hits, explosions,
// movement, pickups, UI blips and a looping background track. Volumes come from the settings screen.
import { settings, onSettings } from './settings.js';

let ctx = null, master, sfxBus, musicBus, noiseBuf, comp;
const rnd = (a, b) => a + (b - a) * Math.random();

function init() {
  if (ctx) return ctx;
  const AC = window.AudioContext || window.webkitAudioContext;
  if (!AC) return null;
  // on iPhones this lets the game play sound even when the ring/silent switch is on silent
  try { if (navigator.audioSession) navigator.audioSession.type = 'playback'; } catch { /* not supported */ }
  ctx = new AC({ latencyHint: 'interactive' });
  comp = ctx.createDynamicsCompressor(); comp.threshold.value = -14; comp.knee.value = 12; comp.ratio.value = 4;
  master = ctx.createGain(); sfxBus = ctx.createGain(); musicBus = ctx.createGain();
  sfxBus.connect(comp); musicBus.connect(comp); comp.connect(master); master.connect(ctx.destination);
  noiseBuf = ctx.createBuffer(1, ctx.sampleRate, ctx.sampleRate);
  const d = noiseBuf.getChannelData(0); for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
  applyVolumes();
  return ctx;
}
function applyVolumes() {
  if (!ctx) return;
  master.gain.value = settings.volume;
  sfxBus.gain.value = settings.sfxVolume;
  musicBus.gain.value = settings.musicVolume * 0.55;
}
onSettings(applyVolumes);

// browsers only allow sound after the player touches, clicks or presses a key
export function unlockAudio() {
  const c = init(); if (!c) return;
  if (c.state !== 'running') c.resume().catch(() => {});
}
for (const ev of ['pointerdown', 'touchend', 'keydown']) addEventListener(ev, unlockAudio, { capture: true, passive: true });

// ---------- building blocks ----------
function env(g, t, a, peak, d, end = 0.0001) {
  g.gain.setValueAtTime(0.0001, t);
  g.gain.linearRampToValueAtTime(peak, t + a);
  g.gain.exponentialRampToValueAtTime(end, t + a + d);
}
function tone({ type = 'sine', f0, f1 = f0, dur = 0.15, vol = 0.3, attack = 0.004, when = 0, bus = sfxBus, filter, detune = 0 }) {
  if (!ctx || ctx.state !== 'running') return;
  const t = ctx.currentTime + when;
  const o = ctx.createOscillator(); o.type = type; o.detune.value = detune;
  o.frequency.setValueAtTime(f0, t); if (f1 !== f0) o.frequency.exponentialRampToValueAtTime(Math.max(1, f1), t + dur);
  const g = ctx.createGain(); env(g, t, attack, vol, dur);
  let node = o;
  if (filter) { const fl = ctx.createBiquadFilter(); fl.type = filter.type || 'lowpass'; fl.frequency.value = filter.f; fl.Q.value = filter.q ?? 1; node.connect(fl); node = fl; }
  node.connect(g); g.connect(bus);
  o.start(t); o.stop(t + attack + dur + 0.05);
}
function noise({ dur = 0.2, vol = 0.3, type = 'bandpass', f0 = 1000, f1 = f0, q = 1, attack = 0.003, when = 0, bus = sfxBus }) {
  if (!ctx || ctx.state !== 'running') return;
  const t = ctx.currentTime + when;
  const s = ctx.createBufferSource(); s.buffer = noiseBuf; s.loop = true;
  const fl = ctx.createBiquadFilter(); fl.type = type; fl.Q.value = q;
  fl.frequency.setValueAtTime(f0, t); if (f1 !== f0) fl.frequency.exponentialRampToValueAtTime(Math.max(20, f1), t + dur);
  const g = ctx.createGain(); env(g, t, attack, vol, dur);
  s.connect(fl); fl.connect(g); g.connect(bus);
  s.start(t, Math.random() * 0.5); s.stop(t + attack + dur + 0.05);
}

// ---------- sound effects ----------
// `k` scales loudness for things far from the hero
const limit = new Map();
function ok(name, gap) { const now = performance.now(); if ((limit.get(name) || 0) > now) return false; limit.set(name, now + gap); return true; }

export const sfx = {
  lancer() { const p = rnd(0.94, 1.06); tone({ type: 'square', f0: 1500 * p, f1: 260 * p, dur: 0.09, vol: 0.09, filter: { f: 3000 } }); noise({ dur: 0.04, vol: 0.06, f0: 5000, q: 0.7 }); },
  scatter() { noise({ dur: 0.22, vol: 0.35, type: 'lowpass', f0: 3500, f1: 400 }); tone({ type: 'triangle', f0: 160, f1: 50, dur: 0.16, vol: 0.35 }); tone({ type: 'sine', f0: 1800, f1: 2600, dur: 0.12, vol: 0.05, when: 0.02 }); },
  lobber() { tone({ type: 'sine', f0: 210, f1: 70, dur: 0.22, vol: 0.45 }); noise({ dur: 0.1, vol: 0.12, type: 'lowpass', f0: 1200 }); tone({ type: 'sine', f0: 600, f1: 900, dur: 0.1, vol: 0.06, when: 0.05 }); },
  rocket() { noise({ dur: 0.35, vol: 0.14, f0: 600, f1: 2400, q: 1.5 }); tone({ type: 'sawtooth', f0: 220, f1: 440, dur: 0.12, vol: 0.04, filter: { f: 1200 } }); },
  bounce(k = 1) { if (ok('bounce', 60)) tone({ type: 'sine', f0: 320, f1: 180, dur: 0.08, vol: 0.12 * k }); },
  empty() { tone({ type: 'square', f0: 140, dur: 0.06, vol: 0.06, filter: { f: 900 } }); },
  overheat() { noise({ dur: 0.6, vol: 0.12, type: 'highpass', f0: 3000, f1: 6000 }); tone({ type: 'sawtooth', f0: 400, f1: 120, dur: 0.4, vol: 0.05, filter: { f: 1500 } }); },
  hit(k = 1) { if (ok('hit', 35)) tone({ type: 'triangle', f0: rnd(900, 1100), f1: 500, dur: 0.05, vol: 0.12 * k }); },
  targetHit() { if (ok('thit', 35)) { tone({ type: 'sine', f0: 1400, dur: 0.06, vol: 0.1 }); tone({ type: 'sine', f0: 2100, dur: 0.08, vol: 0.05, when: 0.02 }); } },
  targetDown() { [880, 1320, 1760].forEach((f, i) => tone({ type: 'triangle', f0: f, dur: 0.1, vol: 0.08, when: i * 0.05 })); },
  explosion(k = 1, big = 1) {
    if (!ok('boom', 40)) return;
    noise({ dur: 0.7 * big, vol: 0.5 * k, type: 'lowpass', f0: 2200, f1: 120, attack: 0.002 });
    tone({ type: 'sine', f0: 120, f1: 32, dur: 0.5 * big, vol: 0.55 * k });
    noise({ dur: 0.12, vol: 0.2 * k, type: 'highpass', f0: 3000 });
  },
  enemyShot(k = 1) { if (ok('eshot', 50)) { tone({ type: 'sawtooth', f0: 900, f1: 180, dur: 0.22, vol: 0.08 * k, filter: { f: 2000 } }); tone({ type: 'square', f0: 450, f1: 90, dur: 0.18, vol: 0.03 * k, filter: { f: 1200 } }); } },
  enemyCharge(k = 1) { if (ok('charge', 300)) tone({ type: 'sine', f0: 300, f1: 1200, dur: 0.6, vol: 0.05 * k }); },
  fuse(k = 1) { if (ok('fuse', 90)) tone({ type: 'square', f0: 1700, dur: 0.04, vol: 0.06 * k, filter: { f: 3000 } }); },
  spawn(k = 1) { if (ok('spawn', 120)) { tone({ type: 'sine', f0: 200, f1: 900, dur: 0.35, vol: 0.08 * k }); noise({ dur: 0.3, vol: 0.06 * k, f0: 400, f1: 3000 }); } },
  zap() { tone({ type: 'sawtooth', f0: 2400, f1: 800, dur: 0.12, vol: 0.05, filter: { f: 4000 } }); noise({ dur: 0.08, vol: 0.05, type: 'highpass', f0: 4000 }); },
  hurt() { tone({ type: 'sawtooth', f0: 220, f1: 70, dur: 0.3, vol: 0.25, filter: { f: 900 } }); noise({ dur: 0.2, vol: 0.2, type: 'lowpass', f0: 1500 }); },
  jump() { tone({ type: 'sine', f0: 280, f1: 620, dur: 0.12, vol: 0.12 }); noise({ dur: 0.08, vol: 0.04, f0: 1200 }); },
  boost() { noise({ dur: 0.4, vol: 0.18, f0: 500, f1: 2500, q: 0.8 }); tone({ type: 'triangle', f0: 300, f1: 700, dur: 0.25, vol: 0.07 }); },
  grind() { if (ok('grind', 70)) noise({ dur: 0.09, vol: 0.07, type: 'bandpass', f0: rnd(2600, 3400), q: 3 }); },
  swing() { noise({ dur: 0.16, vol: 0.22, f0: 900, f1: 3200, q: 1.2 }); },
  bash(v = 1) { noise({ dur: 0.12, vol: 0.35 * v, f0: 500, f1: 120, q: 0.8 }); },
  dash() { noise({ dur: 0.22, vol: 0.2, f0: 2500, f1: 600, q: 0.7 }); },
  land() { if (ok('land', 150)) { tone({ type: 'sine', f0: 140, f1: 60, dur: 0.1, vol: 0.18 }); noise({ dur: 0.08, vol: 0.06, type: 'lowpass', f0: 800 }); } },
  nut() { if (!ok('nut', 30)) return; const s = sfx._nutStep = ((sfx._nutStep || 0) + 1) % 8; tone({ type: 'sine', f0: 1300 * Math.pow(1.06, s), dur: 0.08, vol: 0.07 }); tone({ type: 'triangle', f0: 2600 * Math.pow(1.06, s), dur: 0.05, vol: 0.03 }); },
  cell() { [660, 880, 1100, 1320].forEach((f, i) => tone({ type: 'triangle', f0: f, dur: 0.12, vol: 0.09, when: i * 0.05 })); },
  ammo() { [500, 750].forEach((f, i) => tone({ type: 'square', f0: f, dur: 0.08, vol: 0.05, when: i * 0.07, filter: { f: 2500 } })); },
  levelUp() { [523, 659, 784, 1047, 1319].forEach((f, i) => tone({ type: 'triangle', f0: f, dur: 0.22, vol: 0.1, when: i * 0.07 })); },
  switchWeapon() { tone({ type: 'square', f0: 700, f1: 1100, dur: 0.05, vol: 0.05, filter: { f: 2500 } }); noise({ dur: 0.06, vol: 0.05, f0: 3000, when: 0.03 }); },
  wheelOpen() { noise({ dur: 0.25, vol: 0.08, f0: 3000, f1: 600 }); },
  ui() { tone({ type: 'sine', f0: 900, dur: 0.04, vol: 0.06 }); },
  uiSelect() { tone({ type: 'sine', f0: 700, f1: 1400, dur: 0.1, vol: 0.08 }); },
  waveStart() { [392, 523, 659].forEach((f, i) => tone({ type: 'sawtooth', f0: f, dur: 0.35, vol: 0.06, when: i * 0.12, filter: { f: 2000 } })); },
  waveClear() { [523, 659, 784, 1047].forEach((f, i) => tone({ type: 'triangle', f0: f, dur: 0.3, vol: 0.1, when: i * 0.09 })); },
  gameOver() { [392, 330, 262, 196].forEach((f, i) => tone({ type: 'sawtooth', f0: f, dur: 0.4, vol: 0.07, when: i * 0.18, filter: { f: 1200 } })); },
};

// ---------- music: a looping upbeat sky-city track, scheduled a little ahead of time ----------
const BPM = 112, STEP = 60 / BPM / 4; // sixteenth notes
// A minor: Am - F - C - G, two bars each
const CHORDS = [[57, 60, 64], [53, 57, 60], [48, 52, 55], [55, 59, 62]];
const LEAD = [76, null, 72, null, 74, 76, null, 79, 77, null, 76, null, 74, null, 72, null];
const midi = n => 440 * Math.pow(2, (n - 69) / 12);
let musicOn = false, nextT = 0, step = 0, timerId = 0, intensity = 0.5;

function scheduleStep(s, t) {
  const bar = Math.floor(s / 16), chord = CHORDS[Math.floor(bar / 2) % 4], i = s % 16;
  const bus = musicBus, play = (o) => { const w = t - ctx.currentTime; if (w > -0.01) o(Math.max(0, w)); };
  // kick on beats, snare-ish noise on 2 and 4, hats on off-beats
  if (i % 4 === 0) play(w => tone({ type: 'sine', f0: 150, f1: 45, dur: 0.16, vol: 0.5, when: w, bus }));
  if (i === 4 || i === 12) play(w => noise({ dur: 0.12, vol: 0.18 * intensity + 0.05, type: 'bandpass', f0: 1800, q: 0.8, when: w, bus }));
  if (i % 2 === 1) play(w => noise({ dur: 0.03, vol: 0.06, type: 'highpass', f0: 7000, when: w, bus }));
  // bass: root on eighths, octave bounce
  if (i % 2 === 0) play(w => tone({ type: 'sawtooth', f0: midi(chord[0] - 24 + (i % 8 === 6 ? 12 : 0)), dur: STEP * 1.6, vol: 0.16, when: w, bus, filter: { f: 500, q: 2 } }));
  // pad at the start of each bar
  if (i === 0) chord.forEach((n, k) => play(w => tone({ type: 'triangle', f0: midi(n), dur: STEP * 15, vol: 0.035, attack: 0.25, when: w, bus, detune: k * 4 })));
  // arpeggio sparkle
  if (i % 2 === 0) play(w => tone({ type: 'square', f0: midi(chord[(i / 2) % 3] + 12), dur: STEP * 0.8, vol: 0.022, when: w, bus, filter: { f: 2400 } }));
  // lead melody when the action is on
  const ln = LEAD[i]; if (ln && intensity > 0.6 && bar % 4 >= 2) play(w => tone({ type: 'square', f0: midi(ln - (Math.floor(bar / 2) % 4 === 1 ? 4 : 0)), dur: STEP * 1.8, vol: 0.03, when: w, bus, filter: { f: 3000 } }));
}
function tick() {
  if (!ctx || !musicOn) return;
  if (ctx.state === 'running') {
    if (nextT < ctx.currentTime) nextT = ctx.currentTime + 0.05;
    while (nextT < ctx.currentTime + 0.2) { scheduleStep(step++, nextT); nextT += STEP; }
  }
  timerId = setTimeout(tick, 50);
}
export const music = {
  start() { init(); if (musicOn) return; musicOn = true; tick(); },
  stop() { musicOn = false; clearTimeout(timerId); },
  set intensity(v) { intensity = v; },
};
export const audioState = () => (ctx ? ctx.state : 'none');
