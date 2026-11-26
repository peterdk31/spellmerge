# SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
# SPDX-License-Identifier: GPL-3.0-or-later
"""Tests for tools/head_art.py:  python3 -m unittest discover -s tools -p 'test_*.py'"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import head_art  # noqa: E402
import pixel_grid  # noqa: E402
from staff_art import BONE, OUTLINE, RAMPS, SPARK, WOOD  # noqa: E402

SIZE = head_art.FRAME * head_art.DETAIL
UP = 12


class HeadArtTest(unittest.TestCase):
    def test_the_sheets_are_what_the_rules_draw(self) -> None:
        self.assertEqual(head_art.main(["--check"]), 0, "run tools/head_art.py and commit its sheets")

    def test_every_frame_palette_only_closed_and_clear_of_the_frame_edge(self) -> None:
        palette = set(pixel_grid.palette())
        for name in head_art.HEADS:
            for ramp in range(4):
                for direction in range(head_art.DIRECTIONS):
                    p = head_art.head_frame(name, direction, ramp).pixels
                    where = f"{name}, direction {direction}, ramp {ramp}"
                    for y in range(SIZE):
                        for x in range(SIZE):
                            colour = p[y][x]
                            if colour is None:
                                continue
                            self.assertIn(colour, palette, where)
                            self.assertTrue(0 < x < SIZE - 1 and 0 < y < SIZE - 1, f"{where}: clear of the frame's edge")
                            if colour == OUTLINE:
                                continue
                            # Closed eight ways: every drawn pixel's neighbours are drawn.
                            for dy in (-1, 0, 1):
                                for dx in (-1, 0, 1):
                                    self.assertIsNotNone(p[y + dy][x + dx], f"{where}: ({x}, {y}) closed in")

    def test_the_player_colour_is_on_the_head_only(self) -> None:
        for name in head_art.HEADS:
            for direction in range(head_art.DIRECTIONS):
                frame = head_art.Frame(direction)
                draw = head_art.HEADS[name]
                for ramp in range(4):
                    p = head_art.head_frame(name, direction, ramp).pixels
                    others = {c for r, shades in enumerate(RAMPS) if r != ramp for c in shades}
                    for y in range(SIZE):
                        for x in range(SIZE):
                            if p[y][x] in others:
                                self.fail(f"{name}: another player's colour")
                            if p[y][x] in RAMPS[ramp]:
                                hit = draw(frame, (x + 0.5) / head_art.DETAIL, (y + 0.5) / head_art.DETAIL)
                                self.assertIn(hit[0] if hit else None, (head_art.M_HEAD, head_art.M_DARK), f"{name}: ramp colour off the head at ({x}, {y})")

    def test_the_base_shade_covers_most_of_the_head(self) -> None:
        """docs/STYLE.md, "Light and shading": the base shade most, the light and the shadow its edges."""
        for name in head_art.HEADS:
            for direction in range(head_art.DIRECTIONS):
                pixels = [c for row in head_art.head_frame(name, direction, 0).pixels for c in row]
                shadow, base, light = (pixels.count(c) for c in RAMPS[0])
                self.assertGreaterEqual(base, max(shadow, light), f"{name}, direction {direction}: {shadow}/{base}/{light}")

    def test_each_material_shows_three_shades_and_a_small_glint(self) -> None:
        for name in head_art.HEADS:
            pixels = [c for row in head_art.head_frame(name, 14, 0).pixels for c in row]
            colours = set(pixels)
            self.assertTrue(set(WOOD) <= colours, f"{name}: the wood in its three shades")
            self.assertTrue(set(RAMPS[0]) <= colours, f"{name}: the head in its three shades")
            self.assertTrue(colours & set(SPARK), f"{name}: gold")
            self.assertTrue(1 <= pixels.count(BONE[2]) <= 8, f"{name}: a glint, a spot not a blob")

    def test_an_unknown_head_is_refused(self) -> None:
        with self.assertRaises(SystemExit):
            head_art.main(["--check", "nosuch"])

    def test_the_grip_is_on_the_shaft_and_the_head_keeps_its_reach(self) -> None:
        gx, gy = int(head_art.GRIP[0] * head_art.DETAIL), int(head_art.GRIP[1] * head_art.DETAIL)
        for name in head_art.HEADS:
            frame = head_art.head_frame(name, UP, 0)
            self.assertIn(frame.pixels[gy][gx], WOOD + SPARK, f"{name}: the grip is on the shaft")
            rows = [y for y in range(SIZE) if any(c is not None for c in frame.pixels[y])]
            top, bottom = rows[0] / head_art.DETAIL, (rows[-1] + 1) / head_art.DETAIL
            # Within a pixel or two of the 1x sheet's reach: the head 16-20 above the grip, the butt
            # 10 below it (content/wizard/README.md: every head's shaft is 9-10).
            self.assertTrue(16.0 <= head_art.GRIP[1] - top <= 20.5, f"{name}: the head's reach ({head_art.GRIP[1] - top})")
            self.assertTrue(9.0 <= bottom - head_art.GRIP[1] <= 11.0, f"{name}: the butt's ({bottom - head_art.GRIP[1]})")


if __name__ == "__main__":
    unittest.main()
