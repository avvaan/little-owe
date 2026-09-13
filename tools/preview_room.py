#!/usr/bin/env python3
"""Render a static preview of the attic room, straight from the layout constants.

This is a review aid, not part of the app. It parses `RoomLayout.swift` and
`Palette.swift` so a preview can never quietly drift from the numbers SpriteKit
actually uses, then draws an approximation of what `RoomBuilder` and
`PlaceholderOwlRig` build at runtime.

It does not simulate animation, lighting blend modes or SpriteKit's exact ellipse
rasterisation, so treat it as composition-accurate and finish-approximate.

    python3 tools/preview_room.py

Output: docs/preview/room-<time>.svg
"""

import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LAYOUT = os.path.join(ROOT, "LittleOwl", "Room", "RoomLayout.swift")
PALETTE = os.path.join(ROOT, "LittleOwl", "Support", "Palette.swift")
OUT_DIR = os.path.join(ROOT, "docs", "preview")


# ---------------------------------------------------------------- parsing

def parse_layout():
    text = open(LAYOUT).read()
    values = {}
    for name, number in re.findall(r"static let (\w+)\s*:\s*CGFloat\s*=\s*(-?[\d.]+)", text):
        values[name] = float(number)
    for name, body in re.findall(r"static let (\w+)\s*=\s*CGRect\(([^)]*)\)", text):
        values[name] = {k: float(v) for k, v in re.findall(r"(\w+):\s*(-?[\d.]+)", body)}
    for name, body in re.findall(r"static let (\w+)\s*=\s*CGPoint\(([^)]*)\)", text):
        values[name] = {k: float(v) for k, v in re.findall(r"(\w+):\s*(-?[\d.]+)", body)}
    for name, body in re.findall(r"static let (\w+)\s*=\s*CGSize\(([^)]*)\)", text):
        values[name] = {k: float(v) for k, v in re.findall(r"(\w+):\s*(-?[\d.]+)", body)}
    return values


def parse_palette():
    text = open(PALETTE).read()
    colors = {}
    for name, hexcode in re.findall(r"static let (\w+)\s*=\s*SKColor\(hex:\s*0x([0-9A-Fa-f]{6})\)", text):
        colors[name] = "#" + hexcode.upper()
    for name, body in re.findall(r"static let (\w+)(?:\s*:\s*\[SKColor\])?\s*=\s*\[([^\]]*)\]", text):
        entries = re.findall(r"SKColor\(hex:\s*0x([0-9A-Fa-f]{6})\)", body)
        if entries:
            colors[name] = ["#" + e.upper() for e in entries]
    colors["cloud"] = "#FFFFFF"
    colors["star"] = "#FFFBE8"
    return colors


L = parse_layout()
C = parse_palette()

W = L["designSize"]["width"]
H = L["designSize"]["height"]


# ---------------------------------------------------------------- helpers

def esc(parts):
    return "\n".join(parts)


def ellipse(cx, cy, w, h, fill, stroke=None, sw=0, opacity=1):
    s = '<ellipse cx="%g" cy="%g" rx="%g" ry="%g" fill="%s" opacity="%g"' % (
        cx, cy, w / 2.0, h / 2.0, fill, opacity)
    if stroke:
        s += ' stroke="%s" stroke-width="%g"' % (stroke, sw)
    return s + "/>"


def rect(x, y, w, h, fill, stroke=None, sw=0, rx=0, opacity=1):
    s = '<rect x="%g" y="%g" width="%g" height="%g" rx="%g" fill="%s" opacity="%g"' % (
        x, y, w, h, rx, fill, opacity)
    if stroke:
        s += ' stroke="%s" stroke-width="%g"' % (stroke, sw)
    return s + "/>"


def poly(points, fill, stroke=None, sw=0, opacity=1):
    pts = " ".join("%g,%g" % p for p in points)
    s = '<polygon points="%s" fill="%s" opacity="%g"' % (pts, fill, opacity)
    if stroke:
        s += ' stroke="%s" stroke-width="%g"' % (stroke, sw)
    return s + "/>"


def circle(cx, cy, r, fill, stroke=None, sw=0, opacity=1):
    s = '<circle cx="%g" cy="%g" r="%g" fill="%s" opacity="%g"' % (cx, cy, r, fill, opacity)
    if stroke:
        s += ' stroke="%s" stroke-width="%g"' % (stroke, sw)
    return s + "/>"


def group(body, transform=None, opacity=1):
    attrs = ""
    if transform:
        attrs += ' transform="%s"' % transform
    if opacity != 1:
        attrs += ' opacity="%g"' % opacity
    return "<g%s>\n%s\n</g>" % (attrs, esc(body))


def upright_text(x, y, label, size, fill):
    """Counters the global y-flip so glyphs are not mirrored."""
    return ('<g transform="translate(%g,%g) scale(1,-1)">'
            '<text x="0" y="0" font-family="Avenir Next, Helvetica, sans-serif" '
            'font-weight="800" font-size="%g" fill="%s" text-anchor="middle" '
            'dominant-baseline="central">%s</text></g>') % (x, y, size, fill, label)


# ---------------------------------------------------------------- room

def shell():
    out = []
    ridge_x, ridge_y = W / 2.0, L["ridgeHeight"]
    eave = L["eaveHeight"]

    # Roof planes: the underside of the roof coming towards the viewer.
    for index, edge_x in enumerate((0.0, W)):
        tri = [(edge_x, eave), (ridge_x, ridge_y), (edge_x, ridge_y)]
        clip_id = "roof%d" % index
        out.append('<clipPath id="%s"><polygon points="%s"/></clipPath>'
                   % (clip_id, " ".join("%g,%g" % p for p in tri)))
        inner = [poly(tri, "url(#roofGrad)")]
        offset = 0.0
        while offset < ridge_y - eave + 40:
            inner.append('<line x1="%g" y1="%g" x2="%g" y2="%g" stroke="%s" stroke-width="3"/>'
                         % (edge_x, eave + offset, ridge_x, ridge_y + offset, C["roofSeam"]))
            offset += 44
        out.append('<g clip-path="url(#%s)">%s</g>' % (clip_id, esc(inner)))

    # Gable wall.
    wall = [(0, L["floorLine"]), (0, eave), (ridge_x, ridge_y), (W, eave), (W, L["floorLine"])]
    out.append('<clipPath id="wallClip"><polygon points="%s"/></clipPath>'
               % " ".join("%g,%g" % p for p in wall))
    out.append(poly(wall, "url(#wallGrad)"))

    # Beams.
    out.append('<polyline points="0,%g %g,%g %g,%g" fill="none" stroke="%s" '
               'stroke-width="26" stroke-linecap="round"/>'
               % (eave - 4, ridge_x, ridge_y - 4, W, eave - 4, C["rafter"]))
    out.append('<g clip-path="url(#wallClip)">%s</g>' % esc([
        rect(0, 690, W, 16, C["rafter"], opacity=0.9),
        rect(0, 620, W, 16, C["rafter"], opacity=0.45),
    ]))

    # Floor: bands that get shorter towards the wall.
    band_count = 7
    weights = [1.0 + i * 0.6 for i in range(band_count)]
    total = sum(weights)
    y = L["floorLine"]
    for index, weight in enumerate(weights):
        height = L["floorLine"] * weight / total
        out.append(rect(0, y - height, W, height,
                        C["floorPlank"] if index % 2 == 0 else C["floorPlankAlt"]))
        spacing = 210 + index * 46
        x = index * 73 - spacing
        while x < W + spacing:
            out.append('<line x1="%g" y1="%g" x2="%g" y2="%g" stroke="%s" stroke-width="2"/>'
                       % (x, y - height, x, y, C["floorSeam"]))
            x += spacing
        out.append('<line x1="0" y1="%g" x2="%g" y2="%g" stroke="%s" stroke-width="3" opacity="0.8"/>'
                   % (y - height, W, y - height, C["floorSeam"]))
        y -= height

    out.append(rect(0, L["floorLine"] - 14, W, 20, C["woodDark"]))
    return out


def rug():
    cx, cy = L["rugCentre"]["x"], L["rugCentre"]["y"]
    rw, rh = L["rugSize"]["width"], L["rugSize"]["height"]
    return [ellipse(cx, cy, rw, rh, C["rug"], stroke=C["rugTrim"], sw=8),
            ellipse(cx, cy, rw * 0.7, rh * 0.66, C["rugInner"], stroke=C["rugTrim"], sw=5)]


def perch():
    cx, cy = L["perchCentre"]["x"], L["perchCentre"]["y"]
    return [rect(cx - 86, cy - 46, 172, 92, C["woodDark"], rx=12),
            ellipse(cx, cy + 46, 176, 46, C["wood"], stroke=C["woodLight"], sw=3),
            ellipse(cx, cy + 46, 96, 24, "none", stroke=C["woodLight"], sw=2, opacity=0.7)]


def shelf_and_book():
    s = L["shelfRect"]
    out = [rect(s["x"], s["y"], s["width"], s["height"], C["wood"], stroke=C["woodDark"], sw=2, rx=4)]
    for bx in (s["x"] + 34, s["x"] + s["width"] - 34):
        out.append(poly([(bx - 14, s["y"]), (bx + 14, s["y"]), (bx + 14, s["y"] - 46)], C["woodDark"]))

    bx, by = L["bookAnchor"]["x"], L["bookAnchor"]["y"]
    book = []
    for side, fill, dx in ((-1, C["bookPage"], -74), (1, C["bookPageShade"], 0)):
        book.append(group(
            [rect(0, -34, 74, 68, fill, stroke=C["woodDark"], sw=2, rx=3)],
            transform="translate(%g,%g) rotate(%g)" % (dx, 4, -3.4 * side)))
    book.append(rect(-80, -44, 160, 18, C["bookCover"], rx=5))
    book.append(rect(-4, -56, 9, 52, C["rug"]))
    out.append(group(book, transform="translate(%g,%g)" % (bx, by)))
    return out


def table_and_lamp():
    t = L["tableTopRect"]
    out = [rect(t["x"], t["y"], t["width"], t["height"], C["wood"], stroke=C["woodDark"], sw=2, rx=5)]
    for lx in (t["x"] + 22, t["x"] + t["width"] - 34):
        out.append(rect(lx, L["floorLine"] - 10, 16, t["y"] - L["floorLine"] + 10, C["woodDark"]))

    lx, ly = L["lampAnchor"]["x"], L["lampAnchor"]["y"]
    lamp = [circle(0, 84, 130, "url(#lampGlow)", opacity=0.30),
            ellipse(0, 0, 86, 22, C["lampBase"]),
            rect(-6, 0, 12, 74, C["lampBase"]),
            poly([(-62, 74), (62, 74), (40, 146), (-40, 146)], C["lampShade"],
                 stroke=C["woodDark"], sw=2)]
    out.append(group(lamp, transform="translate(%g,%g)" % (lx, ly)))
    return out


def blocks():
    bx, by = L["blocksAnchor"]["x"], L["blocksAnchor"]["y"]
    faces = C["blockFaces"]
    out = []
    for index, (dx, dy, rot, letter) in enumerate(
            [(-92, 0, 3.4, "A"), (0, -4, -2.3, "B"), (88, 2, 5.7, "C")]):
        body = [rect(-42, -42, 84, 84, faces[index % len(faces)], stroke=C["blockEdge"], sw=3, rx=10),
                upright_text(0, 0, letter, 46, C["blockEdge"])]
        out.append(group(body, transform="translate(%g,%g) rotate(%g)" % (bx + dx, by + dy, rot)))
    return out


# ---------------------------------------------------------------- window

SKY_KEYS = {"morning": "skyMorning", "day": "skyDay", "evening": "skyEvening", "night": "skyNight"}


def window(time):
    cx, cy = L["windowCentre"]["x"], L["windowCentre"]["y"]
    r = L["windowRadius"]
    inner = ['<circle cx="0" cy="0" r="%g" fill="url(#sky_%s)"/>' % (r, time)]

    if time == "morning":
        inner.append(circle(-r * 0.34, -r * 0.18, r * 0.95, "url(#sunGlow)", opacity=0.85))
        inner.append(circle(-r * 0.34, -r * 0.18, r * 0.24, C["sun"]))
        inner.append(cloud(132, -r * 0.1, r * 0.42, 0.75))
    elif time == "day":
        inner.append(cloud(160, -r * 0.3, r * 0.46, 0.95))
        inner.append(cloud(112, r * 0.35, r * 0.08, 0.85))
        inner.append(cloud(190, 0, -r * 0.36, 0.7))
    elif time == "evening":
        inner.append(moon(r, r * 0.34, r * 0.16, 0.9))
        inner.extend(stars(r, 7, 0.45))
        inner.append(cloud(150, -r * 0.2, -r * 0.3, 0.35))
    else:
        inner.append(moon(r, r * 0.26, r * 0.42, 1.0))
        inner.extend(stars(r, 16, 0.95))

    glass = ('<clipPath id="glass"><circle cx="0" cy="0" r="%g"/></clipPath>'
             '<g clip-path="url(#glass)">%s</g>') % (r, esc(inner))

    frame = [circle(0, 0, r, "none", stroke=C["wood"], sw=26),
             circle(0, 0, r - 10, "none", stroke=C["woodDark"], sw=4, opacity=0.6),
             rect(-6, -(r - 7), 12, (r - 7) * 2, C["woodLight"]),
             rect(-(r - 7), -6, (r - 7) * 2, 12, C["woodLight"]),
             rect(-r * 1.15, -r - 17, r * 2.3, 22, C["wood"], stroke=C["woodDark"], sw=2, rx=6)]

    return [group([glass] + frame, transform="translate(%g,%g)" % (cx, cy))]


def cloud(width, x, y, opacity):
    puffs = [(-0.34, -0.02, 0.26), (-0.08, 0.10, 0.34), (0.18, 0.01, 0.28), (0.38, -0.06, 0.20)]
    body = [circle(width * dx, width * dy, width * s, C["cloud"]) for dx, dy, s in puffs]
    return group(body, transform="translate(%g,%g)" % (x, y), opacity=opacity)


def moon(r, x, y, scale):
    disc = r * 0.2 * scale
    body = [circle(0, 0, disc * 3, "url(#moonGlow)", opacity=0.32),
            circle(0, 0, disc, C["moon"])]
    for dx, dy, s in [(-0.3, 0.22, 0.24), (0.28, 0.3, 0.17), (0.1, -0.34, 0.2)]:
        body.append(circle(disc * dx, disc * dy, disc * s, "#D1D1D1", opacity=0.45))
    return group(body, transform="translate(%g,%g)" % (x, y))


def stars(r, count, max_alpha):
    import math
    seed = 0x5EED
    out = []

    def nxt():
        nonlocal seed
        seed = (seed * 6364136223846793005 + 1442695040888963407) % (2 ** 64)
        return ((seed >> 33) % 10000) / 10000.0

    for _ in range(count):
        angle = nxt() * math.pi * 2
        distance = (0.25 + nxt() * 0.66) * r
        radius = 2 + nxt() * 2.6
        alpha = max_alpha * (0.4 + nxt() * 0.6)
        out.append(circle(math.cos(angle) * distance, math.sin(angle) * distance,
                          radius, C["star"], opacity=alpha))
    return out


SPILL = {"morning": ("#FFD79A", 0.20), "day": ("#EAF4FF", 0.14),
         "evening": ("#E2A070", 0.12), "night": ("#9FB6E8", 0.07)}
WASH = {"morning": ("#FFC978", 0.14), "day": ("#FFF6E2", 0.06),
        "evening": ("#C97A5A", 0.12), "night": ("#5C6BA8", 0.22)}


def light_spill(time):
    cx, cy = L["windowCentre"]["x"], L["windowCentre"]["y"]
    r = L["windowRadius"]
    color, alpha = SPILL[time]
    points = [(cx - r * 0.9, cy - r * 0.2), (cx + r * 0.9, cy - r * 0.2),
              (cx + r * 0.2, L["floorLine"] - 190), (cx - r * 3.1, L["floorLine"] - 190)]
    return [poly(points, color, opacity=alpha)]


# ---------------------------------------------------------------- owl

def owl():
    ox, oy = L["owlHome"]["x"], L["owlHome"]["y"]
    body = [ellipse(0, 8, 200, 44, "#000000", opacity=0.20),
            ellipse(-42, 14, 58, 26, C["owlFoot"], stroke=C["owlBeakShade"], sw=2),
            ellipse(42, 14, 58, 26, C["owlFoot"], stroke=C["owlBeakShade"], sw=2),
            group([poly([(-36, 0), (36, 0), (0, -58)], C["owlBodyShade"])],
                  transform="translate(8,74) rotate(10.3)"),
            ellipse(0, 122, 196, 226, C["owlBody"], stroke=C["owlBodyShade"], sw=3),
            ellipse(0, 108, 130, 156, C["owlBelly"]),
            group([ellipse(0, 0, 56, 164, C["owlBodyShade"])], transform="translate(-92,132) rotate(-6.9)"),
            group([ellipse(0, 0, 56, 164, C["owlBodyShade"])], transform="translate(92,132) rotate(6.9)")]

    head = []
    for side in (-1, 1):
        head.append(group([poly([(-17, 0), (17, 0), (0, 64)], C["owlBodyShade"])],
                          transform="translate(%g,%g) rotate(%g)" % (54 * side, 42 + 88 - 26, -9.2 * side)))
    head.append(circle(0, 42, 88, C["owlBody"], stroke=C["owlBodyShade"], sw=3))
    head.append(ellipse(0, 46, 148, 118, C["owlFace"]))
    for side in (-1, 1):
        head.append(circle(37 * side, 50, 30, C["owlEyeWhite"], stroke=C["owlBodyShade"], sw=3))
        head.append(circle(37 * side + 2 * side, 49, 15, C["owlPupil"]))
        head.append(circle(37 * side + 2 * side + 6, 56, 5, "#FFFFFF", opacity=0.9))
    head.append(poly([(-16, 8), (16, 8), (0, -20)], C["owlBeakShade"]))
    head.append(poly([(-22, 24), (22, 24), (0, -2)], C["owlBeak"]))

    body.append(group(head, transform="translate(0,214)"))
    return [group(body, transform="translate(%g,%g)" % (ox, oy))]


# ---------------------------------------------------------------- document

def defs():
    sky_defs = []
    for time, key in SKY_KEYS.items():
        stops = C[key]
        offsets = ["0%", "50%", "100%"][:len(stops)]
        body = "".join('<stop offset="%s" stop-color="%s"/>' % (o, s) for o, s in zip(offsets, stops))
        # y1/y2 flipped because the whole drawing is flipped.
        sky_defs.append('<linearGradient id="sky_%s" x1="0" y1="1" x2="0" y2="0">%s</linearGradient>'
                        % (time, body))

    return """<defs>
  <linearGradient id="roofGrad" x1="0" y1="1" x2="0" y2="0">
    <stop offset="0%%" stop-color="%s"/><stop offset="100%%" stop-color="%s"/>
  </linearGradient>
  <linearGradient id="wallGrad" x1="0" y1="1" x2="0" y2="0">
    <stop offset="0%%" stop-color="%s"/><stop offset="100%%" stop-color="%s"/>
  </linearGradient>
  <radialGradient id="sunGlow"><stop offset="0%%" stop-color="%s" stop-opacity="1"/>
    <stop offset="45%%" stop-color="%s" stop-opacity="0.45"/>
    <stop offset="100%%" stop-color="%s" stop-opacity="0"/></radialGradient>
  <radialGradient id="moonGlow"><stop offset="0%%" stop-color="%s" stop-opacity="1"/>
    <stop offset="45%%" stop-color="%s" stop-opacity="0.45"/>
    <stop offset="100%%" stop-color="%s" stop-opacity="0"/></radialGradient>
  <radialGradient id="lampGlow"><stop offset="0%%" stop-color="%s" stop-opacity="1"/>
    <stop offset="45%%" stop-color="%s" stop-opacity="0.45"/>
    <stop offset="100%%" stop-color="%s" stop-opacity="0"/></radialGradient>
  %s
</defs>""" % (C["roofNear"], C["roofFar"],
              C["wallUpper"], C["wallLower"],
              C["sun"], C["sun"], C["sun"],
              C["moon"], C["moon"], C["moon"],
              C["lampGlow"], C["lampGlow"], C["lampGlow"],
              "\n  ".join(sky_defs))


def render(time):
    layers = []
    layers += shell()
    layers += window(time)
    layers += rug()
    layers += shelf_and_book()
    layers += table_and_lamp()
    layers += perch()
    layers += light_spill(time)
    layers += blocks()
    layers += owl()

    wash_color, wash_alpha = WASH[time]
    layers.append(rect(0, 0, W, H, wash_color, opacity=wash_alpha))

    return """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %g %g" width="%g" height="%g">
%s
<g transform="translate(0,%g) scale(1,-1)">
%s
</g>
</svg>
""" % (W, H, W, H, defs(), H, esc(layers))


if __name__ == "__main__":
    os.makedirs(OUT_DIR, exist_ok=True)
    for time in ["morning", "day", "evening", "night"]:
        path = os.path.join(OUT_DIR, "room-%s.svg" % time)
        with open(path, "w") as handle:
            handle.write(render(time))
        print("wrote", path)
