#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
# SPDX-License-Identifier: GPL-3.0-or-later
"""The pickups drawn at 2x detail from their own shapes (ART2; the owner, 2026-11-26: real new
detail, hand-drawn per sprite): the coin, the key, the potions and the reward reroll's card.

Each icon below is its parts in world units on its 1x art's 16 x 16 grid (so it keeps its
silhouette and its size), drawn by tools/sprite_rules.py at 32 x 32 art pixels: lit from the
top-left in three shades a material, gold rounded and glinting, glass a ball of its liquid with a
streaked shine, a cork's grain, seams between the parts and a one-art-pixel outline.

    tools/pickup_art.py           # writes every icon
    tools/pickup_art.py --check   # fails when a file differs from what the rules draw
    tools/pickup_art.py coin      # only these (a pickup's folder name)
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Callable

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sprite_rules as sr  # noqa: E402
from sprite_rules import Part, ball, box, poly, ring  # noqa: E402
from staff_art import Canvas  # noqa: E402

ROOT = sr.ROOT
SIZE = 16


def coin() -> list[Part]:
    """A gold coin seen face on: a raised rim, a sunk ring and a boss in its middle."""
    return [
        ball((8.0, 8.0), 6.6, 6.6, lean=0.45, material="Spark", glint=True),
        ring((8.0, 8.0), 6.6, 5.2, material="Spark", seam=False),
        ring((8.0, 8.0), 3.4, 2.2, material="Spark"),
        ball((8.0, 8.0), 1.2, 1.2, lean=1.0, material="Spark", seam=False, glint=True),
    ]


def key() -> list[Part]:
    """A gold key lying right: a round bow with its hole, a shaft and two teeth."""
    return [
        box(7.0, 6.9, 15.2, 9.1, bevel=0.6, material="Spark"),
        box(11.4, 8.6, 12.8, 11.4, bevel=0.5, material="Spark", seam=False),
        box(13.6, 8.6, 15.2, 12.4, bevel=0.5, material="Spark", seam=False),
        ring((4.9, 8.0), 3.6, 1.5, material="Spark", glint=True),
    ]


def _flask(body: list[Part], neck: tuple[float, float, float, float], cork: tuple[float, float, float, float]) -> list[Part]:
    """A glass flask: its neck pale glass, its cork, then its body of `liquid` with a shine."""
    nx0, ny0, nx1, ny1 = neck
    cx0, cy0, cx1, cy1 = cork
    return [
        box(nx0, ny0, nx1, ny1, bevel=0.5, material="Bone", surface="streak"),
        box(cx0, cy0, cx1, cy1, bevel=0.5, corner=0.3, material="Wood", surface="grain"),
        *body,
    ]


def _shine(cx: float, cy: float, liquid: str) -> Part:
    """The glass's shine on the upper left of a round body: a short curved streak."""
    return poly([(cx - 0.4, cy - 0.3), (cx + 0.9, cy - 1.6), (cx + 1.6, cy - 1.3), (cx + 0.3, cy + 0.2)], bevel=0.2, material=liquid, colour=sr.PALETTE["Bone"][2], seam=False)


def healing() -> list[Part]:
    return _flask([ball((8.0, 10.4), 4.9, 4.4, material="Fire", glint=True), _shine(5.6, 9.6, "Fire")], (6.6, 4.0, 9.4, 6.6), (6.2, 2.2, 9.8, 4.2))


def large_healing() -> list[Part]:
    return _flask([ball((8.0, 9.9), 6.2, 5.4, material="Fire", glint=True), _shine(4.8, 8.6, "Fire")], (6.4, 2.6, 9.6, 5.0), (6.1, 0.8, 9.9, 2.8))


def max_health() -> list[Part]:
    """The large flask with a bone cross on its glass."""
    return large_healing() + [
        box(7.0, 7.4, 9.0, 13.2, bevel=0.4, material="Bone", seam=True),
        box(5.1, 9.3, 10.9, 11.3, bevel=0.4, material="Bone", seam=True),
    ]


def small_healing() -> list[Part]:
    """A little upright vial."""
    return _flask([box(6.2, 7.4, 9.8, 13.6, bevel=0.7, corner=1.1, material="Fire", glint=True)], (6.9, 5.8, 9.1, 7.6), (6.6, 4.2, 9.4, 6.0))


def vigor() -> list[Part]:
    return _flask([ball((8.0, 10.4), 5.2, 4.7, material="Arc", glint=True), _shine(5.4, 9.4, "Arc")], (6.6, 3.8, 9.4, 6.4), (6.2, 2.0, 9.8, 4.0))


def reward_reroll() -> list[Part]:
    """A face-down card with a four-point star, and a turning arrow over its corner."""
    star = [(7.0, 4.6), (7.9, 7.1), (10.3, 8.0), (7.9, 8.9), (7.0, 11.4), (6.1, 8.9), (3.7, 8.0), (6.1, 7.1)]
    return [
        box(2.2, 1.2, 11.8, 14.8, bevel=0.8, corner=0.8, material="Void"),
        poly(star, bevel=0.6, material="Void", colour=sr.PALETTE["Void"][0]),
        ring((11.9, 11.9), 3.3, 1.9, material="Void"),
        poly([(13.4, 7.4), (15.4, 9.3), (12.4, 10.0)], bevel=0.4, material="Void", seam=False),
    ]


def files() -> dict[Path, Callable[[], Canvas]]:
    every: dict[str, tuple[str, Callable[[], list[Part]]]] = {
        "coin": ("content/coins/coin", coin),
        "key": ("content/keys/key", key),
        "healing": ("content/potions/healing", healing),
        "large_healing": ("content/potions/large_healing", large_healing),
        "max_health": ("content/potions/max_health", max_health),
        "small_healing": ("content/potions/small_healing", small_healing),
        "vigor": ("content/potions/vigor", vigor),
        "reward_reroll": ("content/rerolls/reward_reroll", reward_reroll),
    }
    return {ROOT / folder / "icon@2x.svg": (lambda p=parts: sr.draw(p(), SIZE, SIZE)) for folder, parts in every.values()}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="write nothing; fail when a file differs")
    parser.add_argument("names", nargs="*", help="only these (a pickup's folder name)")
    args = parser.parse_args(argv)
    every = files()
    known = {path.parent.name for path in every}
    unknown = [n for n in args.names if n not in known]
    if unknown:
        parser.error(f"no such pickup: {', '.join(unknown)}")
    status = 0
    for path, draw in every.items():
        if args.names and path.parent.name not in args.names:
            continue
        data = draw().svg().encode("utf-8")
        if args.check:
            if not path.exists() or path.read_bytes() != data:
                print(f"{path.relative_to(ROOT)} differs from what tools/pickup_art.py draws", file=sys.stderr)
                status = 1
        else:
            path.write_bytes(data)
            print(f"wrote {path.relative_to(ROOT)}")
    return status


if __name__ == "__main__":
    sys.exit(main())
