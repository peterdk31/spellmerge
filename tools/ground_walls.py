"""A wall's own art, drawn per pixel where a room's void is wall (content/edges/README.md, `top` and
`face`; docs/milestones/crypt-rework.md, "Built for every room"). Used by tools/ground_shape.py,
which says which pixels are wall and which are floor; this says what the wall looks like there:

- **its face**, on the wall the camera looks at: every wall pixel with floor below it within the
  face's `height` (the wall above, the floor below), in courses of masonry `course` pixels high and
  blocks `block` wide (every other course offset half a block), from `shades[0]` at its foot to
  `shades[1]` at its top, a lit line along its top (`light`) under a dark `cap`;
- **its top**, every other wall pixel: rough stone in `shades`, flecked with `joint` where fine noise
  is low, a lit `rim` along the floor's edge where no face is, falling into `deep` from `fade[0]` to
  `fade[1]` pixels away from the floor, so the room reads as dug into the dark.

Python 3.10 and the standard library only (tools/README.md); the same inputs give the same pixels.
"""

from __future__ import annotations

from typing import Callable

Colour = tuple[int, int, int]


def draw(w: int, h: int, floor: bytearray, wall: bytearray, style: dict, colour: Callable[[str], Colour],
         noise2: Callable[[float, float, float, int], float], seed: int) -> bytearray:
    """The wall art as RGBA (clear where nothing is drawn): `floor` marks the pixels a body stands on,
    `wall` the pixels of wall to draw (1), `style` the edge style (its `top` and `face`)."""
    image = bytearray(w * h * 4)
    top = style.get("top")
    face = style.get("face")
    if top is None and face is None:
        return image
    face_of = _face_rows(w, h, floor, wall, int(face["height"])) if face else bytearray(w * h)
    if face is not None:
        _draw_face(image, w, h, face_of, face, colour, noise2, seed)
    if top is not None:
        _draw_top(image, w, h, floor, wall, face_of, top, colour, noise2, seed)
    return image


def _face_rows(w: int, h: int, floor: bytearray, wall: bytearray, height: int) -> bytearray:
    """For each wall pixel, how far above the floor it is when floor lies right below it within
    `height` pixels (1 at the floor's line); 0 elsewhere. One more row (`height` + 1) is the cap."""
    rows = bytearray(w * h)
    for p in range(w, w * h):
        if not floor[p] or not wall[p - w]:
            continue
        # The floor's top edge: the wall above it is the face, up to its height and a cap.
        x, y = p % w, p // w
        for k in range(1, height + 2):
            yy = y - k
            if yy < 0 or not wall[yy * w + x]:
                break
            rows[yy * w + x] = k
    return rows


def _draw_face(image: bytearray, w: int, h: int, rows: bytearray, face: dict, colour: Callable[[str], Colour],
               noise2: Callable[[float, float, float, int], float], seed: int) -> None:
    height = int(face["height"])
    course = int(face["course"])
    block = int(face["block"])
    low, high = (colour(c) for c in face["shades"])
    joint = colour(face["joint"])
    light = colour(face["light"])
    cap = colour(face["cap"])
    for p in range(w * h):
        k = rows[p]
        if not k:
            continue
        x = p % w
        if k == height + 1:
            rgb = cap
        elif k == height:
            rgb = light
        else:
            row = (k - 1) // course
            if (k - 1) % course == course - 1 or (x + row * (block // 2)) % block == 0:
                rgb = joint
            else:
                # Each block a shade of its own, the face darker toward its top.
                n = noise2(x // block * block + row * 7, row, 3.0, seed + 41)
                rgb = _mix(low, high, min(1.0, (k - 1) / height * 0.8 + n * 0.3))
        _put(image, p, rgb)


def _draw_top(image: bytearray, w: int, h: int, floor: bytearray, wall: bytearray, rows: bytearray, top: dict,
              colour: Callable[[str], Colour], noise2: Callable[[float, float, float, int], float], seed: int) -> None:
    dark, stone = (colour(c) for c in top["shades"])
    joint = colour(top["joint"])
    rim = colour(top["rim"])
    deep = colour(top["deep"])
    near, far = (float(v) for v in top["fade"])
    # How far each wall pixel is from the floor, by a walk out from the floor's edge.
    dist = [0] * (w * h)
    frontier = [p for p in range(w * h) if wall[p] and _touches(floor, w, h, p)]
    for p in frontier:
        dist[p] = 1
    d = 1
    while frontier and d < far + 2:
        d += 1
        nxt = []
        for q in frontier:
            x, y = q % w, q // w
            for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if 0 <= nx < w and 0 <= ny < h:
                    r = ny * w + nx
                    if wall[r] and not dist[r]:
                        dist[r] = d
                        nxt.append(r)
        frontier = nxt
    for p in range(w * h):
        if not wall[p] or rows[p]:
            continue
        x, y = p % w, p // w
        dd = dist[p] or int(far) + 2
        if dd == 1:
            rgb = rim
        else:
            fine = noise2(x, y, 3.0, seed + 51)
            rough = noise2(x, y, 9.0, seed + 52)
            rgb = joint if fine < 0.28 else _mix(dark, stone, rough)
        fade = min(1.0, max(0.0, (dd - near) / max(1.0, far - near)))
        _put(image, p, _mix(rgb, deep, fade))


def _touches(floor: bytearray, w: int, h: int, p: int) -> bool:
    x, y = p % w, p // w
    for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
        if 0 <= nx < w and 0 <= ny < h and floor[ny * w + nx]:
            return True
    return False


def _put(image: bytearray, p: int, rgb: Colour) -> None:
    image[p * 4] = rgb[0]
    image[p * 4 + 1] = rgb[1]
    image[p * 4 + 2] = rgb[2]
    image[p * 4 + 3] = 255


def _mix(a: Colour, b: Colour, t: float) -> Colour:
    return (round(a[0] + (b[0] - a[0]) * t), round(a[1] + (b[1] - a[1]) * t), round(a[2] + (b[2] - a[2]) * t))
