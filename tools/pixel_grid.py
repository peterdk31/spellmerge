#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
# SPDX-License-Identifier: GPL-3.0-or-later
"""Pixel art from a grid of characters (props W7, docs/milestones/props.md, "Art from a grid").

A grid file (`<name>.grid.json`, kept beside the art it makes) says what each character is and
draws the picture one row a line:

    {
      "colours": {"o": "#14121f", "s": "#7a7694", "b": "#4a4663"},
      "motes": "*",
      "rows": [
        "..oooo..",
        ".osssbo.",
        ...
      ]
    }

- `colours`: a character to a palette colour (docs/STYLE.md, "Palette"); `.` and space are
  always empty.
- `motes`: the characters that mark a mote point (`*` when it is left out). A mote character with
  a colour is drawn in the art too; one without is empty there.
- Every row is as long as the first; the picture's width and height are each a multiple of 8.

It writes `<name>.svg` (rects only, one per run of a colour along a row, whole numbers, palette
colours: what tests/core/test_svg_art.gd checks) and, when the grid has mote points,
`<name>_motes.svg`: the points alone in Bone light, the same size, for a prop's look to give off
motes from (a hidden layer with a mask `MoteSource`, core/base/mote_source.gd). So a prop's art and
where its motes come from are one source.

    tools/pixel_grid.py content/props/brazier/lit.grid.json      # writes lit.svg, lit_motes.svg
    tools/pixel_grid.py --check content/props/brazier/lit.grid.json   # fails if the SVGs differ
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STYLE = ROOT / "docs/STYLE.md"
EMPTY = {".", " "}
DEFAULT_MOTES = "*"
# The colour a mote point is drawn in, in its mask: Bone light.
MOTE_COLOUR = "#f4f1ea"
GRID = 8
SUFFIX = ".grid.json"


class GridError(ValueError):
    """A grid that cannot be drawn, with what is wrong in words."""


def palette(style: Path = STYLE) -> set[str]:
    """The palette colours of docs/STYLE.md (its "Palette" section's table), lower case."""
    text = style.read_text(encoding="utf-8")
    start = text.index("## Palette")
    end = text.find("\n## ", start + 1)
    section = text[start:end if end >= 0 else len(text)]
    found: set[str] = set()
    for line in section.splitlines():
        if line.startswith("|"):
            found.update(c.lower() for c in re.findall(r"#[0-9a-fA-F]{6}\b", line))
    return found


def read(grid: dict, colours_allowed: set[str]) -> tuple[list[str], dict[str, str], set[str]]:
    """The rows, the colours by character and the mote characters of `grid`, checked."""
    rows = grid.get("rows")
    if not isinstance(rows, list) or not rows or not all(isinstance(r, str) for r in rows):
        raise GridError("rows must be a list of strings")
    width = len(rows[0])
    for i, row in enumerate(rows):
        if len(row) != width:
            raise GridError(f"row {i} is {len(row)} long, not {width} like the first")
    if width % GRID or len(rows) % GRID:
        raise GridError(f"the picture is {width}x{len(rows)}; each side a multiple of {GRID}")
    colours = {str(k): str(v).lower() for k, v in (grid.get("colours") or {}).items()}
    for char, colour in colours.items():
        if len(char) != 1 or char in EMPTY:
            raise GridError(f"'{char}' cannot be a colour's character (one character, not '.' or space)")
        if colour not in colours_allowed:
            raise GridError(f"'{char}' is {colour}, which is not a palette colour (docs/STYLE.md)")
    motes = set(str(grid.get("motes", DEFAULT_MOTES)))
    for i, row in enumerate(rows):
        for x, char in enumerate(row):
            if char not in EMPTY and char not in colours and char not in motes:
                raise GridError(f"row {i}, column {x}: '{char}' is neither a colour nor a mote point")
    return rows, colours, motes


def runs(rows: list[str], colour_of) -> list[tuple[int, int, int, str]]:
    """Each run of one colour along a row: (x, y, width, colour), in reading order."""
    found = []
    for y, row in enumerate(rows):
        x = 0
        while x < len(row):
            colour = colour_of(row[x])
            if colour is None:
                x += 1
                continue
            start = x
            while x < len(row) and colour_of(row[x]) == colour:
                x += 1
            found.append((start, y, x - start, colour))
    return found


def svg(width: int, height: int, rects: list[tuple[int, int, int, str]]) -> str:
    lines = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}" shape-rendering="crispEdges">']
    for x, y, w, colour in rects:
        lines.append(f'  <rect x="{x}" y="{y}" width="{w}" height="1" fill="{colour}"/>')
    lines.append("</svg>")
    return "\n".join(lines) + "\n"


def draw(grid: dict, colours_allowed: set[str]) -> tuple[str, str | None]:
    """The art's SVG, and its mote points' SVG (None when it has none)."""
    rows, colours, motes = read(grid, colours_allowed)
    width, height = len(rows[0]), len(rows)
    art = svg(width, height, runs(rows, lambda c: colours.get(c)))
    points = runs(rows, lambda c: MOTE_COLOUR if c in motes else None)
    return art, (svg(width, height, points) if points else None)


def outputs(path: Path) -> tuple[Path, Path]:
    """Where a grid file's art and mote points go: `<name>.svg` and `<name>_motes.svg`."""
    if not path.name.endswith(SUFFIX):
        raise GridError(f"{path} is not a {SUFFIX} file")
    stem = path.name[: -len(SUFFIX)]
    return path.with_name(stem + ".svg"), path.with_name(stem + "_motes.svg")


def build(path: Path, check: bool = False, colours_allowed: set[str] | None = None) -> list[str]:
    """Write (or with `check`, compare) the SVGs of the grid file `path`; the problems, in words."""
    allowed = colours_allowed if colours_allowed is not None else palette()
    try:
        art, points = draw(json.loads(path.read_text(encoding="utf-8")), allowed)
    except (GridError, json.JSONDecodeError) as error:
        return [f"{path}: {error}"]
    art_path, motes_path = outputs(path)
    wanted = {art_path: art, motes_path: points}
    problems = []
    for target, text in wanted.items():
        if check:
            have = target.read_text(encoding="utf-8") if target.exists() else None
            if have != text:
                problems.append(f"{target} differs from {path.name}: run tools/pixel_grid.py {path}")
        elif text is None:
            target.unlink(missing_ok=True)
        else:
            target.write_text(text, encoding="utf-8")
    return problems


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("grids", nargs="+", type=Path, help="grid files (<name>.grid.json)")
    parser.add_argument("--check", action="store_true", help="compare, write nothing")
    args = parser.parse_args(argv)
    allowed = palette()
    problems = []
    for path in args.grids:
        problems += build(path, args.check, allowed)
    for line in problems:
        print(line, file=sys.stderr)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
