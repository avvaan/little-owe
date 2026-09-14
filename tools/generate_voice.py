#!/usr/bin/env python3
"""Record the whole content pack with one ElevenLabs voice.

Every line the owl can say has a filename the app already looks for - `story_<id>_<page>`,
`set_<id>_<line>`, `game_<id>_prompt`, `question_<id>`, `phrase_<id>` and so on. This
works out that list from the content itself, so a line added to the JSON is a line this
script offers to record, with no list to keep in step by hand.

It is **resumable and idempotent**: a clip already in `content/<lang>/audio/` is skipped.
Five hundred and ninety-seven generations is not something to start over because the
network blinked at number four hundred.

    export ELEVENLABS_API_KEY=...
    python3 tools/generate_voice.py --dry-run          # what it would do, and the cost
    python3 tools/generate_voice.py --only phrase,set  # the owl's stock lines first
    python3 tools/generate_voice.py                    # everything still missing

The app falls back to the speech synthesiser per line, not per build, so a half-recorded
pack is a perfectly good state to stop in: the recorded lines play, the rest are spoken.
"""

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# The narrator. A voice id only ever comes from the ElevenLabs voice list, never from
# memory. This is "Jessica - Playful, Bright, Warm", chosen by the person this app is for.
#
# Note for anyone changing it: searching the library for this name also turns up a
# "Jessika natural" whose own description is about erotic expression. Read the
# description, not just the name.
DEFAULT_VOICE = "cgSgspJ2msm6clMCkdW9"
DEFAULT_MODEL = "eleven_multilingual_v2"

# Consistency matters more than expressiveness across six hundred clips: a narrator who
# sounds like a different person in the middle of a story is worse than one who is a
# little even.
VOICE_SETTINGS = {
    "stability": 0.55,
    "similarity_boost": 0.8,
    "style": 0.0,
    "use_speaker_boost": True,
}

API = "https://api.elevenlabs.io/v1/text-to-speech/{voice}?output_format=mp3_44100_128"


def content_dir(language):
    return os.path.join(ROOT, "content", language)


def load(language, name):
    with open(os.path.join(content_dir(language), name), encoding="utf-8") as f:
        return json.load(f)


def every_line(language):
    """(stem, text) for everything the owl can say, in the app's own naming.

    Kept in one place and derived from the content, because the alternative is a list
    that silently stops matching `Speakable.audioStem` the first time a mode is added.
    """
    clips = []

    for story in load(language, "stories.json")["stories"]:
        for page in story["pages"]:
            clips.append((f"story_{story['id']}_{page['id']}", page["text"]))

    for spoken in load(language, "spoken-sets.json")["sets"]:
        for line in spoken["lines"]:
            clips.append((f"set_{spoken['id']}_{line['id']}", line["text"]))

    for game in load(language, "word-games.json")["games"]:
        clips.append((f"game_{game['id']}_prompt", game["prompt"]))
        clips.append((f"game_{game['id']}_reveal", game["reveal"]))
        # The no-recognition path: the owl reads each card aloud while it lights up.
        for index, choice in enumerate(game.get("choices", [])):
            clips.append((f"game_{game['id']}_choice_{index}", choice))

    for question in load(language, "questions.json")["questions"]:
        clips.append((f"question_{question['id']}", question["answer"]))
        # Read out on the tap-to-choose cards, so the question itself is spoken too.
        clips.append((f"question_{question['id']}_prompt", question["text"]))

    for group, items in load(language, "phrases.json")["groups"].items():
        if group.startswith("_"):          # a note to translators, not a group
            continue
        for phrase in items:
            clips.append((f"phrase_{phrase['id']}", phrase["text"]))

    stems = [stem for stem, _ in clips]
    if len(set(stems)) != len(stems):
        raise SystemExit("two lines want the same filename - fix the content ids first")
    return clips


def already_recorded(audio_dir, stem):
    # Match ContentLoader, which takes the first of these it finds.
    return any(os.path.exists(os.path.join(audio_dir, stem + ext))
               for ext in (".m4a", ".caf", ".wav", ".mp3"))


def speak(text, voice, model, key, retries=4):
    body = json.dumps({
        "text": text,
        "model_id": model,
        "voice_settings": VOICE_SETTINGS,
    }).encode("utf-8")
    request = urllib.request.Request(
        API.format(voice=voice),
        data=body,
        headers={"xi-api-key": key, "Content-Type": "application/json",
                 "Accept": "audio/mpeg"},
    )

    for attempt in range(retries):
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                return response.read()
        except urllib.error.HTTPError as error:
            detail = error.read().decode("utf-8", "replace")[:300]
            # 429 is the rate limit and 5xx is their end: both are worth waiting out.
            # Anything else - a bad key, an unknown voice, no quota left - will not get
            # better by trying again, and saying so now beats six hundred failures.
            if error.code not in (429, 500, 502, 503, 504) or attempt == retries - 1:
                raise SystemExit(f"ElevenLabs said {error.code}: {detail}")
            wait = 2 ** attempt
            print(f"    {error.code}, waiting {wait}s", flush=True)
            time.sleep(wait)
        except urllib.error.URLError as error:
            if attempt == retries - 1:
                raise SystemExit(f"could not reach ElevenLabs: {error}")
            time.sleep(2 ** attempt)
    raise SystemExit("unreachable")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--language", default="en")
    ap.add_argument("--voice", default=DEFAULT_VOICE)
    ap.add_argument("--model", default=DEFAULT_MODEL)
    ap.add_argument("--only", default="",
                    help="comma-separated prefixes: phrase,set,story,game,question")
    ap.add_argument("--limit", type=int, default=0, help="stop after this many clips")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    audio_dir = os.path.join(content_dir(args.language), "audio")
    os.makedirs(audio_dir, exist_ok=True)

    clips = every_line(args.language)
    if args.only:
        wanted = tuple(p.strip() for p in args.only.split(",") if p.strip())
        clips = [c for c in clips if c[0].startswith(wanted)]

    missing = [(stem, text) for stem, text in clips if not already_recorded(audio_dir, stem)]
    have = len(clips) - len(missing)
    characters = sum(len(text) for _, text in missing)

    print(f"content/{args.language}: {len(clips)} lines, {have} already recorded")
    print(f"to record: {len(missing)} clips, {characters:,} characters")
    print(f"ElevenLabs bills about one credit per character, so roughly "
          f"{characters:,} credits")

    if args.limit:
        missing = missing[:args.limit]
        print(f"limited to {len(missing)} this run")

    if args.dry_run:
        for stem, text in missing[:12]:
            print(f"  {stem:44} {text[:60]}")
        if len(missing) > 12:
            print(f"  ... and {len(missing) - 12} more")
        return 0

    if not missing:
        print("nothing to do")
        return 0

    key = os.environ.get("ELEVENLABS_API_KEY")
    if not key:
        raise SystemExit("set ELEVENLABS_API_KEY")

    for index, (stem, text) in enumerate(missing, 1):
        audio = speak(text, args.voice, args.model, key)
        path = os.path.join(audio_dir, stem + ".mp3")
        # Written whole, then moved into place: a run interrupted mid-write must not
        # leave a truncated file that the next run then skips as "already recorded".
        with open(path + ".part", "wb") as f:
            f.write(audio)
        os.replace(path + ".part", path)
        print(f"  {index:4}/{len(missing)}  {stem:44} {len(audio) // 1024:4} KB", flush=True)

    print(f"\nwrote {len(missing)} clips to {os.path.relpath(audio_dir, ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
