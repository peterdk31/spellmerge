# SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
# SPDX-License-Identifier: GPL-3.0-or-later
"""Shape and light rules for drawing a sprite at 2x detail from parts (ART1: the enemies and the
Old Broom redrawn by hand at 64 px; docs/STYLE.md; art/README.md, "Redrawing a sprite at 64x64").

A sprite is a list of parts, back to front, each a shape in world units (the 1x art's own pixel
grid: x right, y down) with a material and a surface. It is drawn at DETAIL art pixels a world
unit: each art pixel's middle is tested against the parts, the topmost that holds it colours it.

- **Light:** every shape gives its surface's facing (a rod is round across its length, a ball
  round both ways, a bevelled box or polygon flat with its rim turned out). The facing against the
  light from the top-left picks the material's shade: the base most, the light on the top-left
  turns, the shadow on the bottom-right ones (docs/STYLE.md, "Light and shading").
- **Material:** a part's surface marks its inside in its own shades: wood grain along a rod or a
  board, bone pores and cracks, a leaf's vein, a flame's bright core, ice and glass streaks, a
  stone speckle, a glint on what shines. Stone never takes its shadow (the floor's).
- **Edges:** where a part lies over another, the part below takes a dark seam along it, so the
  parts read apart; the outside gets a one-art-pixel outline, closed eight ways; the silhouette's
  bottom-right edge a shade down, its top-left a shade up.

Standard library only; used by tools/enemy_art.py and tools/prop_art.py.
"""

from __future__ import annotations

import math
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

sys.path.insert(0, str(Path(__file__).resolve().parent))
import staff_art  # noqa: E402
from staff_art import OUTLINE, Canvas  # noqa: E402

DETAIL = staff_art.DETAIL
ROOT = staff_art.ROOT

_L = (-0.55, -0.62, 0.56)
_N = math.sqrt(sum(c * c for c in _L))
LIGHT = (_L[0] / _N, _L[1] / _N, _L[2] / _N)
SHADOW_BELOW = 0.22
LIGHT_ABOVE = 0.76

Vec3 = tuple[float, float, float]
Point = tuple[float, float]

_ROW = re.compile(r"^\| \*\*([^*]+)\*\*[^|]*\| `(#[0-9a-f]{6})` \| `(#[0-9a-f]{6})` \| `(#[0-9a-f]{6})` \|", re.M)


def _palette() -> dict[str, tuple[str, str, str]]:
    style = (ROOT / "docs/STYLE.md").read_text(encoding="utf-8")
    return {name.split(" ")[0]: (a, b, c) for name, a, b, c in _ROW.findall(style)}


PALETTE = _palette()


def unit(x: float, y: float, z: float) -> Vec3:
    n = math.sqrt(x * x + y * y + z * z) or 1.0
    return (x / n, y / n, z / n)


def lit(n: Vec3) -> float:
    return n[0] * LIGHT[0] + n[1] * LIGHT[1] + n[2] * LIGHT[2]


def shade_of(n: Vec3) -> int:
    level = lit(n)
    return 0 if level < SHADOW_BELOW else (2 if level > LIGHT_ABOVE else 1)


def _hash(a: int, b: int, seed: int = 0) -> int:
    return ((a * 73856093) ^ (b * 19349663) ^ (seed * 83492791) ^ 0x5BD1E995) % 1000003


@dataclass
class Hit:
    """What a part says of a point: its facing, its local place (u along, v across, for surfaces)."""

    normal: Vec3
    u: float
    v: float


@dataclass
class Part:
    """A shape with a material (a palette material's name, or `colour` for a flat colour) and a
    surface; `seam`: a dark line where it lies over the part below; `glint`: its brightest pixel
    Bone light; `cracks`: polylines (world units) drawn a shade down across it; `raised`: Stone
    that stands up from the floor (a pillar, a slab: tools/prop_art.py) and may take its shadow shade
    on its bottom-right turns, which a body's stone never does."""

    test: Callable[[float, float], Hit | None]
    material: str = "Wood"
    surface: str = ""
    colour: str | None = None
    seam: bool = True
    glint: bool = False
    cracks: list[list[Point]] = field(default_factory=list)
    seed: int = 0
    raised: bool = False


# --- shapes -------------------------------------------------------------------------------------


def _seg(px: float, py: float, a: Point, b: Point) -> tuple[float, float, float]:
    """(t along a->b clamped, signed distance across, length)."""
    dx, dy = b[0] - a[0], b[1] - a[1]
    length = math.hypot(dx, dy) or 1e-9
    ux, uy = dx / length, dy / length
    rx, ry = px - a[0], py - a[1]
    t = (rx * ux + ry * uy) / length
    return t, -rx * uy + ry * ux, length


def rod(a: Point, b: Point, r: float, r_end: float | None = None, **kw: object) -> Part:
    """A round rod from `a` to `b`, `r` thick at a and `r_end` at b, its ends rounded."""
    r1 = r if r_end is None else r_end

    def test(x: float, y: float) -> Hit | None:
        t, across, length = _seg(x, y, a, b)
        tc = min(1.0, max(0.0, t))
        radius = r + (r1 - r) * tc
        cx, cy = a[0] + (b[0] - a[0]) * tc, a[1] + (b[1] - a[1]) * tc
        d = math.hypot(x - cx, y - cy)
        if d > radius:
            return None
        if 0.0 < t < 1.0:
            s = across / radius
            dx, dy = (b[0] - a[0]) / length, (b[1] - a[1]) / length
            return Hit(unit(-dy * s * 1.0, dx * s * 1.0, 0.75), t * length, s)
        return Hit(unit((x - cx) / radius * 1.2, (y - cy) / radius * 1.2, 0.6), t * length, across / radius)

    return Part(test, **kw)  # type: ignore[arg-type]


def ball(c: Point, rx: float, ry: float, lean: float = 0.8, **kw: object) -> Part:
    """An oval, shaded as a ball (`lean`: how round it looks)."""

    def test(x: float, y: float) -> Hit | None:
        dx, dy = (x - c[0]) / rx, (y - c[1]) / ry
        d2 = dx * dx + dy * dy
        if d2 > 1.0:
            return None
        z = math.sqrt(max(0.0, 1.0 - d2))
        # u along its longer axis, v across it (-1 to 1), as a rod's.
        upright = ry >= rx
        return Hit(unit(dx * lean, dy * lean, z + 0.35), (y - c[1]) if upright else (x - c[0]), dx if upright else dy)

    return Part(test, **kw)  # type: ignore[arg-type]


def _bevel(edge_normal: Point, depth: float, bevel: float) -> Vec3:
    if depth < bevel:
        return unit(edge_normal[0], edge_normal[1], 0.75)
    return (0.0, 0.0, 1.0)


def box(x0: float, y0: float, x1: float, y1: float, bevel: float = 0.55, corner: float = 0.0, **kw: object) -> Part:
    """A box, flat, its rim `bevel` wide turned out, its corners rounded `corner`."""

    def test(x: float, y: float) -> Hit | None:
        if not (x0 <= x <= x1 and y0 <= y <= y1):
            return None
        if corner > 0.0:
            cx = min(max(x, x0 + corner), x1 - corner)
            cy = min(max(y, y0 + corner), y1 - corner)
            if math.hypot(x - cx, y - cy) > corner:
                return None
        sides = ((x - x0, (-1.0, 0.0)), (x1 - x, (1.0, 0.0)), (y - y0, (0.0, -1.0)), (y1 - y, (0.0, 1.0)))
        depth, normal = min(sides, key=lambda s: s[0])
        # u along its longer side, v across it (-1 to 1), as a rod's, so a surface runs with it.
        if y1 - y0 >= x1 - x0:
            return Hit(_bevel(normal, depth, bevel), y - y0, (x - (x0 + x1) / 2.0) / ((x1 - x0) / 2.0))
        return Hit(_bevel(normal, depth, bevel), x - x0, (y - (y0 + y1) / 2.0) / ((y1 - y0) / 2.0))

    return Part(test, **kw)  # type: ignore[arg-type]


def poly(points: list[Point], bevel: float = 0.55, **kw: object) -> Part:
    """A polygon (any winding), flat, its rim `bevel` wide turned out."""

    def test(x: float, y: float) -> Hit | None:
        inside = False
        n = len(points)
        for i in range(n):
            ax, ay = points[i]
            bx, by = points[(i + 1) % n]
            if (ay > y) != (by > y) and x < (bx - ax) * (y - ay) / (by - ay) + ax:
                inside = not inside
        if not inside:
            return None
        best, normal = 1e9, (0.0, 0.0)
        for i in range(n):
            a, b = points[i], points[(i + 1) % n]
            t, across, length = _seg(x, y, a, b)
            tc = min(1.0, max(0.0, t))
            cx, cy = a[0] + (b[0] - a[0]) * tc, a[1] + (b[1] - a[1]) * tc
            d = math.hypot(x - cx, y - cy)
            if d < best:
                best = d
                normal = ((cx - x) / (d or 1e-9), (cy - y) / (d or 1e-9))
        return Hit(_bevel(normal, best, bevel), x, y)

    return Part(test, **kw)  # type: ignore[arg-type]


def ring(c: Point, r_out: float, r_in: float, **kw: object) -> Part:
    """A round ring, its outer rim and its hole's rim both turned (a torus)."""

    def test(x: float, y: float) -> Hit | None:
        dx, dy = x - c[0], y - c[1]
        d = math.hypot(dx, dy)
        if d > r_out or d < r_in:
            return None
        mid = (r_out + r_in) / 2.0
        s = (d - mid) / ((r_out - r_in) / 2.0)
        rx, ry = (dx / d, dy / d) if d > 1e-9 else (0.0, 0.0)
        return Hit(unit(rx * s * 1.3, ry * s * 1.3, 0.6), math.atan2(dy, dx), s)

    return Part(test, **kw)  # type: ignore[arg-type]


def mask(rows: list[list[list[int]]], ox: float = 0.0, oy: float = 0.0, apex: Point | None = None, inset: bool = True, **kw: object) -> Part:
    """A silhouette kept from 1x art (with its outline; `inset` false: runs with none, such as a
    flame's tongue): `rows[y]` the runs [from, to) of x it covers, placed at
    (ox, oy). Its facing is a bundle's: strands fanning from `apex` (above it), each round across,
    the whole a little rounder at its sides; u is the strand coordinate, v how far down it is."""
    height = len(rows)
    xs = [x for row in rows for run in row for x in run]
    left, right = (min(xs), max(xs)) if xs else (0, 1)
    middle = (left + right) / 2.0
    top = next((y for y, row in enumerate(rows) if row), 0)
    tip = apex if apex is not None else (middle, -40.0)

    def test(x: float, y: float) -> Hit | None:
        lx, ly = x - ox, y - oy
        row = int(math.floor(ly))
        if not (0 <= row < height):
            return None
        # The runs include the 1x outline: inset half a unit, so the one-art-pixel outline drawn
        # round the fill lands where the 1x outline was.
        pad = 0.5 if inset else 0.0
        if not any(a + pad <= lx < b - pad for a, b in rows[row]):
            return None
        if inset and not (0 <= row - 1 and any(a <= lx < b for a, b in rows[row - 1]) or ly - row >= 0.5):
            return None
        if inset and not (row + 1 < height and any(a <= lx < b for a, b in rows[row + 1]) or ly - row < 0.5):
            return None
        u = math.atan2(lx - tip[0], ly - tip[1]) * 80.0
        phase = (u * DETAIL / 2.0) % 1.0 - 0.5
        side = (lx - middle) / max(1.0, (right - left) / 2.0)
        down = (ly - top) / max(1.0, height - top)
        return Hit(unit(phase * 0.9 + side * 0.35, -0.25 + down * 0.5, 1.0), u, down)

    return Part(test, **kw)  # type: ignore[arg-type]


def moved(part: Part, ox: float, oy: float, scale: float = 1.0, turn: float = 0.0) -> Part:
    """`part` turned by `turn` radians, scaled and moved (its facing turned with it)."""
    cs, sn = math.cos(turn), math.sin(turn)

    def test(x: float, y: float) -> Hit | None:
        lx, ly = (x - ox) / scale, (y - oy) / scale
        hit = part.test(lx * cs + ly * sn, -lx * sn + ly * cs)
        if hit is None:
            return None
        n = hit.normal
        return Hit((n[0] * cs - n[1] * sn, n[0] * sn + n[1] * cs, n[2]), hit.u, hit.v)

    cracks = [[(ox + (px * cs - py * sn) * scale, oy + (px * sn + py * cs) * scale) for px, py in line] for line in part.cracks]
    return Part(test, part.material, part.surface, part.colour, part.seam, part.glint, cracks, part.seed, part.raised)


# --- surfaces -----------------------------------------------------------------------------------


def _surface(part: Part, hit: Hit, shade: int, ax: int, ay: int) -> int:
    """The shade after the part's surface (art pixel ax, ay)."""
    s = part.surface
    if s == "grain":
        # Lines along the length at a few heights across, broken now and then.
        lane = (hit.v + 1.0) * 2.6
        if abs(lane - round(lane)) < 0.18 and _hash(round(lane), int(hit.u * DETAIL / 3.0), part.seed) % 5 != 0:
            return shade - 1 if shade > 0 else 1
    elif s == "board":
        # A plank: grain lines along it, closer than a rod's, each broken now and then.
        lane = (hit.v + 1.0) * 3.6
        if abs(lane - round(lane)) < 0.2 and _hash(round(lane), int(hit.u * DETAIL / 4.0), part.seed) % 4 != 0:
            return shade - 1 if shade > 0 else 1
    elif s == "pores":
        if _hash(ax, ay, part.seed) % 19 == 0:
            return shade - 1 if shade > 0 else 1
    elif s == "vein":
        if abs(hit.v) < 0.16:
            return shade - 1 if shade > 0 else 1
    elif s == "flame":
        # Brighter toward the middle and the root.
        if abs(hit.v) < 0.35:
            return 2
    elif s == "streak":
        if (ax + ay) % 7 == 0 and shade < 2:
            return shade + 1
    elif s == "speckle":
        if _hash(ax, ay, part.seed) % 11 == 0:
            return min(2, shade + 1)
    elif s == "wrap":
        # A cord wound round: bands across the length, each lit on one side.
        if int(math.floor(hit.u * DETAIL / 3.0 + hit.v * 1.5)) % 2 == 0:
            return shade - 1 if shade > 0 else 1
    elif s == "rivets":
        # Rivets along a band: a lit dot with a shade under it.
        if int(hit.u * DETAIL) % 8 == 3 and int(hit.v * DETAIL) % 4 == 1:
            return 2
        if int(hit.u * DETAIL) % 8 == 4 and int(hit.v * DETAIL) % 4 == 2:
            return 0
    elif s == "strands":
        # Straw: a strand every few art pixels, each its own shade, a dark line between some.
        strand = int(math.floor(hit.u * DETAIL / 2.0))
        h = _hash(strand, 7, part.seed)
        if h % 11 == 0:
            return shade - 1 if shade > 0 else 1
        if h % 5 == 0:
            return min(2, shade + 1)
        return shade
    return shade


def _on_crack(part: Part, x: float, y: float) -> bool:
    for line in part.cracks:
        for a, b in zip(line, line[1:]):
            t, across, length = _seg(x, y, a, b)
            if -0.02 <= t <= 1.02 and abs(across) <= 0.3:
                return True
    return False


# --- drawing ------------------------------------------------------------------------------------


def draw(parts: list[Part], width: int, height: int, outline: bool = True) -> Canvas:
    """`parts` (back to front) drawn on a `width` x `height` world-unit sprite at DETAIL."""
    w, h = width * DETAIL, height * DETAIL
    canvas = Canvas(w, h)
    which: list[list[int]] = [[-1] * w for _ in range(h)]
    hits: list[list[Hit | None]] = [[None] * w for _ in range(h)]
    for py in range(h):
        for px in range(w):
            x, y = (px + 0.5) / DETAIL, (py + 0.5) / DETAIL
            for index in range(len(parts) - 1, -1, -1):
                hit = parts[index].test(x, y)
                if hit is not None:
                    which[py][px] = index
                    hits[py][px] = hit
                    break
    glints: dict[int, tuple[float, int, int]] = {}
    for py in range(h):
        for px in range(w):
            index = which[py][px]
            if index < 0:
                continue
            part, hit = parts[index], hits[py][px]
            assert hit is not None
            if part.colour is not None:
                canvas.pixels[py][px] = part.colour
                continue
            ramp = PALETTE[part.material]
            shade = shade_of(hit.normal)
            # The silhouette's own edges: lit top-left, shaded bottom-right (a shade each).
            def empty(dx: int, dy: int) -> bool:
                nx, ny = px + dx, py + dy
                return not (0 <= nx < w and 0 <= ny < h) or which[ny][nx] < 0
            if shade == 1 and empty(1, 0) and empty(0, 1):
                shade = 0
            elif shade == 1 and empty(-1, 0) and empty(0, -1):
                shade = 2
            shade = _surface(part, hit, shade, px, py)
            if _on_crack(part, (px + 0.5) / DETAIL, (py + 0.5) / DETAIL):
                shade = shade - 1 if shade > 0 else 1
            if part.material == "Stone" and not part.raised:
                shade = max(shade, 1)
            canvas.pixels[py][px] = ramp[max(0, min(2, shade))]
            if part.glint:
                level = lit(hit.normal) - 0.001 * (px + py)
                if index not in glints or level > glints[index][0]:
                    glints[index] = (level, px, py)
    for index, (_level, px, py) in glints.items():
        # Its own light shade (never another material's: docs/STYLE.md), Bone's own a white glint.
        light = PALETTE[parts[index].material][2] if parts[index].colour is None else parts[index].colour
        canvas.pixels[py][px] = light
        if py > 0 and which[py - 1][px] == index:
            canvas.pixels[py - 1][px] = light
    # Seams: a pixel beside one of a part drawn over it (a later one, with a seam) goes dark.
    seams: list[tuple[int, int]] = []
    for py in range(h):
        for px in range(w):
            index = which[py][px]
            if index < 0:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = px + dx, py + dy
                if 0 <= nx < w and 0 <= ny < h:
                    other = which[ny][nx]
                    if other > index and parts[other].seam and parts[other].colour != OUTLINE:
                        seams.append((px, py))
                        break
    for px, py in seams:
        canvas.pixels[py][px] = OUTLINE
    if outline:
        # A part in the outline's colour (a leg, a slit) is a line already: nothing round it.
        staff_art._outline(canvas, [[which[y][x] >= 0 and parts[which[y][x]].colour != OUTLINE for x in range(w)] for y in range(h)])
    return canvas


def draw_1x(parts: list[Part], width: int, height: int) -> Canvas:
    """`parts` drawn at one art pixel a world unit (a 1x icon from the same parts as its 2x one, for
    the HUD's small cells; ART2): DETAIL set to 1 for the one drawing."""
    global DETAIL
    detail = DETAIL
    DETAIL = 1
    try:
        return draw(parts, width, height)
    finally:
        DETAIL = detail


def strip(frames: list[list[Part]], width: int, height: int) -> Canvas:
    """Frames side by side, each `width` x `height` world units."""
    out = Canvas(width * DETAIL * len(frames), height * DETAIL)
    for i, parts in enumerate(frames):
        out.blit(draw(parts, width, height), i * width * DETAIL, 0)
    return out
