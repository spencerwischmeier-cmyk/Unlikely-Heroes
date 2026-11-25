// Dodger, the sarcastic drone: talks in a speech bubble, runs the combo meter, rates your best shots out of
// ten and heckles the bots. Vesk answers now and then.
const pick = a => a[Math.floor(Math.random() * a.length)];

export const LINES = {
  spawn: ['Hey, bolt-brains! Over here! No, the other over here!', 'Incoming bots. Try to look busy.', 'More of them? Somebody\'s factory is working overtime.', 'Rust buckets at twelve o\'clock. Also two, four and nine.', 'Bots inbound. I\'ll supervise.', 'Oh good, a crowd. I love an audience.', 'Hey, you! Your warranty just expired!'],
  taunt: ['You call that rolling? My grandma had better bearings!', 'Nice paint job. Did a toaster pick it?', 'Is that a laser or are you just happy to see us?', 'Beep boop, you\'re scrap.', 'You missed! Oh wait, that was us. Never mind.', 'I\'ve seen scarier vending machines. Actually, I know one.'],
  hurt: ['Ow! I mean, you. Ow for you.', 'That looked expensive.', 'Maybe try being somewhere else when they shoot?', 'Hull dented. Pride also dented.'],
  low: ['Vesk, your hull is held together by spite.', 'We are VERY low on hull. Like, worryingly.', 'Grab a green cell before I have to write your eulogy.'],
  fall: ['Gravity: one. Vesk: zero.', 'That was the sky. We don\'t stand on the sky.', 'Back to the checkpoint. I won\'t tell anyone.', 'Have you tried NOT falling?'],
  grind: ['Grind time!', 'Wheee! I mean, how dignified.', 'Rail ride! Keep your arms inside the drone.'],
  air: ['Midair! Show-off.', 'From the sky! Fancy.'],
  far: ['Long shot! Lucky.', 'Sniped it. Okay, that was good.'],
  multi: ['Two for one! Thrifty.', 'Group discount!'],
  combo: ['Combo! Keep it going!', 'Look at you go!', 'Chain them, chain them!'],
  comboEnd: ['Combo over. It was beautiful while it lasted.', 'And the streak ends. Bonus nuts, though.'],
  rate: {
    low: ['Wow. A shot. {n} out of ten.', '{n} out of ten. Points for effort.', 'That one gets a {n}. Generous, I know.'],
    mid: ['Solid. {n} out of ten.', '{n} out of ten. Not bad, old man.', 'I\'ll give that a {n}.'],
    high: ['Okay, that was a {n}. Don\'t let it go to your head.', '{n} out of ten! I\'m telling everyone!', 'A {n}! Who taught you that? Oh right, me.'],
    perfect: ['TEN OUT OF TEN! Okay, nine. No, ten!', 'Perfect ten! Framing that one.'],
  },
};

export function createDodger({ isPlaying }) {
  const el = document.createElement('div'); el.id = 'talk';
  el.innerHTML = `<div class="face"></div><div class="bubble"><b></b><span></span></div>`;
  document.getElementById('hud').append(el);
  const combo = document.createElement('div'); combo.id = 'combo';
  combo.innerHTML = '<b>COMBO</b><span>x2</span><i><u></u></i>';
  document.getElementById('hud').append(combo);
  const stamp = document.createElement('div'); stamp.id = 'stamp'; document.getElementById('hud').append(stamp);
  const face = el.querySelector('.face'), who = el.querySelector('b'), text = el.querySelector('span');

  let showT = 0, gap = 0, queue = [];
  let chain = 0, chainT = 0, bestRating = 0, lastKillT = -9, sinceRate = 9, sinceChat = 0;
  const COMBO_TIME = 3;
  let onComboEnd = null;

  // speak now if nothing more important is showing; `prio` 2 = story, always shown (queued)
  function say(line, prio = 0, speaker = 'dodger') {
    if (!line) return;
    if (prio >= 2) { queue.push({ line, speaker }); if (showT <= 0) next(); return; }
    if (showT > 0.6 || gap > 0) return;
    show(line, speaker);
  }
  function show(line, speaker) {
    who.textContent = speaker === 'vesk' ? 'VESK' : speaker === 'giz' ? 'GIZMART' : 'DODGER';
    face.className = 'face ' + speaker;
    text.textContent = line;
    el.classList.remove('on'); void el.offsetWidth; el.classList.add('on');
    showT = Math.min(5.5, 1.6 + line.length * 0.045); gap = 0; sinceChat = 0;
  }
  function next() { const q = queue.shift(); if (q) show(q.line, q.speaker); }

  function rate(score) {
    const n = Math.max(1, Math.min(10, Math.round(score)));
    bestRating = Math.max(bestRating, n);
    stamp.textContent = `${n}/10`;
    stamp.className = 'on' + (n >= 8 ? ' hi' : '');
    void stamp.offsetWidth;
    const set = n >= 10 ? LINES.rate.perfect : n >= 8 ? LINES.rate.high : n >= 5 ? LINES.rate.mid : LINES.rate.low;
    say(pick(set).replace('{n}', n), 1);
    sinceRate = 0;
  }

  // called for every bot wrecked; ctx: { airborne, grinding, dist, sameFrame, weapon }
  function kill(info) {
    const now = performance.now() / 1000;
    const multi = now - lastKillT < 0.05; lastKillT = now;
    chain = chainT > 0 ? chain + 1 : 1; chainT = COMBO_TIME;
    let score = 4 + Math.random() * 1.5;
    if (info.airborne) score += 2; if (info.grinding) score += 3; if (info.dist > 20) score += 1.5;
    if (multi) score += 2; score += Math.min(3, (chain - 1) * 0.6);
    if (info.boss) score = 10;
    const notable = info.boss || info.grinding || (info.airborne && Math.random() < 0.6) || multi || info.dist > 24;
    if ((notable && sinceRate > 2.5) || (sinceRate > 9 && Math.random() < 0.35)) rate(score);
    else if (chain === 3 || chain === 6) say(pick(LINES.combo));
    else if (info.grinding) say(pick(LINES.grind));
    else if (multi) say(pick(LINES.multi));
    else if (info.airborne && Math.random() < 0.3) say(pick(LINES.air));
    else if (info.dist > 22 && Math.random() < 0.4) say(pick(LINES.far));
  }

  function update(dt) {
    if (!isPlaying()) return;
    showT -= dt; sinceRate += dt; sinceChat += dt;
    if (showT <= 0) { if (queue.length) next(); else { el.classList.remove('on'); gap -= dt; } }
    if (chainT > 0) {
      chainT -= dt;
      if (chainT <= 0) { if (chain >= 3) { onComboEnd?.(chain); say(pick(LINES.comboEnd)); } chain = 0; }
    }
    combo.classList.toggle('on', chain >= 2 && chainT > 0);
    if (chain >= 2) { combo.querySelector('span').textContent = 'x' + chain; combo.querySelector('u').style.width = `${(100 * chainT / COMBO_TIME).toFixed(0)}%`; }
  }

  return {
    say, kill, update, rate,
    line: (k, prio = 0) => say(pick(LINES[k]), prio),
    story: (speaker, line) => say(line, 2, speaker),
    set onComboEnd(f) { onComboEnd = f; },
    get chain() { return chain; }, get best() { return bestRating; }, get sinceChat() { return sinceChat; },
    reset() { queue = []; showT = 0; chain = 0; chainT = 0; bestRating = 0; sinceRate = 9; el.classList.remove('on'); combo.classList.remove('on'); },
  };
}
