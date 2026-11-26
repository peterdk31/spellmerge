# SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
# SPDX-License-Identifier: GPL-3.0-or-later
"""Tests for tools/redraw_2x.py:  python3 -m unittest discover -s tools -p 'test_*.py'"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import redraw_2x  # noqa: E402
from staff_art import OUTLINE  # noqa: E402

FILL = "#7a4a35"
# A filled diamond with a one-pixel outline (1x art): its outside steps one pixel a row.
DIAMOND = [
    "...##...",
    "..#ff#..",
    ".#ffff#.",
    "#ffffff#",
    ".#ffff#.",
    "..#ff#..",
    "...##...",
]


def _svg(rows: list[str]) -> str:
    colours = {"#": OUTLINE, "f": FILL}
    rects = [
        f'<rect x="{x}" y="{y}" width="1" height="1" fill="{colours[c]}"/>'
        for y, row in enumerate(rows) for x, c in enumerate(row) if c != "."
    ]
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{len(rows[0])}" height="{len(rows)}">' + "".join(rects) + "</svg>"


def _clear_beside(pixels: list[list[str | None]], x: int, y: int, ways: list[tuple[int, int]] = redraw_2x.NEAR) -> bool:
    for dx, dy in ways:
        xx, yy = x + dx, y + dy
        if not (0 <= yy < len(pixels) and 0 <= xx < len(pixels[0])) or pixels[yy][xx] is None:
            return True
    return False


class Redraw2xTest(unittest.TestCase):
    def test_twice_the_size_and_the_same_silhouette(self) -> None:
        src = redraw_2x.read_svg(_svg(DIAMOND))
        for smooth in (True, False):
            out = redraw_2x.redraw(src, smooth)
            self.assertEqual((out.width, out.height), (src.width * 2, src.height * 2))
            # Every 2x2 block of a drawn 1x pixel has something drawn: nothing of the shape is lost.
            for y in range(src.height):
                for x in range(src.width):
                    if src.pixels[y][x] is not None:
                        block = [out.pixels[2 * y + j][2 * x + i] for j in (0, 1) for i in (0, 1)]
                        self.assertTrue(any(c is not None for c in block), f"({x}, {y}) is kept")

    def test_the_outside_outline_is_one_art_pixel_and_closed(self) -> None:
        out = redraw_2x.redraw(redraw_2x.read_svg(_svg(DIAMOND)))
        for y in range(out.height):
            for x in range(out.width):
                colour = out.pixels[y][x]
                if colour == FILL:
                    # Closed as docs/STYLE.md has it: a diagonal run steps a pixel at a time.
                    straight = [(1, 0), (-1, 0), (0, 1), (0, -1)]
                    self.assertFalse(_clear_beside(out.pixels, x, y, straight), f"the fill at ({x}, {y}) is closed in by the outline")
                if colour == OUTLINE:
                    self.assertTrue(_clear_beside(out.pixels, x, y), f"the outline at ({x}, {y}) is one art pixel")

    def test_inner_dark_parts_keep_their_weight(self) -> None:
        rows = ["#####", "#fff#", "#f#f#", "#fff#", "#####"]
        out = redraw_2x.redraw(redraw_2x.read_svg(_svg(rows)), smooth=False)
        self.assertEqual([out.pixels[y][x] for y in (4, 5) for x in (4, 5)], [OUTLINE] * 4, "a dark middle stays 2x2")

    def test_the_blocky_outline_is_thinned_toward_the_clear_side(self) -> None:
        out = redraw_2x.redraw(redraw_2x.read_svg(_svg(["###", "#f#", "###"])), smooth=False)
        self.assertEqual(out.pixels[2][0], OUTLINE, "the outer half of the left outline stays")
        self.assertEqual(out.pixels[2][1], FILL, "its inner half takes the fill beside it")
        self.assertEqual(out.pixels[0][0], OUTLINE, "a corner stays outline")

    def test_only_the_source_colours_and_a_rect_it_cannot_read_is_refused(self) -> None:
        out = redraw_2x.redraw(redraw_2x.read_svg(_svg(DIAMOND)))
        self.assertEqual({c for row in out.pixels for c in row} - {None}, {OUTLINE, FILL})
        with self.assertRaises(ValueError):
            redraw_2x.read_svg('<svg width="2" height="2"><rect x="0" y="0" width="1" height="1" fill="#14121f" opacity="0.5"/></svg>')

    def test_the_detail_pass_lights_and_shades_edges_and_folds_cloth(self) -> None:
        stone = ("#2b2840", "#4a4663", "#7a7694")
        rows = ["#" * 14] + ["#" + "s" * 12 + "#" for _ in range(12)] + ["#" * 14]
        colours = {"#": OUTLINE, "s": stone[1]}
        rects = "".join(f'<rect x="{x}" y="{y}" width="1" height="1" fill="{colours[c]}"/>' for y, row in enumerate(rows) for x, c in enumerate(row))
        src = redraw_2x.read_svg(f'<svg width="14" height="14">{rects}</svg>')
        out = redraw_2x.redraw(src, smooth=False, detailed=True)
        inside = [(x, y) for y in range(out.height) for x in range(out.width) if out.pixels[y][x] in stone]
        top_left = min(inside, key=lambda p: p[0] + p[1])
        bottom_right = max(inside, key=lambda p: p[0] + p[1])
        self.assertEqual(out.pixels[top_left[1]][top_left[0]], stone[2], "the top-left edge lit")
        self.assertEqual(out.pixels[bottom_right[1]][bottom_right[0]], stone[0], "the bottom-right edge shaded")
        folds = [x for x in range(out.width) if out.pixels[out.height - 6][x] == stone[0]]
        self.assertGreaterEqual(len(folds), 3, "the cloth's lower part falls in folds")

    def test_a_target_not_named_at_2x_is_refused(self) -> None:
        with self.assertRaises(SystemExit):
            redraw_2x.main(["in.svg", "out.svg"])


if __name__ == "__main__":
    unittest.main()
