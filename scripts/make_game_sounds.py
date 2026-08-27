"""Generates the Ludo sound effects as small mono WAV files.

Synthesised rather than sourced: four short cues need no licence, no
attribution and no 300 KB download, and generating them means the repo carries
the recipe instead of four opaque binaries nobody can adjust.

Design rules for game cues, which are why these are so short:
  * under ~350 ms — anything longer is still playing when the next tap lands
  * peak well under full scale, so they sit under speech and notifications
  * a fade at both ends, because a waveform cut mid-cycle clicks on cheap
    phone speakers, which is exactly the hardware most of these users have

Usage:  python scripts/make_game_sounds.py
"""

import math
import os
import random
import struct
import wave

RATE = 44100
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "sounds")


def write_wav(name, samples):
    """Writes 16-bit mono, with a short fade at each end to kill clicks."""
    n = len(samples)
    fade = int(RATE * 0.006)
    out = bytearray()
    peak = max(1e-9, max(abs(s) for s in samples))
    for i, s in enumerate(samples):
        v = s / peak * 0.62  # headroom: a game cue must not dominate
        if i < fade:
            v *= i / fade
        if i > n - fade:
            v *= max(0.0, (n - i) / fade)
        out += struct.pack("<h", int(max(-1.0, min(1.0, v)) * 32767))
    path = os.path.join(OUT, name)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(bytes(out))
    return path, n / RATE


def envelope(i, n, attack=0.01, decay=1.0):
    """Percussive shape: near-instant attack, exponential tail."""
    t = i / RATE
    total = n / RATE
    a = min(1.0, t / attack) if attack > 0 else 1.0
    return a * math.exp(-decay * t / max(1e-6, total))


def dice_roll():
    """Several wooden clatters — a die tumbling, not a single knock."""
    n = int(RATE * 0.34)
    rnd = random.Random(7)  # fixed seed: regenerating must not change the sound
    out = [0.0] * n
    for start in (0.0, 0.075, 0.14, 0.205, 0.26):
        s = int(RATE * start)
        length = int(RATE * 0.05)
        freq = rnd.uniform(320, 620)
        for i in range(length):
            if s + i >= n:
                break
            env = math.exp(-26 * i / RATE)
            noise = rnd.uniform(-0.35, 0.35)
            out[s + i] += (math.sin(2 * math.pi * freq * i / RATE) + noise) * env
    return out


def token_move():
    """A soft tick, played once per square as a piece walks."""
    n = int(RATE * 0.075)
    return [
        math.sin(2 * math.pi * 880 * i / RATE) * envelope(i, n, 0.002, 7.0)
        for i in range(n)
    ]
    # 880 Hz is high enough to cut through, short enough to repeat six times.


def capture():
    """A downward thud — something was sent home."""
    n = int(RATE * 0.3)
    out = []
    for i in range(n):
        t = i / RATE
        freq = 420 * math.exp(-5.5 * t)  # pitch falls: the "knocked back" cue
        out.append(math.sin(2 * math.pi * freq * t) * envelope(i, n, 0.004, 4.0))
    return out


def token_home():
    """A short rising two-note figure for a token reaching the centre."""
    n = int(RATE * 0.28)
    out = [0.0] * n
    for k, freq in enumerate((784.0, 1046.5)):  # G5 then C6
        s = int(RATE * 0.09 * k)
        for i in range(s, n):
            out[i] += 0.5 * math.sin(2 * math.pi * freq * (i - s) / RATE) * math.exp(
                -5.0 * (i - s) / RATE
            )
    return out


def victory():
    """Four rising notes. The only cue allowed to be long, because it plays
    once and the game is over."""
    n = int(RATE * 0.95)
    out = [0.0] * n
    for k, freq in enumerate((523.25, 659.25, 783.99, 1046.5)):  # C E G C
        s = int(RATE * 0.16 * k)
        for i in range(s, n):
            out[i] += 0.42 * math.sin(
                2 * math.pi * freq * (i - s) / RATE
            ) * math.exp(-2.4 * (i - s) / RATE)
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, fn in [
        ("ludo_dice.wav", dice_roll),
        ("ludo_move.wav", token_move),
        ("ludo_capture.wav", capture),
        ("ludo_home.wav", token_home),
        ("ludo_win.wav", victory),
    ]:
        path, secs = write_wav(name, fn())
        size = os.path.getsize(path)
        print(f"  {name:<20} {secs*1000:5.0f} ms  {size/1024:6.1f} KB")


if __name__ == "__main__":
    main()
