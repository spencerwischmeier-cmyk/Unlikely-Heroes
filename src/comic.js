// Comic panels between levels: one panel at a time with a caption and speech bubbles.
// Tap, click, Enter, Space or A goes to the next panel; Skip, Esc or B skips the rest.
// The panel pictures are rendered in Blender (art/comic.py) into public/comic/.
import { sfx } from './audio.js';

const b = (who, text, x, y, tail = 'down') => ({ who, text, x, y, tail });
export const INTRO = [
  { img: 'comic/intro1.jpg', caption: 'The junkyard at the edge of Skyharbor. Home of Vesk, retired mechanic.',
    bubbles: [b('vesk', 'Finally. Nothing left to fix.', 58, 18, 'left')] },
  { img: 'comic/intro2.jpg', caption: 'Then, at the exact same moment, every bot on every planet went haywire.',
    bubbles: [b('bot', 'WORK. WORK. WORK.', 12, 16, 'down'), b('bot', 'SCRAP. THE. ROCK.', 64, 12, 'down')] },
  { img: 'comic/intro3.jpg', caption: '',
    bubbles: [b('dodger', 'Good news: I traced the signal that\'s making them do that!', 6, 10, 'right'), b('dodger', 'Bad news: it\'s coming from everywhere. Starting with the docks.', 46, 70, 'up')] },
  { img: 'comic/intro4.jpg', caption: 'And so, very much against his will...',
    bubbles: [b('vesk', 'Fine. Let\'s go unplug it.', 8, 14, 'right'), b('dodger', 'That\'s the spirit! Sort of!', 60, 70, 'up')] },
];
export const OUTRO = [
  { img: 'comic/outro1.jpg', caption: 'The Crane Yard, a few minutes later.',
    bubbles: [b('dodger', 'Crane Bot: scrapped. I\'d rate that a nine.', 50, 4, 'down'), b('vesk', 'Only nine?', 6, 30, 'right')] },
  { img: 'comic/outro2.jpg', caption: 'Then the wreck\'s radio crackled to life.',
    bubbles: [b('grudd', 'WORK CREWS. RESUME CONSTRUCTION.', 3, 8, 'right'), b('grudd', 'EVERY PLANET WILL BE ONE BIG FACTORY. THIS IS FOREMAN GRUDD. END OF MESSAGE.', 3, 40, 'right')] },
  { img: 'comic/outro3.jpg', caption: 'The signal leads off-world.',
    bubbles: [b('vesk', 'A giant robot foreman. Of course.', 4, 34, 'down'), b('dodger', 'Road trip!', 70, 56, 'up')], end: 'SKYHARBOR COMPLETE' },
];
const NAMES = { vesk: 'VESK', dodger: 'DODGER', bot: '', grudd: 'FOREMAN GRUDD' };

let el = null, current = null;
function ensure() {
  if (el) return el;
  el = document.createElement('div'); el.id = 'comic'; el.className = 'hidden';
  el.innerHTML = `<div class="cpanel"><div class="cimg"></div><div class="ccap"></div><div class="cbubbles"></div><div class="cend"></div></div>
    <div class="cbar"><span class="cdots"></span><span class="chint">Tap to continue</span><button class="cskip">Skip</button></div>`;
  document.body.append(el);
  el.addEventListener('click', e => { if (e.target.closest('.cskip')) { e.stopPropagation(); finish(); } else advance(); });
  addEventListener('keydown', e => {
    if (!current) return;
    if (e.code === 'Enter' || e.code === 'Space' || e.code === 'ArrowRight') { advance(); e.preventDefault(); }
    else if (e.code === 'Escape') { finish(); e.preventDefault(); }
  });
  return el;
}
function render() {
  const { panels, i } = current, p = panels[i];
  const panel = el.querySelector('.cpanel');
  panel.classList.remove('in'); void panel.offsetWidth; panel.classList.add('in');
  const img = el.querySelector('.cimg');
  img.style.backgroundImage = `url(${p.img}), linear-gradient(135deg, #1b4d6b, #0b1f33)`;
  const cap = el.querySelector('.ccap'); cap.textContent = p.caption; cap.style.display = p.caption ? '' : 'none';
  el.querySelector('.cbubbles').innerHTML = p.bubbles.map((q, k) =>
    `<div class="cb ${q.who} t-${q.tail}" style="left:${q.x}%;top:${q.y}%;animation-delay:${0.25 + k * 0.45}s">${NAMES[q.who] ? `<b>${NAMES[q.who]}</b>` : ''}${q.text}</div>`).join('');
  const end = el.querySelector('.cend'); end.textContent = p.end || ''; end.style.display = p.end ? '' : 'none';
  el.querySelector('.cdots').innerHTML = panels.map((_, k) => `<i class="${k === i ? 'on' : ''}"></i>`).join('');
  current.shownAt = performance.now();
}
function advance() {
  if (!current || performance.now() - current.shownAt < 350) return; // don't skip a panel by accident
  sfx.ui();
  if (current.i < current.panels.length - 1) { current.i++; render(); } else finish();
}
function finish() {
  if (!current) return;
  const done = current.onDone; current = null;
  el.classList.add('hidden'); document.body.classList.remove('comic-open');
  sfx.uiSelect(); done?.();
}
export function playComic(panels, onDone) {
  ensure();
  // warm the images so panels don't pop in
  panels.forEach(p => { const im = new Image(); im.src = p.img; });
  current = { panels, i: 0, onDone, shownAt: 0 };
  el.classList.remove('hidden'); document.body.classList.add('comic-open');
  render();
}
// controller: A next, B or Start skips
export function comicPad(p) {
  if (!current || !p) return;
  if (performance.now() - current.shownAt < 120) return;
  if (p.pressed(p.BTN.A)) advance();
  else if (p.pressed(p.BTN.B) || p.pressed(p.BTN.START)) finish();
}
export const comicOpen = () => !!current;
