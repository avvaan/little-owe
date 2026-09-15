# App Store listing — a draft to paste in

Everything App Store Connect will ask for, written out. Nothing here is code; it is the
half of shipping that lives in a browser.

Character limits are Apple's and are checked by `tools/check_metadata.py`, which reads
this file — a listing rejected on submit for a 31-character subtitle is an avoidable
round trip.

---

## App Information

| Field | Value |
|---|---|
| Name | `Little Owl: Talk and Play` |
| Subtitle | `A talking owl in the attic` |
| Bundle ID | `com.syrkin.littleowl` |
| SKU | `com.syrkin.littleowl` |
| Primary category | **Kids** |
| Kids age band | **5 and under** |
| Secondary category | Education |
| Primary language | English (U.S.) |
| Privacy Policy URL | *(host `docs/PRIVACY_POLICY.md` somewhere and put the link here)* |
| Support URL | *(a page with a way to contact you — required)* |
| Marketing URL | *(optional; leave blank)* |

> **The privacy policy URL is not optional for a Kids listing.** Review will refuse the
> submission without one. Any stable public page will do: a GitHub Pages page, a Notion
> page, a page on a site you already own.

---

## Promotional text

*Up to 170 characters. Can be changed any time without a new build.*

```
A cosy attic, a small owl, and nothing to read. Your child taps, talks, and the owl
talks back — offline, with no ads and nothing to buy.
```

## Description

*Up to 4000 characters.*

```
Little Owl is a digital toy, not a chatbot.

There is one screen: a cosy attic room with a small owl who lives there. Your child taps
things, and the owl answers. Nothing has to be read, nothing has to be typed, and nothing
ever asks them to wait until tomorrow.

WHAT THE OWL DOES

Tap the owl and talk to it. It says whatever it heard straight back, in a funny high
voice. This is the whole app in miniature, and most children need no more than this on
the first day.

Tap the book on the shelf and pick a hero — a fox, a bunny, a bear, a mouse, a hedgehog.
The owl reads a short story, turning the pages itself, with the words lighting up one at
a time underneath for children who are starting to read.

Tap the lamp and the owl says a prayer or a nursery rhyme, one line at a time, and waits
for your child to say it back. It never says "wrong". If they are quiet, it gently says
the line again and then moves on.

Tap the letter blocks on the rug and the owl sets little tasks. Name an animal that
starts with M. Which one doesn't belong: apple, banana, chair? What sound does a cow make?
Your child answers out loud. There are no scores and no streaks — an answer that isn't on
the list gets "Good try! I think it's a monkey!" and the next question.

Tap the round window and ask the owl anything. It knows about a hundred and thirty things
children actually ask: why the sky is blue, where rain comes from, why cats purr, what is
inside a camel's hump. If it doesn't know, it says so and sends your child to ask you.

Tap the basket in the corner and the owl does the asking. It lays out three painted
cards, says what each one is about, and tells your child whichever one they tap. Same
hundred and thirty questions, the other way round — and this one needs no microphone at
all.

MADE FOR SMALL CHILDREN

Everything is a tap on an object. There are no menus, no buttons with words on, and no
text the child has to read. Captions appear only while the owl is speaking, and you can
turn them off.

Nothing times out and nothing ends by itself. There is no timer, no daily limit, no "come
back tomorrow", and nothing locked behind finishing something first. Your child plays for
as long as you let them, and tapping the owl always brings them back from anywhere.

Tap targets are large, every tap answers instantly with a sound and a movement, and the
sounds are soft — there is nothing in here that goes bang.

FOR GROWN-UPS

The owl works completely offline. The app has no networking code in it at all: it cannot
phone home, because there is nowhere for it to phone.

No ads. Nothing to buy. No accounts, no sign-in, no analytics, no tracking, and no
third-party software of any kind.

Nothing your child says is recorded or kept. When they talk to the owl, the sound lives in
memory for a few seconds and is then released — it never becomes a file and never leaves
the iPad. Speech recognition, where it is used, runs on the iPad itself.

Settings sit behind a grown-up gate — hold a corner for three seconds, then answer a sum.
Behind it you choose which objects are in the room, which prayers and rhymes are on the
lamp, whether captions show, and how loud the owl is. Those settings are the only thing
this app stores.

Little Owl needs an iPad and works best held in two hands, in landscape.
```

## Keywords

*Up to 100 characters total, comma-separated, no spaces after the commas.*

```
toddler,preschool,owl,talking,bedtime,story,rhyme,prayer,offline,speech,quiet,no ads
```

## What's New in This Version

*Up to 4000 characters. For 0.1:*

```
The first build. The owl, the room, and all five things it can do.
```

---

## App Privacy answers

App Store Connect → App Privacy. The answer to the first question settles the rest:

**"Do you or your third-party partners collect data from this app?"** → **No**

That is the literal truth and it matches `LittleOwl/Resources/PrivacyInfo.xcprivacy`,
where every list is empty. The listing then shows **Data Not Collected**.

Two things reviewers sometimes query, and the answers:

- **The microphone.** Using the microphone is not "collecting data" under Apple's
  definition unless the audio is stored or transmitted. It is neither: one in-memory
  buffer, released when playback ends, never written to disk.
- **Speech recognition.** The request sets `requiresOnDeviceRecognition` and the app
  refuses to start a task without it, so nothing is sent to Apple's servers either.

---

## Age rating questionnaire

Every content question is **None**. The app has no violence, no scares, no crude humour,
no medical or drug references, no gambling, no contests, no profanity and no sexual
content. The rest:

| Question | Answer |
|---|---|
| Unrestricted web access | **No** — there is no browser and no link out of the app |
| Made for Kids | **Yes**, age band **5 and under** |
| User-generated content | **No** |
| Messaging or chat | **No** |
| Social networking features | **No** |
| Account creation | **No** |
| Advertising | **No** |
| In-app purchases | **No** |
| Data collection for advertising | **No** |
| Location | **No** |

App Store Connect has newer questions about social-media capability; the answer to all of
them is **No**. The app has no way for one child to reach another, or anyone else.

---

## Screenshots

iPad, **landscape** — the app does not rotate. Apple wants the 13-inch size; the 11-inch
set is worth adding too.

| # | What to capture |
|---|---|
| 1 | The room at night: owl on its perch, lamp lit, moon in the window |
| 2 | A story being read — hero cards, or a page with the caption lit |
| 3 | The prayer and rhyme cards, the row of symbols |
| 4 | A word game with the owl listening — the ring around it |
| 5 | The room in daylight, so the window's time of day is visible |

Take them from a real device or the simulator once the artwork is final. There is no
point capturing placeholder shapes for the store.

**No text overlays promising anything the app does not do**, and nothing that implies a
reward, a purchase or a friend to play with.

---

## App Review notes

*This box matters more than it looks. Paste this in.*

```
Little Owl is a toy for children aged 3-6. It works entirely offline and makes no
network connections of any kind.

HOW TO REACH THE PARENT SETTINGS

The parental gate is deliberately hard for a child to find. Press and HOLD the
top-left corner of the screen for THREE SECONDS. A ring fills as you hold. Then
answer the addition shown (two-digit sum, e.g. 13 + 9) on the keypad. Releasing
early cancels silently and shows nothing, by design.

PERMISSIONS

- The microphone prompt appears on the FIRST TAP OF THE OWL and nowhere else.
- The speech-recognition prompt appears on the first tap of the lamp, and only
  after the microphone has already been granted.
- Both are optional. If either is declined, every mode still works: the owl waits
  a short pause instead of listening, and the word games and questions offer cards
  to tap instead of expecting speech.

WHAT IS NOT IN THE APP

No ads, no in-app purchases, no accounts, no links out, no user-generated content,
no third-party SDKs, no analytics. Speech recognition is on-device only
(requiresOnDeviceRecognition is set and the app will not start a task without it).
Audio is held in memory for a few seconds and released; it is never written to
disk and never transmitted.

KNOWN, AND DELIBERATE, IN THIS BUILD

Every spoken line uses the system speech synthesiser. Recordings by a voice actor
replace them without any code change. Story illustrations and the answer cards are
placeholder shapes for the same reason.
```

---

## Kids category checklist

| Requirement | Status |
|---|---|
| Parental gate before any settings | ✅ Hold three seconds, then a two-digit sum |
| Parental gate before leaving the app | ✅ Nothing leaves the app — there are no links |
| No behavioural advertising | ✅ No advertising at all |
| No third-party analytics | ✅ No third-party code at all |
| Privacy policy URL | ⬜ **Text is written; it needs hosting** — `docs/PRIVACY_POLICY.md` |
| Privacy manifest | ✅ `PrivacyInfo.xcprivacy`, everything empty except the UserDefaults reason |
| Required-reason APIs declared | ✅ `NSPrivacyAccessedAPICategoryUserDefaults` / `CA92.1` |
| No collection of personal information | ✅ Nothing is collected from anyone |
| Age band set on the record | ⬜ Set **5 and under** in App Information |
| Nothing purchasable | ✅ |
| No account or sign-in | ✅ |
| Content appropriate for the age band | ✅ |

### Not a Kids requirement, but it will be noticed

| | |
|---|---|
| The owl's voice | Synthesised. A voice actor's recordings drop into `content/en/audio/` with no code change |
| Prayer texts | Traditional placeholders, marked `"placeholder": true` in `content/en/spoken-sets.json` |
| Story illustrations, hero cards, answer cards | Placeholder shapes; the app works without them |
| The lamp and the window in parent settings | Switch the mode off but stay painted in the room — see `docs/ART_BRIEF.md` |
