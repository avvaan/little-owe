# Decisions

Why the code looks the way it does. Each entry names the constraint it serves, so a
later change can tell whether it is undoing a choice or a mistake.

---

# Room and owl (deliverable 1)

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

---

# Echo (deliverable 2)

## Ending the turn is turn-taking, not a timeout

The UX rule is that nothing times out or exits on its own. Recording still has to stop
somehow, and "tap to start, tap again to stop" is beyond a three-year-old mid-sentence.

So the turn ends when the child stops talking (1.1 s of silence), when they tap the owl
again, or at a twelve-second cap. The child never leaves Echo, nothing closes, and
another turn starts with the next tap. That is a conversation taking its turn, not a
session expiring.

## The constants in `VoiceRecorder` are simulated, not guessed

Deciding when a child has finished talking is the hard part of Echo, and getting it
wrong is the difference between a toy and a broken toy. `tools/simulate_turn_detection.py`
mirrors the detector and runs it against synthetic rooms. Every constant in it fixes a
case that misbehaved:

- **A settling window** (the first 0.3 s counts as noise, never as speech). Without it a
  television at a steady level trips the detector the instant the child taps.
- **The noise floor adapts to noise, never to speech.** Letting it climb during speech
  walks the threshold up past the child's own voice and ends the turn while they are
  still talking — the "child never stops" case ended at 6 s instead of the 12 s cap.
- **Hysteresis once speech has been heard** (the bar drops to 0.55×). Without it the dips
  between syllables read as the end of the turn in a noisy room.

Known and accepted: a fan or air conditioner that starts *after* the child has spoken
holds the turn open, because hysteresis keeps treating it as speech. The cap catches it
and the owl echoes a fan, which is funny rather than broken.

Tests would be better than a simulation. They arrive with deliverable 3 — see below.

## `AVAudioUnitTimePitch`, not fast playback

Pitch (in cents) and rate are independent on that unit, so +600 cents at 1.08× gives
"higher and a little quicker". Simply playing the recording fast gives the chipmunk
artefact, where the words speed up as they rise and stop being the child's sentence.

## The beak follows the speaker, not the recording

Mouth openness comes from a tap on the playback engine's main mixer — the actual
output, after the pitch shift and the rate change. Driving it from a precomputed
envelope of the *recording* would drift against the 1.08× playback and put the beak out
of step by the end of a long sentence.

The envelope opens fast and closes slowly (0.6 attack, 0.22 release). A beak that snaps
shut between syllables reads as a glitch; one that lags slightly reads as a mouth.

The giggles come from `SoundKit`, outside the engine, so they produce no envelope to
follow. `OwlNode.wiggleMouth` drives the beak on a fixed 8 Hz rhythm for their duration,
which matches the burst rate of the generated placeholder.

## The recording is memory-only, structurally

No file, no URL, no temporary directory — `VoiceRecorder` has no way to write one. The
captured audio is one `AVAudioPCMBuffer` released when playback ends or anything is
cancelled. Twelve seconds of 48 kHz mono float is about 2 MB, so there is no reason to
spill to disk and every reason not to.

This is the whole privacy story of Echo, and it is a property of the type rather than a
rule someone has to remember when they next touch it.

## The audio session is raised once and never lowered

`.playback` at launch, raised to `.playAndRecord` the first time the microphone is
needed, and left there. Switching categories causes an audible glitch; having one happen
every time a child talks to the owl is worse than staying record-capable. The category
is raised just before the owl starts listening, so the glitch lands under the tap sound.

`.defaultToSpeaker` is not optional: without it a record-capable session comes out of
the earpiece, which on an iPad lying on a table is close to silent.

## The microphone prompt is on the first tap of the owl

Not at launch, not on a splash screen, not behind a "continue" button. The explanation
in `NSMicrophoneUsageDescription` is written for the parent standing next to the child,
and says plainly that nothing is recorded, saved or sent.

`RoomHostView` cancels Echo on `scenePhase == .background` but deliberately **not** on
`.inactive`: the permission alert puts the app there, and cancelling underneath it would
throw away the very tap that asked for permission.

## When the microphone is unavailable, the owl giggles

Denied permission, a failed engine start, an interruption — all of it ends the same way:
a giggle and back to waiting. The owl never says "wrong", never explains, and never puts
anything on screen for a child to read. `EchoMode.onMicrophoneUnavailable` records it so
parent settings can explain the quiet owl in deliverable 7.

## Capture state is behind a lock

Tap callbacks arrive on the engine's queue while `stop` runs on the main queue.
`removeTap` does not rule out a callback already in flight, so an `isCapturing` gate
lives inside the same lock as the buffer list: a late buffer must not land in a
recording that has already been assembled.

---

## Open, and deliberately deferred

- **Room art is placeholder vector shapes.** `docs/ART_BRIEF.md` specifies what has to
  be delivered to replace it.
- **`content/` is empty.** The schema and loader are deliverable 3.
- **There are no tests yet.** The units worth testing — `TimeOfDay` bucketing, the tap
  target padding maths, the idle clock, and now the turn detector — are pure and will
  get a test target alongside deliverable 3, where the content loader makes one pay for
  itself. `tools/simulate_turn_detection.py` stands in for the detector until then; it
  is a real check, but it is a mirror of the Swift rather than the Swift itself, and the
  two can drift.
