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


def giggle(rising):
    """Four quick pitched bursts. A stand-in for the voice actor's real giggle —
    it reads as playful without being shrill, which is what the timing needs."""
    import math
    bursts = 4
    burst = 0.105
    gap = 0.018
    duration = bursts * (burst + gap)
    base = 780.0

    def voice(t):
        index = int(t // (burst + gap))
        if index >= bursts:
            return 0.0
        local = t - index * (burst + gap)
        if local > burst:
            return 0.0
        step = index if rising else (bursts - 1 - index)
        freq = base * (1.0 + 0.085 * step)
        # Each burst has its own little arc, and a vibrato on top.
        shape = math.sin(math.pi * local / burst) ** 1.2
        vibrato = 1.0 + 0.035 * math.sin(2 * math.pi * 14 * local)
        return shape * (math.sin(2 * math.pi * freq * vibrato * local)
                        + 0.32 * math.sin(2 * math.pi * freq * 2 * vibrato * local)
                        + 0.12 * math.sin(2 * math.pi * freq * 3 * vibrato * local))

    # No global envelope: the per-burst arcs already stop it clicking.
    frames = int(SAMPLE_RATE * duration)
    samples = [voice(i / SAMPLE_RATE) for i in range(frames)]
    high = max(abs(s) for s in samples) or 1.0
    return [s / high * 0.26 for s in samples]


def hum():
    """Seamless two-second loop for the owl's thinking state.

    Every component completes a whole number of cycles in the loop length, so the
    end joins the start exactly and there is no click at the wrap point.
    """
    import math
    duration = 2.0
    fundamental = 220.0          # 440 cycles in 2.0 s
    vibrato_rate = 2.5           # 5 cycles
    swell_rate = 1.0             # 2 cycles
    frames = int(SAMPLE_RATE * duration)

    samples = []
    for i in range(frames):
        t = i / SAMPLE_RATE
        vibrato = 1.0 + 0.006 * math.sin(2 * math.pi * vibrato_rate * t)
        swell = 0.82 + 0.18 * math.sin(2 * math.pi * swell_rate * t)
        value = (math.sin(2 * math.pi * fundamental * vibrato * t)
                 + 0.30 * math.sin(2 * math.pi * fundamental * 2 * vibrato * t)
                 + 0.09 * math.sin(2 * math.pi * fundamental * 3 * vibrato * t))
        samples.append(value * swell)

    high = max(abs(s) for s in samples) or 1.0
    return [s / high * 0.13 for s in samples]


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
    write("giggle_a", giggle(rising=True))
    write("giggle_b", giggle(rising=False))
    write("hum", hum())
