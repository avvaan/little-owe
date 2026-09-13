# Art brief — Little Owl

What is delivered, what is still wanted, and the one constraint that matters for each.
The app already runs on the artwork that exists; everything below makes it livelier
without needing a code change.

**Audience:** children aged 3–6. Warm, soft, bedtime. Nothing sharp, nothing startling,
no teeth. The owl is a friend who lives in the attic, not a mascot.

---

## 1. The owl — delivered

The base painting and six expression frames are all in and working:
`owl_base`, `owl_blink`, `owl_sleepy`, `owl_happy`, `owl_listen`, `owl_talk_half`,
`owl_talk_wide`. Sources are in `art-source/`, sprites are derived by
`tools/export_art.py`.

### How a frame is used, and what that asks of new ones

The expression frames land within a pixel of the base, but their bodies still differ
from the painting by a percent or two of texture. So the export treats them two ways:

| Frames | Treatment | Why |
|---|---|---|
| blink, happy, talk_half, talk_wide | **Face only.** The eyes, beak and facial disc are cut out and laid onto the original painted body with a soft edge. | These alternate fast — a blink is 130 ms. Anything that moves in the body would read as a twitch, so the body is left byte-identical. |
| listen, sleepy | **Whole frame.** | Their ear tufts move outside the base silhouette, so a face patch cannot express them. They are sustained states and the rig cross-fades into them over 220 ms, which hides the small body difference. |

If you replace or add a frame, the rule that matters is the same as before: **register
it to `owl_base`** — same owl, same size, same place in the canvas, only the named
feature different. The face patch is taken from a fixed box, so a frame that drifts puts
somebody else's eyes on this owl's head.

## 2. The room — delivered

The painting, the blocks, and all four window skies (`morning`, `day`, `evening`,
`night`) are in. The export cuts the glass out of each generated window, paints the
muntins out of the sky, and puts the room's own woodwork back on top — so all four skies
sit behind the identical painted frame.

The room itself is still lit for night: a lit lamp, a warm pool on the floor. The app
tints it gently for the time of day, but a genuinely bright morning attic would need the
room repainted. Nice-to-have, not a blocker.

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
