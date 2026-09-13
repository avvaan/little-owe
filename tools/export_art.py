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
    shows a ghost of the old cross;
  * derives the owl's expression frames from `art-source/frames-raw/`. Those were
    generated against the base owl and land within a pixel of it, but their bodies
    still differ from the painting by a percent or two of texture. For the frames that
    alternate quickly - blink, the two beak positions, happy - only the face is taken
    and the body stays the original painting, so there is nothing to shimmer. For the
    sustained ones - listening, sleepy - the whole frame is used, because their ear
    tufts move outside the base silhouette and a slow change hides the rest.

    python3 tools/export_art.py            # write the sprites
    python3 tools/export_art.py --check    # verify the committed sprites match

`--check` exports to a temporary directory and compares pixels, not bytes: different
Pillow versions encode the same image to different bytes, so a byte comparison would
fail on a library upgrade rather than on a real change. Sizes must match exactly and
the mean absolute pixel difference must stay under one level, which catches a moved
sprite or a wrong scale while tolerating encoder jitter.

Writes to LittleOwl/Resources/Art/. Needs Pillow and numpy.
"""

import argparse
import os
import re
import shutil
import sys
import tempfile

try:
    from PIL import Image, ImageDraw, ImageFilter
    import numpy as np
except ImportError:
    sys.exit("This needs Pillow and numpy:  pip install Pillow numpy")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "art-source")
SHIPPED = os.path.join(ROOT, "LittleOwl", "Resources", "Art")
LAYOUT = os.path.join(ROOT, "LittleOwl", "Room", "RoomLayout.swift")

# Where this run writes. `--check` redirects it to a temporary directory.
OUT = SHIPPED


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


# ---------------------------------------------------------------- owl frames

# The owl occupied exactly this box on the 1024 card the frames were generated
# against, so cropping it and scaling to the master size is an exact inverse.
FRAME_BOX = (251, 61, 773, 962)

# Face patch in master-owl coordinates: both eyes, the beak and the facial disc,
# measured off art-source/layer_owl.png.
FACE_PATCH = (150, 360, 970, 860)

# name -> how much of the generated frame to take
OWL_FRAMES = {
    "blink": "face",
    "happy": "face",
    "talk_half": "face",
    "talk_wide": "face",
    "listen": "full",
    "sleepy": "full",
}


def _warp_frame(path, size):
    """Generated 1024 card -> master owl space."""
    return Image.open(path).convert("RGB").crop(FRAME_BOX).resize(size, Image.LANCZOS)


def _key_card(rgb):
    """Alpha for an owl sitting on the flat cream card the frames were generated on."""
    a = np.asarray(rgb).astype(int)
    light = a.mean(axis=2) > 205
    sat = a.max(axis=2) - a.min(axis=2)
    card = light & (sat < 30)

    # Only card pixels reachable from the border are background; anything enclosed by
    # the bird (a pale cheek, a highlight) stays opaque.
    h, w = card.shape
    outside = np.zeros_like(card)
    stack = [(0, x) for x in range(w)] + [(h - 1, x) for x in range(w)]
    stack += [(y, 0) for y in range(h)] + [(y, w - 1) for y in range(h)]
    stack = [p for p in stack if card[p]]
    for p in stack:
        outside[p] = True
    while stack:
        y, x = stack.pop()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and card[ny, nx] and not outside[ny, nx]:
                outside[ny, nx] = True
                stack.append((ny, nx))

    alpha = Image.fromarray(np.where(outside, 0, 255).astype("uint8"))
    return alpha.filter(ImageFilter.GaussianBlur(1.2))


def export_owl_frames():
    raw_dir = os.path.join(SRC, "frames-raw")
    base = Image.open(os.path.join(SRC, "layer_owl.png")).convert("RGBA")
    size = base.size
    base_px = np.asarray(base).astype(float)

    patch_mask = Image.new("L", size, 0)
    ImageDraw.Draw(patch_mask).rectangle(FACE_PATCH, fill=255)
    patch_mask = np.asarray(patch_mask.filter(ImageFilter.GaussianBlur(40))).astype(float)[..., None] / 255.0

    drawn = layout_value("owlHeight")
    for name, mode in OWL_FRAMES.items():
        raw = os.path.join(raw_dir, f"owl_{name}.png")
        if not os.path.exists(raw):
            print(f"  owl_{name}.png            (no source frame - skipped)")
            continue

        warped = _warp_frame(raw, size)

        if mode == "face":
            out = base_px.copy()
            out[..., :3] = base_px[..., :3] * (1 - patch_mask) + np.asarray(warped).astype(float) * patch_mask
            frame = Image.fromarray(np.clip(out, 0, 255).astype("uint8"))
        else:
            frame = warped.convert("RGBA")
            frame.putalpha(_key_card(warped))

        target = round(drawn * 2)
        frame = frame.resize((round(frame.width * target / frame.height), target), Image.LANCZOS)
        path = os.path.join(OUT, f"owl_{name}.png")
        frame.save(path, optimize=True)
        print(f"  {'owl_' + name + '.png':<24} {frame.size[0]}x{frame.size[1]}  "
              f"{os.path.getsize(path)//1024}KB  ({mode})")


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


# Where the glass sits inside each generated 1024 window frame. Measured from the
# frames themselves; morning and day agree to within a few pixels and evening's warm
# horizon defeats colour detection, so one consensus circle is used for all three.
GEN_GLASS = (536, 526, 440)

# Half-width of the muntin cross to paint out of a generated sky, as a fraction of the
# glass diameter. The generated bars measure 5.6% and the painted ones that go back on
# top are 5.9%, so a slightly generous mask still ends up completely hidden.
GEN_CROSS_HALF = 0.032


def _paint_out(sky, hole):
    """Grow the surrounding sky inwards over `hole`, so nothing of what was there shows."""
    sky = sky.astype(float).copy()
    hole = hole.copy()
    for _ in range(160):
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
    return sky


def _disc(size):
    yy, xx = np.mgrid[0:size, 0:size]
    r = size / 2
    return (xx - r) ** 2 + (yy - r) ** 2 <= (r - 1) ** 2


def _save_sky(name, crop, hole):
    size = crop.shape[0]
    disc = _disc(size)
    sky = _paint_out(crop[..., :3], hole & disc)
    out = np.zeros((size, size, 4), "uint8")
    out[..., :3] = np.clip(sky, 0, 255).astype("uint8")
    out[..., 3] = np.where(disc, 255, 0)
    path = os.path.join(OUT, f"window_sky_{name}.png")
    Image.fromarray(out).save(path, optimize=True)
    print(f"  {'window_sky_' + name + '.png':<24} {size}x{size}  {os.path.getsize(path)//1024}KB")
    return size


def export_window(room):
    """The night sky and the woodwork, both cut from the room painting itself."""
    centre = layout_value("windowCentre")
    radius = layout_value("glassRadius")
    scale = room.width / DESIGN_W
    cx, cy = round(centre[0] * scale), round((DESIGN_H - centre[1]) * scale)
    r = round(radius * scale)

    crop = np.array(room.crop((cx - r, cy - r, cx + r, cy + r))).astype(int)
    R, B = crop[..., 0], crop[..., 2]

    # In the painting the muntins are the only strongly brown thing inside the glass,
    # so colour finds them exactly. The opening clears the speckle the pink clouds
    # otherwise contribute.
    wood = _open((R - B > 55) & (B < 150))

    size = 2 * r
    disc = _disc(size)
    woodwork = np.zeros((size, size, 4), "uint8")
    woodwork[..., :3] = crop[..., :3]
    woodwork[..., 3] = np.where(wood & disc, 255, 0)
    path = os.path.join(OUT, "window_woodwork.png")
    Image.fromarray(woodwork).save(path, optimize=True)
    print(f"  {'window_woodwork.png':<24} {size}x{size}  {os.path.getsize(path)//1024}KB")

    _save_sky("night", crop, wood)
    return size


def export_generated_skies(shipped_size):
    """Morning, day and evening, cut from the generated window frames."""
    raw_dir = os.path.join(SRC, "frames-raw")
    gcx, gcy, gr = GEN_GLASS

    for name in ("morning", "day", "evening"):
        raw = os.path.join(raw_dir, f"window_{name}.png")
        if not os.path.exists(raw):
            print(f"  window_sky_{name}.png      (no source frame - skipped)")
            continue

        im = Image.open(raw).convert("RGB").crop((gcx - gr, gcy - gr, gcx + gr, gcy + gr))
        im = im.resize((shipped_size, shipped_size), Image.LANCZOS)
        crop = np.array(im).astype(int)

        # Geometry, not colour: a sunset horizon reads as brown to any wood detector,
        # and eating the clouds would be worse than painting out a slightly wide cross.
        half = round(shipped_size * GEN_CROSS_HALF)
        mid = shipped_size // 2
        cross = np.zeros((shipped_size, shipped_size), bool)
        cross[:, mid - half:mid + half] = True
        cross[mid - half:mid + half, :] = True

        _save_sky(name, crop, cross)


def export_all():
    os.makedirs(OUT, exist_ok=True)
    room = Image.open(os.path.join(SRC, "owl_bg_empty.png")).convert("RGB")
    room.save(os.path.join(OUT, "room_bg.jpg"), quality=92, optimize=True, progressive=True)
    print(f"  {'room_bg.jpg':<24} {room.width}x{room.height}  "
          f"{os.path.getsize(os.path.join(OUT,'room_bg.jpg'))//1024}KB")

    export_cutout("layer_owl.png", "owl_base.png", layout_value("owlHeight"))
    for letter in "abc":
        export_cutout(f"layer_block_{letter.upper()}.png", f"block_{letter}.png",
                      layout_value("blockHeight"))
    shipped = export_window(room)
    export_generated_skies(shipped)
    export_owl_frames()


def compare(fresh_dir):
    """Pixel comparison against the committed sprites. Returns a list of complaints."""
    problems = []
    fresh = sorted(os.listdir(fresh_dir))
    shipped = sorted(f for f in os.listdir(SHIPPED) if not f.startswith("."))

    for name in set(fresh) | set(shipped):
        if name not in shipped:
            problems.append(f"{name}: produced by the export but not committed")
            continue
        if name not in fresh:
            problems.append(f"{name}: committed but the export does not produce it")
            continue

        a = Image.open(os.path.join(fresh_dir, name))
        b = Image.open(os.path.join(SHIPPED, name))
        if a.size != b.size:
            problems.append(f"{name}: size {b.size} committed, {a.size} from source")
            continue
        if a.mode != b.mode:
            problems.append(f"{name}: mode {b.mode} committed, {a.mode} from source")
            continue

        delta = np.abs(np.asarray(a, float) - np.asarray(b, float)).mean()
        if delta >= 1.0:
            problems.append(f"{name}: mean pixel difference {delta:.2f}")
    return problems


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true",
                    help="verify the committed sprites instead of overwriting them")
    args = ap.parse_args()

    if args.check:
        tmp = tempfile.mkdtemp(prefix="littleowl-art-")
        try:
            OUT = tmp
            export_all()
            problems = compare(tmp)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)

        if problems:
            print("LittleOwl/Resources/Art is out of step with art-source/:")
            for p in problems:
                print(f"  {p}")
            print("\nRun: python3 tools/export_art.py   and commit the result.")
            sys.exit(1)
        print("Art is in step with its source.")
        sys.exit(0)

    print("exporting to LittleOwl/Resources/Art/")
    export_all()
