# Opening cutscene audio (ElevenLabs; the network secret adds the key):
#   python3 art/audio_intro.py score   -> godot/audio/music/intro/<cue>.ogg, one composed score split at the scene's beats
#   python3 art/audio_intro.py foley   -> godot/audio/sfx/foley_<name>.ogg
# Section lengths follow the beat marks the scene prints with --cut=intro --cut-log (see scene_intro.gd C.mark()).
import json, os, subprocess, sys, urllib.request
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'godot', 'audio')
TMP = '/tmp/claude-0/el/intro'
os.makedirs(TMP, exist_ok=True)

GLOBAL = ['cinematic orchestral cartoon score', 'Saturday-morning sci-fi adventure', 'warm, playful, lush',
          'live orchestra with jazz rhythm section', 'clear themes, film scoring, hits on the beats', 'instrumental']
NEG = ['vocals', 'singing', 'lyrics', 'EDM drop', 'lo-fi hiss', 'dubstep']
SECTIONS = [  # cue, ms, styles
    ('open', 31000, ['airy wonder', 'soft high strings', 'harp and celesta arpeggios', 'gentle glockenspiel melody',
                     'a floating city in the clouds at sunrise', 'slow swell into a warm main theme']),
    ('porch', 57300, ['lazy laid-back morning', 'brushed snare and upright bass', 'muted trumpet melody', 'ukulele and soft clarinet',
                      'cozy jazzy grumpy-old-man groove', 'sleepy, unhurried, a little cheeky']),
    ('tension', 34100, ['ticking pizzicato like a clock', 'low ominous synth drone under strings', 'comedic suspense',
                        'factory whistle motif in the low brass', 'tension slowly building', 'sparse and mysterious']),
    ('haywire', 26000, ['chaotic cartoon action', 'frantic xylophone runs and brass stabs', 'fast driving percussion',
                        'mischievous robots running wild', 'big energy, playful panic']),
    ('porch_b', 3400, ['the lazy trumpet groove returns for a moment', 'smug and relaxed']),
    ('sting', 5100, ['comedic orchestral disaster hit', 'cymbal crash and a descending trombone wah', 'then near silence']),
    ('hero', 18000, ['heroic brass fanfare of the main theme', 'determined, adventurous', 'strong taiko and snare drums',
                     'builds and ends on a confident final hit']),
]

def score():
    mp3 = f'{TMP}/score.mp3'
    if not os.path.exists(mp3):
        plan = {'positive_global_styles': GLOBAL, 'negative_global_styles': NEG,
                'sections': [{'section_name': c, 'positive_local_styles': st, 'negative_local_styles': [], 'duration_ms': ms, 'lines': []}
                             for c, ms, st in SECTIONS]}
        body = json.dumps({'composition_plan': plan, 'model_id': 'music_v1'}).encode()
        r = urllib.request.Request('https://api.elevenlabs.io/v1/music?output_format=mp3_44100_192', data=body,
                                   headers={'Content-Type': 'application/json'})
        open(mp3, 'wb').write(urllib.request.urlopen(r, timeout=600).read())
    out = os.path.abspath(f'{ROOT}/music/intro'); os.makedirs(out, exist_ok=True)
    t = 0.0
    for c, ms, _ in SECTIONS:
        d = ms / 1000.0
        # each cue runs on past its section (the next cue crossfades in over it), 2 s tail with a fade
        tail = 2.0 if c not in ('hero',) else 6.0
        subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-ss', '%.3f' % t, '-t', '%.3f' % (d + tail), '-i', mp3,
                        '-af', 'afade=t=out:st=%.2f:d=%.2f' % (d + tail - 1.5, 1.5), '-c:a', 'libvorbis', '-q:a', '6',
                        f'{out}/{c}.ogg'], check=True)
        print(c, round(t, 2), d)
        t += d

FOLEY = {
    'chair_creak': ("Old wooden porch chair creaks as a heavy person settles back into it, slow and satisfying", 1.6),
    'mug_sip': ("A long loud happy sip of hot coffee from a mug, close up", 1.6),
    'mug_slurp': ("A rude loud slurp of coffee from a mug, close up, comedic", 1.3),
    'clock_tick': ("A single loud mechanical clock tick, close and dry", 0.5),
    'punch_clock': ("An old mechanical time card punch clock: card slides in, a heavy ka-chunk stamp and a small bell ding", 1.2),
    'toaster_growl': ("A small kitchen toaster growling like an angry little dog, metallic rattle and low electrical rumble, cartoon", 1.8),
    'boot_land': ("Heavy boots landing on a wooden porch deck after a hop, a thud and a creak", 0.7),
    'chair_crunch': ("A wooden chair crushed and chewed by a small robot: splintering wood, crunching, metal munching, cartoon", 1.8),
    'scrap_crash': ("A small drone crashes into a pile of scrap metal: a clattering crash, tin cans and metal parts tumbling, comedic", 1.8),
    'porch_tone': ("Peaceful morning ambience on a junkyard porch high in a sky city: soft wind, distant gulls, a far off airship engine hum, "
                   "faint wind chimes and the odd creak of settling metal, calm, no music", 22.0),
}
def foley(names):
    out = os.path.abspath(f'{ROOT}/sfx')
    for n in names:
        text, dur = FOLEY[n]
        mp3 = f'{TMP}/{n}.mp3'
        if not os.path.exists(mp3):
            body = json.dumps({'text': text, 'duration_seconds': dur, 'prompt_influence': 0.55, 'loop': n.endswith('_tone')}).encode()
            r = urllib.request.Request('https://api.elevenlabs.io/v1/sound-generation', data=body, headers={'Content-Type': 'application/json'})
            open(mp3, 'wb').write(urllib.request.urlopen(r, timeout=180).read())
        af = 'silenceremove=start_periods=1:start_threshold=-50dB,afade=t=out:st=%.2f:d=0.15' % max(0.1, dur - 0.15)
        if n.endswith('_tone'): af = 'anull'
        subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', mp3, '-af', af, '-ac', '1' if not n.endswith('_tone') else '2',
                        '-c:a', 'libvorbis', '-q:a', '5', f'{out}/foley_{n}.ogg'], check=True)
        print(n, os.path.getsize(f'{out}/foley_{n}.ogg') // 1024, 'KB', flush=True)

if __name__ == '__main__':
    what = sys.argv[1] if len(sys.argv) > 1 else 'all'
    if what in ('score', 'all'): score()
    if what in ('foley', 'all'): foley(sys.argv[2:] or list(FOLEY))
