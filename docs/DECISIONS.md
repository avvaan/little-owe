# Decisions

Why the code looks the way it does. Each entry names the constraint it serves, so a
later change can tell whether it is undoing a choice or a mistake.

---

## Rive rather than Spine for the owl

**Chosen: Rive.**

- Rive's Swift runtime (`rive-ios`) is first-party, installed through SPM, and actively
  maintained. Spine's runtime is also official and has the real advantage of being a
  native `SKNode` that composites inside the SpriteKit scene graph — Rive draws into a
  `UIView`/`CALayer` that has to sit above the scene.
- Rive has a **State Machine**, which maps almost one-to-one onto `OwlState`'s six
  entries with named triggers and inputs. Spine has animations but no state layer, so
  every blend and transition between idle/listening/thinking/speaking/happy/sleepy
  becomes hand-written app code.
- Rive exposes numeric inputs that can be driven per frame, which is exactly what beak
  sync needs: feed it the audio envelope. In Spine this is a manual bone poke.
- Rive is free for a single editor seat. Spine is $99 (Essential) to $399 (Pro) per seat.

For one character with six states and an audio-driven mouth, Rive is less code and less
money. Spine would win if the artist already lived in it — they do not.

**Consequence:** the owl will be a layer above the SpriteKit scene rather than a node
inside it. `OwlRig` exists so that when that swap happens, no behaviour code changes.
Until the artwork lands there is **no third-party dependency in the project at all**.

## Minimum device: any iPad on iPadOS 17

Matches the stated floor. The real consequence is speech: on-device `SFSpeechRecognizer`
is unreliable on A10-class chips, so the no-recognition fallback (deliverable 5) is a
first-class path that gets built and tested, not an afterthought. Families hand small
children older iPads; that is the device this app is for.

## Four times of day, not three

The brief names morning light, daytime clouds and evening moon. Evening and night look
very different through a window, and a child playing at 21:30 should see the moon high
and the sky deep, not a sunset. `TimeOfDay` buckets are 05–11, 11–17, 17–21, 21–05.

The clock is polled from the scene's update loop rather than by a `Timer`, so nothing
fires while the app is backgrounded and there is no lifecycle bookkeeping to get wrong.
`RoomHostView` also refreshes on `scenePhase == .active`, because hours can pass while
the app is in the background and the window must not still show last night's moon.

## `.aspectFill` at a fixed 1366 × 1024 design size

One authored layout, cropped slightly on narrower iPads, instead of a responsive scene.
Simpler, and the room has no content near the edges that matters.

The cost is that a design point is smaller than a device point on most iPads. Worst case
in the supported range is the 10th-gen iPad at 1180 × 820 pt, where the scale is 0.864,
so the 88 pt tap-target rule needs 102 design points. `RoomLayout.minimumTapTarget` is
120, and `DebugOverlay` (`-showTapTargets`) draws every target with its real size in
device points so the margin is checked on hardware rather than trusted.

## Hit testing in the scene, not per node

Tap targets are padded well past the artwork, so they deliberately overlap their
neighbours. `isUserInteractionEnabled` on each node would resolve those overlaps by z
order, which is not what a child means. The scene sweeps `tappables` sorted smallest
first, so the most specific target wins, and `DebugOverlay` can show exactly what is
being tested.

A tap on empty floor is not ignored: it wakes the owl. Nothing in this app is a dead
zone that silently does nothing to a child.

## The static shell is one baked texture

Roof planes, gable wall, beams and floor are drawn once with Core Graphics into a single
sprite. It began as fifteen shape nodes and none of it ever moves.

Baking buys things `SKShapeNode` cannot do reliably: clipping (the roof planes are
triangles filled with a gradient), gradient fills that line up across separate shapes,
and perspective floorboards. `SKShapeNode.fillTexture` maps a texture over the bounding
box in ways that vary, which is why the wall gradient is baked rather than filled.

## Sound effects on `AVAudioPlayer`, not `SKAction.playSoundFileNamed`

The UX rule is a soft palette with no sudden loud noises, and parent settings will
expose a volume. `SKAction` sounds cannot be attenuated. `SoundKit` keeps a small pool
of preloaded players per effect so rapid taps overlap cleanly, and it no-ops silently if
an asset is missing — a missing placeholder must never take the app down in front of a
child.

The placeholder effects are generated, not sourced: `tools/make_placeholder_sfx.py`
writes them with soft attacks and peaks around −10 dBFS, so the app is tuned against
something that already obeys the rule.

## The idle clock only counts rest

`OwlNode.update` resets its clock on every frame in which the owl is not idle — during a
mode, mid-hop, or already asleep. Otherwise time spent in a mode would accumulate and
the owl would nod off the moment it came home.

The sleepy state is decorative. It gates nothing, it wakes on any tap, and it exists
only so an iPad left on a table does not show a wide-eyed owl for an hour.

## `Info.plist` documents what must stay out

The absent keys are the point: no `NSAppTransportSecurity` (there is nothing to
configure, because there are no network calls), no tracking description, no third-party
keys. The comment in the file says so, so that a future "just add analytics" arrives as
an obvious contradiction rather than a quiet edit.

Microphone and speech-recognition usage strings arrive with the deliverables that need
them — Echo (2) and Prayers (5) — and not before.

## Open, and deliberately deferred

- **Room art is placeholder vector shapes.** `docs/ART_BRIEF.md` specifies what has to
  be delivered to replace it.
- **`content/` is empty.** The schema and loader are deliverable 3.
- **There are no tests yet.** The units worth testing — `TimeOfDay` bucketing, the tap
  target padding maths, the idle clock — are pure and will get a test target alongside
  deliverable 3, where the content loader makes a test target pay for itself.
