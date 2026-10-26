#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
# SPDX-License-Identifier: GPL-3.0-or-later
"""Writes the Spell atlas data (#245): one entry per component, combo and reaction, read from the content.

  python3 tools/atlas.py <out>        e.g. build/clips/atlas.json (ci/build/build.sh --clips does this)

The format is {"entries": [...]} as read by ci/smbot/clips.py: {"id", "kind", "name", "description",
"does", "clips": [clip ids], "source": "repo/path"}. Nothing is listed by hand: a new component
folder, combo file or reaction row is a new entry. The clip ids are the ones tests/clips/scenarios.gd
gives (`combo_<id>`, `<kind>_<id>`, `reaction_<id>` and `reaction_<id>_coop`). `source` is the file
that defines the entry (not the last one that changed it); the page links it to its history.

Standard library only; reads the repository, writes only <out>.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SPELLS = "content/spells"
COMBOS = f"{SPELLS}/combos"  # one JSON file per combo, named like its id
REACTIONS = f"{SPELLS}/reactions.tres"
LORE = "content/story/lore/components"
# The folder of each component kind under content/spells/.
KIND_FOLDERS = {"form": "forms", "element": "elements", "modifier": "modifiers", "trigger": "triggers"}
KIND_ORDER = ("form", "element", "modifier", "trigger", "combo", "reaction")
# ReactionRow.Effect, in the order of the enum in core/base/reaction_row.gd.
EFFECTS = ("burst", "consume", "extend", "spread")
STATUS_WORDS = {"burn": "burning", "chill": "chilled", "shock": "shocked", "hex": "hexed"}


def _value(text: str, key: str, default: str = "") -> str:
    """The value of `key = ...` in a .tres block, without the &"" or "" around a string."""
    match = re.search(rf"^{key} = (.+)$", text, re.MULTILINE)
    if not match:
        return default
    raw = match.group(1).strip()
    if raw.startswith('&"') and raw.endswith('"'):
        return raw[2:-1]
    if raw.startswith('"') and raw.endswith('"'):
        return raw[1:-1]
    return raw


def _number(text: str, key: str) -> float:
    try:
        return float(_value(text, key, "0"))
    except ValueError:
        return 0.0


def _lore(root: Path) -> dict[str, str]:
    """Builder descriptions by component id."""
    out: dict[str, str] = {}
    for path in sorted((root / LORE).glob("*.json")):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if isinstance(data, dict) and isinstance(data.get("id"), str) and isinstance(data.get("text"), str):
            out[data["id"]] = data["text"]
    return out


def components(root: Path) -> list[dict]:
    """Every component file with an id, like the registry's scan. Demo or not: the recorder runs
    with demo_only off, so it records them all. The name must agree with `Spells.component_name`
    (display_name, else the id as it is), because the recorder titles its clips with it."""
    lore = _lore(root)
    rows: list[dict] = []
    for kind, folder in KIND_FOLDERS.items():
        for path in sorted((root / SPELLS / folder).rglob("*.tres")):
            try:
                text = path.read_text(encoding="utf-8")
            except (OSError, UnicodeDecodeError):
                continue  # unreadable, so the registry can't load it either
            comp_id = _value(text, "id")
            if not comp_id:
                continue
            rows.append({"id": comp_id, "kind": kind, "name": _value(text, "display_name", comp_id),
                         "description": lore.get(comp_id, ""), "does": "", "clips": [f"{kind}_{comp_id}"],
                         "source": path.relative_to(root).as_posix()})
    return rows


def combos(root: Path) -> list[dict]:
    rows = []
    for path in sorted((root / COMBOS).glob("*.json")):
        try:
            combo = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if isinstance(combo, dict) and isinstance(combo.get("id"), str):
            rows.append({"id": combo["id"], "kind": "combo", "name": str(combo.get("name", combo["id"])),
                         "description": "", "does": str(combo.get("does", "")),
                         "clips": [f"combo_{combo['id']}"], "source": path.relative_to(root).as_posix()})
    return rows


def _reaction_does(pair: list[dict]) -> str:
    """A plain sentence for a reaction, from its rows (a pair reacts both ways). Rows that do the
    same thing share a sentence; a row that differs gets its own."""
    groups: dict[str, list[str]] = {}
    for row in pair:
        groups.setdefault(_row_effect(row), []).append(_row_trigger(row))
    sentences = []
    for effect, triggers in groups.items():
        trigger = " or ".join(triggers)
        sentences.append(f"{trigger}: {effect}.")
    return " ".join(sentences)


def _row_trigger(row: dict) -> str:
    return f"{str(row['element']).capitalize()} on {STATUS_WORDS.get(row['status'], row['status'])}"


def _row_effect(row: dict) -> str:
    """What one row does, as a phrase. The wording of each effect copies what the game does with
    it; core/base/reaction_row.gd and the combat code are the source of truth, so change this
    with them (test_atlas.py has one test per effect)."""
    effect = EFFECTS[row["effect"]] if 0 <= row["effect"] < len(EFFECTS) else "burst"
    damage = int(row["damage"])
    if effect == "burst":
        text = "bursts"
        if damage:
            text += f" for {damage} damage"
        if row["radius"]:
            text += f" within {row['radius']:g} pixels"
        if row["pull"]:
            text += ", pulling targets in"
        if row["consume"]:
            text += ", using up the status"
        return text
    if effect == "consume":
        return f"uses up the status for {damage} bonus damage (doubled while the target is frozen)"
    if effect == "extend":
        seconds = f"{row['duration']:g}"
        if row["status"] == "chill":  # reaction_row.gd: for chill, EXTEND is a freeze
            text = f"freezes the target for {seconds} seconds (or keeps it frozen that much longer)"
        else:
            word = STATUS_WORDS.get(row["status"], row["status"])
            text = f"extends the {word} status by {seconds} seconds"
            if row["strength"]:
                text += f" and its strength by {row['strength']:g}"
        if damage:
            text += f", dealing {damage} damage"
        return text
    return f"spreads the status to other targets within {row['radius']:g} pixels"


def reactions(root: Path) -> list[dict]:
    try:
        text = (root / REACTIONS).read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return []
    by_id: dict[str, list[dict]] = {}
    for block in re.split(r"^\[sub_resource", text, flags=re.MULTILINE)[1:]:
        reaction = _value(block, "reaction_id")
        if not reaction:
            continue
        by_id.setdefault(reaction, []).append({
            "name": _value(block, "display_name", reaction.capitalize()), "status": _value(block, "status_id"),
            "element": _value(block, "element_id"), "effect": int(_number(block, "effect")),
            "damage": _number(block, "damage"), "radius": _number(block, "radius"),
            "duration": _number(block, "duration"), "strength": _number(block, "strength"), "pull": _number(block, "pull"),
            "consume": _value(block, "consume_status") == "true"})
    rows = []
    for reaction, pair in by_id.items():
        # Like the recorder, a reaction with a single row has no clip.
        clips = [f"reaction_{reaction}", f"reaction_{reaction}_coop"] if len(pair) >= 2 else []
        rows.append({"id": reaction, "kind": "reaction", "name": pair[0]["name"], "description": "",
                     "does": _reaction_does(pair), "clips": clips, "source": REACTIONS})
    return rows


def build(root: Path = ROOT) -> dict:
    """The atlas: every entry, grouped by kind and sorted by name inside a kind."""
    entries = components(root) + combos(root) + reactions(root)
    entries.sort(key=lambda e: (KIND_ORDER.index(e["kind"]), e["name"].lower(), e["id"]))
    return {"entries": entries}


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: python3 tools/atlas.py <out.json>", file=sys.stderr)
        return 2
    atlas = build()
    out = Path(argv[1])
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(atlas, indent=1) + "\n", encoding="utf-8")
    print(f"atlas: {len(atlas['entries'])} entries -> {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
