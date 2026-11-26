# SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
# SPDX-License-Identifier: GPL-3.0-or-later
"""Tests for tools/enemy_art.py and tools/sprite_rules.py:  python3 -m unittest discover -s tools"""

import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import enemy_art  # noqa: E402
import pixel_grid  # noqa: E402
import sprite_rules as sr  # noqa: E402
from staff_art import OUTLINE, RAMPS  # noqa: E402

PLAYER = {c for ramp in RAMPS for c in ramp}
STONE_SHADOW = sr.PALETTE["Stone"][0]


class EnemyArtTest(unittest.TestCase):
    def test_the_files_are_what_the_rules_draw(self) -> None:
        self.assertEqual(enemy_art.main(["--check"]), 0, "run tools/enemy_art.py and commit its files")

    def test_palette_only_no_player_colour_no_stone_shadow_and_closed(self) -> None:
        palette = set(pixel_grid.palette())
        for path, draw in enemy_art.files().items():
            picture = draw()
            p = picture.pixels
            colours = {c for row in p for c in row} - {None}
            self.assertTrue(colours <= palette, f"{path.name}: palette colours only")
            self.assertFalse(colours & PLAYER, f"{path.name}: no player colour")
            self.assertNotIn(STONE_SHADOW, colours, f"{path.name}: no Stone shadow (the floor's)")
            for y in range(picture.height):
                for x in range(picture.width):
                    if p[y][x] is None or p[y][x] == OUTLINE:
                        continue
                    # The portrait's third frame is the eyes' glow alone, drawn with no outline.
                    if path.name.startswith("portrait") and x >= 384:
                        continue
                    for dy in (-1, 0, 1):
                        for dx in (-1, 0, 1):
                            ny, nx = y + dy, x + dx
                            # The handle runs on into the head below its frame.
                            if path.name.startswith("handle") and ny == picture.height:
                                continue
                            inside = 0 <= ny < picture.height and 0 <= nx < picture.width
                            self.assertTrue(inside and p[ny][nx] is not None, f"{path.name}: ({x}, {y}) closed in")

    def test_every_body_is_64_art_pixels_and_shows_its_materials_in_three_shades(self) -> None:
        for name, parts in enemy_art.SPRITES.items():
            picture = sr.draw(parts(), 32, 32)
            self.assertEqual((picture.width, picture.height), (64, 64), name)
            colours = [c for row in picture.pixels for c in row if c is not None]
            wood = sr.PALETTE["Wood"]
            if any(c in wood for c in colours):
                self.assertTrue(all(c in colours for c in wood), f"{name}: its wood in three shades")
            # The base shade covers more of the wood than either other (docs/STYLE.md).
            counts = [colours.count(c) for c in wood]
            if sum(counts) > 60:
                self.assertGreaterEqual(counts[1], min(counts[0], counts[2]), f"{name}: {counts}")

    def test_the_broom_keeps_its_1x_silhouettes_and_frames(self) -> None:
        shapes = json.loads((enemy_art.BROOM / "silhouettes.json").read_text(encoding="utf-8"))
        for frame in range(5):
            picture = sr.draw(enemy_art.broom_head(frame), 88, 32)
            # With its outline, where the 1x outline was.
            drawn = {(x // 2, y // 2) for y in range(64) for x in range(176) if picture.pixels[y][x] is not None}
            kept = {(x, y) for y, row in enumerate(shapes["head"][frame]) for a, b in row for x in range(a, b)}
            self.assertGreater(len(drawn & kept) / len(kept | drawn), 0.9, f"head frame {frame}: its 1x outline")
        self.assertEqual((enemy_art.broom_eyes().width, enemy_art.broom_eyes().height), (480, 32), "ten looks by two rows of 48x16")
        self.assertEqual((enemy_art.broom_brows().width, enemy_art.broom_brows().height), (240, 32), "five moods by two rows")
        self.assertEqual((enemy_art.broom_portrait().width, enemy_art.broom_portrait().height), (576, 192), "three 192x192 frames")

    def test_the_portrait_s_lit_eyes_lie_on_its_rest_pose_s_eyes(self) -> None:
        sheet = enemy_art.broom_portrait()
        bone = set(sr.PALETTE["Bone"]) | {OUTLINE}
        for y in range(192):
            for x in range(192):
                if sheet.pixels[y][384 + x] is not None:
                    self.assertIn(sheet.pixels[y][x], bone, f"the eye lit at ({x}, {y}) is on the rest pose's eye")

    def test_an_unknown_name_is_refused(self) -> None:
        with self.assertRaises(SystemExit):
            enemy_art.main(["--check", "nosuch"])


if __name__ == "__main__":
    unittest.main()
