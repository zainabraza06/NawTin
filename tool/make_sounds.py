"""Synthesizes the game's sound effects into assets/audio/*.wav.

Run from the project root:  python tool/make_sounds.py
Everything is generated from sine waves and filtered noise, so there are no
licensing questions. Replace any file with a recorded one (same name) and the
game picks it up; voice lines for other languages go in
assets/audio/voice/<language code>/<call>.wav (see lib/services/sound).
"""
import math
import os
import random
import struct
import wave

RATE = 22050
OUT = os.path.join('assets', 'audio')
os.makedirs(OUT, exist_ok=True)
rnd = random.Random(7)


def buf(seconds):
    return [0.0] * int(RATE * seconds)


def add(dst, src, at=0.0, gain=1.0):
    start = int(at * RATE)
    for i, v in enumerate(src):
        j = start + i
        if j >= len(dst):
            break
        dst[j] += v * gain


def tone(freq, dur, decay=6.0, attack=0.004, harmonics=((1, 1.0),), sweep_to=None, vibrato=0.0):
    n = int(RATE * dur)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / RATE
        f = freq if sweep_to is None else freq * (sweep_to / freq) ** (t / dur)
        f *= 1.0 + vibrato * math.sin(2 * math.pi * 6 * t)
        phase += 2 * math.pi * f / RATE
        a = min(1.0, t / attack) * math.exp(-decay * t)
        out.append(a * sum(g * math.sin(phase * h) for h, g in harmonics))
    return out


def noise(dur, decay=20.0, lp_start=0.9, lp_end=0.9, attack=0.002):
    n = int(RATE * dur)
    out = []
    y = 0.0
    for i in range(n):
        t = i / RATE
        alpha = lp_start + (lp_end - lp_start) * (i / n)
        y += alpha * (rnd.uniform(-1, 1) - y)
        a = min(1.0, t / attack) * math.exp(-decay * t)
        out.append(y * a)
    return out


def swish(dur, peak=0.5):
    """Airy rising-then-falling noise."""
    n = int(RATE * dur)
    out = []
    y = 0.0
    for i in range(n):
        x = i / n
        alpha = 0.05 + 0.5 * math.sin(math.pi * x)
        y += alpha * (rnd.uniform(-1, 1) - y)
        out.append(y * math.sin(math.pi * x) ** 1.5 * peak)
    return out


def save(name, samples, peak=0.85):
    m = max(1e-9, max(abs(v) for v in samples))
    scale = peak / m
    fade = int(RATE * 0.01)
    data = []
    for i, v in enumerate(samples):
        g = 1.0
        if i > len(samples) - fade:
            g = (len(samples) - i) / fade
        data.append(int(max(-1, min(1, v * scale * g)) * 32767))
    path = os.path.join(OUT, name)
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(struct.pack('<%dh' % len(data), *data))
    print('%-14s %.2fs  %5.1f KB' % (name, len(samples) / RATE, os.path.getsize(path) / 1024))


BELL = ((1, 1.0), (2, 0.35), (3, 0.15))
SOFT = ((1, 1.0), (2, 0.18))

# placement: a soft wooden thud
s = buf(0.25)
add(s, tone(170, 0.25, decay=24, sweep_to=52), 0, 1.0)
add(s, noise(0.03, decay=90, lp_start=0.5, lp_end=0.5), 0, 0.35)
save('place.wav', s)

# slide: a light whoosh ending in a tick
s = buf(0.3)
add(s, swish(0.26, 0.6), 0, 1.0)
add(s, tone(1100, 0.04, decay=70), 0.24, 0.25)
save('move.wav', s)

# PHUTAS: two bright rising bell notes (a friendly warning)
s = buf(0.75)
add(s, tone(659.25, 0.6, decay=6.5, harmonics=BELL), 0.0, 0.8)
add(s, tone(987.77, 0.6, decay=6.0, harmonics=BELL), 0.13, 0.9)
save('phutas.wav', s)

# MACHYAS: rising whoosh, then a crack with a low body and a metallic ring
s = buf(0.95)
add(s, swish(0.14, 0.5), 0.0, 0.8)
add(s, noise(0.09, decay=38, lp_start=0.85, lp_end=0.6), 0.13, 1.0)
add(s, tone(95, 0.6, decay=9, sweep_to=48), 0.13, 1.1)
for f, g in ((523.25, 0.5), (1318.5, 0.35), (2093.0, 0.22)):
    add(s, tone(f * 1.003, 0.7, decay=5.0), 0.14, g)
save('machyas.wav', s)

# BEGI: a quick rising four-note arpeggio with a shimmer on top
s = buf(1.15)
for i, f in enumerate((440.0, 523.25, 659.25, 880.0)):
    add(s, tone(f, 0.6, decay=5.0, harmonics=SOFT), i * 0.11, 0.75)
add(s, tone(1760, 0.7, decay=3.2, vibrato=0.01), 0.3, 0.22)
save('begi.wav', s)

# TREGHI: sub boom, a long rising run, then a big swelling chord
s = buf(2.0)
add(s, tone(60, 1.0, decay=3.4, sweep_to=38), 0.0, 1.2)
add(s, noise(0.12, decay=25, lp_start=0.5, lp_end=0.2), 0.0, 0.5)
for i, f in enumerate((220.0, 277.18, 329.63, 440.0, 554.37, 659.25, 880.0)):
    add(s, tone(f, 0.55, decay=5.0, harmonics=SOFT), 0.12 + i * 0.09, 0.6)
for f in (440.0, 554.37, 659.25, 880.0):
    add(s, tone(f, 1.2, decay=2.2, attack=0.12, harmonics=SOFT), 0.72, 0.42)
add(s, tone(1760, 1.0, decay=2.4, vibrato=0.012), 0.8, 0.2)
save('treghi.wav', s)

# timer: warning (two soft beeps) and the tick for the last ten seconds
s = buf(0.4)
add(s, tone(880, 0.1, decay=14, attack=0.003, harmonics=SOFT), 0.0, 0.8)
add(s, tone(880, 0.1, decay=14, attack=0.003, harmonics=SOFT), 0.16, 0.8)
save('warning.wav', s)

s = buf(0.09)
add(s, tone(1250, 0.08, decay=55, attack=0.001), 0, 1.0)
save('tick.wav', s)

# endings
s = buf(1.9)
for i, f in enumerate((523.25, 659.25, 783.99, 1046.5)):
    add(s, tone(f, 0.9, decay=4.0, harmonics=BELL), i * 0.14, 0.6)
for f in (523.25, 659.25, 783.99, 1046.5):
    add(s, tone(f, 1.2, decay=2.0, attack=0.05, harmonics=SOFT), 0.6, 0.35)
save('win.wav', s)

s = buf(1.5)
for i, f in enumerate((440.0, 349.23, 293.66, 220.0)):
    add(s, tone(f, 0.7, decay=4.0, harmonics=SOFT), i * 0.24, 0.7)
save('lose.wav', s)

s = buf(0.8)
add(s, tone(392.0, 0.5, decay=5.5, harmonics=SOFT), 0.0, 0.7)
add(s, tone(392.0, 0.5, decay=5.5, harmonics=SOFT), 0.22, 0.6)
save('draw.wav', s)
