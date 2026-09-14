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
        "A warm afternoon inside a cosy wooden cottage: honey-coloured plank walls and "
        "floor, a tall wooden shelf, a window with long low afternoon sunlight coming "
        "through it and dust turning in the light. Almost every page of this story is "
        "indoors. No snow, no night",
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


# The answer cards are named by the word, not by the game and slot: the app asks for
# `choice_apple`, and the same apple is meant to be the same apple wherever it appears.
# Seventy-four distinct words fill a hundred and forty-one card slots.
#
# They are not all the same kind of thing, and painting them as if they were is how you
# get a picture of the written word "moo".
SOUNDS = {
    "moo": "a friendly cow", "quack": "a friendly duck", "woof": "a friendly dog",
    "meow": "a friendly cat", "baa": "a friendly sheep", "neigh": "a friendly horse",
    "oink": "a friendly pig", "ribbit": "a friendly frog", "buzz": "a friendly bee",
    "hoo": "a friendly owl",
}
COLOURS = {"red", "blue", "green", "yellow", "black", "white", "brown", "orange", "purple"}
NUMBERS = {"one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
           "six": 6, "eight": 8, "ten": 10}

CARD = ("A single subject alone, centred, filling most of the square with a clear even "
        "margin, painted on a plain soft cream background with no scene, no shadow and "
        "no other objects.")


# Words the rules above get wrong. Small enough to write out, and writing them out is
# cheaper than a picture of "a sand".
IRREGULAR = {
    "bread": "a warm crusty loaf of bread",
    "cheese": "a wedge of cheese",
    "ice": "a clear block of ice with frost on it",
    "sand": "a small heap of golden sand with a few shells",
    "sea": "the open sea with gentle waves",
    "fire": "a small friendly campfire with warm flames, cosy and safe, not dangerous",
    "river": "a winding river between green banks",
    "nose": "a single friendly animal nose and whiskers, close up",
    "one": "one single small round acorn, alone and clearly just the one",
    # White paint on a cream card is not a picture of anything.
    "white": "a soft rounded watercolour patch of clean white, given a faint soft grey "
             "edge so that it reads clearly against the pale cream paper, and nothing "
             "else at all",
}


def word_subject(word):
    """What to paint for one answer word.

    A sound is painted as the animal that makes it - there is no painting of the noise
    "moo", and a child who cannot read needs something on the card. That does make the
    sound games easier: the child finds the cow rather than recalling the word. For a
    three-year-old, with no score kept anywhere in this app, that is the right trade.
    """
    if word in IRREGULAR:
        return IRREGULAR[word]
    if word in SOUNDS:
        return SOUNDS[word]
    if word in COLOURS:
        return (f"a soft rounded watercolour patch of clear {word} colour, like a wash "
                f"of {word} paint on paper, and nothing else at all")
    if word in NUMBERS:
        n = NUMBERS[word]
        return (f"exactly {n} identical small round acorns arranged clearly and evenly "
                f"so a child can count them, {n} and no more")
    article = "an" if word[0] in "aeiou" else "a"
    return f"{article} {word}"


def game_prompts(language):
    """(target, prompt) for every distinct answer word across the word games."""
    words = sorted({c for game in load(language, "word-games.json")["games"]
                    for c in game.get("choices", [])})
    return [(f"content/{language}/illustrations/choice_{w}.jpg",
             f"{STYLE} {CARD} The subject: {word_subject(w)}.")
            for w in words]


def question_prompts(language):
    """(target, prompt) for the cards the owl offers when a child does not speak."""
    out = []
    for question in load(language, "questions.json")["questions"]:
        prompt = (f"{STYLE} {CARD} It illustrates this question for a child who cannot "
                  f"read it, so paint what the question is *about* rather than the "
                  f"answer: {question['text']}")
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
