#!/usr/bin/env python3
"""Generate the placeholder sound effects for Little Owl.

Every effect here is deliberately soft: gentle attacks, no transients above about
-12 dBFS, and short tails. The UX rule is "no sudden loud noises", and a placeholder
that violates it would let us tune the app around the wrong feel.

These are replaced by the voice actor's session recordings. Run:

    python3 tools/make_placeholder_sfx.py

Output: LittleOwl/Resources/Audio/*.wav  (44.1 kHz, 16-bit mono)
"""

import math
import os
import struct
import wave

SAMPLE_RATE = 44100
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                       "LittleOwl", "Resources", "Audio")


def envelope(t, duration, attack=0.012, release_shape=3.0):
    """Soft attack, exponential decay. Never clicks on either end."""
    if t < attack:
        return t / attack
    decay_t = (t - attack) / max(duration - attack, 1e-6)
    return math.exp(-release_shape * decay_t) * (1.0 - decay_t) ** 0.5


def render(duration, voice, peak):
    frames = int(SAMPLE_RATE * duration)
    samples = []
    for i in range(frames):
        t = i / SAMPLE_RATE
        samples.append(voice(t) * envelope(t, duration))
    high = max(abs(s) for s in samples) or 1.0
    return [s / high * peak for s in samples]


def write(name, samples):
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, name + ".wav")
    with wave.open(path, "w") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(SAMPLE_RATE)
        handle.writeframes(b"".join(
            struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in samples
        ))
    print("wrote {} ({} frames)".format(path, len(samples)))


def tap_soft():
    """A wooden tick with a warm overtone. Plays on every touch."""
    def voice(t):
        return (0.70 * math.sin(2 * math.pi * 660 * t)
                + 0.24 * math.sin(2 * math.pi * 990 * t)
                + 0.10 * math.sin(2 * math.pi * 1320 * t))
    return render(0.20, voice, peak=0.30)


def hop():
    """Short rising blip under each hop, so movement is felt as well as seen."""
    def voice(t):
        freq = 420 + 260 * (t / 0.14)
        return math.sin(2 * math.pi * freq * t) + 0.2 * math.sin(2 * math.pi * freq * 2 * t)
    return render(0.14, voice, peak=0.22)


def wake():
    """Two soft notes, C5 then G5, for the owl coming out of the sleepy idle."""
    def voice(t):
        first = math.sin(2 * math.pi * 523.25 * t) * (1.0 if t < 0.26 else 0.0)
        second = math.sin(2 * math.pi * 783.99 * t) * (1.0 if t >= 0.22 else 0.0)
        return 0.8 * first + 0.8 * second
    return render(0.60, voice, peak=0.24)


if __name__ == "__main__":
    write("tap_soft", tap_soft())
    write("hop", hop())
    write("wake", wake())
