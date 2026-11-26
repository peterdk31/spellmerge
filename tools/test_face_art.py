# SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
# SPDX-License-Identifier: GPL-3.0-or-later
"""Tests for tools/face_art.py:  python3 -m unittest discover -s tools -p 'test_*.py'"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import face_art  # noqa: E402
import pixel_grid  # noqa: E402
import staff_art  # noqa: E402


class FaceArtTest(unittest.TestCase):
    def test_the_files_are_what_the_rules_draw(self) -> None:
        self.assertEqual(face_art.main(["--check"]), 0, "run tools/face_art.py and commit its SVGs")

    def test_the_sheets_keep_the_1x_layout_at_twice_the_pixels(self) -> None:
        eyes = face_art.eyes()
        self.assertEqual((eyes.width, eyes.height), (32 * 10, 16 * 6), "ten eye columns by six styles of 32x16")
        brows = face_art.brows()
        self.assertEqual((brows.width, brows.height), (32 * 5, 16 * 2), "five brow columns by two rows of 32x16")

    def test_the_optimist_row_is_the_curl_s_face(self) -> None:
        eyes, cheer = face_art.eyes(), staff_art.cheer_eyes()
        self.assertEqual(eyes.pixels[:16], cheer.pixels, "the shared Optimist eyes are the curl's")
        self.assertEqual(face_art.brows().pixels[:16], staff_art.brows().pixels, "the pair of brows is the curl's")

    def test_palette_only_a_stray_s_eyes_untinted_and_every_frame_drawn(self) -> None:
        palette = pixel_grid.palette()
        eyes = face_art.eyes()
        for style in range(6):
            colours = set()
            for column in range(10):
                drawn = 0
                for y in range(style * 16, style * 16 + 16):
                    for x in range(column * 32, column * 32 + 32):
                        colour = eyes.pixels[y][x]
                        if colour is not None:
                            self.assertIn(colour, palette)
                            colours.add(colour)
                            drawn += 1
                self.assertGreater(drawn, 0, f"style {style}, column {column} is drawn")
            if style >= 4:
                self.assertEqual(colours, {staff_art.OUTLINE, staff_art.BONE[2]}, "a stray's eyes are white, for the game to tint")

    def test_a_one_eyed_stray_has_one_eye_and_one_brow(self) -> None:
        eyes, brows = face_art.eyes(), face_art.brows()
        for x in range(face_art.BOX_LEFT + face_art.BOX_W, 32):
            for y in range(16):
                self.assertIsNone(eyes.pixels[5 * 16 + y][x], "nothing right of the one eye")
                self.assertIsNone(brows.pixels[16 + y][x], "nothing right of the one brow")


if __name__ == "__main__":
    unittest.main()
