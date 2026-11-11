# SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
# SPDX-License-Identifier: GPL-3.0-or-later
"""Tests for tools/pixel_grid.py:  python3 -m unittest discover -s tools -p 'test_*.py'"""

import json
import re
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import pixel_grid  # noqa: E402

OUTLINE = "#14121f"
STONE = "#7a7694"


def grid(rows: list[str], motes: str | None = None) -> dict:
    found = {"colours": {"o": OUTLINE, "s": STONE}, "rows": rows}
    if motes is not None:
        found["motes"] = motes
    return found


def square(fill: str = "s", mark: str = "") -> list[str]:
    """An 8x8 picture: an outline round `fill`, `mark` at (3, 3) when given."""
    rows = ["oooooooo"] + ["o" + fill * 6 + "o" for _ in range(6)] + ["oooooooo"]
    if mark:
        rows[3] = rows[3][:3] + mark + rows[3][4:]
    return rows


def rects(svg: str) -> list[tuple[int, int, int, int, str]]:
    return [(int(x), int(y), int(w), int(h), c) for x, y, w, h, c in re.findall(r'<rect x="(\d+)" y="(\d+)" width="(\d+)" height="(\d+)" fill="(#[0-9a-f]{6})"/>', svg)]


class PixelGridTest(unittest.TestCase):
    def setUp(self) -> None:
        self.palette = pixel_grid.palette()
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)

    def test_the_palette_is_read_from_the_style_guide(self) -> None:
        for colour in (OUTLINE, STONE, "#f4f1ea", "#ffa23c"):
            self.assertIn(colour, self.palette)
        self.assertNotIn("#123456", self.palette)

    def test_each_run_of_a_colour_is_one_rect_and_every_pixel_is_drawn_once(self) -> None:
        art, points = pixel_grid.draw(grid(square()), self.palette)
        self.assertIsNone(points, "no mote points, no mask")
        found = rects(art)
        self.assertIn((0, 0, 8, 1, OUTLINE), found)
        self.assertIn((1, 3, 6, 1, STONE), found)
        covered: set[tuple[int, int]] = set()
        for x, y, w, h, _ in found:
            for i in range(w):
                self.assertNotIn((x + i, y), covered, "no rects overlap")
                covered.add((x + i, y))
        self.assertEqual(len(covered), 64)
        self.assertIn('width="8" height="8"', art)

    def test_mote_points_make_a_mask_and_are_empty_in_the_art_unless_coloured(self) -> None:
        art, points = pixel_grid.draw(grid(square(mark="*")), self.palette)
        self.assertNotIn((3, 3), [(x, y) for x, y, w, h, c in rects(art) if x <= 3 < x + w and y == 3], "an uncoloured mote point is empty in the art")
        self.assertEqual(rects(points), [(3, 3, 1, 1, pixel_grid.MOTE_COLOUR)])
        coloured = grid(square(mark="s"), motes="s")
        art, points = pixel_grid.draw(coloured, self.palette)
        self.assertIn((1, 3, 6, 1, STONE), rects(art), "a coloured mote character is drawn too")
        self.assertEqual(sum(w for _, _, w, _, _ in rects(points)), 6 * 6, "every one of its pixels is a mote point")

    def test_a_bad_grid_says_what_is_wrong(self) -> None:
        cases = {
            "rows must be": {"rows": []},
            "not 8 like the first": grid(["oooooooo", "ooo"] + ["oooooooo"] * 6),
            "multiple of 8": grid(["ooooooo"] * 8),
            "not a palette colour": {"colours": {"x": "#123456"}, "rows": ["xxxxxxxx"] * 8},
            "neither a colour": grid(square(mark="?")),
        }
        for words, bad in cases.items():
            with self.assertRaises(pixel_grid.GridError) as caught:
                pixel_grid.draw(bad, self.palette)
            self.assertIn(words, str(caught.exception))

    def test_a_grid_file_writes_its_svgs_and_check_finds_them_stale(self) -> None:
        path = self.tmp / "crate.grid.json"
        path.write_text(json.dumps(grid(square(mark="*"))), encoding="utf-8")
        self.assertEqual(pixel_grid.build(path, colours_allowed=self.palette), [])
        art, motes = pixel_grid.outputs(path)
        self.assertEqual(art.name, "crate.svg")
        self.assertEqual(motes.name, "crate_motes.svg")
        self.assertTrue(art.exists() and motes.exists())
        self.assertEqual(pixel_grid.build(path, check=True, colours_allowed=self.palette), [])
        path.write_text(json.dumps(grid(square())), encoding="utf-8")
        stale = pixel_grid.build(path, check=True, colours_allowed=self.palette)
        self.assertTrue(stale and "differs" in stale[0], stale)
        self.assertEqual(pixel_grid.build(path, colours_allowed=self.palette), [])
        self.assertFalse(motes.exists(), "a grid with no mote points leaves no mask")

    def test_every_grid_in_the_repository_has_its_svgs_up_to_date(self) -> None:
        grids = [p for p in pixel_grid.ROOT.rglob("*" + pixel_grid.SUFFIX) if "build" not in p.relative_to(pixel_grid.ROOT).parts[:1]]
        self.assertTrue(grids, "the test exploding barrel's grids at least")
        for path in grids:
            self.assertEqual(pixel_grid.build(path, check=True, colours_allowed=self.palette), [], str(path))


if __name__ == "__main__":
    unittest.main()
