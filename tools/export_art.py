#!/usr/bin/env python3
"""Turn the master art in `art-source/` into the sprites the app ships.

The painter delivers a full-resolution room and a set of cut-out layers. The app needs
something smaller and differently sliced, so this does the slicing — reproducibly,
rather than by hand in an image editor that nobody can re-run.

What it does:

  * trims each cut-out to its content and normalises the alpha (the source layers top
    out at 254, which leaves the body very slightly see-through);
  * downscales every sprite to twice the size it is actually drawn at and no more;
  * splits the window glass into a sky and the wooden muntins that cross it, so the
    sky can follow the device clock behind unchanged woodwork. The muntins are painted
    out of the sky by flood-filling from the surrounding sky, so a swapped sky never
    shows a ghost of the old cross.

    python3 tools/export_art.py

Writes to LittleOwl/Resources/Art/. Needs Pillow and numpy.
"""

import os
import re
import sys

try:
    from PIL import Image
    import numpy as np
except ImportError:
    sys.exit("This needs Pillow and numpy:  pip install Pillow numpy")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "art-source")
OUT = os.path.join(ROOT, "LittleOwl", "Resources", "Art")
LAYOUT = os.path.join(ROOT, "LittleOwl", "Room", "RoomLayout.swift")


def layout_value(name):
    """Read a CGFloat or a CGPoint field out of RoomLayout so the two cannot drift."""
    text = open(LAYOUT).read()
    m = re.search(rf"static let {name}\s*:\s*CGFloat\s*=\s*(-?[\d.]+)", text)
    if m:
        return float(m.group(1))
    m = re.search(rf"static let {name}\s*=\s*CGPoint\(x:\s*(-?[\d.]+),\s*y:\s*(-?[\d.]+)\)", text)
    if m:
        return (float(m.group(1)), float(m.group(2)))
    m = re.search(r"static let designSize\s*=\s*CGSize\(width:\s*(-?[\d.]+),\s*height:\s*(-?[\d.]+)\)", text)
    if name == "designSize" and m:
        return (float(m.group(1)), float(m.group(2)))
    raise KeyError(name)


DESIGN_W, DESIGN_H = layout_value("designSize")


# ---------------------------------------------------------------- cut-outs

def export_cutout(src_name, out_name, drawn_height):
    im = Image.open(os.path.join(SRC, src_name)).convert("RGBA")
    a = np.array(im)
    ys, xs = np.where(a[..., 3] > 6)
    im = im.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))

    a = np.array(im).astype(np.int32)
    a[..., 3] = np.clip((a[..., 3] - 6) * 255 // 242, 0, 255)
    im = Image.fromarray(a.astype("uint8"))

    target = round(drawn_height * 2)          # 2x the size it is ever drawn at
    if im.height > target:
        im = im.resize((round(im.width * target / im.height), target), Image.LANCZOS)

    path = os.path.join(OUT, out_name)
    im.save(path, optimize=True)
    print(f"  {out_name:<24} {im.size[0]}x{im.size[1]}  {os.path.getsize(path)//1024}KB")


# ---------------------------------------------------------------- window

def _shift(m, dy, dx):
    out = np.zeros_like(m)
    ys = slice(max(dy, 0), m.shape[0] + min(dy, 0))
    yd = slice(max(-dy, 0), m.shape[0] + min(-dy, 0))
    xs = slice(max(dx, 0), m.shape[1] + min(dx, 0))
    xd = slice(max(-dx, 0), m.shape[1] + min(-dx, 0))
    out[yd, xd] = m[ys, xs]
    return out


def _open(mask, k=2):
    eroded = mask.copy()
    for dy in range(-k, k + 1):
        for dx in range(-k, k + 1):
            eroded &= _shift(mask, dy, dx)
    grown = eroded.copy()
    for dy in range(-k, k + 1):
        for dx in range(-k, k + 1):
            grown |= _shift(eroded, dy, dx)
    return grown


def export_window(room):
    centre = layout_value("windowCentre")
    radius = layout_value("glassRadius")
    scale = room.width / DESIGN_W
    cx, cy = round(centre[0] * scale), round((DESIGN_H - centre[1]) * scale)
    r = round(radius * scale)

    crop = np.array(room.crop((cx - r, cy - r, cx + r, cy + r))).astype(int)
    R, B = crop[..., 0], crop[..., 2]

    # The muntins are the only strongly brown thing inside the glass; the opening
    # clears the speckle the pink clouds otherwise contribute.
    wood = _open((R - B > 55) & (B < 150))

    size = 2 * r
    yy, xx = np.mgrid[0:size, 0:size]
    disc = (xx - r) ** 2 + (yy - r) ** 2 <= (r - 1) ** 2

    woodwork = np.zeros((size, size, 4), "uint8")
    woodwork[..., :3] = crop[..., :3]
    woodwork[..., 3] = np.where(wood & disc, 255, 0)
    Image.fromarray(woodwork).save(os.path.join(OUT, "window_woodwork.png"), optimize=True)

    # Paint the muntins out of the sky by growing the surrounding sky inwards.
    sky = crop[..., :3].astype(float)
    hole = wood & disc
    for _ in range(90):
        if not hole.any():
            break
        filled = ~hole
        acc = np.zeros_like(sky)
        cnt = np.zeros(sky.shape[:2])
        for dy, dx in [(-1, 0), (1, 0), (0, -1), (0, 1)]:
            cnt += _shift(filled.astype(np.uint8), dy, dx).astype(bool)
            for c in range(3):
                acc[..., c] += _shift(np.where(filled, sky[..., c], 0), dy, dx)
        edge = hole & (cnt > 0)
        for c in range(3):
            sky[..., c] = np.where(edge, acc[..., c] / np.maximum(cnt, 1), sky[..., c])
        hole &= ~edge

    night = np.zeros((size, size, 4), "uint8")
    night[..., :3] = np.clip(sky, 0, 255).astype("uint8")
    night[..., 3] = np.where(disc, 255, 0)
    Image.fromarray(night).save(os.path.join(OUT, "window_sky_night.png"), optimize=True)

    for f in ("window_woodwork.png", "window_sky_night.png"):
        print(f"  {f:<24} {size}x{size}  {os.path.getsize(os.path.join(OUT, f))//1024}KB")


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    print("exporting to LittleOwl/Resources/Art/")

    room = Image.open(os.path.join(SRC, "owl_bg_empty.png")).convert("RGB")
    room.save(os.path.join(OUT, "room_bg.jpg"), quality=92, optimize=True, progressive=True)
    print(f"  {'room_bg.jpg':<24} {room.width}x{room.height}  "
          f"{os.path.getsize(os.path.join(OUT,'room_bg.jpg'))//1024}KB")

    export_cutout("layer_owl.png", "owl_base.png", layout_value("owlHeight"))
    for letter in "abc":
        export_cutout(f"layer_block_{letter.upper()}.png", f"block_{letter}.png",
                      layout_value("blockHeight"))
    export_window(room)
