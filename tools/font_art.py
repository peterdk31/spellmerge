#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
# SPDX-License-Identifier: GPL-3.0-or-later
"""The game's text font, drawn from glyph parts (ART4 part 4, 2026-11-27).

An original pixel face: every glyph is a short list of parts (a stem, a bar, a round bowl, a
diagonal, a dot) placed on a face's guides (baseline, x-height, cap height, ascender, descender)
and its stroke, so one drawing of the alphabet gives a face at every size, each drawn at art-pixel
detail (two art pixels a layout pixel: docs/STYLE.md, "The picture and the art's detail"). No
existing font is copied or traced; the parts and the guides are this file's.

It writes two files (both are read by `core/display/pixel_font.gd`, which makes the FontFile the
game draws all its text with):

- `art/ui/fonts/text.png`: the glyph sheet. Each face is a band of three rows: the glyphs, their
  one-art-pixel outline (the glyph grown by a pixel round, the owner's rule of 2026-11-27: text sits
  on the game with a one-art-pixel dark outline), and that outline with a hard shadow a pixel down
  and right (for the heavier outline sizes). White on transparent; the game tints it.
- `art/ui/fonts/text.json`: where each face and glyph is on the sheet, and its metrics.

    tools/font_art.py            # writes both
    tools/font_art.py --check    # fails if either differs from what the parts draw
    tools/font_art.py --preview out.png   # a big preview of every face (outside the repository)
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT_PNG = ROOT / "art/ui/fonts/text.png"
OUT_JSON = ROOT / "art/ui/fonts/text.json"

## The face sizes drawn (font sizes in layout pixels; a face of size s is 2s art pixels an em).
## A size between two is drawn by the face below it, a size past the last by a face scaled by a
## whole number (`core/display/pixel_font.gd`).
FACES = [6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 18, 20, 24, 32, 40, 48]
## Art pixels a layout pixel.
DETAIL = 2
## Room round a glyph in its cell: the outline's pixel and the shadow's.
PAD = 2
SHEET_WIDTH = 1024

## The characters drawn: printable ASCII and the few others the game writes (GlyphWarmup.EXTRA).
CHARS = "".join(chr(c) for c in range(32, 127)) + "×·•–—…∞°"


class Face:
    """A face's guides and widths in art pixels, from its size."""

    def __init__(self, size: int) -> None:
        self.size = size
        self.cap = round(1.4 * size)
        self.xh = round(self.cap * 0.72)
        self.t = max(2, round(size / 5.5)) if size >= 8 else max(1, round(size / 4.5))
        self.asc = self.cap + max(1, round(size / 8))
        self.desc = max(2, round(self.cap * 0.36))
        self.wc = round(self.cap * 0.64)
        self.wn = round(self.xh * 0.85)
        self.ww = self.wn * 2 - self.t
        self.wW = self.wc * 2 - self.t
        self.gap = self.t
        # A round corner's cut: a pixel at the smallest sizes, the stroke above.
        self.k = self.t if size >= 8 else 1

    def env(self, width: int) -> dict[str, int]:
        t = self.t
        return {
            "t": t, "W": width, "R": width - t, "C": (width - t) // 2,
            "x": self.xh, "c": self.cap, "a": self.asc, "d": self.desc,
            "mc": (self.cap + t) // 2, "mx": (self.xh + t) // 2,
            "g": max(1, t // 2), "k": self.k,
            "wn": self.wn, "wc": self.wc, "ww": self.ww, "wW": self.wW,
        }


# Each glyph: its width (an expression of the face's names) and its parts. A part's numbers are
# expressions too: x in art pixel columns from the glyph's left (W its width, R its right stem's
# column, C its centre stem's), y in art pixel rows up from the baseline (x the x-height, c the cap
# height, a the ascender, -d the descender's foot, mc and mx a middle bar's top).
#
#   ("V", x, y0, y1)              a stem t wide: columns [x, x+t), rows [y0, y1)
#   ("H", x0, x1, top)            a bar t high: columns [x0, x1), rows [top-t, top)
#   ("O", x0, x1, y0, y1, sides)  a round box's sides (some of "tblr") t thick in [x0,x1)x[y0,y1),
#                                 each corner of two sides drawn cut round by k
#   ("D", x0, y0, x1, y1)         a diagonal t wide from column x0 at row y0 to x1 at y1
#   ("P", x, top)                 a dot t square: columns [x, x+t), rows [top-t, top)
#   ("B", x0, x1, y0, y1)         a block: columns [x0, x1), rows [y0, y1)
#   ("X", x0, x1, y0, y1)         clear a block (a cut)
G: dict[str, tuple[str, list[tuple]]] = {
    " ": ("max(1, x * 3 // 10)", []),
    "!": ("t", [("V", 0, "t + g", "c"), ("P", 0, "t")]),
    '"': ("t * 2 + g", [("V", 0, "c - c // 3", "c"), ("V", "W - t", "c - c // 3", "c")]),
    "#": ("wc", [("V", "t // 2 + 1", 0, "c - 1"), ("V", "W - t - t // 2 - 1", 0, "c - 1"),
                 ("H", 0, "W", "mc + t + g"), ("H", 0, "W", "mc - t - g + t")]),
    "$": ("wc", [("O", 0, "W", "mc - t", "c - 1", "tlb"), ("O", 0, "W", 1, "mc", "trb"),
                 ("B", "R", "W", "c - 1 - t - g", "c - 1 - t"), ("B", 0, "t", "1 + t", "1 + t + g"),
                 ("V", "C", -1, "c")]),
    "%": ("wc", [("O", 0, "t * 2 + 1", "c - t * 2 - 1", "c", "tblr"),
                 ("O", "W - t * 2 - 1", "W", 0, "t * 2 + 1", "tblr"), ("D", "R", "c - 1", 0, 0)]),
    "&": ("wc + 1", [("O", 0, "W - t - 1", "mc - t", "c", "tlr"), ("O", 0, "W - 1", 0, "mc", "tlb"),
                     ("D", "t", "mc - 1", "R", 0), ("B", "R", "W", "t", "mc")]),
    "'": ("t", [("V", 0, "c - c // 3", "c")]),
    "(": ("t * 2", [("O", 0, "W * 3", "-d + 1", "a", "tlb")]),
    ")": ("t * 2", [("O", "-W * 2", "W", "-d + 1", "a", "trb")]),
    "*": ("wn", [("V", "C", "c - wn + 1", "c"), ("D", 0, "c - 1 - t // 2", "R", "c - wn + 1 + t // 2"),
                 ("D", "R", "c - 1 - t // 2", 0, "c - wn + 1 + t // 2")]),
    "+": ("wn", [("H", 0, "W", "mx"), ("V", "C", "mx - t - C", "mx + C")]),
    ",": ("t", [("V", 0, "-max(1, d - 1)", "t")]),
    "-": ("wn - 1", [("H", 0, "W", "mx")]),
    ".": ("t", [("P", 0, "t")]),
    "/": ("wn", [("D", "R", "a - 1", 0, "-d + 1")]),
    "0": ("wc", [("O", 0, "W", 0, "c", "tblr"), ("P", "C", "mc")]),
    "1": ("wc", [("V", "C", 0, "c"), ("P", "C - t", "c - t // 2"), ("H", "C - t", "C + t * 2", "t")]),
    "2": ("wc", [("O", 0, "W", "mc - t", "c", "tr"), ("B", 0, "t", "c - t - g", "c - t"),
                 ("D", "R", "mc - 1", 0, "t"), ("H", 0, "W", "t"), ("H", "t // 2", "W - t", "c")]),
    "3": ("wc", [("O", 0, "W", 0, "c", "trb"), ("H", "C", "R", "mc"), ("B", 0, "t", "t", "t + g"),
                 ("B", 0, "t", "c - t - g", "c - t")]),
    "4": ("wc", [("V", 0, "c // 3", "c"), ("H", 0, "W", "c // 3 + t"), ("V", "R - 1", 0, "mc + t")]),
    "5": ("wc", [("H", 0, "W", "c"), ("V", 0, "mc - t", "c"), ("O", 0, "W", 0, "mc", "trb"),
                 ("B", 0, "t", "t", "t + g")]),
    "6": ("wc", [("O", 0, "W", 0, "c", "tlb"), ("O", 0, "W", 0, "mc + 1", "tblr"),
                 ("B", "R", "W", "c - t - g", "c - t")]),
    "7": ("wc", [("H", 0, "W", "c"), ("D", "R", "c - t", "C - t // 2", 0)]),
    "8": ("wc", [("O", "t // 2", "W - t // 2", "mc - t", "c", "tblr"), ("O", 0, "W", 0, "mc", "tblr")]),
    "9": ("wc", [("O", 0, "W", "mc - t - 1", "c", "tblr"), ("O", 0, "W", 0, "c", "trb"),
                 ("B", 0, "t", "t", "t + g")]),
    ":": ("t", [("P", 0, "t"), ("P", 0, "x")]),
    ";": ("t", [("V", 0, "-max(1, d - 1)", "t"), ("P", 0, "x")]),
    "<": ("wn", [("D", "R", "x - 1", 0, "mx - t // 2 - 1"), ("D", 0, "mx - t // 2 - 1", "R", 0)]),
    "=": ("wn", [("H", 0, "W", "mx + t // 2 + g + t - t // 2"), ("H", 0, "W", "mx - t // 2 - g + t // 2")]),
    ">": ("wn", [("D", 0, "x - 1", "R", "mx - t // 2 - 1"), ("D", "R", "mx - t // 2 - 1", 0, 0)]),
    "?": ("wc", [("O", 0, "W", "mc - t", "c", "tr"), ("B", 0, "t", "c - t - g", "c - t"),
                 ("H", "C", "R", "mc"), ("V", "C", "t + g", "mc"), ("P", "C", "t")]),
    "@": ("wW", [("O", 0, "W", "-t - 1", "c", "tblr"), ("O", "t + 1", "W - t - 1", 1, "x", "tbl"),
                 ("V", "W - t * 2 - 1", 1, "x"), ("B", "W - t * 2 - 1", "W", "-t - 1", "1")]),
    "A": ("wc", [("O", 0, "W", 0, "c", "tlr"), ("H", 0, "W", "mc")]),
    "B": ("wc", [("V", 0, 0, "c"), ("O", 0, "W - 1", "mc - t", "c", "trb"), ("O", 0, "W", 0, "mc", "trb")]),
    "C": ("wc", [("O", 0, "W", 0, "c", "tlb")]),
    "D": ("wc", [("V", 0, 0, "c"), ("O", 0, "W", 0, "c", "trb")]),
    "E": ("wc - 1", [("V", 0, 0, "c"), ("H", 0, "W", "c"), ("H", 0, "W - 1", "mc"), ("H", 0, "W", "t")]),
    "F": ("wc - 1", [("V", 0, 0, "c"), ("H", 0, "W", "c"), ("H", 0, "W - 1", "mc")]),
    "G": ("wc", [("O", 0, "W", 0, "c", "tlb"), ("V", "R", 0, "mc"), ("H", "C", "W", "mc")]),
    "H": ("wc", [("V", 0, 0, "c"), ("V", "R", 0, "c"), ("H", 0, "W", "mc")]),
    "I": ("t * 3", [("H", 0, "W", "c"), ("H", 0, "W", "t"), ("V", "t", 0, "c")]),
    "J": ("wc - 1", [("O", 0, "W", 0, "c", "rb"), ("O", 0, "W", 0, "mc - t", "lb")]),
    "K": ("wc", [("V", 0, 0, "c"), ("D", "R", "c - 1", "t - 1", "mc - 1"), ("D", "t", "mc - 1", "R", 0)]),
    "L": ("wc - 1", [("V", 0, 0, "c"), ("H", 0, "W", "t")]),
    "M": ("wW", [("V", 0, 0, "c"), ("V", "R", 0, "c"), ("D", "t - 1", "c - 1", "C", "mc - t"),
                 ("D", "R - t + 1", "c - 1", "C", "mc - t")]),
    "N": ("wc + 1", [("V", 0, 0, "c"), ("V", "R", 0, "c"), ("D", "t - 1", "c - 1", "R - t + 1", 0)]),
    "O": ("wc + 1", [("O", 0, "W", 0, "c", "tblr")]),
    "P": ("wc", [("V", 0, 0, "c"), ("O", 0, "W", "mc - t", "c", "trb")]),
    "Q": ("wc + 1", [("O", 0, "W", 0, "c", "tblr"), ("D", "C", "t + t", "W - t", "-t + 1")]),
    "R": ("wc", [("V", 0, 0, "c"), ("O", 0, "W", "mc - t", "c", "trb"), ("D", "C", "mc - t - 1", "R", 0)]),
    "S": ("wc", [("O", 0, "W", "mc - t", "c", "tlb"), ("O", 0, "W", 0, "mc", "trb"),
                 ("B", "R", "W", "c - t - g", "c - t"), ("B", 0, "t", "t", "t + g")]),
    "T": ("wc", [("H", 0, "W", "c"), ("V", "C", 0, "c")]),
    "U": ("wc", [("O", 0, "W", 0, "c", "lrb")]),
    "V": ("wc", [("V", 0, "mc", "c"), ("V", "R", "mc", "c"), ("D", 0, "mc", "C", 0), ("D", "R", "mc", "C", 0)]),
    "W": ("wW", [("O", 0, "C + t", 0, "c", "lb"), ("O", "C", "W", 0, "c", "rb"), ("V", "C", 0, "mc + t")]),
    "X": ("wc", [("D", 0, "c - 1", "R", 0), ("D", "R", "c - 1", 0, 0)]),
    "Y": ("wc", [("D", 0, "c - 1", "C", "mc - 1"), ("D", "R", "c - 1", "C", "mc - 1"), ("V", "C", 0, "mc")]),
    "Z": ("wc", [("H", 0, "W", "c"), ("H", 0, "W", "t"), ("D", "R", "c - t - 1", 0, "t")]),
    "[": ("t * 2", [("V", 0, "-d + 1", "a"), ("H", 0, "W", "a"), ("H", 0, "W", "-d + 1 + t")]),
    "\\": ("wn", [("D", 0, "a - 1", "R", "-d + 1")]),
    "]": ("t * 2", [("V", "R", "-d + 1", "a"), ("H", 0, "W", "a"), ("H", 0, "W", "-d + 1 + t")]),
    "^": ("wn", [("D", 0, "c - wn // 2 - 1", "C", "c - 1"), ("D", "R", "c - wn // 2 - 1", "C", "c - 1")]),
    "_": ("wn", [("H", 0, "W", "-d + 1 + t")]),
    "`": ("t + 1", [("D", 0, "a - 1", 1, "a - t")]),
    "a": ("wn", [("O", 0, "W", 0, "x", "tr"), ("O", 0, "W", 0, "mx", "tlb")]),
    "b": ("wn", [("V", 0, 0, "a"), ("O", 0, "W", 0, "x", "trb")]),
    "c": ("wn", [("O", 0, "W", 0, "x", "tlb")]),
    "d": ("wn", [("V", "R", 0, "a"), ("O", 0, "W", 0, "x", "tlb")]),
    "e": ("wn", [("O", 0, "W", "mx - t", "x", "tblr"), ("O", 0, "W", 0, "mx", "lb")]),
    "f": ("t * 2 + 1", [("O", 1, "W + t", 0, "a", "tl"), ("H", 0, "W", "x")]),
    "g": ("wn", [("O", 0, "W", 0, "x", "tlb"), ("O", 0, "W", "-d", "x", "trb")]),
    "h": ("wn", [("V", 0, 0, "a"), ("O", 0, "W", 0, "x", "tr")]),
    "i": ("t", [("V", 0, 0, "x"), ("P", 0, "a")]),
    "j": ("t * 2", [("O", "-t", "W", "-d", "x", "rb"), ("P", "R", "a")]),
    "k": ("wn", [("V", 0, 0, "a"), ("D", "R", "x - 1", "t - 1", "mx - 1"), ("D", "t", "mx - 1", "R", 0)]),
    "l": ("t", [("V", 0, 0, "a")]),
    "m": ("ww", [("V", 0, 0, "x"), ("O", 0, "C + t", 0, "x", "tr"), ("O", "C", "W", 0, "x", "tr")]),
    "n": ("wn", [("V", 0, 0, "x"), ("O", 0, "W", 0, "x", "tr")]),
    "o": ("wn", [("O", 0, "W", 0, "x", "tblr")]),
    "p": ("wn", [("V", 0, "-d", "x"), ("O", 0, "W", 0, "x", "trb")]),
    "q": ("wn", [("V", "R", "-d", "x"), ("O", 0, "W", 0, "x", "tlb")]),
    "r": ("wn - 1", [("V", 0, 0, "x"), ("O", 0, "W", "x - t - g", "x", "tr")]),
    "s": ("wn", [("O", 0, "W", "mx - t", "x", "tlb"), ("O", 0, "W", 0, "mx", "trb")]),
    "t": ("t * 2 + 1", [("O", 1, "W + t", 0, "a - t", "lb"), ("H", 0, "W", "x")]),
    "u": ("wn", [("O", 0, "W", 0, "x", "lb"), ("V", "R", 0, "x")]),
    "v": ("wn", [("V", 0, "mx", "x"), ("V", "R", "mx", "x"), ("D", 0, "mx", "C", 0), ("D", "R", "mx", "C", 0)]),
    "w": ("ww", [("O", 0, "C + t", 0, "x", "lb"), ("O", "C", "W", 0, "x", "rb"), ("V", "C", 0, "mx + 1")]),
    "x": ("wn", [("D", 0, "x - 1", "R", 0), ("D", "R", "x - 1", 0, 0)]),
    "y": ("wn", [("O", 0, "W", 0, "x", "lb"), ("O", 0, "W", "-d", "x", "rb")]),
    "z": ("wn", [("H", 0, "W", "x"), ("H", 0, "W", "t"), ("D", "R", "x - t - 1", 0, "t")]),
    "{": ("t * 2 + 1", [("O", 1, "W + t", "-d + 1", "mx", "lb"), ("O", 1, "W + t", "mx", "a", "lt"),
                        ("B", 0, 1, "mx - t // 2 - 1", "mx - t // 2 + t - 1")]),
    "|": ("t", [("V", 0, "-d + 1", "a")]),
    "}": ("t * 2 + 1", [("O", "-t", "W - 1", "-d + 1", "mx", "rb"), ("O", "-t", "W - 1", "mx", "a", "rt"),
                        ("B", "W - 1", "W", "mx - t // 2 - 1", "mx - t // 2 + t - 1")]),
    "~": ("wn", [("B", 0, "t", "mx - t + 1", "mx + 1"), ("B", "t", "C + t", "mx", "mx + t"),
                 ("B", "C", "R", "mx - t", "mx"), ("B", "R", "W", "mx - t + 1", "mx + 1")]),
    "×": ("wn", [("D", 0, "mx + C", "R", "mx - C - t + t // 2"), ("D", "R", "mx + C", 0, "mx - C - t + t // 2")]),
    "·": ("t", [("P", 0, "mx")]),
    "•": ("t * 2", [("B", 0, "W", "mx - t", "mx + t")]),
    "–": ("wn", [("H", 0, "W", "mx")]),
    "—": ("wn * 2", [("H", 0, "W", "mx")]),
    "…": ("t * 3 + g * 2 + 2", [("P", 0, "t"), ("P", "C", "t"), ("P", "R", "t")]),
    "∞": ("ww", [("O", 0, "C + t", 0, "x", "tblr"), ("O", "C", "W", 0, "x", "tblr")]),
    "°": ("t * 2 + 1 + t // 2 * 2", [("O", 0, "W", "c - W", "c", "tblr")]),
}


def _eval(expr: object, env: dict[str, int]) -> int:
    if isinstance(expr, int):
        return expr
    return int(eval(str(expr), {"__builtins__": {"max": max, "min": min}}, env))  # noqa: S307 (our own strings)


class Canvas:
    """A glyph's pixels, rows up from the baseline."""

    def __init__(self, width: int, top: int, bottom: int) -> None:
        self.width = width
        self.top = top  # the first row above the cell (exclusive)
        self.bottom = bottom  # the lowest row (inclusive, negative below the baseline)
        self.on: set[tuple[int, int]] = set()

    def put(self, x: int, y: int) -> None:
        if 0 <= x < self.width and self.bottom <= y < self.top:
            self.on.add((x, y))

    def block(self, x0: int, x1: int, y0: int, y1: int) -> None:
        for y in range(y0, y1):
            for x in range(x0, x1):
                self.put(x, y)

    def clear(self, x0: int, x1: int, y0: int, y1: int) -> None:
        self.on -= {(x, y) for y in range(y0, y1) for x in range(x0, x1)}


def _box(cv: Canvas, x0: int, x1: int, y0: int, y1: int, sides: str, t: int, k: int) -> None:
    """A round box's sides: each corner where two sides drawn meet is cut by k."""
    pixels: set[tuple[int, int]] = set()
    if "t" in sides:
        pixels |= {(x, y) for x in range(x0, x1) for y in range(y1 - t, y1)}
    if "b" in sides:
        pixels |= {(x, y) for x in range(x0, x1) for y in range(y0, y0 + t)}
    if "l" in sides:
        pixels |= {(x, y) for x in range(x0, x0 + t) for y in range(y0, y1)}
    if "r" in sides:
        pixels |= {(x, y) for x in range(x1 - t, x1) for y in range(y0, y1)}
    corners = [("tl", x0, y1 - 1, 1, -1), ("tr", x1 - 1, y1 - 1, -1, -1),
               ("bl", x0, y0, 1, 1), ("br", x1 - 1, y0, -1, 1)]
    for name, cx, cy, sx, sy in corners:
        if name[0] in sides and name[1] in sides:
            for i in range(k):
                for j in range(k - i):
                    pixels.discard((cx + sx * i, cy + sy * j))
    for p in pixels:
        cv.put(*p)


def _diagonal(cv: Canvas, x0: int, y0: int, x1: int, y1: int, t: int) -> None:
    """A stroke t wide from column x0 at row y0 to column x1 at row y1, joined row to row."""
    rows = abs(y1 - y0) + 1
    step = 1 if y1 >= y0 else -1
    for i in range(rows):
        f = i / (rows - 1) if rows > 1 else 0.0
        g = (i + 1) / (rows - 1) if rows > 1 else 0.0
        xa = x0 + (x1 - x0) * f
        xb = x0 + (x1 - x0) * min(g, 1.0)
        lo = round(min(xa, (xa + xb) / 2))
        hi = round(max(xa, (xa + xb) / 2))
        for x in range(lo, hi + t):
            cv.put(x, y0 + step * i)


def draw(face: Face, ch: str) -> Canvas:
    width_expr, parts = G[ch]
    width = _eval(width_expr, face.env(0) | {"W": 0})
    env = face.env(width)
    cv = Canvas(width, face.asc, -face.desc)
    t = face.t
    for part in parts:
        kind, *args = part
        if kind == "O":
            sides = args[4]
            v = [_eval(a, env) for a in args[:4]]
            _box(cv, v[0], v[1], v[2], v[3], sides, t, face.k)
            continue
        v = [_eval(a, env) for a in args]
        if kind == "V":
            cv.block(v[0], v[0] + t, v[1], v[2])
        elif kind == "H":
            cv.block(v[0], v[1], v[2] - t, v[2])
        elif kind == "D":
            _diagonal(cv, v[0], v[1], v[2], v[3], t)
        elif kind == "P":
            cv.block(v[0], v[0] + t, v[1] - t, v[1])
        elif kind == "B":
            cv.block(v[0], v[1], v[2], v[3])
        elif kind == "X":
            cv.clear(v[0], v[1], v[2], v[3])
        else:
            raise ValueError(f"{ch!r}: no part {kind!r}")
    return cv


def _grow(on: set[tuple[int, int]], shadow: bool) -> set[tuple[int, int]]:
    """The glyph grown by a pixel round (its outline), and with a pixel's hard shadow down-right."""
    out = set(on)
    for x, y in on:
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                out.add((x + dx, y + dy))
    if shadow:
        out |= {(x + 1, y - 1) for x, y in out}
    return out


def build() -> tuple[list[list[int]], dict]:
    """The sheet's pixels (rows of 0/1) and its metrics."""
    placed: list[tuple[int, int, set[tuple[int, int]], int]] = []  # x, y(top), pixels, ... per draw
    meta: dict = {"detail": DETAIL, "pad": PAD, "chars": CHARS, "faces": [],
                  "glyph": "each glyph, in the order of chars: [x, y in its face's band, cell width, width]"}
    y = 0
    for size in FACES:
        face = Face(size)
        cell_h = face.asc + face.desc + PAD * 2
        glyphs: list[list[int]] = []
        x = 0
        band_y = y
        for ch in CHARS:
            cv = draw(face, ch)
            cell_w = cv.width + PAD * 2
            if x + cell_w > SHEET_WIDTH:
                x = 0
                band_y += cell_h * 3
            for row, pixels in enumerate((cv.on, _grow(cv.on, False), _grow(cv.on, True))):
                top = band_y + row * cell_h
                placed.append((x, top, pixels, face.asc))
            glyphs.append([x, band_y - y, cell_w, cv.width])
            x += cell_w
        meta["faces"].append({
            "size": size, "ascent": face.asc, "descent": face.desc, "cap": face.cap,
            "x_height": face.xh, "stroke": face.t, "gap": face.gap, "cell_height": cell_h,
            "top": y, "height": band_y + cell_h * 3 - y, "glyphs": glyphs,
        })
        y = band_y + cell_h * 3
    height = y
    rows = [[0] * SHEET_WIDTH for _ in range(height)]
    for x, top, pixels, asc in placed:
        for px, py in pixels:
            # Row asc-1 is the cell's first row under the pad; the baseline row 0 is asc-1 down.
            rx = x + PAD + px
            ry = top + PAD + (asc - 1 - py)
            rows[ry][rx] = 1
    return rows, meta


def png(rows: list[list[int]]) -> bytes:
    """A grey-and-alpha PNG: white where a pixel is on, clear elsewhere."""
    height = len(rows)
    width = len(rows[0])
    raw = bytearray()
    for row in rows:
        raw.append(0)
        for v in row:
            raw += b"\xff\xff" if v else b"\xff\x00"

    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", width, height, 8, 4, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b"")


def metrics_json(meta: dict) -> str:
    """The metrics, a face a line."""
    head = {k: v for k, v in meta.items() if k != "faces"}
    lines = [json.dumps(face, ensure_ascii=False, sort_keys=True, separators=(",", ":")) for face in meta["faces"]]
    body = json.dumps(head, ensure_ascii=False, sort_keys=True, indent=1)[:-2]
    return body + ',\n "faces": [\n  ' + ",\n  ".join(lines) + "\n ]\n}\n"


def preview(rows: list[list[int]], scale: int) -> bytes:
    """The sheet on a dark ground, each pixel `scale` square, glyph white and outline grey."""
    big = []
    for row in rows:
        line = []
        for v in row:
            line += [v] * scale
        for _ in range(scale):
            big.append(line)
    height = len(big)
    width = len(big[0])
    raw = bytearray()
    for row in big:
        raw.append(0)
        for v in row:
            raw += b"\xf4\xf1\xea" if v else b"\x14\x12\x1f"

    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b"")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="fail if the files differ from the parts")
    parser.add_argument("--preview", type=Path, help="write a big preview PNG here instead")
    parser.add_argument("--rows", type=int, default=0, help="the preview's first N sheet rows only")
    args = parser.parse_args(argv)
    rows, meta = build()
    if args.preview:
        cut = rows[: args.rows] if args.rows else rows
        args.preview.write_bytes(preview(cut, 3))
        return 0
    image = png(rows)
    text = metrics_json(meta)
    if args.check:
        stale = [p for p, want in ((OUT_PNG, image), (OUT_JSON, text.encode("utf-8")))
                 if not p.exists() or p.read_bytes() != want]
        for p in stale:
            print(f"{p.relative_to(ROOT)}: out of date; run tools/font_art.py", file=sys.stderr)
        return 1 if stale else 0
    OUT_PNG.write_bytes(image)
    OUT_JSON.write_text(text, encoding="utf-8")
    print(f"wrote {OUT_PNG.relative_to(ROOT)} ({len(rows[0])}x{len(rows)}, {len(image)} bytes) and {OUT_JSON.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
