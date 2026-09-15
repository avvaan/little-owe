#!/usr/bin/env python3
"""Render the Word games and Why screens outside the app, from the app's own constants.

A review aid, not part of the app. The owl's spot, the card row and the caption position
are parsed out of the mode files, so a preview cannot quietly drift from what SpriteKit
lays out. What it is really for is catching the thing numbers do not show: a card sitting
on the owl.

    python3 tools/compose_choices.py     # docs/preview/wordgame-*.png, why-*.png

Needs Pillow:  pip install Pillow
"""

import json
import os
import re
import sys

try:
    from PIL import Image, ImageDraw
except ImportError:
    sys.exit("This needs Pillow:  pip install Pillow")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "docs", "preview")

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from compose_room import L, W, H, sk, paste, compose
from compose_prayers import layer, dimmed_room, font, note, approach_point


def swift_point(path, name):
    text = open(os.path.join(ROOT, path)).read()
    m = re.search(rf"var {name} = CGPoint\(x:\s*(-?[\d.]+),\s*y:\s*(-?[\d.]+)\)", text)
    if m:
        return (float(m.group(1)), float(m.group(2)))
    m = re.search(rf"var {name} = RoomLayout\.approachPoint\(for:\s*\.(\w+)\)", text)
    return approach_point(m.group(1))


def swift_caption(path):
    text = open(os.path.join(ROOT, path)).read()
    pos = re.search(r"caption\.position = CGPoint\(x:\s*(-?[\d.]+),\s*y:\s*(-?[\d.]+)\)", text)
    size = re.search(r"CaptionNode\(maxWidth:\s*(\d+),\s*fontSize:\s*(\d+)\)", text)
    return (float(pos.group(1)), float(pos.group(2))), int(size.group(1)), int(size.group(2))


CARD = swift_point("LittleOwl/Modes/SpokenChoices.swift", "__none__") if False else None
_choice_src = open(os.path.join(ROOT, "LittleOwl/Modes/SpokenChoices.swift")).read()
_m = re.search(r"cardSize = CGSize\(width:\s*(\d+),\s*height:\s*(\d+)\)", _choice_src)
CARD_W, CARD_H = float(_m.group(1)), float(_m.group(2))
CARD_GAP = float(re.search(r"gap: CGFloat = (\d+)", _choice_src).group(1))
TINTS = [int(x, 16) for x in re.findall(r"0x([0-9A-Fa-f]{6})", _choice_src)][:5]


def rgb(value, alpha=255):
    return (value >> 16 & 255, value >> 8 & 255, value & 255, alpha)


def wrap(d, text, f, max_width):
    lines, line = [], []
    for word in text.split():
        trial = " ".join(line + [word])
        if d.textlength(trial, font=f) > max_width and line:
            lines.append(" ".join(line))
            line = [word]
        else:
            line.append(word)
    if line:
        lines.append(" ".join(line))
    return lines


def draw_caption(d, text, centre, max_width, size, lit=False):
    """Mirrors CaptionNode, scrim included: on a lit wall the words need a panel."""
    f = font(size)
    lines = wrap(d, text, f, max_width)
    used = max((d.textlength(l, font=f) for l in lines), default=0)
    height = len(lines) * size * 1.34
    top = sk(centre[1])

    pad_x, pad_y = size * 0.7, size * 0.5
    d.rounded_rectangle(
        [centre[0] - used / 2 - pad_x, top - pad_y + size * 0.32,
         centre[0] + used / 2 + pad_x, top + height + pad_y - size * 0.32],
        radius=size * 0.45, fill=(5, 5, 5, 112))

    y = top
    for line in lines:
        width = d.textlength(line, font=f)
        d.text((centre[0] - width / 2, y), line, font=f,
               fill=(255, 230, 176, 255) if lit else (240, 240, 240, 190))
        y += size * 1.34


def draw_cards(d, labels, centre, lit_index=0):
    total = len(labels) * CARD_W + (len(labels) - 1) * CARD_GAP
    x = centre[0] - total / 2 + CARD_W / 2
    y = sk(centre[1])
    f = font(34)
    for index, label in enumerate(labels):
        lit = index == lit_index
        box = [x - CARD_W / 2, y - CARD_H / 2, x + CARD_W / 2, y + CARD_H / 2]
        d.rounded_rectangle(box, radius=22, fill=rgb(TINTS[index % len(TINTS)]),
                            outline=(255, 230, 176, 255) if lit else (255, 255, 255, 90),
                            width=7 if lit else 4)
        # The card carries no words in the app - it is the owl's voice that names it.
        # Here the name is drawn faintly so a reviewer can tell the cards apart.
        lines = wrap(d, label, f, CARD_W - 40)
        top = y - len(lines) * 40 / 2
        for offset, line in enumerate(lines):
            width = d.textlength(line, font=f)
            d.text((x - width / 2, top + offset * 40), line, font=f,
                   fill=(255, 255, 255, 120))
        x += CARD_W + CARD_GAP


def word_game_screen(game):
    canvas = dimmed_room(owl=False)
    spot = swift_point("LittleOwl/Modes/WordGameMode.swift", "playingSpot")
    cards = swift_point("LittleOwl/Modes/WordGameMode.swift", "choicesCentre")
    caption_pos, caption_width, caption_size = swift_caption("LittleOwl/Modes/WordGameMode.swift")

    paste(canvas, "owl_base.png", (spot[0], spot[1] + L["owlHeight"] / 2), L["owlHeight"])
    over = layer()
    d = ImageDraw.Draw(over, "RGBA")
    draw_caption(d, game["prompt"], caption_pos, caption_width, caption_size)
    draw_cards(d, game["choices"], cards, lit_index=1)
    canvas.alpha_composite(over)
    note(canvas, "no recognition on this iPad: the owl reads each card aloud while it lights up, "
                 "and the child taps the one they heard")
    return canvas


def why_screen(question):
    canvas = dimmed_room(owl=False)
    spot = swift_point("LittleOwl/Modes/WhyMode.swift", "askingSpot")
    caption_pos, caption_width, caption_size = swift_caption("LittleOwl/Modes/WhyMode.swift")

    paste(canvas, "owl_base.png", (spot[0], spot[1] + L["owlHeight"] / 2), L["owlHeight"])
    over = layer()
    d = ImageDraw.Draw(over, "RGBA")
    draw_caption(d, question["answer"], caption_pos, caption_width, caption_size, lit=True)
    canvas.alpha_composite(over)
    note(canvas, f"the child asked '{question['text']}' out loud, and the owl answered from the bank")
    return canvas


def why_choices_screen(questions):
    canvas = dimmed_room(owl=False)
    spot = swift_point("LittleOwl/Modes/WhyMode.swift", "askingSpot")
    cards = swift_point("LittleOwl/Modes/WhyMode.swift", "choicesCentre")

    paste(canvas, "owl_base.png", (spot[0], spot[1] + L["owlHeight"] / 2), L["owlHeight"])
    over = layer()
    d = ImageDraw.Draw(over, "RGBA")
    draw_cards(d, [q["text"] for q in questions], cards, lit_index=0)
    canvas.alpha_composite(over)
    note(canvas, "the Why fallback: three questions the owl reads out, and the child taps one")
    return canvas


if __name__ == "__main__":
    games = json.load(open(os.path.join(ROOT, "content", "en", "word-games.json")))["games"]
    questions = json.load(open(os.path.join(ROOT, "content", "en", "questions.json")))["questions"]
    os.makedirs(OUT_DIR, exist_ok=True)

    sound = next(g for g in games if g["kind"] == "animalSound")
    pages = [
        ("wordgame-cards.png", word_game_screen(sound)),
        ("why-answer.png", why_screen(questions[0])),
        ("why-cards.png", why_choices_screen(questions[:3])),
    ]
    for name, canvas in pages:
        path = os.path.join(OUT_DIR, name)
        canvas.convert("RGB").save(path, quality=92)
        print("wrote", os.path.relpath(path, ROOT))
