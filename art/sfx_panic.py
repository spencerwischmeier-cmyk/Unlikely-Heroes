# Panic pass SFX (ElevenLabs sound generation) -> godot/audio/sfx/panic_*.ogg
#   python3 art/sfx_panic.py [name...]
# Loops (name ends in _loop) get a short crossfade so they repeat without a click.
import json, os, subprocess, sys, urllib.request
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'godot', 'audio', 'sfx')
TMP = '/tmp/claude-0/el/panic'
os.makedirs(TMP, exist_ok=True)
S = {
    'panic_crowd_loop': ("Large crowd of townspeople panicking in a city street, overlapping worried shouts, gasps and cries, people "
                         "running, no clear words, slightly distant, cartoon animated film", 12.0),
    'panic_crowd_near_loop': ("Small group of frightened townspeople nearby, nervous murmuring, gasps, quick footsteps hurrying past, "
                              "no clear words", 10.0),
    'panic_siren_loop': ("Distant city-wide evacuation siren slowly rising and falling, a long mournful wail echoing over rooftops "
                         "and open sky", 12.0),
    'panic_ship_takeoff': ("Passenger shuttle spaceship lifts off: engines spool up with a rising whine, then a powerful rumbling "
                           "thrust roar that climbs away and fades into the sky", 7.0),
    'panic_ship_idle_loop': ("Small passenger spaceship hovering at a dock, steady low engine hum with a soft turbine whine and "
                             "gentle hiss", 6.0),
    'panic_skycar_zoom_1': ("Small flying hover car zooms past overhead fast, a doppler whoosh with a buzzy little engine", 2.0),
    'panic_skycar_zoom_2': ("Rattly old flying delivery van speeds past, engine sputtering, doppler whoosh, cartoon", 2.2),
    'panic_skycar_honk_1': ("Cartoon flying car horn honking three times, frantic and impatient", 1.2),
    'panic_skycar_honk_2': ("Squeaky little cartoon bulb horn and a deeper truck horn honking together in a traffic jam", 1.4),
    'panic_far_crash': ("Far away, a small flying car sputters and crashes: engine coughing, a distant metal crunch and a muffled pop", 2.4),
    'panic_pa_chime': ("Airport style public announcement chime, three soft ascending bell tones", 2.0),
    'panic_shuttle_horn': ("Big passenger airship departure horn, two long deep blasts echoing across a harbor", 3.0),
}
def gen(name):
    text, dur = S[name]
    mp3 = f'{TMP}/{name}.mp3'
    if not os.path.exists(mp3):
        body = json.dumps({'text': text, 'duration_seconds': dur, 'prompt_influence': 0.5}).encode()
        r = urllib.request.Request('https://api.elevenlabs.io/v1/sound-generation', data=body, headers={'Content-Type': 'application/json'})
        open(mp3, 'wb').write(urllib.request.urlopen(r, timeout=180).read())
    ogg = os.path.abspath(f'{OUT}/{name}.ogg')
    if name.endswith('_loop'):
        # crossfade the last second into the first so the loop repeats without a click
        import numpy as np
        raw = subprocess.run(['ffmpeg', '-loglevel', 'error', '-i', mp3, '-ac', '1', '-ar', '44100', '-f', 's16le', '-'],
                             capture_output=True, check=True).stdout
        x = np.frombuffer(raw, np.int16).astype(np.float32)
        n = 44100
        w = np.linspace(0, 1, n)
        y = x[n:].copy()
        y[-n:] = y[-n:] * (1 - w) + x[:n] * w
        subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-f', 's16le', '-ar', '44100', '-ac', '1', '-i', '-',
                        '-c:a', 'libvorbis', '-q:a', '4', ogg], input=y.clip(-32768, 32767).astype(np.int16).tobytes(), check=True)
    else:
        subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', mp3, '-af',
                        'silenceremove=start_periods=1:start_threshold=-50dB,afade=t=out:st=%.2f:d=0.15' % max(0.1, dur - 0.15),
                        '-ac', '1', '-c:a', 'libvorbis', '-q:a', '5', ogg], check=True)
    print(name, os.path.getsize(ogg) // 1024, 'KB', flush=True)
if __name__ == '__main__':
    import concurrent.futures as cf
    with cf.ThreadPoolExecutor(4) as ex:
        fs = {ex.submit(gen, n): n for n in (sys.argv[1:] or list(S))}
        for f in cf.as_completed(fs):
            try: f.result()
            except Exception as e: print('ERR', fs[f], e, flush=True)
