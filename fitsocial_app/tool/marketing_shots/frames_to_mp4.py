"""Encodes out/<name>/f####.png into out/<name>.mp4 (H.264, 30 fps, 720 wide).

    python tool/marketing_shots/frames_to_mp4.py <name> [<name> ...]
"""
import glob
import os
import shutil
import subprocess
import sys
from pathlib import Path

OUT = Path(__file__).resolve().parent / "out"
FFMPEG = shutil.which("ffmpeg") or next(iter(glob.glob(
    os.environ.get("LOCALAPPDATA", "")
    + "/Microsoft/WinGet/Packages/Gyan.FFmpeg*/*/bin/ffmpeg.exe")), "ffmpeg")

for name in sys.argv[1:]:
    subprocess.run([
        FFMPEG, "-v", "error", "-y", "-framerate", "30",
        "-i", str(OUT / name / "f%04d.png"),
        "-vf", "scale=720:-2:flags=lanczos", "-c:v", "libx264", "-crf", "16",
        "-preset", "slow", "-pix_fmt", "yuv420p", "-movflags", "+faststart",
        str(OUT / f"{name}.mp4"),
    ], check=True)
    frames = sorted((OUT / name).glob("f*.png"))
    shutil.copy(frames[0], OUT / f"{name}_first.png")
    shutil.copy(frames[-1], OUT / f"{name}_last.png")
    print(f"{name}: {len(frames)} frames -> {name}.mp4")
