# SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
# SPDX-License-Identifier: GPL-3.0-or-later
"""Tests for tools/prop_art.py:  python3 -m unittest discover -s tools"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import pixel_grid  # noqa: E402
import prop_art  # noqa: E402
import sprite_rules as sr  # noqa: E402
from staff_art import OUTLINE, RAMPS  # noqa: E402

PLAYER = {c for ramp in RAMPS for c in ramp}
BLIGHT = set(sr.PALETTE["Blight"])

# Each look's frame in world units (its 1x art's size) and its frames: they never change.
SIZES = {
    "arc_lodestone": (24, 32, 1), "burial_jar": (24, 24, 1), "crate": (24, 24, 1), "exploding_barrel": (24, 32, 1),
    "fountain": (32, 32, 1), "fire_pit": (24, 24, 1),
}
FRAMES = {"cracking": 6, "splitting": 7, "collapsing": 9, "flames": 3}


class PropArtTest(unittest.TestCase):
    def test_the_files_are_what_the_rules_draw(self) -> None:
        self.assertEqual(prop_art.main(["--check"]), 0, "run tools/prop_art.py and commit its files")

    def test_palette_only_no_player_colour_nor_blight_and_closed(self) -> None:
        palette = set(pixel_grid.palette())
        for path, draw in prop_art.files().items():
            picture = draw()
            p = picture.pixels
            colours = {c for row in p for c in row} - {None}
            self.assertTrue(colours <= palette, f"{path.name}: palette colours only")
            self.assertFalse(colours & PLAYER, f"{path.name}: no player colour")
            self.assertFalse(colours & BLIGHT, f"{path.name}: no Blight (the enemies' spells)")
            if path.name.endswith("_motes.svg"):
                continue
            for y in range(picture.height):
                for x in range(picture.width):
                    if p[y][x] is None or p[y][x] == OUTLINE:
                        continue
                    for dy in (-1, 0, 1):
                        for dx in (-1, 0, 1):
                            ny, nx = y + dy, x + dx
                            inside = 0 <= ny < picture.height and 0 <= nx < picture.width
                            self.assertTrue(inside and p[ny][nx] is not None, f"{path.name}: ({x}, {y}) closed in")

    def test_each_look_is_its_1x_size_at_twice_the_pixels(self) -> None:
        for path, draw in prop_art.files().items():
            picture = draw()
            stem = path.name.split("@")[0].split(".")[0]
            if path.name.endswith("_motes.svg"):
                w, h, _ = SIZES[path.parent.name]
                self.assertEqual((picture.width, picture.height), (w, h), f"{path.name}: a mask stays 1x")
                continue
            self.assertIn("@2x", path.name, f"{path.name}: named @2x")
            frames = FRAMES.get(stem, 1)
            self.assertEqual(picture.width % (frames * sr.DETAIL), 0, f"{path.name}: {frames} frames of whole world units")
            self.assertEqual(picture.height % sr.DETAIL, 0, path.name)
            if path.parent.name in SIZES:
                w, h, _ = SIZES[path.parent.name]
                self.assertEqual((picture.width // frames, picture.height), (w * sr.DETAIL, h * sr.DETAIL), path.name)

    def test_each_crumble_starts_where_the_stage_before_rests(self) -> None:
        """docs/STYLE.md, "Smooth": stages hand over, so the crypt pillar falls as one movement."""
        stages = [[prop_art.crypt_intact()], [prop_art.crypt_cracking(i) for i in range(6)],
                  [prop_art.crypt_splitting(i) for i in range(7)], [prop_art.crypt_collapsing(i) for i in range(9)]]
        for before, after in zip(stages, stages[1:]):
            self.assertEqual(sr.draw(after[0], 48, 64).pixels, sr.draw(before[-1], 48, 64).pixels)

    def test_a_crumble_changes_a_little_each_frame(self) -> None:
        """No frame of a crumble is the one before it, and none jumps to a new picture."""
        for name, count in (("cracking", 6), ("splitting", 7), ("collapsing", 9)):
            frames = [sr.draw(getattr(prop_art, f"crypt_{name}")(i), 48, 64).pixels for i in range(count)]
            for i in range(1, count - 1):
                kept = sum(a == b for ra, rb in zip(frames[i - 1], frames[i]) for a, b in zip(ra, rb))
                self.assertGreater(kept, 0.75 * 96 * 128, f"{name} {i}: most pixels kept")

    def test_every_mask_point_lies_on_its_look(self) -> None:
        bodies = {
            "arc_lodestone/idle_motes.svg": prop_art.lodestone_idle(),
            "arc_lodestone/charged_motes.svg": prop_art.lodestone_charged(),
            "exploding_barrel/idle_motes.svg": prop_art.barrel_idle(),
            "fountain/still_motes.svg": prop_art.fountain_still(),
            "fountain/welling_motes.svg": prop_art.fountain_welling(),
        }
        for name, parts in bodies.items():
            mask = prop_art.files()[prop_art.PROPS / name]()
            body = sr.draw(parts, mask.width, mask.height)
            lit = [(x, y) for y in range(mask.height) for x in range(mask.width) if mask.pixels[y][x] is not None]
            self.assertTrue(lit, name)
            for x, y in lit:
                block = [body.pixels[y * 2 + j][x * 2 + i] for j in (0, 1) for i in (0, 1)]
                self.assertTrue(any(c not in (None, OUTLINE) for c in block), f"{name}: ({x}, {y}) on the art")

    def test_an_unknown_name_is_refused(self) -> None:
        with self.assertRaises(SystemExit):
            prop_art.main(["--check", "nosuch"])


if __name__ == "__main__":
    unittest.main()
