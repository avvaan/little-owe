# Content packs

Everything the owl says lives here, not in Swift. A pack is one folder per language,
and **nothing in the code names a language**: `ContentLoader` finds packs by looking, so
adding Russian is copying `en/` to `ru/`, translating the strings, and rebuilding.

```
content/
  en/
    pack.json          the manifest: language, voice locale, which file is which
    heroes.json        the cards a child taps to choose a story
    stories.json       stories, each an ordered list of pages
    spoken-sets.json   prayers and rhymes — the same shape, told apart by `kind`
    word-games.json    tasks, their accepted answers, and the picture fallback
    questions.json     the Why bank and its matching keywords
    phrases.json       the owl's own stock lines: praise, encouragement, "ask a grown-up"
    audio/             the voice actor's recordings
    illustrations/     story pages and hero cards
```

The folder is added to the app target as a **folder reference**, so this structure
survives into the bundle. Loose resources would flatten, and `en/pack.json` would
collide with `ru/pack.json`.

## Audio is named by convention

No JSON file lists an audio filename. Each line's recording is found by its identity:

| Line | File in `audio/` |
|---|---|
| Story page | `story_<storyId>_<pageId>` |
| Prayer or rhyme line | `set_<setId>_<lineId>` |
| Word game prompt | `game_<gameId>_prompt` |
| Word game reveal | `game_<gameId>_reveal` |
| Why answer | `question_<questionId>` |
| Stock phrase | `phrase_<phraseId>` |

Any of `.m4a`, `.caf`, `.wav`, `.mp3`. A line may still carry an explicit `"audio"` key
when a take needs its own name.

This means the voice actor can be handed a list of filenames and their recordings drop
straight in — nobody edits JSON to connect them. A test checks that no two lines want
the same filename, because that would silently give two lines the same take.

**A missing recording is not an error.** The owl speaks that line with
`AVSpeechSynthesizer` instead, per line rather than per build — so a half-recorded pack
works, which is the normal state for weeks while recording happens.

## What is deliberately incomplete

- **One story per hero.** The brief asks for at least six. The shape is proven and
  tested; the rest is writing.
- **28 Why questions.** The brief asks for 100 to 200.
- **Every prayer is marked `"placeholder": true`** — traditional texts standing in until
  the family supplies its own. A test fails if a prayer loses that mark, so nothing
  ships pretending to be chosen.
- **No audio and no illustrations yet.** Both folders are empty.

## Adding a language

1. Copy `en/` to `<code>/` and translate every `text`, `title`, `prompt`, `reveal` and
   `answer`.
2. In `pack.json` set `language`, `displayName`, `speechLocale` and `recognitionLocale`.
3. Rewrite `keywords` and `accepted` in the new language. **Do not translate them
   literally** — they are what a child actually says, and the matcher strips that
   language's function words.
4. Rebuild. That is all.
