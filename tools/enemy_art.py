#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
# SPDX-License-Identifier: GPL-3.0-or-later
"""The enemies and the Old Broom drawn at 2x detail from their own shapes (ART1; the owner,
2026-11-26: "hand-redraw first", each by shape and light rules of its own, as the staff heads).

Each sprite below is its parts in world units on its 1x art's grid (so it keeps its silhouette,
its size and its frames), drawn by tools/sprite_rules.py: lit from the top-left in three shades a
material, with its material's surface (wood grain along each piece, bone pores and cracks, a
leaf's vein, a flame's core, ice streaks, gold and glass glints), seams between its parts and a
one-art-pixel outline.

    tools/enemy_art.py           # writes every sprite
    tools/enemy_art.py --check   # fails when a file differs from what the rules draw
    tools/enemy_art.py ember_imp # only these (an enemy's folder name, or old_broom)
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path
from typing import Callable

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sprite_rules as sr  # noqa: E402
from sprite_rules import OUTLINE, PALETTE, Hit, Part, ball, box, mask, poly, ring, rod  # noqa: E402
from staff_art import Canvas  # noqa: E402

ROOT = sr.ROOT
ENEMIES = ROOT / "content/enemies"


def _mirror(points: list[tuple[float, float]], axis: float) -> list[tuple[float, float]]:
    return [(2.0 * axis - x, y) for x, y in points]


def _pedestal() -> list[Part]:
    """A dummy's stone foot: a low slab, wider at the floor."""
    return [
        poly([(11.6, 26.4), (21.4, 26.4), (24.6, 29.0), (24.6, 30.5), (8.4, 30.5), (8.4, 29.0)], material="Stone", surface="speckle", bevel=0.7),
    ]


# --- the strays ---------------------------------------------------------------------------------


def ember_imp() -> list[Part]:
    """The Cinder Rod: a charred rod, a knot at its top under a crown of fire, an ember band, a
    bone ferrule."""
    flames = []
    for base_x, tip, w, seed in ((12.8, (12.0, 1.4), 1.3, 1), (16.5, (16.5, -0.4), 1.6, 2), (20.2, (21.0, 1.4), 1.3, 3), (14.6, (14.2, 2.6), 1.0, 4), (18.4, (18.9, 2.6), 1.0, 5)):
        flames.append(poly([(base_x - w, 4.2), (tip[0], tip[1]), (base_x + w, 4.2)], material="Fire", surface="flame", bevel=0.5, seam=False, seed=seed))
    return [
        rod((16.5, 9.5), (16.5, 26.0), 2.0, material="Wood", surface="grain", seed=1),
        ball((16.5, 8.0), 3.4, 2.9, material="Wood", surface="grain", cracks=[[(14.6, 7.0), (15.6, 8.4), (15.2, 9.6)]]),
        box(12.4, 3.4, 20.6, 6.4, corner=1.0, material="Fire", surface="flame", seam=False),
        *flames,
        box(14.4, 19.6, 18.6, 21.4, corner=0.4, material="Fire", glint=True),
        poly([(14.5, 25.6), (18.5, 25.6), (17.4, 28.2), (16.5, 29.6), (15.6, 28.2)], material="Bone", surface="pores", glint=True),
    ]


def splinter() -> list[Part]:
    """The Splinter: a split shard of wood, two prongs at its top, two snapped twigs."""
    return [
        rod((16.6, 17.6), (16.5, 28.0), 1.9, 1.1, material="Wood", surface="grain", seed=2),
        rod((15.6, 18.0), (15.3, 14.4), 0.8, 0.35, material="Wood", surface="grain"),
        rod((17.6, 18.0), (17.7, 13.4), 0.8, 0.35, material="Wood", surface="grain"),
        rod((15.2, 21.6), (12.9, 22.7), 0.75, 0.35, material="Wood"),
        rod((18.0, 19.0), (20.0, 19.6), 0.75, 0.35, material="Wood"),
    ]


def storm_fork() -> list[Part]:
    """The Storm Fork: a trident, its three tines tipped with lightning, a spike of it below."""
    parts: list[Part] = [
        rod((16.5, 10.0), (16.5, 25.6), 2.0, material="Wood", surface="grain", seed=3),
        box(10.4, 8.6, 22.6, 11.0, corner=0.8, material="Wood", surface="board"),
    ]
    for x0, x1, top in ((10.5, 13.5, 3.6), (14.5, 18.5, 2.8), (19.5, 22.5, 3.6)):
        parts.append(box(x0, top, x1, 10.0, corner=0.6, material="Wood", surface="grain"))
    for cx, top, w in ((11.75, 0.6, 1.4), (16.5, -0.6, 1.7), (21.25, 0.6, 1.4)):
        parts.append(poly([(cx - w, 4.2), (cx - 0.3, top + 1.6), (cx, top), (cx + 0.4, top + 1.4), (cx + w, 4.2)], material="Arc", surface="streak", glint=True, seam=False))
    parts.append(poly([(14.4, 25.4), (18.6, 25.4), (17.2, 27.4), (16.5, 29.6), (15.8, 27.4)], material="Arc", surface="streak", glint=True))
    return parts


def rime_crook() -> list[Part]:
    """The Rime Crook: a shepherd's crook over a wooden block, icicles in its hook, ice bands."""
    return [
        box(13.4, 3.4, 18.6, 12.4, corner=1.0, material="Wood", surface="grain", seed=4),
        box(13.4, 3.4, 25.6, 6.4, corner=1.6, material="Wood", surface="board"),
        box(21.4, 3.4, 25.6, 10.6, corner=1.0, material="Wood", surface="grain", seed=5),
        poly([(19.2, 6.2), (21.4, 6.2), (20.4, 8.8)], material="Ice", surface="streak", glint=True),
        poly([(21.6, 10.2), (25.4, 10.2), (24.0, 12.2), (23.4, 13.0), (22.6, 12.0)], material="Ice", surface="streak", glint=True),
        box(9.4, 12.4, 22.6, 20.6, corner=0.8, material="Wood", surface="board", seed=6),
        poly([(9.4, 11.4), (23.6, 11.4), (23.2, 13.2), (22.0, 14.4), (20.8, 13.2), (9.4, 13.2)], material="Ice", surface="streak", glint=True),
        box(13.4, 20.2, 18.6, 22.0, material="Wood", surface="grain"),
        box(12.4, 21.6, 19.6, 23.6, corner=0.6, material="Ice", surface="streak", glint=True),
        box(13.4, 23.4, 18.6, 26.8, corner=1.2, material="Wood", surface="grain", seed=7),
        poly([(14.4, 26.6), (17.6, 26.6), (16.8, 28.4), (16.0, 29.4), (15.2, 28.4)], material="Ice", surface="streak", glint=True),
    ]


def bone_scepter() -> list[Part]:
    """The Bone Scepter: a round skull of bone with a window of void, a row of teeth, a shaft with
    void bands."""
    parts: list[Part] = [
        rod((16.5, 17.5), (16.5, 26.8), 2.0, material="Wood", surface="grain", seed=8),
        ball((16.5, 9.2), 9.0, 7.4, lean=0.6, material="Bone", surface="pores", cracks=[[(21.6, 3.8), (22.4, 5.2)]]),
        poly([(8.8, 12.0), (24.2, 12.0), (23.0, 15.4), (20.6, 16.8), (12.4, 16.8), (10.0, 15.4)], material="Bone", surface="pores", seam=False),
        box(9.6, 7.6, 23.4, 13.4, corner=0.8, material="Void", colour=PALETTE["Void"][0]),
    ]
    for x in (12.0, 14.0, 16.0, 18.0, 20.0):
        parts.append(box(x - 0.1, 16.4, x + 1.1, 18.0, corner=0.3, material="Bone"))
    parts.append(box(13.4, 19.4, 19.6, 21.6, corner=0.6, material="Void", glint=True))
    parts.append(poly([(14.4, 26.4), (18.6, 26.4), (18.2, 28.2), (16.5, 29.4), (14.8, 28.2)], material="Void", glint=True))
    return parts


def spitter() -> list[Part]:
    """The Spitter: a hooded leafy head with a pale face and a forked spit, its stalk wound with
    leaves."""
    leaf = dict(material="Leaf", surface="vein")
    return [
        rod((16.4, 14.0), (16.4, 28.4), 1.6, 1.1, material="Wood", surface="grain", seed=9),
        rod((14.4, 25.6), (18.6, 26.2), 0.8, material="Wood"),
        rod((15.0, 27.9), (18.0, 28.5), 0.7, material="Wood"),
        rod((21.8, 15.4), (10.4, 18.4), 1.3, 0.8, **leaf),  # type: ignore[arg-type]
        rod((21.6, 21.6), (10.4, 23.8), 1.3, 0.8, **leaf),  # type: ignore[arg-type]
        rod((14.8, 13.0), (16.6, 15.4), 1.1, material="Skin"),
        poly([(11.6, 8.6), (20.6, 8.6), (20.6, 10.6), (16.0, 11.4), (15.6, 14.4), (13.0, 14.4), (12.0, 11.4)], material="Skin", bevel=0.7),
        poly([(9.4, 9.0), (9.6, 5.4), (11.2, 3.6), (14.6, 3.4), (20.8, 3.6), (22.4, 5.0), (23.4, 7.4), (21.4, 8.4), (12.6, 8.6), (11.2, 10.6)], material="Leaf", surface="vein", bevel=0.8),
        box(12.4, 7.6, 21.6, 8.9, material="Leaf", colour=OUTLINE, seam=False),
        box(15.6, 7.8, 16.6, 8.8, material="Bone", seam=False),
        box(19.6, 7.8, 20.6, 8.8, material="Bone", seam=False),
        rod((21.4, 8.2), (25.0, 8.2), 0.6, material="Fire", glint=True),
        rod((24.6, 8.0), (25.8, 7.0), 0.4, material="Fire"),
        rod((24.6, 8.4), (25.8, 9.4), 0.4, material="Fire"),
    ]


# --- the swarmers -------------------------------------------------------------------------------


def crypt_mite() -> list[Part]:
    """The Crypt Mite: a round wooden beetle, its shell split down the middle, six thin legs and a
    bone sting."""
    legs: list[Part] = []
    for start, end in (((11.8, 18.8), (10.4, 17.4)), ((11.0, 21.4), (8.8, 20.4)), ((11.2, 24.0), (9.0, 23.4))):
        for a, b in ((start, end), (_mirror([start], 16.0)[0], _mirror([end], 16.0)[0])):
            legs.append(rod(a, b, 0.3, colour=OUTLINE, seam=False))
    shell = dict(material="Wood", surface="grain")
    return [
        *legs,
        poly([(13.2, 24.4), (18.8, 24.4), (17.2, 27.6), (14.8, 27.6)], material="Wood", surface="grain", bevel=0.7),
        ball((16.0, 21.2), 5.6, 4.8, lean=0.7, **shell),  # type: ignore[arg-type]
        rod((16.0, 17.0), (16.0, 25.6), 0.35, colour=OUTLINE, seam=False),
        box(14.6, 27.4, 17.4, 28.9, corner=0.5, material="Bone", glint=True),
    ]


def bone_husk() -> list[Part]:
    """The Bone Husk: a knuckled bone with a dark socket, a wooden band round its neck, a knuckle
    below, a gold tip."""
    bone = dict(material="Bone", surface="pores")
    return [
        box(14.6, 27.4, 18.4, 29.0, corner=0.5, material="Spark", glint=True),
        ball((13.8, 25.6), 2.4, 2.2, **bone),  # type: ignore[arg-type]
        ball((19.2, 25.6), 2.4, 2.2, **bone),  # type: ignore[arg-type]
        ball((16.5, 25.2), 3.6, 2.4, seam=False, **bone),  # type: ignore[arg-type]
        rod((16.5, 15.0), (16.5, 24.0), 2.6, cracks=[[(15.6, 22.0), (16.4, 23.0), (16.0, 24.0)], [(16.4, 17.6), (16.0, 18.6)]], **bone),  # type: ignore[arg-type]
        box(12.4, 18.6, 20.6, 20.6, corner=0.5, material="Wood", surface="board"),
        ball((12.6, 6.6), 3.6, 2.6, **bone),  # type: ignore[arg-type]
        ball((20.4, 6.6), 3.6, 2.6, **bone),  # type: ignore[arg-type]
        poly([(8.6, 7.0), (24.4, 7.0), (24.4, 13.0), (22.0, 15.6), (11.0, 15.6), (8.6, 13.0)], seam=False, **bone),  # type: ignore[arg-type]
        box(10.6, 8.6, 22.4, 13.6, corner=1.0, material="Bone", colour=OUTLINE, seam=False),
    ]


# --- the dummies --------------------------------------------------------------------------------


def shooting_dummy() -> list[Part]:
    """The shooting dummy: a stone eye on a post, a gold band, a stone foot."""
    return [
        *_pedestal(),
        rod((16.5, 10.0), (16.5, 27.0), 2.0, material="Wood", surface="grain", seed=10),
        box(14.4, 13.4, 18.6, 15.0, corner=0.4, material="Spark", glint=True),
        ball((16.5, 7.0), 4.9, 4.0, lean=0.7, material="Stone", surface="speckle"),
        ring((16.5, 7.0), 3.4, 2.4, material="Stone"),
        ball((16.8, 7.0), 2.2, 1.9, material="Spark", glint=True),
        ball((17.0, 7.2), 0.8, 0.8, material="Spark", colour=OUTLINE, seam=False),
    ]


def training_dummy() -> list[Part]:
    """The training dummy: a post with a crossbar and a painted target, a stone foot."""
    return [
        *_pedestal(),
        rod((16.5, 5.8), (16.5, 27.0), 2.0, material="Wood", surface="grain", seed=11),
        box(8.4, 8.4, 24.6, 11.0, corner=0.8, material="Wood", surface="board", seed=17),
        ball((16.5, 16.0), 5.4, 4.8, lean=0.5, material="Bone", surface="pores"),
        ring((16.5, 16.0), 3.6, 2.4, material="Fire"),
        ball((16.5, 16.0), 1.4, 1.3, material="Spark", glint=True),
    ]


# --- the Old Broom -----------------------------------------------------------------------------

BROOM = ROOT / "content/bosses/old_broom"


def _silhouettes() -> dict[str, list]:
    return json.loads((BROOM / "silhouettes.json").read_text(encoding="utf-8"))


def broom_handle() -> list[Part]:
    """Its handle (16x40): a stone hanging fork at its top, a wooden pole with grain, a bone cord
    wound round it."""
    return [
        rod((8.0, 5.0), (8.0, 41.0), 2.5, material="Wood", surface="grain", seed=12, cracks=[[(7.4, 22.0), (7.8, 24.6)], [(8.6, 30.0), (8.4, 32.0)]]),
        box(4.6, 11.6, 11.4, 15.4, corner=1.0, material="Bone", surface="wrap"),
        rod((4.5, 4.0), (4.5, 1.7), 0.95, 0.75, material="Stone"),
        rod((11.5, 4.0), (11.5, 1.7), 0.95, 0.75, material="Stone"),
        box(3.6, 2.6, 12.4, 5.6, corner=1.6, material="Stone", surface="speckle", seam=False),
    ]


def broom_binding() -> list[Part]:
    """Its binding (40x16): a wooden plate held by two bone bands with rivets, a scratch on it."""
    return [
        box(1.6, 2.4, 38.4, 10.4, corner=0.4, material="Wood", surface="board", cracks=[[(34.4, 4.2), (35.4, 6.2), (35.0, 8.4)]], seed=13),
        box(2.4, 0.6, 37.6, 3.0, corner=0.9, material="Bone", surface="rivets"),
        box(1.6, 9.8, 38.4, 13.0, corner=1.0, material="Bone", surface="rivets"),
    ]


def _bristles(rows: list[list[list[int]]], seed: int, ox: float = 0.0, oy: float = 0.0) -> Part:
    """Straw in `rows`: strands fanning from above its own top middle, so in every frame of a
    strip a strand keeps its shade and moves with its frame's shape."""
    top = next((row for row in rows if row), [[0, 1]])
    middle = (top[0][0] + top[-1][1]) / 2.0
    return mask(rows, ox, oy, apex=(middle, -40.0), material="Spark", surface="strands", seed=seed)


def _lines(rows: list[list[list[int]]]) -> Part:
    """The splits between its tufts, kept from the 1x art: dark lines."""
    return mask(rows, inset=False, colour=OUTLINE, seam=False)


def _minus(rows: list[list[list[int]]], cut: list[list[list[int]]]) -> list[list[list[int]]]:
    """The runs of `rows` not in `cut`, row by row."""
    out: list[list[list[int]]] = []
    for y, row in enumerate(rows):
        covered = {x for a, b in (cut[y] if y < len(cut) else []) for x in range(a, b)}
        runs: list[list[int]] = []
        for a, b in row:
            x = a
            while x < b:
                if x in covered:
                    x += 1
                    continue
                s = x
                while x < b and x not in covered:
                    x += 1
                runs.append([s, x])
        out.append(runs)
    return out


def _burning(straw: Part, line: float) -> Part:
    """The straw's tips below a wavering line, glowing: the burning straw's hottest, in Spark."""

    def test(x: float, y: float) -> Hit | None:
        if y < line + 2.2 * math.sin(x * 0.55) + 1.4 * math.sin(x * 1.7):
            return None
        return straw.test(x, y)

    return Part(test, material="Spark", surface="strands", seed=straw.seed, seam=False)


def broom_head(frame: int, burning: bool = False) -> list[Part]:
    """One frame of its bristle head (88x32): straw in strands fanning down from the binding, in
    its 1x silhouette; burning, the straw aflame, its tips glowing, flames licking up at its edges."""
    shapes = _silhouettes()
    plain = shapes["head"][frame]
    straw = _bristles(plain, 20)
    lines = _lines(shapes["head_lines"][frame])
    if not burning:
        return [straw, lines]
    # Its flames, one world unit in from the frame's edges so the outline round them fits.
    flames = [[[max(a, 1), min(b, 87)] for a, b in row if min(b, 87) > max(a, 1)] if 1 <= y <= 30 else [] for y, row in enumerate(_minus(shapes["head_burning"][frame], plain))]
    fire = _bristles(plain, 20)
    fire.material = "Fire"
    return [fire, _burning(straw, 23.0), lines, mask(flames, inset=False, material="Fire", surface="flame", seam=False)]


def _eye(look: tuple[int, int], cx: float, inner: float, angry: bool, shut: bool) -> list[Part]:
    """One heavy-lidded eye, 7x6 world units round `cx` (`inner`: +1 its inner side is right)."""
    x0, x1 = cx - 3.5, cx + 3.5
    # The white pale (Bone light, for the game to tint), shaded at its bottom-right rim.
    parts: list[Part] = [box(x0, 0.5, x1, 6.5, corner=1.6, bevel=0.8, material="Bone"), box(x0 + 0.6, 0.5, x1 - 0.9, 5.7, corner=1.2, material="Bone", colour=PALETTE["Bone"][2], seam=False)]
    if shut:
        parts.append(box(x0, 0.5, x1, 6.5, corner=1.6, material="Bone", colour=PALETTE["Bone"][0]))
        parts.append(rod((x0 + 0.8, 4.4), (x1 - 0.8, 4.4), 0.35, colour=OUTLINE, seam=False))
        return parts
    px, py = cx + look[0] * 1.3, 4.1 + look[1] * 0.7
    parts.append(ball((px, py), 1.25, 1.25, colour=OUTLINE, seam=False))
    parts.append(box(px - 0.6, py - 0.75, px - 0.1, py - 0.25, colour=PALETTE["Bone"][2], seam=False))
    low, high = (3.4, 1.9) if angry else (2.4, 2.4)
    inner_y, outer_y = (low, high) if angry else (low, low)
    left_y, right_y = (outer_y, inner_y) if inner > 0 else (inner_y, outer_y)
    parts.append(poly([(x0, 0.5), (x1, 0.5), (x1, right_y), (x0, left_y)], material="Bone", colour=PALETTE["Bone"][0], seam=True))
    return parts


def broom_eyes() -> Canvas:
    """Its own eyes (a FaceArt sheet, 24x8 world units a frame): ten columns (nine looks, then the
    blink) and two rows (its own, then phase 2's angrier lids)."""
    sheet = Canvas(48 * 10, 16 * 2)
    for row in range(2):
        for column in range(10):
            look = (column % 3 - 1, column // 3 - 1)
            parts = _eye(look, 5.0, 1.0, row == 1, column == 9) + _eye(look, 17.0, -1.0, row == 1, column == 9)
            sheet.blit(sr.draw(parts, 24, 8), column * 48, row * 16)
    return sheet


# A brow's top at its outer and inner ends, and how high it arches, a mood each (Face.Mood):
# neutral, raised (high and arched), angry (down to the middle), furious (more), worried (up).
BROW_MOODS = ((2.4, 2.2, 0.4), (0.9, 1.0, 1.0), (1.2, 3.4, 0.0), (0.8, 4.2, 0.0), (3.6, 1.2, 0.3))
# How thick a brow is at its outer and its inner end: bushy toward the middle of the face.
BROW_THICK = (1.6, 3.0)


def _brow(outer: float, inner: float, arch: float, material: str, mirror: bool) -> list[Part]:
    """A bushy brow from x 0.6 (outer) to 9.4 (inner), tapering from its inner end, its top edge
    ragged with three tufts, its hair in strokes along it."""
    def top(x: float) -> float:
        t = (x - 0.6) / 8.8
        # Below the frame's top row, so the outline round it fits.
        return max(0.6, outer + (inner - outer) * t - arch * math.sin(t * math.pi))

    xs = [0.6 + 8.8 * i / 8.0 for i in range(9)]
    points = [(x, top(x)) for x in xs]
    under = [(x, top(x) + BROW_THICK[0] + (BROW_THICK[1] - BROW_THICK[0]) * (x - 0.6) / 8.8) for x in reversed(xs)]
    shape = points + under
    tufts = []
    for x in (2.6, 5.2, 7.8):
        y = top(x)
        # A tuft stops short of the frame's top, so the outline round it fits.
        tufts.append([(x - 0.9, y + 0.5), (x + 0.5, max(y - 0.9, 0.6)), (x + 1.0, y + 0.5)])
    if mirror:
        shape = _mirror(shape, 10.5)
        tufts = [_mirror(tuft, 10.5) for tuft in tufts]
    hair = dict(material=material)
    return [poly(shape, bevel=0.5, **hair)] + [poly(tuft, bevel=0.4, seam=False, **hair) for tuft in tufts]  # type: ignore[arg-type]


def broom_brows() -> Canvas:
    """Its own brows (24x8 a frame): a column a mood, bushy, in Bone, and phase 2's row in Fire."""
    sheet = Canvas(48 * 5, 16 * 2)
    for row, material in enumerate(("Bone", "Fire")):
        for mood, (outer, inner, arch) in enumerate(BROW_MOODS):
            parts = _brow(outer, inner, arch, material, False) + _brow(outer, inner, arch, material, True)
            sheet.blit(sr.draw(parts, 24, 8), mood * 48, row * 16)
    return sheet


def _binding_face(top: float, angry: bool) -> list[Part]:
    """The portrait's binding (x 23.4 to 72.6 from `top`, 27 tall) and its face."""
    bottom = top + 27.0
    parts: list[Part] = [
        box(23.4, top + 3.0, 72.6, bottom - 3.0, corner=0.6, material="Wood", surface="board", seed=14),
        box(24.4, top, 71.6, top + 3.6, corner=1.2, material="Bone", surface="rivets"),
        box(23.4, bottom - 3.6, 72.6, bottom, corner=1.2, material="Bone", surface="rivets"),
    ]
    for mirror in (False, True):
        side: list[Part] = []
        if angry:
            brow = [(29.6, top + 5.6), (31.0, top + 5.6), (36.0, top + 7.6), (42.4, top + 10.4), (42.4, top + 13.0), (35.6, top + 13.0), (32.4, top + 11.0), (29.6, top + 7.4)]
            lid = box(33.6, top + 13.6, 42.4, top + 15.6, corner=0.6, material="Wood")
            white = box(32.6, top + 15.6, 43.4, top + 20.4, corner=1.2, material="Bone")
            pupil = box(37.6, top + 16.4, 40.8, top + 20.4, corner=0.8, material="Fire", glint=True)
            side = [white, pupil, lid]
        else:
            brow = [(30.6, top + 8.2), (33.6, top + 7.0), (39.6, top + 6.0), (43.2, top + 5.6), (43.2, top + 7.6), (39.8, top + 10.6), (33.6, top + 11.6), (31.4, top + 11.0)]
            lid = box(33.6, top + 12.6, 43.4, top + 14.6, corner=0.6, material="Wood")
            white = box(32.6, top + 15.6, 43.4, top + 19.4, corner=1.2, material="Bone")
            pupil = box(36.6, top + 15.6, 39.6, top + 18.6, corner=0.6, colour=OUTLINE, seam=False)
            side = [white, pupil, lid]
        side.append(poly(brow, bevel=0.7, material="Bone", surface="strands"))
        parts.extend(side if not mirror else [_mirrored(p, 48.0) for p in side])
    return parts


def _mirrored(part: Part, axis: float) -> Part:
    """`part` mirrored about x = `axis` (its facing mirrored too)."""

    def test(x: float, y: float) -> Hit | None:
        hit = part.test(2.0 * axis - x, y)
        if hit is None:
            return None
        n = hit.normal
        return Hit((-n[0], n[1], n[2]), hit.u, hit.v)

    return Part(test, part.material, part.surface, part.colour, part.seam, part.glint, [_mirror(line, axis) for line in part.cracks], part.seed)


def _portrait_rest() -> list[Part]:
    shapes = _silhouettes()
    return [
        _bristles(shapes["portrait_rest_straw"], 30),
        _lines(shapes["portrait_rest_straw_lines"]),
        rod((43.6, 21.6), (52.2, 50.6), 5.0, material="Wood", surface="grain", seed=15),
        rod((45.0, 26.0), (47.6, 33.4), 4.9, material="Bone", surface="wrap"),
        ring((40.5, 11.8), 7.2, 3.6, material="Stone", surface="speckle"),
        ball((40.5, 11.8), 3.7, 3.7, colour=OUTLINE, seam=False),
        *_binding_face(50.4, False),
    ]


def _portrait_mean() -> list[Part]:
    shapes = _silhouettes()
    return [
        _bristles(shapes["portrait_mean_straw"], 31),
        box(42.6, 16.0, 53.4, 31.0, corner=0.8, material="Wood", surface="grain", seed=16),
        box(42.6, 21.6, 53.4, 28.8, corner=0.6, material="Bone", surface="wrap"),
        ring((48.5, 8.6), 7.2, 3.6, material="Stone", surface="speckle"),
        ball((48.5, 8.6), 3.7, 3.7, colour=OUTLINE, seam=False),
        *_binding_face(30.4, True),
    ]


def _portrait_eyes() -> list[Part]:
    """The eyes that light up in the dark: the rest pose's eye whites, inset, in Spark."""
    parts: list[Part] = []
    for mirror in (False, True):
        glow = box(33.6, 66.6, 42.4, 69.0, corner=0.8, material="Spark", glint=True)
        parts.append(_mirrored(glow, 48.0) if mirror else glow)
    return parts


def broom_portrait() -> Canvas:
    """Its intro portrait (three 96x96 frames: rest, mean, eyes; BossIntro)."""
    sheet = Canvas(192 * 3, 192)
    sheet.blit(sr.draw(_portrait_rest(), 96, 96), 0, 0)
    sheet.blit(sr.draw(_portrait_mean(), 96, 96), 192, 0)
    sheet.blit(sr.draw(_portrait_eyes(), 96, 96, outline=False), 384, 0)
    return sheet


SPRITES: dict[str, Callable[[], list[Part]]] = {
    "bone_husk": bone_husk,
    "bone_scepter": bone_scepter,
    "crypt_mite": crypt_mite,
    "ember_imp": ember_imp,
    "rime_crook": rime_crook,
    "shooting_dummy": shooting_dummy,
    "spitter": spitter,
    "splinter": splinter,
    "storm_fork": storm_fork,
    "training_dummy": training_dummy,
}


def files() -> dict[Path, Callable[[], Canvas]]:
    out: dict[Path, Callable[[], Canvas]] = {}
    for name, parts in SPRITES.items():
        out[ENEMIES / name / "idle@2x.svg"] = lambda p=parts: sr.draw(p(), 32, 32)
    out[BROOM / "handle@2x.svg"] = lambda: sr.draw(broom_handle(), 16, 40)
    out[BROOM / "binding@2x.svg"] = lambda: sr.draw(broom_binding(), 40, 16)
    out[BROOM / "head@2x.png"] = lambda: sr.strip([broom_head(f) for f in range(5)], 88, 32)
    out[BROOM / "head_burning@2x.png"] = lambda: sr.strip([broom_head(f, True) for f in range(5)], 88, 32)
    out[BROOM / "eyes@2x.svg"] = broom_eyes
    out[BROOM / "brows@2x.svg"] = broom_brows
    out[BROOM / "portrait@2x.svg"] = broom_portrait
    return out


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="write nothing; fail when a file differs")
    parser.add_argument("names", nargs="*", help="only these (an enemy's folder name, or old_broom)")
    args = parser.parse_args(argv)
    every = files()
    known = {path.parent.name for path in every}
    unknown = [n for n in args.names if n not in known]
    if unknown:
        parser.error(f"no such sprite: {', '.join(unknown)}")
    status = 0
    for path, draw in every.items():
        if args.names and path.parent.name not in args.names:
            continue
        picture = draw()
        data = picture.png() if path.suffix == ".png" else picture.svg().encode("utf-8")
        if args.check:
            if not path.exists() or path.read_bytes() != data:
                print(f"{path.relative_to(ROOT)} differs from what tools/enemy_art.py draws", file=sys.stderr)
                status = 1
        else:
            path.write_bytes(data)
            print(f"wrote {path.relative_to(ROOT)}")
    return status


if __name__ == "__main__":
    sys.exit(main())
