"""Per-frame loudness and bass for audio-reactive compositions, no numpy.

    python audio_data.py <track.mp3> <out.js> [seconds=30] [start=0]

Writes window.AUDIO_DATA = {fps, totalFrames, frames: [{rms, bass}]}, each
normalised to 0..1 over the window.
"""
import array
import glob
import json
import math
import os
import shutil
import subprocess
import sys

track, out = sys.argv[1], sys.argv[2]
seconds = float(sys.argv[3]) if len(sys.argv) > 3 else 30
start = float(sys.argv[4]) if len(sys.argv) > 4 else 0
RATE, FPS = 22050, 30

# winget installs ffmpeg without putting it on every shell's PATH.
FFMPEG = shutil.which("ffmpeg") or next(iter(glob.glob(
    os.environ.get("LOCALAPPDATA", "")
    + "/Microsoft/WinGet/Packages/Gyan.FFmpeg*/*/bin/ffmpeg.exe")), "ffmpeg")

raw = subprocess.run(
    [FFMPEG, "-v", "error", "-ss", str(start), "-t", str(seconds), "-i", track,
     "-ac", "1", "-ar", str(RATE), "-f", "s16le", "-"],
    capture_output=True, check=True).stdout
pcm = array.array("h", raw)
per = RATE // FPS
rms, bass = [], []
low = 0.0
alpha = 1 - math.exp(-2 * math.pi * 150 / RATE)  # one-pole low-pass at 150 Hz
for f in range(len(pcm) // per):
    s = e = 0.0
    for x in pcm[f * per:(f + 1) * per]:
        v = x / 32768
        low += alpha * (v - low)
        s += v * v
        e += low * low
    rms.append(math.sqrt(s / per))
    bass.append(math.sqrt(e / per))


def norm(values):
    top = sorted(values)[int(len(values) * 0.98)] or 1
    return [round(min(v / top, 1), 3) for v in values]


frames = [{"rms": r, "bass": b} for r, b in zip(norm(rms), norm(bass))]
with open(out, "w") as fh:
    fh.write("window.AUDIO_DATA=" + json.dumps(
        {"fps": FPS, "totalFrames": len(frames), "frames": frames},
        separators=(",", ":")) + ";")
print(f"{len(frames)} frames -> {out}")
