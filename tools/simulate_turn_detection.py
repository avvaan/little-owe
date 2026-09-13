#!/usr/bin/env python3
"""Mirror of VoiceRecorder's turn-ending logic, checked against synthetic rooms.

Echo decides on its own when the child has finished talking. Getting that wrong is
the difference between a toy and a broken toy: end too early and the owl interrupts,
end too late and it echoes the television. The constants in `VoiceRecorder.consume`
are not guesses — each one fixes a case below that misbehaved.

Keep this in step with the Swift. If you change a constant there, change it here and
re-run:

    python3 tools/simulate_turn_detection.py

Known and accepted: a fan or an air conditioner that starts up *after* the child has
spoken holds the turn open, because hysteresis keeps treating it as speech. The
12-second cap catches it, and the result is the owl echoing a fan, which is a funny
outcome rather than a broken one.
"""
import random

SR = 48000.0
FRAMES = 1024.0
STEP = FRAMES / SR            # 21.3 ms

def run(levels, settle=0.30, max_dur=12.0, silence_to_finish=1.1, patience=6.0):
    noise = 0.004
    elapsed = silence_run = 0.0
    heard = False
    lead = 0.0
    for level in levels:
        elapsed += STEP
        settling = elapsed <= settle
        threshold = max(noise * 3.5, 0.012)
        # Hysteresis: once the child is talking, the bar to *stay* talking is lower, so
        # the dips between syllables do not read as the end of the turn.
        if heard:
            threshold *= 0.55
        speech = (not settling) and level > threshold
        if settling:
            noise += (level - noise) * 0.30          # tracks fast both ways
        elif not speech:
            noise += (level - noise) * (0.25 if level < noise else 0.002)
        if speech:
            heard = True
            silence_run = 0.0
        else:
            silence_run += STEP
            if not heard:
                lead += STEP
        if elapsed >= max_dur:
            return "maxDuration", elapsed, lead, heard
        if heard and silence_run >= silence_to_finish:
            return "silence", elapsed, lead, heard
        if not heard and elapsed >= patience:
            return "noSpeech", elapsed, lead, heard
    return "ranOut", elapsed, lead, heard

def seq(*segments):
    out = []
    for seconds, level, jitter in segments:
        for _ in range(int(seconds / STEP)):
            out.append(max(0.0, level + random.uniform(-jitter, jitter)))
    return out

random.seed(7)
cases = {
  "quiet room, child says nothing":      seq((10, 0.003, 0.002)),
  "quiet room, 2s of speech":            seq((0.5, 0.003, 0.002), (2.0, 0.09, 0.05), (2.5, 0.003, 0.002)),
  "quiet room, shy 0.4s of speech":      seq((0.8, 0.003, 0.002), (0.4, 0.06, 0.03), (2.5, 0.003, 0.002)),
  "busy room (TV at 0.05), no child":    seq((10, 0.050, 0.010)),
  "busy room (TV at 0.05), child talks": seq((0.6, 0.050, 0.010), (2.0, 0.220, 0.080), (2.5, 0.050, 0.010)),
  "very loud room (0.12), no child":     seq((10, 0.120, 0.020)),
  "child never stops (15s)":             seq((0.4, 0.003, 0.002), (15, 0.10, 0.05)),
  "speech with a breath pause":          seq((0.4, 0.003, 0.002), (1.2, 0.09, 0.05), (0.6, 0.004, 0.003), (1.2, 0.09, 0.05), (2.0, 0.003, 0.002)),
}
print(f"{'case':<40} {'reason':<12} {'ends at':>8} {'lead trimmed':>13}")
for name, levels in cases.items():
    reason, elapsed, lead, heard = run(levels)
    print(f"{name:<40} {reason:<12} {elapsed:>7.2f}s {lead:>12.2f}s")
