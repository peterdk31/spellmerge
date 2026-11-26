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

    def _block(self, base: str) -> "redraw_2x.Canvas":
        rows = ["#" * 8] + ["#" + "s" * 6 + "#" for _ in range(6)] + ["#" * 8]
        colours = {"#": OUTLINE, "s": base}
        rects = "".join(f'<rect x="{x}" y="{y}" width="1" height="1" fill="{colours[c]}"/>' for y, row in enumerate(rows) for x, c in enumerate(row))
        return redraw_2x.read_svg(f'<svg width="8" height="8">{rects}</svg>')

    def test_the_detail_pass_lights_and_shades_the_edges_of_the_base_only(self) -> None:
        wood = ("#3d2a2e", "#7a4a35", "#b27a4a")
        plain = redraw_2x.redraw(self._block(wood[1]), smooth=False)
        out = redraw_2x.redraw(self._block(wood[1]), smooth=False, detailed=True)
        inside = [(x, y) for y in range(out.height) for x in range(out.width) if out.pixels[y][x] in wood]
        top_left = min(inside, key=lambda p: p[0] + p[1])
        bottom_right = max(inside, key=lambda p: p[0] + p[1])
        self.assertEqual(out.pixels[top_left[1]][top_left[0]], wood[2], "the top-left edge lit")
        self.assertEqual(out.pixels[bottom_right[1]][bottom_right[0]], wood[0], "the bottom-right edge shaded")
        middle = (out.width // 2, out.height // 2)
        self.assertEqual(out.pixels[middle[1]][middle[0]], wood[1], "the middle stays the base")
        for y in range(out.height):
            for x in range(out.width):
                if plain.pixels[y][x] != wood[1]:
                    self.assertEqual(out.pixels[y][x], plain.pixels[y][x], "only the base shade changes")

    def test_stone_is_never_shaded_down_to_its_shadow(self) -> None:
        stone = ("#2b2840", "#4a4663", "#7a7694")
        out = redraw_2x.redraw(self._block(stone[1]), smooth=False, detailed=True)
        colours = {c for row in out.pixels for c in row}
        self.assertNotIn(stone[0], colours, "Stone shadow is the floor's (docs/STYLE.md, Readability)")
        self.assertIn(stone[2], colours, "its lit edge all the same")

    def test_the_texture_pass_marks_the_inside_of_a_part_the_same_in_every_frame(self) -> None:
        wood, bone = ("#3d2a2e", "#7a4a35", "#b27a4a"), ("#a39fb8", "#d4d0e0", "#f4f1ea")
        for shades in (wood, bone):
            # Two frames of the same tall block side by side.
            frame = ["." * 8] + [".#" + "s" * 4 + "#." for _ in range(14)] + ["." * 8]
            rows = [r + r for r in frame]
            colours = {"#": OUTLINE, "s": shades[1]}
            rects = "".join(f'<rect x="{x}" y="{y}" width="1" height="1" fill="{colours[c]}"/>' for y, row in enumerate(rows) for x, c in enumerate(row) if c != ".")
            src = redraw_2x.read_svg(f'<svg width="16" height="16">{rects}</svg>')
            out = redraw_2x.redraw(src, smooth=False, textured=True, frame_width=16)
            left = [row[:16] for row in out.pixels]
            right = [row[16:] for row in out.pixels]
            self.assertEqual(left, right, "every frame the same surface (docs/STYLE.md, Smooth)")
            inside = [c for row in left[4:-4] for c in row[6:10]]
            self.assertIn(shades[0], inside, "its surface marked in its own shadow (grain, pores)")
            self.assertEqual({c for row in out.pixels for c in row} - {None, OUTLINE}, set(shades), "in its own shades only")

    def test_wood_grain_runs_along_the_part(self) -> None:
        wood = ("#3d2a2e", "#7a4a35", "#b27a4a")
        rows = ["#" * 6] + ["#" + "s" * 4 + "#" for _ in range(14)] + ["#" * 6]
        rects = "".join(f'<rect x="{x}" y="{y}" width="1" height="1" fill="{OUTLINE if c == "#" else wood[1]}"/>' for y, row in enumerate(rows) for x, c in enumerate(row))
        picture = redraw_2x.double(redraw_2x.read_svg(f'<svg width="6" height="16">{rects}</svg>'))
        out = redraw_2x.texture(picture, picture.width)
        grain = [(x, y) for y in range(out.height) for x in range(out.width) if out.pixels[y][x] == wood[0]]
        columns = {x for x, _ in grain}
        self.assertLess(len(columns), len(grain) / 3, "streaks down the tall part, a few columns many pixels long")

    def test_a_strip_not_whole_frames_is_refused_and_stone_never_shaded_down(self) -> None:
        stone = ("#2b2840", "#4a4663", "#7a7694")
        rows = ["#" * 10] + ["#" + "s" * 8 + "#" for _ in range(6)] + ["#" * 10]
        colours = {"#": OUTLINE, "s": stone[0]}
        rects = "".join(f'<rect x="{x}" y="{y}" width="1" height="1" fill="{colours[c]}"/>' for y, row in enumerate(rows) for x, c in enumerate(row))
        picture = redraw_2x.double(redraw_2x.read_svg(f'<svg width="10" height="8">{rects}</svg>'))
        with self.assertRaises(ValueError):
            redraw_2x.texture(picture)
        out = redraw_2x.texture(picture, picture.width)
        colours_out = {c for row in out.pixels for c in row}
        self.assertNotIn(stone[0], colours_out, "a body's Stone shadow becomes its base")
        self.assertEqual([row[0] for row in out.pixels], [row[0] for row in picture.pixels], "the outline left alone")

    def test_a_target_not_named_at_2x_is_refused(self) -> None:
        with self.assertRaises(SystemExit):
            redraw_2x.main(["in.svg", "out.svg"])


if __name__ == "__main__":
    unittest.main()
