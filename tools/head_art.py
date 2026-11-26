#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
# SPDX-License-Identifier: GPL-3.0-or-later
"""The staff heads drawn at 2x detail with real material (ART1: players and enemies; the owner,
2026-11-26: "redraw with real detail"; docs/STYLE.md, "The living staffs"; art/README.md,
"Redrawing a sprite at 64x64"). The curl is tools/staff_art.py's; this draws the other four:

- `crystal`: a faceted bipyramid crystal in the player colour, its facets lit by the top-left
  light, a bright ridge and a white glint, held in a flared wooden collar; a straight shaft with a
  gold butt cap.
- `moon`: a crescent in the player colour with its horns pointing away, shaded as a ball, three
  craters pressed into it; a shaft kinked below a gold wrap.
- `star`: an upright four-point star in the player colour, bevelled into eight facets, a gold
  spark at its heart with a white glint; a crooked shaft with two knots and a gold wrap.
- `dev`: an upright eight-tooth cog in the player colour, its rim and teeth bevelled, four holes
  and a ring groove in its face, a gold hub round a dark axle; a straight shaft, a gold butt cap.

Every shaft is Wood shaded as a round rod, with grain lines along it; gold is Spark, shaded as
metal, with a glint. Shapes are worked out at each art pixel's middle in world units (the 48x48
sheet's layout, grip (24, 27), times DETAIL); a pixel's shade is its surface normal against the
light from the top-left (three shades a material, the light shade's brightest spots a glint); the
outline round the outside is one art pixel. Each head keeps its 1x shape family and about its size,
so its `tip` and `butt` hold; the star and the cog stay upright whichever way the staff points, the
crystal and the moon turn with it (as the 1x sheets).

    tools/head_art.py           # writes content/wizard/staffs/<head>/head@2x.png
    tools/head_art.py --check   # fails when a sheet differs from what the rules draw

Standard library only.
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path
from typing import Callable

sys.path.insert(0, str(Path(__file__).resolve().parent))
import staff_art  # noqa: E402
from staff_art import BONE, OUTLINE, RAMPS, SPARK, WOOD, Canvas  # noqa: E402

ROOT = staff_art.ROOT
DETAIL = staff_art.DETAIL
FRAME = staff_art.FRAME
GRIP = staff_art.GRIP
DIRECTIONS = staff_art.DIRECTIONS
BUTT = 10.0

# The light: from the top-left and toward the viewer (x right, y down, z out of the picture).
_L = (-0.55, -0.62, 0.56)
_N = math.sqrt(sum(c * c for c in _L))
LIGHT = (_L[0] / _N, _L[1] / _N, _L[2] / _N)
# n . LIGHT below SHADOW_BELOW is the shadow shade, above LIGHT_ABOVE the light, above GLINT_ABOVE
# a glint (on the materials that shine).
SHADOW_BELOW = 0.28
LIGHT_ABOVE = 0.76
GLINT_ABOVE = 0.965

# A head colour by shade, not by ramp (an override meaning "this shade of the player's ramp").
RAMPS_SHADE = ("ramp0", "ramp1", "ramp2")

# Materials (index into the colours a frame has).
M_WOOD, M_GOLD, M_HEAD, M_DARK = 1, 2, 3, 4

Vec3 = tuple[float, float, float]
# A hit: (material, normal, part id, an override colour or None).
Hit = tuple[int, Vec3, int, str | None]


def _unit(x: float, y: float, z: float) -> Vec3:
    n = math.sqrt(x * x + y * y + z * z) or 1.0
    return (x / n, y / n, z / n)


def _lit(n: Vec3) -> float:
    return n[0] * LIGHT[0] + n[1] * LIGHT[1] + n[2] * LIGHT[2]


def _shade_of(n: Vec3) -> int:
    level = _lit(n)
    return 0 if level < SHADOW_BELOW else (2 if level > LIGHT_ABOVE else 1)


class Frame:
    """One direction of a staff: the axes from the grip along the staff (`way`) and across it."""

    def __init__(self, direction: int) -> None:
        angle = direction * math.tau / DIRECTIONS
        self.way = (math.cos(angle), math.sin(angle))
        # Across: the side facing up (upright, the left), as the curl's.
        across = (self.way[1], -self.way[0])
        if across[1] > 1e-6:
            across = (-across[0], -across[1])
        self.across = across

    def local(self, wx: float, wy: float) -> tuple[float, float]:
        """(along, side) of the world point from the grip."""
        rx, ry = wx - GRIP[0], wy - GRIP[1]
        return (rx * self.way[0] + ry * self.way[1], rx * self.across[0] + ry * self.across[1])

    def to_screen(self, nu: float, nv: float, nz: float) -> Vec3:
        """A normal given along the staff, across it and out, in the picture's axes."""
        return _unit(nu * self.way[0] + nv * self.across[0], nu * self.way[1] + nv * self.across[1], nz)

    def at(self, along: float) -> tuple[float, float]:
        return (GRIP[0] + self.way[0] * along, GRIP[1] + self.way[1] * along)


# --- the shaft ------------------------------------------------------------------------------


def _rod(frame: Frame, s: float) -> Vec3:
    """A round rod's normal at `s` across it (-1 to 1), leaned out so a thin rod still shows its
    three shades: light on the side toward the light, shadow on the other."""
    return frame.to_screen(0.0, s * 1.4, 0.55)


def _grain(along: float, s: float, seed: int) -> bool:
    """A grain line along the rod: thin streaks at a few heights across it, broken now and then."""
    lane = int((s + 1.0) * 2.4)
    cell = int((along + 20.0) * DETAIL / 5.0)
    h = (lane * 73 + cell * 151 + seed * 19) % 11
    return h < 3 and abs(((s + 1.0) * 2.4) % 1.0 - 0.5) < 0.22


def shaft(frame: Frame, along: float, side: float, *, end: float, half: float = 1.05,
          bend: Callable[[float], float] = lambda a: 0.0, bands: tuple[tuple[float, float], ...] = (),
          cap: float = 0.0, knots: tuple[tuple[float, float], ...] = (), seed: int = 0) -> Hit | None:
    """The rod from BUTT behind the grip to `end`: Wood shaded round, with grain; gold `bands`
    (from, to along it) and a gold butt `cap` this long; `knots` (along, which side) bulge it."""
    if not (-BUTT - 0.2 <= along <= end):
        return None
    off = side - bend(along)
    width = half
    knot_here = 0.0
    for at, way in knots:
        bump = max(0.0, 1.0 - abs(along - at) / 1.2)
        if bump > 0.0 and off * way > 0.0:
            width = half + 0.9 * bump
            knot_here = bump
    # The butt rounds off.
    if along < -BUTT + half:
        width = min(width, math.sqrt(max(0.0, half * half - (-BUTT + half - along) ** 2)) + 0.05)
    if abs(off) > width:
        return None
    s = max(-1.0, min(1.0, off / width))
    normal = _rod(frame, s)
    in_band = any(a <= along <= b for a, b in bands) or along <= -BUTT + cap
    if in_band:
        # A seam where a band meets the wood: its ends a shade down.
        edge = any(abs(along - a) < 0.3 or abs(along - b) < 0.3 for a, b in bands)
        if edge:
            return (M_GOLD, frame.to_screen(0.0, s, 0.2), 2, None)
        return (M_GOLD, normal, 2, None)
    if knot_here > 0.35:
        # A knot: a ring of shadow round a lit eye.
        r = math.hypot((along - min(knots, key=lambda k: abs(k[0] - along))[0]) / 0.9, (abs(off) - half * 0.9) / 0.7)
        if 0.55 < r < 1.0:
            return (M_WOOD, normal, 1, WOOD[0])
    if _grain(along, s, seed) and _shade_of(normal) > 0:
        return (M_WOOD, normal, 1, WOOD[_shade_of(normal) - 1])
    return (M_WOOD, normal, 1, None)


# --- the heads -------------------------------------------------------------------------------


def crystal(frame: Frame, wx: float, wy: float) -> Hit | None:
    along, side = frame.local(wx, wy)
    # The crystal: a bipyramid along the staff, widest at MID, its top TOP, its foot FOOT.
    mid, top, foot, wide = 12.3, 17.6, 8.7, 3.7
    u = along
    if foot <= u <= top:
        reach = (u - mid) / (top - mid) if u >= mid else (mid - u) / (mid - foot)
        if abs(side) / wide + reach <= 1.0:
            upper = u >= mid
            sv = abs(side) / wide
            # Three facets a side: the face (|v| small) and the two flanks.
            nu = 0.5 if upper else -0.35
            if sv < 0.28:
                nv = 0.0
                part = 10 if upper else 11
            else:
                nv = 1.2 if side > 0 else -1.2
                part = (12 if side > 0 else 13) + (0 if upper else 2)
            normal = frame.to_screen(nu, nv, 2.0)
            # The ridges between facets catch the light: a thin bright line down the face's edges.
            if 0.22 < sv < 0.34 and upper:
                return (M_HEAD, normal, part, "ridge")
            return (M_HEAD, normal, part, None)
    # The collar: the wood flaring up to hold the crystal.
    if 7.0 <= along <= 9.6:
        flare = 1.05 + (along - 7.0) / 2.6 * 1.8
        if abs(side) <= flare:
            s = side / flare
            return (M_WOOD, _rod(frame, s), 5, None)
    return shaft(frame, along, side, end=7.2, cap=1.6, seed=1)


def moon(frame: Frame, wx: float, wy: float) -> Hit | None:
    along, side = frame.local(wx, wy)
    # The crescent: a ball of radius OUTER at BOWL, less one of INNER pushed out toward the tip.
    bowl, outer, inner, push = 13.5, 4.4, 3.5, 2.6
    du, dv = along - bowl, side
    r = math.hypot(du, dv)
    if r <= outer and math.hypot(du - push, dv) > inner:
        # Shaded as the ball the crescent is cut from.
        z = math.sqrt(max(0.0, 1.0 - (r / outer) ** 2))
        normal = frame.to_screen(du / outer * 0.6, dv / outer * 0.6, z + 0.55)
        # Craters: shallow dishes, their normals turned in (lit on the far side).
        for cu, cv, cr in ((-1.9, 2.2, 0.9), (-3.0, -0.6, 0.75), (-1.2, -2.6, 0.7)):
            d = math.hypot(du - cu, dv - cv)
            if d <= cr:
                k = d / cr
                # A dish: its wall toward the light in shadow, the far wall's rim lit.
                to = frame.to_screen(du - cu, dv - cv, 0.0)
                toward = to[0] * LIGHT[0] + to[1] * LIGHT[1]
                shade = 0 if toward > 0.1 else (2 if k > 0.6 and toward < -0.3 else 1)
                return (M_HEAD, normal, 21, RAMPS_SHADE[shade])
        # The cut edge, facing the tip, a shade down: the crescent's inner rim.
        if math.hypot(du - push, dv) <= inner + 0.55:
            return (M_HEAD, frame.to_screen(-(du - push), -dv, 1.4), 22, None)
        return (M_HEAD, normal, 20, None)
    if 8.3 <= along <= 9.7:
        flare = 1.05 + (along - 8.3) / 1.4 * 1.0
        if abs(side) <= flare:
            s = side / flare
            return (M_GOLD, _rod(frame, s), 6, None)
    return shaft(frame, along, side, end=8.5, bend=lambda a: -0.9 * min(1.0, max(0.0, (-a - 0.5) / 1.5)),
                 bands=((-3.4, -1.6),), seed=2)


def star(frame: Frame, wx: float, wy: float) -> Hit | None:
    # Upright, whichever way the staff points: the star's middle at CENTRE along the staff.
    centre = frame.at(15.6)
    dx, dy = wx - centre[0], wy - centre[1]
    rx, ry = 5.3, 4.7
    ax, ay = abs(dx) / rx, abs(dy) / ry
    if ax ** 0.62 + ay ** 0.62 <= 1.0:
        if math.hypot(dx, dy) <= 1.25:
            # The gold spark at its heart, a dome with a glint.
            z = math.sqrt(max(0.0, 1.0 - (math.hypot(dx, dy) / 1.3) ** 2))
            return (M_GOLD, _unit(dx / 1.3, dy / 1.3, z + 0.3), 31, None)
        # Bevelled: each arm split down its middle; each half its own facet.
        sx = 1.0 if dx > 0 else -1.0
        sy = 1.0 if dy > 0 else -1.0
        if ax >= ay:
            normal = _unit(sx * 0.2, sy * 0.5, 1.0)
            part = 32 + (0 if sy < 0 else 1) + (0 if sx < 0 else 2)
        else:
            normal = _unit(sx * 0.5, sy * 0.2, 1.0)
            part = 36 + (0 if sy < 0 else 1) + (0 if sx < 0 else 2)
        return (M_HEAD, normal, part, None)
    along, side = frame.local(wx, wy)
    bend = lambda a: 0.55 * math.sin((a + 10.0) * 0.42) - 0.25  # noqa: E731
    return shaft(frame, along, side, end=13.0, bend=bend, bands=((-1.6, 0.4),),
                 knots=((9.6, 1.0), (3.6, -1.0)), seed=3)


def cog(frame: Frame, wx: float, wy: float) -> Hit | None:
    centre = frame.at(12.6)
    dx, dy = wx - centre[0], wy - centre[1]
    r = math.hypot(dx, dy)
    body, teeth_out, teeth = 4.7, 6.1, 8
    theta = math.atan2(dy, dx)
    # The teeth: 8 round, one pointing up (as the 1x cog), each as wide at its root as its gap.
    phase = (theta + math.pi / 2.0) * teeth / math.tau
    tooth = abs(phase - round(phase)) < 0.27 - 0.05 * max(0.0, (r - body) / (teeth_out - body))
    edge = teeth_out if tooth else body
    if r > edge:
        along, side = frame.local(wx, wy)
        return shaft(frame, along, side, end=7.6, cap=1.6, seed=4)
    radial = (dx / r, dy / r) if r > 1e-6 else (0.0, 0.0)
    if r <= 0.65:
        return (M_DARK, (0.0, 0.0, 1.0), 40, OUTLINE)
    if r <= 1.75:
        z = math.sqrt(max(0.0, 1.0 - (r / 1.85) ** 2))
        return (M_GOLD, _unit(dx / 1.85, dy / 1.85, z + 0.2), 41, None)
    # Four round holes on the diagonals: dark, their far wall lit.
    for k in range(4):
        a = math.pi / 4.0 + k * math.pi / 2.0
        hx, hy = math.cos(a) * 3.25, math.sin(a) * 3.25
        d = math.hypot(dx - hx, dy - hy)
        if d <= 0.95:
            return (M_DARK, (0.0, 0.0, 1.0), 44, OUTLINE if (dx - hx) * LIGHT[0] + (dy - hy) * LIGHT[1] > -0.35 else None)
    # The ring round the hub, raised a step: its edge facing the light lit, the far edge shaded.
    if r <= 2.3:
        return (M_HEAD, _unit(radial[0] * 0.8, radial[1] * 0.8, 0.8), 45, None)
    # The rim and the teeth bevelled outward one art pixel; the face flat.
    if r >= edge - 0.5 or (tooth and r > body - 0.5):
        return (M_HEAD, _unit(radial[0], radial[1], 0.6), 46, None)
    return (M_HEAD, (0.0, 0.0, 1.0), 47, None)


HEADS: dict[str, Callable[[Frame, float, float], Hit | None]] = {
    "crystal": crystal,
    "moon": moon,
    "star": star,
    "dev": cog,
}


# --- drawing --------------------------------------------------------------------------------


def _colour(hit: Hit, ramp: int) -> str:
    material, normal, _part, override = hit
    if override in RAMPS_SHADE:
        return RAMPS[ramp][RAMPS_SHADE.index(override)]
    if override is not None and override != "ridge":
        return override
    shade = _shade_of(normal)
    level = _lit(normal)
    if material == M_WOOD:
        return WOOD[shade]
    if material == M_GOLD:
        return BONE[2] if level > GLINT_ABOVE else SPARK[shade]
    if material == M_HEAD:
        if override == "ridge":
            return RAMPS[ramp][2]
        # No glint from the shading on the head: a bevel facing the light would be a white arc;
        # `_glint` puts one small one on it.
        return RAMPS[ramp][shade]
    # A hole's lit far wall.
    return RAMPS[ramp][0]


def head_frame(name: str, direction: int, ramp: int) -> Canvas:
    size = FRAME * DETAIL
    canvas = Canvas(size, size)
    frame = Frame(direction)
    draw = HEADS[name]
    hits: list[list[Hit | None]] = [[None] * size for _ in range(size)]
    for py in range(size):
        for px in range(size):
            hits[py][px] = draw(frame, (px + 0.5) / DETAIL, (py + 0.5) / DETAIL)
    for py in range(size):
        for px in range(size):
            hit = hits[py][px]
            if hit is None:
                continue
            canvas.pixels[py][px] = _colour(hit, ramp)
            # Where the head sits on the wood or the gold, the lower part takes a dark seam, so the
            # parts read apart.
            if hit[0] in (M_WOOD, M_GOLD):
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = px + dx, py + dy
                    if 0 <= nx < size and 0 <= ny < size:
                        other = hits[ny][nx]
                        if other is not None and other[0] == M_HEAD:
                            canvas.pixels[py][px] = OUTLINE
    # The head's edge facing away from the light (bottom right) a shade down where the shading
    # left it the base, so even a head turned full to the light has its shadow edge.
    for py in range(size - 1):
        for px in range(size - 1):
            hit = hits[py][px]
            if hit is None or hit[0] != M_HEAD or canvas.pixels[py][px] != RAMPS[ramp][1]:
                continue
            right, below = hits[py][px + 1], hits[py + 1][px]
            if (right is None or right[0] != M_HEAD) and (below is None or below[0] != M_HEAD):
                canvas.pixels[py][px] = RAMPS[ramp][0]
    _glint(canvas, hits, ramp)
    staff_art._outline(canvas, [[hits[y][x] is not None for x in range(size)] for y in range(size)])
    return canvas


def _glint(canvas: Canvas, hits: list[list[Hit | None]], ramp: int) -> None:
    """A head's glint: the head pixel facing the light most, and the one up-left of it, in Bone
    light (a gem's sparkle), unless the shading already put one there."""
    best, at = -2.0, None
    size = canvas.width
    for py in range(size):
        for px in range(size):
            hit = hits[py][px]
            if hit is not None and hit[0] == M_HEAD and hit[3] is None:
                level = _lit(hit[1]) - 0.002 * (px + py)
                if level > best:
                    best, at = level, (px, py)
    if at is None:
        return
    for dx, dy in ((0, 0), (-1, 0), (0, -1)):
        x, y = at[0] + dx, at[1] + dy
        hit = hits[y][x] if 0 <= x < size and 0 <= y < size else None
        if hit is not None and hit[0] == M_HEAD and hit[3] is None:
            canvas.pixels[y][x] = BONE[2]


def sheet(name: str) -> Canvas:
    size = FRAME * DETAIL
    out = Canvas(size * DIRECTIONS, size * len(RAMPS))
    for ramp in range(len(RAMPS)):
        for direction in range(DIRECTIONS):
            out.blit(head_frame(name, direction, ramp), direction * size, ramp * size)
    return out


def files() -> dict[Path, Callable[[], Canvas]]:
    return {ROOT / f"content/wizard/staffs/{name}/head@2x.png": (lambda n=name: sheet(n)) for name in HEADS}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="write nothing; fail when a sheet differs")
    parser.add_argument("heads", nargs="*", help="only these heads (default: all)")
    args = parser.parse_args(argv)
    unknown = [name for name in args.heads if name not in HEADS]
    if unknown:
        parser.error(f"no such head: {', '.join(unknown)} (the heads: {', '.join(HEADS)})")
    status = 0
    for path, draw in files().items():
        if args.heads and path.parent.name not in args.heads:
            continue
        data = draw().png()
        if args.check:
            if not path.exists() or path.read_bytes() != data:
                print(f"{path.relative_to(ROOT)} differs from what tools/head_art.py draws", file=sys.stderr)
                status = 1
        else:
            path.write_bytes(data)
            print(f"wrote {path.relative_to(ROOT)}")
    return status


if __name__ == "__main__":
    sys.exit(main())
