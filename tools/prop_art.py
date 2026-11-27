#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
# SPDX-License-Identifier: GPL-3.0-or-later
"""The props drawn at 2x detail from their own shapes (ART3, part 1: props and breakables; the
owner, 2026-11-26: real new detail, by shape and light rules of each thing, never an upscale).

Each prop's looks are its parts in world units on its 1x art's grid (so it keeps its silhouette, its
size, its frames and where it stands), drawn by tools/sprite_rules.py: lit from the top-left in three
shades a material, with its material's surface (wood grain and boards, bone pores, stone speckle,
water streaks, a flame's core, a glint where it shines), seams between its parts and a one-art-pixel
outline. Stone that stands up from the floor (a pillar, a basin's rim) is `raised`: it takes its
shadow shade on the bottom-right, as the 1x art did.

A prop's mote masks (`<name>_motes.svg`: content/props/README.md) stay at 1x: a mask is never drawn,
only read for where motes stand, one a world pixel, so the motes are as many as before. Each is
written from its prop's own list of glowing points, the parts the 2x drawing lights there.

    tools/prop_art.py           # writes every prop's art
    tools/prop_art.py --check   # fails when a file differs from what the rules draw
    tools/prop_art.py crate     # only these (a prop's folder name)
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path
from typing import Callable

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sprite_rules as sr  # noqa: E402
from sprite_rules import OUTLINE, PALETTE, Hit, Part, ball, box, poly, rod, unit  # noqa: E402
from staff_art import Canvas  # noqa: E402

ROOT = sr.ROOT
PROPS = ROOT / "content/props"
Point = tuple[float, float]

STONE = dict(material="Stone", raised=True)
MASK_COLOUR = PALETTE["Bone"][2]


# --- shapes of their own ------------------------------------------------------------------------


def drum(cx: float, y0: float, y1: float, r_end: float, r_mid: float, **kw: object) -> Part:
    """A barrel's body: round across, bulging to `r_mid` at its middle from `r_end` at its ends;
    u down it, v across it (-1 to 1), so boards run down it."""
    mid, half = (y0 + y1) / 2.0, (y1 - y0) / 2.0

    def test(x: float, y: float) -> Hit | None:
        if not (y0 <= y <= y1):
            return None
        t = (y - mid) / half
        r = r_end + (r_mid - r_end) * (1.0 - t * t)
        s = (x - cx) / r
        if abs(s) > 1.0:
            return None
        return Hit(unit(s * 1.1, t * 0.35, math.sqrt(max(0.0, 1.0 - s * s)) + 0.25), y - y0, s)

    return Part(test, **kw)  # type: ignore[arg-type]


def column(x0: float, x1: float, y0: float, y1: float, **kw: object) -> Part:
    """A round column seen from the front: lit down its left, shaded down its right."""
    cx, r = (x0 + x1) / 2.0, (x1 - x0) / 2.0

    def test(x: float, y: float) -> Hit | None:
        if not (x0 <= x <= x1 and y0 <= y <= y1):
            return None
        s = (x - cx) / r
        return Hit(unit(s * 1.15, 0.0, math.sqrt(max(0.0, 1.0 - s * s)) + 0.15), y - y0, s)

    return Part(test, **kw)  # type: ignore[arg-type]


def tilted(part: Part, dx: float, dy: float) -> Part:
    """`part` with its facing leant by (dx, dy): a top face turned to the light (dy below 0)."""

    def test(x: float, y: float) -> Hit | None:
        hit = part.test(x, y)
        if hit is None:
            return None
        n = hit.normal
        return Hit(unit(n[0] + dx, n[1] + dy, n[2]), hit.u, hit.v)

    return Part(test, part.material, part.surface, part.colour, part.seam, part.glint, part.cracks, part.seed, part.raised)


def shifted(part: Part, ox: float, oy: float, turn: float = 0.0) -> Part:
    """`part` moved by (ox, oy) and turned by `turn` radians about its moved place's origin."""
    return sr.moved(part, ox, oy, 1.0, turn)


def line(points: list[Point], colour: str, r: float = 0.32) -> list[Part]:
    """A thin line of one colour along `points` (a vein, a crack drawn over a part), no seam."""
    return [rod(a, b, r, colour=colour, seam=False) for a, b in zip(points, points[1:])]


def chunk(cx: float, cy: float, w: float, h: float, turn: float = 0.0, seed: int = 0) -> Part:
    """A broken block of stone, its corners knocked off, turned by `turn` radians."""
    hw, hh = w / 2.0, h / 2.0
    k = min(hw, hh) * 0.45
    pts = [(-hw + k, -hh), (hw - k * 0.6, -hh), (hw, -hh + k), (hw, hh - k * 0.7), (hw - k, hh), (-hw + k * 0.5, hh), (-hw, hh - k), (-hw, -hh + k * 0.8)]
    return shifted(poly(pts, bevel=0.6, surface="pores", seed=seed, **STONE), cx, cy, turn)  # type: ignore[arg-type]


def mask_canvas(width: int, height: int, points: list[tuple[int, int]]) -> Canvas:
    """A 1x mote mask: `points` (whole world pixels) lit, every other clear."""
    canvas = Canvas(width, height)
    for x, y in points:
        canvas.pixels[y][x] = MASK_COLOUR
    return canvas


# --- the exploding barrel -----------------------------------------------------------------------


def _barrel_body() -> list[Part]:
    wood = dict(material="Wood", surface="board")
    return [
        drum(12.0, 10.4, 30.0, 5.6, 7.6, seed=1, **wood),  # type: ignore[arg-type]
        tilted(ball((12.0, 11.0), 4.6, 1.5, lean=0.3, material="Wood", surface="grain", seed=2), 0.0, -0.9),
        drum(12.0, 13.2, 15.0, 6.9, 7.2, surface="rivets", **STONE),  # type: ignore[arg-type]
        drum(12.0, 25.0, 26.8, 6.6, 6.9, surface="rivets", **STONE),  # type: ignore[arg-type]
    ]


def _fuse(spark: bool) -> list[Part]:
    parts = [rod((12.6, 10.4), (13.6, 6.0), 0.55, material="Wood", colour=PALETTE["Wood"][0])]
    if spark:
        parts += [
            ball((13.6, 5.2), 1.0, 1.0, material="Spark", glint=True, seam=False),
            ball((13.6, 4.0), 0.5, 0.7, material="Spark", colour=PALETTE["Spark"][2], seam=False),
        ]
    return parts


def _ember(hot: bool) -> list[Part]:
    """The burning rune on its front: a diamond of fire round a glowing heart."""
    rune = poly([(12.0, 15.6), (14.4, 19.4), (12.0, 22.4), (9.6, 19.4)], bevel=0.5, material="Fire", surface="flame", seam=True)
    heart = ball((12.0, 19.2), 1.1, 1.5, material="Spark" if hot else "Fire", glint=True, seam=False)
    return [rune, heart]


def barrel_idle() -> list[Part]:
    return _barrel_body() + _fuse(False) + _ember(False)


def barrel_fusing() -> list[Part]:
    return _barrel_body() + _fuse(True) + _ember(True)


def barrel_broken() -> list[Part]:
    """Its staves burst into a low ring of splinters round a scorched bottom, a hoop's piece, embers."""
    staves: list[Part] = []
    for (a, b, r, seed) in (
        ((6.0, 27.4), (6.6, 23.0), 1.1, 3),
        ((8.8, 27.6), (9.6, 24.2), 1.0, 4),
        ((13.6, 27.4), (13.6, 23.6), 1.0, 5),
        ((16.6, 27.6), (17.2, 22.6), 1.1, 6),
        ((18.6, 28.0), (18.4, 24.8), 0.9, 7),
    ):
        staves.append(rod(a, b, r, 0.55, material="Wood", surface="grain", seed=seed))
    return [
        tilted(ball((12.0, 28.4), 8.0, 2.4, lean=0.3, material="Wood", surface="board", seed=8), 0.0, -0.5),
        *staves,
        ball((11.2, 28.0), 3.0, 0.9, material="Fire", colour=PALETTE["Fire"][0], seam=False),
        ball((10.0, 27.8), 0.7, 0.6, material="Fire", glint=True, seam=False),
        ball((14.6, 28.2), 0.6, 0.5, material="Fire", glint=True, seam=False),
        rod((3.4, 30.2), (9.0, 30.6), 0.9, surface="rivets", **STONE),  # type: ignore[arg-type]
    ]


BARREL_MASK = [(11, 17), (12, 17), (11, 18), (12, 18), (10, 19), (11, 19), (12, 19), (13, 19), (10, 20), (13, 20), (11, 21), (12, 21)]


# --- the crate ----------------------------------------------------------------------------------


def _crate_parts(cracked: bool) -> list[Part]:
    top_points = [(1.6, 1.6), (22.4, 1.6), (22.4, 7.4), (1.6, 7.4)]
    if cracked:
        top_points = [(1.6, 1.6), (18.4, 1.6), (19.6, 3.0), (21.2, 3.4), (22.4, 4.8), (22.4, 7.4), (1.6, 7.4)]
    top = tilted(poly(top_points, bevel=0.5, material="Wood", surface="grain", seed=11), 0.0, -0.9)
    parts: list[Part] = [box(1.6, 7.0, 22.4, 22.4, bevel=0.6, material="Wood", surface="board", seed=12), top]
    # The top's boards, end on: dark joints between them.
    for x in (8.0, 14.0, 20.0):
        parts += line([(x, 1.8), (x, 7.2)], PALETTE["Wood"][0], 0.28)
    # The front's planks: a dark joint under each, a lit edge over the next.
    for y in (12.0, 17.0):
        parts += line([(2.2, y), (21.8, y)], OUTLINE, 0.36)
        parts.append(box(2.2, y + 0.4, 21.8, y + 0.95, bevel=0.0, material="Wood", colour=PALETTE["Wood"][2], seam=False))
    parts += line([(2.0, 7.6), (22.0, 7.6)], OUTLINE, 0.36)
    # The frame's corner posts.
    parts.append(box(1.6, 7.6, 3.4, 22.4, bevel=0.5, material="Wood", surface="grain", seed=13))
    parts.append(box(20.6, 7.6, 22.4, 22.4, bevel=0.5, material="Wood", surface="grain", seed=14))
    if cracked:
        parts += line([(7.6, 12.6), (8.8, 14.4), (8.4, 15.4), (10.2, 16.8)], OUTLINE, 0.34)
        parts += line([(18.8, 3.2), (19.4, 5.2)], OUTLINE, 0.3)
    return parts


def crate_idle() -> list[Part]:
    return _crate_parts(False)


def crate_cracked() -> list[Part]:
    return _crate_parts(True)


def crate_broken() -> list[Part]:
    """A low pile of loose, crossed planks and a corner post."""
    plank = dict(material="Wood", surface="board")
    return [
        box(1.6, 12.6, 4.6, 21.6, bevel=0.5, material="Wood", surface="grain", seed=15),
        shifted(box(-6.8, -1.2, 6.8, 1.2, bevel=0.5, seed=16, **plank), 11.6, 20.0, 0.0),  # type: ignore[arg-type]
        shifted(box(-7.0, -1.1, 7.0, 1.1, bevel=0.5, seed=17, **plank), 12.6, 17.4, -0.12),  # type: ignore[arg-type]
        shifted(box(-6.2, -1.1, 6.2, 1.1, bevel=0.5, seed=18, **plank), 14.4, 22.0, 0.05),  # type: ignore[arg-type]
        shifted(box(-1.1, -3.6, 1.1, 3.6, bevel=0.5, material="Wood", surface="grain", seed=19), 19.0, 17.8, 0.15),
        rod((5.6, 18.4), (9.4, 16.0), 0.5, 0.3, material="Wood", colour=PALETTE["Wood"][2], seam=False),
    ]


# --- the burial jar -----------------------------------------------------------------------------


def _jar_band(y: float, x0: float, x1: float) -> list[Part]:
    """The void cord bound round it, stitched."""
    parts: list[Part] = [box(x0, y - 0.7, x1, y + 0.7, bevel=0.3, material="Void", surface="wrap")]
    x = x0 + 1.6
    while x < x1 - 0.8:
        parts.append(box(x - 0.35, y - 1.5, x + 0.35, y + 1.5, bevel=0.0, material="Void", colour=PALETTE["Void"][1], seam=False))
        x += 3.0
    return parts


def jar_idle() -> list[Part]:
    bone = dict(material="Bone", surface="pores")
    return [
        ball((12.0, 12.6), 8.6, 7.4, lean=0.75, cracks=[[(16.6, 14.6), (17.6, 16.2), (17.0, 17.4)]], seed=21, **bone),  # type: ignore[arg-type]
        box(6.6, 5.0, 17.4, 6.4, bevel=0.4, material="Bone", colour=OUTLINE, seam=False),
        tilted(box(5.4, 2.6, 18.6, 5.2, corner=0.8, bevel=0.6, seed=22, **bone), 0.0, -0.4),  # type: ignore[arg-type]
        ball((12.0, 1.8), 1.6, 1.4, glint=True, **bone),  # type: ignore[arg-type]
        *_jar_band(10.4, 3.8, 20.2),
    ]


def jar_shattered() -> list[Part]:
    """Its bottom half left standing with a jagged rim, shards and the cord's ends round it."""
    bone = dict(material="Bone", surface="pores")
    rim = [(4.4, 19.4), (4.4, 15.6), (5.8, 12.4), (7.4, 14.6), (8.6, 12.8), (10.4, 15.2), (12.2, 11.0), (14.4, 14.2), (16.6, 10.6), (18.0, 13.4), (19.6, 15.6), (19.6, 19.4), (17.6, 19.8), (6.4, 19.8)]
    return [
        poly(rim, bevel=0.9, seed=23, **bone),  # type: ignore[arg-type]
        poly([(6.6, 16.0), (8.6, 14.2), (10.4, 16.4), (12.2, 13.2), (14.6, 15.6), (16.6, 12.8), (18.2, 15.8), (18.0, 17.6), (6.8, 17.6)], bevel=0.3, material="Bone", colour=PALETTE["Void"][0], seam=False),
        ball((3.6, 21.0), 1.6, 1.1, **bone),  # type: ignore[arg-type]
        poly([(7.6, 22.8), (8.6, 21.0), (9.8, 22.8)], bevel=0.4, **bone),  # type: ignore[arg-type]
        poly([(13.2, 21.4), (15.8, 21.2), (15.0, 23.0)], bevel=0.4, **bone),  # type: ignore[arg-type]
        ball((18.6, 21.4), 1.5, 1.0, **bone),  # type: ignore[arg-type]
        rod((6.6, 11.4), (7.8, 10.6), 0.5, material="Void", colour=PALETTE["Void"][1], seam=False),
    ]


# --- the dust heap ------------------------------------------------------------------------------


def mound(cx: float, base: float, rx: float, height: float, peak: float = 1.0, **kw: object) -> Part:
    """A heap on the floor: a dome `rx` wide each side and `height` tall over `base`, its sides
    falling straighter the higher `peak` (a cone at 0, a dome at 1); round both ways."""

    def test(x: float, y: float) -> Hit | None:
        if y > base:
            return None
        dx = (x - cx) / rx
        if abs(dx) > 1.0:
            return None
        top = base - height * (1.0 - abs(dx) ** (1.0 + peak)) ** (0.5 + 0.5 * peak)
        if y < top:
            return None
        up = (base - y) / height
        return Hit(unit(dx * 1.5, 0.25 - up * 0.7, 0.8), x - cx, up)

    return Part(test, **kw)  # type: ignore[arg-type]


def heap_heap() -> list[Part]:
    """A pale mound of bone dust, its grit pitted, lit on its upper left, a lump or two in it."""
    return [
        mound(12.0, 12.6, 10.6, 9.0, 0.35, material="Bone", surface="pores", seed=31),
        ball((8.4, 10.4), 1.0, 0.7, lean=0.9, material="Bone", surface="pores", seam=False, seed=34),
        ball((15.4, 9.4), 0.8, 0.6, lean=0.9, material="Bone", surface="pores", seam=False, seed=35),
    ]


def heap_scattered() -> list[Part]:
    """The heap kicked flat: a thin drift with flecks thrown round it."""
    parts: list[Part] = [
        mound(14.6, 11.6, 13.4, 4.2, 0.6, material="Bone", surface="pores", seed=32),
    ]
    for x, y in ((3.5, 7.5), (19.5, 5.5), (28.5, 9.5), (10.5, 13.5), (24.5, 13.5)):
        parts.append(box(x - 0.25, y - 0.25, x + 0.25, y + 0.25, bevel=0.0, material="Bone", colour=PALETTE["Bone"][0], seam=False))
    return parts


def heap_burnt() -> list[Part]:
    """The heap burnt to a slab of dark ash, embers glowing in it."""
    parts: list[Part] = [
        tilted(poly([(1.6, 11.0), (4.4, 8.4), (8.6, 7.4), (22.0, 7.4), (26.6, 8.4), (28.4, 10.6), (27.0, 12.8), (4.0, 12.8)], bevel=1.0, surface="pores", seed=33, **STONE), 0.0, 0.6),  # type: ignore[arg-type]
    ]
    for x, y, hot in ((9.6, 11.0, False), (14.6, 9.0, True), (23.2, 10.0, True), (6.6, 10.4, False), (18.2, 11.6, False)):
        parts.append(ball((x, y), 0.6, 0.5, material="Fire", colour=PALETTE["Fire"][1 if hot else 0], seam=False))
    return parts


# --- the arc lodestone --------------------------------------------------------------------------

LODESTONE_VEIN: list[Point] = [(11.4, 12.4), (12.4, 14.0), (12.6, 15.4), (11.4, 17.0), (10.6, 18.6), (11.0, 20.2), (12.4, 21.4), (13.6, 22.6), (13.0, 24.4)]
LODESTONE_ARCS: list[list[Point]] = [
    [(6.4, 15.0), (5.8, 17.0), (6.4, 19.0), (6.9, 21.0)],
    [(17.0, 11.6), (16.6, 14.0), (17.0, 16.6), (16.6, 19.0)],
]


def _lodestone(vein: str | None, arc: str | None, hot: bool) -> list[Part]:
    rock = [(9.0, 7.6), (14.8, 7.6), (16.4, 9.6), (16.4, 22.8), (17.6, 24.2), (17.6, 30.0), (16.4, 30.6), (7.6, 30.6), (6.4, 30.0), (6.4, 24.2), (7.4, 22.8), (7.4, 9.6)]
    cracks = [[(13.6, 26.0), (14.4, 27.6), (14.0, 29.0)]] if vein is not None else [[(11.4, 12.4), (12.4, 14.4), (11.0, 17.4), (11.2, 20.4), (13.4, 22.4), (13.0, 24.4)], [(13.6, 26.0), (14.4, 27.6), (14.0, 29.0)]]
    parts: list[Part] = [poly(rock, bevel=1.6, surface="pores", cracks=cracks, seed=41, **STONE)]  # type: ignore[arg-type]
    if vein is not None:
        parts += line(LODESTONE_VEIN, vein, 0.42)
        nodes = (LODESTONE_VEIN[0], LODESTONE_VEIN[4], LODESTONE_VEIN[7])
        for x, y in nodes:
            parts.append(ball((x, y), 0.8, 0.8, material="Arc", colour=PALETTE["Arc"][2] if hot else PALETTE["Arc"][1], seam=False))
    if arc is not None:
        for points in LODESTONE_ARCS:
            parts += [rod(a, b, 0.45, material="Arc", colour=arc, seam=True) for a, b in zip(points, points[1:])]
    return parts


def lodestone_idle() -> list[Part]:
    return _lodestone(PALETTE["Arc"][0], PALETTE["Arc"][1], False)


def lodestone_charged() -> list[Part]:
    return _lodestone(PALETTE["Arc"][2], PALETTE["Arc"][2], True)


def lodestone_spent() -> list[Part]:
    return _lodestone(None, None, False)


LODESTONE_MASK = [(11, 12), (12, 15), (10, 19), (13, 22)]


# --- the fire pit -------------------------------------------------------------------------------

PIT_STONES: list[tuple[float, float, float, float]] = [
    (12.0, 13.0, 2.0, 1.6), (8.2, 13.8, 2.0, 1.5), (15.8, 13.8, 2.0, 1.5), (4.8, 15.6, 2.0, 1.6), (19.2, 15.6, 2.0, 1.6),
    (3.8, 18.6, 1.8, 1.6), (20.2, 18.6, 1.8, 1.6), (6.4, 20.8, 2.0, 1.5), (17.6, 20.8, 2.0, 1.5), (12.0, 21.4, 2.2, 1.6),
]


def _fire_pit(lit: bool) -> list[Part]:
    parts: list[Part] = [ball((12.0, 17.4), 7.4, 3.6, lean=0.2, material="Stone", colour=OUTLINE, seam=False)]
    # The logs, crossed over the dark hollow.
    parts.append(rod((6.8, 18.0), (12.6, 15.8), 1.0, material="Wood", surface="grain", seed=51))
    parts.append(rod((17.2, 18.0), (11.4, 15.8), 1.0, material="Wood", surface="grain", seed=52))
    parts.append(rod((9.2, 18.4), (15.0, 18.6), 0.9, material="Wood", surface="grain", seed=53))
    if lit:
        for x, y, shade in ((9.4, 16.8, 1), (12.0, 17.2, 2), (14.6, 16.8, 1), (11.0, 19.4, 0), (13.4, 19.4, 1)):
            parts.append(ball((x, y), 0.9, 0.6, material="Fire", colour=PALETTE["Fire"][shade], seam=False))
        parts.append(ball((12.0, 17.0), 0.5, 0.4, material="Spark", colour=PALETTE["Spark"][2], seam=False))
    for i, (x, y, rx, ry) in enumerate(PIT_STONES):
        parts.append(ball((x, y), rx, ry, lean=0.8, surface="pores", seed=54 + i, **STONE))  # type: ignore[arg-type]
    return parts


def pit_unlit() -> list[Part]:
    return _fire_pit(False)


def pit_lit() -> list[Part]:
    return _fire_pit(True)


def _flame(frame: int) -> list[Part]:
    """One frame of the pit's fire: tongues of flame round a bright core, licking up in turn."""
    tips = ((12.0, 3.0), (12.6, 4.2), (11.4, 3.6))[frame]
    left = ((8.6, 9.6), (8.0, 9.0), (8.8, 8.6))[frame]
    right = ((15.4, 8.0), (15.8, 9.6), (15.0, 9.2))[frame]
    flame = dict(material="Fire", surface="flame", seam=False)
    parts: list[Part] = [
        poly([(7.6, 17.6), (left[0], left[1] + 3.0), left, (9.6, 12.0), tips, (14.4, 11.4), right, (right[0] + 0.6, right[1] + 3.6), (16.4, 17.6)], bevel=0.6, **flame),  # type: ignore[arg-type]
        poly([(9.4, 17.6), (10.0, 12.4), (tips[0], tips[1] + 4.2), (14.0, 12.8), (14.6, 17.6)], bevel=0.4, material="Spark", surface="flame", seam=False),
        ball((12.0, 15.8), 1.6, 1.8, material="Spark", colour=PALETTE["Spark"][2], seam=False),
    ]
    sparks = (((8.6, 6.4),), ((13.6, 1.8),), ((15.2, 4.2), (9.4, 2.6)))[frame]
    for x, y in sparks:
        parts.append(box(x - 0.5, y - 0.5, x + 0.5, y + 0.5, bevel=0.0, material="Fire", colour=PALETTE["Fire"][2], seam=False))
    return parts


# --- the fountain -------------------------------------------------------------------------------


def _fountain(welling: bool) -> list[Part]:
    water = dict(material="Water", surface="streak")
    parts: list[Part] = [
        # The basin: a round stone bowl, its rim lit at the back, its front face shaded.
        ball((15.4, 23.4), 14.0, 7.4, lean=0.55, surface="pores", seed=61, **STONE),  # type: ignore[arg-type]
        tilted(ball((15.4, 20.8), 12.4, 4.4, lean=0.25, material="Water", surface="streak", glint=True, seed=62), 0.0, -0.2),
        ball((15.4, 20.8), 10.4, 3.2, lean=0.25, material="Water", colour=PALETTE["Water"][1], seam=False),
    ]
    for x, y in ((8.0, 22.2), (12.4, 23.0), (19.0, 22.4), (22.6, 23.0)):
        parts.append(rod((x - 1.0, y), (x + 1.0, y), 0.4, material="Water", colour=PALETTE["Water"][2], seam=False))
    # The column and its bowl.
    parts.append(column(13.6, 18.4, 10.0, 21.0, surface="pores", cracks=[[(13.8, 16.6), (18.2, 16.6)]], seed=63, **STONE))  # type: ignore[arg-type]
    parts.append(box(11.4, 9.6, 20.6, 11.4, bevel=0.6, corner=0.6, **STONE))  # type: ignore[arg-type]
    parts.append(tilted(ball((16.0, 8.8), 4.6, 1.6, lean=0.3, glint=True, **water), 0.0, -0.4))  # type: ignore[arg-type]
    # Its trickle down the right side into the basin.
    parts.append(rod((20.4, 11.6), (20.4, 18.6), 0.5, material="Water", colour=PALETTE["Water"][2] if welling else PALETTE["Water"][1], seam=True))
    if welling:
        # A spout of water up out of the bowl, white at its top, spilling down both sides.
        parts.append(rod((16.0, 8.4), (16.0, 2.4), 2.2, 1.6, surface="streak", glint=True, material="Water", seed=64))
        parts.append(ball((16.0, 2.2), 0.9, 0.9, material="Bone", colour=PALETTE["Bone"][2], seam=False))
        parts.append(rod((11.6, 11.6), (11.6, 17.4), 0.5, material="Water", colour=PALETTE["Water"][2], seam=True))
        parts.append(ball((6.6, 21.0), 0.8, 0.5, material="Bone", colour=PALETTE["Bone"][2], seam=False))
        parts.append(ball((25.4, 21.0), 0.8, 0.5, material="Bone", colour=PALETTE["Bone"][2], seam=False))
    return parts


def fountain_still() -> list[Part]:
    return _fountain(False)


def fountain_welling() -> list[Part]:
    return _fountain(True)


FOUNTAIN_STILL_MASK = [(15, 9), (16, 9)]
FOUNTAIN_WELLING_MASK = [(15, 2), (16, 3), (14, 4), (17, 5)]


# --- the cracked pillar -------------------------------------------------------------------------

CRACK_DOWN: list[Point] = [(12.6, 7.6), (11.4, 10.6), (13.0, 13.4), (11.6, 16.6), (12.8, 19.6), (11.0, 23.4), (12.4, 26.6), (11.6, 30.4), (13.0, 33.8)]


def _square_pillar(cracks: list[list[Point]]) -> list[Part]:
    joints = [[(4.8, y), (19.2, y)] for y in (14.0, 22.0, 30.0, 38.0)]
    return [
        box(4.4, 7.0, 19.6, 41.6, bevel=1.6, surface="pores", cracks=joints + cracks, seed=71, **STONE),  # type: ignore[arg-type]
        box(2.4, 41.4, 21.6, 46.4, bevel=1.0, surface="pores", seed=72, **STONE),  # type: ignore[arg-type]
        tilted(box(1.4, 1.4, 22.6, 7.4, bevel=1.0, surface="pores", cracks=[c for c in cracks if c[0][1] < 7.0], seed=73, **STONE), 0.0, -0.3),  # type: ignore[arg-type]
    ]


def pillar_intact() -> list[Part]:
    return _square_pillar([])


def pillar_cracked() -> list[Part]:
    return _square_pillar([CRACK_DOWN, [(18.6, 2.6), (19.6, 4.6), (19.0, 6.6)], [(15.6, 44.6), (16.6, 46.0)]])


def pillar_rubble() -> list[Part]:
    """What is left: three blocks fallen in a heap, a chip on top."""
    return [
        chunk(5.0, 12.0, 7.0, 4.4, 0.0, 74),
        chunk(18.6, 12.4, 8.0, 4.0, 0.0, 75),
        chunk(12.0, 10.8, 6.4, 7.0, 0.0, 76),
        chunk(6.6, 7.0, 3.6, 2.8, -0.2, 77),
    ]


# --- the crypt pillar and its crumble -----------------------------------------------------------

CAP_Y0, CAP_Y1 = 3.4, 10.6
SHAFT_X0, SHAFT_X1 = 13.4, 34.6
SHAFT_Y1 = 54.6
BASE_Y0, BASE_Y1 = 54.4, 62.4
CRYPT_CRACK: list[Point] = [(31.6, 14.6), (30.4, 18.4), (31.8, 22.2), (30.0, 26.4), (31.4, 30.6), (29.6, 35.0), (31.0, 39.4), (29.8, 43.4), (31.2, 47.6)]
CRYPT_CRACK_2: list[Point] = [(20.6, 14.6), (21.8, 19.0), (20.2, 23.6), (22.0, 28.4), (20.6, 33.4), (22.2, 38.6), (20.8, 43.6)]


def _shaft(top: float, cracks: list[list[Point]], jagged: bool = False) -> list[Part]:
    """The fluted column from `top` down to its base: drum joints and flutes cut a shade down."""
    flutes = [[(x, top + 0.6), (x, SHAFT_Y1 - 0.6)] for x in (17.4, 21.4, 26.6, 30.6)]
    joints = [[(SHAFT_X0 + 0.4, y), (SHAFT_X1 - 0.4, y)] for y in (27.4, 41.4) if y > top + 1.0]
    parts: list[Part] = [column(SHAFT_X0, SHAFT_X1, top, SHAFT_Y1, surface="pores", cracks=flutes + joints + cracks, seed=81, **STONE)]  # type: ignore[arg-type]
    if jagged:
        # A broken top: a row of teeth knocked out of it, dark where the stone broke.
        for i, x in enumerate((14.6, 18.4, 22.2, 26.0, 29.8, 33.4)):
            parts.append(poly([(x - 1.2, top - 0.2), (x, top - 0.2), (x + 1.4, top + 1.6 + (i % 2) * 0.8), (x - 1.2, top + 1.6)], bevel=0.0, material="Stone", colour=OUTLINE, seam=False))
    return parts


def _cap(right_chip: bool, left_gone: bool) -> list[Part]:
    """The capital: a lit slab over a moulding that narrows into the shaft."""
    x0 = 22.4 if left_gone else 8.4
    slab_points = [(x0, CAP_Y0), (39.6, CAP_Y0), (39.6, CAP_Y1), (x0, CAP_Y1)]
    if right_chip:
        slab_points = [(x0, CAP_Y0), (35.8, CAP_Y0), (37.0, 4.8), (39.6, 5.4), (39.6, CAP_Y1), (x0, CAP_Y1)]
    neck_x0 = 22.4 if left_gone else 10.4
    return [
        poly([(neck_x0, 10.4), (37.6, 10.4), (34.6, 14.8), (SHAFT_X0 if not left_gone else 22.4, 14.8)], bevel=0.8, surface="pores", seed=82, **STONE),  # type: ignore[arg-type]
        tilted(poly(slab_points, bevel=1.0, surface="pores", seed=83, **STONE), 0.0, -0.5),  # type: ignore[arg-type]
    ]


def _base() -> list[Part]:
    return [
        box(9.4, BASE_Y0 + 2.6, 38.6, BASE_Y1, bevel=1.0, corner=0.8, surface="pores", cracks=[[(10.0, 59.4), (38.0, 59.4)]], seed=84, **STONE),  # type: ignore[arg-type]
        tilted(rod((11.4, BASE_Y0 + 1.6), (36.6, BASE_Y0 + 1.6), 1.6, surface="pores", seed=85, **STONE), 0.0, -0.2),  # type: ignore[arg-type]
    ]


def _crypt_pillar(crack: int = 0, crack_2: int = 0, chip: Point | None = None, right_chip: bool = False,
                  left_cap: tuple[float, float, float] | None = None, rest_chunk: bool = False) -> list[Part]:
    """The whole pillar: `crack` and `crack_2` points of its cracks grown down it, a falling `chip`,
    its cap's right corner gone (`right_chip`), its cap's left half moved by `left_cap` (dx, dy,
    turn), or lying at its foot (`rest_chunk`)."""
    cracks = [CRYPT_CRACK[:crack]] if crack >= 2 else []
    if crack_2 >= 2:
        cracks.append(CRYPT_CRACK_2[:crack_2])
    parts = _base() + _shaft(14.6, cracks) + _cap(right_chip, left_cap is not None or rest_chunk)
    if left_cap is not None:
        dx, dy, turn = left_cap
        slab = poly([(-7.0, -3.6), (7.0, -3.6), (7.0, 2.0), (5.4, 3.6), (-7.0, 3.6)], bevel=1.0, surface="pores", seed=86, **STONE)  # type: ignore[arg-type]
        parts.append(shifted(tilted(slab, 0.0, -0.5), 15.4 + dx, 7.0 + dy, turn))
    if rest_chunk:
        parts.append(chunk(9.4, 58.6, 9.0, 4.6, 0.0, 87))
    if chip is not None:
        parts.append(chunk(chip[0], chip[1], 2.6, 2.2, 0.4, 88))
    return parts


CHIP_FALL: list[Point | None] = [None, (40.6, 6.4), (41.4, 11.6), (41.8, 22.4), (41.4, 37.2), (40.6, 60.4)]


def crypt_intact() -> list[Part]:
    return _crypt_pillar()


def crypt_cracking(frame: int) -> list[Part]:
    """Six frames: a chip knocked off its cap falls to its foot as a crack runs down its shaft."""
    return _crypt_pillar(crack=(0, 3, 4, 6, 8, 9)[frame], chip=CHIP_FALL[frame], right_chip=frame > 0)


LEFT_FALL: list[tuple[float, float, float] | None] = [None, None, (-1.0, -1.0, -0.12), (-6.4, 2.4, -0.5), (-7.4, 12.0, -1.1), (-8.4, 34.0, -1.4), None]


def crypt_splitting(frame: int) -> list[Part]:
    """Seven frames: a second crack splits it, the cap's left half breaks off and falls to its foot."""
    return _crypt_pillar(crack=9, crack_2=(0, 4, 7, 7, 7, 7, 7)[frame], chip=CHIP_FALL[-1], right_chip=True, left_cap=LEFT_FALL[frame], rest_chunk=frame == 6)


def _rubble_heap(share: float) -> list[Part]:
    """The heap at its foot, `share` (0 to 1) of the way to all the pillar's drums."""
    stones = [
        (12.6, 59.0, 9.0, 4.6, 0.0), (35.6, 59.4, 7.0, 4.0, 0.1), (24.0, 58.6, 10.0, 5.0, -0.05),
        (17.6, 55.6, 8.0, 4.4, 0.25), (30.4, 55.8, 8.4, 4.2, -0.2), (6.4, 60.4, 4.6, 3.2, 0.3),
        (41.4, 60.6, 4.4, 3.0, -0.3), (23.6, 53.0, 7.0, 4.0, 0.1), (27.6, 51.0, 4.0, 3.0, -0.4),
    ]
    count = max(1, round(share * len(stones)))
    return [chunk(x, y, w, h, t, 90 + i) for i, (x, y, w, h, t) in enumerate(stones[:count])]


CAP_FLIGHT: list[tuple[float, float, float] | None] = [None, (2.0, -1.4, 0.2), (5.0, 0.2, 0.5), (7.0, 6.0, 0.9), (8.0, 20.0, 1.3), (6.0, 40.0, 1.5), None, None, None]
SHAFT_TOP: list[float] = [14.6, 20.6, 27.0, 34.0, 41.0, 48.0, 0.0, 0.0, 0.0]


def crypt_collapsing(frame: int) -> list[Part]:
    """Nine frames: what is left of its cap flies off, the shaft comes down drum by drum, and the
    drums settle into a heap."""
    if frame == 0:
        return crypt_splitting(6)
    parts: list[Part] = []
    top = SHAFT_TOP[frame]
    share = (0.15, 0.3, 0.45, 0.6, 0.75, 0.88, 0.96, 1.0, 1.0)[frame]
    parts += _base()
    if top > 0.0:
        parts += _shaft(top, [CRYPT_CRACK[1:], CRYPT_CRACK_2[1:]], jagged=True)
    parts += _rubble_heap(share)
    flight = CAP_FLIGHT[frame]
    if flight is not None:
        dx, dy, turn = flight
        parts.append(chunk(30.0 + dx, 7.0 + dy, 14.0, 6.0, turn, 99))
    if frame >= 1 and frame <= 3:
        parts.append(chunk(10.0 - frame * 1.4, 18.0 + frame * 10.0, 2.4, 2.2, 0.6 * frame, 100))
    if frame == 6:
        parts.append(chunk(34.0, 52.6, 3.0, 2.4, 0.5, 101))
    if frame == 7:
        parts.append(chunk(34.6, 55.4, 3.0, 2.4, 0.9, 101))
    if frame == 8:
        parts.append(chunk(35.0, 55.6, 3.0, 2.4, 1.1, 101))
    return parts


# --- the files ----------------------------------------------------------------------------------


def _one(parts: Callable[[], list[Part]], w: int, h: int) -> Callable[[], Canvas]:
    return lambda: sr.draw(parts(), w, h)


def _strip(frame: Callable[[int], list[Part]], count: int, w: int, h: int) -> Callable[[], Canvas]:
    return lambda: sr.strip([frame(i) for i in range(count)], w, h)


def _mask(w: int, h: int, points: list[tuple[int, int]]) -> Callable[[], Canvas]:
    return lambda: mask_canvas(w, h, points)


def files() -> dict[Path, Callable[[], Canvas]]:
    p = PROPS
    return {
        p / "arc_lodestone/idle@2x.svg": _one(lodestone_idle, 24, 32),
        p / "arc_lodestone/charged@2x.svg": _one(lodestone_charged, 24, 32),
        p / "arc_lodestone/spent@2x.svg": _one(lodestone_spent, 24, 32),
        p / "arc_lodestone/idle_motes.svg": _mask(24, 32, LODESTONE_MASK),
        p / "arc_lodestone/charged_motes.svg": _mask(24, 32, LODESTONE_MASK),
        p / "burial_jar/idle@2x.svg": _one(jar_idle, 24, 24),
        p / "burial_jar/shattered@2x.svg": _one(jar_shattered, 24, 24),
        p / "cracked_pillar/intact@2x.svg": _one(pillar_intact, 24, 48),
        p / "cracked_pillar/cracked@2x.svg": _one(pillar_cracked, 24, 48),
        p / "cracked_pillar/rubble@2x.svg": _one(pillar_rubble, 24, 16),
        p / "crate/idle@2x.svg": _one(crate_idle, 24, 24),
        p / "crate/cracked@2x.svg": _one(crate_cracked, 24, 24),
        p / "crate/broken@2x.svg": _one(crate_broken, 24, 24),
        p / "crypt_pillar/intact@2x.svg": _one(crypt_intact, 48, 64),
        p / "crypt_pillar/cracking@2x.png": _strip(crypt_cracking, 6, 48, 64),
        p / "crypt_pillar/splitting@2x.png": _strip(crypt_splitting, 7, 48, 64),
        p / "crypt_pillar/collapsing@2x.png": _strip(crypt_collapsing, 9, 48, 64),
        p / "dust_heap/heap@2x.svg": _one(heap_heap, 24, 16),
        p / "dust_heap/scattered@2x.svg": _one(heap_scattered, 32, 16),
        p / "dust_heap/burnt@2x.svg": _one(heap_burnt, 32, 16),
        p / "exploding_barrel/idle@2x.svg": _one(barrel_idle, 24, 32),
        p / "exploding_barrel/fusing@2x.svg": _one(barrel_fusing, 24, 32),
        p / "exploding_barrel/broken@2x.svg": _one(barrel_broken, 24, 32),
        p / "exploding_barrel/idle_motes.svg": _mask(24, 32, BARREL_MASK),
        p / "fire_pit/unlit@2x.svg": _one(pit_unlit, 24, 24),
        p / "fire_pit/lit@2x.svg": _one(pit_lit, 24, 24),
        p / "fire_pit/flames@2x.svg": _strip(_flame, 3, 24, 24),
        p / "fountain/still@2x.svg": _one(fountain_still, 32, 32),
        p / "fountain/welling@2x.svg": _one(fountain_welling, 32, 32),
        p / "fountain/still_motes.svg": _mask(32, 32, FOUNTAIN_STILL_MASK),
        p / "fountain/welling_motes.svg": _mask(32, 32, FOUNTAIN_WELLING_MASK),
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="write nothing; fail when a file differs")
    parser.add_argument("names", nargs="*", help="only these (a prop's folder name)")
    args = parser.parse_args(argv)
    every = files()
    known = {path.parent.name for path in every}
    unknown = [n for n in args.names if n not in known]
    if unknown:
        parser.error(f"no such prop: {', '.join(unknown)}")
    status = 0
    for path, draw in every.items():
        if args.names and path.parent.name not in args.names:
            continue
        picture = draw()
        data = picture.png() if path.suffix == ".png" else picture.svg().encode("utf-8")
        if args.check:
            if not path.exists() or path.read_bytes() != data:
                print(f"{path.relative_to(ROOT)} differs from what tools/prop_art.py draws", file=sys.stderr)
                status = 1
        else:
            path.write_bytes(data)
            print(f"wrote {path.relative_to(ROOT)}")
    return status


if __name__ == "__main__":
    sys.exit(main())
