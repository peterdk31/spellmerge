"""Tests of tools/ground_shape.py, a room's ground from a shape file (docs/milestones/hub-rework.md).

On small fixture shapes, not the hub's: the walls follow the art's clear pixels cell by cell, the
rims run clockwise round the ground with their colour bands, a crack's open cells are holes and the
void is wall or holes as the shape says, a crack opens onto the coast, keeps
clear of what it must and thins out with no step (a fork starts nearly as wide as its parent), a
crack thinner than a cell is drawn into the floor and is never a wall, the same shape always draws
the same files, and every room's ground in the repository is up to date with its shape. A hall
inside walls (the crypt rework, docs/milestones/crypt-rework.md): its frame wanders, is pinned and
keeps clear of what stands in the room; its pits are holes with an edge style of their own, their
rims throwing into the pit and their cracks running outward; its walls have their own art (a face
over the floor's top edges); its floor is slabbed. A floating crypt room (`crypt_edge`, the owner's
second round): no wall art, the slab's rock underside hanging under its south edges, dust falling
off its edge, and its edge still an invisible wall.

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

HALL = {
    "size": [320, 224],
    "seed": 11,
    "edge": "crypt_wall",
    "pit_edge": "crypt_pit",
    "ground": "flagstone",
    "frame": {"inset": 32, "corner": 16, "wander": [14, 20], "rough": [48, 18, 7], "seed": 4,
              "pins": [[144, 0, 176, 34]], "bays": [[40, 180, 22]]},
    "areas": [{"ground": "swept", "centre": [120, 110], "radii": [40, 30], "seed": 2}],
    "pits": [{"centre": [220, 130], "radii": [30, 20], "rough": [[30, 0.12], [10, 0.05]], "seed": 8}],
    "cracks": [{"pit": 0, "angle": 0.5, "width": 9, "length": 40, "seed": 5}],
}
# Where the hall's things stand: its frame's floor is pushed out to these.
HALL_CLEAR = [(60.0, 40.0, 24.0)]


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
        grid = (gs.ROOT / "core/projectiles/room_grid.gd").read_text(encoding="utf-8")
        self.assertIn(f"const WALL_CELL: float = {float(gs.CELL)}", grid)

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


class HallTest(unittest.TestCase):
    """A hall inside walls, its pit and its art (the crypt rework)."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.drawing = gs.Drawing(HALL, [], HALL_CLEAR)

    def _cell_open(self, x: int, y: int) -> bool:
        d = self.drawing
        return not d.solid[(y + gs.CELL // 2) * d.w + x + gs.CELL // 2]

    def test_no_ledge_is_too_narrow_to_stand_beside(self) -> None:
        # Every open cell of a hall lies in a block of 3x3 open cells or beside one: a ledge too
        # narrow for a wizard is trimmed off, so nothing pushed there is out of reach (CR3).
        rough = {**HALL, "frame": {**HALL["frame"], "rough": [20, 7, 3], "wander": [16, 22]}}
        for d in (self.drawing, gs.Drawing(rough, [], HALL_CLEAR)):
            cols, rows = d.w // gs.CELL, d.h // gs.CELL
            open_ = {(c, r) for r in range(rows) for c in range(cols)
                     if d.solid[(r * gs.CELL + gs.CELL // 2) * d.w + c * gs.CELL + gs.CELL // 2]}
            fits = {(c, r) for c, r in open_ if all((c + dc, r + dr) in open_ for dc in (-1, 0, 1) for dr in (-1, 0, 1))}
            for c, r in open_:
                self.assertTrue(any((c + dc, r + dr) in fits for dc in (-1, 0, 1) for dr in (-1, 0, 1)),
                                f"the floor at {c * gs.CELL},{r * gs.CELL} lies beside room to stand")
            self.assertGreater(len(fits), len(open_) // 2, "the hall is still mostly floor")

    def test_the_frame_wanders_but_its_border_cell_is_always_wall(self) -> None:
        d = self.drawing
        for x in range(0, d.w, gs.CELL):
            self.assertTrue(self._cell_open(x, 0) and self._cell_open(x, d.h - gs.CELL), "the top and bottom border cells are wall")
        for y in range(0, d.h, gs.CELL):
            self.assertTrue(self._cell_open(0, y) and self._cell_open(d.w - gs.CELL, y), "the side border cells are wall")
        depths = set()
        for x in range(48, d.w - 48):
            y = 0
            while y < d.h // 2 and not d.solid[y * d.w + x]:
                y += 1
            depths.add(y)
            self.assertGreaterEqual(y, 32 - 20 - 1, f"column {x}: the wall wanders out no more than the frame's wander")
            self.assertLessEqual(y, 32 + 14 + 1, f"column {x}: the wall wanders in no more than the frame's wander")
        self.assertGreater(len(depths), 8, "the top wall's edge wanders, never a straight line")

    def test_a_pin_holds_the_edge_to_the_frames_line(self) -> None:
        d = self.drawing
        for x in range(144, 177):
            self.assertFalse(d.solid[31 * d.w + x], f"column {x}: wall above the line under the pin")
            self.assertTrue(d.solid[32 * d.w + x], f"column {x}: floor from the line under the pin")

    def test_the_floor_reaches_round_what_stands_in_the_room(self) -> None:
        d = self.drawing
        for cx, cy, r in HALL_CLEAR:
            for y in range(int(cy - r) + 1, int(cy + r)):
                for x in range(int(cx - r) + 1, int(cx + r)):
                    if math.hypot(x + 0.5 - cx, y + 0.5 - cy) < r - 1 and x >= gs.CELL and y >= gs.CELL:
                        self.assertTrue(d.solid[y * d.w + x], f"{x},{y}: floor round a thing that stands there")

    def test_a_pit_is_a_hole_with_its_own_edge_style(self) -> None:
        d = self.drawing
        g = d.ground
        cells: dict = {}
        GroundShapeTest._cells(d.walls, cells, "wall", self)
        GroundShapeTest._cells(d.holes, cells, "hole", self)
        middle = (130 // gs.CELL * gs.CELL, 128 // gs.CELL * gs.CELL)
        self.assertEqual(cells.get((216, 128)), "hole", "the pit's middle cell is a hole")
        self.assertNotIn(middle, cells, "the floor beside it is open ground")
        for (cx, cy), kind in cells.items():
            p = (cy + gs.CELL // 2) * d.w + cx + gs.CELL // 2
            self.assertEqual(kind, "hole" if (g.pit[p] or g.crack[p] > 0.0) else "wall", f"cell {cx},{cy}: a hole in the pit or its crack, else wall")
        self.assertEqual(d.side[130 * d.w + 220], 1, "the pit is the pit's side")
        self.assertEqual(d.side[112 * d.w + 64], 0, "beside the west wall, the walls' side")

    def test_the_pits_rim_throws_into_the_pit(self) -> None:
        d = self.drawing
        self.assertEqual(d.rim_sides, [1], "one rim, round the pit: the walls' style has no motes")
        rim = d.rims[0]
        into = 0
        for i in range(len(rim)):
            a, b = rim[i], rim[(i + 1) % len(rim)]
            dx, dy = b[0] - a[0], b[1] - a[1]
            length = math.hypot(dx, dy) or 1.0
            x, y = int(a[0] + dy / length * 3), int(a[1] - dx / length * 3)
            into += not d.solid[y * d.w + x]
        self.assertGreater(into, len(rim) * 0.9, "the left of the rim's way, where a line throws its motes, is the pit")
        text = gs.scene_text(d, {k: gs.ROOT / f"art/{k}.png" for k in ("floor", "under", "glow", "wall")}, "abc")
        self.assertIn('kind = &"pit_dust"', text)
        self.assertIn('colours = Array[StringName]([&"stone", &"bone"])', text, "the rim's own colours")
        self.assertNotIn("band_length", text, "no bands: the rim names its colours")

    def test_a_crack_from_a_pit_runs_outward(self) -> None:
        g = self.drawing.ground
        cracked = [p for p in range(g.width * g.height) if g.crack[p] > 0.0]
        self.assertTrue(cracked, "the crack is carved")
        for p in cracked:
            self.assertEqual(g.pit_side[p], 1, "a crack from a pit is the pit's side")
        self.assertLess(min(p % g.width for p in cracked), 220 - 30 - 10, "it runs out from the pit's west edge, angle 0.5")

    def test_the_walls_have_their_own_art_and_a_face(self) -> None:
        d = self.drawing
        g = d.ground
        self.assertIsNotNone(d.wall_art)
        for p in range(d.w * d.h):
            wall = not d.solid[p] and g.crack[p] == 0.0 and not g.pit[p]
            self.assertEqual(d.wall_art[p * 4 + 3] == 255, wall, f"pixel {p % d.w},{p // d.w}: the wall art covers the walls, only")
        face = d.style["face"]
        light = gs.colour(face["light"], d.mats)
        x = 160
        y = 32
        self.assertEqual(tuple(d.wall_art[((y - face["height"]) * d.w + x) * 4:((y - face["height"]) * d.w + x) * 4 + 3]), light,
                         "the face's lit top row, its height above the floor's top edge")
        text = gs.scene_text(d, {k: gs.ROOT / f"art/{k}.png" for k in ("floor", "under", "glow", "wall")}, "abc")
        self.assertIn('[node name="WallArt" type="Sprite2D" parent="Walls"]', text, "on the walls, which shed it")
        self.assertIn('[node name="Underside" type="Sprite2D" parent="."]', text, "the pit's shaft on the root, never shed by a wall")

    def test_a_style_without_seam_rock_glow_or_motes(self) -> None:
        d = gs.Drawing({k: v for k, v in HALL.items() if k not in ("pits", "cracks", "pit_edge")}, [], HALL_CLEAR)
        self.assertEqual((d.rims, d.drips), ([], []), "no motes")
        self.assertFalse(any(d.glow[3::4]), "no glow")
        self.assertFalse(any(d.under[3::4]), "no rock face")
        self.assertFalse(d.holes, "no holes")

    def test_slabs_never_tile(self) -> None:
        d = self.drawing
        joint = gs.colour(gs.load_ground("flagstone")["slabs"]["joint"], d.mats)
        joints = [p for p in range(d.w * d.h) if d.ground.land[p] and tuple(d.floor[p * 4:p * 4 + 3]) == joint]
        self.assertGreater(len(joints), 500, "the flagstones' joints are drawn")
        size = int(gs.load_ground("flagstone")["slabs"]["size"])
        rows = [bytes(d.floor[(y * d.w + 60) * 4:(y * d.w + 260) * 4]) for y in (80, 80 + size, 80 + 2 * size)]
        self.assertNotEqual(rows[0], rows[1], "no row repeats a slab's size lower")
        self.assertNotEqual(rows[1], rows[2])

    def test_strokes_go_round_the_middle_not_out_from_it(self) -> None:
        import ground_materials as gm
        mats = gs.materials()
        spec = {"base": "#433f5b", "strokes": {"colour": "#8a86aa", "spacing": 9, "share": 0.5, "inner": 20}}
        m = gm.Material(spec, 0, 1, (240, 240), (120.0, 120.0), lambda c: gs.colour(c, mats), gm.Noise(gs.unit, gs.noise1, gs.fbm2))
        base = gs.colour("#433f5b", mats)

        def on(x: float, y: float) -> bool:
            return m.at(int(x), int(y)) != base

        # Out from the middle, a stroke is crossed in a pixel or two at a time: rings, never spokes.
        longest_out = 0
        for k in range(16):
            a = k / 16 * math.tau
            run = 0
            for r in range(24, 110):
                run = run + 1 if on(120 + math.cos(a) * r, 120 + math.sin(a) * r) else 0
                longest_out = max(longest_out, run)
        self.assertLessEqual(longest_out, 3, "a stroke is crossed going out")
        # Round the middle, a stroke runs on for a long way.
        longest_round = 0
        for r in range(30, 100):
            run = 0
            for k in range(720):
                a = k / 720 * math.tau
                run = run + 1 if on(120 + math.cos(a) * r, 120 + math.sin(a) * r) else 0
                longest_round = max(longest_round, run)
        self.assertGreater(longest_round, 30, "a stroke runs round the middle, a long way (a spoke is crossed in a few)")

    def test_the_inputs_hash_reads_every_edge_style(self) -> None:
        import json
        import tempfile
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "room.shape.json"
            path.write_text(json.dumps(HALL), encoding="utf-8")
            first = gs.inputs_hash(path)
            path.write_text(json.dumps({**HALL, "pit_edge": "magic"}), encoding="utf-8")
            self.assertNotEqual(gs.inputs_hash(path), first)


class FloatingHallTest(unittest.TestCase):
    """A floating crypt room (crypt rework CR-G, `crypt_edge`): a slab of floor hanging in the dark,
    its edge an invisible wall."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.shape = {**HALL, "edge": "crypt_edge"}
        cls.drawing = gs.Drawing(cls.shape, [], HALL_CLEAR)

    def test_the_edge_is_an_invisible_wall(self) -> None:
        d = self.drawing
        g = d.ground
        self.assertIsNone(d.wall_art, "no wall art: no masonry, no top, no face")
        cells: dict = {}
        GroundShapeTest._cells(d.walls, cells, "wall", self)
        for y in range(0, d.h, gs.CELL):
            for x in range(0, d.w, gs.CELL):
                p = (y + gs.CELL // 2) * d.w + x + gs.CELL // 2
                if not d.solid[p] and not g.pit[p] and g.crack[p] == 0.0:
                    self.assertEqual(cells.get((x, y)), "wall", f"cell {x},{y}: off the slab, a wall stops a body")
        text = gs.scene_text(d, {k: gs.ROOT / f"art/{k}.png" for k in ("floor", "under", "glow", "wall")}, "abc")
        self.assertNotIn("WallArt", text)
        self.assertIn('[node name="Walls" type="StaticBody2D"', text)

    def test_the_slabs_underside_hangs_under_its_south_edge(self) -> None:
        d = self.drawing
        rock = gs.load_style("crypt_edge")["rock"]
        hung = 0
        for x in range(64, d.w - 64):
            y = d.h - 1
            while y > 0 and not d.solid[y * d.w + x]:
                y -= 1
            # the first pixel under the floor's south edge
            below = (y + 1) * d.w + x
            if y + 1 < d.h and d.under[below * 4 + 3] == 255:
                hung += 1
        self.assertGreater(hung, (d.w - 128) * 0.9, "the rock hangs under the south edge")
        self.assertGreaterEqual(rock["depth"][1], 32, "deep enough to read as a slab's underside")
        self.assertNotIn("glow", gs.load_style("crypt_edge"), "no glow along the slab's edge (only its pit's)")

    def test_dust_falls_off_its_edge(self) -> None:
        d = self.drawing
        self.assertEqual(sorted(d.rim_sides), [0, 1], "a rim round the slab and one round its pit")
        text = gs.scene_text(d, {k: gs.ROOT / f"art/{k}.png" for k in ("floor", "under", "glow", "wall")}, "abc")
        self.assertEqual(text.count('kind = &"pit_dust"'), 2, "dust off the slab's edge and into its pit")

    def test_its_lip_is_broken_stone(self) -> None:
        d = self.drawing
        load = gs.load_style

        def bare(edge_id: str) -> dict:
            style = load(edge_id)
            if edge_id == "crypt_edge":
                style["lip"] = {k: v for k, v in style["lip"].items() if k not in ("rubble", "pebbles")}
            return style
        gs.load_style = bare
        try:
            plain = gs.Drawing(self.shape, [], HALL_CLEAR)
        finally:
            gs.load_style = load
        changed = sum(1 for p in range(d.w * d.h) if d.floor[p * 4:p * 4 + 4] != plain.floor[p * 4:p * 4 + 4])
        self.assertGreater(changed, 300, "stones and grit lie along its lip")

    def test_a_floating_room_with_no_pit_hangs_its_underside_on_the_walls(self) -> None:
        d = gs.Drawing({k: v for k, v in self.shape.items() if k not in ("pits", "cracks", "pit_edge")}, [], HALL_CLEAR)
        text = gs.scene_text(d, {k: gs.ROOT / f"art/{k}.png" for k in ("floor", "under", "glow", "wall")}, "abc")
        self.assertIn('[node name="Underside" type="Sprite2D" parent="Walls"]', text, "a hit on the edge sheds the rock's colours")
        self.assertTrue(any(d.under[3::4]), "the rock is drawn")


class FixtureHashesTest(unittest.TestCase):
    """The test shapes the game's drawing is held to this one by (connected biomes CB4,
    tests/gameplay/feel/test_ground_drawing.gd): their hashes are what this generator draws now."""

    def test_the_fixture_hashes_are_up_to_date(self) -> None:
        self.assertEqual(gs.FIXTURE_HASHES.read_text(encoding="utf-8"), gs.fixture_text(),
                         "run python3 tools/ground_shape.py --fixtures")

    def test_a_number_is_read_as_the_game_reads_it(self) -> None:
        self.assertEqual(gs.single("312.5"), 312.5)
        self.assertNotEqual(gs.single("312.7"), 312.7)


if __name__ == "__main__":
    unittest.main()
