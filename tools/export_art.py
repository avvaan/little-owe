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
    m = re.search(rf"static let {name}\s*=\s*CGSize\(width:\s*(-?[\d.]+),\s*height:\s*(-?[\d.]+)\)", text)
    if m:
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


# ---------------------------------------------------------------- removable props
#
# Parent settings can take a prop out of the room. The blocks are their own sprites and
# simply hide; the book is painted into the wall, so hiding it needs a piece of wall to
# put in its place.
#
# The patch is cloned from elsewhere in the same painting rather than invented. The wall
# here is diagonal roof planking, so a fixed horizontal or vertical offset would break
# the grain - instead the offset is SEARCHED for: every candidate is scored on how well
# the ring of wall just outside the hole matches the same ring moved by that offset, and
# the best one wins. That finds an offset along the planks by itself, whatever angle they
# run at.
#
# The lamp and the window are deliberately not in here. Both are light sources and their
# glow is painted across the wall and the furniture around them, so cloning wall over the
# lamp would leave a pool of light with nothing making it. Removing those two needs a
# repaint, not a patch - see docs/ART_BRIEF.md.

# Book only, in source pixels: the covers and pages, stopping just above the shelf plank
# so the shelf itself survives.
BOOK_HOLE = (262, 262, 636, 467)

# How far past the hole the patch reaches, and the width of the fade at its edge.
PATCH_MARGIN = 26
PATCH_RING = 22


def _best_clone_offset(pixels, hole, ring=PATCH_RING):
    """The (dx, dy) whose wall best continues the wall around `hole`."""
    x0, y0, x1, y1 = hole
    height, width = pixels.shape[:2]

    outer = (max(x0 - ring, 0), max(y0 - ring, 0),
             min(x1 + ring, width), min(y1 + ring, height))
    ring_mask = np.zeros((height, width), bool)
    ring_mask[outer[1]:outer[3], outer[0]:outer[2]] = True
    ring_mask[y0:y1, x0:x1] = False

    ys, xs = np.nonzero(ring_mask)
    wanted = pixels[ys, xs].astype(np.float32)

    best, best_offset = None, (0, 0)
    span_x, span_y = x1 - x0, y1 - y0
    for dy in range(-3 * span_y, 3 * span_y + 1, 8):
        for dx in range(-3 * span_x, 3 * span_x + 1, 8):
            if abs(dx) < span_x * 0.6 and abs(dy) < span_y * 0.6:
                continue                      # the source would sit on the book itself
            sx, sy = xs + dx, ys + dy
            if sx.min() < 0 or sy.min() < 0 or sx.max() >= width or sy.max() >= height:
                continue
            if (x0 + dx) < 0 or (y0 + dy) < 0 or (x1 + dx) > width or (y1 + dy) > height:
                continue
            # Reject a source that overlaps the hole, which would clone the book back in.
            if not (x1 + dx <= x0 or x0 + dx >= x1 or y1 + dy <= y0 or y0 + dy >= y1):
                continue
            score = float(np.mean((pixels[sy, sx].astype(np.float32) - wanted) ** 2))
            if best is None or score < best:
                best, best_offset = score, (dx, dy)
    return best_offset, best


def _feathered_alpha(size, margin=PATCH_MARGIN):
    """Opaque in the middle, fading to nothing over `margin` at the edge."""
    width, height = size
    ramp_x = np.minimum(np.arange(width), np.arange(width)[::-1]) / max(margin, 1)
    ramp_y = np.minimum(np.arange(height), np.arange(height)[::-1]) / max(margin, 1)
    alpha = np.minimum(np.clip(ramp_x, 0, 1)[None, :], np.clip(ramp_y, 0, 1)[:, None])
    # Smoothstep, so the edge has no visible line where the ramp starts.
    alpha = alpha * alpha * (3 - 2 * alpha)
    return (alpha * 255).astype(np.uint8)


def export_patches(room):
    pixels = np.asarray(room.convert("RGB"))
    x0, y0, x1, y1 = BOOK_HOLE
    padded = (x0 - PATCH_MARGIN, y0 - PATCH_MARGIN, x1 + PATCH_MARGIN, y1 + PATCH_MARGIN)

    offset, score = _best_clone_offset(pixels, padded)
    dx, dy = offset
    source = room.crop((padded[0] + dx, padded[1] + dy,
                        padded[2] + dx, padded[3] + dy)).convert("RGBA")

    patch = source.copy()
    patch.putalpha(Image.fromarray(_feathered_alpha(patch.size)))

    name = "patch_book.png"
    patch.save(os.path.join(OUT, name))
    print(f"  {name:<24} {patch.width}x{patch.height}  cloned from ({dx:+d}, {dy:+d})  "
          f"seam {score:.0f}")

    # Where it goes, in design points, measured off the same painting. RoomLayout has to
    # agree: the sprite and its place come from here, and a patch that has moved without
    # the layout moving with it is a piece of wall sitting next to the book.
    scale = room.width / DESIGN_W
    centre = (round((padded[0] + padded[2]) / 2 / scale),
              round((room.height - (padded[1] + padded[3]) / 2) / scale))
    size = (round((padded[2] - padded[0]) / scale), round((padded[3] - padded[1]) / scale))
    print(f"  {'':24} sits at {centre} design points, {size[0]}x{size[1]}")

    declared_centre = layout_value("bookPatchCentre")
    declared_size = layout_value("bookPatchSize")
    drift = (abs(declared_centre[0] - centre[0]), abs(declared_centre[1] - centre[1]),
             abs(declared_size[0] - size[0]), abs(declared_size[1] - size[1]))
    if max(drift) > 1:
        raise ValueError(
            f"RoomLayout.bookPatchCentre/Size say {declared_centre} {declared_size}, "
            f"but the patch cut from the painting is {centre} {size}. "
            "Update RoomLayout to match."
        )


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
    export_patches(room)
    export_dog()
    export_corner()


# ----------------------------------------------------------------- the puppy

# The second character. Generated as a whole animal on a flat card of one colour,
# rather than as a layer with alpha, because that is what an image generator gives you.
DOG_CARD = os.path.join(SRC, "dog-raw", "dog_base_card.png")

# How far a pixel must be from the card colour before it is the animal at all, and how
# far before it is the animal completely. The gap between them is the soft edge: fur is
# mostly soft edge, and a single threshold turns it into a cut-out with scissors.
DOG_KEY_LO, DOG_KEY_HI = 26, 78


def _key_flat_card(rgb):
    """Alpha and un-fringed colour for a subject painted on a card of one flat colour.

    Two things happen here and only the first is obvious. The easy half is the alpha
    ramp. The half that decides whether this looks painted or cut out is recovering the
    colour underneath: a half-transparent pixel of fur on a blue card *is* half blue,
    and leaving it that way rims the whole animal in blue against the warm room. So the
    card is subtracted back out of every partial pixel.
    """
    a = np.asarray(rgb).astype(np.float64)
    # The card is uniform, so any corner is the card. Take the median of all four to be
    # safe against a stray speck.
    corners = np.array([a[4, 4], a[4, -5], a[-5, 4], a[-5, -5]])
    card = np.median(corners, axis=0)

    dist = np.abs(a - card).sum(axis=2)
    alpha = np.clip((dist - DOG_KEY_LO) / (DOG_KEY_HI - DOG_KEY_LO), 0.0, 1.0)

    # c = alpha*F + (1-alpha)*card  ->  F = (c - (1-alpha)*card) / alpha
    safe = np.maximum(alpha, 1e-3)[..., None]
    front = (a - (1.0 - alpha)[..., None] * card) / safe
    front = np.clip(front, 0, 255)

    out = np.dstack([front, alpha * 255.0]).astype("uint8")
    return Image.fromarray(out, "RGBA")


def export_dog():
    """The puppy, cut off its card and scaled into the owl's place.

    Its silhouette is 0.55 wide to tall against the owl's 0.58, so at the same height it
    is eleven points narrower and drops into the same spot with nothing in `RoomLayout`
    changed. That is luck rather than design, and worth checking again if the painting
    is ever redone.
    """
    if not os.path.exists(DOG_CARD):
        print("  (no dog card yet; skipping the puppy)")
        return

    keyed = _key_flat_card(Image.open(DOG_CARD).convert("RGB"))

    a = np.array(keyed)
    ys, xs = np.where(a[..., 3] > 6)
    keyed = keyed.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))

    target = round(layout_value("owlHeight") * 2)     # 2x the size it is ever drawn at
    if keyed.height > target:
        keyed = keyed.resize((round(keyed.width * target / keyed.height), target),
                             Image.LANCZOS)

    path = os.path.join(OUT, "dog_base.png")
    keyed.save(path, optimize=True)
    print(f"  {'dog_base.png':<24} {keyed.size[0]}x{keyed.size[1]}  "
          f"{os.path.getsize(path)//1024}KB")


# ------------------------------------------------------------- the corner

# The basket the owl goes to when it wants to ask rather than answer. Like the puppy it
# comes back as a subject on a flat card, because that is what an image generator gives
# you, and it is keyed with the same code.
#
# Unlike everything else in Resources/Art it is not in the room painting and never was:
# the near right-hand corner is bare floorboards, which is exactly why there was room
# for a fifth prop there.
BASKET_CARD = os.path.join(SRC, "corner-raw", "basket_c_card.png")

# Everything else in the room has its shadow painted into the picture. This one has to
# bring its own or it floats a little way above the floor, which a three-year-old will
# not name but will see. Fractions of the basket's own size.
SHADOW_SPREAD = 0.94
SHADOW_HEIGHT = 0.17
SHADOW_BLUR = 0.045
SHADOW_ALPHA = 0.30

# The basket is painted in daylight on a blue card and stands in the far corner from the
# lamp, so it arrives brighter and cooler than the floor it is standing on. A flat warm
# multiply is not lighting, but it is enough to stop it reading as a sticker.
CORNER_LIGHT = (0.93, 0.89, 0.84)


def export_corner():
    """The basket, keyed off its card and given a shadow to stand on."""
    if not os.path.exists(BASKET_CARD):
        print("  (no basket card yet; skipping the corner)")
        return

    keyed = _key_flat_card(Image.open(BASKET_CARD).convert("RGB"))

    a = np.array(keyed)
    ys, xs = np.where(a[..., 3] > 6)
    keyed = keyed.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))

    # Twice the size it is ever drawn at, the same rule the puppy follows.
    target = round(layout_value("basketSize")[1] * 2)
    # The skirt is the half-height of the shadow ellipse. It is left below the basket
    # *and* below the ellipse: the first is where the shade falls, and the second is room
    # for the blur to fade out in. Without the second the shadow ends in a straight line
    # across the bottom of the sprite.
    skirt = round(target * SHADOW_HEIGHT / 2)
    body = target - 2 * skirt
    width = round(keyed.width * body / keyed.height)
    keyed = keyed.resize((width, body), Image.LANCZOS)

    lit = np.array(keyed).astype(np.float64)
    lit[..., :3] *= np.array(CORNER_LIGHT)
    keyed = Image.fromarray(np.clip(lit, 0, 255).astype("uint8"), "RGBA")

    canvas = Image.new("RGBA", (width, target), (0, 0, 0, 0))

    # An ellipse under the foot of the basket, drawn large and blurred down: a hard edge
    # here reads as a second object rather than as shade.
    shadow = Image.new("L", (width, target), 0)
    draw = ImageDraw.Draw(shadow)
    half = width * SHADOW_SPREAD / 2
    draw.ellipse([width / 2 - half, body - skirt,
                  width / 2 + half, body + skirt],
                 fill=round(255 * SHADOW_ALPHA))
    shadow = shadow.filter(ImageFilter.GaussianBlur(target * SHADOW_BLUR))
    canvas.paste(Image.new("RGBA", canvas.size, (58, 40, 26, 255)), (0, 0), shadow)

    canvas.alpha_composite(keyed, (0, 0))

    path = os.path.join(OUT, "corner_basket.png")
    canvas.save(path, optimize=True)
    print(f"  {'corner_basket.png':<24} {canvas.size[0]}x{canvas.size[1]}  "
          f"{os.path.getsize(path)//1024}KB   "
          f"aspect {canvas.size[0] / canvas.size[1]:.3f}")


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
