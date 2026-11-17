"""Ground materials, drawn per pixel (content/grounds/README.md; docs/milestones/crypt-rework.md,
"Built for every room"). Used by tools/ground_shape.py, which works out where each material lies;
this only says what colour a pixel of a material is.

A material (`content/grounds/<id>/ground.json`) is a `base` colour and, each optional:

- `patches`: soft patches of another colour where smooth noise is above a level;
- `speckle`: flecks, `[colour, share]` pairs;
- `slabs`: irregular flagstones from a seeded cell pattern (never a tile, so no grid shows): their
  `size` in pixels, how far each slab's middle strays (`jitter`, 0 to 1), how much flatter than wide
  they are (`squash`), a second colour each slab's tone leans toward by chance (`tone`, `vary`), the
  joints' colour and width (`joint`, `joint_width`), and a lit upper edge (`light`, `light_width`);
- `toward_edge`: a colour mixed in by noise, more of it the nearer the floor's edge (dust and grit at
  a wall's foot: a material, not a shadow), within `reach` pixels, at most `most` of a pixel's share;
- `strokes`: faint broken arcs round the area's middle in a colour (a broom's sweeping): rings
  `spacing` pixels apart, wavering, `share` of each ring drawn in long pieces, from `inner` pixels
  out.

Python 3.10 and the standard library only (tools/README.md); the same inputs give the same pixels.
"""

from __future__ import annotations

import math
from typing import Callable

# The colour helpers and the noise are the generator's (one definition of each).
Colour = tuple[int, int, int]


class Material:
    """One ground material ready to draw: its colours looked up once, its patches' noise worked out
    on a coarse grid over the room (cheap) and read back."""

    # The patches' noise is worked out every this many pixels and read back between.
    STEP = 4

    def __init__(self, spec: dict, index: int, room_seed: int, size: tuple[int, int], centre: tuple[float, float],
                 colour: Callable[[str], Colour], tools: "Noise") -> None:
        self.spec = spec
        self.noise = tools
        self.base = colour(spec["base"])
        w, h = size
        self.cols = w // self.STEP + 2
        rows = h // self.STEP + 2
        patches = spec.get("patches")
        self.patch_map: list[float] | None = None
        self.patch_colour: Colour | None = None
        self.patch_above = 2.0
        if patches is not None:
            seed = room_seed * 13 + index * 101 + int(patches.get("seed", 0))
            self.patch_map = [tools.fbm2(cx * self.STEP, cy * self.STEP, patches["scales"], seed) for cy in range(rows) for cx in range(self.cols)]
            self.patch_colour = colour(patches["colour"])
            self.patch_above = float(patches.get("above", 0.5))
        self.speckles = [(colour(c), float(share)) for c, share in spec.get("speckle", [])]
        self.seed = room_seed * 7 + index * 31
        slabs = spec.get("slabs")
        self.slabs = slabs
        if slabs is not None:
            self.slab_size = float(slabs["size"])
            self.slab_jitter = float(slabs.get("jitter", 0.8))
            self.slab_squash = float(slabs.get("squash", 1.0))
            self.slab_tone = colour(slabs["tone"]) if "tone" in slabs else self.base
            self.slab_vary = float(slabs.get("vary", 0.0))
            self.joint = colour(slabs["joint"])
            self.joint_width = float(slabs.get("joint_width", 1.2))
            self.light = colour(slabs["light"]) if "light" in slabs else None
            self.light_width = float(slabs.get("light_width", 1.0))
        edge = spec.get("toward_edge")
        self.edge = edge
        if edge is not None:
            self.edge_colour = colour(edge["colour"])
            self.edge_reach = float(edge["reach"])
            self.edge_most = float(edge.get("most", 0.6))
            self.edge_scales = [float(s) for s in edge.get("scales", [10.0, 4.0])]
        strokes = spec.get("strokes")
        self.strokes = strokes
        if strokes is not None:
            self.stroke_colour = colour(strokes["colour"])
            self.stroke_spacing = float(strokes.get("spacing", 10.0))
            self.stroke_share = float(strokes.get("share", 0.4))
            self.stroke_inner = float(strokes.get("inner", 24.0))
            self.centre = centre

    def needs_edge_distance(self) -> bool:
        return self.edge is not None

    def at(self, x: int, y: int, edge_distance: float = 1e9) -> Colour:
        """The colour of this material at pixel (x, y); `edge_distance` is how far the pixel is from
        the floor's edge (only `toward_edge` reads it)."""
        rgb = self.base
        if self.slabs is not None:
            rgb = self._slab(x, y)
        if self.patch_map is not None and _bilinear(self.patch_map, self.cols, x / self.STEP, y / self.STEP) > self.patch_above:
            rgb = self.patch_colour
        if self.strokes is not None:
            rgb = self._stroke(x, y, rgb)
        roll = self.noise.unit(x, y, 4041)
        for speck, share in self.speckles:
            if roll < share:
                rgb = speck
                break
            roll -= share
        if self.edge is not None and edge_distance < self.edge_reach:
            near = 1.0 - edge_distance / self.edge_reach
            grit = self.noise.fbm2(x, y, self.edge_scales, self.seed + 77)
            share = min(self.edge_most, max(0.0, near * 1.6 * grit - 0.25))
            if share > 0.08:
                rgb = _mix(rgb, self.edge_colour, share)
        return rgb

    def _slab(self, x: int, y: int) -> Colour:
        """The flagstone this pixel lies in (the nearest of the jittered cell middles round it), its
        tone, and whether the pixel is on its joint or its lit upper edge."""
        s = self.slab_size
        sq = self.slab_squash
        fx, fy = (x + 0.5) / s, (y + 0.5) / (s * sq)
        cx0, cy0 = math.floor(fx), math.floor(fy)
        best = second = 1e18
        best_cell = (0, 0)
        best_dy = 0.0
        for cy in range(cy0 - 1, cy0 + 2):
            # Every other row is offset half a slab, so the joints never line up into a grid.
            shift = 0.5 if cy % 2 else 0.0
            for cx in range(cx0 - 1, cx0 + 2):
                px = (cx + shift + 0.5 + (self.noise.unit(self.seed, cx, cy, 1) - 0.5) * self.slab_jitter) * s
                py = (cy + 0.5 + (self.noise.unit(self.seed, cx, cy, 2) - 0.5) * self.slab_jitter) * s * sq
                dx, dy = x + 0.5 - px, (y + 0.5 - py) / sq
                d = dx * dx + dy * dy
                if d < best:
                    second = best
                    best = d
                    best_cell = (cx, cy)
                    best_dy = dy
                elif d < second:
                    second = d
        edge = math.sqrt(second) - math.sqrt(best)
        if edge < self.joint_width:
            return self.joint
        rgb = _mix(self.base, self.slab_tone, self.noise.unit(self.seed, best_cell[0], best_cell[1], 3) * self.slab_vary)
        # The upper edge of a slab (its middle lies below the pixel) catches the light.
        if self.light is not None and edge < self.joint_width + self.light_width and best_dy < 0.0:
            rgb = self.light
        return rgb

    def _stroke(self, x: int, y: int, rgb: Colour) -> Colour:
        """On a stroke: a ring round the centre every `stroke_spacing` pixels, one pixel wide, its
        radius wavering slowly with the angle, broken into pieces about 40 px long of which
        `stroke_share` are drawn (each ring its own)."""
        cx, cy = self.centre
        dx, dy = x + 0.5 - cx, y + 0.5 - cy
        r = math.hypot(dx, dy)
        if r < self.stroke_inner:
            return rgb
        turn = (math.atan2(dy, dx) / math.tau) % 1.0
        r += (self.noise.noise1(turn * 6.0, self.seed + 9, 6) - 0.5) * self.stroke_spacing * 0.8
        ring = math.floor(r / self.stroke_spacing + 0.5)
        if abs(r - ring * self.stroke_spacing) >= 0.5:
            return rgb
        pieces = max(3, round(math.tau * ring * self.stroke_spacing / 40.0))
        if self.noise.noise1(turn * pieces, self.seed + 31 * ring, pieces) < 1.0 - self.stroke_share:
            return rgb
        return _mix(rgb, self.stroke_colour, 0.5)


class Noise:
    """The generator's hashes and noise, handed in so this module keeps one definition of them."""

    def __init__(self, unit: Callable[..., float], noise1: Callable[..., float], fbm2: Callable[..., float]) -> None:
        self.unit = unit
        self.noise1 = noise1
        self.fbm2 = fbm2


def _mix(a: Colour, b: Colour, t: float) -> Colour:
    return (round(a[0] + (b[0] - a[0]) * t), round(a[1] + (b[1] - a[1]) * t), round(a[2] + (b[2] - a[2]) * t))


def _bilinear(grid: list[float], cols: int, fx: float, fy: float) -> float:
    ix, iy = int(fx), int(fy)
    tx, ty = fx - ix, fy - iy
    i = iy * cols + ix
    return (grid[i] * (1.0 - tx) + grid[i + 1] * tx) * (1.0 - ty) + (grid[i + cols] * (1.0 - tx) + grid[i + cols + 1] * tx) * ty
