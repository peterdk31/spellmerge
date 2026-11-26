#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
# SPDX-License-Identifier: GPL-3.0-or-later
"""The shared face sheets at 2x detail (ART1: players and enemies; docs/STYLE.md, "The living
staffs"; art/README.md, "Redrawing a sprite at 64x64"), drawn from shape rules.

- `art/faces/eyes@2x.svg`: 32x16 frames, ten columns (nine looks, (y + 1) * 3 + x + 1, then the
  blink) and a row a face style (`Face.Style`): the Optimist's round eyes (the curl's, drawn by
  tools/staff_art.py), the Show-off's with a sparkle, the Dozer's heavy lids, the Sergeant's narrow
  eyes, a stray's white eyes with slit pupils (tinted by the game), and a one-eyed stray's.
- `art/faces/brows@2x.svg`: 32x16 frames, a column a mood (`Face.Mood`), the row of two brows and
  the row of one (the one-eyed stray's).

The left eye's top-left is at (2, 2) of a frame, the brows' at (2, 10): the 16x8 sheets' layout at
two art pixels a world pixel. Palette colours only; rects only, one a run along a row.

    tools/face_art.py           # writes the two SVGs
    tools/face_art.py --check   # fails when an SVG differs from what the rules draw
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import staff_art  # noqa: E402
from staff_art import BONE, OUTLINE, SPARK, Canvas  # noqa: E402

ROOT = staff_art.ROOT
DETAIL = staff_art.DETAIL
FRAME = (staff_art.EYE_FRAME[0] * DETAIL, staff_art.EYE_FRAME[1] * DETAIL)
COLUMNS = staff_art.EYE_COLUMNS
BLINK = COLUMNS - 1
# Where the eye boxes start in a frame (the left eye's; the right one a box further), art pixels.
BOX_LEFT = DETAIL // 2
BOX_W = staff_art.EYE_BOX[0]

Eye = list[list[str | None]]


def _shape(height: int, top_cut: int) -> list[list[bool]]:
    """An oval BOX_W wide and `height` tall, its top `top_cut` rows cut flat (a lid's line)."""
    cx, cy = BOX_W / 2.0, height / 2.0
    rx, ry = BOX_W / 2.0 - 0.2, height / 2.0 - 0.2
    inside = [[((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2 <= 1.0 for x in range(BOX_W)] for y in range(height)]
    if top_cut > 0:
        # Flat across from the cut, as wide as the oval is a row below it.
        for y in range(height):
            if y < top_cut:
                inside[y] = [False] * BOX_W
            elif y == top_cut:
                inside[y] = [a or b for a, b in zip(inside[y], inside[min(y + 1, height - 1)])]
    return inside


def _rimmed(inside: list[list[bool]], shade: bool) -> Eye:
    """The shape with a one-pixel outline rim, the white Bone light, shaded Bone base toward the
    bottom right (`shade`; a stray's eyes are all white, for the game to tint)."""
    h, w = len(inside), BOX_W
    out: Eye = [[None] * w for _ in range(h)]
    for y in range(h):
        for x in range(w):
            if inside[y][x]:
                rim = any(not (0 <= x + dx < w and 0 <= y + dy < h) or not inside[y + dy][x + dx] for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
                out[y][x] = OUTLINE if rim else BONE[2]
    if shade:
        for y in range(h - 1):
            for x in range(w - 1):
                if out[y][x] == BONE[2] and out[y + 1][x + 1] == OUTLINE:
                    out[y][x] = BONE[1]
    return out


def _pupil(eye: Eye, middle: tuple[float, float], radius: float, glint: bool) -> None:
    for y in range(len(eye)):
        for x in range(BOX_W):
            if eye[y][x] in BONE and math.hypot(x + 0.5 - middle[0], y + 0.5 - middle[1]) <= radius:
                eye[y][x] = OUTLINE
    gx, gy = int(middle[0] - radius * 0.5), int(middle[1] - radius * 0.5)
    if glint and 0 <= gy < len(eye) and eye[gy][gx] == OUTLINE:
        eye[gy][gx] = BONE[2]


def _slit(eye: Eye, middle: tuple[float, float]) -> None:
    """A stray's slit pupil: two art pixels wide, five tall, its ends one wide."""
    x0, y0 = int(middle[0] - 1.0), int(middle[1] - 2.5)
    for dy in range(5):
        for dx in range(2):
            if dy in (0, 4) and dx == 1:
                continue
            x, y = x0 + dx, y0 + dy
            if 0 <= y < len(eye) and 0 <= x < BOX_W and eye[y][x] in BONE:
                eye[y][x] = OUTLINE


def _sparkle(eye: Eye) -> None:
    """The Show-off's sparkle: a Spark light glint at the white's top right, a pixel cross."""
    for x, y in ((6, 3), (7, 2), (7, 3), (7, 4), (8, 3)):
        if eye[y][x] in BONE:
            eye[y][x] = SPARK[2]


def _lid(eye: Eye, rows: int) -> None:
    """The Dozer's heavy lid: the white's top `rows` rows Bone shadow, a line under them."""
    for y in range(1, len(eye)):
        for x in range(BOX_W):
            if eye[y][x] in BONE:
                if y <= rows:
                    eye[y][x] = BONE[0]
                elif y == rows + 1:
                    eye[y][x] = OUTLINE


# A style: (the eye's height, its top in the frame (art pixels), its flat top's rows, shaded, the
# pupil (round radius, or 0 for a slit), its middle at rest in the box, the eyes it has).
STYLES = (
    (14, 0, 0, True, 2.3, (5.5, 6.5), 2),  # CHEER: round (staff_art._eye)
    (14, 0, 0, True, 2.3, (5.5, 7.0), 2),  # EAGER: round, a sparkle
    (10, 4, 1, True, 2.0, (5.5, 7.0), 2),  # SLEEPY: heavy-lidded
    (10, 2, 1, True, 2.0, (5.5, 5.5), 2),  # STERN: narrow
    (10, 0, 1, False, 0.0, (5.5, 5.5), 2),  # STRAY: white, flat-topped, slit pupils
    (10, 0, 1, False, 0.0, (5.5, 5.5), 1),  # STRAY_ONE: one eye
)


def eye(style: int, look: tuple[int, int]) -> Eye:
    """One eye of `style`, looking `look` (x, y each -1, 0 or 1; two art pixels a step)."""
    height, _top, cut, shade, radius, rest, _count = STYLES[style]
    if style == 0:
        return staff_art._eye(look)
    picture = _rimmed(_shape(height, cut), shade)
    middle = (rest[0] + look[0] * 2.0, rest[1] + look[1] * (1.0 if height < 14 else 2.0))
    if style == 2:
        _lid(picture, 3)
        middle = (middle[0], max(middle[1], 7.0))
    if radius > 0.0:
        _pupil(picture, middle, radius, glint=True)
    else:
        _slit(picture, middle)
    if style == 1:
        _sparkle(picture)
    return picture


def blink(style: int) -> Eye:
    """A closed eye: the Optimist's smiling lid; the others a flat line two art pixels thick, at
    the 1x sheets' blink row, its ends a pixel shorter."""
    if style == 0:
        return staff_art._blink()
    height, top = STYLES[style][0], STYLES[style][1]
    out: Eye = [[None] * BOX_W for _ in range(height)]
    row = 6 - top
    for x in range(1, BOX_W - 1):
        for dy in range(2):
            if 0 <= row + dy < height:
                out[row + dy][x] = OUTLINE
    return out


def eyes() -> Canvas:
    fw, fh = FRAME
    sheet = Canvas(fw * COLUMNS, fh * len(STYLES))
    for style, (_h, top, _c, _s, _r, _m, count) in enumerate(STYLES):
        for column in range(COLUMNS):
            picture = blink(style) if column == BLINK else eye(style, (column % 3 - 1, column // 3 - 1))
            for side in range(count):
                ox = column * fw + BOX_LEFT + side * BOX_W
                oy = style * fh + top + (DETAIL // 2 if style == 0 or style == 1 else 0)
                for y, row in enumerate(picture):
                    for x, colour in enumerate(row):
                        if colour is not None and 0 <= oy + y - style * fh < fh:
                            sheet.pixels[oy + y][ox + x] = colour
    return sheet


def brows() -> Canvas:
    """The pair (tools/staff_art.py's) and, a row below, the left brow alone."""
    pair = staff_art.brows()
    fw, fh = FRAME
    sheet = Canvas(pair.width, fh * 2)
    sheet.blit(pair, 0, 0)
    for mood in range(staff_art.BROW_COLUMNS):
        for y in range(fh):
            for x in range(BOX_LEFT * 2 + staff_art.BROW_LENGTH):
                sheet.pixels[fh + y][mood * fw + x] = pair.pixels[y][mood * fw + x]
    return sheet


FILES = {
    ROOT / "art/faces/eyes@2x.svg": eyes,
    ROOT / "art/faces/brows@2x.svg": brows,
}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="write nothing; fail when an SVG differs")
    args = parser.parse_args(argv)
    status = 0
    for path, draw in FILES.items():
        data = draw().svg().encode("utf-8")
        if args.check:
            if not path.exists() or path.read_bytes() != data:
                print(f"{path.relative_to(ROOT)} differs from what tools/face_art.py draws", file=sys.stderr)
                status = 1
        else:
            path.write_bytes(data)
            print(f"wrote {path.relative_to(ROOT)}")
    return status


if __name__ == "__main__":
    sys.exit(main())
