# Panic music pass (ElevenLabs music) -> godot/audio/music/<name>.ogg + loop points in loops.json
#   python3 art/music_panic.py gen <name...>    generate (cached mp3 in TMP, never re-bought unless deleted)
#   python3 art/music_panic.py loop <name...>   bake a seamless loop from the cached mp3 and write the ogg
# Every Skyharbor area theme is the panic version (the signal hit without warning, the city is running);
# the old calmer themes live on as area_<a>_calm and come back once the Crane Bot is down.
# Each plan is intro -> A -> B (contrast) -> A' -> tail. The loop runs from the downbeat that starts A
# to the matching downbeat late in A'; the last beat before the loop end is crossfaded with the beat
# before A so the jump is seamless.
import json, os, subprocess, sys, urllib.request
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', 'godot', 'audio', 'music')
TMP = '/tmp/claude-0/el/music'
os.makedirs(TMP, exist_ok=True)

GLOBAL_POS = ["cartoon action adventure video game score", "urgent", "frantic", "rapid", "high energy", "panic",
              "chaotic emergency", "driving percussion", "instrumental", "tight mix", "loopable"]
GLOBAL_NEG = ["vocals", "singing", "choir words", "lyrics", "slow", "calm", "relaxed", "ambient", "lo-fi", "fade out"]

# per area: bpm, key, identity instruments, B-section twist
AREAS = {
    'area_plaza': (168, "D minor", ["brass section stabs", "racing staccato strings", "snare rolls", "orchestral city bustle",
                                    "tubular bell alarm hits", "taiko"],
                   "brass and strings trade a frantic call-and-response like a crowd stampeding through a town square"),
    'area_junkyard': (172, "E minor", ["junk percussion on oil drums and scrap metal", "twangy fast banjo", "slap bass",
                                       "rattling tin cans", "honky distorted harmonica", "breakbeat drums"],
                      "clattering scrap-metal drum breakdown with banjo shredding, things falling apart everywhere"),
    'area_terrace': (166, "A phrygian dominant", ["fast plucked oud and saz", "darbuka and frame drum", "pizzicato strings",
                                                  "market bells", "urgent flute runs"],
                     "bazaar chaos: tumbling hand drums and darting flute over a pulsing string ostinato"),
    'area_gardens': (164, "G minor", ["fast marimba ostinato", "frantic woodwinds and piccolo", "pizzicato strings",
                                      "pounding toms", "glockenspiel"],
                     "woodwinds scatter like startled birds over relentless marimba and toms"),
    'area_docks': (170, "C minor", ["furious accordion", "racing fiddles", "stomping bodhran and kick", "tuba bass",
                                    "ship bell hits", "brass blasts like foghorns"],
                   "a breakneck sea shanty reel gone into emergency mode, fiddles and accordion sprinting"),
    'area_mast': (174, "F# minor", ["pulsing analog synth arpeggios", "glitchy radio signal bleeps", "driving electronic drums",
                                    "soaring urgent strings", "sub bass pulses"],
                  "the signal glitches: stuttering synths and broken radio bleeps over hammering drums, very high altitude"),
    'area_yard': (160, "B minor", ["heavy industrial percussion", "anvil and hammer hits", "distorted low brass",
                                   "chugging cellos", "hydraulic hiss accents", "big toms"],
                  "machinery overload: pounding anvils and grinding low brass, heavy and menacing"),
}

# combat layers (swapped in when bots close in): a notch above the area themes
COMBAT = {
    'combat_a': (180, "D minor", ["full orchestra at maximum intensity", "hammering staccato strings", "blaring brass",
                                  "huge taiko and snare", "electric bass", "cymbal crashes"],
                 "brutal syncopated hits and brass rips, the fight at its peak"),
    'combat_b': (182, "E minor", ["scrappy junk percussion and breakbeat drums", "distorted electric guitar riff",
                                  "fast banjo and fiddle", "slap bass", "brass stabs"],
                 "rowdy scrap brawl: guitar riff and drums go into overdrive"),
    'combat_c': (176, "B minor", ["heavy industrial drums", "metal anvil hits", "distorted guitar chugs", "growling low brass",
                                  "driving cellos", "hydraulic hiss accents"],
                 "machine war: pounding industrial breakdown, crushing and heavy"),
}
AREAS.update(COMBAT)

def plan(name):
    bpm, key, inst, twist = AREAS[name]
    common = [f"{bpm} bpm", key, *inst]
    bar = 4 * 60000.0 / bpm
    ms = lambda bars: int(round(bars * bar))
    if name in COMBAT:
        common = ["battle", "combat", "aggressive", "maximum intensity"] + common
    return {
        "positive_global_styles": GLOBAL_POS + common,
        "negative_global_styles": GLOBAL_NEG,
        "sections": [
            {"section_name": "Alarm intro", "duration_ms": ms(4), "lines": [],
             "positive_local_styles": ["sudden alarm", "rising tension", "build", "snare roll", inst[0]],
             "negative_local_styles": ["quiet"]},
            {"section_name": "Main theme A", "duration_ms": ms(16), "lines": [],
             "positive_local_styles": ["full energy", "memorable urgent melody", "relentless rhythm", *inst[:3]],
             "negative_local_styles": ["breakdown", "quiet"]},
            {"section_name": "Contrast B", "duration_ms": ms(16), "lines": [],
             "positive_local_styles": [twist, "chaotic", "intense"],
             "negative_local_styles": ["slow", "calm"]},
            {"section_name": "Main theme A return", "duration_ms": ms(16), "lines": [],
             "positive_local_styles": ["full energy", "same melody as main theme", "relentless rhythm", "even bigger", *inst[:3]],
             "negative_local_styles": ["ending", "quiet"]},
            {"section_name": "Drive on", "duration_ms": ms(4), "lines": [],
             "positive_local_styles": ["keeps driving", "no ending", "continues like the main theme", *inst[:2]],
             "negative_local_styles": ["ending", "fade out", "final chord"]},
        ],
    }

def gen(name):
    mp3 = f'{TMP}/{name}.mp3'
    if os.path.exists(mp3): print('cached', name); return
    body = json.dumps({"composition_plan": plan(name), "model_id": "music_v1"}).encode()
    r = urllib.request.Request('https://api.elevenlabs.io/v1/music?output_format=mp3_44100_192', data=body,
                               headers={'Content-Type': 'application/json'})
    data = urllib.request.urlopen(r, timeout=600).read()
    open(mp3, 'wb').write(data)
    print('generated', name, len(data))

def loop(name, a_bars=4, b_bars=None):
    import numpy as np, librosa, soundfile as sf
    bpm = AREAS[name][0]
    mp3 = f'{TMP}/{name}.mp3'
    y, sr = librosa.load(mp3, sr=44100, mono=False)
    mono = librosa.to_mono(y)
    _, beats = librosa.beat.beat_track(y=mono, sr=sr, start_bpm=bpm, units='samples', tightness=200)
    beats = np.array(beats)
    bar = 4 * 60.0 / bpm * sr
    # A: beat nearest the planned start of section A; B: beat nearest 32 bars later (A + B sections)
    def near(t): return int(beats[np.argmin(np.abs(beats - t))])
    a0 = near(a_bars * bar)
    span_bars = b_bars or 32
    # search B candidates around a0 + span_bars bars (whole bars) for the best match of the following beat
    feat = librosa.feature.chroma_cqt(y=mono, sr=sr, hop_length=512)
    rms = librosa.feature.rms(y=mono, hop_length=512)[0]
    def f_at(s, n=int(sr * 3.0 / 512)):
        i = s // 512
        return np.concatenate([feat[:, i:i + n].ravel(), rms[i:i + n] * 10])
    ref = f_at(a0)
    best = None
    for k in (span_bars - 4, span_bars, span_bars + 4):   # whole 4-bar phrases, A + B preferred
        b = near(a0 + k * bar)
        if b + sr * 2 > mono.size: break
        c = f_at(b)
        if c.size != ref.size: continue
        score = np.dot(ref, c) / (np.linalg.norm(ref) * np.linalg.norm(c) + 1e-9) + (0.03 if k == span_bars else 0.0)
        if best is None or score > best[0]: best = (score, b, k)
    score, b0, k = best
    # bake: crossfade the last beat before b0 with the beat before a0
    x = int(60.0 / bpm * sr)
    out = y[:, :b0].copy()
    w = np.linspace(0, 1, x)[None, :]
    out[:, b0 - x:b0] = y[:, b0 - x:b0] * np.sqrt(1 - w) + y[:, a0 - x:a0] * np.sqrt(w)
    peak = np.max(np.abs(out))
    wav = f'{TMP}/{name}_loop.wav'
    sf.write(wav, (out.T / max(peak, 1e-6) * 0.89).astype(np.float32), sr)
    ogg = os.path.abspath(f'{OUT}/{name}.ogg')
    # one static gain to the target loudness (a dynamic normaliser would step at the loop seam)
    target = -14.5 if name in COMBAT else -15.5
    m = subprocess.run(['ffmpeg', '-nostats', '-i', wav, '-af', 'ebur128', '-f', 'null', '-'], capture_output=True, text=True).stderr
    lufs = float([l for l in m.splitlines() if l.strip().startswith('I:')][-1].split()[1])
    gain = min(target - lufs, -20 * np.log10(0.89) - 0.5)   # never push the peak past about -0.5 dBFS
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', wav, '-af', f'volume={gain:.2f}dB',
                    '-ar', '44100', '-c:a', 'libvorbis', '-q:a', '6', ogg], check=True)
    lj = f'{OUT}/loops.json'
    d = json.load(open(lj))
    d[name] = round(a0 / sr, 4)
    txt = json.dumps(d, indent=None)
    open(lj, 'w').write(txt)
    print(f'{name}: loop {a0/sr:.2f}s -> {b0/sr:.2f}s ({k} bars, match {score:.3f})')

if __name__ == '__main__':
    cmd, names = sys.argv[1], sys.argv[2:] or list(AREAS)
    for n in names:
        (gen if cmd == 'gen' else loop)(n)
