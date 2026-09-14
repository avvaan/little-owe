#!/usr/bin/env python3
"""Work out the prompt for every picture the content pack asks for.

Derived from the content, for the same reason `generate_voice.py` is: a page added to
the JSON is a picture this offers, with no second list to keep in step. And the scene
comes from the page's own sentence rather than from somebody's memory of it, so the
picture cannot end up showing something the owl does not read out.

    python3 tools/illustration_prompts.py stories > /tmp/prompts.json
    python3 tools/illustration_prompts.py --count
"""

import argparse
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load(language, name):
    with open(os.path.join(ROOT, "content", language, name), encoding="utf-8") as f:
        return json.load(f)


# One voice for every picture in the app, so a story page and a game card look like they
# came from the same hand. Worth keeping in one string rather than pasted per call.
STYLE = ("Children's storybook watercolour illustration. Soft loose watercolour washes "
         "with visible paper grain and hand-painted brush texture, gentle warm palette, "
         "naive storybook charm, soft rounded shapes. No ink outline, no digital "
         "smoothing, no 3D render, no photorealism, no text, no lettering, no numbers, "
         "no watermark, no border or frame. Calm and tender mood for a picture book for "
         "a three-year-old, nothing frightening.")

# The hero has to be recognisably the same animal across ten pages, so the description
# is fixed here rather than left to the sentence, which mentions the hero by name and
# says nothing about what they look like.
HEROES = {
    "fox": "Fern, a small friendly fox with warm ginger fur, a cream chest and a "
           "white-tipped tail",
    "bunny": "Pip, a very small soft cream-coloured bunny with long ears and a round face",
    "bear": "Bramble, a round friendly brown bear cub with a honey-coloured muzzle",
    "mouse": "Tilly, a small brown mouse with big round ears and bright dark eyes",
    "hedgehog": "Nub, a small hedgehog with soft brown spines and a gentle round face",
}


# The season and the place, fixed per story and stated as firmly as the hero.
#
# This is not decoration. The first cut left the setting to each page's own sentence,
# and a story that opens on a frosty morning in the snow reached page five - "she asked
# the rabbits under the hedge" - in high summer, green grass and all, because that
# sentence says nothing about winter. A child notices the snow going away.
SETTINGS = {
    "fox-lost-mitten":
        "Deep winter throughout: snow on the ground in every scene, bare birches and "
        "snow-laden firs, a pale cold sky, breath-cold air. No green grass, no leaves, "
        "no summer anywhere in this story",
    "bunny-tallest-grass":
        "High summer throughout: a wide green meadow of tall grasses and wildflowers, "
        "warm sunlight, soft blue sky with a few clouds. No snow, no autumn anywhere in "
        "this story",
    "bear-slow-honey":
        "Late summer throughout: a warm sunlit woodland of oaks and birches, dappled "
        "green shade, bees and long golden light. No snow, no winter anywhere in this "
        "story",
    "mouse-night-light":
        "Night throughout, mostly inside an old cottage: a dim warm kitchen and the "
        "dusty space behind its wall, lit by moonlight through a window and a single "
        "small warm glow. Quiet and cosy, never dark enough to frighten. No daylight "
        "anywhere in this story",
    "hedgehog-first-hello":
        "Autumn throughout: an old English garden with a long hedge, heaps of dry brown "
        "and gold leaves, soft low sunlight, bare seed-heads. No snow, no summer green "
        "anywhere in this story",
}


def story_prompts(language):
    """(target, prompt) for every story page."""
    out = []
    for story in load(language, "stories.json")["stories"]:
        hero = HEROES.get(story["heroId"], "a small friendly woodland animal")
        setting = SETTINGS.get(story["id"], "")
        for page in story["pages"]:
            stem = os.path.splitext(page["illustration"])[0]
            prompt = (
                f"{STYLE} The recurring character is {hero} — the same animal on every "
                f"page of this story. Setting: {setting}. Wide landscape composition "
                f"with generous empty space. The scene to paint: {page['text']}"
            )
            out.append((f"content/{language}/illustrations/{stem}.jpg", prompt))
    return out


def game_prompts(language):
    """(target, prompt) for every word-game answer card.

    A card is one thing on a plain ground, not a scene: it is 148 x 186 points and a
    child picks between three of them at a glance.
    """
    out = []
    for game in load(language, "word-games.json")["games"]:
        for index, choice in enumerate(game.get("choices", [])):
            prompt = (
                f"{STYLE} A single subject alone, centred, filling most of the square "
                f"with clear margin, painted on a plain soft cream background with no "
                f"scene and no other objects. The subject: {choice}."
            )
            out.append((f"content/{language}/illustrations/game_{game['id']}_choice_{index}.jpg",
                        prompt))
    return out


def question_prompts(language):
    """(target, prompt) for the cards the owl offers when it asks rather than answers."""
    out = []
    for question in load(language, "questions.json")["questions"]:
        prompt = (
            f"{STYLE} A single simple subject, centred, filling most of the square with "
            f"clear margin, painted on a plain soft cream background. It illustrates "
            f"this question for a child who cannot read it: {question['text']}"
        )
        out.append((f"content/{language}/illustrations/question_{question['id']}.jpg", prompt))
    return out


SETS = {"stories": story_prompts, "games": game_prompts, "questions": question_prompts}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("which", nargs="?", choices=sorted(SETS) + ["all"], default="all")
    ap.add_argument("--language", default="en")
    ap.add_argument("--count", action="store_true")
    ap.add_argument("--missing", action="store_true",
                    help="only the ones not already in content/")
    args = ap.parse_args()

    wanted = SETS.keys() if args.which == "all" else [args.which]
    pairs = [p for name in wanted for p in SETS[name](args.language)]

    if args.missing:
        pairs = [(t, p) for t, p in pairs if not os.path.exists(os.path.join(ROOT, t))]

    if args.count:
        for name in sorted(SETS):
            print(f"{name:10} {len(SETS[name](args.language)):4}")
        print(f"{'total':10} {len(pairs):4}")
        return 0

    json.dump([{"target": t, "prompt": p} for t, p in pairs], sys.stdout, indent=1)
    return 0


if __name__ == "__main__":
    sys.exit(main())
