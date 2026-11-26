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
    """A tiny bright speck flying up and right, a thin trail behind it."""
    return [
        rod((2.0, 10.5), (10.0, 7.2), 0.55, 0.9, material="Bone", seam=False),
        ball((11.8, 6.5), 1.9, 1.9, material="Spark", glint=True),
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
    """A round little spirit with two eyes, a wisp of tail under it."""
    return [
        poly([(6.2, 12.0), (9.8, 12.0), (8.6, 15.2), (7.6, 13.8)], bevel=0.5, material="Bone"),
        ball((8.0, 8.0), 5.8, 5.2, material="Bone", glint=True),
        ball((6.0, 7.4), 0.8, 1.2, colour=OUTLINE),
        ball((10.0, 7.4), 0.8, 1.2, colour=OUTLINE),
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
        rod((8.0, 1.2), (8.0, 8.0), 0.9, material="Wood", surface="grain"),
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
    "cast_when_close": (SIGILS / "cast_when_close", cast_when_close), "cast_when_hurt": (SIGILS / "cast_when_hurt", cast_when_hurt),
}


## The icons whose 1x `icon.svg` (the HUD's small one, `icon_small`) is drawn here too, from the same
## parts at one art pixel a world unit: cards made after the 1x icons were drawn by hand.
SMALL_TOO: tuple[str, ...] = ("oil", "spill")


def _small(parts: Callable[[], list[Part]]) -> Canvas:
    """`parts` drawn at 1x (16 x 16): sprite_rules' detail set to 1 for the one drawing."""
    detail = sr.DETAIL
    sr.DETAIL = 1
    try:
        return sr.draw(parts(), SIZE, SIZE)
    finally:
        sr.DETAIL = detail


def files() -> dict[Path, Callable[[], Canvas]]:
    out: dict[Path, Callable[[], Canvas]] = {folder / "icon@2x.svg": (lambda p=parts: sr.draw(p(), SIZE, SIZE)) for folder, parts in ICONS.values()}
    for name in SMALL_TOO:
        folder, parts = ICONS[name]
        out[folder / "icon.svg"] = lambda p=parts: _small(p)
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
