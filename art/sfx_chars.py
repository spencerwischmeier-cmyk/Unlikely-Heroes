# Creature SFX for the characters (ElevenLabs sound generation) -> godot/audio/sfx/chars_*.ogg
#   python3 art/sfx_chars.py [name...]
# Each sound is generated as mp3 (kept in /tmp/claude-0/el/chars/chars_*.mp3), then trimmed and converted to ogg.
import json, os, subprocess, sys, urllib.request
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'godot', 'audio', 'sfx')
TMP = '/tmp/claude-0/el/chars'
os.makedirs(TMP, exist_ok=True)
S = {
    'chars_bot_break': ("Small cartoon robot breaking apart: a crunchy metal pop, then a shower of bolts, nuts and little gears "
                        "clattering and bouncing on a metal floor, short and punchy", 1.4),
    'chars_roller_wake': ("Cute grumpy little robot waking up: a rising servo whirr, two quick electronic chirps and a tiny metal "
                          "rattle, cartoon", 0.9),
    'chars_roller_hop': ("Small rolling robot does a springy hop: a bouncy metal boing with a short servo squeak, cartoon", 0.7),
    'chars_crew_grumble': ("Gruff little worker robot muttering in grumbly electronic beeps and boops, annoyed, short, cartoon", 1.2),
    'chars_hornet_dive': ("Small mechanical wasp drone diving past: an angry tinny buzzing whine that pitches up, cartoon", 1.0),
    'chars_crane_roar': ("Huge construction crane robot roaring: a deep industrial air horn blast mixed with grinding gears "
                         "and hissing hydraulics, angry and cartoonish", 2.2),
    'chars_crane_hurt': ("Big metal robot taking a heavy hit: a deep metallic clang, a sputtering engine cough and a hiss of steam", 1.1),
    'chars_gizmart_hop': ("Cheerful vending machine robot hops in delight: a happy cash register cha-ching, coins jingling and a "
                          "springy boing", 1.0),
    'chars_dodger_happy': ("Tiny cute hover drone happy chirp: a quick rising trill of bright electronic beeps", 0.7),
    'chars_dodger_worried': ("Tiny cute hover drone worried warble: a falling wobbly electronic beep, uh-oh", 0.7),
    'chars_grudd_stomp': ("Giant factory robot heavy footstep: a massive metal stomp that shakes the floor, with a clank of loose "
                          "plates", 1.0),
    'chars_grudd_steam': ("Factory smokestack whistle on a giant robot: a short loud steam whistle toot followed by a hiss", 1.4),
}
def gen(name):
    text, dur = S[name]
    mp3 = f'{TMP}/{name}.mp3'
    if not os.path.exists(mp3):
        body = json.dumps({'text': text, 'duration_seconds': max(0.6, dur), 'prompt_influence': 0.5}).encode()
        r = urllib.request.Request('https://api.elevenlabs.io/v1/sound-generation', data=body, headers={'Content-Type': 'application/json'})
        open(mp3, 'wb').write(urllib.request.urlopen(r, timeout=120).read())
    ogg = os.path.abspath(f'{OUT}/{name}.ogg')
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', mp3, '-af',
                    'silenceremove=start_periods=1:start_threshold=-50dB,afade=t=out:st=%.2f:d=0.12' % max(0.1, dur - 0.12),
                    '-ac', '1', '-c:a', 'libvorbis', '-q:a', '5', ogg], check=True)
    print(name, os.path.getsize(ogg) // 1024, 'KB', flush=True)
for n in (sys.argv[1:] or list(S)):
    try: gen(n)
    except Exception as e: print('ERR', n, e, flush=True)
