"""Generate an original, loopable 90 BPM background bed. No third-party samples."""
from array import array
import math
from pathlib import Path
import wave

RATE = 22050
BPM = 90
BEAT = 60 / BPM
BARS = 8
DURATION = BARS * 4 * BEAT
OUT = Path(__file__).resolve().parents[1] / "audio" / "background-90bpm.wav"

# A quiet four-chord progression with soft synthesized plucks and a restrained
# low pulse. The exact loop length is 32 beats at 90 BPM for bar-aligned repeats.
chords = [
    (130.81, 164.81, 196.00),
    (110.00, 130.81, 164.81),
    (87.31, 110.00, 130.81),
    (98.00, 123.47, 146.83),
]
frames = array("h")
count = round(DURATION * RATE)
for i in range(count):
    t = i / RATE
    beat_index = int(t / BEAT)
    chord = chords[(beat_index // 4) % len(chords)]
    beat_t = t % BEAT
    attack = min(1.0, beat_t / 0.018)
    decay = math.exp(-beat_t * 2.8)
    pad = sum(math.sin(2 * math.pi * f * t) for f in chord) / len(chord)
    shimmer = 0.22 * math.sin(2 * math.pi * chord[1] * 2 * t)
    kick_env = math.exp(-beat_t * 18)
    kick = math.sin(2 * math.pi * (55 - 13 * min(1, beat_t / .12)) * t) * kick_env
    fade = min(1.0, t / .025, (DURATION - t) / .025)
    sample = fade * (0.20 * pad * (.38 + .62 * decay) + 0.035 * shimmer * attack + 0.075 * kick)
    frames.append(round(max(-1, min(1, sample)) * 32767))

OUT.parent.mkdir(parents=True, exist_ok=True)
with wave.open(str(OUT), "wb") as f:
    f.setnchannels(1)
    f.setsampwidth(2)
    f.setframerate(RATE)
    f.writeframes(frames.tobytes())
print(f"Wrote original {BARS}-bar {BPM} BPM loop: {OUT}")
