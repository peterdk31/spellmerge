"""Tests of tools/ground_shape.py, a room's ground from a shape file (docs/milestones/hub-rework.md).

On small fixture shapes, not the hub's: the walls follow the art's clear pixels cell by cell, the
rims run clockwise round the ground with their colour bands, a crack opens onto the coast, keeps
clear of what it must and thins out with no step (a fork starts nearly as wide as its parent), a
crack thinner than a cell is drawn into the floor and is never a wall, the same shape always draws
the same files, and every room's ground in the repository is up to date with its shape.

    python3 -m unittest discover -s tools
"""

from __future__ import annotations

import math
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import ground_shape as gs  # noqa: E402

ISLAND = {
    "size": [320, 224],
    "seed": 5,
    "edge": "magic",
    "ground": "turf",
    "outlines": [{"centre": [160, 112], "radii": [130, 80], "waves": [[3, 0.06, 1.0]], "rough": [[60, 0.08], [12, 0.03]], "seed": 3}],
    "areas": [{"ground": "earth", "centre": [120, 100], "radii": [30, 20], "rough": [[20, 0.2]], "seed": 9}],
    "cracks": [{"angle": 0.3, "width": 14, "length": 60, "seed": 301}],
    "keep_clear": [[120, 100, 28]],
}


class GroundShapeTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.drawing = gs.Drawing(ISLAND)

    def test_palette_and_colours(self) -> None:
        mats = gs.materials()
        self.assertEqual(mats["leaf"][1], (0x5B, 0x72, 0x33), "Leaf's base, read from core/base/palette.gd")
        self.assertEqual(gs.colour("fire.light", mats), (0xFF, 0xA2, 0x3C))
        self.assertEqual(gs.colour("#102030", mats), (0x10, 0x20, 0x30))
        with self.assertRaises(ValueError):
            gs.colour("teal.base", mats)

    def test_png_round_trip(self) -> None:
        few = bytearray([10, 20, 30, 255, 0, 0, 0, 0] * 6)
        self.assertEqual(gs.read_png(gs.png(4, 3, few)), (4, 3, few), "indexed")
        many = bytearray(i % 256 for i in range(4 * 300))
        self.assertEqual(gs.read_png(gs.png(30, 10, many)), (30, 10, many), "true colour with alpha")

    def test_an_outline_runs_clockwise_on_screen(self) -> None:
        points = gs.outline_points(ISLAND["outlines"][0])
        area = sum(points[i][0] * points[(i + 1) % len(points)][1] - points[(i + 1) % len(points)][0] * points[i][1] for i in range(len(points)))
        self.assertGreater(area, 0.0, "y grows down, so a positive area is clockwise on screen")

    def test_a_wall_where_the_art_is_clear_cell_by_cell(self) -> None:
        d = self.drawing
        cells = {}
        for x, y, w, h in d.walls:
            self.assertEqual((x % gs.CELL, y % gs.CELL, w % gs.CELL, h % gs.CELL), (0, 0, 0, 0), "whole cells")
            for cy in range(y, y + h, gs.CELL):
                for cx in range(x, x + w, gs.CELL):
                    self.assertNotIn((cx, cy), cells, "walls never overlap")
                    cells[(cx, cy)] = True
        for cy in range(0, d.h, gs.CELL):
            for cx in range(0, d.w, gs.CELL):
                middle = (cy + gs.CELL // 2) * d.w + cx + gs.CELL // 2
                clear = d.floor[middle * 4 + 3] == 0
                self.assertEqual((cx, cy) in cells, clear, f"cell {cx},{cy}: a wall exactly where the art is clear")

    def test_the_rim_runs_clockwise_round_the_ground_in_bands(self) -> None:
        d = self.drawing
        self.assertEqual(len(d.rims), 1, "one rim round one island")
        rim = d.rims[0]
        area = sum(rim[i][0] * rim[(i + 1) % len(rim)][1] - rim[(i + 1) % len(rim)][0] * rim[i][1] for i in range(len(rim)))
        self.assertGreater(area, 0.0, "clockwise: the void on the left of the way it runs")
        for x, y in rim:
            self.assertTrue(d.solid[int(y) * d.w + int(x)], f"rim point {x},{y} lies on the ground's edge")
        length = d.style["seam"]["band_length"]
        count = len(d.style["seam"]["colours"])
        run = 0.0
        for i, point in enumerate(rim):
            if i:
                run += math.dist(rim[i - 1], point)
            x, y = int(point[0]), int(point[1])
            self.assertEqual(d.band[y * d.w + x], int(run / length) % count, "its band by how far along the rim, as MoteSource.band_length gives the motes")

    def test_a_crack_opens_onto_the_coast_and_keeps_clear(self) -> None:
        g = self.drawing.ground
        inside = bytearray(g.width * g.height)
        gs.fill_polygon(inside, g.width, g.height, g.outlines[0], 1)
        cracked = [p for p in range(g.width * g.height) if g.crack[p] > 0.0]
        self.assertTrue(cracked, "the crack is carved")
        mouth = any(not inside[q] for p in cracked for q in (p - 1, p + 1, p - g.width, p + g.width) if 0 <= q < len(inside))
        self.assertTrue(mouth, "the crack meets the void outside the coast: its mouth is open")
        for cx, cy, r in ISLAND["keep_clear"]:
            for p in cracked:
                self.assertGreaterEqual(math.hypot(p % g.width - cx, p // g.width - cy), r - 4, "clear of a keep_clear circle")

    def test_a_thin_crack_is_drawn_into_the_floor_never_a_wall(self) -> None:
        d = self.drawing
        thin = [p for p in range(d.w * d.h) if 0.0 < d.ground.crack[p] < gs.CELL]
        self.assertTrue(thin, "the crack thins out below a cell")
        for p in thin:
            self.assertTrue(d.solid[p], "a thin crack is ground to stand on")
            self.assertEqual(tuple(d.floor[p * 4:p * 4 + 4]), gs.DEEP + (255,), "drawn dark and opaque")

    def test_a_crack_thins_out_with_no_step(self) -> None:
        widths: list[float] = []
        stamp = gs.Ground._stamp

        def logged(self, x, y, w):  # noqa: ANN001
            widths.append(w)
            stamp(self, x, y, w)

        gs.Ground._stamp = logged
        try:
            gs.Ground(ISLAND)
        finally:
            gs.Ground._stamp = stamp
        self.assertGreater(len(widths), 20)
        for before, after in zip(widths, widths[1:]):
            # A fork starts at nine tenths of its parent; along a crack it narrows a little a step.
            self.assertGreaterEqual(after, before * 0.85, f"a step from {before:.1f} to {after:.1f} px wide")
        d = self.drawing
        ts = sorted({round(d.t[p], 3) for p in range(d.w * d.h) if d.t[p] < 1.0})
        self.assertGreater(len(ts), 20, "the edge fades over many widths, not in one step")

    def test_the_same_shape_draws_the_same_files(self) -> None:
        again = gs.Drawing(ISLAND)
        self.assertEqual(again.floor, self.drawing.floor)
        self.assertEqual(again.under, self.drawing.under)
        self.assertEqual(again.glow, self.drawing.glow)
        self.assertEqual(again.walls, self.drawing.walls)
        self.assertEqual(again.rims, self.drawing.rims)

    def test_the_scene(self) -> None:
        d = self.drawing
        outs = {"floor": gs.ROOT / "art/a.png", "under": gs.ROOT / "art/b.png", "glow": gs.ROOT / "art/c.png"}
        text = gs.scene_text(d, outs, "abc")
        self.assertIn('[node name="Floor" type="Sprite2D"]', text, "its root is the room's Floor")
        self.assertIn(f"z_index = {gs.FLOOR_Z}", text)
        self.assertIn('metadata/ground_inputs = "abc"', text)
        self.assertEqual(text.count('type="CollisionShape2D" parent="Walls"'), len(d.walls))
        self.assertEqual(text.count('groups=["mote_source"]'), len(d.rims) + len(d.drips))
        self.assertIn("band_length = 420", text, "the rim's colours in the seam's bands")

    def test_every_rooms_ground_is_up_to_date(self) -> None:
        shapes = gs.shape_files()
        self.assertTrue(shapes, "the hub has a shape file")
        for path in shapes:
            self.assertIsNone(gs.stale(path), f"{path.relative_to(gs.ROOT)}: run python3 tools/ground_shape.py {path.relative_to(gs.ROOT)}")


if __name__ == "__main__":
    unittest.main()
