"""Loudness envelopes for the lip-synced voice lines (godot/audio/voice/lipenv.json).

Rhubarb gives the mouth shape; this gives how far open it is. 50 frames a second, each line
normalised to its own loud syllables so a shout and a mutter both use the full range of the jaw.
    python3 art/lip_env.py
"""
import json, subprocess, os
import numpy as np

VOICE = os.path.join(os.path.dirname(__file__), "..", "godot", "audio", "voice")
FPS = 50
SR = 16000

def env(path):
    raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", path, "-ac", "1", "-ar", str(SR), "-f", "s16le", "-"],
                         capture_output=True, check=True).stdout
    x = np.frombuffer(raw, np.int16).astype(np.float32) / 32768.0
    hop = SR // FPS
    n = len(x) // hop
    rms = np.sqrt(np.mean(x[: n * hop].reshape(n, hop) ** 2, axis=1) + 1e-12)
    db = 20 * np.log10(rms)
    top = np.percentile(db, 95)
    v = np.clip((db - (top - 30.0)) / 30.0, 0.0, 1.0)   # 30 dB window under the loud syllables
    v = v ** 1.4                                        # quiet tails close the mouth
    k = np.array([0.25, 0.5, 0.25])                     # light smoothing, keeps the syllable edges
    v = np.convolve(v, k, mode="same")
    return [round(float(a), 2) for a in v]

def main():
    cues = json.load(open(os.path.join(VOICE, "lipsync.json")))
    out = {"_note": "per-line loudness 0..1 at fps, from art/lip_env.py", "fps": FPS, "lines": {}}
    for k in cues:
        p = os.path.join(VOICE, k + ".ogg")
        if k.startswith("_") or not os.path.exists(p): continue
        out["lines"][k] = env(p)
    json.dump(out, open(os.path.join(VOICE, "lipenv.json"), "w"), separators=(",", ":"))
    print(len(out["lines"]), "lines")

if __name__ == "__main__":
    main()
