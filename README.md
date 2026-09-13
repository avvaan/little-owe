# Little Owl

An offline talking-companion app for iPad, for children aged 3–6. A cozy attic room
with a small owl who lives there: the child talks to the owl, and the owl talks back.
A digital toy, not a chatbot.

**Status: deliverable 1 of 8.** Project skeleton, room scene, owl idle and tap
animation with placeholder shapes, time-of-day window.

---

## Running it

Open `LittleOwl.xcodeproj` in Xcode 16 or later and run on an iPad simulator
(landscape). No packages to resolve, no scripts to run — there are no dependencies.

The committed project uses Xcode's synchronised folder groups, so new files under
`LittleOwl/` are picked up automatically and never need adding to a target. If the
project file ever conflicts in a merge, delete it and regenerate from `project.yml`:

```
brew install xcodegen && xcodegen generate
```

XcodeGen is a developer convenience and ships nothing into the app.

### Checking tap targets on device

```
Product → Scheme → Edit Scheme → Run → Arguments → add  -showTapTargets
```

Every tap target is drawn with its size **in real device points**, green at or above
88 × 88 pt and red below. This is how the toddler UX rule gets verified on hardware
rather than asserted in a comment.

---

## What is in the room

| Object | Mode | Deliverable |
|---|---|---|
| The owl itself | Echo | 2 |
| Open book on the shelf | Stories | 4 |
| Lamp on the side table | Prayers and rhymes | 5 |
| Letter blocks on the rug | Word games | 6 |
| Round window | "Why?" questions | 6 |

Today every object routes correctly — tap it and the owl hops or flies over and
settles; tap the owl and it comes home — but the modes themselves are not built yet.
`RoomScene.handle(_:)` is the single seam where each one attaches.

## Previews

`docs/preview/` holds a render of the room at each time of day, generated from the
same layout constants the app uses:

```
python3 tools/preview_room.py                 # SVG
CHROME=/path/to/chromium tools/render_preview_png.sh   # SVG + PNG
```

Composition-accurate, finish-approximate: it does not simulate animation or
SpriteKit's blend modes. It exists so layout changes can be reviewed without a Mac.

![The attic room in the morning](docs/preview/room-morning.png)

---

## Layout of the code

```
LittleOwl/
  App/        SwiftUI entry point and the SpriteView host
  Room/       Scene, layout constants, props, the window, the time-of-day clock
  Owl/        Owl behaviour (OwlNode), the rig seam (OwlRig), the placeholder rig
  Support/    Palette, generated textures, sound effects, the tap-target overlay
  Resources/  Asset catalogue and placeholder sound effects
Config/       Info.plist
content/      Content packs (deliverable 3)
docs/         Art brief, decisions, previews
tools/        Placeholder-asset generators and the preview renderer
```

Two seams matter more than the rest:

- **`OwlRig`** separates what the owl *does* from how it is *drawn*. `PlaceholderOwlRig`
  draws vector shapes; a `RiveOwlRig` will drive a Rive state machine. Nothing above
  the protocol knows which is in use. See `docs/ART_BRIEF.md`.
- **`RoomScene.handle(_:)`** separates "a child touched something" from "a mode runs".

## The rules this app is built under

These are load-bearing, not aspirational. Each one has a corresponding decision in the
code:

- **Fully offline.** No networking code, no `URLSession`, no analytics, no crash
  reporting, no remote config. `Config/Info.plist` documents the keys that must stay
  absent.
- **No third-party SDKs** except the animation runtime (Rive, arriving with the art).
- **No locks for the child.** No timers, no limits, no gates. The sleepy idle is
  decorative and wakes on any tap.
- **No text-based UI for the child.** Every action is a tap on an object. The letters
  on the toy blocks are decoration; the child is never asked to read.
- **Nothing is stored** except parent settings (deliverable 7). No history, no logs of
  anything the child said.

## Deliverables

1. **Project skeleton, room, owl idle, time-of-day window** ← you are here
2. Echo mode
3. Content pack schema and loader
4. Stories
5. Prayers and rhymes, with on-device recognition and the no-recognition fallback
6. Word games and "Why?"
7. Parent gate and settings
8. Kids-category checklist: privacy manifest, privacy policy, App Store metadata
