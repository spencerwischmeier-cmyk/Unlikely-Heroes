# Dodger's fight callouts (systems/dodger.gd CALLS: Plated Roller, shell crack, Crane Bot phase change, Quake Stomp)
# ElevenLabs eleven_v3 text-to-speech with audio tags -> godot/audio/voice/dodger_<kind>_<n>.ogg, levelled to his
# other barks (about -17 LUFS, mono, vorbis q5). The texts (tags included) also go in audio/voice/script.json "dodger".
#   python3 art/voice_dodger_calls.py
import json, os, subprocess, urllib.request
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'godot', 'audio', 'voice')
TMP = '/tmp/claude-0/el/dodger_calls'
os.makedirs(TMP, exist_ok=True)
VOICE = 'g1ZuD53LC44Pa8ZFcL0Z'   # "UH Dodger"
L = {
 'platedFirst': ["[alarmed] Plated one! Bolts just bounce off. Wrench it, or stomp it!"],
 'plated': ["[scoffs] Another tin can. Wrench it!", "[urgent] Armoured roller! Crack the shell!",
            "[amused] That one's wearing a saucepan. Wrench!"],
 'crackFirst': ["[delighted] Shell's off! Now it's just a regular grumpy ball."],
 'crack': ["[cheering] Cracked it!", "[laughing] Peeled like a tin of beans!", "[gleeful] Ha! No more armour for you."],
 'phase2First': ["[shocked] It ripped its own arm off. [pause] That's... commitment. [urgent] Grind the track rail!"],
 'phase2': ["[nervous] Here we go again!"],
 'quakeFirst': ["[shouting] It's rearing up! Jump the shockwaves, jump!"],
 'quake': ["[shouting] Jump! Jump!", "[urgent] Shockwaves! Up, up!", "[shouting] Rings again! Hop!"],
}

def gen(kind, i):
    text = L[kind][i]
    name = f'dodger_{kind}_{i + 1}'
    mp3 = f'{TMP}/{name}.mp3'
    if not os.path.exists(mp3):
        body = json.dumps({'text': text, 'model_id': 'eleven_v3',
                           'voice_settings': {'stability': 0.5, 'similarity_boost': 0.8, 'use_speaker_boost': True}}).encode()
        r = urllib.request.Request(f'https://api.elevenlabs.io/v1/text-to-speech/{VOICE}?output_format=mp3_44100_128',
                                   data=body, headers={'Content-Type': 'application/json'})
        open(mp3, 'wb').write(urllib.request.urlopen(r, timeout=180).read())
    trim = 'silenceremove=start_periods=1:start_threshold=-45dB,areverse,silenceremove=start_periods=1:start_threshold=-45dB,areverse'
    wav = f'{TMP}/{name}.wav'
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', mp3, '-af', trim, '-ac', '1', '-ar', '44100', wav], check=True)
    # level to his other barks: -17 LUFS, peaks under -1.3 dBFS
    st = subprocess.run(['ffmpeg', '-i', wav, '-af', 'loudnorm=print_format=json', '-f', 'null', '-'], capture_output=True, text=True).stderr
    li = float(json.loads(st[st.rindex('{'):st.rindex('}') + 1])['input_i'])
    pk = subprocess.run(['ffmpeg', '-i', wav, '-af', 'volumedetect', '-f', 'null', '-'], capture_output=True, text=True).stderr
    peak = float(pk.split('max_volume: ')[1].split(' dB')[0])
    gain = min(-17.0 - li, -1.3 - peak)
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', wav, '-af', f'volume={gain:.2f}dB', '-c:a', 'libvorbis', '-q:a', '5',
                    os.path.abspath(f'{OUT}/{name}.ogg')], check=True)
    return name, f'in={li:.1f} gain={gain:.1f}'

if __name__ == '__main__':
    import concurrent.futures as cf
    jobs = [(k, i) for k in L for i in range(len(L[k]))]
    with cf.ThreadPoolExecutor(4) as ex:
        for f in cf.as_completed([ex.submit(gen, *j) for j in jobs]):
            try: print(*f.result(), flush=True)
            except Exception as e: print('ERR', e, flush=True)
    # add (or refresh) the kinds in the "dodger" block of script.json, keeping its one-kind-per-line layout
    p = f'{OUT}/script.json'
    lines = open(p, encoding='utf-8').read().split('\n')
    lines = [l for l in lines if not any(l.startswith(f' "{k}": ') for k in L)]
    a = lines.index('"dodger": {'); b = lines.index('},', a)
    if not lines[b - 1].endswith(','): lines[b - 1] += ','
    add = [f' "{k}": {json.dumps(v, ensure_ascii=False)},' for k, v in L.items()]
    add[-1] = add[-1][:-1]
    lines[b:b] = add
    open(p, 'w', encoding='utf-8').write('\n'.join(lines))
    json.load(open(p, encoding='utf-8'))   # still valid
