#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
# SPDX-License-Identifier: GPL-3.0-or-later
"""The curl staff drawn at 2x detail (ART0, the pilot of the 64x64 redraw; docs/STYLE.md, "The
picture and the art's detail"; art/README.md, "Redrawing a sprite at 64x64").

It draws, from shape rules, the files the game reads (palette colours only; the SVGs rects only, one a
run of a colour along a row, as tests/core/test_svg_art.gd checks; the head sheet a PNG, as an SVG of
its rects would be over the 1 MB limit):

- `content/wizard/staffs/curl/head@2x.png`: the curl's head sheet, 16 directions (clockwise from
  pointing right, each drawn, never rotated, so the light stays top-left and the curl stays on top)
  by 4 player ramps, 96x96 frames, the grip at (48, 54): the 48x48 sheet's layout at two art
  pixels a world pixel.
- the Optimist's face, 32x16 frames: ten eye columns (nine looks, (y + 1) * 3 + x + 1, then the
  blink) and five brow columns (the moods), the left eye's top-left at (2, 2), the brows' at (2, 10):
  drawn into the shared face sheets by tools/face_art.py (the curl's own face until 2026-11-26).
- `art/kit/golden_staff@2x.svg`: the golden example at 2x, the three layered as the game does.

    tools/staff_art.py           # writes the head sheet and the golden example
    tools/staff_art.py --check   # fails when an SVG differs from what the rules draw

Shapes are worked out at each pixel's middle, in world units times DETAIL; a shape's light and
shadow come from its edges facing the top left and the bottom right; every outline is one art
pixel. Standard library only.
"""

from __future__ import annotations

import argparse
import math
import struct
import sys
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FOLDER = ROOT / "content/wizard/staffs/curl"
DETAIL = 2

OUTLINE = "#14121f"
WOOD = ("#3d2a2e", "#7a4a35", "#b27a4a")
SPARK = ("#b8801f", "#f2c230", "#fff3a6")
BONE = ("#a39fb8", "#d4d0e0", "#f4f1ea")
RAMPS = (
    ("#1d3a6b", "#3b73c9", "#7fc0f0"),
    ("#7a2347", "#d9477a", "#f59ab8"),
    ("#1f4a3a", "#3f8f4f", "#8fd46a"),
    ("#4a2a6b", "#8a4fc4", "#c99af0"),
)

# The head sheet (world units; StaffLook's FRAME_SIZE, GRIP).
FRAME = 48
GRIP = (24.0, 27.0)
DIRECTIONS = 16
# The shaft from BUTT behind the grip to SHAFT_END before it; its half thickness.
BUTT = 10.0
SHAFT_END = 10.0
SHAFT_HALF = 1.1
# How far the shaft bows between the grip and the curl, away from the curl (a grown branch, not a rod).
BOW = 0.7
# Gold: the grip's wrap (from, to along the shaft), a band, and the collar under the curl.
WRAPS = ((-2.5, 1.5), (5.0, 6.0))
# The curl: its outer radius, how far it winds (turns) and to what radius, its band's half
# thickness at the start and the end, and the gem's radius.
CURL_RADIUS = 4.4
CURL_TURNS = 1.75
CURL_INNER = 2.6
CURL_HALF = (1.0, 0.5)
GEM_RADIUS = 1.75

# The face (world units: the 16x8 sheets' layout).
EYE_FRAME = (16, 8)
EYE_COLUMNS = 10
BROW_COLUMNS = 5


def _palette_check() -> None:
    style = (ROOT / "docs/STYLE.md").read_text(encoding="utf-8")
    for colour in (OUTLINE, *WOOD, *SPARK, *BONE, *(c for ramp in RAMPS for c in ramp)):
        if colour not in style:
            raise SystemExit(f"{colour} is not in docs/STYLE.md's palette")


# --- drawing helpers -------------------------------------------------------------------------


class Canvas:
    """A picture of palette colours (None: clear), with the part each pixel belongs to."""

    def __init__(self, width: int, height: int) -> None:
        self.width = width
        self.height = height
        self.pixels: list[list[str | None]] = [[None] * width for _ in range(height)]

    def blit(self, other: "Canvas", at_x: int, at_y: int) -> None:
        for y in range(other.height):
            for x in range(other.width):
                if other.pixels[y][x] is not None:
                    self.pixels[at_y + y][at_x + x] = other.pixels[y][x]

    def svg(self) -> str:
        lines = [
            f'<svg xmlns="http://www.w3.org/2000/svg" width="{self.width}" height="{self.height}" '
            f'viewBox="0 0 {self.width} {self.height}" shape-rendering="crispEdges">'
        ]
        for y in range(self.height):
            x = 0
            row = self.pixels[y]
            while x < self.width:
                colour = row[x]
                if colour is None:
                    x += 1
                    continue
                start = x
                while x < self.width and row[x] == colour:
                    x += 1
                lines.append(f'  <rect x="{start}" y="{y}" width="{x - start}" height="1" fill="{colour}"/>')
        lines.append("</svg>")
        return "\n".join(lines) + "\n"

    def png(self) -> bytes:
        """An indexed PNG of the picture (its few palette colours and the clear one), written by hand
        as tools/ground_shape.py writes its: a sheet too big for an SVG of rects under 1 MB."""
        colours: dict[str | None, int] = {None: 0}
        rows = bytearray()
        for row in self.pixels:
            rows.append(0)
            for colour in row:
                if colour not in colours:
                    colours[colour] = len(colours)
                rows.append(colours[colour])
        palette = b"".join(b"\x00\x00\x00" if c is None else bytes.fromhex(c[1:]) for c in colours)
        alpha = bytes(0 if c is None else 255 for c in colours)
        chunks = [
            (b"IHDR", struct.pack(">IIBBBBB", self.width, self.height, 8, 3, 0, 0, 0)),
            (b"PLTE", palette),
            (b"tRNS", alpha),
            (b"IDAT", zlib.compress(bytes(rows), 9)),
            (b"IEND", b""),
        ]
        out = bytearray(b"\x89PNG\r\n\x1a\n")
        for kind, data in chunks:
            out += struct.pack(">I", len(data)) + kind + data
            out += struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
        return bytes(out)


def _shade(parts: list[list[int]], x: int, y: int, size: tuple[int, int]) -> int:
    """0 shadow, 1 base, 2 light for the part pixel (x, y): light where the pixel up or left of it
    is not its part, shadow where the one down or right is not (light wins on a one-pixel line)."""
    part = parts[y][x]

    def other(dx: int, dy: int) -> bool:
        nx, ny = x + dx, y + dy
        return not (0 <= nx < size[0] and 0 <= ny < size[1]) or parts[ny][nx] != part

    if other(-1, 0) or other(0, -1):
        return 2
    if other(1, 0) or other(0, 1):
        return 0
    return 1


def _outline(canvas: Canvas, filled: list[list[bool]]) -> None:
    """Every clear pixel touching a filled one (eight ways, so corners close) becomes the outline."""
    for y in range(canvas.height):
        for x in range(canvas.width):
            if filled[y][x]:
                continue
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < canvas.width and 0 <= ny < canvas.height and filled[ny][nx]:
                        canvas.pixels[y][x] = OUTLINE
                        break
                else:
                    continue
                break


# --- the curl's head ---------------------------------------------------------------------------

SHAFT, WRAP, CURL, GEM = 1, 2, 3, 4


def _curl_frame(direction: int, ramp: int) -> Canvas:
    size = FRAME * DETAIL
    canvas = Canvas(size, size)
    angle = direction * math.tau / DIRECTIONS
    way = (math.cos(angle), math.sin(angle))
    # The curl's side: across the shaft, the one facing up; upright, the left pointing up and the
    # right pointing down (as the 1x sheet).
    across = (way[1], -way[0])
    if across[1] > 1e-6:
        across = (-across[0], -across[1])
    grip = GRIP
    end = (grip[0] + way[0] * SHAFT_END, grip[1] + way[1] * SHAFT_END)
    centre = (end[0] + across[0] * CURL_RADIUS, end[1] + across[1] * CURL_RADIUS)
    # The bow's side: across the shaft, away from the curl.
    away = -1.0 if (-way[1] * across[0] + way[0] * across[1]) > 0.0 else 1.0
    # The spiral starts at the shaft's end, going on along the shaft, and winds into the centre.
    start_angle = math.atan2(end[1] - centre[1], end[0] - centre[0])
    turn = 1.0 if (way[0] * -math.sin(start_angle) + way[1] * math.cos(start_angle)) > 0.0 else -1.0
    steps = 360
    spiral: list[tuple[float, float, float, float]] = []
    for i in range(steps + 1):
        t = i / steps
        phi = start_angle + turn * t * CURL_TURNS * math.tau
        radius = CURL_RADIUS + (CURL_INNER - CURL_RADIUS) * t
        half = CURL_HALF[0] + (CURL_HALF[1] - CURL_HALF[0]) * t
        spiral.append((centre[0] + radius * math.cos(phi), centre[1] + radius * math.sin(phi), half, t))

    parts = [[0] * size for _ in range(size)]
    curl_t = [[-1.0] * size for _ in range(size)]
    for py in range(size):
        for px in range(size):
            wx, wy = (px + 0.5) / DETAIL, (py + 0.5) / DETAIL
            # The gem over everything, then the curl, then the shaft.
            if math.hypot(wx - centre[0], wy - centre[1]) <= GEM_RADIUS:
                parts[py][px] = GEM
                continue
            best, best_t = 1e9, -1.0
            near_curl = math.hypot(wx - centre[0], wy - centre[1]) <= CURL_RADIUS + CURL_HALF[0] + 0.5
            for sx, sy, half, t in (spiral if near_curl else ()):
                gap = math.hypot(wx - sx, wy - sy) - half
                if gap < best:
                    best, best_t = gap, t
            if best <= 0.0:
                parts[py][px] = CURL
                curl_t[py][px] = best_t
                continue
            rx, ry = wx - grip[0], wy - grip[1]
            along = rx * way[0] + ry * way[1]
            side = -rx * way[1] + ry * way[0]
            if 0.0 < along < SHAFT_END:
                side -= away * BOW * math.sin(math.pi * along / SHAFT_END)
            off = abs(side)
            if -BUTT <= along <= SHAFT_END + 0.4 and off <= SHAFT_HALF:
                parts[py][px] = WRAP if any(a <= along <= b for a, b in WRAPS) else SHAFT
    filled = [[parts[y][x] != 0 for x in range(size)] for y in range(size)]
    # The wood (shaft and curl) shades as one piece; the wraps and the gem each as their own.
    wood = [[(SHAFT if parts[y][x] in (SHAFT, CURL) else parts[y][x]) for x in range(size)] for y in range(size)]
    for py in range(size):
        for px in range(size):
            part = parts[py][px]
            if part == 0:
                continue
            # A curl pixel beside one of another turn (or of the shaft past its start): the dark
            # line between the turns.
            if part == CURL:
                t = curl_t[py][px]
                # The inner turn (the later along the spiral) takes the line.
                seam = False
                for dx, dy in ((1, 0), (0, 1), (-1, 0), (0, -1)):
                    nx, ny = px + dx, py + dy
                    if 0 <= nx < size and 0 <= ny < size and parts[ny][nx] == CURL and t - curl_t[ny][nx] > 0.3:
                        seam = True
                if seam:
                    canvas.pixels[py][px] = OUTLINE
                    continue
            if part == GEM:
                # A bright gem: the light shade, its bottom-right edge the base.
                shade = _shade(parts, px, py, (size, size))
                canvas.pixels[py][px] = RAMPS[ramp][1 if shade == 0 else 2]
                continue
            shade = _shade(wood, px, py, (size, size))
            canvas.pixels[py][px] = (SPARK if part == WRAP else WOOD)[shade]
    # The gem's glint: Bone light at its top left, and its rim dark against the curl.
    gx = int(centre[0] * DETAIL - GEM_RADIUS * DETAIL * 0.45)
    gy = int(centre[1] * DETAIL - GEM_RADIUS * DETAIL * 0.45)
    for dx, dy in ((0, 0), (1, 0), (0, 1)):
        if 0 <= gx + dx < size and 0 <= gy + dy < size and parts[gy + dy][gx + dx] == GEM:
            canvas.pixels[gy + dy][gx + dx] = BONE[2]
    for py in range(size):
        for px in range(size):
            if parts[py][px] == CURL:
                for dx, dy in ((1, 0), (0, 1), (-1, 0), (0, -1)):
                    nx, ny = px + dx, py + dy
                    if 0 <= nx < size and 0 <= ny < size and parts[ny][nx] == GEM:
                        canvas.pixels[py][px] = OUTLINE
    _outline(canvas, filled)
    return canvas


def curl_head() -> Canvas:
    size = FRAME * DETAIL
    sheet = Canvas(size * DIRECTIONS, size * len(RAMPS))
    for ramp in range(len(RAMPS)):
        for direction in range(DIRECTIONS):
            sheet.blit(_curl_frame(direction, ramp), direction * size, ramp * size)
    return sheet


# --- the Optimist's face ---------------------------------------------------------------------

# One eye, in art pixels of its 10 x 14 box: an oval whose rim is the outline.
EYE_BOX = (10, 14)
# The pupil's middle at rest, and how far a look moves it (art pixels), its radius.
PUPIL_AT = (5.5, 6.5)
PUPIL_STEP = (2.0, 2.0)
PUPIL_RADIUS = 2.3


def _eye(look: tuple[int, int]) -> list[list[str | None]]:
    w, h = EYE_BOX
    cx, cy = w / 2.0, h / 2.0
    rx, ry = w / 2.0 - 0.2, h / 2.0 - 0.2
    inside = [[((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2 <= 1.0 for x in range(w)] for y in range(h)]
    out: list[list[str | None]] = [[None] * w for _ in range(h)]
    # The rim: inside pixels with a neighbour outside (four ways) are the outline.
    for y in range(h):
        for x in range(w):
            if not inside[y][x]:
                continue
            rim = any(not (0 <= x + dx < w and 0 <= y + dy < h) or not inside[y + dy][x + dx] for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
            out[y][x] = OUTLINE if rim else BONE[2]
    # The white shaded to the bottom right: a pixel whose bottom-right neighbour two away is the rim.
    for y in range(h):
        for x in range(w):
            if out[y][x] == BONE[2]:
                nx, ny = x + 1, y + 1
                if out[ny][nx] == OUTLINE or (out[min(y + 2, h - 1)][x] == OUTLINE and out[y][min(x + 2, w - 1)] == OUTLINE):
                    out[y][x] = BONE[1]
    # The pupil: a round dark dot, moved by the look, with a Bone light glint at its top left.
    px = PUPIL_AT[0] + look[0] * PUPIL_STEP[0]
    py = PUPIL_AT[1] + look[1] * PUPIL_STEP[1]
    for y in range(h):
        for x in range(w):
            if out[y][x] in BONE and math.hypot(x + 0.5 - px, y + 0.5 - py) <= PUPIL_RADIUS:
                out[y][x] = OUTLINE
    gx, gy = int(px - 1.2), int(py - 1.2)
    if 0 <= gx < w and 0 <= gy < h and out[gy][gx] == OUTLINE and inside[gy][gx]:
        out[gy][gx] = BONE[2]
    return out


def _blink() -> list[list[str | None]]:
    w, h = EYE_BOX
    out: list[list[str | None]] = [[None] * w for _ in range(h)]
    # A closed, smiling lid: a line low in the eye, its ends a pixel up.
    for x in range(1, w - 1):
        out[7][x] = OUTLINE
    out[6][1] = OUTLINE
    out[6][w - 2] = OUTLINE
    out[7][1] = None
    out[7][w - 2] = None
    return out


def cheer_eyes() -> Canvas:
    fw, fh = EYE_FRAME[0] * DETAIL, EYE_FRAME[1] * DETAIL
    sheet = Canvas(fw * EYE_COLUMNS, fh)
    origin = (1 * DETAIL, 1 * DETAIL)
    for column in range(EYE_COLUMNS):
        if column == EYE_COLUMNS - 1:
            eye = _blink()
        else:
            look = (column % 3 - 1, column // 3 - 1)
            eye = _eye(look)
        for side in range(2):
            ox = column * fw + origin[0] - DETAIL // 2 + side * EYE_BOX[0]
            oy = origin[1] - DETAIL // 2
            for y in range(EYE_BOX[1]):
                for x in range(EYE_BOX[0]):
                    if eye[y][x] is not None:
                        sheet.pixels[oy + y][ox + x] = eye[y][x]
    return sheet


# The brows (art pixels from a brow's left end: points along it, left brow; the right is mirrored),
# a column a mood: neutral, raised, angry, furious, worried.
BROW_LENGTH = 8
BROW_ROWS = {
    0: [4, 4, 4, 4, 4, 4, 4, 4],
    1: [2, 2, 2, 2, 2, 2, 2, 2],
    2: [2, 2, 3, 3, 4, 4, 5, 5],
    3: [0, 1, 2, 3, 4, 5, 6, 6],
    4: [5, 5, 4, 4, 3, 3, 2, 2],
}


def brows() -> Canvas:
    fw, fh = EYE_FRAME[0] * DETAIL, EYE_FRAME[1] * DETAIL
    sheet = Canvas(fw * BROW_COLUMNS, fh)
    left = 1 * DETAIL
    for mood, rows in BROW_ROWS.items():
        for side in range(2):
            for i, top in enumerate(rows):
                x = mood * fw + left + (i if side == 0 else EYE_BOX[0] * 2 - 1 - i - DETAIL)
                # Two pixels thick, the ends one.
                thick = 1 if i in (0, BROW_LENGTH - 1) else 2
                for dy in range(thick):
                    sheet.pixels[top + dy + (1 if thick == 1 and i == 0 else 0)][x] = OUTLINE
    return sheet


def golden() -> Canvas:
    """The golden example at 2x (art/kit/golden_staff@2x.svg): frame 14 of the player 1 row (pointing
    up and to the right, 45 degrees) with the eyes looking up-right and the neutral brows over it, the eyes'
    anchor 8 world px above the grip and 5 left of it, as the game layers them."""
    size = FRAME * DETAIL
    out = _curl_frame(14, 0)
    fw, fh = EYE_FRAME[0] * DETAIL, EYE_FRAME[1] * DETAIL
    anchor = (int((GRIP[0] - 5) * DETAIL), int((GRIP[1] - 8) * DETAIL))
    for sheet, column, origin in ((cheer_eyes(), 2, (2, 2)), (brows(), 0, (2, 10))):
        for y in range(fh):
            for x in range(fw):
                colour = sheet.pixels[y][column * fw + x]
                tx, ty = anchor[0] - origin[0] + x, anchor[1] - origin[1] + y
                if colour is not None and 0 <= tx < size and 0 <= ty < size:
                    out.pixels[ty][tx] = colour
    return out


FILES = {
    FOLDER / "head@2x.png": curl_head,
    ROOT / "art/kit/golden_staff@2x.svg": golden,
}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="write nothing; fail when an SVG differs")
    args = parser.parse_args(argv)
    _palette_check()
    status = 0
    for path, draw in FILES.items():
        picture = draw()
        data = picture.png() if path.suffix == ".png" else picture.svg().encode("utf-8")
        if args.check:
            if not path.exists() or path.read_bytes() != data:
                print(f"{path.relative_to(ROOT)} differs from what tools/staff_art.py draws", file=sys.stderr)
                status = 1
        else:
            path.write_bytes(data)
            print(f"wrote {path.relative_to(ROOT)}")
    return status


if __name__ == "__main__":
    sys.exit(main())
