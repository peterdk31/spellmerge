#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
# SPDX-License-Identifier: GPL-3.0-or-later
"""The sound tool (sound plan AU2, docs/milestones/sound.md): bake recipes into `.ogg`, hear them
on a contact sheet, and check that every generated sound is up to date.

    tools/sound.py bake [recipe, score or id ...]   # every recipe and score when none is named
    tools/sound.py sheet <recipe, score, id or family ...> --out DIR
    tools/sound.py check                            # no audio read, no ffmpeg: what the hash test runs

A recipe is `<id>.sound.json` in a folder of its own named `<id>` (`audio/sfx/<id>/`, or a
content item's `sounds/<id>/`). The bake renders each variant (tools/sound_synth.py), places its
loudness on its family's target (docs/STYLE.md, "Sound"), checks the peak, the top (how loud its
part above 2 kHz is) and the ends, encodes it
with `ffmpeg -c:a libvorbis -q:a 6` and writes, in the recipe's folder only:

- a one-shot (`sfx`, `ui`): `variants/1.ogg` ... `n.ogg` and `<id>.tres`, an
  `AudioStreamRandomizer` of them with the family's pitch and volume jitter;
- a `held` sound: `<id>.ogg`, a loop (its new `.import` says `loop=true`);
- `assets.json`: one manifest entry a file, with the recipe's hash, loudness and peak.

A music score is `<track>.score.json` in a folder of its own named `<track>` under `audio/`
(`audio/music/<track>/`). The sequencer (tools/sound_score.py) renders its layers, each exactly one
loop long; the bake places them together on the music family's target and writes beside it a loop
`<layer id>.ogg` a layer (its new `.import` says `loop=true`) and the folder's `assets.json`.

A file whose audio is the same is not rewritten. Then it runs Godot's import, which completes the
`.import` files (`uid`, `dest_files`); an existing `.import` is never rewritten.

ffmpeg (with libvorbis, and libx264 and aac for the sheet's video) is needed by `bake` and `sheet`
only, never by `check` or a test.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import math
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import wave
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Callable, Iterable, Sequence

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sound_meter  # noqa: E402
import sound_score  # noqa: E402
import sound_synth  # noqa: E402
from sound_synth import RATE, SoundError  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
STYLE = Path("docs/STYLE.md")
PATCHES = Path("audio/patches")
SCAN = ("audio", "content")  # where sounds and their manifests are
MANIFEST = Path("audio/manifest.json")
SUFFIX = ".sound.json"
SCORE_SUFFIX = ".score.json"
PATCH_SUFFIX = ".patch.json"
TOOL = f"tools/sound.py (procedural synthesis, generator {sound_synth.GENERATOR})"
AUTHOR = "Claude"
LICENSE = "CC-BY-SA-4.0"
WINDOW = 1.0  # LU either side of a family's target
PEAK_MARGIN = 1.0  # dB under the family's true peak limit, for Vorbis's overshoot
EDGE = 1e-3  # how near zero a one-shot's first and last samples must be
LOOP_MEASURE = 3.0  # seconds of a loop, played round, that its loudness is measured over
# Sounds with no recipe, made before the tool by a generator kept out of the repository. The
# seven ambience files of atmosphere D were the last; AU6 remade them as recipes, so this is empty
# and stays so (a test holds it): every generated sound comes from a recipe.
UNRECIPED: tuple[str, ...] = ()


class BakeError(ValueError):
    """A recipe that rendered but cannot be written: its file and what is wrong."""


# --- Families ----------------------------------------------------------------------------------

@dataclass(frozen=True)
class Family:
    name: str
    loudness: float  # LUFS
    measure: str  # "momentary" or "integrated"
    peak: float  # dBTP, the limit
    variants: int
    pitch: float  # the jitter as a share (0.04 for ±4%)
    volume: float  # the jitter in dB
    top: float | None = None  # how far under a sound's level its top must be, in LU (-10.0); None for no ceiling
    top_hz: float = 2000.0  # a sound's top is its part above this, from the table's header ("above 2 kHz")

    def top_of(self, samples: Sequence[float], loop: bool = False) -> float:
        """How loud the sound's top (its part above `top_hz`) is by the family's measure, in LU from
        the whole sound's level: -10 is a top 10 LU under the sound."""
        return self.level_of(sound_meter.above(samples, RATE, self.top_hz), loop) - self.level_of(samples, loop)

    def level_of(self, samples: Sequence[float], loop: bool = False) -> float:
        """Its loudness by the family's measure; a loop is measured as it plays, over and over
        (at least LOOP_MEASURE seconds of it), not as if silence followed it."""
        if loop and samples:
            samples = list(samples) * max(1, math.ceil(LOOP_MEASURE * RATE / len(samples)))
        if self.measure == "integrated":
            return sound_meter.integrated(samples, RATE)
        return sound_meter.momentary_max(samples, RATE)


def families(root: Path = ROOT) -> dict[str, Family]:
    """The families of docs/STYLE.md's "Sound" table, read from there so the numbers have one home."""
    text = (root / STYLE).read_text(encoding="utf-8")
    start = text.index("## Sound")
    end = text.find("\n## ", start + 1)
    found: dict[str, Family] = {}
    row = re.compile(r"^\|\s*`(\w+)`[^|]*\|\s*(-?[\d.]+)\s+(momentary|integrated)\s*\|\s*(-?[\d.]+)\s*dBTP\s*\|"
                     r"\s*(\d+)\s*\|\s*([^|]+)\|\s*([^|]+)\|\s*([^|]+)\|")
    section = text[start:end]
    header = re.search(r"Top \(above ([\d.]+) kHz\)", section)
    if not header:
        raise ValueError(f"{STYLE}: its Sound table has no column 'Top (above N kHz)'")
    top_hz = float(header.group(1)) * 1000.0
    for line in section.splitlines():
        m = row.match(line)
        if not m:
            if line.startswith("| `"):  # a family's row that does not read: never dropped in silence
                raise ValueError(f"{STYLE}: the Sound table's row {line.split('|')[1].strip()} does not read (loudness, "
                                 "peak, variants, the two jitters and the top, a column each)")
            continue
        pitch = re.search(r"([\d.]+)\s*%", m.group(6))
        volume = re.search(r"([\d.]+)\s*dB", m.group(7))
        top = re.fullmatch(r"\s*(-[\d.]+)\s*LU\s*", m.group(8))
        if not top and m.group(8).strip() != "none":
            raise ValueError(f"{STYLE}: the {m.group(1)} row's top is {m.group(8).strip()!r}; write LU under the "
                             "sound's level (-10 LU) or none")
        found[m.group(1)] = Family(m.group(1), float(m.group(2)), m.group(3), float(m.group(4)), int(m.group(5)),
                                   float(pitch.group(1)) / 100.0 if pitch else 0.0,
                                   float(volume.group(1)) if volume else 0.0,
                                   float(top.group(1)) if top else None, top_hz)
    if not found:
        raise ValueError(f"{STYLE}: no families in its Sound table")
    return found


# --- Recipes and their hashes ------------------------------------------------------------------

def canonical(value: object) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def read_json(path: Path) -> dict:
    """A JSON object from a file, or a BakeError naming the file."""
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        raise BakeError(f"{path}: not JSON ({error})") from error
    if not isinstance(data, dict):
        raise BakeError(f"{path}: must be a JSON object")
    return data


def load_patches(root: Path = ROOT) -> dict[str, dict]:
    found: dict[str, dict] = {}
    folder = root / PATCHES
    if folder.is_dir():
        for path in sorted(folder.glob("*" + PATCH_SUFFIX)):
            found[path.name[: -len(PATCH_SUFFIX)]] = read_json(path)
    return found


def recipe_hash(recipe: dict, patches: dict[str, dict], family: Family | None) -> str:
    """sha256 of the recipe, every patch it names, its family's row of docs/STYLE.md (its target,
    peak and jitter are baked in too) and the synth's GENERATOR."""
    named = {name: patches.get(name) for name in sound_synth.patches_named(recipe)}
    return "sha256:" + hashlib.sha256(canonical({"generator": sound_synth.GENERATOR, "recipe": recipe, "patches": named,
                                                 "family": asdict(family) if family else None})).hexdigest()


def score_hash(score: dict, patches: dict[str, dict], family: Family | None) -> str:
    """sha256 of the score, every patch its instruments name, the music family's row, the synth's
    GENERATOR and the sequencer's VERSION."""
    named = {name: patches.get(name) for name in sound_score.patches_named(score)}
    return "sha256:" + hashlib.sha256(canonical({"generator": sound_synth.GENERATOR, "sequencer": sound_score.VERSION,
                                                 "score": score, "patches": named,
                                                 "family": asdict(family) if family else None})).hexdigest()


def audio_hash(samples: Sequence[float]) -> str:
    """sha256 of the 16-bit samples: what says a rebake's audio is the same, whatever encoder."""
    return "sha256:" + hashlib.sha256(pcm16(samples)).hexdigest()


@dataclass(frozen=True)
class Recipe:
    path: Path  # from the repository root
    id: str
    data: dict  # as written

    @property
    def folder(self) -> Path:
        return self.path.parent

    def outputs(self, family: Family | None = None) -> list[Path]:
        """The audio files a bake writes, from the repository root."""
        if self.data.get("kind") == "held":
            return [self.folder / f"{self.id}.ogg"]
        count = self.data.get("variants", family.variants if family else 1)
        return [self.folder / "variants" / f"{i}.ogg" for i in range(1, count + 1)]


def read_recipe(path: Path, root: Path = ROOT) -> Recipe:
    """A recipe file, its path kept from the repository root (or whole, for one outside it, which
    only the sheet takes). In the repository a recipe is in a folder of its own named for its id,
    under audio/ or a content item's sounds/, so a bake never writes over a content item's files."""
    full = (path if path.is_absolute() else root / path).resolve()
    try:
        rel = full.relative_to(root.resolve())
    except ValueError:
        rel = full
    name = rel.name
    if not name.endswith(SUFFIX):
        raise BakeError(f"{rel}: a recipe is named <id>{SUFFIX}")
    sound_id = name[: -len(SUFFIX)]
    if rel.parent.name != sound_id:
        raise BakeError(f"{rel}: a recipe lives in a folder of its own named {sound_id}/")
    if not rel.is_absolute() and rel.parts[0] != "audio" and (rel.parts[0] != "content" or rel.parent.parent.name != "sounds"):
        raise BakeError(f"{rel}: a recipe lives under audio/ or in a content item's sounds/{sound_id}/")
    return Recipe(rel, sound_id, read_json(root / rel))


@dataclass(frozen=True)
class Score:
    path: Path  # from the repository root
    id: str  # the track's
    data: dict  # as written

    @property
    def folder(self) -> Path:
        return self.path.parent

    def outputs(self, family: Family | None = None) -> list[Path]:
        """A loop a layer, `<layer id>.ogg`, from the repository root."""
        layers = self.data.get("layers")
        return [self.folder / f"{layer['id']}.ogg" for layer in (layers if isinstance(layers, list) else [])
                if isinstance(layer, dict) and isinstance(layer.get("id"), str)]


def read_score(path: Path, root: Path = ROOT) -> Score:
    """A score file, in a folder of its own named for its track under audio/ (or whole, outside the
    repository, for the sheet)."""
    full = (path if path.is_absolute() else root / path).resolve()
    try:
        rel = full.relative_to(root.resolve())
    except ValueError:
        rel = full
    name = rel.name
    if not name.endswith(SCORE_SUFFIX):
        raise BakeError(f"{rel}: a score is named <track>{SCORE_SUFFIX}")
    track = name[: -len(SCORE_SUFFIX)]
    if rel.parent.name != track:
        raise BakeError(f"{rel}: a score lives in a folder of its own named {track}/")
    if not rel.is_absolute() and rel.parts[0] != "audio":
        raise BakeError(f"{rel}: a score lives under audio/ (audio/music/{track}/)")
    return Score(rel, track, read_json(root / rel))


def find_scores(root: Path = ROOT) -> list[Score]:
    found: list[Score] = []
    for top in SCAN:
        if (root / top).is_dir():
            found += [read_score(p.relative_to(root), root) for p in sorted((root / top).rglob("*" + SCORE_SUFFIX))]
    return found


def find_recipes(root: Path = ROOT) -> list[Recipe]:
    found: list[Recipe] = []
    for top in SCAN:
        if (root / top).is_dir():
            found += [read_recipe(p.relative_to(root), root) for p in sorted((root / top).rglob("*" + SUFFIX))]
    return found


def checked(recipe: Recipe, patches: dict[str, dict], fams: dict[str, Family]) -> tuple[dict, Family]:
    """The recipe validated (its patches merged in) and its family; raises BakeError naming the file."""
    try:
        data = sound_synth.validate(recipe.data, patches)
        family = fams.get(data["family"])
        if family is None or family.name == "music":
            raise SoundError("family", f"{data['family']!r} is not a sound family ({', '.join(f for f in fams if f != 'music')})")
        kind = data["kind"]
        if (kind == "held") != (family.name == "held") or (kind == "ui") != (family.name == "ui"):
            raise SoundError("family", f"a {kind} sound is not in the {family.name} family")
    except SoundError as error:
        raise BakeError(f"{recipe.path}: {error}") from error
    return data, family


def checked_score(score: Score, patches: dict[str, dict], fams: dict[str, Family]) -> tuple[dict, Family]:
    """The score validated and the music family; raises BakeError naming the file."""
    try:
        data = sound_score.validate(score.data, patches)
    except SoundError as error:
        raise BakeError(f"{score.path}: {error}") from error
    if "music" not in fams:
        raise BakeError(f"{STYLE}: its Sound table has no music row")
    if fams["music"].top is not None:
        raise BakeError(f"{STYLE}: the music row has a top, which no bake checks (a track's layers are placed "
                        "together); write none")
    return data, fams["music"]


# --- Manifests ---------------------------------------------------------------------------------

def manifest_entries(root: Path = ROOT) -> dict[str, dict]:
    """Every audio manifest entry, by its path: audio/manifest.json and every assets.json."""
    found: dict[str, dict] = {}
    files = [root / MANIFEST] + [p for top in SCAN if (root / top).is_dir() for p in sorted((root / top).rglob("assets.json"))]
    for path in files:
        if path.is_file():
            for entry in read_json(path).get("assets", []):
                if isinstance(entry, dict) and isinstance(entry.get("path"), str):
                    found[entry["path"]] = entry
    return found


def check(root: Path = ROOT) -> list[str]:
    """Every problem with the generated sounds, each with its file and the command that fixes it:
    a recipe that does not validate, a file or manifest entry a recipe makes that is missing, a
    stale `recipe_hash`, and an `.ogg` that no recipe makes and no manifest entry gives another
    source (origin human, or one of UNRECIPED). Reads no audio."""
    problems: list[str] = []
    patches = load_patches(root)
    fams = families(root)
    entries = manifest_entries(root)
    made: set[str] = set()
    recipe_folders: set[str] = set()
    try:
        recipes = find_recipes(root)
        scores = find_scores(root)
    except BakeError as error:
        return [str(error)]
    for score in scores:
        bake_cmd = f"run: tools/sound.py bake {score.path}"
        try:
            _, family = checked_score(score, patches, fams)
        except BakeError as error:
            problems.append(str(error))
            continue
        want = score_hash(score.data, patches, family)
        for out in score.outputs():
            made.add(out.as_posix())
            entry = entries.get(out.as_posix())
            if not (root / out).is_file():
                problems.append(f"{out}: missing; {bake_cmd}")
            elif entry is None:
                problems.append(f"{out}: no entry in {score.folder / 'assets.json'}; {bake_cmd}")
            elif entry.get("recipe_hash") != want:
                problems.append(f"{out}: stale, its score, a patch it names or the music row in docs/STYLE.md "
                                f"changed since it was baked; {bake_cmd}")
    for recipe in recipes:
        bake_cmd = f"run: tools/sound.py bake {recipe.path}"
        recipe_folders.add(recipe.folder.as_posix())
        try:
            _, family = checked(recipe, patches, fams)
        except BakeError as error:
            problems.append(str(error))
            continue
        want = recipe_hash(recipe.data, patches, family)
        outputs = recipe.outputs(family)
        made.update(p.as_posix() for p in outputs)
        for out in outputs:
            entry = entries.get(out.as_posix())
            if not (root / out).is_file():
                problems.append(f"{out}: missing; {bake_cmd}")
            elif entry is None:
                problems.append(f"{out}: no entry in {recipe.folder / 'assets.json'}; {bake_cmd}")
            elif entry.get("recipe_hash") != want:
                problems.append(f"{out}: stale, its recipe, a patch it names or its family's row in docs/STYLE.md "
                                f"changed since it was baked; {bake_cmd}")
        tres = recipe.folder / f"{recipe.id}.tres"
        held = recipe.data.get("kind") == "held"
        if not held and not (root / tres).is_file():
            problems.append(f"{tres}: missing; {bake_cmd}")
        if held and (root / tres).is_file():
            problems.append(f"{tres}: left from when it was a one-shot; {bake_cmd}")
        variants = root / recipe.folder / "variants"
        if variants.is_dir():
            for extra in sorted(variants.glob("*.ogg")):
                if extra.relative_to(root).as_posix() not in made:
                    problems.append(f"{extra.relative_to(root)}: a variant the recipe no longer has; {bake_cmd}")
        loop = recipe.folder / f"{recipe.id}.ogg"
        if not held and (root / loop).is_file():
            made.add(loop.as_posix())
            problems.append(f"{loop}: left from when it was a held sound; {bake_cmd}")
    for top in SCAN:
        if not (root / top).is_dir():
            continue
        for ogg in sorted((root / top).rglob("*.ogg")):
            rel = ogg.relative_to(root).as_posix()
            if rel in made or rel in UNRECIPED:
                continue
            if ogg.parent.name == "variants" and ogg.parent.parent.relative_to(root).as_posix() in recipe_folders:
                continue  # named above as a variant its recipe no longer has
            if entries.get(rel, {}).get("origin") != "human":
                problems.append(f"{rel}: no recipe or score makes it; write one beside it ({SUFFIX}, or "
                                f"{SCORE_SUFFIX} for music), or give it a manifest entry with origin human if it was "
                                "made by hand")
    for rel in UNRECIPED:
        if rel in made:
            problems.append(f"{rel}: has a recipe now; take it off tools/sound.py's UNRECIPED")
    return problems


# --- Baking ------------------------------------------------------------------------------------

Encoder = Callable[[Sequence[float]], bytes]


def place(samples: list[list[float]], family: Family, gain: float,
          loop: bool = False) -> tuple[list[list[float]], list[float], list[float]]:
    """The variants scaled together onto the family's target plus `gain`, with each one's level
    and true peak after; one scale for all, so they keep their own small differences."""
    levels = [family.level_of(s, loop) for s in samples]
    target = family.loudness + gain
    if min(levels) <= sound_meter.SILENCE:
        raise BakeError("a variant is silent")
    scale = 10.0 ** ((target - sum(levels) / len(levels)) / 20.0)
    placed = [[v * scale for v in s] for s in samples]
    shift = 20.0 * math.log10(scale)
    return placed, [lvl + shift for lvl in levels], [sound_meter.true_peak(s) for s in placed]


def render_score_placed(score: Score, data: dict, family: Family) -> list[tuple[str, list[float], float, float]]:
    """Every layer of a score rendered and placed: all of them by one scale, so the layers played
    together are on the music family's target (plus the score's `gain`) and keep their balance;
    (layer id, samples, its own level, its own peak). Raises BakeError for a peak over the limit at
    any intensity of the stacked track (its first n layers together) or of a layer alone."""
    layers = sound_score.render(data)
    together = sound_score.mixed(list(layers.values()))
    level = family.level_of(together, loop=True)
    if level <= sound_meter.SILENCE:
        raise BakeError(f"{score.path}: its layers are silent")
    target = family.loudness + data.get("gain", 0.0)
    scale = 10.0 ** ((target - level) / 20.0)
    limit = family.peak - PEAK_MARGIN
    shift = 20.0 * math.log10(scale)
    raw = list(layers.values())
    heard = {f"its first {n} layers together" if n > 1 else "its first layer": sound_score.mixed(raw[:n])
             for n in range(1, len(raw) + 1)}
    heard.update({f"its layer {layer_id} alone": samples for layer_id, samples in list(layers.items())[1:]})
    for what, samples in heard.items():
        peak = sound_meter.true_peak(samples) + shift
        if peak > limit:
            raise BakeError(f"{score.path}: {what} peak at {peak:.1f} dBTP with the track at {target:.1f} LUFS, over "
                            f"{limit:.1f} (the music limit {family.peak} less {PEAK_MARGIN} for Vorbis); soften its "
                            "hits or lower the loudest layer's gain")
    placed = []
    for layer_id, samples in layers.items():
        scaled = [v * scale for v in samples]
        own_peak = sound_meter.true_peak(scaled)
        placed.append((layer_id, scaled, family.level_of(scaled, loop=True), own_peak))
    return placed


def bake_score(score: Score, root: Path = ROOT, encode: Encoder | None = None,
               say: Callable[[str], None] = print) -> list[Path]:
    """Bake one score: a loop a layer and the folder's assets.json; returns the files it wrote. A
    file is rewritten only when its audio changed (its `audio_hash`)."""
    encode = encode or ffmpeg_encode
    if score.path.is_absolute():
        raise BakeError(f"{score.path}: only a score in the repository is baked (the sheet takes any)")
    patches = load_patches(root)
    data, family = checked_score(score, patches, families(root))
    folder = root / score.folder
    entries_path = folder / "assets.json"
    old = {e["path"]: e for e in read_json(entries_path).get("assets", [])
           if isinstance(e, dict) and isinstance(e.get("path"), str)} if entries_path.is_file() else {}
    want = score_hash(score.data, patches, family)
    written: list[Path] = []
    entries: list[dict] = []
    made: set[str] = set()
    for layer_id, samples, level, peak in render_score_placed(score, data, family):
        out = score.folder / f"{layer_id}.ogg"
        key = out.as_posix()
        made.add(key)
        before = old.get(key, {})
        heard = audio_hash(samples)
        changed = before.get("audio_hash") != heard or not (root / out).is_file()
        if changed:
            (root / out).write_bytes(encode(samples))
            written.append(out)
        tier = before.get("tier", "good")
        if changed and tier == "final":
            tier = "good"
            say(f"{out}: its audio changed, so it is back to tier good (the owner promoted the old one)")
        entries.append({"path": key, "origin": "ai", "author": AUTHOR, "license": LICENSE, "tier": tier,
                        "tool": TOOL, "prompt": score.path.as_posix(), "recipe_hash": want, "audio_hash": heard,
                        "loudness": round(level, 1), "peak": round(peak, 1)})
        if not (root / (key + ".import")).exists():
            (root / (key + ".import")).write_text(IMPORT_LOOP, encoding="utf-8")
            written.append(Path(key + ".import"))
    for extra in sorted(folder.glob("*.ogg")):  # a layer the score no longer has
        rel = extra.relative_to(root)
        if rel.as_posix() not in made and old.get(rel.as_posix(), {}).get("prompt") == score.path.as_posix():
            _remove(root, rel, say, "the score has no such layer now")
            old.pop(rel.as_posix(), None)
    kept = [e for path, e in old.items() if path not in made and (root / path).is_file()]
    manifest = {"assets": sorted(entries + kept, key=lambda e: e["path"])}
    if _write_if_changed(entries_path, (json.dumps(manifest, indent="\t", ensure_ascii=False) + "\n").encode("utf-8")):
        written.append(score.folder / "assets.json")
    return written


def render_placed(recipe: Recipe, data: dict, family: Family) -> list[tuple[list[float], float, float]]:
    """Every variant rendered, placed and checked (its level, its peak, its top and its ends):
    (samples, level, peak). Raises BakeError."""
    count = 1 if data["kind"] == "held" else data.get("variants", family.variants)
    raw = [sound_synth.render(data, i) for i in range(1, count + 1)]
    try:
        placed, levels, peaks = place(raw, family, data.get("gain", 0.0), data["kind"] == "held")
    except BakeError as error:
        raise BakeError(f"{recipe.path}: {error}") from error
    target = family.loudness + data.get("gain", 0.0)
    limit = family.peak - PEAK_MARGIN
    ceiling = data.get("top", family.top)
    for i, (s, level, peak) in enumerate(zip(placed, levels, peaks), 1):
        name = f"{recipe.path} variant {i}"
        if abs(level - target) > WINDOW:
            raise BakeError(f"{name}: {level:.1f} LUFS {family.measure}, more than {WINDOW} LU from the others' "
                            f"{target:.1f}; make the variants less unlike (vary)")
        if peak > limit:
            raise BakeError(f"{name}: true peak {peak:.1f} dBTP at {target:.1f} LUFS, over {limit:.1f} (the "
                            f"{family.name} limit {family.peak} less {PEAK_MARGIN} for Vorbis); soften its attack "
                            "or drive, or set gain lower with a note saying why")
        if ceiling is not None:
            top = family.top_of(s, data["kind"] == "held")
            if top > ceiling:
                raise BakeError(f"{name}: its top (above {family.top_hz:.0f} Hz) is {top:.1f} LU from its level, over the "
                                f"{family.name} ceiling of {ceiling:.1f}, so it cuts through; lower its high layers' "
                                "pitches, filters or gains (or fx.lowpass), or set top with a note saying why")
        if data["kind"] != "held" and (abs(s[0]) > EDGE or abs(s[-1]) > EDGE):
            raise BakeError(f"{name}: does not start and end at silence (a click)")
    return list(zip(placed, levels, peaks))


def pcm16(samples: Sequence[float]) -> bytes:
    return b"".join(struct.pack("<h", max(-32767, min(32767, round(v * 32767)))) for v in samples)


def wav_bytes(samples: Sequence[float]) -> bytes:
    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(pcm16(samples))
    return buffer.getvalue()


def need_ffmpeg() -> str:
    found = shutil.which("ffmpeg")
    if not found:
        raise BakeError("ffmpeg is not installed: bake and sheet need it with libvorbis "
                        "(apt install ffmpeg, brew install ffmpeg, or ffmpeg.org)")
    return found


def ffmpeg_encode(samples: Sequence[float]) -> bytes:
    """Vorbis at quality 6, the same bytes for the same samples (bitexact)."""
    ffmpeg = need_ffmpeg()
    with tempfile.TemporaryDirectory() as tmp:
        src, dst = Path(tmp) / "in.wav", Path(tmp) / "out.ogg"
        src.write_bytes(wav_bytes(samples))
        subprocess.run([ffmpeg, "-v", "error", "-y", "-i", str(src), "-c:a", "libvorbis", "-q:a", "6",
                        "-fflags", "+bitexact", "-flags:a", "+bitexact", "-map_metadata", "-1", str(dst)], check=True)
        return dst.read_bytes()


def randomizer_tres(recipe: Recipe, family: Family, outputs: list[Path]) -> str:
    """`<id>.tres`: an AudioStreamRandomizer of the variants (playback_mode 0, random with no
    repeats, the default) with the family's jitter; `random_pitch` is a scale (1.04 for ±4%)."""
    lines = [f'[gd_resource type="AudioStreamRandomizer" load_steps={len(outputs) + 1} format=3]', ""]
    for i, out in enumerate(outputs, 1):
        lines.append(f'[ext_resource type="AudioStream" path="res://{out.as_posix()}" id="{i}"]')
    lines += ["", "[resource]", "playback_mode = 0",
              f"random_pitch = {1.0 + family.pitch:.4g}", f"random_volume_offset_db = {family.volume:.4g}",
              f"streams_count = {len(outputs)}"]
    for i in range(len(outputs)):
        lines += [f'stream_{i}/stream = ExtResource("{i + 1}")', f"stream_{i}/weight = 1.0"]
    return "\n".join(lines) + "\n"


def _write_if_changed(path: Path, data: bytes) -> bool:
    if path.is_file() and path.read_bytes() == data:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    return True


IMPORT_LOOP = '[remap]\n\nimporter="oggvorbisstr"\ntype="AudioStreamOggVorbis"\n\n[params]\n\nloop=true\n'


def _remove(root: Path, rel: Path, say: Callable[[str], None], why: str) -> None:
    for path in (root / rel, root / (rel.as_posix() + ".import")):
        path.unlink(missing_ok=True)
    say(f"{rel}: removed, {why}")


def bake(recipe: Recipe, root: Path = ROOT, encode: Encoder = ffmpeg_encode,
         say: Callable[[str], None] = print) -> list[Path]:
    """Bake one recipe; returns the files it wrote (from the repository root). A file is rewritten
    only when its audio changed (its `audio_hash`), so another machine's encoder rewrites nothing."""
    if recipe.path.is_absolute():
        raise BakeError(f"{recipe.path}: only a recipe in the repository is baked (the sheet takes any)")
    patches = load_patches(root)
    data, family = checked(recipe, patches, families(root))
    rendered = render_placed(recipe, data, family)
    outputs = recipe.outputs(family)
    folder = root / recipe.folder
    held = data["kind"] == "held"
    written: list[Path] = []
    entries_path = folder / "assets.json"
    old = {e["path"]: e for e in read_json(entries_path).get("assets", [])
           if isinstance(e, dict) and isinstance(e.get("path"), str)} if entries_path.is_file() else {}
    want = recipe_hash(recipe.data, patches, family)
    entries: list[dict] = []
    for out, (samples, level, peak) in zip(outputs, rendered):
        key = out.as_posix()
        before = old.get(key, {})
        heard = audio_hash(samples)
        changed = before.get("audio_hash") != heard or not (root / out).is_file()
        if changed:
            (root / out).parent.mkdir(parents=True, exist_ok=True)
            (root / out).write_bytes(encode(samples))
            written.append(out)
        tier = before.get("tier", "good")
        if changed and tier == "final":
            tier = "good"
            say(f"{out}: its audio changed, so it is back to tier good (the owner promoted the old one)")
        entries.append({"path": key, "origin": "ai", "author": AUTHOR, "license": LICENSE, "tier": tier,
                        "tool": TOOL, "prompt": recipe.path.as_posix(), "recipe_hash": want, "audio_hash": heard,
                        "loudness": round(level, 1), "peak": round(peak, 1)})
        if held and not (root / (key + ".import")).exists():
            (root / (key + ".import")).write_text(IMPORT_LOOP, encoding="utf-8")
            written.append(Path(key + ".import"))
    # What the recipe no longer makes goes: variants it has fewer of, and the files of its other kind.
    made = {o.as_posix() for o in outputs}
    if (folder / "variants").is_dir():
        for extra in sorted((folder / "variants").glob("*.ogg")):
            rel = extra.relative_to(root)
            if rel.as_posix() not in made:
                _remove(root, rel, say, "the recipe makes no such variant now")
                old.pop(rel.as_posix(), None)
    tres = recipe.folder / f"{recipe.id}.tres"
    loop = recipe.folder / f"{recipe.id}.ogg"
    if held and (root / tres).is_file():
        _remove(root, tres, say, "the sound is held now")
    if not held and (root / loop).is_file():
        _remove(root, loop, say, "the sound is a one-shot now")
        old.pop(loop.as_posix(), None)
    kept = [e for path, e in old.items() if path not in made and (root / path).is_file()]  # hand-written entries
    manifest = {"assets": sorted(entries + kept, key=lambda e: e["path"])}
    if _write_if_changed(entries_path, (json.dumps(manifest, indent="\t", ensure_ascii=False) + "\n").encode("utf-8")):
        written.append(recipe.folder / "assets.json")
    if not held and _write_if_changed(root / tres, randomizer_tres(recipe, family, outputs).encode("utf-8")):
        written.append(tres)
    return written


def godot() -> str | None:
    if os.environ.get("GODOT"):
        return os.environ["GODOT"]
    tools = ROOT / "build/godot"
    found = sorted(tools.glob("Godot_v*_linux.x86_64")) if tools.is_dir() else []
    return str(found[0]) if found else None


def godot_import(root: Path = ROOT) -> None:
    binary = godot()
    command = [binary or "<godot>", "--headless", "--path", str(root), "--import"]
    if binary is None:
        print("Godot was not found (set GODOT, or run ci/build/build.sh --quick once); then run: "
              + " ".join(command[:2] + ["--path", ".", "--import"]))
        return
    subprocess.run(command, check=True, stdout=subprocess.DEVNULL)


Source = Recipe | Score


def resolve(names: Iterable[str], root: Path = ROOT) -> list[Source]:
    """Recipe or score paths, sound or track ids (a layer's id names its score), or family names
    (`music` for every score) into recipes and scores."""
    every: list[Source] | None = None
    found: list[Source] = []
    for name in names:
        if name.endswith(SUFFIX):
            found.append(read_recipe(Path(name).resolve(), root))
            continue
        if name.endswith(SCORE_SUFFIX):
            found.append(read_score(Path(name).resolve(), root))
            continue
        every = every if every is not None else [*find_recipes(root), *find_scores(root)]
        hits = [r for r in every if r.id == name or (isinstance(r, Recipe) and r.data.get("family") == name)
                or (isinstance(r, Score) and (name == "music" or name in {o.stem for o in r.outputs()}))]
        if not hits:
            raise BakeError(f"{name}: no recipe or score with that id or family")
        found += hits
    return found


def bake_any(source: Source, root: Path = ROOT, say: Callable[[str], None] = print) -> list[Path]:
    return bake_score(source, root, say=say) if isinstance(source, Score) else bake(source, root, say=say)


# --- The contact sheet -------------------------------------------------------------------------

GAP = 0.4  # seconds between the sheet's parts
CROWD = (0.0, 0.023, 0.051, 0.080)  # four players casting at once, a frame or so apart


MUSIC_ROUNDS = 2  # a music intensity on the sheet is heard round its loop this many times


def music_timeline(layers: list[list[float]]) -> list[float]:
    """A track on the sheet: its first layer, then the first two together, and so on (its intensities
    as a stacked MusicTrack plays them), each round its loop MUSIC_ROUNDS times."""
    out: list[float] = []
    for n in range(1, len(layers) + 1):
        out += sound_score.mixed(layers[:n]) * MUSIC_ROUNDS + [0.0] * round(GAP * RATE)
    return out


def sheet_timeline(sounds: list[tuple[str, list[list[float]]]], music: list[list[float]] | None = None) -> list[float]:
    """The sheet's audio: each sound's variants in turn with a gap, then four of it at once, then
    every sound together, then each track's intensities in turn (`music`, a track's timeline
    each); scaled down only if the sum would clip."""
    gap = [0.0] * round(GAP * RATE)
    out: list[float] = []

    def mix(parts: list[tuple[int, Sequence[float]]]) -> list[float]:
        size = max(start + len(p) for start, p in parts)
        buf = [0.0] * size
        for start, p in parts:
            for i, v in enumerate(p):
                buf[start + i] += v
        return buf

    for _, variants in sounds:
        for v in variants:
            out += list(v) + gap
        crowd = [(round(t * RATE), variants[i % len(variants)]) for i, t in enumerate(CROWD)]
        out += mix(crowd) + gap + gap
    if len(sounds) > 1:
        out += mix([(0, variants[0]) for _, variants in sounds]) + gap
    for track in music or []:
        out += track + gap
    peak = max((abs(v) for v in out), default=0.0)
    if peak > 0.99:
        out = [v * 0.99 / peak for v in out]
    return out


def sheet(sources: list[Source], out_dir: Path, root: Path = ROOT) -> list[Path]:
    """`sheet.ogg` and `sheet.mp4` (the same audio over a still card of the ids) in `out_dir`."""
    ffmpeg = need_ffmpeg()
    patches = load_patches(root)
    fams = families(root)
    sounds = []
    music: list[list[float]] = []
    lines: list[str] = []
    unique = list({r.path: r for r in sources}.values())  # a sound named twice is heard once
    for source in unique:
        if isinstance(source, Score):
            data, family = checked_score(source, patches, fams)
            placed = render_score_placed(source, data, family)
            music.append(music_timeline([s for _, s, _, _ in placed]))
            ids = [layer_id for layer_id, _, _, _ in placed]
            lines.append(f"{source.id} (music): " + ", then ".join(" + ".join(ids[:n]) for n in range(1, len(ids) + 1))
                         + "; each twice round")
            continue
        data, family = checked(source, patches, fams)
        sounds.append((source.id, [s for s, _, _ in render_placed(source, data, family)]))
    audio = sheet_timeline(sounds, music)
    out_dir.mkdir(parents=True, exist_ok=True)
    ogg, mp4 = out_dir / "sheet.ogg", out_dir / "sheet.mp4"
    with tempfile.TemporaryDirectory() as tmp:
        wav, card = Path(tmp) / "sheet.wav", Path(tmp) / "card.txt"
        wav.write_bytes(wav_bytes(audio))
        subprocess.run([ffmpeg, "-v", "error", "-y", "-i", str(wav), "-c:a", "libvorbis", "-q:a", "6", str(ogg)], check=True)
        card.write_text("Spellmerge sound sheet\n\n" + "\n".join(
            f"{i}. {sid}: variants, then four at once" for i, (sid, _) in enumerate(sounds, 1))
            + ("\n\nthen all together" if len(sounds) > 1 else "")
            + "".join(f"\n\n{line}" for line in lines) + "\n", encoding="utf-8")
        draw = f"drawtext=textfile='{card}':fontcolor=0xf4f1ea:fontsize=28:x=60:y=60:line_spacing=12"
        command = [ffmpeg, "-v", "error", "-y", "-f", "lavfi", "-i", "color=c=0x14121f:s=1280x720:r=2", "-i", str(wav),
                   "-vf", draw, "-c:v", "libx264", "-tune", "stillimage", "-pix_fmt", "yuv420p",
                   "-c:a", "aac", "-b:a", "192k", "-shortest", str(mp4)]
        if subprocess.run(command, stderr=subprocess.DEVNULL).returncode != 0:  # no drawtext: a plain card
            del command[command.index("-vf"):command.index("-vf") + 2]
            subprocess.run(command, check=True)
    return [ogg, mp4]


# --- The command -------------------------------------------------------------------------------

def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="command", required=True)
    b = sub.add_parser("bake", help="bake recipes into .ogg (every recipe when none is named)")
    b.add_argument("names", nargs="*", help="recipe or score files, sound or track ids")
    b.add_argument("--no-import", action="store_true", help="skip Godot's import")
    s = sub.add_parser("sheet", help="a contact sheet (.ogg and .mp4) outside the repository")
    s.add_argument("names", nargs="+", help="recipe or score files, sound or track ids, or a family (music)")
    s.add_argument("--out", required=True, type=Path)
    sub.add_parser("check", help="every generated sound up to date (reads no audio)")
    args = parser.parse_args(argv)
    try:
        if args.command == "check":
            problems = check()
            for p in problems:
                print(p)
            print("sound check: " + (f"{len(problems)} problem(s)" if problems else "every generated sound is up to date"))
            return 1 if problems else 0
        if args.command == "bake":
            sources: list[Source] = resolve(args.names) if args.names else [*find_recipes(), *find_scores()]
            written: list[Path] = []
            for source in sources:
                files = bake_any(source)
                written += files
                print(f"{source.path}: " + (", ".join(str(f) for f in files) if files else "up to date"))
            if written and not args.no_import:
                godot_import()
            return 0
        out = args.out.resolve()
        if out == ROOT or ROOT in out.parents:
            raise BakeError(f"{args.out}: the sheet is written outside the repository, never committed")
        for path in sheet(resolve(args.names), out):
            print(path)
        return 0
    except (BakeError, SoundError) as error:
        print(f"sound: {error}", file=sys.stderr)
        return 1
    except subprocess.CalledProcessError as error:
        print(f"sound: {error.cmd[0]} failed (exit {error.returncode}); its message is above", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
