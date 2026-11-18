#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
# SPDX-License-Identifier: GPL-3.0-or-later
"""The sound room's fixture sounds (sound plan AU4, docs/milestones/sound.md, section 7): baked by
the sound tool from recipes kept here and in the tool's tests, never as `.sound.json` files, so
`tools/sound.py check` (which scans audio/ and content/) never sees them.

    tools/sound_fixtures.py bake     # writes tests/sound_room/fixtures/<id>/ (needs ffmpeg)
    tools/sound_fixtures.py check    # every fixture baked from its recipe as it is now

The fixtures are AU2's three samples (`SAMPLES` in tools/test_sound_synth.py), its held loop
(`HELD` there) and a two-layer music track (`TRACK` below: two held loops of one length, since the
score sequencer is AU7's). Each folder is what `sound.py bake` writes for a recipe in it, with the
manifest's `prompt` naming the recipe here instead of a `.sound.json`.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sound  # noqa: E402
from test_sound_synth import HELD, SAMPLES  # noqa: E402

FOLDER = Path("tests/sound_room/fixtures")

# The two layers of the sound room's music track, of one length (2 s), so they stay in step: a
# calm pad, then a soft pulse over it.
TRACK = {
    "calm": {"version": 1, "kind": "held", "family": "held", "seconds": 2.0,
             "layers": [{"source": "triangle", "pitch": 220, "gain": -4},
                        {"source": "sine", "pitch": 330, "gain": -10},
                        {"source": "noise", "filter": {"type": "low", "from": 700, "q": 0.7}, "gain": -20}],
             "fx": {"reverb": {"mix": 0.3, "size": 1.0}},
             "notes": "The sound room's music, first layer: a soft open fifth that loops."},
    "pulse": {"version": 1, "kind": "held", "family": "held", "seconds": 2.0,
              "layers": [{"source": "sine", "pitch": {"from": 90, "to": 50}, "length": 0.2, "start": s,
                          "amp": {"attack": 0.002, "shape": "perc", "power": 2.0}} for s in (0.0, 0.5, 1.0, 1.5)],
              "notes": "The sound room's music, second layer: a soft low thump on every half second."},
}

# Each fixture's id, where its recipe is (the manifest's `prompt`) and the recipe.
FIXTURES: dict[str, tuple[str, dict]] = {
    "room_whoosh": ("tools/test_sound_synth.py SAMPLES['whoosh']", SAMPLES["whoosh"]),
    "room_fire_hit": ("tools/test_sound_synth.py SAMPLES['fire_hit']", SAMPLES["fire_hit"]),
    "room_glass_ping": ("tools/test_sound_synth.py SAMPLES['glass_ping']", SAMPLES["glass_ping"]),
    "room_hum": ("tools/test_sound_synth.py HELD", HELD),
    "room_track_calm": ("tools/sound_fixtures.py TRACK['calm']", TRACK["calm"]),
    "room_track_pulse": ("tools/sound_fixtures.py TRACK['pulse']", TRACK["pulse"]),
}


def recipe(sound_id: str) -> sound.Recipe:
    """The fixture `sound_id` as the tool's recipe, in its folder under FOLDER."""
    return sound.Recipe(FOLDER / sound_id / f"{sound_id}{sound.SUFFIX}", sound_id, FIXTURES[sound_id][1])


def bake(root: Path = sound.ROOT, encode: sound.Encoder = sound.ffmpeg_encode,
         say=print) -> list[Path]:
    """Bakes every fixture (`sound.bake`) and names its recipe in its manifest; the files written."""
    written: list[Path] = []
    for sound_id, (source, _) in FIXTURES.items():
        made = recipe(sound_id)
        entries = root / made.folder / "assets.json"
        before = entries.read_bytes() if entries.is_file() else None
        files = sound.bake(made, root, encode, say)
        manifest = sound.read_json(entries)
        for entry in manifest["assets"]:
            entry["prompt"] = source
        text = (json.dumps(manifest, indent="\t", ensure_ascii=False) + "\n").encode("utf-8")
        entries.write_bytes(text)
        if text == before:
            # The bake wrote it with its own prompt; with the recipe named again it is as it was.
            files = [f for f in files if f != made.folder / "assets.json"]
        written += files
    return written


def check(root: Path = sound.ROOT) -> list[str]:
    """What is out of date, one line each: a fixture's file or manifest entry missing, or its
    `recipe_hash` not its recipe's now. Reads no audio."""
    problems: list[str] = []
    patches = sound.load_patches(root)
    fams = sound.families(root)
    for sound_id, (source, _) in FIXTURES.items():
        made = recipe(sound_id)
        _, family = sound.checked(made, patches, fams)
        want = sound.recipe_hash(made.data, patches, family)
        entries_path = root / made.folder / "assets.json"
        entries = {e["path"]: e for e in sound.read_json(entries_path).get("assets", [])} if entries_path.is_file() else {}
        held = made.data["kind"] == "held"
        outputs = made.outputs(family) + ([Path(o.as_posix() + ".import") for o in made.outputs(family)] if held
                                          else [made.folder / f"{sound_id}.tres"])
        for out in outputs:
            if not (root / out).is_file():
                problems.append(f"{out}: missing; run tools/sound_fixtures.py bake")
        for out in made.outputs(family):
            entry = entries.get(out.as_posix())
            if entry is None:
                problems.append(f"{out}: no entry in {entries_path.relative_to(root)}; run tools/sound_fixtures.py bake")
            elif entry.get("recipe_hash") != want:
                problems.append(f"{out}: baked from an older {source}; run tools/sound_fixtures.py bake")
            elif entry.get("prompt") != source:
                problems.append(f"{out}: its manifest names {entry.get('prompt')!r}, not {source!r}")
    if (root / FOLDER).is_dir():
        for folder in sorted(p for p in (root / FOLDER).iterdir() if p.is_dir()):
            if folder.name not in FIXTURES:
                problems.append(f"{folder.relative_to(root)}: no fixture is named {folder.name} now; remove the folder")
    return problems


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("command", choices=["bake", "check"])
    parser.add_argument("--no-import", action="store_true", help="skip Godot's import after a bake")
    args = parser.parse_args(argv)
    try:
        if args.command == "check":
            problems = check()
            for p in problems:
                print(p)
            print("sound fixtures: " + (f"{len(problems)} problem(s)" if problems else "up to date"))
            return 1 if problems else 0
        written = bake()
        for path in written:
            print(path)
        if written and not args.no_import:
            sound.godot_import()
        return 0
    except (sound.BakeError, sound.SoundError) as error:
        print(f"sound fixtures: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
