"""Generates the panic siren: a two-tone sweep, mono, 44.1 kHz, 16-bit PCM.

    python tool/generate_panic_siren.py

Writes the same file to both bundles:
  android/app/src/main/res/raw/panic_siren.wav   (played by PanicBridge.kt)
  assets/sounds/panic_siren.wav                  (played by PanicBridge.swift,
                                                  through the Flutter asset key)

One cycle sweeps LOW -> HIGH -> LOW as a triangle in frequency. The phase
accumulated over a triangle sweep is PERIOD * (LOW + HIGH) / 2 cycles, and the
constants below make that a whole number, so the waveform ends exactly where it
began: the file loops with no click and no fade.

The tone is lightly saturated (tanh) rather than a pure sine. A square-ish wave
carries more energy in the 2-4 kHz band where the ear is most sensitive, which
is the most loudness a phone speaker can be coaxed into without clipping.
"""

import math
import os
import struct
import wave

RATE = 44100
LOW = 650.0    # Hz
HIGH = 1450.0  # Hz
PERIOD = 1.2   # seconds per up-and-down sweep; 1.2 * 1050 = 1260 whole cycles
CYCLES = 2     # sweeps per file
DRIVE = 2.5    # tanh saturation
GAIN = 0.89    # headroom below full scale

assert abs(PERIOD * (LOW + HIGH) / 2 - round(PERIOD * (LOW + HIGH) / 2)) < 1e-9


def samples():
    n = int(RATE * PERIOD * CYCLES)
    phase = 0.0
    norm = math.tanh(DRIVE)
    for i in range(n):
        t = (i / RATE) % PERIOD
        half = PERIOD / 2
        frac = t / half if t < half else (PERIOD - t) / half
        freq = LOW + (HIGH - LOW) * frac
        yield GAIN * math.tanh(DRIVE * math.sin(phase)) / norm
        phase += 2 * math.pi * freq / RATE


def write(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data)


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    data = b"".join(struct.pack("<h", int(s * 32767)) for s in samples())
    for rel in ("android/app/src/main/res/raw/panic_siren.wav",
                "assets/sounds/panic_siren.wav"):
        write(os.path.join(root, rel), data)
        print("wrote", rel, len(data), "bytes")


if __name__ == "__main__":
    main()
