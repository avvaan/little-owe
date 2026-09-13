# Art brief — Little Owl

What the artist needs to deliver so the placeholder shapes can be replaced without
changing app code. Everything here is driven by the `OwlRig` protocol
(`LittleOwl/Owl/OwlRig.swift`); if a deliverable below is missing, that protocol cannot
be satisfied and behaviour code has to change to compensate.

**Audience:** children aged 3–6. Warm, soft, bedtime. Nothing sharp, nothing startling,
no teeth. The owl is a friend who lives in the attic, not a mascot.

---

## 1. The owl — Rive file (`owl.riv`)

Authored in Rive (free single-seat editor, https://rive.app). One artboard.

### Artboard

- **Size:** 512 × 640 px at 1× (the owl stands roughly 344 design points tall and is
  drawn at ~1.5× for headroom).
- **Origin:** the artboard's bottom-centre must sit **between the owl's feet**. The app
  positions the character by its feet, not by its centre.
- **Facing:** straight at the viewer, symmetrical. The owl never turns away.

### Required state machine: `Owl`

One state machine named `Owl`, with these inputs. Names are exact — the app looks them
up by string.

| Input | Type | Meaning |
|---|---|---|
| `idle` | Trigger | Breathing, blinking, occasional head tilt. The resting loop. |
| `listening` | Trigger | Ear tufts up and out, head forward, leaning in. Microphone is live. |
| `thinking` | Trigger | Eyes closed, gentle sway. Covers processing delay. |
| `speaking` | Trigger | Head bob; the beak is driven by `mouth`, not by the animation. |
| `happy` | Trigger | A two-beat bounce, then automatically back to the previous loop. |
| `sleepy` | Trigger | Yawn, then droop: eyes closed, head down, slow deep breathing. |
| `mouth` | Number 0–100 | Beak openness. 0 closed, 100 wide. Driven per frame from the audio envelope. |
| `blink` | Trigger | A single blink, playable over any state. |

Requirements:

- **Every sustained state loops** (`idle`, `listening`, `thinking`, `speaking`,
  `sleepy`). Only `happy` is a one-shot and must return to the state it interrupted.
- **`mouth` must be usable in every state**, blended over whatever is playing. It is the
  single most important input: the owl talks constantly and lip-sync sells the character.
- **Transitions between states are 150–250 ms** and must never snap. A child taps in the
  middle of everything.
- **No state may end on a pose that differs from where the next one starts.** Any state
  can follow any other.

### Rig notes

- Ear tufts, head, eyelids and the lower beak need to be separately animatable. Eyelids
  close downward over the eye.
- The head should be a child of the body so breathing carries through.
- Keep the silhouette readable at 260 × 384 points — that is how large the owl actually
  appears on a 10th-gen iPad.

### Delivery

- `owl.riv` exported for the **Rive runtime version pinned in the project** (state at
  hand-off; ask before exporting).
- The source `.rev` file, so the rig can be revised.
- A short screen recording of each state playing, for reference.

---

## 2. The room

The room can be delivered as flat art; it does not need to be rigged. Replace
`RoomBuilder`'s shapes sprite by sprite.

Design canvas: **1366 × 1024 points**, landscape. Supply at **@2x (2732 × 2048)**.
The scene is drawn `.aspectFill`, so keep 80 points of bleed on every edge with nothing
important in it.

| Asset | Size (points) | Notes |
|---|---|---|
| `room_shell` | 1366 × 1024 | Roof planes, gable wall, beams, floor, skirting. One flat image. |
| `rug` | 780 × 236 | Oval, sits at (700, 186). |
| `shelf` | 360 × 72 | Plank plus brackets, at (80, 706). |
| `side_table` | 232 × 170 | Top plus legs, top surface at y = 442. |
| `perch` | 176 × 92 | Low stump the owl stands on, centred at (716, 346). |
| `book` | 168 × 106 | Open book, seen from the front. Must read as "book" instantly. |
| `lamp` | 132 × 170 | Shade, stem, base. The glow is generated in code; do not paint it in. |
| `blocks` | 276 × 100 | Three wooden cubes. Letters are decoration — see below. |
| `window_frame` | 304 × 330 | Ring, two muntins, sill. **Centre must be transparent.** |

Notes:

- **The sky behind the window is generated in code** (four times of day, drifting
  clouds, twinkling stars, a moon). Deliver the frame only, with a transparent circle of
  radius 138 at its centre.
- **The letters on the blocks are decoration.** The app never asks the child to read.
  Keep them chunky and incidental, not instructional.
- **No text anywhere else in the room.** No labels, no signs, no book title.
- Warm, low-contrast palette. `LittleOwl/Support/Palette.swift` holds the current values
  and is the fastest way to see the intended range; treat it as a starting point, not a
  constraint.

---

## 3. What the artist does **not** need to provide

- The sky, clouds, stars, moon, sun, lamp glow and the shaft of window light — all
  generated.
- Any UI: there is none. No buttons, no menus, no icons for the child.
- Loading or splash artwork beyond the app icon.

## 4. App icon

1024 × 1024, no transparency, no rounded corners (the system rounds it). The owl's face,
warm background, readable at 60 points. Kids-category apps are browsed by parents on
small tiles.
