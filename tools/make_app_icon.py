#!/usr/bin/env python3
"""Build the App Store icon from the owl artwork.

Kids-category apps are browsed by parents on small tiles, so the icon is the owl's
face rather than the whole room: at 60 pt a wide shot reads as brown mush.

Apple requires 1024 x 1024, sRGB, **no alpha channel and no rounded corners** — the
system rounds it. This writes exactly that.

    python3 tools/make_app_icon.py

Output: LittleOwl/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png
"""

import os
import sys

try:
    from PIL import Image, ImageDraw
    import numpy as np
except ImportError:
    sys.exit("This needs Pillow and numpy:  pip install Pillow numpy")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "art-source", "layer_owl.png")
OUT = os.path.join(ROOT, "LittleOwl", "Resources", "Assets.xcassets",
                   "AppIcon.appiconset", "icon-1024.png")

SIDE = 1024
# Warm attic tones, sampled from the room painting.
BACKDROP_TOP = (214, 168, 112)
BACKDROP_BOTTOM = (150, 106, 66)


def owl_head():
    """The head and ear tufts, trimmed to their own content."""
    owl = Image.open(SRC).convert("RGBA")
    a = np.array(owl)
    alpha = a[..., 3]

    # The head is the upper part of the bird; cut at the shoulders.
    cut = int(owl.height * 0.46)
    head = owl.crop((0, 0, owl.width, cut))

    a = np.array(head)
    ys, xs = np.where(a[..., 3] > 8)
    return head.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))


def backdrop():
    """Vertical warm gradient with a soft glow behind the owl."""
    grad = Image.new("RGB", (1, SIDE))
    for y in range(SIDE):
        t = y / (SIDE - 1)
        grad.putpixel((0, y), tuple(
            round(BACKDROP_TOP[c] + (BACKDROP_BOTTOM[c] - BACKDROP_TOP[c]) * t) for c in range(3)
        ))
    canvas = grad.resize((SIDE, SIDE))

    glow = Image.new("L", (SIDE, SIDE), 0)
    d = ImageDraw.Draw(glow)
    for i in range(70, 0, -1):
        r = SIDE * 0.30 * i / 70
        d.ellipse([SIDE / 2 - r, SIDE * 0.46 - r, SIDE / 2 + r, SIDE * 0.46 + r],
                  fill=int(70 * (1 - i / 70)))
    canvas.paste(Image.new("RGB", (SIDE, SIDE), (255, 236, 196)), (0, 0), glow)
    return canvas


if __name__ == "__main__":
    head = owl_head()

    # Fill most of the tile — a small subject on a big field looks like a mistake —
    # but leave a margin below the chin so the head does not end at a flat cut.
    target_h = round(SIDE * 0.74)
    head = head.resize((round(head.width * target_h / head.height), target_h), Image.LANCZOS)

    canvas = backdrop()
    canvas.paste(head, ((SIDE - head.width) // 2, round(SIDE * 0.13)), head)

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    # RGB, not RGBA: an alpha channel is rejected at upload.
    canvas.convert("RGB").save(OUT)
    print(f"wrote {os.path.relpath(OUT, ROOT)}  {canvas.size[0]}x{canvas.size[1]} RGB")
