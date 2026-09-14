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

# The painted room (art integration)

## Texture swapping, not a cut-up puppet

The obvious way to animate a 2D character is to cut it into parts — head, eyelids, beak —
and transform them. That is what the vector placeholder did, and it is why blinking was
pixel-perfect there.

It does not survive contact with this artwork. The owl is a watercolour painting with
feather texture running continuously across every edge; cut the head off the body and the
seam is visible at any rotation, because there is nothing painted behind the cut. So the
rig swaps whole painted frames and moves the whole bird. That is how a paper puppet
moves, and at this scale it reads correctly.

The cost is that every frame must be registered to the base pose. `docs/ART_BRIEF.md`
states that as the one rule that matters, because a frame that drifts a few pixels turns
a blink into a twitch.

## Missing frames degrade, they do not break

`WatercolourOwlRig` looks for `owl_<state>.png` at launch and falls back to the base pose
for anything absent. The app is complete and shippable with only `owl_base` present, and
improves the moment more art lands — no code change, no feature flag, no branch.

This is also why `setMouthOpenness` uses two thresholds with a gap between them rather
than one cut-off: a single boundary makes the beak stutter between frames on every wobble
of the audio envelope.

## The window glass was split at export time

The painting has a night sky baked into its glass, and the brief wants the window to
follow the device clock. Rather than ask for the room to be repainted four times, the
export separates the glass into a sky sprite and the wooden muntins that cross it, so a
new sky drops in behind unchanged woodwork.

The muntins are found by colour (they are the only strongly brown thing inside the glass)
and cleaned with a morphological opening, which clears the speckle the pink clouds
otherwise contribute. They are then painted *out* of the sky by growing the surrounding
sky inwards — otherwise a swapped sky would show a ghost of the old cross.

## The sprites are derived, never hand-edited

`tools/export_art.py` is the only thing that writes `LittleOwl/Resources/Art/`. Source
layers live in `art-source/` exactly as delivered. This costs about 16 MB in the
repository and buys the ability to re-run the whole pipeline when the painter revises
something, instead of hand-repeating a sequence of image-editor steps nobody wrote down.

It also reads `RoomLayout.swift` for the window geometry, so the export and the app
cannot disagree about where the glass is.

## Painted props glow instead of squashing

Only the blocks, the window glass and the owl are separate sprites. The book and the lamp
are part of the room painting and cannot move at all — but the UX rule says every tap
gets instant sound *and* motion. They answer with a soft bloom of warm light over the
prop, which is motion the painting can actually do.

## The ambient wash was turned down

The vector room was flat, so a strong tint sold the time of day. The painting carries its
own light — a lit lamp, a warm pool on the floor — and a heavy tint fights it. The wash
is now gentle and the window does most of the work. A genuinely bright morning attic
needs the room repainted; that is in the art brief as a nice-to-have.

## Face patch for fast frames, whole frame for slow ones

The generated expression frames register to the base within a pixel — measured, not
assumed — but their bodies differ by one to three percent of texture. Whether that
matters depends entirely on how fast the frame changes.

A blink is 130 ms. Anything moving in the body during it reads as a twitch, so for
blink, happy and the two beak positions the export takes **only the face** — eyes, beak
and facial disc, soft-edged — and lays it on the original painted body. The body is then
byte-identical across those frames and there is nothing to shimmer.

Listening and sleepy raise and droop the ear tufts, which move outside the base
silhouette, so a face patch cannot express them at all. They use the **whole frame**, and
the rig cross-fades into them over 220 ms. A slow fade hides a one-percent texture
difference completely; cutting to it would not.

That split is why `Frame.isWholeBody` exists in the rig and why `show` fades for some
frames and cuts for others.

## The muntins are found by colour in the painting, by geometry in the generated skies

In the room painting the muntins are the only strongly brown thing inside the glass, so
colour finds them exactly. In a generated sky a sunset horizon reads as brown to any
wood detector, and eating the clouds would be far worse than painting out a slightly
wide cross — so those use a fixed geometric cross instead.

It is safe to be generous there: the generated bars measure 5.6% of the glass diameter
and the painted ones that go back on top are 5.9%, so the painted-out cross ends up
completely hidden.

## The generated frames could not be fetched into this session

The owl poses and the three extra skies were generated through Higgsfield, but this
session's egress policy blocks its delivery CDN (`d8j0ntlcm91z4.cloudfront.net`), so they
could not be downloaded, inspected or composited here. They are visible in the Higgsfield
widget and have to come back into the repository by hand.

Nothing in the app depends on them: the rig falls back to the base pose, which is why the
missing-frames design above matters more than it looked at the time.

## Prayers listen, but the mode does not need to hear

Recognition is a bonus laid on top of a mode that works without it. Four things can take
it away — no recogniser for the pack's language, no on-device model on this iPad, no
microphone permission, no speech-recognition permission — and every one of them lands on
the same path: the owl says the line, waits a pause scaled to the line, praises, and
moves on. That is the brief's "fixed pause", and it is the floor rather than an error
case. A child on a device that cannot hear gets the whole prayer, said the same way; the
device just listens while it happens.

`SFSpeechAudioBufferRecognitionRequest.requiresOnDeviceRecognition` is set to true and a
task is **never started without it**. There is deliberately no server fallback to take,
because a server fallback is a network call.

## The microphone prompt stays on the owl

The brief puts the microphone prompt on the first tap of the owl and nowhere else, so
Prayers does not ask for it. A child who has never played Echo gets the pause instead of
a permission alert on the lamp. Speech recognition is a second, separate permission, and
it is only ever asked for once the microphone is already granted — so it reaches a parent
who has already said yes once, rather than a cold first tap.

## `RepeatJudge` counts words and nothing else

The brief is explicit that recognition detects *that the child said something of roughly
the right length*, never whether they said it correctly. So the judge looks at how many
words came back and at nothing else — not which words, not their order. "Banana banana
banana" against "Now I lay me down to sleep," is a pass, and that is the design working.

The bar is a third of the line, capped at four words however long the line is: long lines
are the ones a small child most needs help with, so they must not also be the hardest to
pass. Across the shipped pack no line asks for more than 40% of itself, and the longest
asks for three words out of nine.

There is exactly one thing it guards against: a cough, a sibling or a television reading
as the child. One stray word against a fourteen-word line is not enough, and the owl says
the line again — which is the same gentle path silence takes.

## The gentle repeat happens once

"If the child is silent for 8 seconds, the owl gently repeats the line once, then moves
on." The owl nudges ("Let's try it together."), says the line again, and opens one more
turn. If that one passes in silence too, it moves to the next line without comment. There
is no third attempt and no "you didn't say it": a toy that waits a three-year-old out is
a toy that has stopped being fun.

## No set title is ever shown to a child

The cards are symbols — a sun, a moon, a bowl, a star. A three-year-old cannot read
"Before meals", but they know the bowl, and after two evenings they reach for the same
card without looking. That is also why the cards keep the pack's order rather than the
order a parent happened to tick them in, and why a test fails if two sets on the lamp
share a symbol.

## Two bugs the sibling code found

Writing the set picker turned up the same mistake already shipped in the hero picker: the
cards' hit areas are in each card's own space, but the tap was tested against a point in
the row's space. Only a card sitting exactly on the picker's origin was reachable, so
choosing a hero worked for the middle card and silently did nothing for the other four.
Both pickers now subtract the card's position, and a test taps every card in both.

The story's "tap the book again" offer had the same shape of problem. The book and the
lamp are painted into the room and have no artwork of their own, so a prop node is a hit
area plus a glow held at alpha 0 — and the offer was breathing the *node's* alpha, which
changed nothing a child could see. `RoomObject.setOffering` now breathes the glow itself.

## The tap-to-choose fallback is read aloud, not looked at

The brief asks Word games and Why to "fall back to a tap-to-choose picture answer" where
speech recognition is unavailable. The pictures are not drawn, and the app never asks a
child to read — so a card cannot be a label, and a coloured rectangle on its own tells a
three-year-old nothing.

So the owl **reads each card aloud while that card lights up**, and the child taps the one
they remember hearing. A card is a place to aim, not a label. Illustrations drop in
without touching any of this: a card shows `choice_<something>.png` the moment one exists
in the pack.

That change made an old content decision wrong. The three animal-sound tasks offered
cards named *cow*, *duck*, *cat* — pictures, so tapping the cow answered "what sound does
a cow make". Once the cards are spoken, tapping a card that says "cow" is not an answer to
that question at all. The cards are now *moo*, *quack*, *meow*, which is both coherent and
better, and a test asserts that a game's first card is an answer `accepted` would take and
the other two are not.

## One `ListeningTurn`, three modes

Prayers, Word games and Why all want the same thing: open the microphone, let the child
talk, come back with what they said or with the fact that nothing was heard. That seam is
one type now, so there is one place that decides whether this device can hear, one place
that guarantees exactly one outcome per turn, and one place that never asks for the
microphone — the prompt stays on the first tap of the owl, where the brief puts it.

It also means one `AVAudioEngine`. `VoiceRecorder` owns the tap and does the turn
detection; the live buffers go straight to on-device recognition rather than a second
engine fighting for the same input node, and `retainsAudio` is off so nothing is copied or
kept.

## The owl must never answer a question nobody asked

The Why bank is 129 questions now, inside the brief's 100-200. Two tests hold the line:
every canonical phrasing **and every authored alternate** must resolve to its own
question, so a new entry that shadows an old one fails the build rather than quietly
stealing its answers; and a handful of things a child says that are not questions at all
must match nothing.

Writing them turned up a trap worth recording. An entry whose keywords or alternates
reduce to **one content word** matches on that word wherever it appears. That is right for
"volcano" or "hibernation", which only ever mean one thing, and wrong for "colour" — the
alternate "what is colour" was answering "what is my favourite colour" with an explanation
of how eyes work. Single-word candidates are now kept to words that only ever mean their
own question, and a test names the two that used to be wrong.

## No scores, anywhere

The brief says no scores and no streaks, so Word games has nowhere to put one. It keeps a
short list of the tasks just asked, purely so the same one does not come round twice in a
minute, and that list dies when the child leaves. Nothing counts right answers, in memory
or on disk, because a three-year-old who gets one wrong should not then be a three-year-old
with a number attached.

## The privacy manifest had left itself a note, and the note had expired

It said, in a comment: *"Parent settings (deliverable 7) will add UserDefaults, which
needs NSPrivacyAccessedAPICategoryUserDefaults with reason CA92.1. Add it when that code
lands, not before."*

Deliverable 7 landed two PRs ago. `ParentSettings` reads and writes `UserDefaults`, the
manifest still declared nothing, and Apple rejects a build that touches a required-reason
API without declaring it — with a message that names the API category rather than the code
that called it.

Declared now, with `CA92.1`: "information accessible only to the app itself", which is the
literal truth — four keys, no app group, no shared container, nothing about the child. A
sweep for the other required-reason categories found nothing: no file timestamps, no
disk-space APIs, no system boot time, no active-keyboard API.

Two tests hold it. One asserts the manifest still promises that nothing is tracked and
nothing is collected — the day somebody adds analytics is the day that test fails, which
is the entire point of having it. The other asserts the UserDefaults reason is there.

## Nothing is collected, and the manifest is how that is said in Apple's language

`NSPrivacyCollectedDataTypes` is empty and must stay empty. Worth writing down why the
microphone does not belong in it: under Apple's definition, using the microphone is not
collection unless the audio is stored or transmitted. It is neither — one in-memory
buffer, released when playback ends, never a file. Speech recognition is the same: the
request sets `requiresOnDeviceRecognition` and the app refuses to start a task without it,
so nothing reaches a server.

That means the App Privacy answer in App Store Connect is a single **No**, and the listing
shows **Data Not Collected**.

## The review notes are load-bearing

The parental gate is deliberately invisible: a small target in a corner that shows nothing
until it is held for three seconds. That is right for a three-year-old and wrong for a
reviewer, who will not find it and cannot check the settings they are required to check.

So `docs/APP_STORE.md` carries review notes that say exactly where the gate is and what it
asks for, alongside where each permission prompt appears and what happens when it is
declined. A Kids submission where the reviewer cannot reach the parent settings is a
rejection about something that works.

## A script measures the listing, because Apple measures it at the worst moment

App Store Connect enforces field limits one at a time, at submission, after the form is
filled in. A 31-character subtitle is a round trip for no reason.
`tools/check_metadata.py` reads the fenced blocks out of the metadata draft and measures
them, and CI runs it. It also refuses a keyword list with a space beside a comma, which
silently wastes one of the hundred characters each time.

---

## Open, and deliberately deferred

- **The room is painted for night only.** The window follows the clock, but a bright
  morning attic would need the room itself repainted; the app tints it gently instead.
- **`content/` is empty.** The schema and loader are deliverable 3.
- **There are no tests yet.** The units worth testing — `TimeOfDay` bucketing, the tap
  target padding maths, the idle clock, and now the turn detector — are pure and will
  get a test target alongside deliverable 3, where the content loader makes one pay for
  itself. `tools/simulate_turn_detection.py` stands in for the detector until then; it
  is a real check, but it is a mirror of the Swift rather than the Swift itself, and the
  two can drift.
