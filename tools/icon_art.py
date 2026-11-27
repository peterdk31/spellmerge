#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
# SPDX-License-Identifier: GPL-3.0-or-later
"""The card and sigil icons drawn at 2x detail from their own shapes (ART2; the owner, 2026-11-26:
real new detail, hand-drawn per sprite, never a 2x upscale).

Each icon below is its parts in world units on its 1x icon's 16 x 16 grid (so it keeps its idea and
its silhouette), drawn by tools/sprite_rules.py at 32 x 32 art pixels as `icon@2x.svg`: lit from the
top-left in three shades a material, with its material's surface, seams between its parts and a
one-art-pixel outline. The 1x `icon.svg` stays beside it for the HUD's small cells (`IconDetail`).

    tools/icon_art.py           # writes every icon
    tools/icon_art.py --check   # fails when a file differs from what the rules draw
    tools/icon_art.py fire bolt # only these (a card's or a sigil's folder name)
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path
from typing import Callable

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sprite_rules as sr  # noqa: E402
from sprite_rules import OUTLINE, Part, ball, box, poly, ring, rod  # noqa: E402
from staff_art import Canvas  # noqa: E402

ROOT = sr.ROOT
SIZE = 16
SPELLS = ROOT / "content/spells"
SIGILS = ROOT / "content/sigils"


def _star(c: tuple[float, float], outer: float, inner: float, points: int, turn: float = 0.0) -> list[tuple[float, float]]:
    out = []
    for i in range(points * 2):
        r = outer if i % 2 == 0 else inner
        a = turn + math.pi * i / points
        out.append((c[0] + math.cos(a) * r, c[1] + math.sin(a) * r))
    return out


def _bolt(ox: float = 0.0, oy: float = 0.0, s: float = 1.0) -> list[tuple[float, float]]:
    """A lightning bolt's zigzag, top right to bottom left."""
    pts = [(9.6, 0.8), (3.4, 9.0), (7.4, 9.0), (5.0, 15.2), (12.8, 6.2), (8.8, 6.2), (12.6, 0.8)]
    return [(ox + 8.0 + (x - 8.0) * s, oy + 8.0 + (y - 8.0) * s) for x, y in pts]


# --- carriers -------------------------------------------------------------------------------------


def atom() -> list[Part]:
    """A tiny bright speck flying up and right, a thin trail of sparks behind it."""
    return [
        rod((2.4, 11.6), (5.0, 10.2), 0.4, material="Spark", seam=False),
        rod((6.0, 9.6), (9.2, 7.8), 0.45, material="Spark", seam=False),
        ball((11.6, 6.6), 2.0, 2.0, material="Spark", glint=True),
    ]


def beam() -> list[Part]:
    """A beam across: a gold band with a white-hot core and flared ends."""
    return [
        poly([(0.8, 6.0), (3.0, 7.0), (13.0, 7.0), (15.2, 6.0), (15.2, 10.0), (13.0, 9.0), (3.0, 9.0), (0.8, 10.0)], bevel=0.7, material="Spark"),
        box(2.6, 7.6, 13.4, 8.4, bevel=0.2, material="Bone", colour=sr.PALETTE["Bone"][2], seam=False),
    ]


def bolt() -> list[Part]:
    """A comet flying right: a pale tail tapering behind a gold-tipped head."""
    return [
        poly([(1.0, 7.0), (9.0, 5.6), (9.0, 10.4), (1.0, 9.0)], bevel=0.8, material="Bone", surface="streak"),
        ball((11.0, 8.0), 3.2, 2.6, material="Bone", glint=True),
        poly([(12.4, 6.2), (15.2, 8.0), (12.4, 9.8)], bevel=0.5, material="Spark", seam=True),
    ]


def dash() -> list[Part]:
    """An arrow leaping right with speed lines behind it."""
    return [
        box(1.0, 5.4, 4.6, 6.4, bevel=0.3, material="Stone", seam=False),
        box(0.6, 9.6, 4.6, 10.6, bevel=0.3, material="Stone", seam=False),
        poly([(5.2, 5.6), (9.2, 5.6), (9.2, 3.0), (15.0, 8.0), (9.2, 13.0), (9.2, 10.4), (5.2, 10.4)], bevel=0.8, material="Bone"),
    ]


def decoy() -> list[Part]:
    """A pale stand-in: a round head on a sack of a body."""
    return [
        poly([(4.4, 15.0), (5.0, 8.4), (11.0, 8.4), (11.6, 15.0)], bevel=0.9, material="Bone", surface="pores"),
        ball((8.0, 5.4), 3.4, 3.4, material="Bone", glint=True),
        box(6.2, 4.6, 7.2, 6.0, bevel=0.1, colour=OUTLINE),
        box(8.8, 4.6, 9.8, 6.0, bevel=0.1, colour=OUTLINE),
    ]


def familiar() -> list[Part]:
    """A round little spirit with two eyes and two small horns, hovering."""
    return [
        poly([(3.6, 5.6), (4.2, 1.6), (6.6, 4.4)], bevel=0.4, material="Bone"),
        poly([(12.4, 5.6), (11.8, 1.6), (9.4, 4.4)], bevel=0.4, material="Bone"),
        ball((8.0, 8.6), 6.0, 5.4, material="Bone", glint=True),
        ball((6.0, 8.0), 0.8, 1.2, colour=OUTLINE),
        ball((10.0, 8.0), 0.8, 1.2, colour=OUTLINE),
        box(4.4, 14.4, 11.6, 15.0, bevel=0.2, material="Stone", seam=False),
    ]


def field() -> list[Part]:
    """A trembling ring on the floor, seen at a slant, shots caught in it."""
    return [
        ring((8.0, 8.4), 6.8, 5.2, material="Ice"),
        ball((6.6, 7.6), 1.2, 1.2, material="Spark", glint=True),
        ball((9.8, 9.6), 1.0, 1.0, material="Spark", glint=True),
    ]


def pool() -> list[Part]:
    """A puddle of light on the floor, its rim lifted, a ripple in it."""
    return [
        ball((8.0, 9.0), 7.2, 3.8, lean=0.5, material="Ice", surface="streak"),
        ring((8.0, 9.0), 3.6, 2.6, material="Ice", seam=False),
    ]


def portal() -> list[Part]:
    """Two rings, one each end, linked by a line of light."""
    return [
        rod((5.2, 10.8), (10.8, 5.2), 0.5, material="Void", seam=False),
        ring((4.4, 11.6), 3.4, 1.8, material="Void"),
        ring((11.6, 4.4), 3.4, 1.8, material="Void"),
    ]


def pulse() -> list[Part]:
    """A gold ring going out from a bright middle."""
    return [
        ring((8.0, 8.0), 7.0, 5.0, material="Spark"),
        box(6.4, 6.4, 9.6, 9.6, bevel=0.6, corner=0.6, material="Bone", glint=True),
    ]


def rune() -> list[Part]:
    """A gold rune stone, a diamond with a mark cut in it."""
    return [
        poly([(8.0, 0.8), (15.2, 8.0), (8.0, 15.2), (0.8, 8.0)], bevel=1.2, material="Spark", glint=True),
        poly([(8.0, 5.0), (11.0, 8.0), (8.0, 11.0), (5.0, 8.0)], bevel=0.5, material="Spark", colour=sr.PALETTE["Spark"][0]),
    ]


def slam() -> list[Part]:
    """A hammer coming down on the floor, sparks flying from the blow."""
    return [
        box(1.0, 13.4, 15.0, 15.0, bevel=0.5, material="Stone", surface="speckle"),
        rod((8.0, 1.8), (8.0, 8.0), 0.9, material="Wood", surface="grain"),
        box(3.6, 7.4, 12.4, 12.6, bevel=1.0, corner=0.6, material="Stone", glint=True),
        box(3.6, 9.4, 12.4, 10.4, bevel=0.3, material="Spark", seam=True),
        rod((2.6, 11.6), (1.2, 9.4), 0.45, material="Spark", seam=False),
        rod((13.4, 11.6), (14.8, 9.4), 0.45, material="Spark", seam=False),
    ]


def spray() -> list[Part]:
    """A fan of droplets thrown up and right from a nozzle."""
    return [
        rod((2.0, 14.0), (6.0, 10.0), 1.0, material="Wood", surface="grain"),
        poly([(6.0, 10.6), (14.6, 1.6), (15.0, 6.4), (7.2, 11.6)], bevel=0.9, material="Ice", surface="streak", glint=True),
    ]


def swap() -> list[Part]:
    """Two arrows passing each other, one each way."""
    return [
        poly([(1.2, 4.0), (10.0, 4.0), (10.0, 2.0), (14.8, 5.2), (10.0, 8.4), (10.0, 6.4), (1.2, 6.4)], bevel=0.6, material="Bone"),
        poly([(14.8, 9.6), (6.0, 9.6), (6.0, 7.6), (1.2, 10.8), (6.0, 14.0), (6.0, 12.0), (14.8, 12.0)], bevel=0.6, material="Bone"),
    ]


def swing() -> list[Part]:
    """A blade swung through an arc, its trail of light curving behind it."""
    arc = [(3.0 + 10.0 * math.sin(a), 13.0 - 10.0 * math.cos(a)) for a in [i * 0.16 for i in range(11)]]
    inner = [(3.0 + 8.2 * math.sin(a), 13.0 - 8.2 * math.cos(a)) for a in [i * 0.16 for i in range(11)]][::-1]
    return [
        poly(arc + inner, bevel=0.5, material="Spark", seam=False),
        rod((2.0, 14.0), (5.6, 10.4), 0.9, material="Wood", surface="grain"),
        poly([(5.0, 9.6), (11.6, 3.0), (12.6, 4.0), (6.2, 11.0)], bevel=0.5, material="Bone", glint=True),
    ]


def teleport() -> list[Part]:
    """A tall door of void light, marks at its sides where one steps out."""
    return [
        ball((8.0, 8.0), 4.4, 6.6, material="Void", glint=True),
        ball((8.0, 8.0), 2.0, 4.0, colour=sr.PALETTE["Void"][0]),
        box(1.0, 7.4, 2.4, 8.6, bevel=0.2, material="Void", seam=False),
        box(13.6, 7.4, 15.0, 8.6, bevel=0.2, material="Void", seam=False),
    ]


def wall() -> list[Part]:
    """A stone wall of bricks, each bevelled, the joints dark."""
    parts: list[Part] = []
    for row, y in enumerate((2.0, 6.0, 10.0)):
        shift = 0.0 if row % 2 == 0 else -3.5
        x = 1.0 + shift
        while x < 15.0:
            parts.append(box(max(x, 1.0), y, min(x + 6.6, 15.0), y + 3.6, bevel=0.7, material="Stone", surface="speckle", seed=row))
            x += 7.0
    return parts


# --- elements -------------------------------------------------------------------------------------


def fire() -> list[Part]:
    """A flame: an outer tongue of fire, a hotter one inside it, a white heart at its root."""
    return [
        poly([(8.0, 0.8), (12.6, 7.0), (13.2, 11.0), (11.0, 14.6), (5.0, 14.6), (2.8, 11.0), (3.6, 7.6), (5.6, 9.0), (6.0, 5.0)], bevel=1.0, material="Fire", surface="flame"),
        poly([(8.4, 5.4), (10.8, 10.0), (9.8, 13.6), (6.2, 13.6), (5.4, 11.0), (7.0, 9.6)], bevel=0.6, material="Spark", seam=False),
        ball((8.0, 12.2), 1.4, 1.2, colour=sr.PALETTE["Bone"][2]),
    ]


def frost() -> list[Part]:
    """A cut ice crystal: a long diamond with its facets lit from the top-left."""
    return [
        poly([(8.0, 0.8), (14.4, 8.0), (8.0, 15.2), (1.6, 8.0)], bevel=1.6, material="Ice", surface="streak", glint=True),
        poly([(8.0, 3.6), (10.6, 8.0), (8.0, 12.4), (5.4, 8.0)], bevel=0.4, material="Ice", seam=False, glint=True),
    ]


def lightning() -> list[Part]:
    """A bolt of lightning, its zigzag bevelled and glinting."""
    return [poly(_bolt(), bevel=0.7, material="Arc", glint=True)]


def mend() -> list[Part]:
    """A green cross, bevelled, with a leaf at its heart."""
    return [
        box(5.6, 1.4, 10.4, 14.6, bevel=1.0, corner=0.6, material="Leaf"),
        box(1.4, 5.6, 14.6, 10.4, bevel=1.0, corner=0.6, material="Leaf", seam=False, glint=True),
    ]


def oil() -> list[Part]:
    """A dark drop of oil over the slick it makes, a small flame lit at its edge."""
    return [
        ball((8.0, 13.2), 6.8, 2.2, lean=0.5, material="Oil"),
        poly([(8.0, 1.0), (11.4, 6.8), (12.0, 9.6), (10.6, 12.2), (8.0, 12.8), (5.4, 12.2), (4.0, 9.6), (4.6, 6.8)], bevel=1.4, material="Oil", glint=True),
        poly([(13.4, 9.4), (14.6, 12.2), (13.8, 13.4), (12.4, 13.4), (12.0, 12.2)], bevel=0.4, material="Fire", surface="flame"),
    ]


def storm() -> list[Part]:
    """A gold bolt from a dark cloud."""
    return [
        poly(_bolt(0.6, 1.4, 0.82), bevel=0.6, material="Spark", glint=True),
        ball((7.4, 3.4), 5.4, 2.6, material="Stone", surface="speckle"),
    ]


def void() -> list[Part]:
    """A ring of void round a dark hollow, its rim glowing."""
    return [
        ring((8.0, 8.0), 7.0, 3.4, material="Void"),
        ball((8.0, 8.0), 3.4, 3.4, colour=sr.PALETTE["Void"][0]),
        box(5.6, 7.2, 10.4, 8.8, bevel=0.3, colour=OUTLINE),
    ]


def water() -> list[Part]:
    """A drop of water: round below, pointed above, a shine on its left."""
    return [
        poly([(8.0, 0.8), (12.4, 7.6), (13.2, 10.6), (11.4, 14.2), (8.0, 15.2), (4.6, 14.2), (2.8, 10.6), (3.6, 7.6)], bevel=1.6, material="Water", glint=True),
        rod((5.2, 9.0), (5.6, 12.0), 0.5, colour=sr.PALETTE["Water"][2], seam=False),
    ]


# --- a modifier and the sigils --------------------------------------------------------------------


def spill() -> list[Part]:
    """A splash on the floor: a crown of drops thrown up round where it landed."""
    parts: list[Part] = [ball((8.0, 12.6), 6.8, 2.4, lean=0.5, material="Ice", surface="streak")]
    for x, top in ((3.0, 7.0), (5.6, 4.6), (8.0, 3.6), (10.4, 4.6), (13.0, 7.0)):
        parts.append(rod((x, 11.6), (x, top + 1.2), 0.55, material="Ice", seam=False))
        parts.append(ball((x, top), 0.9, 0.9, material="Ice", glint=True))
    return parts


def cast_when_close() -> list[Part]:
    """A watching face in a ring: something near is seen."""
    return [
        ball((8.0, 8.0), 7.2, 7.2, material="Ice", surface="streak"),
        ball((8.0, 8.4), 4.6, 4.2, material="Bone", glint=True),
        ball((6.4, 7.8), 0.9, 1.2, colour=OUTLINE),
        ball((9.6, 7.8), 0.9, 1.2, colour=OUTLINE),
    ]


def cast_when_hurt() -> list[Part]:
    """A heart in a ring: when its bearer is hurt."""
    return [
        ball((8.0, 8.0), 7.2, 7.2, material="Void"),
        ball((6.2, 6.8), 2.4, 2.4, material="Fire", glint=True),
        ball((9.8, 6.8), 2.4, 2.4, material="Fire", seam=False),
        poly([(3.9, 7.6), (12.1, 7.6), (8.0, 12.6)], bevel=0.8, material="Fire", seam=False),
    ]


# --- modifiers ------------------------------------------------------------------------------------
# A shot is a pale bead (`_shot`) unless the card is about something else; Spark marks power.


def _shot(c: tuple[float, float], r: float = 2.0, material: str = "Bone") -> Part:
    return ball(c, r, r, material=material, glint=True)


def _arrow(points: list[tuple[float, float]], material: str = "Bone", bevel: float = 0.6) -> Part:
    return poly(points, bevel=bevel, material=material)


def barrier() -> list[Part]:
    """A ring of ice round a shot: a ward that holds."""
    return [ring((8.0, 8.0), 7.0, 5.0, material="Ice"), _shot((8.0, 8.0), 2.0)]


def bigger() -> list[Part]:
    """A great round shot, swollen, its glow a ring round it."""
    return [ball((8.0, 8.0), 7.0, 7.0, material="Spark", glint=True), ball((6.0, 6.0), 2.4, 2.4, colour=sr.PALETTE["Spark"][2], seam=False)]


def blast() -> list[Part]:
    """A round bomb with its fuse lit."""
    return [
        ball((7.4, 9.6), 5.2, 5.2, material="Stone", glint=True),
        box(6.2, 3.4, 8.6, 5.0, bevel=0.3, material="Stone"),
        rod((8.0, 3.8), (10.2, 2.6), 0.45, material="Wood"),
        ball((11.0, 2.4), 1.1, 1.1, material="Spark", glint=True),
    ]


def bounce() -> list[Part]:
    """A shot leaving a wall it struck: its path bent at the wall."""
    return [
        box(1.0, 1.0, 3.4, 15.0, bevel=0.6, material="Stone", surface="speckle"),
        rod((13.0, 14.0), (4.4, 8.4), 0.5, material="Spark", seam=False),
        rod((4.4, 8.4), (10.4, 3.4), 0.5, material="Spark", seam=False),
        _shot((12.0, 2.8), 2.2),
    ]


def chain() -> list[Part]:
    """Two oval links of a chain, one through the other, turned to the light."""
    return [
        ring((5.4, 9.6), 4.0, 2.2, material="Bone"),
        ring((10.6, 6.4), 4.0, 2.2, material="Bone", glint=True),
        rod((7.6, 11.2), (8.6, 10.6), 0.7, material="Bone", seam=True),
    ]


def charge() -> list[Part]:
    """A gold shot swelling with gathered sparks round it."""
    return [
        _shot((8.0, 9.4), 4.0, "Spark"),
        ball((3.4, 3.6), 0.9, 0.9, material="Spark", glint=True),
        ball((8.0, 1.8), 0.9, 0.9, material="Spark", glint=True),
        ball((12.6, 3.6), 0.9, 0.9, material="Spark", glint=True),
    ]


def deflect() -> list[Part]:
    """A blade turning a dark shot aside."""
    return [
        ball((5.4, 11.0), 3.4, 3.4, material="Stone", glint=True),
        rod((7.0, 9.4), (14.4, 1.6), 1.0, material="Spark", glint=True),
        rod((5.6, 6.0), (10.4, 10.8), 0.7, material="Wood", surface="grain"),
    ]


def echo() -> list[Part]:
    """A shot and its echo beside it, fainter."""
    return [box(1.6, 5.2, 7.2, 10.8, bevel=0.9, corner=1.4, material="Stone"), box(8.8, 5.2, 14.4, 10.8, bevel=0.9, corner=1.4, material="Bone", glint=True)]


def faster() -> list[Part]:
    """Two chevrons pressing right."""
    return [
        _arrow([(2.0, 3.0), (5.0, 3.0), (9.0, 8.0), (5.0, 13.0), (2.0, 13.0), (6.0, 8.0)], "Spark"),
        _arrow([(7.4, 3.0), (10.4, 3.0), (14.4, 8.0), (10.4, 13.0), (7.4, 13.0), (11.4, 8.0)], "Spark"),
    ]


def faster_casting() -> list[Part]:
    """Three chevrons pressing right, one after another, quicker still."""
    return [
        _arrow([(0.8, 2.6), (3.4, 2.6), (6.6, 8.0), (3.4, 13.4), (0.8, 13.4), (4.0, 8.0)], "Spark"),
        _arrow([(5.2, 2.6), (7.8, 2.6), (11.0, 8.0), (7.8, 13.4), (5.2, 13.4), (8.4, 8.0)], "Spark"),
        _arrow([(9.6, 2.6), (12.2, 2.6), (15.2, 8.0), (12.2, 13.4), (9.6, 13.4), (12.8, 8.0)], "Spark"),
    ]


def ghost() -> list[Part]:
    """A shot passing through a wall as if it were not there."""
    return [
        box(7.0, 1.0, 9.0, 15.0, bevel=0.4, material="Stone", surface="speckle"),
        rod((1.6, 8.0), (13.0, 8.0), 0.7, material="Ice", seam=False),
        _shot((12.6, 8.0), 2.4, "Ice"),
    ]


def growth() -> list[Part]:
    """A small shot, then a bigger one: it grows as it flies."""
    return [_shot((3.2, 8.0), 1.3, "Spark"), _shot((10.4, 8.0), 4.2, "Spark")]


def heavy() -> list[Part]:
    """An iron weight with a handle."""
    return [
        poly([(2.6, 14.6), (3.8, 6.4), (12.2, 6.4), (13.4, 14.6)], bevel=1.0, material="Stone", surface="speckle", glint=True),
        ring((8.0, 5.0), 2.8, 1.5, material="Stone"),
    ]


def hold() -> list[Part]:
    """A shot held in a cage of light, waiting."""
    return [
        ball((8.0, 8.0), 5.0, 5.6, material="Ice", glint=True),
        box(1.2, 3.0, 3.0, 13.0, bevel=0.5, material="Spark"),
        box(13.0, 3.0, 14.8, 13.0, bevel=0.5, material="Spark"),
    ]


def homing() -> list[Part]:
    """A shot curving round to its mark."""
    arc = [(8.0 + 5.4 * math.cos(a), 8.0 + 5.4 * math.sin(a)) for a in [math.pi * (0.9 + i * 0.12) for i in range(11)]]
    inner = [(8.0 + 3.8 * math.cos(a), 8.0 + 3.8 * math.sin(a)) for a in [math.pi * (0.9 + i * 0.12) for i in range(11)]][::-1]
    return [
        poly(arc + inner, bevel=0.4, material="Ice", seam=False),
        _shot((3.2, 11.2), 1.8, "Ice"),
        box(10.2, 10.2, 14.0, 14.0, bevel=0.6, material="Fire", glint=True),
    ]


def linger() -> list[Part]:
    """A shot slowing to a stop, its pauses left behind it."""
    return [
        box(1.2, 6.6, 2.6, 9.4, bevel=0.3, material="Stone"),
        box(4.0, 6.0, 5.6, 10.0, bevel=0.3, material="Stone"),
        _shot((10.6, 8.0), 4.0),
    ]


def lumber() -> list[Part]:
    """A heavy log, its end rings showing, rolling slow."""
    return [
        box(3.6, 4.6, 14.6, 11.4, bevel=1.0, corner=1.6, material="Wood", surface="board"),
        ball((3.6, 8.0), 2.4, 3.4, lean=0.6, material="Wood"),
        ring((3.6, 8.0), 1.6, 0.8, material="Wood", seam=False),
    ]


def magnet() -> list[Part]:
    """A horseshoe magnet, its ends bright."""
    arc = [(8.0 + 6.0 * math.cos(a), 8.6 - 6.0 * math.sin(a)) for a in [math.pi * i / 10 for i in range(11)]]
    inner = [(8.0 + 2.8 * math.cos(a), 8.6 - 2.8 * math.sin(a)) for a in [math.pi * i / 10 for i in range(11)]][::-1]
    return [
        poly(arc + [(5.2, 14.6), (2.0, 14.6)][::-1] + inner + [(10.8, 14.6), (14.0, 14.6)], bevel=0.8, material="Fire"),
        box(2.0, 12.0, 5.2, 14.6, bevel=0.4, material="Bone", seam=True),
        box(10.8, 12.0, 14.0, 14.6, bevel=0.4, material="Bone", seam=True),
    ]


def mirror() -> list[Part]:
    """A shot and its mirror image either side of a glass."""
    return [
        box(7.0, 1.0, 9.0, 15.0, bevel=0.5, material="Ice", surface="streak", glint=True),
        box(2.0, 6.2, 5.2, 9.8, bevel=0.6, corner=0.6, material="Bone"),
        box(10.8, 6.2, 14.0, 9.8, bevel=0.6, corner=0.6, material="Stone"),
    ]


def nova() -> list[Part]:
    """A ring bursting out round a bright middle."""
    return [ring((8.0, 8.0), 7.2, 5.4, material="Bone"), ring((8.0, 8.0), 3.8, 2.4, material="Stone"), _shot((8.0, 8.0), 1.4, "Spark")]


def orbit() -> list[Part]:
    """Shots circling a middle."""
    parts: list[Part] = [_shot((8.0, 8.0), 1.6, "Spark")]
    for i in range(6):
        a = math.pi * i / 3.0
        parts.append(_shot((8.0 + 5.6 * math.cos(a), 8.0 + 5.6 * math.sin(a)), 1.2))
    return parts


def overcharge() -> list[Part]:
    """A bolt of power, its spill crackling off it."""
    return [poly(_bolt(-1.0, -0.6, 0.86), bevel=0.6, material="Spark", glint=True), box(11.6, 11.6, 13.4, 13.4, bevel=0.3, material="Fire"), box(13.4, 13.4, 15.0, 15.0, bevel=0.3, material="Fire")]


def penta() -> list[Part]:
    """Five shots round a star."""
    parts: list[Part] = [poly(_star((8.0, 8.0), 3.4, 1.4, 5, -math.pi / 2), bevel=0.4, material="Void", glint=True)]
    for i in range(5):
        a = -math.pi / 2 + 2 * math.pi * i / 5
        parts.append(_shot((8.0 + 6.0 * math.cos(a), 8.0 + 6.0 * math.sin(a)), 1.4, "Void"))
    return parts


def pierce() -> list[Part]:
    """A spear head through a plate."""
    return [
        box(6.4, 2.0, 9.6, 14.0, bevel=0.7, material="Stone", surface="speckle"),
        rod((1.6, 8.0), (11.0, 8.0), 0.9, material="Bone", seam=True),
        _arrow([(10.6, 5.2), (15.2, 8.0), (10.6, 10.8)], "Bone"),
    ]


def plow() -> list[Part]:
    """A plough's blade on its pole, driven through the floor."""
    return [
        rod((1.6, 2.0), (8.0, 8.4), 0.8, material="Wood", surface="grain"),
        poly([(7.0, 6.4), (13.6, 5.0), (14.4, 12.4), (8.4, 14.2)], bevel=1.0, material="Stone", glint=True),
        box(1.0, 13.6, 7.0, 14.6, bevel=0.3, material="Stone", seam=False),
    ]


def point_blank() -> list[Part]:
    """A staff's end bursting at the touch."""
    return [
        rod((1.6, 14.4), (8.6, 7.4), 0.9, material="Wood", surface="grain"),
        poly(_star((10.6, 5.4), 4.6, 1.8, 6), bevel=0.5, material="Spark", glint=True),
    ]


def possess() -> list[Part]:
    """A spirit's face in a ring of void."""
    return [
        ball((8.0, 8.0), 7.2, 7.2, material="Void"),
        ball((8.0, 8.4), 4.0, 4.6, material="Void", glint=True),
        ball((6.6, 7.6), 0.8, 1.1, colour=OUTLINE),
        ball((9.4, 7.6), 0.8, 1.1, colour=OUTLINE),
    ]


def pull() -> list[Part]:
    """An anchor's hook, drawing things in."""
    return [
        ring((8.0, 3.0), 2.2, 1.0, material="Stone"),
        rod((8.0, 5.0), (8.0, 13.0), 0.9, material="Stone"),
        poly([(1.6, 9.6), (3.4, 9.6), (8.0, 13.2), (12.6, 9.6), (14.4, 9.6), (8.0, 15.0)], bevel=0.6, material="Stone", glint=True),
    ]


def quick_hand() -> list[Part]:
    """An hourglass, its sand running fast."""
    return [
        box(3.0, 1.0, 13.0, 2.6, bevel=0.4, material="Wood", surface="grain"),
        box(3.0, 13.4, 13.0, 15.0, bevel=0.4, material="Wood", surface="grain"),
        poly([(4.0, 2.6), (12.0, 2.6), (8.8, 8.0), (12.0, 13.4), (4.0, 13.4), (7.2, 8.0)], bevel=0.8, material="Ice", surface="streak"),
        poly([(5.6, 13.4), (8.0, 10.4), (10.4, 13.4)], bevel=0.3, material="Spark", seam=False),
    ]


def reach() -> list[Part]:
    """A long arrow, far further than a shot goes."""
    return [rod((1.6, 8.0), (11.6, 8.0), 1.0, material="Ice", seam=False), _arrow([(10.6, 4.0), (15.2, 8.0), (10.6, 12.0)], "Ice")]


def recoil() -> list[Part]:
    """A shot leaving one way, a kick back the other."""
    return [_arrow([(1.0, 8.0), (5.4, 4.0), (5.4, 6.6), (9.0, 6.6), (9.0, 9.4), (5.4, 9.4), (5.4, 12.0)], "Spark"), _shot((12.4, 8.0), 2.6, "Ice")]


def relay() -> list[Part]:
    """A shot handing on to an arrow beyond it."""
    return [_shot((4.0, 8.0), 2.8, "Ice"), _arrow([(8.0, 6.8), (11.4, 6.8), (11.4, 4.6), (15.0, 8.0), (11.4, 11.4), (11.4, 9.2), (8.0, 9.2)], "Spark")]


def return_() -> list[Part]:
    """An arc turning back on itself: it comes home."""
    arc = [(8.0 + 6.2 * math.cos(a), 8.0 + 6.2 * math.sin(a)) for a in [math.pi * (0.75 + i * 0.15) for i in range(11)]]
    inner = [(8.0 + 4.2 * math.cos(a), 8.0 + 4.2 * math.sin(a)) for a in [math.pi * (0.75 + i * 0.15) for i in range(11)]][::-1]
    return [poly(arc + inner, bevel=0.6, material="Bone"), _arrow([(1.8, 9.0), (5.6, 13.6), (7.4, 9.6)], "Bone")]


def shield() -> list[Part]:
    """A heater shield, rimmed, its face lit."""
    return [
        poly([(2.0, 2.0), (14.0, 2.0), (14.0, 8.4), (8.0, 15.0), (2.0, 8.4)], bevel=1.2, material="Ice", glint=True),
        poly([(4.6, 4.4), (11.4, 4.4), (11.4, 8.0), (8.0, 11.8), (4.6, 8.0)], bevel=0.4, material="Ice", seam=True),
    ]


def siphon() -> list[Part]:
    """A flask drawing mana up out of a body."""
    return [
        ball((8.0, 11.2), 4.6, 3.8, material="Mana", glint=True),
        box(6.8, 4.6, 9.2, 7.6, bevel=0.4, material="Bone", surface="streak"),
        _arrow([(8.0, 0.8), (11.0, 3.8), (5.0, 3.8)], "Spark"),
    ]


def skyfall() -> list[Part]:
    """A pillar falling from above onto the floor."""
    return [
        box(1.6, 1.0, 14.4, 3.6, bevel=0.6, material="Spark"),
        box(6.4, 3.6, 9.6, 13.0, bevel=0.8, material="Spark", glint=True),
        box(3.0, 13.0, 13.0, 15.0, bevel=0.4, material="Stone", seam=False),
    ]


def slow() -> list[Part]:
    """A snail creeping, its shell a spiral, its trail of slime behind."""
    return [
        poly([(1.2, 14.6), (13.4, 14.6), (15.0, 12.0), (13.4, 11.4), (11.4, 12.8), (2.4, 12.8)], bevel=0.6, material="Ice"),
        rod((13.6, 11.6), (14.6, 8.6), 0.45, material="Ice", seam=False),
        ball((7.2, 8.6), 5.2, 4.8, material="Ice", surface="streak", glint=True),
        ring((7.2, 8.6), 2.6, 1.6, material="Ice", seam=False),
    ]


def sniper() -> list[Part]:
    """A sight's cross on its mark."""
    return [
        ring((8.0, 8.0), 6.8, 5.6, material="Stone"),
        box(7.4, 0.6, 8.6, 15.4, bevel=0.2, material="Stone", seam=False),
        box(0.6, 7.4, 15.4, 8.6, bevel=0.2, material="Stone", seam=False),
        ball((8.0, 8.0), 1.4, 1.4, material="Fire", glint=True),
    ]


def spiral() -> list[Part]:
    """A shot's wavy path."""
    pts = [(1.8 + i * 0.62, 8.0 - 3.0 * math.sin(i * 0.62 * 1.0)) for i in range(21)]
    return [rod(pts[i], pts[i + 1], 0.7, material="Bone", seam=False) for i in range(20)]


def _plus() -> list[Part]:
    """The plus of a card that adds shots, on the left."""
    return [box(1.4, 7.0, 7.6, 9.0, bevel=0.4, material="Spark", seam=False), box(3.5, 4.9, 5.5, 11.1, bevel=0.4, material="Spark", glint=True, seam=False)]


def plus_two() -> list[Part]:
    """A plus and a 2: two more shots."""
    return _plus() + [
        box(9.0, 2.6, 14.6, 4.4, bevel=0.3, material="Bone", seam=False),
        box(12.8, 2.6, 14.6, 8.9, bevel=0.3, material="Bone", seam=False),
        box(9.0, 7.1, 14.6, 8.9, bevel=0.3, material="Bone", seam=False),
        box(9.0, 7.1, 10.8, 13.4, bevel=0.3, material="Bone", seam=False),
        box(9.0, 11.6, 14.6, 13.4, bevel=0.3, material="Bone", glint=True, seam=False),
    ]


def plus_three() -> list[Part]:
    """A plus and a 3: three more shots."""
    return _plus() + [
        box(9.0, 2.6, 14.6, 4.4, bevel=0.3, material="Bone", seam=False),
        box(10.0, 7.1, 14.6, 8.9, bevel=0.3, material="Bone", seam=False),
        box(9.0, 11.6, 14.6, 13.4, bevel=0.3, material="Bone", seam=False),
        box(12.8, 2.6, 14.6, 13.4, bevel=0.3, material="Bone", glint=True, seam=False),
    ]


def sticky() -> list[Part]:
    """A shot stuck to a wall, the wall's face round it."""
    return [
        box(9.4, 1.0, 14.6, 15.0, bevel=0.8, material="Stone", surface="speckle"),
        box(2.0, 6.0, 9.6, 10.0, bevel=0.6, corner=0.8, material="Bone", glint=True),
    ]


def zap() -> list[Part]:
    """A small arc of lightning, crackling."""
    return [poly(_bolt(0.0, 0.0, 0.92), bevel=0.6, material="Arc", glint=True), box(12.6, 11.4, 14.0, 12.8, bevel=0.2, material="Arc")]


# --- multicasts -----------------------------------------------------------------------------------


def burst() -> list[Part]:
    """Three shots in a row, cast at once."""
    return [_shot((3.0, 8.0), 1.8), _shot((8.0, 8.0), 1.8), _shot((13.0, 8.0), 1.8)]


def double() -> list[Part]:
    """Two shots side by side, flying down."""
    return [
        rod((4.6, 1.6), (4.6, 10.0), 0.9, material="Bone", seam=False), _arrow([(2.4, 10.0), (6.8, 10.0), (4.6, 14.8)], "Bone"),
        rod((11.4, 1.6), (11.4, 10.0), 0.9, material="Bone", seam=False), _arrow([(9.2, 10.0), (13.6, 10.0), (11.4, 14.8)], "Bone"),
    ]


def scatter() -> list[Part]:
    """Shots flung every way."""
    return [_shot((3.0, 3.4), 1.6), _shot((12.4, 4.4), 1.6), _shot((6.2, 12.6), 1.6), _shot((12.8, 11.6), 1.4), _shot((8.4, 7.6), 1.3)]


def triple() -> list[Part]:
    """Three shots side by side."""
    parts: list[Part] = []
    for x in (3.0, 8.0, 13.0):
        parts.append(rod((x, 1.6), (x, 11.0), 0.8, material="Bone", seam=False))
        parts.append(_arrow([(x - 1.8, 11.0), (x + 1.8, 11.0), (x, 14.8)], "Bone"))
    return parts


# --- triggers: a shot (white) and the moment it fires on ------------------------------------------


def on_any_cast() -> list[Part]:
    """A spark among shots in every way: any cast."""
    parts: list[Part] = [_shot((8.0, 8.0), 2.0, "Spark")]
    for i in range(8):
        a = math.pi * i / 4.0
        parts.append(_shot((8.0 + 5.8 * math.cos(a), 8.0 + 5.8 * math.sin(a)), 0.9, "Spark"))
    return parts


def on_block() -> list[Part]:
    """A shot meeting a raised shield."""
    return [
        _shot((3.4, 8.0), 2.2),
        poly([(8.2, 2.0), (15.0, 2.0), (15.0, 8.6), (11.6, 14.6), (8.2, 8.6)], bevel=1.0, material="Stone", glint=True),
        poly([(10.2, 4.0), (13.0, 4.0), (13.0, 8.0), (11.6, 11.0), (10.2, 8.0)], bevel=0.3, material="Stone", seam=True),
    ]


def on_cast() -> list[Part]:
    """A shot leaving the staff."""
    return [box(10.2, 5.0, 15.0, 11.0, bevel=0.6, material="Wood", surface="grain"), ball((5.6, 8.0), 4.0, 3.6, material="Bone", glint=True)]


def on_expire() -> list[Part]:
    """A shot at the end of its way, a box drawn round where it stops."""
    return [_shot((3.6, 8.0), 1.4), box(8.2, 4.4, 15.0, 11.6, bevel=0.8, material="Bone"), box(10.2, 6.4, 13.0, 9.6, bevel=0.3, colour=OUTLINE)]


def on_hit() -> list[Part]:
    """A shot striking its mark: a burst where it lands."""
    return [
        rod((1.6, 8.0), (5.6, 8.0), 0.9, material="Bone", seam=False),
        _shot((6.4, 8.0), 2.2),
        poly(_star((11.6, 8.0), 4.0, 1.4, 4, -math.pi / 2), bevel=0.5, material="Spark", glint=True),
    ]


def on_hurt() -> list[Part]:
    """A heart: when its bearer is hurt."""
    return [
        ball((5.2, 6.4), 3.6, 3.6, material="Fire", glint=True),
        ball((10.8, 6.4), 3.6, 3.6, material="Fire", seam=False),
        poly([(1.6, 7.4), (14.4, 7.4), (8.0, 14.6)], bevel=1.0, material="Fire", seam=False),
    ]


def on_kill() -> list[Part]:
    """A skull: when a foe falls."""
    return [
        ball((8.0, 7.0), 5.4, 4.8, material="Bone", surface="pores", glint=True),
        box(5.6, 10.0, 10.4, 13.2, bevel=0.5, material="Bone"),
        ball((5.8, 7.4), 1.2, 1.4, colour=OUTLINE),
        ball((10.2, 7.4), 1.2, 1.4, colour=OUTLINE),
    ]


def on_near() -> list[Part]:
    """A watching face with sense rings out to one side: when something comes near."""
    return [
        ring((8.0, 8.0), 7.4, 6.4, material="Stone"),
        ring((8.0, 8.0), 5.4, 4.6, material="Stone", seam=False),
        ball((6.6, 8.0), 4.0, 4.0, material="Bone", glint=True),
        ball((5.4, 7.4), 0.7, 1.0, colour=OUTLINE),
        ball((7.8, 7.4), 0.7, 1.0, colour=OUTLINE),
    ]


def on_reaction() -> list[Part]:
    """A four-point flare where two elements meet."""
    return [poly(_star((8.0, 8.0), 7.0, 1.8, 4, -math.pi / 2), bevel=0.8, material="Spark", glint=True)]


def on_recast() -> list[Part]:
    """A flame on a stone block: cast again."""
    return [
        box(3.0, 10.0, 13.0, 15.0, bevel=0.8, material="Stone", surface="speckle"),
        poly([(8.0, 2.0), (11.2, 6.8), (10.4, 10.0), (5.6, 10.0), (4.8, 6.8), (6.6, 7.6)], bevel=0.6, material="Fire", surface="flame", seam=False),
    ]


def on_wall() -> list[Part]:
    """A shot about to meet a wall of bricks."""
    parts: list[Part] = [_shot((3.4, 8.0), 2.2)]
    for row, y in enumerate((1.0, 5.0, 9.0, 13.0)):
        x0 = 9.0 if row % 2 == 0 else 10.8
        parts.append(box(x0, y, 15.0, y + 3.0 if y < 13.0 else 15.0, bevel=0.6, material="Stone", surface="speckle", seed=row))
        if row % 2 == 1:
            parts.append(box(9.0, y, 10.6, min(y + 3.0, 15.0), bevel=0.5, material="Stone", seed=row + 4))
    return parts


def timer() -> list[Part]:
    """A clock face, its hands at a quarter."""
    return [
        ball((8.0, 8.0), 7.2, 7.2, material="Bone", glint=True),
        box(7.4, 3.0, 8.6, 8.6, bevel=0.1, colour=OUTLINE),
        box(7.4, 7.4, 12.0, 8.6, bevel=0.1, colour=OUTLINE),
    ]


ICONS: dict[str, tuple[Path, Callable[[], list[Part]]]] = {
    "atom": (SPELLS / "carriers/atom", atom), "beam": (SPELLS / "carriers/beam", beam),
    "bolt": (SPELLS / "carriers/bolt", bolt), "dash": (SPELLS / "carriers/dash", dash),
    "decoy": (SPELLS / "carriers/decoy", decoy), "familiar": (SPELLS / "carriers/familiar", familiar),
    "field": (SPELLS / "carriers/field", field), "pool": (SPELLS / "carriers/pool", pool),
    "portal": (SPELLS / "carriers/portal", portal), "pulse": (SPELLS / "carriers/pulse", pulse),
    "rune": (SPELLS / "carriers/rune", rune), "slam": (SPELLS / "carriers/slam", slam),
    "spray": (SPELLS / "carriers/spray", spray), "swap": (SPELLS / "carriers/swap", swap),
    "swing": (SPELLS / "carriers/swing", swing), "teleport": (SPELLS / "carriers/teleport", teleport),
    "wall": (SPELLS / "carriers/wall", wall),
    "fire": (SPELLS / "elements/fire", fire), "frost": (SPELLS / "elements/frost", frost),
    "lightning": (SPELLS / "elements/lightning", lightning), "mend": (SPELLS / "elements/mend", mend),
    "oil": (SPELLS / "elements/oil", oil), "storm": (SPELLS / "elements/storm", storm),
    "void": (SPELLS / "elements/void", void), "water": (SPELLS / "elements/water", water),
    "spill": (SPELLS / "modifiers/spill", spill),
    "barrier": (SPELLS / "modifiers/barrier", barrier),
    "bigger": (SPELLS / "modifiers/bigger", bigger),
    "blast": (SPELLS / "modifiers/blast", blast),
    "bounce": (SPELLS / "modifiers/bounce", bounce),
    "chain": (SPELLS / "modifiers/chain", chain),
    "charge": (SPELLS / "modifiers/charge", charge),
    "deflect": (SPELLS / "modifiers/deflect", deflect),
    "echo": (SPELLS / "modifiers/echo", echo),
    "faster": (SPELLS / "modifiers/faster", faster),
    "faster_casting": (SPELLS / "modifiers/faster_casting", faster_casting),
    "ghost": (SPELLS / "modifiers/ghost", ghost),
    "growth": (SPELLS / "modifiers/growth", growth),
    "heavy": (SPELLS / "modifiers/heavy", heavy),
    "hold": (SPELLS / "modifiers/hold", hold),
    "homing": (SPELLS / "modifiers/homing", homing),
    "linger": (SPELLS / "modifiers/linger", linger),
    "lumber": (SPELLS / "modifiers/lumber", lumber),
    "magnet": (SPELLS / "modifiers/magnet", magnet),
    "mirror": (SPELLS / "modifiers/mirror", mirror),
    "nova": (SPELLS / "modifiers/nova", nova),
    "orbit": (SPELLS / "modifiers/orbit", orbit),
    "overcharge": (SPELLS / "modifiers/overcharge", overcharge),
    "penta": (SPELLS / "modifiers/penta", penta),
    "pierce": (SPELLS / "modifiers/pierce", pierce),
    "plow": (SPELLS / "modifiers/plow", plow),
    "point_blank": (SPELLS / "modifiers/point_blank", point_blank),
    "possess": (SPELLS / "modifiers/possess", possess),
    "pull": (SPELLS / "modifiers/pull", pull),
    "quick_hand": (SPELLS / "modifiers/quick_hand", quick_hand),
    "reach": (SPELLS / "modifiers/reach", reach),
    "recoil": (SPELLS / "modifiers/recoil", recoil),
    "relay": (SPELLS / "modifiers/relay", relay),
    "return": (SPELLS / "modifiers/return", return_),
    "shield": (SPELLS / "modifiers/shield", shield),
    "siphon": (SPELLS / "modifiers/siphon", siphon),
    "skyfall": (SPELLS / "modifiers/skyfall", skyfall),
    "slow": (SPELLS / "modifiers/slow", slow),
    "sniper": (SPELLS / "modifiers/sniper", sniper),
    "spiral": (SPELLS / "modifiers/spiral", spiral),
    "plus_two": (SPELLS / "modifiers/plus_two", plus_two),
    "plus_three": (SPELLS / "modifiers/plus_three", plus_three),
    "sticky": (SPELLS / "modifiers/sticky", sticky),
    "zap": (SPELLS / "modifiers/zap", zap),
    "burst": (SPELLS / "multicasts/burst", burst),
    "double": (SPELLS / "multicasts/double", double),
    "scatter": (SPELLS / "multicasts/scatter", scatter),
    "triple": (SPELLS / "multicasts/triple", triple),
    "on_any_cast": (SPELLS / "triggers/on_any_cast", on_any_cast),
    "on_block": (SPELLS / "triggers/on_block", on_block),
    "on_cast": (SPELLS / "triggers/on_cast", on_cast),
    "on_expire": (SPELLS / "triggers/on_expire", on_expire),
    "on_hit": (SPELLS / "triggers/on_hit", on_hit),
    "on_hurt": (SPELLS / "triggers/on_hurt", on_hurt),
    "on_kill": (SPELLS / "triggers/on_kill", on_kill),
    "on_near": (SPELLS / "triggers/on_near", on_near),
    "on_reaction": (SPELLS / "triggers/on_reaction", on_reaction),
    "on_recast": (SPELLS / "triggers/on_recast", on_recast),
    "on_wall": (SPELLS / "triggers/on_wall", on_wall),
    "timer": (SPELLS / "triggers/timer", timer),
    "cast_when_close": (SIGILS / "cast_when_close", cast_when_close), "cast_when_hurt": (SIGILS / "cast_when_hurt", cast_when_hurt),
}


## Every icon's 1x `icon.svg` (the HUD's small one, `icon_small`) is drawn here too, from the same parts
## at one art pixel a world unit (`sprite_rules.draw_1x`), so a card looks the same in a small cell and
## a big one (the owner, 2026-11-26: "redraw the small 1x icons from the same parts").


def files() -> dict[Path, Callable[[], Canvas]]:
    out: dict[Path, Callable[[], Canvas]] = {folder / "icon@2x.svg": (lambda p=parts: sr.draw(p(), SIZE, SIZE)) for folder, parts in ICONS.values()}
    for folder, parts in ICONS.values():
        out[folder / "icon.svg"] = lambda p=parts: sr.draw_1x(p(), SIZE, SIZE)
    return out


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="write nothing; fail when a file differs")
    parser.add_argument("names", nargs="*", help="only these (a card's or a sigil's folder name)")
    args = parser.parse_args(argv)
    every = files()
    unknown = [n for n in args.names if n not in ICONS]
    if unknown:
        parser.error(f"no such icon: {', '.join(unknown)}")
    status = 0
    for path, draw in every.items():
        if args.names and path.parent.name not in args.names:
            continue
        data = draw().svg().encode("utf-8")
        if args.check:
            if not path.exists() or path.read_bytes() != data:
                print(f"{path.relative_to(ROOT)} differs from what tools/icon_art.py draws", file=sys.stderr)
                status = 1
        else:
            path.write_bytes(data)
    return status


if __name__ == "__main__":
    sys.exit(main())
