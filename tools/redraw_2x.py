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
    tools/redraw_2x.py --blocky IN OUT     # no smoothing: small round shapes (the face sheets)

Standard library only. The 1x file is deleted after (its `.import` renamed), so the 2x file is the
art from then on: redraw it by hand or with a generator, not by running this again.
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
            if None not in sides.values() and all(0 <= x + dx < src.width and 0 <= y + dy < src.height for dx, dy in sides):
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


def redraw(src: Canvas, smooth: bool = True) -> Canvas:
    """`src` at 2x detail: smoothed (or doubled, `smooth` false), its outside outline one art pixel."""
    return thin_outline(scale2x(src)) if smooth else double(src)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("source", type=Path)
    parser.add_argument("target", type=Path)
    parser.add_argument("--blocky", action="store_true", help="double without smoothing (small round shapes)")
    args = parser.parse_args(argv)
    if "@2x" not in args.target.stem:
        parser.error("the target's name ends in @2x (ArtDetail)")
    art = redraw(read_svg(args.source.read_text(encoding="utf-8")), not args.blocky)
    if args.target.suffix == ".png":
        args.target.write_bytes(art.png())
    else:
        args.target.write_text(art.svg(), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
