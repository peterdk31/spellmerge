# SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
# SPDX-License-Identifier: GPL-3.0-or-later
"""Tests for tools/icon_art.py:  python3 -m unittest discover -s tools"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import icon_art  # noqa: E402
import pixel_grid  # noqa: E402
from staff_art import OUTLINE, RAMPS  # noqa: E402

PLAYER = {c for ramp in RAMPS for c in ramp}


class IconArtTest(unittest.TestCase):
    def test_the_files_are_what_the_rules_draw(self) -> None:
        self.assertEqual(icon_art.main(["--check"]), 0, "run tools/icon_art.py and commit its files")

    def test_every_icon_is_32_art_pixels_palette_only_and_closed(self) -> None:
        palette = set(pixel_grid.palette())
        for path, draw in icon_art.files().items():
            big = path.name.endswith("@2x.svg")
            self.assertTrue(big or path.parent.name in icon_art.SMALL_TOO, f"{path}: named for its detail")
            picture = draw()
            p = picture.pixels
            side = 32 if big else 16
            self.assertEqual((picture.width, picture.height), (side, side), path.name)
            colours = {c for row in p for c in row} - {None}
            self.assertTrue(colours <= palette, f"{path.parent.name}: palette colours only")
            self.assertFalse(colours & PLAYER, f"{path.parent.name}: no player colour")
            for y in range(picture.height):
                for x in range(picture.width):
                    if p[y][x] is None or p[y][x] == OUTLINE:
                        continue
                    for dy in (-1, 0, 1):
                        for dx in (-1, 0, 1):
                            ny, nx = y + dy, x + dx
                            inside = 0 <= ny < picture.height and 0 <= nx < picture.width
                            self.assertTrue(inside and p[ny][nx] is not None, f"{path.parent.name}: ({x}, {y}) closed in")


if __name__ == "__main__":
    unittest.main()
