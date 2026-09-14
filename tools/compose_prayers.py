#!/usr/bin/env python3
"""Render the Prayers and rhymes screens outside the app, from the app's own constants.

A review aid, not part of the app. Card size, gap, row-wrapping rule and the mode's
layer constants are parsed out of the Swift, and the sets come from the shipped content
pack — so the composition cannot quietly drift from what SpriteKit lays out.

The symbols themselves are redrawn here rather than parsed, so treat the shapes as
indicative and the positions as exact.

    python3 tools/compose_prayers.py     # docs/preview/prayers-*.png

Needs Pillow:  pip install Pillow
"""

import json
import math
import os
import re
import sys

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    sys.exit("This needs Pillow:  pip install Pillow")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(ROOT, "LittleOwl", "Resources", "Art")
OUT_DIR = os.path.join(ROOT, "docs", "preview")

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from compose_room import L, W, H, sk, paste, compose   # same layout, same room


def swift_numbers(path):
    text = open(os.path.join(ROOT, path)).read()
    out = {}
    for name, num in re.findall(r"static let (\w+)(?::\s*CGFloat)?\s*=\s*(-?[\d.]+)\b", text):
        out[name] = float(num)
    for name, body in re.findall(r"static let (\w+)\s*=\s*CGSize\(([^)]*)\)", text):
        out[name] = {k: float(v) for k, v in re.findall(r"(\w+):\s*(-?[\d.]+)", body)}
    return out


P = swift_numbers("LittleOwl/Modes/SpokenSetPicker.swift")
CARD_W = P["cardSize"]["width"]
CARD_H = P["cardSize"]["height"]
GAP = P["gap"]
ROW_GAP = P["rowGap"]
MAX_PER_ROW = int(P["maxPerRow"])


def rows(count):
    """Mirrors SpokenSetPicker.rows(for:)."""
    if count <= 0:
        return []
    row_count = math.ceil(count / MAX_PER_ROW)
    base, extra = divmod(count, row_count)
    return [base + (1 if i < extra else 0) for i in range(row_count)]


def approach_point(object_id):
    """RoomLayout.approachPoint(for:) — where the owl lands when it goes to a prop."""
    text = open(os.path.join(ROOT, "LittleOwl", "Room", "RoomLayout.swift")).read()
    m = re.search(rf"case \.{object_id}:\s*return CGPoint\(x:\s*(-?[\d.]+),\s*y:\s*(-?[\d.]+)\)", text)
    return (float(m.group(1)), float(m.group(2)))


def font(size):
    for name in ("DejaVuSans.ttf", "LiberationSans-Regular.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def hexcolour(value, alpha=255):
    v = int(value, 16)
    return (v >> 16 & 255, v >> 8 & 255, v & 255, alpha)


# ------------------------------------------------------------------- symbols

def symbol(d, kind, cx, cy, h, fill, behind=(0, 0, 0, 0)):
    r = h / 2
    if kind == "sun":
        core = h * 0.27
        d.ellipse([cx - core, cy - core, cx + core, cy + core], fill=fill)
        for i in range(8):
            a = i * math.pi / 4
            spread = (math.pi / 4) * 0.16
            pts = [(cx + math.cos(a - spread) * core * 1.18, cy - math.sin(a - spread) * core * 1.18),
                   (cx + math.cos(a) * r, cy - math.sin(a) * r),
                   (cx + math.cos(a + spread) * core * 1.18, cy - math.sin(a + spread) * core * 1.18)]
            d.polygon(pts, fill=fill)
    elif kind == "moon":
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=fill)
        o, ir = r * 0.40, r * 0.86
        # In the app the bite is a hole in one path and the card shows through it.
        d.ellipse([cx + o - ir, cy - ir, cx + o + ir, cy + ir], fill=behind)
    elif kind == "bowl":
        w = h * 0.46
        d.pieslice([cx - w, cy - h * 0.36, cx + w, cy + h * 0.36], 0, 180, fill=fill)
        d.rectangle([cx - w * 1.12, cy - h * 0.05, cx + w * 1.12, cy + h * 0.04], fill=fill)
        # One curl of steam, centred: two marks above a rimmed half-disc read as a face.
        d.line([(cx + h * 0.07, cy - h * 0.10), (cx - h * 0.07, cy - h * 0.22),
                (cx + h * 0.07, cy - h * 0.32), (cx, cy - h * 0.40)],
               fill=fill, width=max(2, round(h * 0.05)), joint="curve")
    elif kind == "star":
        pts = []
        for i in range(10):
            a = -math.pi / 2 + i * math.pi / 5
            rad = r if i % 2 == 0 else r * 0.42
            pts.append((cx + math.cos(a) * rad, cy + math.sin(a) * rad))
        d.polygon(pts, fill=fill)
    elif kind == "egg":
        w = h * 0.36
        d.ellipse([cx - w, cy - r * 0.72, cx + w, cy + r], fill=fill)
        d.ellipse([cx - w * 0.86, cy - r, cx + w * 0.86, cy + r * 0.3], fill=fill)
    elif kind == "note":
        head = h * 0.16
        d.ellipse([cx - h * 0.30, cy + r - head * 1.7, cx - h * 0.30 + head * 2.2, cy + r], fill=fill)
        stem = cx - h * 0.30 + head * 1.85
        d.rectangle([stem, cy - r * 0.96, stem + h * 0.055, cy + r * 0.84], fill=fill)
        d.polygon([(stem, cy - r * 0.96), (cx + h * 0.30, cy - r * 0.12),
                   (stem, cy - r * 0.60)], fill=fill)
    elif kind == "boat":
        d.polygon([(cx - r * 0.96, cy + r * 0.32), (cx + r * 0.96, cy + r * 0.32),
                   (cx + r * 0.60, cy + r * 0.80), (cx - r * 0.60, cy + r * 0.80)], fill=fill)
        d.rectangle([cx - h * 0.025, cy - r, cx + h * 0.025, cy + r * 0.32], fill=fill)
        d.polygon([(cx + h * 0.04, cy - r), (cx + h * 0.40, cy + r * 0.16),
                   (cx + h * 0.04, cy + r * 0.16)], fill=fill)


# ------------------------------------------------------------------- screens

def layer():
    return Image.new("RGBA", (W, H), (0, 0, 0, 0))


def dimmed_room(owl=True):
    """The room behind a running mode. `owl=False` for a screen that moves the owl."""
    canvas = compose("night", owl=owl)
    # Pillow's ImageDraw overwrites pixels on an RGBA image rather than blending them, so
    # anything translucent has to be its own layer and composited.
    sheet = Image.new("RGBA", (W, H), (8, 8, 8, 168))    # the mode's dimming layer
    canvas.alpha_composite(sheet)
    return canvas


def picker_screen(sets):
    canvas = dimmed_room()
    # The owl stays on its perch while the cards are up, lit above the dimming.
    paste(canvas, "owl_base.png",
          (L["owlHome"]["x"], L["owlHome"]["y"] + L["owlHeight"] / 2), L["owlHeight"])
    over = layer()
    d = ImageDraw.Draw(over, "RGBA")

    layout = rows(len(sets))
    total_h = len(layout) * CARD_H + max(len(layout) - 1, 0) * ROW_GAP
    # Mirrors SpokenSetMode.place(_:): the cards hang below the owl's feet.
    ceiling = sk(L["owlHome"]["y"] - 20)
    index = 0
    y = ceiling + CARD_H / 2

    for row in layout:
        width = row * CARD_W + (row - 1) * GAP
        x = W / 2 - width / 2 + CARD_W / 2
        for _ in range(row):
            s = sets[index]
            fill = hexcolour(s.get("colour", "C9A06A"))
            d.rounded_rectangle([x - CARD_W / 2, y - CARD_H / 2, x + CARD_W / 2, y + CARD_H / 2],
                                radius=22, fill=fill, outline=(255, 255, 255, 128), width=4)
            symbol(d, s.get("symbol", "star"), x, y, CARD_H * 0.52,
                   (255, 255, 255, 219), behind=fill)
            x += CARD_W + GAP
            index += 1
        y += CARD_H + ROW_GAP

    canvas.alpha_composite(over)
    note(canvas, "the cards, as a child sees them: no titles, no words")
    return canvas


def reciting_screen(line, lit_words):
    canvas = dimmed_room(owl=False)
    spot = approach_point("lamp")
    paste(canvas, "owl_base.png", (spot[0], spot[1] + L["owlHeight"] / 2), L["owlHeight"])
    over = layer()
    d = ImageDraw.Draw(over, "RGBA")

    # The listening ring, drawn where the mode attaches it to the owl.
    rr = L["owlHeight"] * 0.60
    ring_y = sk(spot[1] + L["owlHeight"] * 0.5)
    d.ellipse([spot[0] - rr, ring_y - rr, spot[0] + rr, ring_y + rr],
              outline=(255, 230, 176, 191), width=7)

    # The caption, whole-line lit: the child's turn.
    f = font(52)
    words = line.split()
    widths = [d.textlength(w + " ", font=f) for w in words]
    total = sum(widths)
    x = 860 - total / 2
    y = sk(660)
    for w, width in zip(words, widths):
        colour = (255, 230, 176, 255) if lit_words else (240, 240, 240, 184)
        d.text((x, y), w, font=f, fill=colour)
        x += width

    canvas.alpha_composite(over)
    note(canvas, "the owl has said the line; the whole caption lights up and the ring says it is the child's turn")
    return canvas


def note(canvas, text):
    over = layer()
    d = ImageDraw.Draw(over, "RGBA")
    d.rectangle([0, H - 44, W, H], fill=(0, 0, 0, 150))
    d.text((16, H - 36), text, font=font(24), fill=(200, 220, 255, 230))
    canvas.alpha_composite(over)


if __name__ == "__main__":
    sets = json.load(open(os.path.join(ROOT, "content", "en", "spoken-sets.json")))["sets"]
    os.makedirs(OUT_DIR, exist_ok=True)

    for name, canvas in [
        ("prayers-cards.png", picker_screen(sets)),
        ("prayers-listening.png",
         reciting_screen(sets[3]["lines"][0]["text"], lit_words=True)),
    ]:
        path = os.path.join(OUT_DIR, name)
        canvas.convert("RGB").save(path, quality=92)
        print("wrote", os.path.relpath(path, ROOT))
