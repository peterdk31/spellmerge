# SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
# SPDX-License-Identifier: GPL-3.0-or-later
"""Tests for tools/staff_art.py:  python3 -m unittest discover -s tools -p 'test_*.py'"""

import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import pixel_grid  # noqa: E402
import staff_art  # noqa: E402

RECT = re.compile(r'<rect x="(\d+)" y="(\d+)" width="(\d+)" height="1" fill="(#[0-9a-f]{6})"/>')


class StaffArtTest(unittest.TestCase):
    def test_the_files_are_what_the_rules_draw(self) -> None:
        self.assertEqual(staff_art.main(["--check"]), 0, "run tools/staff_art.py and commit its SVGs")

    def test_the_sheets_keep_the_1x_layout_at_twice_the_pixels(self) -> None:
        head = staff_art.curl_head()
        self.assertEqual((head.width, head.height), (48 * 2 * 16, 48 * 2 * 4), "16 directions by 4 ramps of 96x96")
        eyes = staff_art.cheer_eyes()
        self.assertEqual((eyes.width, eyes.height), (32 * 10, 16), "ten eye columns of 32x16")
        brows = staff_art.brows()
        self.assertEqual((brows.width, brows.height), (32 * 5, 16), "five brow columns of 32x16")

    def test_only_palette_colours_and_one_rect_a_run(self) -> None:
        palette = pixel_grid.palette()
        for path in staff_art.FILES:
            text = path.read_text(encoding="utf-8")
            self.assertIn('shape-rendering="crispEdges"', text)
            rows: dict[int, list[tuple[int, int, str]]] = {}
            for x, y, width, colour in RECT.findall(text):
                self.assertIn(colour, palette, f"{path.name}: {colour} is a palette colour")
                rows.setdefault(int(y), []).append((int(x), int(width), colour))
            for y, runs in rows.items():
                runs.sort()
                for (x, width, colour), (next_x, _, next_colour) in zip(runs, runs[1:]):
                    self.assertLessEqual(x + width, next_x, f"{path.name}: rects on row {y} do not overlap")
                    if x + width == next_x:
                        self.assertNotEqual(colour, next_colour, f"{path.name}: one rect a run on row {y}")

    def test_the_rows_differ_only_on_the_gem(self) -> None:
        head = staff_art.curl_head()
        size = 96
        ramp_colours = {c for ramp in staff_art.RAMPS for c in ramp}
        for direction in range(16):
            for ramp in range(1, 4):
                for y in range(size):
                    for x in range(size):
                        a = head.pixels[y][direction * size + x]
                        b = head.pixels[ramp * size + y][direction * size + x]
                        if a != b:
                            self.assertIn(a, ramp_colours, "a pixel that differs between rows is the gem's")
                            self.assertIn(b, ramp_colours)

    def test_the_grip_is_on_the_shaft_in_every_frame(self) -> None:
        head = staff_art.curl_head()
        grip = (int(staff_art.GRIP[0] * 2), int(staff_art.GRIP[1] * 2))
        for direction in range(16):
            colour = head.pixels[grip[1]][direction * 96 + grip[0]]
            self.assertIn(colour, staff_art.SPARK + staff_art.WOOD, f"frame {direction}: the grip is on the staff")


if __name__ == "__main__":
    unittest.main()
