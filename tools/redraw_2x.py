#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
# SPDX-License-Identifier: GPL-3.0-or-later
"""Redraw a 1x sprite sheet (an SVG of rects) at 2x detail (ART1: players and enemies; docs/STYLE.md,
"The picture and the art's detail"; art/README.md, "Redrawing a sprite at 64x64").

The sheet keeps its layout at twice the pixels (every frame, grip and origin at twice its numbers),
its palette colours and its silhouette, and is drawn finer in two ways:

1. **Smoothed edges.** Each pixel becomes four by the EPX rule (Scale2x): a quarter takes its two
   neighbours' colour where they agree and the others do not, so a stepped diagonal of 1x art is
   drawn as a straight line of one art pixel steps, never a staircase of 2x2 blocks.
2. **A one-art-pixel outline.** The outline round the outside (outline pixels touching clear ones)
   becomes one art pixel thick: the inner half of a doubled outline takes the colour of the part
   it encloses. Inner lines and dark fills (a pupil, a seam) keep their weight, so they still
   read when the camera zooms out to hold a party (art/README.md, step 5).

    tools/redraw_2x.py IN.svg OUT@2x.svg   # an SVG of rects, one a run along a row
    tools/redraw_2x.py IN.svg OUT@2x.png   # an indexed PNG, for a sheet whose rects would pass 1 MB
    tools/redraw_2x.py --blocky IN OUT     # no smoothing: small round shapes (a small face)
    tools/redraw_2x.py --detail IN OUT     # and new detail: one-pixel edge light and shadow
    tools/redraw_2x.py --texture IN OUT    # and each material's surface (pores, grain, flecks, glints)

Standard library only. Delete the 1x file after by hand (renaming its `.import`, art/README.md step
2), so the 2x file is the art from then on: redraw it by hand or with a generator, not by running
this again.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from staff_art import OUTLINE, Canvas  # noqa: E402

RECT = re.compile(r'<rect\s+x="(\d+)"\s+y="(\d+)"\s+width="(\d+)"\s+height="(\d+)"\s+fill="(#[0-9a-fA-F]{6})"\s*/>')
SIZE = re.compile(r'<svg[^>]*\swidth="(\d+)"\s+height="(\d+)"')

Pixels = list[list[str | None]]


def read_svg(text: str) -> Canvas:
    """The pixels of an SVG of whole-pixel rects (later rects over earlier ones)."""
    size = SIZE.search(text)
    if size is None:
        raise ValueError("no <svg width height>")
    canvas = Canvas(int(size.group(1)), int(size.group(2)))
    for x, y, w, h, colour in RECT.findall(text):
        for yy in range(int(y), int(y) + int(h)):
            for xx in range(int(x), int(x) + int(w)):
                canvas.pixels[yy][xx] = colour.lower()
    rects = text.count("<rect")
    if rects != len(RECT.findall(text)):
        raise ValueError("a rect this reader does not take (only x, y, width, height, fill)")
    return canvas


def _at(pixels: Pixels, x: int, y: int) -> str | None:
    if 0 <= y < len(pixels) and 0 <= x < len(pixels[0]):
        return pixels[y][x]
    return None


def scale2x(src: Canvas) -> Canvas:
    """EPX: each pixel E as four; a quarter takes the colour of its two side neighbours where they
    agree, differ from the other two, so diagonals stay one step a pixel."""
    out = Canvas(src.width * 2, src.height * 2)
    p = src.pixels
    for y in range(src.height):
        for x in range(src.width):
            e = p[y][x]
            b = _at(p, x, y - 1)
            d = _at(p, x - 1, y)
            f = _at(p, x + 1, y)
            h = _at(p, x, y + 1)
            quads = [e, e, e, e]
            if b != h and d != f:
                quads[0] = d if d == b else e
                quads[1] = f if b == f else e
                quads[2] = d if d == h else e
                quads[3] = f if h == f else e
            out.pixels[2 * y][2 * x] = quads[0]
            out.pixels[2 * y][2 * x + 1] = quads[1]
            out.pixels[2 * y + 1][2 * x] = quads[2]
            out.pixels[2 * y + 1][2 * x + 1] = quads[3]
    return out


NEAR = [(dx, dy) for dy in (-1, 0, 1) for dx in (-1, 0, 1) if (dx, dy) != (0, 0)]


def thin_outline(src: Canvas) -> Canvas:
    """The outside outline one art pixel thick: an outline pixel that touches no clear pixel, beside
    one that does (the edge) with a part's own colour on its other side, takes that colour. Decided
    from the picture as it was, all at once, so a line is thinned from its outside only."""
    p = src.pixels

    def edge(x: int, y: int) -> bool:
        if _at(p, x, y) != OUTLINE:
            return False
        for dx, dy in NEAR:
            xx, yy = x + dx, y + dy
            if not (0 <= yy < src.height and 0 <= xx < src.width) or p[yy][xx] is None:
                return True
        return False

    out = Canvas(src.width, src.height)
    for y in range(src.height):
        for x in range(src.width):
            colour = p[y][x]
            out.pixels[y][x] = colour
            if colour != OUTLINE or edge(x, y):
                continue
            # The straight directions first, so a fill follows the part beside, then the corners.
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, 1), (1, -1), (-1, -1)):
                inside = _at(p, x - dx, y - dy)
                if edge(x + dx, y + dy) and inside is not None and inside != OUTLINE:
                    out.pixels[y][x] = inside
                    break
    return out


def double(src: Canvas) -> Canvas:
    """Each pixel as a 2x2 block, no smoothing, for small round shapes (an eye, a pupil) that the
    EPX rule would bend out of shape; the outside outline thinned block by block: of an outline
    pixel beside a clear one, only the quarters facing the clear side stay outline, the others take
    the colour of the part beside them on their own side (or stay outline where none is)."""
    out = Canvas(src.width * 2, src.height * 2)
    p = src.pixels
    for y in range(src.height):
        for x in range(src.width):
            colour = p[y][x]
            for qy in (0, 1):
                for qx in (0, 1):
                    out.pixels[2 * y + qy][2 * x + qx] = colour
            if colour != OUTLINE:
                continue
            sides = {(dx, dy): _at(p, x + dx, y + dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))}
            if None not in sides.values():
                continue
            for qy in (0, 1):
                for qx in (0, 1):
                    across = (1 if qx else -1, 0)
                    down = (0, 1 if qy else -1)
                    if sides[across] is None or sides[down] is None:
                        continue
                    for side in (across, down):
                        if sides[side] != OUTLINE:
                            out.pixels[2 * y + qy][2 * x + qx] = sides[side]
                            break
    return out


MATERIAL_ROW = re.compile(r"^\| \*\*([^*]+)\*\*[^|]*\| `(#[0-9a-f]{6})` \| `(#[0-9a-f]{6})` \| `(#[0-9a-f]{6})` \|", re.M)


def materials() -> dict[str, tuple[str, int]]:
    """Each palette colour's material and shade (0 shadow, 1 base, 2 light), read from
    docs/STYLE.md's table."""
    style = (Path(__file__).resolve().parent.parent / "docs/STYLE.md").read_text(encoding="utf-8")
    out: dict[str, tuple[str, int]] = {}
    for name, *shades in MATERIAL_ROW.findall(style):
        for shade, colour in enumerate(shades):
            out[colour] = (name, shade)
    return out


# Materials a character never shades down to their shadow (docs/STYLE.md, "Readability": Stone
# shadow is the floor's), so their edge on the bottom right stays the base.
NO_SHADOW = ("Stone",)


def detail(src: Canvas) -> Canvas:
    """New detail at the 2x picture's own pixels (the owner, 2026-11-26: real detail, not a 2x):
    every part's base shade gets a one-art-pixel lit edge where it meets something else on its top
    or left and a shaded one on its bottom or right (a rounder form than the 1x shading's two-pixel
    bands; Stone keeps its base there, NO_SHADOW). Decided from the picture as it was, all at once."""
    shades = materials()
    p = src.pixels
    out = Canvas(src.width, src.height)

    def material(x: int, y: int) -> str | None:
        colour = _at(p, x, y)
        return shades[colour][0] if colour in shades else None

    def recolour(colour: str, shade: int) -> str:
        name = shades[colour][0]
        for other, (n, s) in shades.items():
            if n == name and s == shade:
                return other
        return colour

    for y in range(src.height):
        for x in range(src.width):
            colour = p[y][x]
            out.pixels[y][x] = colour
            if colour is None or colour == OUTLINE or colour not in shades:
                continue
            name, shade = shades[colour]
            if shade != 1:
                continue
            if material(x - 1, y) != name or material(x, y - 1) != name:
                out.pixels[y][x] = recolour(colour, 2)
            elif name not in NO_SHADOW and (material(x + 1, y) != name or material(x, y + 1) != name):
                out.pixels[y][x] = recolour(colour, 0)
    return out


# Each material's surface at the finer pixels (`texture`): what its inner base-shade pixels show.
SURFACES = {
    "Bone": "pores",
    "Wood": "grain",
    "Leaf": "veins",
    "Fire": "flicker",
    "Ice": "glints",
    "Water": "glints",
    "Arc": "glints",
    "Spark": "glints",
    "Stone": "speckle",
    "Void": "speckle",
    "Blight": "speckle",
}


def _hash(x: int, y: int) -> int:
    return ((x * 73856093) ^ (y * 19349663) ^ 0x5BD1E995) % 1000003


def texture(src: Canvas, frame_width: int = 0) -> Canvas:
    """A material's surface at the finer pixels (the owner, 2026-11-26: "texture and material"), on
    the base-shade pixels inside a part (all four neighbours its own material), in the material's
    own shades: bone pitted with pores (a shadow pit, its bottom-right lit), wood grain in broken
    streaks along the part's length, leaf veins and fire flicker in light flecks, ice, gold and
    lightning glints, stone and void speckled. Placed by a hash of the pixel's place in its frame
    (`frame_width` wide; 0: the picture's height, square frames), so every frame of a strip has
    the same surface and nothing jumps between frames (docs/STYLE.md, "Smooth")."""
    shades = materials()
    p = src.pixels
    width = frame_width or src.height
    out = Canvas(src.width, src.height)

    def material(x: int, y: int) -> str | None:
        colour = _at(p, x, y)
        return shades[colour][0] if colour in shades else None

    def shade(name: str, which: int) -> str:
        return next(c for c, (n, s) in shades.items() if n == name and s == which)

    # Each part (a run of one material, four ways): upright when it is at least as tall as wide.
    part_of: list[list[int]] = [[-1] * src.width for _ in range(src.height)]
    upright_part: list[bool] = []
    for sy in range(src.height):
        for sx in range(src.width):
            name = material(sx, sy)
            if name is None or part_of[sy][sx] >= 0:
                continue
            index = len(upright_part)
            stack = [(sx, sy)]
            part_of[sy][sx] = index
            box = [sx, sy, sx, sy]
            while stack:
                cx, cy = stack.pop()
                box = [min(box[0], cx), min(box[1], cy), max(box[2], cx), max(box[3], cy)]
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = cx + dx, cy + dy
                    if 0 <= nx < src.width and 0 <= ny < src.height and part_of[ny][nx] < 0 and material(nx, ny) == name:
                        part_of[ny][nx] = index
                        stack.append((nx, ny))
            upright_part.append(box[3] - box[1] >= box[2] - box[0])

    for y in range(src.height):
        out.pixels[y] = list(p[y])
    for y in range(src.height):
        for x in range(src.width):
            colour = p[y][x]
            if colour not in shades or shades[colour][1] != 1:
                continue
            name = shades[colour][0]
            surface = SURFACES.get(name)
            if surface is None or any(material(x + dx, y + dy) != name for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                continue
            fx = x % width
            h = _hash(fx, y)
            if surface == "pores" and h % 17 == 0:
                out.pixels[y][x] = shade(name, 0)
                if _at(p, x + 1, y + 1) == colour:
                    out.pixels[y + 1][x + 1] = shade(name, 2)
            elif surface == "grain":
                upright = upright_part[part_of[y][x]]
                lane, along = (fx, y) if upright else (y, fx)
                if lane % 3 == 1 and _hash(lane, along // 3) % 4 != 0:
                    out.pixels[y][x] = shade(name, 0)
            elif surface in ("veins", "flicker") and h % 9 == 0:
                out.pixels[y][x] = shade(name, 2)
            elif surface == "glints" and h % 23 == 0:
                out.pixels[y][x] = shade(name, 2)
            elif surface == "speckle" and h % 13 == 0:
                out.pixels[y][x] = shade(name, 2)
    return out


def redraw(src: Canvas, smooth: bool = True, detailed: bool = False, textured: bool = False, frame_width: int = 0) -> Canvas:
    """`src` at 2x detail: smoothed (or doubled, `smooth` false), its outside outline one art pixel;
    with `detailed` new detail at the finer pixels (`detail`), with `textured` its materials'
    surfaces too (`texture`, frames `frame_width` wide)."""
    out = thin_outline(scale2x(src)) if smooth else double(src)
    if textured:
        out = texture(out, frame_width)
    return detail(out) if detailed or textured else out


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("source", type=Path)
    parser.add_argument("target", type=Path)
    parser.add_argument("--blocky", action="store_true", help="double without smoothing (small round shapes)")
    parser.add_argument("--detail", action="store_true", help="add detail at the finer pixels: one-pixel edge light and shadow")
    parser.add_argument("--texture", action="store_true", help="and each material's surface (bone pores, wood grain, flecks, glints)")
    parser.add_argument("--frame", type=int, default=0, help="a frame's width in the 2x picture (default: its height)")
    args = parser.parse_args(argv)
    if "@2x" not in args.target.stem:
        parser.error("the target's name ends in @2x (ArtDetail)")
    art = redraw(read_svg(args.source.read_text(encoding="utf-8")), not args.blocky, args.detail, args.texture, args.frame)
    if args.target.suffix == ".png":
        args.target.write_bytes(art.png())
    else:
        args.target.write_text(art.svg(), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
