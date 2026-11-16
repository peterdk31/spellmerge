#!/usr/bin/env python3
"""Draw a room's ground from a shape file (docs/milestones/hub-rework.md, "Built for every room").

    python3 tools/ground_shape.py content/rooms/hub/hub.shape.json      # write the room's ground
    python3 tools/ground_shape.py --check                                # every shape file up to date?

A shape file (`<room>.shape.json`, beside the room's scene) says what a room's ground is: its
outlines (land inside, the void or a wall outside), the cracks that run into them from their
edge, the areas of another ground material inside them, which edge style its edges are drawn in
(`content/edges/<id>/edge.json`) and which ground material its floor is (`content/grounds/<id>/
ground.json`). From it this writes the room's ground scene, `<room>_ground.tscn`, beside it, and
its art, in `art/grounds/<room>/` (art lives under art/; a room's folder holds its layout):

- `<room>_ground_floor.png`: the floor as the room shows it, every pixel a body may stand on
  opaque and every other pixel clear (the void or a wall's own art shows there). The scene's root
  is a `Sprite2D` of it named `Floor` (the room instances it under that name, so everything that
  reads a room's `Floor` sprite reads it), at `RoomBase.FLOOR_Z`.
- `<room>_ground_under.png`: the rock face under every edge that faces down, hanging into the
  void (a sprite on the walls' body where the void is wall, so a hit on the edge sheds its colours;
  on the root where it is a hole, which no shot hits).
- `<room>_ground_glow.png`: the edges' glow, at half size, added over what lies below it.
- the walls and the holes, as rectangles of whole 8 px cells: a cell is open (not ground) when the
  pixel at its middle is clear in the floor art, so the art and the grid never disagree. An open
  cell in a crack is a hole (`Holes`, on the hole layer: a body may dash, be pushed or teleport over
  it, and falls in; docs/milestones/hub-rework.md, "Holes"); an open cell outside the outlines is
  the shape's `void`: `"hole"` (an island in the void, the hub: the same void as in the cracks) or
  `"wall"` (the default: a floor's edge inside walls, on the wall layer, `Walls`);
- the edges' motes: a hidden closed `Line2D` round every outline (`Rim`, `Rim2`, ...) and an open
  one under each run of rock face (`Drip1`, ...), each a `MoteSource` of the edge style's kinds;
  a rim's colours run in bands along it (`MoteSource.band_length`), the same bands the edge's seam
  is drawn in, so the motes match the edge they leave.

**Cracks thin out smoothly.** Everything drawn about an edge beside a crack follows the crack's width
there: the lip's width, the seam's shade, the glow and the rock face, from the edge
style's `full_width` (the whole edge) to nothing at a hairline. A crack narrower than a cell
(`CELL`) is drawn into the floor (dark, opaque) rather than cut out of it, so it is never a wall
or a hole of less than a cell; only its wide part is clear.

The scene's root carries the hash of everything it was made from (`metadata/ground_inputs`):
`--check` fails when a shape file, its edge style, its ground materials or this generator changed
since its scene was written. Python 3.10 and the standard library only (tools/README.md); the same
inputs always give the same files.
"""

from __future__ import annotations

import argparse
import array
import hashlib
import json
import math
import re
import struct
import sys
import zlib
from pathlib import Path

import ground_materials
import ground_walls

ROOT = Path(__file__).resolve().parent.parent
# Bump when what the generator draws changes, so every room's `--check` asks for a new run.
VERSION = 3
PALETTE = ROOT / "core/base/palette.gd"
EDGES = ROOT / "content/edges"
GROUNDS = ROOT / "content/grounds"
# The size of a wall cell, in pixels (the projectile manager's wall grid: `WALL_CELL`).
CELL = 8
# `RoomBase.FLOOR_Z`, and the z of the glow (over the floor, under every body; at the marks' and the
# cover's z, so it is drawn by tree order among them, before them: it is the room's).
FLOOR_Z = -2
GLOW_Z = -1
# `RoomBase.WALL_LAYER` and `RoomBase.HOLE_LAYER`.
WALL_LAYER = 1
HOLE_LAYER = 2
# How far from open ground a pixel still takes its edge style's side, in pixels.
SIDE_REACH = 130
# How far past a pin's end a frame's edge eases back to its noise, in pixels.
PIN_EASE = 12.0
# The most bytes a file may be (AGENTS.md, hard rule 3: 1 MB an image).
MOST_BYTES = 1024 * 1024


# ----------------------------------------------------------------------------------------------
# Colours


def materials(path: Path = PALETTE) -> dict[str, list[tuple[int, int, int]]]:
    """The palette's materials by name, each its shadow, base and light (core/base/palette.gd)."""
    found: dict[str, list[tuple[int, int, int]]] = {}
    pattern = re.compile(r'&"(\w+)":\s*\[Color\("([0-9a-f]{6})"\),\s*Color\("([0-9a-f]{6})"\),\s*Color\("([0-9a-f]{6})"\)\]')
    for match in pattern.finditer(path.read_text(encoding="utf-8")):
        found[match.group(1)] = [_rgb(match.group(i)) for i in (2, 3, 4)]
    return found


def _rgb(text: str) -> tuple[int, int, int]:
    text = text.lstrip("#")
    return (int(text[0:2], 16), int(text[2:4], 16), int(text[4:6], 16))


SHADES = {"shadow": 0, "base": 1, "light": 2}


def colour(spec: str, mats: dict[str, list[tuple[int, int, int]]]) -> tuple[int, int, int]:
    """A colour as data names it: `#rrggbb`, or a palette material's shade (`leaf.base`)."""
    if spec.startswith("#"):
        return _rgb(spec)
    name, _, shade = spec.partition(".")
    if name not in mats or shade not in SHADES:
        raise ValueError(f"unknown colour {spec!r}: write #rrggbb or <material>.<shadow|base|light>")
    return mats[name][SHADES[shade]]


def _mix(a: tuple[int, int, int], b: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    return (round(a[0] + (b[0] - a[0]) * t), round(a[1] + (b[1] - a[1]) * t), round(a[2] + (b[2] - a[2]) * t))


# ----------------------------------------------------------------------------------------------
# Hashes and noise (seeded, the same everywhere)


def hash32(*values: int) -> int:
    """A 32-bit hash of whole numbers (FNV-1a over them, then mixed)."""
    x = 2166136261
    for value in values:
        x = ((x ^ (int(value) & 0xFFFFFFFF)) * 16777619) & 0xFFFFFFFF
    x ^= x >> 13
    x = (x * 0x5BD1E995) & 0xFFFFFFFF
    return x ^ (x >> 15)


def unit(*values: int) -> float:
    """A number in [0, 1) from whole numbers."""
    return hash32(*values) / 4294967296.0


def _smooth(t: float) -> float:
    return t * t * (3.0 - 2.0 * t)


def noise1(s: float, seed: int, period: int = 0) -> float:
    """Smooth value noise along a line, in [0, 1); with `period`, it repeats every that many units."""
    i = math.floor(s)
    t = _smooth(s - i)
    a, b = i, i + 1
    if period > 0:
        a, b = a % period, b % period
    return unit(seed, a) * (1.0 - t) + unit(seed, b) * t


def noise2(x: float, y: float, scale: float, seed: int) -> float:
    """Smooth value noise over the plane, cells of `scale` pixels, in [0, 1)."""
    fx, fy = x / scale, y / scale
    ix, iy = math.floor(fx), math.floor(fy)
    tx, ty = _smooth(fx - ix), _smooth(fy - iy)
    a = unit(seed, ix, iy)
    b = unit(seed, ix + 1, iy)
    c = unit(seed, ix, iy + 1)
    d = unit(seed, ix + 1, iy + 1)
    return (a * (1.0 - tx) + b * tx) * (1.0 - ty) + (c * (1.0 - tx) + d * tx) * ty


def fbm2(x: float, y: float, scales: list[float], seed: int) -> float:
    """Several octaves of `noise2`, the first the strongest, in [0, 1)."""
    total, weight, amp = 0.0, 0.0, 1.0
    for i, scale in enumerate(scales):
        total += noise2(x, y, scale, seed + i) * amp
        weight += amp
        amp *= 0.5
    return total / weight


# ----------------------------------------------------------------------------------------------
# PNG (written by hand: no image library)


def png(width: int, height: int, rgba: bytearray) -> bytes:
    """A PNG of `rgba` (4 bytes a pixel, rows top down): indexed when it has at most 256 colours
    (the floor's few shades pack far smaller), else true colour with alpha."""
    colours: dict[bytes, int] = {}
    for i in range(0, len(rgba), 4):
        key = bytes(rgba[i:i + 4])
        if key not in colours:
            if len(colours) == 256:
                colours = {}
                break
            colours[key] = len(colours)
    rows = bytearray()
    if colours:
        index = {key: i for key, i in colours.items()}
        for y in range(height):
            rows.append(0)
            start = y * width * 4
            rows.extend(index[bytes(rgba[start + x * 4:start + x * 4 + 4])] for x in range(width))
        header = struct.pack(">IIBBBBB", width, height, 8, 3, 0, 0, 0)
        palette = b"".join(key[:3] for key in colours)
        alpha = bytes(key[3] for key in colours)
        chunks = [(b"IHDR", header), (b"PLTE", palette), (b"tRNS", alpha)]
    else:
        stride = width * 4
        for y in range(height):
            rows.append(0)
            rows.extend(rgba[y * stride:(y + 1) * stride])
        chunks = [(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))]
    chunks.append((b"IDAT", zlib.compress(bytes(rows), 9)))
    chunks.append((b"IEND", b""))
    out = bytearray(b"\x89PNG\r\n\x1a\n")
    for kind, data in chunks:
        out += struct.pack(">I", len(data)) + kind + data
        out += struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    return bytes(out)


def read_png(data: bytes) -> tuple[int, int, bytearray]:
    """Read back a PNG this file wrote (indexed or RGBA, filter 0): width, height and its RGBA."""
    pos = 8
    width = height = kind = 0
    idat = bytearray()
    palette = b""
    alpha = b""
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos:pos + 4])
        chunk = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if chunk == b"IHDR":
            width, height, _, kind = struct.unpack(">IIBB", body[:10])
        elif chunk == b"PLTE":
            palette = body
        elif chunk == b"tRNS":
            alpha = body
        elif chunk == b"IDAT":
            idat += body
    raw = zlib.decompress(bytes(idat))
    rgba = bytearray(width * height * 4)
    per = 1 if kind == 3 else 4
    for y in range(height):
        row = raw[y * (width * per + 1) + 1:(y + 1) * (width * per + 1)]
        for x in range(width):
            o = (y * width + x) * 4
            if kind == 3:
                i = row[x]
                rgba[o:o + 3] = palette[i * 3:i * 3 + 3]
                rgba[o + 3] = alpha[i] if i < len(alpha) else 255
            else:
                rgba[o:o + 4] = row[x * 4:x * 4 + 4]
    return width, height, rgba


# ----------------------------------------------------------------------------------------------
# The shape


def placements(shape_path: Path) -> list[tuple[float, float, float]]:
    """Where the room's things stand, as circles a crack keeps clear of: every node of the room's
    scene (`<room>.tscn` beside its shape) placed under another node (its spawns, props, dummies,
    items: anything but the room's own top-level nodes), `keep_clear_round` pixels round, and every
    zone (a `ReferenceRect` under `Zones`), as a row of circles along it, each out to its piece's
    corners and that much more.
    So moving a thing in the editor moves the cracks away from it (its ground is then out of date
    until drawn again: `--check`)."""
    shape = json.loads(shape_path.read_text(encoding="utf-8"))
    radius = float(shape.get("keep_clear_round", 0))
    scene = shape_path.parent / (shape_path.name.removesuffix(".shape.json") + ".tscn")
    if radius <= 0 or not scene.exists():
        return []
    found: list[tuple[float, float, float]] = []
    for block in re.split(r"\n(?=\[)", scene.read_text(encoding="utf-8")):
        head = re.match(r'\[node name="[^"]+"(?: type="(\w+)")? parent="([^"]+)"', block)
        if head is None or head.group(2) == ".":
            continue
        if head.group(1) == "ReferenceRect":
            if head.group(2) != "Zones":
                continue
            sides = {k: float(v) for k, v in re.findall(r"offset_(left|top|right|bottom) = ([-\d.]+)", block)}
            if len(sides) == 4:
                # A row (or column) of circles along a long zone, each round a square-ish piece of it.
                w, h = sides["right"] - sides["left"], sides["bottom"] - sides["top"]
                count = max(1, math.ceil(max(w, h) / max(1.0, min(w, h))))
                for i in range(count):
                    t = (i + 0.5) / count
                    cx = sides["left"] + (w * t if w >= h else w / 2)
                    cy = sides["top"] + (h * t if h > w else h / 2)
                    piece = (w / count, h) if w >= h else (w, h / count)
                    found.append((cx, cy, math.hypot(*piece) / 2 + radius))
            continue
        at = re.search(r"position = Vector2\(([-\d.]+), ([-\d.]+)\)", block)
        if at:
            found.append((float(at.group(1)), float(at.group(2)), radius))
    return found


def clear_points(shape_path: Path) -> list[tuple[float, float, float]]:
    """Where a frame's floor is pushed out to (its `clear`): every node of the room's scene whose
    parent is one of `clear.of` (e.g. `PlayerSpawns`, `Props`: groups at the room's origin), `clear.round`
    pixels round, so a wandering wall never covers what stands in the room."""
    shape = json.loads(shape_path.read_text(encoding="utf-8"))
    spec = shape.get("frame", {}).get("clear")
    scene = shape_path.parent / (shape_path.name.removesuffix(".shape.json") + ".tscn")
    if not spec or not scene.exists():
        return []
    radius = float(spec["round"])
    parents = set(spec["of"])
    found: list[tuple[float, float, float]] = []
    for block in re.split(r"\n(?=\[)", scene.read_text(encoding="utf-8")):
        head = re.match(r'\[node name="[^"]+"(?: type="(\w+)")? parent="([^"]+)"', block)
        # Direct children only: a child's position is its own place in the room (its parent, a
        # plain group node, stands at the room's origin); a grandchild's is not.
        if head is None or head.group(2) not in parents:
            continue
        at = re.search(r"position = Vector2\(([-\d.]+), ([-\d.]+)\)", block)
        if at:
            found.append((float(at.group(1)), float(at.group(2)), radius))
    return found


def outline_points(spec: dict, step: float = 2.0) -> list[tuple[float, float]]:
    """An outline's points, clockwise on screen: a wavy, rough oval.

    `centre` and `radii` place the oval; `waves` ([[k, amount, phase], ...]) bend it k times round;
    `rough` ([[scale, amount], ...]) roughens it along its length with noise of that many pixels
    (the large bays and points first, the small notches last), seeded by `seed`."""
    cx, cy = spec["centre"]
    rx, ry = spec["radii"]
    seed = int(spec.get("seed", 0))
    mean = (rx + ry) * 0.5
    count = max(64, int(math.tau * mean / step))
    points = []
    for i in range(count):
        a = i / count * math.tau
        r = 1.0
        for k, amount, phase in spec.get("waves", []):
            r += amount * math.sin(k * a + phase)
        for j, (scale, amount) in enumerate(spec.get("rough", [])):
            period = max(1, round(math.tau * mean / scale))
            r += amount * 2.0 * (noise1(a / math.tau * period, seed + 17 * j, period) - 0.5)
        points.append((cx + math.cos(a) * rx * r, cy + math.sin(a) * ry * r))
    return points


def fill_polygon(mask: bytearray, width: int, height: int, points: list[tuple[float, float]], value: int) -> None:
    """Set every pixel whose middle is inside `points` (even-odd) to `value`."""
    edges = [(points[i], points[(i + 1) % len(points)]) for i in range(len(points))]
    ys = [p[1] for p in points]
    top, bottom = max(0, int(min(ys))), min(height - 1, int(max(ys)) + 1)
    for y in range(top, bottom + 1):
        sy = y + 0.5
        xs = []
        for (x1, y1), (x2, y2) in edges:
            if (y1 <= sy < y2) or (y2 <= sy < y1):
                xs.append(x1 + (sy - y1) * (x2 - x1) / (y2 - y1))
        xs.sort()
        row = y * width
        for k in range(0, len(xs) - 1, 2):
            start = max(0, math.ceil(xs[k] - 0.5))
            end = min(width - 1, math.floor(xs[k + 1] - 0.5))
            for x in range(start, end + 1):
                mask[row + x] = value


class Ground:
    """A room's ground as it is worked out: which pixels are land, how wide a crack is where it
    runs, and which ground material each pixel of land is."""

    def __init__(self, shape: dict, placed: list[tuple[float, float, float]] | None = None,
                 clear: list[tuple[float, float, float]] | None = None) -> None:
        self.width, self.height = (int(v) for v in shape["size"])
        if self.width % CELL or self.height % CELL:
            raise ValueError(f"size {shape['size']} is not whole {CELL} px cells")
        n = self.width * self.height
        self.land = bytearray(n)
        # The crack's width at each of its pixels (0: no crack).
        self.crack = array.array("f", bytes(4 * n))
        # The index of a pixel's ground material in `grounds` (0: the floor's own).
        self.material = bytearray(n)
        # 1 where a pit is (always a hole), and where open ground is a pit's side (a pit, a crack
        # from one): its edges are drawn in the shape's `pit_edge` style.
        self.pit = bytearray(n)
        self.pit_side = bytearray(n)
        self._side = 0
        self.shape = shape
        self.keep_clear = [tuple(c) for c in shape.get("keep_clear", [])] + list(placed or [])
        self.outlines = [outline_points(o) for o in shape.get("outlines", [])]
        for points in self.outlines:
            fill_polygon(self.land, self.width, self.height, points, 1)
        if "frame" in shape:
            self._frame(shape["frame"], clear or [])
        for i, area in enumerate(shape.get("areas", [])):
            area_mask = bytearray(n)
            fill_polygon(area_mask, self.width, self.height, outline_points(area, 3.0), 1)
            for p in range(n):
                if area_mask[p] and self.land[p]:
                    self.material[p] = i + 1
        for spec in shape.get("pits", []):
            mask = bytearray(n)
            fill_polygon(mask, self.width, self.height, outline_points(spec), 1)
            for p in range(n):
                if mask[p]:
                    self.land[p] = 0
                    self.pit[p] = 1
                    self.pit_side[p] = 1
        for crack in shape.get("cracks", []):
            if "pit" in crack:
                self._crack_from_pit(crack)
            else:
                self._crack(crack)

    def _frame(self, spec: dict, clear: list[tuple[float, float, float]]) -> None:
        """A room's floor inside walls: a rounded rectangle `inset` pixels in from the room's border
        (`corner` its corners' radius), its edge wandering by noise (`rough`: the noise's scales,
        largest first; `seed`) up to `wander[0]` pixels in (thicker walls) and `wander[1]` out
        (thinner), held to the plain line along each of its `pins` (`[x0, y0, x1, y1]`: under a door,
        a torch, a narrow way) and easing back to its noise over PIN_EASE pixels; opened into `bays`
        (`[x, y, r]`: rough round alcoves); and pushed back from every circle of `clear` (where the
        room's things stand), outside the pins. The room's outermost cell is always wall."""
        w, h = self.width, self.height
        inset = float(spec["inset"])
        corner = float(spec.get("corner", 16))
        wander_in, wander_out = (float(v) for v in spec["wander"])
        scales = [float(v) for v in spec.get("rough", [40, 14, 5])]
        seed = int(spec.get("seed", 0))
        pins = [tuple(float(v) for v in pin) for pin in spec.get("pins", [])]
        bays = [tuple(float(v) for v in bay) for bay in spec.get("bays", [])]
        cx, cy = w / 2.0, h / 2.0
        hw, hh = w / 2.0 - inset - corner, h / 2.0 - inset - corner
        reach = max(wander_in, wander_out) + 2.0
        for y in range(h):
            for x in range(w):
                p = y * w + x
                if x < CELL or y < CELL or x >= w - CELL or y >= h - CELL:
                    self.land[p] = 0
                    continue
                px, py = x + 0.5, y + 0.5
                qx, qy = abs(px - cx) - hw, abs(py - cy) - hh
                inward = -(math.hypot(max(qx, 0.0), max(qy, 0.0)) + min(max(qx, qy), 0.0) - corner)
                pinned = 1.0
                for x0, y0, x1, y1 in pins:
                    dx = max(x0 - px, 0.0, px - x1)
                    dy = max(y0 - py, 0.0, py - y1)
                    pinned = min(pinned, math.hypot(dx, dy) / PIN_EASE)
                inside = inward > 0.0
                if abs(inward) < reach and pinned > 0.0:
                    n = max(-1.0, min(1.0, (fbm2(px, py, scales, seed) - 0.5) * 2.6))
                    inside = inward + (n * wander_out if n > 0.0 else n * wander_in) * min(1.0, pinned) > 0.0
                if not inside and pinned >= 1.0:
                    for bx, by, br in bays:
                        if math.hypot(px - bx, py - by) + (fbm2(px, py, [12.0, 5.0], seed + 7) - 0.5) * br * 0.6 < br:
                            inside = True
                            break
                if not inside and pinned >= 1.0:
                    inside = any(math.hypot(px - kx, py - ky) < kr for kx, ky, kr in clear)
                if inside:
                    self.land[p] = 1

    def _crack_from_pit(self, spec: dict) -> None:
        """Carve a crack out from the edge of pit `pit`: it starts where a line out from the pit's
        middle at `angle` (in turns, 0 to the right, clockwise) meets land, and wanders outward,
        away from the pit, as an outline's crack wanders in."""
        pit = self.shape["pits"][int(spec["pit"])]
        cx, cy = pit["centre"]
        a = float(spec["angle"]) * math.tau
        x, y = float(cx), float(cy)
        while 0 <= x < self.width and 0 <= y < self.height and not self.land[int(y) * self.width + int(x)]:
            x += math.cos(a)
            y += math.sin(a)
        seed = int(spec.get("seed", 0))
        heading = a + (unit(seed, 3) - 0.5) * 0.4
        self._side = 1
        self._walk(x - math.cos(a) * 4.0, y - math.sin(a) * 4.0, heading, float(spec["width"]), int(spec["length"]), seed, 0)
        self._side = 0

    def _near_keep_clear(self, x: float, y: float) -> bool:
        return any(math.hypot(x - cx, y - cy) < r for cx, cy, r in self.keep_clear)

    def _crack(self, spec: dict) -> None:
        """Carve a crack in from the edge of outline `outline` (default 0): it starts where a line
        out from the outline's middle at `angle` (in turns, 0 to the right, clockwise) leaves the
        land, and wanders back in `width` pixels wide at its mouth, tapering over `length` steps of
        3 px and forking, never into a `keep_clear` circle."""
        outline = self.shape["outlines"][int(spec.get("outline", 0))]
        cx, cy = outline["centre"]
        rx, ry = outline["radii"]
        a = float(spec["angle"]) * math.tau
        x, y = float(cx), float(cy)
        while 0 <= x < self.width and 0 <= y < self.height and self.land[int(y) * self.width + int(x)]:
            x += math.cos(a)
            y += math.sin(a) * ry / rx
        seed = int(spec.get("seed", 0))
        heading = a + math.pi + (unit(seed, 3) - 0.5) * 0.4
        self._walk(x - math.cos(a) * 4.0, y - math.sin(a) * 4.0, heading, float(spec["width"]), int(spec["length"]), seed, 0)

    def _walk(self, x: float, y: float, heading: float, width: float, steps: int, seed: int, depth: int) -> None:
        for i in range(steps):
            heading += math.sin(i * 0.37 + seed) * 0.22 + (unit(seed, i) - 0.5) * 0.25
            x += math.cos(heading) * 3.0
            y += math.sin(heading) * 3.0
            if self._near_keep_clear(x, y) or not (0 <= x < self.width and 0 <= y < self.height):
                return
            if i > 6 and not self.land[int(y) * self.width + int(x)] and self.crack[int(y) * self.width + int(x)] == 0.0:
                return
            w = width * max(0.0, 1.0 - i / steps) ** 1.6
            if w < 1.5:
                return
            self._stamp(x, y, w)
            if depth < 2 and i > 4 and hash32(seed, i, 7) % 26 == 0:
                turn = 0.7 if hash32(seed, i, 8) % 2 else -0.7
                self._walk(x, y, heading + turn, w * 0.9, int((steps - i) * 0.6), seed * 31 + i, depth + 1)

    def _stamp(self, x: float, y: float, w: float) -> None:
        r = w * 0.5
        reach = int(r + 6)
        seed = int(self.shape.get("seed", 0))
        for py in range(max(0, int(y) - reach), min(self.height, int(y) + reach + 1)):
            for px in range(max(0, int(x) - reach), min(self.width, int(x) + reach + 1)):
                d = math.hypot(px + 0.5 - x, py + 0.5 - y)
                if d > r + 5.0:
                    continue
                edge = r
                if w > 6.0:
                    # A wide crack's walls are as rough as the coast's; a thin one is a clean line.
                    edge += min(r * 0.9, 4.0) * 2.0 * (fbm2(px, py, [12.0, 6.0], seed + 310) - 0.5)
                    edge += 1.5 * (fbm2(px, py, [4.0, 2.0], seed + 311) - 0.5)
                if d <= edge:
                    p = py * self.width + px
                    if self.land[p] or self.crack[p] > 0.0:
                        self.land[p] = 0
                        if w > self.crack[p]:
                            self.crack[p] = w
                        if self._side:
                            self.pit_side[p] = 1


# ----------------------------------------------------------------------------------------------
# Drawing


def load_style(edge_id: str) -> dict:
    return json.loads((EDGES / edge_id / "edge.json").read_text(encoding="utf-8"))


def load_ground(ground_id: str) -> dict:
    return json.loads((GROUNDS / ground_id / "ground.json").read_text(encoding="utf-8"))


class Drawing:
    """Everything the generator writes for one shape: three images, the wall cells, the rims and
    the drip lines."""

    def __init__(self, shape: dict, placed: list[tuple[float, float, float]] | None = None,
                 clear: list[tuple[float, float, float]] | None = None) -> None:
        self.mats = materials()
        self.ground = Ground(shape, placed, clear)
        # The edge styles by side: the outlines' (0) and the pits' and their cracks' (1).
        self.style = load_style(shape["edge"])
        self.styles = [self.style, load_style(shape["pit_edge"]) if "pit_edge" in shape else self.style]
        self.deeps = [colour(st["deep"], self.mats) for st in self.styles]
        self.deep = self.deeps[0]
        self.grounds = [load_ground(shape["ground"])] + [load_ground(a["ground"]) for a in shape.get("areas", [])]
        g = self.ground
        self.w, self.h = g.width, g.height
        n = self.w * self.h
        self.side = self._sides()
        fulls = [float(st["full_width"]) for st in self.styles]
        # Solid: what a body may stand on. Land, and a crack too thin for a whole cell.
        self.solid = bytearray(n)
        for p in range(n):
            if g.land[p] or 0.0 < g.crack[p] < CELL:
                self.solid[p] = 1
        self._drop_slivers()
        # t: how much of the whole edge a place has, from the nearest crack's width (1 away from
        # cracks, on the coast and in a crack's wide mouth; toward 0 where a crack narrows).
        near = array.array("f", bytes(4 * n))
        for p in range(n):
            w = g.crack[p]
            if w > 0.0:
                px, py = p % self.w, p // self.w
                for dy in range(-4, 5):
                    for dx in range(-4 + abs(dy), 5 - abs(dy)):
                        x, y = px + dx, py + dy
                        if 0 <= x < self.w and 0 <= y < self.h and near[y * self.w + x] < w:
                            near[y * self.w + x] = w
        self.t = array.array("f", [1.0]) * n
        for p in range(n):
            if near[p] > 0.0:
                full = fulls[self.side[p]]
                self.t[p] = min(1.0, max(0.0, (near[p] - 1.5) / (full - 1.5)))
        self.floor = bytearray(n * 4)
        self.under = bytearray(n * 4)
        self.rims: list[list[tuple[float, float]]] = []
        # The side (its edge style) of each rim in `rims`.
        self.rim_sides: list[int] = []
        # Each drip line: the palette material of the seam band it hangs under, and its points.
        self.drips: list[tuple[str, list[tuple[float, float]]]] = []
        self.drip_sides: list[int] = []
        self.band = array.array("h", [-1]) * n
        self._rim_paths: list[tuple[list[int], int, int]] = []
        self._draw_floor()
        self._trace_rims()
        self._spread_bands()
        self._draw_edges()
        self._draw_under()
        self.glow_w, self.glow_h, self.glow = self._draw_glow()
        self.walls, self.holes = self._grid_rects()
        self.wall_art = self._draw_wall_art()

    def _sides(self) -> bytearray:
        """Which edge style each pixel's nearest edge is drawn in: open ground is its own side (a
        pit's or a crack from one: 1, the void or a wall: 0); ground takes the side of the nearest
        open ground, out to SIDE_REACH pixels (0 beyond)."""
        g = self.ground
        side = bytearray(g.pit_side)
        if not any(g.pit_side):
            return side
        seen = bytearray(self.w * self.h)
        frontier = []
        for p in range(self.w * self.h):
            if not g.land[p]:
                seen[p] = 1
                frontier.append(p)
        for _ in range(SIDE_REACH):
            nxt = []
            for q in frontier:
                x, y = q % self.w, q // self.w
                for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                    if 0 <= nx < self.w and 0 <= ny < self.h:
                        r = ny * self.w + nx
                        if not seen[r]:
                            seen[r] = 1
                            side[r] = side[q]
                            nxt.append(r)
            frontier = nxt
            if not frontier:
                break
        return side

    def _style_at(self, p: int) -> dict:
        return self.styles[self.side[p]]

    def _drop_slivers(self) -> None:
        """Clear every piece of ground that holds no open cell (no cell whose middle is ground): a
        sliver a crack cut loose would be drawn over the walls and given a rim of its own."""
        g = self.ground
        seen = bytearray(self.w * self.h)
        for p0 in range(self.w * self.h):
            if not self.solid[p0] or seen[p0]:
                continue
            piece = [p0]
            seen[p0] = 1
            k = 0
            open_cell = False
            while k < len(piece):
                q = piece[k]
                k += 1
                x, y = q % self.w, q // self.w
                if x % CELL == CELL // 2 and y % CELL == CELL // 2:
                    open_cell = True
                for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                    if 0 <= nx < self.w and 0 <= ny < self.h:
                        r = ny * self.w + nx
                        if self.solid[r] and not seen[r]:
                            seen[r] = 1
                            piece.append(r)
            if not open_cell:
                for q in piece:
                    self.solid[q] = 0
                    g.land[q] = 0

    # -- the floor and its edges --

    def _put(self, image: bytearray, p: int, rgb: tuple[int, int, int], a: int = 255) -> None:
        image[p * 4] = rgb[0]
        image[p * 4 + 1] = rgb[1]
        image[p * 4 + 2] = rgb[2]
        image[p * 4 + 3] = a

    def _draw_floor(self) -> None:
        g = self.ground
        seed = int(g.shape.get("seed", 0))
        noise = ground_materials.Noise(unit, noise1, fbm2)
        centres = [(self.w / 2.0, self.h / 2.0)] + [tuple(a["centre"]) for a in g.shape.get("areas", [])]
        mats = [ground_materials.Material(spec, k, seed, (self.w, self.h), centres[k], lambda c: colour(c, self.mats), noise)
                for k, spec in enumerate(self.grounds)]
        edge_distance = self._edge_distance(max((int(m.edge_reach) for m in mats if m.needs_edge_distance()), default=0))
        for p in range(self.w * self.h):
            if not self.solid[p]:
                continue
            x, y = p % self.w, p // self.w
            if not g.land[p]:
                self._put(self.floor, p, self.deeps[self.side[p]])
                continue
            self._put(self.floor, p, mats[g.material[p]].at(x, y, edge_distance[p] if edge_distance else 1e9))

    def _edge_distance(self, reach: int) -> list[int]:
        """How far each pixel of land is from open ground, out to `reach` pixels (empty for 0)."""
        if reach <= 0:
            return []
        g = self.ground
        dist = [reach + 1] * (self.w * self.h)
        frontier = [p for p in range(self.w * self.h) if self._is_edge(p)]
        for p in frontier:
            dist[p] = 0
        for d in range(1, reach + 1):
            nxt = []
            for q in frontier:
                x, y = q % self.w, q // self.w
                for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                    if 0 <= nx < self.w and 0 <= ny < self.h:
                        r = ny * self.w + nx
                        if g.land[r] and dist[r] > d:
                            dist[r] = d
                            nxt.append(r)
            frontier = nxt
        return dist

    def _is_edge(self, p: int) -> bool:
        """Land with a 4-neighbour that is not land (the void, a crack or the room's border)."""
        if not self.ground.land[p]:
            return False
        x, y = p % self.w, p // self.w
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if not (0 <= nx < self.w and 0 <= ny < self.h) or not self.ground.land[ny * self.w + nx]:
                return True
        return False

    def _trace_rims(self) -> None:
        """The rims: the boundary of each piece of solid ground, traced clockwise on screen (the void
        on the left of the way it runs), a point every few pixels."""
        seen = bytearray(self.w * self.h)
        for p in range(self.w * self.h):
            if not self.solid[p] or seen[p]:
                continue
            x, y = p % self.w, p // self.w
            if y > 0 and self.solid[p - self.w]:
                continue
            # A pixel on a top edge of solid ground not traced yet: trace its boundary.
            path = self._moore(x, y)
            if len(path) < 16:
                for q in path:
                    seen[q] = 1
                continue
            for q in path:
                seen[q] = 1
            # Keep the outer boundaries (a ring traced round a piece of ground) and the rings round a
            # pit; not a ring round any other pond.
            area = 0.0
            for i in range(len(path)):
                x1, y1 = path[i] % self.w, path[i] // self.w
                x2, y2 = path[(i + 1) % len(path)] % self.w, path[(i + 1) % len(path)] // self.w
                area += x1 * y2 - x2 * y1
            side = self.side[p - self.w] if y > 0 else 0
            if not ((area > 0.0 and side == 0) or (area < 0.0 and side == 1)):
                continue
            style = self.styles[side]
            every = int(style.get("rim", {}).get("every", 4))
            self._rim_paths.append((path, every, side))
            if "rim" in style:
                self.rims.append([(path[i] % self.w + 0.5, path[i] // self.w + 0.5) for i in range(0, len(path), every)])
                self.rim_sides.append(side)

    def _moore(self, sx: int, sy: int) -> list[int]:
        """Moore-neighbour tracing of the solid pixels' boundary from the top-edge pixel (sx, sy),
        clockwise on screen."""
        ways = [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)]
        start = sy * self.w + sx
        path = [start]
        x, y = sx, sy
        back = 6  # we came from above (the pixel above is not solid)
        first = -1
        for _ in range(self.w * self.h * 2):
            step = -1
            for k in range(8):
                d = (back + 1 + k) % 8
                nx, ny = x + ways[d][0], y + ways[d][1]
                if 0 <= nx < self.w and 0 <= ny < self.h and self.solid[ny * self.w + nx]:
                    step = d
                    break
            if step < 0:
                break
            # Jacob's stop: back at the start and about to leave it the way it first left, so a
            # start on a one-pixel neck still goes round the whole boundary.
            if y * self.w + x == start and step == first:
                break
            if first < 0:
                first = step
            back = (step + 4) % 8
            x, y = x + ways[step][0], y + ways[step][1]
            if y * self.w + x != start:
                path.append(y * self.w + x)
        return path

    def _spread_bands(self) -> None:
        """Every pixel within reach of a rim takes the colour band of the nearest stretch of rim:
        the rim's own pixels by how far along it they lie, every other by a walk out from them."""
        frontier: list[int] = []
        reach = 0
        for path, every, side in self._rim_paths:
            seam = self.styles[side].get("seam")
            if seam is None:
                continue
            length = float(seam["band_length"])
            count = len(seam["colours"])
            reach = max(reach, int(seam.get("reach", 120)))
            run = 0.0
            last = None
            marks = []
            for i in range(0, len(path), every):
                q = path[i]
                here = (q % self.w + 0.5, q // self.w + 0.5)
                if last is not None:
                    run += math.dist(last, here)
                marks.append(run)
                last = here
            for i, q in enumerate(path):
                band = int(marks[min(i // every, len(marks) - 1)] / length) % count
                if self.band[q] < 0:
                    self.band[q] = band
                    frontier.append(q)
        for _ in range(reach):
            nxt: list[int] = []
            for q in frontier:
                x, y = q % self.w, q // self.w
                b = self.band[q]
                for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                    if 0 <= nx < self.w and 0 <= ny < self.h:
                        r = ny * self.w + nx
                        if self.band[r] < 0 and self.side[r] == self.side[q]:
                            self.band[r] = b
                            nxt.append(r)
            frontier = nxt
            if not frontier:
                break

    def _seam_colour(self, p: int) -> tuple[int, int, int] | None:
        b = self.band[p]
        seam = self._style_at(p).get("seam")
        if b < 0 or seam is None:
            return None
        return self.mats[seam["colours"][b]]

    def _draw_edges(self) -> None:
        """The seam (the edge's own pixels, in its band's shades by t) and the lip inside it (as wide
        as t allows), over the floor, each in its side's edge style; then the lip's pebbles and
        rubble, and the dark foot of a wall's face."""
        g = self.ground
        lips = [([colour(c, self.mats) for c in st["lip"]["shades"]], int(st["lip"]["width"])) for st in self.styles]
        lip_most = max(width for _, width in lips)
        # The distance in from the edge, up to the widest lip, by a walk in from the edges.
        dist = bytearray(self.w * self.h)
        frontier = [p for p in range(self.w * self.h) if self._is_edge(p)]
        for p in frontier:
            dist[p] = 1
        for d in range(2, lip_most + 2):
            nxt = []
            for q in frontier:
                x, y = q % self.w, q // self.w
                for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                    if 0 <= nx < self.w and 0 <= ny < self.h:
                        r = ny * self.w + nx
                        if g.land[r] and not dist[r]:
                            dist[r] = d
                            nxt.append(r)
            frontier = nxt
        self.seam: list[int] = []
        edge_pixels: list[int] = []
        for p in range(self.w * self.h):
            d = dist[p]
            if not d:
                continue
            side = self.side[p]
            lip_cols, lip_width = lips[side]
            t = self.t[p]
            x, y = p % self.w, p // self.w
            roll = unit(x, y, 5051)
            if d == 1:
                edge_pixels.append(p)
            if d == 1 and "seam" in self.styles[side]:
                ramp = self._seam_colour(p)
                if ramp is None:
                    continue
                # Light and base where the edge is whole, base then shadow as a crack narrows.
                if roll < t * 0.5:
                    rgb = ramp[2]
                elif roll < 0.25 + t * 0.75:
                    rgb = ramp[1]
                else:
                    rgb = ramp[0]
                self._put(self.floor, p, rgb)
                self.seam.append(p)
            elif d - 1 <= lip_width * t + 0.2 and t > 0.2:
                self._put(self.floor, p, lip_cols[1] if roll < 0.3 else lip_cols[0])
        for side, style in enumerate(self.styles):
            pebbles = style["lip"].get("pebbles")
            if pebbles:
                self._draw_pebbles(pebbles, [p for p in self.seam if self.side[p] == side])
            rubble = style["lip"].get("rubble")
            if rubble:
                self._draw_rubble(rubble, [p for p in edge_pixels if self.side[p] == side])
            face = style.get("face")
            if face and "foot" in face and side == 0:
                self._draw_foot(face["foot"])

    def _draw_pebbles(self, pebbles: dict, seam: list[int]) -> None:
        g = self.ground
        shades = [colour(c, self.mats) for c in pebbles["shades"]]
        for p in seam:
            if self.t[p] < 0.9 or hash32(p, 6061) % int(pebbles["every"]):
                continue
            x, y = p % self.w, p // self.w
            for dy in range(-6, -3):
                for dx in range(-2, 2):
                    q = (y + dy) * self.w + x + dx
                    if 0 <= y + dy < self.h and 0 <= x + dx < self.w and g.land[q]:
                        inner = -5 <= dy <= -4 and -1 <= dx <= 0
                        self._put(self.floor, q, shades[2] if (inner and dx == -1 and dy == -5) else shades[1] if inner else shades[0])

    def _draw_rubble(self, rubble: dict, edge: list[int]) -> None:
        """Stones and grit fallen along an edge: one every `every` edge pixels (by hash), `sizes`
        pixels across, lying on the land just inside it; each its base colour with a lit top row and
        a dark row under it (`shades`: dark, base, light)."""
        g = self.ground
        dark, base, light = (colour(c, self.mats) for c in rubble["shades"])
        lo, hi = (int(v) for v in rubble["sizes"])
        every = int(rubble["every"])
        for p in edge:
            if self.t[p] < 0.6 or hash32(p, 7071) % every:
                continue
            size = lo + hash32(p, 7072) % (hi - lo + 1)
            x, y = p % self.w, p // self.w
            # Lie inside the edge: step to the land side of the edge pixel.
            for nx, ny in ((x, y + 1), (x + 1, y), (x - 1, y), (x, y - 1)):
                if 0 <= nx < self.w and 0 <= ny < self.h and g.land[ny * self.w + nx] and not self._is_edge(ny * self.w + nx):
                    x, y = nx, ny
                    break
            for dy in range(size + 1):
                for dx in range(size + 1):
                    xx, yy = x + dx, y + dy
                    if not (0 <= xx < self.w and 0 <= yy < self.h) or not g.land[yy * self.w + xx]:
                        continue
                    rgb = dark if dy == size else light if dy == 0 and size > 1 else base
                    if dx == size and dy < size:
                        continue
                    self._put(self.floor, yy * self.w + xx, rgb)

    def _draw_foot(self, foot: list) -> None:
        """The dark foot of a wall's face: the floor right under it, `foot[1]` rows mixed toward
        `foot[0]`, less each row down."""
        g = self.ground
        shade = colour(foot[0], self.mats)
        rows = int(foot[1])
        for p in range(self.w, self.w * self.h):
            if not g.land[p] or g.land[p - self.w] or g.pit[p - self.w] or g.crack[p - self.w] > 0.0:
                continue
            for k in range(rows):
                q = p + k * self.w
                if q >= self.w * self.h or not g.land[q]:
                    break
                old = tuple(self.floor[q * 4:q * 4 + 3])
                self._put(self.floor, q, _mix(old, shade, (rows - k) / (rows + 1)))

    def _draw_under(self) -> None:
        """The rock face under every edge that faces down, hanging into the clear pixels below it:
        as deep as the edge style says (noise along the edge), shallower and darker down a crack as
        it narrows; banded, with roots; its bottom gives off the drips."""
        rocks = []
        for st in self.styles:
            rock = st.get("rock")
            rocks.append(None if rock is None else ([colour(c, self.mats) for c in rock["shades"]], colour(rock["strata"], self.mats),
                                                    colour(rock["roots"], self.mats), rock["depth"]))
        seed = int(self.ground.shape.get("seed", 0)) + 21
        bottoms: dict[int, int] = {}
        # The edge pixel each bottom hangs under (its seam band is the drips' colour).
        edges: dict[int, int] = {}
        for x in range(self.w):
            for y in range(self.h - 1):
                p = y * self.w + x
                if not self.solid[p] or self.solid[p + self.w]:
                    continue
                side = self.side[p + self.w]
                if rocks[side] is None:
                    continue
                shades, strata, root, (lo, hi) = rocks[side]
                deep = self.deeps[side]
                t = self.t[p]
                depth = int((lo + (hi - lo) * noise1(x / 14.0, seed) ** 1.8) * t)
                bottom = y
                for d in range(1, depth + 1):
                    yy = y + d
                    if yy >= self.h:
                        break
                    q = yy * self.w + x
                    if self.solid[q]:
                        break
                    k = noise2(x, yy, 7.0, seed + 1)
                    rgb = shades[1] if k > 0.55 else shades[0]
                    if math.sin((yy + noise1(x / 9.0, seed + 2) * 18.0) / 5.0) > 0.85:
                        rgb = strata
                    rgb = _mix(deep, rgb, t)
                    self._put(self.under, q, rgb)
                    bottom = yy
                if bottom > y and t > 0.6:
                    q = bottom * self.w + x
                    self._put(self.under, q, strata)
                    bottoms[x * self.h + bottom] = q
                    edges[x * self.h + bottom] = p
                    if hash32(x, y, seed) % 7 == 0:
                        length = 6 + hash32(x, y, seed, 2) % 30
                        for d in range(1, length):
                            yy = bottom + d
                            if yy < self.h and not self.solid[yy * self.w + x]:
                                self._put(self.under, yy * self.w + x, root)
        # The drips leave from the rock's bottom: runs of neighbouring columns under one band of the
        # seam, each in that band's colour alone; a line runs right to left, so the left of its way
        # (where a line throws its motes) is down.
        cells = sorted(bottoms)
        runs: list[tuple[int, int, list[tuple[float, float]]]] = []
        last = None
        for key in cells:
            x, y = key // self.h, key % self.h
            band = self.band[edges[key]]
            side = self.side[edges[key] + self.w]
            if last is not None and x == last[0] + 1 and abs(y - last[1]) <= 6 and band == last[2] and side == last[3]:
                runs[-1][2].append((x + 0.5, y + 1.0))
            else:
                runs.append((band, side, [(x + 0.5, y + 1.0)]))
            last = (x, y, band, side)
        self.drips = []
        self.drip_sides = []
        for band, side, run in runs:
            style = self.styles[side]
            if len(run) < 12 or band < 0 or "drip" not in style or "seam" not in style:
                continue
            every = int(style.get("rim", {}).get("every", 4))
            points = run[::every] + ([run[-1]] if (len(run) - 1) % every else [])
            self.drips.append((style["seam"]["colours"][band], points[::-1]))
            self.drip_sides.append(side)

    def _draw_glow(self) -> tuple[int, int, bytearray]:
        """The edges' glow, at half size: every seam pixel adds its band's base colour by its t, blurred
        twice (near and far) and added together."""
        gw, gh = self.w // 2, self.h // 2
        out = [array.array("f", bytes(4 * gw * gh)) for _ in range(3)]
        for side, style in enumerate(self.styles):
            glow = style.get("glow")
            if glow is None or (side == 1 and self.styles[1] is self.styles[0]):
                continue
            acc = [array.array("f", bytes(4 * gw * gh)) for _ in range(3)]
            for p in self.seam:
                if self.styles[self.side[p]] is not style:
                    continue
                ramp = self._seam_colour(p)
                if ramp is None:
                    continue
                k = self.t[p] ** 1.5
                x, y = (p % self.w) // 2, (p // self.w) // 2
                q = y * gw + x
                for c in range(3):
                    acc[c][q] += ramp[1][c] * k / 255.0 * 0.25
            for radius, strength in glow["blurs"]:
                for c in range(3):
                    blurred = _box_blur(_box_blur(acc[c], gw, gh, int(radius), True), gw, gh, int(radius), False)
                    for q in range(gw * gh):
                        out[c][q] += blurred[q] * float(strength)
        image = bytearray(gw * gh * 4)
        for q in range(gw * gh):
            r, g, b = out[0][q], out[1][q], out[2][q]
            a = min(1.0, max(r, g, b))
            if a < 1.0 / 255.0:
                continue
            image[q * 4] = min(255, round(r / a * 255))
            image[q * 4 + 1] = min(255, round(g / a * 255))
            image[q * 4 + 2] = min(255, round(b / a * 255))
            image[q * 4 + 3] = round(a * 255)
        return gw, gh, image

    def _grid_rects(self) -> tuple[list[tuple[int, int, int, int]], list[tuple[int, int, int, int]]]:
        """The walls and the holes: every cell whose middle pixel is not solid is open; an open cell
        in a crack, or any open cell where the shape's `void` is `"hole"`, is a hole, the rest walls.
        Each merged into rectangles (`_merge`)."""
        cols, rows = self.w // CELL, self.h // CELL
        void_holes = self.ground.shape.get("void", "wall") == "hole"
        walls = [[False] * cols for _ in range(rows)]
        holes = [[False] * cols for _ in range(rows)]
        for r in range(rows):
            for c in range(cols):
                middle = (r * CELL + CELL // 2) * self.w + c * CELL + CELL // 2
                if self.solid[middle]:
                    continue
                if void_holes or self.ground.crack[middle] > 0.0 or self.ground.pit[middle]:
                    holes[r][c] = True
                else:
                    walls[r][c] = True
        return self._merge(walls), self._merge(holes)

    def _draw_wall_art(self) -> bytearray | None:
        """The walls' own art (their top and face, ground_walls.py) where the void is wall and the
        outlines' edge style draws them; None when it does not."""
        g = self.ground
        if g.shape.get("void", "wall") == "hole" or not ("top" in self.style or "face" in self.style):
            return None
        wall = bytearray(self.w * self.h)
        for p in range(self.w * self.h):
            if not self.solid[p] and g.crack[p] == 0.0 and not g.pit[p]:
                wall[p] = 1
        return ground_walls.draw(self.w, self.h, self.solid, wall, self.style, lambda c: colour(c, self.mats), noise2,
                                 int(g.shape.get("seed", 0)) + 61)

    @staticmethod
    def _merge(wall: list[list[bool]]) -> list[tuple[int, int, int, int]]:
        """The cells marked in `wall` merged into rectangles (runs along a row, then runs of the same
        span down the rows), as (x, y, w, h) in pixels."""
        rows = len(wall)
        cols = len(wall[0]) if rows else 0
        open_runs: dict[tuple[int, int], list[int]] = {}
        rects: list[tuple[int, int, int, int]] = []
        for r in range(rows + 1):
            runs = set()
            if r < rows:
                c = 0
                while c < cols:
                    if wall[r][c]:
                        start = c
                        while c < cols and wall[r][c]:
                            c += 1
                        runs.add((start, c))
                    else:
                        c += 1
            for span in list(open_runs):
                if span not in runs:
                    top, height = open_runs.pop(span)
                    rects.append((span[0] * CELL, top * CELL, (span[1] - span[0]) * CELL, height * CELL))
            for span in runs:
                if span in open_runs:
                    open_runs[span][1] += 1
                else:
                    open_runs[span] = [r, 1]
        rects.sort(key=lambda rect: (rect[1], rect[0]))
        return rects


def _bilinear(grid: list[float], cols: int, fx: float, fy: float) -> float:
    ix, iy = int(fx), int(fy)
    tx, ty = fx - ix, fy - iy
    i = iy * cols + ix
    return (grid[i] * (1.0 - tx) + grid[i + 1] * tx) * (1.0 - ty) + (grid[i + cols] * (1.0 - tx) + grid[i + cols + 1] * tx) * ty


def _box_blur(src: array.array, w: int, h: int, radius: int, along_rows: bool) -> array.array:
    out = array.array("f", bytes(4 * w * h))
    span = 2 * radius + 1
    if along_rows:
        for y in range(h):
            row = y * w
            total = 0.0
            for x in range(-radius, radius + 1):
                if 0 <= x < w:
                    total += src[row + x]
            for x in range(w):
                out[row + x] = total / span
                if x - radius >= 0:
                    total -= src[row + x - radius]
                if x + radius + 1 < w:
                    total += src[row + x + radius + 1]
    else:
        for x in range(w):
            total = 0.0
            for y in range(-radius, radius + 1):
                if 0 <= y < h:
                    total += src[y * w + x]
            for y in range(h):
                out[y * w + x] = total / span
                if y - radius >= 0:
                    total -= src[(y - radius) * w + x]
                if y + radius + 1 < h:
                    total += src[(y + radius + 1) * w + x]
    return out


# ----------------------------------------------------------------------------------------------
# Writing


def inputs_hash(shape_path: Path) -> str:
    """The hash of everything a shape's ground is made from: the shape, where the room's things stand
    (`placements`, `clear_points`), its edge styles, its ground materials, the palette and this
    generator with its two modules."""
    shape = json.loads(shape_path.read_text(encoding="utf-8"))
    digest = hashlib.sha256()
    digest.update(f"ground_shape {VERSION}\n".encode())
    digest.update(Path(__file__).read_bytes())
    digest.update(Path(ground_materials.__file__).read_bytes())
    digest.update(Path(ground_walls.__file__).read_bytes())
    digest.update(shape_path.read_bytes())
    digest.update(repr(placements(shape_path)).encode())
    digest.update(repr(clear_points(shape_path)).encode())
    for edge in [shape["edge"]] + ([shape["pit_edge"]] if "pit_edge" in shape else []):
        digest.update((EDGES / edge / "edge.json").read_bytes())
    for ground in [shape["ground"]] + [a["ground"] for a in shape.get("areas", [])]:
        digest.update((GROUNDS / ground / "ground.json").read_bytes())
    digest.update(PALETTE.read_bytes())
    return digest.hexdigest()[:16]


# Where a room's ground art goes: art lives under art/ (content/rooms/README.md: rooms hold layout).
ART = ROOT / "art/grounds"


def outputs_of(shape_path: Path) -> dict[str, Path]:
    """The scene beside the shape file, its art in art/grounds/<room>/."""
    stem = shape_path.name.removesuffix(".shape.json")
    art = ART / stem
    return {
        "scene": shape_path.parent / f"{stem}_ground.tscn",
        "floor": art / f"{stem}_ground_floor.png",
        "under": art / f"{stem}_ground_under.png",
        "glow": art / f"{stem}_ground_glow.png",
        "wall": art / f"{stem}_ground_wall.png",
    }


def res_path(path: Path) -> str:
    return "res://" + path.resolve().relative_to(ROOT).as_posix()


def _vec(points: list[tuple[float, float]]) -> str:
    return ", ".join(f"{_num(x)}, {_num(y)}" for x, y in points)


def _num(value: float) -> str:
    return str(int(value)) if float(value).is_integer() else f"{value:.1f}"


def scene_text(drawing: Drawing, outs: dict[str, Path], digest: str) -> str:
    sizes = sorted({(w, h) for _, _, w, h in drawing.walls + drawing.holes})
    shape_ids = {size: f"Box_{size[0]}x{size[1]}" for size in sizes}
    wall_art = drawing.wall_art is not None
    steps = 5 + len(drawing.rims) + len(drawing.drips) + len(sizes) + (1 if wall_art else 0)
    lines = [f"[gd_scene load_steps={steps} format=3]", ""]
    lines.append(f'[ext_resource type="Texture2D" path="{res_path(outs["floor"])}" id="1_floor"]')
    lines.append(f'[ext_resource type="Texture2D" path="{res_path(outs["under"])}" id="2_under"]')
    lines.append(f'[ext_resource type="Texture2D" path="{res_path(outs["glow"])}" id="3_glow"]')
    lines.append('[ext_resource type="Script" path="res://core/base/mote_source.gd" id="4_motes"]')
    if wall_art:
        lines.append(f'[ext_resource type="Texture2D" path="{res_path(outs["wall"])}" id="5_wall"]')
    lines.append("")
    lines += ['[sub_resource type="CanvasItemMaterial" id="GlowAdd"]', "blend_mode = 1", ""]
    for i, (points, side) in enumerate(zip(drawing.rims, drawing.rim_sides)):
        style = drawing.styles[side]
        rim = style["rim"]
        length = sum(math.dist(points[k], points[(k + 1) % len(points)]) for k in range(len(points)))
        lines += [f'[sub_resource type="Resource" id="MoteSource_rim{i + 1}"]', 'script = ExtResource("4_motes")',
                  f'kind = &"{rim["kind"]}"', f"rate = {length / 100.0 * float(rim['per_100px']):.1f}", "from = 1"]
        if "colours" in rim:
            # The rim's own colours, at random along it (not the seam's bands).
            colours = ", ".join(f'&"{c}"' for c in rim["colours"])
            lines.append(f"colours = Array[StringName]([{colours}])")
        elif "seam" in style:
            colours = ", ".join(f'&"{c}"' for c in style["seam"]["colours"])
            lines += [f"colours = Array[StringName]([{colours}])", f"band_length = {_num(float(style['seam']['band_length']))}"]
        lines.append("")
    for i, ((material, points), side) in enumerate(zip(drawing.drips, drawing.drip_sides)):
        drip = drawing.styles[side]["drip"]
        length = sum(math.dist(points[k], points[k + 1]) for k in range(len(points) - 1))
        lines += [f'[sub_resource type="Resource" id="MoteSource_drip{i + 1}"]', 'script = ExtResource("4_motes")',
                  f'kind = &"{drip["kind"]}"', f"rate = {max(0.1, length / 100.0 * float(drip['per_100px'])):.1f}", "from = 1",
                  f'colours = Array[StringName]([&"{material}"])', ""]
    for size in sizes:
        lines += [f'[sub_resource type="RectangleShape2D" id="{shape_ids[size]}"]', f"size = Vector2({size[0]}, {size[1]})", ""]
    lines += ['[node name="Floor" type="Sprite2D"]', f"z_index = {FLOOR_Z}", "texture_filter = 1", 'texture = ExtResource("1_floor")',
              "centered = false", f'metadata/ground_inputs = "{digest}"', ""]
    lines += ['[node name="Glow" type="Sprite2D" parent="."]', 'material = SubResource("GlowAdd")', "z_as_relative = false",
              f"z_index = {GLOW_Z}", "texture_filter = 2", "scale = Vector2(2, 2)", 'texture = ExtResource("3_glow")', "centered = false", ""]
    if drawing.walls:
        lines += ['[node name="Walls" type="StaticBody2D" parent="."]', f"collision_layer = {WALL_LAYER}", "collision_mask = 0", ""]
    if wall_art:
        # The walls' own art, on their body, so a hit on a wall sheds its colours.
        lines += ['[node name="WallArt" type="Sprite2D" parent="Walls"]', "z_as_relative = false", f"z_index = {FLOOR_Z}",
                  "texture_filter = 1", 'texture = ExtResource("5_wall")', "centered = false", ""]
    # The rock face hangs into the void: on the walls' body where the void is wall and no pit's
    # shaft is among it (a hit on a wall sheds it), else on the root.
    on_walls = drawing.ground.shape.get("void", "wall") != "hole" and drawing.walls and not any(drawing.ground.pit_side)
    under_parent = "Walls" if on_walls else "."
    lines += [f'[node name="Underside" type="Sprite2D" parent="{under_parent}"]', "z_as_relative = false", f"z_index = {FLOOR_Z}",
              "texture_filter = 1", 'texture = ExtResource("2_under")', "centered = false", ""]
    for i, (x, y, w, h) in enumerate(drawing.walls):
        lines += [f'[node name="W{i + 1}" type="CollisionShape2D" parent="Walls"]', f"position = Vector2({_num(x + w / 2)}, {_num(y + h / 2)})",
                  f'shape = SubResource("{shape_ids[(w, h)]}")', ""]
    if drawing.holes:
        lines += ['[node name="Holes" type="StaticBody2D" parent="."]', f"collision_layer = {HOLE_LAYER}", "collision_mask = 0", ""]
    for i, (x, y, w, h) in enumerate(drawing.holes):
        lines += [f'[node name="H{i + 1}" type="CollisionShape2D" parent="Holes"]', f"position = Vector2({_num(x + w / 2)}, {_num(y + h / 2)})",
                  f'shape = SubResource("{shape_ids[(w, h)]}")', ""]
    for i, points in enumerate(drawing.rims):
        name = "Rim" if i == 0 else f"Rim{i + 1}"
        lines += [f'[node name="{name}" type="Line2D" parent="." groups=["mote_source"]]', "visible = false", "closed = true",
                  f"points = PackedVector2Array({_vec(points)})", f'metadata/mote_source = SubResource("MoteSource_rim{i + 1}")', ""]
    for i, (_, points) in enumerate(drawing.drips):
        lines += [f'[node name="Drip{i + 1}" type="Line2D" parent="." groups=["mote_source"]]', "visible = false",
                  f"points = PackedVector2Array({_vec(points)})", f'metadata/mote_source = SubResource("MoteSource_drip{i + 1}")', ""]
    return "\n".join(lines)


def draw(shape_path: Path) -> "Drawing":
    """The drawing of the shape file `shape_path`, with the room's placements kept clear."""
    return Drawing(json.loads(shape_path.read_text(encoding="utf-8")), placements(shape_path), clear_points(shape_path))


def files_of(drawing: "Drawing", shape_path: Path) -> dict[str, bytes]:
    """The bytes of every file the ground of `shape_path` is, by what it is (as `generate` writes them)."""
    outs = outputs_of(shape_path)
    found = {
        "floor": png(drawing.w, drawing.h, drawing.floor),
        "under": png(drawing.w, drawing.h, drawing.under),
        "glow": png(drawing.glow_w, drawing.glow_h, drawing.glow),
        "scene": scene_text(drawing, outs, inputs_hash(shape_path)).encode("utf-8"),
    }
    if drawing.wall_art is not None:
        found["wall"] = png(drawing.w, drawing.h, drawing.wall_art)
    for kind, data in found.items():
        if len(data) > MOST_BYTES:
            raise ValueError(f"{outs[kind].name} would be {len(data)} bytes, over the {MOST_BYTES} a file may be (AGENTS.md, hard rule 3)")
    return found


def generate(shape_path: Path) -> dict[str, Path]:
    """Write the ground of the shape file `shape_path`; the files written, by what they are."""
    drawing = draw(shape_path)
    outs = outputs_of(shape_path)
    outs["floor"].parent.mkdir(parents=True, exist_ok=True)
    written = files_of(drawing, shape_path)
    for kind, data in written.items():
        outs[kind].write_bytes(data)
    if "wall" not in written and outs["wall"].exists():
        outs["wall"].unlink()
    return {kind: outs[kind] for kind in written}


def shape_files() -> list[Path]:
    return sorted((ROOT / "content").rglob("*.shape.json"))


def stale(shape_path: Path) -> str | None:
    """Why the ground of `shape_path` is out of date (None when it is up to date)."""
    scene = outputs_of(shape_path)["scene"]
    if not scene.exists():
        return f"{scene.relative_to(ROOT)} is missing"
    match = re.search(r'metadata/ground_inputs = "([0-9a-f]+)"', scene.read_text(encoding="utf-8"))
    if match is None or match.group(1) != inputs_hash(shape_path):
        return f"{scene.relative_to(ROOT)} is older than its shape, edge style, ground materials or the generator"
    kinds = ["floor", "under", "glow"] + (["wall"] if "_ground_wall.png" in scene.read_text(encoding="utf-8") else [])
    for kind in kinds:
        if not outputs_of(shape_path)[kind].exists():
            return f"{outputs_of(shape_path)[kind].relative_to(ROOT)} is missing"
    return None


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("shapes", nargs="*", type=Path, help="shape files to draw (default with --check: every one)")
    parser.add_argument("--check", action="store_true", help="write nothing; fail when a room's ground is out of date")
    args = parser.parse_args(argv)
    if args.check:
        problems = [f"{path.relative_to(ROOT)}: {why}" for path in (args.shapes or shape_files()) if (why := stale(path.resolve()))]
        for problem in problems:
            print(problem, file=sys.stderr)
        if problems:
            print("Run python3 tools/ground_shape.py <shape file> to draw it again.", file=sys.stderr)
        return 1 if problems else 0
    if not args.shapes:
        parser.error("name the shape files to draw")
    for path in args.shapes:
        outs = generate(path.resolve())
        print("wrote " + ", ".join(str(p.relative_to(ROOT)) for p in outs.values()))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
