#!/usr/bin/env python3
"""Render the attic room outside the app, from the app's own layout constants.

A review aid, not part of the app. It parses `RoomLayout.swift` and composites the
same sprites `RoomBuilder` does, in the same order, at the same coordinates — so a
preview can never quietly drift from the numbers SpriteKit actually uses.

It does not simulate animation, blend modes or the ambient wash, so treat it as
composition-accurate and finish-approximate.

    python3 tools/compose_room.py           # docs/preview/room.png
    python3 tools/compose_room.py --grid    # plus a measured grid and the tap targets

Needs Pillow:  pip install Pillow
"""

import argparse
import os
import re
import sys

try:
    from PIL import Image, ImageDraw
except ImportError:
    sys.exit("This needs Pillow:  pip install Pillow")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LAYOUT = os.path.join(ROOT, "LittleOwl", "Room", "RoomLayout.swift")
ART = os.path.join(ROOT, "LittleOwl", "Resources", "Art")
OUT_DIR = os.path.join(ROOT, "docs", "preview")


# ---------------------------------------------------------------- layout

def parse_layout():
    text = open(LAYOUT).read()
    L = {}
    for name, num in re.findall(r"static let (\w+)\s*:\s*CGFloat\s*=\s*(-?[\d.]+)", text):
        L[name] = float(num)
    for name, body in re.findall(r"static let (\w+)\s*=\s*CGPoint\(([^)]*)\)", text):
        L[name] = {k: float(v) for k, v in re.findall(r"(\w+):\s*(-?[\d.]+)", body)}
    for name, body in re.findall(r"static let (\w+)\s*=\s*CGSize\(([^)]*)\)", text):
        L[name] = {k: float(v) for k, v in re.findall(r"(\w+):\s*(-?[\d.]+)", body)}
    block = re.search(r"static let blockCentres:\s*\[CGPoint\]\s*=\s*\[(.*?)\]", text, re.S)
    L["blockCentres"] = [
        {"x": float(x), "y": float(y)}
        for x, y in re.findall(r"CGPoint\(x:\s*(-?[\d.]+),\s*y:\s*(-?[\d.]+)\)", block.group(1))
    ]
    return L


L = parse_layout()
W = int(L["designSize"]["width"])
H = int(L["designSize"]["height"])


def sk(y):
    """SpriteKit y (from the bottom) -> image y (from the top)."""
    return H - y


# ---------------------------------------------------------------- compositing

def paste(canvas, filename, centre, height=None):
    path = os.path.join(ART, filename)
    if not os.path.exists(path):
        print(f"  (missing {filename} \u2014 skipped)")
        return
    im = Image.open(path).convert("RGBA")
    if height:
        im = im.resize((max(1, round(im.width * height / im.height)), round(height)), Image.LANCZOS)
    canvas.alpha_composite(im, (round(centre[0] - im.width / 2), round(sk(centre[1]) - im.height / 2)))


def compose(time="night", owl=True):
    """`owl=False` leaves the owl out, for a preview that puts it somewhere else."""
    room = os.path.join(ART, "room_bg.jpg")
    canvas = Image.open(room).convert("RGBA").resize((W, H), Image.LANCZOS)

    glass_c = (L["windowCentre"]["x"], L["windowCentre"]["y"])
    glass_d = L["glassRadius"] * 2
    sky = f"window_sky_{time}.png"
    if not os.path.exists(os.path.join(ART, sky)):
        sky = "window_sky_night.png"
    paste(canvas, sky, glass_c, glass_d)
    paste(canvas, "window_woodwork.png", glass_c, glass_d)

    for letter, centre in zip("abc", L["blockCentres"]):
        paste(canvas, f"block_{letter}.png", (centre["x"], centre["y"]), L["blockHeight"])

    # The basket is the one prop that is not in room_bg.jpg, so it is the one the preview
    # would silently leave out. `paste` says so and carries on if its painting is absent,
    # which is the same thing the app does.
    paste(canvas, "corner_basket.png",
          (L["basketCentre"]["x"], L["basketCentre"]["y"]), L["basketSize"]["height"])

    if owl:
        owl_h = L["owlHeight"]
        paste(canvas, "owl_base.png", (L["owlHome"]["x"], L["owlHome"]["y"] + owl_h / 2), owl_h)
    return canvas


def draw_grid(canvas):
    d = ImageDraw.Draw(canvas, "RGBA")
    for x in range(0, W, 100):
        d.line([(x, 0), (x, H)], fill=(0, 255, 255, 90))
        d.text((x + 3, 3), str(x), fill=(0, 255, 255, 220))
    for y in range(0, H, 100):
        d.line([(0, y), (W, y)], fill=(255, 0, 255, 90))
        d.text((3, y + 3), str(H - y), fill=(255, 0, 255, 220))

    minimum = L["minimumTapTarget"]
    targets = [
        ("book", L["bookCentre"], L["bookSize"]),
        ("lamp", L["lampCentre"], L["lampSize"]),
        ("blocks", L["blocksTapCentre"], L["blocksTapSize"]),
        ("window", L["windowCentre"], L["windowTapSize"]),
        ("basket", L["basketCentre"], L["basketSize"]),
        ("owl", {"x": L["owlHome"]["x"], "y": L["owlHome"]["y"] + L["owlHeight"] / 2},
         {"width": 260, "height": L["owlHeight"] + 40}),
    ]
    for name, c, s in targets:
        w = max(s["width"], minimum)
        h = max(s["height"], minimum)
        x0, x1 = c["x"] - w / 2, c["x"] + w / 2
        y0, y1 = sk(c["y"]) - h / 2, sk(c["y"]) + h / 2
        d.rectangle([x0, y0, x1, y1], outline=(60, 255, 120, 255), width=3)
        d.text((x0 + 6, y0 + 6), f"{name} {int(w)}x{int(h)}", fill=(60, 255, 120, 255))
    return canvas


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--grid", action="store_true", help="overlay the measuring grid and tap targets")
    ap.add_argument("--time", default="night", help="morning | day | evening | night")
    args = ap.parse_args()

    os.makedirs(OUT_DIR, exist_ok=True)
    canvas = compose(args.time)
    name = f"room-{args.time}.png"
    if args.grid:
        canvas = draw_grid(canvas)
        name = f"room-{args.time}-grid.png"
    path = os.path.join(OUT_DIR, name)
    canvas.convert("RGB").save(path)
    print("wrote", os.path.relpath(path, ROOT))
