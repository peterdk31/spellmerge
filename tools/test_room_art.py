# SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
# SPDX-License-Identifier: GPL-3.0-or-later
"""Tests for tools/room_art.py:  python3 -m unittest discover -s tools"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import pixel_grid  # noqa: E402
import room_art  # noqa: E402
import sprite_rules as sr  # noqa: E402
from staff_art import OUTLINE, RAMPS  # noqa: E402

PLAYER = {c for ramp in RAMPS for c in ramp}
BLIGHT = set(sr.PALETTE["Blight"])

# Each piece's frame in world units (its 1x art's size) and its frames: they never change.
SIZES = {
    "floor": (32, 32, 1), "wall": (32, 32, 1), "wall_top": (32, 32, 1), "pillar": (32, 32, 1), "pillar_top": (32, 32, 1),
    "door": (32, 32, 1), "torch": (32, 32, 1), "torch_flame": (32, 32, 4), "torch_glow": (64, 64, 1),
    "torch_glow_core": (32, 32, 3), "candles": (32, 32, 1), "candle_flame": (32, 32, 4), "skull": (32, 32, 1),
    "rubble": (32, 32, 1), "bone_pile": (32, 16, 1), "sarcophagus": (64, 32, 1), "fallen_column": (64, 32, 1),
    "ossuary_wall": (128, 32, 1), "void": (32, 32, 1), "stone": (96, 96, 1), "stone_lit": (96, 96, 1),
    "altar": (96, 96, 1), "beam": (64, 224, 1), "beam_pool": (80, 32, 1),
}
MASKS = {"stone_lit_motes": (96, 96)}


class RoomArtTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.pictures = {path: draw() for path, draw in room_art.files().items()}

    def test_the_files_are_what_the_rules_draw(self) -> None:
        self.assertEqual(room_art.main(["--check"]), 0, "run tools/room_art.py and commit its files")

    def test_every_piece_is_listed_once_with_its_size(self) -> None:
        self.assertEqual(sorted(room_art.stem(p) for p in self.pictures), sorted([*SIZES, *MASKS]))

    def test_each_is_its_1x_size_at_twice_the_pixels_named_2x(self) -> None:
        for path, picture in self.pictures.items():
            if room_art.stem(path) in MASKS:
                self.assertEqual((picture.width, picture.height), MASKS[room_art.stem(path)], f"{path.name}: a mask stays 1x")
                continue
            w, h, frames = SIZES[room_art.stem(path)]
            self.assertIn("@2x", path.name, path.name)
            self.assertEqual((picture.width, picture.height), (w * sr.DETAIL * frames, h * sr.DETAIL), path.name)

    def test_palette_only_no_player_colour_nor_blight(self) -> None:
        palette = set(pixel_grid.palette())
        for path, picture in self.pictures.items():
            colours = {c for row in picture.pixels for c in row} - {None}
            if room_art.stem(path) in ("beam", "beam_pool"):
                continue
            self.assertTrue(colours <= palette, f"{path.name}: palette colours only")
            self.assertFalse(colours & PLAYER, f"{path.name}: no player colour")
            self.assertFalse(colours & BLIGHT, f"{path.name}: no Blight (the enemies' spells)")

    def test_what_stands_in_the_room_is_closed_by_its_outline(self) -> None:
        for path, picture in self.pictures.items():
            if room_art.stem(path) in room_art.UNOUTLINED:
                continue
            if room_art.stem(path) == "altar":
                picture = sr.draw(room_art.hub_altar(), 96, 96)  # Its motes of light are drawn over, unoutlined.
            p = picture.pixels
            for y in range(picture.height):
                for x in range(picture.width):
                    if p[y][x] is None or p[y][x] == OUTLINE:
                        continue
                    for dy in (-1, 0, 1):
                        for dx in (-1, 0, 1):
                            ny, nx = y + dy, x + dx
                            inside = 0 <= ny < picture.height and 0 <= nx < picture.width
                            # A pillar's shaft runs on past its tile's edge into the next one.
                            if not inside and room_art.stem(path) in ("pillar", "pillar_top"):
                                continue
                            self.assertTrue(inside and p[ny][nx] is not None, f"{path.name}: ({x}, {y}) closed in")

    def test_tiles_fill_their_cell_and_repeat_with_no_seam(self) -> None:
        """A tile's every pixel is drawn, and its edges meet: the joint or course that leaves one
        side comes in at the other (each edge row is as like its opposite as the tile's middle)."""
        for path, picture in self.pictures.items():
            name = room_art.stem(path)
            if name not in room_art.TILES:
                continue
            p = picture.pixels
            self.assertTrue(all(c is not None for row in p for c in row), f"{path.name}: fills its cell")
            if name in ("wall_top", "door"):
                continue  # They repeat along a row only: the wall's top, a door in its frame.
            w, h = picture.width, picture.height

            def alike(a: list, b: list) -> float:
                return sum(x == y for x, y in zip(a, b)) / len(a)

            self.assertGreater(alike(p[0], p[h - 1]), 0.6, f"{path.name}: top meets bottom")
            self.assertGreater(alike([r[0] for r in p], [r[w - 1] for r in p]), 0.6, f"{path.name}: left meets right")

    def test_the_floor_is_flat_and_quiet(self) -> None:
        """docs/STYLE.md, "Tiles": Stone base with a few details, nothing on its outer edge pixels."""
        p = self.pictures[room_art.CRYPT / "floor@2x.svg"].pixels
        flat = [c for row in p for c in row]
        self.assertGreater(flat.count(room_art.S1) / len(flat), 0.85, "mostly Stone base")
        edge = p[0] + p[-1] + [r[0] for r in p] + [r[-1] for r in p]
        self.assertTrue(all(c == room_art.S1 for c in edge), "nothing on its outer edge")

    def test_the_lit_runes_lie_on_the_carved_ones(self) -> None:
        stone = self.pictures[room_art.PROPS / "hub_stone/stone@2x.png"].pixels
        lit = self.pictures[room_art.PROPS / "hub_stone/stone_lit@2x.svg"].pixels
        glowing = [(x, y) for y, row in enumerate(lit) for x, c in enumerate(row) if c is not None]
        self.assertTrue(glowing)
        for x, y in glowing:
            self.assertEqual(stone[y][x], room_art.S0, f"({x}, {y}): carved where it glows")

    def test_every_mote_point_lies_on_the_lit_runes(self) -> None:
        mask = self.pictures[room_art.PROPS / "hub_stone/stone_lit_motes.svg"]
        lit = self.pictures[room_art.PROPS / "hub_stone/stone_lit@2x.svg"].pixels
        points = [(x, y) for y, row in enumerate(mask.pixels) for x, c in enumerate(row) if c is not None]
        self.assertGreater(len(points), 100, "the runes, rings and star")
        for x, y in points:
            block = [lit[y * 2 + j][x * 2 + i] for j in (0, 1) for i in (0, 1)]
            self.assertTrue(any(c is not None for c in block), f"({x}, {y}) on the lit runes")

    def test_the_ossuary_skulls_are_a_shade_down(self) -> None:
        """The owner, 2026-11-27 (#968): no Bone light on the background wall, its skulls dimmed."""
        wall = self.pictures[room_art.CRYPT / "ossuary_wall@2x.png"].pixels
        colours = {c for row in wall for c in row}
        self.assertNotIn(room_art.B2, colours, "no Bone light")
        self.assertIn(room_art.B1, colours, "the skulls still bone")

    def test_a_flame_changes_a_little_each_frame(self) -> None:
        """docs/STYLE.md, "Smooth": the loop's looks are near one another, never the same."""
        for name, count in (("torch_flame", 4), ("candle_flame", 4)):
            frames = [sr.draw(getattr(room_art, name)(i), 32, 32).pixels for i in range(count)]
            for a in range(count):
                for b in range(a + 1, count):
                    self.assertNotEqual(frames[a], frames[b], f"{name} {a} and {b}")

    def test_the_light_is_whole_steps_of_one_colour(self) -> None:
        for name in ("beam", "beam_pool"):
            light = getattr(room_art, name)()
            steps = {a for row in light.alpha for a in row} - {0}
            self.assertTrue(2 <= len(steps) <= 6, f"{name}: a few steps, {sorted(steps)}")
            self.assertTrue(all(0 < a < 255 for a in steps), f"{name}: soft, never opaque")

    def test_an_unknown_name_is_refused(self) -> None:
        with self.assertRaises(SystemExit):
            room_art.main(["--check", "nosuch"])


if __name__ == "__main__":
    unittest.main()
