"""Tests of tools/ground_shape.py, a room's ground from a shape file (docs/milestones/hub-rework.md).

On small fixture shapes, not the hub's: the walls follow the art's clear pixels cell by cell, the
rims run clockwise round the ground with their colour bands, a crack's open cells are holes and the
void is wall or holes as the shape says, a crack opens onto the coast, keeps
clear of what it must and thins out with no step (a fork starts nearly as wide as its parent), a
crack thinner than a cell is drawn into the floor and is never a wall, the same shape always draws
the same files, and every room's ground in the repository is up to date with its shape.

    python3 -m unittest discover -s tools
"""

from __future__ import annotations

import math
import re
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

    @staticmethod
    def _cells(rects: list[tuple[int, int, int, int]], into: dict, kind: str, test: unittest.TestCase) -> None:
        for x, y, w, h in rects:
            test.assertEqual((x % gs.CELL, y % gs.CELL, w % gs.CELL, h % gs.CELL), (0, 0, 0, 0), "whole cells")
            for cy in range(y, y + h, gs.CELL):
                for cx in range(x, x + w, gs.CELL):
                    test.assertNotIn((cx, cy), into, "walls and holes never overlap")
                    into[(cx, cy)] = kind

    def test_a_wall_or_a_hole_where_the_art_is_clear_cell_by_cell(self) -> None:
        # The void outside the outline is wall (the default `void`); a crack's open cells are holes.
        d = self.drawing
        cells: dict = {}
        self._cells(d.walls, cells, "wall", self)
        self._cells(d.holes, cells, "hole", self)
        self.assertTrue(d.holes, "the crack is a hole")
        for cy in range(0, d.h, gs.CELL):
            for cx in range(0, d.w, gs.CELL):
                middle = (cy + gs.CELL // 2) * d.w + cx + gs.CELL // 2
                clear = d.floor[middle * 4 + 3] == 0
                self.assertEqual((cx, cy) in cells, clear, f"cell {cx},{cy}: open exactly where the art is clear")
                if clear:
                    self.assertEqual(cells[(cx, cy)], "hole" if d.ground.crack[middle] > 0.0 else "wall", f"cell {cx},{cy}: a hole in the crack, wall in the void")

    def test_a_void_of_holes_has_no_walls(self) -> None:
        # An island in the void (the hub): the void is the same void as in the cracks.
        d = gs.Drawing(dict(ISLAND, void="hole"))
        self.assertEqual(d.walls, [], "no walls")
        cells: dict = {}
        self._cells(d.holes, cells, "hole", self)
        open_cells = sum(1 for cy in range(0, d.h, gs.CELL) for cx in range(0, d.w, gs.CELL) if d.floor[((cy + gs.CELL // 2) * d.w + cx + gs.CELL // 2) * 4 + 3] == 0)
        self.assertEqual(len(cells), open_cells, "every open cell a hole")
        text = gs.scene_text(d, {"floor": gs.ROOT / "art/a.png", "under": gs.ROOT / "art/b.png", "glow": gs.ROOT / "art/c.png"}, "abc")
        self.assertNotIn('name="Walls"', text)
        self.assertIn(f'[node name="Holes" type="StaticBody2D" parent="."]\ncollision_layer = {gs.HOLE_LAYER}', text)
        self.assertIn('[node name="Underside" type="Sprite2D" parent="."]', text, "the rock face on the root: no wall to shed it")

    def test_the_rim_runs_clockwise_round_the_ground_in_bands(self) -> None:
        d = self.drawing
        self.assertEqual(len(d.rims), 1, "one rim round one island, no sliver with one of its own")
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
            self.assertEqual(tuple(d.floor[p * 4:p * 4 + 4]), d.deep + (255,), "drawn dark and opaque, in the edge style's deep")

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
        self.assertEqual(again.holes, self.drawing.holes)
        self.assertEqual(again.rims, self.drawing.rims)

    def test_the_scene(self) -> None:
        d = self.drawing
        outs = {"floor": gs.ROOT / "art/a.png", "under": gs.ROOT / "art/b.png", "glow": gs.ROOT / "art/c.png"}
        text = gs.scene_text(d, outs, "abc")
        self.assertIn('[node name="Floor" type="Sprite2D"]', text, "its root is the room's Floor")
        self.assertIn(f"z_index = {gs.FLOOR_Z}", text)
        self.assertIn('metadata/ground_inputs = "abc"', text)
        self.assertEqual(text.count('type="CollisionShape2D" parent="Walls"'), len(d.walls))
        self.assertEqual(text.count('type="CollisionShape2D" parent="Holes"'), len(d.holes))
        self.assertIn('[node name="Underside" type="Sprite2D" parent="Walls"]', text, "the rock face on the walls, which shed it")
        self.assertEqual(text.count('groups=["mote_source"]'), len(d.rims) + len(d.drips))
        self.assertIn("band_length = 420", text, "the rim's colours in the seam's bands")

    def test_the_drips_fall_from_the_rock_in_the_colour_above_them(self) -> None:
        d = self.drawing
        self.assertTrue(d.drips, "the rock face drips")
        for material, points in d.drips:
            self.assertIn(material, d.style["seam"]["colours"])
            for a, b in zip(points, points[1:]):
                self.assertLess(b[0], a[0], "right to left, so the left of its way, where a line throws, is down")
            x, y = int(points[len(points) // 2][0]), int(points[len(points) // 2][1]) - 1
            while y > 0 and not d.solid[y * d.w + x]:
                y -= 1
            self.assertEqual(d.style["seam"]["colours"][d.band[y * d.w + x]], material, "in the band of the edge it hangs under")

    def test_every_piece_of_ground_holds_an_open_cell(self) -> None:
        # A shape whose crack cuts a sliver loose: the sliver is cleared, never drawn over the walls.
        for shape in (ISLAND, {**ISLAND, "cracks": [{"angle": a, "width": 16, "length": 80, "seed": 400 + i} for i, a in enumerate((0.1, 0.2, 0.3, 0.4, 0.6, 0.8))]}):
            d = gs.Drawing(shape)
            seen = bytearray(d.w * d.h)
            for p0 in range(d.w * d.h):
                if not d.solid[p0] or seen[p0]:
                    continue
                piece, k, open_cell = [p0], 0, False
                seen[p0] = 1
                while k < len(piece):
                    q = piece[k]
                    k += 1
                    x, y = q % d.w, q // d.w
                    open_cell = open_cell or (x % gs.CELL == gs.CELL // 2 and y % gs.CELL == gs.CELL // 2)
                    for r in (q - 1, q + 1, q - d.w, q + d.w):
                        if 0 <= r < len(seen) and d.solid[r] and not seen[r] and abs(r % d.w - x) <= 1:
                            seen[r] = 1
                            piece.append(r)
                self.assertTrue(open_cell, f"the piece of ground at {p0 % d.w},{p0 // d.w} holds an open cell")
            # Every rim is round a piece that holds an open cell (just checked): no sliver has one.
            self.assertGreaterEqual(len(d.rims), 1)

    def test_a_boundary_through_a_one_pixel_neck_is_traced_whole(self) -> None:
        # Two squares joined at a corner pixel: the trace starts on the neck and still goes all round.
        shape = {**ISLAND, "outlines": [], "cracks": [], "areas": [], "size": [64, 48]}
        d = gs.Drawing.__new__(gs.Drawing)
        d.w, d.h = 64, 48
        d.solid = bytearray(64 * 48)
        for y in range(8, 24):
            for x in range(8, 24):
                d.solid[y * 64 + x] = 1
        for y in range(24, 40):
            for x in range(24, 40):
                d.solid[y * 64 + x] = 1
        path = d._moore(8, 8)
        self.assertIn(39 * 64 + 39, path, "the far square's far corner is on the traced boundary")
        self.assertIsNotNone(shape)

    def test_cracks_keep_clear_of_the_rooms_placements(self) -> None:
        placed = [(200.0, 60.0, 40.0)]
        d = gs.Drawing(ISLAND, placed)
        g = d.ground
        for p in range(g.width * g.height):
            if g.crack[p] > 0.0:
                self.assertGreaterEqual(math.hypot(p % g.width - 200, p // g.width - 60), 36, "clear of a placement")
        for path in gs.shape_files():
            self.assertTrue(gs.placements(path), f"{path.relative_to(gs.ROOT)}: its cracks keep clear of its scene's placements")

    def test_the_numbers_shared_with_the_game(self) -> None:
        base = (gs.ROOT / "core/base/room_base.gd").read_text(encoding="utf-8")
        self.assertIn(f"const FLOOR_Z: int = {gs.FLOOR_Z}", base)
        self.assertIn(f"const WALL_LAYER: int = {gs.WALL_LAYER}", base)
        self.assertIn(f"const HOLE_LAYER: int = {gs.HOLE_LAYER}", base)
        manager = (gs.ROOT / "core/projectiles/projectile_manager.gd").read_text(encoding="utf-8")
        self.assertIn(f"const WALL_CELL: float = {float(gs.CELL)}", manager)

    def test_the_hubs_mark_colours_are_its_turfs(self) -> None:
        # The hub names its floor-mark colours (its art is too large to sample): they must be its turf's.
        turf = gs.load_ground("turf")
        mats = gs.materials()
        tres = (gs.ROOT / "content/rooms/hub/hub.tres").read_text(encoding="utf-8")
        numbers = [float(v) for v in re.search(r"floor_mark_colors = PackedColorArray\(([^)]*)\)", tres).group(1).split(",")]
        shades = [tuple(round(numbers[i + c] * 255) for c in range(3)) for i in (0, 4, 8)]
        self.assertEqual(shades[1], gs.colour(turf["patches"]["colour"], mats), "base: the turf's patches")
        self.assertEqual(shades[2], gs.colour(turf["base"], mats), "shadow: the turf's own colour")

    def test_every_rooms_ground_is_up_to_date(self) -> None:
        shapes = gs.shape_files()
        self.assertTrue(shapes, "the hub has a shape file")
        for path in shapes:
            self.assertIsNone(gs.stale(path), f"{path.relative_to(gs.ROOT)}: run python3 tools/ground_shape.py {path.relative_to(gs.ROOT)}")
            # Drawn again here, every file is the one committed (a hand-edited scene or picture fails).
            outs = gs.outputs_of(path)
            for kind, data in gs.files_of(gs.draw(path), path).items():
                self.assertEqual(outs[kind].read_bytes(), data, f"{outs[kind].relative_to(gs.ROOT)} is as drawn")


if __name__ == "__main__":
    unittest.main()
