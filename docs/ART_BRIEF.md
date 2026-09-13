# Art brief — Little Owl

What is delivered, what is still wanted, and the one constraint that matters for each.
The app already runs on the artwork that exists; everything below makes it livelier
without needing a code change.

**Audience:** children aged 3–6. Warm, soft, bedtime. Nothing sharp, nothing startling,
no teeth. The owl is a friend who lives in the attic, not a mascot.

---

## 1. The owl — state frames

**The base artwork has arrived** (`art-source/layer_owl.png`) and is in the app. What is
still missing is the other poses.

`WatercolourOwlRig` looks for these files in the bundle at launch and falls back to the
base pose for anything absent, so each one can be added on its own and needs **no code
change** — drop the file into `art-source/`, add a line to `tools/export_art.py`, re-run
it. The owl gets livelier with each one.

| File | Pose | What it unlocks |
|---|---|---|
| `owl_base.png` | Eyes open, beak closed. **Shipped.** | idle, the fallback for everything below |
| `owl_blink.png` | Eyes fully closed, lids as soft downward arcs | blinking, and the thinking pose |
| `owl_sleepy.png` | Eyes closed, lids heavy, tufts sagging | the sleepy idle |
| `owl_happy.png` | Eyes closed into upward crescents, cheeks lifted | praise |
| `owl_listen.png` | Eyes wider, pupils larger, ear tufts perked up | listening, while the microphone is live |
| `owl_talk_half.png` | Beak slightly open, eyes as in base | lip sync, quieter syllables |
| `owl_talk_wide.png` | Beak wide open, eyes as in base | lip sync, loud syllables; also the yawn |

### The one rule that matters

**Every frame must be registered to `owl_base`**: the same owl at the same size in the
same place in the canvas, with only the named feature different. The rig swaps the whole
texture at up to 8 frames a second, so anything that shifts between frames — the body a
few pixels left, the feet a little lower, the wings a shade darker — reads as the owl
twitching rather than blinking.

If a frame drifts, it is usually cheaper to paint the difference onto a copy of the base
than to re-generate it.

Deliver as PNG with alpha, trimmed the same way as the base, at least 744 px tall.

---

## 2. The room

**Delivered and in the app** (`art-source/owl_bg_empty.png`). The shelf, book, lamp,
table, stump and rug are all painted into it; only the blocks, the window glass and the
owl are separate. `tools/export_art.py` does the slicing.

### Still wanted: the room at other times of day

The window follows the device clock, and today only the night sky is painted. Three more
skies would complete it:

| File | Sky through the glass |
|---|---|
| `window_sky_morning.png` | Peach and pale gold low down, a soft rising sun glow |
| `window_sky_day.png` | Clear blue with white cumulus |
| `window_sky_evening.png` | Orange and rose fading to violet, the first faint stars |
| `window_sky_night.png` | **Shipped** — moon, stars, dusk clouds below |

Same framing as the reference crop: the identical round window, identical wooden
muntins, identical position. The export splits the muntins off automatically, so paint
the full window and let the tool cut it.

Beyond that, the room itself is lit for night — a lit lamp, a warm floor. The app tints
it gently for the time of day, but a genuinely bright morning attic would need the room
repainted. That is a nice-to-have, not a blocker.

## 3. Voice — not art, but the same hand-off

Three assets belong to the voice actor rather than the illustrator, and Echo already
uses generated stand-ins for all three. Mono WAV, 44.1 kHz, 16-bit, no music bed.

| Asset | Length | Notes |
|---|---|---|
| `giggle_a.wav` | 0.4–0.7 s | A short, warm giggle that **rises** in pitch. |
| `giggle_b.wav` | 0.4–0.7 s | The same giggle **falling**. Echo alternates the two so the owl never sounds like a sample. |
| `hum.wav` | 2.0 s exactly | A soft thinking hum, played on a loop. **Must loop seamlessly** — start and end at the same point in the phrase, with no fade at either end, or the join will click. |

Keep all three well below the owl's speaking level: they play under the room, not over
it. Nothing sudden, nothing sharp — a child may be holding the iPad at arm's length in a
quiet bedroom.

`tools/make_placeholder_sfx.py` generates the current stand-ins and documents the
intended character of each.

## 4. App icon

1024 × 1024, no transparency, no rounded corners (the system rounds it). The owl's face,
warm background, readable at 60 points. Kids-category apps are browsed by parents on
small tiles.
