# Where everything in this app came from

Little Owl ships free, with no ads, no in-app purchases and no accounts. That is a
pricing decision and nobody else has standing in it: a competitor has no claim on the
fact that something cheaper sits next to them in the store, and Apple does not take
complaints of that shape. **Price is not the risk. Provenance is.**

So this file is the list. One row per thing that ships inside the app, where it came
from, and on what basis it is allowed to be there. It is meant to be the answer to a
letter, which means it has to be true rather than reassuring — the last section is the
part that is not settled yet, and it is deliberately the longest.

---

## What actually ships

| In the app | What it is | Where it came from | Basis |
|---|---|---|---|
| `LittleOwl/` | Every line of Swift | Written for this project | Owned outright |
| Third-party code | **None.** No Swift packages, no CocoaPods, no vendored source | — | Nothing to license |
| `content/en/*.json` | The stories, the questions and their answers, the owl's stock lines | Written for this project | Owned outright |
| The four rhymes | Twinkle Twinkle, Humpty Dumpty, Hey Diddle Diddle, Row Row Row Your Boat | Public domain — see below | Public domain |
| The three prayers | **Still placeholder text** | Placeholder | Nothing shipped yet — see below |
| `content/en/audio/*.mp3` | 601 recorded lines | ElevenLabs text-to-speech, voice `cgSgspJ2msm6clMCkdW9` | ElevenLabs paid-plan commercial licence — **to confirm** |
| `content/en/illustrations/*.jpg` | 260 paintings — story pages, set cards, answer cards, question cards | Higgsfield, model `gpt_image_2_5`, all on 14 September 2026 | Higgsfield output terms — **to confirm** |
| `Resources/Art/owl_*.png`, `window_sky_{morning,day,evening}.png` | The owl's six expression frames and three of the four skies | Higgsfield | Same as above |
| `Resources/Art/corner_basket.png` | The basket in the corner | Higgsfield | Same as above |
| `Resources/Art/dog_base.png` | The puppy | Higgsfield | Same as above |
| `Resources/Art/room_bg.jpg`, `owl_base.png`, `block_*.png`, `window_sky_night.png`, `patch_book.png` | The room painting and everything cut out of it | **Not recorded anywhere** — see below | **Unknown** |
| `Resources/Audio/*.wav` | Six sound effects: two giggles, a hum, a hop, a tap, a wake | `tools/make_placeholder_sfx.py` — synthesised from sine waves and noise, no samples | Owned outright |
| Type | `AvenirNext-Medium` for captions, `Menlo` in the debug overlay | Shipped with iOS | Apple's system fonts, used on-device |

### The rhymes

All four are long out of copyright, and `content/en/spoken-sets.json` records the
attribution line by line rather than leaving it to be remembered:

- *Twinkle, Twinkle, Little Star* — Jane Taylor, 1806
- *Humpty Dumpty*, *Hey Diddle Diddle*, *Row, Row, Row Your Boat* — traditional

The recordings of them are a separate question — those are ElevenLabs output, and are
covered by the voice row above. A public-domain text read by a licensed voice is two
permissions, not one.

### The prayers

All three sets are still `"placeholder": true` and the parent settings screen says so
out loud. Nothing has shipped that anybody could have a claim on. **When real texts go
in, they need a row here**, because a prayer in current use can be under copyright —
modern translations and denominational wordings routinely are, even where the prayer
itself is ancient. Public domain is not the default for a text simply because it is old.

---

## ElevenLabs — the voice

**What the terms say.** Paid plans carry a commercial licence and the user owns the
generated audio; the rights are perpetual, so audio generated while on a paid plan stays
usable even after the subscription ends. Free-plan output may **not** be used
commercially and must be attributed to `elevenlabs.io`. ElevenLabs keeps a licence to
use content for training, but undertakes not to commercialise a voice standalone.

- Terms: <https://elevenlabs.io/terms-of-use>
- Help centre: <https://elevenlabs.io/docs/help-center/legal/can-i-publish-the-content-i-generate-on-the-platform>

**Why "free app" does not help here.** The distinction these terms draw is free plan
versus paid plan, not free app versus paid app. Publishing 601 recordings inside a
product in the App Store is publishing, whatever the download costs. Releasing at zero
does not move this into the free tier's allowance — if anything it is the paid-plan
licence that makes it fine.

**Two things this file cannot settle** — see the open list below.

## Higgsfield — the paintings

**What the terms say.** Higgsfield does not claim ownership of inputs or outputs and
does not restrict commercial use of outputs; the list of permitted uses explicitly
includes *products that incorporate AI-generated visuals*. Rights in exported outputs
survive cancellation of the subscription or deletion of the account, and may be
transferred or sublicensed. Content may be used to train Higgsfield's models unless
deleted or under an Enterprise agreement.

- Terms: <https://higgsfield.ai/terms-of-use-agreement>
- Help centre: <https://higgsfield.ai/creator-hub/help-center/account/who-owns-my-generations-and-can-i-use-them-commercially>

The account used for this project is on the **Plus** plan, which is a paid plan, and
every picture was generated on 14 September 2026.

`art-source/generated.json` is the audit trail: it maps all 262 fetched files to the
exact Higgsfield URL each one came from, and `tools/illustration_prompts.py` regenerates
the prompt behind every one of them from the content itself. If anybody ever asks where
a particular picture came from, those two files answer it without anybody having to
remember.

**The model underneath.** The paintings were made with `gpt_image_2_5`, which is
OpenAI's image model served through Higgsfield. Higgsfield is the counterparty — the
account, the payment and the terms above are all theirs — but it is worth knowing that
a second company's model produced the pixels, in case Higgsfield's arrangement with
them ever changes.

---

## Not settled

Everything above this line is either certain or quoted. Everything below is a real gap,
listed because a licensing page that only contains good news is not worth showing to
anybody.

**1. I could not read either vendor's terms first-hand.** This session's network proxy
blocks `elevenlabs.io` and `higgsfield.ai` outright. What is summarised above came from
web search results quoting those pages, not from the pages themselves. The wording was
consistent across sources and matches what both companies say publicly, but *it has not
been read at the source.* Open the two links in each section and check the wording
against what is written here. This takes about five minutes and is the single most
valuable thing on this list.

**2. Was the ElevenLabs account on a paid plan when the 601 clips were recorded?** This
is the hinge the whole voice question turns on, and it cannot be seen from the
repository — the API key lives in a GitHub secret and the plan lives in the dashboard.
If any clip was generated on the free tier it is not licensed for this use and must be
re-recorded, not merely attributed.

This one is easier than it sounds: **every one of the 601 clips was recorded on
14 September 2026**, in four runs of the Voice workflow on that single day. So it is one
date to check in the billing history, not a range.

**3. Is voice `cgSgspJ2msm6clMCkdW9` an ElevenLabs premade voice, or one shared through
the Voice Library?** It is labelled "Jessica — Playful, Bright, Warm" in
`tools/generate_voice.py`. The difference matters: a premade voice is ElevenLabs' own
and ElevenLabs is the only counterparty, whereas a Voice Library voice belongs to a
person who shared it and may carry its own terms on top of the plan's. The voice list
this session could reach did not include it. Look it up in the dashboard and write the
answer into this file.

**4. Where did the room painting come from?** `art-source/owl_bg_empty.png`,
`layer_owl.png` and `layer_block_*.png` are the foundation of everything — the room, the
owl's base, the blocks, the night sky and the patch of wall behind the book are all cut
from them. The commit that added them says only "the master layers exactly as
delivered" and refers to "the painter". Delivered by whom, and under what terms? If a
person painted them, there should be an invoice or a message saying the work is
assigned or licensed for commercial use; if they were generated, they belong in the
Higgsfield section with everything else. **This is the largest single asset in the app
and the only one with no recorded provenance at all.**

**5. The prayers, when they arrive.** Covered above — a row here before they ship, not
after.

---

## What would change the answer

- **Charging for the app, or adding ads or purchases.** Nothing above depends on the
  price being zero; both vendors' paid-plan licences cover commercial products outright.
  So this changes nothing legally — but it is worth re-reading the two links before
  doing it, since a licence that covers "products" is the clause you would then be
  leaning on harder.
- **Replacing the generated voice with a recorded actor.** Then the contract with that
  person becomes the governing document and the ElevenLabs rows come out.
- **Adding another language.** New recordings, new pictures, same two vendors, same
  questions — and a translator's work is theirs unless the agreement says otherwise.
- **Either vendor changing terms.** Rights already granted in the outputs generated
  today do not evaporate — both sets of terms say so explicitly — but anything generated
  after a change is under the new terms. That is the reason this file records *when*
  things were made, not only *what*.
