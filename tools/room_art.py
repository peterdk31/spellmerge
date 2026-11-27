#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
# SPDX-License-Identifier: GPL-3.0-or-later
"""The crypt's set pieces, its tiles, the hub's void and props and the shaft of light, drawn at 2x
detail from their own shapes (ART3, part 2; the owner, 2026-11-26: real new detail, by shape and
light rules of each thing, never an upscale).

As tools/prop_art.py: each piece is its parts in world units on its 1x art's grid (so it keeps its
silhouette, its size, its frames and where it stands), drawn by tools/sprite_rules.py, lit from the
top-left in three shades a material, with its material's surface, seams and a one-art-pixel
outline. On top of that:

- **Tiles** (floor, wall, wall top, door, the hub's void) fill their cell and repeat with no seam:
  a part that crosses the cell's edge is drawn again from the other side (`tiled`), and a tile
  has no outline. The floor is flat (docs/STYLE.md, "Tiles"): Stone base, its joints and a crack in
  its shadow and light shades, nothing on its outer edge pixels.
- **Lights** (a torch's flame and glow, a candle's flame) are flat colours with no outline round a
  glow: a glow is one or two flat rings of the light shade (docs/STYLE.md, "Light and shading").
- **The shaft of light** (decor/beam, beam_pool) is a room's soft light (docs/STYLE.md, "Rooms"):
  one pale colour in a few steps of alpha, whole pixels, drawn as an indexed PNG.
- **The hub's stone and its lit runes** share one carving: the lit look is the same lines in Ice,
  so it lies exactly over the carved one.

    tools/room_art.py           # writes every file
    tools/room_art.py --check   # fails when a file differs from what the rules draw
    tools/room_art.py torch     # only these (a file's name before its @2x)
"""

from __future__ import annotations

import argparse
import math
import struct
import sys
import zlib
from pathlib import Path
from typing import Callable

sys.path.insert(0, str(Path(__file__).resolve().parent))
import prop_art as pa  # noqa: E402
import sprite_rules as sr  # noqa: E402
from sprite_rules import OUTLINE, PALETTE, Part, ball, box, poly, ring, rod  # noqa: E402
from staff_art import Canvas  # noqa: E402

ROOT = sr.ROOT
CRYPT = ROOT / "art/tilesets/crypt"
DECOR = ROOT / "art/tilesets/decor"
HUB = ROOT / "art/tilesets/hub"
PROPS = ROOT / "content/props"
Point = tuple[float, float]

STONE = dict(material="Stone", raised=True)
S0, S1, S2 = PALETTE["Stone"]
B0, B1, B2 = PALETTE["Bone"]
line = pa.line


def flat(x0: float, y0: float, x1: float, y1: float, colour: str) -> Part:
    """A flat rectangle of one colour, no seam (a joint's lit lip, a fill)."""
    return box(x0, y0, x1, y1, bevel=0.0, material="Stone", colour=colour, seam=False)


def dot(x: float, y: float, colour: str, r: float = 0.3) -> Part:
    """One art pixel or so of one colour (a fleck, a speck of grit, a stud)."""
    return box(x - r, y - r, x + r, y + r, bevel=0.0, material="Stone", colour=colour, seam=False)


def tiled(parts: list[Part], width: float, height: float, across: bool = True, down: bool = True) -> list[Part]:
    """`parts` again from each side of a `width` x `height` tile, so what crosses an edge comes in at
    the other one and the tile repeats with no seam."""
    out: list[Part] = []
    xs = (-width, 0.0, width) if across else (0.0,)
    ys = (-height, 0.0, height) if down else (0.0,)
    for part in parts:
        for oy in ys:
            for ox in xs:
                out.append(part if ox == 0.0 and oy == 0.0 else sr.moved(part, ox, oy))
    return out


def teardrop(cx: float, base: float, width: float, height: float, lean: float = 0.0, steps: int = 18) -> list[Point]:
    """A flame's outline: a round bottom `width` across at `base`, drawn up to a tip `height` above
    it, leant `lean` to the side at the tip."""
    r = width / 2.0
    points: list[Point] = []
    for i in range(steps + 1):
        a = math.pi * i / steps
        points.append((cx + r * math.cos(a), base - r + r * math.sin(a)))
    tip = (cx + lean, base - height)
    left, right = points[-1], points[0]
    # Up from the round bottom's sides to the tip, bowed out a little: a flame's belly.
    for i in range(1, 6):
        t = i / 6.0
        bow = math.sin(t * math.pi) * r * 0.35
        points.append((left[0] + (tip[0] - left[0]) * t * t - bow * (1.0 - t), left[1] + (tip[1] - left[1]) * t))
    points.append(tip)
    for i in range(5, 0, -1):
        t = i / 6.0
        bow = math.sin(t * math.pi) * r * 0.35
        points.append((right[0] + (tip[0] - right[0]) * t * t + bow * (1.0 - t), right[1] + (tip[1] - right[1]) * t))
    return points


# --- the floor ----------------------------------------------------------------------------------


def floor() -> list[Part]:
    """Worn flagstones: joints in Stone's shadow, the lip past each joint caught by the light in
    short broken lengths, a crack, a little grit. Flat and quiet (shots read over it), nothing on its
    outer edge pixels, so it repeats with no seam."""
    parts: list[Part] = [flat(0.0, 0.0, 32.0, 32.0, S1)]
    joints = [[(9.2, 1.2), (9.0, 8.0), (9.4, 15.4)], [(1.4, 15.6), (12.0, 15.4), (22.0, 15.8), (30.6, 15.6)], [(22.2, 16.2), (22.0, 24.0), (22.4, 30.6)]]
    for joint in joints:
        parts += line(joint, S0, 0.26)
    # The lit lip on the far side of a joint: a stone's top-left edge turned to the light.
    for x0, y0, x1, y1 in ((9.9, 2.4, 10.4, 6.8), (9.9, 9.6, 10.4, 13.4), (2.6, 16.3, 7.4, 16.8), (14.6, 16.3, 19.6, 16.8), (24.4, 16.5, 28.6, 17.0), (22.9, 18.6, 23.4, 22.4), (23.0, 25.6, 23.5, 28.8)):
        parts.append(flat(x0, y0, x1, y1, S2))
    # A crack across the top-right flag and a chipped corner in the bottom-left one.
    parts += line([(20.6, 3.2), (22.4, 5.4), (21.8, 7.0), (24.0, 9.6), (25.6, 10.4)], S0, 0.24)
    parts += line([(22.4, 5.4), (24.2, 5.0)], S0, 0.22)
    parts += line([(4.6, 26.4), (6.2, 27.2), (6.6, 28.8)], S0, 0.24)
    for x, y in ((3.2, 3.6), (14.8, 6.2), (27.6, 4.4), (16.6, 11.8), (5.8, 21.0), (12.4, 24.8), (17.2, 28.4), (28.0, 22.6)):
        parts.append(dot(x, y, S0, 0.25))
    for x, y in ((4.4, 9.8), (26.2, 13.0), (14.0, 20.6), (27.6, 28.2)):
        parts.append(dot(x, y, S2, 0.25))
    return parts


# --- the wall and its top -----------------------------------------------------------------------


def _brick(x0: float, y0: float, x1: float, y1: float, seed: int, cracks: list[list[Point]] | None = None) -> Part:
    """One dressed block: lit on its top-left rim, shaded on its bottom-right, pitted."""
    return box(x0 + 0.5, y0 + 0.5, x1 - 0.5, y1 - 0.5, bevel=0.9, corner=0.5, surface="worn", seam=False, seed=seed, cracks=cracks or [], **STONE)  # type: ignore[arg-type]


def _courses(top: float, rows: list[tuple[float, float]], seed: int) -> list[Part]:
    """Courses of blocks from `top`, each (height, offset): two blocks a course, staggered."""
    parts: list[Part] = []
    y = top
    for i, (height, offset) in enumerate(rows):
        for j in range(2):
            x = offset + j * 16.0
            cracks = [[(x + 9.0, y + 1.4), (x + 10.4, y + 3.4), (x + 9.6, y + height - 1.6)]] if (i + j + seed) % 5 == 2 else None
            parts.append(_brick(x, y, x + 16.0, y + height, seed + i * 2 + j, cracks))
        y += height
    return parts


def wall() -> list[Part]:
    """Four courses of dressed blocks in dark mortar, every other one set half a block over."""
    parts = [flat(0.0, 0.0, 32.0, 32.0, S0)]
    parts += tiled(_courses(0.0, [(8.0, 0.0), (8.0, 8.0), (8.0, 0.0), (8.0, 8.0)], 101), 32.0, 32.0)
    return parts


def wall_top() -> list[Part]:
    """The wall's top seen from above: two worn capstones, lit, a shadow under their lip, then the
    courses of its face going down into the dark."""
    parts = [flat(0.0, 0.0, 32.0, 32.0, S0)]
    caps = [
        pa.tilted(box(0.5, 0.0, 15.5, 10.0, bevel=0.8, surface="worn", seam=False, seed=111, cracks=[[(5.2, 3.2), (7.6, 3.6), (8.4, 2.8)]], **STONE), 0.0, -0.9),  # type: ignore[arg-type]
        pa.tilted(box(16.5, 0.0, 31.5, 10.0, bevel=0.8, surface="worn", seam=False, seed=112, cracks=[[(21.4, 6.4), (24.0, 6.2), (25.6, 7.2)]], **STONE), 0.0, -0.9),  # type: ignore[arg-type]
    ]
    parts += tiled(caps, 32.0, 32.0, down=False)
    parts += tiled(_courses(10.8, [(8.6, 10.0), (8.6, 2.0)], 113), 32.0, 32.0, down=False)
    # The foot of the face, in the dark: the last course's top only.
    parts.append(flat(0.0, 28.6, 32.0, 32.0, S0))
    parts += line([(0.0, 10.5), (32.0, 10.5)], OUTLINE, 0.3)
    return parts


# --- the pillar tiles ---------------------------------------------------------------------------


def pillar() -> list[Part]:
    """A square pillar's shaft (going on up into its top tile) on a plinth: lit down its left face,
    shaded down its right, a joint between its blocks, the plinth's top caught by the light."""
    shaft = box(4.5, -3.0, 27.5, 20.0, bevel=3.0, surface="worn", seed=121, cracks=[[(20.6, 13.0), (21.8, 15.4), (21.2, 17.6)]], **STONE)  # type: ignore[arg-type]
    parts: list[Part] = [shaft]
    parts += line([(5.2, 10.0), (26.8, 10.0)], S0, 0.32)
    parts.append(flat(7.0, 10.6, 25.0, 11.0, S2))
    parts += [
        box(1.5, 20.5, 30.5, 31.5, bevel=1.1, corner=0.6, surface="worn", seed=122, cracks=[[(2.4, 27.8), (29.6, 27.8)]], **STONE),  # type: ignore[arg-type]
        pa.tilted(box(2.2, 20.9, 29.8, 22.6, bevel=0.4, seam=False, surface="worn", seed=123, **STONE), 0.0, -1.6),  # type: ignore[arg-type]
    ]
    return parts


def pillar_top() -> list[Part]:
    """The pillar's capital seen from above and the front: a lit capstone with a moulding under its
    front edge, its neck in shadow, the shaft going on down into the pillar tile."""
    return [
        box(4.5, 18.0, 27.5, 35.0, bevel=3.0, surface="worn", seed=131, **STONE),  # type: ignore[arg-type]
        box(5.0, 18.2, 27.0, 20.6, bevel=0.0, colour=S0, material="Stone", seam=False),
        box(1.5, 12.0, 30.5, 18.0, bevel=0.9, corner=0.4, surface="worn", seed=132, **STONE),  # type: ignore[arg-type]
        pa.tilted(box(1.5, 1.5, 30.5, 12.2, bevel=1.0, corner=0.6, surface="worn", seed=133, cracks=[[(13.4, 5.0), (15.6, 5.4), (18.4, 4.8)], [(6.6, 8.2), (8.4, 8.6)]], **STONE), 0.0, -1.0),  # type: ignore[arg-type]
        flat(2.6, 13.0, 29.4, 13.4, S2),
    ]


# --- the door -----------------------------------------------------------------------------------


def door() -> list[Part]:
    """A plank door in a stone frame: three boards of grained oak, two iron straps riveted across
    them, a brass ring to pull, the lintel's underside dark over its top."""
    parts: list[Part] = [
        box(-1.0, -1.0, 4.4, 33.0, bevel=1.0, surface="worn", seed=141, seam=False, **STONE),  # type: ignore[arg-type]
        box(27.6, -1.0, 33.0, 33.0, bevel=1.0, surface="worn", seed=142, seam=False, **STONE),  # type: ignore[arg-type]
        pa.tilted(box(-1.0, -1.0, 33.0, 3.4, bevel=0.8, surface="worn", seed=143, seam=False, **STONE), 0.0, -1.0),  # type: ignore[arg-type]
        flat(4.0, 3.0, 28.0, 4.4, OUTLINE),
    ]
    for x0, x1, seed, lean in ((4.4, 11.4, 144, 0.0), (11.4, 20.6, 145, -0.9), (20.6, 27.6, 146, 0.0)):
        parts.append(pa.tilted(box(x0, 4.4, x1, 33.0, bevel=0.6, material="Wood", surface="grain", seed=seed), lean, 0.0))
    for y in (10.8, 26.8):
        parts.append(box(4.4, y, 27.6, y + 1.8, bevel=0.4, surface="rivets", seed=147, **STONE))  # type: ignore[arg-type]
    parts += [
        ring((23.6, 19.6), 1.5, 0.7, material="Spark"),
        dot(23.6, 17.8, PALETTE["Spark"][0], 0.35),
        ball((23.0, 19.0), 0.3, 0.3, material="Spark", colour=PALETTE["Spark"][2], seam=False),
    ]
    return parts


# --- the torch ----------------------------------------------------------------------------------


def torch() -> list[Part]:
    """The wall torch's bracket: a wooden cup bound with an iron band, on a turned handle with an
    iron collar."""
    wood = dict(material="Wood")
    return [
        rod((16.0, 16.2), (16.0, 22.6), 2.2, 1.9, surface="grain", seed=151, **wood),  # type: ignore[arg-type]
        rod((13.6, 19.4), (18.4, 19.4), 0.7, surface="rivets", **STONE),  # type: ignore[arg-type]
        poly([(10.8, 13.4), (21.2, 13.4), (19.8, 17.6), (12.2, 17.6)], bevel=0.7, surface="board", seed=152, **wood),  # type: ignore[arg-type]
        box(11.4, 15.6, 20.6, 16.6, bevel=0.3, surface="rivets", **STONE),  # type: ignore[arg-type]
        ball((16.0, 13.9), 4.2, 0.6, lean=0.3, material="Wood", colour=OUTLINE, seam=False),
    ]


TORCH_FLAMES: list[tuple[float, float, float, list[Point]]] = [
    # (height, width, lean at its tip, sparks): the four looks the flame's loop plays.
    (9.0, 6.4, 0.2, [(9.0, 6.0), (21.6, 8.2)]),
    (10.6, 6.0, -0.8, [(8.8, 5.0), (21.8, 6.8)]),
    (7.6, 6.6, 0.4, [(8.4, 3.6), (22.6, 5.8)]),
    (10.0, 6.2, 0.9, [(8.0, 3.2), (23.2, 5.0)]),
]


def torch_flame(frame: int) -> list[Part]:
    """One look of the torch's flame: an outer tongue of fire round a gold heart and a white core,
    sparks lifting off it. Its foot sits in the cup."""
    height, width, lean, sparks = TORCH_FLAMES[frame]
    base = 13.6
    fire = dict(surface="flame", seam=False)
    parts: list[Part] = [
        poly(teardrop(16.0, base, width, height, lean), bevel=0.7, material="Fire", **fire),  # type: ignore[arg-type]
        poly(teardrop(16.0 + lean * 0.2, base - 0.6, width * 0.58, height * 0.66, lean * 0.6), bevel=0.4, material="Spark", **fire),  # type: ignore[arg-type]
        ball((16.0, base - 2.0), 0.9, 1.4, material="Spark", colour=PALETTE["Spark"][2], seam=False),
        poly([(13.6, base - 0.4), (18.4, base - 0.4), (17.6, base + 0.4), (14.4, base + 0.4)], bevel=0.0, material="Fire", colour=PALETTE["Fire"][0], seam=False),
    ]
    for x, y in sparks:
        parts.append(dot(x, y, PALETTE["Spark"][1], 0.4))
        parts.append(dot(x + 0.5, y + 0.9, PALETTE["Fire"][2], 0.3))
    return parts


# --- the glows ----------------------------------------------------------------------------------


def torch_glow() -> list[Part]:
    """The warm pool a torch or a candle casts (added over the room, faint): a flat disc of fire,
    a brighter ring of its light shade inside it."""
    return [
        ball((32.0, 32.0), 27.0, 27.0, material="Fire", colour=PALETTE["Fire"][1], seam=False),
        ball((32.0, 32.0), 15.0, 15.0, material="Fire", colour=PALETTE["Fire"][2], seam=False),
    ]


GLOW_CORES: list[float] = [12.6, 10.0, 6.4]


def torch_glow_core(frame: int) -> list[Part]:
    """The flame's own glow breathing in its three sizes: a disc of fire's light, its heart a ring of
    spark's."""
    r = GLOW_CORES[frame]
    return [
        ball((16.0, 16.0), r, r, material="Fire", colour=PALETTE["Fire"][2], seam=False),
        ball((16.0, 16.0), r * 0.5, r * 0.5, material="Spark", colour=PALETTE["Spark"][1], seam=False),
    ]


# --- the candles --------------------------------------------------------------------------------

CANDLES: list[tuple[float, float, float]] = [(9.5, 15.6, 1.9), (15.5, 18.6, 1.8), (21.5, 21.6, 1.7)]


def candles() -> list[Part]:
    """Three tallow candles on a pewter dish, burnt down to different heights: round and pale, wax
    run down their sides and pooled at their feet, a black wick in each cupped top."""
    parts: list[Part] = [
        box(4.6, 27.6, 27.4, 29.8, bevel=0.6, corner=0.5, surface="worn", seed=161, **STONE),  # type: ignore[arg-type]
        pa.tilted(box(4.8, 27.4, 27.2, 28.4, bevel=0.3, seam=False, seed=162, **STONE), 0.0, -1.4),  # type: ignore[arg-type]
    ]
    bone = dict(material="Bone", surface="pores")
    for i, (cx, top, r) in enumerate(CANDLES):
        parts.append(rod((cx, top + 1.0), (cx, 27.4), r, seed=163 + i, **bone))  # type: ignore[arg-type]
        parts.append(pa.tilted(ball((cx, top + 0.9), r - 0.2, 0.7, lean=0.3, seam=False, seed=166 + i, **bone), 0.0, -0.8))  # type: ignore[arg-type]
        parts.append(rod((cx + r - 0.4, top + 2.2), (cx + r - 0.2, top + 4.6 + i), 0.5, 0.6, seam=False, **bone))  # type: ignore[arg-type]
        parts.append(ball((cx, 27.4), r + 0.9, 0.8, lean=0.3, seam=False, **bone))  # type: ignore[arg-type]
        parts.append(rod((cx, top + 0.6), (cx + 0.2, top - 0.4), 0.3, material="Wood", colour=OUTLINE, seam=False))
    return parts


CANDLE_FLAMES: list[list[tuple[float, float, float]]] = [
    # Each candle's flame in each look: (height, lean, how far over its wick its foot is).
    [(3.4, 0.2, 0.0), (2.6, -0.3, 0.0), (3.0, 0.4, 0.0)],
    [(3.0, -0.3, 0.0), (3.4, 0.3, 0.0), (2.6, 0.0, 0.0)],
    [(2.6, 0.3, 0.0), (3.0, 0.0, 0.0), (3.4, -0.3, 0.0)],
    [(3.2, 0.0, 0.0), (2.8, 0.4, 0.0), (3.2, 0.3, 0.0)],
]


def candle_flame(frame: int) -> list[Part]:
    """One look of the three candles' flames: small tongues of fire over their wicks, gold at the
    foot, white at the heart, each flickering on its own."""
    parts: list[Part] = []
    for (cx, top, _r), (height, lean, _) in zip(CANDLES, CANDLE_FLAMES[frame]):
        base = top - 0.6
        parts.append(poly(teardrop(cx, base, 1.8, height, lean, 10), bevel=0.0, material="Fire", colour=PALETTE["Spark"][1], seam=False))
        parts.append(poly(teardrop(cx, base - 0.2, 1.0, height * 0.55, lean * 0.5, 8), bevel=0.0, material="Fire", colour=PALETTE["Spark"][2], seam=False))
        parts.append(dot(cx + lean, base - height + 0.2, PALETTE["Fire"][2], 0.3))
    return parts


# --- skulls, rubble and bones -------------------------------------------------------------------


def _skull(cx: float, cy: float, scale: float = 1.0, seed: int = 0, material: str = "Bone") -> list[Part]:
    """A skull from the front: a round cranium, dark sockets, a notch of a nose, a jaw of teeth."""
    s = scale
    bone = dict(material=material, surface="pores", seed=seed)
    parts: list[Part] = [
        box(cx - 2.6 * s, cy + 1.2 * s, cx + 2.6 * s, cy + 3.6 * s, bevel=0.5, corner=0.5, **bone),  # type: ignore[arg-type]
        ball((cx, cy), 4.4 * s, 3.8 * s, lean=0.85, glint=True, **bone),  # type: ignore[arg-type]
        ball((cx - 1.7 * s, cy + 0.9 * s), 1.1 * s, 1.0 * s, lean=0.4, material=material, colour=OUTLINE, seam=False),
        ball((cx + 1.7 * s, cy + 0.9 * s), 1.1 * s, 1.0 * s, lean=0.4, material=material, colour=OUTLINE, seam=False),
        poly([(cx - 0.45 * s, cy + 2.6 * s), (cx + 0.45 * s, cy + 2.6 * s), (cx, cy + 1.8 * s)], bevel=0.0, material=material, colour=OUTLINE, seam=False),
    ]
    for i in (-1, 0, 1):
        parts.append(rod((cx + i * 1.2 * s, cy + 3.0 * s), (cx + i * 1.2 * s, cy + 3.6 * s), 0.24, material=material, colour=OUTLINE, seam=False))
    return parts


def skull() -> list[Part]:
    """A skull lying on the floor."""
    return _skull(15.8, 14.6, 1.0, 171)


def rubble() -> list[Part]:
    """Broken stone on the floor: three knocked-off lumps and a few chips."""
    return [
        pa.chunk(8.4, 20.6, 4.6, 3.6, 0.1, 181),
        pa.chunk(16.4, 23.6, 5.4, 3.4, -0.05, 182),
        pa.chunk(23.2, 18.8, 3.6, 2.8, 0.2, 183),
        pa.chunk(11.6, 25.8, 1.6, 1.3, 0.3, 184),
        pa.chunk(25.4, 23.0, 1.4, 1.2, -0.2, 185),
    ]


def _long_bone(a: Point, b: Point, r: float, seed: int, material: str = "Bone") -> list[Part]:
    """A long bone: a shaft swelling to a double knuckle at each end."""
    dx, dy = b[0] - a[0], b[1] - a[1]
    n = math.hypot(dx, dy) or 1.0
    px, py = -dy / n, dx / n
    bone = dict(material=material, surface="pores")
    parts = [rod(a, b, r, seed=seed, **bone)]  # type: ignore[arg-type]
    for end in (a, b):
        for side in (-1.0, 1.0):
            parts.append(ball((end[0] + px * side * r * 0.9, end[1] + py * side * r * 0.9), r * 1.05, r * 1.05, lean=0.8, seam=False, seed=seed + 1, **bone))  # type: ignore[arg-type]
    return parts


def bone_pile() -> list[Part]:
    """A heap of bones: a thigh bone laid across, a rib and a shin under it, a skull on top."""
    parts: list[Part] = []
    parts += _long_bone((5.6, 12.2), (14.0, 9.6), 0.75, 191)
    parts.append(rod((17.4, 12.6), (24.0, 9.4), 0.5, material="Bone", surface="pores", seed=192))
    parts += _long_bone((3.0, 10.4), (28.6, 10.4), 0.9, 193)
    parts += _skull(11.6, 5.8, 0.75, 194)
    parts.append(ball((21.4, 8.8), 1.1, 0.9, lean=0.8, material="Bone", surface="pores", seed=195))
    return parts


# --- the sarcophagus ----------------------------------------------------------------------------


def sarcophagus() -> list[Part]:
    """A stone coffin: its heavy lid carved with a sleeper (a round head, a long robed body studded
    down its sides, a sword laid along it), a corner of the lid broken off, the panelled front of
    the chest under the lid's lip."""
    lid = [(0.6, 0.6), (56.8, 0.6), (58.4, 1.6), (60.6, 1.2), (61.6, 3.0), (63.4, 3.2), (63.4, 21.0), (0.6, 21.0)]
    parts: list[Part] = [
        box(0.6, 20.6, 63.4, 31.4, bevel=1.0, corner=0.4, surface="worn", seed=201, **STONE),  # type: ignore[arg-type]
        pa.tilted(poly(lid, bevel=1.2, surface="worn", seed=202, **STONE), 0.0, -1.0),  # type: ignore[arg-type]
    ]
    # The front's panels: dark joints between, a lit sill under them.
    for x in (12.4, 26.4, 38.4, 52.4):
        parts += line([(x, 23.0), (x, 28.0)], S0, 0.32)
    parts += line([(2.6, 22.6), (61.4, 22.6)], S0, 0.3)
    parts += line([(2.6, 28.6), (61.4, 28.6)], S0, 0.3)
    parts.append(flat(3.6, 29.2, 60.4, 29.6, S2))
    # The sleeper in relief.
    parts += [
        poly([(14.0, 4.6), (32.0, 4.0), (47.0, 5.4), (56.0, 6.6), (58.2, 9.8), (56.0, 13.4), (47.0, 14.6), (32.0, 16.0), (14.0, 16.4)], bevel=1.0, surface="worn", seed=203, **STONE),  # type: ignore[arg-type]
        ball((10.6, 10.4), 5.2, 5.6, lean=0.75, surface="worn", seed=204, **STONE),  # type: ignore[arg-type]
        pa.tilted(ball((9.6, 10.4), 2.8, 3.6, lean=0.6, surface="worn", seed=205, seam=False, **STONE), -0.4, 0.0),  # type: ignore[arg-type]
    ]
    # Its face turned up, eyes shut: two lids and a mouth, carved.
    parts += line([(12.2, 8.6), (13.0, 8.4)], S0, 0.26)
    parts += line([(12.2, 12.2), (13.0, 12.4)], S0, 0.26)
    parts += line([(14.6, 9.6), (14.6, 11.2)], S0, 0.24)
    parts += line([(32.0, 4.6), (32.0, 15.4)], S0, 0.3)
    parts += line([(47.0, 5.8), (47.0, 14.2)], S0, 0.3)
    # The sword: a lit blade along its middle, its hilt a cross-guard.
    parts.append(rod((25.4, 10.2), (49.0, 10.2), 0.55, material="Stone", colour=S2, seam=True))
    parts.append(rod((24.0, 8.2), (24.0, 12.2), 0.6, **STONE))  # type: ignore[arg-type]
    parts.append(rod((20.6, 10.2), (23.6, 10.2), 0.6, material="Wood", surface="grain", seed=206))
    for x in (18.6, 27.4, 35.4, 43.4, 51.4):
        parts.append(dot(x, 6.8, OUTLINE, 0.36))
        parts.append(dot(x, 13.8, OUTLINE, 0.36))
    # A worn rosette at each of the lid's corners.
    parts.append(dot(3.6, 3.6, S0, 0.5))
    parts.append(dot(3.6, 17.8, S0, 0.5))
    parts += line([(58.8, 17.6), (60.0, 16.4), (61.2, 17.6)], S0, 0.28)
    return parts


# --- the fallen column --------------------------------------------------------------------------


def _drum(cx: float, cy: float, length: float, r: float, seed: int) -> list[Part]:
    """A column's drum lying on its side: round along its length, its broken end face to the right,
    lit, its flutes running along it."""
    body = sr.moved(pa.column(-r, r, -length / 2.0, length / 2.0, surface="worn", seed=seed, **STONE), cx, cy, 1.0, -math.pi / 2.0)  # type: ignore[arg-type]
    parts: list[Part] = [body]
    for k in (-0.5, 0.15):
        parts += line([(cx - length / 2.0 + 0.8, cy + k * r), (cx + length / 2.0 - 0.8, cy + k * r)], S0, 0.26)
    parts.append(pa.tilted(ball((cx + length / 2.0, cy), 1.5, r, lean=0.3, surface="worn", seed=seed + 1, cracks=[[(cx + length / 2.0 - 0.6, cy - 1.0), (cx + length / 2.0 + 0.4, cy + 1.2)]], **STONE), -1.2, -0.4))  # type: ignore[arg-type]
    return parts


def fallen_column() -> list[Part]:
    """A broken column: its stump on its plinth, its top snapped off in jagged teeth, and two of its
    drums rolled away on the floor, dust and chips round them."""
    stump = [(6.0, 14.0), (8.4, 12.4), (10.2, 15.0), (12.6, 11.2), (15.0, 15.6), (17.4, 12.4), (19.6, 15.0), (21.6, 14.4), (21.6, 25.6), (6.0, 25.6)]
    parts: list[Part] = [
        box(2.0, 25.0, 29.6, 29.8, bevel=0.9, corner=0.5, surface="worn", seed=211, cracks=[[(23.0, 27.6), (29.0, 27.6)]], **STONE),  # type: ignore[arg-type]
        pa.tilted(box(2.4, 25.2, 29.2, 26.4, bevel=0.3, seam=False, seed=212, **STONE), 0.0, -1.4),  # type: ignore[arg-type]
        poly(stump, bevel=1.6, surface="worn", seed=213, **STONE),  # type: ignore[arg-type]
    ]
    for x in (9.4, 13.4, 17.4):
        parts += line([(x, 16.6), (x, 24.8)], S0, 0.28)
    parts += line([(10.2, 17.0), (10.2, 24.6)], S2, 0.22)
    # The break: dark where the stone snapped.
    parts += line([(8.4, 13.4), (10.2, 15.6), (12.6, 12.2), (15.0, 16.4), (17.4, 13.4), (19.6, 15.8)], OUTLINE, 0.3)
    parts += _drum(43.4, 22.0, 18.4, 4.4, 214)
    parts += _drum(57.2, 26.6, 9.6, 3.6, 216)
    for i, (x, y) in enumerate(((47.0, 15.4), (62.4, 20.4), (36.6, 28.8), (31.6, 22.2))):
        parts.append(pa.chunk(x, y, 1.5, 1.2, 0.3 * i, 218 + i))
    return parts


# --- the ossuary wall ---------------------------------------------------------------------------

OSSUARY_NICHES: list[float] = [20.6, 63.6, 106.6]
OSSUARY_TOP_SKULLS: list[float] = [42.0, 92.0]


def ossuary_wall() -> list[Part]:
    """A low wall built of the dead: long bones stacked along its top in three courses, two skulls
    set in them, then a face of bone ends packed in rows round three arched niches, a skull in each,
    on a stone sill. The bones are dusty and dim (Stone), the skulls their own bone a shade down
    (`DIM_BONE`), so the wall stays calm behind a fight."""
    parts: list[Part] = [box(0.4, 0.4, 127.6, 31.6, bevel=1.2, corner=0.6, material="Stone", colour=S0, seam=False)]
    # The top: three courses of long bones end to end, each course set over from the one below.
    courses = [(2.6, [(1.4, 20.0), (21.0, 38.0), (46.4, 64.0), (65.0, 88.0), (96.4, 110.0), (111.0, 126.6)]),
               (6.2, [(1.4, 12.0), (13.0, 36.0), (47.0, 60.0), (61.0, 86.0), (97.0, 118.0), (119.0, 126.6)]),
               (9.8, [(1.4, 26.0), (27.0, 50.0), (51.0, 72.0), (73.0, 100.0), (101.0, 126.6)])]
    for row, (y, runs) in enumerate(courses):
        for i, (x0, x1) in enumerate(runs):
            parts += _long_bone((x0 + 1.2, y), (x1 - 1.2, y + (0.3 if (i + row) % 2 else -0.3)), 0.85, 221 + row * 10 + i, material="Stone")
    for x in OSSUARY_TOP_SKULLS:
        parts += _skull(x, 4.8, 0.8, 251)
    parts += line([(1.0, 12.4), (127.0, 12.4)], OUTLINE, 0.4)
    # The face: rows of bone ends, each a lit knob, round the niches.
    for row, y in enumerate((15.0, 18.6, 22.2, 25.8)):
        x = 3.0 + (row % 2) * 2.2
        while x < 126.0:
            if all(abs(x - n) > 8.6 for n in OSSUARY_NICHES):
                parts.append(ball((x, y), 1.25, 1.1, lean=0.8, surface="worn", seed=int(x * 7 + row), **STONE))  # type: ignore[arg-type]
            x += 4.4
    for n in OSSUARY_NICHES:
        arch = [(n - 7.4, 28.4), (n - 7.4, 17.0), (n - 5.6, 14.4), (n - 2.6, 13.4), (n + 2.6, 13.4), (n + 5.6, 14.4), (n + 7.4, 17.0), (n + 7.4, 28.4)]
        parts.append(poly(arch, bevel=1.0, surface="worn", seed=261, **STONE))  # type: ignore[arg-type]
        inner = [(n - 6.0, 28.4), (n - 6.0, 17.6), (n - 4.6, 15.6), (n - 2.2, 14.8), (n + 2.2, 14.8), (n + 4.6, 15.6), (n + 6.0, 17.6), (n + 6.0, 28.4)]
        parts.append(poly(inner, bevel=0.0, material="Stone", colour=OUTLINE, seam=False))
        parts += _skull(n, 20.6, 1.0, 262)
    parts += [
        box(0.4, 28.2, 127.6, 31.6, bevel=0.8, corner=0.4, surface="worn", seed=271, **STONE),  # type: ignore[arg-type]
        flat(1.6, 28.8, 126.4, 29.2, S2),
    ]
    return parts


# --- the hub's void -----------------------------------------------------------------------------


def void() -> list[Part]:
    """The dark past the hub's edge: the outline's black, with far motes of stone-dust in it, two
    faint crosses of a star and a fleck of void's violet. Sparse and quiet; repeats with no seam."""
    parts: list[Part] = [flat(0.0, 0.0, 32.0, 32.0, OUTLINE)]
    for x, y in ((6.25, 5.25), (23.25, 9.25), (27.75, 25.25), (4.25, 27.25), (15.75, 2.75), (30.25, 15.75), (10.75, 16.25), (20.25, 29.75)):
        parts.append(dot(x, y, S0, 0.25))
    for cx, cy in ((18.25, 26.25), (26.75, 5.75)):
        parts += [dot(cx, cy, S1, 0.25), dot(cx - 0.5, cy, S0, 0.25), dot(cx + 0.5, cy, S0, 0.25), dot(cx, cy - 0.5, S0, 0.25), dot(cx, cy + 0.5, S0, 0.25)]
    parts.append(dot(13.25, 19.25, PALETTE["Void"][0], 0.25))
    parts.append(dot(2.75, 12.25, PALETTE["Void"][0], 0.25))
    return parts


# --- the hub's stone ----------------------------------------------------------------------------

STONE_C: Point = (48.0, 45.6)
RUNE_R = 30.4
RUNE_STEP = math.tau / 12.0

# Twelve abstract runes, each strokes in a 4 x 4 box round its middle (world units).
RUNES: list[list[list[Point]]] = [
    [[(-1.6, 1.4), (0.0, -1.4), (1.6, 1.4), (-1.6, 1.4)]],
    [[(-1.4, -1.4), (0.0, 0.0), (1.4, -1.4)], [(0.0, 0.0), (0.0, 1.6)]],
    [[(-1.6, -1.2), (-0.4, -1.2), (0.4, 1.2), (1.6, 1.2)]],
    [[(0.0, -1.6), (0.0, 1.6)], [(-1.6, 0.0), (1.6, 0.0)], [(-1.0, -1.0), (1.0, 1.0)]],
    [[(1.4, -1.4), (-1.4, -1.4), (-1.4, 1.4), (1.4, 1.4), (1.4, 0.0), (0.2, 0.0)]],
    [[(-1.4, -1.4), (1.4, 1.4)], [(1.4, -1.4), (-1.4, 1.4)]],
    [[(0.0, 1.6), (0.0, -1.6)], [(-1.4, -0.2), (0.0, -1.6), (1.4, -0.2)]],
    [[(-1.4, -1.4), (1.4, 1.4)], [(1.4, -1.4), (-1.4, 1.4)], [(-1.4, 0.0), (-0.6, 0.0)]],
    [[(-1.0, -1.4), (1.0, -1.4), (1.6, 0.0), (1.0, 1.4), (-1.0, 1.4), (-1.6, 0.0), (-1.0, -1.4)]],
    [[(-1.6, -1.4), (-1.6, 0.4), (1.6, 0.4), (1.6, -1.4)], [(0.0, -1.4), (0.0, 1.6)]],
    [[(-1.4, -1.4), (0.0, -0.4), (-1.4, 0.6), (0.0, 1.6)], [(1.0, -1.4), (1.0, 1.4)]],
    [[(-1.6, 1.2), (-0.4, 1.2), (0.4, -1.2), (1.6, -1.2)], [(-1.6, -1.2), (-0.8, -1.2)]],
]


def _rune_strokes() -> list[list[Point]]:
    strokes: list[list[Point]] = []
    for i, rune in enumerate(RUNES):
        a = -math.pi / 2.0 + i * RUNE_STEP
        cx, cy = STONE_C[0] + math.cos(a) * RUNE_R, STONE_C[1] + math.sin(a) * RUNE_R
        for stroke in rune:
            strokes.append([(cx + x, cy + y) for x, y in stroke])
    return strokes


def _sigil_star() -> list[Point]:
    cx, cy = STONE_C
    points: list[Point] = []
    for i in range(8):
        a = -math.pi / 2.0 + i * math.pi / 4.0
        r = 6.4 if i % 2 == 0 else 2.2
        points.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    return points + [points[0]]


def _carving(colour: str, light: str) -> list[Part]:
    """The stone's carving in `colour` (its runes, its inner ring, the sigil's ring and star) and the
    star's heart and tips in `light`: carved Stone shadow on the stone, glowing Ice when it is lit."""
    parts: list[Part] = [
        ring(STONE_C, 23.0, 22.0, material="Stone", colour=colour, seam=False),
        ring(STONE_C, 10.0, 9.0, material="Stone", colour=colour, seam=False),
    ]
    for stroke in _rune_strokes():
        parts += line(stroke, colour, 0.5)
    parts += line(_sigil_star(), colour, 0.45)
    cx, cy = STONE_C
    parts.append(dot(cx, cy, light, 0.55))
    for i in range(4):
        a = -math.pi / 2.0 + i * math.pi / 2.0
        parts.append(dot(cx + math.cos(a) * 6.4, cy + math.sin(a) * 6.4, light, 0.4))
    return parts


def hub_stone() -> list[Part]:
    """The teleporter stone: a round platform of dark dressed stone set in the floor, its rim
    rounded (lit on its top-left, shaded on its bottom-right, its inner face the other way), its
    front edge's thickness in shadow, worn cracks across it and its runes carved round a sigil."""
    cx, cy = STONE_C
    face = ball((cx, cy), 39.0, 39.0, lean=0.0, seed=281, cracks=[[(30.0, 70.0), (33.4, 72.6), (33.0, 76.0)], [(68.6, 18.6), (71.4, 21.2), (74.6, 21.6)], [(18.4, 34.0), (16.2, 37.6)]], **STONE)  # type: ignore[arg-type]
    parts: list[Part] = [
        ball((cx, cy + 2.6), 44.0, 44.0, lean=0.9, surface="worn", seed=282, **STONE),  # type: ignore[arg-type]
        ring((cx, cy), 44.0, 39.0, surface="worn", seed=283, **STONE),  # type: ignore[arg-type]
        pa.tilted(face, 0.0, 0.0),
        ring((cx, cy), 41.0, 40.4, material="Stone", colour=S0, seam=False),
    ]
    return parts + _carving(S0, S0)


def hub_stone_lit() -> list[Part]:
    """What glows when the stone is lit, over the same pixels as its carving: the runes, rings and
    star in Ice, the star's heart and tips Ice's light."""
    return _carving(PALETTE["Ice"][1], PALETTE["Ice"][2])


def hub_stone_motes() -> Canvas:
    """The lit runes' mote mask (content/props/README.md): where the stone's glimmer leaves from,
    one a world pixel as before, so its motes are as many and stand on whole world pixels. It is
    the same carving drawn at 1x (`sr.draw_1x`), every pixel it lights in Bone light."""
    drawn = sr.draw_1x(_carving(PALETTE["Ice"][1], PALETTE["Ice"][2]), 96, 96)
    points = [(x, y) for y, row in enumerate(drawn.pixels) for x, c in enumerate(row) if c not in (None, OUTLINE)]
    return pa.mask_canvas(96, 96, points)


# --- the hub's altar ----------------------------------------------------------------------------

ALTAR_GEMS: list[tuple[float, float, float]] = [(48.0, 37.0, 1.8), (17.6, 56.6, 1.8), (78.4, 56.6, 1.8), (48.0, 76.6, 1.8), (48.0, 56.4, 2.6)]


def hub_altar() -> list[Part]:
    """The party altar: a broad eight-sided slab, its rim lit on the left and back, its front's
    thickness in shadow, carved lines joining five set ice-stones; at its back a short plinth with a
    crystal floating over it, motes of light round it."""
    slab = [(24.0, 25.4), (72.0, 25.4), (92.6, 40.0), (92.6, 86.4), (78.0, 92.4), (18.0, 92.4), (3.4, 86.4), (3.4, 40.0)]
    top = [(25.0, 26.4), (71.0, 26.4), (91.4, 40.6), (91.4, 84.6), (77.4, 86.4), (18.6, 86.4), (4.6, 84.6), (4.6, 40.6)]
    parts: list[Part] = [
        pa.tilted(poly(slab, bevel=1.4, surface="worn", seed=291, **STONE), 0.4, 1.6),  # type: ignore[arg-type]
        pa.tilted(poly(top, bevel=1.6, surface="worn", seed=292, cracks=[[(14.6, 46.0), (17.4, 48.4), (19.4, 48.0)], [(74.4, 74.0), (77.6, 76.4), (80.4, 76.6)]], **STONE), 0.0, -0.25),  # type: ignore[arg-type]
    ]
    gems = ALTAR_GEMS
    # The carved lines: a cross through the middle stone and a lozenge through the four round it.
    for a, b in ((0, 3), (1, 2)):
        parts += line([(gems[a][0], gems[a][1]), (gems[b][0], gems[b][1])], S0, 0.5)
    for a, b in ((0, 1), (1, 3), (3, 2), (2, 0)):
        parts += line([(gems[a][0], gems[a][1]), (gems[b][0], gems[b][1])], S0, 0.4)
    for x, y in ((12.6, 44.0), (83.4, 44.0), (12.6, 78.0), (83.4, 78.0)):
        parts += line([(x - 0.6, y - 0.6), (x + 0.6, y + 0.6)], S0, 0.26)
    for x, y, r in gems:
        parts.append(ball((x, y), r + 1.0, r + 1.0, lean=0.2, material="Stone", colour=OUTLINE, seam=False))
        parts.append(ball((x, y), r, r, lean=0.9, material="Ice", glint=True))
    # The plinth at its back and the crystal over it.
    parts += [
        box(43.0, 21.0, 53.0, 28.6, bevel=0.9, surface="worn", seed=293, **STONE),  # type: ignore[arg-type]
        pa.tilted(box(41.6, 17.4, 54.4, 21.4, bevel=0.8, corner=0.4, surface="worn", seed=294, **STONE), 0.0, -0.8),  # type: ignore[arg-type]
        poly([(48.4, 2.4), (51.4, 6.6), (49.6, 13.0), (47.0, 13.0), (45.2, 6.6)], bevel=1.2, material="Ice", surface="streak", glint=True),
        rod((47.2, 4.6), (46.6, 9.6), 0.3, material="Ice", colour=PALETTE["Ice"][2], seam=False),
    ]
    return parts


def hub_altar_motes() -> list[Part]:
    """The motes of light round the altar's crystal: small crosses of Ice and a gold one, lights with
    no outline (drawn over the altar's)."""
    parts: list[Part] = []
    for x, y, c in ((39.4, 6.0, PALETTE["Ice"][1]), (58.0, 2.6, PALETTE["Spark"][2]), (58.4, 12.0, PALETTE["Ice"][1]), (37.6, 13.4, PALETTE["Ice"][0]), (56.6, 7.4, PALETTE["Ice"][2])):
        parts += [dot(x, y, c, 0.3), dot(x - 0.55, y, c, 0.25), dot(x + 0.55, y, c, 0.25), dot(x, y - 0.55, c, 0.25), dot(x, y + 0.55, c, 0.25)]
    return parts


# --- the shaft of light -------------------------------------------------------------------------

BEAM_COLOUR = (222, 230, 255)


class Light:
    """A picture of one pale colour in steps of alpha (0 clear), written as an indexed PNG."""

    def __init__(self, width: int, height: int) -> None:
        self.width = width
        self.height = height
        self.alpha: list[list[int]] = [[0] * width for _ in range(height)]

    @property
    def pixels(self) -> list[list[str | None]]:
        """Its pixels as a Canvas has them (its colour where lit), for the tests."""
        colour = "#%02x%02x%02x" % BEAM_COLOUR
        return [[colour if a else None for a in row] for row in self.alpha]

    def png(self) -> bytes:
        steps = sorted({a for row in self.alpha for a in row} | {0})
        index = {a: i for i, a in enumerate(steps)}
        rows = bytearray()
        for row in self.alpha:
            rows.append(0)
            rows += bytes(index[a] for a in row)
        chunks = [
            (b"IHDR", struct.pack(">IIBBBBB", self.width, self.height, 8, 3, 0, 0, 0)),
            (b"PLTE", b"".join(bytes(BEAM_COLOUR) if a else b"\x00\x00\x00" for a in steps)),
            (b"tRNS", bytes(steps)),
            (b"IDAT", zlib.compress(bytes(rows), 9)),
            (b"IEND", b""),
        ]
        out = bytearray(b"\x89PNG\r\n\x1a\n")
        for kind, data in chunks:
            out += struct.pack(">I", len(data)) + kind + data
            out += struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
        return bytes(out)


BEAM_STEPS = (28, 44, 60, 76)


def beam() -> Light:
    """The shaft of light falling from a crack in the roof (64 x 224 world units): pale, widening as
    it falls, brighter down its middle, a few fine streaks of brighter light along it, its foot
    rounding off where it meets the floor. Four steps of alpha, whole pixels."""
    d = sr.DETAIL
    w, h = 64, 224
    out = Light(w * d, h * d)
    cx = w / 2.0
    for py in range(h * d):
        y = (py + 0.5) / d
        t = y / 200.0
        half = 9.0 + 13.0 * min(t, 1.0)
        foot = max(0.0, (y - 200.0) / 22.0)
        half *= math.sqrt(max(0.0, 1.0 - foot * foot))
        inner = max(0.0, (y - 96.0) / 104.0) * 10.0 * math.sqrt(max(0.0, 1.0 - min(1.0, foot * 1.25) ** 2))
        for px in range(w * d):
            x = (px + 0.5) / d
            dx = abs(x - cx)
            if dx > half:
                continue
            a = BEAM_STEPS[0]
            if dx < half * 0.7:
                a = BEAM_STEPS[1]
            if dx < inner:
                a = BEAM_STEPS[2]
            # Fine streaks along the shaft, fanning out with it.
            for k in (-0.45, 0.2, 0.6):
                if abs(x - (cx + k * half)) < 0.26 and 20.0 < y < 205.0 and (int(y * 0.35 + k * 10) % 7) != 0:
                    a = min(BEAM_STEPS[-1], a + 16)
            out.alpha[py][px] = a
    return out


def beam_pool() -> Light:
    """Where the shaft meets the floor (80 x 32 world units): rings of pale light, brighter inward,
    a bright fleck at its heart."""
    d = sr.DETAIL
    w, h = 80, 32
    out = Light(w * d, h * d)
    cx, cy = 40.0, 16.0
    rings = ((34.0, 13.6, 40), (26.0, 10.4, 64), (20.0, 7.6, 96), (11.0, 4.2, 128))
    for py in range(h * d):
        for px in range(w * d):
            x, y = (px + 0.5) / d, (py + 0.5) / d
            a = 0
            for rx, ry, step in rings:
                if ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1.0:
                    a = step
            if (abs(x - cx) < 0.5 and abs(y - cy) < 1.5) or (abs(y - cy) < 0.5 and abs(x - cx) < 2.5):
                a = 160
            out.alpha[py][px] = a
    return out


# --- the files ----------------------------------------------------------------------------------


def _one(parts: Callable[[], list[Part]], w: int, h: int, outline: bool = True) -> Callable[[], Canvas]:
    return lambda: sr.draw(parts(), w, h, outline)


def _over(parts: Callable[[], list[Part]], lights: Callable[[], list[Part]], w: int, h: int) -> Callable[[], Canvas]:
    """`parts` drawn with their outline, then `lights` over them with none (motes of light)."""

    def draw() -> Canvas:
        out = sr.draw(parts(), w, h)
        out.blit(sr.draw(lights(), w, h, False), 0, 0)
        return out

    return draw


# The ossuary's skulls a shade down (the owner, 2026-11-27, on #968: a background wall stays calm
# behind a fight): Bone's light to its base, its base to its shadow, its shadow to Stone's light.
DIM_BONE = {B2: B1, B1: B0, B0: S2}


def _dimmed(draw: Callable[[], Canvas], shades: dict[str, str]) -> Callable[[], Canvas]:
    """`draw`'s picture with each colour in `shades` a shade down."""

    def dim() -> Canvas:
        out = draw()
        out.pixels = [[shades.get(c, c) if c is not None else None for c in row] for row in out.pixels]
        return out

    return dim


def _strip(frame: Callable[[int], list[Part]], count: int, w: int, h: int, outline: bool = True) -> Callable[[], Canvas]:
    def draw() -> Canvas:
        out = Canvas(w * sr.DETAIL * count, h * sr.DETAIL)
        for i in range(count):
            out.blit(sr.draw(frame(i), w, h, outline), i * w * sr.DETAIL, 0)
        return out

    return draw


# Drawn with no outline: tiles (they fill their cell) and lights.
UNOUTLINED = {"stone_lit_motes", "floor", "wall", "wall_top", "door", "void", "torch_glow", "torch_glow_core", "candle_flame", "stone_lit", "beam", "beam_pool"}
# Tiles: they repeat, so their edges must meet.
TILES = {"floor", "wall", "wall_top", "door", "void"}
# Lights: flat colours added over the room, no outline to close.
LIGHTS = {"torch_glow", "torch_glow_core", "candle_flame", "stone_lit", "beam", "beam_pool"}


def files() -> dict[Path, Callable[[], Canvas | Light]]:
    c = CRYPT
    return {
        c / "floor@2x.svg": _one(floor, 32, 32, False),
        c / "wall@2x.svg": _one(wall, 32, 32, False),
        c / "wall_top@2x.svg": _one(wall_top, 32, 32, False),
        c / "pillar@2x.svg": _one(pillar, 32, 32),
        c / "pillar_top@2x.svg": _one(pillar_top, 32, 32),
        c / "door@2x.svg": _one(door, 32, 32, False),
        c / "torch@2x.svg": _one(torch, 32, 32),
        c / "torch_flame@2x.svg": _strip(torch_flame, 4, 32, 32),
        c / "torch_glow@2x.svg": _one(torch_glow, 64, 64, False),
        c / "torch_glow_core@2x.svg": _strip(torch_glow_core, 3, 32, 32, False),
        c / "candles@2x.svg": _one(candles, 32, 32),
        c / "candle_flame@2x.svg": _strip(candle_flame, 4, 32, 32, False),
        c / "skull@2x.svg": _one(skull, 32, 32),
        c / "rubble@2x.svg": _one(rubble, 32, 32),
        c / "bone_pile@2x.svg": _one(bone_pile, 32, 16),
        c / "sarcophagus@2x.svg": _one(sarcophagus, 64, 32),
        c / "fallen_column@2x.svg": _one(fallen_column, 64, 32),
        c / "ossuary_wall@2x.png": _dimmed(_one(ossuary_wall, 128, 32), DIM_BONE),
        HUB / "void@2x.svg": _one(void, 32, 32, False),
        PROPS / "hub_stone/stone@2x.png": _one(hub_stone, 96, 96),
        PROPS / "hub_stone/stone_lit@2x.svg": _one(hub_stone_lit, 96, 96, False),
        PROPS / "hub_stone/stone_lit_motes.svg": hub_stone_motes,
        PROPS / "hub_altar/altar@2x.png": _over(hub_altar, hub_altar_motes, 96, 96),
        DECOR / "beam@2x.png": beam,
        DECOR / "beam_pool@2x.png": beam_pool,
    }


def stem(path: Path) -> str:
    """A file's piece name: its name before `@2x`, else before its extension (a 1x mask)."""
    return Path(path.name.split("@")[0]).stem


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="write nothing; fail when a file differs")
    parser.add_argument("names", nargs="*", help="only these (a file's name before its @2x)")
    args = parser.parse_args(argv)
    every = files()
    known = {stem(path) for path in every}
    unknown = [n for n in args.names if n not in known]
    if unknown:
        parser.error(f"no such piece: {', '.join(unknown)}")
    status = 0
    for path, draw in every.items():
        if args.names and stem(path) not in args.names:
            continue
        picture = draw()
        data = picture.png() if path.suffix == ".png" else picture.svg().encode("utf-8")  # type: ignore[union-attr]
        if args.check:
            if not path.exists() or path.read_bytes() != data:
                print(f"{path.relative_to(ROOT)} differs from what tools/room_art.py draws", file=sys.stderr)
                status = 1
        else:
            path.write_bytes(data)
            print(f"wrote {path.relative_to(ROOT)}")
    return status


if __name__ == "__main__":
    sys.exit(main())
