# Vesk emotion pass (ElevenLabs eleven_v3, audio tags) -> godot/audio/voice/<id>.ogg
#
# Vesk is grumpy, but grumpy is not flat: every line gets a direction that fits the moment
# (exasperated, sarcastic, angry, effort, wary, warm, smug). Each line is recorded in several
# takes; takes whose transcript does not match the script are dropped, and of the rest the most
# expressive one (pitch movement + loudness range) wins. The [tags] are not shown in subtitles.
#
#   python3 art/voice_vesk.py            # record + pick everything
#   python3 art/voice_vesk.py intro_06   # just these ids
#   TAKES=4 python3 art/voice_vesk.py    # more takes per line
#
# Needs: ffmpeg, numpy, librosa (pip install librosa). Uses the ElevenLabs key from the
# environment's network secret (xi-api-key is injected by the proxy).
import json, os, re, subprocess, sys, difflib, urllib.request, concurrent.futures as cf, warnings
warnings.filterwarnings('ignore')
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = f'{ROOT}/godot/audio/voice'
TMP = os.environ.get('VESK_TMP', '/tmp/vesk_takes')
VOICE = '9XZK0IYa8gELFK0AzC6B'  # "UH Vesk", see voice_ids.json
TAKES = int(os.environ.get('TAKES', '3'))
KEY = os.environ.get('ELEVEN_API_KEY', 'proxy-injected')

# id -> tagged line. Story lines keep their subtitle text; only the direction changes.
LINES = {
    # ---- intro (cutscene)
    'intro_04': "[long, satisfied exhale] Ahhh. [content] Finally. Nothing left to fix.",
    'intro_06': "[exasperated sigh] Dodger. [annoyed, slowing down like explaining to a child] It's my day off. Every day is my day off. [grumbling] That's what retired means.",
    'intro_11': "[scoffs, dismissive] Somebody else's problem.",
    'intro_13': "[long pause] ... [furious, through gritted teeth] Fine. [growling] Let's go unplug it.",
    'cs_intro_sip': "[sips, then a deep happy hum] Mmm. [cozy, smiling] Not too hot. Not too cold. Not too anything.",
    'cs_intro_gate_2': "[bored, not looking up] Sign says closed.",
    'cs_intro_gate_4': "[sips loudly] [smug] Same thing.",
    'cs_intro_chair': "[stunned silence] ... [quiet, seething, dangerous] That was a good chair.",
    'sky_intro_coffee_2': "[irritated, insisting] No. I'm retired. [exasperated] The coffee maker is retired.",
    # ---- junkyard
    'sky_junk_found_2': "[sighs, unimpressed] You flew into the scrap pile again.",
    'sky_junk_bots_2': "[angry growl, protective] Nobody touches the fence.",
    'sky_dodger_up_2': "[determined, rolling up his sleeves] Gate's open. Let's find whoever is broadcasting [annoyed] and tell them to stop.",
    'junkyard_heap_2': "[firm, a little alarmed] Then it stays buried.",
    'junkyard_summit_1': "[impressed, surprised] Huh. Nice view. [chuckles] Still a dump. [proud, warm] My dump.",
    'junkyard_hull_2': "[flat refusal, slightly wounded] No.",
    'junkyard_crane_2': "[shrugs, matter-of-fact] It gets bored.",
    'junkyard_lookout_1': "[relaxed, content sigh] My thinking spot. [firm] No talking.",
    'junkyard_statue_2': "[defensive, embarrassed] It says approximate.",
    # ---- docks
    'dock_intro_2': "[frustrated groan] I just wanted ONE quiet day.",
    'dock_clear_2': "[stern, wagging a finger] We are not shopping.",
    'sky_docks_clear_2': "[focused, all business] Three turbines. Restart them and the lift runs again.",
    'cargo_clear_2': "[sarcastic] Of course it's up.",
    'depot_canyon_2': "[dark chuckle] Wouldn't be the worst thing that happened to me this week.",
    'depot_belt_2': "[exasperated] That belt runs away from the button. [sarcastic] Course it does.",
    'depot_button_1': "[pleased with himself] There. Line two runs uphill now. [encouraging] Hop on.",
    'depot_berth_2': "[warning, suspicious] Don't get ideas.",
    'sky_turbines_done_2': "[quiet, troubled] The turbine crew walked off mid-shift. Same minute as the toaster. [grim] Same signal.",
    # ---- mast
    'sky_mast_climb_2': "[groans, looking up] Every time. [exasperated] Always up.",
    'sky_mast_pylon_2': "[annoyed, sarcastic] Nobody guards the stairs anymore.",
    'sky_mast_gust_2': "[straining against the wind, shouting] I've been blown around by worse! [teasing] Mostly by you.",
    'sky_mast_dish_2': "[focused, a bit eager] Aim it right and we'll hear where the signal comes from.",
    'mast_clear_2': "[frustrated] Relay's down. [puzzled, worried] The signal is still coming from somewhere else.",
    'sky_shard_3': "[concerned, slowly] Your eye just went orange.",
    'sky_shard_5': "[thoughtful] One shard of a code. Nana Quill can read it. [determined] After the crane.",
    # ---- crane yard
    'sky_yard_gate_clear_2': "[serious, uneasy] Stock up. [low] Something big is moving in there.",
    'yard_intro_2': "[nervous, trying to sound sure] Cranes do not look at people.",
    'cs_ci_vesk_1': "[low, wary whisper] Nobody leaves a spot that empty. [tense] Something's parking there.",
    'cs_ci_vesk_2': "[cracks knuckles] [gruff, ready for a fight] I'm retired, you know.",
    'respawn_1': "[groans in pain] Ugh. [wheezing] I'm getting too old for this.",
    # ---- terrace / gardens
    'terrace_tea_2': "[delighted, impressed] Finally. Somebody in this city with standards.",
    'terrace_perch_1': "[annoyed groan] Wind chimes. [sarcastic] Great. A headache, now in brass.",
    'gardens_dome_2': "[sniffs, disgusted] Smells like wet socks and roses.",
    'gardens_tree_1': "[bewildered] A tree. Growing out of the sky. [giving up, sarcastic] Sure. Why not.",
    'gardens_zip_1': "[yelling in panic] I am too old for vines!",
    # ---- broadcast / outro
    'cs_bc_vesk_1': "[long pause] ... [quiet, haunted] Lots of foremen out there.",
    'cs_bc_vesk_2': "[snapping out of it, gruff resolve] Rail's open. Crane Yard. [grim smile] Let's go unplug something.",
    'cs_out_vesk_1': "[snorts, mocking] He talks a lot for a guy with a chimney on his head.",
    'outro_03': "[genuinely offended] Only NINE?",
    'outro_09': "[long, weary sigh] A giant robot foreman. [deadpan disbelief] Of course.",
    'outro_11': "[hopeful, almost pleading] Back to my chair?",
    'sky_outro_eye_1': "[quiet, worried, gentle] Dodger. Your eye's doing the orange thing again.",
    'sky_outro_nana_2': "[suspicious, guarded] Who's asking?",
    'sky_outro_nana_5': "[suspicious, a little rattled] How did you get this frequency?",
    # ---- combat barks (vesk_<kind>_<n>)
    'vesk_hurt_1': "[grunts in pain] Ugh!",
    'vesk_hurt_2': "[yelps, angry] Hey!",
    'vesk_hurt_3': "[grunts, offended] Rude!",
    'vesk_hurt_4': "[pained groan] Oof. My back.",
    'vesk_hurt_5': "[angry growl] Watch it, tin can!",
    'vesk_hurt_6': "[sharp hiss of pain] Agh, that stings!",
    'vesk_kill_1': "[satisfied grunt] Scrap.",
    'vesk_kill_2': "[smug] Back to the pile.",
    'vesk_kill_3': "[mocking] Should've stayed in the box.",
    'vesk_kill_4': "[bored, impatient] Next.",
    'vesk_kill_5': "[chuckles darkly] Recycled.",
    'vesk_kill_6': "[pleased] Ha! Still got it.",
    'vesk_kill_7': "[shouting, fired up] Who's next?!",
    'vesk_overheat_1': "[panicked, shaking his hand] Hot, hot, hot!",
    'vesk_overheat_2': "[frustrated, blowing on it] Gotta let it cool.",
    'vesk_buy_1': "[reluctant sigh] Fine. I'll take it.",
    'vesk_buy_2': "[suspicious, grumbling] This better work.",
    'vesk_empty_1': "[annoyed] Out. [sarcastic] Of course it is.",
    'vesk_empty_2': "[frustrated] Empty! [shouting] Somebody find me a crate.",
    'vesk_empty_3': "[dry, sarcastic] Click. That's the sound of bad planning.",
    'vesk_levelup_1': "[surprised, impressed] Huh. That actually feels better.",
    'vesk_levelup_2': "[excited, grinning] Now we are talking! [chuckles] Mostly to myself.",
    'vesk_levelup_3': "[pleased laugh] Tuned it up. Like riding a bike. [mischievous] A bike that shoots.",
}

def strip(t): return re.sub(r'\[[^\]]*\]\s*', '', t).replace('...', '').strip()
def words(t): return re.sub(r"[^a-z' ]", ' ', t.lower().replace('-', ' ')).split()

def tts(text, path, stability):
    body = json.dumps({'text': text, 'model_id': 'eleven_v3',
                       'voice_settings': {'stability': stability, 'similarity_boost': 0.8, 'use_speaker_boost': True}}).encode()
    r = urllib.request.Request(f'https://api.elevenlabs.io/v1/text-to-speech/{VOICE}?output_format=mp3_44100_128',
                               data=body, headers={'Content-Type': 'application/json', 'xi-api-key': KEY})
    open(path, 'wb').write(urllib.request.urlopen(r, timeout=180).read())

def stt(path):
    bnd = 'vesk7b3f'
    data = open(path, 'rb').read()
    body = (f'--{bnd}\r\nContent-Disposition: form-data; name="model_id"\r\n\r\nscribe_v1\r\n'
            f'--{bnd}\r\nContent-Disposition: form-data; name="language_code"\r\n\r\neng\r\n'
            f'--{bnd}\r\nContent-Disposition: form-data; name="tag_audio_events"\r\n\r\nfalse\r\n'
            f'--{bnd}\r\nContent-Disposition: form-data; name="file"; filename="a.mp3"\r\nContent-Type: audio/mpeg\r\n\r\n').encode() + data + f'\r\n--{bnd}--\r\n'.encode()
    r = urllib.request.Request('https://api.elevenlabs.io/v1/speech-to-text', data=body,
                               headers={'Content-Type': f'multipart/form-data; boundary={bnd}', 'xi-api-key': KEY})
    return json.loads(urllib.request.urlopen(r, timeout=180).read()).get('text', '')

def expressiveness(path):
    import numpy as np, librosa
    y, sr = librosa.load(path, sr=22050)
    f0, vf, _ = librosa.pyin(y, fmin=50, fmax=500, sr=sr, frame_length=1024)
    f = f0[vf & ~np.isnan(f0)]
    rms = librosa.feature.rms(y=y)[0]; db = 20 * np.log10(rms[rms > rms.max() * 0.05] + 1e-9)
    lr = float(np.percentile(db, 95) - np.percentile(db, 10)) if len(db) else 0.0
    if len(f) < 5: return lr / 4, len(y) / sr, 0.0
    st = 12 * np.log2(f / np.median(f))
    return float(np.std(st)) + lr / 4, len(y) / sr, float(np.median(f))

def take(lid, k):
    os.makedirs(TMP, exist_ok=True)
    mp3 = f'{TMP}/{lid}__{k}.mp3'
    meta = mp3 + '.json'
    if os.path.exists(meta): return json.load(open(meta))
    # mostly Creative (most emotional range in v3), one Natural take as a safety net
    stab = 0.5 if k == TAKES - 1 and TAKES > 2 else 0.0
    if not os.path.exists(mp3): tts(LINES[lid], mp3, stab)
    heard = stt(mp3)
    match = difflib.SequenceMatcher(None, words(strip(LINES[lid])), words(heard)).ratio()
    score, dur, med = expressiveness(mp3)
    m = {'mp3': mp3, 'stability': stab, 'heard': heard, 'match': round(match, 3), 'score': round(score, 3), 'dur': round(dur, 2), 'f0': round(med, 1)}
    json.dump(m, open(meta, 'w')); return m

def pick(lid, ms):
    exp = 0.9 + len(strip(LINES[lid])) * 0.07  # rough expected seconds incl. tags/pauses
    loud = re.search(r'shout|yell|panic|!', LINES[lid]) is not None
    # same character: Vesk sits around 70-95 Hz; a calm take far above that has drifted off-voice
    ok = [m for m in ms if m['match'] >= 0.8 and m['dur'] < exp * 2.6 + 1.5 and m.get('f0', 0) < (220 if loud else 135)]
    if not ok: ok = sorted(ms, key=lambda m: -m['match'])[:1]
    return max(ok, key=lambda m: m['score'])

def to_ogg(mp3, lid):
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', mp3, '-af',
                    'silenceremove=start_periods=1:start_threshold=-45dB,areverse,silenceremove=start_periods=1:start_threshold=-45dB,areverse',
                    '-ac', '1', '-c:a', 'libvorbis', '-q:a', '5', f'{OUT}/{lid}.ogg'], check=True)

if __name__ == '__main__':
    ids = sys.argv[1:] or list(LINES)
    res = {}
    with cf.ThreadPoolExecutor(4) as ex:
        futs = {ex.submit(take, lid, k): (lid, k) for lid in ids for k in range(TAKES)}
        for f in cf.as_completed(futs):
            lid, k = futs[f]
            try: res.setdefault(lid, []).append(f.result())
            except Exception as e: print('ERR', lid, k, e, flush=True)
    report = {}
    for lid in ids:
        if lid not in res: continue
        best = pick(lid, res[lid]); to_ogg(best['mp3'], lid)
        report[lid] = {'chosen': os.path.basename(best['mp3']), 'takes': res[lid]}
        print(f"{lid:24s} take {best['mp3'][-5]} match {best['match']:.2f} score {best['score']:.2f} | {best['heard']}", flush=True)
    json.dump(report, open(f'{TMP}/report.json', 'w'), indent=1)
