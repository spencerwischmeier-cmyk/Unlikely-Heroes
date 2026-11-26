# Panic pass voice barks (ElevenLabs text-to-speech, eleven_v3 audio tags) -> godot/audio/voice/panic_<who>_<n>.ogg
#   python3 art/voice_panic.py [who...]
# Citizens: frog dockhand, heron lady, mole shopkeeper, goat tourist. "pa" is the Skyharbor Authority announcer.
# panic_lines.json (written next to the oggs) maps each file to its line, for subtitles.
import json, os, subprocess, sys, urllib.request
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'godot', 'audio', 'voice')
TMP = '/tmp/claude-0/el/panic_voice'
os.makedirs(TMP, exist_ok=True)
VOICE = {'frog': 'HIGUfNOdjuWQwwapnTRW', 'bird': 'pFZP5JQG7iQjIQuC4Bku', 'mole': 'pqHfZKP75CvOlQylNhV4',
         'goat': 'TX3LPaxmHKxFdv7VOQHJ', 'pa': 'onwK4e9ZLuTAKqWW03F9'}
L = {
 'frog': ["[shouting] The forklifts are chasing people! FORKLIFTS!",
          "[panicked] Every ship's full! I'll ride in the cargo hold, I don't care!",
          "[shouting] Outta the way, outta the way!",
          "[yelling] My own wrench just tried to bite me!",
          "[surprised] Vesk?! You're going TOWARD the bots?",
          "[screams] Waaagh!"],
 'bird': ["[gasps] Oh, this is simply dreadful! Where is my ticket?!",
          "[shrieks] The tea urn is ATTACKING!",
          "[nervous] Excuse me, is this the queue for off-world?",
          "[panicked] I am NOT missing the eight-fifteen!",
          "[desperate] Somebody, anybody, do something!",
          "[screams] Eeeeeek!"],
 'mole': ["[panicked] My shop! My lovely little shop!",
          "[frantic] Forty years I've lived here and the toasters never did THIS!",
          "[shouting] Get down, get down, here comes another one!",
          "[flustered] Are the docks this way? My glasses are all fogged up!",
          "[relieved] Oh thank goodness, it's the mechanic!",
          "[yelps] Yeeep!"],
 'goat': ["[screaming] This is NOT what the brochure said!",
          "[panicked laugh] Best vacation ever, I said! Ha... ha... HELP!",
          "[shouting] Do they do refunds?! Does ANYONE do refunds?!",
          "[shouting] Run! The parking meters have gone feral!",
          "[desperate] Wait for me! WAIT FOR MEEE!",
          "[screams] Aaaaah!"],
 'pa': ["[calm] Attention, Skyharbor. All off-world flights are now boarding at the Cargo Docks. Please proceed calmly. [pause] Calmly. That means no running.",
        "[calm] Shuttle seven is now full. Shuttle seven is also on fire. Please wait for shuttle eight.",
        "[calm] A reminder: robots are not permitted on departing ships. If your luggage is growling, please leave it behind.",
        "[calm] Will the gentleman clinging to the outside of shuttle four please come inside. Thank you.",
        "[calm] The Skyharbor Authority reminds you: do not panic. Please panic quietly, and in single file.",
        "[calm] Final boarding call for all flights leaving Skyharbor. [pause] That's all of them. All the flights."],
}
def gen(who, i):
    text = L[who][i]
    name = f'panic_{who}_{i + 1}'
    mp3 = f'{TMP}/{name}.mp3'
    if not os.path.exists(mp3):
        body = json.dumps({'text': text, 'model_id': 'eleven_v3', 'voice_settings': {'stability': 0.5 if who == 'pa' else 0.0}}).encode()
        r = urllib.request.Request(f'https://api.elevenlabs.io/v1/text-to-speech/{VOICE[who]}?output_format=mp3_44100_128',
                                   data=body, headers={'Content-Type': 'application/json'})
        open(mp3, 'wb').write(urllib.request.urlopen(r, timeout=180).read())
    ogg = os.path.abspath(f'{OUT}/{name}.ogg')
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', mp3, '-af',
                    'silenceremove=start_periods=1:start_threshold=-45dB,areverse,silenceremove=start_periods=1:start_threshold=-45dB,areverse',
                    '-ac', '1', '-c:a', 'libvorbis', '-q:a', '5', ogg], check=True)
    return name, text
if __name__ == '__main__':
    import concurrent.futures as cf, re
    jobs = [(w, i) for w in (sys.argv[1:] or list(L)) for i in range(len(L[w]))]
    out = {}
    with cf.ThreadPoolExecutor(4) as ex:
        for f in cf.as_completed([ex.submit(gen, *j) for j in jobs]):
            try:
                n, t = f.result(); out[n] = re.sub(r'\[[^\]]*\]\s*', '', t).strip(); print(n, flush=True)
            except Exception as e: print('ERR', e, flush=True)
    p = f'{OUT}/panic_lines.json'
    old = json.load(open(p)) if os.path.exists(p) else {}
    old.update(out); json.dump(dict(sorted(old.items())), open(p, 'w'), indent=1)
